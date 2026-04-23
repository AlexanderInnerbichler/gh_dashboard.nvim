local M      = {}
local heatmap = require("gh_dashboard.heatmap")
local config  = require("gh_dashboard.config")

-- ── helpers ────────────────────────────────────────────────────────────────

local EVENT_ICONS = {
  PushEvent         = "↑",
  PullRequestEvent  = "⎇",
  IssuesEvent       = "!",
  IssueCommentEvent = "·",
  CreateEvent       = "+",
  ForkEvent         = "⑂",
  WatchEvent        = "★",
}

local function separator(width)
  return "  " .. string.rep("─", (width or 60) - 2)
end

local function sl(s) return (s or ""):gsub("[\n\r]", " ") end

local function trunc(s, n)
  s = sl(s)
  return #s > n and s:sub(1, n - 3) .. "…" or s
end

local function age_seconds(iso8601)
  if not iso8601 then return 0 end
  local y, mo, d, h, mi, s = iso8601:match("(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)")
  if not y then return 0 end
  local t = os.time({ year = y, month = mo, day = d, hour = h, min = mi, sec = s, isdst = false })
  return os.time(os.date("!*t")) - t
end

local function age_string(iso8601)
  if not iso8601 then return "" end
  local diff = age_seconds(iso8601)
  if     diff < 60        then return "just now"
  elseif diff < 3600      then return math.floor(diff / 60)       .. "m ago"
  elseif diff < 86400     then return math.floor(diff / 3600)     .. "h ago"
  elseif diff < 604800    then return math.floor(diff / 86400)    .. "d ago"
  elseif diff < 2592000   then return math.floor(diff / 604800)   .. "w ago"
  elseif diff < 31536000  then return math.floor(diff / 2592000)  .. "mo ago"
  else                         return math.floor(diff / 31536000) .. "y ago"
  end
end

-- ── section renderers ──────────────────────────────────────────────────────

