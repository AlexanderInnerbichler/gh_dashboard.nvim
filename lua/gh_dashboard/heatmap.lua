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

  -- Pad all rows to the same display width + 1 so virt_text EOL anchors are consistent.
  local max_dw = 0
  for _, row in ipairs(heatmap_lines) do
    local dw = vim.api.nvim_strwidth(row)
    if dw > max_dw then max_dw = dw end
  end
  -- Centre the heatmap horizontally; left_pad spaces become the left grass zone.
  local hm_content_w = max_dw + 1
  local left_pad     = math.max(0, math.floor(((win_width or 120) - hm_content_w) / 2))
  local pad_str      = string.rep(" ", left_pad)
  for i, row in ipairs(heatmap_lines) do
    local dw = vim.api.nvim_strwidth(row)
    heatmap_lines[i] = pad_str .. row .. string.rep(" ", max_dw - dw + 1)
  end

  local base_line = #lines
  for i, row in ipairs(heatmap_lines) do
    table.insert(lines, row)
    for _, cell in ipairs(heatmap_hl[i] or {}) do
      table.insert(hl_specs, {
        hl    = M.HEAT_HLS[cell.tier],
        line  = base_line + i - 1,
        col_s = cell.col + left_pad,
        col_e = cell.col + left_pad + 2,
      })
    end
    if items and username and day_last_dates[i] then
      table.insert(items, {
        line     = base_line + i - 1,
        kind     = "day",
        date     = day_last_dates[i],
        username = username,
      })
    end
  end

  local total_line = string.format("     %d contributions this year", contrib.total or 0)
  local total_dw   = vim.api.nvim_strwidth(total_line)
  local total_padded = pad_str .. total_line .. string.rep(" ", math.max(0, max_dw + 1 - total_dw))
  table.insert(lines, total_padded)
  table.insert(hl_specs, { hl = "GhStats", line = #lines - 1, col_s = left_pad, col_e = left_pad + #total_line })
  table.insert(lines, separator(win_width))
  table.insert(hl_specs, { hl = "GhSeparator", line = #lines - 1, col_s = 0, col_e = -1 })
  return left_pad
end

return M
