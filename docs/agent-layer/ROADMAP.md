# Roadmap

Note: This is an agent-layer memory file. It is primarily for agent use.

## Purpose
A phased plan of work that guides architecture decisions and sequencing. The roadmap is the “what next” reference; the backlog holds unscheduled items.

## Format
- The roadmap is a single list of numbered phases under `<!-- PHASES START -->`.
- Do not renumber completed phases (phases marked with ✅).
- You may renumber incomplete phases when updating the roadmap (e.g., to insert a new phase).
- Incomplete phases include **Goal**, **Tasks** (checkbox list), and **Exit criteria** sections.
- When a phase is complete:
  - update the heading to: `## Phase N ✅ — <phase name>`
  - replace ALL phase content (Goal, Tasks, Task details, Exit criteria) with a concise bullet summary of what was accomplished (no checkbox list).
- **Archival:** When more than 5 completed phases exist, consolidate the oldest completed phases into a single `## Archived phases` summary. Keep the 5 most recently completed phases as individual entries. The archive section uses one line per phase.

### Phase templates

Archived (compact):
```markdown
## Archived phases (1–N)
- Phase 1 — <name>: <one-line summary>
- Phase 2 — <name>: <one-line summary>
```

Completed:
```markdown
## Phase N ✅ — <phase name>
- <Accomplishment summary bullet>
- <Accomplishment summary bullet>
```

Incomplete:
```markdown
## Phase N — <phase name>

### Goal
- <What success looks like for this phase, in 1–3 bullet points.>

### Tasks
- [ ] <Concrete deliverable-oriented task>
- [ ] <Concrete deliverable-oriented task>

### Exit criteria
- <Objective condition that must be true to call the phase complete.>
- <Prefer testable statements: “X exists”, “Y passes”, “Z is documented”.>
```

## Phases

<!-- PHASES START -->

## Phase 0 ✅ — ProjectSwitcher reset and cleanup
- Renamed the app/core targets to ProjectSwitcher and removed the legacy CLI.
- Stripped activation/workspace management from the switcher, leaving list + selection logging.
- Updated paths, logging, and docs to the ProjectSwitcher namespace.

## Phase 1 ✅ — Foundations: Doctor, config, persistence (UI skeleton)
- Doctor is 100% functional with checks for Homebrew, AeroSpace, VS Code, Chrome, agent-layer CLI, config validity, and directories.
- Config loading/validation is exhaustive with actionable errors; schema documented in README.
- StateStore persistence API implemented with versioned JSON schema, focus stack (LIFO, 20 max, 7-day prune), and lastLaunchedAt.
- CLI has test coverage for argument parsing and command execution; `pswitcher --version` added.
- Core interface document (`docs/CORE_API.md`) catalogs all public APIs.
- Switcher UI skeleton loads config, lists projects, and logs selections.

## Phase 2 ✅ — Focus + switcher UX + core interfaces (separation of concerns)
- Focus domain model defined with FocusEvent, FocusEventKind, and SessionManager as the single source of truth for state and focus history.
- Focus history persisted via StateStore with query, prune, and export capabilities; comprehensive test coverage.
- Switcher search + sorting rules specified and implemented in ProjectSorter: recency-based ordering, prefix-match prioritization, case-insensitive substring matching.
- Strict separation of concerns enforced: business logic in ProjectSwitcherCore, presentation in App/CLI.
- AppKit integration consolidated into shared ProjectSwitcherAppKit module (Core → AppKit → App/CLI layering).

## Phase 3 ✅ — MVP: activation/project lifecycle
- Activation/project lifecycle API designed and implemented in ProjectSwitcherCore with success/failure states and idempotency.
- Activation orchestration implemented with tests for success, failure, and partial-failure scenarios.
- "Close project" implemented in core (API complete; UI wiring deferred to Phase 4).
- "Back to non-project space" implemented — returns focus to most recent non-project window.
- Switcher wired to activation with progress and failure messaging.
- Public API audit: CLI-only items removed; 20+ internal types made internal; CORE_API.md updated.

