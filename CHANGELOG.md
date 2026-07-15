# Changelog

All notable changes to ProjectSwitcher are documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versions follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.2.2] - 2026-07-15

### Fixed

- **Canonical CLI package path** -- moved the signed PKG destination into repository-controlled release configuration and added payload validation so the installer places the binary at `/usr/local/bin/pswitcher`. This supersedes the `v0.2.1` PKG, which used a stale GitHub environment value.

## [0.2.1] - 2026-07-15

### Added

- **Optional Chrome integration** -- added per-project `openChrome` configuration so VS Code-only projects can skip Chrome activation, positioning, and capture work.
- **Repeatable debugging procedure** -- added a current-path-only guide for collecting application and unified logs without exposing unrelated diagnostic data.

### Changed

- **Canonical ProjectSwitcher identity only** -- removed support for former config/state paths, log filenames, Visual Studio Code markers, window tokens, and workspace-recovery event names. Existing local data must be cut over to ProjectSwitcher paths before first launch.
- **Best-effort Chrome activation** -- Chrome lookup, launch, movement, and arrival failures now surface warnings without blocking VS Code project activation.
- **AeroSpace compatibility contract** -- global window searches now use the required `--monitor all` scope, readiness waits on a daemon-backed command, and compatibility checks require formatted workspace output.

### Fixed

- **Window token prefix collisions** -- window matching now requires a leading project token boundary, preventing one project ID from adopting windows belonging to a longer similarly prefixed ID.
- **Chrome launch duplication** -- tag new Chrome windows before URL operations and identify a single newly created window while its title propagates, avoiding repeat launches after discovery timeouts.
- **Transient Accessibility enumeration failures** -- classify `cannotComplete` window enumeration errors as retryable across activation, capture, and recovery paths.
- **Duplicate switcher operations** -- guard concurrent activation and close requests until the active operation completes.
- **Launch-at-login reconciliation** -- change registration only when configured and actual service states differ, with consistent structured failure logging.

## [0.2.0] - 2026-03-27

### Changed

- **Project rename** -- renamed the product and release identity from AgentPanel to ProjectSwitcher.

### Deprecated

- **Project sunset** -- added a prominent README notice clarifying that the repository remains available but is no longer actively maintained.

## [0.1.15] - 2026-03-19

### Added

- **Display configuration change monitoring** -- ProjectSwitcher now detects display configuration changes (dock/undock, monitor connect/disconnect) and triggers a health refresh, since these events correlate with AeroSpace tree-node bugs.
- **Structured JSON logging** -- added `ProjectSwitcherLogger` with structured JSON logging throughout circuit breaker recovery, config management, executable resolution, close-project, and focus-restore paths with contextual fields (window_id, workspace, project_id, screen dimensions).

### Changed

- **Enhanced recovery coordinator diagnostics** -- recovery coordinator logs now include window_id, workspace, and screen dimensions context; coordinator-unavailable warnings are emitted even after coordinator deallocation.
- **Extracted `loadBundledConfigContent`** -- AeroSpaceConfigManager resource loading now uses a dedicated method with error logging.

### Fixed

- **Non-project fallback stranding** -- `fallbackToNonProjectWorkspace` now uses a 3-tier fallback (window → empty workspace → canonical "1") to prevent the user from being stranded in a project workspace after close/exit.
- **Tree-node error recovery for all focus paths** -- `focusWindow()` now retries with `reloadConfig` on tree-node errors as a safety net across all focus paths, not just recovery. A 5-second cooldown prevents repeated config reloads in tight polling loops.
- **Post-close stale tree nodes** -- `closeProject` now calls `reloadConfig` after closing to flush stale AeroSpace tree nodes before focus restoration.
- **Capture retry on transient failure** -- `captureCurrentFocus` now retries on transient AeroSpace failures with a breaker-open guard, and skips `Thread.sleep` retry when called on the main thread to avoid blocking UI.
- **Stale focus history from gone windows** -- focus history entries now include a window-existence check before preservation; gone windows are invalidated immediately instead of being retried.
- **Skip window capture with no IDE windows** -- `captureWindowPositions` now skips capture when the IDE has no windows, and removes an unreliable `listWindowsForApp` skip guard that could miss windows on secondary monitors.
- **Login item unregister crash** -- guarded `SMAppService.unregister()` against `.notRegistered` status to prevent errors when the login item was never registered.
- **Timeout log truncation** -- `ensureWorkspaceFocused` now uses `%.1f` format instead of Int cast so sub-second timeout values are logged correctly.
- **Weak-self no-op in RecoveryOperationCoordinator** -- logger is now captured directly instead of routing through `self?.logEvent`, ensuring coordinator-unavailable warnings are emitted after deallocation.

