## Efficient window listing with the `aerospace` CLI

### Avoid `--all` unless you truly need it

`aerospace list-windows --all` is an alias for `--monitor all`, and the docs explicitly say to use it with caution; for multi‑monitor setups they recommend `--monitor focused` in almost all cases. ([Nikita Bobko][1])

So, yes: `--all` can be noticeably slow (or just feel slow) because it’s the maximum scope and can generate a lot of output.

---

## Scope first (fast), then filter

`list-windows` is built around narrowing by **workspace** and/or **monitor**, then optionally filtering by app:

### 1) Smallest scope: one window

```sh
aerospace list-windows --focused
```

([Nikita Bobko][1])

### 2) Typical: current workspace

```sh
aerospace list-windows --workspace focused
```

`focused` is a special workspace name. ([Nikita Bobko][1])

### 3) “What’s on screen right now?” (all visible workspaces)

```sh
aerospace list-windows --workspace visible
```

`visible` represents all currently visible workspaces (important on multi‑monitor). ([Nikita Bobko][1])

### 4) Focused monitor only (preferred instead of `--all` on multi-monitor)

```sh
aerospace list-windows --monitor focused
```

Monitor selectors can be numeric (left→right), or special IDs like `focused`, `mouse`, `all`. ([Nikita Bobko][1])

### 5) Visible windows on the focused monitor (common “local” query)

```sh
aerospace list-windows --monitor focused --workspace visible
```

This combines both scopers (allowed by the command signature). ([Nikita Bobko][1])

---

## Filter at the source (don’t post-filter huge output)

If you only care about a specific app:

### Filter by bundle ID

```sh
aerospace list-windows --workspace visible --app-bundle-id com.google.Chrome
```

([Nikita Bobko][1])

### Filter by PID

```sh
aerospace list-windows --workspace visible --pid 12345
```

([Nikita Bobko][1])

To discover app bundle IDs/PIDs for running GUI apps:

```sh
aerospace list-apps
```

([Nikita Bobko][1])

---

## Reduce output (often the real speed win)

By default, `list-windows` prints window id + app name + window title. ([Nikita Bobko][1])
If you’re going to feed results into another command/script, you usually only need IDs:

```sh
aerospace list-windows --workspace visible --format '%{window-id}'
```

([Nikita Bobko][1])

Other useful output modes:

### Count only

```sh
aerospace list-windows --workspace visible --count
```

([Nikita Bobko][1])

### JSON (for scripts)

```sh
aerospace list-windows --workspace visible --json
```

([Nikita Bobko][1])

If you use JSON, a safe approach is to inspect keys first:

```sh
aerospace list-windows --workspace visible --json | jq '.[0] | keys'
```

---

## If `--all` is *unusually* slow or returns “ghost” entries

`--all` being slower than scoped queries is expected (it’s global scope, and discouraged for casual use). ([Nikita Bobko][1])
If it’s pathologically slow or you suspect incorrect window state, AeroSpace provides an interactive debugging command intended for bug reports about incorrect window handling:

```sh
aerospace debug-windows
```

([Nikita Bobko][1])

---

# Ways to use AeroSpace on macOS

## 1) Keybindings + config (`~/.aerospace.toml`)

AeroSpace searches for config in:

* `~/.aerospace.toml`
* or `${XDG_CONFIG_HOME}/aerospace/aerospace.toml` (defaults to `~/.config` if `XDG_CONFIG_HOME` is unset) ([Nikita Bobko][2])

The guide states there are two main ways to use AeroSpace commands:

1. bind keys in the config
2. run commands in the CLI ([Nikita Bobko][2])

## 2) CLI for ad‑hoc control + scripting

Manual install notes that putting `bin/aerospace` on your `PATH` is optional, and specifically needed if you want to interact via CLI. ([Nikita Bobko][2])

Common uses:

* scripts that query state (`list-windows`, `list-workspaces`, `list-monitors`)
* integration with `jq`, `fzf`, status bars, launchers, etc.