## Phase 4 ✅ — UX polish
- Wired "close project" into the UI and restored users to non-project context on close.
- Added keybind behavior to toggle back to the most recent macOS space or non-project window.
- Added visual menu bar health indication driven by Doctor results.

## Phase 5 ✅ — Daily-driver required features
- Chrome tab persistence: Verbatim URL capture and restoration via AppleScript.
- LIFO Focus Stack: Returns to last non-project window with workspace-level fallbacks when the stack is exhausted.
- SSH & Agent Layer Support: Orchestration for `code --remote` and `al sync` with environment preservation and `.vscode/settings.json` tagging for window identification.
- Config Hardening: Strict absolute path validation and protection against malicious SSH authority options.
- PATH Propagation: Robust PATH discovery via login shell with timeout and pipe safety.
- Switcher UX Polish: Automatic focus refresh on project close to ensure reliable restoration and subsequent selections.
- Core Extensibility: Added `workingDirectory` support to the `CommandRunning` interface.

## Phase 6 ✅ — Cleanup: reduce code debt + raise coverage
- View Config File menu item, light mode fix, dismiss policy extraction, config warnings surfacing.
- Activation error visibility fix (isActivating guard suppresses premature dismiss during async launch).
- Comprehensive test expansion: switcher dismiss/restore lifecycle, ProjectManager config/sort/recency/activation, CLI runner tests.
- Doctor hardening: unrecognized config keys → FAIL, VS Code/Chrome severity context-aware, focus restore on Doctor window close.
- VS Code settings.json block injection replacing workspace files (local + SSH), reactive write on config change.
- Coverage gate (> 90%) enforced via `scripts/test.sh` + `scripts/coverage_gate.sh` + git pre-commit hook. Hit 95% coverage.

## Phase 7 ✅ — Polish required features + harden daily use
- Window positioning: layout engine with `[layout]` config, AX-based positioning, per-project per-mode persistence, Accessibility permission check in Doctor.
- Window recovery and management: "Move Current Window", "Recover Current Window", "Recover Project" / "Recover All Projects" menu items.
- Workspace cycling: native Swift Option-Tab / Option-Shift-Tab via `WindowCycler` + Carbon hotkeys.
- AeroSpace resilience: circuit breaker (30s cooldown), auto-recovery for breaker-open states with bounded restart/terminate behavior (max 2 attempts), managed config with versioned templates and user sections.
- UX: auto-start at login, auto-doctor on critical errors, VS Code Peacock color differentiation, Doctor SSH parallelization.

## Phase 8 ✅ — Release: packaging, verification, and documentation
- Distribution shape decided: signed + notarized arm64 assets via GitHub tagged releases (Homebrew deferred).
- Signing + notarization integrated into scripted releases (no manual Xcode GUI steps).
- Release scripts: `ci_archive.sh`, `ci_package.sh`, `ci_notarize.sh`, `ci_release_validate.sh`, `ci_setup_signing.sh`.
- README finalized: install (GitHub Releases), permissions, config schema, usage (switcher + `pswitcher`), troubleshooting.
- CI gates (build + tests) and documented release checklist.
- Fresh-machine onboarding validated using README + Doctor only.

## Phase 9 ✅ — Extra non-required features
- Improved switcher performance and search quality, including acronym-friendly matching (`al` → `Agent Layer`).
- Migrated build/test workflow to Makefile entrypoints and aligned CI/coverage gates with `make coverage`.
- Added Option-Tab overlay-based project window cycling with commit-on-Option-release behavior and updated documentation.
- Added SSH remote icon indicators in switcher rows to distinguish remote vs local projects.

## Phase 10 — Next release: self-update + recovery + onboarding/Chrome quality

### Goal
- Ship robust in-app updating and update signaling using a standard framework.
- Expand recovery behavior for both focused-window and non-project contexts.
- Deliver high-impact onboarding and Chrome workspace quality improvements.
- Support side-by-side dev/release app installs with distinct macOS app identities.

