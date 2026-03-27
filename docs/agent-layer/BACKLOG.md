# Backlog

Note: This is an agent-layer memory file. It is primarily for agent use.

## Purpose
Unscheduled user-visible features and tasks (distinct from issues; not refactors). Maintainability refactors belong in ISSUES.md.

## Format
- Insert new entries immediately below `<!-- ENTRIES START -->` (most recent first).
- Keep each entry **3–5 lines**.
- Line 1 starts with `- Backlog YYYY-MM-DD <id>:` and a short title.
- Lines 2–5 are indented by **4 spaces** and use `Key: Value`.
- Keep **exactly one blank line** between entries.
- Prevent duplicates: search the file and merge/rewrite instead of adding near-duplicates.
- When scheduled into ROADMAP.md, move the work into ROADMAP.md and remove it from this file.
- When implemented, remove the entry from this file.

### Entry template
```text
- Backlog YYYY-MM-DD short-slug: Short title
    Priority: Critical | High | Medium | Low. Area: <area>
    Description: <what the user should be able to do>
    Acceptance criteria: <clear condition to consider it done>
    Notes: <optional dependencies/constraints>
```

## Features and tasks (not scheduled)

<!-- ENTRIES START -->

- Backlog 2026-03-19 aerobug: Detect AeroSpace crash and surface user notification
    Priority: Low. Area: external dependency
    Description: AeroSpace 0.20.2-Beta crashes at `Workspace.swift:97:14 ==(_:_:)` during `socketServer` refresh. Our circuit breaker handles the outage, but the user has no visibility. Detect crashes via `/tmp/bobko.aerospace/aerospace-runtime-error.txt` and show a notification.
    Acceptance criteria: When AeroSpace crash file is detected, a user-visible notification is shown explaining the situation.
    Notes: Upstream bug — file or check for existing report at github.com/nikitabobko/AeroSpace.

- Backlog 2026-02-20 favorites: Favorites/stars for projects
    Priority: Deferred. Area: Switcher UX
    Description: Persisted favorite/star flag per project with UI affordances (star icon, Favorites section, Cmd+D toggle). Bulk "Open All Favorites" action to activate all starred projects.
    Acceptance criteria: Favorites persisted in state file, visible in switcher and CLI, bulk-open works with defined focus-stack contract.
