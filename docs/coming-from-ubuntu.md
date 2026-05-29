# Coming from Ubuntu — what's different on Hyprland

Ubuntu/GNOME and KDE Plasma are **desktop environments**: integrated stacks
where the file manager, settings app, taskbar, notifications and theming all
ship and update together as one product. They assume mouse-first, dock-driven
interaction.

Hyprland + caelestia is a **tiling window manager + custom shell**: minimal by
design. Hyprland arranges windows; caelestia paints a vertical sidebar and a
launcher on top. There is no "Settings app" because there is no central
settings system — every subsystem (audio, network, bluetooth, GPU, theming)
has its own tool. The interaction model assumes keyboard-first: instead of
pinning apps to a dock you bind `Super+<key>` and launch with one keystroke;
instead of right-clicking icons you fuzzy-search the launcher.

That's not better or worse — it's different. This page maps the Ubuntu
muscle-memory to what works here.

## The "Settings app"

Closest equivalents:

| Tool | What it covers | Install |
|---|---|---|
| `systemsettings` (KDE) | display, audio, bluetooth, theming, input, keyboard shortcuts, regional. Most "Ubuntu Settings"-like; some panels assume Plasma and no-op on Hyprland. | `sudo pacman -S systemsettings` |
| `kinfocenter` | "About this system" — CPU/GPU/RAM/disks, kernel/distro, network stack | `sudo pacman -S kinfocenter` |
| `gnome-control-center` | GNOME Settings — closer to Ubuntu's exact look; bigger no-op surface on Hyprland | `sudo pacman -S gnome-control-center` |
| Per-area tools | `nm-connection-editor` (network), `pavucontrol` (audio), `blueman-manager` (bluetooth), `wdisplays` (monitors) | `pacman -S` as needed |

`systemsettings` is the current pick — installed by default. Launch from a
terminal or bind a key in `hypr-user.conf`:

```ini
bind = Super+Shift, S, exec, systemsettings
```

## The "Files" app (Nautilus → Dolphin)

Ubuntu uses **Nautilus** (GNOME Files); this setup uses **Dolphin** (KDE Files).
Different ecosystem, different shortcuts, but mostly the same feature set.

| Action | Nautilus (Ubuntu) | Dolphin (here) |
|---|---|---|
| Toggle hidden files | `Ctrl+H` | `Ctrl+H` (already toggled on by default — see below) |
| Show menu bar | `F10` (auto-hides) | menu bar is *disabled* by default in `dolphinrc`; press `Ctrl+M` to bring it back, or use the hamburger icon top-right |
| Split view | not built-in | `F3` |
| Show terminal panel | extension | `F4` |
| Show preview panel | sidebar toggle | `F11` (preview), `F9` (places sidebar) |
| Tabs | `Ctrl+T` | `Ctrl+T` |
| Address bar (type a path) | `Ctrl+L` | `Ctrl+L` |
| Properties | `Ctrl+I` | `Alt+Enter` |

**Hidden files defaults**: this repo's setup writes
`~/.config/dolphinrc` with `GlobalViewProps=true` and
`~/.local/share/dolphin/view_properties/global/.directory` with
`HiddenFilesShown=true`. The "global" view-property file is required because
Dolphin stores view state per-folder unless told to share globally.

If you genuinely prefer Nautilus, `sudo pacman -S nautilus` and set it default:
`xdg-mime default org.gnome.Nautilus.desktop inode/directory`.

## "Pin apps to taskbar + open with keyboard shortcut"

In a tiling WM the keybind itself is the pin — there is no taskbar to drop an
icon onto. Two ways to launch:

### Bind a hotkey per app

Most-used apps live on **single `Super+<letter>`** by retargeting caelestia's
`$browser` / `$editor` / `$fileExplorer` variables in `hypr-vars.conf`:

```
Super+T  →  foot         Super+G  →  Google Chrome
Super+W  →  Firefox       Super+E  →  Dolphin
Super+C  →  VS Code
```

Everything else uses `Super+Shift+<letter>` in `hypr-user.conf`:

```ini
bind = Super+Shift, B, exec, app2unit -- brave
bind = Super+Shift, I, exec, app2unit -- systemsettings
# ...
```

See [Keybinds](keybinds.md) for the full table and how to add more.

The `app2unit --` wrapper (caelestia ships it) launches the app under a
systemd user unit so it gets clean process accounting; plain `exec, dolphin`
works too.

### Use the launcher for everything else

