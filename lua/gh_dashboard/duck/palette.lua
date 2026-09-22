local M = {}

-- ── color palette ──────────────────────────────────────────────────
-- Each season owns a six-step background ramp (root → sunlit tip), a four-step
-- near-black ramp for the blades in front, a hill silhouette and a shimmer.
-- The table used to be capped at 63 entries, because the highlight cache packed
-- an index pair into fg * 64 + bg and a 64th colour made hl(0, 64) and hl(1, 0)
-- collide. M.hl keys on a string now, so the table can grow.

local COLORS = {
  "#b09060",  -- 1  outline
  "#ccb080",  -- 2  body
  "#cc6050",  -- 3  beak
  "#1e2127",  -- 4  eye
  "#b8bcc4",  -- 5  wing stripe
  "#b89472",  -- 6  feet / legs
  "#8a6438",  -- 7  deep shadow
  "#d8c08a",  -- 8  belly highlight

  -- summer: deep and saturated, the tip sunlit rather than neon
  "#1e5a26",  -- 9  summer root
  "#2b7a33",  -- 10 summer lower
  "#3a9440",  -- 11 summer mid
  "#4bb04e",  -- 12 summer upper
  "#5ecc5c",  -- 13 summer body
  "#86ec7e",  -- 14 summer tip
  "#0a1a0a",  -- 15 fg summer root
  "#102810",  -- 16 fg summer stem
  "#183a18",  -- 17 fg summer mid
  "#0e3218",  -- 18 fg summer tip

  "#5ba8d8",  -- 19 flower blue
  "#e8f0f8",  -- 20 flower white
  "#d94040",  -- 21 flower red
  "#b6ffa8",  -- 22 summer shimmer
  "#f5e050",  -- 23 firefly glow
  "#39414d",  -- 24 cloud

  -- autumn: rust up through gold, warmer and redder at the root
  "#3a1c0c",  -- 25 autumn root
  "#6b3312",  -- 26 autumn lower
  "#94501c",  -- 27 autumn mid
  "#bd7024",  -- 28 autumn upper
  "#dd9433",  -- 29 autumn body
  "#f5c55a",  -- 30 autumn tip
  "#180800",  -- 31 fg autumn root
  "#281000",  -- 32 fg autumn stem
  "#3a1c08",  -- 33 fg autumn mid
  "#1e0a00",  -- 34 fg autumn tip

  -- winter: blue-grey rather than flat grey, snow on top
  "#1b2430",  -- 35 winter root
  "#26333f",  -- 36 winter lower
  "#33434f",  -- 37 winter mid
  "#445563",  -- 38 winter upper
  "#7d93a0",  -- 39 winter body
  "#d6ecf5",  -- 40 winter tip (snow)
  "#070a0e",  -- 41 fg winter root
  "#0d1219",  -- 42 fg winter stem
  "#141d26",  -- 43 fg winter mid
  "#0a1119",  -- 44 fg winter tip

  "#f5a8c8",  -- 45 tulip pink

  -- spring: yellow-green and lighter than summer, new growth
  "#3f6b1f",  -- 46 spring root
  "#548a28",  -- 47 spring lower
  "#6aa832",  -- 48 spring mid
  "#84c43e",  -- 49 spring upper
  "#9fd94a",  -- 50 spring body
  "#c2f065",  -- 51 spring tip (new leaf)
  "#101a06",  -- 52 fg spring root
  "#16240a",  -- 53 fg spring stem
  "#1e3210",  -- 54 fg spring mid
  "#132a0c",  -- 55 fg spring tip

  "#1b2a16",  -- 56 spring hill
  "#16261a",  -- 57 summer hill
  "#241a10",  -- 58 autumn hill
  "#1c2430",  -- 59 winter hill

  "#e0ff9a",  -- 60 spring shimmer
  "#ffe08a",  -- 61 autumn shimmer
  "#f0ffff",  -- 62 winter shimmer

  -- sky
  "#ffe9a8",  -- 63 sun core
  "#ffc64e",  -- 64 sun rim
  "#e9eff8",  -- 65 moon lit
  "#c3cede",  -- 66 moon shadow
  "#dce8ff",  -- 67 star
  "#232831",  -- 68 bird silhouette

  -- winter: ice, lying snow, the scarf, the aurora, the snowman
  "#7fb6cf",  -- 69 pond ice
  "#cfe9f5",  -- 70 ice highlight
  "#e8f2fa",  -- 71 lying snow
  "#b9cddd",  -- 72 snow shadow / footprints
  "#c8434a",  -- 73 scarf
  "#8f2f36",  -- 74 scarf shadow
  "#6ef0b0",  -- 75 aurora green
  "#4fd0d8",  -- 76 aurora teal
  "#a98cf0",  -- 77 aurora violet
  "#1a1d22",  -- 78 coal
  "#e8792a",  -- 79 carrot

  "#4a3524",  -- 80 bark
  "#6b4e33",  -- 81 bark lit

  -- Depth bands. Each plane sits in its own luminance range so the planes can
  -- be told apart before any shape resolves; the last winter had five things
  -- all at 201-240 and turned to mush.
  "#171d25",  -- 82 sky, high        lum  28
  "#1f2733",  -- 83 sky, middle      lum  38
  "#28323f",  -- 84 sky, horizon     lum  49
  "#37444f",  -- 85 far range        lum  66
  "#8399ae",  -- 86 summit snow      lum 149
  "#0f141a",  -- 87 treeline         lum  19   darkest thing in the scene
  "#0a0d11",  -- 88 near branch      lum  13
  "#f4fbff",  -- 89 near snow        lum 250
  "#4d5a69",  -- 90 far snow         lum  88
  "#b9c9db",  -- 91 field            lum 198  Snow in daylight is blue-white
                  --                            and bright. This was neutral
                  --                            grey to stop it tinting the
                  --                            cabin, and the cabin is gone.
  "#d3e0ed",  -- 92 field, lit       lum 222

  -- Cozy: everything cold and dark except the window. The warm tones appear
  -- nowhere else in the scene, which is what makes the eye go there.
  "#272d36",  -- 93  cabin wall
  "#1a1f26",  -- 94  cabin wall, shadowed
  "#39414e",  -- 95  roof
  "#ffd07a",  -- 96  window, lit
  "#fff3cc",  -- 97  window, core
  "#141920",  -- 98  window, unlit (day)
  "#6e6354",  -- 99  lamplight on snow
  "#3f4652",  -- 100 smoke
  "#ffdf9a",  -- 101 lantern

  -- Log walls. Dark and drained of colour on purpose: wood is a warm tone by
  -- nature, and the scene only works while the window is the one warm thing in
  -- it. The two courses sit 22 apart in luminance, which is what makes the
  -- stacked logs read as stacked logs.
  "#96663f",  -- 102 log course, upper  lum 112  warmer and browner; the old
                  --                            tone drifted towards rose
  "#7f5634",  -- 103 log course, middle lum  94
  "#c2ccd6",  -- 104 corner trim        lum 202  white boards against the red
  "#32262b",  -- 105 door and eaves     lum  40
  "#141d1a",  -- 106 fir silhouette     lum 26
  "#56383a",  -- 107 roof and chimney   lum  65  dark, but red-brown not grey
  -- Weathering. Only ~15 either side of the wall tone: any more and scattered
  -- pixels stop reading as texture and start reading as dirt.
  "#c3a17b",  -- 108 log ends           lum 166  warm tan, not khaki
  "#684628",  -- 109 log course, lower  lum  77
  -- Wall the window light actually falls on, so the glow has somewhere to land
  "#b85a3e",  -- 110 wall, lit          lum 115  warm, not salmon
  "#313842",  -- 111 window, daylight   lum  55  glass in daylight is dark and
                  --                            reflects the sky, so it goes cool
                  --                            rather than warm
  -- a campfire beside the hut
  "#e0702f",  -- 112 flame, outer       lum 132
  "#ffc84a",  -- 113 flame, core        lum 190
  "#3a2820",  -- 114 fire logs          lum  43
  -- detail tones: the seam between log courses, the sunlit side of the wall,
  -- and the frames around the openings
  "#3d2a18",  -- 115 log seam            lum  46
  "#a87a4c",  -- 116 log course, sunlit  lum 131
  "#241a14",  -- 117 door / window frame lum  28
  -- spring blossom, five steps of one hue. Summer and autumn already had a
  -- full ramp in the palette; spring only had the one pink.
  "#ffe6f0",  -- 118 blossom, highlight  lum 236
  "#fcc9dd",  -- 119 blossom, light      lum 211
  "#d98cae",  -- 120 blossom, shadow     lum 155
  "#b06585",  -- 121 blossom, core       lum 118
}

