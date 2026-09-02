local M = {}

-- ── parsing ────────────────────────────────────────────────────────────────

local function split_lines(s)
  return vim.split(s or "", "\n", { plain = true })
end

--- Parse a per-file unified patch (as returned by the pulls/files API) into hunks.
--- Each hunk: { old_start, old_count, new_start, new_count, header, lines }
--- where lines is a list of { kind = "+"|"-"|" ", text }.
function M.parse(patch)
  local hunks, cur = {}, nil
  for _, line in ipairs(split_lines(patch)) do
    local os_, oc, ns_, nc = line:match("^@@ %-(%d+),?(%d*) %+(%d+),?(%d*) @@")
    if os_ then
      cur = {
        old_start = tonumber(os_),
        old_count = tonumber(oc ~= "" and oc or 1),
        new_start = tonumber(ns_),
        new_count = tonumber(nc ~= "" and nc or 1),
        header    = line,
        lines     = {},
      }
      table.insert(hunks, cur)
    elseif cur then
      local kind = line:sub(1, 1)
      if kind == "+" or kind == "-" or kind == " " then
        table.insert(cur.lines, { kind = kind, text = line:sub(2) })
      elseif line == "" then
        -- git emits a bare empty line for an empty context line
        table.insert(cur.lines, { kind = " ", text = "" })
      end
      -- "\ No newline at end of file" is dropped
    end
  end
  return hunks
end

-- ── reconstruction ─────────────────────────────────────────────────────────

--- Rebuild the pre-change file by reverse-applying hunks to the head content.
--- Exact by construction, so nvim's diff of (base, head) matches the PR's patch.
function M.reconstruct_base(head_lines, hunks)
  local base, i = {}, 1
  for _, h in ipairs(hunks) do
    local stop = h.new_count == 0 and h.new_start + 1 or h.new_start
    while i < stop do
      table.insert(base, head_lines[i] or "")
      i = i + 1
    end
    for _, l in ipairs(h.lines) do
      if l.kind == "-" then
        table.insert(base, l.text)
      elseif l.kind == " " then
        table.insert(base, l.text)
        i = i + 1
      else
        i = i + 1
      end
    end
  end
  while i <= #head_lines do
    table.insert(base, head_lines[i])
    i = i + 1
  end
  return base
end

--- Collect one side of a patch as plain text. Used for added / removed files,
--- where the patch already contains the whole file and no blob fetch is needed.
function M.side_lines(hunks, side)
  local want = side == "old" and "-" or "+"
  local out  = {}
  for _, h in ipairs(hunks) do
    for _, l in ipairs(h.lines) do
      if l.kind == want or l.kind == " " then
        table.insert(out, l.text)
      end
    end
  end
  return out
end

-- ── queries ────────────────────────────────────────────────────────────────

--- Line ranges a review comment may target, per side.
--- Returns { RIGHT = { {from, to}, ... }, LEFT = { ... } }
function M.comment_ranges(hunks)
  local ranges = { RIGHT = {}, LEFT = {} }
  for _, h in ipairs(hunks) do
    if h.new_count > 0 then
      table.insert(ranges.RIGHT, { h.new_start, h.new_start + h.new_count - 1 })
    end
    if h.old_count > 0 then
      table.insert(ranges.LEFT, { h.old_start, h.old_start + h.old_count - 1 })
    end
  end
  return ranges
end

--- New-side line of the first actual change, for parking the cursor on open.
function M.first_change_line(hunks)
  for _, h in ipairs(hunks) do
    local n, del_at = h.new_start - 1, nil
    for _, l in ipairs(h.lines) do
      if l.kind == "+" then
        return n + 1
      elseif l.kind == "-" then
        -- a replacement emits its "-" lines first; hold off in case a "+" follows
        del_at = del_at or math.max(n, 1)
      else
        if del_at then return del_at end
        n = n + 1
      end
    end
    if del_at then return del_at end
  end
  return hunks[1] and hunks[1].new_start or 1
end

function M.in_ranges(ranges, line)
  for _, r in ipairs(ranges or {}) do
    if line >= r[1] and line <= r[2] then return true end
  end
  return false
end

--- True when a hunk only adds or removes whitespace.
function M.is_whitespace_only(hunk)
  local removed, added = {}, {}
  for _, l in ipairs(hunk.lines) do
    if     l.kind == "-" then table.insert(removed, (l.text:gsub("%s+", "")))
    elseif l.kind == "+" then table.insert(added,   (l.text:gsub("%s+", ""))) end
  end
  if #removed == 0 and #added == 0 then return true end
  return table.concat(removed) == table.concat(added)
end

-- ── unified rendering ──────────────────────────────────────────────────────

--- Render hunks as a unified patch buffer.
--- Returns lines, hl_specs, line_map (buf line -> {line, side}), hunk_lines.
function M.render_unified(hunks, skip_whitespace)
  local lines, hl_specs, line_map, hunk_lines = {}, {}, {}, {}

  for _, h in ipairs(hunks) do
    if not (skip_whitespace and M.is_whitespace_only(h)) then
      table.insert(lines, h.header)
      table.insert(hunk_lines, #lines)
      table.insert(hl_specs, { hl = "GhDiffHunk", line = #lines - 1, col_s = 0, col_e = -1 })

      local old_n, new_n = h.old_start - 1, h.new_start - 1
      for _, l in ipairs(h.lines) do
        table.insert(lines, l.kind .. l.text)
        local ln = #lines - 1
        if l.kind == "+" then
          new_n = new_n + 1
          line_map[ln] = { line = new_n, side = "RIGHT" }
          table.insert(hl_specs, { hl = "GhDiffAdd", line = ln, col_s = 0, col_e = -1 })
        elseif l.kind == "-" then
          old_n = old_n + 1
          line_map[ln] = { line = old_n, side = "LEFT" }
          table.insert(hl_specs, { hl = "GhDiffDel", line = ln, col_s = 0, col_e = -1 })
        else
          old_n, new_n = old_n + 1, new_n + 1
          line_map[ln] = { line = new_n, side = "RIGHT" }
        end
      end
      table.insert(lines, "")
    end
  end

  if #lines == 0 then lines = { "  (no changes to show)" } end
  return lines, hl_specs, line_map, hunk_lines
end

return M
