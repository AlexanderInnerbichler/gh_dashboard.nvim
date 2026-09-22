local M       = {}
local art     = require("gh_dashboard.duck.art")
local palette = require("gh_dashboard.duck.palette")
local scenes  = require("gh_dashboard.duck.scenes")
local P       = require("gh_dashboard.duck.particles")

local duck_ns = vim.api.nvim_create_namespace("GhDashboardDuck")

-- ── forward-declare state so all closures can reference it ─────────────────

local state

-- ── forward declarations (closures defined after state) ───────────────────

local sway
local grass_c
local sky_at
local air_at
local ground_at

-- ── geometry ─────────────────────────────────────────────────────

-- The strip used to be seven rows of two dots. The rows either side of the
-- heatmap were empty, so it takes ten now, and sextants carry three dots per
-- row instead of two: 20 x 30 dots a side where it was 20 x 14.
local ROWS    = 10
local DOTS_Y  = 3
M.PX          = ROWS * DOTS_Y

-- how tall the duck stands, and how much of that is legs
local DUCK_PX = 21
local LEGS_PX = 3
local DUCK_BODY_ROWS = DUCK_PX - LEGS_PX

--- Pixel row for the i-th dot of terminal row tr, i counting down from the top.
local function row_px(tr, i)
  return DOTS_Y * (ROWS - tr) + (DOTS_Y - 1 - i)
end

local function fg_eff_h(fh) return fh end

-- ── strip builders ────────────────────────────────────────────

--- Front to back: the snow falling over everything, the duck, what it walks
--- past, the ground, and whatever sits behind that. The scene is lit by one
--- warm window in an otherwise dark, cold picture -- that contrast is the whole
--- design, and it is why nothing else here competes for attention.
local function duck_dot(frame, legs_row, px, dc)
  if px < LEGS_PX then
    return legs_row and (legs_row[dc + 1] or 0) or 0
  end
  local row = frame and frame[DUCK_PX - px]
  return row and (row[dc + 1] or 0) or 0
end

local function dot_at(wc, px, frame, legs_row, duck_x, grass_h)
  local n = P.at(state.near_grid, wc, px)
  if n ~= 0 then return n end

  local dc = wc - duck_x
  if dc >= 0 and dc < art.DUCK_COLS then
    local v = duck_dot(frame, legs_row, px, dc)
    if v ~= 0 then return v end
  end

  local a = air_at(wc, px)
  if a ~= 0 then return a end
  local g = ground_at(wc, px)
  if g ~= 0 then return g end
  local gh = math.max(0, math.min(9, (grass_h[wc] or 0) + sway(wc)))
  if gh >= px + 1 then return grass_c(px, gh) end

  return sky_at(wc, px)
end

-- zone_start and zone_w are dot columns; every cell covers two of them and
-- three dot rows.
local function build_row_vt(frame, legs_row, tr, duck_x, zone_start, zone_w, grass_h)
  local p0, p1, p2 = row_px(tr, 0), row_px(tr, 1), row_px(tr, 2)
  local vt = {}
  for sc = 0, math.floor(zone_w / 2) - 1 do
    local w0 = zone_start + sc * 2
    local w1 = w0 + 1
    table.insert(vt, palette.cell6(
      dot_at(w0, p0, frame, legs_row, duck_x, grass_h),
      dot_at(w1, p0, frame, legs_row, duck_x, grass_h),
      dot_at(w0, p1, frame, legs_row, duck_x, grass_h),
      dot_at(w1, p1, frame, legs_row, duck_x, grass_h),
      dot_at(w0, p2, frame, legs_row, duck_x, grass_h),
      dot_at(w1, p2, frame, legs_row, duck_x, grass_h)))
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
  flowers             = {},
  grass_pat           = {},
  grass_from_contribs = false,
  passes_done         = 0,
  passes_total        = 2,
  run_active          = false,
  next_trigger_at     = nil,
  swaying             = {},
  sky                 = {},
  air                 = {},
  sky_grid            = {},
  air_grid            = {},
  near                = {},
  near_grid           = {},
  ground              = nil,
  ground_grid         = {},
  ground_bare         = {},
  amb_tick            = 0,
  scene_state         = {},
  wind_timer          = nil,
  -- new
  night_mode          = false,
  season              = "summer",
  override_night      = nil,    -- nil=auto, true/false=forced
  override_season     = nil,    -- nil=auto, or "spring"/"summer"/"autumn"/"winter"
  peck_ticks          = 0,
  force_peck          = false,
  rest_x              = -1,     -- x of sitting duck between runs (-1=none)
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

