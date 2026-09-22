local M = {}

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
local TIER_TO_HEIGHT = { 3, 4, 6, 7, 9, 9 }

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

-- ── pixel art helper ───────────────────────────────────────────────────────

local function get_art(wing_frame, pecking, sitting)
  local head = pecking and HEAD_PECK or HEAD
  local body = sitting and BODY_SIT or BODY[wing_frame]
  local art  = {}
  for _, row in ipairs(head) do table.insert(art, row) end
  for _, row in ipairs(body) do table.insert(art, row) end
  return art
end
M.get_art = get_art

--- Nearest-neighbour vertical stretch, so the duck keeps its height in a strip
--- whose rows now hold three dots instead of two.
function M.stretch(frame, n)
  local out, h = {}, #frame
  for i = 0, n - 1 do out[i + 1] = frame[math.floor(i * h / n) + 1] end
  return out
end


-- ── scene sprites ──────────────────────────────────────────────────────────
-- Relative to the particle's anchor: sprite[dx][dy], dx rightward, dy upward,
-- matching pixel_pos (0 = ground, 13 = sky). `true` paints the particle's own
-- colour; a number is a fixed palette index, for sprites that carry more.

-- clouds: anchored at their lowest row
local CLOUD_A = {
  [0] = { [0]=true },
  [1] = { [0]=true, [1]=true },
  [2] = { [0]=true, [1]=true },
  [3] = { [0]=true, [1]=true },
  [4] = { [0]=true, [1]=true },
  [5] = { [0]=true, [1]=true },
  [6] = { [0]=true },
}
local CLOUD_B = {
  [0] = { [0]=true },
  [1] = { [0]=true, [1]=true },
  [2] = { [0]=true, [1]=true },
  [3] = { [0]=true },
}
-- spring: thin and high, a single torn line
local CLOUD_THIN = {
  [0] = { [0]=true }, [1] = { [0]=true }, [2] = { [0]=true },
  [4] = { [0]=true }, [5] = { [0]=true },
}
-- summer: few, fat, piled up
local CLOUD_FAT = {
  [0] = { [0]=true },
  [1] = { [0]=true, [1]=true },
  [2] = { [0]=true, [1]=true, [2]=true },
  [3] = { [0]=true, [1]=true, [2]=true },
  [4] = { [0]=true, [1]=true, [2]=true },
  [5] = { [0]=true, [1]=true },
  [6] = { [0]=true, [1]=true },
  [7] = { [0]=true },
}
-- autumn: drawn out by the wind
local CLOUD_STREAK = {
  [0] = { [0]=true }, [1] = { [0]=true }, [2] = { [0]=true, [1]=true },
  [3] = { [0]=true, [1]=true }, [4] = { [0]=true, [1]=true },
  [5] = { [0]=true }, [6] = { [0]=true }, [7] = { [0]=true },
  [8] = { [0]=true }, [9] = { [0]=true },
}
-- winter: a flat overcast lid
local CLOUD_BAND = {}
for dx = 0, 15 do
  CLOUD_BAND[dx] = { [0]=true, [1]=true }
end

local SUN = {
  [0] = {         [1]=64, [2]=64, [3]=64         },
  [1] = { [0]=64, [1]=63, [2]=63, [3]=63, [4]=64 },
  [2] = { [0]=64, [1]=63, [2]=63, [3]=63, [4]=64 },
  [3] = { [0]=64, [1]=63, [2]=63, [3]=63, [4]=64 },
  [4] = {         [1]=64, [2]=64, [3]=64         },
}

local MOON = {
  [0] = {         [1]=65, [2]=65, [3]=65         },
  [1] = { [0]=65, [1]=65, [2]=65, [3]=65, [4]=65 },
  [2] = { [0]=65, [1]=66, [2]=66, [3]=66, [4]=65 },
  [3] = {         [1]=66, [2]=66, [3]=65         },
}

local STAR     = { [0] = { [0]=true } }
local STAR_BIG = { [0] = { [1]=true },
                   [1] = { [0]=true, [1]=true, [2]=true },
                   [2] = { [1]=true } }

