# gh_dashboard.nvim

A GitHub dashboard inside Neovim. Needs the [gh CLI](https://cli.github.com) authenticated and Neovim 0.10+.

## Install

```lua
{
  "AlexanderInnerbichler/gh_dashboard.nvim",
  cmd  = { "GhDashboard", "GhWatchlist", "GhNotifications", "GhRepoPicker" },
  keys = {
    { "<leader>gh", "<cmd>GhDashboard<cr>",     desc = "GitHub Dashboard" },
    { "<leader>gw", "<cmd>GhWatchlist<cr>",     desc = "GitHub Watchlist" },
    { "<leader>gn", "<cmd>GhNotifications<cr>", desc = "GitHub Notifications" },
    { "<leader>gu", function() require("gh_dashboard.user_watchlist").toggle() end, desc = "GitHub User Watchlist" },
  },
  config = function()
    require("gh_dashboard").setup()
    require("gh_dashboard.reader").setup()
    require("gh_dashboard.watchlist").setup()
    require("gh_dashboard.user_watchlist").setup()
    require("gh_dashboard.notifications").setup()
  end,
}
```

## Config

```lua
require("gh_dashboard").setup({
  cache_ttl         = 300,  -- seconds before cache expires
  poll_interval     = 60,   -- seconds between watchlist polls
  notification_ttl  = 5,    -- seconds before toast dismisses
  max_notifications = 3,    -- max simultaneous toasts
  max_history       = 20,   -- max notification history entries
  window_width      = 0.9,  -- window width as fraction of screen
  stale_pr_days     = 7,    -- PRs older than this get a [stale] tag

  diff = {
    layout          = "side_by_side",  -- or "unified"
    picker_width    = 0.6,             -- file picker width as fraction of screen
    context         = 6,               -- unchanged lines kept visible around hunks
    auto_preview    = true,            -- open the file under the panel cursor
    hide_generated  = true,            -- hide lockfiles and build output by default
    generated_globs = { "*.lock", "package-lock.json", "go.sum", "*.min.js", "dist/*" },
  },
})
```

## Dashboard

`:GhDashboard` (or `<leader>gh`) opens a floating window with:

- **Profile** — name, followers, following, public repos, total contributions, unread notification count
- **Contribution heatmap** — last 20 weeks, colour-coded by intensity; animated duck walks across it
- **Pull Requests** — open PRs where you are author, assignee, or review-requested; tagged `[draft]`, `[review]`, `[stale]`
- **Assigned Issues** — open issues assigned to you across all repos
- **Activity Feed** — chronological events from your repo and user watchlists (your own activity filtered out)

### Dashboard keys

| Key | Action |
|-----|--------|
| `<CR>` / `o` | Open item under cursor (PR/issue reader, repo view, user profile, day activity, notifications) |
| `d` | Open the diff viewer for the PR under cursor |
| `w` | Toggle repo watchlist for repo under cursor |
| `r` | Force refresh (clears cache) |
| `<leader>gw` | Repo watchlist |
| `<leader>gn` | Notifications panel |
| `q` / `<Esc>` | Close |

## PR & Issue Reader

`<CR>` on any PR or issue opens a detail view with the full description, comments, and metadata. On a PR, press `d` to open the diff viewer.

## Diff Viewer

`d` on a PR (from the dashboard or the reader), or `:GhDiff`, opens a file picker listing
every changed file. `<CR>` takes you into the diff; `q` takes you back out to the picker.

```
╭──────── PR #9  you/repo  3/14 viewed ─────────╮
│  14 files  +1911  −1927            no-gen  path│
│─────────────────────────────────────────────────│
│  ✓ M  lua/gh_dashboard/init.lua  +39  −732 ▇▇▇▇▁│
│    D  lua/gh_dashboard/reader.lua +0 −1131 ▇▇▇▇▇│
│    A  lua/gh_dashboard/reader/init.lua +432 ▇▇▁▁│
╰─── <CR> open  <Space> viewed  S sort  q close ╯
```

Inside, the diff takes the full width of the terminal:

```
 base  master                         │ lua/gh_dashboard/init.lua    q files  <Tab> next  ]h hunk  ? help
   1 local M = {}                     │   1 local M = {}
   2 local heatmap = require(…)       │   2 local heatmap    = require(…)
     ------------------------------   │   3 local highlights = require(…)
```

Both sides are real buffers with the file's own filetype, so you get treesitter syntax
highlighting on top of Neovim's diff highlighting — including character-level intra-line
diffs. Unchanged regions are folded away (`zo` to expand). The picker shows every changed
file with its status, `+`/`−` counts and a bar scaled to the largest file in the PR.

Files load lazily — one request for the whole file list, then one blob per file as you open
it, with the next file prefetched in the background.

The most-used keys sit in the winbar above the diff, trimmed to whatever the window fits;
`?` lists all of them.

`:GhDiff` with no argument diffs the pull request for the current branch. `:GhDiff 42` infers
the repo from the working directory; `:GhDiff 42 owner/repo` targets any repo.

### Diff keys

| Key | Action |
|-----|--------|
| `<CR>` / `o` | Open the file under the cursor (picker) |
| `<Tab>` / `<S-Tab>` | Next / previous file |
| `]f` / `[f` | Next / previous file |
| `]h` / `[h` | Next / previous hunk |
| `]x` / `[x` | Next / previous review comment |
| `<Space>` | Mark viewed, jump to next unviewed |
| `u` | Jump to next unviewed file |
| `s` | Toggle side-by-side / unified split |
| `c` | Queue a review comment (normal line or visual range) |
| `A` | Submit review with all queued comments |
| `D` | Discard queued comments |
| `S` | Cycle sort: path / change size / status *(picker)* |
| `f` / `F` | Filter files by substring / toggle generated files *(picker)* |
| `w` | Toggle whitespace-only changes *(picker)* |
| `zo` / `zc` / `zR` / `zM` | Folds |
| `O` / `gy` | Open on github.com / yank a permalink |
| `<C-h>` | Reopen the file picker |
| `r` | Refresh |
| `q` | In the diff: back to the picker  In the picker: close |

Keys marked *(picker)* are bound in the picker only, so `w`, `f`, `F` and `S` stay native
motions in the diff windows.

Which files you have marked viewed is remembered per PR and reset when the PR gets new
commits.

### Reviewing

`c` queues an inline comment rather than posting it immediately — comments show up under
their line tagged `[pending]`, and `A` submits all of them as a **single** GitHub review
(approve, request changes, or comment). Existing review comments are rendered under the
lines they target; comments GitHub can no longer anchor are listed at the bottom of the file
panel instead of being dropped.

## Repo View

`<CR>` on a heatmap day or a repo in the feed opens the repo view: stars, language, description, recent CI runs, and a rendered README preview.

## User Profile

`<CR>` on an activity feed event opens that user's profile: bio, stats, and their recent public activity.

## Watchlists

**Repo watchlist** (`:GhWatchlist` / `<leader>gw`) — add/remove repos to watch. Watched repos appear in the Activity Feed and trigger notification toasts when new events come in.

**User watchlist** (`<leader>gu`) — add/remove GitHub users to watch. Their public events appear in the Activity Feed.

## Notifications

`:GhNotifications` / `<leader>gn` opens the full notification list. Unread count is shown in the dashboard header. Background polling fires toast notifications for new events on your watchlist.

## Keys

The same key means the same thing in every view:

| Key | Everywhere |
|-----|------------|
| `<CR>` / `o` | Open the item under the cursor |
| `q` / `<Esc>` | Back one level, or close at the top |
| `r` | Refresh |
| `x` | Dismiss the item under the cursor (unwatch a repo, mark a notification read, close an issue) |
| `a` | Add (watchlists) |
| `d` | Open a diff. Never destructive. |
| `?` | Keys for the current view |

## Commands

| Command | Description |
|---------|-------------|
| `:GhDashboard` | Toggle dashboard |
| `:GhWatchlist` | Toggle repo watchlist |
| `:GhNotifications` | Toggle notifications panel |
| `:GhRepoPicker` | Fuzzy-search and open a repo |
| `:GhDiff [n] [repo]` | Diff a pull request (current branch if no argument) |
| `:GhDebug` | Show internal debug info |
| `:checkhealth gh_dashboard` | Verify setup |

---

*generated by alex*
