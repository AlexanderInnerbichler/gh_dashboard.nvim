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
  diff                   = {
    layout          = "side_by_side",  -- or "unified"
    picker_width    = 0.6,
    context         = 6,
    auto_preview    = true,
    hide_generated  = true,
    generated_globs = {
      "*.lock", "package-lock.json", "yarn.lock", "pnpm-lock.yaml",
      "go.sum", "Cargo.lock", "*.min.js", "*.min.css", "dist/*", "vendor/*",
    },
  },
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
  for _, k in ipairs({ "picker_width", "context" }) do
    if type(opts.diff[k]) ~= "number" then
      vim.notify(
        string.format("gh_dashboard: config.diff.%s must be a number (got %s)", k, type(opts.diff[k])),
        vim.log.levels.WARN, { title = "GhDashboard" })
      opts.diff[k] = defaults.diff[k]
    end
  end
  if opts.diff.layout ~= "side_by_side" and opts.diff.layout ~= "unified" then
    vim.notify("gh_dashboard: config.diff.layout must be 'side_by_side' or 'unified'",
      vim.log.levels.WARN, { title = "GhDashboard" })
    opts.diff.layout = defaults.diff.layout
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
