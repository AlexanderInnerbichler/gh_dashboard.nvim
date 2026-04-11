local M = {}

-- ── constants ──────────────────────────────────────────────────────────────

local CODE_WIDTH = 70  -- inner width of code boxes

-- ── state ──────────────────────────────────────────────────────────────────

local state = {
  buf           = nil,
  win           = nil,
  item          = nil,  -- { kind, number, repo, url }
  data          = nil,  -- decoded IssueDetail | PRDetail
  input_buf     = nil,
  input_win     = nil,
  diff_item     = nil,  -- { number, repo } of currently displayed diff
  diff_line_map = {},   -- [buf_line_0idx] = { path, line, side }
  diff_head_sha = nil,  -- PR head commit SHA; nil until fetched
}

-- ── highlights ─────────────────────────────────────────────────────────────

local ns = vim.api.nvim_create_namespace("GhReader")

local function setup_highlights()
  vim.api.nvim_set_hl(0, "GhReaderTitle",    { fg = "#7fc8f8", bold = true                })
  vim.api.nvim_set_hl(0, "GhReaderMeta",     { fg = "#4b5263"                             })
  vim.api.nvim_set_hl(0, "GhReaderStateOpen",   { fg = "#a3be8c", bold = true             })
  vim.api.nvim_set_hl(0, "GhReaderStateClosed", { fg = "#e06c75", bold = true             })
  vim.api.nvim_set_hl(0, "GhReaderStateMerged", { fg = "#b48ead", bold = true             })
  vim.api.nvim_set_hl(0, "GhReaderSep",      { fg = "#3b4048"                             })
  vim.api.nvim_set_hl(0, "GhReaderSection",  { fg = "#88c0d0", bold = true                })
  vim.api.nvim_set_hl(0, "GhReaderEmpty",    { fg = "#4b5263", italic = true              })
  vim.api.nvim_set_hl(0, "GhReaderError",       { fg = "#e06c75"                           })
  vim.api.nvim_set_hl(0, "GhReaderBreadcrumb", { fg = "#4b5263"                           })
  vim.api.nvim_set_hl(0, "GhReaderH2",       { fg = "#88c0d0", bold = true                })
  vim.api.nvim_set_hl(0, "GhReaderH3",       { fg = "#6b7a8d", bold = true                })
  vim.api.nvim_set_hl(0, "GhReaderCode",     { fg = "#4b5263"                             })
  vim.api.nvim_set_hl(0, "GhReaderCodeBody", { fg = "#abb2bf", bg = "#1e1e26"             })
  vim.api.nvim_set_hl(0, "GhReaderBullet",   { fg = "#e5c07b"                             })
  vim.api.nvim_set_hl(0, "GhReaderQuote",    { fg = "#616e88", italic = true              })
  vim.api.nvim_set_hl(0, "GhCiPass",         { fg = "#a3be8c"                             })
  vim.api.nvim_set_hl(0, "GhCiFail",         { fg = "#e06c75"                             })
  vim.api.nvim_set_hl(0, "GhCiPending",      { fg = "#e5c07b"                             })
  vim.api.nvim_set_hl(0, "GhReviewApproved", { fg = "#a3be8c"                             })
  vim.api.nvim_set_hl(0, "GhReviewChanges",  { fg = "#e06c75"                             })
  vim.api.nvim_set_hl(0, "GhReviewComment",  { fg = "#616e88"                             })
  vim.api.nvim_set_hl(0, "GhDiffAdd",        { fg = "#98c379"                             })
  vim.api.nvim_set_hl(0, "GhDiffDel",        { fg = "#e06c75"                             })
  vim.api.nvim_set_hl(0, "GhDiffHunk",       { fg = "#61afef"                             })
end

-- ── helpers ────────────────────────────────────────────────────────────────

local function separator()
  return "  " .. string.rep("─", CODE_WIDTH + 2)
end

local function age_string(iso8601)
  if not iso8601 or iso8601 == vim.NIL then return "" end
  local y, mo, d, h, mi, s = iso8601:match("(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)")
  if not y then return "" end
  local t = os.time({ year = tonumber(y), month = tonumber(mo), day = tonumber(d),
                      hour = tonumber(h), min = tonumber(mi), sec = tonumber(s), isdst = false })
  local diff = os.time(os.date("!*t")) - t
  if diff < 3600 then
    return math.floor(diff / 60) .. "m ago"
  elseif diff < 86400 then
    return math.floor(diff / 3600) .. "h ago"
  elseif diff < 604800 then
    return math.floor(diff / 86400) .. "d ago"
  else
    return math.floor(diff / 604800) .. "w ago"
  end
end

local function safe_str(v)
  if v == nil or v == vim.NIL then return "" end
  return tostring(v)
end

local function sl(s)
  return s:gsub("[\n\r]", " ")
end

local function safe_list(v)
  if type(v) ~= "table" then return {} end
  return v
end

-- ── write buffer ───────────────────────────────────────────────────────────

local function write_buf(lines, hl_specs)
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then return end
  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.bo[state.buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(state.buf, ns, 0, -1)
  for _, spec in ipairs(hl_specs) do
    local col_e = spec.col_e == -1 and -1 or spec.col_e
    vim.api.nvim_buf_add_highlight(state.buf, ns, spec.hl, spec.line, spec.col_s, col_e)
  end
end

-- ── async gh runner ────────────────────────────────────────────────────────

local function run_gh(args, callback)
  vim.system(args, { text = true }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        callback(result.stderr or "gh error", nil)
        return
      end
      local ok, decoded = pcall(vim.fn.json_decode, result.stdout)
      if not ok then
        callback("json decode error: " .. tostring(decoded), nil)
        return
      end
      callback(nil, decoded)
    end)
  end)
end

