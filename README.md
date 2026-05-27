# arch-hyprland-setup

Personal documentation for an Arch Linux + Hyprland (caelestia) setup, plus all the customisation built around it: NVIDIA RTX 3060 + LG ultrawide, DualSense audio fix, HDR toggle, robotics dev environment, and more.

**📖 Read the docs:** <https://glitchydreamer.github.io/arch-hyprland-setup/>

## Layout

```
arch-hyprland-setup/
├── docs/
│   ├── index.md          ← main reference
│   ├── display.md        ← monitors / HDR / VRR
│   ├── keybinds.md       ← keybind reference
│   ├── coming-from-ubuntu.md
│   └── assets/
├── install.sh            ← reproduce the SYSTEM half on a fresh install (sudo)
├── mkdocs.yml            ← site config (MkDocs Material)
├── requirements.txt      ← Python deps for the site build
├── sync.sh               ← edit → commit → push helper
└── .github/workflows/
    └── deploy-docs.yml   ← builds & deploys to GitHub Pages on push to main
```

## Rebuilding on a fresh install

The home-dir configs (Hyprland overrides, `~/.local/bin` scripts, git, fish,
Dolphin) are documented per-file in the docs. The **system half** — packages
(repo + AUR), the DualSense udev fix, CUDA path, Docker + NVIDIA runtime, group
membership, and switching the login shell to fish — is scripted:

```sh
bash ~/Documents/arch-hyprland-setup/install.sh
```

It's idempotent (`--needed` everywhere) and calls `sudo` itself only where
required. See `docs/index.md` §10 for what changed across rebuilds.

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
