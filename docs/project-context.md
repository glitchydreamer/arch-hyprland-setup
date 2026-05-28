# Project context (read me first)

A single-page map of *what this project is*, so anyone (or any AI assistant)
can pick it up cold. Details live in the other pages; this is the index of
intent and decisions.

## What this is

Personal Arch Linux + Hyprland (**caelestia** dotfiles) workstation setup. This
repo is **documentation + reproducibility scripts** — it is **not** the dotfiles
themselves. The live config lives in the home directory; the repo describes it
and can regenerate it.

- **Display manager:** GDM (was SDDM on the first install).
- **GPU:** NVIDIA (RTX 3060 on the desktop). Wayland session.
- **Roaming NVMe:** the same SSD boots two machines — a **desktop** (RTX 3060,
  LG 34" ultrawide, currently on **DP-1**) and a **laptop** (Intel + RTX 4070
  Mobile, internal panel on **eDP-1**). Configs must work on both; per-host
  switching is automatic.
- **User workflow:** robotics / ML dev (CUDA, embedded serial), terminal-first,
  fish shell, came from Ubuntu/GNOME.

## The two-script rebuild

A clean `archinstall` + NVIDIA drivers + caelestia, then:

```sh
bash setup-home.sh   # 1. home-dir configs, NO sudo, auto-detects the display
bash install.sh      # 2. packages + system, calls sudo itself
gh auth login && git push   # 3. the only step that can't be scripted
```

**All three scripts are interactive + component-based and share one shape.** Run
with no args for a numbered menu; or pass component names, `all`, `--yes` (skip
the prompt), and `--dry-run` (preview only). Examples:
`bash install.sh cuda audio`, `bash install.sh --dry-run all`,
`bash uninstall.sh docker isaac ros2`. install.sh always runs its prereqs (DB
refresh, git/base-devel/gh/ssh, an AUR helper) before the chosen components.

Both setup scripts are **idempotent**. After them: set `git config --global
user.name`, then log out/in (fish shell + group changes need a fresh session).

- `setup-home.sh` — components: `hyprland`, `scripts`, `fish`, `dolphin`,
  `wireplumber`, `git`. The **source of truth** for those files; edit & re-run.
- `install.sh` — components: `build`, `cuda`, `python`, `anaconda`, `node`,
  `editors`, `embedded`, `audio` (incl. the DualSense PipeWire 1.6.5 pin +
  touchpad udev rule), `gpu`, `media`, `terminal`, `kde`, `display`, `aurapps`,
  `groups`, `shell`. CUDA is driver-matched.
