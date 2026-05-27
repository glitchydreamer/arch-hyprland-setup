# Project context (read me first)

A single-page map of *what this project is*, so anyone (or any AI assistant)
can pick it up cold. Details live in the other pages; this is the index of
intent and decisions.

## What this is

Personal Arch Linux + Hyprland (**caelestia** dotfiles) workstation setup. This
repo is **documentation + reproducibility scripts** — it is **not** the dotfiles
themselves. The live config lives in the home directory; the repo describes it
and can regenerate it.

- **Display manager:** GDM (was SDDM on the first install).
- **GPU:** NVIDIA (RTX 3060 on the desktop). Wayland session.
- **Roaming NVMe:** the same SSD boots two machines — a **desktop** (RTX 3060,
  LG 34" ultrawide, currently on **DP-1**) and a **laptop** (Intel + RTX 4070
  Mobile, internal panel on **eDP-1**). Configs must work on both; per-host
  switching is automatic.
- **User workflow:** robotics / ML dev (CUDA, ROS 2, embedded serial),
  terminal-first, fish shell, came from Ubuntu/GNOME.

## The two-script rebuild

A clean `archinstall` + NVIDIA drivers + caelestia, then:

```sh
bash setup-home.sh   # 1. home-dir configs, NO sudo, auto-detects the display
bash install.sh      # 2. packages + system, calls sudo itself
gh auth login && git push   # 3. the only step that can't be scripted
```

Both are **idempotent**. After them: set `git config --global user.name`, then
log out/in (fish shell + group changes need a fresh session).

- `setup-home.sh` — generates Hyprland overrides, `~/.local/bin` scripts, fish
  `dev-env.fish`, Dolphin config, WirePlumber DualSense drop-in, git defaults.
  It is the **source of truth** for those files; edit the script, re-run it.
- `install.sh` — bootstraps git/`gh`/AUR-helper first, then installs the dev
  stack, **driver-matched CUDA** + cuDNN, Docker + NVIDIA runtime, gaming/media,
  KDE settings apps, sweet-cursors, the DualSense touchpad udev rule; enables
  docker, adds groups, switches the login shell to fish.

## File map (live system, not the repo)

| Thing | Path |
|---|---|
| caelestia upstream (never edit) | `~/.local/share/caelestia/` (and `~/.config/hypr` → symlink into it) |
| User Hyprland overrides | `~/.config/caelestia/hypr-user.conf`, `hypr-vars.conf` |
| Per-host monitors + active symlink | `~/.config/caelestia/hypr-monitors-{desktop,laptop}.conf`, `hypr-monitors.conf` |
| Scripts | `~/.local/bin/{select-monitors.sh, hdr-toggle, ros2-jazzy, dualsense-audio}` |
| Fish additions | `~/.config/fish/conf.d/dev-env.fish` |
| WirePlumber DualSense | `~/.config/wireplumber/wireplumber.conf.d/51-dualsense-headphones.conf` |
| DualSense touchpad ignore | `/etc/udev/rules.d/71-dualsense-touchpad-ignore.rules` |
| CUDA PATH | `/etc/profile.d/cuda.sh` (+ fish via `dev-env.fish`) |

## Decisions & root causes worth remembering

- **Connector is detected, not hardcoded.** First install used DP-2; this one
  is DP-1. `setup-home.sh` writes the desktop monitor file and `hdr-toggle`
  works off whatever the first non-eDP output is.
- **Two-cursor bug = DualSense touchpad**, not (mainly) the NVIDIA HW cursor.
  The controller's touchpad is an absolute pointer that parks a cursor at
  centre. Fixed by disabling it (Hyprland `device{enabled=false}` + a libinput
  `LIBINPUT_IGNORE_DEVICE` udev rule). `no_hardware_cursors=true` is kept for a
  separate NVIDIA stale-cursor class but was not the cause. → [§8.8](index.md#88-two-mouse-cursors-one-moving-one-stuck-at-centre)
- **DualSense audio = profile routing**, not the old `PCM Playback Volume`
  amixer hack (this UCM card has no mixer controls). Speaker vs the 3.5mm jack
  are separate PipeWire *profiles*; auto-switching ships disabled. Fixed with a
  WirePlumber drop-in (re-enable auto) + a `dualsense-audio` helper. → [§8.1](index.md#81-dualsense-audio-silent-earphones-in-the-controller-jack)
- **CUDA is matched to the driver.** `install.sh` reads `nvidia-smi`'s max CUDA
  and only installs the rolling repo `cuda` if it fits, else an AUR `cuda-<ver>`.
- **VRR on the desktop:** `vrr, 0` on the monitor line (locked 160 Hz). NVIDIA
  reports `vrr=true` regardless — that's a capability readout, not the setting.
- **Half-screen snaps omitted:** `Super+Ctrl+arrows` is caelestia's workspace
  nav; a float-based snap is unreliable on dwindle.

## Git identity

Commits use **`glitchydreamer <creativegod0307@gmail.com>`** (the GitHub
account), *not* the Claude-context account email. Remote is HTTPS; pushing
needs `gh auth login` (or SSH/PAT) — a fresh install has no credentials.

## History

- **2026-05-17** — original setup (SDDM, DP-2).
- **2026-05-27** — full rebuild on a clean minimal install (GDM, DP-1):
  scripted into `setup-home.sh` + `install.sh`; fixed the DualSense cursor and
  audio after discovering the first round's diagnoses were the wrong root cause.
