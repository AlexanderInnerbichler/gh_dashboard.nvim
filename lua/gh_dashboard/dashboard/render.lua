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
  local t  = os.time({ year = y, month = mo, day = d, hour = h, min = mi, sec = s })
  local u  = os.date("!*t", t)  u.isdst = nil
  return os.time() - (t + os.difftime(t, os.time(u)))
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

local function render_profile(lines, hl_specs, items, profile, total_contrib, win_width, is_loading, is_stale, notif_count)
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
    if notif_count and notif_count > 0 then
      local s = string.format("  🔔 %d unread notification%s",
        notif_count, notif_count == 1 and "" or "s")
      table.insert(items, { line = #lines, kind = "notifications" })
      table.insert(lines, s)
      table.insert(hl_specs, { hl = "GhNotifUnread", line = #lines - 1, col_s = 0, col_e = -1 })
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
    -- layout: "   <repo(15)>  #<num(4)>  <title>  <age>"
    -- overhead: 3 + 15 + 2 + 1 + 4 + 2 + 2 = 29; ~10 for age
    local repo_w  = 20
    local title_w = math.min(60, math.max(30, (win_width or 120) - 29 - 12))
    local age_col = 3 + repo_w + 2 + 1 + 4 + 2 + title_w + 2
    local repo_colors = {}
    local color_count = 0
    for _, iss in ipairs(issues) do
      local short_repo = iss.repo:match("[^/]+$") or iss.repo
      if not repo_colors[iss.repo] then
        color_count = color_count + 1
        repo_colors[iss.repo] = (color_count - 1) % 6 + 1
      end
      local age   = age_string(iss.created_at)
      local title = trunc(iss.title, title_w)
      local repo  = trunc(short_repo, repo_w)
      local fmt   = "   %-" .. repo_w .. "s  #%-4d  %-" .. title_w .. "s  %s"
      local line  = string.format(fmt, repo, iss.number, title, age)
      table.insert(items, { line = #lines, url = iss.url, kind = "issue", number = iss.number, repo = iss.repo })
      table.insert(lines, line)
      local ln       = #lines - 1
      local num_col  = 3 + repo_w + 2
      table.insert(hl_specs, { hl = "GhIssueRepo" .. repo_colors[iss.repo], line = ln, col_s = 3,       col_e = 3 + repo_w })
      table.insert(hl_specs, { hl = "GhItem",                               line = ln, col_s = num_col, col_e = num_col + 6 })
      table.insert(hl_specs, { hl = "GhMeta",                               line = ln, col_s = age_col, col_e = -1 })
    end
  end
  table.insert(lines, separator(win_width))
  table.insert(hl_specs, { hl = "GhSeparator", line = #lines - 1, col_s = 0, col_e = -1 })
end

local function event_desc(ev)
  local t, a = ev.type or "", ev.action or ""
  if t == "PushEvent" then
    local ref = (type(ev.ref) == "string" and ev.ref or ""):gsub("refs/heads/", "")
    return "pushed to " .. (ref ~= "" and ref or "?")
  elseif t == "PullRequestEvent" then
    local n = type(ev.pr_number) == "number" and ("#" .. ev.pr_number) or ""
    if a == "opened"       then return "opened PR " .. n
    elseif a == "closed"   then return (ev.merged == true and "merged" or "closed") .. " PR " .. n
    elseif a == "reopened" then return "reopened PR " .. n
    else                        return a .. " PR " .. n end
  elseif t == "IssuesEvent" then
    local n = type(ev.issue_number) == "number" and ("#" .. ev.issue_number) or ""
    return a .. " issue " .. n
  elseif t == "IssueCommentEvent" then
    local n = type(ev.issue_number) == "number" and ("#" .. ev.issue_number) or ""
    return "commented on " .. n
  elseif t == "CreateEvent" then
    return "created " .. (type(ev.ref_type) == "string" and ev.ref_type or "?")
  elseif t == "ReleaseEvent" then
    return "released " .. (type(ev.release_tag) == "string" and ev.release_tag or "?")
  elseif t == "ForkEvent"  then return "forked"
  elseif t == "WatchEvent" then return "starred"
  else return t:gsub("Event", ""):lower() end
end

local function render_activity_feed(lines, hl_specs, items, events, err)
  local users = require("gh_dashboard.user_watchlist").get_users()
  local repos = require("gh_dashboard.watchlist").get_repos()
  local has_sources = #users > 0 or #repos > 0
  if not has_sources and not err and events == nil then return end

  local count  = (not err and events) and #events or nil
  local header = count ~= nil and ("  Activity Feed (" .. count .. ")") or "  Activity Feed"
  table.insert(lines, header)
  table.insert(hl_specs, { hl = "GhSection", line = #lines - 1, col_s = 0, col_e = #header })

  if err then
    local msg = "  ✗ " .. sl(err)
    table.insert(lines, msg)
    table.insert(hl_specs, { hl = "GhError", line = #lines - 1, col_s = 0, col_e = #msg })
  elseif not events or #events == 0 then
    local msg = has_sources
      and "   No recent activity from watched users or repos"
      or  "   Add users or repos to your watchlists to see activity here"
    table.insert(lines, msg)
    table.insert(hl_specs, { hl = "GhEmpty", line = #lines - 1, col_s = 0, col_e = #msg })
  else
    for _, ev in ipairs(events) do
      local icon  = EVENT_ICONS[ev.type] or "·"
      local actor = sl(ev.actor or "?")
      local repo  = sl(ev.repo  or "?")
      local desc  = event_desc(ev)
      local age   = age_string(ev.created_at)
      local line  = string.format("  %s  %-18s  %-24s  %-28s  %s",
        icon, "@" .. trunc(actor, 17), trunc(repo, 24), trunc(desc, 28), age)

      if ev.type == "PullRequestEvent" and type(ev.pr_number) == "number" then
        table.insert(items, { line = #lines, kind = "pr",    number = ev.pr_number,    repo = ev.repo })
      elseif (ev.type == "IssuesEvent" or ev.type == "IssueCommentEvent")
          and type(ev.issue_number) == "number" then
        table.insert(items, { line = #lines, kind = "issue", number = ev.issue_number, repo = ev.repo })
      else
        table.insert(items, { line = #lines, kind = "user",  username = ev.actor })
      end

      table.insert(lines, line)
      local ln        = #lines - 1
      local icon_col  = 2
      local actor_col = icon_col + #icon + 2
      local repo_col  = actor_col + 18 + 2
      local desc_col  = repo_col  + 24 + 2
      local age_col   = desc_col  + 28 + 2

      local icon_hl = "GhStats"
      if ev.type == "PushEvent" then icon_hl = "GhPush"
      elseif ev.type == "PullRequestEvent" then icon_hl = "GhPR"
      elseif ev.type == "IssuesEvent" or ev.type == "IssueCommentEvent" then icon_hl = "GhIssue"
      end

      table.insert(hl_specs, { hl = icon_hl,      line = ln, col_s = icon_col,  col_e = icon_col + #icon })
      table.insert(hl_specs, { hl = "GhUsername", line = ln, col_s = actor_col, col_e = actor_col + 18 })
      table.insert(hl_specs, { hl = "GhItem",     line = ln, col_s = repo_col,  col_e = repo_col  + 24 })
      table.insert(hl_specs, { hl = "GhMeta",     line = ln, col_s = age_col,   col_e = -1 })
    end
  end
  table.insert(lines, separator())
  table.insert(hl_specs, { hl = "GhSeparator", line = #lines - 1, col_s = 0, col_e = -1 })
end

-- ── public: build all lines/highlights/items ───────────────────────────────

--- Build display content for the dashboard.
--- Returns lines, hl_specs, items tables ready for writing to a buffer.
function M.build(data, is_loading, is_stale, win_width)
  local lines    = {}
  local hl_specs = {}
  local items    = {}

  table.insert(lines, "")  -- top padding

  render_profile(lines, hl_specs, items, data.profile, data.contributions and data.contributions.total,
    win_width, is_loading, is_stale, data.notif_count)
  local login = data.profile and data.profile.login
  local hm_left_pad = heatmap.render_heatmap(lines, hl_specs, data.contributions, items, login, win_width)
  render_prs(lines, hl_specs, items, data.prs, data.prs_err, win_width)
  render_issues(lines, hl_specs, items, data.issues, data.issues_err, win_width)
  render_activity_feed(lines, hl_specs, items, data.feed_events, data.feed_err)

  return lines, hl_specs, items, hm_left_pad or 0
end

return M
