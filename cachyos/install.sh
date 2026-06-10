#!/usr/bin/env bash
# ============================================================================
# install.sh — rebuilds the system-level half of the CachyOS + Hyprland + caelestia
# setup on a fresh minimal install (NVIDIA). Interactive + component-based,
# the mirror image of uninstall.sh.
#
# Run setup-home.sh FIRST (it writes the home-dir configs, no sudo). THIS script
# does the sudo-gated parts: packages (repo + AUR), driver-matched CUDA + cuDNN,
# CUDA PATH, audio apps, group membership, and the fish login shell. (CachyOS's
# stock PipeWire handles the DualSense controller, so no audio workaround here.)
#
#     bash ~/Documents/hyprland-rice/cachyos/setup-home.sh        # 1. home configs
#     bash ~/Documents/hyprland-rice/cachyos/install.sh           # 2. system, menu
#     bash ~/Documents/hyprland-rice/cachyos/install.sh cuda audio # just these
#     bash ~/Documents/hyprland-rice/cachyos/install.sh --yes all  # everything
#     bash ~/Documents/hyprland-rice/cachyos/install.sh --dry-run all  # preview
#
# Flags:
#   --dry-run   show what WOULD be installed/changed; touch nothing.
#   --yes / -y  skip the confirmation prompt.
#   all         select every component.
#
# Prereqs (DB refresh, git/base-devel/gh/ssh, an AUR helper) ALWAYS run first —
# they're needed by the other components and to push afterward.
#
# Run as your normal user (it calls sudo itself where needed).
# Safe to re-run: every step uses --needed / is idempotent.
# ============================================================================
set -uo pipefail

if [ "$(id -u)" -eq 0 ]; then
    echo "Run as your normal user, not root (the script calls sudo itself)." >&2
    exit 1
fi

USER_NAME="$(id -un)"
FAILED=()
HELPER=""   # AUR helper, resolved by ensure_aur_helper()
DRY_RUN=0
ASSUME_YES=0

say() { echo -e "$*"; }
hr()  { echo "------------------------------------------------------------"; }

pac() {  # install a group; record failure but keep going
    local group="$1"; shift
    if [ "$DRY_RUN" -eq 1 ]; then say "    [dry-run] pacman -S --needed $*"; return; fi
    echo -e "\n>>> pacman: $group"
    sudo pacman -S --needed --noconfirm "$@" || FAILED+=("pacman:$group")
}

# Make sure an AUR helper exists. A truly fresh minimal install has neither
# paru nor yay; bootstrap yay from the AUR (clone + makepkg) if needed.
ensure_aur_helper() {
    if command -v paru >/dev/null; then HELPER=paru; return; fi
    if command -v yay  >/dev/null; then HELPER=yay;  return; fi
    if [ "$DRY_RUN" -eq 1 ]; then say "    [dry-run] bootstrap yay from the AUR"; HELPER="yay"; return; fi
    echo -e "\n>>> No AUR helper found — bootstrapping yay"
    sudo pacman -S --needed --noconfirm git base-devel || true
    local tmp; tmp="$(mktemp -d)"
    if git clone https://aur.archlinux.org/yay-bin.git "$tmp/yay-bin" \
        && ( cd "$tmp/yay-bin" && makepkg -si --noconfirm ); then
        HELPER=yay
    else
        FAILED+=("yay-bootstrap")
    fi
    rm -rf "$tmp"
}

# Run an AUR install through whichever helper we have.
aur() {
    if [ "$DRY_RUN" -eq 1 ]; then say "    [dry-run] ${HELPER:-aur} -S --needed $*"; return 0; fi
    [ -n "$HELPER" ] || { FAILED+=("aur:no-helper"); return 1; }
    "$HELPER" -S --needed "$@"
}

# Make the GTK icon theme STICK across reboots, GTK upgrades, and caelestia
# colour-scheme regenerations. Symptom this fixes: the icon theme silently
# reverting to Papirus-Dark (caelestia's default) after an update — a plain
# `gsettings set` (what setup-home does) can be overwritten again by whatever
# re-asserts the default. We set a SYSTEM-level dconf default AND lock the key so
# nothing in the user session can change it back. Idempotent. Variant via $1.
lock_icon_theme() {
    local variant="${1:-Sweet-Purple}"
    say "\n### Persist the icon theme (system dconf lock → $variant)"
    if [ "$DRY_RUN" -eq 1 ]; then
        say "    [dry-run] ensure system-db:local in /etc/dconf/profile/user"
        say "    [dry-run] write /etc/dconf/db/local.d/10-icon-theme (icon-theme='$variant') + locks/icon-theme; dconf update"
        return
    fi
    if [ ! -d "/usr/share/icons/$variant" ]; then
        say "    !! icon theme '$variant' not installed yet — install candy-icons + sweet-folders first (this component)."
        FAILED+=("icon-lock:missing-theme"); return
    fi
    # dconf only consults the system db if the user profile lists it. Create/extend
    # the profile minimally (adding a low-priority system layer is safe; user
    # settings still win, except for keys we explicitly lock).
    if [ ! -f /etc/dconf/profile/user ]; then
        printf 'user-db:user\nsystem-db:local\n' | sudo tee /etc/dconf/profile/user >/dev/null \
            || FAILED+=("icon-lock:profile")
    elif ! grep -q '^system-db:local' /etc/dconf/profile/user; then
        echo 'system-db:local' | sudo tee -a /etc/dconf/profile/user >/dev/null \
            || FAILED+=("icon-lock:profile")
    fi
    sudo install -d /etc/dconf/db/local.d/locks || FAILED+=("icon-lock:dir")
    printf "[org/gnome/desktop/interface]\nicon-theme='%s'\n" "$variant" \
        | sudo tee /etc/dconf/db/local.d/10-icon-theme >/dev/null || FAILED+=("icon-lock:value")
    echo '/org/gnome/desktop/interface/icon-theme' \
        | sudo tee /etc/dconf/db/local.d/locks/icon-theme >/dev/null || FAILED+=("icon-lock:lock")
    sudo dconf update || FAILED+=("icon-lock:update")
    say "    · icon theme locked to $variant — survives reboots, GTK upgrades, and"
    say "      caelestia colour-scheme changes (it can no longer reset to Papirus-Dark)."
    say "    · change it later:  ICON_THEME=<variant> bash install.sh theme"
    say "    · undo the lock (revert to caelestia default):  bash uninstall.sh icons"
}

