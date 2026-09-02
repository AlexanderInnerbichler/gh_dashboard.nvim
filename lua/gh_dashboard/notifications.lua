local M = {}
local gh         = require("gh_dashboard.gh")
local highlights = require("gh_dashboard.highlights")
local utils      = require("gh_dashboard.utils")

local update_title  -- forward declaration

-- ── constants ──────────────────────────────────────────────────────────────

local TYPE_ICONS = {
  PullRequest = "⎇ ",
  Issue       = "!  ",
  Commit      = "↑  ",
  Release     = "⊙  ",
}

local REASON_LABELS = {
  assign           = "[assign]",
  author           = "[author]",
  comment          = "[comment]",
  mention          = "[mention]",
  review_requested = "[review]",
  team_mention     = "[team]",
  subscribed       = "[sub]",
}

-- ── state ──────────────────────────────────────────────────────────────────

local state = {
  buf      = nil,
  win      = nil,
  items    = {},
  show_all = false,
}

local ns = vim.api.nvim_create_namespace("GhNotifications")

-- ── helpers ────────────────────────────────────────────────────────────────

local function parse_subject(url, stype)
  if type(url) ~= "string" then return nil, nil, nil end
  local repo, num = url:match("repos/([^/]+/[^/]+)/[^/]+/(%d+)")
  if not repo or not num then return nil, nil, nil end
  local kind = (stype == "PullRequest") and "pr" or "issue"
  return kind, tonumber(num), repo
end

-- ── buffer write ───────────────────────────────────────────────────────────

local function write_buf(lines, hl_specs)
  utils.write_buf(state.buf, ns, lines, hl_specs)
end

-- ── render ─────────────────────────────────────────────────────────────────

