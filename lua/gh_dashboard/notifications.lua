local M = {}
local gh         = require("gh_dashboard.gh")
local highlights = require("gh_dashboard.highlights")

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
  items    = {},   -- { line, id, kind, number, repo, unread }
  show_all = false,
}

local ns = vim.api.nvim_create_namespace("GhNotifications")

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
  local t  = os.time({ year = y, month = mo, day = d, hour = h, min = mi, sec = s })
  local u  = os.date("!*t", t)  u.isdst = nil
  local diff = os.time() - (t + os.difftime(t, os.time(u)))
  if     diff < 60       then return "just now"
  elseif diff < 3600     then return math.floor(diff / 60)    .. "m ago"
  elseif diff < 86400    then return math.floor(diff / 3600)  .. "h ago"
  elseif diff < 604800   then return math.floor(diff / 86400) .. "d ago"
  else                        return math.floor(diff / 604800) .. "w ago"
  end
end

local function parse_subject(url, stype)
  if type(url) ~= "string" then return nil, nil, nil end
  local repo, num = url:match("repos/([^/]+/[^/]+)/[^/]+/(%d+)")
  if not repo or not num then return nil, nil, nil end
  local kind = (stype == "PullRequest") and "pr" or "issue"
  return kind, tonumber(num), repo
end

-- ── buffer write ───────────────────────────────────────────────────────────

local function write_buf(lines, hl_specs)
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then return end
  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.bo[state.buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(state.buf, ns, 0, -1)
  for _, spec in ipairs(hl_specs) do
    vim.api.nvim_buf_add_highlight(state.buf, ns, spec.hl, spec.line,
      spec.col_s, spec.col_e == -1 and -1 or spec.col_e)
  end
end

-- ── render ─────────────────────────────────────────────────────────────────

local function render(notifs, err)
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then return end

  local lines    = {}
  local hl_specs = {}
  local items    = {}

  table.insert(lines, "")

  if err then
    local msg = "  ✗ " .. sl(err)
    table.insert(lines, msg)
    table.insert(hl_specs, { hl = "GhError", line = #lines - 1, col_s = 0, col_e = #msg })
  elseif not notifs or #notifs == 0 then
    local label = state.show_all and "No notifications" or "No unread notifications  (press 'a' to show all)"
    local msg   = "  " .. label
    table.insert(lines, msg)
    table.insert(hl_specs, { hl = "GhEmpty", line = #lines - 1, col_s = 0, col_e = -1 })
  else
    -- layout: dot(2) + icon(3) + repo(25) + 2 + title(fill) + 2 + reason(9) + 2 + age(8)
    local win_width = state.win and vim.api.nvim_win_is_valid(state.win)
      and vim.api.nvim_win_get_width(state.win) or 120
    local fixed     = 2 + 3 + 25 + 2 + 2 + 9 + 2 + 8
    local title_w   = math.max(20, win_width - fixed - 4)

    for _, n in ipairs(notifs) do
      local dot    = n.unread and "● " or "○ "
      local icon   = TYPE_ICONS[n.subject and n.subject.type] or "·  "
      local repo   = trunc(type(n.repository) == "table" and n.repository.full_name or "?", 25)
      local title  = trunc(n.subject and n.subject.title or "?", title_w)
      local reason = REASON_LABELS[n.reason] or ""
      local age    = age_string(n.updated_at)
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
  local suffix = state.show_all and " · all" or ""
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
    state.buf = vim.api.nvim_create_buf(false, true)
    vim.b[state.buf].render_markdown = { enabled = false }
    vim.bo[state.buf].bufhidden  = "wipe"
    vim.bo[state.buf].buftype    = "nofile"
    vim.bo[state.buf].modifiable = false
    vim.bo[state.buf].filetype   = "text"
  end

  local ui     = vim.api.nvim_list_uis()[1] or { width = 180, height = 50 }
  local width  = math.floor(ui.width  * 0.80)
  local height = math.floor(ui.height * 0.70)
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
    title      = " GitHub Notifications ",
    title_pos  = "center",
    footer     = " <CR> open  ·  r read  ·  R refresh  ·  a toggle all  ·  q close ",
    footer_pos = "center",
  })

  vim.wo[state.win].number         = false
  vim.wo[state.win].relativenumber = false
  vim.wo[state.win].signcolumn     = "no"
  vim.wo[state.win].wrap           = false
  vim.wo[state.win].cursorline     = true
  vim.wo[state.win].foldenable     = false

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
      vim.system({ "xdg-open", "https://github.com/" .. item.repo })
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