# Install Anaconda (AUR) and wire it into the fish login shell.
# Used for general ML/Python work. Idempotent: conda init is a no-op if the
# managed block already exists, and we never auto-activate base.
install_anaconda() {
    if [ ! -x /opt/anaconda/bin/conda ] && ! command -v conda >/dev/null; then
        echo -e "\n>>> Anaconda (AUR via ${HELPER:-none})"
        aur anaconda || { FAILED+=("anaconda"); return; }
    else
        echo ">>> Anaconda already present — skipping install."
    fi
    [ "$DRY_RUN" -eq 1 ] && { say "    [dry-run] conda init fish + disable auto_activate_base"; return; }
    local conda
    conda="$(command -v conda || echo /opt/anaconda/bin/conda)"
    [ -x "$conda" ] || { FAILED+=("anaconda:no-conda-bin"); return; }
    # `conda init fish` writes ~/.config/fish/conf.d/conda.fish (idempotent).
    "$conda" init fish || FAILED+=("conda init fish")
    # Don't drop every shell into (base); opt in with `conda activate`.
    "$conda" config --set auto_activate_base false || true
}

# Install CUDA + cuDNN matched to the installed NVIDIA driver.
# The repo `cuda` is rolling (always newest); a too-new toolkit needs a newer
# driver than you have. nvidia-smi's "CUDA Version" is the MAX CUDA the current
# driver supports. If the repo toolkit fits under that ceiling, install it;
# otherwise fall back to the AUR cuda-<major.minor> pinned to the driver.
install_cuda() {
    if ! command -v nvidia-smi >/dev/null; then
        echo ">>> No nvidia-smi (driver not loaded yet?) — skipping CUDA."
        FAILED+=("cuda:no-driver"); return
    fi
    local maxc repoc
    maxc=$(nvidia-smi | grep -oP 'CUDA( UMD)? Version:\s*\K[0-9]+\.[0-9]+' | head -1)
    repoc=$(pacman -Si cuda 2>/dev/null | awk -F': +' '/^Version/{print $2}' | grep -oP '^[0-9]+\.[0-9]+')
    echo ">>> Driver supports up to CUDA $maxc; repo cuda is $repoc."
    if [ -z "$maxc" ] || [ -z "$repoc" ]; then
        echo ">>> Could not determine versions — installing repo cuda/cudnn as-is."
        pac cuda cuda cudnn; return
    fi
    # repo fits if repoc <= maxc (lowest of the two sorted == repoc)
    if [ "$(printf '%s\n%s\n' "$repoc" "$maxc" | sort -V | head -1)" = "$repoc" ]; then
        echo ">>> Repo toolkit is within the driver ceiling — installing cuda + cudnn."
        pac cuda cuda cudnn
    else
        echo ">>> Repo cuda ($repoc) is newer than the driver supports ($maxc)."
        echo ">>> Trying the AUR toolkit pinned to your driver: cuda-$maxc"
        aur "cuda-$maxc" cudnn \
            || { echo ">>> No matching AUR cuda-$maxc. Either update the NVIDIA driver"
                 echo ">>> (sudo pacman -S nvidia/nvidia-open) then re-run, or install a"
                 echo ">>> CUDA <= $maxc manually."; FAILED+=("cuda:driver-too-old"); }
    fi
}

# ============================================================================
# Rolling-release resilience — keep out-of-tree DKMS modules (NVIDIA, VirtualBox,
# …) building across kernel upgrades so a `pacman -Syu` never leaves a kernel
# without its modules. That's the exact trap this box hit: the regular `linux`
# kernel rolled forward but its `linux-headers` weren't installed, so the NVIDIA
# DKMS build failed and mkinitcpio baked a module-less UKI → that kernel boots
# with no GPU driver. The functions below detect installed kernels, keep their
# headers in lockstep, rebuild DKMS, and regenerate the boot images — automatically.
# ============================================================================