-- Night used to remap four indices, two of which were summer grass — so an
-- autumn or winter night looked exactly like its day. Every colour now goes
-- through the same moonlight transform instead, and only the few things that
-- genuinely glow after dark are named here.
local NIGHT_EXCEPTIONS = {
  [4]  = "#080a0e",  -- eye stays a pit
  [20] = "#b9c9e4",  -- white petals catch the moon
  [22] = "#8fd0ff",  -- shimmer reads as a moonlight glint, not sunlight
  [23] = "#fff6a8",  -- fireflies burn brighter against the dark
  [40] = "#9ec4e0",  -- snow stays luminous under a moon
  [60] = "#8fd0ff",
  [61] = "#9ec0e8",
  [62] = "#dff2ff",
  -- the moon and the stars only ever come out at night; dimming them would be
  -- dimming the light source itself
  [65] = "#f2f7ff",
  [66] = "#cdd7e6",
  [67] = "#eaf2ff",
  [71] = "#c9d9ea",  -- lying snow keeps the moonlight
  [70] = "#a9c8dc",
  -- the aurora only ever burns at night; it is a light source, not a lit thing
  [75] = "#7cffc0",
  [76] = "#5fe4ec",
  [77] = "#bfa2ff",
  -- The depth bands are spaced by hand, and halving every one of them (which
  -- is what the transform does) collapses the far planes into each other after
  -- dark. Night gets its own spacing instead.
  [82] = "#0d1219",  -- sky, high        lum  17
  [83] = "#131a24",  -- sky, middle      lum  25
  [84] = "#1a232f",  -- sky, horizon     lum  34
  [85] = "#26303c",  -- far range        lum  46
  [86] = "#4e627a",  -- summit snow      lum  95
  [87] = "#070a0d",  -- treeline         lum  10
  [90] = "#3a4655",  -- far snow         lum  68
  [91] = "#2b3a52",  -- field            lum  56  moonlit blue, not grey
  [92] = "#3a4c68",  -- field, lit       lum  74
  -- The window is the light source. Dimming it the way the transform dims
  -- everything else would put out the only warm thing in the picture.
  [96]  = "#ffd88c",
  [97]  = "#fff8dd",
  [99]  = "#7d6f5c",
  [101] = "#ffe6ab",
  -- the timber keeps its warmth after dark instead of going blue-grey
  [102] = "#75502f",
  [103] = "#62442a",
  [108] = "#95795e",
  [109] = "#513821",
  [107] = "#40292b",
  [110] = "#c4643f",  -- lit wall, not painted wall -- but still wall
  -- a fire is a light source; dimming it after dark would be putting it out
  [112] = "#f07d38",
  [113] = "#ffd66a",
  [115] = "#2e2012",
  [116] = "#7f5c39",
  [117] = "#1b1410",
  [104] = "#8b96a3",  -- and the white trim goes to moonlit grey
}

