local M = {}

-- ── constants ──────────────────────────────────────────────────────────────

local WATCHLIST_PATH = vim.fn.expand("~/.config/nvim/gh-watchlist.json")
local NOTIF_WIDTH    = 54
local NOTIF_HEIGHT   = 3
local MAX_NOTIFS     = 3
local MAX_HISTORY    = 20
local NOTIF_TTL_MS   = 5000
local POLL_DELAY_MS  = 5000
local POLL_REPEAT_MS = 60000

-- ── state ──────────────────────────────────────────────────────────────────

local state = {
  repos        = {},   -- list of { owner, repo, last_seen_id }
  poll_timer   = nil,
  notifs       = {},   -- list of { win, buf, timer, _repo, _ev }
  history      = {},   -- list of { _repo, _ev } newest-first, max MAX_HISTORY
  manager_buf  = nil,
  manager_win  = nil,
}

-- ── highlights ─────────────────────────────────────────────────────────────

local ns = vim.api.nvim_create_namespace("GhWatchlist")

local function setup_highlights()
  vim.api.nvim_set_hl(0, "GhWatchTitle",  { fg = "#7fc8f8", bold = true       })
  vim.api.nvim_set_hl(0, "GhWatchRepo",   { fg = "#abb2bf"                    })
  vim.api.nvim_set_hl(0, "GhWatchNotif",  { fg = "#e5c07b"                    })
  vim.api.nvim_set_hl(0, "GhWatchEmpty",  { fg = "#4b5263", italic = true     })
  vim.api.nvim_set_hl(0, "GhWatchSep",    { fg = "#3b4048"                    })
  vim.api.nvim_set_hl(0, "GhWatchMeta",   { fg = "#4b5263"                    })
end

-- ── persistence ────────────────────────────────────────────────────────────

local function load_watchlist()
  if vim.fn.filereadable(WATCHLIST_PATH) == 0 then return end
  local lines = vim.fn.readfile(WATCHLIST_PATH)
  if not lines or #lines == 0 then return end
  local ok, data = pcall(vim.fn.json_decode, table.concat(lines, "\n"))
  if ok and type(data) == "table" and type(data.repos) == "table" then
    state.repos = data.repos
  end
end

local function save_watchlist()
  local tmp = WATCHLIST_PATH .. ".tmp"
  vim.fn.writefile({ vim.fn.json_encode({ repos = state.repos }) }, tmp)
  vim.uv.fs_rename(tmp, WATCHLIST_PATH, function() end)
end

-- ── buffer helper ──────────────────────────────────────────────────────────

local function write_buf(buf, lines, hl_specs)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for _, spec in ipairs(hl_specs) do
    vim.api.nvim_buf_add_highlight(buf, ns, spec.hl, spec.line,
      spec.col_s, spec.col_e == -1 and -1 or spec.col_e)
  end
end

-- ── async gh runner ────────────────────────────────────────────────────────

local function run_gh(args, callback)
  vim.system(args, { text = true }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then callback(nil) return end
      local ok, data = pcall(vim.fn.json_decode, result.stdout)
      callback(ok and data or nil)
    end)
  end)
end

-- ── notification HUD ──────────────────────────────────────────────────────

local EVENT_LABELS = {
  PushEvent              = "push",
  PullRequestEvent       = "PR",
  IssuesEvent            = "issue",
  IssueCommentEvent      = "comment",
  PullRequestReviewEvent = "review",
  CreateEvent            = "branch/tag created",
  DeleteEvent            = "branch/tag deleted",
  ForkEvent              = "forked",
  WatchEvent             = "starred",
}

