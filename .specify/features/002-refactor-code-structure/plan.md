# Implementation Plan: Code Structure Refactor

**Branch**: feature/002-refactor-code-structure
**Spec**: /home/alexander/gh_dashboard.nvim/.specify/features/002-refactor-code-structure/spec.md
**Created**: 2026-04-14

---

## Constitution Check

| Principle | Compliant? | Notes |
|-----------|------------|-------|
| Zero External Dependencies | ✅ | No new dependencies introduced; pure restructuring |
| Non-Blocking by Default | ✅ | Async pattern preserved in shared `gh.lua`; no behaviour change |
| Minimal, Discoverable UI | ✅ | No UI changes |
| Configuration-Driven Behaviour | ✅ | No hardcoded values added or changed |
| Single Responsibility per Module | ✅ | This plan is specifically designed to enforce this principle |

---

## Technical Context

**Affected modules**:
- `lua/gh_dashboard/init.lua` — split into orchestrator + `dashboard/fetch.lua` + `dashboard/render.lua`
- `lua/gh_dashboard/reader.lua` — converted to `reader/init.lua` + `reader/fetch.lua` + `reader/render.lua` + `reader/actions.lua`
- `lua/gh_dashboard/watchlist.lua` — remove local `run_gh`, update ColorScheme handler
- `lua/gh_dashboard/user_profile.lua` — remove local `run_gh`
- `lua/gh_dashboard/user_watchlist.lua` — remove local `nvim_set_hl` calls, update ColorScheme handler

**New modules**:
- `lua/gh_dashboard/gh.lua` — shared async gh runner
- `lua/gh_dashboard/highlights.lua` — all highlight group definitions, single ColorScheme handler
- `lua/gh_dashboard/dashboard/fetch.lua` — all `fetch_*()` functions from `init.lua`
- `lua/gh_dashboard/dashboard/render.lua` — all `render_*()` and line/hl builder functions from `init.lua`
- `lua/gh_dashboard/reader/init.lua` — thin orchestrator (replaces `reader.lua` as public entry point)
- `lua/gh_dashboard/reader/fetch.lua` — all `fetch_*()` functions from `reader.lua`
- `lua/gh_dashboard/reader/render.lua` — all rendering/markdown/diff functions from `reader.lua`
- `lua/gh_dashboard/reader/actions.lua` — `post_comment`, `submit_review`, `merge_pr`, `close_issue`

**External dependencies**: None

**Breaking changes**: No — public require paths unchanged. Internal module paths are new but
not part of the public API.

---

## Research Summary

See `research.md` for full rationale. Key decisions:

- **`run_gh` signature**: Unified to `callback(err, data)`. Watchlist callers adapt by adding `if not err then` guard (trivial).
- **Reader layout**: Nested directory `reader/` — public path `require("gh_dashboard.reader")` resolves to `reader/init.lua` automatically.
- **Dashboard layout**: Nested directory `dashboard/` — `init.lua` stays as thin orchestrator.
- **Highlights calling**: Each module's `setup()` calls `highlights.setup()` with an internal guard preventing double-registration.

---

## Data Model Changes

No data model changes. Cache file format, watchlist JSON, and user-watchlist JSON are untouched.

---

## Implementation Phases

### Phase 1: Shared `gh.lua` helper (Issue #1)

**Goal**: Extract the `run_gh` pattern into a single shared module; remove all local copies.
**Deliverable**: Plugin loads without error; all dashboard data fetches and watchlist polls work correctly.

Tasks:
- [ ] Create `lua/gh_dashboard/gh.lua` with `M.run(args, callback)` using the `callback(err, data)` signature
- [ ] Replace local `run_gh` in `init.lua` with `require("gh_dashboard.gh").run`
- [ ] Replace local `run_gh` in `reader.lua` with `require("gh_dashboard.gh").run`
- [ ] Replace local `run_gh` in `user_profile.lua` with `require("gh_dashboard.gh").run`
- [ ] Replace local `run_gh` in `watchlist.lua` with `require("gh_dashboard.gh").run`; adapt callers from `callback(data)` to `callback(err, data)` form (add `if not err then` guard at each call site)
- [ ] Verify: open dashboard, open a PR in reader, trigger watchlist poll — all data loads correctly

### Phase 2: Centralized `highlights.lua` (Issue #3)

**Goal**: Move all `nvim_set_hl` calls and ColorScheme autocmds into a single module.
**Deliverable**: Toggling colorscheme updates all highlights in one event; no module registers its own ColorScheme handler.