local function clamp8(v)
  return math.max(0, math.min(255, math.floor(v + 0.5)))
end

--- Moonlight: pull most of the saturation out towards luminance, drop the
--- brightness hard, and leave a blue cast by keeping more blue than red.
local function moonlit(hex)
  local r = tonumber(hex:sub(2, 3), 16)
  local g = tonumber(hex:sub(4, 5), 16)
  local b = tonumber(hex:sub(6, 7), 16)
  local lum = 0.299 * r + 0.587 * g + 0.114 * b
  local function drain(c) return c * 0.45 + lum * 0.55 end
  return string.format("#%02x%02x%02x",
    clamp8(drain(r) * 0.42), clamp8(drain(g) * 0.50), clamp8(drain(b) * 0.78))
end

local night_cache = {}

local night_on    = false

--- The scene asks for colours by palette index; whether it is night is a
--- property of the palette, not of every call site.
function M.set_night(on)
  night_on = on and true or false
end

function M.is_night()
  return night_on
end

function M.color(idx)
  if not night_on then return COLORS[idx] end
  if NIGHT_EXCEPTIONS[idx] then return NIGHT_EXCEPTIONS[idx] end
  if not night_cache[idx] then night_cache[idx] = moonlit(COLORS[idx]) end
  return night_cache[idx]