-- a migrating V, wings up and wings down
local BIRD_UP   = { [0] = { [1]=true }, [1] = { [0]=true }, [2] = { [1]=true } }
local BIRD_DOWN = { [0] = { [0]=true }, [1] = { [1]=true }, [2] = { [0]=true } }

local BUTTERFLY_OPEN = { [0] = { [1]=true },
                         [1] = { [0]=true, [1]=true },
                         [2] = { [1]=true } }
local BUTTERFLY_SHUT = { [1] = { [0]=true, [1]=true } }

local BEE = { [0] = { [0]=23 }, [1] = { [0]=4 } }

local FIREFLY = { [0] = { [0]=true } }

local SNOW_S = { [0] = { [0]=true } }
local SNOW_L = { [0] = { [0]=true }, [1] = { [0]=true } }

-- three frames of a leaf turning over as it falls
local LEAF_FLAT = { [0] = { [0]=true }, [1] = { [0]=true } }
local LEAF_TILT = { [0] = { [0]=true }, [1] = { [1]=true } }
local LEAF_EDGE = { [0] = { [0]=true, [1]=true } }

local PETAL = { [0] = { [0]=true } }

local RAIN = { [0] = { [1]=true }, [1] = { [0]=true } }

-- ── winter ─────────────────────────────────────────────────────────────────

-- Accessories overlay the duck sprite: overlay[row][col] = palette index, in
-- the same 12 x 14 grid get_art returns. Two frames, so the tail flutters.
local SCARF = {
  {
    [6] = { [5]=73, [6]=73, [7]=73, [8]=73, [9]=73 },
    [7] = { [1]=74, [2]=73, [3]=73 },
    [8] = { [1]=74 },
  },
  {
    [5] = { [3]=74, [4]=74 },
    [6] = { [5]=73, [6]=73, [7]=73, [8]=73, [9]=73 },
    [7] = { [1]=73, [2]=73, [3]=73 },
  },
}

--- Apply an accessory without touching the source art: get_art hands back the
--- same row tables every call, so the rows an overlay writes to are copied.
local function dress(frame, overlay)
  if not overlay then return frame end
  local out = {}
  for i, row in ipairs(frame) do
    local o = overlay[i]
    if o then
      local copy = {}
      for c = 1, #row do copy[c] = row[c] end
      for c, v in pairs(o) do copy[c] = v end
      out[i] = copy
    else
      out[i] = row
    end
  end
  return out
end

-- rolled, stacked, finished: coal eyes and a carrot
local SNOWMAN = {
  {
    [0] = { [0]=71 },
    [1] = { [0]=71, [1]=71 },
    [2] = { [0]=71, [1]=71 },
    [3] = { [0]=71, [1]=71 },
    [4] = { [0]=71 },
  },
  {
    [0] = { [0]=71, [1]=71 },
    [1] = { [0]=71, [1]=71, [2]=71, [3]=71 },
    [2] = { [0]=71, [1]=71, [2]=71, [3]=71 },
    [3] = { [0]=71, [1]=71, [2]=71, [3]=71 },
    [4] = { [0]=71, [1]=71 },
  },
  {
    [0] = { [0]=71, [1]=71 },
    [1] = { [0]=71, [1]=71, [2]=71, [3]=71, [4]=78 },
    [2] = { [0]=71, [1]=71, [2]=71, [3]=71, [4]=71 },
    [3] = { [0]=71, [1]=71, [2]=71, [3]=71, [4]=78 },
    [4] = { [0]=71, [1]=71,                 [4]=79 },
  },
}

-- The ribbon's silhouette is hand-drawn: one height per column, looped. The
-- three colour bands are filled underneath it.
local AURORA_WAVE = { 0,1,1,2,2,3,3,2,2,1,1,0,0,1,2,2,3,3,2,1,1,0,0,1 }

