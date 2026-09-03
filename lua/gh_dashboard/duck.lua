local M = {}

local duck_ns = vim.api.nvim_create_namespace("GhDashboardDuck")

-- ── forward-declare state so all closures can reference it ─────────────────

local state

-- ── color palette ──────────────────────────────────────────────────────────

local COLORS = {
  "#b09060",  -- 1  outline
  "#ccb080",  -- 2  body
  "#cc6050",  -- 3  beak
  "#1e2127",  -- 4  eye
  "#b8bcc4",  -- 5  wing stripe
  "#b89472",  -- 6  feet / legs
  "#8a6438",  -- 7  deep shadow
  "#d8c08a",  -- 8  belly highlight
  "#2d6b2d",  -- 9  summer grass root
  "#3d8840",  -- 10 summer lower stem
  "#4ea055",  -- 11 summer mid stem
  "#5ab85e",  -- 12 summer upper
  "#12a878",  -- 13 summer body
  "#20e890",  -- 14 summer tip (sunlit)
  "#0d1f0d",  -- 15 fg summer root
  "#142b14",  -- 16 fg summer stem
  "#1a3f1a",  -- 17 fg summer mid
  "#0a4a2a",  -- 18 fg summer tip
  "#5ba8d8",  -- 19 flower blue
  "#e8f0f8",  -- 20 flower white
  "#d94040",  -- 21 flower red
  "#a8ffb0",  -- 22 shimmer bright-tip
  "#f5e050",  -- 23 firefly glow
  "#1a281a",  -- 24 hill silhouette
  "#3a2810",  -- 25 autumn root
  "#6a4820",  -- 26 autumn lower
  "#8a6030",  -- 27 autumn mid
  "#b08040",  -- 28 autumn upper
  "#d8a050",  -- 29 autumn body (golden)
  "#f0c060",  -- 30 autumn tip
  "#1a0800",  -- 31 fg autumn root
  "#2a1400",  -- 32 fg autumn stem
  "#3a2010",  -- 33 fg autumn mid
  "#200c00",  -- 34 fg autumn tip
  "#1a2020",  -- 35 winter root
  "#283030",  -- 36 winter lower
  "#343e3e",  -- 37 winter mid
  "#404848",  -- 38 winter upper
  "#505858",  -- 39 winter body
  "#b0d8e0",  -- 40 winter tip (icy blue-white)
  "#0a0d0a",  -- 41 fg winter root
  "#101510",  -- 42 fg winter stem
  "#141c14",  -- 43 fg winter mid
  "#081208",  -- 44 fg winter tip
  "#f5a8c8",  -- 45 tulip pink
}

-- Colours that change at night (day → night remapping by index)
local NIGHT_OVERRIDES = {
  [13] = "#0a2040",  -- bg body: dark navy
  [14] = "#1a3a5a",  -- bg tip: dim blue
  [22] = "#60a0e0",  -- shimmer: cool blue
  [23] = "#ffffa0",  -- firefly: bright white-yellow
}

local SEASONAL_GRASS_IDX = {
  spring = { 9, 10, 11, 12, 13, 14 },
  summer = { 9, 10, 11, 12, 13, 14 },
  autumn = { 25, 26, 27, 28, 29, 30 },
  winter = { 35, 36, 37, 38, 39, 40 },
}
local SEASONAL_FG_GRASS_IDX = {
  spring = { 15, 16, 17, 18 },
  summer = { 15, 16, 17, 18 },
  autumn = { 31, 32, 33, 34 },
  winter = { 41, 42, 43, 44 },
}

-- ── pixel art ──────────────────────────────────────────────────────────────
-- 12 pixel rows × 14 cols per wing frame.
-- Terminal rows 1-6 = duck body.  Terminal row 7 (contributions line) = legs.

local HEAD = {
  {0,0,0,0,0,0,0,0,0,0,0,0,0,0},
  {0,0,0,0,0,0,1,1,1,1,0,0,0,0},
  {0,0,0,0,0,1,2,2,2,1,0,0,0,0},
  {0,0,0,0,0,1,2,2,2,4,1,0,0,0},
  {0,0,0,0,0,1,2,2,2,2,3,3,0,0},
  {0,0,0,0,1,2,2,2,2,3,0,0,0,0},
}

