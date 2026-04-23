local M = {}
local config     = require("gh_dashboard.config")
local gh         = require("gh_dashboard.gh")
local highlights = require("gh_dashboard.highlights")

-- ── constants ──────────────────────────────────────────────────────────────

local WATCHLIST_PATH = vim.fn.expand("~/.config/nvim/gh-watchlist.json")
local NOTIF_WIDTH    = 60
local NOTIF_HEIGHT   = 4
local POLL_DELAY_MS  = 5000

-- ── state ──────────────────────────────────────────────────────────────────

local state = {
  repos        = {},   -- list of { owner, repo, last_seen_id }
  poll_timer   = nil,
  notifs       = {},   -- list of { win, buf, timer, _repo, _ev }
  history      = {},   -- list of { _repo, _ev } newest-first
  manager_buf  = nil,
  manager_win  = nil,
}

-- ── namespace ──────────────────────────────────────────────────────────────

local ns = vim.api.nvim_create_namespace("GhWatchlist")

-- ── persistence ────────────────────────────────────────────────────────────

local function load_watchlist()
  if vim.fn.filereadable(WATCHLIST_PATH) == 0 then return end
  local lines = vim.fn.readfile(WATCHLIST_PATH)
  if not lines or #lines == 0 then return end
  local ok, data = pcall(vim.fn.json_decode, table.concat(lines, "\n"))
  if ok and type(data) == "table" and type(data.repos) == "table" then
    state.repos = data.repos
    -- migrate legacy last_seen_id → seen_ids
    for _, entry in ipairs(state.repos) do
      if entry.last_seen_id and not entry.seen_ids then
        entry.seen_ids    = { tostring(entry.last_seen_id) }
        entry.last_seen_id = nil
      end
      if not entry.seen_ids then entry.seen_ids = {} end
    end
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

local EVENT_ICONS = {
  PushEvent              = "󰛀 ",
  PullRequestEvent       = "󰘙 ",
  IssuesEvent            = "󰀨 ",
  IssueCommentEvent      = "󰅿 ",
  PullRequestReviewEvent = "󰃤 ",
  CreateEvent            = "󰐕 ",
  DeleteEvent            = "󰍵 ",
  ForkEvent              = "󰈤 ",
  WatchEvent             = "󰓾 ",
}
local DEFAULT_EVENT_ICON = "󰋙 "

local function time_ago(iso)
  if not iso then return "" end
  local y, mo, d, h, mi, s = iso:match("(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)")
  if not y then return "" end
  local t    = os.time({ year = tonumber(y), month = tonumber(mo), day = tonumber(d),
                         hour = tonumber(h), min = tonumber(mi), sec = tonumber(s) })
  local tz   = os.difftime(t, os.time(os.date("!*t", t)))
  local diff = os.time() - (t + tz)
  if diff < 3600   then return math.floor(diff / 60)   .. "m ago"
  elseif diff < 86400 then return math.floor(diff / 3600) .. "h ago"
  else                  return math.floor(diff / 86400) .. "d ago" end
end

local function event_detail(ev)
  local p = ev.payload or {}
  if ev.type == "PullRequestEvent" then
    local pr = p.pull_request
    return (pr and pr.title) or ""
  elseif ev.type == "IssuesEvent" then
    local iss = p.issue
    return (iss and iss.title) or ""
  elseif ev.type == "IssueCommentEvent" then
    local body = (p.comment and p.comment.body) or ""
    return body:match("^([^\n]+)") or ""
  elseif ev.type == "PushEvent" then
    local commits = p.commits
    if type(commits) == "table" and commits[1] then
      return commits[1].message:match("^([^\n]+)") or ""
    end
    return ""
  elseif ev.type == "CreateEvent" then
    return (p.ref_type or "") .. ": " .. (p.ref or "")
  end
  return ""
end

