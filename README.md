# arch-hyprland-setup

Personal documentation for an Arch Linux + Hyprland (caelestia) setup, plus all the customisation built around it: NVIDIA RTX 3060 + LG ultrawide, DualSense audio fix, HDR toggle, CUDA/ML dev environment, and more.

**📖 Read the docs:** <https://glitchydreamer.github.io/arch-hyprland-setup/>

## Layout

```
arch-hyprland-setup/
├── docs/
│   ├── project-context.md ← READ FIRST: one-page map of the whole project
│   ├── index.md          ← main reference
│   ├── display.md        ← monitors / HDR / VRR
│   ├── keybinds.md       ← keybind reference
│   ├── coming-from-ubuntu.md
│   └── assets/
├── setup-home.sh         ← reproduce the HOME-DIR half (configs/scripts, no sudo)
├── install.sh            ← reproduce the SYSTEM half on a fresh install (sudo)
├── uninstall.sh          ← interactive clean uninstaller (per-component)
├── mkdocs.yml            ← site config (MkDocs Material)
├── requirements.txt      ← Python deps for the site build
├── sync.sh               ← edit → commit → push helper
└── .github/workflows/
    └── deploy-docs.yml   ← builds & deploys to GitHub Pages on push to main
```

## Rebuilding on a fresh install

Two scripts, run in order. Both are idempotent and assume caelestia is already
installed.

```sh
# 1. Home-dir configs — Hyprland overrides, ~/.local/bin scripts, fish, Dolphin,
#    git defaults. No sudo. Auto-detects your desktop connector + current mode,
#    so it isn't pinned to one machine (DP-1 / DP-2 / HDMI all work).
bash ~/Documents/arch-hyprland-setup/setup-home.sh

# 2. System half — packages (repo + AUR), DualSense udev + audio fix, CUDA
#    (matched to your NVIDIA driver) + cuDNN, groups, fish login shell.
#    Calls sudo itself where needed.
bash ~/Documents/arch-hyprland-setup/install.sh
```

To cleanly remove a component later, use the interactive uninstaller — it strips
the packages, data, configs, and launchers and reports the space reclaimed:

```sh
bash ~/Documents/arch-hyprland-setup/uninstall.sh            # interactive menu
bash ~/Documents/arch-hyprland-setup/uninstall.sh --dry-run docker   # preview
```

`install.sh` bootstraps the essentials first — `git`, `base-devel`, the GitHub
CLI (`gh`), and an **AUR helper** (it builds `yay` from the AUR if neither
`paru` nor `yay` is present on a fresh minimal install) — so the AUR steps have
a helper and you can push as soon as it finishes. It also picks the CUDA toolkit
that fits your installed driver: it reads `nvidia-smi`'s max-supported CUDA and
only installs the rolling repo `cuda` if it's within that ceiling, otherwise it
reaches for an AUR `cuda-<ver>` pinned to the driver.

After both scripts, the **only remaining manual step is authentication**:

```sh
gh auth login && git push          # the one thing that can't be scripted
git config --global user.name "…"  # if not already set
# then log out / back in for the fish + group changes
```

See `docs/index.md` §10 for what changed across rebuilds.

## Updating the docs

Edit `docs/index.md`, then either:

```sh
~/arch-setup-docs/sync.sh "docs: <what changed>"
```

or do it by hand:

```sh
cd ~/arch-setup-docs
git add -A
git commit -m "docs: <what changed>"
git push
```

GitHub Actions rebuilds and redeploys the Pages site automatically on every push to `main` (takes ~30–60 s).

## Previewing locally (optional)

```sh
cd ~/arch-setup-docs
python -m venv .venv && source .venv/bin/activate.fish   # or .venv/bin/activate for bash
pip install -r requirements.txt
mkdocs serve
# open http://127.0.0.1:8000
```
