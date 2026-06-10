# Glossary

Plain-language definitions for the terms used across this site. Skim it, or use
your browser's find (<span class="keys">Ctrl</span>+F).

## Core stack

**Distribution (distro)**
: A complete, curated bundle of the Linux kernel plus everything around it
(package manager, services, tools). Arch, Ubuntu, Fedora are distros — each picks
its own software versions and update cadence. See
[Arch & pacman](../arch/arch-and-pacman.md).

**Arch Linux**
: A minimal, do-it-yourself distro with a **rolling release** (see below) and the
`pacman` package manager. You assemble your own desktop.

**Rolling release**
: A distro model with no big versions — you continuously update to the newest
software. Opposite of point releases (Ubuntu 22.04 → 24.04).

**Kernel**
: The core of the OS that talks directly to hardware and manages memory,
processes, and devices. The GPU driver's kernel module lives here.

**Userspace**
: Everything running *outside* the kernel — apps and the libraries they use
(OpenGL, Vulkan, CUDA runtime). The [kernel/userspace
split](../arch/nvidia.md#kernel-module-vs-userspace-the-split-that-explains-everything)
is key to debugging GPU issues.

## Packages

**pacman**
: Arch's package manager — installs, upgrades, and removes software and tracks
dependencies. `-Syu` upgrades everything; `-S` installs; `-Rns` cleanly removes.

**AUR (Arch User Repository)**
: A community collection of *build recipes* (`PKGBUILD`s) for software not in the
official repos. Built locally via an **AUR helper** (see below).

**AUR helper**
: A tool (`yay` or `paru`) that automates downloading, building, and installing
AUR packages — same feel as `pacman -S`.

**Idempotent**
: A script you can run repeatedly with the same end result — it skips work
already done. The [setup scripts](reproducibility.md) are idempotent.

**Pin / `IgnorePkg`**
: Telling pacman to *not* upgrade a specific package, used to hold back a known
good version after a newer one regressed (e.g. the
[PipeWire 1.6.5 pin](audio.md#problem-a-the-speaker-went-silent-a-software-regression)).

## Display & graphics

**Display server**
: The program that puts app windows on screen and routes mouse/keyboard input.
Either **X11** (old) or **Wayland** (modern) — both defined below.

**X11 / X.Org**
: The ~40-year-old display server, built from separate server + window manager +
compositor pieces. Being replaced by Wayland.

**Wayland**
: The modern display *protocol* that merges server/WM/compositor into one
**compositor** process (defined below). Tear-free and secure by design. See
[Wayland & Hyprland](wayland-and-hyprland.md).

**Compositor**
: Under Wayland, the single program that arranges windows into the final image
and handles input. **Hyprland is a compositor.**

**XWayland**
: A compatibility layer that runs old X11 apps inside a Wayland session. The
reason some apps blur at fractional scales.

**Window manager (WM)**
: The component that decides where windows go. May be *floating* (free, overlapping)
or *tiling* (auto-arranged grid).

**Tiling WM**
: A window manager that auto-fits windows into non-overlapping regions, driven by
the keyboard. Hyprland is tiling.

**Hyprland**
: The Wayland compositor + tiling WM used here. Animated, scriptable, configured
in `.conf` files; controlled live with `hyprctl`.

**caelestia**
: The desktop *shell* on top of Hyprland — the bar, launcher, notifications,
panels. Built on **Quickshell** (defined below). See
[the caelestia shell](caelestia-shell.md).

**Quickshell**
: A toolkit for building desktop shells in QML; caelestia is built with it.

**Desktop shell**
: The visible "furniture" (bar, launcher, notifications) around your windows. On
GNOME/KDE it's fused with the WM; in the Wayland tiling world it's separate
(here, caelestia).

**`hyprctl`**
: Hyprland's command-line remote control — query state (`hyprctl monitors`) or
change settings live (`hyprctl keyword ...`).

**EDID**
: A data blob a monitor sends over the cable describing its capabilities
(supported modes, bit depth, HDR). Read it with `drm_info -i`.

**Resolution / refresh rate**
: Pixel count (`3440x1440`) and redraws per second (`@160` Hz). Higher refresh =
smoother motion.

**Scaling (HiDPI)**
: Drawing the UI larger on dense panels. Integer scales are crisp; fractional
(1.25, 1.5) can blur XWayland apps. See [Displays](displays.md#scaling-hidpi).

**VRR (Variable Refresh Rate)**
: Letting the monitor redraw the instant a frame is ready instead of on a fixed
cadence — kills tearing/stutter. "G-Sync," "FreeSync," and "Adaptive Sync" are
brand names for this one thing.

**Bit depth**
: Levels per color channel — 8-bit (256) vs 10-bit (1024). Higher = smoother
gradients, no banding.

**Color gamut / wide gamut**
: The *range* of colors a display shows. sRGB is the standard range apps assume;
wide gamut (P3/Adobe RGB) is larger but breaks untagged sRGB apps — see [why this
machine stays on sRGB](displays.md#color-management-srgb-vs-wide-gamut).

**HDR (High Dynamic Range)**
: Brighter highlights and deeper darks than standard (SDR). Opt-in per session
here via a toggle, because naive HDR makes SDR content look washed out.

**Color management (`cm`)**
: How the system maps app colors to the panel — `srgb`, `hdr`, or `wide`.

## GPU

**Driver**
: Software translating generic GPU requests into hardware commands. Without it,
no acceleration. See [NVIDIA on Linux](../arch/nvidia.md).

**nouveau**
: The open-source, reverse-engineered NVIDIA driver — fully free but slow; not
used here.

**nvidia / nvidia-open**
: NVIDIA's own drivers. `nvidia` is fully proprietary; **`nvidia-open`** (used
here) open-sources the kernel modules while keeping userspace closed —
recommended for recent GPUs.

**CUDA**
: NVIDIA's platform for general-purpose GPU computing (ML/AI, science). Your
driver caps the max usable CUDA version. See
[dev environment](dev-environment.md#cuda-matched-to-the-driver).

**cuDNN**
: NVIDIA's deep-learning primitive library, installed alongside CUDA.

**`nvidia-smi`**
: NVIDIA's status command — driver version, GPU model, the max CUDA the driver
supports, and live utilisation.

## Audio

**ALSA**
: The kernel-level Linux audio layer — the actual sound-card drivers. Always
present, but low-level.

**PulseAudio**
: The previous-generation audio server on top of ALSA; largely superseded by
PipeWire.

**PipeWire**
: The modern Linux audio (and video) server, replacing PulseAudio and JACK while
speaking their protocols. Used here. See [Audio](audio.md).

**WirePlumber**
: PipeWire's session/policy manager — decides default devices, routing rules, and
profiles. PipeWire moves audio; WirePlumber decides the rules.

**Profile**
: A device's selectable configuration (e.g. "Speakers" vs "Headphones"); only one
is active at a time. **Ports** are the outputs/inputs within a profile.

**UCM (Use Case Manager)**
: Config files describing modern USB audio devices by use case rather than raw
mixer controls — why some devices have no volume sliders.

## Misc

**Symlink (symbolic link)**
: A file that points at another file/directory. `~/.config/hypr` is a symlink
into the caelestia tree — important for the [override
model](caelestia-shell.md#the-golden-rule-never-edit-the-upstream-tree).

**fish**
: A user-friendly interactive shell (the program in your terminal), used as the
login shell here. Notably, fish has *no heredocs* — a quirk the scripts work
around.

**systemd**
: The init system and service manager on most modern Linux — starts services,
manages units, handles logging (`journalctl`).

**Dotfiles**
: Configuration files in your home directory (named with a leading dot). This
repo *documents and regenerates* the dotfiles rather than being them.

**Component (in these scripts)**
: A named, self-contained unit of work in `install.sh` / `uninstall.sh` /
`setup-home.sh` (e.g. `cuda`, `audio`) you can select individually. See
[Reproducibility](reproducibility.md#the-component-model).

---

Back to the [Learning Path](index.md) or the [Full Reference](../arch/reference.md).
