local M     = {}
local fetch = require("gh_dashboard.diff.fetch")

--- Pending comments, one queue per pull request. A single shared queue meant
--- glancing at a second PR mid-review silently threw away everything already
--- written, so every entry point addresses its queue by key.
local queues = {}

function M.key(repo, number)
  return repo .. "#" .. tostring(number)
end

local function queue(key)
  queues[key] = queues[key] or {}
  return queues[key]
end

-- ── pending comments ───────────────────────────────────────────────────────

function M.all(key)
  return queue(key)
end

function M.count(key)
  return #queue(key)
end

function M.clear(key)
  queues[key] = {}
end

function M.add(key, comment)
  table.insert(queue(key), comment)
end

function M.for_path(key, path)
  local out = {}
  for _, c in ipairs(queue(key)) do
    if c.path == path then table.insert(out, c) end
  end
  return out
end

--- Drop the pending comment anchored at path/line/side. Returns true if removed.
function M.remove(key, path, line, side)
  local list = queue(key)
  for i, c in ipairs(list) do
    if c.path == path and c.line == line and c.side == side then
      table.remove(list, i)
      return true
    end
  end
  return false
end

-- ── submission ─────────────────────────────────────────────────────────────

--- Submit every pending comment for `key` as a single GitHub review.
function M.submit(key, number, repo, head_sha, event, body, callback)
  local comments = {}
  for _, c in ipairs(queue(key)) do
    local entry = { path = c.path, line = c.line, side = c.side, body = c.body }
    if c.start_line and c.start_line ~= c.line then
      entry.start_line = c.start_line
      entry.start_side = c.start_side or c.side
    end
    table.insert(comments, entry)
  end
  fetch.submit_review(number, repo, head_sha, event, body, comments, function(err)
    if not err then M.clear(key) end
    callback(err)
  end)
end

return M