local function render_profile(lines, hl_specs, profile, total_contrib, win_width, is_loading, is_stale)
  local loading_tag = is_loading and "  [loading…]" or ""
  local stale_tag   = is_stale   and "  [stale]"    or ""
  local login    = (profile and profile.login) or "GitHub"
  local has_name = profile and profile.name and profile.name ~= "" and profile.name ~= vim.NIL
  local display  = has_name and (profile.name .. "  @" .. login) or login
  local title    = "  GitHub  " .. display .. loading_tag .. stale_tag
  table.insert(lines, title)
  local u_start = #"  GitHub  "
  table.insert(hl_specs, { hl = "GhTitle",    line = #lines - 1, col_s = 0,       col_e = u_start })
  table.insert(hl_specs, { hl = "GhUsername", line = #lines - 1, col_s = u_start, col_e = u_start + #display })
  if loading_tag ~= "" then
    table.insert(hl_specs, { hl = "GhStats", line = #lines - 1,
      col_s = u_start + #display, col_e = u_start + #display + #loading_tag })
  end
  if stale_tag ~= "" then
    local soff = u_start + #display + #loading_tag
    table.insert(hl_specs, { hl = "GhStale", line = #lines - 1, col_s = soff, col_e = soff + #stale_tag })
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

local function render_prs(lines, hl_specs, items, prs, err, win_width)
  local count  = (not err and prs) and #prs or nil
  local header = count ~= nil and ("  Pull Requests (" .. count .. ")") or "  Pull Requests"
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
    local cfg             = config.get()
    local stale_threshold = cfg.stale_pr_days * 86400
    -- fixed overhead: 3 (indent) + 1 (#) + 4 (num) + 2 + 25 (repo) + 2 + 2 = 39; ~32 for age+tags
    local title_w = math.min(60, math.max(30, (win_width or 120) - 39 - 32))
    local age_col = 3 + 1 + 4 + 2 + title_w + 2 + 25 + 2
    for _, pr in ipairs(prs) do
      local age    = age_string(pr.updated_at)
      local draft  = pr.is_draft    and " [draft]"  or ""
      local review = pr.needs_review and " [review]" or ""
      local stale  = age_seconds(pr.updated_at) > stale_threshold and " [stale]" or ""
      local title  = trunc(pr.title, title_w)
      local repo   = trunc(pr.repo,  25)
      local fmt    = "   #%-4d  %-" .. title_w .. "s  %-25s  %s%s%s%s"
      local line   = string.format(fmt, pr.number, title, repo, age, draft, review, stale)
      table.insert(items, { line = #lines, url = pr.url, kind = "pr", number = pr.number, repo = pr.repo, title = pr.title })
      table.insert(lines, line)
      local ln      = #lines - 1
      local tag_col = age_col + #age
      table.insert(hl_specs, { hl = "GhItem", line = ln, col_s = 0,       col_e = 9 })
      table.insert(hl_specs, { hl = "GhMeta", line = ln, col_s = age_col, col_e = tag_col })
      if draft ~= "" then
        table.insert(hl_specs, { hl = "GhPRDraft",  line = ln, col_s = tag_col,          col_e = tag_col + #draft })
      end
      if review ~= "" then
        local r_col = tag_col + #draft
        table.insert(hl_specs, { hl = "GhPRReview", line = ln, col_s = r_col, col_e = r_col + #review })
      end
      if stale ~= "" then
        local s_col = tag_col + #draft + #review
        table.insert(hl_specs, { hl = "GhStale",    line = ln, col_s = s_col, col_e = s_col + #stale })
      end
    end
  end
  table.insert(lines, separator(win_width))
  table.insert(hl_specs, { hl = "GhSeparator", line = #lines - 1, col_s = 0, col_e = -1 })
end

local function render_issues(lines, hl_specs, items, issues, err, win_width)
  local count  = (not err and issues) and #issues or nil
  local header = count ~= nil and ("  Assigned Issues (" .. count .. ")") or "  Assigned Issues"
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
    local title_w = math.min(60, math.max(30, (win_width or 120) - 39 - 32))
    local age_col = 3 + 1 + 4 + 2 + title_w + 2 + 25 + 2
    for _, iss in ipairs(issues) do
      local age   = age_string(iss.created_at)
      local title = trunc(iss.title, title_w)
      local repo  = trunc(iss.repo,  25)
      local fmt   = "   #%-4d  %-" .. title_w .. "s  %-25s  %s"
      local line  = string.format(fmt, iss.number, title, repo, age)
      table.insert(items, { line = #lines, url = iss.url, kind = "issue", number = iss.number, repo = iss.repo })
      table.insert(lines, line)
      table.insert(hl_specs, { hl = "GhItem", line = #lines - 1, col_s = 0,       col_e = 9 })
      table.insert(hl_specs, { hl = "GhMeta", line = #lines - 1, col_s = age_col, col_e = -1 })
    end
  end
  table.insert(lines, separator(win_width))
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
        icon, trunc(ev.summary or "", 30), trunc(ev.repo or "", 35), age)
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

local function render_repos(lines, hl_specs, items, repos, err, watched)
  local count  = (not err and repos) and #repos or nil
  local header = count ~= nil and ("  Repositories (" .. count .. ")") or "  Repositories"
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
      local is_watched = watched and watched[repo.full_name]
      local prefix = is_watched and "●  " or "   "
      local lock = repo.is_private and "🔒" or " ⊙"
      local lang = sl(repo.language) ~= "" and sl(repo.language) or "—"
      local age  = age_string(repo.updated_at)
      local line = string.format("%s%s  %-30s  %-10s  ★%-3d  %s",
        prefix, lock, trunc(repo.name, 30), lang:sub(1, 10), repo.stars, age)
      table.insert(items, { line = #lines, url = repo.url, full_name = repo.full_name, kind = "repo" })
      table.insert(lines, line)
      local ln = #lines - 1
      table.insert(hl_specs, { hl = "GhItem", line = ln, col_s = 0, col_e = 35 })
      table.insert(hl_specs, { hl = "GhMeta", line = ln, col_s = 45, col_e = -1 })
      if is_watched then
        table.insert(hl_specs, { hl = "GhWatchIndicator", line = ln, col_s = 0, col_e = 3 })
      end
    end
  end
end

local function render_org_repos(lines, hl_specs, items, org_repos, err, watched)
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
      local is_watched = watched and watched[repo.full_name]
      local prefix = is_watched and "●  " or "   "
      local lock = repo.is_private and "🔒" or " ⊙"
      local lang = sl(repo.language) ~= "" and sl(repo.language) or "—"
      local age  = age_string(repo.updated_at)
      local line = string.format("%s%s  %-30s  %-10s  ★%-3d  %s",
        prefix, lock, trunc(repo.name, 30), lang:sub(1, 10), repo.stars, age)
      table.insert(items, { line = #lines, url = repo.url, full_name = repo.full_name, kind = "repo" })
      table.insert(lines, line)
      local ln = #lines - 1
      table.insert(hl_specs, { hl = "GhItem", line = ln, col_s = 0, col_e = 35 })
      table.insert(hl_specs, { hl = "GhMeta", line = ln, col_s = 45, col_e = -1 })
      if is_watched then
        table.insert(hl_specs, { hl = "GhWatchIndicator", line = ln, col_s = 0, col_e = 3 })
      end
    end
  end
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
      local actor_line = "   @" .. actor
      table.insert(items, { line = #lines, kind = "user", username = actor })
      table.insert(lines, actor_line)
      table.insert(hl_specs, { hl = "GhSection",  line = #lines - 1, col_s = 0, col_e = 4 })
      table.insert(hl_specs, { hl = "GhUsername", line = #lines - 1, col_s = 4, col_e = #actor_line })

      for _, ev in ipairs(actor_events[actor]) do
        local icon = EVENT_ICONS[ev.type] or "·"
        local repo = trunc(ev.repo or "?", 32)
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
        local icon_hl  = "GhStats"
        if ev.type == "PushEvent"        then icon_hl = "GhPush"
        elseif ev.type == "PullRequestEvent" then icon_hl = "GhPR"
        elseif ev.type == "IssuesEvent" or ev.type == "IssueCommentEvent" then icon_hl = "GhIssue"
        end
        local icon_col = 6
        local meta_col = icon_col + #icon + 2 + 32 + 2
        table.insert(hl_specs, { hl = icon_hl,  line = #lines - 1, col_s = icon_col, col_e = icon_col + #icon })
        table.insert(hl_specs, { hl = "GhMeta", line = #lines - 1, col_s = meta_col, col_e = -1 })
      end
    end
  end
  table.insert(lines, separator())
  table.insert(hl_specs, { hl = "GhSeparator", line = #lines - 1, col_s = 0, col_e = -1 })
end

-- ── public: build all lines/highlights/items ───────────────────────────────

--- Build display content for the dashboard.
--- Returns lines, hl_specs, items tables ready for writing to a buffer.
function M.build(data, is_loading, is_stale, win_width, watched)
  local lines    = {}
  local hl_specs = {}
  local items    = {}

  table.insert(lines, "")  -- top padding

  render_profile(lines, hl_specs, data.profile, data.contributions and data.contributions.total,
    win_width, is_loading, is_stale)
  local login = data.profile and data.profile.login
  heatmap.render_heatmap(lines, hl_specs, data.contributions, items, login)
  render_prs(lines, hl_specs, items, data.prs, data.prs_err, win_width)
  render_issues(lines, hl_specs, items, data.issues, data.issues_err, win_width)
  render_activity(lines, hl_specs, data.activity, data.activity_err)
  render_repos(lines, hl_specs, items, data.repos, data.repos_err, watched)
  render_org_repos(lines, hl_specs, items, data.org_repos, data.org_repos_err, watched)
  render_watched_users(lines, hl_specs, items, data.watched_events, data.watched_events_err)

  return lines, hl_specs, items
end

return M
