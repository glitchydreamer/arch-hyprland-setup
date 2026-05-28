# Display setup (resolution, refresh, VRR, scale)

This SSD moves between two machines, so the display config has to handle both
without manual edits each swap. Both hosts pick the right `monitor =` lines
automatically at session start via a small detection script.

## What runs where

| Host | Output | Mode | Scale | VRR | Bit depth |
|---|---|---|---|---|---|
| **Laptop** (Intel + RTX 4070 Mobile) | `eDP-1` — BOE 16" 2560×1600 | `2560x1600@240` | `1.25` | on (global `misc { vrr = 1 }`) | 8-bit (panel maxes out at 8 bpc per EDID) |
| **Desktop** (RTX 3060) | `DP-1` — LG 34" WQHD ultrawide | `3440x1440@159.96` | `1.0` | **off** (locked 160 Hz) | **10-bit SDR (sRGB)** by default; HDR on demand via toggle |

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

`~/.config/hypr` is a **symlink** into the caelestia package tree
(`~/.local/share/caelestia/hypr`), so per-host monitor files can't live there —
they'd be clobbered on a caelestia update. They live in user-owned
`~/.config/caelestia/` instead, and the detection script lives in `~/.local/bin/`:

```
~/.config/caelestia/
├── hypr-user.conf                      # sources hypr-monitors.conf + runs the script
├── hypr-monitors.conf                  # symlink → active host's file
├── hypr-monitors-laptop.conf           # laptop settings
└── hypr-monitors-desktop.conf          # desktop settings
~/.local/bin/
└── select-monitors.sh                  # flips the symlink based on /sys/class/drm
```

`hypr-monitors.conf` is a symlink, not a real file — it points at whichever
per-host file is correct for the machine currently booted. `hypr-user.conf`
(sourced last by caelestia) pulls it in with `source = $cConf/hypr-monitors.conf`
and starts the detector with `exec-once = ~/.local/bin/select-monitors.sh`.

### `hypr-monitors-laptop.conf`

```ini
monitor = eDP-1, 2560x1600@240, 0x0, 1.25
monitor = , preferred, auto, 1          # catch-all for external monitors
```

### `hypr-monitors-desktop.conf`

```ini
monitor = DP-1, 3440x1440@159.96, 0x0, 1, bitdepth, 10, cm, srgb, vrr, 0
monitor = , preferred, auto, 1
```

`setup-home.sh` writes this file with the **connector and mode it detects at
setup time** (the first connected non-eDP output and its current resolution),
so on a different machine the `DP-1`/`3440x1440@159.96` above is filled in with
whatever that box actually uses (`DP-2`, `HDMI-A-1`, …). The 10-bit / sRGB /
`vrr, 0` tuning is the same regardless.

The trailing args:

- `bitdepth, 10` — 10-bit output (the LG panel reports 10 bpc in its EDID).
- `cm, srgb` — sRGB color management; not HDR, not wide gamut.
- `vrr, 0` — VRR off, display locked at 160 Hz. Overrides the global
  `misc { vrr = 1 }`. The laptop inherits the global, so VRR stays on there.

