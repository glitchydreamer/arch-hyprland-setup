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
> system-level half (packages, DualSense fix, CUDA, fish shell)
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
| Anaconda (general ML) | `/opt/anaconda`, `conda init fish`, base not auto-activated |
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
| **File manager — hidden files, view settings** | Nautilus (GNOME Files): `Ctrl+H` toggles hidden; launched by `Super+E`. Folder/app icons themed by `setup-home.sh nautilus` | Dolphin was removed in favour of Nautilus; `sudo pacman -S dolphin` to bring it back |

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

- **VS Code** (MS official build) — binary `code`. Extensions: Python, Pylance, C++, CMake Tools, YAML, Ruff, Jupyter.
- **Neovim 0.12** with LazyVim starter at `~/.config/nvim`.

> **Robotics status (working, 2026-05-28).** Isaac Sim **and** Isaac Lab run
> **natively** on this box after the NVIDIA stack was switched to driver
> **580.119.02** on the **`linux-lts`** kernel (Isaac's RTX renderer needs the
> 580 branch; Arch's 595 segfaults it — a driver-*version* mismatch, not
> hardware). The switch is automated/reversible via
> [`nvidia-switch.sh`](https://github.com/glitchydreamer/arch-hyprland-setup/blob/main/nvidia-switch.sh)
> `downgrade`. **ROS 2 Humble is wired up** too (`install.sh docker` + the
> `ros2-humble` launcher): the NVIDIA Container Toolkit injects the 580 host driver
> into containers, and `--network host` + `--ipc host` + a shared `ROS_DOMAIN_ID`/RMW
> (`rmw_fastrtps_cpp`) bridge the container to native Isaac's ROS 2 bridge over Fast
> DDS, with a UDP-only transport profile (a Jazzy container *crashed* Isaac on the
> cross-distro `ros_discovery_info` message — Humble matches Isaac's bundled Fast DDS
> 2.6, see §8). Run `ros2-humble pull` then `ros2-humble shell`; enable Isaac's
> `isaacsim.ros2.bridge` extension. CUDA + Anaconda remain for general ML; align CUDA to the 580
> ceiling with `nvidia-switch.sh cuda`. To remove components the clean way, use
> [`uninstall.sh`](https://github.com/glitchydreamer/arch-hyprland-setup/blob/main/uninstall.sh).
>
> **NVIDIA stack switching** — `nvidia-switch.sh status | downgrade [ver] | latest
> | cuda | purge`. Switches the *whole* NVIDIA stack (driver + userspace)
> atomically, pins the result (`IgnorePkg`), verifies the dkms build, rebuilds the
> UKI, steers the Limine boot default, prunes the cache, and prints a recovery
> note. `cuda` aligns CUDA+cuDNN to the loaded driver. `--dry-run` previews
> everything; read [NVIDIA learn §the fix](learn/05-nvidia.md#the-fix-switch-the-whole-nvidia-stack-to-the-validated-driver).

### 6.5 Audio / DualSense

- PipeWire + WirePlumber.
- DualSense earphone-jack output: a WirePlumber drop-in re-enables ACP
  auto-profile/auto-port so the jack auto-routes; `dualsense-audio` forces it
  manually. (The old `PCM Playback Volume` amixer hack no longer applies — this
  controller is UCM/profile-based. See [troubleshooting §8.1](#81-dualsense-audio-silent-earphones-in-the-controller-jack).)
- DualSense touchpad is disabled as a pointer so it doesn't park a second cursor
  at screen centre (see [§8.7](#87-two-mouse-cursors-one-moving-one-stuck-at-centre)).

### 6.6 GPU / gaming

- NVIDIA driver 595.71 (nvidia-open), 12 GB RTX 3060.
- gamemode + lib32-gamemode (CPU governor boost while gaming).
- mangohud + lib32-mangohud (FPS / GPU overlay — enable per app with env `MANGOHUD=1` or as a Steam launch option).

### 6.7 Multimedia

- mpv (video), haruna (Qt video frontend), easyeffects (PipeWire EQ/effects), pavucontrol (audio mixer), obs-studio (recording/streaming), gimp (raster editor), okular (PDF), gwenview/swayimg (image).

### 6.8 Embedded / robotics CLI

- picocom + minicom (serial terminals — talk to `/dev/ttyUSB0`, etc.)
- arduino-cli
- stlink (STM32 flashing)
- openocd (JTAG/SWD)
- wireshark-qt (network protocol analysis)

### 6.9 Terminal productivity

fish (shell, with caelestia config), starship (prompt), fzf, ripgrep (`rg`), fd, bat, eza, zoxide (`cd` replacement), lazygit (`lg`), gh (GitHub CLI), tmux, tree, jq, yq, **chafa** (terminal image renderer; drives the fastfetch-logo helper — see §6.11).

### 6.10 System monitoring (HWiNFO-equivalent stack)

Installed via `install.sh monitor`. All packages are in the official `extra`
repo — no AUR needed.

| Tool | Role | Launch |
|---|---|---|
| **psensor** | live sensor graphs over time (temps, fans, voltages) — the closest match to HWiNFO's sensor-history window | `psensor` |
| **hardinfo2** | comprehensive hardware inventory + benchmarks + a Sensors tab fed by lm_sensors — the single best HWiNFO analogue | `hardinfo2` |
| **mission-center** | Task-Manager-style GUI: live CPU / GPU / RAM / disk / network utilization + per-process | `Super+Shift+P`, or `missioncenter` |
| **nvtop** | live GPU TUI (NVIDIA / AMD / Intel) — per-process VRAM, utilization, power; the bits `nvidia-smi` can't show | `nvtop` |
| **btop** | modern CLI process / system viewer (replaces htop) — live CPU/RAM/disk/net with mouse support | `btop` |
| **lm_sensors** | kernel sensor framework everything above surfaces (CPU temps, motherboard voltages, chassis fans) | `sensors` |
| **nvidia-settings** | NVIDIA's own GPU control panel (clocks, fans, displays) — installed by the `gpu` component, not `monitor` | `Super+Shift+N`, or `nvidia-settings` |

**One-time `lm_sensors` setup** (only needed if `sensors` shows no chips —
on this box the NCT6798 motherboard chip is already auto-loaded by the
kernel, so no action required):

```bash
sudo sensors-detect --auto    # probes and writes /etc/modules-load.d entries
sudo systemctl restart systemd-modules-load
sensors                       # should now print temps, fans, voltages
```

Notes: **mission-center** in the repo is the stable build (1.1.x); the AUR
`mission-center-git` package **hard-conflicts** with it (they install the same
files). Under `pacman --needed --noconfirm` the conflict is fatal — pacman
refuses to swap and aborts the entire transaction (taking psensor + hardinfo2
down with it). So `do_monitor` queries pacman first and **only adds the repo
mission-center to the package list if neither variant is currently installed**.
Either variant covers Super+Shift+P, so this is a no-op semantically. The
component prints `· mission-center already provided (skipping the repo build
to avoid the AUR git conflict)` when it skips. **nvidia-settings** lives in
the `gpu` component because it ships with the NVIDIA stack and needs to track
the driver.

### 6.11 fastfetch with a custom image / GIF / video logo

caelestia ships fastfetch (`fastfetch-git` from the AUR) and a config at
`~/.config/fastfetch/config.jsonc`. The `fastfetch` component of
`setup-home.sh` installs **`~/.local/bin/fastfetch-logo`**, an interactive
helper for swapping the logo to any image, animated GIF, or video without
hand-editing JSON.

| Command | What it does |
|---|---|
| `fastfetch-logo PATH` | Auto-detect, render the file as a sixel logo. For GIF/video, extracts a static frame at 1 s. |
| `fastfetch-logo --size WxH PATH` | Override chafa render size (default `70x18`). Bigger = sharper but more rows. |
| `fastfetch-logo --frame T PATH` | For GIF/video, extract the frame at T seconds before rendering. |
| `fastfetch-logo --animate PATH` | (GIF/video only) wires a `chafa --animate=on` line into `fish_greeting.fish` to play the clip every time a new shell opens, and clears fastfetch's logo so they don't fight. Pair with `--duration N` (default 3 s). |
| `fastfetch-logo --position top\|left` | Layout. **`top` is the default** because foot wipes sixel pixels on any row where it later prints text — putting the modules below the image (top) dodges the bug. `left` works in kitty/ghostty. |
| `fastfetch-logo --none` | Revert to the OS ASCII logo and undo the fish_greeting animation hook. |
| `fastfetch-logo --info` | Print the current config + sixel state. |

The helper writes the rendered sixel to `~/.config/fastfetch/logo.sixel` and
sets the config's `logo` block to `type: raw` so fastfetch just streams the
bytes. The actual cell footprint in foot is larger than chafa's `--size`
suggests (chafa assumes ~10×20 px cells; foot at JetBrains Mono 12pt is
~8×17), so the helper scales the JSON `width`/`height` up by ~1.2× to leave
room for the modules. See [Learn / fastfetch](learn/12-fastfetch-logo.md) for
the full sizing math + the foot row-clear bug story.

**Quick recipe**:
```bash
bash install.sh terminal media          # ensures chafa + ffmpeg
bash setup-home.sh fastfetch            # interactive: ask for a path
# or, by hand:
fastfetch-logo ~/Pictures/Wallpapers/something.jpg
fastfetch-logo --animate ~/Videos/loop.mp4
fastfetch-logo --none
```

### 6.12 iPad / Android tablet as graphic tablet & touchscreen (Weylus)

Installed via `install.sh tablet`. Uses the maintained community fork
([electronstudio/WeylusCommunityEdition](https://github.com/electronstudio/WeylusCommunityEdition))
shipped as a prebuilt AUR binary — `weylus-community-bin`. Upstream
H-M-H/Weylus has been unmaintained since 2022 and its `weylus` source-build
PKGBUILD **no longer compiles** on current rustc (the transitive
`syntex_pos 0.42` crate uses `RustcEncodable`/`Decodable` derive macros
modern rustc removed).

| Step | Command / file |
|---|---|
| Install | `bash install.sh tablet` — pulls `weylus-community-bin` + `gst-plugin-pipewire`, sets up uinput |
| Same network as your tablet | Desktop and iPad/Android on the same LAN (or hotspot). Weylus serves a webpage, the tablet visits it. |
| Launch | `weylus` (GUI) — set an access code, leave defaults, press **Start** |
| On the tablet | Open the printed URL (`http://<desktop-ip>:1701`) in Safari / Chrome / Firefox. Enter the access code. |
| Pen pressure | Apple Pencil (Safari, iPadOS 13+) and S-Pen / active styli (recent Chromium/Firefox) come through via Pointer Events. Capacitive touch works everywhere. |
| Stop | Close the Weylus GUI, or `pkill weylus`. The TCP/WS ports close with the process. |

**Ports**: 1701 (webserver) and 9001 (WebSocket). Default Arch has no
firewall; if you've enabled `ufw`/`firewalld` later, allow those two for
the LAN side only.

**uinput plumbing** the installer sets up so Weylus can inject pointer
/ stylus events:

- `/etc/udev/rules.d/60-weylus-uinput.rules` — makes `/dev/uinput`
  group-owned by `uinput` mode 0660, and creates a static node so the
  device exists at boot.
- `/etc/modules-load.d/uinput.conf` — autoloads the kernel module.
- Your user added to the `uinput` group. **Requires a fresh login** for
  the group to apply (`groups | grep uinput` to verify).

**Wayland capture** uses `xdg-desktop-portal-hyprland` (already in
caelestia) plus `gst-plugin-pipewire` (installed by this component).
Without `gst-plugin-pipewire` the capture falls back to X11 and you get
a black frame on Hyprland.

**Revert**: `bash uninstall.sh tablet` — removes Weylus, the udev rule,
the modules-load file, the user from the `uinput` group, and the
per-user state in `~/.local/share/weylus`. Leaves `gst-plugin-pipewire`
(shared with audio).

See [Learn / Tablet as drawing pad](learn/13-weylus-tablet.md) for the
full walkthrough — why the community fork, latency tuning, pen pressure
debugging, and the "I see a black screen on the tablet" recipe.

### 6.13 Virtual machines — QEMU/KVM + virt-manager (Gentoo / LFS / any guest OS)

Installed **on demand** via `install.sh vm` (it is *not* part of `all`-by-habit
mandatory apps — run it when you actually want to spin up guests, remove it with
`uninstall.sh vm` to reclaim the disk). The use case is building **Gentoo** and
**Linux From Scratch** in throwaway VMs, but the stack runs anything: Windows,
the BSDs, other distros, cross-arch images.

Everything is pulled from the official `extra` repo, so you always get the
**newest rolling release** — no AUR build is needed for "latest and greatest".

| Package | Why |
|---|---|
| `qemu-full` | The emulator + **all** UI/audio/block/network backends **and every guest architecture** (x86_64 plus ARM/RISC-V/… for cross-arch LFS), not just the host arch. |
| `libvirt` | The management daemon `virt-manager`/`virsh` talk to. |
| `virt-manager` | The GTK management GUI. |
| `virt-viewer` | The SPICE/VNC guest-console window. |
| `edk2-ovmf` | UEFI firmware for guests (modern installers + Secure Boot). |
| `swtpm` | Software TPM 2.0 (Windows 11 guests, measured-boot tests). |
| `dnsmasq` | Backs libvirt's default NAT network (guest DHCP + outbound). |
| `dmidecode` | Lets libvirt read host SMBIOS for guest CPU/board passthrough. |
| `libguestfs` | `virt-resize`, `guestfish`, etc. — inspect/edit guest disk images from the host (handy when crafting LFS/Gentoo images). |

**Works on both kernels with zero extra setup.** KVM acceleration lives *inside*
the kernel — the `kvm` + `kvm_intel`/`kvm_amd` + `vhost` modules ship **in-tree
with every Arch kernel**. There is no DKMS module and no per-kernel rebuild
(unlike the NVIDIA stack), so whether you boot `linux` or `linux-lts`,
`/dev/kvm` is there. The only kernel-touching file the component writes is the
nested-virt modprobe option, which the running kernel reads at module load —
same file, both kernels.

**What `install.sh vm` configures after installing the packages:**

- Adds your user to the **`libvirt`** group (manage the system QEMU instance
  `qemu:///system` without a polkit prompt) and the **`kvm`** group (direct
  `/dev/kvm` access). **Requires a fresh login** to take effect.
- Sets `unix_sock_group = "libvirt"` + `unix_sock_rw_perms = "0770"` in
  `/etc/libvirt/libvirtd.conf` so the `libvirt` group owns the control socket.
- `systemctl enable --now libvirtd.service`.
- Defines (if needed), autostarts, and starts the **default NAT network** so
  guests get DHCP + outbound networking with zero host config.
- Writes `/etc/modprobe.d/kvm-nested.conf` with the right per-vendor option
  (`kvm_intel nested=1` or `kvm_amd nested=1`, auto-detected from the CPU) to
  enable **nested virtualization** (run KVM inside a guest).

| Step | Command / note |
|---|---|
| Install | `bash install.sh vm` |
| Verify HW virt | `LC_ALL=C lscpu \| grep Virtualization` (should show VT-x / AMD-V; if blank, enable it in UEFI/BIOS) |
| Log out / in | once, for the `libvirt` + `kvm` groups to apply |
| Launch | `virt-manager` (auto-connects to `qemu:///system`) |
| Check nested | `cat /sys/module/kvm_intel/parameters/nested` → `Y` (or `kvm_amd`) |

**Revert / reclaim disk**: `bash uninstall.sh vm` — stops the daemon + default
network, removes the whole stack, and **deletes all guest disk images in every
storage pool** — not just the default `/var/lib/libvirt` one but also any
**custom pool you created on `/home`** (e.g. a `gentoo` pool). Before stopping the
daemon it asks libvirt for every volume in every pool and removes only genuine VM
disk images (`.qcow2`/`.raw`/`.img`/`.qed`/`.vmdk`/…), each as an individual file —
so even if you **forget to tick "Delete associated storage" in virt-manager**, the
orphaned disk on `/home` is still reclaimed. It deliberately **leaves your ISOs and
any other files untouched** (a directory-type pool lists those as "volumes" too, but
they're yours, not the script's) and prints their paths so you can delete them by
hand if you want the space. It also removes `/etc/libvirt` (pool definitions live
here), the per-user virt-manager state, the nested-virt drop-in, and drops the
`libvirt`/`kvm` group memberships. KVM kernel modules are in-tree, so there's
nothing to uninstall there.

See [Learn / Virtual machines](learn/14-virtual-machines.md) for the full
walkthrough — KVM vs emulation, why virt-manager over plain QEMU, a first
Gentoo/LFS guest, performance tuning (virtio, hugepages, CPU pinning), and
nested virt.

### 6.14 System health & rolling-release self-repair (the `health` component + auto-heal)

`install.sh` is **rolling-release self-healing**. Every run — for *any* component —
the mandatory prereq step does more than a plain upgrade:

1. **Keyring first.** `archlinux-keyring` is pulled at the front of the `-Syu`, so a
   long gap between updates can't fail the whole transaction on an expired signing key.
2. **Kernel headers in lockstep.** It detects every installed kernel via
   `/usr/lib/modules/*/pkgbase` and folds each one's matching `-headers`
   (`linux-headers`, `linux-lts-headers`, …) **into the same `-Syu`**. So when a kernel
   rolls forward its headers roll with it, and the DKMS module (NVIDIA) builds against
   the right version in one transaction — closing the **"new kernel booted with no GPU
   driver"** trap. Only real repo targets are added, so a custom/AUR kernel can't abort
   the upgrade with "target not found".
3. **Always a full `-Syu`**, never `-Sy` (partial upgrades are the #1 way to break Arch).
4. **Post-upgrade DKMS + initramfs self-heal.** Runs `dkms autoinstall` for every
   kernel that has headers, regenerates the initramfs/UKI with `mkinitcpio -P` if the
   module set changed, then **verifies** each kernel has its module. If one genuinely
   can't be built (the pinned 580 driver being too old for a brand-new kernel API), it
   prints the concrete options — boot the kernel that *is* built, `nvidia-switch.sh
   latest`, or remove the unused kernel — instead of leaving a silent landmine.

Because this lives in the always-run prereqs, **re-running `install.sh` repairs a
botched upgrade.** The exact state this box was left in (mainline `linux` updated
without `linux-headers`, so its UKI had no NVIDIA) is fixed simply by running the
script again: the next run installs the headers, rebuilds NVIDIA for that kernel, and
regenerates its boot image.

For a one-shot doctor with **no app install**:

```bash
bash install.sh health
```

The `health` component does the same kernel/headers/DKMS auto-repair, then prints a
read-only report:

| Report section | What it shows |
|---|---|
| Kernels ↔ headers ↔ DKMS | per-kernel: headers present? DKMS module built? |
| Orphaned packages | `pacman -Qtdq` — installed-as-dep, now needed by nothing (review, not auto-removed) |
| Failed systemd units | `systemctl --failed` |
| Pending `.pacnew` | config files needing a merge (`pacdiff`, from pacman-contrib) |
| Held-back pins | the active `IgnorePkg` lines (PipeWire 1.6.5, NVIDIA 580) so you remember what's frozen on purpose |

Only the auto-repair changes anything; the report half is pure inspection. Under
`--dry-run`, even the repair is simulated. See
[Learn / System maintenance](learn/11-system-maintenance.md) for the full mental model
of rolling upgrades, pinning, and DKMS-vs-kernel risk.

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

### 7.4 Serial / microcontroller

```bash
picocom -b 115200 /dev/ttyUSB0     # serial term at 115200 baud (Ctrl-A Ctrl-X to quit)
minicom -D /dev/ttyACM0 -b 115200  # alternative
arduino-cli board list             # find connected boards
arduino-cli compile --fqbn FQBN sketch.ino
arduino-cli upload   --fqbn FQBN -p /dev/ttyUSB0 sketch.ino
st-info --probe                    # STM32 board info
st-flash write fw.bin 0x8000000    # flash STM32
```

### 7.5 Git (your defaults)

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

#### PipeWire 1.6.6 regression — DualSense audio silent

Distinct from the routing issue above. **The 1.6.6 audio-stack bump broke DualSense
USB audio**: first the built-in speaker *and* the 3.5mm jack went silent, then —
after pinning only the `pipewire*` packages — the **speaker came back but the jack
stayed silent**. Everything looks correct throughout (sink `RUNNING`, jack
`available`, unmuted, default). Proof it's not routing:
`cat /proc/asound/card<N>/pcm0p/sub0/status` shows `state: RUNNING` with `hw_ptr`
advancing — the kernel delivers 4-channel frames, nothing sounds.

What 1.6.6 broke, and what it did **not**:

- **Speaker — software, fixed.** PipeWire 1.6.6 (`pipewire` + `libpipewire`,
  `pipewire-{audio,alsa,pulse,jack}`, `gst-plugin-pipewire`) killed the controller's
  built-in **speaker**. Pinning back to **1.6.5** restores it. `alsa-card-profiles`
  is the ACP channel/profile data, versioned in lockstep (`1:1.6.x`) but *not*
  named `pipewire*`; pin it alongside the rest for version-consistency.
- **3.5mm jack — NOT a software/version issue (controller-side fault).** The jack
  stayed silent on 1.6.5 too. Proven not to be PipeWire/routing: with the earphones
  confirmed working on a phone and the speaker working, a raw
  `speaker-test -D plughw:<card>,0 -c 4` driving **all four DAC channels directly**
  (bypassing PipeWire) produced **no sound in the earphones on any channel**. So the
  controller's headphone output stage isn't emitting analog — a controller
  firmware/hardware fault, not something the OS can fix. Try: the DualSense
  **hardware reset** (pinhole on the back, hold ~5s with a pin), then test the jack
  on another host (PS5 / another PC). If silent there too, the controller needs
  repair/replacement.

Fix for the **speaker** regression: pin the audio stack back to **1.6.5**.
`install.sh` does this automatically via `pin_pipewire_dualsense()` — self-limiting
(only acts when the installed pipewire is in the known-bad range), downgrades the
set from the pacman cache, and adds an `IgnorePkg` line so `pacman -Syu` won't
re-pull the breakage. Lift the pin (delete the `IgnorePkg` line in
`/etc/pacman.conf` and drop the call) once a fixed build ships. Manual one-off:

```bash
sudo pacman -U /var/cache/pacman/pkg/{libpipewire,pipewire,pipewire-audio,pipewire-alsa,pipewire-pulse,pipewire-jack,gst-plugin-pipewire,alsa-card-profiles}-1:1.6.5-*.pkg.tar.zst
systemctl --user restart pipewire pipewire-pulse wireplumber
```

> The DualSense re-enumerates with a **different ALSA card index** across reboots
> (it was card 2, became card 0) — don't hard-code `card<N>`; resolve it from
> `pactl list cards short | grep -i sony` each time.

### 8.2 Hyprland config change broke things

Hyprland keeps a log at `~/.local/share/hyprland/hyprland.log` (or run `hyprctl logs`). If a bad keybind crashes reload, edit `~/.config/caelestia/hypr-user.conf` from a TTY (Ctrl+Alt+F2) and re-launch.

### 8.3 Need to talk to /dev/ttyUSB0 but get permission denied

You should be in the `uucp` group (Arch's convention for serial devices). Check with `groups`. If missing:

```bash
sudo usermod -aG uucp,lock $USER
# Then log out and back in.
```

### 8.4 Wireshark says "you need to be in wireshark group"

```bash
sudo usermod -aG wireshark $USER
newgrp wireshark      # apply to current shell, or just log out/in
```

### 8.5 HDR looks washed out / colors wrong

Try in order:

1. Bump `sdrbrightness, 1.8` (or `2.0`) in the monitor line, reload.
2. Swap `cm, hdr` → `cm, hdredid` (let monitor declare its own HDR metadata).
3. If still bad, just toggle off with `Super + Ctrl + Alt + H` and only enable HDR for mpv / gamescope sessions.

### 8.6 Gazebo natively (gz-harmonic) won't build

The AUR `gz-harmonic` package currently fails on gcc 16 because of `ogre-next2`, `fcl`, `libccd`, `octomap`. Re-check in a few months once AUR maintainers patch.

### 8.7 Two mouse cursors (one moving, one stuck at centre)

There are **two independent causes**, and the persistent one is the NVIDIA
renderer. Both fixes are baked into the rebuild scripts, so a clean install
needs no manual tweaking.

#### Cause 1 (the real culprit): NVIDIA software-cursor artifact

A cursor frozen at screen centre that survives reboots, unplugging the
controller, and disabling every input device is **not an input device at all** —
it's a stale software cursor the NVIDIA driver leaves behind. The fix is a CPU
cursor buffer **with hardware cursors enabled**. Counter-intuitively, forcing
`no_hardware_cursors = true` *causes* this on recent drivers, so it's explicitly
off. In `~/.config/caelestia/hypr-user.conf` (written by `setup-home.sh`):

```ini
cursor {
    no_hardware_cursors = false
    use_cpu_buffer = true
}
```

Verify live: `hyprctl getoption cursor:use_cpu_buffer` → `int: 1`. Test combos
without editing files:

```bash
hyprctl keyword cursor:no_hardware_cursors 0
hyprctl keyword cursor:use_cpu_buffer 1
hyprctl setcursor sweet-cursors 24      # nudge a re-render, then move the mouse
```

#### Cause 2 (secondary): the DualSense touchpad as a pointer

When the controller is plugged in, its **touchpad** also registers as an
absolute pointer that can sit at centre. Confirm: `hyprctl devices | grep -i touchpad`.
The authoritative fix is a libinput udev rule (`install.sh`); the Hyprland
device block is a secondary layer.

```
/etc/udev/rules.d/71-dualsense-touchpad-ignore.rules
SUBSYSTEM=="input", ATTRS{name}=="Sony Interactive Entertainment DualSense Wireless Controller Touchpad", ENV{LIBINPUT_IGNORE_DEVICE}="1"
```
Apply: `sudo udevadm control --reload-rules && sudo udevadm trigger`, **then
unplug/replug the controller (or reboot)** — the rule (like Hyprland's
`device{enabled=false}`) only takes effect when the device *re-attaches*; a
plain `hyprctl reload` won't drop an already-connected controller. Only the
pointer role is ignored — the gamepad still works in games.

> Writing this file from **fish** (no heredocs): use a one-shot script
> (`sudo bash script.sh`) or `printf '…\n' | sudo tee <path>` on a single
> unwrapped line. `sudo tee <path> <<'EOF'` is a bash-ism and won't parse.

Separately, `hypr-user.conf` also keeps `cursor { no_hardware_cursors = true }`.
That addresses a *different* NVIDIA-Wayland class of stale-cursor bug (the GPU
leaving a stale image on the hardware cursor plane) and is harmless to keep on.
Verify: `hyprctl getoption cursor:no_hardware_cursors` → `int: 1`. GDM's own
login-screen cursor is unrelated.

### 8.8 Isaac Sim ↔ ROS 2 bridge: crashes or silent topics

The container is **`ros2-humble`** on purpose. Two distinct failure modes, both
already handled by the launcher:

**(a) Isaac Sim *crashes* when the container runs `ros2 topic list`.**
The Omniverse crash log backtrace ends in `cdr_deserialize(... ParticipantEntitiesInfo
...)` → `vector<NodeEntitiesInfo>::resize(<huge>)` → `operator new` → `abort`, inside
`libfastrtps.so.2.6`. Cause: a **cross-distro DDS mismatch.** Isaac's *bundled* ROS 2
bridge is **Humble** (Fast DDS 2.6); a **Jazzy** container (Fast DDS 2.14) encodes the
`ros_discovery_info` graph message (`rmw_dds_common`) with a different CDR layout (XCDR
v2 vs v1), so Isaac's discovery listener reads a bogus vector length and aborts. **Fix:
match the distro** — use `osrf/ros:humble-desktop-full` (the `ros2-humble` launcher),
not Jazzy. Tell-tale: the version in the backtrace (`.so.2.6` = Humble).

**(b) `ros2 topic echo` / `hz` show a publisher but *zero data*.**
Fast DDS *discovery* rides UDP (fine across `--network host`), but its default *data*
transport is **shared memory** — and native Isaac (UID 1000) and the root container
can't share `/dev/shm` segments, so every sample is silently dropped. **Fix: force
UDP-only.** On Humble's Fast DDS 2.6 there is **no `FASTDDS_BUILTIN_TRANSPORTS` env var**
(that arrived in 2.10/Iron), so the launcher mounts a Fast DDS XML profile and points
`FASTRTPS_DEFAULT_PROFILES_FILE` at it:

```xml title="~/.config/ros2/fastdds-udp-only.xml"
<dds xmlns="http://www.eprosima.com/XMLSchemas/fastRTPS_Profiles">
  <profiles>
    <transport_descriptors>
      <transport_descriptor>
        <transport_id>udp_only</transport_id>
        <type>UDPv4</type>
      </transport_descriptor>
    </transport_descriptors>
    <participant profile_name="udp_only_participant" is_default_profile="true">
      <rtps>
        <userTransports><transport_id>udp_only</transport_id></userTransports>
        <useBuiltinTransports>false</useBuiltinTransports>
      </rtps>
    </participant>
  </profiles>
</dds>
```

Verify the bridge end-to-end: play the sim, then `ros2-humble shell` →
`ros2 topic list` (Isaac topics appear) → `ros2 topic hz /isaac_joint_states`
(~60 Hz). If `topic list` is empty, check `ROS_DOMAIN_ID` matches and Isaac's
`isaacsim.ros2.bridge` extension is enabled.

---

## 9. Remote access, drives & disk tools

Set up by the `storage` + `remote` components of `install.sh` (plus the
`vnc-server` helper from `setup-home.sh`'s `scripts`).

### 9.1 Spotlight-style launcher
caelestia already ships one: **tap `Super`** (press & release the Super key alone)
to open the launcher/search. No extra app needed.

### 9.2 Mounting Windows / external drives in nautilus
Arch (unlike Ubuntu) doesn't ship the NTFS/exFAT userspace drivers, so clicking an
NTFS SSD in nautilus silently fails. Fix:
```bash
bash install.sh storage      # ntfs-3g + exfatprogs + gnome-disk-utility
```
After that, internal Windows drives mount on click (udisks2 handles it). A LUKS-
encrypted partition will prompt for its passphrase instead.

!!! warning "\"wrong fs type, bad superblock\" on a Windows drive = the dirty flag"
    If a drive *still* won't mount with an error like *"wrong fs type, bad option,
    bad superblock … missing codepage or helper program"*, the NTFS volume is
    **dirty** — Windows left it "in use" (almost always **Fast Startup** /
    hibernation). udisks now uses the **kernel `ntfs3`** driver, which *refuses* to
    mount a dirty volume RW; the kernel log shows `ntfs3(...): volume is dirty and
    "force" flag is not set!`. (Ubuntu "just worked" because it used the lenient
    **ntfs-3g** userspace driver instead.) Two fixes:

    - **Immediate** — clear the flag (Windows must be **fully powered off**, since
      it discards any unsaved cached writes), then click the drive again:
      ```bash
      sudo ntfsfix /dev/nvme0n1p4      # one device per call
      ```
    - **Permanent (recommended)** — in Windows disable **Fast Startup** (Power
      Options → *Choose what the power buttons do* → uncheck *Turn on fast
      startup*) and always do a full shutdown. The volume then stays clean and
      mounts on click every time.

    Alternative (never touch Windows): add an `/etc/fstab` entry for the drive's
    UUID with type `ntfs-3g` + `nofail,noauto,x-gvfs-show` so nautilus always uses
    the lenient driver — survives the dirty flag, like Ubuntu did.

### 9.3 Disk free space / partitions (Ubuntu "Disks" equivalent)
- GUI: **`gnome-disks`** (gnome-disk-utility) — partitions, free space, SMART.
- GUI usage map: **`filelight`** (already installed).
- CLI: `df -h` (free space per mount), `lsblk -f` (devices + filesystems).
- Benchmark (CrystalDiskMark equivalent): **`kdiskmark`** — Qt6 GUI for
  sequential / random read+write throughput and IOPS, drives `fio` under the
  hood. Installed by the `storage` component alongside the Disks app.
  gnome-disks also has its own *Benchmark* dialog in the menu if you want a
  quick read-only sweep without leaving the partition view.

### 9.4 SSH (both directions) — on demand
`openssh` is installed by `bash install.sh remote`, but **`sshd` is left OFF by
default**: an idle sshd costs almost nothing, but keeping it off shrinks the attack
surface. Flip it per session with the **`remote`** helper:
```bash
remote on        # start sshd (accept logins) + print this box's IP
remote off       # stop sshd + stop any running wayvnc
remote status    # what's active + LAN IP + listening :22/:5900
```
Then connect:
```bash
ssh <user>@<this-ip>          # from another PC, into Arch
ssh <user>@<other-host>       # from Arch, out to another box (always works)
```
Want it reachable at every boot instead of toggling? `sudo systemctl enable --now
sshd`.

### 9.5 Remote desktop
- **Out of Arch → Windows/others (RDP/VNC):** `remmina` (GUI) or
  `xfreerdp /v:<host> /u:<user>`.
- **Into Arch (VNC):** RDP into a live Hyprland/Wayland session isn't supported, so
  use **VNC via `wayvnc`**, started with the helper:
  ```bash
  vnc-server                  # localhost only (secure) — reach via SSH tunnel
  vnc-server --lan            # expose on the LAN (trusted networks only)
  vnc-server DP-1             # share a specific monitor
  ```
  Secure pattern (default localhost), from the client:
  ```bash
  ssh -L 5900:localhost:5900 <user>@<this-ip>   # then point a VNC viewer at localhost:5900
  ```
  Windows viewers: TigerVNC / RealVNC. Linux: remmina / vinagre.

  `wayvnc` only runs while `vnc-server` is open (no idle cost); close that terminal
  or run `remote off` to stop it.

---

## 10. Useful URLs

- Hyprland wiki: <https://wiki.hyprland.org/>
- Hyprland dispatchers: <https://wiki.hyprland.org/Configuring/Dispatchers/>
- Hyprland monitor config (HDR): <https://wiki.hyprland.org/Configuring/Monitors/>
- Caelestia dotfiles: <https://github.com/caelestia-dots/shell>
- Arch wiki Hyprland: <https://wiki.archlinux.org/title/Hyprland>
- DualSense Linux info: <https://www.kernel.org/doc/html/latest/hid/hid-playstation.html>

---

## 11. Where things came from

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
added (`cursor { no_hardware_cursors = true }` — see §8.7). Update or delete
this file freely — it's yours.
