# CachyOS — project context (read me first)

A single-page map of the **CachyOS** build of this Hyprland + caelestia
workstation. It mirrors the [Arch build](../arch/project-context.md); this page
focuses on **what's the same** and **what's different**. The shared learning
material lives under [Common](../common/index.md).

## What this is

Personal **CachyOS** + Hyprland (**caelestia** dotfiles) workstation. CachyOS is a
performance-tuned Arch derivative (`ID_LIKE=arch`) — pacman, the AUR, and caelestia
all work exactly as on Arch, plus the `cachyos-*` repositories and optimized
kernels. This directory (`cachyos/` in the repo) holds the **reproducibility
scripts**; the live config lives in the home directory.

- **GPU:** NVIDIA RTX 3060 (desktop), LG 34" ultrawide on **DP-1**. Wayland session.
- **Kernel:** booted on **`linux-cachyos-lts`** (6.18); `linux-cachyos` (7.0) also
  installed as the rolling kernel.
- **Bootloader:** **Limine**, managed by `limine-entry-tool` + `limine-mkinitcpio-hook`
  (auto-generated entries, ESP `/boot`, UKI off).
- **AUR helper:** **paru** (ships with CachyOS).

## Differences from the Arch build (the only three that matter)

| Area | Arch build | CachyOS build |
|---|---|---|
| **DualSense** | speaker pin (PipeWire 1.6.5) + touchpad udev rule + WirePlumber drop-in + `dualsense-audio` helper | **none** — stock PipeWire drives the controller correctly, so all of it is dropped |
| **Duplicate cursor** | `cursor { no_hardware_cursors = false; use_cpu_buffer = true }` | **VRR off** — `misc { vrr = 0 }` in the override kills the ghost cursor (the user's discovery) |
| **NVIDIA driver mgmt** | DKMS/prebuilt `nvidia-open` + Arch Linux Archive + UKI/Limine manual entry | **prebuilt per-kernel** `linux-cachyos*-nvidia-open`; the 580 switcher swaps to `nvidia-open-dkms` (ALA) + steers Limine `default_entry`. See [NVIDIA](nvidia.md). |

Everything else — the caelestia override files, the monitor auto-detection, the
Sweet icon theme, the `~/.local/bin` helpers, CUDA/Anaconda/LeRobot, Docker + ROS 2
Humble + MoveIt 2 Humble, QEMU/KVM, the HWiNFO-style monitoring stack, etc. — is
**carried over verbatim** (full parity).

## The rebuild

```sh
bash cachyos/setup-home.sh   # 1. home-dir configs, NO sudo, auto-detects the display
bash cachyos/install.sh      # 2. packages + system, calls sudo itself
gh auth login && git push    # 3. the only step that can't be scripted
```

All four scripts (`setup-home.sh`, `install.sh`, `uninstall.sh`,
`nvidia-switch.sh`) are interactive + component-based and share one shape: no args
for a numbered menu, or pass component names, `all`, `--yes`, `--dry-run`. They are
idempotent and `FAILED=()`-tracked. This is identical to the Arch shape — see
[Reproducibility](../common/reproducibility.md) for the model.

### Key CachyOS-specific behaviours baked into the scripts

- **`install.sh` prereqs** refresh **both** keyrings (`archlinux-keyring` +
  `cachyos-keyring`) and fold each installed kernel's `-headers`
  (`linux-cachyos-headers`, `linux-cachyos-lts-headers`) into the same `-Syu`.
- **DKMS self-heal** is a no-op under the default prebuilt modules (it detects
  "no DKMS modules registered") and only becomes active after `nvidia-switch.sh`
  swaps in `nvidia-open-dkms`. The `health` doctor reports each kernel's module as
  *prebuilt nvidia-open* or *dkms nvidia*.
- **`setup-home.sh hyprland`** writes `misc { vrr = 0 }` into
  `~/.config/caelestia/hypr-user.conf` (sourced last, wins globally) and reverts any
  hand-edit of caelestia's base `hypr/hyprland/misc.conf` so the dotfiles tree stays
  clean for `git pull`.

## File map (live system)

| Thing | Path |
|---|---|
| caelestia upstream (never edit) | `~/.local/share/caelestia/` (and `~/.config/hypr` → symlink into it) |
| User Hyprland overrides | `~/.config/caelestia/hypr-user.conf`, `hypr-vars.conf` |
| caelestia shell settings | `~/.config/caelestia/shell.json` |
| Per-host monitors + active symlink | `~/.config/caelestia/hypr-monitors-{desktop,laptop}.conf`, `hypr-monitors.conf` |
| Scripts | `~/.local/bin/{select-monitors.sh, hdr-toggle, ros2-humble, moveit2-humble, vnc-server, remote, lerobot-verify, fastfetch-logo}` |
| Fish additions | `~/.config/fish/conf.d/dev-env.fish` |
| CUDA PATH | `/etc/profile.d/cuda.sh` (+ fish via `dev-env.fish`) |
| NVIDIA pin (after a downgrade) | `IgnorePkg` block in `/etc/pacman.conf` |
| Limine config | `/boot/limine.conf` (root-only; `default_entry` steered by `nvidia-switch.sh`) |

## Decisions worth remembering

- **VRR=0 fixes the duplicate cursor here.** Discovered by accident editing
  `misc.conf`; made reproducible via the override so caelestia upgrades don't undo
  or conflict with it. The monitor lines also carry `vrr, 0`.
- **No DualSense work needed.** CachyOS's stock PipeWire plays the controller's
  speaker and 3.5mm jack out of the box — the Arch box's whole DualSense saga does
  not reproduce here.
- **NVIDIA is prebuilt, not DKMS, by default.** A driver downgrade therefore
  *changes the delivery model* (prebuilt → dkms), which is why the switcher removes
  the `linux-cachyos*-nvidia-open` packages and installs `nvidia-open-dkms`. See
  [NVIDIA](nvidia.md).
- **Already on an LTS kernel.** Unlike the Arch box (which had to install
  `linux-lts` for the 580 build), CachyOS already runs `linux-cachyos-lts` 6.18 —
  which 580.105.08+ compiles against — so a downgrade drags in **no second kernel**.
