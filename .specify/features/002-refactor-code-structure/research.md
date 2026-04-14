# Research: Code Structure Refactor

**Feature**: feature/002-refactor-code-structure
**Date**: 2026-04-14

---

## Decision 1: Unified `run_gh` callback signature

**Question**: `watchlist.lua` uses `callback(data_or_nil)` (no error arg), while the other
three modules use `callback(err, data)`. Which signature should the shared module adopt?

**Decision**: `callback(err, data)` — the full error-propagating form used by `init.lua`,
`reader.lua`, and `user_profile.lua`.

**Rationale**: Three of the four call sites already use this form. The `watchlist.lua`
variant silently discards errors, which is why polling failures are invisible to the user
(issue #6). Adopting the richer signature in the shared module means `watchlist.lua` callers
update to `if not err then ... end` — a trivial one-line change per call site with no
behaviour regression, and sets up future error-surfacing improvements cleanly.

**Alternatives considered**:
- Keep the watchlist variant as a second helper function → adds complexity without benefit;
  every future caller would need to choose between two nearly-identical helpers.

---

## Decision 2: Reader split — nested directory vs flat siblings

**Question**: Should `reader.lua` split into `reader/init.lua` + sub-modules (nested), or
into flat sibling files like `reader_fetch.lua`, `reader_render.lua`?

**Decision**: Nested directory — `lua/gh_dashboard/reader/init.lua` as the public entry
point, with `fetch.lua`, `render.lua`, and `actions.lua` as sub-modules inside
`lua/gh_dashboard/reader/`.

**Rationale**: Neovim's Lua loader maps `require("gh_dashboard.reader")` to
`lua/gh_dashboard/reader/init.lua` automatically, so the public require path is unchanged.
The nested layout makes the ownership boundary explicit in the filesystem. Flat sibling
names like `reader_fetch.lua` would still appear at the top level and make the directory
feel cluttered as the plugin grows.

**Alternatives considered**:
- Flat siblings (`reader_fetch.lua` etc.) → pollutes top-level directory, no path-stability
  advantage over the nested form.

---

## Decision 3: Dashboard split — subdirectory vs in-place reorganisation

**Question**: Should the dashboard split follow the same nested-directory pattern, or keep
everything at the top level since `init.lua` is already the Lua package root?

**Decision**: Nested directory — `lua/gh_dashboard/dashboard/fetch.lua` and
`lua/gh_dashboard/dashboard/render.lua`. `init.lua` remains as the thin orchestrator and
public entry point (unchanged require path).

**Rationale**: Mirrors the reader split pattern for consistency. `init.lua` stays exactly
where it is (it IS `require("gh_dashboard")`); the subdirectory only contains internal
implementation files that no external caller touches.

**Alternatives considered**:
- Keep everything in `lua/gh_dashboard/` with names like `gh_dashboard_fetch.lua` →
  inconsistent with reader split, hard to distinguish from other modules at a glance.

---

## Decision 4: How `highlights.lua` gets called

**Question**: Should each module's `setup()` call `highlights.setup()`, or should there be
a single call from a top-level initializer?

**Decision**: Each module's `setup()` calls `require("gh_dashboard.highlights").setup()`.
`highlights.lua` internally guards with a module-level boolean so highlights are registered
exactly once regardless of how many times `setup()` is called.

**Rationale**: This matches the existing convention (each module is independently
`setup()`-able). It avoids creating a mandatory call-order dependency where one module must
be set up before others. The guard is trivial: `if registered then return end; registered = true`.

**Alternatives considered**:
- Single top-level call only → requires user to call a separate init function or know the
  right call order; breaks existing setup convention.
- No guard, allow duplicate calls → redundant work on colorscheme change; could cause
  flicker if highlights are reset mid-render.

---

## Confirmed scope: 4 files define `run_gh`, not 5

A grep of the codebase confirms `run_gh` is defined in exactly 4 files:
`init.lua`, `reader.lua`, `watchlist.lua`, `user_profile.lua`.
`day_activity.lua` does not define its own — it calls the `watchlist.lua` version indirectly
or uses no gh calls requiring JSON decode outside of its own pattern. This doesn't change
the plan but corrects the issue description.

---

## No data model changes

This is a pure structural refactor. No persistent data structures change. Cache file format,
watchlist JSON, and user-watchlist JSON are untouched.

## No external interface contracts

The public Lua require paths are the only "API". They are preserved as-is:
- `require("gh_dashboard")` → `lua/gh_dashboard/init.lua` (unchanged)
- `require("gh_dashboard.reader")` → `lua/gh_dashboard/reader/init.lua` (was `reader.lua`)
- `require("gh_dashboard.watchlist")` → `lua/gh_dashboard/watchlist.lua` (unchanged)
- `require("gh_dashboard.user_watchlist")` → `lua/gh_dashboard/user_watchlist.lua` (unchanged)
- `require("gh_dashboard.gh")` → new internal module (not exposed to users)
- `require("gh_dashboard.highlights")` → new internal module (not exposed to users)