## [0.1.14] - 2026-03-11

### Changed

- **RecoveryOperationCoordinator extraction** -- moved recover-current-window, recover-workspace, and recover-all-windows operations from AppDelegate into a dedicated testable coordinator, matching the SwitcherOperationCoordinator pattern.
- **Async close/exit/recovery operations** -- converted close, exit, and recovery operations from Thread.sleep to async/await with Task.sleep for cooperative, non-blocking retry delays.
- **Structured window positioning errors** -- replaced message-text matching with structured `PsCoreError.reason` values (`.windowTokenNotFound`, `.windowInventoryEmpty`) across all window positioning retry/fallback paths.
- **Non-project focus restoration bounded** -- `restoreNonProjectFocusFromStack` now limited to 5 candidates with a 30-second budget to prevent runaway loops.
- **retryTransientWindowOp extraction** -- extracted shared retry helper, eliminating 4x duplication across window operation paths.
- **Doctor decomposition** -- decomposed `Doctor.run()` into per-section methods for maintainability.
- **CI script hardening** -- validate tool availability in archive/package scripts, handle `create-dmg` exit code 2, and capture notarization submission ID on failure.

### Fixed

- **Cross-Space recovery crash** -- focus workspace before window recovery to prevent AeroSpace double-unbind crash (`makeFloatingWindowsSeenAsTiling`) when recovering from a different macOS desktop Space.
- **Disconnected monitor window positioning** -- fall back to primary display when IDE window center references a disconnected external monitor's coordinate space, preventing skipped positioning and corrupted layout saves.
- **AeroSpace tree-node stale state after undocking** -- pre-recovery `reloadConfig()` flushes stale tree nodes; focus retry with AX-only fallback keeps recovery working when AeroSpace is in a bad state.
- **Circuit breaker stuck recovery** -- auto-clear stuck recovery flag after 60 seconds to prevent permanent breaker lockout.
- **Non-Sendable capture warnings** -- snapshot mutable callbacks before `@Sendable` Task closures to avoid non-Sendable capture across isolation boundaries.
- **Data races in health and overlay coordinators** -- fix healthCoordinator read race (move inside main queue), WindowCycleOverlayCoordinator potential deadlock, and lock ordering inversion in `loadFocusHistory`.
- **Primary screen fallback** -- use `NSScreen.screens.first` instead of `NSScreen.main` for primary display fallback, since `NSScreen.main` tracks the key window's screen and may be nil.
- **Precondition guards for poll parameters** -- validate `windowPollTimeout` and `windowPollInterval` are finite and non-negative at init to prevent `UInt64` conversion traps in `Task.sleep`.

## [0.1.13] - 2026-03-05

### Added

- **AeroSpace auto-recovery** -- when the AeroSpace process becomes unresponsive, ProjectSwitcher now detects the condition and attempts a graceful restart with force-terminate fallback (max 2 attempts), preventing extended outages from a hung AeroSpace process.
- **Dedicated Doctor circuit breaker** -- Doctor diagnostics now use an independent circuit breaker so diagnostic checks are never blocked by the shared AeroSpace breaker state.

### Changed

