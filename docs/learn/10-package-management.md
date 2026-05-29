# Package management cheat-sheet — pacman, yay, Flatpak

**Goal of this page:** the everyday commands for finding, listing, and *cleanly*
removing software on Arch — plus the one idea that makes them all make sense (the
way pacman records *why* each package is installed). This is the hands-on companion
to the conceptual [Arch Linux & pacman](01-arch-and-pacman.md) page.

Three package "worlds" can coexist on an Arch machine:

| Tool | What it manages | Front-end on this box |
|---|---|---|
| **pacman** | the official Arch repositories (prebuilt binaries) | `pacman` / `sudo pacman` |
| **AUR** | community *build recipes* compiled locally | **`paru`** (or `yay`) — both take pacman-style flags |
| **Flatpak** | sandboxed, distro-agnostic apps | `flatpak` (optional — not core to this setup) |

`paru` and `yay` are *wrappers* around pacman, so nearly every `pacman -Q…` query
below also works by swapping in `paru`/`yay`.

## The one concept: explicit vs dependency

pacman remembers *why* each package is on your system:

- **Explicit** — you asked for it directly (`sudo pacman -S firefox`).
- **Dependency** — it was pulled in automatically because another package needed it
  (e.g. `gtk3`, `libx11`).

| Package | How it got here |
|---|---|
| `vlc` | Explicit — you chose it |
| `ffmpeg` | Dependency — VLC needs it |
| `qt6-base` | Dependency — VLC needs it |

This distinction is the key to *clean* removal: when you uninstall a package, the
libraries it dragged in become **orphans** (nothing depends on them anymore), and
orphans can be swept away safely. Everything below builds on that idea.

## Listing what's installed

```bash
pacman -Q            # every installed package + version
pacman -Qe           # only the ones YOU explicitly installed
pacman -Qd           # only the ones pulled in as dependencies
pacman -Qm           # "foreign" packages — i.e. from the AUR, not the repos
pacman -Qs <name>    # search installed packages by name
pacman -Qi <pkg>     # detailed info (size, deps, install reason, …)
pacman -Qe > installed.txt   # export your explicit list (handy for rebuilds)
```

!!! tip "Long output? Use a pager"
    `pacman -Q` can be hundreds of lines. Pipe it to a pager to scroll:
    ```bash
    pacman -Q | less
    ```
    If you hit `fish: Unknown command: less`, the pager just isn't installed yet
    (`sudo pacman -S less`). The `terminal` component of this repo's `install.sh`
    also brings the modern equivalents (`bat`, `fzf`, `ripgrep`) — e.g.
    `pacman -Q | grep -i nvidia` to filter instead of scroll.

## Removing a package cleanly

The "as if it was never installed" command:

```bash
sudo pacman -Rns <package>
```

| Flag | Meaning |
|---|---|
| `-R` | remove the package |
| `-n` | also remove pacman-tracked config/backup files (no `.pacsave` left behind) |
| `-s` | remove the dependencies it brought in, *if nothing else needs them* |

!!! warning "`-s` follows the dependency chain — double-check shared libraries"
    `-s` removes now-unneeded dependencies, which is usually what you want. But if a
    dependency is *shared*, pacman keeps it. Read the removal list before confirming;
    for packages tangled into a larger stack (e.g. drivers) prefer a plain
    `sudo pacman -R <pkg>` so you don't cascade into something still in use.

### Sweep up orphans

After a few install/uninstall cycles, stray dependencies pile up. Find and remove
the orphans (dependency packages nothing requires anymore):

```bash
pacman -Qdt                       # list orphans
sudo pacman -Rns $(pacman -Qdtq)  # remove them all (-q = bare names for the subshell)
```

### Reclaim disk space from the package cache

pacman keeps every downloaded package file in `/var/cache/pacman/pkg` — great for
downgrades, but it grows without bound.

```bash
du -sh /var/cache/pacman/pkg      # how big is the cache?
sudo paccache -r                  # keep the 3 most recent versions of each pkg
sudo pacman -Scc                  # nuke the ENTIRE cache (reinstalls re-download)
```

`paccache` comes from `pacman-contrib` (`sudo pacman -S pacman-contrib`). This repo's
`nvidia-switch.sh` uses the same idea to reclaim space after a driver swap.

!!! note "pacman only tracks files it installed"
    `-Rns` removes the program's files, but pacman has **no idea** about data your
    apps create *after* install — home configs and caches like `~/.config/…`,
    `~/.local/…`, `~/.mozilla/`, `~/.var/app/…`. Uninstalling Firefox leaves your
    profile in `~/.mozilla/` untouched. This blind spot is exactly why this repo
    ships an [`uninstall.sh`](08-reproducibility.md) that cleans the *home-side*
    data + configs each component created — the part `pacman -Rns` can't reach.

## AUR packages (paru / yay)

Same flags as pacman, because they wrap it:

```bash
yay -Qm                       # list AUR (foreign) packages specifically
yay -Qe                       # explicit packages (repo + AUR)
yay -Rns <package>            # fully remove an AUR package
yay -Rns $(yay -Qdtq)         # remove orphans
```

(This setup uses **paru** as its AUR helper — swap `paru` for `yay` in any of the
above; the flags are identical.)

## Flatpak (if you use it)

Flatpak manages sandboxed apps entirely separately from pacman — useful for
proprietary apps, but **not part of this machine's core setup** (which favours repo
+ AUR). The equivalents, for reference:

```bash
flatpak list                          # everything installed
flatpak list --app                    # apps only
flatpak list --runtime                # runtimes (the shared "dependency" layer)
flatpak uninstall <app-id>            # remove an app
flatpak uninstall --unused            # remove unused runtimes (orphan cleanup)
flatpak uninstall --delete-data <id>  # remove the app AND its user data
```

Flatpak apps keep their data under `~/.var/app/<app-id>` — `--delete-data` is the
flag that clears it (the Flatpak equivalent of the "pacman leaves home data behind"
caveat above).

## Quick comparison

| Task | pacman / paru / yay | Flatpak |
|---|---|---|
| List installed | `-Q` | `flatpak list` |
| Explicitly installed | `-Qe` | — |
| Dependencies / runtimes | `-Qd` | `flatpak list --runtime` |
| AUR / foreign only | `-Qm` | — |
| Remove a package | `-Rns` | `flatpak uninstall` |
| Remove unused deps | `-Qdt` then `-Rns` | `flatpak uninstall --unused` |
| Remove user data too | manual (`~/.config`, …) | `--delete-data` |

---

**Where to go next:** the [Full Reference → Common commands](../reference.md#7-common-commands-cheat-sheet)
has more day-to-day one-liners, and the [project scripts](../project-context.md)
show how `install.sh` / `uninstall.sh` wrap these commands into clean, repeatable
components. Unsure of a term? The [Glossary](glossary.md) has you covered.