end

M.SIZE = #COLORS

-- ── highlight cache ────────────────────────────────────────────────────────

local hl_cache = {}
local hl_count = 0

--- A highlight per (fg, bg, night) triple. Keyed by string rather than packed
--- bits: the old fg * 64 + bg packing capped the palette at 63 colours and
--- collided silently past that.
function M.hl(fg_idx, bg_idx)
  local key = fg_idx .. ":" .. bg_idx .. ":" .. (night_on and "n" or "d")
  if hl_cache[key] then return hl_cache[key] end
  hl_count = hl_count + 1
  local name = "GhDuckPx" .. hl_count
  vim.api.nvim_set_hl(0, name, {
    fg = fg_idx ~= 0 and M.color(fg_idx) or nil,
    bg = bg_idx ~= 0 and M.color(bg_idx) or nil,
  })
  hl_cache[key] = name
  return name
end

function M.reset_cache()
  hl_cache  = {}
  hl_count  = 0
end

-- ── cell builder ─────────────────────────────────────────────────

local TRANSPARENT = { " ", "NormalFloat" }

-- Sextants: a 2x3 dot grid per cell, so half again the vertical resolution of
-- the quadrants. Unicode assigns U+1FB00..U+1FB3B to the patterns that do not
-- already exist as block elements -- 21, 42 and 63 being the left half, the
-- right half and the full block. Bits: 1 top-left, 2 top-right, 4 middle-left,
-- 8 middle-right, 16 bottom-left, 32 bottom-right.
local SEXT = { [0] = " " }
do
  local cp = 0x1FB00
  for v = 1, 62 do
    if v == 21 then
      SEXT[v] = "▌"
    elseif v == 42 then
      SEXT[v] = "▐"
    else
      SEXT[v] = vim.fn.nr2char(cp)
      cp = cp + 1
    end
  end
  SEXT[63] = "█"
end

--- Six dots, one cell. The non-zero colour on
--- the most dots is the foreground, the most common of the rest is the ground.
function M.cell6(a, b, c, d, e, f)
  if a == 0 and b == 0 and c == 0 and d == 0 and e == 0 and f == 0 then
    return TRANSPARENT
  end
  local function count(v)
    return (a == v and 1 or 0) + (b == v and 1 or 0) + (c == v and 1 or 0)
         + (d == v and 1 or 0) + (e == v and 1 or 0) + (f == v and 1 or 0)
  end
  local fg, n = 0, 0
  for _, v in ipairs({ a, b, c, d, e, f }) do
    if v ~= 0 then local t = count(v) if t > n then fg, n = v, t end end
  end
  local mask = (a == fg and 1 or 0) + (b == fg and 2 or 0) + (c == fg and 4 or 0)
             + (d == fg and 8 or 0) + (e == fg and 16 or 0) + (f == fg and 32 or 0)
  if mask == 63 then return { "█", M.hl(fg, 0) } end
  local bg, m = 0, 0
  for _, v in ipairs({ a, b, c, d, e, f }) do
    if v ~= fg then local t = count(v) if t > m then bg, m = v, t end end
  end
  return { SEXT[mask], M.hl(fg, bg) }
end


return M
