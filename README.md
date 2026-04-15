# gh_dashboard.nvim

GitHub dashboard for Neovim.

**Requires**: [gh CLI](https://cli.github.com) authenticated + Neovim 0.10+

## Install

```lua
{
  "AlexanderInnerbichler/gh_dashboard.nvim",
  cmd  = { "GhDashboard", "GhWatchlist" },
  keys = {
    { "<leader>gh", "<cmd>GhDashboard<cr>", desc = "GitHub Dashboard" },
    { "<leader>gw", "<cmd>GhWatchlist<cr>", desc = "GitHub Watchlist" },
  },
  config = function()
    require("gh_dashboard").setup()
    require("gh_dashboard.reader").setup()
    require("gh_dashboard.watchlist").setup()
    require("gh_dashboard.user_watchlist").setup()
  end,
}
```

## Config

```lua
require("gh_dashboard").setup({
  cache_ttl         = 300,  -- seconds before cache expires
  poll_interval     = 60,   -- seconds between watchlist polls
  notification_ttl  = 5,    -- seconds before toast dismisses
  max_notifications = 3,
  max_history       = 20,
  window_width      = 0.9,
})
```

## Keys

| Key | Action |
|-----|--------|
| `<leader>gh` | Dashboard |
| `<leader>gw` | Repo watchlist |
| `<leader>gn` | Latest notification |
| `<leader>gu` | User watchlist |

`:checkhealth gh_dashboard` — checks gh CLI, auth, and scopes.
