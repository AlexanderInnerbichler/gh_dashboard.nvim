# Tasks: Code Structure Refactor

**Branch**: feature/002-refactor-code-structure
**Plan**: .specify/features/002-refactor-code-structure/plan.md
**Generated**: 2026-04-14

---

## Summary

- Total tasks: 22
- Phases: Setup + 4 user story phases + Polish
- Parallelizable tasks: 10 (marked [P])

---

## Phase 1: Setup

**Goal**: Create the new directory structure required by the split modules.

- [x] T001 [P] Create lua/gh_dashboard/dashboard/ directory (mkdir -p lua/gh_dashboard/dashboard)
- [x] T002 [P] Create lua/gh_dashboard/reader/ directory (mkdir -p lua/gh_dashboard/reader)

---

## Phase 2: US1 — Shared GitHub Command Helper

**Story goal**: A single shared module provides the async `gh` CLI runner; no module defines its own copy.

**Test criteria**: After this phase — open the dashboard (`<leader>gh`), verify all panels load data; open a PR in the reader, verify body and comments display; trigger a watchlist poll (add a repo via `<leader>gw`). All data loads without error.

- [x] T00X [US1] Create lua/gh_dashboard/gh.lua with `M.run(args, callback)` implementing the unified `callback(err, data)` signature: `vim.system(args, { text = true }, function(result) vim.schedule(function() ... end) end)`
- [x] T00X [P] [US1] Remove the local `run_gh` function from lua/gh_dashboard/init.lua and replace all call sites with `require("gh_dashboard.gh").run`
- [x] T00X [P] [US1] Remove the local `run_gh` function from lua/gh_dashboard/reader.lua and replace all call sites with `require("gh_dashboard.gh").run`
- [x] T00X [P] [US1] Remove the local `run_gh` function from lua/gh_dashboard/user_profile.lua and replace all call sites with `require("gh_dashboard.gh").run`
- [x] T00X [P] [US1] Remove the local `run_gh` function from lua/gh_dashboard/watchlist.lua and replace all call sites with `require("gh_dashboard.gh").run`; adapt the simplified `callback(data)` callers to the `callback(err, data)` form by adding `if not err then` guards at each call site

---

## Phase 3: US2 — Centralized Highlight Definitions

**Story goal**: All highlight group definitions and the ColorScheme re-application handler live in one module; no other module calls the highlight-setting API.

**Test criteria**: After this phase — run `:colorscheme desert` then reopen the dashboard and reader; verify all highlight groups (section headers, heatmap tiers, diff colours, CI status) render correctly.

- [x] T00X [US2] Create lua/gh_dashboard/highlights.lua with `M.setup()`, an internal `local registered = false` guard, a single `local function apply()` containing every `vim.api.nvim_set_hl` call currently spread across init.lua, reader.lua, watchlist.lua, and user_watchlist.lua, and one `ColorScheme` autocmd that calls `apply()`
- [x] T00X [P] [US2] Remove all `vim.api.nvim_set_hl` calls and the `ColorScheme` autocmd from lua/gh_dashboard/init.lua; add `require("gh_dashboard.highlights").setup()` to `M.setup()`
- [x] T010 [P] [US2] Remove all `vim.api.nvim_set_hl` calls and the `ColorScheme` autocmd from lua/gh_dashboard/reader.lua; add `require("gh_dashboard.highlights").setup()` to `M.setup()`
- [x] T011 [P] [US2] Remove all `vim.api.nvim_set_hl` calls and the `ColorScheme` autocmd from lua/gh_dashboard/watchlist.lua; add `require("gh_dashboard.highlights").setup()` to `M.setup()`
- [x] T012 [P] [US2] Remove all `vim.api.nvim_set_hl` calls and the `ColorScheme` autocmd from lua/gh_dashboard/user_watchlist.lua; add `require("gh_dashboard.highlights").setup()` to `M.setup()`

---

## Phase 4: US3 — Split init.lua

**Story goal**: The dashboard module's data fetching and display rendering are in separate, clearly named files; `init.lua` is a thin orchestrator.

**Test criteria**: After this phase — open the dashboard; verify all panels render (heatmap, profile stats, open PRs, issues, recent activity, repos, org repos, team activity, watched users); confirm `init.lua` is ≤ 200 lines and neither `dashboard/fetch.lua` nor `dashboard/render.lua` exceeds 400 lines.

- [x] T013 [US3] Create lua/gh_dashboard/dashboard/fetch.lua by moving these functions from init.lua: `fetch_profile`, `fetch_prs`, `fetch_issues`, `fetch_activity`, `fetch_contributions`, `fetch_repos`, `fetch_org_repos`, `fetch_team_activity`, `fetch_watched_users_activity`; expose them via the module return table; require `gh_dashboard.gh` for the runner
- [x] T014 [P] [US3] Create lua/gh_dashboard/dashboard/render.lua by moving these functions from init.lua: `render_profile`, `render_prs`, `render_issues`, `render_activity`, `render_repos`, `render_org_repos`, `render_team_activity`, `render_watched_users`, `apply_render`, `write_buf`, and all line/highlight builder helpers; expose them via the module return table
- [x] T015 [US3] Update lua/gh_dashboard/init.lua to `require("gh_dashboard.dashboard.fetch")` and `require("gh_dashboard.dashboard.render")`; remove all moved functions; verify the file retains only: module-level state table, cache I/O helpers, `open_win()`, `toggle()`, `setup()`, keymap registration, and `fetch_and_render()` orchestrator; confirm line count ≤ 200

