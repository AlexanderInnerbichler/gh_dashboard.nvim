local M = {}

local defaults = {
  cache_ttl         = 300,   -- seconds before cached dashboard data is stale
  poll_interval     = 60,    -- seconds between watchlist polls
  notification_ttl  = 5,     -- seconds before a toast auto-dismisses
  max_notifications = 3,     -- maximum simultaneous notification toasts
  max_history       = 20,    -- maximum notification history entries
  window_width      = 0.9,   -- dashboard/reader window width as fraction of screen
}

local _config = vim.deepcopy(defaults)

function M.setup(opts)
  _config = vim.tbl_deep_extend("force", defaults, opts or {})
end

function M.get()
  return _config
end

return M
