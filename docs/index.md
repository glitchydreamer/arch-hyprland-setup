# Arch + Hyprland Setup Reference

> New here? Start with [Project context](project-context.md) for a one-page map.

> Last updated 2026-05-27. HDR set to OFF by default; toggle with `Super + Ctrl + Alt + H`.
> Machine: Arch Linux + Hyprland + caelestia dotfiles, **GDM** as the display manager.
> The install lives on a portable NVMe and roams between two hosts —
> **desktop** (NVIDIA RTX 3060, LG Ultrawide 3440x1440@160 Hz on **DP-1**)
> and **laptop** (Intel Raptor Lake + RTX 4070 Mobile, BOE 16" 2560x1600@240 Hz on eDP-1).
> Per-host monitor config switches automatically on session start — see [Display setup](display.md).
>
> **Rebuilt 2026-05-27** on a fresh minimal Arch install (NVIDIA + GDM). The
> system-level half (packages, DualSense fix, CUDA, Docker/NVIDIA, fish shell)
> is reproduced by [`install.sh`](https://github.com/glitchydreamer/arch-hyprland-setup/blob/main/install.sh)
> at the repo root; the home-dir configs below were recreated directly. Two
> things changed vs. the previous install: the desktop output is now **DP-1**
> (was DP-2), and user Hyprland files live under `~/.config/caelestia/` because
> `~/.config/hypr` is now a symlink into the caelestia package tree.

---

## 1. File layout (where things live)

| Purpose | Path |
|---|---|
| Caelestia upstream config (don't edit) | `~/.local/share/caelestia/hypr/` |
| **Your Hyprland user overrides** | `~/.config/caelestia/hypr-user.conf` |
| **Your Hyprland variable overrides** | `~/.config/caelestia/hypr-vars.conf` |
| Hyprland entrypoint (symlink into caelestia tree) | `~/.config/hypr` → `~/.local/share/caelestia/hypr` |
| **Per-host monitor configs** | `~/.config/caelestia/hypr-monitors-{laptop,desktop}.conf` |
| Active monitor symlink (flips per host) | `~/.config/caelestia/hypr-monitors.conf` |
| Host-detection script (runs on session start) | `~/.local/bin/select-monitors.sh` |
| Fish shell config (caelestia) | `~/.config/fish/config.fish` |
| **Your fish dev-env additions** | `~/.config/fish/conf.d/dev-env.fish` |
| Personal scripts (in PATH) | `~/.local/bin/` |
| Robotics workspace | `~/robotics/ws` |
| DualSense audio → headphone jack | `~/.local/bin/dualsense-audio` + `~/.config/wireplumber/wireplumber.conf.d/51-dualsense-headphones.conf` |
| DualSense touchpad ignore (cursor) | `~/.config/caelestia/hypr-user.conf` (device block) + `/etc/udev/rules.d/71-dualsense-touchpad-ignore.rules` |
| HDR toggle script | `~/.local/bin/hdr-toggle` |

**Golden rule**: never edit anything under `~/.local/share/caelestia/`. It will be overwritten when caelestia updates. All your customisation goes in `~/.config/caelestia/hypr-user.conf` (sourced LAST, so it always wins).

After editing any Hyprland config: `hyprctl reload` (or just save — caelestia's helper auto-reloads).

---

## 2. Where to change a setting (the "Settings app" equivalent)

Linux has no single "Settings app" the way Ubuntu/GNOME or Plasma do — but `systemsettings` from KDE is installed here as the closest equivalent. Launch it with `systemsettings` (or pin a keybind). It covers display, audio, bluetooth, theming, input, keyboard shortcuts, and most of the panels you remember from Ubuntu. Some panels assume KDE Plasma is running and won't apply on Hyprland; the table below covers what really lives where.

Configuration is owned by different layers depending on what you're changing. Use this table as a first lookup, then jump to the file or command.

| I want to change... | Where | Notes |
|---|---|---|
| **Hyprland — windows, monitors, keybinds, input** | | |
| Keybinds, window rules, startup apps | `~/.config/caelestia/hypr-user.conf` | sourced last — always wins; full reference: [Keybinds](keybinds.md) |
| Monitor (resolution, refresh, scale, VRR) | `~/.config/caelestia/hypr-monitors-{laptop,desktop}.conf` | per-host file, picked automatically; see [Display setup](display.md) |
| Inspect / arrange displays (GUI) | `wdisplays` | drag-arrange, scale, refresh, VRR toggle — see [Display setup → Inspecting current state](display.md#inspecting-current-state) |
| Inspect displays (CLI, deep) | `drm_info` | full kernel DRM dump: modes, EDID, HDR/VRR caps, pixel formats |
| HDR / color management for DP-1 | toggle with `Super+Ctrl+Alt+H` (script `~/.local/bin/hdr-toggle`) | live mode flip via `hyprctl keyword monitor` |
| Gaps, borders, rounded corners, animations | `~/.config/caelestia/hypr-vars.conf` | `general / decoration / animations` blocks |
| Keyboard layout, repeat rate, mouse / trackpad | same — `input {}` block | |
| **Caelestia shell — bar, launcher, theme, notifications** | `~/.config/caelestia/shell.json` | reload with `Ctrl + Super + Shift + R` |
| Wallpaper | same | |
| **Audio (PipeWire / WirePlumber)** | `pavucontrol` (GUI, `Ctrl + Alt + V`) or `wpctl` (CLI) | Hyprland never touches audio |
| Audio EQ / effects | `easyeffects` | |
| **Network (NetworkManager)** | `nmcli` or `nm-connection-editor` | caelestia bar applet also works |
| **Bluetooth** | `bluetoothctl` or caelestia bar applet | |
| **Brightness** | `brightnessctl set 50%` or media keys | |
| **Sleep / power behavior** | `/etc/systemd/logind.conf` | manual: `Super + Shift + L` |
| **GTK theme, icons, cursor** | `gsettings set org.gnome.desktop.interface ...` | also `~/.config/gtk-{3,4}.0/` |
| **Fonts** | install + `fc-cache -f`; config in `~/.config/fontconfig/` | |
| **Time zone / locale** | `sudo timedatectl set-timezone ...` / `sudo localectl set-locale ...` | |
| **User account — password, groups** | `passwd`, `sudo usermod -aG GROUP $USER` | re-login for group changes |
| **Fish shell — aliases, env vars** | `~/.config/fish/conf.d/dev-env.fish` | `config.fish` is caelestia's — don't edit |
| **Prompt (starship)** | `~/.config/starship.toml` | |
| **Services / daemons** | `systemctl [start\|stop\|enable\|disable] foo` | user units: add `--user` |
| **Packages** | `sudo pacman -S pkg` / `paru -S pkg` (AUR) | no GUI store by default |
| **NVIDIA GPU** | `nvidia-settings` (GUI) | overclock, fan curves, monitor info |
| **Catch-all GUI ("Ubuntu Settings"-equivalent)** | `systemsettings` (KDE), `kinfocenter` (hardware/about) | most panels work without full KDE; some assume Plasma and no-op on Hyprland |
| **File manager — hidden files, view settings** | Dolphin: `Ctrl+H` toggles hidden; defaults in `~/.config/dolphinrc` (`GlobalViewProps=true`) + `~/.local/share/dolphin/view_properties/global/.directory` | Nautilus also installable if you prefer the Ubuntu Files UX |

### 2.1 Mental model

- **Hyprland** owns *how the desktop behaves while you use it* — windows, monitors, input devices, keybinds.
- **Caelestia** is the shell layered on top of Hyprland — bar, launcher, notifications, theme. Its config lives in `~/.config/caelestia/`.
- Underneath: **PipeWire** owns all audio. **NetworkManager** owns all networking. **systemd** owns services, boot, sleep, and power.

If a setting you're looking for isn't in `hypr-user.conf` / `hypr-vars.conf` / `shell.json`, it's almost certainly owned by one of those three lower layers.

### 2.2 "I want to..." one-liners

```bash
# Add a startup app (runs once at session login)
echo 'exec-once = signal-desktop' >> ~/.config/caelestia/hypr-user.conf

# Always-float a window class
echo 'windowrulev2 = float, class:^(MyApp)$' >> ~/.config/caelestia/hypr-user.conf

# Switch keyboard layout (Hyprland) to UK
#   in hypr-vars.conf:  input { kb_layout = gb }

# Change cursor theme system-wide
gsettings set org.gnome.desktop.interface cursor-theme "Bibata-Modern-Classic"

# Persist a Wi-Fi network
nmcli device wifi connect "SSID" password "..."

# Find which config file a tool actually reads
strace -f -e openat foo 2>&1 | grep -i config
```

### 2.3 Rule of thumb for "which file?"

- **Caelestia files under `~/.local/share/caelestia/`** — upstream defaults. Never edit. Will be overwritten on update.
- **Caelestia files under `~/.config/caelestia/`** — your overrides. Always edit here.
- **App-specific config under `~/.config/<app>/`** — owned by that app, not by Hyprland or caelestia.
- **System-wide config under `/etc/`** — needs `sudo`. Use only when no per-user equivalent exists (logind, fstab, pacman, etc.).

---

## 3. Hyprland keybind reference

`Super` = the Windows/Meta key.

### 3.1 Window focus + movement

| Action | Keys |
|---|---|
| Focus left / right / up / down window | `Super + ←/→/↑/↓` |
| Move window left / right / up / down | `Super + Shift + ←/→/↑/↓` |
| Drag-move with mouse | `Super + LMB` drag |
| Drag-resize with mouse | `Super + RMB` drag |
| **Hide / "minimize" focused window** | `Super + H` (sends to `special:minimized`) |
| **Show minimized stack** | `Super + Shift + H` |

### 3.2 Resizing

| Action | Keys |
|---|---|
| Resize ±10% right/left | `Super + =` / `Super + -` |
| Resize ±10% up/down | `Super + Shift + =` / `Super + Shift + -` |
| Resize with arrows (±10%) | `Super + Alt + ←/→/↑/↓` |
| **Enter sticky resize mode** | `Super + Ctrl + R` |
| └ In resize mode | arrows or `h/j/k/l` (±40 px); add `Shift` for ±120 px |
| └ Leave resize mode | `Esc` or `Enter` |

### 3.3 Maximize / fullscreen / float / pin

| Action | Keys |
|---|---|
| **Maximize (fullscreen)** | `Super + F` |
| Bordered fullscreen | `Super + Alt + F` |
| Toggle floating | `Super + Alt + Space` |
| Pin (sticks on all workspaces) | `Super + P` |
| Center window | `Ctrl + Super + \` |
| Pip-resize (55%×70% centered) | `Ctrl + Super + Alt + \` |
| Picture-in-picture mode | `Super + Alt + \` |
| Close window | `Super + Q` |

### 3.4 Half-screen snaps (your additions)

| Action | Keys |
|---|---|
| Snap to left half | `Super + Ctrl + ←` |
| Snap to right half | `Super + Ctrl + →` |
| Snap to top half | `Super + Ctrl + ↑` |
| Snap to bottom half | `Super + Ctrl + ↓` |

### 3.5 Splits / layout (dwindle)

| Action | Keys |
|---|---|
| **Toggle split direction (V↔H)** | `Super + Ctrl + J` |
| Pseudo-tile toggle | `Super + Ctrl + P` |
| Swap across split | `Super + Ctrl + O` |

### 3.6 Workspaces

| Action | Keys |
|---|---|
| Go to workspace N | `Super + 1..9, 0` |
| Move window to workspace N | `Super + Alt + 1..9, 0` |
| Next / prev workspace | `Ctrl + Super + →` / `Ctrl + Super + ←` |
| Scroll workspaces | `Super + scroll wheel` |
| Toggle special (scratchpad) | `Super + S` |
| Move window to special | `Super + Alt + S` |
| System monitor (special ws) | `Ctrl + Shift + Esc` |
| Music (special ws) | `Super + M` |
| Communication (special ws) | `Super + D` |
| Todo (special ws) | `Super + R` |

### 3.7 Window groups (tabbed groups inside a tile)

| Action | Keys |
|---|---|
| Toggle group | `Super + ,` |
| Cycle next/prev in group | `Alt + Tab` / `Shift + Alt + Tab` |
| Ungroup | `Super + U` |
| Lock group (no auto-merge) | `Super + Shift + ,` |

### 3.8 Apps

| App | Keys |
|---|---|
| Terminal (foot) | `Super + T` |
| Browser (zen-browser) | `Super + W` |
| Editor (codium) | `Super + C` |
| File explorer (thunar) | `Super + E` |
| Nemo file manager | `Super + Alt + E` |
| GitHub Desktop | `Super + G` |
| Audio mixer (pavucontrol) | `Ctrl + Alt + V` |
| Process viewer (qps) | `Ctrl + Alt + Esc` |

### 3.9 Utilities

| Action | Keys |
|---|---|
| Launcher (caelestia) | tap `Super` |
| Screenshot full → clipboard | `Print` |
| Screenshot region (freeze) | `Super + Shift + S` |
| Screenshot region | `Super + Shift + Alt + S` |
| Record screen with sound | `Super + Alt + R` |
| Record screen (silent) | `Ctrl + Alt + R` |
| Record region | `Super + Shift + Alt + R` |
| Color picker | `Super + Shift + C` |
| Clipboard history | `Super + V` |
| Clipboard delete entry | `Super + Alt + V` |
| Emoji picker | `Super + .` |
| Sidebar | `Super + N` |
| Show all panels | `Super + K` |
| Lock screen | `Super + L` |
| Sleep / suspend-hibernate | `Super + Shift + L` |
| Session menu | `Ctrl + Alt + Del` |
| Clear notifications | `Ctrl + Alt + C` |
| Reload caelestia shell | `Ctrl + Super + Shift + R` |

### 3.10 Media + volume

| Action | Keys |
|---|---|
| Play/pause | media key or `Ctrl + Super + Space` |
| Next track | media key or `Ctrl + Super + =` |
| Prev track | media key or `Ctrl + Super + -` |
| Mute output | mute key or `Super + Shift + M` |
| Volume up / down | media keys (±10%) |

### 3.11 HDR (your addition)

| Action | Keys |
|---|---|
| **Toggle HDR ↔ SDR** | `Super + Ctrl + Alt + H` |

---

## 4. How to edit / add keybinds

**Hyprland bind syntax**:

```
bind  = MODIFIERS, KEY, DISPATCHER, ARGS    # one-shot
binde = MODIFIERS, KEY, DISPATCHER, ARGS    # repeats while held
bindl = MODIFIERS, KEY, DISPATCHER, ARGS    # also fires while screen locked
bindm = MODIFIERS, KEY, DISPATCHER, ARGS    # mouse bind
bindr = MODIFIERS, KEY, DISPATCHER, ARGS    # fires on key release
```

`MODIFIERS` is `+`-joined: `Super`, `Ctrl`, `Alt`, `Shift`. Example: `Super+Ctrl+Alt`.

To **add** a bind: append a line to `~/.config/caelestia/hypr-user.conf`, then either save (auto-reload) or run `hyprctl reload`.

To **override** a caelestia default: just rebind the same key combo in your user file — last-loaded wins.

To **disable** a caelestia bind: `unbind = MODIFIERS, KEY`.

To **discover** a Hyprland dispatcher: run `hyprctl dispatch -h` or browse <https://wiki.hyprland.org/Configuring/Dispatchers/>.

Quick examples to drop into `hypr-user.conf`:

```
# Open the file manager on Super+B
bind = Super, B, exec, app2unit -- thunar

# Bigger resize step (override caelestia's ±10%)
unbind = Super, Equal
unbind = Super, Minus
binde = Super, Equal, resizeactive, 20% 0
binde = Super, Minus, resizeactive, -20% 0
```

Live reload + verify:

```
hyprctl reload
hyprctl binds | grep -A3 'YourKeyHere'
```

---

## 5. HDR / color management

### 5.1 Current state

Your monitor (LG Ultrawide on DP-1) supports:

- HDR10 (SMPTE ST2084 / PQ EOTF)
- BT.2020 RGB + YCC color spaces
- Peak luminance 302 nits (HDR400 tier)
- VRR 48–160 Hz

**HDR is OFF by default** — the session starts in plain 8-bit sRGB. HDR is opt-in per session via the toggle bind (`Super + Ctrl + Alt + H`).

The default monitor line in `~/.config/caelestia/hypr-monitors-desktop.conf`:

```
monitor = DP-1, 3440x1440@159.96, 0x0, 1, bitdepth, 10, cm, srgb, vrr, 0
```

Boot baseline: native resolution, 160 Hz **fixed** (VRR off — see
[Display setup → G-Sync vs. VRR](display.md#g-sync-vs-freesync-vs-vrr-theyre-all-the-same-thing)),
**10-bit** SDR within the sRGB gamut. HDR is opt-in per session.

(Previously this lived in `hypr-user.conf`. It moved to a per-host file so the
same SSD can boot cleanly on the laptop too — see [Display setup](display.md).)

When toggled on, the HDR profile applied by `~/.local/bin/hdr-toggle` is:

```
monitor = DP-1, 3440x1440@159.96, 0x0, 1, bitdepth, 10, cm, hdr, sdrbrightness, 1.5, sdrsaturation, 1.0
```

Rationale for SDR-default: most Linux apps don't produce HDR output, SDR content under HDR mode often looks dim/washed-out without tuning, and HDR + VRR can flicker. Enable HDR only when launching an HDR-aware client (mpv with `--target-colorspace-hint=yes`, gamescope, Steam-in-gamescope).

### 5.2 Monitor line syntax

```
monitor = NAME, RESOLUTION@RATE, POS, SCALE, [extra args]
```

Extra args (comma-separated key/value pairs):

| Arg | Values | What |
|---|---|---|
| `bitdepth` | `8` / `10` | Output bit depth (10 needed for HDR) |
| `cm` | `srgb` / `wide` / `hdr` / `hdredid` | Color management preset |
| `sdrbrightness` | float, typ. `1.0`–`2.5` | Multiplier for SDR content brightness in HDR mode |
| `sdrsaturation` | float, typ. `1.0` | SDR saturation in HDR mode |
| `vrr` | `0` / `1` / `2` | VRR off / on / fullscreen-only |
| `bitdepth, 10, cm, srgb` | | Plain 10-bit SDR (wider color than 8-bit) |
| `cm, wide` | | Wide gamut without HDR |
| `cm, hdr` | | HDR with metadata derived from settings above |
| `cm, hdredid` | | HDR using the metadata reported in the monitor EDID |

### 5.3 Toggling HDR live

The bind `Super + Ctrl + Alt + H` runs `~/.local/bin/hdr-toggle` which flips between HDR and sRGB on-the-fly via `hyprctl keyword monitor`. No reload required. Since SDR is the boot default, the first press of this bind enables HDR for the session; the second press returns to SDR.

The script **auto-detects the target monitor** (the first non-eDP output — i.e. the desktop ultrawide, not the laptop panel) and reads its *current* mode/position/scale, so it isn't pinned to a connector or resolution. It's written by `setup-home.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
MON=$(hyprctl monitors -j | jq -r '([.[] | select(.name|test("eDP")|not)] + .)[0].name')
read -r W H R X Y S STATE < <(hyprctl monitors -j | jq -r --arg m "$MON" \
    '.[] | select(.name==$m) | "\(.width) \(.height) \(.refreshRate) \(.x) \(.y) \(.scale) \(.colorManagementPreset)"')
MODE="${W}x${H}@${R}"
case "$STATE" in
  srgb|unknown)
    hyprctl keyword monitor "$MON, $MODE, ${X}x${Y}, $S, bitdepth, 10, cm, hdr, sdrbrightness, 1.5, sdrsaturation, 1.0"
    notify-send -i video-display "HDR enabled" "$MON • HDR10 / BT.2020"
    ;;
  *)
    hyprctl keyword monitor "$MON, $MODE, ${X}x${Y}, $S, bitdepth, 10, cm, srgb, vrr, 0"
    notify-send -i video-display "HDR disabled" "$MON • sRGB / 10-bit"
    ;;
esac
```

### 5.4 Verifying HDR is on

```
hyprctl monitors -j | jq '.[] | {name, colorManagementPreset, currentFormat}'
```

- `colorManagementPreset: "hdr"` and `currentFormat: "XBGR2101010"` → HDR active.
- `colorManagementPreset: "srgb"` and `currentFormat: "XBGR2101010"` → 10-bit SDR (the default).
- `colorManagementPreset: "srgb"` and `currentFormat: "XRGB8888"` → 8-bit SDR (laptop, or pre-update desktop).

### 5.5 Caveats

- Most Linux apps don't produce HDR output. **Working HDR clients today**: mpv (`--target-colorspace-hint=yes`), gamescope-wrapped games, Steam in gamescope mode.
- If SDR content looks dim under HDR, raise `sdrbrightness` (try `1.8` then `2.0`).
- HDR + VRR sometimes causes flicker on certain monitors. Disable VRR (`vrr, 0`) if you see it.
- Browser HDR (Netflix/YouTube HDR) is hit-or-miss on Linux even now.

### 5.6 Persisting tweaks

If you decide you like `sdrbrightness, 1.8`, edit the `monitor =` line in `~/.config/caelestia/hypr-monitors-desktop.conf` to make it permanent across reboots. The toggle script picks up the monitor's *current* mode/position/scale automatically, but `sdrbrightness`/`sdrsaturation` are still hard-coded in `hdr-toggle` (and in `setup-home.sh`, which generates it) — update them there if you tweak.

---

## 6. Installed software

### 6.1 Dev toolchain

- **Compilers/build**: gcc 16, clang 22, cmake, ninja, meson, ccache, make, pkgconf
- **Debug/profile**: gdb, lldb, valgrind, cppcheck, doxygen, graphviz
- **C++ libs**: boost, eigen, tbb, openssl
- **CUDA 13.2** at `/opt/cuda` (path in `/etc/profile.d/cuda.sh`; fish gets it via `dev-env.fish`)
- **cuDNN 9.22**

> **Driver-matched CUDA.** Arch's `cuda` package is rolling — always the newest
> toolkit, which needs a recent enough driver. `install.sh` reads the max CUDA
> your driver supports (the `CUDA Version` field in `nvidia-smi`) and only
> installs the repo `cuda`/`cudnn` if the repo toolkit is **≤** that ceiling.
> If the repo toolkit is too new for your driver, it falls back to an AUR
> `cuda-<major.minor>` pinned to the driver (and tells you to bump the driver if
> no match exists). So the same script does the right thing across driver
> versions — it won't install a CUDA your driver can't run.

### 6.2 Python (3.14.5)

pip, pipx, virtualenv, numpy, scipy, pandas, scikit-learn, matplotlib, h5py, jupyterlab, ipython, pytest, mypy, ruff, pylint, black.

### 6.3 Node.js (26.1) + JS toolchain

npm 11, pnpm 10, yarn classic.

### 6.4 Editors

- **VS Code** (MS official build) — binary `code`. Extensions: Python, Pylance, C++, CMake Tools, ROS, Docker, YAML, Ruff, Jupyter.
- **Neovim 0.12** with LazyVim starter at `~/.config/nvim`.
- **Zed** — binary is `zeditor` on Arch (`zed` is taken by something else). Fish abbr `zed` aliases to `zeditor`.

### 6.5 Containers / robotics

- **Docker 29.5** with NVIDIA runtime. You're in the `docker` group.
- **ROS 2 Jazzy** via Docker image `osrf/ros:jazzy-desktop-full` (6.35 GB).
- Launcher: `ros2-jazzy` (subcommands `shell`, `run "..."`, `attach`, `stop`, `pull`).
- Workspace: `~/robotics/ws` mounted as `/root/ws` in the container.

### 6.6 Audio / DualSense

- PipeWire + WirePlumber.
- DualSense earphone-jack output: a WirePlumber drop-in re-enables ACP
  auto-profile/auto-port so the jack auto-routes; `dualsense-audio` forces it
  manually. (The old `PCM Playback Volume` amixer hack no longer applies — this
  controller is UCM/profile-based. See [troubleshooting §8.1](#81-dualsense-audio-silent-earphones-in-the-controller-jack).)
- DualSense touchpad is disabled as a pointer so it doesn't park a second cursor
  at screen centre (see [§8.8](#88-two-mouse-cursors-one-moving-one-stuck-at-centre)).

### 6.7 GPU / gaming

- NVIDIA driver 595.71 (nvidia-open), 12 GB RTX 3060.
- gamemode + lib32-gamemode (CPU governor boost while gaming).
- mangohud + lib32-mangohud (FPS / GPU overlay — enable per app with env `MANGOHUD=1` or as a Steam launch option).

### 6.8 Multimedia

- mpv (video), haruna (Qt video frontend), easyeffects (PipeWire EQ/effects), pavucontrol (audio mixer), obs-studio (recording/streaming), gimp/inkscape (if installed), okular (PDF), gwenview/swayimg (image).

### 6.9 Embedded / robotics CLI

- picocom + minicom (serial terminals — talk to `/dev/ttyUSB0`, etc.)
- arduino-cli
- stlink (STM32 flashing)
- openocd (JTAG/SWD)
- wireshark-qt (network protocol analysis; ROS DDS debugging)

### 6.10 Terminal productivity

fish (shell, with caelestia config), starship (prompt), fzf, ripgrep (`rg`), fd, bat, eza, zoxide (`cd` replacement), lazygit (`lg`), gh (GitHub CLI), tmux, tree, jq, yq.

---

## 7. Common commands cheat-sheet

### 7.1 Package management

```bash
sudo pacman -Syu              # update everything
sudo pacman -S pkg            # install from official repos
sudo pacman -Rns pkg          # remove + unused deps + config
paru -S pkg                   # install from AUR (or repos)
paru -Sua                     # update AUR packages only
pacman -Qq | grep foo         # search installed
pacman -Qi pkg                # info on installed package
pacman -Qdt                   # orphaned dependencies
```

#### Checking if a package is installed (e.g. cuDNN)

```bash
pacman -Qs cudnn              # query INSTALLED — empty output = not installed
pacman -Qi cudnn              # full info (version, install date); exits non-zero if absent
pacman -Ss cudnn              # search REMOTE repos (like `apt search`)
pacman -Ql cudnn              # list files the package owns
ldconfig -p | grep libcudnn   # verify the shared library is actually linkable
```

AUR packages installed via `paru`/`yay` still register with pacman, so `pacman -Qs` finds them too.

#### apt → pacman cheat sheet

| Ubuntu / Debian | Arch |
|---|---|
| `apt search foo \| grep installed` | `pacman -Qs foo` |
| `apt list --installed` | `pacman -Q` |
| `apt search foo` (remote) | `pacman -Ss foo` |
| `apt show foo` | `pacman -Si foo` (remote) / `pacman -Qi foo` (installed) |
| `dpkg -L foo` | `pacman -Ql foo` |
| `dpkg -S /path/to/file` | `pacman -Qo /path/to/file` |
| `apt update && apt upgrade` | `sudo pacman -Syu` |
| `apt install foo` | `sudo pacman -S foo` |
| `apt remove foo` | `sudo pacman -Rns foo` |
| `apt autoremove` | `sudo pacman -Rns $(pacman -Qdtq)` |

### 7.2 Hyprland

```bash
hyprctl monitors              # info on all monitors
hyprctl clients               # all open windows
hyprctl binds                 # all active keybinds (lots of output)
hyprctl reload                # reload config
hyprctl keyword KEY VALUE     # set a config value live
hyprctl dispatch KEY ARG      # invoke a dispatcher (same as a bind would)
hyprctl version
```

### 7.3 Audio

```bash
wpctl status                                    # tree view of audio devices/streams
wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.5       # set default sink volume to 50%
wpctl set-mute   @DEFAULT_AUDIO_SINK@ toggle    # toggle mute
pactl list short sinks                          # one-line list
pactl set-default-sink SINK_NAME                # change default
pavucontrol                                     # GUI mixer
amixer -c N contents                            # raw ALSA controls for card N
amixer -c N cset numid=N VALUE                  # set a raw control
```

### 7.4 ROS 2 Jazzy via Docker

```bash
ros2-jazzy                              # open interactive ROS shell
ros2-jazzy run "ros2 topic list"        # one-off command
ros2-jazzy attach                       # attach to existing container
ros2-jazzy stop                         # kill the container
ros2-jazzy pull                         # pull latest image
```

Inside the container, your host `~/robotics/ws` is at `/root/ws`. GPU is passed through. X11 + Wayland sockets are forwarded so `rviz2`, `rqt`, `gz sim` all open windows on your desktop.

### 7.5 Docker

```bash
docker ps                          # running containers
docker ps -a                       # all containers
docker images                      # local images
docker logs -f NAME                # follow logs
docker exec -it NAME bash          # shell into a running container
docker system prune                # reclaim space (careful)
```

### 7.6 Serial / microcontroller

```bash
picocom -b 115200 /dev/ttyUSB0     # serial term at 115200 baud (Ctrl-A Ctrl-X to quit)
minicom -D /dev/ttyACM0 -b 115200  # alternative
arduino-cli board list             # find connected boards
arduino-cli compile --fqbn FQBN sketch.ino
arduino-cli upload   --fqbn FQBN -p /dev/ttyUSB0 sketch.ino
st-info --probe                    # STM32 board info
st-flash write fw.bin 0x8000000    # flash STM32
```

### 7.7 Git (your defaults)

Already configured globally: `init.defaultBranch=main`, `push.autoSetupRemote=true`, `pull.rebase=false`, `fetch.prune=true`, `rerere.enabled=true`, `core.editor=nvim`.

**Identity** still needs setting:

```bash
git config --global user.name  "Your Name"
git config --global user.email "you@example.com"
```

---

## 8. Troubleshooting recipes

### 8.1 DualSense audio silent (earphones in the controller jack)

This bit us on the 2026-05-27 rebuild. The **old amixer/`numid` fix does not
apply** on a modern PipeWire stack: the DualSense is UCM/profile-based and has
*no* ALSA mixer controls (`amixer -c <card>` is empty). The real problem is
**routing**: the controller exposes its internal speaker and its 3.5mm jack as
separate PipeWire **profiles**, and it ships with auto-switching disabled
(`api.acp.auto-profile/auto-port = false`), so plugging earphones into the jack
never moves audio off the `HiFi (Mic, Speaker)` profile → silence.

Two-part fix (both written by `setup-home.sh`, no sudo):

```bash
# Immediate: route to the 3.5mm jack + make it default (the helper does all this)
dualsense-audio

# Under the hood it runs, roughly:
CARD=$(pactl list cards short | awk '/Sony|DualSense/{print $2; exit}')
pactl set-card-profile "$CARD" 'HiFi (Headphones, Mic)'
SINK=$(pactl list sinks short | awk '/Sony|DualSense/{print $2; exit}')
pactl set-default-sink "$SINK"; pactl set-sink-mute "$SINK" 0; pactl set-sink-volume "$SINK" 70%
```

Durable: `~/.config/wireplumber/wireplumber.conf.d/51-dualsense-headphones.conf`
turns ACP `auto-profile`/`auto-port` back **on** for the DualSense so WirePlumber
follows the jack automatically. If it ever doesn't catch, run `dualsense-audio`.

Inspect available profiles/ports:

```bash
pactl list cards | grep -A2 -iE 'Profiles:|Headphones'   # see HiFi (Headphones, Mic) etc.
pactl list sinks | grep -iE 'Description|Active Port'
```

### 8.2 Hyprland config change broke things

Hyprland keeps a log at `~/.local/share/hyprland/hyprland.log` (or run `hyprctl logs`). If a bad keybind crashes reload, edit `~/.config/caelestia/hypr-user.conf` from a TTY (Ctrl+Alt+F2) and re-launch.

### 8.3 No GPU in Docker

```bash
sudo docker run --rm --gpus all nvidia/cuda:12.6.0-base-ubuntu22.04 nvidia-smi
# If it errors:
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker
```

### 8.4 Need to talk to /dev/ttyUSB0 but get permission denied

You should be in the `uucp` group (Arch's convention for serial devices). Check with `groups`. If missing:

```bash
sudo usermod -aG uucp,lock $USER
# Then log out and back in.
```

### 8.5 Wireshark says "you need to be in wireshark group"

```bash
sudo usermod -aG wireshark $USER
newgrp wireshark      # apply to current shell, or just log out/in
```

### 8.6 HDR looks washed out / colors wrong

Try in order:

1. Bump `sdrbrightness, 1.8` (or `2.0`) in the monitor line, reload.
2. Swap `cm, hdr` → `cm, hdredid` (let monitor declare its own HDR metadata).
3. If still bad, just toggle off with `Super + Ctrl + Alt + H` and only enable HDR for mpv / gamescope sessions.

### 8.7 Gazebo natively (gz-harmonic) won't build

The AUR `gz-harmonic` package currently fails on gcc 16 because of `ogre-next2`, `fcl`, `libccd`, `octomap`. Use Gazebo via the ROS 2 Jazzy Docker image instead (`ros2-jazzy` → `gz sim ...`). Re-check in a few months once AUR maintainers patch.

### 8.8 Two mouse cursors (one moving, one stuck at centre)

**The actual cause here was the DualSense.** When the controller is plugged in
(e.g. for audio), its **touchpad** registers as an *absolute* pointer and parks
a cursor at the centre of the screen; the usable cursor is your real mouse.
Confirm by listing pointers — the touchpad shows up as a mouse:

```bash
hyprctl devices | grep -i touchpad
#  sony-interactive-entertainment-dualsense-wireless-controller-touchpad
```

Fix (both applied by the rebuild scripts):

1. **Hyprland disables the device** (`setup-home.sh` → `hypr-user.conf`, no sudo,
   takes effect on `hyprctl reload`):

   ```ini
   device {
       name = sony-interactive-entertainment-dualsense-wireless-controller-touchpad
       enabled = false
   }
   ```

2. **libinput ignores it outright** (`install.sh` → udev, survives reboots and
   works before any compositor sees the device):

   ```
   /etc/udev/rules.d/71-dualsense-touchpad-ignore.rules
   SUBSYSTEM=="input", ATTRS{name}=="Sony Interactive Entertainment DualSense Wireless Controller Touchpad", ENV{LIBINPUT_IGNORE_DEVICE}="1"
   ```
   Apply now without rebooting: `sudo udevadm control --reload-rules && sudo udevadm trigger`.
   This only affects the *pointer* role — the gamepad still works in games.

Separately, `hypr-user.conf` also keeps `cursor { no_hardware_cursors = true }`.
That addresses a *different* NVIDIA-Wayland class of stale-cursor bug (the GPU
leaving a stale image on the hardware cursor plane) and is harmless to keep on.
Verify: `hyprctl getoption cursor:no_hardware_cursors` → `int: 1`. GDM's own
login-screen cursor is unrelated.

---

## 9. Useful URLs

- Hyprland wiki: <https://wiki.hyprland.org/>
- Hyprland dispatchers: <https://wiki.hyprland.org/Configuring/Dispatchers/>
- Hyprland monitor config (HDR): <https://wiki.hyprland.org/Configuring/Monitors/>
- Caelestia dotfiles: <https://github.com/caelestia-dots/shell>
- ROS 2 Jazzy docs: <https://docs.ros.org/en/jazzy/>
- Arch wiki Hyprland: <https://wiki.archlinux.org/title/Hyprland>
- DualSense Linux info: <https://www.kernel.org/doc/html/latest/hid/hid-playstation.html>

---

## 10. Where things came from

Original setup performed by Claude on 2026-05-17. **Rebuilt 2026-05-27** on a
fresh minimal Arch install (clean `archinstall`, NVIDIA drivers, GDM instead of
SDDM). The whole thing is now reproducible by two idempotent scripts at the repo
root: [`setup-home.sh`](https://github.com/glitchydreamer/arch-hyprland-setup/blob/main/setup-home.sh)
(home-dir configs, no sudo — auto-detects the desktop connector) then
[`install.sh`](https://github.com/glitchydreamer/arch-hyprland-setup/blob/main/install.sh)
(packages + system, sudo — CUDA matched to the driver).
Notable deltas from the first install: desktop output moved DP-2 → **DP-1**,
user Hyprland files moved under `~/.config/caelestia/` (since `~/.config/hypr`
is now a symlink into the caelestia tree), and the NVIDIA ghost-cursor fix was
added (`cursor { no_hardware_cursors = true }` — see §8.8). Update or delete
this file freely — it's yours.
