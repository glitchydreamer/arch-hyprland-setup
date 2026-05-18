# Keybinds

A working reference for the chords that actually fire on this setup.
Caelestia defaults plus the personal additions in
`~/.config/caelestia/hypr-user.conf`.

## Modifier convention

The single `Super+<letter>` namespace is owned by **window / workspace /
caelestia panel actions** — every letter is one keystroke away from a window
operation. That's the whole point of a tiling WM. Trying to cram app
launchers in there overwrites the action layer.

Personal apps therefore live on **`Super+Shift+<mnemonic letter>`** —
two-fingers-while-holding-Super, same speed once learned, mnemonic on the
letter (G = Google Chrome, F = Firefox, etc.).

## Apps

```
APPS — Super+Shift+<letter>
  Super+Shift+G  →  Google Chrome
  Super+Shift+F  →  Firefox
  Super+Shift+B  →  Brave
  Super+Shift+E  →  Microsoft Edge
  Super+Shift+A  →  Antigravity
  Super+Shift+D  →  Claude Desktop
  Super+Shift+K  →  KWrite
  Super+Shift+I  →  KDE System Settings   (I = settIngs / Info)
  Super+Shift+N  →  NVIDIA X Server Settings
  Super+Shift+P  →  Mission Center        (P = Performance)
  Super+Shift+U  →  Discover               (U = Updates)
```

Defined in `~/.config/caelestia/hypr-user.conf`. All apps are launched via
`app2unit -- <cmd>` so they run as systemd user units with clean process
accounting.

### Apps already on single Super (caelestia defaults — don't rebind)

```
Super+T  →  Terminal (foot)
Super+W  →  Default browser (Zen, via $browser variable)
Super+C  →  VS Code         ($kbEditor)
Super+E  →  Dolphin         ($kbFileExplorer)
Super+G  →  GitHub Desktop  (user override)
```

## Caelestia panels (the auto-hidden bars)

The bar, top notifications, and bottom-right utilities all default to
`showOnHover: true` — they appear when you nudge the screen edge with the
mouse. The IPC bindings below toggle them explicitly without needing the
hover gesture.

```
Super+Shift+Y  →  toggle bar         (left taskbar)
Super+Shift+O  →  toggle dashboard   (top notifications)
Super+Shift+J  →  toggle utilities   (bottom-right status / quick toggles)
```

Plus caelestia's own:

```
Super+N        →  toggle sidebar     (right control panel)
Super+K        →  show ALL panels    (taskbar + notifications + status at once)
```

These all run `qs -c caelestia ipc call drawers toggle <name>` under the hood.
`<name>` is one of: `bar`, `dashboard`, `utilities`, `sidebar`, `osd`,
`session`, `launcher`. Full list: `qs -c caelestia ipc call drawers list`.

## Window & workspace (caelestia defaults — cheat sheet)

The window/workspace layer that consumes most of single-Super:

| Combo | Action |
|---|---|
| `Super+1..9, 0` | Switch to workspace 1..10 |
| `Super+Shift+1..0` | Move focused window to workspace |
| `Super+Page_Up/Down`, `Super+mouse_scroll` | Prev/next workspace |
| `Super+arrow` | Move focus left/right/up/down |
| `Super+Shift+arrow` | Move *window* l/r/u/d |
| `Super+Alt+arrow`, `Super+Minus/Equal` | Resize active window |
| `Super+F` | Fullscreen |
| `Super+Q` | Close window |
| `Super+H` | Send to "minimized" special workspace (your override) |
| `Super+Shift+H` | Bring "minimized" back (your override) |
| `Super+P` | Pin / float-above |
| `Super+L` | Lock screen |
| `Super+S` | Toggle special workspace |
| `Super+Space` | Launcher (caelestia fuzzy) |
| `Super+V` | Clipboard history |
| `Super+Period` | Emoji picker |
| `Super+M`, `Super+D`, `Super+R` | Music, Communication, Todo overlays |
| `Super+Ctrl+Alt+H` | Toggle HDR on DP-2 (`hdr-toggle`) |
| `Print` | Screenshot to clipboard |
| `Super+Shift+S` | Region screenshot (frozen) |
| `Super+Shift+Alt+S` | Region screenshot (live) |
| `Ctrl+Alt+Delete` | Session menu (logout / reboot / shutdown) |

Open the full keybinds source any time:
`~/.config/hypr/hyprland/keybinds.conf`. Definitions of the `$kb*` aliases
live in `~/.config/hypr/variables.conf`.

## Adding more app binds

Any new app launcher follows the same pattern. Pick a free `Super+Shift+<letter>`,
edit `~/.config/caelestia/hypr-user.conf`, save, and the caelestia
config-watcher reloads Hyprland automatically (or run `hyprctl reload`).

```ini
bind = Super+Shift, X, exec, app2unit -- some-app
```

To check whether a combo is already used:

```bash
hyprctl binds -j | jq -r '.[] | "\(.modmask) \(.key)  →  \(.dispatcher) \(.arg)"' | grep ' X$'
```

Modmask reference: `64` = Super, `65` = Super+Shift, `72` = Super+Ctrl,
`80` = Super+Alt, `81` = Super+Shift+Alt, `73` = Super+Shift+Ctrl.

## Conflicts checked

These additions were verified against the existing bind table — no overlaps
with caelestia's keybinds, the user overrides already in `hypr-user.conf`, or
the `$kb*` variable definitions. Verify yourself any time:

```bash
hyprctl binds -j | jq -r '.[] | select(.modmask==65) | "\(.key)  →  \(.dispatcher) \(.arg)"' | sort
```

## Required package (one-time)

Mission Center isn't installed by default on this drive. To make
`Super+Shift+P` work:

```bash
sudo pacman -S mission-center
```

Until then the bind is a no-op (the command runs and fails silently).