# Emit "<kernelversion> <pkgbase>" for each installed kernel. Kernels are found
# the canonical way (each owns /usr/lib/modules/<ver>/pkgbase). We skip pkgbase
# files NOT owned by an installed package, so a stale/old running-kernel module
# dir left behind by an upgrade doesn't generate false "missing module" warnings.
installed_kernels() {
    local f
    for f in /usr/lib/modules/*/pkgbase; do
        [ -r "$f" ] || continue
        pacman -Qo "$f" >/dev/null 2>&1 || continue
        printf '%s %s\n' "$(basename "$(dirname "$f")")" "$(cat "$f")"
    done
}

# Echo the -headers package for every installed kernel, but ONLY when it's an
# installable target (in a repo, or already installed). This is deliberate: a
# custom/AUR kernel whose -headers isn't a repo package must NOT be folded into
# `pacman -Syu` or the whole upgrade aborts with "target not found".
kernel_headers_pkgs() {
    local kver base hdr
    while read -r kver base; do
        hdr="${base}-headers"
        if pacman -Qq "$hdr" >/dev/null 2>&1 || pacman -Si "$hdr" >/dev/null 2>&1; then
            printf '%s\n' "$hdr"
        fi
    done < <(installed_kernels) | sort -u
}

# After the big upgrade: make sure every DKMS module is built for every installed
# kernel and present in each boot image. Auto-repairs what it can (dkms
# autoinstall + a single mkinitcpio -P when something actually changed) and loudly
# flags what it can't (e.g. a pinned-old driver that won't compile against a
# brand-new kernel) with the concrete options — never silently leaving a landmine.
heal_dkms_initramfs() {
    if ! command -v dkms >/dev/null 2>&1; then
        say "    · no DKMS on this system — nothing to heal."; return
    fi
    if [ "$DRY_RUN" -eq 1 ]; then
        say "    [dry-run] dkms autoinstall per kernel; mkinitcpio -P if the module set changed; verify"
        return
    fi
    local before after kver base
    before=$(dkms status 2>/dev/null)
    # Build any modules still missing, per installed kernel that has headers.
    while read -r kver base; do
        if [ -d "/usr/lib/modules/$kver/build" ] || [ -e "/usr/lib/modules/$kver/build" ]; then
            say "    · dkms autoinstall -k $kver"
            sudo dkms autoinstall -k "$kver" 2>&1 | sed 's/^/      /' || true
        else
            say "    · $kver: no kernel headers present yet — skipping dkms build"
        fi
    done < <(installed_kernels)
    after=$(dkms status 2>/dev/null)

    # If autoinstall changed anything, the new module must land in the
    # initramfs/UKI — pacman's mkinitcpio hook only fires during package txns,
    # so regenerate here. (No-op-cheap when nothing changed.)
    if [ "$before" != "$after" ]; then
        say "    · DKMS set changed — regenerating initramfs/UKI for all presets"
        sudo mkinitcpio -P 2>&1 | sed 's/^/      /' || FAILED+=("mkinitcpio")
    fi

    # On stock CachyOS the NVIDIA module is the PREBUILT linux-cachyos*-nvidia-open
    # package, not a DKMS module — so dkms has nothing registered and the per-kernel
    # "is the module built?" check below must NOT fire (it would false-flag a
    # perfectly healthy prebuilt-module kernel). Only verify when dkms actually has
    # at least one module registered (true after nvidia-switch swaps in
    # nvidia-open-dkms, or for any other DKMS module like VirtualBox).
    if [ -z "$after" ]; then
        say "    · no DKMS modules registered — CachyOS prebuilt linux-cachyos*-nvidia-open"
        say "      handles the GPU per-kernel (pacman keeps it in lockstep). Nothing to verify."
        return
    fi

    # Verify: any installed kernel that has headers but STILL no DKMS module is a
    # genuine problem (usually: pinned driver too old for a too-new kernel).
    local still_missing=()
    while read -r kver base; do
        if [ -e "/usr/lib/modules/$kver/build" ] \
           && ! dkms status -k "$kver" 2>/dev/null | grep -q installed; then
            still_missing+=("$kver")
        fi
    done < <(installed_kernels)

    if [ "${#still_missing[@]}" -gt 0 ]; then
        FAILED+=("dkms-unbuilt:${still_missing[*]}")
        say ""
        say "    !! DKMS modules could NOT be built for kernel(s): ${still_missing[*]}"
        say "    !! Those kernels would boot WITHOUT the NVIDIA driver. This almost"
        say "    !! always means the pinned driver is too old for a brand-new kernel."
        say "    !! Pick one (none is done automatically — they change what boots):"
        say "    !!   • Just boot the kernel that IS built (after an nvidia-switch"
        say "    !!     downgrade this box runs 580 on linux-cachyos-lts, which stays"
        say "    !!     built & healthy; linux-cachyos 7.0 can't build 580), or"
        say "    !!   • Move the NVIDIA stack to a version that supports the new kernel:"
        say "    !!       bash ~/Documents/hyprland-rice/cachyos/nvidia-switch.sh latest"
        say "    !!   • If you never boot that kernel, remove it so the warning stops:"
        say "    !!       sudo pacman -Rns <kernel-package>   # e.g. linux-cachyos"
    else
        say "    · every installed kernel has its DKMS modules + initramfs ✓"
    fi
}

# ============================================================================
# Components — a row here + a matching do_<name>() teaches install.sh a new one.
# The menu and `all` are generated from this list; selected components run in
# THIS order (dependencies hold) regardless of how they were typed.
# ============================================================================
COMPONENTS=(
    "health|Rolling-release self-repair + doctor: sync each kernel's headers, rebuild DKMS modules (NVIDIA…) for every kernel + regenerate initramfs/UKI, report orphans/failed-units/.pacnew/held pins (this also runs automatically on every install.sh invocation)"
    "build|Compilers + build/debug tooling (clang, cmake, ninja, gdb, boost, eigen, ...)"
    "cuda|CUDA toolkit + cuDNN matched to your NVIDIA driver, and the CUDA PATH"
    "python|Python scientific stack (numpy/scipy/pandas/sklearn/jupyter/ruff/...)"
    "anaconda|Anaconda (AUR) wired into fish; base not auto-activated"
    "node|Node toolchain (node, pnpm, yarn)"
    "editors|Neovim"
    "embedded|Embedded/serial (picocom, minicom, arduino-cli, stlink, openocd, wireshark)"
    "audio|PipeWire audio apps (pavucontrol, easyeffects, alsa-utils) — no DualSense workaround needed on CachyOS"
    "gpu|GPU/gaming (lib32 nvidia, gamemode, mangohud, nvidia-settings)"
    "docker|Docker + NVIDIA Container Toolkit (data-root on /home; for ROS 2 Humble / GPU containers)"
    "vm|QEMU/KVM + virt-manager virtualization (libvirt, OVMF UEFI, swTPM, virt-viewer, guestfs) for Gentoo/LFS & other guest OSes; adds libvirt+kvm groups, default NAT net, nested virt — works on both linux-cachyos & linux-cachyos-lts"
    "media|Multimedia apps (haruna, obs, gimp, okular, gwenview, swayimg)"
    "terminal|Terminal productivity (fzf, ripgrep, fd, bat, zoxide, lazygit, tmux, ...)"
    "kde|KDE settings apps (systemsettings, discover, kinfocenter)"
    "display|Display inspection tools (drm-info, wdisplays, wlr-randr, brightnessctl)"
    "monitor|System monitoring — HWiNFO-style: psensor + hardinfo2 (GUIs), mission-center (Task Mgr equiv), nvtop, btop, lm_sensors"
    "storage|Mount Windows/other drives + Disks app + disk benchmark (ntfs-3g, exfatprogs, gnome-disk-utility, kdiskmark)"
    "remote|SSH + remote desktop: freerdp/remmina (out) + wayvnc (VNC in); sshd left OFF, toggle with the 'remote' helper"
    "tablet|Use an iPad/Android tablet as a graphic tablet / touchscreen via Weylus Community Edition (weylus-community-bin AUR + uinput group/udev/module setup)"
    "theme|Candy rainbow icons (AUR: candy-icons + sweet-folders) — GTK icon theme for nautilus etc."
    "aurapps|AUR apps (sweet-cursors, brave, edge, claude-desktop)"
    "groups|Add your user to the serial + wireshark groups (uucp, lock, wireshark)"
    "shell|Switch your login shell to fish"
)

# Standalone "doctor": the rolling-release self-repair (also run by the mandatory
# prereqs on every invocation) plus a read-only health report. `install.sh health`
# is the one-shot "something feels off after an update — fix what you can and tell
# me what you can't" entry point. Repairs are idempotent; reports never change anything.
do_health() {
    say "\n>>> System health check (rolling-release doctor)"

    say "\n### Kernels ↔ headers ↔ GPU module"
    # On CachyOS each kernel's NVIDIA module is normally the PREBUILT package
    # <pkgbase>-nvidia-open (e.g. linux-cachyos-lts-nvidia-open), kept in lockstep
    # by pacman — no DKMS build. After nvidia-switch downgrades to nvidia-open-dkms,
    # the module is built by DKMS instead. Report whichever applies, per kernel.
    local kver base hdr gpu
    while read -r kver base; do
        if pacman -Qq "${base}-headers" >/dev/null 2>&1; then hdr="headers ✓"; else hdr="headers MISSING"; fi
        if pacman -Qq "${base}-nvidia-open" >/dev/null 2>&1; then
            gpu="prebuilt nvidia-open ✓"
        elif command -v dkms >/dev/null 2>&1 && dkms status -k "$kver" 2>/dev/null | grep -q installed; then
            gpu="dkms nvidia ✓"
        elif command -v dkms >/dev/null 2>&1; then
            gpu="no GPU module built"
        else
            gpu="no prebuilt module, no dkms"
        fi
        say "    · $kver ($base): $hdr · $gpu"
    done < <(installed_kernels)

    # NB: the kernel-headers sync + dkms autoinstall + mkinitcpio repair already
    # ran in the mandatory prereqs immediately before this — we do NOT re-run it
    # here (that would rebuild + double the warnings). The matrix above reflects
    # the post-repair state; any unbuildable kernel was flagged up in that step.
    say "\n### DKMS + initramfs"
    say "    · auto-repair ran in the upgrade step above; matrix reflects the result."

    say "\n### Orphaned packages (installed as deps, now needed by nothing)"
    local orph; orph=$(pacman -Qtdq 2>/dev/null)
    if [ -n "$orph" ]; then
        say "    · $(printf '%s\n' "$orph" | wc -l) orphan(s): $(echo $orph | tr '\n' ' ')"
        say "      review, then reclaim with:  sudo pacman -Rns \$(pacman -Qtdq)"
    else
        say "    · none ✓"
    fi

    say "\n### Failed systemd units"
    local fu; fu=$(systemctl --failed --no-legend --plain 2>/dev/null | awk '{print $1}')
    [ -n "$fu" ] && say "    · $(echo $fu | tr '\n' ' ')   (inspect: systemctl status <unit>)" \
                 || say "    · none ✓"

    if [ "$DRY_RUN" -eq 0 ] && command -v pacdiff >/dev/null 2>&1; then
        say "\n### Pending .pacnew config merges"
        local pn; pn=$(sudo pacdiff -o 2>/dev/null)
        if [ -n "$pn" ]; then
            say "    · $(printf '%s\n' "$pn" | wc -l) file(s) need merging:"
            printf '%s\n' "$pn" | sed 's/^/      /'
            say "      merge with:  sudo DIFFPROG=nvim pacdiff"
        else
            say "    · none ✓"
        fi
    fi

    say "\n### Held-back packages (IgnorePkg in /etc/pacman.conf)"
    local pins; pins=$(grep -E '^[[:space:]]*IgnorePkg' /etc/pacman.conf 2>/dev/null | sed 's/.*=//')
    [ -n "$pins" ] && say "    ·$pins" || say "    · none"
    say "      (these are pinned on purpose — e.g. the NVIDIA stack held at the"
    say "       Isaac-validated 580 by nvidia-switch.sh, if you've run a downgrade.)"

    say "\n>>> Health check complete."
}

do_build() {
    pac build base-devel clang lld lldb cmake ninja meson ccache gdb valgrind \
              cppcheck doxygen graphviz boost eigen onetbb
}

do_cuda() {
    install_cuda
    say "\n### CUDA PATH for login shells (/etc/profile.d/cuda.sh)"
    if [ "$DRY_RUN" -eq 1 ]; then say "    [dry-run] write /etc/profile.d/cuda.sh"; return; fi
    if [ -d /opt/cuda ]; then
        sudo tee /etc/profile.d/cuda.sh >/dev/null <<'EOF'
export CUDA_HOME=/opt/cuda
export PATH="$CUDA_HOME/bin:$PATH"
EOF
    fi
}

do_python() {
    pac python python-pip python-pipx python-virtualenv python-numpy python-scipy \
               python-pandas python-scikit-learn python-matplotlib python-h5py \
               jupyterlab ipython python-pytest mypy ruff python-pylint python-black
}

do_anaconda() { install_anaconda; }
do_node()     { pac node pnpm yarn; }
do_editors()  { pac editors neovim; }
do_embedded() { pac embedded picocom minicom arduino-cli stlink openocd wireshark-qt; }

do_audio() {
    # alsa-utils: aplay/speaker-test for low-level audio debugging.
    # CachyOS's stock PipeWire drives the DualSense controller's audio (speaker +
    # 3.5mm jack) correctly, so none of the Arch DualSense workarounds (the 1.6.5
    # pin, the touchpad-ignore udev rule, the WirePlumber drop-in) are carried over.
    pac audio pavucontrol easyeffects alsa-utils
}

do_gpu()     { pac gpu lib32-nvidia-utils gamemode lib32-gamemode mangohud lib32-mangohud nvidia-settings; }

# Docker engine + NVIDIA Container Toolkit, for GPU containers (ROS 2 Humble, Isaac
# ROS). The NVIDIA toolkit injects the HOST driver into containers, so containers
# get whatever driver the host runs (currently 580 — see nvidia-switch.sh). The
# ros2-humble launcher (setup-home.sh) runs the container with --network host so
# its DDS shares a domain with native Isaac Sim's ROS 2 bridge (Humble matches the
# bridge's bundled Fast DDS — a Jazzy container crashed Isaac on discovery).
do_docker() {
    # xorg-xauth: host-side xauth so GUI tools (rviz2) forward X11 from the container.
    pac docker docker docker-buildx nvidia-container-toolkit xorg-xauth
    say "\n### Docker: data-root on /home + NVIDIA runtime + enable + docker group"
    if [ "$DRY_RUN" -eq 1 ]; then
        say "    [dry-run] nvidia-ctk runtime configure; daemon.json data-root=/home/docker-data"
        say "    [dry-run] + containerd-snapshotter=false; enable docker; usermod -aG docker"
        return
    fi
    command -v docker >/dev/null || { say "    · docker not installed — skipping config."; FAILED+=("docker:not-installed"); return; }
    sudo nvidia-ctk runtime configure --runtime=docker || FAILED+=("nvidia-ctk")
    # Docker 25+ resolves `--gpus all` via its NATIVE CDI support (it reads the
    # spec in /etc/cdi), NOT via nvidia-container-runtime. Generate a FRESH CDI
    # spec from the actually-installed driver so it lists only real files. A stale
    # spec (e.g. left over from a mid-driver-swap generation) referenced a phantom
    # libnvidia-tileiras.so the open driver never ships, and `--gpus all` died on
    # it. IMPORTANT: this spec is driver-version-specific — nvidia-switch.sh
    # regenerates it on every driver swap. See docs/learn/07-dev-environment.md.
    sudo install -d /etc/cdi
    sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml || FAILED+=("nvidia-cdi-generate")
    # Root partition is small (~50G) and images are large, so put Docker's
    # data-root on /home. data-root alone isn't enough: with the containerd image
    # store ON, layers land under /var/lib/containerd (root) and data-root is
    # ignored — so also disable the containerd snapshotter (overlay2 honors it).
    sudo install -d -m 0711 /home/docker-data || FAILED+=("docker data-root dir")
    sudo python - <<'PY' || FAILED+=("docker daemon.json")
import json, os
p = "/etc/docker/daemon.json"
d = {}
if os.path.exists(p):
    try: d = json.load(open(p))
    except Exception: d = {}
d["data-root"] = "/home/docker-data"
d.setdefault("features", {})["containerd-snapshotter"] = False
os.makedirs("/etc/docker", exist_ok=True)
json.dump(d, open(p, "w"), indent=2)
PY
    sudo systemctl enable --now docker || FAILED+=("docker enable")
    sudo usermod -aG docker "$USER_NAME" || FAILED+=("docker group")
    say "    · added $USER_NAME to the docker group — log out/in to activate, then:"
    say "      ros2-humble pull  # fetch the ROS 2 Humble image (~4 GB)"
}
# QEMU/KVM + libvirt + virt-manager — a full desktop virtualization stack for
# running guest operating systems (the use case here is building Gentoo / Linux
# From Scratch in throwaway VMs, but it runs anything: Windows, *BSD, other
# distros). Everything is in the official 'extra' repo, so it's always the newest
# rolling release — "latest and greatest" needs no AUR build.
#
# Why this is kernel-agnostic (works on BOTH linux-cachyos and linux-cachyos-lts with nothing
# extra): KVM hardware acceleration lives INSIDE the kernel — the kvm +
# kvm_intel/kvm_amd + vhost modules ship in-tree with every Arch kernel. There's
# no DKMS module and no per-kernel rebuild (unlike the NVIDIA stack). Whichever
# kernel you boot, /dev/kvm is there. The only kernel-touching file this writes
# is the nested-virt modprobe option, which the running kernel reads at module
# load — same file, both kernels.
#
#   qemu-full      the emulator + ALL UI/audio/block/network backends AND every
#                  guest architecture (x86_64 plus ARM/RISC-V/… — handy for
#                  cross-arch LFS experiments), not just the host arch.
#   libvirt        the management daemon virt-manager / virsh talk to.
#   virt-manager   the GTK management GUI.
#   virt-viewer    the SPICE/VNC guest-console window.
#   edk2-ovmf      UEFI firmware for guests (modern installers + Secure Boot).
#   swtpm          software TPM 2.0 (Windows 11 guests, measured-boot tests).
#   dnsmasq        backs libvirt's default NAT network (guest DHCP + outbound).
#   dmidecode      lets libvirt read host SMBIOS for guest CPU/board passthrough.
#   libguestfs     virt-* tools to inspect/edit guest disk images from the host
#                  (virt-resize, guestfish — useful when crafting LFS/Gentoo imgs).
do_vm() {
    pac vm qemu-full libvirt virt-manager virt-viewer edk2-ovmf swtpm \
           dnsmasq dmidecode libguestfs
    say "\n### libvirt: group access + daemon + default NAT network + nested virt"
    if [ "$DRY_RUN" -eq 1 ]; then
        say "    [dry-run] usermod -aG libvirt,kvm $USER_NAME"
        say "    [dry-run] set unix_sock_group/perms in /etc/libvirt/libvirtd.conf"
        say "    [dry-run] systemctl enable --now libvirtd.service"
        say "    [dry-run] virsh net-define(if needed)/autostart/start default"
        say "    [dry-run] write /etc/modprobe.d/kvm-nested.conf (Intel/AMD auto-detected)"
        return
    fi
    command -v virsh >/dev/null || { say "    · libvirt not installed — skipping config."; FAILED+=("vm:not-installed"); return; }
    # Group access: members of 'libvirt' manage the SYSTEM QEMU instance
    # (qemu:///system) without a polkit password each time; 'kvm' grants direct
    # /dev/kvm access. Like every group change here, it needs a fresh login.
    sudo usermod -aG libvirt,kvm "$USER_NAME" || FAILED+=("vm:groups")
    # Let the libvirt group own the read-write control socket (Arch-wiki standard).
    # The stock libvirtd.conf ships these keys commented out; flip them in place
    # whether they're currently commented or not.
    if [ -f /etc/libvirt/libvirtd.conf ]; then
        sudo sed -i \
            -e 's/^#\?unix_sock_group = .*/unix_sock_group = "libvirt"/' \
            -e 's/^#\?unix_sock_rw_perms = .*/unix_sock_rw_perms = "0770"/' \
            /etc/libvirt/libvirtd.conf || FAILED+=("vm:sockcfg")
    fi
    # Enable the daemon (socket-activated; pulls in virtlogd/virtlockd as needed).
    sudo systemctl enable --now libvirtd.service || FAILED+=("vm:daemon")
    # Default NAT network: guests get DHCP + outbound NAT with zero host config.
    # libvirt ships the template at /etc/libvirt/qemu/networks/default.xml; define
    # it if it isn't known yet, then mark it autostart and bring it up now.
    if ! sudo virsh net-info default >/dev/null 2>&1; then
        [ -f /etc/libvirt/qemu/networks/default.xml ] && \
            sudo virsh net-define /etc/libvirt/qemu/networks/default.xml 2>/dev/null
    fi
    sudo virsh net-autostart default 2>/dev/null || true
    sudo virsh net-start default 2>/dev/null || true   # harmless if already active
    # Nested virtualization: lets a guest itself run KVM (test a hypervisor, or run
    # a VM inside your LFS/Gentoo guest). Off by default; set the right per-vendor
    # module option. Detect Intel vs AMD from the CPU and write the modprobe drop-in.
    local vendor cpumod
    vendor=$(grep -m1 '^vendor_id' /proc/cpuinfo | awk '{print $3}')
    case "$vendor" in
        GenuineIntel) cpumod=kvm_intel ;;
        AuthenticAMD) cpumod=kvm_amd ;;
        *)            cpumod="" ;;
    esac
    if [ -n "$cpumod" ]; then
        echo "options $cpumod nested=1" | sudo tee /etc/modprobe.d/kvm-nested.conf >/dev/null \
            || FAILED+=("vm:nested")
        # Apply now if the module is idle (no VMs yet on a fresh setup); if it's in
        # use the reload fails harmlessly and the option takes effect next boot.
        sudo modprobe -r "$cpumod" 2>/dev/null && sudo modprobe "$cpumod" 2>/dev/null || true
    fi
    say "    · added $USER_NAME to libvirt,kvm — LOG OUT/IN before launching virt-manager."
    say "    · confirm hardware virt is enabled in firmware:  LC_ALL=C lscpu | grep Virtualization"
    say "      (should show VT-x or AMD-V; if blank, turn it on in the UEFI/BIOS setup)."
    say "    · KVM modules ship with BOTH linux-cachyos and linux-cachyos-lts — no per-kernel setup needed."
    say "    · launch:  virt-manager   (auto-connects to qemu:///system)"
}

