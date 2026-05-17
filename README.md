# arch-hyprland-setup

Personal documentation for an Arch Linux + Hyprland (caelestia) setup, plus all the customisation built around it: NVIDIA RTX 3060 + LG ultrawide, DualSense audio fix, HDR toggle, robotics dev environment, and more.

## Contents

- [dev-setup-notes.md](./dev-setup-notes.md) — main reference: file layout, where to change settings, troubleshooting, all the workarounds.

## How to use

GitHub renders the markdown directly — open the file above on any device.

## Updating

Edits live in this repo. After changing anything:

```sh
cd ~/arch-setup-docs
git add -A
git commit -m "docs: <what changed>"
git push
```

Or use the included helper:

```sh
~/arch-setup-docs/sync.sh "docs: <what changed>"
```