local function render(notifs, err)
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then return end

  local lines    = {}
  local hl_specs = {}
  local items    = {}

  table.insert(lines, "")

  if err then
    local msg = "  ✗ " .. utils.sl(err)
    table.insert(lines, msg)
    table.insert(hl_specs, { hl = "GhError", line = #lines - 1, col_s = 0, col_e = #msg })
  elseif not notifs or #notifs == 0 then
    local label = state.show_all and "No notifications" or "No unread notifications  (press 'a' to show all)"
    local msg   = "  " .. label
    table.insert(lines, msg)
    table.insert(hl_specs, { hl = "GhEmpty", line = #lines - 1, col_s = 0, col_e = -1 })
  else
    local win_width = state.win and vim.api.nvim_win_is_valid(state.win)
      and vim.api.nvim_win_get_width(state.win) or 120
    local fixed   = 2 + 3 + 25 + 2 + 2 + 9 + 2 + 8
    local title_w = math.max(20, win_width - fixed - 4)

    for _, n in ipairs(notifs) do
      local dot    = n.unread and "● " or "○ "
      local icon   = TYPE_ICONS[n.subject and n.subject.type] or "·  "
      local repo   = utils.trunc(type(n.repository) == "table" and n.repository.full_name or "?", 25)
      local title  = utils.trunc(n.subject and n.subject.title or "?", title_w)
      local reason = REASON_LABELS[n.reason] or ""
      local age    = utils.age_string(n.updated_at)
      local stype  = n.subject and n.subject.type
      local surl   = n.subject and n.subject.url

      local fmt  = "  %s%s%-25s  %-" .. title_w .. "s  %-9s  %s"
      local line = string.format(fmt, dot, icon, repo, title, reason, age)

      local kind, number, item_repo = parse_subject(surl, stype)
      table.insert(items, {
        line   = #lines,
        id     = tostring(n.id or ""),
        kind   = kind,
        number = number,
        repo   = item_repo or (type(n.repository) == "table" and n.repository.full_name),
        unread = n.unread,
      })
      table.insert(lines, line)

      local ln      = #lines - 1
      local dot_col = 2
      local icon_col = dot_col + #dot
      local repo_col = icon_col + #icon
      local age_col  = repo_col + 25 + 2 + title_w + 2 + 9 + 2

      if n.unread then
        table.insert(hl_specs, { hl = "GhNotifUnread", line = ln, col_s = dot_col, col_e = dot_col + #dot })
      else
        table.insert(hl_specs, { hl = "GhMeta",        line = ln, col_s = dot_col, col_e = dot_col + #dot })
      end
      table.insert(hl_specs, { hl = "GhItem", line = ln, col_s = repo_col, col_e = repo_col + 25 })
      if reason ~= "" then
        local r_col = repo_col + 25 + 2 + title_w + 2
        table.insert(hl_specs, { hl = "GhPRReview", line = ln, col_s = r_col, col_e = r_col + #reason })
      end
      table.insert(hl_specs, { hl = "GhMeta", line = ln, col_s = age_col, col_e = -1 })
    end
  end

  table.insert(lines, "")
  state.items = items
  write_buf(lines, hl_specs)
  update_title()
end

-- ── mark as read ───────────────────────────────────────────────────────────

local function mark_read(id, cb)
  vim.system(
    { "gh", "api", "-X", "PATCH", "/notifications/threads/" .. id },
    { text = true },
    function(r)
      vim.schedule(function()
        if cb then cb(r.code ~= 0 and (r.stderr or "error") or nil) end
      end)
    end
  )
end

-- ── fetch ──────────────────────────────────────────────────────────────────

local function fetch()
  write_buf({ "", "  ⠋ loading notifications…" }, {})
  local endpoint = state.show_all and "/notifications?all=true" or "/notifications"
  gh.run_with_retry(
    { "gh", "api", endpoint },
    function(err, data) render(data, err) end
  )
end

-- ── cursor helpers ─────────────────────────────────────────────────────────

local function item_at_cursor()
  if not state.win or not vim.api.nvim_win_is_valid(state.win) then return nil end
  local cur = vim.api.nvim_win_get_cursor(state.win)[1] - 1
  for _, item in ipairs(state.items) do
    if item.line == cur then return item end
  end
  return nil
end

-- ── window ─────────────────────────────────────────────────────────────────

update_title = function()
  if not state.win or not vim.api.nvim_win_is_valid(state.win) then return end
  local unread = 0
  for _, item in ipairs(state.items) do
    if item.unread then unread = unread + 1 end
  end
  local suffix = state.show_all and " (all)" or ""
  local title  = unread > 0
    and (" GitHub Notifications  (" .. unread .. " unread)" .. suffix .. " ")
    or  (" GitHub Notifications" .. suffix .. " ")
  vim.api.nvim_win_set_config(state.win, { title = title, title_pos = "center" })
end

local function close_win()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, false)
    state.win = nil
  end
end

local function open_win()
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
    state.buf = utils.scratch_buf()
  end

  state.win = utils.float(state.buf, {
    w = 0.80, h = 0.70, cursorline = true,
    title  = " GitHub Notifications ",
    footer = " <CR> open   r read   m read all   R refresh   a toggle all   q close ",
  })

  local function bmap(lhs, fn)
    vim.keymap.set("n", lhs, fn, { buffer = state.buf, nowait = true, silent = true })
  end

  bmap("q",     close_win)
  bmap("<Esc>", close_win)

  local function open_at_cursor()
    local item = item_at_cursor()
    if not item then return end
    if item.unread and item.id ~= "" then
      mark_read(item.id, function() end)
      item.unread = false
      update_title()
    end
    if item.kind and item.number and item.repo then
      require("gh_dashboard.reader").open({ kind = item.kind, number = item.number, repo = item.repo })
    elseif item.repo then
      require("gh_dashboard.repo_view").open({ kind = "repo", full_name = item.repo })
    end
  end

  bmap("<CR>", open_at_cursor)
  bmap("o",    open_at_cursor)

  bmap("r", function()
    local item = item_at_cursor()
    if not item or not item.unread or item.id == "" then return end
    mark_read(item.id, function(err)
      if err then
        vim.notify("Mark read failed: " .. err, vim.log.levels.WARN)
      else
        item.unread = false
        fetch()
      end
    end)
  end)

  bmap("m", function()
    local unreads = {}
    for _, item in ipairs(state.items) do
      if item.unread and item.id ~= "" then
        table.insert(unreads, item.id)
      end
    end
    if #unreads == 0 then
      vim.notify("No unread notifications", vim.log.levels.INFO)
      return
    end
    local pending = #unreads
    for _, id in ipairs(unreads) do
      mark_read(id, function()
        pending = pending - 1
        if pending == 0 then fetch() end
      end)
    end
  end)

  bmap("R", fetch)

  bmap("a", function()
    state.show_all = not state.show_all
    fetch()
  end)

  require("gh_dashboard.help").setup_keymap(state.buf, "notifications")

  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer   = state.buf,
    once     = true,
    callback = function()
      state.buf   = nil
      state.win   = nil
      state.items = {}
    end,
  })
end

-- ── public API ─────────────────────────────────────────────────────────────

M.toggle = function()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    close_win()
    return
  end
  open_win()
  fetch()
end

M.setup = function()
  highlights.setup()
end

return M
