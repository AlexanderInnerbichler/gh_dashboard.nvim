local M   = {}
local art = require("gh_dashboard.duck.art")
local P   = require("gh_dashboard.duck.particles")

--- A season is a scene, and a scene is deliberately almost empty. The canvas is
--- about fifty cells by seven rows a side; the previous version put hills,
--- cloud, a six-tone grass ramp, silhouette blades, flowers, lying snow,
--- falling snow, stars and a shimmer into that and it came out as static.
--- What is left: one grass band whose height is still your contribution count,
--- one thing in the sky, one kind of weather, and the duck.
---
--- ctx = { max_x, left_w, right_w, night, grass_h }  -- widths in dot columns

-- ── shared ─────────────────────────────────────────────────────────────────

--- In the right half, because the tree stands in the left one and sits in the
--- layer in front of the sky -- at its old place the moon was simply behind it.
--- x even and y a multiple of three so it lands on the cell grid.
local function moon(out, ctx)
  table.insert(out, P.make({
    x = math.floor((ctx.left_w + ctx.right_w * 0.22) / 2) * 2,
    y = 21, sprite = art.MOON, wrap = "none",
  }))
end

local function sun(out, ctx)
  table.insert(out, P.make({
    x = math.floor(ctx.max_x * 0.80), y = 22, sprite = art.SUN, wrap = "none",
  }))
end

--- The centrepiece. One per zone, standing on the field, drawn large enough to
--- read at this size -- which is the whole point of the redesign.
local function trees(out, ctx, season, xs)
  local sprite = art.TREES[season]
  if not sprite then return end
  -- One, in the left panel. The heatmap splits the scene in two, and the same
  -- tree in both halves reads as repetition rather than as a wood; leaving the
  -- right half open snow gives the duck somewhere to walk.
  xs = xs or { ctx.left_w * 0.12 }
  for _, x in ipairs(xs) do
    -- x on an even column and y on a multiple of three: a cell spans two dot
    -- columns and three dot rows, and a sprite off that grid loses colours
    local ex = math.floor(x / 2) * 2
    if ex >= 0 and ex + art.TREE_W <= ctx.max_x then
      table.insert(out, P.make({ x = ex, y = 3, sprite = sprite, wrap = "none" }))
    end
  end
end

local function falling(out, ctx, n, spec)
  for _ = 1, n do
    table.insert(out, P.make({
      x      = math.random(0, ctx.max_x - 1),
      y      = math.random(0, 29),
      vy     = spec.vy,
      vx     = spec.vx(),
      color  = spec.color(),
      sprite = spec.sprite and spec.sprite(),
      frames = spec.frames,
      frame_rate = spec.frame_rate,
      bob    = spec.bob,
      wrap   = "fall",
    }))
  end
end

-- ── terrain ────────────────────────────────────────────────────────────────

local function triangle(x, period)
  local t = (x % period) / period
  return t < 0.5 and t * 2 or (1 - t) * 2
end

--- Winter's skyline: narrow summits, twice as many as a pair of sines gives.
--- Idle while the hills are off; the trees will want a horizon to stand on.
function M.jagged(sc)
  return math.max(6, math.min(13,
    math.floor(6 + triangle(sc, 34) * 6 + triangle(sc + 4, 14) * 2)))
end

-- ── the seasons ────────────────────────────────────────────────────────────