**Tapping `Super`** (press and release the Super/Windows key by itself) opens
caelestia's launcher with fuzzy search across all installed `.desktop` apps — this
is your **Spotlight**. Type a few letters, Enter. For most apps this is *faster*
than clicking a pinned icon — there's no aiming, no scanning. (The bind is
`bindi = Super, Super_L` in caelestia's `keybinds.conf`.)

The launcher is fuzzy-search-only — no right-click action menu. If you want a
launcher with right-click actions, app history, ssh/window/clipboard modes,
swap to `rofi` (most mature) or `walker` (newer GTK option) — set the default
in `hypr-user.conf` and rebind the launcher key.

## "I want a horizontal taskbar at the bottom of the screen"

Caelestia's bar is architecturally vertical. It's a `ColumnLayout` in
`/etc/xdg/quickshell/caelestia/modules/bar/Bar.qml:12`, anchored to the left
edge in `BarWrapper.qml:78-80`, with the screen exclusion zone set to
`anchors.left: true` in `drawers/Exclusions.qml:15-18`, and every popout
positioned via Y-coordinate math against the vertical layout. There is no
`bar.position` knob in `shell.json` — making it horizontal at the bottom
means copying the package tree to `~/.config/quickshell/caelestia/`, rewriting
those files, and re-applying after every `caelestia-shell` update.

Pragmatic alternative: **waybar**. Install it, write a config that mirrors
caelestia's colors (caelestia exposes its scheme in
`~/.config/hypr/scheme/current.conf` — read it from waybar's stylesheet), kill
caelestia's bar process, keep the launcher / clipboard / wallpaper / HDR
toggle / scheme manager (those are independent of the bar). Waybar gives you
horizontal bottom placement, pinned apps, right-click context menus on
modules, window taskbar — out of the box.

This isn't done yet — left as a choice point. Revisit when the vertical bar
becomes a real friction point rather than a curiosity.

## "Right-click an app icon to see options"

Three layers to this in Ubuntu — and three different equivalents here:

| Ubuntu interaction | Hyprland equivalent |
|---|---|
| Right-click pinned app in dock → "New Window", "Quit", "Pin/Unpin" | Bind a key per action: `Super, W` opens browser; `Super+Shift+Q` (or `closewindow`) closes |
| Right-click on desktop → background, display, terminal here | No "desktop" in tiling WMs; reach for the keybind cheat-sheet (`Super, ?`) |
| Right-click in launcher → app context (open with, properties, app info) | Caelestia's launcher doesn't expose this; rofi/walker do |
| Right-click in file manager → file actions | Dolphin behaves exactly like Nautilus — works as expected |

## Other Ubuntu-isms and where they live

| Ubuntu / GNOME thing | Where here |
|---|---|
| GNOME Tweaks | `gnome-tweaks` (works, doesn't change WM behavior) or `systemsettings` |
| Activities overview / Spotlight (`Super`) | **tap `Super`** opens the launcher for apps; workspaces switch with `Super+1..5` |
| Notifications shade (top of screen) | Caelestia's notifications popout (top-right by default) |
| Quick settings (top-right toggle bar) | Caelestia's control center panel |
| Snap store | None here — use `pacman` / `paru` (AUR) |
| Software Updater notification | `paru -Syu` (manual); auto-update isn't enabled by design |
| Startup applications GUI | `exec-once = ...` lines in `~/.config/hypr/hyprland/execs.conf` |
| Default applications | `xdg-mime default <app>.desktop <mime/type>` |
| Disks utility | `gnome-disk-utility` (`sudo pacman -S gnome-disk-utility`) — works fine; `df -h` for a quick CLI check |
| Clicking an NTFS/Windows drive auto-mounts it | Needs the userspace driver Arch omits: `bash install.sh storage` (ntfs-3g + exfatprogs). Then it mounts on click, like Ubuntu |
| Remote login / "Sharing → Remote Desktop" | `bash install.sh remote` — enables `sshd` (SSH in) + `freerdp`/`remmina` (RDP/VNC out) + `wayvnc` (VNC into this Wayland desktop). See [reference §9](../reference.md) |
| System Monitor (Ctrl+Esc) | `btop` (TUI), `gnome-system-monitor` if you want a GUI |

## When this paradigm helps you

After the adjustment period the keyboard-first model is faster for most
workflows. Five seconds to reach the mouse, find an icon, click it, wait for a
menu, click again — vs. one keystroke. Workspaces (`Super+1..5`) replace
window-shopping a taskbar full of icons. Fuzzy launcher replaces hunting
through a Start menu.

What you give up: discoverability. Nothing tells you what's possible — you
need a cheat-sheet. Open it any time with the binding documented in
`keybinds.conf` (commonly `Super+?`), or read the file directly:
`~/.config/hypr/hyprland/keybinds.conf`.