HDR is opt-in per session via `Super+Ctrl+Alt+H` (the `hdr-toggle` script flips
the live mode to 10-bit HDR via `hyprctl keyword monitor` without touching this
file). See the HDR section of [the main reference](reference.md#5-hdr-color-management).

### `~/.local/bin/select-monitors.sh`

Detects host by checking `/sys/class/drm/card*-eDP-1/status`. If `connected`,
it's the laptop; otherwise the desktop. Updates the symlink and runs
`hyprctl reload` if anything changed.

```bash
#!/usr/bin/env bash
set -eu
dir="$HOME/.config/caelestia"
link="$dir/hypr-monitors.conf"
target=hypr-monitors-desktop.conf
for f in /sys/class/drm/card*-eDP-1/status; do
    [ -r "$f" ] || continue
    if [ "$(cat "$f")" = "connected" ]; then
        target=hypr-monitors-laptop.conf
        break
    fi
done
current=$(readlink "$link" 2>/dev/null || true)
if [ "$current" != "$target" ]; then
    ln -sfn "$target" "$link"
    [ -n "${HYPRLAND_INSTANCE_SIGNATURE-}" ] && hyprctl reload >/dev/null
fi
```

Wired into `hypr-user.conf`:

```ini
exec-once = ~/.local/bin/select-monitors.sh
```

It also works as a standalone tool — run `~/.local/bin/select-monitors.sh`
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
| `NAME` | DRM connector (`eDP-1`, `DP-1`, `HDMI-A-1`). Empty `=` matches any unmatched output. |
| `RESOLUTION@REFRESH` | `2560x1600@240` etc. Or `preferred` to use the EDID's preferred mode. |
| `POSITION` | Logical pixel offset, e.g. `0x0`. `auto` lets Hyprland place it. |
| `SCALE` | `1`, `1.25`, `1.5`, `1.75`, `2`. Fractional values render up and downsample — XWayland apps will be blurry at non-integer scales. |
| Extras | Comma-separated keyword/value pairs: `vrr, 2`, `bitdepth, 10`, `transform, 1`, `mirror, eDP-1`, `cm, hdr`, `sdrbrightness, 1.2`. |

Full reference: <https://wiki.hyprland.org/Configuring/Monitors/>.

## Inspecting current state

Two installed power-tools cover almost every question — one CLI, one GUI —
plus the lightweight Hyprland/kernel commands for quick checks.

### `drm_info` — the feature-rich CLI inspector

`drm_info` (package: `drm-info`) dumps **everything the kernel knows** about
every DRM device, connector, encoder, CRTC, plane and property — far more
than `hyprctl monitors` exposes. It's the tool to reach for when you're
diagnosing weird behaviour or want to verify a hardware claim (HDR support,
VRR capability, supported pixel formats, EDID parsing).

```bash
drm_info                              # full human-readable dump for all GPUs
drm_info /dev/dri/card1               # restrict to one card
drm_info -j                           # JSON (pipe to jq for scripting)
drm_info -i                           # include EDID raw bytes
```

What you get for each connector:

- **Status** — `connected` / `disconnected`
- **Physical size** — for accurate DPI / scale decisions
- **Modes** — every resolution / refresh the panel reports
- **EDID parsed** — manufacturer, model, serial
- **DRM properties** — `vrr_capable`, `Colorspace`
  (`Default / BT2020_RGB / BT2020_YCC`), `HDR_OUTPUT_METADATA`, `non-desktop`,
  `link-status`, plus dozens of NVIDIA-specific ones
- **CRTCs / Planes** — every pixel format and modifier the hardware can scan
  out, gamma/degamma LUT sizes, CTM color matrix support

Useful one-liners:

```bash
# Just the connected outputs and their best modes
drm_info 2>/dev/null | awk '/Connector [0-9]/,/Properties/' | \
    grep -E 'Connector|Status|×.*@' | head -30

# Is this monitor VRR-capable per the kernel?
drm_info 2>/dev/null | grep -A1 'DP-1\|vrr_capable'

# All supported pixel formats on the desktop GPU
drm_info -j 2>/dev/null | jq '.[].planes[].formats' | sort -u
```

> **Note:** `drm_info` reads DRM master state. If a Wayland compositor (i.e.
> Hyprland) has the device open, some property blobs come back as `0` and a
> few `drmModeGetPropertyBlob: No such file or directory` warnings print to
> stderr — that's harmless. The full data is still produced.

### `wdisplays` — the feature-rich GUI

`wdisplays` (package: `wdisplays`) is a Wayland-native GUI display arranger,
modeled on `arandr` from the X11 days. Closest to "GNOME Settings → Displays"
in feel, but works on any wlroots compositor including Hyprland.

```bash
wdisplays &        # launches the GUI
```

What it lets you do interactively:

- **Drag monitors** around to set their logical position
- **Resolution & refresh rate** dropdown per monitor (driven by what wlroots
  reports — same list `wlr-randr` shows)
- **Scale** spinner (fractional supported, but XWayland caveat applies)
- **Rotation** (normal / 90 / 180 / 270 / flipped variants)
- **Adaptive sync** (VRR) toggle per monitor
- **Enable / disable** each output
- **Apply** to test, **Save** to keep (Hyprland persists via its wlr-output
  manager bridge — `hyprctl reload` will revert to your config files, so
  treat the GUI as scratch space)

When to reach for it: testing scales/refresh rates without leaving the
desktop, arranging a docked external monitor, confirming what modes a panel
actually offers. When **not** to: making permanent changes — those still
belong in `monitors-*.conf` so they survive a reload and the
laptop ↔ desktop swap.

### Quick checks (already on the system)

```bash
hyprctl monitors                # what Hyprland is doing right now
hyprctl monitors all            # includes disabled outputs
wlr-randr                       # all supported modes (install wlr-randr)
ls /sys/class/drm/              # connectors the kernel sees
cat /sys/class/drm/card*-DP-1/status      # connected | disconnected
drm_info -i 2>/dev/null | grep -A20 -i edid       # parsed EDID: bit depth, HDR, primaries
```

Fields worth knowing in `hyprctl monitors` output:

| Field | Meaning |
|---|---|
| `2560x1600@240.00000 at 0x0` | active mode and position |
| `scale` | applied HiDPI scale |
| `vrr` | currently varying refresh? `true` means VRR is active |
| `currentFormat` | `XRGB8888` = 8-bit, `XBGR2101010` = 10-bit, `XBGR2101010` w/ `cm hdr` = 10-bit HDR |
| `availableModes` | every mode the panel reports via EDID |
| `colorManagementPreset` | `srgb` / `hdr` / `wide` from the `cm` extra |

### Which tool for which question

| Question | Reach for |
|---|---|
| What's Hyprland doing *right now*? | `hyprctl monitors` |
| What modes does this panel support? | `wlr-randr` or `drm_info` |
| Does this monitor really support 10-bit / HDR / VRR? | `drm_info` (`-i` for raw EDID) |
| Try a layout / scale visually | `wdisplays` |
| Diagnose "no signal" on a connector | `drm_info` (look at `link-status`, EDID blob present?) |
| Dump everything for a bug report | `drm_info -j > drm.json` |

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
monitor = HDMI-A-1, preferred, 0x0, 1, mirror, DP-1

# Force 10-bit (only if both panel + cable support it)
monitor = DP-1, 3440x1440@160, 0x0, 1, bitdepth, 10

# Fullscreen-only VRR (overrides global `misc { vrr = 1 }`)
monitor = DP-1, 3440x1440@160, 0x0, 1, vrr, 2

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
hyprctl keyword monitor "DP-1,3440x1440@159.96,0x0,1,bitdepth,10,cm,wide,vrr,0"
hyprctl keyword monitor "DP-1,3440x1440@159.96,0x0,1,bitdepth,10,cm,srgb,vrr,0"
```

## Other GUI / arranger tools

`wdisplays` (above) is the installed default. A few alternatives if its
feature set ever falls short:

| Tool | Install | What it does |
|---|---|---|
| `nwg-displays` | `pacman -S nwg-displays` | GUI arranger that writes `monitor =` lines straight into Hyprland config — useful if you want the GUI to *persist* changes |
| `kanshi` | `pacman -S kanshi` | Profile-based auto-switching (e.g. dock vs. undock) |
| `kscreen-doctor` (KDE) | `pacman -S libkscreen` | KDE's CLI; works partially on Hyprland via wlr-output protocol |

The script-based setup here predates and supersedes `kanshi` for the
laptop ↔ desktop swap — but `kanshi` is the right tool if you want, say,
different behaviour when docking a USB-C hub vs. plugging in a TV.

## Troubleshooting

**Display stuck at low refresh or wrong scale** — run
`~/.local/bin/select-monitors.sh` manually and check
`readlink ~/.config/caelestia/hypr-monitors.conf` points at the right file.

**Hot-plug external display doesn't appear** — the catch-all
`monitor = , preferred, auto, 1` should pick it up. If it doesn't,
`hyprctl monitors all` will show its name; add an explicit line for it.

**Text blurry in some apps after scale change** — those are XWayland apps.
Set `xwayland { force_zero_scaling = true }` in `general.conf` and use
`GDK_SCALE` / `QT_SCALE_FACTOR` env vars per-app instead.

**VRR causing flicker** — drop from always-on (`vrr = 1` global) to
fullscreen-only by adding `vrr, 2` to the monitor line, which overrides global.