M.SEASONS = {

  spring = {
    grass = { 48, 50 },

    spawn = function(ctx)
      local sky, air = {}, {}
      trees(air, ctx, "spring")
      if ctx.night then moon(sky, ctx) end
      falling(air, ctx, 6, {
        vy = -0.12,
        vx = function() return 0.10 + math.random() * 0.08 end,
        color = function() return math.random() < 0.5 and 45 or 20 end,
        sprite = function() return art.PETAL end,
        bob = { amp = 1.2, rate = 0.16 },
      })
      falling(air, ctx, 10, {
        vy = -0.85,
        vx = function() return 0.18 end,
        color = function() return 19 end,
        sprite = function() return art.RAIN end,
      })
      return sky, air
    end,

    tick = function(ctx, ss, air)
      ss.shower = ((ss.shower or 0) + 0.9) % (ctx.max_x * 1.8)
      local from, to = ss.shower, ss.shower + math.floor(ctx.max_x * 0.28)
      for _, p in ipairs(air) do
        if p.color == 19 then p.band = { from = from, to = to } end
      end
    end,
  },

  summer = {
    grass = { 11, 13 },

    spawn = function(ctx)
      local sky, air = {}, {}
      trees(air, ctx, "summer")
      if ctx.night then moon(sky, ctx) else sun(sky, ctx) end
      if ctx.night then
        for _ = 1, 8 do
          table.insert(air, P.make({
            x = math.random(0, ctx.max_x - 1), y = math.random(6, 16),
            vx = (math.random() - 0.5) * 0.18,
            sprite = art.FIREFLY, color = 23,
            blink = { rate = 0.35, duty = 0.45, phase = math.random() * 6.28 },
          }))
        end
      else
        for i = 1, 2 do
          table.insert(air, P.make({
            x = math.random(0, ctx.max_x - 1), y = math.random(8, 18),
            vx = (i == 1 and 1 or -1) * (0.15 + math.random() * 0.12),
            frames = { art.BUTTERFLY_OPEN, art.BUTTERFLY_SHUT },
            frame_rate = 0.34,
            color = i == 1 and 19 or 21,
            bob = { amp = 1.5, rate = 0.12 },
          }))
        end
      end
      return sky, air
    end,
  },

  autumn = {
    grass = { 27, 29 },

    spawn = function(ctx)
      local sky, air = {}, {}
      trees(air, ctx, "autumn")
      if ctx.night then
        moon(sky, ctx)
      else
        local bx, by = math.random(0, ctx.max_x - 1), 24
        for _, off in ipairs({ { 0, 0 }, { -4, 1 }, { -8, 2 }, { 4, 1 }, { 8, 2 } }) do
          table.insert(air, P.make({
            x = bx + off[1], y = by + off[2],
            vx = 0.22,
            frames = { art.BIRD_UP, art.BIRD_DOWN },
            frame_rate = 0.22,
            color = 68,
          }))
        end
      end
      falling(air, ctx, 8, {
        vy = -0.28,
        vx = function() return (math.random() - 0.35) * 0.22 end,
        color = function() return ({ 27, 29, 30 })[math.random(1, 3)] end,
        frames = { art.LEAF_FLAT, art.LEAF_TILT, art.LEAF_EDGE, art.LEAF_TILT },
        frame_rate = 0.18,
        bob = { amp = 1.6, rate = 0.19 },
      })
      return sky, air
    end,
  },

  winter = {
    -- The field stays dark and low contrast so the lying snow and the fir have
    -- the picture to themselves.
    grass = { 91, 92 },

    ground = {
      init = function(ctx)
        local g = { cols = {} }
        for wc = 0, ctx.max_x - 1 do g.cols[wc] = { depth = 0 } end
        return g
      end,

      tick = function(ctx, g)
        for wc = 0, ctx.max_x - 1 do
          local c = g.cols[wc]
          -- drifts bank against the tall columns: the weeks you committed most
          -- hold the most snow
          local cap = 1 + math.min(3, math.floor((ctx.grass_h[wc] or 0) / 3))
          if c.depth < cap and math.random() < 0.02 then
            c.depth = c.depth + 1
          end
        end
      end,

      paint = function(ctx, g)
        local grid = {}
        for wc = 0, ctx.max_x - 1 do
          local d = g.cols[wc].depth
          if d > 0 then
            local col = {}
            local top = math.max(0, (ctx.grass_h[wc] or 0) - 1)
            for k = 0, d - 1 do col[top + k] = 71 end
            grid[wc] = col
          end
        end
        return grid, {}
      end,
    },

    accessory = function(tick)
      return art.SCARF[math.floor(tick / 6) % 2 + 1]
    end,

    spawn = function(ctx)
      local sky, air, near = {}, {}, {}
      trees(air, ctx, "winter")
      if ctx.night then moon(sky, ctx) end

      -- and the snow, over the top of all of it
      falling(near, ctx, 16, {
        vy = -0.16,
        vx = function() return (math.random() - 0.5) * 0.10 end,
        color = function() return 20 end,
        sprite = function() return math.random() < 0.3 and art.SNOW_L or art.SNOW_S end,
        bob = { amp = 0.8, rate = 0.09 },
      })
      return sky, air, near
    end,
  },
}

M.ORDER = { "spring", "summer", "autumn", "winter" }

function M.get(name)
  return M.SEASONS[name] or M.SEASONS.summer
end

M.WIND = {
  spring = { chance = 0.14, amp = 1.1, speed = 0.17, gusts = 3 },
  summer = { chance = 0.12, amp = 1.0, speed = 0.15, gusts = 3 },
  autumn = { chance = 0.30, amp = 1.9, speed = 0.24, gusts = 7 },
  winter = { chance = 0.05, amp = 0.5, speed = 0.10, gusts = 2 },
}

return M