---

## Phase 5: US4 — Split reader.lua

**Story goal**: The reader module's data fetching, rendering, and mutation actions are in separate files; `require("gh_dashboard.reader")` continues to resolve to the public entry point.

**Test criteria**: After this phase — open a PR (`<CR>` on a PR in the dashboard); verify body and comments display; press `c` and cancel to confirm input modal opens; press `d` to verify diff renders; press `a` to confirm review modal opens; press `m` and verify merge confirmation prompt appears; press `x` on an issue and verify close prompt appears. Confirm each file in `reader/` is ≤ 400 lines.

- [x] T016 [US4] Create lua/gh_dashboard/reader/fetch.lua by moving these functions from reader.lua: `fetch_pr`, `fetch_issue`, `fetch_comments`, `fetch_diff`, `fetch_checks`, `fetch_review_comments`; expose via module return table; require `gh_dashboard.gh` for the runner
- [x] T017 [P] [US4] Create lua/gh_dashboard/reader/render.lua by moving all rendering functions from reader.lua: markdown body renderer, code block formatter, diff renderer, CI check renderer, review/comment formatters, and all line/highlight builder helpers; expose via module return table
- [x] T018 [P] [US4] Create lua/gh_dashboard/reader/actions.lua by moving from reader.lua: `M.post_comment`, `M.submit_review`, `M.merge_pr`, `M.close_issue`; these functions use `vim.system` directly (not the gh helper) for mutation commands — keep that pattern; expose via module return table
- [x] T019 [US4] Create lua/gh_dashboard/reader/init.lua as the thin orchestrator: `M.open`, `M.open_diff`, `M.open_input`, `M.setup`, window and buffer management, keymap registration; require fetch, render, and actions sub-modules; ensure `local state` table is defined here as it is shared across interactions
- [x] T020 [US4] Delete lua/gh_dashboard/reader.lua after verifying `:lua require("gh_dashboard.reader").open` resolves to reader/init.lua and the full interaction flow works end-to-end

---

## Final Phase: Polish & Cross-Cutting Concerns

**Goal**: Verify line-count targets, run health check, confirm no regressions.

- [x] T021 Check line counts for all modified and new files: init.lua ≤ 200, reader/init.lua ≤ 150, dashboard/fetch.lua ≤ 400, dashboard/render.lua ≤ 400, reader/fetch.lua ≤ 400, reader/render.lua ≤ 400, reader/actions.lua ≤ 400, gh.lua ≤ 30, highlights.lua ≤ 150; split any file that exceeds its target
- [x] T022 Run `:checkhealth gh_dashboard` in Neovim and verify all checks pass (gh CLI present, authenticated, read:user scope)

---

## Dependency Graph

```
T001 ──┐
T002 ──┘ (parallel setup)
        │
T003 ───┤ (gh.lua must exist before all T004–T007)
        ├── T004 [P]
        ├── T005 [P]
        ├── T006 [P]
        └── T007 [P]
              │
T008 ─────────┤ (highlights.lua must exist before T009–T012)
              ├── T009 [P]
              ├── T010 [P]
              ├── T011 [P]
              └── T012 [P]
                    │
        ┌───────────┴───────────┐
        │                       │
  T013 + T014 [P]         T016 + T017 [P] + T018 [P]
        │                       │
       T015                   T019
                                │
                              T020
                                │
                          T021 + T022
```

---

## Parallel Execution Examples

**US1** — after T003 is complete, run T004–T007 in parallel (each touches a different file):
```
T004 ‖ T005 ‖ T006 ‖ T007
```

**US2** — after T008 is complete, run T009–T012 in parallel:
```
T009 ‖ T010 ‖ T011 ‖ T012
```

**US3** — T013 and T014 can be written in parallel, then T015 wires them together:
```
T013 ‖ T014 → T015
```

**US4** — T016, T017, T018 can be written in parallel, then T019 assembles them:
```
T016 ‖ T017 ‖ T018 → T019 → T020
```

**US3 and US4** — the two splits are independent and can be executed in parallel after US2:
```
(T013 ‖ T014 → T015) ‖ (T016 ‖ T017 ‖ T018 → T019 → T020)
```

---

## MVP Scope

Minimum viable: **Phase 2 only (US1 — shared gh.lua)**

This is the highest-value, lowest-risk change. It eliminates duplication, improves error
visibility in the watchlist, and is a prerequisite that makes all subsequent phases cleaner.
The remaining phases can be done independently in follow-up PRs if needed.
