# Keybinds

A working reference for the chords that actually fire on this setup.
Caelestia defaults plus the personal additions in
`~/.config/caelestia/hypr-vars.conf` and `~/.config/caelestia/hypr-user.conf`.

## Modifier convention

The single `Super+<letter>` namespace is owned by **window / workspace /
caelestia panel actions** — every letter is one keystroke away from a window
operation. That's the whole point of a tiling WM. A handful of letters are
already wired to apps via caelestia's `$browser` / `$editor` / `$fileExplorer`
variables (see below) — those land the most-used apps on the shortest chord.

Everything else lives on **`Super+Shift+<mnemonic letter>`**.

## Apps on single Super (most-used)

Caelestia ships `$kbBrowser`, `$kbEditor`, `$kbFileExplorer`, `$kbTerminal`
which bind to `Super+W / C / E / T` and `exec app2unit -- $variable`. The
defaults point at apps that aren't installed on this system
(`zen-browser`, `codium`, `thunar`), so the variables are overridden in
`~/.config/caelestia/hypr-vars.conf`:

```ini
$browser      = firefox
$editor       = code
$fileExplorer = nautilus
```

`hypr-vars.conf` is sourced **after** caelestia's `variables.conf` but
**before** its `keybinds.conf`, so the existing bind lines pick up the new
values automatically — no separate rebind needed.

`Super+G` (originally `github-desktop`, also not installed) is rebound in
`hypr-user.conf` using `unbind` + `bind` to retarget it onto Google Chrome:

```ini
unbind = Super, G
bind   = Super, G, exec, app2unit -- google-chrome-stable
```

Result:

```
Super+T  →  Terminal (foot)
Super+W  →  Firefox
Super+C  →  VS Code
Super+E  →  Nautilus
Super+G  →  Google Chrome
```

## Apps on Super+Shift

Defined in `~/.config/caelestia/hypr-user.conf`, all launched via
`app2unit -- <cmd>` so they run as systemd user units with clean process
accounting.

```
Super+Shift+B  →  Brave
Super+Shift+E  →  Microsoft Edge
Super+Shift+A  →  Antigravity
Super+Shift+D  →  Claude Desktop
Super+Shift+K  →  KWrite
Super+Shift+I  →  KDE System Settings   (I = settIngs / Info)
Super+Shift+N  →  NVIDIA X Server Settings
Super+Shift+P  →  Mission Center        (P = Performance)
Super+Shift+U  →  Discover               (U = Updates)
Super+Shift+Z  →  Zen Browser
Super+Shift+V  →  Obsidian               (V = Vault)
```

Firefox and Chrome are intentionally **not** duplicated here — they already
sit on the shorter `Super+W` / `Super+G` chords.

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
| `Super+Ctrl+Alt+H` | Toggle HDR on DP-1 (`hdr-toggle`) |
| `Print` | Screenshot to clipboard |
| `Super+Shift+S` | Region screenshot (frozen) |
| `Super+Shift+Alt+S` | Region screenshot (live) |
| `Ctrl+Alt+Delete` | Session menu (logout / reboot / shutdown) |

Open the full keybinds source any time:
`~/.config/hypr/hyprland/keybinds.conf`. Definitions of the `$kb*` aliases
live in `~/.config/hypr/variables.conf`.

## Adding your own keybinds

**This is identical on the Arch and CachyOS builds** — both generate
`~/.config/caelestia/hypr-user.conf` from the same `setup-home.sh hyprland`
component, and on both, `hyprland.conf` sources that file **last**, so anything you
put there wins over caelestia's defaults without touching the upstream tree. Every
kind of keybind — app launchers, system commands, workspaces, window actions — goes
in this one file.

### The syntax

```ini
bind = MODS, KEY, DISPATCHER, ARGS
```

- **MODS** — `Super`, `Shift`, `Ctrl`, `Alt`, combined with `+` (e.g. `Super+Shift`).
  Leave empty for no modifier: `bind = , XF86AudioPlay, ...`.
- **KEY** — a letter/number, a named key (`Return`, `space`, `comma`, `Print`,
  `XF86AudioRaiseVolume`), or `code:NN` for a raw keycode.
