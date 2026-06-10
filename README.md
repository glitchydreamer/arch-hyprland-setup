# hyprland-rice

Personal documentation **and** reproducibility scripts for a Hyprland (caelestia)
workstation on NVIDIA hardware — built across more than one distribution. The
**learning core** is shared; each distro gets its own scripts, docs, and GitHub
Pages section, all under this one master repo.

**📖 Read the docs:** <https://glitchydreamer.github.io/hyprland-rice/>

> Renamed from `arch-hyprland-setup` when it went multi-distro. GitHub
> auto-redirects the old URL.

## Layout

```
hyprland-rice/
├── README.md             ← you are here (master index)
├── arch/                 ← Arch Linux build (original)
│   ├── setup-home.sh  install.sh  uninstall.sh  nvidia-switch.sh  README.md
├── cachyos/              ← CachyOS build (full parity, minus DualSense)
│   ├── setup-home.sh  install.sh  uninstall.sh  nvidia-switch.sh  README.md
├── docs/
│   ├── index.md          ← cross-OS landing ("pick your distro")
│   ├── common/           ← shared, distro-neutral learning path
│   ├── arch/             ← Arch-specific docs (pacman, NVIDIA, reference, …)
│   ├── cachyos/          ← CachyOS-specific docs
│   └── assets/
├── mkdocs.yml            ← one site, nav sections: Common / Arch / CachyOS
├── requirements.txt      ← Python deps for the site build
├── sync.sh               ← edit → commit → push helper (whole repo)
└── .github/workflows/
    └── deploy-docs.yml   ← builds & deploys to GitHub Pages on push to main
```

Each distro directory is **self-contained** (its own scripts + reference) but
**interlinked** with the shared `docs/common/` learning material.

## Builds

| Distro | Directory | Status | Notes |
|---|---|---|---|
| **Arch Linux** | [`arch/`](arch/) · [docs](https://glitchydreamer.github.io/hyprland-rice/arch/project-context/) | original | RTX 3060 + ultrawide, NVIDIA pinned 580 for Isaac, DualSense fixes, roaming SSD |
| **CachyOS** | [`cachyos/`](cachyos/) · [docs](https://glitchydreamer.github.io/hyprland-rice/cachyos/project-context/) | full parity | stock PipeWire (no DualSense work), VRR-off cursor fix, prebuilt-module NVIDIA + dkms 580 switcher |

## Rebuilding on a fresh install

Pick your distro's directory; the two-script flow is the same shape everywhere
(interactive, component-based, idempotent, `--dry-run`/`--yes`/`all`):

```sh
# CachyOS, for example:
bash cachyos/setup-home.sh   # 1. home-dir configs (Hyprland overrides, scripts, fish, git). No sudo.
bash cachyos/install.sh      # 2. system half (packages repo+AUR, CUDA, groups, fish shell). Calls sudo itself.

# Pick just a few components, or preview without changing anything:
bash cachyos/install.sh cuda audio
bash cachyos/install.sh --dry-run all
```

To cleanly remove a component later, use that distro's interactive uninstaller:

```sh
bash cachyos/uninstall.sh            # interactive menu
bash cachyos/uninstall.sh --dry-run docker
```

To switch the whole NVIDIA stack between repo-latest and the Isaac-validated 580
(or purge it), use the distro's dedicated tool — it can change what boots, so read
its recovery notes:

```sh
bash cachyos/nvidia-switch.sh status
bash cachyos/nvidia-switch.sh downgrade   # -> 580 for Isaac
bash cachyos/nvidia-switch.sh latest      # -> repo newest
```

After both scripts, the **only remaining manual step is authentication**:

```sh
gh auth login && git push          # the one thing that can't be scripted
git config --global user.name "…"  # if not already set
# then log out / back in for the fish + group changes
```

See each distro's `project-context` doc for what differs and why.

## Updating the docs

Edit under `docs/`, then either run `./sync.sh "docs: <what changed>"` or commit +
push by hand. GitHub Actions rebuilds and redeploys the Pages site automatically on
every push to `main`.

## Previewing locally (optional)

```sh
python -m venv .venv && source .venv/bin/activate.fish   # or .venv/bin/activate for bash
pip install -r requirements.txt
mkdocs serve            # open http://127.0.0.1:8000
```

## Adding another distro

The structure is built for it: add a `<distro>/` directory with the four scripts,
a `docs/<distro>/` section that links into `docs/common/` for the shared learning,
and a `<distro>` nav block in `mkdocs.yml`. The `arch/` and `cachyos/` directories
are the templates.
