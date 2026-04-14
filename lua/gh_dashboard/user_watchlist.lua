local M = {}
local highlights = require("gh_dashboard.highlights")

-- ── constants ──────────────────────────────────────────────────────────────

local WATCHLIST_PATH = vim.fn.expand("~/.config/nvim/gh-user-watchlist.json")

-- ── state ──────────────────────────────────────────────────────────────────

local state = {
  users        = {},
  manager_buf  = nil,
  manager_win  = nil,
}

-- ── namespace ──────────────────────────────────────────────────────────────

local ns = vim.api.nvim_create_namespace("GhUserWatch")

-- ── persistence ────────────────────────────────────────────────────────────

local function load_watchlist()
  if vim.fn.filereadable(WATCHLIST_PATH) == 0 then return end
  local lines = vim.fn.readfile(WATCHLIST_PATH)
  if not lines or #lines == 0 then return end
  local ok, data = pcall(vim.fn.json_decode, table.concat(lines, "\n"))
  if ok and type(data) == "table" and type(data.users) == "table" then
    state.users = data.users
  end
end

local function save_watchlist()
  local tmp = WATCHLIST_PATH .. ".tmp"
  vim.fn.writefile({ vim.fn.json_encode({ users = state.users }) }, tmp)
  vim.uv.fs_rename(tmp, WATCHLIST_PATH, function() end)
end

-- ── manager window ─────────────────────────────────────────────────────────

local function render_manager()
  if not state.manager_buf or not vim.api.nvim_buf_is_valid(state.manager_buf) then return end
  local lines, hl_specs = {}, {}
  table.insert(lines, "")
  if #state.users == 0 then
    local msg = "   No watched users. Press 'a' to add one."
    table.insert(lines, msg)
    table.insert(hl_specs, { hl = "GhUserWatchEmpty", line = #lines - 1, col_s = 0, col_e = #msg })
  else
    for _, username in ipairs(state.users) do
      local line = "   " .. username
      table.insert(lines, line)
      table.insert(hl_specs, { hl = "GhUserWatchItem", line = #lines - 1, col_s = 3, col_e = 3 + #username })
    end
  end
  table.insert(lines, "")
  vim.bo[state.manager_buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.manager_buf, 0, -1, false, lines)
  vim.bo[state.manager_buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(state.manager_buf, ns, 0, -1)
  for _, spec in ipairs(hl_specs) do
    vim.api.nvim_buf_add_highlight(state.manager_buf, ns, spec.hl, spec.line,
      spec.col_s, spec.col_e == -1 and -1 or spec.col_e)
  end
end

local function close_manager()
  if state.manager_win and vim.api.nvim_win_is_valid(state.manager_win) then
    vim.api.nvim_win_close(state.manager_win, false)
    state.manager_win = nil
  end
end

local function open_add_input()
  local input_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[input_buf].buftype    = "nofile"
  vim.bo[input_buf].bufhidden  = "wipe"
  vim.bo[input_buf].modifiable = true
  vim.bo[input_buf].filetype   = "text"

  local ui    = vim.api.nvim_list_uis()[1] or { width = 180, height = 50 }
  local width = 40
  local row   = math.floor(ui.height / 2)
  local col   = math.floor((ui.width - width) / 2)

  local input_win = vim.api.nvim_open_win(input_buf, true, {
    relative   = "editor",
    width      = width,
    height     = 1,
    row        = row,
    col        = col,
    style      = "minimal",
    border     = "rounded",
    title      = " Add GitHub username ",
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
    if text:find("/") then
      vim.notify("Enter a bare username, not owner/repo", vim.log.levels.WARN)
      return
    end
    for _, u in ipairs(state.users) do
      if u == text then
        vim.notify(text .. " is already on the watch list", vim.log.levels.INFO)
        return
      end
    end
    table.insert(state.users, text)
    save_watchlist()
    render_manager()
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
end

local function remove_at_cursor()
  if not state.manager_win or not vim.api.nvim_win_is_valid(state.manager_win) then return end
  if #state.users == 0 then return end
  local cur = vim.api.nvim_win_get_cursor(state.manager_win)[1]
  local idx = cur - 1  -- line 1 = "", line 2 = first user
  if idx < 1 or idx > #state.users then return end
  local removed = state.users[idx]
  table.remove(state.users, idx)
  save_watchlist()
  render_manager()
  vim.notify("Removed " .. removed .. " from user watch list", vim.log.levels.INFO)
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
    title      = " Watched Users ",
    title_pos  = "center",
    footer     = " a add  ·  d remove  ·  <CR> profile  ·  q close ",
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
  bmap("a",     open_add_input)
  bmap("d",     remove_at_cursor)
  bmap("x",     remove_at_cursor)
  bmap("q",     close_manager)
  bmap("<Esc>", close_manager)
  bmap("<CR>", function()
    if not state.manager_win or not vim.api.nvim_win_is_valid(state.manager_win) then return end
    local cur = vim.api.nvim_win_get_cursor(state.manager_win)[1]
    local idx = cur - 1  -- line 1 = "", line 2 = first user
    if idx >= 1 and idx <= #state.users then
      require("gh_dashboard.user_profile").open(state.users[idx])
    end
  end)

  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = state.manager_buf, once = true,
    callback = function()
      state.manager_buf = nil
      state.manager_win = nil
    end,
  })
end

-- ── public API ────────────────────────────────────────────────────────────

M.get_users = function()
  return state.users
end

M.toggle = function()
  if state.manager_win and vim.api.nvim_win_is_valid(state.manager_win) then
    close_manager()
    return
  end
  open_manager()
end

M.setup = function()
  highlights.setup()
  vim.fn.mkdir(vim.fn.fnamemodify(WATCHLIST_PATH, ":h"), "p")
  load_watchlist()
end

return M