-- Head dipped, beak pointing ground-ward (peck pose)
local HEAD_PECK = {
  {0,0,0,0,0,0,0,0,0,0,0,0,0,0},
  {0,0,0,0,0,0,0,0,0,0,0,0,0,0},
  {0,0,0,0,0,0,1,1,1,1,0,0,0,0},
  {0,0,0,0,0,1,2,2,2,4,1,0,0,0},
  {0,0,0,1,2,2,2,3,3,0,0,0,0,0},
  {0,0,1,2,2,3,0,0,0,0,0,0,0,0},
}

local BODY = {
  [0] = {  -- wing down / resting
    {0,0,1,1,1,2,2,2,1,0,0,0,0,0},
    {7,1,2,8,8,2,2,2,1,0,0,0,0,0},
    {7,2,2,8,8,2,2,2,1,0,0,0,0,0},
    {7,2,2,5,5,5,2,2,1,0,0,0,0,0},
    {7,2,2,2,2,2,2,1,0,0,0,0,0,0},
    {0,1,2,2,2,2,1,0,0,0,0,0,0,0},
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

-- Sitting/resting duck — wider, rounder, settled into the grass
local BODY_SIT = {
  {0,0,0,1,1,2,2,2,2,1,0,0,0,0},
  {7,1,2,8,8,8,2,2,2,1,0,0,0,0},
  {7,2,2,8,8,8,2,2,2,2,1,0,0,0},
  {7,2,2,2,5,5,5,5,2,2,1,0,0,0},
  {7,2,2,2,2,2,2,2,2,1,0,0,0,0},
  {0,7,7,1,2,2,2,2,1,0,0,0,0,0},
}

local LEGS = {
  [1] = {0,0,6,0,0,6,0,0,0,0,0,0,0,0},
  [2] = {0,0,0,6,6,0,0,0,0,0,0,0,0,0},
}

local WING_SEQ  = { 0, 1, 2, 1 }
local DUCK_COLS = 14

-- ── grass pattern constants ────────────────────────────────────────────────

local GRASS_PAT      = { 2,4,1,3,2,1,4,3,1,2,3,4,1,2,5,3,1,4,2,3 }
local GRASS_PAT_N    = #GRASS_PAT
local FG_BLADE_PAT   = { 0,0,4,3,0,0,4,0,0,4,3,0,0,2,3,0,4,4,0,3,2,0,0 }
local FG_BLADE_PAT_N = #FG_BLADE_PAT
local TIER_TO_HEIGHT = { 3, 4, 5, 6, 7, 8 }

-- ── cloud shapes (pixel_pos 12–13 = tr=1, topmost terminal rows) ──────────

local CLOUD_A = {
  [0] = { [12]=24 },
  [1] = { [12]=24, [13]=24 },
  [2] = { [12]=24, [13]=24 },
  [3] = { [12]=24, [13]=24 },
  [4] = { [12]=24, [13]=24 },
  [5] = { [12]=24, [13]=24 },
  [6] = { [12]=24 },
}
local CLOUD_B = {
  [0] = { [12]=24 },
  [1] = { [12]=24, [13]=24 },
  [2] = { [12]=24, [13]=24 },
  [3] = { [12]=24 },
}
local CLOUD_WIDTHS = { 7, 4 }

-- ── flower shapes ──────────────────────────────────────────────────────────

-- slot 1=petal, 2=core(white/20), 3=stem(dark/15)
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
local TULIP_SHAPE = {
  [0] = { [6]=1, [7]=1 },
  [1] = { [5]=1, [6]=1, [7]=1 },
  [2] = { [0]=3, [1]=3, [2]=3, [3]=3, [4]=2, [5]=1, [6]=1, [7]=1 },
  [3] = { [5]=1, [6]=1, [7]=1 },
  [4] = { [6]=1, [7]=1 },
}

-- ── highlight cache ────────────────────────────────────────────────────────
-- bg is only set when bg_idx ~= 0 (two explicit duck colors meeting at a
-- half-block boundary).  When bg_idx == 0 the attribute is omitted so
-- the cell inherits the floating window's NormalFloat background naturally.

local hl_cache = {}
local hl_count = 0

local function get_color(idx)
  if state and state.night_mode and NIGHT_OVERRIDES[idx] then
    return NIGHT_OVERRIDES[idx]
  end
  return COLORS[idx]
end

local function hl_for(fg_idx, bg_idx)
  local night_bit = (state and state.night_mode) and 8192 or 0
  local key       = night_bit + fg_idx * 64 + bg_idx
  if hl_cache[key] then return hl_cache[key] end
  hl_count = hl_count + 1
  local name = "GhDuckPx" .. hl_count
  vim.api.nvim_set_hl(0, name, {
    fg = fg_idx ~= 0 and get_color(fg_idx) or nil,
    bg = bg_idx ~= 0 and get_color(bg_idx) or nil,
  })
  hl_cache[key] = name
  return name
end

-- ── cell builder ───────────────────────────────────────────────────────────

local TRANSPARENT = { " ", "NormalFloat" }

local function cell(t, b, gt, gb)
  local ft = t ~= 0 and t or gt
  local fb = b ~= 0 and b or gb
  if     ft == 0 and fb == 0 then return TRANSPARENT
  elseif ft ~= 0 and fb == 0 then return { "▀", hl_for(ft, 0) }
  elseif ft == 0 and fb ~= 0 then return { "▄", hl_for(fb, 0) }
  elseif ft == fb             then return { "█", hl_for(ft, 0) }
  else                             return { "▀", hl_for(ft, fb) }
  end
end

-- ── forward declarations (closures defined after state) ───────────────────

local flower_at
local sway
local grass_c
local fly_color
local hill_at
local fg_grass_color
local butterfly_at
local cloud_at

-- ── position helpers ───────────────────────────────────────────────────────

local function bot_pos(tr) return 2 * (7 - tr) end
local function top_pos(tr) return 2 * (7 - tr) + 1 end
local function fg_eff_h(fh) return fh end

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
      local fgh = math.max(0, math.min(5, fg_eff_h(fg) + sway(wc, 1.3, 0.55, 1.0)))
      if fgh >= tp + 1 then t = fg_grass_color(tp, fg) end
      if fgh >= bp + 1 then b = fg_grass_color(bp, fg) end
    end
    local gh_bg = (tr >= 4) and math.max(0, math.min(8,
      (grass_h[wc] or 0) + sway(wc))) or 0
    local gt = (t == 0 and gh_bg >= tp + 1) and grass_c(tp, gh_bg, wc) or 0
    local gb = (b == 0 and gh_bg >= bp + 1) and grass_c(bp, gh_bg, wc) or 0
    if t == 0 and gt == 0 then gt = hill_at(wc, tp) end
    if b == 0 and gb == 0 then gb = hill_at(wc, bp) end
    -- clouds (sky background, below flowers/fireflies/butterfly)
    if t == 0 and gt == 0 then
      local clt = cloud_at(wc, tp)
      if clt ~= 0 then gt = clt end
    end
    if b == 0 and gb == 0 then
      local clb = cloud_at(wc, bp)
      if clb ~= 0 then gb = clb end
    end
    local ft = flower_at(wc, tp)
    local fb = flower_at(wc, bp)
    if ft ~= 0 then t = ft; gt = 0 end
    if fb ~= 0 then b = fb; gb = 0 end
    local fct = fly_color(wc, tp)
    local fcb = fly_color(wc, bp)
    if fct ~= 0 then t = fct; gt = 0 end
    if fcb ~= 0 then b = fcb; gb = 0 end
    -- butterfly doesn't override duck pixels
    local bft = butterfly_at(wc, tp)
    local bfb = butterfly_at(wc, bp)
    if bft ~= 0 and t == 0 then t = bft; gt = 0 end
    if bfb ~= 0 and b == 0 then b = bfb; gb = 0 end
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
    local fgh = math.max(0, math.min(5, fg_eff_h(fg) + sway(wc, 1.3, 0.55, 1.0)))
    local t_final  = (fgh >= 2) and fg_grass_color(1, fg) or t
    local gt_final = (t_final == 0 and gh >= 2) and grass_c(1, gh, wc) or 0
    local gb_final = (fgh >= 1) and fg_grass_color(0, fg) or grass_c(0, gh, wc)
    local fft = flower_at(wc, 1)
    local ffb = flower_at(wc, 0)
    if fft ~= 0 then t_final = fft; gt_final = 0 end
    if ffb ~= 0 then gb_final = ffb end
    local fct = fly_color(wc, 1)
    local fcb = fly_color(wc, 0)
    if fct ~= 0 then t_final = fct; gt_final = 0 end
    if fcb ~= 0 then gb_final = fcb end
    local bft = butterfly_at(wc, 1)
    local bfb = butterfly_at(wc, 0)
    if bft ~= 0 and t_final == 0 then t_final = bft; gt_final = 0 end
    if bfb ~= 0 then gb_final = bfb end
    table.insert(vt, cell(t_final, 0, gt_final, gb_final))
  end
  return vt
end

-- ── module state ───────────────────────────────────────────────────────────

state = {
  buf                 = nil,
  base_line           = nil,
  timer               = nil,
  trigger_timer       = nil,
  x                   = 0,
  tick                = 0,
  foot_frame          = 1,
  wing_step           = 1,
  max_x               = 40,
  left_w              = 0,
  right_w             = 40,
  hm_display_w        = 0,
  grass_h             = {},
  fg_grass_h          = {},
  flowers             = {},
  grass_pat           = {},
  grass_from_contribs = false,
  passes_done         = 0,
  passes_total        = 2,
  run_active          = false,
  next_trigger_at     = nil,
  swaying             = {},
  hill_h              = {},
  shimmer_col         = 0,
  shimmer_ttl         = 30,
  fireflies           = {},
  wind_timer          = nil,
  -- new
  night_mode          = false,
  season              = "summer",
  override_night      = nil,    -- nil=auto, true/false=forced
  override_season     = nil,    -- nil=auto, or "spring"/"summer"/"autumn"/"winter"
  peck_ticks          = 0,
  force_peck          = false,
  rest_x              = -1,     -- x of sitting duck between runs (-1=none)
  butterfly           = nil,
  clouds              = {},
}

-- ── season / time helpers (defined after state) ────────────────────────────

local function is_night()
  if state.override_night ~= nil then return state.override_night end
  local h = os.date("*t").hour
  return h >= 20 or h <= 5
end

local function get_season()
  if state.override_season then return state.override_season end
  local m = os.date("*t").month
  if m >= 3 and m <= 5  then return "spring"
  elseif m >= 6 and m <= 8  then return "summer"
  elseif m >= 9 and m <= 11 then return "autumn"
  else                           return "winter"
  end
end

local function auto_season_name()
  local m = os.date("*t").month
  if m >= 3 and m <= 5  then return "spring"
  elseif m >= 6 and m <= 8  then return "summer"
  elseif m >= 9 and m <= 11 then return "autumn"
  else                           return "winter"
  end
end

-- ── closure implementations ────────────────────────────────────────────────

flower_at = function(wc, pixel_pos)
  local col = state.flowers[wc]
  return col and col[pixel_pos] or 0
end

sway = function(wc)
  local s = state.swaying[wc]
  if not s then return 0 end
  return math.floor(math.sin(s.phase) * s.amp + 0.5)
end

fg_grass_color = function(pixel_pos, fh)
  local fgc = SEASONAL_FG_GRASS_IDX[state.season or "summer"]
  if fh <= 1 then return fgc[1] end
  if pixel_pos == 0       then return fgc[1] end
  if pixel_pos >= fh - 1  then return fgc[4] end
  if pixel_pos == 1       then return fgc[2] end
  return fgc[3]
end

grass_c = function(pixel_pos, gh, wc)
  local gc = SEASONAL_GRASS_IDX[state.season or "summer"]
  if math.abs(wc - state.shimmer_col) <= 3 and pixel_pos >= gh - 2 and gh >= 3 then
    return 22
  end
  if gh <= 1 then return gc[1] end
  if pixel_pos == 0                         then return gc[1] end
  if pixel_pos >= gh - 1                    then return gc[6] end
  if pixel_pos >= gh - 2                    then return gc[5] end
  if pixel_pos == 1                         then return gc[2] end
  if gh >= 7 and pixel_pos >= gh - 4        then return gc[4] end
  return gc[3]
end

fly_color = function(wc, pixel_pos)
  for _, fly in ipairs(state.fireflies) do
    if math.floor(fly.x) == wc and math.sin(fly.phase) > 0.45 and fly.y == pixel_pos then
      return 23
    end
  end
  return 0
end

hill_at = function(wc, pixel_pos)
  local hh = state.hill_h[wc] or 0
  return hh >= pixel_pos + 1 and 24 or 0
end

butterfly_at = function(wc, pixel_pos)
  local bf = state.butterfly
  if not bf then return 0 end
  local bx    = math.floor(bf.x)
  local eff_y = bf.effective_y or bf.y
  if pixel_pos ~= eff_y then return 0 end
  local wing_up = math.floor(bf.phase / math.pi) % 2 == 0
  if bx == wc then
    return bf.color  -- body always visible
  elseif wing_up and (bx - 1 == wc or bx + 1 == wc) then
    return bf.color  -- wings spread on up-frame
  end
  return 0
end

cloud_at = function(wc, pixel_pos)
  for _, c in ipairs(state.clouds) do
    local cx     = math.floor(c.x)
    local offset = wc - cx
    if offset >= 0 then
      local col_data = c.shape[offset]
      if col_data then
        local col_color = col_data[pixel_pos]
        if col_color then return col_color end
      end
    end
  end
  return 0
end

-- ── pixel art helper ───────────────────────────────────────────────────────

local function get_art(wing_frame, pecking, sitting)
  local head = pecking and HEAD_PECK or HEAD
  local body = sitting and BODY_SIT or BODY[wing_frame]
  local art  = {}
  for _, row in ipairs(head) do table.insert(art, row) end
  for _, row in ipairs(body) do table.insert(art, row) end
  return art
end

-- ── grass pattern ──────────────────────────────────────────────────────────

local function build_grass_pattern(contributions, max_x)
  if not contributions or not contributions.weeks then
    local pat = {}
    for sc = 0, max_x - 1 do
      pat[sc + 1] = GRASS_PAT[sc % GRASS_PAT_N + 1]
    end
    return pat, false
  end
  local days = {}
  for i = #contributions.weeks, 1, -1 do
    local week = contributions.weeks[i]
    if week then
      for j = 7, 1, -1 do
        if week[j] then table.insert(days, week[j]) end
      end
    end
  end
  local n = #days
  for i = 1, math.floor(n / 2) do
    days[i], days[n - i + 1] = days[n - i + 1], days[i]
  end
  local pat = {}
  for sc = 0, max_x - 1 do
    local day    = days[n - max_x + sc + 1]
    local tier   = (day and day.tier) or 1
    local base   = TIER_TO_HEIGHT[tier] or 1
    local jitter = GRASS_PAT[sc % GRASS_PAT_N + 1] % 3 - 1
    pat[sc + 1] = math.max(3, math.min(8, base + jitter))
  end
  return pat, true
end

-- ── seasonal flower setup ──────────────────────────────────────────────────

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

  local season = state.season or "summer"

  if season == "winter" then
    place(lw - 5, DAISY_SHAPE, 19)  -- sparse: one daisy
    for wc = 0, state.max_x - 1 do
      if math.random() < 0.40 then
        local gh = state.grass_h[wc] or 3
        state.flowers[wc] = state.flowers[wc] or {}
        state.flowers[wc][gh - 1] = 40  -- icy blue-white snow tip
        if gh > 1 then state.flowers[wc][gh - 2] = 40 end
      end
    end
  elseif season == "spring" then
    place(lw - 5,  DAISY_SHAPE, 19)   -- blue daisy
    place(lw - 12, TULIP_SHAPE, 45)   -- pink tulip
    place(lw + math.floor(state.right_w * 3 / 4), STAR_SHAPE, 21)
  elseif season == "autumn" then
    place(lw - 5, DAISY_SHAPE, 30)    -- golden daisy
    for _ = 1, math.random(8, 16) do  -- scattered fallen leaves
      local wc = math.random(0, state.max_x - 1)
      local gh = state.grass_h[wc] or 3
      state.flowers[wc] = state.flowers[wc] or {}
      local px = math.random(0, math.min(2, math.max(0, gh - 1)))
      state.flowers[wc][px] = 29  -- golden autumn colour
    end
  else  -- summer (default)
    place(lw - 5, DAISY_SHAPE, 19)
    place(lw + math.floor(state.right_w * 3 / 4), STAR_SHAPE, 21)
  end
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
  vim.api.nvim_buf_clear_namespace(state.buf, duck_ns, 0, -1)
  local grass_h = state.grass_h
  local fg_h    = state.fg_grass_h
  local lw      = state.left_w
  local rw      = state.right_w
  -- sitting duck is visible between runs when rest_x >= 0
  local duck_x = state.rest_x >= 0 and state.rest_x or -(DUCK_COLS + 1)
  local art    = state.rest_x >= 0 and get_art(0, false, true) or nil
  for tr = 1, 6 do
    set_row(state.base_line + tr,
      build_body_vt(art, tr, duck_x, 0,  lw, grass_h, fg_h),
      build_body_vt(art, tr, duck_x, lw, rw, grass_h, fg_h))
  end
  local line7 = state.base_line + 7
  if vim.api.nvim_buf_line_count(state.buf) > line7 then
    -- sitting duck has no leg row
    set_row(line7,
      build_legs_vt(nil, duck_x, 0,  lw, grass_h, fg_h),
      build_legs_vt(nil, duck_x, lw, rw, grass_h, fg_h))
  end
end

local function stop_run()
  if state.timer then
    state.timer:stop()
    state.timer:close()
    state.timer = nil
  end
  state.run_active = false
  state.rest_x     = state.x  -- duck sits where it stopped
  draw_grass_only()
end

local function start_run(interval_ms)
  stop_run()
  state.passes_total = math.random(2, 3)
  state.passes_done  = 0
  state.x            = 0
  state.tick         = 0
  state.foot_frame   = 1
  state.wing_step    = 1
  state.peck_ticks   = 0
  state.rest_x       = -1  -- hide sitting duck while walking
  state.run_active   = true
  local t = vim.uv.new_timer()
  state.timer = t
  t:start(0, interval_ms or 400, vim.schedule_wrap(draw))
end

-- ── draw ───────────────────────────────────────────────────────────────────

draw = function()
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
    M.stop(); return
  end

  vim.api.nvim_buf_clear_namespace(state.buf, duck_ns, 0, -1)

  local dx      = state.x
  local lw      = state.left_w
  local rw      = state.right_w
  local mxw     = state.max_x
  local grass_h = state.grass_h
  local fg_h    = state.fg_grass_h

  -- peck animation: head dips first half of peck_ticks, rises second half
  local pecking = state.peck_ticks > 6
  local art     = get_art(WING_SEQ[state.wing_step], pecking, false)

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

  -- if pecking, count down but don't advance x
  if state.peck_ticks > 0 then
    state.peck_ticks = state.peck_ticks - 1
    return
  end

  -- advance counters
  state.tick = state.tick + 1
  if state.tick % 2 == 0 then
    local nx = (state.x + 1) % mxw
    if nx < state.x then
      -- completed one full pass
      state.passes_done = state.passes_done + 1
      if state.passes_done >= state.passes_total then
        stop_run(); return
      end
      -- maybe peck at the end of this pass before the next
      if state.force_peck or math.random() < 0.30 then
        state.force_peck = false
        state.peck_ticks = 12
      end
    end
    state.x = nx
  end
  if state.tick % 8  == 0 then state.foot_frame = state.foot_frame == 1 and 2 or 1 end
  if state.tick % 24 == 0 then state.wing_step  = state.wing_step  % #WING_SEQ + 1 end
end

-- ── debug UI ───────────────────────────────────────────────────────────────

local debug_state  = { buf = nil, win = nil, timer = nil }
local debug_ns     = vim.api.nvim_create_namespace("GhDuckDebug")  -- unused but reserved
local SEASON_CYCLE = { "spring", "summer", "autumn", "winter" }

local function close_debug()
  if debug_state.timer then
    debug_state.timer:stop()
    debug_state.timer:close()
    debug_state.timer = nil
  end
  if debug_state.win and vim.api.nvim_win_is_valid(debug_state.win) then
    vim.api.nvim_win_close(debug_state.win, false)
    debug_state.win = nil
  end
end

local function refresh_debug()
  if not debug_state.buf or not vim.api.nvim_buf_is_valid(debug_state.buf) then
    close_debug(); return
  end
  local h   = os.date("*t").hour
  local mon = os.date("*t").month
  local auto_s = auto_season_name()
  local night_label = state.override_night ~= nil
    and ("override=" .. tostring(state.override_night))
    or  (is_night() and "night" or "day")
  local lines = {
    "",
    "  State",
    string.format("  %-14s %s", "session",    state.trigger_timer and "● active" or "○ inactive"),
    string.format("  %-14s %s", "run",        state.run_active    and "● running" or "○ idle"),
    string.format("  %-14s %d / %d",           "passes",   state.passes_done, state.passes_total),
    string.format("  %-14s %d / %d",           "x pos",    state.x,           state.max_x),
    string.format("  %-14s %d",                "tick",     state.tick),
    string.format("  %-14s %d",                "peck",     state.peck_ticks),
    string.format("  %-14s %d",                "rest x",   state.rest_x),
    "",
    "  Environment",
    string.format("  %-14s %02d:00  →  %s",   "hour",     h,   night_label),
    string.format("  %-14s %d  →  %s",         "month",    mon, auto_s),
    string.format("  %-14s %s%s",              "season",   state.season or auto_s,
      state.override_season and "  [override]" or ""),
    "",
    "  Controls",
    "  r  trigger run now",
    "  p  force peck next pass",
    "  n  cycle night override  (auto → night → day → auto)",
    "  s  cycle season override",
    "  c  clear all overrides",
    "  q / <Esc>  close",
    "",
  }
  vim.bo[debug_state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(debug_state.buf, 0, -1, false, lines)
  vim.bo[debug_state.buf].modifiable = false
end

local function apply_overrides_and_redraw()
  state.season     = get_season()
  state.night_mode = is_night()
  setup_flowers(state.left_w)
  if not state.run_active then draw_grass_only() end
end

M.debug_win = function()
  if debug_state.win and vim.api.nvim_win_is_valid(debug_state.win) then
    close_debug(); return
  end

  debug_state.buf = vim.api.nvim_create_buf(false, true)
  vim.bo[debug_state.buf].buftype    = "nofile"
  vim.bo[debug_state.buf].bufhidden  = "wipe"
  vim.bo[debug_state.buf].modifiable = false
  vim.b[debug_state.buf].render_markdown = { enabled = false }

  local ui   = vim.api.nvim_list_uis()[1] or { width = 180, height = 50 }
  local w, h = 58, 24
  debug_state.win = vim.api.nvim_open_win(debug_state.buf, true, {
    relative   = "editor",
    width      = w,
    height     = h,
    row        = math.floor((ui.height - h) / 2),
    col        = math.floor((ui.width  - w) / 2),
    style      = "minimal",
    border     = "rounded",
    title      = " Duck Debug ",
    title_pos  = "center",
    footer     = " r run  p peck  n night  s season  c clear  q close ",
    footer_pos = "center",
  })
  vim.wo[debug_state.win].number         = false
  vim.wo[debug_state.win].relativenumber = false
  vim.wo[debug_state.win].cursorline     = false
  vim.wo[debug_state.win].signcolumn     = "no"

  local function dmap(lhs, fn)
    vim.keymap.set("n", lhs, fn, { buffer = debug_state.buf, nowait = true, silent = true })
  end

  dmap("q",     close_debug)
  dmap("<Esc>", close_debug)

  dmap("r", function()
    if not state.run_active and state.trigger_timer then
      start_run(400)
    end
  end)

  dmap("p", function()
    state.force_peck = true
  end)

  dmap("n", function()
    -- cycle: auto → force night → force day → auto
    if state.override_night == nil then
      state.override_night = true
    elseif state.override_night == true then
      state.override_night = false
    else
      state.override_night = nil
    end
    apply_overrides_and_redraw()
  end)

  dmap("s", function()
    local cur = state.override_season or auto_season_name()
    local idx = 1
    for i, s in ipairs(SEASON_CYCLE) do
      if s == cur then idx = i; break end
    end
    state.override_season = SEASON_CYCLE[idx % #SEASON_CYCLE + 1]
    apply_overrides_and_redraw()
  end)

  dmap("c", function()
    state.override_night  = nil
    state.override_season = nil
    apply_overrides_and_redraw()
  end)

  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer   = debug_state.buf,
    once     = true,
    callback = close_debug,
  })

  refresh_debug()

  local rt = vim.uv.new_timer()
  debug_state.timer = rt
  rt:start(200, 200, vim.schedule_wrap(function()
    if not debug_state.buf or not vim.api.nvim_buf_is_valid(debug_state.buf) then
      close_debug(); return
    end
    refresh_debug()
  end))
end

-- ── public API ─────────────────────────────────────────────────────────────

M.stop = function()
  stop_run()
  if state.trigger_timer then
    state.trigger_timer:stop()
    state.trigger_timer:close()
    state.trigger_timer = nil
  end
  if state.wind_timer then
    state.wind_timer:stop()
    state.wind_timer:close()
    state.wind_timer = nil
  end
end

M.start = function(buf, base_line, interval_ms, win_width, hm_display_w, contributions, left_w)
  local hm_w      = hm_display_w or 58
  local lw        = math.max(0, left_w or 0)
  local rw        = math.max(DUCK_COLS + 1, (win_width or 160) - hm_w)
  local new_max_x = lw + rw
  local pat, from_contribs = build_grass_pattern(contributions, new_max_x)
  local new_night  = is_night()
  local new_season = get_season()

  local function apply_grass()
    state.season              = new_season
    state.night_mode          = new_night
    state.grass_pat           = pat
    state.grass_from_contribs = from_contribs
    state.grass_h             = {}
    state.fg_grass_h          = {}
    state.swaying             = {}
    for sc = 0, new_max_x - 1 do
      state.grass_h[sc]    = pat[sc + 1]
      state.fg_grass_h[sc] = FG_BLADE_PAT[sc % FG_BLADE_PAT_N + 1]
      local raw_h = 9 + 3 * math.sin(sc * 0.08) + 2 * math.sin(sc * 0.19 + 1.4)
      state.hill_h[sc] = math.max(6, math.min(13, math.floor(raw_h)))
    end
    setup_flowers(lw)

    -- fireflies (more at night)
    state.fireflies = {}
    local n_flies = math.max(4, math.floor(new_max_x / 20))
    if new_night then n_flies = n_flies * 2 end
    for _ = 1, n_flies do
      table.insert(state.fireflies, {
        x     = math.random(0, new_max_x - 1),
        y     = math.random(3, 7),
        phase = math.random() * 6.28,
        vx    = (math.random() - 0.5) * 0.18,
      })
    end

    -- butterfly
    local init_y = math.random(4, 8)
    state.butterfly = {
      x           = math.random(5, new_max_x - 5),
      y           = init_y,
      vx          = (math.random() < 0.5 and 1 or -1) * (0.15 + math.random() * 0.12),
      phase       = math.random() * 6.28,
      wobble      = math.random() * 6.28,
      color       = math.random() < 0.5 and 19 or 21,
      effective_y = init_y,
    }

    -- clouds
    state.clouds = {
      { x = math.random(0, new_max_x), shape = CLOUD_A, width = CLOUD_WIDTHS[1] },
      { x = math.random(0, new_max_x), shape = CLOUD_B, width = CLOUD_WIDTHS[2] },
    }
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
  state.rest_x = math.floor(new_max_x / 2)  -- start with sitting duck visible
  draw_grass_only()

  if not state.wind_timer then
    local wt = vim.uv.new_timer()
    state.wind_timer = wt
    wt:start(0, 120, vim.schedule_wrap(function()
      if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then return end

      -- Advance swaying blades; remove finished ones
      for wc, s in pairs(state.swaying) do
        s.phase = s.phase + s.speed
        if s.phase >= math.pi * 2 then state.swaying[wc] = nil end
      end

      -- Occasionally start a new blade
      local n = 0
      for _ in pairs(state.swaying) do n = n + 1 end
      if n < 3 and math.random() < 0.12 then
        local wc = math.random(0, state.max_x - 1)
        if not state.swaying[wc] then
          state.swaying[wc] = {
            phase = 0,
            speed = 0.15 + math.random() * 0.12,
            amp   = 1.0  + math.random() * 0.8,
          }
        end
      end

      -- Shimmer sweep
      state.shimmer_ttl = state.shimmer_ttl - 1
      if state.shimmer_ttl <= 0 then
        state.shimmer_col = 0
        state.shimmer_ttl = 60 + math.random(0, 30)
      end
      state.shimmer_col = (state.shimmer_col + 2) % state.max_x

      -- Fireflies drift
      for _, fly in ipairs(state.fireflies) do
        fly.phase = fly.phase + 0.35
        fly.x     = (fly.x + fly.vx + state.max_x) % state.max_x
      end

      -- Butterfly drift + vertical wobble
      local bf = state.butterfly
      if bf then
        bf.phase  = bf.phase  + 0.3
        bf.wobble = bf.wobble + 0.05
        bf.x      = bf.x + bf.vx
        local disp = math.floor(math.sin(bf.wobble) * 1.5 + 0.5)
        bf.effective_y = math.max(2, math.min(10, bf.y + disp))
        if bf.x > state.max_x + 3 then
          bf.x  = -3
          bf.vx = math.abs(bf.vx)
        elseif bf.x < -3 then
          bf.x  = state.max_x + 3
          bf.vx = -math.abs(bf.vx)
        end
      end

      -- Clouds drift slowly rightward
      for _, c in ipairs(state.clouds) do
        c.x = (c.x + 0.05) % (state.max_x + c.width + 8)
      end

      if not state.run_active then draw_grass_only() end
    end))
  end

  -- Re-trigger every 2–4 minutes (randomised each time)
  local tt = vim.uv.new_timer()
  state.trigger_timer = tt
  local function schedule_next()
    local delay = math.random(120000, 240000)
    state.next_trigger_at = vim.uv.now() + delay
    tt:start(delay, 0, vim.schedule_wrap(function()
      if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
        M.stop(); return
      end
      if not state.run_active then start_run(ms) end
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
    session_active      = state.trigger_timer ~= nil,
    run_active          = state.run_active,
    passes_done         = state.passes_done,
    passes_total        = state.passes_total,
    x                   = state.x,
    max_x               = state.max_x,
    left_w              = state.left_w,
    right_w             = state.right_w,
    tick                = state.tick,
    secs_until_next     = secs_until,
    grass_from_contribs = state.grass_from_contribs,
    grass_pat           = state.grass_pat,
    season              = state.season,
    night_mode          = state.night_mode,
  }
end

return M
