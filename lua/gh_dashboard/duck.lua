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
  "#2d6b2d",  -- 9  bg grass root   (lighter than fg)
  "#3d8840",  -- 10 bg lower stem   (medium green)
  "#4ea055",  -- 11 bg mid stem     (vibrant)
  "#5ab85e",  -- 12 bg upper/blend  (bright)
  "#12a878",  -- 13 bg body         (bright teal-green)
  "#20e890",  -- 14 bg tip          (sunlit, clearly lighter than fg)
  "#0d1f0d",  -- 15 fg root  (near-black green)
  "#142b14",  -- 16 fg stem  (dark forest shadow)
  "#1a3f1a",  -- 17 fg mid   (still dark)
  "#0a4a2a",  -- 18 fg tip   (dark teal)
  "#5ba8d8",  -- 19 flower blue
  "#e8f0f8",  -- 20 flower white
  "#d94040",  -- 21 flower red
}
local GRASS_COLORS    = { 9, 10, 11, 12, 13, 14 }
local FG_GRASS_COLORS = { 15, 16, 17, 18 }

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

local GRASS_PAT      = { 2,4,1,3,2,1,4,3,1,2,3,4,1,2,5,3,1,4,2,3 }
local GRASS_PAT_N    = #GRASS_PAT
local FG_BLADE_PAT   = { 0,0,4,3,0,0,4,0,0,4,3,0,0,2,3,0,4,4,0,3,2,0,0 }  -- 23 elems (prime vs 20)
local FG_BLADE_PAT_N = #FG_BLADE_PAT

local TIER_TO_HEIGHT = { 3, 4, 5, 6, 7, 8 }  -- contribution tier 1-6 → grass height 3-8

local function build_grass_pattern(contributions, max_x)
  if not contributions or not contributions.weeks then
    local pat = {}
    for sc = 0, max_x - 1 do
      pat[sc + 1] = GRASS_PAT[sc % GRASS_PAT_N + 1]
    end
    return pat, false
  end
  -- Flatten all days newest-first, then reverse so oldest = column 0
  local days = {}
  for i = #contributions.weeks, 1, -1 do
    local week = contributions.weeks[i]
    if week then
      for j = 7, 1, -1 do
        if week[j] then table.insert(days, week[j]) end
      end
    end
  end
  -- Reverse: oldest day first so the rightmost column is today
  local n = #days
  for i = 1, math.floor(n / 2) do
    days[i], days[n - i + 1] = days[n - i + 1], days[i]
  end
  local pat = {}
  for sc = 0, max_x - 1 do
    local day    = days[n - max_x + sc + 1]  -- last max_x days, oldest at sc=0
    local tier   = (day and day.tier) or 1
    local base   = TIER_TO_HEIGHT[tier] or 1
    local jitter = GRASS_PAT[sc % GRASS_PAT_N + 1] % 3 - 1
    pat[sc + 1] = math.max(3, math.min(8, base + jitter))
  end
  return pat, true
end

local function bot_pos(tr) return 2 * (7 - tr) end
local function top_pos(tr) return 2 * (7 - tr) + 1 end

local function fg_eff_h(fh) return fh end

local function fg_grass_color(pixel_pos, fh)
  if fh <= 1 then return FG_GRASS_COLORS[1] end
  if pixel_pos == 0      then return FG_GRASS_COLORS[1] end
  if pixel_pos >= fh - 1 then return FG_GRASS_COLORS[4] end
  if pixel_pos == 1      then return FG_GRASS_COLORS[2] end
  return FG_GRASS_COLORS[3]
end

local function grass_color(pixel_pos, gh)
  if gh <= 1 then return GRASS_COLORS[1] end
  if pixel_pos == 0                          then return GRASS_COLORS[1] end  -- root shadow
  if pixel_pos >= gh - 1                     then return GRASS_COLORS[6] end  -- sunlit tip
  if pixel_pos >= gh - 2                     then return GRASS_COLORS[5] end  -- near-tip glow
  if pixel_pos == 1                          then return GRASS_COLORS[2] end  -- lower shadow
  if gh >= 7 and pixel_pos >= gh - 4         then return GRASS_COLORS[4] end  -- upper body (tall blades)
  return GRASS_COLORS[3]                                                        -- main stem
end

local flower_at  -- forward declaration; defined after state

-- ── highlight cache ────────────────────────────────────────────────────────
-- bg is only set when bg_idx ~= 0 (two explicit duck colors meeting at a
-- half-block boundary).  When bg_idx == 0 the attribute is omitted so
-- the cell inherits the floating window's NormalFloat background naturally —
-- this prevents the black-background bug that occurs when setting bg="NONE".

local hl_cache = {}
local hl_count = 0

