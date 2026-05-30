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
  shell/dashboard tweaks — e.g. weather in °C via `services.useFahrenheit=false`),
  `nautilus` (sets a Sweet icon theme — synthwave **Sweet-Purple** folders +
  candy app icons — as the GTK icon theme; `ICON_THEME=<variant>` to pick another),
  `scripts`, `fish`, `wireplumber`, `git`. The **source of truth** for
  those files; edit & re-run.
- `install.sh` — components: `build`, `cuda`, `python`, `anaconda`, `node`,
  `editors`, `embedded`, `audio` (incl. the DualSense PipeWire 1.6.5 pin +
  touchpad udev rule), `gpu`, `docker` (Docker + NVIDIA Container Toolkit;
  data-root on /home/docker-data + containerd-snapshotter=false; for ROS 2 Humble /
  GPU containers), `media`, `terminal`, `kde`, `display`, `storage` (NTFS/exFAT
  userspace drivers + gnome-disk-utility so Windows-formatted SSDs mount in
  nautilus — Arch omits these by default, unlike Ubuntu), `remote` (enable `sshd`
  + freerdp/remmina for RDP/VNC *out* + `wayvnc` as a VNC server *into* this
  Hyprland box — RDP-into-Wayland is unsupported, VNC is the working path),
  `theme`
  (candy-icons + sweet-folders from the AUR — the rainbow GTK icon set),
  `aurapps`, `groups`, `shell`. CUDA is driver-matched.
- `uninstall.sh` — interactive, component-based **clean** uninstaller (the
  counterpart to `install.sh`): components `docker`, `isaac`, `ros2`, `anaconda`,
  `cuda`, `icons` (switch the GTK icon theme back to the caelestia default
  Papirus-Dark; keeps the Sweet/candy packages so `setup-home.sh nautilus`
  re-applies instantly), `inputremap` (remove input-remapper + its daemon + presets —
  no longer needed since the Razer mouse remaps via onboard memory), `extras`
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
  [§NVIDIA learn page](learn/05-nvidia.md#the-fix-switch-the-whole-nvidia-stack-to-the-validated-driver).

## File map (live system, not the repo)

| Thing | Path |
|---|---|
| caelestia upstream (never edit) | `~/.local/share/caelestia/` (and `~/.config/hypr` → symlink into it) |
| User Hyprland overrides | `~/.config/caelestia/hypr-user.conf`, `hypr-vars.conf` |
| Caelestia shell settings | `~/.config/caelestia/shell.json` (bar/dashboard/weather; written by the `caelestia` component) |
| Per-host monitors + active symlink | `~/.config/caelestia/hypr-monitors-{desktop,laptop}.conf`, `hypr-monitors.conf` |
| Scripts | `~/.local/bin/{select-monitors.sh, hdr-toggle, dualsense-audio, ros2-humble, vnc-server, remote}` |
| ROS 2 Fast DDS profile | `~/.config/ros2/fastdds-udp-only.xml` (UDP-only transport; written by the `ros2-humble` launcher) |
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
