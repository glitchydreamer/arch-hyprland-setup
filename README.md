# arch-hyprland-setup

Personal documentation for an Arch Linux + Hyprland (caelestia) setup, plus all the customisation built around it: NVIDIA RTX 3060 + LG ultrawide, DualSense audio fix, HDR toggle, robotics dev environment, and more.

**📖 Read the docs:** <https://glitchydreamer.github.io/arch-hyprland-setup/>

## Layout

```
arch-setup-docs/
├── docs/
│   ├── index.md          ← main reference (was dev-setup-notes.md)
│   └── assets/
├── mkdocs.yml            ← site config (MkDocs Material)
├── requirements.txt      ← Python deps for the site build
├── sync.sh               ← edit → commit → push helper
└── .github/workflows/
    └── deploy-docs.yml   ← builds & deploys to GitHub Pages on push to main
```

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
