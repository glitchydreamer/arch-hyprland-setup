# Package management cheat-sheet (CachyOS)

CachyOS *is* Arch underneath, so the [Arch package-management
cheat-sheet](../arch/package-management.md) applies in full: `pacman` flags,
querying, orphans, the cache, `.pacnew` files, `IgnorePkg` pins, the AUR. This page
lists only the **CachyOS-specific** commands and names. For the repo/keyring/`downgrade`
background see [CachyOS & pacman](cachyos-and-pacman.md).

## Daily commands

```sh
sudo pacman -Syu                 # full upgrade (NEVER -Sy alone)
paru -Syu                        # repo + AUR upgrade in one go (paru ships with CachyOS)
pacman -Qtdq                     # list orphans → sudo pacman -Rns $(pacman -Qtdq)
paccache -ruk0                   # trim every cached package except installed (reclaim disk)
sudo cachyos-rate-mirrors        # refresh fastest CachyOS mirrors
```

## CachyOS-specific names to know

| Generic Arch | CachyOS equivalent |
|---|---|
| `linux` / `linux-lts` | `linux-cachyos` / `linux-cachyos-lts` |
| `linux-headers` | `linux-cachyos-headers` / `linux-cachyos-lts-headers` |
| (prebuilt nvidia) | `linux-cachyos-nvidia-open` / `linux-cachyos-lts-nvidia-open` |
| `archlinux-keyring` | **plus** `cachyos-keyring` (need both) |
| yay | **paru** (preinstalled) |

## The doctor

`install.sh health` is the one-shot "something feels off after an update" command.
It runs the rolling-release self-repair (kernel↔headers in lockstep, DKMS rebuild
+ `mkinitcpio -P` *if* a DKMS module is in play) and a read-only report of orphans,
failed units, `.pacnew` files, and `IgnorePkg` pins. On a stock prebuilt-module
setup the DKMS step correctly reports nothing to do; after a `nvidia-switch.sh
downgrade` it keeps the `nvidia-open-dkms` module built across kernel upgrades.

```sh
bash cachyos/install.sh health
```

## Pins you may see

- The **NVIDIA stack** is `IgnorePkg`-pinned only **after** you run a
  `nvidia-switch.sh downgrade` (to hold it at 580). On a fresh install there's no
  NVIDIA pin.
- caelestia pins **`hyprland aquamarine hyprtoolkit`** so its shell stays matched to
  a known-good Hyprland — that's expected, not a problem.

See [System maintenance & upgrades](system-maintenance.md) for how pins survive a
`-Syu` and the recovery nets.
