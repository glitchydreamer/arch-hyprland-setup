# Display setup (resolution, refresh, VRR, scale)

This SSD moves between two machines, so the display config has to handle both
without manual edits each swap. Both hosts pick the right `monitor =` lines
automatically at session start via a small detection script.

## What runs where

| Host | Output | Mode | Scale | VRR | Bit depth |
|---|---|---|---|---|---|
| **Laptop** (Intel + RTX 4070 Mobile) | `eDP-1` — BOE 16" 2560×1600 | `2560x1600@240` | `1.25` | on (global `misc { vrr = 1 }`) | 8-bit (panel maxes out at 8 bpc per EDID) |
| **Desktop** (RTX 3060) | `DP-2` — LG 34" WQHD ultrawide | `3440x1440@159.96` | `1.0` | on | 8-bit SDR by default; HDR/10-bit on demand via toggle |

10-bit isn't enabled on either: the laptop panel is hardware-limited to 8 bpc,
and the desktop monitor wasn't configured for 10-bit (would need
`bitdepth, 10` on the monitor line *and* a panel/cable that supports it).

## File layout

```
~/.config/hypr/
├── hyprland.conf                       # entrypoint — sources monitors.conf
├── hyprland/
│   ├── monitors.conf                   # symlink → active host's file
│   ├── monitors-laptop.conf            # laptop settings
│   ├── monitors-desktop.conf           # desktop settings
│   └── execs.conf                      # runs select-monitors.sh at startup
└── scripts/
    └── select-monitors.sh              # flips the symlink based on /sys/class/drm
```

`monitors.conf` is a symlink, not a real file — it points at whichever per-host
file is correct for the machine currently booted.

### `monitors-laptop.conf`

```ini
monitor = eDP-1, 2560x1600@240, 0x0, 1.25
monitor = , preferred, auto, 1          # catch-all for external monitors
```

### `monitors-desktop.conf`

```ini
monitor = DP-2, 3440x1440@159.96, 0x0, 1, bitdepth, 8, cm, srgb
monitor = , preferred, auto, 1
```