## 3) Event-driven automation (callbacks)

The guide documents callbacks such as:

* `on-window-detected`
* `on-focus-changed` / `on-focused-monitor-changed`
* `exec-on-workspace-change` ([Nikita Bobko][2])

These are the usual mechanism for “auto-assign app X to workspace Y,” “mouse follows focus,” and triggering external tools when workspaces change.

## 4) Third-party integrations / UX enhancements

The official “Goodies” page lists integrations and workflow ideas, including:

* a third‑party Raycast extension
* trackpad gesture workflows for switching workspaces
* showing workspaces in Sketchybar or simple-bar
* highlighting focused windows via JankyBorders
* AppleScript snippets for opening new windows without pulling an existing workspace into focus ([Nikita Bobko][3])

---

## Practical default recommendation

If your habit is `list-windows --all`, switch to:

1. `--focused` (single window)
2. `--workspace focused` (current workspace)
3. `--workspace visible` (everything you can currently see)
4. `--monitor focused` (current monitor only)

Then add `--app-bundle-id` / `--pid`, and use `--format` to output only what you need. In ProjectSwitcher, this remains the default guidance for ad-hoc queries; the project activation path is an explicit exception (see below). ([Nikita Bobko][1])

---

# Project Activation Command Sequence

This section documents the exact AeroSpace commands and sequencing used by the proven activation flow (reference: `ProjectSwitcherCore/ProjectManager.swift` and `ProjectSwitcherCore/AeroSpace/PsAeroSpace.swift`). The Swift implementation must mirror this sequence.

## Overview

Activation is **strictly sequential**. Each step must complete before the next begins. Chrome is set up first (without focus follow), then VS Code (with focus follow so the final focus lands in the target workspace on the IDE window).

## Window format

All `list-windows` calls use a consistent `--format`:

```sh
aerospace list-windows ... --format "%{window-id}||%{app-bundle-id}||%{workspace}||%{window-title}"
```

Fields are separated by `||` (double pipe). Parsing splits on `||` to extract: window ID, bundle ID, workspace name, and window title.

## Window token

Each project window is tagged with `PS:<project-id>` in the window title. Chrome uses AppleScript `given name`; VS Code uses a `// >>> project-switcher` block in `.vscode/settings.json` with `window.title` containing the token (for SSH projects, the file is written on the remote host via SSH).

## Step 1: Find or launch tagged windows

### Window resolution (global search with fallback)

Search **all monitors** first. If that fails (older AeroSpace builds), fall back to `--monitor focused`:

```sh
# Preferred: global search
aerospace list-windows --app-bundle-id <bundle-id> --format <format>

# Fallback: focused monitor only
aerospace list-windows --monitor focused --app-bundle-id <bundle-id> --format <format>
```

This is the one exception to the "prefer scoped queries" guidance above — tagged-window resolution needs global scope to find windows that may be on any monitor or workspace.

### Chrome launch (AppleScript)

If no tagged Chrome window exists, resolve initial tab URLs and launch via `osascript`. Tab URLs come from the last captured snapshot (verbatim, preserving order). If no snapshot exists (cold start), URLs are computed from always-open URLs (global `pinnedTabs` + per-project `chromePinnedTabs` + git remote if enabled) followed by default tabs. URL resolution is deferred until after confirming Chrome needs a fresh launch.

Launch with tab URLs (single AppleScript, no placeholder):

```applescript
tell application "Google Chrome"
  set newWindow to make new window
  set URL of active tab of newWindow to "<first-tab-url>"
  set given name of newWindow to "PS:<project-id>"
  -- additional tabs opened via `make new tab` with each URL
end tell
```

If the tab-restore launch fails, Chrome falls back to launching without tabs (empty window with tag only) and a warning is surfaced to the caller.

### VS Code launch (settings.json block)

If no tagged VS Code window exists:

