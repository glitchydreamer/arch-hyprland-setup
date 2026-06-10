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

- `setup-home.sh` — components: `hyprland`, `caelestia` (merges `shell.json`
  shell/dashboard tweaks — weather in °C via `services.useFahrenheit=false`, and the
  screen-wide background audio visualiser via `background.visualiser.enabled=true`,
  re-asserted each run so a caelestia default-flip can't silently disable it),
  `nautilus` (sets a Sweet icon theme — synthwave **Sweet-Purple** folders +
  candy app icons — as the GTK icon theme via gsettings + GTK3/4 settings.ini;
  `ICON_THEME=<variant>` to pick another. For PERSISTENCE across upgrades use
  `install.sh theme`, which adds a system dconf lock so caelestia/GTK can't reset
  it to Papirus-Dark),
  `scripts`, `fish`, `wireplumber`, `git`. The **source of truth** for
  those files; edit & re-run.
- `install.sh` — **rolling-release self-healing**: the always-run prereqs do a
  full `-Syu` with `archlinux-keyring` + every installed kernel's `-headers`
  folded into the *same* transaction (so DKMS/NVIDIA rebuilds in lockstep and no
  kernel is left module-less), then auto-`dkms autoinstall` + `mkinitcpio -P` +
  verify. Re-running the script therefore REPAIRS a botched upgrade. Components:
  `health` (standalone doctor: the same kernel-headers/DKMS/initramfs auto-repair
  + a read-only report of orphans, failed units, `.pacnew`, and `IgnorePkg`
  pins), `build`, `cuda`, `python`, `anaconda`, `node`,
  `editors`, `embedded`, `audio` (incl. the DualSense PipeWire 1.6.5 pin +
  touchpad udev rule), `gpu`, `docker` (Docker + NVIDIA Container Toolkit;
  data-root on /home/docker-data + containerd-snapshotter=false; for ROS 2 Humble /
  GPU containers), `vm` (**QEMU/KVM + virt-manager** desktop virtualization for
  building Gentoo / Linux From Scratch & running any guest OS — `qemu-full` +
  `libvirt` + `virt-manager` + `virt-viewer` + `edk2-ovmf` + `swtpm` + `dnsmasq`
  + `dmidecode` + `libguestfs` from the official repo, so always newest; adds the
  user to `libvirt`+`kvm`, sets the libvirt-group socket perms, enables
  `libvirtd`, defines/starts the default NAT net, and writes a vendor-detected
  nested-virt modprobe drop-in. **Kernel-agnostic**: KVM modules are in-tree on
  both `linux` and `linux-lts`, no DKMS), `media` (haruna/obs/gimp/okular/gwenview/swayimg + `ffmpeg`
  for video decoding & frame extraction by the fastfetch-logo helper),
  `terminal` (fzf/rg/fd/bat/zoxide/lazygit/gh/tmux/tree/jq/yq + `chafa`,
  the terminal-image renderer that drives fastfetch-logo), `kde`, `display`, `monitor` (HWiNFO
  equivalent — psensor + hardinfo2 GUIs, mission-center, nvtop, btop, lm_sensors),
  `storage` (NTFS/exFAT userspace drivers + gnome-disk-utility so
  Windows-formatted SSDs mount in nautilus — Arch omits these by default,
  unlike Ubuntu — plus `kdiskmark`, the CrystalDiskMark-equivalent
  Qt6 disk-benchmark GUI), `remote` (enable `sshd` + freerdp/remmina for RDP/VNC *out* +
  `wayvnc` as a VNC server *into* this Hyprland box — RDP-into-Wayland is
  unsupported, VNC is the working path), `tablet` (use an iPad/Android tablet as
  a graphic tablet / touchscreen via **Weylus Community Edition** — the
  prebuilt `weylus-community-bin`; upstream H-M-H/Weylus is dead and no longer
  compiles on current rustc — plus the `uinput` group + udev rule + module
  autoload so the daemon can inject pen/pointer events, and
  `gst-plugin-pipewire` for the Hyprland portal screencast), `theme` (candy-icons + sweet-folders
  from the AUR — the rainbow GTK icon set — AND a **system dconf lock** that pins
  the icon theme so an upgrade / caelestia colour-scheme change can't revert it to
  Papirus-Dark; variant via `ICON_THEME`, default Sweet-Purple. The two AUR
  packages are the complete minimal set — all 12 colour variants ship inside the
  one ~2 MiB `sweet-folders-icons-git`, so there's nothing extra to prune for
  disk), `aurapps`, `groups`, `shell`.
  CUDA is driver-matched.
- `uninstall.sh` — interactive, component-based **clean** uninstaller (the
  counterpart to `install.sh`): components `docker`, `vm` (remove the whole
  QEMU/KVM + libvirt + virt-manager stack and **delete all guest disk images in
  EVERY pool** — the default `/var/lib/libvirt` one *and* any custom pool on
  `/home`, found by querying libvirt for every volume before the daemon is
  stopped; only real disk images `.qcow2/.raw/.img/…` go, ISOs/other files are
  left alone and their paths printed — so a disk orphaned by forgetting
  virt-manager's "Delete associated storage" is still reclaimed — plus
  `/etc/libvirt`, per-user virt-manager state, the nested-virt drop-in, and the
  `libvirt`/`kvm` group memberships; KVM modules are in-tree so nothing to
  uninstall there), `isaac`, `ros2`, `anaconda`,
  `cuda`, `icons` (switch the GTK icon theme back to the caelestia default
  Papirus-Dark — now also **removes the system dconf icon-theme lock** install.sh
  wrote, FIRST, since a locked key can't otherwise be changed; keeps the
  Sweet/candy packages so `setup-home.sh nautilus` re-applies instantly),
  `inputremap` (remove input-remapper + its daemon + presets —
  no longer needed since the Razer mouse remaps via onboard memory), `fastfetch`
  (revert the fastfetch logo + sixel file + animation hook),
  `tablet` (remove Weylus + the uinput udev rule/module-load file + drop the
  user from the `uinput` group; keeps `gst-plugin-pipewire` because it's shared
  with audio/screen recording), `extras`
  (remove unused apps + their home data: Zed, Dolphin, Inkscape, Kate, HyprKCS).
  Each removes its packages + data + configs + launchers and reports
  reclaimed space. Note: the reclaim total counts **both** the deleted home/data
  paths **and** the removed packages — `remove_pkgs` simulates the removal
  (`pacman -Rs --print`) to learn the full cascade (named pkgs + the deps `-Rns`
  pulls) and sums their installed sizes; and it measures root-owned paths with
  `sudo du` (a non-root `du` can't read e.g. Docker's 0711 data-root and would
  under-count). The driver-level NVIDIA purge is deliberately
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
  [§NVIDIA learn page](nvidia.md#the-fix-switch-the-whole-nvidia-stack-to-the-validated-driver).

## File map (live system, not the repo)

| Thing | Path |
|---|---|
| caelestia upstream (never edit) | `~/.local/share/caelestia/` (and `~/.config/hypr` → symlink into it) |
| User Hyprland overrides | `~/.config/caelestia/hypr-user.conf`, `hypr-vars.conf` |
| Caelestia shell settings | `~/.config/caelestia/shell.json` (bar/dashboard/weather; written by the `caelestia` component) |
| Per-host monitors + active symlink | `~/.config/caelestia/hypr-monitors-{desktop,laptop}.conf`, `hypr-monitors.conf` |
| Scripts | `~/.local/bin/{select-monitors.sh, hdr-toggle, dualsense-audio, ros2-humble, moveit2-humble, vnc-server, remote}` |
| ROS 2 Fast DDS profile | `~/.config/ros2/fastdds-udp-only.xml` (UDP-only transport; written by the `ros2-humble`/`moveit2-humble` launchers, shared by both) |
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
- **Isaac Sim/Lab WORK on Arch now, and ROS 2 Jazzy is back (2026-05-28).** Isaac
  failed earlier because the RTX renderer needs driver **580** (validated) but
  Arch ships **595** — a driver-*version* mismatch, not hardware (the same RTX
  3060 runs Isaac on the Ubuntu 22.04 SSD). The NVIDIA Container Toolkit *injects
  the host driver*, so a container couldn't fix it either; the only cure was
  making **580 the host driver**. `nvidia-switch.sh downgrade` does that (whole
  stack → 580.119.02 + `linux-lts`, since `nvidia-utils` is a single global
  version and 580 won't build on kernel 7.0). Isaac Sim **and** Isaac Lab now run
  **natively** on that stack. With the driver sorted, **ROS 2 Jazzy was re-added**
  (Docker + NVIDIA Container Toolkit + the `ros2-jazzy` launcher) — the toolkit
  injects the 580 driver into containers, and `--network host` + a shared DDS
  domain bridge it to native Isaac's ROS 2 bridge. **CUDA must be aligned to the
  580 ceiling (13.0) via `nvidia-switch.sh cuda`** — it had stayed at the 595-era
  13.2. **CUDA + Anaconda** stay for general ML regardless.

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
- **2026-05-28 — ROS 2 container wouldn't start: `nvidia-settings` left at 595.**
  `ros2-jazzy shell` (`docker --gpus all`) failed: *"open
  /usr/lib/libnvidia-gtk3.so.580.119.02: no such file or directory"*. The NVIDIA
  Container Toolkit injects host NVIDIA libs **by the driver version**, but
  `nvidia-settings` (ships `libnvidia-gtk3` / `libnvidia-wayland-client`) wasn't
  in the swap set, so it stayed at 595 and the 580 file didn't exist. Fix:
  `nvidia-switch.sh` now includes **and pins `nvidia-settings`** in `downgrade`
  (and restores it in `latest`) when it's installed. Immediate repair: `pacman -U`
  the 580.119.02 `nvidia-settings` from the archive + add it to the pin. Lesson:
  the *entire* NVIDIA package set (module + userspace + settings libs) must sit on
  one version or `--gpus all` breaks.
- **2026-05-28 — ROS 2 container, part 2: stale Docker CDI spec.** After fixing
  `nvidia-settings`, `ros2-jazzy shell` still failed: *"open
  /usr/lib/libnvidia-tileiras.so.580.119.02: no such file"*. Root cause: **Docker
  29 resolves `--gpus all` via its NATIVE CDI** (reads `/etc/cdi/nvidia.yaml`), and
  the spec there was stale — it listed a phantom `libnvidia-tileiras` the open
  driver doesn't ship. (`nvidia-container-runtime.mode=legacy` was a red herring —
  `--gpus` bypasses that runtime.) A *fresh* `nvidia-ctk cdi generate` scans real
  files and is clean. Fix: regenerate the spec — and do it automatically: the
  `docker` install component generates it, and **`nvidia-switch.sh` regenerates it
  on every driver swap** so it never goes stale again.
- **2026-05-28 — ROS 2 Jazzy ↔ Isaac Sim bridge VERIFIED.** After the CDI fix,
  `ros2-jazzy shell` starts and `ros2 topic list` works; Isaac's
  `isaacsim.ros2.bridge` was enabled by default, so topics crossed immediately.
  The full robotics stack (Isaac Sim + Lab native on 580.119 + ROS 2 Jazzy
  container) is functional on Arch.
- **2026-05-29 — ROS 2 topic data wasn't flowing (discovery-only).** `ros2 topic
  list` showed `/isaac_joint_states` and `topic info --verbose` reported
  `Publisher count: 1`, but `ros2 topic echo`/`hz` were silent. Cause: Fast DDS
  discovery rides UDP (works over `--network host`), but the default *data*
  transport is shared memory — and native Isaac (UID 1000) and the container
  (root) can't share `/dev/shm`, so every sample was dropped. Fix: force UDP with
  `FASTDDS_BUILTIN_TRANSPORTS=UDPv4` on the container/subscriber side (Isaac
  already advertises UDP locators). Confirmed ~60 Hz. Baked into the `ros2-jazzy`
  launcher as a default env var; documented in Learn → dev-environment (Gotcha 3).
- **2026-05-29 — caelestia weather panel switched to Celsius.** The dashboard
  weather defaulted to Fahrenheit; the unit lives in `shell.json` at
  `services.useFahrenheit` (a `ServiceConfig` property, per the
  `caelestia-config.qmltypes`). Set to `false`. Added a new `caelestia` component
  to `setup-home.sh` that deep-merges the key into `shell.json` (preserving other
  keys); documented in Learn → caelestia-shell (new `shell.json` section).
- **2026-05-29 — rainbow icons for nautilus (Sweet-Mars *theme* not feasible).**
  Request was Sweet-Mars GTK theme + rainbow icons on nautilus. Reality check:
  nautilus is **GTK4/libadwaita (1.9)**, and libadwaita takes window colours ONLY
  from the global `~/.config/gtk-4.0/gtk.css` `@define-color` palette — which
  **caelestia owns and regenerates** from its colour scheme. libadwaita ignores
  both `gtk-theme` and the `GTK_THEME` env var, so a *per-app* Sweet-Mars window
  theme isn't achievable without fighting caelestia (user chose not to recolour
  all libadwaita apps). What works and shows in nautilus is the **icon theme**:
  installed `candy-icons` + `sweet-folders` (AUR, new `theme` component in
  `install.sh`) and set them as the GTK icon theme via the new `nautilus`
  component in `setup-home.sh` (gsettings + gtk-3.0/gtk-4.0 `settings.ini`). Icon
  themes are system-wide for GTK apps; KDE/Qt and the QML bar are unaffected.
- **2026-05-29 — synthwave folders via Sweet-folders + easy revert.** candy-icons'
  own folders are cyan; the user wanted the synthwave (purple) Sweet-folders look.
  Key insight: each `sweet-folders` variant (`Sweet-Purple`, `Sweet-Rainbow`, …)
  ships **only folder icons** and its `index.theme` already `Inherits=candy-icons`
  — so setting the icon theme to `Sweet-Purple` gives purple folders + candy app
  icons in one setting. `setup-home.sh nautilus` now defaults to `Sweet-Purple`
  (override `ICON_THEME=<variant>`). Added a `uninstall.sh icons` component to
  switch back to the caelestia default (Papirus-Dark) + strip the gtk ini
  overrides, keeping the packages so re-applying is instant.
- **2026-05-29 — remote access + drive mounting + Disks app.** Four asks: (1)
  *spotlight* — already exists: **tap `Super`** opens caelestia's launcher. (2)
  *nautilus can't open the other SSDs* — they're **NTFS** (`nvme0n1` p3/p4/p5) and
  Arch lacked `ntfs-3g`; new `storage` install component adds `ntfs-3g` +
  `exfatprogs` + `gnome-disk-utility`, after which they mount on click (udisks2 was
  already running). (3) *SSH/RDP both ways* — new `remote` component enables `sshd`
  and installs `freerdp`+`remmina` (out) + `wayvnc` (VNC server in); RDP into a live
  Hyprland/Wayland session isn't supported, so **VNC via wayvnc** is the chosen
  into-box path, with a `vnc-server` helper (localhost by default → SSH-tunnel).
  (4) *Ubuntu "Disks" equivalent* — `gnome-disk-utility` (`gnome-disks`); `df -h`
  for CLI; `filelight` already present.
- **2026-05-29 — remote access is OFF by default + a `remote` toggle.** Per the
  user's preference, `install.sh remote` no longer enables `sshd` at boot (an idle
  sshd is ~free, but off = smaller attack surface; wayvnc was already on-demand).
  Added a `remote on|off|status` helper (`~/.local/bin/remote`, setup-home
  `scripts`): `on` starts sshd, `off` stops sshd + kills any wayvnc, `status` shows
  active state + LAN IP + listening :22/:5900. Always-on is still one command:
  `sudo systemctl enable --now sshd`.
- **2026-05-29 — Razer side keys work out of the box; input-remapper removed.** The
  side-key remaps were never a Linux problem: the Razer Basilisk V3 stores profiles
  in **onboard memory**, and the wrong profile had been flashed. Re-flashing the
  correct profile via **Razer Synapse on Windows 11** made every button work the
  moment Linux sees the device — no evdev remapper required. So `input-remapper` was
  dropped from `install.sh`, and `uninstall.sh inputremap` now removes it cleanly
  (disable+stop the daemon → `-Rns input-remapper` → delete the `~/.config/input-remapper-2`
  presets). Lesson: peripherals with onboard memory remap at the firmware layer,
  independent of the OS — fix the profile on the device, not in the compositor.
- **2026-05-29 — ROS 2 container switched Jazzy → Humble (Isaac was crashing).**
  With the sim playing, `ros2 topic list` from the Jazzy container **crashed Isaac
  Sim** (Omniverse breakpad abort). Backtrace: `cdr_deserialize(... ParticipantEntitiesInfo
  ...)` → a `vector<NodeEntitiesInfo>::resize(huge)` → `operator new` → abort, inside
  `libfastrtps.so.2.6`. Root cause: a **cross-distro DDS mismatch.** Isaac's *bundled*
  ROS 2 bridge is **Humble** (Fast DDS 2.6), but the container was **Jazzy** (Fast DDS
  2.14); the two encode the `ros_discovery_info` graph message (`rmw_dds_common`)
  differently (XCDR v2 vs v1), so Isaac's discovery listener mis-read a length field
  and aborted. (Data topics like `sensor_msgs/JointState` flowed fine at 60 Hz — only
  the *discovery* message differs — which is why it looked like it worked before.)
  Fix: **match the distro** — the launcher is now `ros2-humble` on
  `osrf/ros:humble-desktop-full`. Carried over every prior fix (`--gpus all`,
  `--network host`, `--ipc host`, shared `ROS_DOMAIN_ID`/`rmw_fastrtps_cpp`, X11/Wayland
  forwarding, `~/robotics/ws` mount). One fix had to change form: Humble's Fast DDS 2.6
  has **no `FASTDDS_BUILTIN_TRANSPORTS` env var** (added in 2.10/Iron), so the UDP-only
  transport (needed because native Isaac UID 1000 and the root container can't share
  `/dev/shm` SHM segments) is now a **Fast DDS XML profile** (`~/.config/ros2/fastdds-udp-only.xml`,
  `useBuiltinTransports=false` + a single UDPv4 transport) mounted in and selected via
  `FASTRTPS_DEFAULT_PROFILES_FILE`. The 4.58 GB Jazzy image + old `ros2-jazzy` launcher
  were removed (`docker rmi`); `uninstall.sh ros2` now targets Humble and also sweeps a
  leftover Jazzy image. Images still land on `/home/docker-data` (data-root), so the
  ~4 GB Humble pull uses the 800 GB `/home`, not the small root.
- **2026-05-29 — decluttered unused apps (Zed, Dolphin, Inkscape, Kate, HyprKCS).**
  All were explicitly installed with nothing depending on them (`Required By: None`),
  so removal is safe. New `uninstall.sh extras` component removes the packages **and**
  their home `~/.config`/`.cache`/`.state` (Zed, Dolphin, Inkscape, Kate, HyprKCS — the
  hyprkcs `-debug` split goes too). Also stopped *installing* them so a rebuild won't
  bring them back: `editors` dropped `zed` (Neovim only), `media` dropped `inkscape`,
  `kde` dropped `dolphin`. **Dolphin's removal cascaded into doc/config fixes** — the
  daily file manager has been **nautilus** for a while (live `$fileExplorer = nautilus`,
  `Super+E`), but the generator and several docs still said Dolphin: fixed
  `setup-home.sh` (`$fileExplorer` → nautilus, deleted the dead `dolphin` component +
  the `zed`→`zeditor` fish abbr) and updated coming-from-ubuntu / keybinds / reference /
  Learn pages to say Nautilus. Kate + HyprKCS were never in `install.sh` (came with the
  KDE/Hyprland deps / a manual AUR install).
- **2026-05-29 — keybinds for Zen browser + Obsidian.** Added `Super+Shift+Z` →
  `zen-browser` and `Super+Shift+V` → `obsidian` (V = Vault; Obsidian's natural `O`
  was already the dashboard toggle). Added to both the live `hypr-user.conf` and the
  `setup-home.sh` generator (source of truth), `hyprctl reload`-verified, and listed
  in `docs/keybinds.md`. Zen kept as a dedicated key — google-chrome-stable stays the
  `$browser` on `Super+W`.
- **2026-05-29 — new Learn page: System maintenance & upgrades.** Documentation-only.
  User (ex-Ubuntu) asked how rolling-release upgrades interact with the system's pins
  (NVIDIA 580, PipeWire 1.6.5) and whether routine `-Syu` would break Isaac/the
  controller. Wrote `docs/learn/11-system-maintenance.md` explaining: frequent full
  upgrades are the *safe* path (not the risk); the partial-upgrade cardinal sin
  (`-Sy` without `-u`); how `IgnorePkg` makes the pins persist automatically and how
  pacman refuses to build a broken dep graph; the real long-term pin risk (580 is DKMS,
  so a future kernel series could fail its module build — boot linux-lts to delay this,
  loud failure not silent); recovery nets (two kernels via Limine, pacman cache +
  `downgrade`, keyring refresh); and the weekly update ritual. Added to `mkdocs.yml`
  nav as item 11 and linked from page 10's footer. No script/config changes.
- **2026-05-30 — second desktop monitor (Acer VG240YS) wired into the desktop
  profile.** User has an Acer VG240YS (1080p/165, IPS, 8-bit) used occasionally
  in portrait, to the right of the LG ultrawide, on the second DP port of the
  RTX 3060. Added one rule to `hypr-monitors-desktop.conf` (live) and the
  matching block in `setup-home.sh` do_hyprland generator:
  `monitor = DP-2, 1920x1080@165, 3440x0, 1, transform, 3, bitdepth, 10, vrr, 0`.
  Kept active full-time — a monitor rule is inert until that output appears, so
  it costs nothing when the Acer is unplugged and gives true plug-and-play
  portrait/placement when it is. Rotation defaulted to `transform, 3` (90° CCW)
  since user didn't know which way the stand pivots; flip to `transform, 1` and
  `hyprctl reload` if it comes up wrong. `bitdepth, 10` requested but the panel
  is natively 8-bit (16.7M colours) so the GPU dithers — true 10-bit stays the
  LG's privilege. Connector assumed DP-2; if it lands elsewhere, swap the name
  (or `desc:` match). Laptop profile untouched. Docs: `display.md` host table
  gained an "optional desktop" row and the desktop-config block explains all
  five caveats (placement, rotation, 8-bit panel, connector, inert-when-absent).
  `hyprctl reload` clean; ultrawide unaffected.
- **2026-05-30 — LeRobot install for real SO-arm 101, plus uv-env cleanup
  automation.** User tried the official HF LeRobot install with `uv pip install
  'lerobot[all]'` (and earlier with conda). Both failed identically while
  building **`egl-probe==1.0.2`**: `CMake Error … Compatibility with CMake < 3.5
  has been removed`. Root cause is **Arch shipping cmake 4.3.3**, which dropped
  policy compat for `cmake_minimum_required < 3.5`. Same crash in any package
  manager — the bug is the system cmake meeting a pre-2025 `CMakeLists.txt`.
  Fix is `CMAKE_POLICY_VERSION_MINIMUM=3.5`. Also: the `[all]` extra drags in
  `hf-libero` → `robomimic` → `egl-probe` (LIBERO sim benchmark — irrelevant for
  real hardware), so the recommended install for SO-arm 101 work is
  `lerobot[feetech]` (Feetech STS3215 servo SDK), optionally adding
  `smolvla`/`pyav` extras.
  - **`setup-home.sh lerobot`** new component: creates conda env (defaults:
    `lerobot`, Python 3.10, `lerobot[feetech]`), writes
    `etc/conda/activate.d/cmake_policy.sh` to export the cmake env var so
    *every* future `pip install` in the env inherits the fix, then runs the
    install. Overrides: `LEROBOT_ENV` / `LEROBOT_EXTRAS` / `LEROBOT_PY`. Prints
    SO-arm 101 next-steps (uucp group for `/dev/ttyACM*` access, port check,
    sanity-import).
  - **`uninstall.sh uv`** new component: clears the user's primary venv
    (`~/.venv`), uv build cache (`~/.cache/uv` via `uv cache clean` for proper
    reclaim), and uv-managed Pythons (`uv python uninstall --all` + leftover
    `~/.local/share/uv`, plus the `~/.local/bin/python3.12` shim). Leaves the
    pacman `uv` binary alone (free disk-wise; user removes via `pacman -Rns uv`).
  - **`uninstall.sh lerobot`** new component: `conda env remove -y -n
    "$LEROBOT_ENV"` (default `lerobot`), tally-counted. Anaconda itself stays.
  - **Live cleanup executed:** reclaimed **14.8 GB** from the failed-uv attempt
    (6.9 G venv + 7.6 GiB cache + 106 MB uv-managed CPython 3.12).
  - Docs: `learn/07-dev-environment.md` gained Gotcha 5 (Arch cmake-4 vs old
    `CMakeLists.txt` — affects ANY legacy wheel, not just LeRobot), Gotcha 6
    (skip `[all]` for real-hardware work), and a "LeRobot for the SO-arm 101"
    section with the script invocations + uucp/serial-port next-steps table.
    The LeRobot install was **not auto-run** during this change — user invokes
    `./setup-home.sh lerobot` when ready (heavy PyTorch download).
- **2026-05-30 — LeRobot install made clone-aware (editable from ~/lerobot
  preferred).** User pointed out they had an HF LeRobot clone at `~/lerobot`
  (260 MB, recent commit `b8ad81bf`) and asked whether to keep it. The official
  docs offer two install paths (PyPI wheel vs `pip install -e .` from a clone);
  for real-hardware SO-arm 101 work the editable path is the right one because
  `examples/`, `scripts/`, and `src/lerobot/scripts/` (calibration / teleop /
  dataset-record entry points the HF docs reference) only exist *in the clone*,
  not the wheel — and `git pull` keeps the install current with no reinstall.
  - `do_lerobot()` in setup-home.sh is now **clone-aware**: if
    `$LEROBOT_DIR` (default `~/lerobot`) contains a `pyproject.toml`, it runs
    `pip install -e "$dir[$extras]"`; otherwise falls back to
    `pip install "lerobot[$extras]"`. Says/dry-run messages reflect the chosen
    mode; finished output prints the clone path + the `git pull` upstream-tracking
    recipe.
  - `do_lerobot()` in uninstall.sh **does NOT delete the clone** (it's user
    data — branches, calibration files, recorded datasets). Prints its size +
    a manual `rm -rf` hint instead. The `LEROBOT_DIR` env var honoured here too.
  - Docs: learn/07-dev-environment.md gained an "Editable clone vs PyPI" table
    and an explicit `git clone …/lerobot.git ~/lerobot` quick-start; the
    "After it finishes" checklist gained `cd ~/lerobot && git pull` as the
    update path. Gotcha 6 footer points readers at the editable section.
  - Memory `project-lerobot-soarm-101-install` updated to reflect editable as
    the default and `LEROBOT_DIR` as the override.
- **2026-05-30 — symmetric LeRobot clone lifecycle: install clones, uninstall
  removes.** User asked for the `git clone` to be part of the install (so they
  can A/B-test editable vs PyPI on a fresh setup), planning to delete the
  current `~/lerobot` manually before re-running. Asked uninstall to also
  remove the clone — install/uninstall symmetry.
  - `setup-home.sh do_lerobot()` source-mode resolution now: (1) clone present
    with `pyproject.toml` → editable from it; (2) clone path exists but isn't
    LeRobot → PyPI (refuse to overwrite); (3) `LEROBOT_NO_CLONE=1` → PyPI
    (explicit opt-out, e.g. for A/B testing the wheel); (4) otherwise →
    `git clone $LEROBOT_REPO $LEROBOT_DIR` then editable. New env var
    `LEROBOT_REPO` (default `https://github.com/huggingface/lerobot.git`)
    lets users point at a fork/mirror. A partial-clone failure cleans up the
    half-cloned dir before PyPI fallback, so re-runs are safe.
  - `uninstall.sh do_lerobot()` now removes the clone too (via `reclaim` so it
    counts toward the tally), with two safeties: (a) **dirty-tree abort** —
    if `git status --porcelain` in the clone is non-empty, the clone removal
    is SKIPPED and the dirty-file count is printed (env env still removed);
    (b) **`LEROBOT_KEEP_CLONE=1`** explicit opt-out skips clone removal even
    when the tree is clean. The component row in COMPONENTS updated to mention
    both clone deletion and the keep-clone override.
  - Docs `learn/07-dev-environment.md`: "Editable clone vs PyPI" section
    rewritten with the four-rule source-mode order + `LEROBOT_NO_CLONE` and
    `LEROBOT_REPO` examples; new "Cleanup" subsection explains the dirty-tree
    abort + `LEROBOT_KEEP_CLONE` opt-out + the `LEROBOT_DIR` symmetry between
    install and uninstall.
  - Dry-run verified: clone-fresh path prints `[dry-run] git clone …`; the
    `LEROBOT_NO_CLONE=1` path skips it; the existing-clone path detects
    pyproject.toml and uses editable without re-cloning.
- **2026-05-30 — LeRobot Python default bumped 3.10 → 3.12 (upstream
  requires-python bump) + fail-fast on pip errors.** First live run of
  `./setup-home.sh lerobot` hit `ERROR: Package 'lerobot' requires a different
  Python: 3.10.20 not in '>=3.12'` — upstream LeRobot's `pyproject.toml` was
  updated to `requires-python = ">=3.12"` (commit b8ad81bf-era), but the
  component defaulted to 3.10. The script SILENTLY continued past the failure
  and printed the success banner — fixed both:
  - Default `LEROBOT_PY` is now **3.12**. Override (e.g. for pinning to an
    older lerobot release that still accepts 3.10/3.11) still works.
  - `pip install` is now wrapped in an `if ! pip install …; then …; return 1; fi`
    block: on failure, the component deactivates the env, prints a focused
    diagnostic (likely causes + the exact recovery commands
    `LEROBOT_KEEP_CLONE=1 ./uninstall.sh lerobot && ./setup-home.sh lerobot`),
    and exits non-zero — no more bogus "done." after a failed install.
  - **Live verification done:** removed the broken env via
    `LEROBOT_KEEP_CLONE=1 ./uninstall.sh lerobot` (reclaimed 196 MB, clone
    preserved), re-ran `./setup-home.sh lerobot`, install succeeded with
    `lerobot 0.5.2`, `torch 2.11.0+cu130` (CUDA True), `feetech-servo-sdk
    1.0.0` (note: import name is `scservo_sdk`, not `feetech_servo_sdk` —
    legacy Feetech SDK module identity). Editable confirmed: `lerobot.__file__`
    points at `/home/gamingsoul03/lerobot/src/lerobot`.
  - Docs `learn/07-dev-environment.md`: "Python 3.10" → "Python 3.12"; example
    override changed from `LEROBOT_PY=3.11` to `LEROBOT_PY=3.13`; intro
    paragraph notes the upstream `>=3.12` constraint with the "pin lower only
    if you've also pinned an older lerobot release" caveat. Memory updated.
- **2026-05-30 — `setup-home.sh lerobot` checklist detects existing `uucp`
  membership.** Confirmed user is already in `uucp` (along with lock,
  wireshark, docker) — `install.sh groups` had run during the original setup,
  so the post-install printout's unconditional "run `sudo usermod -aG uucp`"
  was wrong (would either add a no-op duplicate or worry users about a step
  they'd already completed). do_lerobot's printed step #2 now inspects
  `id -nG`: if `uucp` is present, prints "✓ already in 'uucp' group — nothing
  to do"; otherwise prints both `./install.sh groups` (canonical — also adds
  lock + wireshark for embedded/wireshark workflows) and the standalone
  `sudo usermod -aG uucp "$USER"` one-liner. Docs updated to point at
  `install.sh groups` as the canonical path. No live changes (user already
  configured); installation declared complete — just plug in the SO-arm.
- **2026-05-30 — `lerobot-verify` helper + `dataset` extra in defaults.** User
  asked how to verify the install without the robot plugged in. Confirmed
  install is correct, but found two issues:
  - **`lerobot[feetech]` alone misses `datasets` package** — `lerobot.datasets`
    submodules fail to import; the upstream pyproject splits it into the
    `[dataset]` extra (`datasets>=4.7,<5`, pandas, pyarrow). For real-hardware
    SO-arm 101 work this is *required* (record demos = create LeRobot datasets).
    Default extras bumped from `feetech` → `feetech,dataset`. As a free bonus,
    `[dataset]` transitively pulls **`torchcodec` + `av` (PyAV)**, so dataset
    video encoding works without a separate `pyav` extra. Installed live
    (`pip install -e "~/lerobot[dataset]"` — datasets 4.8.5, pandas 2.3.3,
    pyarrow 24.0.0, av 15.1.0, plus torchcodec).
  - **Module-name mismatches in my first verification attempt.** `scservo_sdk`,
    not `feetech_servo_sdk` (legacy import name kept after the package rename).
    `lerobot.robots.so_follower` / `lerobot.teleoperators.so_leader`, not
    `so100_follower` / `so101_follower` — SO-100 and SO-101 use identical
    Feetech STS3215 servos and mechanics, so they share one wrapper (confirmed
    by `so100.md` and `so101.md` both living inside `so_follower/`).
  - **`~/.local/bin/lerobot-verify`** — new helper added to `setup-home.sh`
    `do_scripts` (so `./setup-home.sh scripts` installs it). 9-section check
    (env / cmake hook / lerobot editable mode / torch+CUDA / scservo_sdk /
    SO-100/101 wrappers / HF dataset stack / OpenCV / CLI entry points), clear
    PASS/FAIL banner, exits non-zero on any miss (CI-friendly). Honors
    `LEROBOT_ENV` (matches install component). The `lerobot` install component
    **calls it automatically** at the end of a successful install — fresh
    installs end with a green report.
  - **Live verification:** all 9 sections PASS (python 3.12.13, hook +
    CMAKE_POLICY_VERSION_MINIMUM=3.5, lerobot 0.5.2 editable, torch 2.11.0+cu130
    + RTX 3060 sm_86, scservo_sdk + 4 classes, all SO-arm 100/101 modules,
    datasets 4.8.5 + pandas + pyarrow + av, opencv 4.13.0 headless, 7 CLI
    entry points). Install is END-TO-END READY for SO-arm 101 work.
  - Docs `learn/07-dev-environment.md`: new "Verifying the install without the
    robot" subsection enumerates the 9 checks; intro paragraph updated to
    `[feetech,dataset]` defaults with the torchcodec/av bonus noted; "add more
    extras later" example updated to `[feetech,dataset,smolvla]`.
- **2026-05-30 — default extras bumped feetech,dataset → feetech,core_scripts
  (adds rerun + pynput).** User asked whether `rerun` was in the install.
  Found that `rerun-sdk` is in upstream's `viz` extra, NOT in `dataset` —
  but upstream defines a composite `core_scripts = [dataset, hardware, viz]`
  whose pyproject.toml docstring explicitly says it "maps to the CLI scripts"
  (`lerobot-record`, `lerobot-replay`, `lerobot-calibrate`,
  `lerobot-teleoperate`). That's the right umbrella for hands-on SO-arm 101
  work, so the default `LEROBOT_EXTRAS` is now **`feetech,core_scripts`**.
  This pulls (on top of dataset's HF datasets/pandas/pyarrow/torchcodec/av):
  `pynput` (keyboard teleop), `pyserial`+`deepdiff` (already there via
  feetech), and **`rerun-sdk`** (LeRobot's standard live-visualization viewer).
  - Installed live: `pip install -e "~/lerobot[core_scripts]"` →
    rerun-sdk 0.26.2, pynput 1.8.2, evdev 1.9.3, python-xlib 0.33.
  - `lerobot-verify` helper gained Section 7b (CLI-script extras): checks
    `rerun` and `pynput`. The verifier's version-reading helper switched to
    `importlib.metadata.version(...)` because `pynput` doesn't expose
    `__version__` on its top-level module — a future-proof fix for any pkg
    that follows the same pattern.
  - Live re-verify: full PASS, including the new 7b section.
  - Docs `learn/07-dev-environment.md`: intro paragraph rewritten with a
    sub-extras breakdown table (dataset/hardware/viz with what each adds and
    why); "add more extras later" example bumped to
    `[feetech,core_scripts,smolvla]`; the verify list gains row 7b.
- **2026-05-30 — `install.sh monitor` component: HWiNFO-equivalent stack.**
  User asked for an HWiNFO GUI on Arch. Audited what's already present:
  mission-center-git, nvtop, btop, lm_sensors (+ lib32), nvidia-settings —
  all installed ad-hoc, none scripted. Found psensor and hardinfo2 BOTH in
  official `extra` (no AUR needed), confirmed sensors already returns data
  from the NCT6798 motherboard chip (auto-loaded by the kernel).
  - **New `install.sh monitor` component** consolidates all six: psensor
    (live sensor history graphs — user's stated preference; the closest match
    to HWiNFO's sensor-history window), hardinfo2 (single best HWiNFO analogue —
    hardware inventory + Sensors tab + benchmarks), mission-center (Task-Mgr
    GUI; already bound to Super+Shift+P), nvtop (live GPU TUI — what
    nvidia-smi can't show per-process), btop (modern CLI viewer), lm_sensors
    + lib32-lm_sensors (kernel sensor framework). `nvidia-settings` stays
    in the `gpu` component because it tracks the NVIDIA driver. mission-center
    in `extra` (stable 1.1.x) provides the same binary as the AUR
    `mission-center-git`, so on systems with the git build pacman --needed
    silently skips the repo one — both serve Super+Shift+P.
  - Docs `reference.md`: new §6.10 "System monitoring (HWiNFO-equivalent
    stack)" with a launch table + the one-time `sensors-detect` recipe (only
    needed if `sensors` shows no chips; on this box NCT6798 is auto-loaded).
  - Project-context component list updated to include `monitor`.
  - **Live install:** user runs `./install.sh monitor` (I can't sudo per the
    standing rule). On this machine only psensor + hardinfo2 are missing —
    the other five are already in place. `pac --needed` skips them.
- **2026-05-30 — `monitor` component: handle mission-center hard-conflict with
  AUR `mission-center-git`.** First live run of `./install.sh monitor` aborted:
  pacman flagged the repo `mission-center 1.1.0-1` as in-conflict with the
  installed AUR `mission-center-git 1.1.0.r108`, and under `--needed
  --noconfirm` it refuses to swap and bails on the *entire* transaction —
  taking `psensor` and `hardinfo2` down with it (so the user's machine ended
  up with NEITHER GUI installed). My prior claim that "pacman silently skips
  the conflicting package" was wrong; under --noconfirm the conflict is fatal.
  - **Fix:** `do_monitor()` now queries `pacman -Qq mission-center{,_git}` and
    **omits the repo mission-center from the install set if either variant is
    already present**, printing "· mission-center already provided (skipping
    the repo build to avoid the AUR git conflict)". Either variant covers
    Super+Shift+P, so it's a no-op semantically.
  - Reference.md note about mission-center rewritten with the real behaviour
    (hard conflict, deliberate skip, why).
  - Dry-run verified on this machine: skip line printed; install set becomes
    `psensor hardinfo2 nvtop btop lm_sensors lib32-lm_sensors`.
  - **User re-runs `./install.sh monitor`** to actually install psensor +
    hardinfo2 (the other four are already there and `--needed` skips them).
- **2026-05-31 — `psensor` + `hardinfo2` live-installed; `kdiskmark` folded
  into the `storage` component.** User confirmed the re-run of
  `./install.sh monitor` succeeded — both GUIs now present (closing out the
  prior session's outstanding item). Separately, they installed `kdiskmark`
  ad-hoc (`extra` repo, Qt6 GUI for sequential/random disk read+write
  throughput + IOPS, drives `fio` under the hood — the CrystalDiskMark
  equivalent) and asked to add it to the installer so a future fresh
  rebuild picks it up automatically.
  - Placed in the **`storage`** component (not `monitor`) — it's disk-specific
    and pairs naturally with gnome-disks' own Benchmark dialog, while
    `monitor` is for *live* system status (sensors, processes, GPU). Same
    rationale as keeping `nvidia-settings` in `gpu` rather than `monitor`:
    fit by *subject*, not by *kind of tool*.
  - `do_storage()` now installs `ntfs-3g exfatprogs gnome-disk-utility
    kdiskmark`; component description and the post-install hint line both
    updated. Reference.md §9.3 ("Disk free space / partitions") picked up a
    bullet for kdiskmark + a note that gnome-disks has its own quick
    benchmark dialog if you don't want to leave the partition view.
  - No memory file added — small package add with no surprising lesson; this
    history entry is the durable record.
- **2026-05-31 — fastfetch custom-image/GIF/video logo via the
  fastfetch-logo helper.** User wanted to replace fastfetch's OS ASCII
  logo with a real image (Sukuna lofi wallpaper at the time), and
  ultimately a flexible system for swapping in any image, animated GIF,
  or video later. Long debugging arc (transcript captures the journey;
  this entry is the summary):
  - **fastfetch's own image protocols are quirky on Arch.** The repo
    `fastfetch-git` build's `--list-features` does NOT include `sixel` —
    the sixel rendering goes through `imagemagick7` instead, and that
    coder *crop-fills* the source rather than preserving aspect, slicing
    the top half off any 16:9 image. `type: chafa` works once
    `pacman -S chafa` provides `libchafa.so` (silent ASCII fallback if
    not), but it's character-cell block-art, intrinsically pixelated.
  - **Working architecture**: pre-render with the chafa **CLI** (which
    preserves aspect properly), point fastfetch at the file with
    `type: raw` so it streams the bytes verbatim. Bypasses the
    imagemagick coder entirely. Output = native sixel, foot draws it
    pixel-perfect.
  - **Foot row-clear bug discovered**: with `position: left` (logo and
    modules in parallel rows), foot wipes sixel pixels on any cell-row
    where text is subsequently printed — even when text is in different
    columns. Result: only the rows below where modules end survived
    (the desk/hands strip — head + torso clipped). Fix: `position: top`
    puts the image on its own rows where nothing else writes.
    [[project-fastfetch-sixel-foot-quirks]] captures this so we don't
    re-discover it.
  - **chafa size ≠ foot cells.** chafa internally assumes ~10×20 px
    cells; foot at JetBrains Mono 12pt is ~8×17. So chafa
    `--size=70x18` (claims 18 rows) actually renders into ~21 foot
    rows. The helper scales fastfetch's JSON `width`/`height` up by
    ~1.2× to reserve the real footprint.
  - **Helper script** `~/.local/bin/fastfetch-logo` (deployed by
    `setup-home.sh scripts`): auto-detects image vs GIF vs video,
    extracts a frame via `ffmpeg -ss T -vframes 1` for the latter two,
    pre-renders to `~/.config/fastfetch/logo.sixel` via chafa, edits
    `config.jsonc` via `jq`. Flags: `--size`, `--frame`, `--position`,
    `--animate` (GIF/video: wires a `chafa --animate=on` line into
    `fish_greeting.fish` for shell-startup playback; default 3 s
    duration; `--none` reverts everything including the fish_greeting
    hook).
  - **New `setup-home.sh fastfetch` component**: interactive prompt
    that asks for a media path (empty = keep current, `none` = revert),
    offers `--animate` for GIF/video, and forwards to the helper. Lets
    a clean rebuild swap the logo with a single answered prompt.
  - **install.sh**: `chafa` added to the `terminal` component
    (alongside fzf/rg/bat/...) since it's a generic CLI image tool and
    chafa is the missing piece without which the helper silently falls
    back to ASCII. `ffmpeg` added to the `media` component (was a
    transitive dep already via haruna/obs/gimp but now explicit) so
    GIF/video frame extraction works on a fresh box.
  - **uninstall.sh**: new `fastfetch` component calls
    `fastfetch-logo --none` (which knows to clear sixel + animation
    hook + jq the config back to `null`); falls back to a manual sweep
    if the helper is missing.
  - **Docs**: `reference.md` §6.11 (command table + quick recipe);
    `learn/12-fastfetch-logo.md` (full walkthrough of the protocol
    matrix, the cell-size math, the foot row-clear bug, why
    `type: raw` instead of `type: sixel`); `mkdocs.yml` nav updated.
  - **Live migration done**: the existing `sukuna.sixel` (set
    manually during the debugging arc) was re-rendered via the helper
    to `logo.sixel`; orphan file removed; config now references the
    helper-managed path. User's current setup unchanged visually.

- **2026-06-02 — iPad as graphic tablet via Weylus Community Edition.**
  User wanted to use an iPad as a writing pad. Tried the AUR `weylus`
  source build first — it failed at compile time on `syntex_pos 0.42`:
  modern rustc removed the `RustcEncodable`/`Decodable` derive macros
  that 2022-era crate used. Upstream H-M-H/Weylus is unmaintained
  (last release 0.11.4, Oct 2022). Switched to the community fork
  [electronstudio/WeylusCommunityEdition](https://github.com/electronstudio/WeylusCommunityEdition),
  shipped via the prebuilt `weylus-community-bin` AUR package — fresh
  May 2026 release, no Rust build path, conflicts with the legacy
  variants so the AUR helper handles the swap.
  - **New `install.sh tablet` component**: installs
    `weylus-community-bin` + `gst-plugin-pipewire` (the optdepend that
    enables xdg-desktop-portal screencast capture on Wayland — without
    it Hyprland gives a black frame), creates the `uinput` group +
    udev rule (`/etc/udev/rules.d/60-weylus-uinput.rules` with
    `static_node=uinput` so the node exists before lazy modprobe) +
    `/etc/modules-load.d/uinput.conf`, adds the user to the group,
    reloads udev. Needs a logout/login for the group to take effect.
  - **Why `gst-plugin-pipewire` is on the package list explicitly**:
    it's only an optdepend of the package, so a clean box without the
    `audio` component (which pulls it transitively via the PipeWire
    stack) would silently miss it. Then the portal hands GStreamer a
    PipeWire stream that has no decoder → black tablet screen.
  - **uinput plumbing rationale**: Weylus writes pointer/keystroke
    events to `/dev/uinput`, root-only by default. The udev rule makes
    the node group-readable to `uinput` mode 0660; the static_node
    trick creates the device up-front so Weylus doesn't race against
    the kernel module's lazy autoload. The modules-load file pins the
    module so it's there at boot even if nothing else asked for it.
  - **`uninstall.sh tablet`**: removes the package, the udev rule, the
    modules-load file, drops the user from the `uinput` group, removes
    the group if it ends up empty, and clears `~/.local/share/weylus`
    + `~/.config/weylus`. Leaves `gst-plugin-pipewire` alone (cheap
    and shared with audio/screen recording).
  - **Docs**: `reference.md` §6.12 (command table + ports + portal
    chain debug recipe); `learn/13-weylus-tablet.md` (full walkthrough
    — why the community fork, uinput plumbing explained, Wayland-vs-X11
    capture, pen-pressure matrix per browser, latency tuning); nav
    entry in `mkdocs.yml`. Memory: `project-weylus-tablet.md`.

- **2026-06-05 — Virtual machines: QEMU/KVM + virt-manager (`vm`
  component).** User wants to learn/build Gentoo and Linux From Scratch
  in VMs and chose the QEMU + virt-manager stack for performance +
  features. Added an **on-demand** `vm` component (deliberately *not*
  a mandatory app — install when wanted, `uninstall.sh vm` to reclaim
  the disk).
  - **New `install.sh vm` component**: installs `qemu-full` (full
    emulator + all backends + every guest arch, not just x86_64),
    `libvirt`, `virt-manager`, `virt-viewer`, `edk2-ovmf` (UEFI/Secure
    Boot for guests), `swtpm` (TPM 2.0 for Win11 guests), `dnsmasq`
    (default NAT net), `dmidecode`, and `libguestfs` (host-side disk
    image tools) — all from the official `extra` repo, so always the
    newest rolling release ("latest and greatest" with no AUR build).
    Then: `usermod -aG libvirt,kvm`; sets `unix_sock_group="libvirt"`
    + `unix_sock_rw_perms="0770"` in `/etc/libvirt/libvirtd.conf`;
    `systemctl enable --now libvirtd.service`; defines (if needed) +
    autostarts + starts the default NAT network; writes
    `/etc/modprobe.d/kvm-nested.conf` with the vendor-detected option
    (`kvm_intel`/`kvm_amd nested=1`) for nested virtualization.
  - **Why it works on both kernels with nothing extra**: KVM lives in
    the kernel — `kvm` + `kvm_intel`/`kvm_amd` + `vhost` are in-tree on
    *both* `linux` and `linux-lts`. No DKMS, no per-kernel rebuild
    (contrast the NVIDIA stack). The only kernel-touching file the
    component writes is the nested-virt modprobe drop-in, read by
    whichever kernel boots. So a single install covers both.
  - **`uninstall.sh vm`**: BEFORE stopping anything it queries libvirt
    (`virsh pool-list` → `vol-list` per pool, while the daemon is still
    up) to find **guest disks in EVERY pool — including custom pools on
    `/home`** (e.g. a `gentoo` pool at `~/Documents/linux-iso/gentoo`),
    not just the default. Then stops the default network + the libvirt
    daemons, `-Rns` the whole stack (qemu-full + sub-packages + spice
    via cascade, edk2-ovmf/swtpm/libguestfs/virt-viewer; dnsmasq +
    dmidecode best-effort), **deletes all guest disk images + storage
    pools under `/var/lib/libvirt`** (the default-pool space hogs), and
    **reclaims any disk images found OUTSIDE `/var/lib/libvirt`** as
    individual files (so a disk orphaned by forgetting virt-manager's
    "Delete associated storage" is still freed). Safety: it removes only
    real disk images (`.qcow2/.raw/.img/.qed/.vmdk/.vdi/.vhd/.qcow`);
    **ISOs and any other files in a directory-type pool are left in place
    and their paths printed** for manual deletion, and a custom pool's
    directory is only `rmdir`'d if it ends up empty. Also clears
    `/etc/libvirt` (pool definitions), per-user virt-manager state
    (`~/.config/libvirt`, `~/.local/share/libvirt`, `~/.cache/libvirt`),
    the nested-virt drop-in, and drops the `libvirt`/`kvm` group
    memberships. Leaves the groups themselves (`kvm` is a system group
    other tooling uses) and the in-tree kernel modules.
  - **Docs**: `reference.md` §6.13 (package table + config summary +
    verify/revert recipes); `learn/14-virtual-machines.md` (full
    walkthrough — KVM vs emulation, why virt-manager, a first
    Gentoo/LFS guest, virtio/hugepages/CPU-pinning perf, nested virt);
    nav entry in `mkdocs.yml`. Memory: `project-qemu-virt-manager.md`.

- **2026-06-05 — Rolling-release self-heal + `health` doctor component.**
  Installing the `vm` component surfaced a latent breakage: the mandatory
  `pacman -Syu` install.sh runs first had rolled the mainline `linux` kernel
  to 7.0.11, but `linux-headers` was **not installed**, so the NVIDIA 580
  DKMS module couldn't build for it and `mkinitcpio` baked a module-less
  `arch-linux.efi` (`==> ERROR: module not found: 'nvidia'`). linux-lts
  (6.18.34) stayed fine (its headers + DKMS built). User asked to make the
  scripts robust so a system-wide upgrade can't break things and so re-running
  them auto-resolves issues.
  - **Hardened the mandatory prereqs** (so EVERY install.sh run self-heals):
    (1) `archlinux-keyring` pulled at the front of the upgrade (expired-key
    safety); (2) new `kernel_headers_pkgs()` enumerates installed kernels via
    `/usr/lib/modules/*/pkgbase` and folds each one's `-headers` into the SAME
    `-Syu` — but only repo-installable targets, so a custom/AUR kernel can't
    abort the txn with "target not found"; (3) always full `-Syu`, never `-Sy`.
  - **`heal_dkms_initramfs()`** runs after the upgrade: `dkms autoinstall -k`
    per installed kernel that has headers, `mkinitcpio -P` if the DKMS set
    changed, then verifies every kernel has its module. If one genuinely can't
    build (pinned driver too old for a too-new kernel) it adds a FAILED tag and
    prints the real options (boot the built kernel / `nvidia-switch.sh latest`
    / remove the unused kernel) — never a silent landmine. `installed_kernels()`
    skips pkgbase files not owned by a package, so a stale running-kernel module
    dir doesn't cause false positives.
  - **New `health` component**: standalone doctor — the same auto-repair plus a
    read-only report (kernel↔headers↔DKMS matrix, `pacman -Qtdq` orphans,
    `systemctl --failed`, `pacdiff -o` `.pacnew` files, active `IgnorePkg`
    pins). `bash install.sh health` = "fix what you can, tell me what you can't".
  - **Effect on the reported breakage**: re-running install.sh now installs
    `linux-headers` in-transaction → DKMS rebuilds NVIDIA for 7.0.11 (if 580
    supports it) → UKI regenerated; if 580 can't compile against 7.0 the heal
    flags it with options. linux-lts remains the healthy daily kernel.
  - **Docs**: `reference.md` §6.14; `learn/11-system-maintenance.md` (new
    "Letting the scripts do it for you" section + headers/DKMS split in the
    pinning-risk discussion + kernel versions refreshed); install.sh component
    map above. Memory: `feedback-rolling-release-self-heal.md`.

- **2026-06-05 — Sweet icon theme made persistent (system dconf lock).**
  After the day's big `-Syu`+reboot the user's Sweet-Purple nautilus icons had
  reverted to Papirus-Dark: the packages + all `Sweet-*` themes were still
  installed, but the **`gsettings` icon-theme had been reset to Papirus-Dark**
  (caelestia's dep/default) while the GTK3/4 `settings.ini` still said
  Sweet-Purple — nautilus follows gsettings, so it showed the default.
  Re-applied immediately with `setup-home.sh --yes nautilus`, then baked in a
  durable fix.
  - **`install.sh theme` now writes a system dconf lock**: new helper
    `lock_icon_theme()` ensures `/etc/dconf/profile/user` lists `system-db:local`,
    writes `/etc/dconf/db/local.d/10-icon-theme` (`icon-theme='<variant>'`) and
    `…/locks/icon-theme`, then `dconf update`. A *locked* key can't be changed
    from the user session, so caelestia / a GTK update / a colour-scheme change
    can no longer reset it. Variant via `ICON_THEME` (default Sweet-Purple),
    same knob as setup-home.
  - **`uninstall.sh icons` removes the lock first** (else the locked key can't be
    reverted), then restores Papirus-Dark + strips the settings.ini lines.
  - **Disk-cleanup reality check**: the 12 unused Sweet colour variants are all
    one package (`sweet-folders-icons-git`, 2.27 MiB) that also provides
    Sweet-Purple — pacman can't split them, and the unused folders total ~3 MB.
    Declined to hand-delete package-owned files (would make `pacman -Qkk` report
    corruption) for negligible gain; the `theme` install is already the minimal
    two packages. (The 45 MB `Sweet-cursors` is the separate, in-use cursor theme.)
  - **Docs**: `project-context.md` component maps (theme/nautilus/icons) + this
    entry; `setup-home.sh` nautilus note points to `install.sh theme` for
    persistence. Memory: `project-gtk-libadwaita-theming.md` (reset-on-upgrade
    gotcha + the lock as the durable fix).

- **2026-06-06 — `uninstall.sh vm` now sweeps custom storage pools.** While
  setting up the first Gentoo guest the user keeps the VM disk in a **custom
  `gentoo` pool on `/home`** (`~/Documents/linux-iso/gentoo`), not the default
  `/var/lib/libvirt/images`. The old `uninstall.sh vm` only reclaimed
  `/var/lib/libvirt`, so a disk in that `/home` pool — e.g. one orphaned by
  forgetting to tick virt-manager's *"Delete associated storage"* — would have
  been left behind eating GBs. Fixed so a single `uninstall.sh vm` truly leaves
  nothing behind regardless of where disks were stored.
  - **How**: `do_vm()` now, **before** stopping the daemon, walks
    `virsh pool-list --all --name` → `virsh vol-list <pool>` for every pool and
    collects volume paths. After the existing `/var/lib/libvirt` sweep it
    `reclaim`s each collected disk that lives **outside** `/var/lib/libvirt`
    (those inside ride the sweep, so no double-count), then `rmdir`s the pool dir
    only if it became empty.
  - **Safety (important)**: a *directory*-type pool reports **every** file in its
    dir as a "volume" — including the user's `.iso` and stray files. So the sweep
    matches **only real disk-image extensions**
    (`.qcow2/.qcow/.raw/.img/.qed/.vmdk/.vdi/.vhd/.vhdx`); everything else is
    **left in place and its path printed** so the user can delete it by hand
    (`rm …/gentoo/*.iso`). Verified against the live setup: the Gentoo ISO and the
    empty `vm/` subdir were correctly classified as "skip", a future `.qcow2`
    would be reclaimed, and the pool dir (still holding the ISO) is preserved.
  - **Two cleanup paths documented**: (1) remove one VM but keep the stack →
    virt-manager *Delete* + tick "Delete associated storage"; (2) remove
    everything → `uninstall.sh vm`, which now also covers case (1)'s disk if you
    forgot. ISOs always survive both.
  - **Docs**: `reference.md` §6.13 revert recipe; `learn/14-virtual-machines.md`
    "Reverting / reclaiming disk" (new tip on the two cleanup paths + ISOs being
    spared); `project-context.md` uninstall map + this entry. Memory:
    `project-qemu-virt-manager.md`.

