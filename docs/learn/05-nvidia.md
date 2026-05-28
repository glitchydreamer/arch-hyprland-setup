# NVIDIA on Linux

**Goal of this page:** understand what a GPU driver actually is, the difference
between the driver options (`nouveau`, `nvidia`, `nvidia-open`), the crucial
**kernel vs userspace** split, what CUDA is, and why NVIDIA has historically been
the tricky vendor on Linux — illustrated by two real problems this machine hit.

## What a "driver" is

Your GPU is a separate computer on a card. The OS can't use it without a
**driver** — software that translates generic requests ("draw these triangles,"
"run this compute kernel") into the exact commands *this* GPU understands. No
driver, no acceleration (and often no display at all beyond a basic fallback).

## The three NVIDIA driver options

| Driver | Who makes it | Notes |
|---|---|---|
| **nouveau** | Community (reverse-engineered) | Fully open, ships in the kernel, but slow and incomplete for modern cards — fine for a console, not for gaming/CUDA. |
| **nvidia** (proprietary) | NVIDIA, closed-source | Full performance + CUDA. The long-time default; the historical source of Wayland friction. |
| **nvidia-open** | NVIDIA, open kernel modules | NVIDIA's open-source *kernel* modules (the userspace stays closed). Recommended for recent GPUs (Turing and newer). **This machine uses `nvidia-open`.** |

`nvidia-open` is not the same as `nouveau`: it's NVIDIA's *own* code, just with
the kernel-level part open-sourced. You get full performance and CUDA, plus
better long-term kernel compatibility.

## Kernel module vs userspace — the split that explains everything

An NVIDIA driver is really **two pieces**:

```mermaid
flowchart TD
    K["KERNEL module<br/>(runs inside Linux, talks to the GPU silicon)"]
    U["USERSPACE libraries<br/>(OpenGL, Vulkan, CUDA runtime — apps link against these)"]
    A[Your app / game / Isaac Sim] --> U --> K --> GPU[GPU hardware]
```

- The **kernel module** is loaded into Linux itself and is what actually
  commands the silicon. There is exactly **one**, shared by everything.
- The **userspace libraries** are what apps link to (Vulkan for rendering, the
  CUDA runtime for compute).

This split is the single most useful idea for diagnosing NVIDIA problems,
because **a bug in the kernel module cannot be fixed by swapping userspace** —
and that's exactly what bit the Isaac Sim attempt below.

## What CUDA is

**CUDA** is NVIDIA's platform for running general computation (not just
graphics) on the GPU — the backbone of modern ML/AI and scientific computing.
Practically it's a toolkit (`nvcc` compiler, libraries) plus a runtime that talks
to the driver.

The key gotcha, which the [install script](07-dev-environment.md) automates:
**your driver caps the maximum CUDA version you can use.** `nvidia-smi` shows a
"CUDA Version" — that's the *highest* CUDA the installed driver supports, not
what's installed. Install a CUDA newer than that ceiling and it won't run. The
[dev environment page](07-dev-environment.md) explains the matching logic.

## Why NVIDIA was "the hard one" on Wayland

For years the proprietary driver didn't implement the standard buffer-sharing
mechanisms Wayland compositors expected (it used its own, `EGLStreams`). So
Wayland on NVIDIA meant glitches, black screens, and broken apps, while AMD/Intel
(open drivers) worked smoothly. Most of that gap has closed — the driver now
supports the standard path, and compositors like Hyprland run well on NVIDIA. But
a few sharp edges remain, and this machine met two of them.

## Case study 1: the "ghost cursor"

**Symptom:** a mouse cursor frozen at screen centre that survived reboots,
unplugging devices, and disabling every input — clearly *not* an input device.

**Root cause:** an NVIDIA **software-cursor rendering artifact**. The fix is a
specific Hyprland cursor config — a CPU cursor buffer *with* hardware cursors
left enabled:

```ini
cursor {
    no_hardware_cursors = false
    use_cpu_buffer = true
}
```

Counterintuitively, forcing `no_hardware_cursors = true` *caused* the stale
cursor. (A *second*, unrelated cause existed too — the DualSense touchpad
registering as an absolute pointer — fixed separately with a udev rule.) The full
write-up with both causes is in the
[reference](../reference.md#87-two-mouse-cursors-one-moving-one-stuck-at-centre).
This is a textbook example of "the obvious explanation (an input device) was
wrong; the real cause was a layer down (the renderer)."

## Case study 2: Isaac Sim, and a bug a container couldn't fix

**Isaac Sim** is NVIDIA's robotics simulator. The attempt to run it here failed
in a way that's deeply instructive about the [kernel/userspace
split](#kernel-module-vs-userspace-the-split-that-explains-everything).

- First it was tried in a Python/conda environment. That broke repeatedly on
  Arch's rolling **userspace** (library version mismatches) — a fixable class of
  problem.
- Then the **RTX renderer segfaulted** (crashed) whenever it built a 3D scene, on
  this box's NVIDIA **595** driver. A non-rendering compatibility check passed;
  actual rendering crashed.
- The textbook fix for "Arch userspace mismatch" is a **container** (Docker) —
  it ships a matched, frozen userspace. So Isaac was moved into the official
  Docker container... and it **still crashed the same way**.

Why? Because a container replaces *userspace* but **shares the host's kernel**.
The crash was in the kernel-level interaction between the RTX renderer and the
595 driver — and no container can swap the kernel module. That realisation is
what led to **abandoning Isaac entirely** on this machine (and removing the whole
Docker/ROS stack with it). The detailed post-mortem lives in the project memory
and the [reproducibility page](08-reproducibility.md).

!!! note "The lesson"
    When a container *doesn't* fix a "userspace" problem, suspect the kernel. The
    layers diagram at the top of this page is the tool: match the symptom to the
    layer, and you stop wasting time fixing the wrong one.

## Practical NVIDIA commands

```bash
nvidia-smi                 # driver version, GPU model, max supported CUDA, usage
pacman -Qs nvidia          # which NVIDIA packages are installed
hyprctl monitors           # confirm the compositor sees the GPU's outputs
```

---

**Next:** [Audio on Linux →](06-audio.md) — the modern sound stack, and a real
debugging story.
