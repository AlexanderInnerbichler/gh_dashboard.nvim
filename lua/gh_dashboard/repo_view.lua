local M = {}
local gh         = require("gh_dashboard.gh")
local highlights = require("gh_dashboard.highlights")
local actions    = require("gh_dashboard.reader.actions")

-- ── state ──────────────────────────────────────────────────────────────────

local state = {
  buf       = nil,
  win       = nil,
  item      = nil,
  items     = {},
  input_buf = nil,
  input_win = nil,
}

local ns = vim.api.nvim_create_namespace("GhRepoView")

-- ── helpers ────────────────────────────────────────────────────────────────

local function sl(s) return (s or ""):gsub("[\n\r]", " ") end

local function trunc(s, n)
  s = sl(s)
  return #s > n and s:sub(1, n - 3) .. "…" or s
end

local function age_string(iso8601)
  if not iso8601 then return "" end
  local y, mo, d, h, mi, s = iso8601:match("(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)")
  if not y then return "" end
  local t    = os.time({ year = y, month = mo, day = d, hour = h, min = mi, sec = s, isdst = false })
  local diff = os.time(os.date("!*t")) - t
  if     diff < 60       then return "just now"
  elseif diff < 3600     then return math.floor(diff / 60)     .. "m ago"
  elseif diff < 86400    then return math.floor(diff / 3600)   .. "h ago"
  elseif diff < 604800   then return math.floor(diff / 86400)  .. "d ago"
  elseif diff < 2592000  then return math.floor(diff / 604800) .. "w ago"
  elseif diff < 31536000 then return math.floor(diff / 2592000) .. "mo ago"
  else                        return math.floor(diff / 31536000) .. "y ago"
  end
end

local function sep()
  return "  " .. string.rep("─", 58)
end

-- ── buffer I/O ─────────────────────────────────────────────────────────────

