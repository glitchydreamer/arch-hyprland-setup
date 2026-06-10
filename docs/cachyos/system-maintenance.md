# System maintenance & upgrades (CachyOS)

The rolling-release maintenance philosophy is the same as Arch — frequent **full**
upgrades are the *safe* path, partial upgrades (`-Sy` without `-u`) are the cardinal
sin, and `IgnorePkg` makes pins persist automatically. The full treatment is on the
[Arch system-maintenance page](../arch/system-maintenance.md); read it for the
*why*. This page is the CachyOS-flavoured **ritual + recovery nets**.

## The weekly ritual

```sh
sudo pacman -Syu archlinux-keyring cachyos-keyring   # both keyrings first
# (or just: bash cachyos/install.sh health  — it does the keyrings + headers + self-heal)
paru -Sua                                            # then AUR rebuilds, if any
```

`install.sh`'s prereqs do this for you every run: refresh **both** keyrings, fold
each installed kernel's `-headers` (`linux-cachyos-headers`,
`linux-cachyos-lts-headers`) into the **same** `-Syu` so modules rebuild in
lockstep, then run the DKMS/initramfs self-heal. Re-running `install.sh` therefore
**repairs** a botched upgrade.

## Pins on this system

- **NVIDIA → 580** (only after a `nvidia-switch.sh downgrade`): the whole stack is
  `IgnorePkg`-pinned, including the prebuilt module package names, so a `-Syu` can't
  pull 610 back. Undo with `nvidia-switch.sh latest`.
- **caelestia → matched Hyprland**: `hyprland aquamarine hyprtoolkit` are pinned so
  the shell stays compatible with a known-good Hyprland.

`pacman` refuses to build a broken dependency graph, so a pin that would conflict
with an upgrade aborts the transaction loudly rather than half-applying it.

## The real long-term risk

The NVIDIA pin's only long-term hazard is **DKMS** (after a downgrade): a future
kernel series could fail the 580 module build. Because you're on **`linux-cachyos-lts`
6.18** — which 580 supports — this is delayed for a long time, and when it does
happen it's a **loud** failure (`install.sh health` flags the kernel as having no
built module), not a silent driverless boot. Mitigations:

- Boot the LTS kernel (the default after a downgrade) and let `linux-cachyos` 7.0 be
  the recovery entry.
- When 580 finally won't build, `nvidia-switch.sh latest` returns you to the
  prebuilt repo-latest stack.

## Recovery nets

- **Two kernels via Limine.** The menu always lists `linux-cachyos` *and*
  `linux-cachyos-lts` — pick the other one if a boot goes wrong.
- **pacman cache + `downgrade`.** Every installed package version stays in
  `/var/cache/pacman/pkg`; `downgrade <pkg>` (CachyOS preinstalls it) rolls a single
  package back. `nvidia-switch.sh` does the whole NVIDIA stack atomically.
- **Keyring refresh.** A box that hasn't updated in a while may have expired signing
  keys — refresh `archlinux-keyring` + `cachyos-keyring` *first*, then `-Su`.
- **`limine-mkinitcpio-hook`** redeploys regenerated initramfs images into the
  Limine entries automatically, so a manual `sudo mkinitcpio -P` is enough to fix a
  bad initramfs.