do_media()   { pac media haruna obs-studio gimp okular gwenview swayimg ffmpeg; }
do_terminal() {
    # chafa = the terminal image renderer the fastfetch-logo helper drives.
    # fastfetch itself is bundled with caelestia (fastfetch-git from the AUR),
    # so it doesn't need its own line here; what's missing on a fresh box is
    # chafa, without which the helper silently falls back to ASCII.
    pac terminal fzf ripgrep fd bat zoxide lazygit github-cli tmux tree yq rsync chafa
}

do_monitor() {
    # HWiNFO-equivalent stack for Arch. All in the official 'extra' repo — no AUR
    # build, no driver coupling (nvidia-settings stays in the 'gpu' component
    # because it ships with the NVIDIA stack and lives or dies with it).
    #
    #   psensor              — live sensor graphs over time (temps/fans/voltages).
    #                          The single most HWiNFO-like piece for sensor history.
    #   hardinfo2            — comprehensive hardware-inventory + benchmark suite;
    #                          the closest single HWiNFO analogue. Lists CPU/RAM
    #                          modules, every PCI/USB device, audio codecs, SMART,
    #                          and surfaces lm_sensors in a Sensors tab.
    #   mission-center       — Task-Manager-style GUI: live CPU/GPU/RAM/disk/net
    #                          utilization + per-process. (Already bound to
    #                          Super+Shift+P in hypr-user.conf.) See below for the
    #                          conflict-with-mission-center-git handling.
    #   nvtop                — live GPU TUI (NVIDIA / AMD / Intel). Per-process VRAM
    #                          + utilization + power; what nvidia-smi can't show.
    #   btop                 — modern CLI process/system viewer (replaces htop).
    #   lm_sensors           — the kernel sensor framework everything else surfaces
    #                          (CPU temps, motherboard voltages, chassis fans).
    #                          After install, run `sudo sensors-detect --auto` once
    #                          to add any extra chip modules to /etc/modules-load.d
    #                          (most boards work out of the box — e.g. NCT6798 here
    #                          is auto-loaded by the kernel — but sensors-detect is
    #                          the catch-all for the rest).
    local pkgs=(psensor hardinfo2 nvtop btop lm_sensors lib32-lm_sensors)
    # mission-center vs mission-center-git: the AUR git build hard-conflicts with
    # the repo stable. Under --needed --noconfirm pacman REFUSES to silently
    # remove the git variant and aborts the entire transaction (taking psensor +
    # hardinfo2 down with it). So only add the repo mission-center if neither
    # variant is currently installed.
    if pacman -Qq mission-center >/dev/null 2>&1 \
       || pacman -Qq mission-center-git >/dev/null 2>&1; then
        say "    · mission-center already provided (skipping the repo build to avoid the AUR git conflict)"
    else
        pkgs+=(mission-center)
    fi
    pac monitor "${pkgs[@]}"
}
do_kde()     { pac kde systemsettings discover kinfocenter; }
do_display() { pac display drm-info wdisplays wlr-randr brightnessctl nm-connection-editor; }