local function hl_for(fg_idx, bg_idx)
  local key = fg_idx * 32 + bg_idx
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

-- zone_start: first world column of this zone; zone_w: number of columns.
-- art may be nil (grass-only draw); duck_x far off-world produces no duck pixels.
local function build_body_vt(art, tr, duck_x, zone_start, zone_w, grass_h, fg_grass_h)
  local row_top = art and art[2 * tr - 1] or {}
  local row_bot = art and art[2 * tr] or {}
  local bp      = bot_pos(tr)
  local tp      = top_pos(tr)
  local vt      = {}
  for sc = 0, zone_w - 1 do
    local wc = sc + zone_start
    local dc = wc - duck_x
    local t, b = 0, 0
    if dc >= 0 and dc < DUCK_COLS then
      t = row_top[dc + 1] or 0
      b = row_bot[dc + 1] or 0
    end
    if tr == 6 and fg_grass_h then
      local fg  = fg_grass_h[wc] or 0
      local fgh = fg_eff_h(fg)
      if fgh >= tp + 1 then t = fg_grass_color(tp, fg) end
      if fgh >= bp + 1 then b = fg_grass_color(bp, fg) end
    end
    local gh = (tr >= 4) and (grass_h[wc] or 0) or 0
    local gt = (t == 0 and gh >= tp + 1) and grass_color(tp, gh) or 0
    local gb = (b == 0 and gh >= bp + 1) and grass_color(bp, gh) or 0
    local ft = flower_at(wc, tp)
    local fb = flower_at(wc, bp)
    if ft ~= 0 then t = ft; gt = 0 end
    if fb ~= 0 then b = fb; gb = 0 end
    table.insert(vt, cell(t, b, gt, gb))
  end
  return vt
end

local function build_legs_vt(legs_row, duck_x, zone_start, zone_w, grass_h, fg_grass_h)
  local vt = {}
  for sc = 0, zone_w - 1 do
    local wc = sc + zone_start
    local dc = wc - duck_x
    local t  = (legs_row and dc >= 0 and dc < DUCK_COLS) and (legs_row[dc + 1] or 0) or 0
    local gh = grass_h[wc] or 0
    local fg = (fg_grass_h and fg_grass_h[wc]) or 0
    local fgh = fg_eff_h(fg)
    local t_final  = (fgh >= 2) and fg_grass_color(1, fg) or t
    local gt_final = (t_final == 0 and gh >= 2) and grass_color(1, gh) or 0
    local gb_final = (fgh >= 1) and fg_grass_color(0, fg) or grass_color(0, gh)
    local fft = flower_at(wc, 1)
    local ffb = flower_at(wc, 0)
    if fft ~= 0 then t_final = fft; gt_final = 0 end
    if ffb ~= 0 then gb_final = ffb end
    table.insert(vt, cell(t_final, 0, gt_final, gb_final))
  end
  return vt
end

-- ── module state ───────────────────────────────────────────────────────────

local state = {
  buf                    = nil,
  base_line              = nil,
  timer                  = nil,
  trigger_timer          = nil,
  x                      = 0,
  tick                   = 0,
  foot_frame             = 1,
  wing_step              = 1,
  max_x                  = 40,
  left_w                 = 0,
  right_w                = 40,
  hm_display_w           = 0,
  grass_h                = {},
  fg_grass_h             = {},
  flowers                = {},
  grass_pat              = {},
  grass_from_contribs    = false,
  passes_done            = 0,
  passes_total           = 2,
  run_active             = false,
  next_trigger_at        = nil,
}

-- ── flower sprites ─────────────────────────────────────────────────────────

flower_at = function(wc, pixel_pos)
  local col = state.flowers[wc]
  return col and col[pixel_pos] or 0
end

-- slot 1=petal, 2=core(white/20), 3=stem(dark/15)
-- [col_offset] = { [pixel_row] = color_slot }
local DAISY_SHAPE = {
  [0] = { [5]=1, [6]=1 },
  [1] = { [4]=1, [5]=1, [6]=1, [7]=1 },
  [2] = { [0]=3, [1]=3, [2]=3, [3]=3, [4]=2, [5]=2, [6]=1, [7]=1 },
  [3] = { [4]=1, [5]=1, [6]=1, [7]=1 },
  [4] = { [5]=1, [6]=1 },
}

local STAR_SHAPE = {
  [0] = { [4]=1, [7]=1 },
  [1] = { [5]=1, [6]=1 },
  [2] = { [0]=3, [1]=3, [2]=3, [3]=3, [4]=2, [5]=2, [6]=1, [7]=1 },
  [3] = { [5]=1, [6]=1 },
  [4] = { [4]=1, [7]=1 },
}

