# Full reference (CachyOS)

The CachyOS build is **full parity** with the Arch build minus the DualSense
workarounds, so the exhaustive component-by-component reference — installed
software, the script component lists, HDR, Docker/ROS 2, LeRobot, VMs,
troubleshooting recipes — is shared. Use the
[**Arch full reference**](../arch/reference.md) as the manual; substitute the
CachyOS names below where they differ.

This page is the **CachyOS delta sheet**.

## System facts

| Thing | Value |
|---|---|
| Distro | CachyOS (`ID_LIKE=arch`) |
| Kernels | `linux-cachyos` (rolling) + `linux-cachyos-lts` (**booted**) |
| Bootloader | Limine (`limine-entry-tool` + `limine-mkinitcpio-hook`, ESP `/boot`, UKI off) |
| AUR helper | paru |
| GPU | NVIDIA RTX 3060, driver 610 (prebuilt module), LG ultrawide on DP-1 |
| Audio | PipeWire (stock — no DualSense workaround) |

## What's removed vs the Arch reference

These Arch sections **do not apply** on CachyOS:

- **DualSense audio fix** (§8.1) — stock PipeWire works; no 1.6.5 pin, no
  `dualsense-audio` helper, no WirePlumber drop-in.
- **DualSense touchpad / ghost-cursor udev rule** — not needed.
- The **two-cursor** fix (§8.7) is replaced by **`misc { vrr = 0 }`** in the
  override (see [Display](display.md)).

## What's changed vs the Arch reference

| Arch reference says | On CachyOS |
|---|---|
| `linux` / `linux-lts` kernels | `linux-cachyos` / `linux-cachyos-lts` |
| `nvidia-open` / DKMS, Arch Linux Archive, UKI + manual Limine entry | prebuilt `linux-cachyos*-nvidia-open`; `nvidia-switch.sh` swaps to `nvidia-open-dkms` (ALA) + steers `default_entry`. See [NVIDIA](nvidia.md). |
| `archlinux-keyring` | also `cachyos-keyring` |
| yay bootstrap | paru (preinstalled) |
| `audio` component installs the DualSense fix | `audio` installs apps only (`pavucontrol easyeffects alsa-utils`) |

## Scripts (this directory)

```sh
bash cachyos/setup-home.sh [all|<component>...] [--dry-run] [--yes]
bash cachyos/install.sh    [all|<component>...] [--dry-run] [--yes]
bash cachyos/uninstall.sh  [all|<component>...] [--dry-run] [--yes]
bash cachyos/nvidia-switch.sh [status|downgrade [ver]|latest|cuda|purge] [--dry-run] [--yes]
```

- **`setup-home.sh` components:** `hyprland` (incl. the `vrr=0` override),
  `caelestia` (°C), `nautilus`, `scripts`, `fastfetch`, `fish`, `git`, `lerobot`.
  (No `wireplumber` component.)
- **`install.sh` components:** `health`, `build`, `cuda`, `python`, `anaconda`,
  `node`, `editors`, `embedded`, `audio` (apps only), `gpu`, `docker`, `vm`,
  `media`, `terminal`, `kde`, `display`, `monitor`, `storage`, `remote`, `tablet`,
  `theme`, `aurapps`, `groups`, `shell`.
- **`uninstall.sh` / `nvidia-switch.sh`:** same component/action sets as Arch, with
  the CachyOS package names.

For everything else (the exact package lists per component, the Docker data-root +
CDI setup, the ROS 2 Humble launcher and Fast DDS UDP profile, the LeRobot conda
env + cmake-4 hook, the QEMU/KVM stack, the HWiNFO-style monitoring tools, the
fastfetch-logo helper) the [Arch reference](../arch/reference.md) is authoritative —
the commands and package names are identical except where this delta sheet says
otherwise.