local function write_buf(lines, hl_specs)
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then return end
  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.bo[state.buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(state.buf, ns, 0, -1)
  for _, spec in ipairs(hl_specs) do
    vim.api.nvim_buf_add_highlight(state.buf, ns, spec.hl, spec.line, spec.col_s,
      spec.col_e == -1 and -1 or spec.col_e)
  end
end

-- ── render ─────────────────────────────────────────────────────────────────

local function render(data)
  local lines    = {}
  local hl_specs = {}
  local items    = {}
  local repo     = state.item and state.item.full_name or "?"

  table.insert(lines, "")

  -- Issues section
  local iss_header = data.issues
    and ("  Issues (" .. #data.issues .. ")")
    or  "  Issues"
  table.insert(lines, iss_header)
  table.insert(hl_specs, { hl = "GhSection", line = #lines - 1, col_s = 0, col_e = #iss_header })

  if data.issues_err then
    local msg = "  ✗ " .. sl(data.issues_err)
    table.insert(lines, msg)
    table.insert(hl_specs, { hl = "GhError", line = #lines - 1, col_s = 0, col_e = #msg })
  elseif not data.issues or #data.issues == 0 then
    local msg = "   No open issues"
    table.insert(lines, msg)
    table.insert(hl_specs, { hl = "GhEmpty", line = #lines - 1, col_s = 0, col_e = #msg })
  else
    for _, iss in ipairs(data.issues) do
      local age    = age_string(iss.updatedAt)
      local author = iss.author and ("@" .. (iss.author.login or "?")) or ""
      local labels = ""
      for _, lbl in ipairs(iss.labels or {}) do
        labels = labels .. " [" .. (lbl.name or "") .. "]"
      end
      local line = string.format("   #%-4d  %-45s  %-20s  %s%s",
        iss.number, trunc(iss.title, 45), author, age, labels)
      table.insert(items, { line = #lines, kind = "issue", number = iss.number, repo = repo })
      table.insert(lines, line)
      table.insert(hl_specs, { hl = "GhItem", line = #lines - 1, col_s = 0,  col_e = 9 })
      table.insert(hl_specs, { hl = "GhMeta", line = #lines - 1, col_s = 57, col_e = -1 })
    end
  end

  table.insert(lines, sep())
  table.insert(hl_specs, { hl = "GhSeparator", line = #lines - 1, col_s = 0, col_e = -1 })

  -- PRs section
  local pr_header = data.prs
    and ("  Pull Requests (" .. #data.prs .. ")")
    or  "  Pull Requests"
  table.insert(lines, pr_header)
  table.insert(hl_specs, { hl = "GhSection", line = #lines - 1, col_s = 0, col_e = #pr_header })

  if data.prs_err then
    local msg = "  ✗ " .. sl(data.prs_err)
    table.insert(lines, msg)
    table.insert(hl_specs, { hl = "GhError", line = #lines - 1, col_s = 0, col_e = #msg })
  elseif not data.prs or #data.prs == 0 then
    local msg = "   No open pull requests"
    table.insert(lines, msg)
    table.insert(hl_specs, { hl = "GhEmpty", line = #lines - 1, col_s = 0, col_e = #msg })
  else
    for _, pr in ipairs(data.prs) do
      local age    = age_string(pr.updatedAt)
      local draft  = pr.isDraft and " [draft]" or ""
      local author = pr.author and ("@" .. (pr.author.login or "?")) or ""
      local line   = string.format("   #%-4d  %-45s  %-20s  %s%s",
        pr.number, trunc(pr.title, 45), author, age, draft)
      table.insert(items, { line = #lines, kind = "pr", number = pr.number, repo = repo })
      table.insert(lines, line)
      local ln      = #lines - 1
      local age_col = 3 + 1 + 4 + 2 + 45 + 2 + 20 + 2
      local tag_col = age_col + #age
      table.insert(hl_specs, { hl = "GhItem",   line = ln, col_s = 0,       col_e = 9 })
      table.insert(hl_specs, { hl = "GhMeta",   line = ln, col_s = age_col, col_e = tag_col })
      if draft ~= "" then
        table.insert(hl_specs, { hl = "GhPRDraft", line = ln, col_s = tag_col, col_e = tag_col + #draft })
      end
    end
  end

  table.insert(lines, sep())
  table.insert(hl_specs, { hl = "GhSeparator", line = #lines - 1, col_s = 0, col_e = -1 })

  -- Branches section
  local br_header = "  Branches"
  table.insert(lines, br_header)
  table.insert(hl_specs, { hl = "GhSection", line = #lines - 1, col_s = 0, col_e = #br_header })

  if data.branches_err then
    local msg = "  ✗ " .. sl(data.branches_err)
    table.insert(lines, msg)
    table.insert(hl_specs, { hl = "GhError", line = #lines - 1, col_s = 0, col_e = #msg })
  elseif not data.branches or #data.branches == 0 then
    local msg = "   No branches"
    table.insert(lines, msg)
    table.insert(hl_specs, { hl = "GhEmpty", line = #lines - 1, col_s = 0, col_e = #msg })
  else
    local names = {}
    for _, b in ipairs(data.branches) do table.insert(names, b.name) end
    local line = "   " .. table.concat(names, "  ·  ")
    table.insert(lines, line)
    table.insert(hl_specs, { hl = "GhStats", line = #lines - 1, col_s = 0, col_e = -1 })
  end

  table.insert(lines, "")

  state.items = items
  write_buf(lines, hl_specs)
end

-- ── fetch ──────────────────────────────────────────────────────────────────

local function fetch_and_render()
  local full_name = state.item.full_name
  local data      = {}
  local pending   = 3

  local function done()
    pending = pending - 1
    if pending ~= 0 then return end
    if state.win and vim.api.nvim_win_is_valid(state.win) then
      vim.api.nvim_win_set_config(state.win, {
        title     = " " .. full_name .. " ",
        title_pos = "center",
      })
    end
    render(data)
  end

  gh.run(
    { "gh", "issue", "list", "-R", full_name, "--state", "open",
      "--json", "number,title,labels,author,updatedAt", "--limit", "20" },
    function(err, issues)
      if err then data.issues_err = err else data.issues = issues end
      done()
    end
  )
  gh.run(
    { "gh", "pr", "list", "-R", full_name, "--state", "open",
      "--json", "number,title,author,isDraft,updatedAt", "--limit", "10" },
    function(err, prs)
      if err then data.prs_err = err else data.prs = prs end
      done()
    end
  )
  gh.run(
    { "gh", "api", "repos/" .. full_name .. "/branches",
      "--jq", "[.[] | {name:.name}] | .[0:15]" },
    function(err, branches)
      if err then data.branches_err = err else data.branches = branches end
      done()
    end
  )
end

-- ── input buffer ───────────────────────────────────────────────────────────

local function close_input()
  if state.input_win and vim.api.nvim_win_is_valid(state.input_win) then
    vim.api.nvim_win_close(state.input_win, false)
    state.input_win = nil
    state.input_buf = nil
    vim.cmd("stopinsert")
  end
end

local function open_input(hint, on_submit)
  close_input()
  state.input_buf = vim.api.nvim_create_buf(false, true)
  vim.b[state.input_buf].render_markdown = { enabled = false }
  vim.bo[state.input_buf].buftype   = "nofile"
  vim.bo[state.input_buf].bufhidden = "wipe"
  vim.bo[state.input_buf].filetype  = "text"
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
    footer     = " <C-s> submit  ·  q / <Esc><Esc> cancel ",
    footer_pos = "center",
  })
  vim.wo[state.input_win].number         = false
  vim.wo[state.input_win].relativenumber = false
  vim.wo[state.input_win].signcolumn     = "no"
  vim.wo[state.input_win].wrap           = true
  vim.wo[state.input_win].linebreak      = true
  vim.wo[state.input_win].foldenable     = false
  vim.api.nvim_win_set_cursor(state.input_win, { 1, 0 })
  vim.cmd("startinsert")

  local function do_submit()
    local all_lines = vim.api.nvim_buf_get_lines(state.input_buf, 0, -1, false)
    local body      = table.concat(all_lines, "\n"):gsub("^%s+", ""):gsub("%s+$", "")
    close_input()
    on_submit(body)
  end

  local function imap(mode, lhs, fn)
    vim.keymap.set(mode, lhs, fn, { buffer = state.input_buf, nowait = true, silent = true })
  end
  imap("n", "<C-s>",      do_submit)
  imap("i", "<C-s>",      do_submit)
  imap("n", "<Esc><Esc>", close_input)
  imap("n", "q",          close_input)

  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = state.input_buf, once = true,
    callback = function()
      state.input_buf = nil
      state.input_win = nil
    end,
  })
end

-- ── window ─────────────────────────────────────────────────────────────────

local function close_win()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, false)
    state.win = nil
  end
end

local function open_win()
  local title = " " .. (state.item and state.item.full_name or "…") .. " — loading… "

  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
    state.buf = vim.api.nvim_create_buf(false, true)
    vim.b[state.buf].render_markdown = { enabled = false }
    vim.bo[state.buf].bufhidden  = "wipe"
    vim.bo[state.buf].buftype    = "nofile"
    vim.bo[state.buf].modifiable = false
  end

  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_set_config(state.win, { title = title, title_pos = "center" })
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
    title      = title,
    title_pos  = "center",
    footer     = " <CR> open  ·  n new issue  ·  r refresh  ·  q close ",
    footer_pos = "center",
  })
  vim.wo[state.win].number         = false
  vim.wo[state.win].relativenumber = false
  vim.wo[state.win].signcolumn     = "no"
  vim.wo[state.win].wrap           = false
  vim.wo[state.win].cursorline     = true
  vim.wo[state.win].foldenable     = false

  highlights.setup()

  local function bmap(lhs, fn)
    vim.keymap.set("n", lhs, fn, { buffer = state.buf, nowait = true, silent = true })
  end

  bmap("q",     close_win)
  bmap("<Esc>", close_win)
  bmap("r", function()
    if state.item then M.open(state.item) end
  end)
  bmap("<CR>", function()
    if not state.win or not vim.api.nvim_win_is_valid(state.win) then return end
    local cur = vim.api.nvim_win_get_cursor(state.win)[1] - 1
    for _, item in ipairs(state.items) do
      if item.line == cur then
        require("gh_dashboard.reader").open(item)
        return
      end
    end
  end)
  bmap("n", function()
    if not state.item then return end
    local repo = state.item.full_name
    vim.ui.input({ prompt = "Issue title: " }, function(title_input)
      if not title_input or vim.trim(title_input) == "" then return end
      local issue_title = vim.trim(title_input)
      open_input("Issue body (optional)", function(body)
        actions.create_issue(repo, issue_title, body, function(err)
          if err then
            vim.notify("Create issue failed: " .. err, vim.log.levels.ERROR)
          else
            vim.notify("Issue created in " .. repo, vim.log.levels.INFO)
            M.open(state.item)
          end
        end)
      end)
    end)
  end)
end

-- ── public API ─────────────────────────────────────────────────────────────

function M.open(item)
  state.item  = item
  state.items = {}
  open_win()
  fetch_and_render()
end

return M