- `uninstall.sh` — interactive, component-based **clean** uninstaller (the
  counterpart to `install.sh`): components `docker`, `isaac`, `ros2`, `anaconda`,
  `cuda`. Each removes its packages + data + configs + launchers and reports
  reclaimed space. Note: it measures root-owned paths with `sudo du` so the
  reclaim total is accurate (a non-root `du` can't read e.g. Docker's 0711
  data-root and would under-count). The driver-level NVIDIA purge is deliberately
  **not** a sweepable component here (so `all` can't nuke the display driver) — it
  lives in `nvidia-switch.sh purge` behind a hard confirmation.
- `nvidia-switch.sh` — dedicated, **stateful** switcher for the WHOLE NVIDIA
  stack (driver + userspace; CUDA/cuDNN via a separate action). Actions: `status`
  (read-only report), `downgrade [ver]` (whole stack → 580.x + `linux-lts`, for
  Isaac Sim/Lab; default target **580.119.02**), `latest` (restore repo-newest,
  boot back into `linux`), `cuda` (align CUDA+cuDNN to the LOADED driver's ceiling
  — clean-remove + reinstall — run post-reboot), `purge` (remove everything NVIDIA
  — leaves no driver, TTY/recovery only). Higher risk than the other scripts
  because NVIDIA drives the display, so every package swap is **one atomic
  transaction**, the result is **pinned** (`IgnorePkg`), the swap is **verified to
  actually build under dkms** before boot is touched, the UKI/initramfs is
  rebuilt, the boot default is steered, and the **pacman cache is pruned** of the
  superseded driver/CUDA versions to reclaim space (the install tree itself never
  holds duplicates — pacman replaces in place). Honours `--dry-run` / `--yes`.
  Sources pinned-older packages from the Arch Linux Archive.
  **CUDA note:** the driver caps the max CUDA (`nvidia-smi`'s "CUDA Version"); 580
  caps at 13.0, 595 at 13.2 — that ceiling is only readable once the new driver is
  *loaded*, which is why CUDA alignment is the separate post-reboot `cuda` action,
  not bundled into `downgrade`. See
  [§NVIDIA learn page](learn/05-nvidia.md#the-fix-switch-the-whole-nvidia-stack-to-the-validated-driver).

## File map (live system, not the repo)

| Thing | Path |
|---|---|
| caelestia upstream (never edit) | `~/.local/share/caelestia/` (and `~/.config/hypr` → symlink into it) |
| User Hyprland overrides | `~/.config/caelestia/hypr-user.conf`, `hypr-vars.conf` |
| Per-host monitors + active symlink | `~/.config/caelestia/hypr-monitors-{desktop,laptop}.conf`, `hypr-monitors.conf` |
| Scripts | `~/.local/bin/{select-monitors.sh, hdr-toggle, dualsense-audio}` |
| Fish additions | `~/.config/fish/conf.d/dev-env.fish` |
| WirePlumber DualSense | `~/.config/wireplumber/wireplumber.conf.d/51-dualsense-headphones.conf` |
| DualSense touchpad ignore | `/etc/udev/rules.d/71-dualsense-touchpad-ignore.rules` |
| CUDA PATH | `/etc/profile.d/cuda.sh` (+ fish via `dev-env.fish`) |

## Decisions & root causes worth remembering

- **Connector is detected, not hardcoded.** First install used DP-2; this one
  is DP-1. `setup-home.sh` writes the desktop monitor file and `hdr-toggle`
  works off whatever the first non-eDP output is.
- **Stuck centre cursor = NVIDIA software-cursor artifact** (the real culprit,
  confirmed after the touchpad theory was ruled out — it survived removing the
  touchpad). Fix: `cursor { no_hardware_cursors = false; use_cpu_buffer = true }`.
  Forcing `no_hardware_cursors=true` actually *caused* the stale cursor.
  Secondary, separate issue: the DualSense **touchpad** registers as an absolute
  pointer — handled by a libinput `LIBINPUT_IGNORE_DEVICE` udev rule (+ Hyprland
  `device{enabled=false}`), which only take effect when the device re-attaches
  (replug/reboot). → [§8.7](reference.md#87-two-mouse-cursors-one-moving-one-stuck-at-centre)
- **DualSense audio = profile routing**, not the old `PCM Playback Volume`
  amixer hack (this UCM card has no mixer controls). Speaker vs the 3.5mm jack
  are separate PipeWire *profiles*; auto-switching ships disabled. Fixed with a
  WirePlumber drop-in (re-enable auto) + a `dualsense-audio` helper. → [§8.1](reference.md#81-dualsense-audio-silent-earphones-in-the-controller-jack)
- **CUDA is matched to the driver.** `install.sh` reads `nvidia-smi`'s max CUDA
  and only installs the rolling repo `cuda` if it fits, else an AUR `cuda-<ver>`.
- **VRR on the desktop:** `vrr, 0` on the monitor line (locked 160 Hz). NVIDIA
  reports `vrr=true` regardless — that's a capability readout, not the setting.
- **Half-screen snaps omitted:** `Super+Ctrl+arrows` is caelestia's workspace
  nav; a float-based snap is unreliable on dwindle.
- **Isaac Sim/Lab is being brought back via a driver downgrade (revised
  2026-05-28).** Earlier the same day Isaac + the container stack were removed
  after the RTX renderer segfaulted on driver **595** even inside the official
  container. The refined diagnosis: this is a **driver-version mismatch**, not a
  hardware/unfixable bug — the *same* RTX 3060 runs Isaac fine on this machine's
  separate **Ubuntu 22.04 SSD**, and Isaac Sim 5.1 validates driver **580** (Arch
  ships 595). The container couldn't help because the NVIDIA Container Toolkit
  *injects the host driver*, so Isaac was stuck on the host's 595. Fix path: make
  **580 the host driver**. Because `nvidia-utils` is a single global version and
  580 won't build on kernel 7.0, this means the whole stack moves to 580 + a
  `linux-lts` kernel — automated in `nvidia-switch.sh downgrade`. Test order once
  on 580: **native binary Isaac first**, container only if Arch userspace needs
  it. **CUDA + Anaconda** stay for general ML regardless.

## Maintenance habit

Every fix or feature is followed — deliberately, without being asked — by:
**fold it into the automated scripts** (`install.sh` for system/sudo steps,
`setup-home.sh` for home configs/launchers; `uninstall.sh` gets a matching
component when something is *removed*), **make it robust** (idempotent,
self-limiting, `FAILED=()`-tracked — rolling Arch breaks things), **update the
docs** (and this page if a decision/root-cause changed), **update memory**, and
**`git push`**. A clean reinstall must reproduce the *fixed* system, and a clean
uninstall must leave no trace. Nothing is left as an ad-hoc `/tmp` one-off —
removals go through `uninstall.sh`, not throwaway scripts.

Gotcha: the login shell is **fish**, which has **no heredocs**. To write a
root-owned file, use `printf '…\n' | sudo tee /path` (not `sudo tee … <<'EOF'`).
fish does support `&&` / `||`.

## Git identity

Commits use **`glitchydreamer <creativegod0307@gmail.com>`** (the GitHub
account), *not* the Claude-context account email. Remote is HTTPS; pushing
needs `gh auth login` (or SSH/PAT) — a fresh install has no credentials.

**Repo visibility doesn't affect pushing.** Public vs private is gated by
auth + write access, not visibility — as the owner you push the same either way.

**GitHub Pages is LIVE (resolved 2026-05-28):**
<https://glitchydreamer.github.io/arch-hyprland-setup/>. The repo was **made
public** to get there — on the Free plan Pages is unavailable for *private* repos,
which is why it 404'd and every `deploy-docs` run failed at
`actions/configure-pages` (API HTTP 422 "current plan does not support GitHub
Pages"). After going public, the workflow's `enablement: true` still couldn't
create the site (token "Resource not accessible by integration"); Pages had to be
enabled once via the owner's CLI token (`gh api -X POST .../pages -f
build_type=workflow`). The deploy now succeeds on every push. (Earlier note that
"Pages stays public even if the repo is private" was wrong.)

## History

- **2026-05-17** — original setup (SDDM, DP-2).
- **2026-05-27** — full rebuild on a clean minimal install (GDM, DP-1):
  scripted into `setup-home.sh` + `install.sh`; fixed the DualSense cursor and
  audio after discovering the first round's diagnoses were the wrong root cause.
- **2026-05-27** — tried Isaac Sim 5.1 + Isaac Lab in a conda env (Python 3.11),
  then **dropped it** after a driver-595 RTX renderer segfault and repeated Arch
  userspace breakage. Switched to the official **Docker container** route.
- **2026-05-28** — the container route also crashed (same driver-595 fault; a
  container can't change the host driver the toolkit injects). First
  **abandoned Isaac** and **removed the whole container stack** (Docker, ROS 2
  Jazzy, Isaac Lab clone, ~20 GB of images) from the live system and scripts;
  added a reusable interactive `uninstall.sh` (now the habit for any removal).
  Kept CUDA + Anaconda. DualSense speaker pin (PipeWire 1.6.5) stays; the 3.5mm
  jack is a controller hardware fault, not software.
- **2026-05-28 (later)** — **reversed the abandonment.** Refined the diagnosis to
  a *driver-version* mismatch (595 vs Isaac's validated 580; proven by the Ubuntu
  SSD running the same hardware). Decided to make 580 the host driver and built
  **`nvidia-switch.sh`** — an atomic, pinned, UKI-aware, reversible switcher for
  the whole NVIDIA stack (`status`/`downgrade`/`latest`/`purge`), sourcing older
  drivers from the Arch Linux Archive and installing `linux-lts` for the build.
  Plan: `downgrade` → boot linux-lts → test Isaac (native binary first, container
  fallback). This machine boots **UKIs** (`/boot/EFI/Linux/*.efi` via mkinitcpio
  presets) under the **Limine** bootloader — Limine does NOT auto-discover UKIs,
  so the tool also gives linux-lts a UKI preset AND adds a `linux-lts` entry to
  `/boot/limine/limine.conf` + sets `default_entry` (bootctl kept as a fallback
  for other machines).
- **2026-05-28 (later still) — first `downgrade` run partially failed; tool
  fixed.** The 580 `pacman -U` aborted with "installing nvidia-utils breaks
  dependency `nvidia-utils=595.71.05` required by nvidia-open": pacman won't
  auto-remove the version-pinned, conflicting prebuilt `nvidia-open` under
  `--noconfirm`. Fix: the swap now **explicitly `pacman -Rdd nvidia-open` first**
  (running module persists in RAM), then `-U` the 580 set, then **verifies**
  `nvidia-open-dkms` installed before pinning/boot changes (restores `nvidia-open`
  and aborts if not). Also found the bootloader is **Limine, not systemd-boot**
  (the earlier `bootctl set-default` was a no-op; only one menu entry showed
  because Limine needs a manual entry). The partial run left `linux-lts`+`dkms`
  installed and a stale 595 IgnorePkg pin (now auto-cleared at downgrade step 0).
- **2026-05-28 (final fix) — 580.76.05 won't compile on linux-lts 6.18; default
  bumped to 580.119.02.** Second run installed the 580.76.05 packages but the
  **DKMS module failed to build** (`dkms status: added`, never `installed`), so
  linux-lts booted with NO driver (`nvidia-smi` failed). Cause: kernel 6.18
  changed the DRM `.fb_create` / `drm_helper_mode_fill_fb_struct` API (commit
  `81112eaac559`, 2025-07-16); the Aug-2025 580.76.05 source has a hard 3-arg
  call. **`linux-lts` (6.18) is itself too new for the old 580** — same wall as
  kernel 7.0. 580.105.08+ add a conftest for the new API; **580.119.02** (newest
  580, Isaac needs the 580 *branch* anyway) builds fine. Fixes: default target →
  `580.119.02`; the downgrade now also **verifies the DKMS module actually built**
  (`dkms status` shows `installed`, not just the package present) before pinning /
  changing boot — the check that would have prevented the driverless boot. Also
  fixed `installed_of` to match exact names (was a false positive: `pacman -Q
  nvidia-open` resolves to nvidia-open-dkms via `provides`).