Tasks:
- [ ] Create `lua/gh_dashboard/highlights.lua` with `M.setup()` and an internal `registered` guard
- [ ] Move all `nvim_set_hl` calls from `init.lua` into `highlights.lua`
- [ ] Move all `nvim_set_hl` calls from `reader.lua` into `highlights.lua`
- [ ] Move all `nvim_set_hl` calls from `watchlist.lua` into `highlights.lua`
- [ ] Move all `nvim_set_hl` calls from `user_watchlist.lua` into `highlights.lua`
- [ ] Remove the four per-module `ColorScheme` autocmd registrations; add one in `highlights.lua`
- [ ] Call `require("gh_dashboard.highlights").setup()` from each module's existing `setup()` function
- [ ] Verify: change colorscheme (`:colorscheme default`) and reopen dashboard — all highlight groups render correctly

### Phase 3: Split `init.lua` (Issue #5, part 1)

**Goal**: Decompose `init.lua` (~992 lines) into fetch / render / orchestrator layers.
**Deliverable**: Dashboard opens and renders all panels correctly; `init.lua` is under 200 lines.

Tasks:
- [ ] Create `lua/gh_dashboard/dashboard/` directory
- [ ] Create `lua/gh_dashboard/dashboard/fetch.lua` — move all `fetch_*()` functions (`fetch_profile`, `fetch_prs`, `fetch_issues`, `fetch_activity`, `fetch_contributions`, `fetch_repos`, `fetch_org_repos`, `fetch_team_activity`, `fetch_watched_users_activity`) and their direct helpers
- [ ] Create `lua/gh_dashboard/dashboard/render.lua` — move all `render_*()` functions, `apply_render()`, `write_buf()`, and line/highlight builder utilities
- [ ] Update `init.lua` to require both sub-modules; keep only: state table, cache I/O, `open_win()`, `toggle()`, `setup()`, keymap registration, and the `fetch_and_render()` orchestrator
- [ ] Verify: all dashboard panels (heatmap, profile, PRs, issues, activity, repos, org repos, team activity, watched users) render correctly
- [ ] Verify: `init.lua` ≤ 200 lines; `dashboard/fetch.lua` ≤ 400 lines; `dashboard/render.lua` ≤ 400 lines

### Phase 4: Split `reader.lua` (Issue #5, part 2)

**Goal**: Decompose `reader.lua` (~1131 lines) into fetch / render / actions / orchestrator layers.
**Deliverable**: All reader interactions work; `require("gh_dashboard.reader")` still resolves correctly; reader orchestrator is under 150 lines.

Tasks:
- [ ] Create `lua/gh_dashboard/reader/` directory
- [ ] Create `lua/gh_dashboard/reader/fetch.lua` — move `fetch_pr()`, `fetch_issue()`, `fetch_comments()`, `fetch_diff()`, `fetch_checks()`, `fetch_review_comments()` and their helpers
- [ ] Create `lua/gh_dashboard/reader/render.lua` — move all markdown rendering, diff rendering, CI check rendering, review/comment formatting functions
- [ ] Create `lua/gh_dashboard/reader/actions.lua` — move `M.post_comment()`, `M.submit_review()`, `M.merge_pr()`, `M.close_issue()`
- [ ] Create `lua/gh_dashboard/reader/init.lua` — thin orchestrator with `M.open()`, `M.open_diff()`, `M.open_input()`, `M.setup()`, window management, keymap registration; require the three sub-modules
- [ ] Delete original `lua/gh_dashboard/reader.lua` (now replaced by the directory)
- [ ] Verify: open a PR → read comments → post a comment → submit a review → view diff → merge confirmation works end-to-end
- [ ] Verify: each file in `reader/` is ≤ 400 lines

---

## Rollout & Verification

Execute all four phases in order on the `feature/002-refactor-code-structure` branch.
After each phase, manually verify in Neovim before proceeding:

1. `:lua require("gh_dashboard").toggle()` — dashboard opens with all panels
2. Press `<CR>` on a PR → reader opens with body and comments
3. Press `c` → comment input opens; press `<Esc>` to cancel
4. Press `d` → diff view renders
5. Press `<leader>gw` → watchlist manager opens
6. Press `<leader>gu` → user watchlist opens
7. `:checkhealth gh_dashboard` → all checks pass
8. `:colorscheme desert` then reopen dashboard → highlights correct

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Circular require between new sub-modules | Low | High | Pass shared state (buf, win, ns) as function arguments rather than module-level upvalues where needed |
| `require("gh_dashboard.reader")` fails after directory conversion | Low | High | Neovim resolves `reader` → `reader/init.lua` automatically; verify with a quick `:lua print(require("gh_dashboard.reader"))` before and after |
| watchlist `run_gh` callback adaptation introduces a regression | Medium | Medium | The adaptation is mechanical (`if not err then ... end`); test watchlist poll immediately after Phase 1 |
| Split increases require startup time | Low | Low | Lua module caching means each `require` path is loaded once; no measurable overhead for ~6 new files |
