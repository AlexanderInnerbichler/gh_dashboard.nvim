local M = {}

local duck_ns = vim.api.nvim_create_namespace("GhDashboardDuck")

-- ── color palette (muted ~25% from original) ───────────────────────────────

local COLORS = {
  "#b09060",  -- 1  outline
  "#ccb080",  -- 2  body
  "#cc6050",  -- 3  beak
  "#1e2127",  -- 4  eye
  "#b8bcc4",  -- 5  wing stripe
  "#b89472",  -- 6  feet / legs
  "#8a6438",  -- 7  deep shadow
  "#d8c08a",  -- 8  belly highlight
  "#3a6b3a",  -- 9  grass dark (stem)
  "#6aaa6a",  -- 10 grass light (tip)
}
local GD = 9
local GL = 10

-- ── pixel art ──────────────────────────────────────────────────────────────
-- 12 pixel rows × 14 cols per wing frame.
-- Terminal rows 1-6 = duck body.  Terminal row 7 (contributions line) = legs.

local HEAD = {
  {0,0,0,0,0,0,0,0,0,0,0,0,0,0},  
  {0,0,0,0,0,0,1,1,1,1,0,0,0,0},  --  1  head top  (wider + shifted left)
  {0,0,0,0,0,1,2,2,2,1,0,0,0,0},  --  2  head       (plumper)
  {0,0,0,0,0,1,2,2,2,4,1,0,0,0},  --  3  eye
  {0,0,0,0,0,1,2,2,2,2,3,3,0,0},  --  4  beak       (shorter, shifted left)
  {0,0,0,0,1,2,2,2,2,3,0,0,0,0},  --  5  beak lower (one-row stub)
}

local BODY = {
  [0] = {  -- wing down / resting
    {0,0,1,1,1,2,2,2,1,0,0,0,0,0},  --  7  upper back      ← tr=4 top pixel
    {7,1,2,8,8,2,2,2,1,0,0,0,0,0},  --  8  body            ← tr=4 bot pixel
    {7,2,2,8,8,2,2,2,1,0,0,0,0,0},  --  9  body wide       ← tr=5 top pixel
    {7,2,2,5,5,5,2,2,1,0,0,0,0,0},  -- 10  wing stripe     ← tr=5 bot pixel
    {7,2,2,2,2,2,2,1,0,0,0,0,0,0},  -- 11  body lower      ← tr=6 top pixel
    {0,1,2,2,2,2,1,0,0,0,0,0,0,0},  -- 12  body bottom     ← tr=6 bot pixel
  },
  [1] = {  -- wing mid (rising)
    {0,0,1,1,1,2,2,2,1,0,0,0,0,0},
    {7,1,2,8,8,2,2,2,1,0,0,0,0,0},
    {7,2,2,5,5,2,2,2,1,0,0,0,0,0},
    {7,2,2,2,5,5,2,2,1,0,0,0,0,0},
    {7,2,2,2,2,2,2,1,0,0,0,0,0,0},
    {0,1,2,2,2,2,1,0,0,0,0,0,0,0},
  },
  [2] = {  -- wing up (raised)
    {0,0,1,1,1,2,2,2,1,0,0,0,0,0},
    {7,1,2,8,8,2,2,2,1,0,0,0,0,0},
    {7,2,2,5,5,2,2,2,1,0,0,0,0,0},
    {7,2,2,2,2,2,2,2,1,0,0,0,0,0},
    {7,2,2,2,2,2,2,1,0,0,0,0,0,0},
    {0,1,2,2,2,2,1,0,0,0,0,0,0,0},
  },
}

local function get_art(wing_frame)
  local art = {}
  for _, row in ipairs(HEAD) do table.insert(art, row) end
  for _, row in ipairs(BODY[wing_frame]) do table.insert(art, row) end
  return art
end

local LEGS = {
  [1] = {0,0,6,0,0,6,0,0,0,0,0,0,0,0},
  [2] = {0,0,0,6,6,0,0,0,0,0,0,0,0,0},
}

local WING_SEQ  = { 0, 1, 2, 1 }
local DUCK_COLS = 14

-- ── grass pattern ──────────────────────────────────────────────────────────

local GRASS_PAT   = { 2,4,1,3,2,1,4,3,1,2,3,4,1,2,5,3,1,4,2,3 }
local GRASS_PAT_N = #GRASS_PAT

local TIER_TO_HEIGHT = { 1, 2, 3, 4, 5, 6 }  -- contribution tier 1-6 → grass height 1-6

local function build_grass_pattern(contributions)
  if not contributions or not contributions.weeks then return GRASS_PAT end
  local days = {}
  for i = #contributions.weeks, 1, -1 do
    local week = contributions.weeks[i]
    if week then
      for j = 7, 1, -1 do
        if week[j] then table.insert(days, week[j]) end
      end
    end
  end
  local pat = {}
  for i = 1, GRASS_PAT_N do
    local day    = days[i]
    local tier   = (day and day.tier) or 1
    local base   = TIER_TO_HEIGHT[tier] or 1
    local jitter = GRASS_PAT[i] % 3 - 1
    pat[i] = math.max(1, math.min(6, base + jitter))
  end
  return pat