- **Circuit breaker log noise reduction** -- breaker-open errors are now logged at info level instead of warn across ProjectManager, SwitcherPanelController, and menu coordinator, reducing log spam during expected breaker cooldown periods.
- **Window positioning retry with fallback** -- all window identification paths (activation, capture, recovery) now retry with bounded loops and fall back to focused-or-only-window strategies when VS Code/Chrome title updates lag AX visibility.
- **Capture skip-save on partial frames** -- when Chrome frame capture fails, the save is skipped entirely instead of writing a partial (IDE-only) layout, preserving the prior complete layout for the next restore.
- **Off-screen recovery threshold** -- window off-screen detection now uses a percentage-based threshold (10%) instead of absolute pixels, improving reliability across display resolutions.
- **ProjectManager and SwitcherPanelController split** -- decomposed the monolithic controller into separate focused modules for maintainability.
- **AeroSpace facade decomposition** -- split PsAeroSpace into Parser, CommandTransport, and Compatibility modules (1054 to 886 LOC in the main file).
- **Test infrastructure overhaul** -- always-coverage collection, smart pre-commit hook that maps staged files to affected test targets, decomposed monolithic test files into 33 focused suites, and stubbed slow infrastructure dependencies for faster test runs.

### Fixed

- **Switcher first-open size jump** -- the switcher now seeds workspace-derived state and computes the initial filtered rows before presenting the panel, reducing the initial "starts small then jumps" effect while preserving existing selection and AeroSpace interaction behavior.
- **Recover-project Escape regression** -- after running switcher `Cmd+R` recovery, the switcher now explicitly restores search-field input focus so `Esc` keeps dismissing the panel.
- **Timer store-before-resume race** -- `retryTimer` is now stored under lock before calling `resume()`, closing a window where `cancelRetry` could miss an active timer.
- **Retry coordinator data race** -- moved generation check from background queue to main-thread dispatch to eliminate a data race on `retryGeneration`.
- **Stale pre-entry focus on activation failure** -- `preEntryFocus` is now stored only after activation succeeds, so failure paths never leave stale entries.
- **Close-project focus restore with transient lookup failure** -- close now attempts pre-entry `focusWindow` even when window lookup fails transiently, using lookup only as validation when available.
- **Missing pre-focus capture no longer crashes switcher** -- removed hard-fail guard when `capturedFocus` is nil; proceeds with best-effort restore semantics instead.
- **Transient close-workspace window misses** -- `closeWorkspace` now includes bounded re-query/retry when windows survive the first close attempt.
- **Menu workspace state race** -- added a generation counter to prevent background refresh from overwriting an explicit `updateFocusCapture()` call.
- **Zero-window IDE positioning probe** -- added fast-fail with multi-confirmation confidence thresholds when no IDE windows are found, avoiding wasted retry loops.
- **Doctor focus steal during accessibility prompts** -- added `skipActivation` plumbing to `DoctorWindowController` to prevent focus steal.
- **LoginShell timeout precondition** -- `loginShellTimeoutSeconds` now validates with a precondition to fail loudly on invalid (non-positive/non-finite) values.

## [0.1.12] - 2026-03-01

### Added

- **Auto-recover off-screen windows on focus** -- when focusing a window (project switch exit, non-project restore, or Option-Tab cycling), the app now automatically detects and recovers windows that are off-screen or oversized, silently moving them on-screen.
- **Recover current window menu action** -- added a dedicated `Recover Current Window` menu item and reordered the recovery block so `Move Current Window` appears first.
- **Switcher recover-project shortcut** -- added `Cmd+R` in the switcher to trigger Recover Project for the focused workspace, with footer hint text updated to advertise the shortcut.

### Changed

- **Recover all projects flow** -- renamed the menu action to `Recover All Projects...` and changed behavior to recover every window across all workspaces, routing project-tagged windows (`PS:<projectId>`) for configured projects into their `ps-<projectId>` workspace before workspace recovery runs.

## [0.1.11] - 2026-02-24

### Added

- **Persisted non-project focus history** -- ProjectSwitcher now persists non-project focus history in `state.json` and reuses it across app/CLI sessions, improving return/exit restoration determinism after restarts.
- **Launch-at-login toggler coverage** -- app wiring now includes explicit launch-at-login toggler behavior and regression coverage for login-item state transitions.

### Changed

