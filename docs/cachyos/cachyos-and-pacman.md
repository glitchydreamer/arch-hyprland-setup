# CachyOS & pacman

CachyOS is a **performance-tuned Arch derivative**. If you've read the
[Arch & pacman](../arch/arch-and-pacman.md) page, 90% of it applies unchanged:
same `pacman`, same `-Syu`, same AUR, same rolling-release model and the same
[rolling-release bargain](../arch/arch-and-pacman.md#the-rolling-release-bargain).
This page covers only **what CachyOS adds or changes**.

## What CachyOS is

It's Arch underneath (`/etc/os-release` reports `ID=cachyos`, `ID_LIKE=arch`).
On top of stock Arch it adds:

- **Optimized package repositories** built with newer CPU instruction sets (x86-64-v3/v4)
  for measurable speedups.
- **Performance kernels** (`linux-cachyos`, `linux-cachyos-lts`, and variants) with
  the BORE/EEVDF scheduler tuning, plus matching prebuilt extras (NVIDIA modules,
  headers).
- Sane defaults out of the box: `paru` (AUR helper), the Limine bootloader, a
  graphical installer, and `downgrade`.

## The extra repositories

`/etc/pacman.conf` lists the CachyOS repos **above** the standard Arch ones, so
pacman prefers the optimized builds and falls back to Arch's `core`/`extra`/`multilib`:

```
[cachyos-v3]          # x86-64-v3 optimized packages
[cachyos-extra-v3]
[cachyos-core-v3]
[cachyos]             # generic CachyOS packages
[core]                # ↓ standard Arch repos
[extra]
[multilib]
```

The `-v3` repos only appear if your CPU supports x86-64-v3 (most CPUs from ~2015
on). The practical upshot: a package like `nvidia-utils` may come from
`cachyos-v3` (e.g. `610.43.02-3`) rather than Arch `extra` (`610.43.02-2`) — same
upstream version, CachyOS build.

## Two keyrings, not one

Because packages are signed by **both** Arch and CachyOS keys, you need **both**
keyrings current or signature checks fail (*"invalid or corrupted package
(PGP signature)"*):

```sh
sudo pacman -Sy archlinux-keyring cachyos-keyring && sudo pacman -Su
```

`install.sh` folds both into its prereq `-Syu` automatically (it only adds
`cachyos-keyring` when that package exists, so the same script still works on a
plain Arch box).

## paru, not yay

CachyOS ships **`paru`** as the AUR helper. The scripts here detect `paru` first,
then `yay`, and bootstrap `yay-bin` only on a truly bare install — so on CachyOS
the AUR steps just use `paru`. Everything AUR-related (claude-desktop, brave,
sweet-cursors, candy-icons, weylus-community-bin, anaconda) is identical to the
Arch build.

## The `downgrade` tool

CachyOS preinstalls **`downgrade`**, which fetches an older version of a package
from the pacman cache or the Arch Linux Archive and offers to install + `IgnorePkg`
it:

```sh
sudo downgrade nvidia-utils      # interactive: pick a version, optionally pin
```

The repo's `nvidia-switch.sh` does the equivalent for the *whole* NVIDIA stack
atomically (so the userspace + module never disagree mid-step) and verifies the
dkms build before touching the boot default — see [NVIDIA](nvidia.md). Use bare
`downgrade` for one-off single-package rollbacks.

## CachyOS-specific package management notes

- **Kernels are `linux-cachyos*`**, not `linux`/`linux-lts`. Their headers are
  `linux-cachyos-headers` / `linux-cachyos-lts-headers`, and the prebuilt NVIDIA
  modules are `linux-cachyos-nvidia-open` / `linux-cachyos-lts-nvidia-open`.
- **Updates** are still a full `sudo pacman -Syu` (never `-Sy` alone — the
  [partial-upgrade cardinal sin](../arch/system-maintenance.md) applies identically).
  CachyOS also has `cachyos-rate-mirrors` to refresh the fastest mirrors.
- For the day-to-day cheat sheet (orphans, cache, `.pacnew`, pins) see
  [Package management](package-management.md) and
  [System maintenance](system-maintenance.md).