local function aurora_frame(offset)
  local sprite, n = {}, #AURORA_WAVE
  for dx = 0, n - 1 do
    local y = AURORA_WAVE[(dx + offset) % n + 1]
    sprite[dx] = { [y] = 75, [y + 1] = 76, [y + 2] = 77 }
  end
  return sprite
end

local AURORA = { aurora_frame(0), aurora_frame(2), aurora_frame(4), aurora_frame(2) }

-- ── buildings ─────────────────────────────────────────────────

--- Rows to a sprite with an arbitrary legend. dy counts up from the ground, so
--- the rows come in bottom-first.
local function from_rows(rows, legend_map)
  local sprite, h = {}, #rows
  for r, line in ipairs(rows) do
    local dy = h - r
    for dx = 0, #line - 1 do
      local c = legend_map[line:sub(dx + 1, dx + 1)]
      if c then
        sprite[dx] = sprite[dx] or {}
        sprite[dx][dy] = c
      end
    end
  end
  return sprite
end

-- A log cabin, 44 x 21 dots, drawn with real detail rather than flat shapes.
--
-- Each course is three rows: a dark seam along the top, then two of body. That
-- is what makes the logs read as stacked. Across the wall the body runs shadow
-- on the left, plain in the middle, sunlit on the right. The window has a frame
-- and a centre mullion; the door has a frame and a handle. The sawn log ends
-- stand proud of the corners, further on alternate courses.
--
-- A cell is two dots wide and three tall and carries two colours, so every
-- block is two dots wide on an even column and the seam sits on the top row of
-- each group -- exactly where a cell can afford its second colour.
--
-- s seam, % shadowed body, # body, ^ sunlit body, L log ends, f/d frames,
-- W window, D door, h handle, = roof, e eaves, * snow, C chimney.
local CABIN_ROWS = {
  "                    ****    CC              ",
  "                  ********  CC              ",
  "                ************CC              ",
  "              ================              ",
  "            ====================            ",
  "          ========================          ",
  "        ============================        ",
  "      ================================      ",
  "  eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee    ",
  "    LLssssssssssssssssssssssssssssssssLL    ",
  "    LL%%%%########################^^^^LL    ",
  "    LL%%%%########################^^^^LL    ",
  "  LLLLssssssssssssssssffffffffffffffssLLLL  ",
  "  LLLL%%%%############ffWWWWffWWWWff^^LLLL  ",
  "  LLLL%%%%############ffWWWWffWWWWff^^LLLL  ",
  "    LLssssddddddddssssssssssssssssssssLL    ",
  "    LL%%%%ddDDhhdd################^^^^LL    ",
  "    LL%%%%ddDDhhdd################^^^^LL    ",
  "  LLLLssssddddddddssssssssssssssssssssLLLL  ",
  "  LLLL%%%%ddDDDDdd################^^^^LLLL  ",
  "  LLLL%%%%ddDDDDdd################^^^^LLLL  ",
}

local LANTERN_ROWS = {
  "  **  ",
  "  ==  ",
  " #LL# ",
  " #LL# ",
  "  ##  ",
  "  ##  ",
  "  ##  ",
  "  ##  ",
  "  ##  ",
  " #### ",
}

local COLD = { ["#"] = 102, ["%"] = 103, ["^"] = 116, ["s"] = 115,
               ["L"] = 108, ["f"] = 117, ["d"] = 117, ["D"] = 105, ["h"] = 108,
               ["="] = 107, ["e"] = 105, ["*"] = 71,  ["C"] = 107 }

local function legend(extra)
  local l = {}
  for k, v in pairs(COLD)  do l[k] = v end
  for k, v in pairs(extra) do l[k] = v end
  return l
end

-- Lit by night; by day the glass is dark, as real glass is.
M.CABIN_NIGHT   = from_rows(CABIN_ROWS,   legend({ W = 96 }))
M.CABIN_DAY     = from_rows(CABIN_ROWS,   legend({ W = 111 }))
-- on the lantern, L is the lamp rather than a log end
M.LANTERN_NIGHT = from_rows(LANTERN_ROWS, legend({ L = 101, ["#"] = 107, ["="] = 107 }))
M.LANTERN_DAY   = from_rows(LANTERN_ROWS, legend({ L = 111, ["#"] = 107, ["="] = 107 }))

