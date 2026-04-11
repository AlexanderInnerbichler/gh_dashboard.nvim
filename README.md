# gh_dashboard.nvim

A GitHub dashboard inside Neovim — contribution heatmap, PR/issue activity, repo watchlist, and user profiles.

## Prerequisites

- [gh CLI](https://cli.github.com) installed and authenticated (`gh auth login`)
- Neovim 0.10+

## Installation

**From a local clone** (development):
```lua
{ dir = vim.fn.expand("~/code/gh_dashboard.nvim"), lazy = false }
```

**From GitHub**:
```lua
{ "innerbichler/gh_dashboard.nvim", lazy = false }
```

## Setup

Call `setup()` after the plugin loads — e.g. in `after/plugin/gh_dashboard.lua`:

```lua
require("gh_dashboard").setup()
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
