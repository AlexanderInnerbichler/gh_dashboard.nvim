local M = {}

--- gh's JSON decodes absent fields to vim.NIL, so every string helper has to
--- tolerate it rather than each caller wrapping its own guard.
function M.safe_str(v)
  if v == nil or v == vim.NIL then return "" end
  return tostring(v)
end

function M.safe_list(v)
  if type(v) ~= "table" then return {} end
  return v
end

function M.sl(s) return (M.safe_str(s)):gsub("[\n\r]", " ") end

function M.trunc(s, n)
  s = M.sl(s)
  return #s > n and s:sub(1, n - 3) .. "…" or s
end

--- Truncate to n display cells. M.trunc counts bytes, which misaligns any
--- column holding multibyte characters (… — ★ and the like).
function M.dtrunc(s, n)
  s = M.sl(s)
  if vim.fn.strdisplaywidth(s) <= n then return s end
  local out = ""
  for _, ch in ipairs(vim.fn.split(s, "\\zs")) do
    if vim.fn.strdisplaywidth(out .. ch) > n - 1 then break end
    out = out .. ch
  end
  return out .. "…"
end

--- Right-pad to n display cells.
function M.dpad(s, n)
  return s .. string.rep(" ", math.max(0, n - vim.fn.strdisplaywidth(s)))
end

function M.age_seconds(iso8601)
  if not iso8601 or iso8601 == vim.NIL then return 0 end
  local y, mo, d, h, mi, s = iso8601:match("(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)")
  if not y then return 0 end
  local t = os.time({ year = y, month = mo, day = d, hour = h, min = mi, sec = s })
  local u = os.date("!*t", t)  u.isdst = nil
  return os.time() - (t + os.difftime(t, os.time(u)))
end

function M.age_string(iso8601)
  if not iso8601 or iso8601 == vim.NIL then return "" end
  local diff = M.age_seconds(iso8601)
  if     diff < 60        then return "just now"
  elseif diff < 3600      then return math.floor(diff / 60)       .. "m ago"
  elseif diff < 86400     then return math.floor(diff / 3600)     .. "h ago"
  elseif diff < 604800    then return math.floor(diff / 86400)    .. "d ago"
  elseif diff < 2592000   then return math.floor(diff / 604800)   .. "w ago"
  elseif diff < 31536000  then return math.floor(diff / 2592000)  .. "mo ago"
  else                         return math.floor(diff / 31536000) .. "y ago"
  end
end

function M.write_buf(buf, ns, lines, hl_specs)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for _, spec in ipairs(hl_specs) do
    vim.api.nvim_buf_add_highlight(buf, ns, spec.hl, spec.line, spec.col_s,
      spec.col_e == -1 and -1 or spec.col_e)
  end
end

--- Scratch buffer with the options every view in this plugin wants.
function M.scratch_buf(opts)
  opts = opts or {}
  local buf = vim.api.nvim_create_buf(false, true)
  vim.b[buf].render_markdown = { enabled = false }
  vim.bo[buf].buftype    = "nofile"
  vim.bo[buf].bufhidden  = opts.bufhidden or "wipe"
  vim.bo[buf].swapfile   = false
  vim.bo[buf].filetype   = opts.filetype or "text"
  vim.bo[buf].modifiable = opts.modifiable == true
  return buf
end

--- Centred float with the plugin's standard chrome.
--- Size with fractions (w/h) or absolute cells (width/height); row/col default
--- to centred. Returns the window id.
function M.float(buf, opts)
  local ui     = vim.api.nvim_list_uis()[1] or { width = 180, height = 50 }
  local width  = opts.width  or math.floor(ui.width  * (opts.w or 0.9))
  local height = opts.height or math.floor(ui.height * (opts.h or 0.9))

  local win = vim.api.nvim_open_win(buf, opts.enter ~= false, {
    relative   = "editor",
    width      = width,
    height     = height,
    row        = opts.row or math.floor((ui.height - height) / 2),
    col        = opts.col or math.floor((ui.width  - width)  / 2),
    style      = "minimal",
    border     = "rounded",
    title      = opts.title,
    title_pos  = opts.title and (opts.title_pos or "center") or nil,
    footer     = opts.footer,
    footer_pos = opts.footer and "center" or nil,
    focusable  = opts.focusable,
    zindex     = opts.zindex,
  })

  vim.wo[win].number         = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn     = "no"
  vim.wo[win].foldenable     = false
  vim.wo[win].wrap           = opts.wrap == true
  vim.wo[win].cursorline     = opts.cursorline == true
  if opts.wrap then vim.wo[win].linebreak = true end
  return win
end

--- Text prompt in a float. `lines` > 1 gives a multi-line body.
--- on_submit gets the trimmed text; cancelling never calls it.
function M.prompt(opts, on_submit)
  local rows = opts.lines or 1
  local buf  = M.scratch_buf({ modifiable = true })
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "" })

  local win = M.float(buf, {
    width  = opts.width,
    w      = opts.w or 0.6,
    height = rows,
    wrap   = true,
    title  = " " .. opts.title .. " ",
    footer = opts.footer or (rows == 1
      and " <C-s> submit   <Esc> cancel "
      or  " <C-s> submit   <Esc> then <Esc> cancel "),
  })
  vim.api.nvim_win_set_cursor(win, { 1, 0 })
  vim.cmd("startinsert")

  local function close()
    if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
    vim.cmd("stopinsert")
  end
  local function submit()
    local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
    close()
    on_submit(vim.trim(text))
  end
  local function map(mode, lhs, fn)
    vim.keymap.set(mode, lhs, fn, { buffer = buf, nowait = true, silent = true })
  end
  map("n", "<C-s>", submit)
  map("i", "<C-s>", submit)
  map("n", "<Esc>", close)
  map("n", "q",     close)
  -- A one-line prompt has nothing to edit, so <Esc> may as well cancel outright
  -- instead of dropping to normal mode first. A body keeps <Esc> for normal
  -- mode, so vim motions still work while writing it.
  if rows == 1 then map("i", "<Esc>", close) end
end

function M.open_url(url)
  if vim.ui.open then
    vim.ui.open(url)
  else
    vim.system({ "xdg-open", url })
  end
end

return M
