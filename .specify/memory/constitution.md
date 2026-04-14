<!--
## Sync Impact Report

Version change: N/A → 1.0.0 (initial ratification)

Added sections: All (initial)
Modified principles: N/A
Removed sections: N/A

Templates requiring updates:
  ✅ .specify/templates/spec-template.md — created and aligned
  ✅ .specify/templates/plan-template.md — created and aligned
  ✅ .specify/templates/tasks-template.md — created and aligned
  ✅ .specify/templates/constitution-template.md — source template created

Follow-up TODOs:
  - RATIFICATION_DATE set to today (2026-04-14) as first-time setup
-->

# Project Constitution: gh_dashboard.nvim

**Version**: 1.0.0
**Ratified**: 2026-04-14
**Last Amended**: 2026-04-14
**Maintainer**: AlexanderInnerbichler

---

## Purpose

gh_dashboard.nvim is a Neovim plugin that brings a GitHub dashboard directly into the editor.
It displays contribution heatmaps, open PRs, issues, repo activity, user profiles, and a
real-time watchlist — all powered by the `gh` CLI, requiring no separate API tokens or
configuration from the user.

---

## Principles

### 1. Zero External Dependencies

The plugin MUST rely exclusively on the `gh` CLI and Neovim's built-in Lua APIs
(`vim.system`, `vim.uv`, `vim.api`, `vim.fn`). No third-party Lua libraries, no
direct HTTP clients, no additional binaries beyond `gh`. This keeps installation
trivial: if `gh` is authenticated, the plugin works.

**Rationale**: Every additional dependency is a potential installation failure for users.
The `gh` CLI already handles auth, rate limiting, and API versioning.

### 2. Non-Blocking by Default

All GitHub API calls MUST be asynchronous. The editor MUST never freeze or block the
main loop while fetching data. Use `vim.system()` with callbacks and `vim.schedule()`
to re-enter the main loop. Polling timers MUST use `vim.uv.new_timer()`.

**Rationale**: A plugin that freezes Neovim during network calls is unusable. Users
expect the editor to remain responsive at all times.

### 3. Minimal, Discoverable UI

All UI MUST be rendered in floating windows with rounded borders and a footer that
lists available keymaps. Windows MUST be closeable with `q` or `<Esc>`. No persistent
side panels, no tab takeovers. The plugin MUST leave no lasting marks on the user's
buffer layout when closed.

**Rationale**: Neovim users expect plugins to be unobtrusive. The dashboard should feel
like a popup, not a permanent workspace change.

### 4. Configuration-Driven Behaviour

All user-facing tunable values (cache TTL, poll intervals, window sizes, notification
counts) MUST be exposed via `setup()` config tables with documented defaults.
Hardcoded magic numbers are NOT permitted in shipping code.

**Rationale**: Different users have different workflows. A developer on a fast connection
might want a 60s poll; one on mobile might want 5 minutes. Forcing them to edit plugin
source is a poor experience.

### 5. Single Responsibility per Module

Each Lua module MUST have a clearly bounded responsibility. Fetching, rendering, state
management, and user interaction MUST NOT be mixed in the same function or file where
they can reasonably be separated. Files exceeding ~400 lines SHOULD be split.

**Rationale**: Large files with mixed concerns are hard to navigate, test, and extend.
The existing init.lua (~992 lines) and reader.lua (~1131 lines) violate this and are
known technical debt.

---

## Scope & Boundaries

**In scope:**
- Displaying GitHub data (PRs, issues, activity, contributions, repos, user profiles)
- Real-time event notifications for watched repos
- Interacting with PRs and issues (comment, review, merge, close)
- Health checks and dependency validation

**Out of scope:**
- Repository management (create, delete, fork repos)
- GitHub Actions / CI pipeline management
- Code review line-by-line commenting in editor buffers (beyond diff view)
- Authentication management (handled entirely by `gh auth`)
- Supporting non-`gh`-CLI GitHub access methods

---

## Governance

### Amendment Procedure

1. Open a GitHub issue describing the proposed change and rationale
2. The maintainer reviews and merges a PR updating this file
3. Version is bumped according to the versioning policy below
4. All affected templates are updated in the same PR

### Versioning Policy

- MAJOR: Backward-incompatible governance changes (principle removal or redefinition that invalidates existing features)
- MINOR: New principle or section added; existing principle materially expanded
- PATCH: Clarifications, wording improvements, typo fixes

### Compliance Review

Compliance with these principles is reviewed:
- During `/speckit.plan` (Constitution Check section in every plan)
- During code review of any PR that touches module boundaries or adds new API calls
- When a new principle is added (retroactive scan of existing code for violations)