local function show_notification(repo, ev)
  local ui  = vim.api.nvim_list_uis()[1] or { width = 180, height = 50 }

  -- evict oldest if at cap
  if #state.notifs >= config.get().max_notifications then
    local oldest = table.remove(state.notifs, 1)
    if oldest.timer then oldest.timer:stop() oldest.timer:close() end
    if oldest.win and vim.api.nvim_win_is_valid(oldest.win) then
      pcall(vim.api.nvim_win_close, oldest.win, true)
    end
  end

  local slot   = #state.notifs
  local row    = 1 + slot * (NOTIF_HEIGHT + 1)
  local col    = ui.width - NOTIF_WIDTH - 2
  local icon   = EVENT_ICONS[ev.type] or DEFAULT_EVENT_ICON
  local label  = event_label(ev)
  local age    = time_ago(ev.created_at)
  local detail = event_detail(ev)

  local max_detail = NOTIF_WIDTH - 4
  if #detail > max_detail then detail = detail:sub(1, max_detail - 1) .. "…" end

  local line1 = "  " .. icon .. label .. (age ~= "" and ("  ·  " .. age) or "")
  local line2 = detail ~= "" and ("  " .. detail) or nil

  local buf = vim.api.nvim_create_buf(false, true)
  vim.b[buf].render_markdown = { enabled = false }
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { line1, line2 or "", "", "" })
  vim.bo[buf].modifiable = false
  vim.api.nvim_buf_add_highlight(buf, ns, "GhWatchNotif", 0, 2, 2 + #icon)
  if line2 then
    vim.api.nvim_buf_add_highlight(buf, ns, "GhWatchMeta", 1, 0, -1)
  end

  local win = vim.api.nvim_open_win(buf, false, {
    relative   = "editor",
    row        = row,
    col        = col,
    width      = NOTIF_WIDTH,
    height     = NOTIF_HEIGHT,
    style      = "minimal",
    border     = "rounded",
    title      = " " .. repo .. " ",
    title_pos  = "left",
    footer     = " <CR> expand  ·  q dismiss ",
    footer_pos = "center",
    focusable  = true,
    zindex     = 50,
  })
  vim.api.nvim_set_option_value("winhl",
    "FloatTitle:GhWatchTitle,FloatBorder:GhWatchNotif", { win = win })
  vim.wo[win].foldenable = false

  local function close_notif()
    if vim.api.nvim_win_is_valid(win) then
      pcall(vim.api.nvim_win_close, win, true)
    end
    for i, n in ipairs(state.notifs) do
      if n.win == win then table.remove(state.notifs, i) break end
    end
  end

  vim.keymap.set("n", "<CR>",  function() close_notif(); open_event(repo, ev) end,
    { buffer = buf, nowait = true, silent = true })
  vim.keymap.set("n", "q",     close_notif, { buffer = buf, nowait = true, silent = true })
  vim.keymap.set("n", "<Esc>", close_notif, { buffer = buf, nowait = true, silent = true })

  local t = vim.uv.new_timer()
  t:start(config.get().notification_ttl * 1000, 0, vim.schedule_wrap(function()
    t:stop() t:close()
    close_notif()
  end))

  table.insert(state.notifs, { win = win, buf = buf, timer = t, _repo = repo, _ev = ev })

  -- keep a history so open_latest works after the popup auto-dismisses
  table.insert(state.history, 1, { _repo = repo, _ev = ev })
  if #state.history > config.get().max_history then table.remove(state.history) end
end

-- ── polling ────────────────────────────────────────────────────────────────

local function is_new(entry, ev_id)
  for _, id in ipairs(entry.seen_ids or {}) do
    if id == ev_id then return false end
  end
  return true
end

local function mark_seen(entry, ev_id)
  entry.seen_ids = entry.seen_ids or {}
  table.insert(entry.seen_ids, 1, ev_id)
  if #entry.seen_ids > 50 then table.remove(entry.seen_ids) end
end

local function seed_seen(entry)
  gh.run(
    { "gh", "api", "repos/" .. entry.owner .. "/" .. entry.repo .. "/events",
      "--jq", "[.[] | {id}] | .[0:10]" },
    function(err, events)
      if err or type(events) ~= "table" then return end
      for _, ev in ipairs(events) do
        mark_seen(entry, tostring(ev.id))
      end
      save_watchlist()
    end
  )
end

local function poll_repo(entry)
  gh.run_with_retry(
    { "gh", "api",
      "repos/" .. entry.owner .. "/" .. entry.repo .. "/events",
      "--jq", "[.[] | {id,type,created_at,payload}] | .[0:10]" },
    function(err, events)
      if err or not events or type(events) ~= "table" or #events == 0 then return end
      local new_events = {}
      for _, ev in ipairs(events) do
        local ev_id = tostring(ev.id)
        if is_new(entry, ev_id) then
          table.insert(new_events, ev)
          mark_seen(entry, ev_id)
        end
      end
      if #new_events > 0 then
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
    gh.run(
      { "gh", "api",
        "repos/" .. entry.owner .. "/" .. entry.repo .. "/events",
        "--jq", "[.[] | {id,type,created_at,payload}] | .[0:5]" },
      function(err, events)
        if err or not events or type(events) ~= "table" then return end
        local repo_key = entry.owner .. "/" .. entry.repo
        for _, ev in ipairs(events) do
          table.insert(state.history, { _repo = repo_key, _ev = ev })
        end
        while #state.history > config.get().max_history do
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
  vim.wo[input_win].wrap       = true
  vim.wo[input_win].foldenable = false

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

local function open_repo_at_cursor()
  if not state.manager_win or not vim.api.nvim_win_is_valid(state.manager_win) then return end
  if #state.repos == 0 then return end
  local cur = vim.api.nvim_win_get_cursor(state.manager_win)[1]
  local idx = cur - 1
  if idx < 1 or idx > #state.repos then return end
  local entry = state.repos[idx]
  require("gh_dashboard.repo_view").open({
    kind      = "repo",
    full_name = entry.owner .. "/" .. entry.repo,
  })
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
    footer     = " <CR> view  ·  a add  ·  d remove  ·  q close ",
    footer_pos = "center",
  })
  vim.wo[state.manager_win].number         = false
  vim.wo[state.manager_win].relativenumber = false
  vim.wo[state.manager_win].signcolumn     = "no"
  vim.wo[state.manager_win].cursorline     = true
  vim.wo[state.manager_win].foldenable     = false

  render_manager()

  local function bmap(lhs, fn)
    vim.keymap.set("n", lhs, fn, { buffer = state.manager_buf, nowait = true, silent = true })
  end
  bmap("<CR>",  open_repo_at_cursor)
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
    local icon  = EVENT_ICONS[entry._ev.type] or DEFAULT_EVENT_ICON
    local label = event_label(entry._ev)
    local repo  = entry._repo
    local age   = time_ago(entry._ev.created_at)
    local age_part = age ~= "" and ("  ·  " .. age) or ""
    local line  = "   " .. icon .. label .. "  ·  " .. repo .. age_part
    local ln         = #lines
    local icon_s     = 3
    local icon_e     = icon_s + #icon
    local label_e    = icon_e + #label
    local repo_s     = label_e + 5  -- "  ·  "
    local repo_e     = repo_s + #repo
    local age_s      = repo_e + 5
    table.insert(lines, line)
    table.insert(hl_specs, { hl = "GhWatchNotif", line = ln, col_s = icon_s, col_e = icon_e })
    table.insert(hl_specs, { hl = "GhWatchTitle", line = ln, col_s = icon_e, col_e = label_e })
    table.insert(hl_specs, { hl = "GhWatchRepo",  line = ln, col_s = repo_s, col_e = repo_e })
    if age ~= "" then
      table.insert(hl_specs, { hl = "GhWatchMeta", line = ln, col_s = age_s, col_e = -1 })
    end
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
  vim.api.nvim_set_option_value("winhl",
    "FloatTitle:GhWatchTitle,FloatBorder:GhWatchSep", { win = win })
  vim.wo[win].cursorline     = true
  vim.wo[win].number         = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn     = "no"
  vim.wo[win].foldenable     = false

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

M.get_repos = function()
  return state.repos
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
  local entry = { owner = owner, repo = repo, seen_ids = {} }
  table.insert(state.repos, entry)
  save_watchlist()
  seed_seen(entry)
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
  vim.fn.mkdir(vim.fn.fnamemodify(WATCHLIST_PATH, ":h"), "p")
  load_watchlist()
  seed_history()
  state.poll_timer = vim.uv.new_timer()
  state.poll_timer:start(POLL_DELAY_MS, config.get().poll_interval * 1000, vim.schedule_wrap(poll))
  highlights.setup()
end

return M