do_storage() {
    # nautilus/udisks can't mount NTFS or exFAT without the userspace drivers
    # (Arch, unlike Ubuntu, doesn't ship them). With these installed, clicking an
    # internal Windows SSD in nautilus mounts it. gnome-disk-utility = the "Disks"
    # app from Ubuntu (partitions, free space, SMART). udisks2 is already a dep.
    # kdiskmark = CrystalDiskMark-style sequential/random read+write benchmark
    # (Qt6 GUI, drives `fio` under the hood); the closest match to the Windows
    # tool. Lives here rather than in `monitor` because it's disk-specific and
    # pairs naturally with gnome-disks' own SMART/benchmark dialogs.
    pac storage ntfs-3g exfatprogs gnome-disk-utility kdiskmark
    say "    · after this, internal NTFS drives mount on click in nautilus."
    say "    · free space / partitions:  gnome-disks   (GUI)   ·   df -h   (CLI)"
    say "    · disk read/write benchmark (CrystalDiskMark equivalent):  kdiskmark"
}

do_remote() {
    # SSH both ways + remote desktop. freerdp+remmina = RDP/VNC CLIENT (Arch ->
    # Windows). wayvnc = a VNC SERVER that works on Hyprland/wlroots, so other PCs
    # can view this desktop (true RDP into a live Wayland session isn't supported).
    # sshd is intentionally LEFT OFF (an idle sshd costs ~nothing, but off = smaller
    # attack surface); flip it per session with the 'remote' helper rather than
    # running it at every boot.
    pac remote openssh freerdp remmina wayvnc
    say "    · sshd is left OFF. Turn remote access on/off as needed (setup-home 'scripts'):"
    say "        remote on   ·   remote off   ·   remote status"
    say "      (always-on at boot instead:  sudo systemctl enable --now sshd)"
    say "    · RDP/VNC OUT to Windows:  remmina   (or  xfreerdp /v:<host> /u:<user>)"
    say "    · VNC INTO this box:       vnc-server   (localhost; tunnel: ssh -L 5900:localhost:5900 $USER_NAME@<ip>)"
}