### Tasks
- [x] Split dev vs release app identity: add `ProjectSwitcherDev` target/scheme with `PRODUCT_NAME=ProjectSwitcher Dev` and `PRODUCT_BUNDLE_IDENTIFIER=com.projectswitcher.ProjectSwitcher.dev`, add `make build-dev`, and keep shared `~/.config/project-switcher` + `~/.local/state/project-switcher` paths.
- [ ] Implement full best-practices self-update using a framework for ProjectSwitcher app updates (signed update feed, signature verification, staged install/relaunch UX, and explicit failure reporting).
- [ ] Add update-available signaling in the app UI (menu indicator + latest version detail + update action entry point).
- [x] Auto recover a single window.
- [x] Get auto recovery for project working when not on project; recover non-project windows on the current desktop.
- [x] Add switcher `Cmd+R` shortcut to trigger Recover Project for the focused workspace and surface the shortcut in switcher footer hints.
- [ ] Add project flow in the UI (including "+" button) that writes to config safely, including a GUI form and path-based auto-detection.
- [ ] Chrome profile selection in config: Implement support for selecting specific Chrome profiles via config.toml (`chromeProfile` key or similar). This allows different projects to open in their respective Chrome profiles, maintaining separation of state and accounts. Chrome windows for a project open using the profile specified in the project's configuration. May involve using `--profile-directory` or similar Chrome CLI flags.
- [ ] Auto-associate existing Chrome window in project workspace: If a project lacks an associated Chrome window but a window is found within the project's workspace (e.g., without matching title), associate it instead of opening a new one. Selecting a project without a matched Chrome window automatically adopts an existing Chrome window if it's already on the project's assigned workspace/screen. Improves seamlessness when switching projects where Chrome windows might have lost their specific title match but are still in the right place.

### Exit criteria
- In-app self-update is implemented via framework and works from one stable release to the next with signed/notarized artifacts.
- The app visibly flags update availability with clear current/latest version information and graceful offline behavior.
- Single-window recovery and non-project recovery flows are available, deterministic, and validated.
- UI add-project flow, Chrome profile selection, and Chrome auto-association are implemented and documented.
- Dev and release app variants can be built and installed side-by-side with distinct bundle IDs and separate Accessibility/Automation permission entries.

## Phase 11 — Future features

### Goal
- Track larger post-release product features that are intentionally deferred beyond the next release.

### Tasks
- [ ] Allow Switcher usage when `config.toml` is missing by providing an "Open Project..." flow that adds the selected folder to config and activates it, while preserving config ordering rules and reporting failures clearly.
- [ ] Open project workspaces on dedicated macOS Spaces with a defined strategy (one space per workspace vs all project workspaces on a single dedicated space), and make the selected behavior reliable.
- [ ] Custom IDE support: config `[[ide]]` blocks (app path, bundle id, etc) and project `ide = "vscode" | "<custom>"`.
- [ ] Better integration with existing AeroSpace config (non-destructive merge; avoid overwriting).
- [ ] Chrome visual differentiation matching VS Code project color: Apply project color to the Chrome window to visually match the associated VS Code window. Possible approaches: Chrome profile customization, theme injection, or Chrome extension. Deferred from Phase 7 — Chrome has no clean programmatic injection point for color theming (unlike VS Code's Peacock extension). May require a custom Chrome extension or Chrome profile switching.
- [ ] Hot Corners and trackpad activation/switching: Add support for Hot Corners and trackpad gestures (e.g., specific swipes) to trigger the project switcher or quickly toggle between recent projects. Streamlines navigation for laptop users who prefer gesture-based interaction over keyboard shortcuts. User can configure a specific screen corner or trackpad gesture in the settings to invoke the ProjectSwitcher switcher.
- [ ] Homebrew packaging for app + CLI: Provide optional Homebrew distribution (cask/formula or unified strategy) on top of GitHub tagged release assets. A documented Homebrew install/upgrade path exists and is validated against release artifacts. Deferred intentionally while release work focuses on signed + notarized arm64 GitHub tagged releases.

### Exit criteria
- Missing-config onboarding path allows users to add and open a project from Switcher with explicit error surfacing and no silent defaults.
- Dedicated-space behavior is deterministic and matches the selected configuration strategy.
- Homebrew install/upgrade path is documented and validated.
- Phase 11 is split into one or more concrete follow-on phases with scoped goals; any remaining work is tracked in BACKLOG.md.