local function event_label(ev)
  local base = EVENT_LABELS[ev.type] or "activity"
  local p = ev.payload or {}
  if ev.type == "PullRequestEvent" then
    local num = type(p.pull_request) == "table" and p.pull_request.number or nil
    local act = p.action or ""
    return num and ("PR #" .. num .. " " .. act) or ("PR " .. act)
  elseif ev.type == "IssuesEvent" then
    local num = type(p.issue) == "table" and p.issue.number or nil
    local act = p.action or ""
    return num and ("issue #" .. num .. " " .. act) or ("issue " .. act)
  elseif ev.type == "IssueCommentEvent" then
    local num = type(p.issue) == "table" and p.issue.number or nil
    return num and ("comment on #" .. num) or "comment"
  elseif ev.type == "PullRequestReviewEvent" then
    local num = type(p.pull_request) == "table" and p.pull_request.number or nil
    return num and ("review on PR #" .. num) or "review"
  elseif ev.type == "PushEvent" then
    local ref  = type(p.ref) == "string" and p.ref:gsub("^refs/heads/", "") or ""
    local size = type(p.size) == "number" and p.size or 0
    return "push" .. (ref ~= "" and (" → " .. ref) or "") .. " (" .. size .. ")"
  end
  return base
end

local function show_notification(repo, ev)
  local ui  = vim.api.nvim_list_uis()[1] or { width = 180, height = 50 }

  -- evict oldest if at cap
  if #state.notifs >= MAX_NOTIFS then
    local oldest = table.remove(state.notifs, 1)
    if oldest.timer then oldest.timer:stop() oldest.timer:close() end
    if oldest.win and vim.api.nvim_win_is_valid(oldest.win) then
      pcall(vim.api.nvim_win_close, oldest.win, true)
    end
  end

  local slot = #state.notifs
  local row  = 1 + slot * (NOTIF_HEIGHT + 1)
  local col  = ui.width - NOTIF_WIDTH - 2
  local label = event_label(ev)
  local text  = "  ⊙ " .. repo .. "  ·  " .. label

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { text, "", "" })
  vim.bo[buf].modifiable = false
  vim.api.nvim_buf_add_highlight(buf, ns, "GhWatchNotif", 0, 2, 5)  -- ⊙ bullet (3 bytes)
  vim.api.nvim_buf_add_highlight(buf, ns, "GhWatchRepo",  0, 5, 5 + #repo)

  local win = vim.api.nvim_open_win(buf, false, {
    relative  = "editor",
    row       = row,
    col       = col,
    width     = NOTIF_WIDTH,
    height    = NOTIF_HEIGHT,
    style     = "minimal",
    border    = "rounded",
    focusable = false,
    zindex    = 50,
  })

  local t = vim.uv.new_timer()
  t:start(NOTIF_TTL_MS, 0, vim.schedule_wrap(function()
    t:stop() t:close()
    if vim.api.nvim_win_is_valid(win) then
      pcall(vim.api.nvim_win_close, win, true)
    end
    for i, n in ipairs(state.notifs) do
      if n.win == win then table.remove(state.notifs, i) break end
    end
  end))

  table.insert(state.notifs, { win = win, buf = buf, timer = t, _repo = repo, _ev = ev })

  -- keep a history so open_latest works after the popup auto-dismisses
  table.insert(state.history, 1, { _repo = repo, _ev = ev })
  if #state.history > MAX_HISTORY then table.remove(state.history) end
end

-- ── polling ────────────────────────────────────────────────────────────────

local function poll_repo(entry)
  run_gh(
    { "gh", "api",
      "repos/" .. entry.owner .. "/" .. entry.repo .. "/events",
      "--jq", "[.[] | {id,type,created_at,payload}] | .[0:10]" },
    function(events)
      if not events or type(events) ~= "table" or #events == 0 then return end
      local new_events = {}
      for _, ev in ipairs(events) do
        if tostring(ev.id) == tostring(entry.last_seen_id) then break end
        table.insert(new_events, ev)
      end
      if #new_events > 0 then
        entry.last_seen_id = tostring(events[1].id)
        save_watchlist()
        for _, ev in ipairs(new_events) do
          local ok, err = pcall(show_notification, entry.owner .. "/" .. entry.repo, ev)
          if not ok then
            vim.notify("watchlist: notif error — " .. tostring(err), vim.log.levels.WARN)
          end
        end
      end
    end
  )
end

local function seed_history()
  for _, entry in ipairs(state.repos) do
    run_gh(
      { "gh", "api",
        "repos/" .. entry.owner .. "/" .. entry.repo .. "/events",
        "--jq", "[.[] | {id,type,created_at,payload}] | .[0:5]" },
      function(events)
        if not events or type(events) ~= "table" then return end
        local repo_key = entry.owner .. "/" .. entry.repo
        for _, ev in ipairs(events) do
          table.insert(state.history, { _repo = repo_key, _ev = ev })
        end
        while #state.history > MAX_HISTORY do
          table.remove(state.history)
        end
      end
    )
  end
end

local function poll()
  for _, entry in ipairs(state.repos) do
    poll_repo(entry)
  end
end

-- ── watchlist manager ─────────────────────────────────────────────────────

local function render_manager()
  if not state.manager_buf or not vim.api.nvim_buf_is_valid(state.manager_buf) then return end
  local lines    = {}
  local hl_specs = {}

  table.insert(lines, "")
  if #state.repos == 0 then
    local msg = "   No repos watched. Press 'a' to add one."
    table.insert(lines, msg)
    table.insert(hl_specs, { hl = "GhWatchEmpty", line = #lines - 1, col_s = 0, col_e = -1 })
  else
    for _, entry in ipairs(state.repos) do
      local line = "   " .. entry.owner .. "/" .. entry.repo
      table.insert(lines, line)
      table.insert(hl_specs, { hl = "GhWatchRepo", line = #lines - 1, col_s = 3, col_e = -1 })
    end
  end
  table.insert(lines, "")

  write_buf(state.manager_buf, lines, hl_specs)
end

local function close_manager()
  if state.manager_win and vim.api.nvim_win_is_valid(state.manager_win) then
    vim.api.nvim_win_close(state.manager_win, false)
    state.manager_win = nil
  end
end

local function open_add_input()
  local input_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[input_buf].buftype   = "nofile"
  vim.bo[input_buf].bufhidden = "wipe"
  vim.bo[input_buf].filetype  = "text"

  vim.api.nvim_buf_set_lines(input_buf, 0, -1, false, { "", "" })

  local ui    = vim.api.nvim_list_uis()[1] or { width = 180, height = 50 }
  local width = math.floor(ui.width * 0.50)
  local height = 5
  local row   = math.floor((ui.height - height) / 2)
  local col   = math.floor((ui.width  - width)  / 2)

  local input_win = vim.api.nvim_open_win(input_buf, true, {
    relative   = "editor",
    width      = width,
    height     = height,
    row        = row,
    col        = col,
    style      = "minimal",
    border     = "rounded",
    title      = " Add repo (owner/repo) ",
    title_pos  = "center",
    footer     = " <C-s> confirm  ·  <Esc><Esc> cancel ",
    footer_pos = "center",
  })
  vim.wo[input_win].wrap = true

  vim.api.nvim_win_set_cursor(input_win, { 1, 0 })
  vim.cmd("startinsert")

  local function do_cancel()
    if vim.api.nvim_win_is_valid(input_win) then
      vim.api.nvim_win_close(input_win, true)
    end
  end

  local function do_confirm()
    local text = vim.trim(vim.api.nvim_buf_get_lines(input_buf, 0, 1, false)[1] or "")
    if vim.api.nvim_win_is_valid(input_win) then
      vim.api.nvim_win_close(input_win, true)
    end
    if text == "" then return end
    local owner, repo = text:match("^([^/]+)/([^/]+)$")
    if not owner or not repo then
      vim.notify("Invalid format — use owner/repo", vim.log.levels.WARN)
      return
    end
    -- check for duplicate
    for _, e in ipairs(state.repos) do
      if e.owner == owner and e.repo == repo then
        vim.notify(text .. " is already on the watchlist", vim.log.levels.INFO)
        return
      end
    end
    table.insert(state.repos, { owner = owner, repo = repo, last_seen_id = "" })
    save_watchlist()
    render_manager()
    -- move cursor to newly added entry
    if state.manager_win and vim.api.nvim_win_is_valid(state.manager_win) then
      local lines = vim.api.nvim_buf_get_lines(state.manager_buf, 0, -1, false)
      vim.api.nvim_win_set_cursor(state.manager_win, { math.max(1, #lines - 1), 0 })
    end
  end

  local function imap(mode, lhs, fn)
    vim.keymap.set(mode, lhs, fn, { buffer = input_buf, nowait = true, silent = true })
  end
  imap("n", "<C-s>", do_confirm)
  imap("i", "<C-s>", do_confirm)
  imap("n", "<Esc><Esc>", do_cancel)

  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = input_buf, once = true,
    callback = function() end,
  })
end

local function remove_at_cursor()
  if not state.manager_win or not vim.api.nvim_win_is_valid(state.manager_win) then return end
  if #state.repos == 0 then return end
  local cur = vim.api.nvim_win_get_cursor(state.manager_win)[1]
  -- line 1 = "", line 2 = first repo (if any), etc.
  local idx = cur - 1  -- accounts for leading empty line
  if idx < 1 or idx > #state.repos then return end
  local removed = state.repos[idx]
  table.remove(state.repos, idx)
  save_watchlist()
  render_manager()
  vim.notify("Removed " .. removed.owner .. "/" .. removed.repo, vim.log.levels.INFO)
end

local function open_manager()
  if state.manager_win and vim.api.nvim_win_is_valid(state.manager_win) then
    vim.api.nvim_set_current_win(state.manager_win)
    return
  end

  if not state.manager_buf or not vim.api.nvim_buf_is_valid(state.manager_buf) then
    state.manager_buf = vim.api.nvim_create_buf(false, true)
    vim.bo[state.manager_buf].buftype    = "nofile"
    vim.bo[state.manager_buf].bufhidden  = "wipe"
    vim.bo[state.manager_buf].modifiable = false
    vim.bo[state.manager_buf].filetype   = "text"
  end

  local ui     = vim.api.nvim_list_uis()[1] or { width = 180, height = 50 }
  local width  = math.floor(ui.width  * 0.70)
  local height = math.floor(ui.height * 0.50)
  local row    = math.floor((ui.height - height) / 2)
  local col    = math.floor((ui.width  - width)  / 2)

  state.manager_win = vim.api.nvim_open_win(state.manager_buf, true, {
    relative   = "editor",
    width      = width,
    height     = height,
    row        = row,
    col        = col,
    style      = "minimal",
    border     = "rounded",
    title      = " Watched Repos ",
    title_pos  = "center",
    footer     = " a add  ·  d remove  ·  q close ",
    footer_pos = "center",
  })
  vim.wo[state.manager_win].number         = false
  vim.wo[state.manager_win].relativenumber = false
  vim.wo[state.manager_win].signcolumn     = "no"
  vim.wo[state.manager_win].cursorline     = true

  render_manager()

  local function bmap(lhs, fn)
    vim.keymap.set("n", lhs, fn, { buffer = state.manager_buf, nowait = true, silent = true })
  end
  bmap("a",     open_add_input)
  bmap("d",     remove_at_cursor)
  bmap("x",     remove_at_cursor)
  bmap("q",     close_manager)
  bmap("<Esc>", close_manager)

  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = state.manager_buf, once = true,
    callback = function()
      state.manager_buf = nil
      state.manager_win = nil
    end,
  })
end

-- ── jump to activity ──────────────────────────────────────────────────────

local function open_event(repo, ev)
  local p = ev.payload or {}
  if ev.type == "PullRequestEvent" then
    local num = type(p.pull_request) == "table" and p.pull_request.number or nil
    if num then
      require("gh_dashboard.reader").open({ kind = "pr", number = num, repo = repo })
      return
    end
  elseif ev.type == "IssuesEvent" then
    local num = type(p.issue) == "table" and p.issue.number or nil
    if num then
      require("gh_dashboard.reader").open({ kind = "issue", number = num, repo = repo })
      return
    end
  elseif ev.type == "IssueCommentEvent" then
    local num = type(p.issue) == "table" and p.issue.number or nil
    if num then
      require("gh_dashboard.reader").open({ kind = "issue", number = num, repo = repo })
      return
    end
  end
  vim.system({ "xdg-open", "https://github.com/" .. repo })
end

local function open_history_popup()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype    = "nofile"
  vim.bo[buf].bufhidden  = "wipe"
  vim.bo[buf].filetype   = "text"
  vim.bo[buf].modifiable = false

  local lines, hl_specs = {}, {}
  table.insert(lines, "")
  for _, entry in ipairs(state.history) do
    local label = event_label(entry._ev)
    local line  = "   " .. entry._repo .. "  ·  " .. label
    table.insert(lines, line)
    table.insert(hl_specs, { hl = "GhWatchRepo",  line = #lines - 1, col_s = 3, col_e = 3 + #entry._repo })
    table.insert(hl_specs, { hl = "GhWatchMeta",  line = #lines - 1, col_s = 3 + #entry._repo, col_e = -1 })
  end
  table.insert(lines, "")
  write_buf(buf, lines, hl_specs)

  local ui     = vim.api.nvim_list_uis()[1] or { width = 180, height = 50 }
  local width  = math.floor(ui.width  * 0.70)
  local height = math.floor(ui.height * 0.50)
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
    title      = " Recent Notifications ",
    title_pos  = "center",
    footer     = " <CR> open  ·  q close ",
    footer_pos = "center",
  })
  vim.wo[win].cursorline     = true
  vim.wo[win].number         = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn     = "no"

  local function bmap(lhs, fn)
    vim.keymap.set("n", lhs, fn, { buffer = buf, nowait = true, silent = true })
  end

  local function open_at_cursor()
    local cur = vim.api.nvim_win_get_cursor(win)[1]
    local idx = cur - 1  -- offset for leading blank line
    if idx < 1 or idx > #state.history then return end
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, false)
    end
    open_event(state.history[idx]._repo, state.history[idx]._ev)
  end

  bmap("<CR>",  open_at_cursor)
  bmap("q",     function() if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, false) end end)
  bmap("<Esc>", function() if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, false) end end)
end

M.open_latest = function()
  -- prefer a live popup: dismiss it and open directly
  local last = state.notifs[#state.notifs]
  if last then
    if last.timer then last.timer:stop() last.timer:close() end
    if last.win and vim.api.nvim_win_is_valid(last.win) then
      pcall(vim.api.nvim_win_close, last.win, true)
    end
    table.remove(state.notifs)
    open_event(last._repo, last._ev)
    return
  end
  -- fall back to browseable history
  if #state.history == 0 then
    vim.notify("No recent notifications", vim.log.levels.INFO)
    return
  end
  open_history_popup()
end

-- ── public API — toggle_repo ─────────────────────────────────────────────

M.toggle_repo = function(full_name)
  local owner, repo = full_name:match("^([^/]+)/([^/]+)$")
  if not owner or not repo then return end
  for i, e in ipairs(state.repos) do
    if e.owner == owner and e.repo == repo then
      table.remove(state.repos, i)
      save_watchlist()
      vim.notify("Removed " .. full_name .. " from watchlist", vim.log.levels.INFO)
      return
    end
  end
  table.insert(state.repos, { owner = owner, repo = repo, last_seen_id = "" })
  save_watchlist()
  vim.notify("Added " .. full_name .. " to watchlist", vim.log.levels.INFO)
end

-- ── public API ────────────────────────────────────────────────────────────

M.toggle = function()
  if state.manager_win and vim.api.nvim_win_is_valid(state.manager_win) then
    close_manager()
    return
  end
  open_manager()
end

M.setup = function()
  setup_highlights()
  vim.fn.mkdir(vim.fn.fnamemodify(WATCHLIST_PATH, ":h"), "p")
  load_watchlist()
  seed_history()
  state.poll_timer = vim.uv.new_timer()
  state.poll_timer:start(POLL_DELAY_MS, POLL_REPEAT_MS, vim.schedule_wrap(poll))
  vim.api.nvim_create_autocmd("ColorScheme", {
    callback = setup_highlights,
    desc = "Re-apply GhWatchlist highlights on colorscheme change",
  })
end

return M