sway = function(wc)
  local s = state.swaying[wc]
  if not s then return 0 end
  return math.floor(math.sin(s.phase) * s.amp + 0.5)
end

local function scene()
  return scenes.get(state.season)
end

--- One band. Its height is still your contribution count; only the six tones
--- of texture inside it are gone.
grass_c = function(pixel_pos, gh)
  local g = scene().grass
  return pixel_pos >= gh - 1 and g[2] or g[1]
end

sky_at = function(wc, pixel_pos)
  return P.at(state.sky_grid, wc, pixel_pos)
end

--- Lying snow: a layer of its own, because it covers the ground rather than
--- growing out of it.
ground_at = function(wc, pixel_pos)
  local col = state.ground_grid[wc]
  return col and col[pixel_pos] or 0
end

air_at = function(wc, pixel_pos)
  return P.at(state.air_grid, wc, pixel_pos)
end

-- ── grass pattern ──────────────────────────────────────────────────────────

local function build_grass_pattern(contributions, max_x)
  if not contributions or not contributions.weeks then
    local pat = {}
    for sc = 0, max_x - 1 do
      pat[sc + 1] = art.GRASS_PAT[sc % art.GRASS_PAT_N + 1]
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
    local base   = art.TIER_TO_HEIGHT[tier] or 1
    local jitter = art.GRASS_PAT[sc % art.GRASS_PAT_N + 1] % 3 - 1
    pat[sc + 1] = math.max(3, math.min(9, base + jitter))
  end
  return pat, true
end

-- ── scene ────────────────────────────────────────────────────────

local function scene_ctx()
  return {
    max_x   = state.max_x,
    left_w  = state.left_w,
    right_w = state.right_w,
    night   = state.night_mode,
    grass_h = state.grass_h,
  }
end

--- Rebuild everything the season owns: its flowers, its sky and its weather.
local function build_scene()
  palette.set_night(state.night_mode)
  local ctx = scene_ctx()
  local sc  = scenes.get(state.season)
  state.scene_state = {}
  state.ground = sc.ground and sc.ground.init(ctx) or nil
  if state.ground then
    state.ground_grid, state.ground_bare = sc.ground.paint(ctx, state.ground)
  else
    state.ground_grid, state.ground_bare = {}, {}
  end
  local sky, air, near = sc.spawn(ctx)
  state.sky, state.air, state.near = sky, air, near or {}
  if sc.tick then sc.tick(ctx, state.scene_state, state.air) end
  state.sky_grid  = P.index(state.sky, state.max_x)
  state.air_grid  = P.index(state.air, state.max_x)
  state.near_grid = P.index(state.near, state.max_x)
end

