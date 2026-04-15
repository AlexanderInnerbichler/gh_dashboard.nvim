local M = {}

local ns = vim.api.nvim_create_namespace("GhDayActivity")

-- ── fetch ──────────────────────────────────────────────────────────────────

local function fetch_day_events(username, date, callback)
  local jq = '[.[] | select(.created_at | startswith("' .. date .. '"))]'
  vim.system(
    { "gh", "api", "/users/" .. username .. "/events", "--jq", jq },
    { text = true },
    function(result)
      vim.schedule(function()
        if result.code ~= 0 then
          callback(result.stderr or "gh error", nil)
          return
        end
        local ok, decoded = pcall(vim.fn.json_decode, result.stdout)
        if not ok then
          callback("json decode error", nil)
          return
        end
        if type(decoded) ~= "table" then decoded = {} end
        callback(nil, decoded)
      end)
    end
  )
end

-- ── formatting ─────────────────────────────────────────────────────────────

local function event_summary(ev)
  local t    = ev.type or "Event"
  local p    = ev.payload or {}
  local repo = (ev.repo or {}).name or "?"

  if t == "PullRequestEvent" then
    local pr  = p.pull_request or {}
    local num = pr.number or p.number or "?"
    local act = p.action or "updated"
    if act == "closed" and pr.merged then act = "merged" end
    return repo, string.format("%s PR #%s", act, num)
  elseif t == "IssuesEvent" then
    local num = (p.issue or {}).number or "?"
    return repo, string.format("%s issue #%s", p.action or "updated", num)
  elseif t == "IssueCommentEvent" then
    local num = (p.issue or {}).number or "?"
    return repo, string.format("commented on issue #%s", num)
  elseif t == "CreateEvent" then
    return repo, string.format("created %s %s", p.ref_type or "", p.ref or "")
  elseif t == "ForkEvent" then
    return repo, "forked"
  elseif t == "WatchEvent" then
    return repo, "starred"
  elseif t == "DeleteEvent" then
    return repo, string.format("deleted %s %s", p.ref_type or "", p.ref or "")
  elseif t == "ReleaseEvent" then
    local tag = (p.release or {}).tag_name or ""
    return repo, string.format("%s release %s", p.action or "published", tag)
  else
    return repo, t
  end
end

-- ── rendering ─────────────────────────────────────────────────────────────

local function render_events(lines, hl_specs, username, date, events, err)
  local crumb_prefix = "  GitHub Dashboard  ›  "
  local crumb        = crumb_prefix .. "@" .. username .. "  ›  " .. date
  table.insert(lines, crumb)
  table.insert(hl_specs, { hl = "GhReaderBreadcrumb", line = #lines - 1, col_s = 0,             col_e = #crumb_prefix })
  table.insert(hl_specs, { hl = "GhReaderTitle",      line = #lines - 1, col_s = #crumb_prefix, col_e = -1 })
  table.insert(lines, "")

  if err then
    local msg = "  ✗ " .. (err:gsub("[\n\r]", " "))
    table.insert(lines, msg)
    table.insert(hl_specs, { hl = "GhError", line = #lines - 1, col_s = 0, col_e = #msg })
    return
  end

  if #events == 0 then
    local msg = "  No activity on this day"
    table.insert(lines, msg)
    table.insert(hl_specs, { hl = "GhStats", line = #lines - 1, col_s = 0, col_e = #msg })
    return
  end

  -- aggregate push events by repo; collect unique branches pushed to
  local push_branches = {}  -- repo → list of unique branch names (ordered)
  for _, ev in ipairs(events) do
    if ev.type == "PushEvent" then
      local repo   = (ev.repo or {}).name or "?"
      local ref    = (ev.payload or {}).ref or ""
      local branch = ref:gsub("^refs/heads/", "")
      if not push_branches[repo] then push_branches[repo] = {} end
      local seen = false
      for _, b in ipairs(push_branches[repo]) do
        if b == branch then seen = true; break end
      end
      if not seen then table.insert(push_branches[repo], branch) end
    end
  end

  local push_rendered = {}
  for _, ev in ipairs(events) do
    local repo, summary
    if ev.type == "PushEvent" then
      repo = (ev.repo or {}).name or "?"
      if push_rendered[repo] then goto continue end
      push_rendered[repo] = true
      local branches = push_branches[repo] or {}
      summary = "pushed to " .. table.concat(branches, ", ")
    else
      repo, summary = event_summary(ev)
    end
    local row = string.format("  %-40s  %s", repo, summary)
    table.insert(lines, row)
    table.insert(hl_specs, { hl = "GhRepo",  line = #lines - 1, col_s = 2,  col_e = 42 })
    table.insert(hl_specs, { hl = "GhStats", line = #lines - 1, col_s = 44, col_e = #row })
    ::continue::
  end
end

-- ── public API ─────────────────────────────────────────────────────────────

M.open = function(username, date)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype    = "nofile"
  vim.bo[buf].bufhidden  = "wipe"
  vim.bo[buf].modifiable = true
  vim.bo[buf].filetype   = "text"

  local ui     = vim.api.nvim_list_uis()[1] or { width = 180, height = 50 }
  local width  = math.floor(ui.width  * 0.90)
  local height = math.floor(ui.height * 0.90)
  local row    = math.floor((ui.height - height) / 2)
  local col    = math.floor((ui.width  - width)  / 2)

  local win = vim.api.nvim_open_win(buf, true, {
    relative   = "editor",
    width      = width,
    height     = height,
    row        = row,
    col        = col,
    style      = "minimal",
    border     = "rounded",
    title      = " " .. date .. " ",
    title_pos  = "center",
    footer     = " q close ",
    footer_pos = "center",
  })
  vim.wo[win].number         = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn     = "no"
  vim.wo[win].cursorline     = true
  vim.wo[win].wrap           = false
  vim.wo[win].foldenable     = false

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "", "  Loading…", "" })
  vim.bo[buf].modifiable = false

  local function close()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, false)
    end
  end

  local function bmap(lhs, fn)
    vim.keymap.set("n", lhs, fn, { buffer = buf, nowait = true, silent = true })
  end
  bmap("q",     close)
  bmap("<Esc>", close)

  fetch_day_events(username, date, function(err, events)
    if not vim.api.nvim_buf_is_valid(buf) then return end

    local lines, hl_specs = {}, {}
    table.insert(lines, "")
    render_events(lines, hl_specs, username, date, events or {}, err)
    table.insert(lines, "")

    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false
    vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    for _, spec in ipairs(hl_specs) do
      vim.api.nvim_buf_add_highlight(buf, ns, spec.hl, spec.line,
        spec.col_s, spec.col_e == -1 and -1 or spec.col_e)
    end
  end)
end

return M
