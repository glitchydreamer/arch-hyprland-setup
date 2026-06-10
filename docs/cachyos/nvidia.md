# NVIDIA driver management (CachyOS)

Read [NVIDIA on Linux — the concepts](../common/nvidia.md) first (kernel module vs
userspace, open vs proprietary, modeset, the CUDA ceiling). This page is the
**CachyOS-specific driver management**: how the module is delivered here, and how
the `nvidia-switch.sh` tool drops the whole stack to **580** for Isaac Sim/Lab and
back.

## How CachyOS delivers the module: prebuilt, not DKMS

Out of the box this box runs:

- **Global userspace** (one version, shared by all kernels): `nvidia-utils`,
  `lib32-nvidia-utils`, `opencl-nvidia`, `lib32-opencl-nvidia`, `nvidia-settings`.
- **A prebuilt per-kernel module** for *each* installed kernel:
  `linux-cachyos-nvidia-open` (for `linux-cachyos`) and
  `linux-cachyos-lts-nvidia-open` (for `linux-cachyos-lts`).

There is **no DKMS** by default — pacman ships the module already compiled and keeps
it in lockstep with its kernel. `dkms status` is empty; that's normal and healthy.
The `install.sh health` doctor knows this and reports each kernel's module as
*prebuilt nvidia-open ✓* rather than warning about a missing DKMS build.

This differs from a plain Arch box, where you typically run DKMS or the single
prebuilt `nvidia-open`. It's why the switcher below is a CachyOS-specific rewrite.

## The 580 problem (same as everywhere)

Isaac Sim/Lab needs the driver **580 branch** (what NVIDIA validates the RTX
renderer against). CachyOS shipped the absolute-latest (**610**). Same fix as the
[Arch build](../arch/nvidia.md): make 580 the host driver. The
[container toolkit injects the host driver](../common/nvidia.md#why-a-version-mismatch-not-hardware-breaks-things),
so a container can't fix it — only the host can.

### Two CachyOS advantages over the Arch box

1. **Already on an LTS kernel.** This box boots `linux-cachyos-lts` (6.18), which
   580.105.08+ compiles against — so a downgrade installs **no second kernel** (the
   Arch box had to add `linux-lts`). `linux-cachyos` (7.0) still can't build 580, so
   you boot the lts entry and keep the cachyos entry as a TTY recovery fallback.
2. **`nvidia-utils` is global.** As everywhere, the whole system runs on 580 until
   you switch back — you can't run 610 on one kernel and 580 on another.

## The fix: `nvidia-switch.sh`

A dedicated, **stateful, boot-aware** switcher for the whole NVIDIA stack. Because
NVIDIA drives the display, every swap is **one atomic transaction**, the result is
**pinned** (`IgnorePkg`), the swap is **verified to actually build under dkms before
the boot default is touched**, the initramfs is rebuilt (`mkinitcpio -P`, which
`limine-mkinitcpio-hook` redeploys), the Limine `default_entry` is steered, and the
pacman cache + Docker CDI spec are refreshed.

```sh
bash cachyos/nvidia-switch.sh status      # read-only report (module mode, pins, entries)
bash cachyos/nvidia-switch.sh --dry-run downgrade   # preview, change nothing
bash cachyos/nvidia-switch.sh downgrade   # -> nvidia-open-dkms 580.119.02, boot lts
# (reboot into the linux-cachyos-lts entry)
bash cachyos/nvidia-switch.sh cuda        # align CUDA/cuDNN to the 580 ceiling (post-reboot)
bash cachyos/nvidia-switch.sh latest      # restore prebuilt + repo-latest, boot cachyos
bash cachyos/nvidia-switch.sh purge       # remove everything NVIDIA (TTY/recovery only)
```

### What `downgrade` does, step by step

1. Ensure `dkms` + `linux-cachyos-lts-headers` (already on lts — no second kernel).
2. **Remove** the prebuilt `linux-cachyos*-nvidia-open` modules (they hard-depend on
   the 610 userspace). The *running* module stays loaded in RAM, so the desktop
   keeps working until reboot.
3. Atomically `pacman -U` the **580 set from the Arch Linux Archive**:
   `nvidia-open-dkms` + the five userspace packages (+ `nvidia-settings` if
   installed). DKMS builds the module for `linux-cachyos-lts`; its attempt against
   `linux-cachyos` 7.0 may fail — expected.
4. **Verify** the dkms module is `installed` *for the booted lts kernel
   specifically* before going further. If it only `added` (build failed), the tool
   restores the prebuilt modules and aborts — **no pin, no boot change** — so you
   never reboot into a driverless kernel. (This is the exact guard that caught the
   Arch box's 580.76.05-vs-6.18 build failure.)
5. **Pin** the swapped packages *and* the prebuilt module names (`IgnorePkg`) so
   `-Syu` can't pull 610 back.
6. Rebuild the initramfs and set Limine's `default_entry` to the lts entry.
7. Reclaim cache + regenerate the Docker CDI spec for the new driver version.

### Why the CUDA step is separate

The driver caps the max CUDA, and that ceiling is only readable from `nvidia-smi`
once the new module is **loaded** — i.e. after you reboot. So `cuda` is a separate
post-reboot action that aligns CUDA/cuDNN to the 580 ceiling (580 caps at CUDA
13.0). See the [CUDA ceiling](../common/nvidia.md#the-cuda-ceiling).

!!! note "Driver 610's `nvidia-smi` renamed the field"
    The 610 driver prints **`CUDA UMD Version:`** where older drivers print
    `CUDA Version:`. The scripts match both, so CUDA detection works before and
    after a downgrade.

## Recovery

The Limine menu always shows **both** kernel entries. If a downgrade leaves the
desktop unable to start, pick the **`linux-cachyos` (7.0)** entry at boot to reach a
TTY, then run `nvidia-switch.sh latest` to restore the prebuilt repo-latest stack
and boot back into `linux-cachyos`. The tool's build-verify-before-boot guard makes
this rare, but the fallback entry is always there.

## Bootloader specifics

CachyOS uses **Limine** via `limine-entry-tool` (auto-generated entries) +
`limine-mkinitcpio-hook` (rebuilds redeploy automatically). UKI is off, so entries
are plain `vmlinuz` + initramfs. The switcher steers the default by editing
`default_entry:` in `/boot/limine.conf` (root-only — reads go through a
non-blocking `sudo -n` so `status` never hangs). It never guesses an index it can't
find; if parsing fails it prints the entries and asks you to set the default by hand.
