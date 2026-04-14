# Agent Context: claude

**Feature**: feature/002-refactor-code-structure
**Updated**: 2026-04-14

## Technology Stack

<!-- BEGIN:MANAGED -->
- Language: Lua (Neovim plugin)
- Runtime: Neovim 0.10+ built-in APIs only (`vim.api`, `vim.system`, `vim.uv`, `vim.fn`)
- External tool: `gh` CLI (all GitHub API calls go through it)
- No third-party Lua libraries
<!-- END:MANAGED -->

## Manual Notes

- `run_gh` in 4 files: init.lua, reader.lua, watchlist.lua, user_profile.lua
- watchlist.lua uses diverged callback(data) form — needs adapting to callback(err, data) in Phase 1
- ColorScheme autocmds in 4 files: init.lua, reader.lua, watchlist.lua, user_watchlist.lua
- nvim_set_hl in 4 files: init.lua, reader.lua, watchlist.lua, user_watchlist.lua
- reader/ directory: Neovim resolves require("gh_dashboard.reader") → reader/init.lua automatically