- **Workspace routing policy centralization** -- workspace and non-project destination routing now flow through a shared policy module to keep restore decisions deterministic and consistent across switcher actions.

### Fixed

- **Non-project restore edge cases** -- focus handoff now prefers canonical persisted history when transient stack entries are stale or unavailable, reducing incorrect return targets.
- **No-lookup restore fallback** -- when global AeroSpace window listing fails, exit-to-non-project now still attempts persisted stack/recent restoration instead of skipping directly to workspace fallback.
- **History preservation on transient focus instability** -- failed focus-stability verification no longer eagerly discards stack candidates; entries are preserved for retry to avoid destructive history loss during temporary AeroSpace instability.
- **Move-window destination routing efficiency** -- moving windows out of project workspaces now uses a single global window lookup fast path and only falls back to per-workspace probes when needed.
- **Logger path hardening** -- logger/data-path handling now uses stricter path validation and safer defaults to prevent path-shape regressions in diagnostics and persistence flows.

## [0.1.10] - 2026-02-23

### Fixed

- **Exit-to-non-project focus transition reliability** -- the switcher now suppresses resign-key dismissal during in-flight external focus transitions and prevents duplicate exit actions while a transition is running, which avoids dropped/incorrect focus handoff when exiting to a non-project window.

## [0.1.9] - 2026-02-21

### Changed

- **Accessibility startup prompt UX** -- when Accessibility permission is missing, ProjectSwitcher now requests it automatically once per installed app build at startup. Doctor still provides the manual retry button.

### Fixed

- **Doctor release-build text visibility hardening** -- moved Doctor attributed rendering into `ProjectSwitcherAppKit`, switched to explicit contrast-safe palettes (light/dark), and aligned report background/text color handling so report text remains readable across release toolchains and appearance changes.
- **CI toolchain modernization** -- CI and release workflows now run on `macos-26`, use latest action majors (`actions/checkout@v6`, `actions/cache@v5`), and enforce Xcode major version (`26+`) to keep release builds aligned with current toolchains.

## [0.1.8] - 2026-02-21

### Added

- **Window cycle overlay** -- holding `Option` while cycling windows now shows an on-screen overlay with app icons and selected window title, and commits focus on `Option` release.
- **Switcher performance primitives** -- added shared core utilities for config fingerprinting, debounce tokening, and table reload planning.
- **Window cycle session API** -- `WindowCycler` now exposes explicit session lifecycle operations (`startSession`, `advanceSelection`, `commitSelection`, `cancelSession`) used by the overlay path.

### Changed

- **Switcher filtering/reload behavior** -- added debounced filtering, config snapshot reuse, and planner-driven table updates (`fullReload` / `visibleRowsReload` / `noReload`) to reduce full reloads and stale-selection effects.
- **Doctor window presentation** -- replaced plain text output with rich report rendering (colored severities), spinner-based loading state, and clearer action grouping with context buttons shown only when applicable.
- **Window cycle fallback behavior** -- overlay display is suppressed while the switcher is open and falls back to immediate cycle semantics when no overlay session is available (for example, 0-1 windows).
- **Non-project wording consistency** -- updated CLI and switcher copy from "previous window" to "non-project space/window" to match current behavior.

### Fixed

- **Enter key race in switcher search** -- pending debounced filter work is now flushed before primary actions so Enter applies to the latest query result set.
- **Option-release commit reliability** -- added modifier-change handling plus watchdog fallback so overlay sessions commit deterministically when `Option` release events are missed.
- **Non-project focus restoration reliability** -- close/return paths now restore the most recent known non-project window when stack entries are exhausted/stale and avoid focusing empty non-project workspaces.

## [0.1.7] - 2026-02-20

### Fixed

- **Doctor text invisible in light mode (release builds)** -- Setting `NSTextView.string` can reset the foreground color when the text storage is replaced, causing white-on-white text in light mode. Switched from `textColor` + `.string` assignment to explicit `NSAttributedString` with font and foreground color attributes set on every text update, ensuring the text is always visible regardless of appearance mode or build configuration.

## [0.1.6] - 2026-02-20

### Added

