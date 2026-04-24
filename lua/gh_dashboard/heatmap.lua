local M = {}

-- ── authoritative heatmap constants ────────────────────────────────────────

local TIER_CHARS      = { " ", "░", "▒", "▓", "█", "󰵿" }
local TIER_THRESHOLDS = { 0, 1, 4, 10, 20, 35 }

M.HEAT_HLS     = { "GhHeat0", "GhHeat1", "GhHeat2", "GhHeat3", "GhHeat4", "GhHeat5" }
M.HEATMAP_WEEKS = 52

-- ── helpers ────────────────────────────────────────────────────────────────

local function separator(width)
  return "  " .. string.rep("─", (width or 60) - 2)
end

-- ── public API ─────────────────────────────────────────────────────────────

M.contribution_tier = function(count)
  if count == 0 then return 1 end
  for i = #TIER_THRESHOLDS, 2, -1 do
    if count >= TIER_THRESHOLDS[i] then return i end
  end
  return 2
end

M.render_heatmap = function(lines, hl_specs, contrib, items, username, win_width)
  if not contrib then return 0 end
  local weeks = contrib.weeks
  if not weeks or #weeks == 0 then return 0 end

  local day_labels    = { "Su", "  ", "Tu", "  ", "Th", "  ", "Sa" }
  local heatmap_lines = {}
  local heatmap_hl    = {}
  local day_last_dates = {}

  for day_idx = 1, 7 do
    local row_chars     = { "  ", day_labels[day_idx], " " }
    local col_positions = {}
    local last_date     = nil
    for _, week in ipairs(weeks) do
      local day = week[day_idx]
      if day then
        local tier = day.tier or 1
        local char = TIER_CHARS[tier]
        table.insert(col_positions, { col = #table.concat(row_chars), tier = tier })
        table.insert(row_chars, char)
        if day.date then last_date = day.date end
      else
        table.insert(row_chars, "  ")
      end
    end
    table.insert(heatmap_lines, table.concat(row_chars))
    table.insert(heatmap_hl, col_positions)
    day_last_dates[day_idx] = last_date
  end

  -- Pad all rows to the same display width so virt_text EOL anchors are consistent.
  local max_dw = 0
  for _, row in ipairs(heatmap_lines) do
    local dw = vim.api.nvim_strwidth(row)
    if dw > max_dw then max_dw = dw end
  end
  -- Centre the heatmap horizontally; left_pad spaces become the left grass zone.
  -- Reserve 1 col of left_pad for the │ border character.
  local hm_content_w = max_dw + 1
  local left_pad     = math.max(2, math.floor(((win_width or 120) - hm_content_w) / 2))
  local border_pad   = left_pad - 1   -- spaces before the │ border char (≥ 1)
  local border_str   = string.rep(" ", border_pad)
  -- │ is 3 UTF-8 bytes but 1 display column; hl byte offsets need +2 correction.
  local hl_col_off   = left_pad + 2

  -- Build rows with │ borders; collect right-│ byte offsets for highlighting.
  -- right_bar[i] = byte offset of the right │ in bordered row i.
  local right_bar = {}
  for i, row in ipairs(heatmap_lines) do
    local dw = vim.api.nvim_strwidth(row)
    right_bar[i] = border_pad + 3 + #row + (max_dw - dw)
    heatmap_lines[i] = border_str .. "│" .. row .. string.rep(" ", max_dw - dw) .. "│"
  end

  -- Top border
  table.insert(lines, border_str .. "╭" .. string.rep("─", max_dw) .. "╮")
  table.insert(hl_specs, { hl = "GhSeparator", line = #lines - 1, col_s = border_pad, col_e = -1 })

  local base_line = #lines
  for i, row in ipairs(heatmap_lines) do
    table.insert(lines, row)
    local ln = base_line + i - 1
    -- Side border highlights (same grey as top/bottom)
    table.insert(hl_specs, { hl = "GhSeparator", line = ln, col_s = border_pad,    col_e = border_pad + 3 })
    table.insert(hl_specs, { hl = "GhSeparator", line = ln, col_s = right_bar[i],  col_e = right_bar[i] + 3 })
    for _, cell in ipairs(heatmap_hl[i] or {}) do
      table.insert(hl_specs, {
        hl    = M.HEAT_HLS[cell.tier],
        line  = ln,
        col_s = cell.col + hl_col_off,
        col_e = cell.col + hl_col_off + 2,
      })
    end
    if items and username and day_last_dates[i] then
      table.insert(items, {
        line     = ln,
        kind     = "day",
        date     = day_last_dates[i],
        username = username,
      })
    end
  end

  local total_line    = string.format("     %d contributions this year", contrib.total or 0)
  local total_dw      = vim.api.nvim_strwidth(total_line)
  local total_padded  = border_str .. "│" .. total_line
                        .. string.rep(" ", math.max(0, max_dw - total_dw)) .. "│"
  table.insert(lines, total_padded)
  local total_ln      = #lines - 1
  local total_rbar    = border_pad + 3 + max_dw  -- total_line is ASCII so bytes == display cols
  table.insert(hl_specs, { hl = "GhStats",    line = total_ln, col_s = hl_col_off,  col_e = hl_col_off + #total_line })
  table.insert(hl_specs, { hl = "GhSeparator", line = total_ln, col_s = border_pad,  col_e = border_pad + 3 })
  table.insert(hl_specs, { hl = "GhSeparator", line = total_ln, col_s = total_rbar,  col_e = total_rbar + 3 })

  -- Bottom border + full-width separator
  table.insert(lines, border_str .. "╰" .. string.rep("─", max_dw) .. "╯")
  table.insert(hl_specs, { hl = "GhSeparator", line = #lines - 1, col_s = border_pad, col_e = -1 })
  table.insert(lines, separator(win_width))
  table.insert(hl_specs, { hl = "GhSeparator", line = #lines - 1, col_s = 0, col_e = -1 })
  return border_pad
end

return M