- **DISPATCHER + ARGS** — what it does (see categories below). Full list:
  [Hyprland dispatchers](https://wiki.hyprland.org/Configuring/Dispatchers/).

### By category

```ini
# Launch a GUI app — use app2unit (runs it as a systemd user unit, the convention
# every launcher here follows; gives clean process accounting + cgroup isolation):
bind = Super+Shift, X, exec, app2unit -- some-app

# Run a script or system command — plain exec:
bind = Super+Shift, L, exec, ~/.local/bin/my-script.sh
bind = , XF86AudioRaiseVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+
bind = Super, Print, exec, grim -g "$(slurp)" - | wl-copy   # region screenshot

# Workspaces — `workspace` to switch, `movetoworkspace` to send the focused window:
bind = Super, F1,       workspace, 6
bind = Super+Shift, F1, movetoworkspace, 6
bind = Super, grave,    workspace, previous

# Window / system actions — any dispatcher:
bind = Super, F, fullscreen, 0
bind = Super+Shift, Q, killactive,
```

Launch GUI apps by their **binary** name (`which <cmd>`), not the package name —
see the [gotcha below](#package-name-vs-binary-name-gotcha).

### Overriding a caelestia default

If a chord is already taken (Super+1–9, Super+Q, the Super+Ctrl arrows, …),
`unbind` it first, then rebind — exactly how `Super+G` is retargeted to Chrome:

```ini
unbind = Super, G
bind   = Super, G, exec, app2unit -- google-chrome-stable
```

### Apply the change

No logout needed — save the file and run:

```bash
hyprctl reload
```

If a bind doesn't fire, `hyprctl reload` prints any parse error; otherwise check it
registered with `hyprctl binds`.

### Check a combo isn't already used

```bash
hyprctl binds -j | jq -r '.[] | "\(.modmask) \(.key)  →  \(.dispatcher) \(.arg)"' | grep ' X$'
```

Modmask reference: `64` = Super, `65` = Super+Shift, `72` = Super+Ctrl,
`80` = Super+Alt, `81` = Super+Shift+Alt, `73` = Super+Shift+Ctrl.

!!! warning "Make a bind survive a fresh reinstall"
    `hypr-user.conf` is **generated** by `setup-home.sh` and is *not* tracked in the
    repo — a clean `setup-home.sh hyprland` run rewrites it from the template, so
    binds you add by hand live only on that box. To make one permanent across
    reinstalls, add it to the `hypr-user.conf` heredoc in **both** `arch/setup-home.sh`
    and `cachyos/setup-home.sh` and commit. For quick experiments, just edit the live
    file.

## Verifying no duplicates / dead targets

```bash
# Every Super+letter bind on this system, what it actually launches:
hyprctl binds -j | jq -r '.[] | select(.dispatcher=="exec") |
  select(.arg | test("app2unit|qs -c caelestia")) |
  "\(.modmask) \(.key)  →  \(.arg)"' | sort

# Does the target executable exist?
for cmd in firefox code nautilus foot google-chrome-stable brave \
           microsoft-edge-stable antigravity claude-desktop kwrite \
           systemsettings nvidia-settings missioncenter plasma-discover \
           zen-browser obsidian; do
    which "$cmd" >/dev/null 2>&1 && echo "OK   $cmd" || echo "MISS $cmd"
done
```

## Known dead caelestia default (not fixed — harmless)

Caelestia also ships `bind = Super+Alt, E, exec, app2unit -- nemo`. Nemo
isn't installed and there's no reason to install a second file manager —
`Super+E` (Nautilus) is what you'll actually use. The bind sits idle.
If it ever annoys you, drop `unbind = Super+Alt, E` into `hypr-user.conf`.

## Package-name vs. binary-name gotcha

Some apps install their executable under a name that doesn't match the
package. Always launch by the **binary** name (what `which <cmd>` returns),
not the package name. Confirmed mismatches on this system:

| Package (`pacman -Qs`) | Binary (used in bind) |
|---|---|
| `mission-center` | `missioncenter` (no hyphen) |
| `visual-studio-code-bin` (if used) | `code` |
| `microsoft-edge-stable-bin` (if used) | `microsoft-edge-stable` |

When adding a new bind, sanity-check with `which <cmd>` first.