--- One frame of weather. The grids are rebuilt once here instead of every
--- particle being rescanned for every cell the compositor touches.
local function advance_scene()
  local sc  = scenes.get(state.season)
  local ctx = scene_ctx()
  if state.ground and sc.ground then
    sc.ground.tick(ctx, state.ground)
    state.ground_grid, state.ground_bare = sc.ground.paint(ctx, state.ground)
  end
  state.amb_tick = state.amb_tick + 1
  P.tick(state.sky, state.max_x)
  P.tick(state.air, state.max_x)
  P.tick(state.near, state.max_x)
  if sc.tick then sc.tick(ctx, state.scene_state, state.air) end
  state.sky_grid  = P.index(state.sky, state.max_x)
  state.air_grid  = P.index(state.air, state.max_x)
  state.near_grid = P.index(state.near, state.max_x)
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
  local lw      = state.left_w
  local rw      = state.right_w
  -- sitting duck is visible between runs when rest_x >= 0
  local sc     = scenes.get(state.season)
  local duck_x = state.rest_x >= 0 and state.rest_x or -(art.DUCK_COLS + 1)
  local frame  = state.rest_x >= 0 and art.get_art(0, false, true) or nil
  if frame and sc.accessory then frame = art.dress(frame, sc.accessory(state.amb_tick)) end
  frame = frame and art.stretch(frame, DUCK_BODY_ROWS) or nil
  for tr = 1, ROWS do
    local line = state.base_line + tr - 2
    if line >= 0 and line < vim.api.nvim_buf_line_count(state.buf) then
      set_row(line,
        build_row_vt(frame, nil, tr, duck_x, 0,  lw, grass_h),
        build_row_vt(frame, nil, tr, duck_x, lw, rw, grass_h))
    end
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

  -- peck animation: head dips first half of peck_ticks, rises second half
  local pecking = state.peck_ticks > 6
  local sc      = scenes.get(state.season)
  local frame   = art.get_art(art.WING_SEQ[state.wing_step], pecking, false)
  if sc.accessory then frame = art.dress(frame, sc.accessory(state.tick)) end
  frame = art.stretch(frame, DUCK_BODY_ROWS)
  local legs    = art.LEGS[state.foot_frame]

  for tr = 1, ROWS do
    local line = state.base_line + tr - 2
    if line >= 0 and line < vim.api.nvim_buf_line_count(state.buf) then
      set_row(line,
        build_row_vt(frame, legs, tr, dx, 0,  lw, grass_h),
        build_row_vt(frame, legs, tr, dx, lw, rw, grass_h))
    end
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
  if state.tick % 24 == 0 then state.wing_step  = state.wing_step  % #art.WING_SEQ + 1 end
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
    string.format("  %-14s %d sky  %d air",   "scene",
      #(state.sky or {}), #(state.air or {})),
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
  build_scene()
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

-- ── theme preview ─────────────────────────────────────────────────

M.SEASONS = SEASON_CYCLE

--- Every theme the scene has: each season by day and by night.
M.THEMES = {}
for _, s in ipairs(SEASON_CYCLE) do
  for _, n in ipairs({ false, true }) do
    table.insert(M.THEMES, { season = s, night = n })
  end
end

local function theme_label(season, night)
  return season .. " " .. (night and "night" or "day")
end

local function running()
  return state.buf ~= nil and vim.api.nvim_buf_is_valid(state.buf)
end

--- A theme with no duck in it is not worth screenshotting, and the duck only
--- appears once a run has ended, so park it where the scene can be seen.
local function park_duck()
  if state.rest_x < 0 then
    state.rest_x = state.left_w + math.floor(state.right_w / 2)
  end
end

--- Force a theme. nil leaves that half alone, so "winter" keeps the clock in
--- charge of day and night. Returns the resulting label, "" with no dashboard.
M.set_theme = function(season, night)
  if not running() then return "" end
  if season ~= nil then state.override_season = season end
  if night  ~= nil then state.override_night  = night  end
  park_duck()
  apply_overrides_and_redraw()
  return theme_label(get_season(), is_night())
end

--- Step to the next of the eight themes.
M.next_theme = function()
  if not running() then return "" end
  local cur, idx = theme_label(get_season(), is_night()), 1
  for i, t in ipairs(M.THEMES) do
    if theme_label(t.season, t.night) == cur then idx = i break end
  end
  local t = M.THEMES[idx % #M.THEMES + 1]
  return M.set_theme(t.season, t.night)
end

--- Hand the scene back to the calendar and the clock.
M.auto_theme = function()
  if not running() then return "" end
  state.override_season = nil
  state.override_night  = nil
  apply_overrides_and_redraw()
  return theme_label(get_season(), is_night())
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
  local rw        = math.max(art.DUCK_COLS + 1, (win_width or 160) - hm_w)
  -- one cell is two dot columns wide; the world is measured in dots
  lw, rw          = lw * 2, rw * 2
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
    state.swaying             = {}
    for sc = 0, new_max_x - 1 do
      state.grass_h[sc]    = pat[sc + 1]
    end
    build_scene()
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
  palette.reset_cache()

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
      -- shut the whole thing down rather than just returning: a bare return
      -- left this waking the loop eight times a second for the rest of the
      -- session whenever the buffer went away without M.stop() being called
      if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
        M.stop(); return
      end

      -- Advance swaying blades; remove finished ones
      for wc, s in pairs(state.swaying) do
        s.phase = s.phase + s.speed
        if s.phase >= math.pi * 2 then state.swaying[wc] = nil end
      end

      -- Occasionally start a new blade. How often, and how hard, is the
      -- season's business: winter is nearly still, autumn gusts.
      local wind = scenes.WIND[state.season] or scenes.WIND.summer
      local n = 0
      for _ in pairs(state.swaying) do n = n + 1 end
      if n < wind.gusts and math.random() < wind.chance then
        local wc = math.random(0, state.max_x - 1)
        if not state.swaying[wc] then
          state.swaying[wc] = {
            phase = 0,
            speed = wind.speed + math.random() * 0.12,
            amp   = wind.amp   + math.random() * 0.8,
          }
        end
      end

      advance_scene()

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
      -- M.stop() can land between this timer firing and its callback running,
      -- and then tt is already closed; re-arming it would throw out of a
      -- scheduled callback
      if state.trigger_timer ~= tt then return end
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