-- A campfire, two frames so it flickers. F outer flame, f core, L the logs.
local FIRE_A = {
  "    FF    ",
  "  FFFFFF  ",
  "  FFffFF  ",
  "  ffffff  ",
  "LLffffffLL",
  "LLLLLLLLLL",
}
local FIRE_B = {
  "      FF  ",
  "  FFFFFF  ",
  "  FFFFff  ",
  "  ffffff  ",
  "LLffffffLL",
  "LLLLLLLLLL",
}
local FIRE_LEGEND = { F = 112, f = 113, L = 114 }
M.FIRE   = { from_rows(FIRE_A, FIRE_LEGEND), from_rows(FIRE_B, FIRE_LEGEND) }
M.FIRE_W = 10
M.SMOKE  = { [0] = { [0] = true } }

-- ── trees ─────────────────────────────────────────────────────────
-- One big subject per season, drawn straight onto the 2x2 dot grid. Written as
-- rows so the shape is legible in the source: # is the body, * the lit top,
-- | the trunk. Row 1 is the crown; the last row sits on the ground.

-- The trees, 28 x 24 dots.
--
-- The crown is shaded as a sphere lit from the upper left: the highlight is a
-- patch off to one side, not a band across the full width. Banding it
-- horizontally is why the old one read as a lollipop. Five tones of the same
-- hue stepping down in brightness -- a shadow that changes hue is not a shadow,
-- it is a different material.
--
-- The silhouette is drawn per dot so the edge stays fine, while the tone is
-- picked per cell. A cell is two dots by three and holds two colours; doing it
-- the other way round puts three tones in a cell and one gets dropped.

local TREE_SUMMER = {
  "      BBBBBBLL LLLHHHHH     ",
  "    SSBBBBBBLLLLLLHHHHHH    ",
  "   SSSBBBBBBLLLLLLHHHHHHH   ",
  "  SSSSBBBBBBLLLLHHHHHHHHHH  ",
  "  SSSSBBBBBBLLLLHHHHHHHHHH  ",
  " CSSSSBBBBBBLLLLHHHHHHHHHH  ",
  " CSSSSSSBBBBBBLLLLLLLLLLLL  ",
  " CSSSSSSBBBBBBLLLLLLLLLLLL  ",
  " CSSSSSSBBBBBBLLLLLLLLLLLL  ",
  " CCCSSSSSSBBBBBBBBBBBBBBBB  ",
  " CCCSSSSSSBBBBBBBBBBBBBBBBB ",
  "CCCCSSSSSSBBBBBBBBBBBBBBBBB ",
  "  CCCCCCSSSSSSSSSSSSSSSSSSS ",
  "   CCCCCSSSSSSSSSSSSSSSSSSS ",
  "   C   CSSSSSSSSSSSSSSSSSSS ",
  "       CCCCCCCCCCCSSSSSSS   ",
  "        CCCCCCCCCC  SSSS    ",
  "         CCCCCCC            ",
  "            ||!!            ",
  "            ||!!            ",
  "            ||!!            ",
  "          ||||!!!!          ",
  "          ||||!!!!          ",
  "          ||||!!!!          ",
}

-- A fir carries its snow in layers, so the bands alternate instead of shading
-- from top to bottom.
local TREE_SPRING = {
  "        BB      LLHHH       ",
  "     SBBBBBB  LLLLHHHHH     ",
  "    SSBBBBBBLLLLLLHHHHHH    ",
  "   SSSBBBBBBLLLLHHHHHHHHH   ",
  "   SSSBBBBBBLLLLHHHHHHHHH   ",
  "  SSSSBBBBBBLLLLHHHHHHHHHH  ",
  "  SSSSSSBBBBB  LLLLLLLLLL   ",
  "   SSSSSBBBB    LLLLLLLLL   ",
  "   SSSSSBBBB    LLLLLLLLL   ",
  "   CSSSSSSBBB  BBBB  BBBBB  ",
  "    SS  SSBBBBBBBBB  BBBBB  ",
  "    SS  SSBBBBBBBBBBBBBBBB  ",
  "     CCCSSSSSSSSSS SSSSSSS  ",
  "        SSSSSSSSSS SSSSSS   ",
  "       CSSSSSSSSSSSS SSS    ",
  "         CCCCCCCC           ",
  "          CCCCCC            ",
  "            CCC             ",
  "            ||!!            ",
  "            ||!!            ",
  "            ||!!            ",
  "          ||||!!!!          ",
  "          ||||!!!!          ",
  "          ||||!!!!          ",
}

