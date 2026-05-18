# Display setup (resolution, refresh, VRR, scale)

This SSD moves between two machines, so the display config has to handle both
without manual edits each swap. Both hosts pick the right `monitor =` lines
automatically at session start via a small detection script.

## What runs where

| Host | Output | Mode | Scale | VRR | Bit depth |
|---|---|---|---|---|---|
| **Laptop** (Intel + RTX 4070 Mobile) | `eDP-1` — BOE 16" 2560×1600 | `2560x1600@240` | `1.25` | on (global `misc { vrr = 1 }`) | 8-bit (panel maxes out at 8 bpc per EDID) |
| **Desktop** (RTX 3060) | `DP-2` — LG 34" WQHD ultrawide | `3440x1440@159.96` | `1.0` | **off** (locked 160 Hz) | **10-bit SDR (sRGB)** by default; HDR on demand via toggle |

The laptop panel is hardware-limited to 8 bpc (BOE EDID says so). The desktop
monitor is 10-bit capable and is configured for 10-bit SDR — smoother
gradients within the sRGB gamut, no downsides since modern DP cables carry it
fine. HDR is not on at boot (toggle is opt-in per session); wide gamut is not
on either — see [Why sRGB is the desktop default](#why-srgb-and-not-wide-gamut).

VRR on the desktop is explicitly **off** (`vrr, 0` on the monitor line, which
overrides the global `misc { vrr = 1 }`). The GPU comfortably feeds 160 Hz, so
locking the display at its max refresh is what we want. VRR's job is to drag
the refresh rate *down* to match a fluctuating GPU frame rate — useful on the
laptop, counterproductive on a desktop that never struggles to keep up. The
laptop keeps VRR on for power and tear-free behaviour during fluctuating loads.

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
monitor = DP-2, 3440x1440@159.96, 0x0, 1, bitdepth, 10, cm, srgb, vrr, 0
monitor = , preferred, auto, 1
```

The trailing args:

- `bitdepth, 10` — 10-bit output (the LG panel reports 10 bpc in its EDID).
- `cm, srgb` — sRGB color management; not HDR, not wide gamut.
- `vrr, 0` — VRR off, display locked at 160 Hz. Overrides the global
  `misc { vrr = 1 }`. The laptop inherits the global, so VRR stays on there.

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

## G-Sync vs. FreeSync vs. VRR — they're all the same thing

"G-Sync" (NVIDIA), "FreeSync" (AMD), and "Adaptive Sync" (VESA) are three brand
names for the same underlying technology: **variable refresh rate (VRR)**. The
display tells the GPU "I can redraw at any rate between X and Y Hz" and the GPU
sends frames as fast as it can render them — the panel updates the moment a
frame arrives instead of on a fixed cadence. No tearing, no waiting for the
next vsync interval.

On Linux there is one knob — `vrr` — and it controls all three. There is no
separate "G-Sync on / VRR off" mode: with NVIDIA's proprietary driver, enabling
`vrr` is what registers the display as a G-Sync Compatible target.

Modes (per-monitor `vrr, N` overrides the global `misc { vrr = N }`):

| `vrr` | Behaviour |
|---|---|
| `0` | Off. Display runs at the configured fixed refresh rate, period. |
| `1` | Always on. Refresh follows GPU frame rate within the panel's VRR range. |
| `2` | On only when a fullscreen window is focused (typical gaming setup). |
| `3` | On for fullscreen *and* video / mpv-like content. |

When to use which:

- **Desktop + high-refresh + capable GPU** → `vrr, 0`. You want the display
  pinned at max refresh; the GPU keeps up.
- **Laptop, mixed workloads** → `vrr, 1` or `vrr, 2`. Saves power, smooths
  unstable frame rates.
- **HDR + VRR causing flicker** → drop to `vrr, 0` for that monitor.

## Why sRGB and not wide gamut

"Wide gamut" means telling Hyprland your monitor can paint outside the sRGB
color triangle — typically up to DCI-P3 or Adobe RGB. Hyprland then asks the
panel to use that wider range. Set with `cm, wide` on the monitor line.

The catch: most Linux desktop apps still encode their output as sRGB without
tagging it. In wide-gamut mode, Hyprland treats those sRGB values as if they
were P3 → reds look neon, skin tones go orange, the whole desktop has a "TV
showroom" look. Same root cause as HDR-without-tone-mapping looking weird.

Apps that *do* handle color management correctly today are a short list — mpv
with the right flags, gamescope-wrapped games, recent Firefox (after setting
`gfx.color_management.mode = 2`), some KDE/Plasma apps. Everything else
(GTK apps, Electron apps, Steam, terminals, file managers) assumes sRGB and
will look wrong.

The current setup keeps `cm, srgb` for predictable, accurate colors and
combines it with `bitdepth, 10` so you get smoother gradients *inside* the sRGB
gamut — that's the "free" upgrade with no downsides. If a wide-gamut workflow
becomes a priority later, flip to `cm, wide` and expect to adjust per-app
color settings.

A/B test live without committing:

```bash
hyprctl keyword monitor "DP-2,3440x1440@159.96,0x0,1,bitdepth,10,cm,wide,vrr,0"
hyprctl keyword monitor "DP-2,3440x1440@159.96,0x0,1,bitdepth,10,cm,srgb,vrr,0"
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
