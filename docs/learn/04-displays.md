# Displays: resolution, refresh, HDR

**Goal of this page:** build intuition for the knobs that control your picture —
resolution, refresh rate, scaling, variable refresh (VRR), bit depth, and HDR /
color management — so the [display reference](../display.md) reads as decisions
rather than magic numbers.

Everything below is configured per-monitor with one line in Hyprland:

```
monitor = NAME, RESOLUTION@REFRESH, POSITION, SCALE, [extras...]
```

e.g. `monitor = DP-1, 3440x1440@159.96, 0x0, 1, bitdepth, 10, cm, srgb, vrr, 0`.
The [reference](../display.md#the-monitor-line-decoded) decodes every field; this
page explains *what each concept means*.

## Resolution & refresh rate

- **Resolution** — how many pixels, e.g. `3440x1440`. More pixels = sharper, but
  more work for the GPU.
- **Refresh rate** — how many times per second the screen redraws, in Hz, e.g.
  `@160`. Higher = smoother motion. Written together as `3440x1440@159.96`.

A monitor advertises the modes it supports through its **EDID** (a little data
blob it sends over the cable). `preferred` in the monitor line means "use the
EDID's recommended mode."

## Scaling (HiDPI)

On a dense, high-resolution panel, everything would be tiny at 1:1. **Scaling**
makes UI elements physically larger by telling apps to render bigger. `scale =
1.25` means "draw the UI 25% larger."

!!! warning "Fractional scaling and blur"
    Integer scales (1, 2) are crisp. **Fractional** scales (1.25, 1.5) render the
    image larger then downsample it — native Wayland apps handle this fine, but
    **XWayland** (legacy X11) apps can look slightly blurry. The laptop here uses
    1.25 (its dense panel needs it); the desktop ultrawide uses 1.0 (no scaling,
    no blur). Workarounds for blurry XWayland apps are in the
    [reference](../display.md#troubleshooting).

## Variable refresh rate (VRR) — and the brand-name confusion

**G-Sync (NVIDIA), FreeSync (AMD), and Adaptive Sync (VESA) are three brand
names for the same thing: variable refresh rate.** Normally a monitor redraws on
a fixed cadence (e.g. exactly 60 times/sec). If the GPU finishes a frame
mid-cycle you get **tearing** (a visible seam) or have to wait for the next
cycle (stutter). VRR lets the panel redraw *the moment a frame is ready*, within
a supported range — eliminating both.

On Linux there's **one knob**, `vrr`, controlling all of it:

| `vrr` | Behaviour | Good for |
|---|---|---|
| `0` | Off — fixed refresh, always | Desktop with a GPU that easily hits max Hz |
| `1` | Always on | Laptops, mixed/unstable workloads |
| `2` | On only for fullscreen windows | Typical gaming |
| `3` | Fullscreen + video | Media playback |

The mental key: **VRR's job is to drag refresh *down* to match a struggling
GPU.** This machine's desktop (RTX 3060) comfortably feeds 160 Hz, so VRR is
*off* there — you want it pinned at max. The laptop keeps VRR on for power and
smoothness under variable load. (Per-monitor `vrr, N` overrides the global
default — see the [reference](../display.md#g-sync-vs-freesync-vs-vrr-theyre-all-the-same-thing).)

## Bit depth — smoother gradients

**Bit depth** is how many distinct values each color channel can take. 8-bit =
256 levels per channel (~16.7M colors); 10-bit = 1024 levels (~1.07B). More
levels means **smoother gradients** — no visible "banding" in a sunset or a
shadow. `bitdepth, 10` requests 10-bit output; the panel and cable must support
it (the desktop LG does; the laptop panel is hardware-capped at 8-bit).

10-bit is a "free" upgrade *within* the normal color range — strictly smoother,
no downside. That's different from **wide gamut** and **HDR**, below.

## Color management: sRGB vs wide gamut

**Color gamut** is the *range* of colors a display can show. **sRGB** is the
standard range almost all Linux apps assume. **Wide gamut** (P3, Adobe RGB) can
show more saturated colors — but here's the trap:

!!! warning "Why this machine stays on sRGB"
    Most Linux apps output sRGB colors *without tagging them as sRGB*. If you tell
    the system the monitor is wide-gamut (`cm, wide`), it stretches those untagged
    sRGB values across the wider range → reds glow neon, skin tones go orange, the
    desktop looks like a TV showroom. Only a few apps (mpv, gamescope, recent
    Firefox with a flag) manage color correctly today. So this setup uses
    `cm, srgb` for *accurate* color, plus `bitdepth, 10` for smooth gradients —
    the best combination that doesn't break everything else. Full reasoning:
    [Why sRGB and not wide gamut](../display.md#why-srgb-and-not-wide-gamut).

## HDR — opt-in, not always-on

**HDR** (High Dynamic Range) allows brighter highlights and deeper darks than
standard ("SDR") content. The catch is the same as wide gamut: SDR content shown
through a naive HDR pipeline looks washed out, because it isn't tone-mapped.

So HDR here is **opt-in per session**, not the default. A keybind (<span
class="keys">Super</span>+<span class="keys">Ctrl</span>+<span
class="keys">Alt</span>+H) runs the `hdr-toggle` script, which flips the live
monitor mode to HDR when you want it (a game, an HDR movie) and back to sRGB
afterward — without editing any file. How that script works is in the
[reference](../reference.md#5-hdr-color-management).

## The roaming-SSD twist

This drive boots two machines with different displays. Rather than hard-coding
one monitor, `setup-home.sh` **detects** the connected display at setup time, and
a small login script (`select-monitors.sh`) picks the right per-host monitor file
on every boot by checking whether a laptop panel (`eDP-1`) is present. The
*theory* of that detection is worth reading once — it's a clean example of
"configure by hardware fact, not by hostname": see the full
[display setup page](../display.md).

## Inspecting reality

Two tools answer almost any display question:

- `hyprctl monitors` — what Hyprland is doing *right now* (mode, scale, VRR,
  pixel format).
- `drm_info` — what the *kernel* knows about the hardware (does the panel really
  support 10-bit/HDR/VRR per its EDID?).

The [reference](../display.md#inspecting-current-state) has a "which tool for
which question" table and ready-made one-liners.

---

**Next:** [NVIDIA on Linux →](05-nvidia.md) — drivers, CUDA, and why NVIDIA earns
its reputation here.
