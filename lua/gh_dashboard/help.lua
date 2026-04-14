local M = {}

-- ── help content ───────────────────────────────────────────────────────────

local HELP = {
  dashboard = {
    { key = "<CR> / o",    desc = "Open item under cursor" },
    { key = "d",           desc = "Open PR diff" },
    { key = "w",           desc = "Watch / unwatch repo" },
    { key = "r",           desc = "Refresh dashboard" },
    { key = "<leader>gw",  desc = "Open watchlist manager" },
    { key = "<leader>gn",  desc = "Open notifications" },
    { key = "q / <Esc>",   desc = "Close dashboard" },
    { key = "?",           desc = "Toggle this help" },
  },
  reader = {
    { key = "r",           desc = "Refresh" },
    { key = "c",           desc = "Write a comment" },
    { key = "a",           desc = "Submit a review" },
    { key = "m",           desc = "Merge PR" },
    { key = "x",           desc = "Close issue" },
    { key = "d",           desc = "Open PR diff" },
    { key = "q / <Esc>",   desc = "Back to dashboard" },
    { key = "?",           desc = "Toggle this help" },
  },
  diff = {
    { key = "c (visual)",  desc = "Post inline review comment" },
    { key = "q / <Esc>",   desc = "Back" },
    { key = "?",           desc = "Toggle this help" },
  },
}

-- ── state ──────────────────────────────────────────────────────────────────

local state = { buf = nil, win = nil, context = nil }

-- ── window ─────────────────────────────────────────────────────────────────

local function close()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, false)
  end
  state.win     = nil
  state.buf     = nil
  state.context = nil
end

local function open(context)
  local entries = HELP[context] or {}

  -- key column width
  local key_w = 0
  for _, e in ipairs(entries) do
    if #e.key > key_w then key_w = #e.key end
  end

  local lines = { "" }
  for _, e in ipairs(entries) do
    local padding = string.rep(" ", key_w - #e.key)
    table.insert(lines, "  " .. e.key .. padding .. "   " .. e.desc)
  end
  table.insert(lines, "")

  local win_w  = math.max(key_w + 20, 36)
  local win_h  = #lines
  local ui     = vim.api.nvim_list_uis()[1] or { width = 180, height = 50 }
  local row    = math.floor((ui.height - win_h) / 2)
  local col    = math.floor((ui.width  - win_w) / 2)

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype    = "nofile"
  vim.bo[buf].bufhidden  = "wipe"
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  local titles = { dashboard = "Dashboard Help", reader = "Reader Help", diff = "Diff Help" }
  local win = vim.api.nvim_open_win(buf, true, {
    relative   = "editor",
    width      = win_w,
    height     = win_h,
    row        = row,
    col        = col,
    style      = "minimal",
    border     = "rounded",
    title      = " " .. (titles[context] or "Help") .. " ",
    title_pos  = "center",
    footer     = " q / ? close ",
    footer_pos = "center",
  })
  vim.wo[win].number         = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn     = "no"
  vim.wo[win].cursorline     = false

  state.buf     = buf
  state.win     = win
  state.context = context

  local function bmap(lhs, fn)
    vim.keymap.set("n", lhs, fn, { buffer = buf, nowait = true, silent = true })
  end
  bmap("q",     close)
  bmap("<Esc>", close)
  bmap("?",     close)
end

-- ── public API ─────────────────────────────────────────────────────────────

function M.open(context)
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    close()
    return
  end
  open(context)
end

function M.close()
  close()
end

function M.setup_keymap(buf, context)
  vim.keymap.set("n", "?", function()
    M.open(context)
  end, { buffer = buf, nowait = true, silent = true })
end

return M
