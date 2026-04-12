local M = {}
local heatmap = require("gh_dashboard.heatmap")

-- ── constants ──────────────────────────────────────────────────────────────

local CACHE_TTL = 300  -- 5 minutes

local EVENT_ICONS = {
  PushEvent         = "↑",
  PullRequestEvent  = "⎇",
  IssuesEvent       = "!",
  IssueCommentEvent = "·",
  CreateEvent       = "+",
  ForkEvent         = "⑂",
  WatchEvent        = "★",
}

-- ── state ──────────────────────────────────────────────────────────────────

local state = {
  buf        = nil,
  win        = nil,
  data       = nil,
  is_loading = false,
  is_stale   = false,
  items      = {},
}

-- ── cache ──────────────────────────────────────────────────────────────────

local cache_path = vim.fn.expand("~/.cache/nvim/gh-dashboard.json")

local function read_cache()
  if vim.fn.filereadable(cache_path) == 0 then return nil end
  local lines = vim.fn.readfile(cache_path)
  if not lines or #lines == 0 then return nil end
  local ok, decoded = pcall(vim.fn.json_decode, table.concat(lines, "\n"))
  if ok and type(decoded) == "table" then return decoded end
  return nil
end

local function write_cache(data)
  local tmp = cache_path .. ".tmp"
  local encoded = vim.fn.json_encode(data)
  vim.fn.writefile({ encoded }, tmp)
  vim.uv.fs_rename(tmp, cache_path, function() end)
end

local function cache_age_seconds()
  local stat = vim.uv.fs_stat(cache_path)
  if not stat then return math.huge end
  return os.time() - stat.mtime.sec
end

-- ── helpers ────────────────────────────────────────────────────────────────

local function age_string(iso8601)
  if not iso8601 then return "" end
  local y, mo, d, h, mi, s = iso8601:match("(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)")
  if not y then return "" end
  local t = os.time({ year = y, month = mo, day = d, hour = h, min = mi, sec = s, isdst = false })
  local diff = os.time(os.date("!*t")) - t
  if diff < 3600 then
    return math.floor(diff / 60) .. "m ago"
  elseif diff < 86400 then
    return math.floor(diff / 3600) .. "h ago"
  elseif diff < 604800 then
    return math.floor(diff / 86400) .. "d ago"
  else
    return math.floor(diff / 604800) .. "w ago"
  end
end

local function repo_from_url(url)
  if not url then return "?" end
  return url:match("github%.com/([^/]+/[^/]+)") or "?"
end

local function event_summary(ev)
  local t = ev.type or "Event"
  if t == "PushEvent" then
    return "pushed commits"
  elseif t == "PullRequestEvent" then
    return "PR activity"
  elseif t == "IssuesEvent" then
    return "issue activity"
  elseif t == "IssueCommentEvent" then
    return "commented on issue"
  elseif t == "CreateEvent" then
    return "created branch/tag"
  elseif t == "ForkEvent" then
    return "forked repo"
  elseif t == "WatchEvent" then
    return "starred repo"
  else
    return t:gsub("Event$", ""):lower()
  end
end

-- ── highlights ─────────────────────────────────────────────────────────────

local ns = vim.api.nvim_create_namespace("GhDashboard")

local function setup_highlights()
  vim.api.nvim_set_hl(0, "GhTitle",     { fg = "#ffffff", bold = true,  bg = "NONE" })
  vim.api.nvim_set_hl(0, "GhUsername",  { fg = "#7fc8f8", bold = true,  bg = "NONE" })
  vim.api.nvim_set_hl(0, "GhStats",     { fg = "#616e88",               bg = "NONE" })
  vim.api.nvim_set_hl(0, "GhStale",     { fg = "#e5c07b",               bg = "NONE" })
  vim.api.nvim_set_hl(0, "GhSeparator", { fg = "#3b4048",               bg = "NONE" })
  vim.api.nvim_set_hl(0, "GhSection",   { fg = "#88c0d0", bold = true,  bg = "NONE" })
  vim.api.nvim_set_hl(0, "GhItem",      { fg = "#abb2bf",               bg = "NONE" })
  vim.api.nvim_set_hl(0, "GhMeta",      { fg = "#4b5263",               bg = "NONE" })
  vim.api.nvim_set_hl(0, "GhEmpty",     { fg = "#4b5263", italic = true, bg = "NONE" })
  vim.api.nvim_set_hl(0, "GhError",     { fg = "#e06c75",               bg = "NONE" })
  vim.api.nvim_set_hl(0, "GhSelected",  { bg = "#2c313a",               fg = "#abb2bf" })
  vim.api.nvim_set_hl(0, "GhPush",      { fg = "#7fc8f8",               bg = "NONE" })
  vim.api.nvim_set_hl(0, "GhPR",        { fg = "#b48ead",               bg = "NONE" })
  vim.api.nvim_set_hl(0, "GhIssue",     { fg = "#e5c07b",               bg = "NONE" })
  -- heatmap tiers (teal-shifted cool greens)
  vim.api.nvim_set_hl(0, "GhHeat0",  { fg = "#1b1f2b", bg = "NONE" })  -- dark navy (empty)
  vim.api.nvim_set_hl(0, "GhHeat1",  { fg = "#0d4a3a", bg = "NONE" })  -- deep forest teal
  vim.api.nvim_set_hl(0, "GhHeat2",  { fg = "#0a7a5c", bg = "NONE" })  -- emerald
  vim.api.nvim_set_hl(0, "GhHeat3",  { fg = "#10c87e", bg = "NONE" })  -- bright teal-green
  vim.api.nvim_set_hl(0, "GhHeat4",  { fg = "#00ff99", bg = "NONE" })  -- neon mint
  vim.api.nvim_set_hl(0, "GhHeat5",  { fg = "#00ffFF", bg = "NONE" })  
