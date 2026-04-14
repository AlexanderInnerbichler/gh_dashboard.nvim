# Feature Specification: Code Structure Refactor

**Status**: Draft
**Created**: 2026-04-14
**Branch**: feature/002-refactor-code-structure
**Issues**: #1 (shared gh helper), #3 (centralize highlights), #5 (split large modules)

---

## Overview

This refactor improves the long-term maintainability of gh_dashboard.nvim by eliminating
code duplication, centralizing theme definitions, and splitting oversized files into
focused modules — without changing any user-visible behaviour.

---

## Problem Statement

The plugin has grown organically to ~3,500 lines across 8 files. Three structural problems
have accumulated:

1. **Duplicated GitHub call helper**: The same ~12-line pattern for running a `gh` command
   asynchronously and decoding JSON is copy-pasted across 5 separate modules. Any bug fix
   must be applied in 5 places, and the copies have already diverged slightly.

2. **Scattered highlight definitions**: Every module independently defines its own highlight
   groups and registers its own theme-change handler. Adding or changing a colour requires
   locating and editing multiple unrelated files.

3. **Oversized mixed-concern files**: `init.lua` (~992 lines) and `reader.lua` (~1131 lines)
   each combine data fetching, display rendering, state management, window setup, and user
   interaction in a single file. New contributors cannot easily locate where to make a
   targeted change, and each file is too large to hold in working memory.

---

## Goals

- Eliminate all duplication of the GitHub command helper pattern
- Consolidate all highlight/colour definitions into one place with a single theme-change handler
- Split `init.lua` and `reader.lua` into modules with clearly bounded responsibilities
- Leave user-visible behaviour completely unchanged

## Non-Goals

- No new features or behaviour changes of any kind
- No changes to the public Lua API (`setup()`, `toggle()`, `open()`, `post_comment()`, etc.)
- No changes to keymaps, window appearance, or displayed content
- No performance optimisations beyond what the restructuring naturally enables

---

## User Scenarios & Testing

### Primary Flow: Contributor fixes a bug in the GitHub call pattern

**Actor**: Plugin contributor
**Trigger**: A bug is found in how `gh` errors are surfaced (e.g., stderr is swallowed)
**Steps**:
1. Contributor searches the codebase for the GitHub call helper
2. Finds exactly one file containing the shared implementation
3. Fixes the bug in that one location
4. Verifies the fix applies to all modules that invoke GitHub commands
**Outcome**: Bug is fixed in one edit; no risk of missing a copy elsewhere

### Primary Flow: Contributor changes a highlight colour

**Actor**: Plugin contributor
**Trigger**: User reports that a highlight colour clashes with their colourscheme
**Steps**:
1. Contributor opens the centralized highlights module
2. Finds the relevant highlight group definition
3. Adjusts the colour
4. Confirms the change is reflected across all panels (dashboard, reader, watchlist)
**Outcome**: Colour updated in one file; theme-change handler fires once on colorscheme switch

### Primary Flow: Contributor adds a new dashboard section

**Actor**: Plugin contributor
**Trigger**: Feature request to add a new data panel to the dashboard
**Steps**:
1. Contributor opens the fetch module to add a new data-fetching function
2. Contributor opens the render module to add the corresponding renderer
3. Contributor wires the two together in the thin orchestrator module
**Outcome**: New section added with each concern touched in isolation

### Edge Cases

- All existing keymaps continue to function after the refactor
- The watchlist poller continues to run correctly across the module boundary
- The reader public entry point continues to work after reader is split into sub-modules
- Cache read/write behaviour is unchanged

---

## Functional Requirements

### Must Have (P1)

- [ ] A single shared module provides the GitHub command helper; every other module uses it rather than defining its own copy
- [ ] All highlight group definitions live in one module; no other module calls the highlight-setting API directly
- [ ] A single theme-change event handler registers all highlights; no module registers its own redundant handler
- [ ] The dashboard module is reorganised so that data fetching, display rendering, and orchestration are in separate, clearly named modules
- [ ] The reader module is reorganised so that data fetching, display rendering, user actions (comment/review/merge/close), and orchestration are in separate, clearly named modules
- [ ] The public Lua require paths used in user setup calls remain valid and return the same functions
- [ ] No module exceeds 400 lines after the refactor
- [ ] All dashboard panels display correct data after the refactor
- [ ] All reader interactions (comment, review, merge, close, diff) function correctly after the refactor
- [ ] The watchlist poller and notification system function correctly after the refactor

### Should Have (P2)

- [ ] The highlight module exposes a single setup function that other modules can call, with internal deduplication so it is safe to call multiple times
- [ ] The shared GitHub call helper accepts the same arguments and callback signature currently used at all call sites, requiring no changes to callers beyond the import path

---

## Success Criteria

| Criterion | Measure | Target |
|-----------|---------|--------|
| No duplicated helper code | Count of modules defining the GitHub call pattern | Exactly 1 |
| No scattered highlights | Count of modules registering highlight groups | Exactly 1 |
| File size discipline | Maximum line count of any single module | 400 lines or fewer |
| Behaviour parity | All existing features work identically after refactor | Zero regressions |
| Contributor discoverability | A new contributor can locate the fetch, render, or action logic for any panel | Within 2 minutes of reading the directory structure |

---

## Assumptions

- The refactor will be done as a single atomic changeset to avoid a long-lived partial state
- The public require paths (`gh_dashboard`, `gh_dashboard.reader`, `gh_dashboard.watchlist`, `gh_dashboard.user_watchlist`) are treated as stable API and must not change
- Sub-module paths introduced by the split are internal and may be freely chosen
- Behaviour parity is verified manually by exercising each feature in Neovim after the refactor; there are no automated tests in this project

---

## Dependencies

- Issues #1, #3, and #5 are addressed together because they are mutually reinforcing: splitting large files naturally exposes the need for a shared helper and a shared highlight module
- No external dependencies; this is a pure internal restructuring
