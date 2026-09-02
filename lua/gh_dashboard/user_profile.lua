local utils = require("gh_dashboard.utils")
local M = {}
local heatmap = require("gh_dashboard.heatmap")
local gh      = require("gh_dashboard.gh")

local ns = vim.api.nvim_create_namespace("GhUserProfile")

-- ── helpers ────────────────────────────────────────────────────────────────

local sl = utils.sl

-- ── fetch functions ────────────────────────────────────────────────────────

local function fetch_user_profile(username, callback)
  gh.run_with_retry(
    { "gh", "api", "/users/" .. username,
      "--jq", "{login:.login,name:.name,bio:.bio,followers:.followers,following:.following,public_repos:.public_repos}" },
    callback
  )
end

local CONTRIB_QUERY_FMT = "{ user(login: \"%s\") { contributionsCollection { contributionCalendar { totalContributions weeks { contributionDays { contributionCount date } } } } } }"

local function fetch_user_contributions(username, callback)
  local query = string.format(CONTRIB_QUERY_FMT, username)
  vim.system(
    { "gh", "api", "graphql", "-f", "query=" .. query },
    { text = true },
    function(result)
      vim.schedule(function()
        if result.code ~= 0 then
          callback(result.stderr or "graphql error", nil)
          return
        end
        local ok, decoded = pcall(vim.fn.json_decode, result.stdout)
        if not ok then callback("json error", nil) return end
        local cal = ((((decoded or {}).data or {}).user or {}).contributionsCollection or {}).contributionCalendar
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

-- ── rendering ─────────────────────────────────────────────────────────────

local function render_content(lines, hl_specs, items, username, profile, contrib, profile_err, contrib_err)
  -- breadcrumb
  local crumb_prefix = "  GitHub Dashboard  ›  "
  local crumb        = crumb_prefix .. "@" .. username
  table.insert(lines, crumb)
  table.insert(hl_specs, { hl = "GhReaderBreadcrumb", line = #lines - 1, col_s = 0,             col_e = #crumb_prefix })
  table.insert(hl_specs, { hl = "GhReaderTitle",      line = #lines - 1, col_s = #crumb_prefix, col_e = -1 })

  -- profile stats
  if profile_err then
    local msg = "  ✗ " .. sl(profile_err)
    table.insert(lines, msg)
    table.insert(hl_specs, { hl = "GhError", line = #lines - 1, col_s = 0, col_e = #msg })
  elseif profile then
    local total = contrib and contrib.total or 0
    local stats = string.format(
      "  👥 %d followers  %d following  %d repos  %d contributions",
      profile.followers or 0, profile.following or 0, profile.public_repos or 0, total
    )
    table.insert(lines, stats)
    table.insert(hl_specs, { hl = "GhStats", line = #lines - 1, col_s = 0, col_e = #stats })
    if profile.bio and profile.bio ~= "" and profile.bio ~= vim.NIL then
      local bio = "  " .. profile.bio
      table.insert(lines, bio)
      table.insert(hl_specs, { hl = "GhStats", line = #lines - 1, col_s = 0, col_e = #bio })
    end
  end

  -- heatmap (render_heatmap includes trailing "N contributions this year" + separator)
  if contrib_err then
    local msg = "  ✗ contributions unavailable"
    table.insert(lines, msg)
    table.insert(hl_specs, { hl = "GhError", line = #lines - 1, col_s = 0, col_e = #msg })
    return
  end
  heatmap.render_heatmap(lines, hl_specs, contrib, items, username)
end

-- ── popup ─────────────────────────────────────────────────────────────────

M.open = function(username)
  -- create buffer
  local buf = utils.scratch_buf({ modifiable = true })
  local win = utils.float(buf, {
    cursorline = true, title = " @" .. username .. " ", footer = " q close ",
  })

  -- show loading state immediately
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "", "  Loading @" .. username .. "…", "" })
  vim.bo[buf].modifiable = false

  local function close()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, false)
    end
  end

  local popup_items = {}

  local function bmap(lhs, fn)
    vim.keymap.set("n", lhs, fn, { buffer = buf, nowait = true, silent = true })
  end
  bmap("q",     close)
  bmap("<Esc>", close)
  bmap("<CR>", function()
    if not vim.api.nvim_win_is_valid(win) then return end
    local cur_line = vim.api.nvim_win_get_cursor(win)[1] - 1
    for _, item in ipairs(popup_items) do
      if item.line == cur_line and item.kind == "day" then
        require("gh_dashboard.day_activity").open(item.username, item.date)
        return
      end
    end
  end)

  -- fan-out async fetches
  local pending     = 2
  local profile_res = nil
  local contrib_res = nil
  local profile_err = nil
  local contrib_err = nil

  local function render_and_apply()
    local lines, hl_specs = {}, {}
    local items = {}
    table.insert(lines, "")
    render_content(lines, hl_specs, items, username, profile_res, contrib_res, profile_err, contrib_err)
    popup_items = items
    table.insert(lines, "")

    if not vim.api.nvim_buf_is_valid(buf) then return end
    utils.write_buf(buf, ns, lines, hl_specs)
  end

  local function done()
    pending = pending - 1
    if pending == 0 then render_and_apply() end
  end

  fetch_user_profile(username, function(err, data)
    profile_err = err
    profile_res = data
    done()
  end)

  fetch_user_contributions(username, function(err, data)
    contrib_err = err
    contrib_res = data
    done()
  end)
end

return M
