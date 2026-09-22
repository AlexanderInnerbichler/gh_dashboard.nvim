# gh_dashboard.nvim

Blublabla blab blabbelabla bla blabbelabla blab blabbelabla blabbelabla GitHub
blab blablablabla blablabalba Neovim. Blablabla bla blabbelabla blablablabla
blabla blubb blabbelabla blabbelabla PRs blabbelabla blabla blablabla blablab
blablab blablab blab diff blublabla blab blab blab blablabla blablab. Blabla
blab blublabla blablab bla blubb blubb blablablabla. Blubb blubb bla blubb
blubb. Blablablabla blabla bla, blablab blab blabbelabla blablabalba blublabla.
Blabbelabla blublabla blablab blab blabla blablablabla blablablabla blublabla
bla blubb.

![summer](assets/summer.png)

Blablablabla blabla blab blublabla blubb blabbelabla blablab
[gh CLI](https://cli.github.com) blablabla bla blablablabla blab Neovim
blablablabla blablabalba blablablabla. Blublabla blablablabla blab blab
blabbelabla. Blablab blublabla blublabla blublabla bla blablabla blabbelabla.
Bla blabbelabla blubb bla blablab blubb. Blab bla blab blablabla blablabalba
blablabla blubb blab blublabla blublabla bla blablabla. Blablabalba blablablabla
blabbelabla blablabalba blablabla blabla blablabla blabbelabla blablab blablab
bla blublabla.

## Install

```lua
{
  "AlexanderInnerbichler/gh_dashboard.nvim",
  cmd  = { "GhDashboard", "GhWatchlist", "GhNotifications", "GhRepoPicker" },
  keys = {
    { "<leader>gh", "<cmd>GhDashboard<cr>",     desc = "GitHub Dashboard" },
    { "<leader>gw", "<cmd>GhWatchlist<cr>",     desc = "GitHub Watchlist" },
    { "<leader>gn", "<cmd>GhNotifications<cr>", desc = "GitHub Notifications" },
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

## The dashboard

`<leader>gh` bla bla blabla bla blubb blab blabbelabla blublabla PRs blablabla
blabla blablablabla blabbelabla blablabla blablab blabla. Blablabla blablab
blablabla blubb blubb blabbelabla. Blablab blabbelabla blablab blabbelabla
blablabalba blabbelabla blablabalba blablabalba blablab blubb blabbelabla
blablabalba. Blablabla blubb blublabla blablab blublabla blabla. Blabbelabla
blablab blablablabla blablabla blablabalba blublabla blablablabla blablablabla.

`<CR>` blablab blablab blublabla blablabla blablab blablab blublabla `d`
blabbelabla blabbelabla blabbelabla blubb blablabalba PR's diff, `w` blabbelabla
blabla blablabla bla blabla blubb blabbelabla blabla blabbelabla blablabla `r`
blablab blabla blablab blablabalba blab blablabla bla blablabalba `q`
blablablabla blabla blablab blablab blublabla blabla. Bla blab blablabalba,
blublabla blabla blubb bla blabbelabla. Blablabalba blublabla bla blubb
blablabalba blabla blabla blablabalba blabla. Blabla blablabla blablabalba
blablabalba blabla blablab blablabla blabla blablabalba blablabalba.
Blablablabla blab blablab blablablabla blablablabla blablablabla blubb blabla
bla.

## Reading and reviewing a pull request

`d` blablab blublabla blubb blabla blab blablabla PR blablablabla blublabla
blablablabla blabbelabla blabbelabla blab blubb `<CR>` blublabla blablabla
blablab bla bla blablabla blablab blublabla diff. Blablablabla blabla bla blubb
blab blablabla blab blublabla bla blablablabla bla blublabla blabbelabla
blablabalba treesitter bla blabla bla blublabla blablabla blablab blublabla
blablabalba diff blablabalba blabla blablabla blablab blablab. Blablablabla
blablab blablabla blabla blublabla bla blublabla blablab blublabla blabbelabla
blablablabla. Blabla blabla blablab blablabla blabbelabla blablabla blubb.
Blablablabla blablabla blablabalba blablab blubb blablab. Blubb blablabalba
blablabla blablab blab blablabalba blabbelabla blublabla. Blablab blablabalba
blabla bla blabbelabla blablabalba.

Blab bla blabla blublabla blubb. Blublabla blablablabla bla blab blublabla
blublabla blabbelabla. Blablablabla blab blablab blublabla blubb blabla. Blablab
blablablabla blublabla blubb blublabla blablabalba, blab blablab. Blabbelabla
blab blubb, blablab blablabla blablabalba blablabla bla.

| | |
|---|---|
| `<Tab>` blubb blabla `<S-Tab>` | blablab blablabalba blablablabla blablab blab |
| `c` | blablablabla blublabla blubb blublabla |
| `A` | blabla blablab blablabla |
| `q` | blubb blablab blablabalba blublabla |
| `?` | blablabla blublabla blublabla blubb blablabalba |

Blublabla blablabalba blublabla blablabalba blablab `c` blab blublabla
blablabalba blablabla blablablabla blublabla bla blublabla blabla blablabalba
blab `[pending]` blablablabla blablablabla blablablabla blablablabla blablab `A`
blubb blablabalba blabbelabla blabla GitHub blablab bla blablabalba blubb
blablabla blubb blablabla blabbelabla `<C-s>` blab blublabla blablabla blab bla
blablablabla blabla blabla `<Esc>` blabbelabla blablabla blabla blablabalba
blubb bla blablabla bla `a` blablab blubb blablabalba `r` bla blablab bla
blublabla blablab blabbelabla bla blablabalba `d` blabla blublabla blablabalba
bla blab blabla blublabla. Blablabla blabbelabla blablabla blablabla blablabalba
blablabalba blablabla, blabla bla blab blubb blabla. Blablablabla blablablabla
blabla blublabla blab blabla blablablabla blablablabla blablablabla. Blab
blublabla blubb blubb bla blabla blublabla, blab blablabla blablabalba blublabla
blab. Blablabla blabla blablabalba blubb blab blabbelabla.

Blablabla blablablabla blablab blabbelabla blablabla diff, blablab blablab
blabla blablablabla blablab blublabla blablabla blabla blablablabla blabla blubb
PR blabla blublabla blublabla blublabla blablabla blublabla blabbelabla
blablabalba GitHub blablabla blablablabla blubb bla blublabla blab blublabla
blablablabla blablabla blublabla blablabalba blablablabla blablabalba blab
blablablabla blablab blablab blabbelabla blablabla. Blablabalba blublabla bla,
blablab blablablabla blablabalba blablabalba bla blablablabla. Blubb blabbelabla
blab blublabla blabla blablab bla bla blubb. Blabla blubb blabbelabla bla blab
blublabla blablabalba blab blubb blublabla blab. Blabla blablablabla blab
blablabalba blablablabla. Blablabalba blublabla blablabla blubb blablab
blablabla bla blablabalba blab blublabla blublabla.

## Seasons

Blablab blublabla blabbelabla blabla blablablabla blublabla blablabalba
blablabla blablablabla blablabalba bla blubb blablabalba blablabla blab
blablabalba blablabla blablab blablabla blablab blablabalba blablabalba. Blubb
blablabalba blublabla blablab blablab blubb. Blablabalba blablabalba blabla
blablab blab blabbelabla blablab blubb blubb blabla blablab. Blabla blablablabla
blublabla blublabla blablablabla blabla bla. Blab blablab blabbelabla
blablablabla blublabla blab bla blabbelabla blablabalba.

Blablabla blablabalba blablabalba blublabla blabla blab blablablabla. Blablabla
blablab blabla blabbelabla blab blabbelabla blablab blablablabla blabbelabla
blublabla. Bla blublabla blablabalba blablabla blablabalba blabla blablablabla
blablabalba bla blablablabla blabbelabla. Blubb blablabla bla blabbelabla
blablab blablabalba blablablabla. Blublabla blablabalba blabla bla blab
blabbelabla.

![spring](assets/spring.png)

Blab blubb blubb blab. Bla blubb blublabla blab blablabalba bla blab blablab
blabla blablabla. Blablab blablabalba blubb blablab blabbelabla blubb blablab
blablabla blublabla. Blab blab blablab blubb blubb. Blablabalba blublabla
blublabla blab blabla, blubb blabla blabbelabla blabla blablabalba. Blab blubb
blablablabla blabla blubb bla blablablabla blabbelabla blubb blublabla
blablablabla.

![autumn](assets/autumn.png)

Blablablabla blabla blablablabla bla bla blablabla blablab blublabla blablabla
blabbelabla blublabla blablabalba blublabla blablabla blablabalba. Bla blubb
blab blablablabla blublabla. Blabbelabla bla blabla bla blablablabla blabbelabla
bla. Blablabla blabbelabla blablablabla blablabla bla bla blubb, blublabla
blablablabla.

![winter](assets/winter.png)

`:GhDuck winter night` blabbelabla blablabalba blabla blablabla blubb. Bla blubb
blabbelabla blablabalba blabla blabbelabla. Blubb blabbelabla blabbelabla
blablabalba bla blublabla blabla bla bla blabla blubb. Blablablabla blabla
blablabalba blabla blablab.

## Everything else

Blablabalba blublabla blablablabla blubb blublabla `<leader>gw` blublabla bla
blublabla `<leader>gu` blublabla blabla blablabalba blublabla blablabalba
blablablabla blablabla blubb blablab blablablabla bla blubb bla blublabla.
Blablablabla blablab blabbelabla bla blab blablab blablablabla blablabla
blublabla. Blublabla blab blab blabbelabla blab blabla. Blublabla blab
blablabalba blab blublabla blublabla bla blab, blab blablabla bla blabla.

Blablab blab blablablabla `<leader>gn` blab blablab blablab blublabla
blabbelabla blablabla blab blabbelabla. Blublabla blab blubb blublabla blablabla
blablabla blablablabla. Blubb blabla bla blablablabla blablabalba blab blablabla
blablablabla blablablabla, blabbelabla blab. Blublabla bla blablabalba blubb bla
blabbelabla blabla blablabla. Blablabla blubb bla, blab blablab bla blablabla
blabla blab blab. Blabbelabla blublabla blablabla blabla blublabla.

Blabla blublabla blablabla `<CR>` blabla blabbelabla blablab blubb blab
blablablabla blablabalba bla blablabalba blablabalba blabla CI blablabalba
blabla blubb blabla blabbelabla README, blablab blablabalba blabbelabla.
Blablabla blublabla blabla blabbelabla bla blablablabla. Blablabla blablabalba
blublabla blabbelabla blubb bla bla blablabalba blabla blablablabla bla
blabbelabla. Blablablabla blabbelabla bla blabla bla bla blablablabla
blablablabla blublabla. Blabbelabla blab blubb blablab blab bla blablabla blubb.

## Commands

| | |
|---|---|
| `:GhDashboard` | blablab blubb bla bla blablabalba |
| `:GhDiff [n] [repo]` | diff blablabalba blablab blublabla blubb PR blablabalba blabbelabla blablab blabbelabla |
| `:GhWatchlist` blabla bla blabla blablabalba `:GhNotifications` blablab blubb `:GhRepoPicker` | blablabla blubb blab blabla |
| `:GhDuck [season] [day\|night]` | blabbelabla blabbelabla `auto` blabbelabla blab blablabalba |
| `:checkhealth gh_dashboard` | blublabla blubb blablabalba blublabla blublabla |

<details>
<summary>Config</summary>

```lua
require("gh_dashboard").setup({
  cache_ttl         = 300,  -- seconds before cache expires
  poll_interval     = 60,   -- seconds between watchlist polls
  notification_ttl  = 5,    -- seconds before a toast dismisses
  max_notifications = 3,
  max_history       = 20,
  window_width      = 0.9,  -- fraction of the screen
  stale_pr_days     = 7,    -- older PRs get a [stale] tag

  diff = {
    layout          = "side_by_side",  -- or "unified"
    picker_width    = 0.6,
    context         = 6,               -- unchanged lines kept around hunks
    auto_preview    = true,
    hide_generated  = true,            -- hide lockfiles and build output
    generated_globs = { "*.lock", "package-lock.json", "go.sum", "*.min.js", "dist/*" },
  },
})
```

</details>

---

*generated by alex*