-- ── window management ──────────────────────────────────────────────────────

local function close_popup()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, false)
    state.win = nil
  end
end

local function close_input()
  if state.input_win and vim.api.nvim_win_is_valid(state.input_win) then
    vim.api.nvim_win_close(state.input_win, false)
    state.input_win = nil
    state.input_buf = nil
    vim.cmd("stopinsert")
  end
end

local function register_keymaps()
  local function bmap(lhs, fn)
    vim.keymap.set("n", lhs, fn, { buffer = state.buf, nowait = true, silent = true })
  end
  local function back()
    close_popup()
    require("gh_dashboard").focus_win()
  end
  bmap("q",     back)
  bmap("<Esc>", back)
  bmap("r", function()
    if state.item then M.open(state.item) end
  end)
  bmap("c", function()
    if not state.item then return end
    local item = state.item
    M.open_input("Write comment  |  <C-s> submit  ·  <Esc><Esc> cancel", function(body)
      if body == "" then return end
      M.post_comment(item, body, function(err)
        if err then
          vim.notify("Comment failed: " .. err, vim.log.levels.ERROR)
        else
          vim.notify("Comment posted", vim.log.levels.INFO)
          M.open(item)
        end
      end)
    end)
  end)
  bmap("a", function()
    if not state.item or state.item.kind ~= "pr" then return end
    local item = state.item
    vim.ui.select(
      { "Approve", "Request Changes", "Comment Only", "Cancel" },
      { prompt = "Review type:" },
      function(choice)
        if not choice or choice == "Cancel" then return end
        local kind_map = {
          ["Approve"] = "approve",
          ["Request Changes"] = "request_changes",
          ["Comment Only"] = "comment",
        }
        local kind = kind_map[choice]
        M.open_input(choice .. "  |  <C-s> submit  ·  <Esc><Esc> cancel", function(body)
          M.submit_review(item, kind, body, function(err)
            if err then
              vim.notify("Review failed: " .. err, vim.log.levels.ERROR)
            else
              vim.notify("Review submitted", vim.log.levels.INFO)
              M.open(item)
            end
          end)
        end)
      end
    )
  end)
  bmap("m", function()
    if not state.item or state.item.kind ~= "pr" then return end
    if not state.data then return end
    local item = state.item
    if state.data.mergeable ~= "MERGEABLE" then
      vim.notify("Cannot merge: " .. safe_str(state.data.mergeable), vim.log.levels.WARN)
      return
    end
    vim.ui.select(
      { "Merge commit", "Squash and merge", "Rebase and merge", "Cancel" },
      { prompt = "Merge method:" },
      function(choice)
        if not choice or choice == "Cancel" then return end
        local method_map = {
          ["Merge commit"] = "merge",
          ["Squash and merge"] = "squash",
          ["Rebase and merge"] = "rebase",
        }
        local method = method_map[choice]
        local base = safe_str(state.data.base_ref)
        vim.ui.input(
          { prompt = "Merge #" .. item.number .. " into " .. base .. "? (yes/no): " },
          function(ans)
            if ans ~= "yes" then return end
            M.merge_pr(item, method, function(err)
              if err then
                vim.notify("Merge failed: " .. err, vim.log.levels.ERROR)
              else
                vim.notify("PR #" .. item.number .. " merged", vim.log.levels.INFO)
                local cache = vim.fn.expand("~/.cache/nvim/gh-dashboard.json")
                vim.uv.fs_unlink(cache, function() end)
                M.open(item)
              end
            end)
          end
        )
      end
    )
  end)
  bmap("d", function()
    if state.item and state.item.kind == "pr" then
      M.open_diff(state.item)
    end
  end)
  bmap("x", function()
    if not state.item or state.item.kind ~= "issue" then return end
    local item = state.item
    vim.ui.input(
      { prompt = "Close issue #" .. item.number .. "? (yes/no): " },
      function(ans)
        if ans ~= "yes" then return end
        M.close_issue(item, function(err)
          if err then
            vim.notify("Close failed: " .. err, vim.log.levels.ERROR)
          else
            vim.notify("Issue #" .. item.number .. " closed", vim.log.levels.INFO)
            local cache = vim.fn.expand("~/.cache/nvim/gh-dashboard.json")
            vim.uv.fs_unlink(cache, function() end)
            M.open(item)
          end
        end)
      end
    )
  end)
end

local function open_popup(title, footer)
  footer = footer or ""
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
    state.buf = vim.api.nvim_create_buf(false, true)
    vim.bo[state.buf].buftype    = "nofile"
    vim.bo[state.buf].bufhidden  = "wipe"
    vim.bo[state.buf].modifiable = false
    vim.bo[state.buf].filetype   = "text"
  end
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_set_config(state.win, {
      title = " " .. title .. " ", title_pos = "center",
      footer = footer ~= "" and (" " .. footer .. " ") or nil, footer_pos = "center",
    })
    return
  end
  local ui     = vim.api.nvim_list_uis()[1] or { width = 180, height = 50 }
  local width  = math.floor(ui.width  * 0.90)
  local height = math.floor(ui.height * 0.90)
  local row    = math.floor((ui.height - height) / 2)
  local col    = math.floor((ui.width  - width)  / 2)
  state.win = vim.api.nvim_open_win(state.buf, true, {
    relative   = "editor",
    width      = width,
    height     = height,
    row        = row,
    col        = col,
    style      = "minimal",
    border     = "rounded",
    title      = " " .. title .. " ",
    title_pos  = "center",
    footer     = footer ~= "" and (" " .. footer .. " ") or nil,
    footer_pos = "center",
  })
  vim.wo[state.win].number         = false
  vim.wo[state.win].relativenumber = false
  vim.wo[state.win].signcolumn     = "no"
  vim.wo[state.win].wrap           = true
  vim.wo[state.win].linebreak      = true
  vim.wo[state.win].cursorline     = false
  register_keymaps()