do_tablet() {
    # Weylus = a small web-server you run on the desktop; you open its URL on an
    # iPad / Android browser and the tablet acts as a graphic tablet (pen pressure
    # via Apple Pencil / S-Pen) or a plain touchscreen pointing into the live
    # desktop. Upstream H-M-H/Weylus (the AUR `weylus` source build) hasn't been
    # touched since 2022 and no longer compiles on current rustc — its transitive
    # `syntex_pos 0.42` uses RustcEncodable/Decodable derive macros that modern
    # rustc removed. The maintained fork is electronstudio/WeylusCommunityEdition;
    # `weylus-community-bin` ships its prebuilt Linux binary so we sidestep the
    # whole Rust build path. conflicts with weylus / weylus-bin / weylus-git, so
    # the AUR helper handles the swap if any of those were installed before.
    #
    # gst-plugin-pipewire is the optdepend that enables Wayland (xdg-desktop-portal
    # screencast) capture — without it, capture falls back to X11 and on Hyprland
    # you get a black frame. Installed explicitly so a clean box without the
    # 'audio' component still works. xdg-desktop-portal[-hyprland] is already part
    # of caelestia's base.
    say "\n>>> Weylus Community Edition (AUR via ${HELPER:-none}) + screencast plugin"
    aur weylus-community-bin || FAILED+=("aur:weylus")
    # gst-plugin-pipewire: the Wayland-capture optdepend. CachyOS has no PipeWire
    # pin (unlike the Arch box), so a plain --needed install is safe.
    pac tablet gst-plugin-pipewire

    # uinput: Weylus writes pointer/keystroke events into /dev/uinput. By default
    # that node is root-only; running Weylus as your user requires a group + udev
    # rule so the node is group-writable, and the user must be in that group.
    # We also force-load the uinput module at boot (it's usually a kernel module
    # autoloaded on first use, but with the udev rule below the static_node trick
    # creates the device node up front so Weylus doesn't race against modprobe).
    say "\n### uinput group + udev rule + module autoload (so Weylus can inject input)"
    if [ "$DRY_RUN" -eq 1 ]; then
        say "    [dry-run] groupadd -r uinput; usermod -aG uinput $USER_NAME"
        say "    [dry-run] write /etc/udev/rules.d/60-weylus-uinput.rules + /etc/modules-load.d/uinput.conf"
        say "    [dry-run] udevadm control --reload-rules; modprobe uinput"
        return
    fi
    getent group uinput >/dev/null || sudo groupadd -r uinput || FAILED+=("uinput group")
    if ! id -nG "$USER_NAME" | tr ' ' '\n' | grep -qx uinput; then
        sudo usermod -aG uinput "$USER_NAME" || FAILED+=("uinput membership")
    fi
    sudo tee /etc/udev/rules.d/60-weylus-uinput.rules >/dev/null <<'EOF'
KERNEL=="uinput", GROUP="uinput", MODE="0660", OPTIONS+="static_node=uinput"
EOF
    sudo tee /etc/modules-load.d/uinput.conf >/dev/null <<'EOF'
uinput
EOF
    sudo udevadm control --reload-rules || FAILED+=("udev reload")
    sudo modprobe uinput 2>/dev/null || true
    say "    · log out + back in so your shell picks up the uinput group, then run:"
    say "        weylus      # opens the GUI; pick an access code + press Start"
    say "      and open the printed http://<your-ip>:1701 URL in your tablet's browser."
    say "    · Wayland capture needs xdg-desktop-portal-hyprland (already in caelestia)"
    say "      and gst-plugin-pipewire (just installed). Pen pressure works in Safari"
    say "      (iPadOS) and recent Chromium/Firefox via Pointer Events."
}