- **Fuzzy project search** -- the switcher now uses tiered fuzzy matching instead of exact substring matching. Scoring tiers: prefix > word-boundary acronym > substring > non-consecutive fuzzy. Both project name and ID are scored, with the best match used for ranking. For example, typing "al" now matches "Agent Layer" via word-boundary acronym detection.
- **Remote indicator in switcher** -- SSH projects show a network icon next to the project name in the switcher row, making remote projects immediately distinguishable from local ones.
- **Makefile build system** -- `make build`, `make test`, `make coverage`, `make clean`, `make regen`, and `make preflight` as the single entrypoint for all dev operations. `make test` skips coverage for fast local iteration. `make coverage` runs the full quality gate with per-file coverage summary.

### Changed

- **Remote icon position** -- moved the SSH remote indicator icon to appear after the project name instead of before it.
- **Capture window positions on project switch** -- window positions are now captured when switching between projects (not only on close/exit), so returning to a project restores the user's window arrangement.
- **Optional Chrome frame** -- Chrome window frame capture failures no longer abort the entire save. IDE-only partial saves are written instead.

### Fixed

- **Partial-save log noise** -- consolidated redundant partial-save log events into a single entry.

## [0.1.5] - 2026-02-18

### Fixed

- **Doctor window text invisible in dark mode** -- `NSTextView` defaulted to black text color. With `isRichText = false`, the `usesAdaptiveColorMappingForDarkAppearance` flag had no effect. Set explicit `textColor = .labelColor` which adapts to light/dark appearance.

## [0.1.4] - 2026-02-18

### Fixed

- **Red menu bar icon after every update** -- Accessibility permission check used FAIL severity, causing the menu bar icon to turn red after every app update (macOS revokes Accessibility when the binary signature changes). Changed to WARN severity — the icon shows orange instead of red, correctly reflecting that the app works without Accessibility (only window positioning is degraded).
- **CLI reports version 0.0.0-dev** -- The `pswitcher` CLI binary had no Info.plist, so `Bundle.main.infoDictionary` returned nil and the version fell back to `"0.0.0-dev"`. Added a build-time `buildVersion` constant in `Identity.swift` with a CI preflight check to keep it in sync with `MARKETING_VERSION` in `project.yml`.
- **Doctor logs don't show what failed** -- Doctor log entries only included pass/warn/fail counts, making remote debugging impossible. Added `fail_findings` and `warn_findings` context keys with actual finding titles. Added full rendered report text, per-section timing breakdown, and total duration to every Doctor log entry. Startup log now includes binary path, bundle path, and macOS version. Doctor report header now shows duration and section timings.

## [0.1.3] - 2026-02-18

### Fixed

- **Doctor appears to hang with no feedback** -- Clicking "Run Doctor" dispatched Doctor.run() to a background thread but showed nothing until completion (20-30s when SSH hosts are unreachable). The Doctor window now opens immediately with "Running diagnostics..." loading text and disabled action buttons. The report populates when checks complete.
- **SSH check timeouts too slow** -- Doctor and settings block SSH commands used `ConnectTimeout=5` with 10s process timeout. Reduced to `ConnectTimeout=2` with 3s process timeout. Worst-case Doctor SSH checks drop from ~20s to ~6s. Adequate for LAN hosts; unreachable hosts fail faster.

## [0.1.2] - 2026-02-18

### Fixed