end

-- ── fetch functions ────────────────────────────────────────────────────────

local function fetch_readme(item, callback)
  vim.system(
    { "gh", "api", "repos/" .. item.full_name .. "/readme",
      "-H", "Accept: application/vnd.github.raw" },
    { text = true },
    function(result)
      vim.schedule(function()
        if result.code ~= 0 then
          callback("No README found", nil)
          return
        end
        callback(nil, result.stdout)
      end)
    end
  )
end

local function fetch_issue(item, callback)
  run_gh(
    { "gh", "issue", "view", tostring(item.number), "-R", item.repo,
      "--json", "number,title,state,body,labels,author,comments,createdAt,assignees,url" },
    function(err, raw)
      if err then callback(err, nil) return end
      local labels = {}
      for _, l in ipairs(safe_list(raw.labels)) do
        if type(l) == "table" and l.name then
          table.insert(labels, l.name)
        end
      end
      local comments = {}
      for _, c in ipairs(safe_list(raw.comments)) do
        table.insert(comments, {
          id         = safe_str(c.id),
          author     = type(c.author) == "table" and safe_str(c.author.login) or "?",
          body       = safe_str(c.body),
          created_at = safe_str(c.createdAt),
        })
      end
      callback(nil, {
        kind       = "issue",
        number     = raw.number,
        title      = safe_str(raw.title),
        state      = safe_str(raw.state),
        body       = safe_str(raw.body),
        labels     = labels,
        author     = type(raw.author) == "table" and safe_str(raw.author.login) or "?",
        created_at = safe_str(raw.createdAt),
        url        = safe_str(raw.url),
        comments   = comments,
      })
    end
  )
end

local function fetch_pr(item, callback)
  run_gh(
    { "gh", "pr", "view", tostring(item.number), "-R", item.repo,
      "--json", "number,title,state,body,author,headRefName,baseRefName,reviews,statusCheckRollup,comments,createdAt,isDraft,mergeable,url,assignees" },
    function(err, raw)
      if err then callback(err, nil) return end
      local labels = {}
      for _, l in ipairs(safe_list(raw.labels)) do
        if type(l) == "table" and l.name then table.insert(labels, l.name) end
      end
      local reviews = {}
      for _, r in ipairs(safe_list(raw.reviews)) do
        table.insert(reviews, {
          author       = type(r.author) == "table" and safe_str(r.author.login) or "?",
          state        = safe_str(r.state),
          body         = safe_str(r.body),
          submitted_at = safe_str(r.submittedAt),
        })
      end
      local ci_checks = {}
      for _, c in ipairs(safe_list(raw.statusCheckRollup)) do
        table.insert(ci_checks, {
          name       = safe_str(c.name or c.context),
          status     = safe_str(c.status or c.state),
          conclusion = c.conclusion ~= vim.NIL and safe_str(c.conclusion) or nil,
        })
      end
      local comments = {}
      for _, c in ipairs(safe_list(raw.comments)) do
        table.insert(comments, {
          id         = safe_str(c.id),
          author     = type(c.author) == "table" and safe_str(c.author.login) or "?",
          body       = safe_str(c.body),
          created_at = safe_str(c.createdAt),
        })
      end
      callback(nil, {
        kind       = "pr",
        number     = raw.number,
        title      = safe_str(raw.title),
        state      = safe_str(raw.state),
        body       = safe_str(raw.body),
        author     = type(raw.author) == "table" and safe_str(raw.author.login) or "?",
        head_ref   = safe_str(raw.headRefName),
        base_ref   = safe_str(raw.baseRefName),
        is_draft   = raw.isDraft == true,
        mergeable  = safe_str(raw.mergeable),
        created_at = safe_str(raw.createdAt),
        url        = safe_str(raw.url),
        labels     = labels,
        reviews    = reviews,
        ci_checks  = ci_checks,
        comments   = comments,
      })
    end
  )
end

local function fetch_review_comments(number, repo, callback)
  vim.system(
    { "gh", "api", "repos/" .. repo .. "/pulls/" .. tostring(number) .. "/comments",
      "--jq", "[.[] | {login: .user.login, path: .path, line: (.line // .original_line), body: .body, hunk: .diff_hunk}]" },
    { text = true },
    function(result)
      vim.schedule(function()
        if result.code ~= 0 then callback({}) return end
        local ok, data = pcall(vim.json.decode, result.stdout or "[]")
        callback(ok and type(data) == "table" and data or {})
      end)
    end
  )
end

-- ── render helpers ─────────────────────────────────────────────────────────

local function state_hl(s)
  local upper = s:upper()
  if upper == "OPEN"   then return "GhReaderStateOpen"
  elseif upper == "MERGED" then return "GhReaderStateMerged"
  else return "GhReaderStateClosed"
  end
end