do_theme() {
    say "\n>>> Candy rainbow icons (AUR via ${HELPER:-none})"
    # candy-icons = the rainbow/gradient APP icons; sweet-folders supplies the
    # coloured FOLDER icons that Inherit candy-icons. Both go to /usr/share/icons
    # (pacman-tracked). These two packages are the COMPLETE, minimal set for the
    # Sweet look — the 12 colour variants all ship inside sweet-folders-icons-git
    # (one ~2 MiB package), so there's nothing extra to remove for disk.
    aur candy-icons-git sweet-folders-icons-git || FAILED+=("aur:theme")
    # Persistence: lock the icon theme at the system level so an upgrade / caelestia
    # colour-scheme regeneration can't silently revert it to Papirus-Dark. Variant
    # via ICON_THEME (default Sweet-Purple) — same knob setup-home.sh nautilus uses.
    lock_icon_theme "${ICON_THEME:-Sweet-Purple}"
    say "    · also apply the per-user GTK side:  bash setup-home.sh nautilus"
}

do_aurapps() {
    say "\n>>> AUR via ${HELPER:-(none)}"
    aur sweet-cursors-git sweet-cursors-hyprcursor-git \
        brave-bin microsoft-edge-stable-bin claude-desktop-bin \
        || FAILED+=("aur:apps")
}

do_groups() {
    say "\n### Group membership (serial, wireshark)"
    if [ "$DRY_RUN" -eq 1 ]; then say "    [dry-run] usermod -aG uucp,lock,wireshark $USER_NAME"; return; fi
    sudo usermod -aG uucp,lock,wireshark "$USER_NAME" || FAILED+=("usermod groups")
}

do_shell() {
    say "\n### Login shell -> fish"
    if [ "$DRY_RUN" -eq 1 ]; then say "    [dry-run] chsh -s /usr/bin/fish $USER_NAME"; return; fi
    if [ "$(getent passwd "$USER_NAME" | cut -d: -f7)" != /usr/bin/fish ]; then
        sudo chsh -s /usr/bin/fish "$USER_NAME" || FAILED+=("chsh fish")
    fi
}

# ============================================================================
# Arg parsing + interactive menu (shared shape with uninstall.sh)
# ============================================================================
SELECTED=()
ALL_NAMES=(); for row in "${COMPONENTS[@]}"; do ALL_NAMES+=("${row%%|*}"); done
is_component() { local n; for n in "${ALL_NAMES[@]}"; do [ "$n" = "$1" ] && return 0; done; return 1; }

for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        -y|--yes)  ASSUME_YES=1 ;;
        all)       SELECTED=("${ALL_NAMES[@]}") ;;
        -h|--help)
            say "usage: install.sh [--dry-run] [--yes] [all | <component>...]"
            say "components: ${ALL_NAMES[*]}"; exit 0 ;;
        *)
            if is_component "$arg"; then SELECTED+=("$arg")
            else say "Unknown component '$arg'. Known: ${ALL_NAMES[*]}"; exit 1; fi ;;
    esac
done

