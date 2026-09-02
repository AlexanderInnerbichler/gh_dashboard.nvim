local M     = {}
local fetch = require("gh_dashboard.diff.fetch")

local state = { key = "", list = {} }

-- ── pending comments ───────────────────────────────────────────────────────

function M.reset(key)
  if state.key ~= key then
    state.key  = key
    state.list = {}
  end
end

function M.clear()
  state.list = {}
end

function M.all()
  return state.list
end

function M.add(comment)
  table.insert(state.list, comment)
end

function M.for_path(path)
  local out = {}
  for _, c in ipairs(state.list) do
    if c.path == path then table.insert(out, c) end
  end
  return out
end

--- Drop the pending comment anchored at path/line/side. Returns true if removed.
function M.remove(path, line, side)
  for i, c in ipairs(state.list) do
    if c.path == path and c.line == line and c.side == side then
      table.remove(state.list, i)
      return true
    end
  end
  return false
end

-- ── submission ─────────────────────────────────────────────────────────────

--- Submit every pending comment as a single GitHub review.
function M.submit(number, repo, head_sha, event, body, callback)
  local comments = {}
  for _, c in ipairs(state.list) do
    local entry = { path = c.path, line = c.line, side = c.side, body = c.body }
    if c.start_line and c.start_line ~= c.line then
      entry.start_line = c.start_line
      entry.start_side = c.start_side or c.side
    end
    table.insert(comments, entry)
  end
  fetch.submit_review(number, repo, head_sha, event, body, comments, function(err)
    if not err then M.clear() end
    callback(err)
  end)
end

return M