local function process_body(body, lines, hl_specs)
  if body == "" then
    local msg = "   (no description)"
    table.insert(lines, msg)
    table.insert(hl_specs, { hl = "GhReaderEmpty", line = #lines - 1, col_s = 0, col_e = -1 })
    return
  end
  local in_code = false
  for raw in (body .. "\n"):gmatch("([^\n]*)\n") do
    if raw:match("^```") then
      if in_code then
        table.insert(lines, "  ╰" .. string.rep("─", CODE_WIDTH) .. "╯")
        table.insert(hl_specs, { hl = "GhReaderCode", line = #lines - 1, col_s = 0, col_e = -1 })
        in_code = false
      else
        local lang = (raw:match("^```(.-)%s*$") or ""):gsub("%s+", "")
        local label = lang ~= "" and (" " .. lang .. " ") or ""
        local fill  = string.rep("─", math.max(0, CODE_WIDTH - #label - 1))
        table.insert(lines, "  ╭─" .. label .. fill .. "╮")
        table.insert(hl_specs, { hl = "GhReaderCode", line = #lines - 1, col_s = 0, col_e = -1 })
        in_code = true
      end
    elseif in_code then
      table.insert(lines, "  │ " .. raw)
      table.insert(hl_specs, { hl = "GhReaderCodeBody", line = #lines - 1, col_s = 0, col_e = -1 })
    elseif raw:match("^> ") then
      local quote = raw:match("^> (.*)$") or ""
      table.insert(lines, "  ┃ " .. quote)
      table.insert(hl_specs, { hl = "GhReaderQuote", line = #lines - 1, col_s = 0, col_e = -1 })
    elseif raw:match("^(#+) ") then
      local level   = #(raw:match("^(#+) "))
      local heading = raw:match("^#+%s+(.+)$") or ""
      table.insert(lines, "")
      if level <= 2 then
        table.insert(lines, "  " .. heading)
        table.insert(hl_specs, { hl = "GhReaderH2", line = #lines - 1, col_s = 2, col_e = -1 })
        table.insert(lines, "  " .. string.rep("─", math.min(#heading, CODE_WIDTH)))
        table.insert(hl_specs, { hl = "GhReaderSep", line = #lines - 1, col_s = 0, col_e = -1 })
      else
        table.insert(lines, "  ▸ " .. heading)
        table.insert(hl_specs, { hl = "GhReaderH3", line = #lines - 1, col_s = 2, col_e = -1 })
      end
    elseif raw:match("^%s*[%-%*%+] ") then
      local item = raw:match("^%s*[%-%*%+] (.*)$") or ""
      table.insert(lines, "  • " .. item)
      table.insert(hl_specs, { hl = "GhReaderBullet", line = #lines - 1, col_s = 2, col_e = 5 })
    elseif raw:match("^%s*%d+%. ") then
      local item = raw:match("^%s*(%d+%..*)$") or raw
      table.insert(lines, "  " .. item)
    elseif raw:match("^%-%-%-+$") or raw:match("^%*%*%*+$") or raw:match("^___+$") then
      table.insert(lines, "  " .. string.rep("─", CODE_WIDTH))
      table.insert(hl_specs, { hl = "GhReaderSep", line = #lines - 1, col_s = 0, col_e = -1 })
    else
      table.insert(lines, "  " .. raw)
    end
  end
  if in_code then
    table.insert(lines, "  ╰" .. string.rep("─", CODE_WIDTH) .. "╯")
    table.insert(hl_specs, { hl = "GhReaderCode", line = #lines - 1, col_s = 0, col_e = -1 })
  end
end

local function render_comments_section(lines, hl_specs, comments)
  table.insert(lines, "")
  table.insert(lines, separator())
  table.insert(hl_specs, { hl = "GhReaderSep", line = #lines - 1, col_s = 0, col_e = -1 })
  local header = "  💬 Comments (" .. #comments .. ")"
  table.insert(lines, header)
  table.insert(hl_specs, { hl = "GhReaderSection", line = #lines - 1, col_s = 0, col_e = #header })
  if #comments == 0 then
    local msg = "   No comments yet"
    table.insert(lines, msg)
    table.insert(hl_specs, { hl = "GhReaderEmpty", line = #lines - 1, col_s = 0, col_e = #msg })
    return
  end
  for _, c in ipairs(comments) do
    table.insert(lines, "")
    local meta = "  @" .. sl(c.author) .. "  ·  " .. age_string(c.created_at)
    table.insert(lines, meta)
    table.insert(hl_specs, { hl = "GhReaderMeta", line = #lines - 1, col_s = 0, col_e = -1 })
    table.insert(lines, "  " .. string.rep("╌", CODE_WIDTH))
    table.insert(hl_specs, { hl = "GhReaderSep", line = #lines - 1, col_s = 0, col_e = -1 })
    process_body(c.body, lines, hl_specs)
  end
end

local function render_review_comments_section(lines, hl_specs, review_comments)
  if #review_comments == 0 then return end
  table.insert(lines, "")
  table.insert(lines, separator())
  table.insert(hl_specs, { hl = "GhReaderSep", line = #lines - 1, col_s = 0, col_e = -1 })
  local header = "  🔎 Review Comments (" .. #review_comments .. ")"
  table.insert(lines, header)
  table.insert(hl_specs, { hl = "GhReaderSection", line = #lines - 1, col_s = 0, col_e = #header })
  for _, rc in ipairs(review_comments) do
    table.insert(lines, "")
    local meta = "  @" .. sl(rc.login) .. "  ·  " .. sl(rc.path) .. ":" .. tostring(rc.line or "?")
    table.insert(lines, meta)
    table.insert(hl_specs, { hl = "GhReaderMeta", line = #lines - 1, col_s = 0, col_e = -1 })
    table.insert(lines, "  " .. string.rep("╌", CODE_WIDTH))
    table.insert(hl_specs, { hl = "GhReaderSep", line = #lines - 1, col_s = 0, col_e = -1 })
    if rc.hunk and rc.hunk ~= "" then
      local hunk_lines = {}
      for hunk_line in rc.hunk:gmatch("[^\n]+") do
        if not hunk_line:match("^@@") then
          table.insert(hunk_lines, hunk_line)
        end
      end
      local start = math.max(1, #hunk_lines - 2)
      for i = start, #hunk_lines do
        local hl = hunk_lines[i]
        local display = "  " .. hl
        table.insert(lines, display)
        local ln = #lines - 1
        if hl:sub(1, 1) == "+" then
          table.insert(hl_specs, { hl = "GhDiffAdd", line = ln, col_s = 0, col_e = -1 })
        elseif hl:sub(1, 1) == "-" then
          table.insert(hl_specs, { hl = "GhDiffDel", line = ln, col_s = 0, col_e = -1 })
        end
      end
      table.insert(lines, "  " .. string.rep("╌", CODE_WIDTH))
      table.insert(hl_specs, { hl = "GhReaderSep", line = #lines - 1, col_s = 0, col_e = -1 })
    end
    process_body(rc.body, lines, hl_specs)
  end
end

local function render_reviews_section(lines, hl_specs, reviews)
  local with_body = {}
  for _, r in ipairs(reviews) do
    if r.body ~= "" then table.insert(with_body, r) end
  end
  if #with_body == 0 then return end
  table.insert(lines, "")
  table.insert(lines, separator())
  table.insert(hl_specs, { hl = "GhReaderSep", line = #lines - 1, col_s = 0, col_e = -1 })
  local header = "  🔍 Reviews (" .. #with_body .. ")"
  table.insert(lines, header)
  table.insert(hl_specs, { hl = "GhReaderSection", line = #lines - 1, col_s = 0, col_e = #header })
  for _, r in ipairs(with_body) do
    table.insert(lines, "")
    local state_icon = r.state == "APPROVED" and "✓" or (r.state == "CHANGES_REQUESTED" and "✗" or "·")
    local meta = "  " .. state_icon .. " @" .. sl(r.author) .. "  ·  " .. r.state:lower():gsub("_", " ") .. "  ·  " .. age_string(r.submitted_at)
    local hl = r.state == "APPROVED" and "GhReviewApproved" or (r.state == "CHANGES_REQUESTED" and "GhReviewChanges" or "GhReviewComment")
    table.insert(lines, meta)
    table.insert(hl_specs, { hl = hl, line = #lines - 1, col_s = 0, col_e = -1 })
    table.insert(lines, "  " .. string.rep("╌", CODE_WIDTH))
    table.insert(hl_specs, { hl = "GhReaderSep", line = #lines - 1, col_s = 0, col_e = -1 })
    process_body(r.body, lines, hl_specs)
  end
end

-- ── issue render ───────────────────────────────────────────────────────────

local function render_issue(data)
  local lines    = {}
  local hl_specs = {}

  local crumb_prefix = "  GitHub Dashboard  ›  "
  local crumb_title  = "#" .. data.number .. "  " .. sl(data.title):sub(1, 50)
  local crumb = crumb_prefix .. crumb_title
  table.insert(lines, crumb)
  table.insert(hl_specs, { hl = "GhReaderBreadcrumb", line = #lines - 1, col_s = 0,             col_e = #crumb_prefix })
  table.insert(hl_specs, { hl = "GhReaderTitle",      line = #lines - 1, col_s = #crumb_prefix, col_e = -1 })

  table.insert(lines, "")
  local title_line = "  #" .. data.number .. "  " .. sl(data.title)
  table.insert(lines, title_line)
  table.insert(hl_specs, { hl = "GhReaderTitle", line = #lines - 1, col_s = 0, col_e = -1 })

  local state_tag  = " " .. data.state .. " "
  local labels_str = #data.labels > 0 and ("  · " .. table.concat(data.labels, " · ")) or ""
  local meta       = "  " .. state_tag .. "  @" .. sl(data.author) .. labels_str .. "  ·  " .. age_string(data.created_at)
  table.insert(lines, meta)
  table.insert(hl_specs, { hl = state_hl(data.state), line = #lines - 1, col_s = 2, col_e = 2 + #state_tag })
  table.insert(hl_specs, { hl = "GhReaderMeta",       line = #lines - 1, col_s = 2 + #state_tag, col_e = -1 })

  table.insert(lines, separator())
  table.insert(hl_specs, { hl = "GhReaderSep", line = #lines - 1, col_s = 0, col_e = -1 })
  table.insert(lines, "")

  process_body(data.body, lines, hl_specs)
  render_comments_section(lines, hl_specs, data.comments)

  local issue_footer = "q back  ·  r refresh  ·  c comment  ·  x close issue"
  open_popup("#" .. data.number .. "  " .. sl(data.title):sub(1, 55), issue_footer)
  write_buf(lines, hl_specs)
end

-- ── PR render ──────────────────────────────────────────────────────────────

local function render_pr(data, review_comments)
  local lines    = {}
  local hl_specs = {}

  local crumb_prefix = "  GitHub Dashboard  ›  "
  local crumb_title  = "#" .. data.number .. "  " .. sl(data.title):sub(1, 50)
  local crumb = crumb_prefix .. crumb_title
  table.insert(lines, crumb)
  table.insert(hl_specs, { hl = "GhReaderBreadcrumb", line = #lines - 1, col_s = 0,             col_e = #crumb_prefix })
  table.insert(hl_specs, { hl = "GhReaderTitle",      line = #lines - 1, col_s = #crumb_prefix, col_e = -1 })

  table.insert(lines, "")
  local draft_tag  = data.is_draft and "  [draft]" or ""
  local title_line = "  #" .. data.number .. "  " .. sl(data.title) .. draft_tag
  table.insert(lines, title_line)
  table.insert(hl_specs, { hl = "GhReaderTitle", line = #lines - 1, col_s = 0, col_e = -1 })

  local state_tag = " " .. data.state .. " "
  local meta      = "  " .. state_tag .. "  @" .. sl(data.author) .. "  ·  " .. age_string(data.created_at)
  table.insert(lines, meta)
  table.insert(hl_specs, { hl = state_hl(data.state), line = #lines - 1, col_s = 2, col_e = 2 + #state_tag })
  table.insert(hl_specs, { hl = "GhReaderMeta",       line = #lines - 1, col_s = 2 + #state_tag, col_e = -1 })

  local mergeable_icon = data.mergeable == "MERGEABLE" and "✓" or (data.mergeable == "CONFLICTING" and "✗" or "?")
  local branch_line    = "  ⎇  " .. sl(data.head_ref) .. " → " .. sl(data.base_ref) .. "   merge: " .. mergeable_icon
  table.insert(lines, branch_line)
  table.insert(hl_specs, { hl = "GhReaderMeta", line = #lines - 1, col_s = 0, col_e = -1 })

  if #data.ci_checks > 0 then
    local parts   = { "  CI: " }
    local ci_hls  = {}
    local col     = #"  CI: "
    for _, check in ipairs(data.ci_checks) do
      local s    = safe_str(check.status):upper()
      local icon = (s == "SUCCESS" or s == "COMPLETED") and "✓" or (s == "FAILURE" or s == "ERROR") and "✗" or "⠋"
      local hl   = (icon == "✓") and "GhCiPass" or (icon == "✗") and "GhCiFail" or "GhCiPending"
      local chunk = icon .. " " .. sl(check.name) .. "  "
      table.insert(ci_hls, { hl = hl, col_s = col, col_e = col + #icon })
      col = col + #chunk
      table.insert(parts, chunk)
    end
    local ci_line = table.concat(parts)
    table.insert(lines, ci_line)
    local ln = #lines - 1
    for _, h in ipairs(ci_hls) do
      table.insert(hl_specs, { hl = h.hl, line = ln, col_s = h.col_s, col_e = h.col_e })
    end
  else
    table.insert(lines, "  CI: no checks")
    table.insert(hl_specs, { hl = "GhReaderMeta", line = #lines - 1, col_s = 0, col_e = -1 })
  end

  if #data.reviews > 0 then
    local parts  = { "  Reviews: " }
    local rev_hls = {}
    local col    = #"  Reviews: "
    for _, r in ipairs(data.reviews) do
      local icon  = r.state == "APPROVED" and "✓" or (r.state == "CHANGES_REQUESTED" and "✗" or "·")
      local hl    = r.state == "APPROVED" and "GhReviewApproved" or (r.state == "CHANGES_REQUESTED" and "GhReviewChanges" or "GhReviewComment")
      local chunk = icon .. " " .. sl(r.author) .. "  "
      table.insert(rev_hls, { hl = hl, col_s = col, col_e = col + #icon })
      col = col + #chunk
      table.insert(parts, chunk)
    end
    local rev_line = table.concat(parts)
    table.insert(lines, rev_line)
    local ln = #lines - 1
    for _, h in ipairs(rev_hls) do
      table.insert(hl_specs, { hl = h.hl, line = ln, col_s = h.col_s, col_e = h.col_e })
    end
  else
    table.insert(lines, "  Reviews: none")
    table.insert(hl_specs, { hl = "GhReaderMeta", line = #lines - 1, col_s = 0, col_e = -1 })
  end

  table.insert(lines, separator())
  table.insert(hl_specs, { hl = "GhReaderSep", line = #lines - 1, col_s = 0, col_e = -1 })
  table.insert(lines, "")

  process_body(data.body, lines, hl_specs)
  render_reviews_section(lines, hl_specs, data.reviews)
  render_comments_section(lines, hl_specs, data.comments)
  render_review_comments_section(lines, hl_specs, review_comments or {})

  local pr_footer = "q back  ·  r refresh  ·  c comment  ·  a review  ·  d diff  ·  m merge"
  open_popup("#" .. data.number .. "  " .. sl(data.title):sub(1, 55), pr_footer)
  write_buf(lines, hl_specs)
end

local function render_readme(data)
  local lines    = {}
  local hl_specs = {}

  local crumb_prefix = "  GitHub Dashboard  ›  "
  local crumb        = crumb_prefix .. data.full_name .. "  ›  README"
  table.insert(lines, crumb)
  table.insert(hl_specs, { hl = "GhReaderBreadcrumb", line = 0, col_s = 0,             col_e = #crumb_prefix })
  table.insert(hl_specs, { hl = "GhReaderTitle",      line = 0, col_s = #crumb_prefix, col_e = -1 })
  table.insert(lines, "")
  table.insert(lines, separator())
  table.insert(hl_specs, { hl = "GhReaderSep", line = #lines - 1, col_s = 0, col_e = -1 })
  table.insert(lines, "")

  process_body(data.body, lines, hl_specs)

  open_popup(data.full_name .. "  README", "q back")
  write_buf(lines, hl_specs)
end

-- ── input buffer ───────────────────────────────────────────────────────────

function M.open_input(hint, on_submit)
  close_input()

  state.input_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[state.input_buf].buftype   = "nofile"
  vim.bo[state.input_buf].bufhidden = "wipe"
  vim.bo[state.input_buf].filetype  = "markdown"

  vim.api.nvim_buf_set_lines(state.input_buf, 0, -1, false, { "", "" })

  local ui     = vim.api.nvim_list_uis()[1] or { width = 180, height = 50 }
  local width  = math.floor(ui.width  * 0.60)
  local height = 12
  local row    = math.floor((ui.height - height) / 2)
  local col    = math.floor((ui.width  - width)  / 2)

  state.input_win = vim.api.nvim_open_win(state.input_buf, true, {
    relative   = "editor",
    width      = width,
    height     = height,
    row        = row,
    col        = col,
    style      = "minimal",
    border     = "rounded",
    title      = " " .. hint .. " ",
    title_pos  = "center",
    footer     = " <C-s> submit  ·  <Esc><Esc> cancel ",
    footer_pos = "center",
  })
  vim.wo[state.input_win].number         = false
  vim.wo[state.input_win].relativenumber = false
  vim.wo[state.input_win].signcolumn     = "no"
  vim.wo[state.input_win].wrap           = true
  vim.wo[state.input_win].linebreak      = true

  vim.api.nvim_win_set_cursor(state.input_win, { 1, 0 })
  vim.cmd("startinsert")

  local function do_cancel()
    close_input()
  end

  local function do_submit()
    local all_lines = vim.api.nvim_buf_get_lines(state.input_buf, 0, -1, false)
    local body = table.concat(all_lines, "\n"):gsub("^%s+", ""):gsub("%s+$", "")
    close_input()
    on_submit(body)
  end

  local function imap(mode, lhs, fn)
    vim.keymap.set(mode, lhs, fn, { buffer = state.input_buf, nowait = true, silent = true })
  end

  imap("n", "<C-s>", do_submit)
  imap("i", "<C-s>", do_submit)
  imap("n", "<Esc><Esc>", do_cancel)

  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer   = state.input_buf,
    once     = true,
    callback = function()
      state.input_buf = nil
      state.input_win = nil
    end,
  })
end

-- ── action functions ───────────────────────────────────────────────────────

function M.post_comment(item, body, callback)
  local cmd = item.kind == "issue"
    and { "gh", "issue", "comment", tostring(item.number), "-R", item.repo, "--body", body }
    or  { "gh", "pr",    "comment", tostring(item.number), "-R", item.repo, "--body", body }
  vim.system(cmd, { text = true }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then callback(result.stderr or "gh error")
      else callback(nil) end
    end)
  end)
end

function M.submit_review(item, kind, body, callback)
  local flag = kind == "approve" and "--approve"
    or kind == "request_changes" and "--request-changes"
    or "--comment"
  vim.system(
    { "gh", "pr", "review", tostring(item.number), "-R", item.repo, flag, "--body", body },
    { text = true },
    function(result)
      vim.schedule(function()
        if result.code ~= 0 then callback(result.stderr or "gh error")
        else callback(nil) end
      end)
    end
  )
end

function M.merge_pr(item, method, callback)
  local flag = method == "squash" and "--squash" or method == "rebase" and "--rebase" or "--merge"
  vim.system(
    { "gh", "pr", "merge", tostring(item.number), "-R", item.repo, flag },
    { text = true },
    function(result)
      vim.schedule(function()
        if result.code ~= 0 then callback(result.stderr or "gh error")
        else callback(nil) end
      end)
    end
  )
end

function M.close_issue(item, callback)
  vim.system(
    { "gh", "issue", "close", tostring(item.number), "-R", item.repo },
    { text = true },
    function(result)
      vim.schedule(function()
        if result.code ~= 0 then callback(result.stderr or "gh error")
        else callback(nil) end
      end)
    end
  )
end

-- ── public API ─────────────────────────────────────────────────────────────

function M.open(item)
  state.item = item
  state.data = nil
  local label = item.number and ("#" .. tostring(item.number)) or (item.full_name or item.repo or "…")
  open_popup(label .. " — loading…", "q back")

  local crumb_prefix = "  GitHub Dashboard  ›  "
  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, {
    crumb_prefix .. label,
    "",
    "  ⠋ loading " .. label .. "…",
  })
  vim.bo[state.buf].modifiable = false

  if item.kind == "issue" then
    fetch_issue(item, function(err, data)
      if err then
        vim.bo[state.buf].modifiable = true
        vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, { "", "  ✗ " .. sl(err) })
        vim.bo[state.buf].modifiable = false
        return
      end
      state.data = data
      render_issue(data)
    end)
  elseif item.kind == "pr" then
    local pr_data, rc_data
    local pending = 2
    local function on_both()
      pending = pending - 1
      if pending > 0 then return end
      state.data = pr_data
      render_pr(pr_data, rc_data or {})
    end
    fetch_pr(item, function(err, data)
      if err then
        vim.bo[state.buf].modifiable = true
        vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, { "", "  ✗ " .. sl(err) })
        vim.bo[state.buf].modifiable = false
        return
      end
      pr_data = data
      on_both()
    end)
    fetch_review_comments(item.number, item.repo, function(data)
      rc_data = data
      on_both()
    end)
  elseif item.kind == "repo" then
    fetch_readme(item, function(err, body)
      if err then
        vim.bo[state.buf].modifiable = true
        vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, { "", "  ✗ " .. sl(err) })
        vim.bo[state.buf].modifiable = false
        return
      end
      render_readme({ full_name = item.full_name, body = body })
    end)
  end
end

-- ── diff viewer ────────────────────────────────────────────────────────────

local function fetch_head_sha(number, repo, callback)
  vim.system(
    { "gh", "pr", "view", tostring(number), "--repo", repo,
      "--json", "headRefOid", "--jq", ".headRefOid" },
    { text = true },
    function(result)
      vim.schedule(function()
        if result.code ~= 0 then
          callback(result.stderr or "gh error", nil)
        else
          callback(nil, vim.trim(result.stdout or ""))
        end
      end)
    end
  )
end

local function post_review_comment(number, repo, sha, path, line, side, body, callback)
  vim.system(
    { "gh", "api", "repos/" .. repo .. "/pulls/" .. tostring(number) .. "/comments",
      "-f", "body=" .. body,
      "-f", "commit_id=" .. sha,
      "-f", "path=" .. path,
      "-F", "line=" .. tostring(line),
      "-f", "side=" .. side },
    { text = true },
    function(result)
      vim.schedule(function()
        if result.code ~= 0 then
          local msg = (result.stdout ~= "" and result.stdout)
                   or (result.stderr ~= "" and result.stderr)
                   or "api error"
          callback(msg)
        else
          callback(nil)
        end
      end)
    end
  )
end

local function fetch_diff(number, repo, callback)
  vim.system(
    { "gh", "pr", "diff", tostring(number), "--repo", repo },
    { text = true },
    function(result)
      vim.schedule(function()
        if result.code ~= 0 then
          callback(result.stderr or "gh error", nil)
        else
          callback(nil, result.stdout or "")
        end
      end)
    end
  )
end

local function render_diff_content(lines, hl_specs, number, repo, diff_text, err, line_map)
  local crumb_prefix = "  GitHub Dashboard  ›  "
  local crumb        = crumb_prefix .. repo .. "  ›  PR #" .. number .. " diff"
  table.insert(lines, crumb)
  table.insert(hl_specs, { hl = "GhReaderBreadcrumb", line = #lines - 1, col_s = 0,             col_e = #crumb_prefix })
  table.insert(hl_specs, { hl = "GhReaderTitle",      line = #lines - 1, col_s = #crumb_prefix, col_e = -1 })
  table.insert(lines, "")

  if err then
    local msg = "  ✗ " .. err:gsub("[\n\r]", " ")
    table.insert(lines, msg)
    table.insert(hl_specs, { hl = "GhReaderError", line = #lines - 1, col_s = 0, col_e = #msg })
    return
  end

  if diff_text == "" then
    local msg = "  (no diff)"
    table.insert(lines, msg)
    table.insert(hl_specs, { hl = "GhReaderEmpty", line = #lines - 1, col_s = 0, col_e = #msg })
    return
  end

  local cur_path   = nil
  local new_line_n = 0
  local old_line_n = 0

  for raw_line in diff_text:gmatch("[^\n]+") do
    table.insert(lines, raw_line)
    local buf_ln = #lines - 1

    if raw_line:match("^diff %-%-git") then
      cur_path   = raw_line:match(" b/(.+)$")
      new_line_n = 0
      old_line_n = 0
    elseif raw_line:match("^@@") then
      local ns, nn = raw_line:match("@@ %-(%d+),?%d* %+(%d+),?%d* @@")
      old_line_n = tonumber(ns or 0) - 1
      new_line_n = tonumber(nn or 0) - 1
      table.insert(hl_specs, { hl = "GhDiffHunk", line = buf_ln, col_s = 0, col_e = -1 })
    elseif raw_line:sub(1, 1) == "+" and not raw_line:match("^%+%+%+") then
      new_line_n = new_line_n + 1
      table.insert(hl_specs, { hl = "GhDiffAdd", line = buf_ln, col_s = 0, col_e = -1 })
      if line_map and cur_path then
        line_map[buf_ln] = { path = cur_path, line = new_line_n, side = "RIGHT" }
      end
    elseif raw_line:sub(1, 1) == "-" and not raw_line:match("^%-%-%-") then
      old_line_n = old_line_n + 1
      table.insert(hl_specs, { hl = "GhDiffDel", line = buf_ln, col_s = 0, col_e = -1 })
      if line_map and cur_path then
        line_map[buf_ln] = { path = cur_path, line = old_line_n, side = "LEFT" }
      end
    elseif raw_line:sub(1, 1) == " " then
      new_line_n = new_line_n + 1
      old_line_n = old_line_n + 1
      if line_map and cur_path then
        line_map[buf_ln] = { path = cur_path, line = new_line_n, side = "RIGHT" }
      end
    end
  end
end

M.open_diff = function(item)
  open_popup(string.format(" PR #%d diff ", item.number), " c comment · q close ")
  vim.wo[state.win].wrap = false

  state.diff_item     = item
  state.diff_line_map = {}
  state.diff_head_sha = nil

  write_buf({ "", "  Loading diff…" }, {})

  vim.keymap.set("v", "c", function()
    local end_ln = vim.fn.getpos("'>")[2] - 1  -- 0-indexed
    local info   = state.diff_line_map[end_ln]
    if not info then
      vim.cmd("normal! \27")
      vim.notify("Cannot comment on this line", vim.log.levels.INFO)
      return
    end
    if not state.diff_head_sha or state.diff_head_sha == "" then
      vim.cmd("normal! \27")
      vim.notify("Still loading, please try again", vim.log.levels.INFO)
      return
    end
    vim.cmd("normal! \27")
    M.open_input("Review comment  |  <C-s> submit  ·  <Esc><Esc> cancel", function(body)
      if body == "" then
        vim.notify("Comment cannot be empty", vim.log.levels.WARN)
        return
      end
      post_review_comment(
        state.diff_item.number, state.diff_item.repo,
        state.diff_head_sha, info.path, info.line, info.side,
        body, function(err)
          if err then
            vim.notify("Failed: " .. err:gsub("[\n\r]", " "), vim.log.levels.ERROR)
          else
            vim.notify("Review comment posted", vim.log.levels.INFO)
          end
        end
      )
    end)
  end, { buffer = state.buf, nowait = true, silent = true })

  local pending = 2
  local diff_text, diff_err, head_sha

  local function on_both()
    pending = pending - 1
    if pending > 0 then return end
    state.diff_head_sha = head_sha or ""
    local lines, hl_specs = {}, {}
    table.insert(lines, "")
    render_diff_content(lines, hl_specs, item.number, item.repo,
                        diff_text or "", diff_err, state.diff_line_map)
    table.insert(lines, "")
    write_buf(lines, hl_specs)
  end

  fetch_diff(item.number, item.repo, function(err, text)
    diff_err, diff_text = err, text
    on_both()
  end)
  fetch_head_sha(item.number, item.repo, function(_, sha)
    head_sha = sha
    on_both()
  end)
end

function M.setup()
  setup_highlights()
  vim.api.nvim_create_autocmd("ColorScheme", {
    callback = setup_highlights,
    desc = "Re-apply GhReader highlights on colorscheme change",
  })
end

return M