- **App freeze on startup** -- Every `PsSystemCommandRunner` instance spawned a login shell process during init to build an augmented PATH. With 9 instances created on the main thread during startup (`ProjectManager` launchers, `PsAeroSpace`, `WindowCycler`, etc.), this blocked the main thread for 5-10+ seconds, freezing the entire system. The augmented environment is now computed once (lazily, on first `run()` call) and cached globally via a thread-safe `static let`. Init is instant.
- **Menu bar freeze on click** -- `menuNeedsUpdate` called `captureCurrentFocus()` and `workspaceState()` synchronously on the main thread, each invoking AeroSpace CLI with a 5-second timeout. Now uses cached workspace state refreshed in the background after Doctor runs, switcher sessions end, and each menu open.
- **Switcher/Doctor/menu actions block main thread** -- `toggleSwitcher`, `openSwitcher`, `runDoctor`, and `addWindowToProject` all called AeroSpace CLI on the main thread. Moved all CLI calls to background dispatch queues with main-thread callbacks for UI updates.
- **Switcher panel blocks main thread** -- `refreshWorkspaceState()`, `closeProject()`, `captureCurrentFocus()`, `exitToNonProjectWindow()`, and workspace retry timer all called AeroSpace CLI synchronously on the main thread within the switcher panel. Dispatched all CLI calls to background queues; UI updates bounce back to main thread.
- **Command timeout stretches 5s to 10s** -- After a 5-second process timeout, the command runner still waited up to 4 additional seconds for pipe EOF signals that would never arrive. Now skips pipe EOF waits on timeout since the output is discarded anyway.
- **AeroSpace config reload blocks main thread** -- Moved the `aerospace.reloadConfig()` call during startup config update to a background thread to avoid blocking the main thread on the first command runner invocation.

## [0.1.1] - 2026-02-18

### Fixed

- **Doctor freeze in release build** -- `ExecutableResolver.runLoginShellCommand()` used synchronous `readDataToEndOfFile()` which blocks forever if the user's shell config (`.zshrc`/`.zprofile`) spawns background daemons that inherit the pipe's write-end file descriptor. Replaced with async `readabilityHandler` + EOF semaphore with bounded timeout, matching the safe pattern already used by `PsSystemCommandRunner`.

## [0.1.0] - 2026-02-17

Initial public release.

### Added

- **Project switching** -- global hotkey (`Cmd+Shift+Space`) opens a searchable switcher panel sorted by recency. Select a project to activate its workspace with VS Code and Chrome.
- **Workspace orchestration** -- each project gets a dedicated AeroSpace workspace (`ps-<projectId>`). Windows are created, moved, and focused automatically.
- **Chrome tab persistence** -- tabs are captured on project close and restored on activate. Per-project pinned tabs and default tabs configurable.
- **Window layout engine** -- configurable side-by-side positioning with screen-size-aware rules. Small screens maximize; wide screens tile. Requires Accessibility permission.
- **Window recovery** -- recover project windows to computed layout or center all windows across workspaces.
- **Window cycling** -- `Option+Tab` / `Option+Shift+Tab` cycles through windows in the current workspace (native implementation, includes floating windows).
- **SSH remote projects** -- VS Code Remote-SSH integration with remote `.vscode/settings.json` block management and parallel SSH Doctor checks.
- **Agent Layer integration** -- optional `al sync` + `al vscode` launch path for projects using the Agent Layer CLI.
- **VS Code color differentiation** -- per-project colors via the Peacock extension. Colors persist across settings.json re-injections.
- **Doctor diagnostics** -- comprehensive setup validation (Homebrew, AeroSpace, VS Code, Chrome, config, paths, SSH, permissions, hotkeys) with actionable fix guidance. Available in app UI and CLI (`pswitcher doctor`).
- **AeroSpace auto-management** -- versioned config template with auto-update on startup. User keybindings and custom config preserved between updates.
- **AeroSpace resilience** -- circuit breaker (30s cooldown) prevents timeout cascades. Auto-recovery restarts crashed AeroSpace processes (max 2 attempts).
- **Focus stack** -- LIFO stack tracks non-project windows. `Shift+Enter` or `pswitcher return` restores the last active non-project context.
- **Auto-start at login** -- configurable via `[app].autoStartAtLogin` or menu bar toggle. Uses `SMAppService`.
- **Auto-doctor on critical errors** -- background Doctor run when critical activation errors occur.
- **CLI (`pswitcher`)** -- `doctor`, `show-config`, `list-projects`, `select-project`, `close-project`, `return` commands with ANSI color output and TTY detection.
- **Menu bar app** -- background-only (no Dock icon) with health indicator, config access, window recovery, and Doctor.
- **Signed and notarized releases** -- DMG (app), PKG (CLI installer), and tarball published via GitHub Releases. CI workflow handles signing, notarization, and stapling.