end


-- ── async gh runner ────────────────────────────────────────────────────────

local function run_gh(args, callback)
  vim.system(args, { text = true }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        callback(result.stderr or "gh error", nil)
        return
      end
      local ok, decoded = pcall(vim.fn.json_decode, result.stdout)
      if not ok then
        callback("json decode error: " .. tostring(decoded), nil)
        return
      end
      callback(nil, decoded)
    end)
  end)
end

-- ── fetch functions ────────────────────────────────────────────────────────

local function fetch_profile(callback)
  run_gh(
    { "gh", "api", "user", "--jq",
      "{login:.login,name:.name,bio:.bio,followers:.followers,following:.following,public_repos:.public_repos}" },
    callback
  )
end

local function fetch_prs(callback)
  run_gh(
    { "gh", "search", "prs", "--author", "@me", "--state", "open",
      "--json", "number,title,repository,url,createdAt,isDraft" },
    function(err, data)
      if err then callback(err, nil) return end
      local prs = {}
      for _, pr in ipairs(data or {}) do
        table.insert(prs, {
          number     = pr.number,
          title      = pr.title,
          repo       = type(pr.repository) == "table" and pr.repository.nameWithOwner or repo_from_url(pr.url),
          url        = pr.url,
          created_at = pr.createdAt,
          is_draft   = pr.isDraft,
        })
      end
      callback(nil, prs)
    end
  )
end

