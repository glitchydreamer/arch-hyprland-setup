# Hyprland Rice, explained

Welcome. This site documents a **Hyprland + caelestia** workstation on NVIDIA
hardware — and it's written so a *complete beginner* can understand not just
**what** was set up, but **why** each piece works the way it does.

The same desktop has been rebuilt on more than one distribution. The **learning
core** (Wayland, Hyprland, the shell, displays, audio, the dev environment) is
identical everywhere and lives once under **Common**. The parts that genuinely
differ between distros — package management, the NVIDIA driver model, the
bootloader — get their own per-distro section.

!!! tip "New here? Start with the Learning Path."
    Read [**Common → Start here**](common/index.md) first. It explains the big
    picture and the order to read things in. You do **not** need to read the
    reference pages top-to-bottom.

## Pick your distribution

<div class="grid cards" markdown>

-   :material-arch: **Arch Linux**

    ---

    The original build: RTX 3060 + ultrawide, NVIDIA driver pinned to **580** for
    Isaac Sim/Lab, DualSense audio/cursor fixes, a roaming SSD that boots two
    machines. → [**Arch overview**](arch/project-context.md) ·
    [**reference**](arch/reference.md) · [**NVIDIA**](arch/nvidia.md)

-   :material-linux: **CachyOS**

    ---

    Same rice on CachyOS (LTS kernel, performance-tuned Arch derivative). Stock
    PipeWire handles the controller (no DualSense workarounds); the duplicate
    cursor is fixed by turning **VRR off**; NVIDIA uses **prebuilt per-kernel
    modules** with a dkms-based 580 switcher. →
    [**CachyOS overview**](cachyos/project-context.md) ·
    [**reference**](cachyos/reference.md) · [**NVIDIA**](cachyos/nvidia.md)

</div>

## Three ways to use this site

<div class="grid cards" markdown>

-   :material-school: **Learn it**

    ---

    The [**Common Learning Path**](common/index.md) — a guided, beginner-first
    tour of every layer (Wayland, Hyprland, the shell, NVIDIA, audio) with the
    theory behind each. Read it in order. Distro-agnostic.

-   :material-book-open-variant: **Look it up**

    ---

    Each distro has a **Full Reference** ([Arch](arch/reference.md) ·
    [CachyOS](cachyos/reference.md)) — the exhaustive "what is configured and
    where" page: file layout, packages, HDR, troubleshooting recipes.

-   :material-wrench: **Rebuild it**

    ---

    Each distro's **project-context** page ([Arch](arch/project-context.md) ·
    [CachyOS](cachyos/project-context.md)) maps that distro's directory and the
    interactive scripts (`setup-home.sh`, `install.sh`, `uninstall.sh`,
    `nvidia-switch.sh`) that reproduce — or cleanly remove — the system.

</div>

## The Learning Path (Common)

Each step assumes the one before it. Skim what you already know; don't skip what
you don't. These pages are distro-neutral — where a command differs between Arch
and CachyOS it's noted inline, but the concepts are identical.

1. [**Start here — the big picture**](common/index.md) — the mental model and how
   the layers stack.
2. [**Wayland & Hyprland**](common/wayland-and-hyprland.md) — how Linux draws
   windows, why Wayland replaced X11, and what a *tiling window manager* is.
3. [**The caelestia shell**](common/caelestia-shell.md) — the bar, the launcher,
   and the all-important config-override model (the "golden rule").
4. [**Displays: resolution, refresh, HDR**](common/displays.md) — scaling,
   variable refresh rate, bit depth, and color management, from first principles.
5. [**NVIDIA on Linux (concepts)**](common/nvidia.md) — the kernel/userspace
   split, open vs proprietary, modeset, and the CUDA ceiling. (Driver *management*
   is per-distro: [Arch](arch/nvidia.md) · [CachyOS](cachyos/nvidia.md).)
6. [**Audio on Linux**](common/audio.md) — PipeWire, WirePlumber, ALSA, and a real
   debugging case study (the DualSense controller).
7. [**The developer environment**](common/dev-environment.md) — CUDA matching,
   Python environments, and the package philosophy.
8. [**Reproducibility & the scripts**](common/reproducibility.md) — idempotent
   install/uninstall, the component model, and the roaming-SSD trick.
9. [**The troubleshooting mindset**](common/troubleshooting-mindset.md) — how to
   diagnose Linux problems instead of guessing, with worked examples.

Plus a [**Glossary**](common/glossary.md) for every term you don't recognise.

## What these machines actually are

| Layer | Choice | In one line |
|---|---|---|
| Distribution | **Arch Linux** / **CachyOS** | Bleeding-edge, you assemble it yourself (CachyOS = perf-tuned Arch) |
| Display protocol | **Wayland** | The modern replacement for X11 |
| Window manager | **Hyprland** | Tiling, keyboard-driven, animated |
| Desktop shell | **caelestia** | The bar + launcher + panels on top of Hyprland |
| GPU | **NVIDIA** (RTX 3060 / 4070 Mobile) | Powerful, historically the awkward one on Linux/Wayland |
| Audio | **PipeWire** | The modern Linux audio server |
| Shell (terminal) | **fish** | A friendly interactive shell |

Don't worry if half those words are new — that's exactly what the
[Learning Path](common/index.md) is for.
