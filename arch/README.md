# arch/ — Arch Linux build

The original build of this Hyprland + caelestia workstation, on **Arch Linux**.
Part of the [`hyprland-rice`](../README.md) master repo.

**📖 Docs:** [Arch section](https://glitchydreamer.github.io/hyprland-rice/arch/project-context/)
· [shared learning core](https://glitchydreamer.github.io/hyprland-rice/common/)

## Scripts

```sh
bash arch/setup-home.sh      # 1. home-dir configs (no sudo)
bash arch/install.sh         # 2. system half (calls sudo itself)
bash arch/uninstall.sh       # clean, component-based uninstaller
bash arch/nvidia-switch.sh   # switch the NVIDIA stack (latest ⇄ 580 for Isaac) / purge
```

All four are interactive + component-based and share one shape: no args for a
numbered menu, or pass component names, `all`, `--yes`, `--dry-run`. Idempotent.

## What's specific to this build

- NVIDIA via DKMS/prebuilt `nvidia-open`, sourced from the **Arch Linux Archive**
  for the 580 downgrade; **UKI + Limine** manual boot entry for `linux-lts`.
- **DualSense** fixes: PipeWire 1.6.5 speaker pin, touchpad-ignore udev rule,
  WirePlumber drop-in, `dualsense-audio` helper.
- Ghost-cursor fix via `cursor { no_hardware_cursors = false; use_cpu_buffer = true }`.
- Roaming NVMe that boots both a desktop (RTX 3060) and a laptop (RTX 4070 Mobile).

See [docs/arch/project-context.md](../docs/arch/project-context.md) for the full map.