if [ "${#SELECTED[@]}" -eq 0 ]; then
    hr; say "Interactive installer — pick what to install."
    say "(Prereqs: DB refresh, git/base-devel/gh/ssh + an AUR helper always run first.)"
    [ "$DRY_RUN" -eq 1 ] && say "(dry-run: nothing will actually be installed)"
    hr
    i=1
    for row in "${COMPONENTS[@]}"; do say "  $i) ${row%%|*} — ${row#*|}"; i=$((i+1)); done
    say "  a) all of the above"
    say "  q) quit"
    hr
    read -rp "Enter numbers (space/comma separated), 'a', or 'q': " reply
    case "$reply" in
        q|Q|"") say "Nothing selected — exiting."; exit 0 ;;
        a|A)    SELECTED=("${ALL_NAMES[@]}") ;;
        *)
            reply=${reply//,/ }
            for tok in $reply; do
                if [[ "$tok" =~ ^[0-9]+$ ]] && [ "$tok" -ge 1 ] && [ "$tok" -le "${#ALL_NAMES[@]}" ]; then
                    SELECTED+=("${ALL_NAMES[$((tok-1))]}")
                else
                    say "  (ignoring invalid choice '$tok')"
                fi
            done ;;
    esac
fi

[ "${#SELECTED[@]}" -eq 0 ] && { say "Nothing selected — exiting."; exit 0; }

# De-duplicate selection (membership test only; run order follows COMPONENTS).
in_selected() { local s; for s in "${SELECTED[@]}"; do [ "$s" = "$1" ] && return 0; done; return 1; }

hr
say "Will install: ${SELECTED[*]}"
[ "$DRY_RUN" -eq 1 ] && say "Mode: DRY-RUN (no changes)."
hr
if [ "$ASSUME_YES" -eq 0 ] && [ "$DRY_RUN" -eq 0 ]; then
    read -rp "Proceed? [y/N]: " ok
    case "$ok" in y|Y|yes|YES) ;; *) say "Aborted."; exit 0 ;; esac
fi

# ============================================================================
# Mandatory prereqs (always) — full upgrade (rolling-release safe), base tooling,
# AUR helper, then DKMS/initramfs self-heal. This block is why simply re-running
# install.sh repairs a botched upgrade: it pulls each kernel's headers IN the same
# transaction as the kernel, so DKMS rebuilds in lockstep and no kernel is left
# module-less.
# ============================================================================
hr
say "### Full system upgrade — keyring + every kernel's headers, in one transaction"
# 1) Refresh the keyrings FIRST. On a box that hasn't updated in a while an expired
#    signing key makes the whole -Syu fail ("invalid or corrupted package"). CachyOS
#    needs BOTH keyrings — archlinux-keyring (core/extra) AND cachyos-keyring (the
#    cachyos-* repos) — or packages from the cachyos repos fail signature checks.
# 2) Fold each installed kernel's matching -headers into the SAME -Syu, so when a
#    kernel rolls forward its headers do too and any DKMS module builds against the
#    right version immediately. On CachyOS the default nvidia module is the prebuilt
#    linux-cachyos*-nvidia-open package (no DKMS build), but DKMS matters once
#    nvidia-switch.sh swaps in nvidia-open-dkms — and this keeps any other DKMS
#    module (VirtualBox, etc.) in lockstep. kernel_headers_pkgs only emits
#    installable targets, so it can't abort the upgrade on a kernel whose -headers
#    isn't a repo package.
# 3) Always a FULL -Syu (never -Sy): partial upgrades are the #1 way to break Arch/CachyOS.
mapfile -t HDRS < <(kernel_headers_pkgs)
say "    · kernel headers kept in sync: ${HDRS[*]:-none found}"
# Only fold in a keyring package that actually exists (cachyos-keyring is absent on
# a plain Arch box; archlinux-keyring is always present).
KEYRINGS=()
for k in archlinux-keyring cachyos-keyring; do
    pacman -Si "$k" >/dev/null 2>&1 && KEYRINGS+=("$k")
done
if [ "$DRY_RUN" -eq 1 ]; then
    say "    [dry-run] sudo pacman -Syu --needed ${KEYRINGS[*]} ${HDRS[*]}"
else
    sudo pacman -Syu --needed --noconfirm "${KEYRINGS[@]}" "${HDRS[@]}" \
        || FAILED+=("pacman -Syu")
fi
# Base tooling, done up front so `gh auth login` + `git push` work afterward and
# the AUR components below have a helper to use.
pac prereqs git base-devel github-cli openssh
ensure_aur_helper
say ">>> AUR helper: ${HELPER:-none}"

# Self-heal DKMS + boot images after the upgrade — catches the rolling-release
# "kernel updated but its out-of-tree module didn't" class automatically, every run.
hr
say "### Post-upgrade DKMS + initramfs self-heal"
heal_dkms_initramfs

# Run selected components in canonical order.
for row in "${COMPONENTS[@]}"; do
    name="${row%%|*}"
    if in_selected "$name"; then hr; "do_${name}"; fi
done

# ============================================================================
hr
if [ ${#FAILED[@]} -eq 0 ]; then
    say "All steps completed."
else
    say "Completed with issues in: ${FAILED[*]}"
    say "Re-run is safe (everything uses --needed / is idempotent)."
fi
[ "$DRY_RUN" -eq 1 ] && say "(dry-run: nothing was changed)"
cat <<'EOF'

Next (gh + an AUR helper are installed, so the only auth step is manual):
  1. Authenticate GitHub, then push:
       gh auth login
       git push
  2. Set your git identity name (email is usually set by setup-home/your config):
       git config --global user.name "Your Name"
  3. Log out and back in (group + shell changes need a fresh session).
  4. Verify the ghost cursor is gone and sweet-cursors renders:
       hyprctl reload
  5. Anaconda (general ML): open a new fish shell, then
       conda activate base    # base is not auto-activated by design

Rolling-release self-heal: every install.sh run does a full upgrade with each
kernel's headers in lockstep, then rebuilds DKMS modules + initramfs/UKI — so
re-running this script also REPAIRS a botched upgrade. For a one-shot doctor
(kernel/DKMS repair + orphans/failed-units/.pacnew/pins report) with no app
install:  bash ~/Documents/hyprland-rice/cachyos/install.sh health

To cleanly remove a component later (CUDA, Anaconda, ...), use the interactive
uninstaller:  bash ~/Documents/hyprland-rice/cachyos/uninstall.sh

To switch the WHOLE NVIDIA stack between repo-latest and the older driver Isaac
Sim/Lab validates (580.x) — or to purge it entirely — use the dedicated tool
(read its recovery notes; it can change what boots):
  bash ~/Documents/hyprland-rice/cachyos/nvidia-switch.sh status
  bash ~/Documents/hyprland-rice/cachyos/nvidia-switch.sh downgrade   # -> 580 for Isaac
  bash ~/Documents/hyprland-rice/cachyos/nvidia-switch.sh latest      # -> repo newest
EOF
