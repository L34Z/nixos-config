# Hyprland Lua config — migration notes & the `hyprctl dispatch` gotcha

Since **Hyprland 0.55** hyprlang is deprecated in favour of Lua. When
`$XDG_CONFIG_HOME/hypr/hyprland.lua` exists it is loaded **instead of**
`hyprland.conf` (the two are never merged). Confirm which was picked in the log:

```
grep -n 'Using lua config' /run/user/$(id -u)/hypr/*/hyprland.log
# → [cfg] Using lua config found at /home/z/.config/hypr/hyprland.lua
```

Our live config is `home/dotfiles/hypr/hyprland.lua` (out-of-store symlink, so
edits apply on the next reload — see "Reload vs restart" below). The old
`hyprland.conf` is kept only as a reference until the migration is trusted.

## Authoritative API reference (local, versioned with your Hyprland)

- **`…/share/hypr/stubs/hl.meta.lua`** — LuaLS annotations for the entire `hl.*`
  surface (dispatchers, config keys, rule specs). This is the source of truth,
  not the wiki. Find it with:
  ```
  find /nix/store -path '*hyprland*/share/hypr/stubs/hl.meta.lua' 2>/dev/null
  ```
- **`…/share/hypr/hyprland.lua`** — the distro's example config (working idioms).

## THE GOTCHA that broke the migration

**Under the Lua config, `hyprctl dispatch <arg>` evaluates `<arg>` as Lua** — it
wraps it as `hl.dispatch(<arg>)`. So the old hyprlang-style flat commands are now
**Lua syntax errors that silently no-op**:

```
$ hyprctl dispatch exec kitty
error: [string "return hl.dispatch(exec kitty)"]:1: ')' expected near 'kitty'
 → Note: dispatch in lua is a shorthand for hl.dispatch(...), your syntax might need to be updated.
```

The first migration used a `hl.dsp.exec_cmd("hyprctl dispatch exec '[workspace
special:…] cmd'")` "escape hatch" everywhere the clean `hl.*` form was unknown.
Every one of those expanded to invalid Lua and did nothing. Symptoms:

- SUPER+SHIFT scratchpad spawns did nothing.
- The startup **prewarm loop** created no special workspaces.
- SUPER+F / SUPER+SHIFT+F fullscreen did nothing.

Binds still *registered* (61 of them, `hyprctl configerrors` clean) because the
bad string is just the dispatcher's *argument* — the failure is deferred to
keypress/exec time, so nothing warns you at config load.

### Correct `hl.*` forms (no shell-out)

| Intent | Wrong (old escape hatch) | Right |
|---|---|---|
| Exec into a **silent** special ws (prewarm) | `hl.exec_cmd("hyprctl dispatch exec '[workspace special:foo silent] cmd'")` | `hl.exec_cmd("cmd", { workspace = "special:foo silent" })` |
| Bind: spawn into a special ws | `hl.dsp.exec_cmd("hyprctl dispatch exec '[workspace special:foo] cmd'")` | `hl.dsp.exec_cmd("cmd", { workspace = "special:foo" })` |
| Fullscreen (maximize) | `hl.dsp.exec_cmd("hyprctl dispatch fullscreen 1")` | `hl.dsp.window.fullscreen("maximized")` |
| Fullscreen (true) | `hl.dsp.exec_cmd("hyprctl dispatch fullscreen 0")` | `hl.dsp.window.fullscreen("fullscreen")` |
| Toggle a special ws | — | `hl.dsp.workspace.toggle_special("foo")` |
| Move active window into a special ws | — | `hl.dsp.window.move({ workspace = "special:foo" })` |

Both `hl.exec_cmd` and `hl.dsp.exec_cmd` take an optional **exec-rules table** as
the 2nd arg (`{ workspace = …, float = …, … }`) — that is the clean replacement
for the `[…]` prefix. Valid `fullscreen` modes are exactly `"maximized"` and
`"fullscreen"` (a bad mode errors with `expected fullscreen/maximized`).

## Reload vs restart

- `hyprctl reload` **does** re-run the Lua and re-register binds (the earlier
  file-header claim that only a restart works was wrong).
- The `hl.on("hyprland.start", …)` autostart hook fires on the **startup** event
  only, so **prewarm does not re-run on reload** — scratchpads are pre-launched
  at login. After a `reload`, a scratchpad is created on its first toggle/spawn.

## Debugging via the Lua REPL

Because `hyprctl dispatch` now evals Lua, it doubles as a live REPL against the
running compositor:

```
# syntax-check the config WITHOUT running it (loadfile compiles only):
hyprctl dispatch 'assert(loadfile("/home/z/.config/hypr/hyprland.lua"))'   # → ok

# run a side-effecting call live (e.g. test an exec rule):
hyprctl dispatch 'hl.exec_cmd("kitty", { workspace = "special:test silent" })'
```

(An immediate `hl.exec_cmd` prints a harmless `hl.dispatch: expected a
dispatcher` note — the wrapper wanted a dispatcher return value — but the exec
still runs. `hl.dsp.*` calls return a real dispatcher and run cleanly.)

## Keybinds — parity with the old `hyprland.conf`

Bindings match the old `.conf` 1:1, including the scratchpad keys:

- **SUPER+RETURN** term · **K** close · **END** exit · **V** float · **F/SHIFT+F**
  maximize/fullscreen · **SPACE** launcher (caelestia) · **J** togglesplit · **B** browser ·
  **L** hyprlock · **arrows** focus · **1-0 / SHIFT+1-0** workspace switch/move.
- Scratchpads (SUPER toggle · SUPER+SHIFT spawn): **BACKSPACE** terminal ·
  **P** 1Password · **backslash** audio (pavucontrol) · **ESCAPE** btop ·
  **R** ranger.
- **SUPER+S** toggle / **SUPER+SHIFT+S** *move active window into* the `magic`
  scratchpad (the odd one out — SHIFT moves, it does not spawn).
- **SUPER+ALT+H/N/A** config editors · **SUPER+CTRL+END** shutdown ·
  **PRINT / SHIFT+PRINT** screenshots · CTRL+SHIFT wtype snippets.

Two deliberate deviations from the old `.conf` (behaviour, not key combos):

1. **SUPER+ALT+H** opens `hyprland.lua`, not the retired `hyprland.conf`.
2. **Prewarm** pre-launches *every* scratchpad at startup; the old config only
   prewarmed terminal/btop/ranger and started 1Password via `--silent`.