local TREE_AUTUMN = {
  "        B                   ",
  "    SSBBBBB      LHHHH      ",
  "    SSBBBBBB  LLLLHHHHHH    ",
  "   SSSBBBBBBL LLHHHHHHHH    ",
  "   SSSBBBBBBL LLHHHHHHHH    ",
  "  SSSSBBBBBB  LLHHHHHHHHH   ",
  "  SSSSSSBBB    LLLLLLLLLL   ",
  "  SSSSSSBBB    LLLLLLLLLL   ",
  "  SSSSSSBBBB  LLLLLLLLLLL   ",
  "  CCS  SSSBBBBBBBBBBBBBBBB  ",
  "   CS  SSSBBBBBBBBBB  BBBB  ",
  "    SSSSSSBBBBBBBBB    BBB  ",
  "    CCCCSSSSSSSSSSS    SSSS ",
  "        SSSSSSS  S    SSSSS ",
  "         SSSSSS  S   SSSSS  ",
  "          CCCCCCC     SS    ",
  "          CCCCCC            ",
  "             C              ",
  "            ||!!            ",
  "            ||!!            ",
  "            ||!!            ",
  "          ||||!!!!          ",
  "          ||||!!!!          ",
  "          ||||!!!!          ",
}

local TREE_BARE = {
  "                            ",
  "                            ",
  "        ssss    ssss        ",
  "          b       b         ",
  "         bb       bb        ",
  "    ssss  bbssss bb ssss    ",
  "     b     b     b     b    ",
  "      b     b   b     b     ",
  "       bss  b bbb ss b      ",
  "       bb    bss    bbb     ",
  "       bbbb  bbb   bbb      ",
  "    ssb   bb  bbssbb  b ss  ",
  "    bb     bb ss bb    bb   ",
  "            bbbbbb          ",
  "              bb            ",
  "              ss            ",
  "              bb            ",
  "              bb            ",
  "            ||!!            ",
  "            ||!!            ",
  "            ||!!            ",
  "          ||||!!!!          ",
  "          ||||!!!!          ",
  "          ||||!!!!          ",
}

--- Five tones of one hue: highlight, light, body, shadow, core shadow.
local function season_tree(rows, h, l, b, sh, c)
  return from_rows(rows, { H = h, L = l, B = b, S = sh, C = c,
                           t = 80, ["|"] = 80, ["!"] = 81 })
end

M.TREE_W, M.TREE_H = 28, 24

M.TREES = {
  -- one crown per season: summer full and broad, spring airier with gaps,
  -- autumn thinned and ragged. t is bare branch showing through a gap.
  spring = season_tree(TREE_SPRING, 118, 119,  45, 120, 121),
  summer = season_tree(TREE_SUMMER,  13,  12,  11,  10,   9),
  autumn = season_tree(TREE_AUTUMN,  30,  29,  28,  27,  26),
  -- winter is the same tree stripped bare, with snow along the branches
  winter = from_rows(TREE_BARE, { b = 80, s = 71, ["|"] = 80, ["!"] = 81 }),
}

-- ── resolution ─────────────────────────────────────────────────────────────
-- The renderer moved from 1x2 half blocks to a 2x2 dot grid, so everything
-- drawn for the old grid is widened once here and comes out looking identical.
-- New art is drawn straight onto the finer grid and skips this.

