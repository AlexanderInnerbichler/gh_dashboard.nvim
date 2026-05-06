local M = {}

local defaults = {
  cache_ttl              = 300,
  poll_interval          = 60,
  notification_ttl       = 5,
  max_notifications      = 3,
  max_history            = 20,
  window_width           = 0.9,
  stale_pr_days          = 7,
  pr_fetch_limit         = 100,
  feed_events_per_source = 20,
}

M.CACHE_PATH = vim.fn.expand("~/.cache/nvim/gh-dashboard.json")

local _config = vim.deepcopy(defaults)

local NUM_KEYS = {
  "cache_ttl", "poll_interval", "notification_ttl", "max_notifications",
  "max_history", "stale_pr_days", "pr_fetch_limit", "feed_events_per_source",
}

local function validate(opts)
  for _, k in ipairs(NUM_KEYS) do
    if opts[k] ~= nil and type(opts[k]) ~= "number" then
      vim.notify(
        string.format("gh_dashboard: config.%s must be a number (got %s)", k, type(opts[k])),
        vim.log.levels.WARN, { title = "GhDashboard" })
      opts[k] = defaults[k]
    end
  end
  if opts.window_width ~= nil then
    if type(opts.window_width) ~= "number" or opts.window_width <= 0 or opts.window_width > 1 then
      vim.notify("gh_dashboard: config.window_width must be a number in (0, 1]",
        vim.log.levels.WARN, { title = "GhDashboard" })
      opts.window_width = defaults.window_width
    end
  end
end

function M.setup(opts)
  local merged = vim.tbl_deep_extend("force", defaults, opts or {})
  validate(merged)
  _config = merged
end

function M.get()
  return _config
end

return M
