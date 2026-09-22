local M  = {}
local gh = require("gh_dashboard.gh")

-- One superset projection covering every consumer: the watchlist wants
-- id/type/created_at/payload, the activity feed wants actor, repo and a few
-- flattened payload fields. --jq is applied client-side, so the four callers
-- that each hit /events with their own filter were issuing the identical HTTP
-- request - four times per repo, per dashboard open.
local JQ = "[.[] | {id, type, created_at, actor: .actor.login,"
        .. " repo: .repo.name, payload}] | .[0:30]"

local TTL_MS = 30000

-- Failures need caching too. Without it each consumer re-fetches a failing
-- repo, and with retries on top that is up to nine requests per dead repo per
-- open - enough concurrent traffic to trip GitHub's secondary rate limit,
-- whose 30s timeouts then trigger more retries.
local ERR_TTL_MS  = 15000
local GONE_TTL_MS = 600000

local cache    = {}  -- path -> { at, events, err, ttl }
local inflight = {}  -- path -> list of callbacks

local function fetch(path, callback)
  local hit = cache[path]
  if hit and (vim.uv.now() - hit.at) < hit.ttl then
    callback(hit.err, hit.events)
    return
  end
  -- Coalesce: the startup burst asks for the same repo from several places at
  -- once, before any response has landed to populate the cache.
  if inflight[path] then
    table.insert(inflight[path], callback)
    return
  end
  inflight[path] = { callback }

  gh.run_with_retry({ "gh", "api", path, "--jq", JQ }, function(err, events)
    local waiting = inflight[path] or {}
    inflight[path] = nil
    if err then
      cache[path] = { at = vim.uv.now(), err = err,
        ttl = gh.is_permanent(err) and GONE_TTL_MS or ERR_TTL_MS }
    elseif type(events) == "table" then
      cache[path] = { at = vim.uv.now(), events = events, ttl = TTL_MS }
    end
    for _, cb in ipairs(waiting) do cb(err, events) end
  end)
end

--- callback(err, events) - events are the superset shape described above.
function M.repo(owner, repo, callback)
  fetch("repos/" .. owner .. "/" .. repo .. "/events", callback)
end

function M.user(username, callback)
  fetch("users/" .. username .. "/events", callback)
end

--- Flatten one event into the shape the activity feed renders.
function M.feed_item(ev)
  local p   = ev.payload or {}
  local pr  = type(p.pull_request) == "table" and p.pull_request or {}
  local iss = type(p.issue)        == "table" and p.issue        or {}
  local rel = type(p.release)      == "table" and p.release      or {}
  return {
    type         = ev.type,
    actor        = ev.actor,
    repo         = ev.repo,
    created_at   = ev.created_at,
    action       = p.action,
    merged       = pr.merged,
    pr_number    = pr.number,
    issue_number = iss.number,
    ref          = p.ref,
    ref_type     = p.ref_type,
    release_tag  = rel.tag_name,
  }
end

--- Drop the cache so the next fetch goes to the network (used by refresh).
function M.invalidate()
  cache = {}
end

return M