local function wide_rows(rows)
  local out = {}
  for i, row in ipairs(rows) do
    local r = {}
    for c = 1, #row do r[c * 2 - 1] = row[c]; r[c * 2] = row[c] end
    out[i] = r
  end
  return out
end

local function wide_sprite(sp)
  local out = {}
  for dx, col in pairs(sp) do
    out[dx * 2]     = col
    out[dx * 2 + 1] = col
  end
  return out
end

local function wide_overlay(ov)
  local out = {}
  for row, cols in pairs(ov) do
    local r = {}
    for c, v in pairs(cols) do r[c * 2 - 1] = v; r[c * 2] = v end
    out[row] = r
  end
  return out
end

HEAD      = wide_rows(HEAD)
HEAD_PECK = wide_rows(HEAD_PECK)
BODY_SIT  = wide_rows(BODY_SIT)
for k, frame in pairs(BODY) do BODY[k] = wide_rows(frame) end
for k, row in pairs(LEGS) do
  local r = {}
  for c = 1, #row do r[c * 2 - 1] = row[c]; r[c * 2] = row[c] end
  LEGS[k] = r
end
for i, ov in ipairs(SCARF) do SCARF[i] = wide_overlay(ov) end
DUCK_COLS = DUCK_COLS * 2

for _, sp in ipairs({ CLOUD_A, CLOUD_B, CLOUD_THIN, CLOUD_FAT, CLOUD_STREAK,
                      CLOUD_BAND, SUN, MOON, STAR_BIG, BIRD_UP, BIRD_DOWN,
                      BUTTERFLY_OPEN, BUTTERFLY_SHUT, BEE, SNOW_L, LEAF_FLAT,
                      LEAF_TILT, LEAF_EDGE, RAIN }) do
  local w = wide_sprite(sp)
  for k in pairs(sp) do sp[k] = nil end
  for k, v in pairs(w) do sp[k] = v end
end
for i, f in ipairs(SNOWMAN) do SNOWMAN[i] = wide_sprite(f) end
for i, f in ipairs(AURORA)  do AURORA[i]  = wide_sprite(f) end

M.wide_sprite     = wide_sprite

M.SCARF           = SCARF
M.dress           = dress
M.SNOWMAN         = SNOWMAN
M.AURORA          = AURORA

M.HEAD            = HEAD
M.LEGS            = LEGS
M.WING_SEQ        = WING_SEQ
M.DUCK_COLS       = DUCK_COLS
M.GRASS_PAT       = GRASS_PAT
M.GRASS_PAT_N     = GRASS_PAT_N
M.FG_BLADE_PAT    = FG_BLADE_PAT
M.FG_BLADE_PAT_N  = FG_BLADE_PAT_N
M.TIER_TO_HEIGHT  = TIER_TO_HEIGHT
M.DAISY_SHAPE     = DAISY_SHAPE
M.STAR_SHAPE      = STAR_SHAPE
M.TULIP_SHAPE     = TULIP_SHAPE

M.CLOUD_A         = CLOUD_A
M.CLOUD_B         = CLOUD_B
M.CLOUD_THIN      = CLOUD_THIN
M.CLOUD_FAT       = CLOUD_FAT
M.CLOUD_STREAK    = CLOUD_STREAK
M.CLOUD_BAND      = CLOUD_BAND
M.SUN             = SUN
M.MOON            = MOON
M.STAR            = STAR
M.STAR_BIG        = STAR_BIG
M.BIRD_UP         = BIRD_UP
M.BIRD_DOWN       = BIRD_DOWN
M.BUTTERFLY_OPEN  = BUTTERFLY_OPEN
M.BUTTERFLY_SHUT  = BUTTERFLY_SHUT
M.BEE             = BEE
M.FIREFLY         = FIREFLY
M.SNOW_S          = SNOW_S
M.SNOW_L          = SNOW_L
M.LEAF_FLAT       = LEAF_FLAT
M.LEAF_TILT       = LEAF_TILT
M.LEAF_EDGE       = LEAF_EDGE
M.PETAL           = PETAL
M.RAIN            = RAIN

return M
