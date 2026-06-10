# NVIDIA on Linux — the concepts

NVIDIA has a reputation for being "the hard one" on Linux. Most of that reputation
comes from **not understanding which piece is which**. Once you can name the parts,
the troubleshooting (and the per-distro driver management) stops being mysterious.

This page is **distro-neutral concepts**. The actual *driver management* — how you
pin, downgrade, or switch the driver — differs by distro and lives on its own page:

- **Arch Linux:** [NVIDIA driver management](../arch/nvidia.md) — DKMS / prebuilt
  `nvidia-open`, the Arch Linux Archive, the UKI + Limine boot steering.
- **CachyOS:** [NVIDIA driver management](../cachyos/nvidia.md) — prebuilt
  per-kernel `linux-cachyos*-nvidia-open` modules and a dkms-based 580 switcher.

## Kernel module vs userspace — the split that explains everything

An NVIDIA "driver" is really **two** things that must agree on a version:

1. **The kernel module** — code that runs *inside* the Linux kernel and talks to
   the GPU hardware. It has to be compiled against the exact kernel you boot. This
   is `nvidia` / `nvidia_drm` / `nvidia_modeset` / `nvidia_uvm`.
2. **The userspace** — the libraries normal programs link against
   (`libnvidia-*.so`, the OpenGL/Vulkan/CUDA drivers, `nvidia-smi`). This is
   `nvidia-utils` and friends, and it's a **single global version** shared by
   every kernel on the system.

When `nvidia-smi` fails with *"couldn't communicate with the NVIDIA driver"*, it's
almost always that the **module didn't build/load for the running kernel** while
the userspace is fine — the two halves disagree. Keeping them in lockstep is the
whole game.

### How the module gets built

There are two delivery models for the kernel module:

- **DKMS** (Dynamic Kernel Module Support): the *source* is installed and DKMS
  **recompiles** it for each kernel you have, automatically, whenever a kernel or
  the driver changes. Flexible (any kernel) but needs the matching kernel
  **headers** present, and a too-old driver may fail to compile against a brand-new
  kernel.
- **Prebuilt**: a package ships the module **already compiled** for one specific
  kernel package. No build step, no headers needed — but it only exists for the
  kernels the distro builds it for, and it's version-locked to its kernel +
  userspace. (This is CachyOS's default: `linux-cachyos-nvidia-open` etc.)

## Open vs proprietary

Modern NVIDIA GPUs (Turing/RTX 20-series and newer) can use the **open-source
kernel module** (`nvidia-open` / `nvidia-open-dkms`) instead of the old
closed one. "Open" refers to the *kernel module* only — the userspace
(`nvidia-utils`) is still proprietary. On RTX cards the open module is the
recommended default and what both builds here use.

## modeset — why it's on the kernel cmdline

`nvidia_drm.modeset=1` tells the NVIDIA DRM module to do kernel modesetting. On
Wayland this is **required** — without it the compositor (Hyprland) can't drive
the display through the NVIDIA driver properly. You'll see the nvidia modules
loaded **early** (in the initramfs `MODULES=(...)` or via a modprobe drop-in) so
modeset is active before the desktop starts.

## The CUDA ceiling

`nvidia-smi` prints a **"CUDA Version"** (newer drivers label it *"CUDA UMD
Version"*). That number is **not** the CUDA toolkit you have installed — it's the
**maximum** CUDA the *loaded driver* supports. A toolkit newer than that ceiling
needs a newer driver.

This is why these builds **match CUDA to the driver**: the install script reads the
ceiling from `nvidia-smi` and only installs the rolling repo `cuda` if it fits;
otherwise it pins an older toolkit. And it's why a driver downgrade (e.g. to 580
for Isaac Sim) forces a CUDA re-align afterward — the ceiling only becomes readable
once the new driver is actually *loaded* (after a reboot). See each distro's
driver page for the `nvidia-switch.sh cuda` action.

!!! note "CUDA minor-version compatibility"
    A newer-*minor* toolkit of the **same major** (e.g. 13.2 on a driver that caps
    at 13.0) runs fine — only a **major** mismatch needs an older toolkit. The
    `cuda` action compares majors for this reason.

## Why a *version* mismatch, not hardware, breaks things

The headline case study across both builds: **Isaac Sim/Lab** wouldn't run on the
rolling-latest driver but ran fine on driver **580** — the same RTX 3060, just a
different driver *version* (580 is what NVIDIA validates Isaac against). The fix on
every distro is "make 580 the host driver," because the NVIDIA **Container Toolkit
injects the host driver into containers** — so a container can't paper over a host
driver mismatch either. How you get to 580 is the per-distro part:
[Arch](../arch/nvidia.md) · [CachyOS](../cachyos/nvidia.md).
