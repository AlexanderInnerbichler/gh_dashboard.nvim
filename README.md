# gh_dashboard.nvim

A GitHub dashboard inside Neovim — contribution heatmap, PR/issue activity, repo watchlist, and user profiles.

## Prerequisites

- [gh CLI](https://cli.github.com) installed and authenticated (`gh auth login`)
- Neovim 0.10+

## Installation

**lazy.nvim (deferred — recommended)**:
```lua
{
  "AlexanderInnerbichler/gh_dashboard.nvim",
  cmd  = { "GhDashboard", "GhWatchlist" },
  keys = {
    { "<leader>gh", "<cmd>GhDashboard<cr>", desc = "GitHub Dashboard" },
    { "<leader>gw", "<cmd>GhWatchlist<cr>",  desc = "GitHub Watchlist" },
  },
  config = function()
    require("gh_dashboard").setup()
    require("gh_dashboard.reader").setup()
    require("gh_dashboard.watchlist").setup()
    require("gh_dashboard.user_watchlist").setup()
  end,
}
```

**lazy.nvim (eager)**:
```lua
{ "AlexanderInnerbichler/gh_dashboard.nvim", lazy = false }
```

**From a local clone** (development):
```lua
{ dir = vim.fn.expand("~/gh_dashboard.nvim"), lazy = false, dev = true }
```

## Setup

```lua
require("gh_dashboard").setup({
  -- all keys are optional; shown values are defaults
  cache_ttl         = 300,  -- seconds before dashboard cache is stale
  poll_interval     = 60,   -- seconds between watchlist polls
  notification_ttl  = 5,    -- seconds before a toast auto-dismisses
  max_notifications = 3,    -- maximum simultaneous toasts
  max_history       = 20,   -- maximum notification history entries
  window_width      = 0.9,  -- window width as fraction of screen (0–1)
})
require("gh_dashboard.reader").setup()
require("gh_dashboard.watchlist").setup()
require("gh_dashboard.user_watchlist").setup()
```

No options are required. The plugin derives your GitHub username from `gh api user`.

## Keymaps

| Keymap | Action |
|--------|--------|
| `<leader>gh` | Toggle the GitHub dashboard |
| `<leader>gw` | Toggle the repo watchlist |
| `<leader>gn` | Open latest watchlist notification |
| `<leader>gu` | Toggle the user activity watchlist |

## Health check

```
:checkhealth gh_dashboard
```

Reports `gh` CLI presence, authentication status, and token scopes.

## Dashboard panels

- **Contribution heatmap** — 52-week grid, Sunday-first rows
- **Contributions total** — year-to-date count
- **Recent activity** — push, PR, issue, fork, star events
- **Open PRs** — PRs across watched repos
- **Watched users** — activity from followed GitHub users