Note the explicit `bitdepth, 8, cm, srgb` — this is the boot-time SDR baseline.
HDR is opt-in per session via `Super+Ctrl+Alt+H` (the `hdr-toggle` script flips
the live mode to 10-bit HDR via `hyprctl keyword monitor` without touching this
file). See the HDR section of [the main reference](index.md#5-hdr--color-management).

### `scripts/select-monitors.sh`

Detects host by checking `/sys/class/drm/card*-eDP-1/status`. If `connected`,
it's the laptop; otherwise the desktop. Updates the symlink and runs
`hyprctl reload` if anything changed.

```bash
#!/usr/bin/env bash
set -eu
dir="$HOME/.config/hypr/hyprland"
link="$dir/monitors.conf"
target=monitors-desktop.conf
for f in /sys/class/drm/card*-eDP-1/status; do
    [ -r "$f" ] || continue
    if [ "$(cat "$f")" = "connected" ]; then
        target=monitors-laptop.conf
        break
    fi
done
current=$(readlink "$link" 2>/dev/null || true)
if [ "$current" != "$target" ]; then
    ln -sfn "$target" "$link"
    [ -n "${HYPRLAND_INSTANCE_SIGNATURE-}" ] && hyprctl reload >/dev/null
fi
```

Wired into `execs.conf`:

```ini
exec-once = $hypr/scripts/select-monitors.sh
```

It also works as a standalone tool — run `~/.config/hypr/scripts/select-monitors.sh`
any time to re-detect (e.g. after hot-plugging a dock).

## Why a symlink and a script

A simpler approach is `source = $hl/monitors-$ENV{HYPR_HOST}.conf` plus setting
`HYPR_HOST` per machine — but that needs both hosts to have a distinct env or
hostname set up *before* Hyprland starts. Currently both machines report
`/etc/hostname = archlinux`, so the detection has to look at hardware. The
presence of a connected `eDP-1` panel is the most reliable signal: laptops have
one, desktops don't.

## The `monitor =` line, decoded

```
monitor = NAME, RESOLUTION@REFRESH, POSITION, SCALE, [extras...]
```

| Field | Notes |
|---|---|
| `NAME` | DRM connector (`eDP-1`, `DP-2`, `HDMI-A-1`). Empty `=` matches any unmatched output. |
| `RESOLUTION@REFRESH` | `2560x1600@240` etc. Or `preferred` to use the EDID's preferred mode. |
| `POSITION` | Logical pixel offset, e.g. `0x0`. `auto` lets Hyprland place it. |
| `SCALE` | `1`, `1.25`, `1.5`, `1.75`, `2`. Fractional values render up and downsample — XWayland apps will be blurry at non-integer scales. |
| Extras | Comma-separated keyword/value pairs: `vrr, 2`, `bitdepth, 10`, `transform, 1`, `mirror, eDP-1`, `cm, hdr`, `sdrbrightness, 1.2`. |

Full reference: <https://wiki.hyprland.org/Configuring/Monitors/>.

## Inspecting current state

```bash
hyprctl monitors                # what Hyprland is doing right now
hyprctl monitors all            # includes disabled outputs
wlr-randr                       # all supported modes (install wlr-randr)
ls /sys/class/drm/              # connectors the kernel sees
cat /sys/class/drm/card*-DP-2/status      # connected | disconnected
edid-decode /sys/class/drm/card*-eDP-1/edid   # bit depth, HDR, primaries
```

Fields worth knowing in `hyprctl monitors` output:

| Field | Meaning |
|---|---|
| `2560x1600@240.00000 at 0x0` | active mode and position |
| `scale` | applied HiDPI scale |
| `vrr` | currently varying refresh? `true` means VRR is active |
| `currentFormat` | `XRGB8888` = 8-bit, `XRGB2101010` = 10-bit |
| `availableModes` | every mode the panel reports via EDID |
| `colorManagementPreset` | `srgb` / `hdr` / `wide` from the `cm` extra |

## Testing changes without editing files

`hyprctl keyword` applies a setting live until the next reload — perfect for
trying scales or refresh rates:

```bash
hyprctl keyword monitor "eDP-1,2560x1600@240,0x0,1.5"   # try scale 1.5
hyprctl keyword monitor "eDP-1,2560x1600@60,0x0,1.25"   # drop to 60 Hz
hyprctl monitors                                          # confirm
```

When you've found something you like, write it into the matching
`monitors-*.conf`.

## Common adjustments

```ini
# Rotate 90°
monitor = HDMI-A-1, 1920x1080@60, 3440x0, 1, transform, 1

# Mirror an external display
monitor = HDMI-A-1, preferred, 0x0, 1, mirror, DP-2

# Force 10-bit (only if both panel + cable support it)
monitor = DP-2, 3440x1440@160, 0x0, 1, bitdepth, 10

# Fullscreen-only VRR (overrides global `misc { vrr = 1 }`)
monitor = DP-2, 3440x1440@160, 0x0, 1, vrr, 2

# Disable a connector entirely
monitor = HDMI-A-1, disable
```

## GUI alternatives

If you'd rather drag boxes around than edit a file:

| Tool | Install | What it does |
|---|---|---|
| `nwg-displays` | `pacman -S nwg-displays` | GUI arranger; writes `monitor =` lines straight into Hyprland config |
| `wdisplays` | `pacman -S wdisplays` | Generic wlroots display GUI |
| `kanshi` | `pacman -S kanshi` | Profile-based auto-switching (e.g. dock vs. undock) |

The script-based setup here predates and supersedes `kanshi` for the
laptop ↔ desktop swap — but `kanshi` is the right tool if you want, say,
different behaviour when docking a USB-C hub vs. plugging in a TV.

## Troubleshooting

**Display stuck at low refresh or wrong scale** — run
`~/.config/hypr/scripts/select-monitors.sh` manually and check
`readlink ~/.config/hypr/hyprland/monitors.conf` points at the right file.

**Hot-plug external display doesn't appear** — the catch-all
`monitor = , preferred, auto, 1` should pick it up. If it doesn't,
`hyprctl monitors all` will show its name; add an explicit line for it.

**Text blurry in some apps after scale change** — those are XWayland apps.
Set `xwayland { force_zero_scaling = true }` in `general.conf` and use
`GDK_SCALE` / `QT_SCALE_FACTOR` env vars per-app instead.

**VRR causing flicker** — drop from always-on (`vrr = 1` global) to
fullscreen-only by adding `vrr, 2` to the monitor line, which overrides global.
