local M = {}
local gh      = require("gh_dashboard.gh")
local heatmap = require("gh_dashboard.heatmap")

-- ── helpers ────────────────────────────────────────────────────────────────

local function repo_from_url(url)
  if not url then return "?" end
  return url:match("github%.com/([^/]+/[^/]+)") or "?"
end

-- ── fetch functions ────────────────────────────────────────────────────────

function M.profile(callback)
  gh.run_with_retry(
    { "gh", "api", "user", "--jq",
      "{login:.login,name:.name,bio:.bio,followers:.followers,following:.following,public_repos:.public_repos}" },
    callback
  )
end

function M.prs(callback)
  local seen    = {}   -- key → index in `all`
  local all     = {}
  local pending = 3
  local any_err

  local function collect(err, prs, is_review_query)
    if err then any_err = err end
    for _, pr in ipairs(prs or {}) do
      local key = pr.repo .. "#" .. pr.number
      if seen[key] then
        if is_review_query then all[seen[key]].needs_review = true end
      else
        if is_review_query then pr.needs_review = true end
        table.insert(all, pr)
        seen[key] = #all
      end
    end
    pending = pending - 1
    if pending == 0 then
      table.sort(all, function(a, b) return (a.updated_at or "") > (b.updated_at or "") end)
      if any_err and #all == 0 then
        callback(any_err, nil)
      else
        callback(nil, all)
      end
    end
  end

  local function run_query(filter_key, filter_val, is_review_query)
    gh.run_with_retry(
      { "gh", "search", "prs", filter_key, filter_val, "--state", "open",
        "--json", "number,title,repository,url,updatedAt,isDraft" },
      function(err, data)
        if err then collect(err, nil, is_review_query) return end
        local prs = {}
        for _, pr in ipairs(data or {}) do
          table.insert(prs, {
            number     = pr.number,
            title      = pr.title,
            repo       = type(pr.repository) == "table" and pr.repository.nameWithOwner or repo_from_url(pr.url),
            url        = pr.url,
            updated_at = pr.updatedAt,
            is_draft   = pr.isDraft,
          })
        end
        collect(nil, prs, is_review_query)
      end
    )
  end

  run_query("--author",           "@me", false)
  run_query("--assignee",         "@me", false)
  run_query("--review-requested", "@me", true)
end

function M.issues(callback)
  gh.run_with_retry(
    { "gh", "search", "issues", "--assignee", "@me", "--state", "open",
      "--json", "number,title,repository,url,createdAt" },
    function(err, data)
      if err then callback(err, nil) return end
      local issues = {}
      for _, iss in ipairs(data or {}) do
        table.insert(issues, {
          number     = iss.number,
          title      = iss.title,
          repo       = type(iss.repository) == "table" and iss.repository.nameWithOwner or repo_from_url(iss.url),
          url        = iss.url,
          created_at = iss.createdAt,
        })
      end
      callback(nil, issues)
    end
  )
end

local CONTRIB_QUERY = table.concat({
  "{ viewer { contributionsCollection {",
  "  contributionCalendar {",
  "    totalContributions",
  "    weeks { contributionDays { contributionCount date } }",
  "  }",
  "} } }",
}, " ")

