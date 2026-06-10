# Display setup (CachyOS)

The display *concepts* — resolution, scaling, refresh rate, VRR, bit depth, HDR
vs sRGB, color management — are distro-neutral and live in
[Common → Displays](../common/displays.md). The monitor-config *mechanism*
(per-host `hypr-monitors-*.conf` files + an active symlink flipped by
`select-monitors.sh`) is identical to the [Arch display page](../arch/display.md).

This page covers only the **CachyOS deltas**.

## The hardware here

| Host | Output | Mode | Notes |
|---|---|---|---|
| Desktop | **DP-1** | 3440×1440 @ 160 Hz | LG 34" ultrawide, 10-bit SDR (sRGB), **VRR off** |

The connector is **auto-detected** at setup time, not hardcoded — `setup-home.sh`
reads the first connected non-eDP output (DP-1 here) and its current mode, so the
generated `hypr-monitors-desktop.conf` matches whatever the box reports.

## The big delta: VRR is OFF, on purpose

On this CachyOS + NVIDIA box, leaving **Variable Refresh Rate on** produced the
classic NVIDIA **duplicate-cursor** artifact — two pointers, one of them stuck.
Turning VRR **off** eliminated it. (The Arch box fixed the same symptom a different
way, with a CPU cursor buffer; on CachyOS, `vrr = 0` is the clean fix that worked.)

How it's made reproducible:

- `setup-home.sh hyprland` writes `misc { vrr = 0 }` into
  `~/.config/caelestia/hypr-user.conf`. That file is sourced **last** by caelestia's
  `hyprland.conf`, so it overrides caelestia's base `misc { vrr = 1 }` **globally**
  without editing the caelestia-tracked tree.
- The generated monitor lines also carry `vrr, 0` (belt and suspenders).
- If you'd hand-edited caelestia's base `hypr/hyprland/misc.conf`, the script
  **reverts** it (the durable setting now lives in the override), so a future
  `git pull` of the dotfiles doesn't conflict.

Verify it took:

```sh
hyprctl getoption misc:vrr      # -> int: 0
```

## HDR toggle

Unchanged from Arch: `Super+Ctrl+Alt+H` runs `~/.local/bin/hdr-toggle`, which flips
the primary (non-eDP) display between sRGB/10-bit and HDR10/BT.2020 live, detecting
the monitor + mode so it isn't pinned to one connector. See
[Common → Displays](../common/displays.md#color-management-srgb-vs-wide-gamut) for
why the default is sRGB, not wide-gamut.