1. Inject a `// >>> project-switcher` block into the project's `.vscode/settings.json`:

```jsonc
{
  // >>> project-switcher
  // Managed by ProjectSwitcher. Do not edit this block manually.
  "window.title": "PS:<project-id> - ${dirty}${activeEditorShort}${separator}${rootName}${separator}${appName}",
  // <<< project-switcher
  // ... rest of file preserved ...
}
```

   The block is always inserted at the top of the file (right after `{`). Existing content is preserved. If the file doesn't exist, it is created with the block. If an existing `// >>> project-switcher` block exists, it is replaced.

2. Launch:
   - **Direct projects:** `code --new-window <project-path>`
   - **Agent Layer projects** (`useAgentLayer = true`): inject settings.json block, run `al sync` with working directory set to the project path, then `al vscode --no-sync --new-window` (working directory = project path). This avoids a current `al vscode` dual-window issue by not passing a positional path, and preserves Agent Layer env vars like `CODEX_HOME`.
   - **SSH projects:** Write the settings.json block on the remote via SSH (read remote file → inject block → base64-encode → write). Then `code --new-window --remote <authority> <remote-path>`. If the SSH write fails, project activation fails loudly (no workspace fallback).

### Poll until window appears

After launch, poll `list-windows` (using the global-with-fallback pattern) until a window matching the token appears, with a 10-second timeout and 100ms interval.

## Step 2: Move windows to workspace (sequential)

Move **Chrome first** (no focus follow), then **VS Code** (with focus follow):

```sh
# Chrome: move without following focus
aerospace move-node-to-workspace --window-id <chrome-id> <workspace>

# VS Code: move with focus follow (lands focus in target workspace)
aerospace move-node-to-workspace --focus-follows-window --window-id <ide-id> <workspace>
```

The `--focus-follows-window` flag on the IDE move is critical — it shifts the user's view to the target workspace so subsequent focus commands operate in the right context.

**Fallback:** If `--focus-follows-window` is not supported, fall back to a plain move:

```sh
aerospace move-node-to-workspace --window-id <ide-id> <workspace>
```

## Step 3: Verify windows arrived

Poll `list-windows --workspace <workspace>` until both window IDs appear, with a 10-second timeout:

```sh
aerospace list-windows --workspace <workspace> --format <format>
```

## Step 4: Focus workspace

Use `summon-workspace` (preferred for multi-monitor) with fallback to `workspace`:

```sh
# Preferred: pulls workspace to current monitor
aerospace summon-workspace <workspace>

# Fallback: switches to workspace wherever it is
aerospace workspace <workspace>
```

Verify with dual-signal polling (both must be true):

```sh
# Signal 1: workspace summary marks target as focused
aerospace list-workspaces --all --format "%{workspace}||%{workspace-is-focused}"

# Signal 2: focused window reports target workspace
aerospace list-windows --focused --format <format>
```

## Step 5: Focus IDE window

```sh
aerospace focus --window-id <ide-window-id>
```

## Step 6: Verify focus stability

Poll `list-windows --focused` repeatedly. If the focused window ID matches the target, focus is stable. If focus is lost (macOS or another app steals it), re-assert with `aerospace focus --window-id`:

```sh
# Check current focus
aerospace list-windows --focused --format <format>

# Re-assert if stolen
aerospace focus --window-id <ide-window-id>
```

The Swift activation flow uses a 10-second timeout with 100ms polling interval. If focus cannot be verified within the timeout, activation fails loudly.

### Focus trace (diagnostic only)

Current Swift implementation does not run the older sampled shell trace. On focus verification timeout, activation returns failure immediately.

[1]: https://nikitabobko.github.io/AeroSpace/commands "AeroSpace Commands"
[2]: https://nikitabobko.github.io/AeroSpace/guide "AeroSpace Guide"
[3]: https://nikitabobko.github.io/AeroSpace/goodies "AeroSpace Goodies"