end

local function bot_pos(tr) return 2 * (7 - tr) end
local function top_pos(tr) return 2 * (7 - tr) + 1 end

local function grass_color(pixel_pos, gh)
  return (pixel_pos == gh - 1) and GL or GD
end

-- ── highlight cache ────────────────────────────────────────────────────────
-- bg is only set when bg_idx ~= 0 (two explicit duck colors meeting at a
-- half-block boundary).  When bg_idx == 0 the attribute is omitted so
-- the cell inherits the floating window's NormalFloat background naturally —
-- this prevents the black-background bug that occurs when setting bg="NONE".

local hl_cache = {}
local hl_count = 0

local function hl_for(fg_idx, bg_idx)
  local key = fg_idx * 16 + bg_idx
  if hl_cache[key] then return hl_cache[key] end
  hl_count = hl_count + 1
  local name = "GhDuckPx" .. hl_count
  vim.api.nvim_set_hl(0, name, {
    fg = fg_idx ~= 0 and COLORS[fg_idx] or nil,
    bg = bg_idx ~= 0 and COLORS[bg_idx] or nil,
  })
  hl_cache[key] = name
  return name
end

-- ── cell builder ───────────────────────────────────────────────────────────

local TRANSPARENT = { " ", "NormalFloat" }

local function cell(t, b, gt, gb)
  local ft = t ~= 0 and t or gt
  local fb = b ~= 0 and b or gb
  if ft == 0 and fb == 0 then
    return TRANSPARENT
  elseif ft ~= 0 and fb == 0 then
    return { "▀", hl_for(ft, 0) }
  elseif ft == 0 and fb ~= 0 then
    return { "▄", hl_for(fb, 0) }
  elseif ft == fb then
    return { "█", hl_for(ft, 0) }
  else
    return { "▀", hl_for(ft, fb) }
  end
end

-- ── strip builders ─────────────────────────────────────────────────────────

local function build_body_vt(art, tr, dx, max_x, grass_h)
  local row_top = art[2 * tr - 1]
  local row_bot = art[2 * tr]
  local bp      = bot_pos(tr)
  local tp      = top_pos(tr)
  local vt      = {}
  for sc = 0, max_x - 1 do
    local dc = (sc - dx) % max_x
    local t, b = 0, 0
    if dc < DUCK_COLS then
      t = row_top[dc + 1] or 0
      b = row_bot[dc + 1] or 0
    end
    local gh = (tr >= 5) and grass_h[sc] or 0
    local gt = (t == 0 and gh >= tp + 1) and grass_color(tp, gh) or 0
    local gb = (b == 0 and gh >= bp + 1) and grass_color(bp, gh) or 0
    table.insert(vt, cell(t, b, gt, gb))
  end
  return vt
end

local function build_legs_vt(legs_row, dx, max_x, grass_h)
  local vt = {}
  for sc = 0, max_x - 1 do
    local dc = (sc - dx) % max_x
    local t  = (dc < DUCK_COLS) and (legs_row[dc + 1] or 0) or 0
    local gh = grass_h[sc]
    local gb = (gh >= 1) and grass_color(0, gh) or 0
    table.insert(vt, cell(t, 0, 0, gb))
  end
  return vt
end

-- ── module state ───────────────────────────────────────────────────────────

local state = {
  buf              = nil,
  base_line        = nil,
  timer            = nil,
  trigger_timer    = nil,
  x                = 0,
  tick             = 0,
  foot_frame       = 1,
  wing_step        = 1,
  max_x            = 40,
  grass_h          = {},
  passes_done      = 0,
  passes_total     = 2,
  run_active       = false,
  next_trigger_at  = nil,  -- vim.uv.now() ms value
}

-- ── run helpers ────────────────────────────────────────────────────────────

local draw  -- forward declaration

local function draw_grass_only()
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then return end
  local mxw     = state.max_x
  local grass_h = state.grass_h
  for tr = 5, 6 do
    local bp = bot_pos(tr)
    local tp = top_pos(tr)
    local vt = {}
    for sc = 0, mxw - 1 do
      local gh = grass_h[sc]
      local gt = (gh >= tp + 1) and grass_color(tp, gh) or 0
      local gb = (gh >= bp + 1) and grass_color(bp, gh) or 0
      table.insert(vt, cell(0, 0, gt, gb))
    end
    vim.api.nvim_buf_set_extmark(state.buf, duck_ns, state.base_line + tr, 0, {
      virt_text = vt, virt_text_pos = "eol",
    })
  end
  local line7 = state.base_line + 7
  if vim.api.nvim_buf_line_count(state.buf) > line7 then
    local vt = {}
    for sc = 0, mxw - 1 do
      local gh = grass_h[sc]
      local gb = (gh >= 1) and grass_color(0, gh) or 0
      table.insert(vt, cell(0, 0, 0, gb))
    end
    vim.api.nvim_buf_set_extmark(state.buf, duck_ns, line7, 0, {
      virt_text = vt, virt_text_pos = "eol",
    })
  end