local function setup_flowers(lw)
  state.flowers = {}
  if lw < 5 then return end

  local function place(center_wc, shape, petal_color)
    for col_off = 0, 4 do
      local wc = center_wc - 2 + col_off
      local s  = shape[col_off]
      if s then
        state.flowers[wc] = state.flowers[wc] or {}
        for px, slot in pairs(s) do
          state.flowers[wc][px] = (slot == 1) and petal_color
                               or (slot == 2) and 20
                               or 15
        end
      end
    end
  end

  place(lw - 5, DAISY_SHAPE, 19)
  place(lw + math.floor(state.right_w * 3 / 4), STAR_SHAPE, 21)
end

-- ── run helpers ────────────────────────────────────────────────────────────

local draw  -- forward declaration

local function set_row(buf_line, vt_left, vt_right)
  if #vt_left > 0 then
    vim.api.nvim_buf_set_extmark(state.buf, duck_ns, buf_line, 0, {
      virt_text = vt_left, virt_text_pos = "overlay",
    })
  end
  vim.api.nvim_buf_set_extmark(state.buf, duck_ns, buf_line, 0, {
    virt_text = vt_right, virt_text_pos = "overlay",
    virt_text_win_col = state.hm_display_w,
  })
end

local function draw_grass_only()
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then return end
  local grass_h = state.grass_h
  local fg_h    = state.fg_grass_h
  local lw      = state.left_w
  local rw      = state.right_w
  local no_duck = -(DUCK_COLS + 1)
  for tr = 4, 6 do
    set_row(state.base_line + tr,
      build_body_vt(nil, tr, no_duck, 0,  lw, grass_h, fg_h),
      build_body_vt(nil, tr, no_duck, lw, rw, grass_h, fg_h))
  end
  local line7 = state.base_line + 7
  if vim.api.nvim_buf_line_count(state.buf) > line7 then
    set_row(line7,
      build_legs_vt(nil, no_duck, 0,  lw, grass_h, fg_h),
      build_legs_vt(nil, no_duck, lw, rw, grass_h, fg_h))
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

  local dx      = state.x
  local lw      = state.left_w
  local rw      = state.right_w
  local mxw     = state.max_x
  local art     = get_art(WING_SEQ[state.wing_step])
  local grass_h = state.grass_h
  local fg_h    = state.fg_grass_h

  for tr = 1, 6 do
    set_row(state.base_line + tr,
      build_body_vt(art, tr, dx, 0,  lw, grass_h, fg_h),
      build_body_vt(art, tr, dx, lw, rw, grass_h, fg_h))
  end

  local line7 = state.base_line + 7
  if vim.api.nvim_buf_line_count(state.buf) > line7 then
    set_row(line7,
      build_legs_vt(LEGS[state.foot_frame], dx, 0,  lw, grass_h, fg_h),
      build_legs_vt(LEGS[state.foot_frame], dx, lw, rw, grass_h, fg_h))
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

M.start = function(buf, base_line, interval_ms, win_width, hm_display_w, contributions, left_w)
  local hm_w     = hm_display_w or 58
  local lw       = math.max(0, left_w or 0)
  local rw       = math.max(DUCK_COLS + 1, (win_width or 160) - hm_w)
  local new_max_x = lw + rw
  local pat, from_contribs = build_grass_pattern(contributions, new_max_x)

  local function apply_grass()
    state.grass_pat           = pat
    state.grass_from_contribs = from_contribs
    state.grass_h             = {}
    state.fg_grass_h          = {}
    for sc = 0, state.max_x - 1 do
      state.grass_h[sc] = pat[sc + 1]
      state.fg_grass_h[sc] = FG_BLADE_PAT[sc % FG_BLADE_PAT_N + 1]
    end
    setup_flowers(state.left_w)
  end

  if state.trigger_timer then
    state.buf          = buf
    state.base_line    = base_line
    state.left_w       = lw
    state.right_w      = rw
    state.hm_display_w = hm_w
    state.max_x        = new_max_x
    apply_grass()
    if not state.run_active then draw_grass_only() end
    return
  end

  M.stop()
  hl_cache = {}
  hl_count = 0

  state.buf          = buf
  state.base_line    = base_line
  state.left_w       = lw
  state.right_w      = rw
  state.hm_display_w = hm_w
  state.max_x        = new_max_x
  apply_grass()

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
    session_active       = state.trigger_timer ~= nil,
    run_active           = state.run_active,
    passes_done          = state.passes_done,
    passes_total         = state.passes_total,
    x                    = state.x,
    max_x                = state.max_x,
    left_w               = state.left_w,
    right_w              = state.right_w,
    tick                 = state.tick,
    secs_until_next      = secs_until,
    grass_from_contribs  = state.grass_from_contribs,
    grass_pat            = state.grass_pat,
  }
end

return M
