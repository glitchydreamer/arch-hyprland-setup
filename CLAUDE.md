# CLAUDE.md — operating guide for this repo

Personal **multi-distro Hyprland + caelestia** workstation rice (Arch + CachyOS
builds). The deep context lives in `docs/<distro>/project-context.md` — **read
the one for the build you're working on first** (the live box is CachyOS:
`docs/cachyos/project-context.md`). Shared learning material is under
`docs/common/`. The docs are a MkDocs site deployed to GitHub Pages by
`.github/workflows/deploy-docs.yml` on push to `main`.

## Working habits (do these by default — don't wait to be asked)

- **Sync.** At the start of a session, `git fetch` and check status. After
  finishing a unit of work that changes tracked files, **commit and push to
  `origin/main`** — this is a personal repo (`glitchydreamer/hyprland-rice`, gh
  authed with `repo` scope), and pushing also redeploys the docs site. Use
  conventional-commit messages and end them with the
  `Co-Authored-By: Claude ...` trailer.
- **Keep docs + pages in sync with code.** When you change a script's behaviour
  or a config, update the matching page under `docs/` (and the relevant
  `project-context.md` if a decision or difference changed) **in the same
  commit**. Code and its docs ship together.
- **Idempotent, component-based scripts.** All four scripts (`setup-home.sh`,
  `install.sh`, `uninstall.sh`, `nvidia-switch.sh`) share one shape: no-arg
  numbered menu OR component names / `all` / `--yes` / `--dry-run`; idempotent;
  `FAILED=()`-tracked, never abort mid-run. Match that shape in any change.

## Environment gotchas

- **Run `sudo` in a real terminal, never via Claude's `!` bridge.** The bridge
  mangles the password prompt; 3 failures trip `pam_faillock` (deny=3,
  unlock_time=600s) and lock `sudo` for 10 minutes. `su` is unaffected (no
  faillock in its PAM stack). If locked: wait 10 min, or `su -` to root and
  `faillock --user <you> --reset`. Surface sudo steps to the user to run.
- **NVIDIA is pinned at 580.119.02** for Isaac Sim/Lab (`nvidia-open-dkms` +
  IgnorePkg). Boot `linux-cachyos-lts`; `linux-cachyos` 7.0 can't build 580
  (expected — it's the TTY fallback). Manage the stack **only** via
  `cachyos/nvidia-switch.sh` (boot-critical, read its recovery notes). After a
  downgrade, `nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml` is deferred
  to post-reboot — a stale CDI spec breaks `docker --gpus all`.
- **Don't edit caelestia-owned files**: `~/.config/fish/config.fish` and the
  hypr base tree. Personal fish → `~/.config/fish/conf.d/dev-env.fish`; personal
  hypr → `~/.config/caelestia/hypr-user.conf`.
- **CachyOS-box specifics**: `misc { vrr = 0 }` (not a CPU-cursor buffer) fixes
  the duplicate cursor; DualSense needs no special work; bootloader is Limine
  (steer `default_entry:`, never manage UKI, never guess an index).