end

local function stop_run()
  if state.timer then
    state.timer:stop()
    state.timer:close()
    state.timer = nil
  end
  state.run_active = false
  if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
    vim.api.nvim_buf_clear_namespace(state.buf, duck_ns, 0, -1)
    draw_grass_only()
  end
end

local function start_run(interval_ms)
  stop_run()
  state.passes_total = math.random(2, 3)
  state.passes_done  = 0
  state.x            = 0
  state.tick         = 0
  state.foot_frame   = 1
  state.wing_step    = 1
  state.run_active   = true
  local t = vim.uv.new_timer()
  state.timer = t
  t:start(0, interval_ms or 400, vim.schedule_wrap(draw))
end

-- ── draw ───────────────────────────────────────────────────────────────────

draw = function()
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
    M.stop()
    return
  end

  vim.api.nvim_buf_clear_namespace(state.buf, duck_ns, 0, -1)

  local dx         = state.x
  local mxw        = state.max_x
  local wing_frame = WING_SEQ[state.wing_step]
  local art        = get_art(wing_frame)
  local grass_h    = state.grass_h

  -- Terminal rows 1-6: full duck body in the strip right of the heatmap.
  for tr = 1, 6 do
    local vt = build_body_vt(art, tr, dx, mxw, grass_h)
    vim.api.nvim_buf_set_extmark(state.buf, duck_ns, state.base_line + tr, 0, {
      virt_text     = vt,
      virt_text_pos = "eol",
    })
  end

  -- Terminal row 7 (contributions line): legs + foreground grass.
  local line7 = state.base_line + 7
  if vim.api.nvim_buf_line_count(state.buf) > line7 then
    local vt7 = build_legs_vt(LEGS[state.foot_frame], dx, mxw, grass_h)
    vim.api.nvim_buf_set_extmark(state.buf, duck_ns, line7, 0, {
      virt_text     = vt7,
      virt_text_pos = "eol",
    })
  end

  -- Advance counters.
  state.tick = state.tick + 1
  if state.tick % 2  == 0 then
    local nx = (state.x + 1) % mxw
    if nx < state.x then
      state.passes_done = state.passes_done + 1
      if state.passes_done >= state.passes_total then
        stop_run()
        return
      end
    end
    state.x = nx
  end
  if state.tick % 8  == 0 then state.foot_frame = state.foot_frame == 1 and 2 or 1 end
  if state.tick % 24 == 0 then state.wing_step  = state.wing_step  % #WING_SEQ + 1 end
end

-- ── public API ─────────────────────────────────────────────────────────────

M.stop = function()
  stop_run()
  if state.trigger_timer then
    state.trigger_timer:stop()
    state.trigger_timer:close()
    state.trigger_timer = nil
  end
end

M.start = function(buf, base_line, interval_ms, win_width, hm_display_w, contributions)
  local hm_w      = hm_display_w or 58
  local new_max_x = math.max(DUCK_COLS + 1, (win_width or 160) - hm_w - 2)
  local pat       = build_grass_pattern(contributions)

  if state.trigger_timer then
    state.buf       = buf
    state.base_line = base_line
    state.max_x     = new_max_x
    state.grass_h   = {}
    for sc = 0, state.max_x - 1 do
      state.grass_h[sc] = pat[sc % #pat + 1]
    end
    if not state.run_active then draw_grass_only() end
    return
  end

  M.stop()
  hl_cache = {}
  hl_count = 0

  state.buf       = buf
  state.base_line = base_line
  state.max_x     = new_max_x

  state.grass_h = {}
  for sc = 0, state.max_x - 1 do
    state.grass_h[sc] = pat[sc % #pat + 1]
  end

  local ms = interval_ms or 400
  draw_grass_only()

  -- Re-trigger every 2–4 minutes (randomised each time).
  local tt = vim.uv.new_timer()
  state.trigger_timer = tt
  local function schedule_next()
    local delay = math.random(120000, 240000)
    state.next_trigger_at = vim.uv.now() + delay
    tt:start(delay, 0, vim.schedule_wrap(function()
      if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
        M.stop()
        return
      end
      if not state.run_active then
        start_run(ms)
      end
      schedule_next()
    end))
  end
  schedule_next()
end

M.debug_info = function()
  local secs_until = nil
  if state.next_trigger_at then
    secs_until = math.max(0, math.floor((state.next_trigger_at - vim.uv.now()) / 1000))
  end
  return {
    session_active  = state.trigger_timer ~= nil,
    run_active      = state.run_active,
    passes_done     = state.passes_done,
    passes_total    = state.passes_total,
    x               = state.x,
    max_x           = state.max_x,
    tick            = state.tick,
    secs_until_next = secs_until,
  }
end

return M