local function fetch_issues(callback)
  run_gh(
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

local function fetch_activity(login, callback)
  run_gh(
    { "gh", "api", "/users/" .. login .. "/events",
      "--jq", "[.[] | {type,repo:.repo.name,created_at}] | .[0:20]" },
    function(err, data)
      if err then callback(err, nil) return end
      local events = {}
      for _, ev in ipairs(data or {}) do
        table.insert(events, {
          type       = ev.type,
          repo       = ev.repo,
          created_at = ev.created_at,
          summary    = event_summary(ev),
        })
      end
      callback(nil, events)
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

local function fetch_contributions(callback)
  vim.system(
    { "gh", "api", "graphql", "-f", "query=" .. CONTRIB_QUERY },
    { text = true },
    function(result)
      vim.schedule(function()
        if result.code ~= 0 then
          callback(result.stderr or "graphql error", nil)
          return
        end
        local ok, decoded = pcall(vim.fn.json_decode, result.stdout)
        if not ok then callback("json error", nil) return end
        local cal = ((((decoded or {}).data or {}).viewer or {}).contributionsCollection or {}).contributionCalendar
        if not cal then callback("no contribution data", nil) return end
        local weeks = {}
        local all_weeks = cal.weeks or {}
        local start = math.max(1, #all_weeks - heatmap.HEATMAP_WEEKS + 1)
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

local function fetch_repos(callback)
  run_gh(
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

local function fetch_org_repos(callback)
  run_gh(
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
        run_gh(
          { "gh", "repo", "list", org.login, "--limit", "10",
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

local function fetch_team_activity(callback)
  run_gh(
    { "gh", "api", "/user/orgs", "--paginate" },
    function(err, orgs)
      if err then callback(err, nil) return end
      if not orgs or #orgs == 0 then callback(nil, nil) return end
      local pending    = #orgs
      local all_events = {}
      local last_err
      for _, org in ipairs(orgs) do
        run_gh(
          { "gh", "api", "/orgs/" .. org.login .. "/events",
            "--jq", "[.[] | {type, actor: .actor.login, repo: .repo.name, created_at, pr_number: .payload.pull_request.number, issue_number: .payload.issue.number}]" },
          function(ferr, events)
            if ferr then
              last_err = ferr
            else
              for _, ev in ipairs(events or {}) do
                table.insert(all_events, ev)
              end
            end
            pending = pending - 1
            if pending == 0 then
              table.sort(all_events, function(a, b)
                return (a.created_at or "") > (b.created_at or "")
              end)
              local top = {}
              for i = 1, math.min(10, #all_events) do
                top[i] = all_events[i]
              end
              if #top == 0 and last_err then
                callback(last_err, nil)
              else
                callback(nil, top)
              end
            end
          end
        )
      end
    end
  )
end

local function fetch_watched_users_activity(callback)
  local users = require("gh_dashboard.user_watchlist").get_users()
  if not users or #users == 0 then callback(nil, nil) return end
  local pending    = #users
  local all_events = {}
  local last_err
  for _, username in ipairs(users) do
    run_gh(
      { "gh", "api", "/users/" .. username .. "/events",
        "--jq", "[.[] | {type, actor: .actor.login, repo: .repo.name, created_at, pr_number: .payload.pull_request.number, issue_number: .payload.issue.number}] | .[0:20]" },
      function(ferr, events)
        if ferr then
          last_err = ferr
        else
          for _, ev in ipairs(events or {}) do
            table.insert(all_events, ev)
          end
        end
        pending = pending - 1
        if pending == 0 then
          table.sort(all_events, function(a, b)
            return (a.created_at or "") > (b.created_at or "")
          end)
          local top = {}
          for i = 1, math.min(10, #all_events) do
            top[i] = all_events[i]
          end
          if #top == 0 and last_err then
            callback(last_err, nil)
          else
            callback(nil, top)
          end
        end
      end
    )
  end
end

-- ── render functions ───────────────────────────────────────────────────────

local function separator(width)
  return "  " .. string.rep("─", (width or 60) - 2)
end

local function sl(s) return (s or ""):gsub("[\n\r]", " ") end

local function render_profile(lines, hl_specs, profile, total_contrib, win_width)
  local loading_tag = state.is_loading and "  [loading…]" or ""
  local stale_tag   = state.is_stale   and "  [stale]"    or ""
  local login  = (profile and profile.login)  or "GitHub"
  local title  = "  GitHub  " .. login .. loading_tag .. stale_tag
  table.insert(lines, title)
  -- highlight: "  GitHub  " plain, then username in GhUsername
  local u_start = #"  GitHub  "
  table.insert(hl_specs, { hl = "GhTitle",    line = #lines - 1, col_s = 0,       col_e = u_start })
  table.insert(hl_specs, { hl = "GhUsername", line = #lines - 1, col_s = u_start, col_e = u_start + #login })
  if loading_tag ~= "" then
    table.insert(hl_specs, { hl = "GhStats", line = #lines - 1,
      col_s = u_start + #login, col_e = u_start + #login + #loading_tag })
  end
  if stale_tag ~= "" then
    local soff = u_start + #login + #loading_tag
    table.insert(hl_specs, { hl = "GhStale", line = #lines - 1,
      col_s = soff, col_e = soff + #stale_tag })
  end

  if profile then
    local stats = string.format(
      "  👥 %d followers · %d following · %d repos · %d contributions",
      profile.followers or 0, profile.following or 0,
      profile.public_repos or 0, total_contrib or 0
    )
    table.insert(lines, stats)
    table.insert(hl_specs, { hl = "GhStats", line = #lines - 1, col_s = 0, col_e = #stats })
    if profile.bio and profile.bio ~= "" and profile.bio ~= vim.NIL then
      local bio = "  " .. profile.bio
      table.insert(lines, bio)
      table.insert(hl_specs, { hl = "GhStats", line = #lines - 1, col_s = 0, col_e = #bio })
    end
  end
  table.insert(lines, separator(win_width))
  table.insert(hl_specs, { hl = "GhSeparator", line = #lines - 1, col_s = 0, col_e = -1 })
end

local function render_prs(lines, hl_specs, items, prs, err)
  local header = "  Pull Requests"
  table.insert(lines, header)
  table.insert(hl_specs, { hl = "GhSection", line = #lines - 1, col_s = 0, col_e = #header })

  if err then
    local msg = "  ✗ " .. sl(err)
    table.insert(lines, msg)
    table.insert(hl_specs, { hl = "GhError", line = #lines - 1, col_s = 0, col_e = #msg })
  elseif not prs or #prs == 0 then
    local msg = "   No open pull requests"
    table.insert(lines, msg)
    table.insert(hl_specs, { hl = "GhEmpty", line = #lines - 1, col_s = 0, col_e = #msg })
  else
    for _, pr in ipairs(prs) do
      local draft  = pr.is_draft and " [draft]" or ""
      local age    = age_string(pr.created_at)
      local title  = pr.title:gsub("[\n\r]", " "):sub(1, 45)
      local repo   = pr.repo:gsub("[\n\r]", " "):sub(1, 25)
      local line   = string.format("   #%-4d  %-45s  %-25s  %s%s",
        pr.number, title, repo, age, draft)
      table.insert(items, { line = #lines, url = pr.url, kind = "pr", number = pr.number, repo = pr.repo, title = pr.title })
      table.insert(lines, line)
      table.insert(hl_specs, { hl = "GhItem", line = #lines - 1, col_s = 0, col_e = 9 })
      table.insert(hl_specs, { hl = "GhMeta", line = #lines - 1, col_s = 57, col_e = -1 })
    end
  end
  table.insert(lines, separator())
  table.insert(hl_specs, { hl = "GhSeparator", line = #lines - 1, col_s = 0, col_e = -1 })
end

local function render_issues(lines, hl_specs, items, issues, err)
  local header = "  Assigned Issues"
  table.insert(lines, header)
  table.insert(hl_specs, { hl = "GhSection", line = #lines - 1, col_s = 0, col_e = #header })

  if err then
    local msg = "  ✗ " .. sl(err)
    table.insert(lines, msg)
    table.insert(hl_specs, { hl = "GhError", line = #lines - 1, col_s = 0, col_e = #msg })
  elseif not issues or #issues == 0 then
    local msg = "   No assigned issues"
    table.insert(lines, msg)
    table.insert(hl_specs, { hl = "GhEmpty", line = #lines - 1, col_s = 0, col_e = #msg })
  else
    for _, iss in ipairs(issues) do
      local age  = age_string(iss.created_at)
      local title = iss.title:gsub("[\n\r]", " "):sub(1, 45)
      local repo  = iss.repo:gsub("[\n\r]", " "):sub(1, 25)
      local line  = string.format("   #%-4d  %-45s  %-25s  %s",
        iss.number, title, repo, age)
      table.insert(items, { line = #lines, url = iss.url, kind = "issue", number = iss.number, repo = iss.repo })
      table.insert(lines, line)
      table.insert(hl_specs, { hl = "GhItem", line = #lines - 1, col_s = 0, col_e = 9 })
      table.insert(hl_specs, { hl = "GhMeta", line = #lines - 1, col_s = 57, col_e = -1 })
    end
  end
  table.insert(lines, separator())
  table.insert(hl_specs, { hl = "GhSeparator", line = #lines - 1, col_s = 0, col_e = -1 })
end

local function render_activity(lines, hl_specs, activity, err)
  local header = "  Recent Activity"
  table.insert(lines, header)
  table.insert(hl_specs, { hl = "GhSection", line = #lines - 1, col_s = 0, col_e = #header })

  if err then
    local msg = "  ✗ " .. sl(err)
    table.insert(lines, msg)
    table.insert(hl_specs, { hl = "GhError", line = #lines - 1, col_s = 0, col_e = #msg })
  elseif not activity or #activity == 0 then
    local msg = "   No recent activity"
    table.insert(lines, msg)
    table.insert(hl_specs, { hl = "GhEmpty", line = #lines - 1, col_s = 0, col_e = #msg })
  else
    for i, ev in ipairs(activity) do
      if i > 10 then break end
      local icon = EVENT_ICONS[ev.type] or "·"
      local age  = age_string(ev.created_at)
      local line = string.format("   %s  %-30s  %-35s  %s",
        icon, sl(ev.summary):sub(1, 30), sl(ev.repo or ""):sub(1, 35), age)
      table.insert(lines, line)
      local icon_hl = "GhStats"
      if ev.type == "PushEvent"        then icon_hl = "GhPush"
      elseif ev.type == "PullRequestEvent" then icon_hl = "GhPR"
      elseif ev.type == "IssuesEvent" or ev.type == "IssueCommentEvent" then icon_hl = "GhIssue"
      end
      table.insert(hl_specs, { hl = icon_hl, line = #lines - 1, col_s = 3, col_e = 3 + #icon })
      table.insert(hl_specs, { hl = "GhMeta", line = #lines - 1, col_s = 38, col_e = -1 })
    end
  end
  table.insert(lines, separator())
  table.insert(hl_specs, { hl = "GhSeparator", line = #lines - 1, col_s = 0, col_e = -1 })
end

local function render_repos(lines, hl_specs, items, repos, err)
  local header = "  Repositories"
  table.insert(lines, header)
  table.insert(hl_specs, { hl = "GhSection", line = #lines - 1, col_s = 0, col_e = #header })

  if err then
    local msg = "  ✗ " .. sl(err)
    table.insert(lines, msg)
    table.insert(hl_specs, { hl = "GhError", line = #lines - 1, col_s = 0, col_e = #msg })
  elseif not repos or #repos == 0 then
    local msg = "   No repositories"
    table.insert(lines, msg)
    table.insert(hl_specs, { hl = "GhEmpty", line = #lines - 1, col_s = 0, col_e = #msg })
  else
    for _, repo in ipairs(repos) do
      local lock  = repo.is_private and "🔒" or " ⊙"
      local lang  = sl(repo.language) ~= "" and sl(repo.language) or "—"
      local age   = age_string(repo.updated_at)
      local line  = string.format("   %s  %-30s  %-10s  ★%-3d  %s",
        lock, sl(repo.name):sub(1, 30), lang:sub(1, 10), repo.stars, age)
      table.insert(items, { line = #lines, url = repo.url, full_name = repo.full_name, kind = "repo" })
      table.insert(lines, line)
      table.insert(hl_specs, { hl = "GhItem", line = #lines - 1, col_s = 0, col_e = 35 })
      table.insert(hl_specs, { hl = "GhMeta", line = #lines - 1, col_s = 45, col_e = -1 })
    end
  end
end

local function render_org_repos(lines, hl_specs, items, org_repos, err)
  if not err and (not org_repos or #org_repos == 0) then return end

  local header = "  Organization Repositories"
  table.insert(lines, header)
  table.insert(hl_specs, { hl = "GhSection", line = #lines - 1, col_s = 0, col_e = #header })

  if err then
    local msg = "  ✗ " .. sl(err)
    table.insert(lines, msg)
    table.insert(hl_specs, { hl = "GhError", line = #lines - 1, col_s = 0, col_e = #msg })
  else
    for _, repo in ipairs(org_repos) do
      local lock = repo.is_private and "🔒" or " ⊙"
      local lang = sl(repo.language) ~= "" and sl(repo.language) or "—"
      local age  = age_string(repo.updated_at)
      local line = string.format("   %s  %-30s  %-10s  ★%-3d  %s",
        lock, sl(repo.name):sub(1, 30), lang:sub(1, 10), repo.stars, age)
      table.insert(items, { line = #lines, url = repo.url, full_name = repo.full_name, kind = "repo" })
      table.insert(lines, line)
      table.insert(hl_specs, { hl = "GhItem", line = #lines - 1, col_s = 0, col_e = 35 })
      table.insert(hl_specs, { hl = "GhMeta", line = #lines - 1, col_s = 45, col_e = -1 })
    end
  end
end

local function render_team_activity(lines, hl_specs, items, team_events, err)
  if not err and team_events == nil then return end

  local header = "  Team Activity"
  table.insert(lines, header)
  table.insert(hl_specs, { hl = "GhSection", line = #lines - 1, col_s = 0, col_e = #header })

  if err then
    local msg = "  ✗ " .. sl(err)
    table.insert(lines, msg)
    table.insert(hl_specs, { hl = "GhError", line = #lines - 1, col_s = 0, col_e = #msg })
  elseif #team_events == 0 then
    local msg = "   No recent team activity"
    table.insert(lines, msg)
    table.insert(hl_specs, { hl = "GhEmpty", line = #lines - 1, col_s = 0, col_e = #msg })
  else
    for _, ev in ipairs(team_events) do
      local actor = sl(ev.actor or "?"):sub(1, 18)
      local icon  = EVENT_ICONS[ev.type] or "·"
      local repo  = sl(ev.repo or "?"):sub(1, 30)
      local age   = age_string(ev.created_at)
      local line  = string.format("   %-18s  %s  %-30s  %s", actor, icon, repo, age)
      if ev.type == "PullRequestEvent" and ev.pr_number and ev.pr_number ~= vim.NIL then
        table.insert(items, { line = #lines, kind = "pr", number = ev.pr_number, repo = ev.repo })
      elseif ev.type == "IssuesEvent" and ev.issue_number and ev.issue_number ~= vim.NIL then
        table.insert(items, { line = #lines, kind = "issue", number = ev.issue_number, repo = ev.repo })
      else
        table.insert(items, { line = #lines, kind = "push", url = "https://github.com/" .. (ev.repo or "") })
      end
      table.insert(lines, line)
      local icon_hl = "GhStats"
      if ev.type == "PushEvent"        then icon_hl = "GhPush"
      elseif ev.type == "PullRequestEvent" then icon_hl = "GhPR"
      elseif ev.type == "IssuesEvent" or ev.type == "IssueCommentEvent" then icon_hl = "GhIssue"
      end
      local icon_col = 3 + 18 + 2  -- after "   " + actor + "  "
      table.insert(hl_specs, { hl = icon_hl,   line = #lines - 1, col_s = icon_col, col_e = icon_col + #icon })
      table.insert(hl_specs, { hl = "GhStats", line = #lines - 1, col_s = 3,        col_e = 3 + 18 })
      table.insert(hl_specs, { hl = "GhMeta",  line = #lines - 1, col_s = icon_col + #icon + 2 + 30 + 2, col_e = -1 })
    end
  end
  table.insert(lines, separator())
  table.insert(hl_specs, { hl = "GhSeparator", line = #lines - 1, col_s = 0, col_e = -1 })
end

local function render_watched_users(lines, hl_specs, items, events, err)
  if not err and events == nil then return end

  local header = "  Watched Users"
  table.insert(lines, header)
  table.insert(hl_specs, { hl = "GhSection", line = #lines - 1, col_s = 0, col_e = #header })

  if err then
    local msg = "  ✗ " .. sl(err)
    table.insert(lines, msg)
    table.insert(hl_specs, { hl = "GhError", line = #lines - 1, col_s = 0, col_e = #msg })
  elseif #events == 0 then
    local msg = "   No recent activity from watched users"
    table.insert(lines, msg)
    table.insert(hl_specs, { hl = "GhEmpty", line = #lines - 1, col_s = 0, col_e = #msg })
  else
    -- group events by actor, preserving first-appearance order
    local actor_order  = {}
    local actor_events = {}
    for _, ev in ipairs(events) do
      local actor = sl(ev.actor or "?")
      if not actor_events[actor] then
        table.insert(actor_order, actor)
        actor_events[actor] = {}
      end
      table.insert(actor_events[actor], ev)
    end

    for _, actor in ipairs(actor_order) do
      -- actor header row — <CR> opens profile popup
      local actor_line = "   @" .. actor
      table.insert(items, { line = #lines, kind = "user", username = actor })
      table.insert(lines, actor_line)
      table.insert(hl_specs, { hl = "GhSection",  line = #lines - 1, col_s = 0, col_e = 4 })
      table.insert(hl_specs, { hl = "GhUsername", line = #lines - 1, col_s = 4, col_e = #actor_line })

      -- events for this actor (indented, no actor column)
      for _, ev in ipairs(actor_events[actor]) do
        local icon = EVENT_ICONS[ev.type] or "·"
        local repo = sl(ev.repo or "?"):sub(1, 32)
        local age  = age_string(ev.created_at)
        local line = string.format("      %s  %-32s  %s", icon, repo, age)
        if ev.type == "PullRequestEvent" and ev.pr_number and ev.pr_number ~= vim.NIL then
          table.insert(items, { line = #lines, kind = "pr", number = ev.pr_number, repo = ev.repo })
        elseif ev.type == "IssuesEvent" and ev.issue_number and ev.issue_number ~= vim.NIL then
          table.insert(items, { line = #lines, kind = "issue", number = ev.issue_number, repo = ev.repo })
        else
          table.insert(items, { line = #lines, kind = "push", url = "https://github.com/" .. (ev.repo or "") })
        end
        table.insert(lines, line)
        local icon_hl = "GhStats"
        if ev.type == "PushEvent"        then icon_hl = "GhPush"
        elseif ev.type == "PullRequestEvent" then icon_hl = "GhPR"
        elseif ev.type == "IssuesEvent" or ev.type == "IssueCommentEvent" then icon_hl = "GhIssue"
        end
        local icon_col = 6  -- 6 spaces indent
        local meta_col = icon_col + #icon + 2 + 32 + 2
        table.insert(hl_specs, { hl = icon_hl,   line = #lines - 1, col_s = icon_col, col_e = icon_col + #icon })
        table.insert(hl_specs, { hl = "GhMeta",  line = #lines - 1, col_s = meta_col, col_e = -1 })
      end
    end
  end
  table.insert(lines, separator())
  table.insert(hl_specs, { hl = "GhSeparator", line = #lines - 1, col_s = 0, col_e = -1 })
end

-- ── main render ────────────────────────────────────────────────────────────

local function apply_render()
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then return end
  local data = state.data or {}
  local win_width = state.win and vim.api.nvim_win_is_valid(state.win)
    and vim.api.nvim_win_get_width(state.win) or 120

  local lines    = {}
  local hl_specs = {}
  local items    = {}

  table.insert(lines, "")  -- top padding

  render_profile(lines, hl_specs, data.profile, data.contributions and data.contributions.total, win_width)
  local login = data.profile and data.profile.login
  heatmap.render_heatmap(lines, hl_specs, data.contributions, items, login)
  render_prs(lines, hl_specs, items, data.prs, data.prs_err)
  render_issues(lines, hl_specs, items, data.issues, data.issues_err)
  render_activity(lines, hl_specs, data.activity, data.activity_err)
  render_repos(lines, hl_specs, items, data.repos, data.repos_err)
  render_org_repos(lines, hl_specs, items, data.org_repos, data.org_repos_err)
  render_team_activity(lines, hl_specs, items, data.team_events, data.team_events_err)
  render_watched_users(lines, hl_specs, items, data.watched_events, data.watched_events_err)

  state.items = items

  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.bo[state.buf].modifiable = false

  vim.api.nvim_buf_clear_namespace(state.buf, ns, 0, -1)
  for _, spec in ipairs(hl_specs) do
    local col_e = spec.col_e == -1 and -1 or spec.col_e
    vim.api.nvim_buf_add_highlight(state.buf, ns, spec.hl, spec.line, spec.col_s, col_e)
  end
end

-- ── fetch & merge ──────────────────────────────────────────────────────────

local function fetch_and_render()
  state.is_loading = true
  apply_render()  -- show loading state immediately

  local pending   = 0
  local any_error = false
  local function done(had_err)
    if had_err then any_error = true end
    pending = pending - 1
    if pending == 0 then
      state.is_loading = false
      if not any_error then write_cache(state.data) end
      apply_render()
    end
  end

  local login = state.data and state.data.profile and state.data.profile.login

  local function start_secondary_fetches()
    pending = pending + 6
    fetch_prs(function(err, prs)
      if err then state.data.prs_err = err else state.data.prs = prs end
      done(err ~= nil)
    end)
    fetch_issues(function(err, issues)
      if err then state.data.issues_err = err else state.data.issues = issues end
      done(err ~= nil)
    end)
    fetch_repos(function(err, repos)
      if err then state.data.repos_err = err else state.data.repos = repos end
      done(err ~= nil)
    end)
    fetch_org_repos(function(err, org_repos)
      if err then state.data.org_repos_err = err else state.data.org_repos = org_repos end
      done(err ~= nil)
    end)
    fetch_team_activity(function(err, events)
      if err then state.data.team_events_err = err else state.data.team_events = events end
      done(err ~= nil)
    end)
    fetch_watched_users_activity(function(err, events)
      if err then state.data.watched_events_err = err else state.data.watched_events = events end
      done(err ~= nil)
    end)
    if login then
      pending = pending + 2
      fetch_activity(login, function(err, activity)
        if err then state.data.activity_err = err else state.data.activity = activity end
        done(err ~= nil)
      end)
      fetch_contributions(function(err, contrib)
        if err then state.data.contrib_err = err else state.data.contributions = contrib end
        done(err ~= nil)
      end)
    end
  end

  -- always (re)fetch profile first for the login name
  pending = pending + 1
  fetch_profile(function(err, profile)
    if err then
      state.data.profile_err = err
    else
      state.data.profile = profile
      login = profile.login
    end
    start_secondary_fetches()
    done(err ~= nil)
  end)
end

-- ── window ─────────────────────────────────────────────────────────────────

local function open_url_at_cursor()
  if not state.win or not vim.api.nvim_win_is_valid(state.win) then return end
  local cur_line = vim.api.nvim_win_get_cursor(state.win)[1] - 1  -- 0-indexed
  for _, item in ipairs(state.items) do
    if item.line == cur_line then
      if item.kind == "issue" or item.kind == "pr" or item.kind == "repo" then
        require("gh_dashboard.reader").open(item)
      elseif item.kind == "user" then
        require("gh_dashboard.user_profile").open(item.username)
      elseif item.kind == "day" then
        require("gh_dashboard.day_activity").open(item.username, item.date)
      else
        vim.system({ "xdg-open", item.url })
      end
      return
    end
  end
  vim.notify("No link under cursor", vim.log.levels.INFO)
end

local function close_win()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, false)
    state.win = nil
  end
end

local function open_win()
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
    state.buf = vim.api.nvim_create_buf(false, true)
    vim.bo[state.buf].bufhidden = "hide"
    vim.bo[state.buf].buftype   = "nofile"
    vim.bo[state.buf].modifiable = false
  end

  local ui     = vim.api.nvim_list_uis()[1] or { width = 180, height = 50 }
  local width  = math.floor(ui.width  * 0.90)
  local height = math.floor(ui.height * 0.90)
  local row    = math.floor((ui.height - height) / 2)
  local col    = math.floor((ui.width  - width)  / 2)

  local footer_default = " <CR> open  ·  w watch  ·  r refresh  ·  <leader>gw watchlist  ·  <leader>gn notifs  ·  q close "
  local footer_pr      = " <CR> open  ·  d diff  ·  w watch  ·  r refresh  ·  q close "

  state.win = vim.api.nvim_open_win(state.buf, true, {
    relative = "editor",
    width    = width,
    height   = height,
    row      = row,
    col      = col,
    style    = "minimal",
    border   = "rounded",
    title      = " GitHub Dashboard ",
    title_pos  = "center",
    footer     = footer_default,
    footer_pos = "center",
  })

  vim.wo[state.win].number         = false
  vim.wo[state.win].relativenumber = false
  vim.wo[state.win].signcolumn     = "no"
  vim.wo[state.win].wrap           = false
  vim.wo[state.win].cursorline     = true
  vim.wo[state.win].foldenable     = false

  local function buf_map(lhs, fn)
    vim.keymap.set("n", lhs, fn, { buffer = state.buf, nowait = true, silent = true })
  end

  local function toggle_watch_at_cursor()
    if not state.win or not vim.api.nvim_win_is_valid(state.win) then return end
    local cur_line = vim.api.nvim_win_get_cursor(state.win)[1] - 1  -- 0-indexed
    for _, item in ipairs(state.items) do
      if item.line == cur_line and item.full_name then
        require("gh_dashboard.watchlist").toggle_repo(item.full_name)
        return
      end
    end
  end

  local function open_diff_at_cursor()
    if not state.win or not vim.api.nvim_win_is_valid(state.win) then return end
    local cur_line = vim.api.nvim_win_get_cursor(state.win)[1] - 1
    for _, item in ipairs(state.items) do
      if item.line == cur_line and item.kind == "pr" then
        require("gh_dashboard.reader").open_diff(item)
        return
      end
    end
  end

  buf_map("q",     close_win)
  buf_map("<Esc>", close_win)
  buf_map("<CR>",  open_url_at_cursor)
  buf_map("o",     open_url_at_cursor)
  buf_map("d",     open_diff_at_cursor)
  buf_map("w",     toggle_watch_at_cursor)
  buf_map("r", function()
    vim.uv.fs_unlink(cache_path, function() end)
    state.data = state.data or {}
    state.is_stale = false
    fetch_and_render()
  end)

  vim.api.nvim_create_autocmd("CursorMoved", {
    buffer = state.buf,
    callback = function()
      if not state.win or not vim.api.nvim_win_is_valid(state.win) then return end
      local cur = vim.api.nvim_win_get_cursor(state.win)[1] - 1
      local on_pr = false
      for _, item in ipairs(state.items) do
        if item.line == cur and item.kind == "pr" then on_pr = true; break end
      end
      vim.api.nvim_win_set_config(state.win, {
        footer     = on_pr and footer_pr or footer_default,
        footer_pos = "center",
      })
    end,
  })
end

-- ── public API ─────────────────────────────────────────────────────────────

M.toggle = function()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    close_win()
    return
  end

  state.data = read_cache()
  state.is_stale = cache_age_seconds() >= CACHE_TTL

  open_win()

  if state.data then
    apply_render()  -- show cached data immediately
  end

  if not state.data or state.is_stale then
    state.data = state.data or {}
    fetch_and_render()
  end
end

M.setup = function()
  vim.fn.mkdir(vim.fn.expand("~/.cache/nvim"), "p")
  setup_highlights()
  vim.api.nvim_create_autocmd("ColorScheme", {
    callback = setup_highlights,
    desc = "Re-apply GhDashboard highlights on colorscheme change",
  })
end

M.focus_win = function()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_set_current_win(state.win)
  end
end

return M
