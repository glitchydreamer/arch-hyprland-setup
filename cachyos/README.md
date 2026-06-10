# cachyos/ — CachyOS build

The **CachyOS** build of this Hyprland + caelestia workstation — **full parity**
with the [Arch build](../arch/README.md) minus the DualSense workarounds. Part of
the [`hyprland-rice`](../README.md) master repo.

**📖 Docs:** [CachyOS section](https://glitchydreamer.github.io/hyprland-rice/cachyos/project-context/)
· [shared learning core](https://glitchydreamer.github.io/hyprland-rice/common/)

## Scripts

```sh
bash cachyos/setup-home.sh      # 1. home-dir configs (no sudo)
bash cachyos/install.sh         # 2. system half (calls sudo itself)
bash cachyos/uninstall.sh       # clean, component-based uninstaller
bash cachyos/nvidia-switch.sh   # switch the NVIDIA stack (latest ⇄ 580 for Isaac) / purge
```

All four are interactive + component-based and share one shape: no args for a
numbered menu, or pass component names, `all`, `--yes`, `--dry-run`. Idempotent.

## What's different from the Arch build

| Area | Here on CachyOS |
|---|---|
| **DualSense** | none — stock PipeWire handles the controller; all Arch DualSense work dropped |
| **Duplicate cursor** | fixed by **VRR off** (`misc { vrr = 0 }` in the override), not the CPU-cursor-buffer trick |
| **NVIDIA** | prebuilt per-kernel `linux-cachyos*-nvidia-open`; the 580 switcher swaps to `nvidia-open-dkms` (ALA) + steers Limine `default_entry` |
| **Keyrings** | needs `archlinux-keyring` **and** `cachyos-keyring` |
| **AUR helper** | paru (preinstalled) |
| **Kernels** | `linux-cachyos` / `linux-cachyos-lts` (already on lts — no second kernel for the 580 build) |

Everything else (caelestia overrides, Sweet icons, `~/.local/bin` helpers,
CUDA/Anaconda/LeRobot, Docker + ROS 2 Humble, QEMU/KVM, monitoring stack) is carried
over verbatim.

See [docs/cachyos/project-context.md](../docs/cachyos/project-context.md) for the
full map and [docs/cachyos/nvidia.md](../docs/cachyos/nvidia.md) for the driver
switcher details.
