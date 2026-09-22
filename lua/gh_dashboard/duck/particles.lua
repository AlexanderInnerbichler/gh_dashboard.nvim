local M = {}

--- Everything that moves over the scene — clouds, snow, leaves, petals, rain,
--- fireflies, butterflies, birds, the sun and the moon — is one of these.
--- Three hand-written systems used to do this, each with its own lookup that
--- scanned every instance for every cell on every frame.
---
---   x, y        world column, pixel row (0 = ground, 13 = sky)
---   vx, vy      drift per tick
---   sprite      a table from art.lua
---   frames      animation frames, used instead of sprite
---   frame_rate  how fast to step through them
---   color       palette index painted wherever the sprite says `true`
---   wrap        "x" (default) wraps around the world
---               "fall" also respawns at the top once it lands
---               "none" stays put
---   bob         { amp, rate } vertical wander, for things that fly
---   blink       { rate, duty, phase } on only part of the time
---   floor       pixel row a falling particle lands on (default 0)
---   band        { from, to } columns a falling particle respawns within

local TOP = 29

function M.make(p)
  p.x      = p.x or 0
  p.y      = p.y or 0
  p.phase  = p.phase or math.random() * 64
  p.draw_y = p.y
  return p
end

local function sprite_of(p)
  if not p.frames then return p.sprite end
  local i = math.floor(p.phase * (p.frame_rate or 0.5)) % #p.frames + 1
  return p.frames[i]
end

local function visible(p)
  if not p.blink then return true end
  return math.sin(p.phase * p.blink.rate + (p.blink.phase or 0)) > (p.blink.duty or 0.45)
end

local function respawn(p, max_x)
  p.y = TOP + math.random(0, 2)
  local from = p.band and p.band.from or 0
  local to   = p.band and p.band.to   or (max_x - 1)
  if to < from then from, to = 0, max_x - 1 end
  p.x = math.random(math.floor(from), math.floor(to)) % max_x
end

function M.tick(list, max_x)
  for _, p in ipairs(list) do
    p.phase = p.phase + 1
    p.x = p.x + (p.vx or 0)
    p.y = p.y + (p.vy or 0)
    p.draw_y = p.bob and (p.y + math.sin(p.phase * p.bob.rate) * p.bob.amp) or p.y
    if p.wrap ~= "none" then
      p.x = (p.x % max_x + max_x) % max_x
    end
    if p.wrap == "fall" and p.y <= (p.floor or 0) then
      respawn(p, max_x)
    end
  end
end

--- Flatten the list into grid[column][pixel] = palette index, once per frame,
--- so the compositor can ask about a cell in one lookup instead of scanning.
function M.index(list, max_x)
  local grid = {}
  for _, p in ipairs(list) do
    local sp = visible(p) and sprite_of(p) or nil
    if sp then
      local px = math.floor(p.x)
      local py = math.floor(p.draw_y or p.y)
      for dx, col in pairs(sp) do
        local wc  = (px + dx) % max_x
        local row = grid[wc]
        if not row then row = {}; grid[wc] = row end
        for dy, c in pairs(col) do
          local y = py + dy
          if y >= 0 and y <= TOP then
            row[y] = (c == true) and p.color or c
          end
        end
      end
    end
  end
  return grid
end

function M.at(grid, wc, pixel)
  local row = grid[wc]
  return row and row[pixel] or 0
end

return M
