local M     = {}
local utils = require("gh_dashboard.utils")

local TS_MAX_LINES = 20000

-- vim.filetype.match resolves these only from a real buffer, which our scratch
-- buffers can't stand in for, so map them directly.
local FT_BY_EXT = {
  sh = "sh", bash = "bash", zsh = "zsh", ksh = "ksh", txt = "text",
  mk = "make", cmake = "cmake", tf = "terraform", env = "sh",
}

local FT_BY_NAME = {
  Makefile = "make", makefile = "make", GNUmakefile = "make",
  Dockerfile = "dockerfile", Justfile = "just", justfile = "just",
}

local function detect_ft(path, lines)
  local ok, ft = pcall(vim.filetype.match, { filename = path, contents = lines })
  if ok and ft then return ft end
  local base = path:match("[^/]+$") or path
  return FT_BY_NAME[base] or FT_BY_EXT[base:match("%.([^.]+)$") or ""]
end

-- ── buffers ────────────────────────────────────────────────────────────────

function M.new_buf(name)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.b[buf].render_markdown = { enabled = false }
  vim.bo[buf].buftype    = "nofile"
  vim.bo[buf].bufhidden  = "hide"
  vim.bo[buf].swapfile   = false
  vim.bo[buf].modifiable = false
  pcall(vim.api.nvim_buf_set_name, buf, name)
  return buf
end

--- Replace a buffer's contents and re-attach syntax highlighting for `path`.
--- Passing path = nil leaves the buffer as plain text.
function M.set_content(buf, lines, path)
  if not vim.api.nvim_buf_is_valid(buf) then return end
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  pcall(vim.treesitter.stop, buf)
  local ft = path and detect_ft(path, lines) or nil
  vim.bo[buf].filetype = ft or ""
  if ft and #lines <= TS_MAX_LINES then
    local lang = vim.treesitter.language.get_lang(ft)
    if lang then pcall(vim.treesitter.start, buf, lang) end
  end
end

-- ── window modes ───────────────────────────────────────────────────────────

local DIFF_HL = {
  DiffAdd    = { fg = "NONE", bg = "#1e3226" },
  DiffDelete = { fg = "#4b2b30", bg = "#33222a" },
  DiffChange = { fg = "NONE", bg = "#20303f" },
  DiffText   = { fg = "NONE", bg = "#2f5578" },
}

function M.setup_diff_hl()
  for name, spec in pairs(DIFF_HL) do
    vim.api.nvim_set_hl(0, "GhDiff_" .. name, spec)
  end
end

local function winhl()
  local parts = {}
  for name, _ in pairs(DIFF_HL) do
    table.insert(parts, name .. ":GhDiff_" .. name)
  end
  return table.concat(parts, ",")
end

function M.enable_diff(wins)
  for _, win in ipairs(wins) do
    if vim.api.nvim_win_is_valid(win) then
      vim.wo[win].diff       = true
      vim.wo[win].scrollbind = true
      vim.wo[win].cursorbind = true
      vim.wo[win].foldmethod = "diff"
      vim.wo[win].foldenable = true
      vim.wo[win].foldlevel  = 0
      vim.wo[win].foldcolumn = "0"
      vim.wo[win].wrap       = false
      vim.wo[win].number     = true
      vim.wo[win].winhighlight = winhl()
    end
  end
  if #wins > 0 and vim.api.nvim_win_is_valid(wins[1]) then
    vim.api.nvim_win_call(wins[1], function() vim.cmd("diffupdate") end)
  end
end

function M.disable_diff(wins)
  for _, win in ipairs(wins) do
    if vim.api.nvim_win_is_valid(win) then
      vim.wo[win].diff       = false
      vim.wo[win].scrollbind = false
      vim.wo[win].cursorbind = false
      vim.wo[win].foldenable = false
      vim.wo[win].foldmethod = "manual"
      vim.wo[win].number     = false
      vim.wo[win].winhighlight = ""
    end
  end
end

-- ── comment overlays ───────────────────────────────────────────────────────

local function wrap(text, width)
  local out = {}
  for _, raw in ipairs(vim.split(text or "", "\n", { plain = true })) do
    if raw == "" then
      table.insert(out, "")
    else
      while #raw > width do
        local cut = raw:sub(1, width):match(".*()%s") or width
        table.insert(out, raw:sub(1, cut - 1))
        raw = raw:sub(cut + 1)
      end
      table.insert(out, raw)
    end
  end
  return out
end

--- Draw review comments as virtual lines under the line they target.
--- Returns the sorted list of 1-based lines that carry a comment.
function M.overlay_comments(buf, ns, entries, width)
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  local anchored, total = {}, vim.api.nvim_buf_line_count(buf)

  for _, c in ipairs(entries) do
    local line = tonumber(c.line)
    if line and line >= 1 and line <= total then
      anchored[line] = anchored[line] or {}
      table.insert(anchored[line], c)
    end
  end

  local marked = {}
  for line, list in pairs(anchored) do
    local virt = {}
    for _, c in ipairs(list) do
      local pending  = c.pending == true
      local head_hl  = pending and "GhDiffCommentPending" or "GhDiffCommentAuthor"
      local head     = "  ▏ @" .. (c.login or "you") .. (pending and "  [pending]" or "")
      table.insert(virt, { { head, head_hl } })
      for _, l in ipairs(wrap(c.body, math.max(20, width - 8))) do
        table.insert(virt, { { "  ▏ " .. l, "GhDiffCommentBody" } })
      end
    end
    table.insert(virt, { { "", "GhDiffCommentBody" } })
    vim.api.nvim_buf_set_extmark(buf, ns, line - 1, 0, { virt_lines = virt })
    table.insert(marked, line)
  end

  table.sort(marked)
  return marked
end

-- ── placeholder content ────────────────────────────────────────────────────

function M.placeholder(text)
  return { "", "  " .. utils.sl(text) }
end

return M
