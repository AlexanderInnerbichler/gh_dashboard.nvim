local M = {}
local config     = require("gh_dashboard.config")
local heatmap    = require("gh_dashboard.heatmap")
local highlights = require("gh_dashboard.highlights")
local fetch      = require("gh_dashboard.dashboard.fetch")
local render     = require("gh_dashboard.dashboard.render")

-- ── state ──────────────────────────────────────────────────────────────────

local state = {
  buf        = nil,
  win        = nil,
  data       = nil,
  is_loading = false,
  is_stale   = false,
  items      = {},
}

-- ── namespace ──────────────────────────────────────────────────────────────

local ns = vim.api.nvim_create_namespace("GhDashboard")

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
  vim.fn.writefile({ vim.fn.json_encode(data) }, tmp)
  vim.uv.fs_rename(tmp, cache_path, function() end)
end

local function cache_age_seconds()
  local stat = vim.uv.fs_stat(cache_path)
  if not stat then return math.huge end
  return os.time() - stat.mtime.sec
end

-- ── render ─────────────────────────────────────────────────────────────────

local function apply_render()
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then return end
  local data      = state.data or {}
  local win_width = state.win and vim.api.nvim_win_is_valid(state.win)
    and vim.api.nvim_win_get_width(state.win) or 120

  local watched = {}
  for _, entry in ipairs(require("gh_dashboard.watchlist").get_repos() or {}) do
    watched[entry.owner .. "/" .. entry.repo] = true
  end
  local lines, hl_specs, items = render.build(data, state.is_loading, state.is_stale, win_width, watched)
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

-- ── fetch orchestrator ─────────────────────────────────────────────────────

local function fetch_and_render()
  state.is_loading = true
  apply_render()

  local pending    = 0
  local any_error  = false
  local timed_out  = false
  local timer      = vim.uv.new_timer()

  timer:start(30000, 0, vim.schedule_wrap(function()
    if timed_out then return end
    timed_out = true
    timer:close()
    state.is_loading = false
    apply_render()
  end))

  local function done(had_err)
    if timed_out then return end
    if had_err then any_error = true end
    pending = pending - 1
    if pending == 0 then
      timer:close()
      state.is_loading = false
      if not any_error then write_cache(state.data) end
      apply_render()
    end
  end

  local login = state.data and state.data.profile and state.data.profile.login

  local function start_secondary_fetches()
    pending = pending + 5
    fetch.prs(function(err, prs)
      if err then state.data.prs_err = err else state.data.prs = prs end
      done(err ~= nil)
    end)
    fetch.issues(function(err, issues)
      if err then state.data.issues_err = err else state.data.issues = issues end
      done(err ~= nil)
    end)
    fetch.repos(function(err, repos)
      if err then state.data.repos_err = err else state.data.repos = repos end
      done(err ~= nil)
    end)
    fetch.org_repos(function(err, org_repos)
      if err then state.data.org_repos_err = err else state.data.org_repos = org_repos end
      done(err ~= nil)
    end)
    fetch.watched_users_activity(function(err, events)
      if err then state.data.watched_events_err = err else state.data.watched_events = events end
      done(err ~= nil)
    end)
    if login then
      pending = pending + 1
      fetch.contributions(function(err, contrib)
        if err then state.data.contrib_err = err else state.data.contributions = contrib end
        done(err ~= nil)
      end)
    end
  end

  pending = pending + 1
  fetch.profile(function(err, profile)
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
  local cur_line = vim.api.nvim_win_get_cursor(state.win)[1] - 1
  for _, item in ipairs(state.items) do
    if item.line == cur_line then
      if item.kind == "issue" or item.kind == "pr" then
        require("gh_dashboard.reader").open(item)
      elseif item.kind == "repo" then
        require("gh_dashboard.repo_view").open(item)
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
    vim.b[state.buf].render_markdown = { enabled = false }
    vim.bo[state.buf].bufhidden  = "hide"
    vim.bo[state.buf].buftype    = "nofile"
    vim.bo[state.buf].modifiable = false
  end

  local ui     = vim.api.nvim_list_uis()[1] or { width = 180, height = 50 }
  local width  = math.floor(ui.width  * config.get().window_width)
  local height = math.floor(ui.height * 0.90)
  local row    = math.floor((ui.height - height) / 2)
  local col    = math.floor((ui.width  - width)  / 2)

  local footer_default = " <CR> open  ·  w watch  ·  r refresh  ·  <leader>gw watchlist  ·  <leader>gn notifs  ·  q close "
  local footer_pr      = " <CR> open  ·  d diff  ·  w watch  ·  r refresh  ·  q close "

  state.win = vim.api.nvim_open_win(state.buf, true, {
    relative   = "editor",
    width      = width,
    height     = height,
    row        = row,
    col        = col,
    style      = "minimal",
    border     = "rounded",
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
    local cur_line = vim.api.nvim_win_get_cursor(state.win)[1] - 1
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
    state.data    = state.data or {}
    state.is_stale = false
    fetch_and_render()
  end)
  require("gh_dashboard.help").setup_keymap(state.buf, "dashboard")

  vim.api.nvim_create_autocmd("CursorMoved", {
    buffer = state.buf,
    callback = function()
      if not state.win or not vim.api.nvim_win_is_valid(state.win) then return end
      local cur   = vim.api.nvim_win_get_cursor(state.win)[1] - 1
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

  state.data     = read_cache()
  state.is_stale = cache_age_seconds() >= config.get().cache_ttl

  open_win()

  if state.data then apply_render() end

  if not state.data or state.is_stale then
    state.data = state.data or {}
    fetch_and_render()
  end
end

M.setup = function(opts)
  config.setup(opts)
  vim.fn.mkdir(vim.fn.expand("~/.cache/nvim"), "p")
  highlights.setup()
end

M.focus_win = function()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_set_current_win(state.win)
  end
end

return M
