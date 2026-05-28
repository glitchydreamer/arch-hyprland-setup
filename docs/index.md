# Arch + Hyprland, explained

Welcome. This site documents one specific Linux workstation — **Arch Linux +
Hyprland + the caelestia shell, on NVIDIA hardware** — but it's written so that a
*complete beginner* can understand not just **what** was set up, but **why** each
piece works the way it does.

If you've only ever used Windows, macOS, or Ubuntu, a lot of this will be
unfamiliar. That's expected. The [Learning Path](#the-learning-path) starts from
zero and builds up the mental model one layer at a time.

!!! tip "New here? Start with the Learning Path."
    Read the [**Learning Path → Start here**](learn/index.md) page first. It
    explains the big picture and tells you what order to read things in. You do
    **not** need to read the reference pages top-to-bottom.

## Three ways to use this site

<div class="grid cards" markdown>

-   :material-school: **Learn it**

    ---

    The [**Learning Path**](learn/index.md) — a guided, beginner-first tour of
    every layer (Arch, Wayland, Hyprland, the shell, NVIDIA, audio) with the
    theory behind each. Read it in order.

-   :material-book-open-variant: **Look it up**

    ---

    The [**Full Reference**](reference.md) — the exhaustive "what is configured
    and where" page: file layout, every package, HDR, troubleshooting recipes.
    Use it like a manual, not a tutorial.

-   :material-wrench: **Rebuild it**

    ---

    The [**Project context**](project-context.md) page maps the repo and the
    three interactive scripts (`setup-home.sh`, `install.sh`, `uninstall.sh`)
    that reproduce — or cleanly remove — the whole system.

</div>

## The Learning Path

Each step assumes the one before it. Skim what you already know; don't skip what
you don't.

1. [**Start here — the big picture**](learn/index.md) — the mental model and how
   the layers stack.
2. [**Arch Linux & pacman**](learn/01-arch-and-pacman.md) — what a "rolling
   release" is, package management, the AUR, and the tradeoffs you signed up for.
3. [**Wayland & Hyprland**](learn/02-wayland-and-hyprland.md) — how Linux draws
   windows, why Wayland replaced X11, and what a *tiling window manager* is.
4. [**The caelestia shell**](learn/03-caelestia-shell.md) — the bar, the
   launcher, and the all-important config-override model (the "golden rule").
5. [**Displays: resolution, refresh, HDR**](learn/04-displays.md) — scaling,
   variable refresh rate, bit depth, and color management, from first principles.
6. [**NVIDIA on Linux**](learn/05-nvidia.md) — drivers, the kernel/userspace
   split, CUDA, and why NVIDIA has a reputation here.
7. [**Audio on Linux**](learn/06-audio.md) — PipeWire, WirePlumber, ALSA, and a
   real debugging case study (the DualSense controller).
8. [**The developer environment**](learn/07-dev-environment.md) — CUDA matching,
   Python environments, and the package philosophy.
9. [**Reproducibility & the scripts**](learn/08-reproducibility.md) — idempotent
   install/uninstall, the component model, and the roaming-SSD trick.
10. [**The troubleshooting mindset**](learn/09-troubleshooting-mindset.md) — how
    to diagnose Linux problems instead of guessing, with worked examples.

Plus a [**Glossary**](learn/glossary.md) for every term you don't recognise.

## What this machine actually is

A quick orientation so the rest makes sense:

| Layer | Choice here | In one line |
|---|---|---|
| Distribution | **Arch Linux** | Bleeding-edge, you assemble it yourself |
| Display protocol | **Wayland** | The modern replacement for X11 |
| Window manager | **Hyprland** | Tiling, keyboard-driven, animated |
| Desktop shell | **caelestia** | The bar + launcher + panels on top of Hyprland |
| GPU | **NVIDIA** (RTX 3060 / 4070 Mobile) | Powerful, historically the awkward one on Linux/Wayland |
| Audio | **PipeWire** | The modern Linux audio server |
| Shell (terminal) | **fish** | A friendly interactive shell |
| Quirk | **Roaming NVMe** | One SSD that boots two different machines |

Don't worry if half those words are new — that's exactly what the
[Learning Path](learn/index.md) is for.
