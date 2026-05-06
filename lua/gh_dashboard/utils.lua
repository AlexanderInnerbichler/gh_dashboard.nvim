local M = {}

function M.sl(s) return (s or ""):gsub("[\n\r]", " ") end

function M.trunc(s, n)
  s = M.sl(s)
  return #s > n and s:sub(1, n - 3) .. "…" or s
end

function M.age_seconds(iso8601)
  if not iso8601 then return 0 end
  local y, mo, d, h, mi, s = iso8601:match("(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)")
  if not y then return 0 end
  local t = os.time({ year = y, month = mo, day = d, hour = h, min = mi, sec = s })
  local u = os.date("!*t", t)  u.isdst = nil
  return os.time() - (t + os.difftime(t, os.time(u)))
end

function M.age_string(iso8601)
  if not iso8601 then return "" end
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

function M.open_url(url)
  if vim.ui.open then
    vim.ui.open(url)
  else
    vim.system({ "xdg-open", url })
  end
end

return M