local function contributions_attempt(attempts, callback)
  vim.system(
    { "gh", "api", "graphql", "-f", "query=" .. CONTRIB_QUERY },
    { text = true },
    function(result)
      vim.schedule(function()
        if result.code ~= 0 then
          if attempts < 2 then
            vim.defer_fn(function()
              contributions_attempt(attempts + 1, callback)
            end, 2 ^ attempts * 1000)
          else
            callback(result.stderr or "graphql error", nil)
          end
          return
        end
        local ok, decoded = pcall(vim.fn.json_decode, result.stdout)
        if not ok then callback("json error", nil) return end
        local cal = ((((decoded or {}).data or {}).viewer or {}).contributionsCollection or {}).contributionCalendar
        if not cal then callback("no contribution data", nil) return end
        local weeks     = {}
        local all_weeks = cal.weeks or {}
        local start     = math.max(1, #all_weeks - heatmap.HEATMAP_WEEKS + 1)
        for i = start, #all_weeks do
          local days = {}
          for _, d in ipairs(all_weeks[i].contributionDays or {}) do
            table.insert(days, {
              date  = d.date,
              count = d.contributionCount,
              tier  = heatmap.contribution_tier(d.contributionCount),
            })
          end
          table.insert(weeks, days)
        end
        callback(nil, { total = cal.totalContributions, weeks = weeks })
      end)
    end
  )
end

function M.contributions(callback)
  contributions_attempt(0, callback)
end

function M.repos(callback)
  gh.run_with_retry(
    { "gh", "repo", "list", "--limit", "10",
      "--json", "name,nameWithOwner,url,description,primaryLanguage,stargazerCount,isPrivate,pushedAt" },
    function(err, data)
      if err then callback(err, nil) return end
      local repos = {}
      for _, r in ipairs(data or {}) do
        table.insert(repos, {
          name        = r.name,
          full_name   = r.nameWithOwner,
          url         = r.url,
          description = r.description or "",
          language    = type(r.primaryLanguage) == "table" and r.primaryLanguage.name or "",
          stars       = r.stargazerCount or 0,
          is_private  = r.isPrivate,
          updated_at  = r.pushedAt,
        })
      end
      callback(nil, repos)
    end
  )
end

function M.org_repos(callback)
  gh.run_with_retry(
    { "gh", "api", "/user/orgs", "--paginate" },
    function(err, orgs)
      if err or not orgs or #orgs == 0 then
        callback(nil, {})
        return
      end
      local pending   = #orgs
      local all_repos = {}
      local any_err
      for _, org in ipairs(orgs) do
        gh.run_with_retry(
          { "gh", "repo", "list", org.login, "--limit", "1000",
            "--json", "name,nameWithOwner,url,primaryLanguage,stargazerCount,isPrivate,pushedAt" },
          function(ferr, repos)
            if ferr then
              any_err = ferr
            else
              for _, r in ipairs(repos or {}) do
                table.insert(all_repos, {
                  name       = r.name,
                  full_name  = r.nameWithOwner,
                  url        = r.url,
                  language   = type(r.primaryLanguage) == "table" and r.primaryLanguage.name or "",
                  stars      = r.stargazerCount or 0,
                  is_private = r.isPrivate,
                  updated_at = r.pushedAt,
                })
              end
            end
            pending = pending - 1
            if pending == 0 then
              table.sort(all_repos, function(a, b)
                return (a.updated_at or "") > (b.updated_at or "")
              end)
              callback(any_err, all_repos)
            end
          end
        )
      end
    end
  )
end

function M.notifications(callback)
  gh.run_with_retry(
    { "gh", "api", "/notifications" },
    function(err, data)
      if err then callback(err, nil) return end
      local count = 0
      for _, n in ipairs(data or {}) do
        if n.unread then count = count + 1 end
      end
      callback(nil, count)
    end
  )
end

function M.activity_feed(callback)
  local users = require("gh_dashboard.user_watchlist").get_users()
  local repos = require("gh_dashboard.watchlist").get_repos()
  local total = #users + #repos
  if total == 0 then callback(nil, nil) return end

  local all_events = {}
  local pending    = total
  local last_err

  local JQ = '[.[] | {type, actor:.actor.login, repo:.repo.name, created_at,' ..
    'action:.payload.action, merged:.payload.pull_request.merged,' ..
    'pr_number:.payload.pull_request.number, issue_number:.payload.issue.number,' ..
    'ref:.payload.ref, ref_type:.payload.ref_type,' ..
    'release_tag:.payload.release.tag_name}] | .[0:20]'

  local function collect(err, events)
    if err then last_err = err
    else for _, ev in ipairs(events or {}) do table.insert(all_events, ev) end
    end
    pending = pending - 1
    if pending == 0 then
      table.sort(all_events, function(a, b)
        return (a.created_at or "") > (b.created_at or "")
      end)
      local top = {}
      for i = 1, math.min(20, #all_events) do top[i] = all_events[i] end
      if #top == 0 and last_err then callback(last_err, nil)
      else callback(nil, top) end
    end
  end

  for _, username in ipairs(users) do
    gh.run_with_retry(
      { "gh", "api", "/users/" .. username .. "/events", "--jq", JQ },
      function(err, evs) collect(err, evs) end
    )
  end
  for _, r in ipairs(repos) do
    gh.run_with_retry(
      { "gh", "api", "/repos/" .. r.owner .. "/" .. r.repo .. "/events", "--jq", JQ },
      function(err, evs) collect(err, evs) end
    )
  end
end

return M
