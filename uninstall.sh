#!/usr/bin/env bash
# ============================================================================
# uninstall.sh — interactive, component-based CLEAN uninstaller for this setup.
#
# The counterpart to install.sh. Each "component" knows how to remove itself the
# way install.sh added it: packages (pacman -Rns), data dirs, configs, launchers,
# services, and group memberships — so the result is as if it had never been
# installed, and the space it ate is reclaimed.
#
#     bash ~/Documents/arch-hyprland-setup/uninstall.sh            # interactive menu
#     bash ~/Documents/arch-hyprland-setup/uninstall.sh docker     # one component
#     bash ~/Documents/arch-hyprland-setup/uninstall.sh docker isaac ros2
#     bash ~/Documents/arch-hyprland-setup/uninstall.sh --dry-run docker
#     bash ~/Documents/arch-hyprland-setup/uninstall.sh --yes all   # no prompts
#
# Flags:
#   --dry-run   show exactly what WOULD happen; touch nothing.
#   --yes / -y  skip the per-component confirmation (still prints the plan).
#   all         select every component.
#
# Run as your normal user (it calls sudo itself where needed). Idempotent: a
# component already gone is reported as "nothing to do", never an error.
# ============================================================================
set -uo pipefail

if [ "$(id -u)" -eq 0 ]; then
    echo "Run as your normal user, not root (the script calls sudo itself)." >&2
    exit 1
fi

USER_NAME="$(id -un)"
DRY_RUN=0
ASSUME_YES=0
FAILED=()
RECLAIMED_KB=0

# ---- Components: name|one-line description ----------------------------------
# Add a row here + a matching do_<name>() function to teach the uninstaller a new
# component. The menu and `all` are generated from this list.
COMPONENTS=(
    "docker|Docker engine, buildx, containerd, NVIDIA container toolkit, all images/data, the docker group"
    "vm|QEMU/KVM + libvirt + virt-manager + virt-viewer + OVMF/swTPM/guestfs, the default NAT net, ALL guest disk images in EVERY pool (default + custom pools on /home), /etc/libvirt, the nested-virt modprobe drop-in, and libvirt/kvm group membership (leaves your ISOs untouched)"
    "isaac|Isaac Sim container caches, the IsaacLab clone, the isaac-sim launcher, xorg-xauth"
    "ros2|The ros2-humble launcher + its Docker image + the Fast DDS UDP profile (also clears a leftover Jazzy image/launcher; image only if Docker is still present)"
    "anaconda|Anaconda (AUR) + the conda fish init; leaves your project envs' data under ~/anaconda3 if external"
    "lerobot|Conda env 'lerobot' + the ~/lerobot clone the install created (override LEROBOT_DIR); set LEROBOT_KEEP_CLONE=1 to keep the clone. Anaconda itself stays."
    "uv|uv venv (~/.venv), build cache (~/.cache/uv) and uv-managed Pythons; keeps the pacman uv binary"
    "cuda|CUDA toolkit + cuDNN + the /etc/profile.d/cuda.sh PATH (leaves the NVIDIA driver alone)"
    "icons|Switch the GTK icon theme back to the caelestia default (Papirus-Dark); keeps the Sweet/candy packages so you can re-apply"
    "inputremap|input-remapper (AUR) + its daemon/service + ~/.config presets — no longer needed (the Razer mouse remaps via onboard memory)"
    "extras|Remove unused apps + their ~/.config/.cache/.state: Zed, Dolphin (using nautilus), Inkscape, Kate, HyprKCS"
    "fastfetch|Revert fastfetch to the OS ASCII logo, drop ~/.config/fastfetch/logo.sixel + any animated.* copy + fish_greeting animation hook (keeps the fastfetch-logo helper itself)"
    "tablet|Weylus (any variant) + the uinput udev rule + module autoload + uinput group membership (~/.local/share/weylus access-codes too); leaves gst-plugin-pipewire alone (cheap, shared)"
)

# ---- helpers ----------------------------------------------------------------
say()  { echo -e "$*"; }
hr()   { echo "------------------------------------------------------------"; }

# Echo + run, unless --dry-run. Records a FAILED tag (arg after --) on nonzero
# but never aborts the script — best-effort cleanup keeps going.
run() {
    local tag="$1"; shift
    if [ "$DRY_RUN" -eq 1 ]; then
        say "    [dry-run] $*"
        return 0
    fi
    say "    + $*"
    "$@" || FAILED+=("$tag")
}

# Same as run() but the command is a single string evaluated by the shell
# (for pipes / globs / sudo-with-redirection).
run_sh() {
    local tag="$1"; shift
    if [ "$DRY_RUN" -eq 1 ]; then
        say "    [dry-run] $*"
        return 0
    fi
    say "    + $*"
    bash -c "$*" || FAILED+=("$tag")
}

# Pretty-print a size given in KB.
human_kb() {
    awk -v k="$1" 'BEGIN{
        split("KB MB GB TB", u); s=k; i=1;
        while (s>=1024 && i<4){ s/=1024; i++ }
        printf "%.1f %s", s, u[i] }'
}

# Measure a path's size (KB) and add to the running reclaim tally, then delete it.
# Pass "sudo" as $3 for root-owned paths: BOTH the measurement and the delete then
# run via sudo — otherwise a non-root `du` can't descend a root-owned dir (e.g.
# Docker's mode-0711 data-root) and the reclaim total is wildly under-counted.
# No-op if the path is absent.
reclaim() {
    local tag="$1" path="$2" sudo_rm="${3:-}"
    [ -e "$path" ] || { say "    · $path — absent, skip"; return; }
    local du_pfx=""
    [ "$sudo_rm" = "sudo" ] && du_pfx="sudo"
    local kb; kb=$($du_pfx du -sk "$path" 2>/dev/null | awk '{print $1}'); kb=${kb:-0}
    RECLAIMED_KB=$((RECLAIMED_KB + kb))
    say "    · $path  ($(human_kb "$kb"))"
    if [ "$sudo_rm" = "sudo" ]; then
        run "$tag" sudo rm -rf "$path"
    else
        run "$tag" rm -rf "$path"
    fi
}

# Remove packages only if installed; -Rns also drops now-orphaned deps. Filters
# to the installed subset so a missing package isn't a hard pacman error.
remove_pkgs() {
    local tag="$1"; shift
    local present=()
    local p
    for p in "$@"; do
        pacman -Qq "$p" >/dev/null 2>&1 && present+=("$p")
    done
    if [ "${#present[@]}" -eq 0 ]; then
        say "    · packages already absent: $*"
        return
    fi
    # Tally the package space too, not just deleted home data. Simulate the removal
    # to learn the FULL set -Rns will take (the named packages + every dependency it
    # cascades) and sum their installed sizes. `-Rs --print` expands the identical
    # set as `-Rns` (the -n/--nosave flag only governs .pacsave files, not which
    # packages go — and it can't be combined with --print). Needs no root.
    local rmset kb=0
    rmset=$(pacman -Rs --print --print-format '%n' "${present[@]}" 2>/dev/null)
    if [ -n "$rmset" ]; then
        kb=$(pacman -Qi $rmset 2>/dev/null | awk '/^Installed Size/ {
                v=$(NF-1); u=$NF;
                if(u=="B") v/=1024; else if(u=="MiB") v*=1024; else if(u=="GiB") v*=1048576;
                s+=v } END { printf "%d", s }')
        kb=${kb:-0}
        RECLAIMED_KB=$((RECLAIMED_KB + kb))
        say "    · packages + cascaded deps  ($(human_kb "$kb"))"
    fi
    say "    · removing packages: ${present[*]}"
    run "$tag" sudo pacman -Rns --noconfirm "${present[@]}"
}

# ---- components -------------------------------------------------------------

do_docker() {
    say ">>> Docker (engine + containerd + NVIDIA toolkit + all data)"
    # Stop & disable services first so nothing holds the data-root open.
    run docker-stop  sudo systemctl disable --now docker.service docker.socket containerd.service
    # Remove the engine + tooling. containerd is pulled in by docker; -Rns clears it.
    remove_pkgs docker-pkgs docker docker-buildx nvidia-container-toolkit containerd
    # All image/layer/volume data — the space hogs. data-root was moved to /home.
    reclaim docker-data /home/docker-data       sudo
    reclaim docker-var  /var/lib/docker          sudo
    reclaim ctrd-var    /var/lib/containerd       sudo
    reclaim docker-etc  /etc/docker               sudo
    # Drop the docker group membership we granted in install.sh.
    if id -nG "$USER_NAME" 2>/dev/null | tr ' ' '\n' | grep -qx docker; then
        run docker-group sudo gpasswd -d "$USER_NAME" docker
    else
        say "    · $USER_NAME not in docker group — skip"
    fi
}

do_vm() {
    say ">>> QEMU/KVM + libvirt + virt-manager virtualization stack"
    # --- Find guest disks in EVERY pool, not just the default one ----------------
    # A VM disk may live in a CUSTOM pool on /home (e.g. a 'gentoo' pool pointing at
    # ~/Documents/linux-iso/gentoo) that the /var/lib/libvirt sweep below would miss
    # entirely — so a user who forgot to "Delete associated storage" in virt-manager
    # would be left with a multi-GB qcow2 on /home. Ask libvirt — WHILE IT'S STILL
    # RUNNING — for every volume in every pool, and remember the ones that are real
    # VM disk images. We match only known disk extensions: a directory-type pool
    # reports EVERY file in its dir as a "volume" (including the user's .iso and any
    # stray files), and we must never delete those. Disks outside /var/lib/libvirt
    # get reclaimed explicitly further down; ones inside it ride the dir sweep.
    local VM_DISKS=() VM_SKIPPED=()
    if command -v virsh >/dev/null 2>&1; then
        local _pool _vol
        while IFS= read -r _pool; do
            [ -n "$_pool" ] || continue
            while IFS= read -r _vol; do
                [ -n "$_vol" ] || continue
                case "${_vol,,}" in
                    *.qcow2|*.qcow|*.raw|*.img|*.qed|*.vmdk|*.vdi|*.vhd|*.vhdx)
                        VM_DISKS+=("$_vol") ;;
                    *) VM_SKIPPED+=("$_vol") ;;   # .iso / unknown → not ours to delete
                esac
            done < <(sudo virsh vol-list "$_pool" 2>/dev/null | awk 'NR>2 && NF>=2 {print $2}')
        done < <(sudo virsh pool-list --all --name 2>/dev/null)
    fi
    # Stop the default NAT network + the daemons first so nothing holds the virbr0
    # bridge / storage pools open while packages and data go away.
    if command -v virsh >/dev/null 2>&1; then
        run vm-net-stop   sudo virsh net-destroy default
        run vm-net-noauto sudo virsh net-autostart --disable default
    fi
    run vm-daemon sudo systemctl disable --now \
        libvirtd.service libvirtd.socket libvirtd-ro.socket libvirtd-admin.socket \
        virtlogd.service virtlockd.service
    # Remove the stack. -Rns sweeps the cascaded deps (the qemu-* sub-packages,
    # spice, etc.). edk2-ovmf/swtpm/libguestfs/virt-viewer were pulled in solely
    # for this component, so they go too.
    remove_pkgs vm-pkgs qemu-full libvirt virt-manager virt-viewer \
                edk2-ovmf swtpm libguestfs
    # dnsmasq + dmidecode are general-purpose utilities other things may want; try
    # to remove them but -Rns will (correctly) refuse if anything still needs them.
    remove_pkgs vm-extra dnsmasq dmidecode
    # The space hogs: guest disk images + storage pools live under /var/lib/libvirt
    # (default images dir is /var/lib/libvirt/images). This is what frees real GBs
    # after building Gentoo/LFS guests. The whole tree is root-owned → sudo.
    reclaim vm-varlib /var/lib/libvirt sudo
    # Guest disks that live OUTSIDE /var/lib/libvirt (custom pools on /home, etc.).
    # The default-pool disks are already gone with /var/lib/libvirt above, so skip
    # those here to avoid a double "reclaim" of nothing. Each disk is removed as an
    # individual FILE — the pool's directory (which may also hold the user's ISOs)
    # is left in place. sudo: system-pool volumes are created root-owned.
    local _d _dir
    for _d in "${VM_DISKS[@]}"; do
        case "$_d" in /var/lib/libvirt/*) continue ;; esac   # handled by the sweep
        reclaim "vm-disk" "$_d" sudo
        # If removing that disk emptied its directory, drop the now-empty dir too —
        # but ONLY if empty, so a pool dir still holding ISOs/other files survives.
        _dir=$(dirname "$_d")
        if [ -d "$_dir" ] && [ -z "$(ls -A "$_dir" 2>/dev/null)" ]; then
            run vm-disk-dir sudo rmdir "$_dir"
        fi
    done
    # Anything we deliberately DIDN'T touch (ISOs / stray files in a dir pool): tell
    # the user where they are so they can delete them by hand if they want the space.
    if [ "${#VM_SKIPPED[@]}" -gt 0 ]; then
        say "    · left in place (not VM disks — delete by hand if unwanted):"
        for _d in "${VM_SKIPPED[@]}"; do say "        - $_d"; done
    fi
    reclaim vm-etc    /etc/libvirt      sudo
    # Per-user virt-manager state (connection list, window/default settings).
    reclaim vm-cfg    "$HOME/.config/libvirt"
    reclaim vm-share  "$HOME/.local/share/libvirt"
    reclaim vm-cache  "$HOME/.cache/libvirt"
    # The nested-virt modprobe drop-in install.sh wrote.
    [ -f /etc/modprobe.d/kvm-nested.conf ] && \
        run vm-nested sudo rm -f /etc/modprobe.d/kvm-nested.conf
    # Drop the secondary group memberships install.sh granted (never the primary).
    # Leave the groups themselves — 'kvm' is a system group other tooling uses.
    local g
    for g in libvirt kvm; do
        if id -nG "$USER_NAME" 2>/dev/null | tr ' ' '\n' | grep -qx "$g"; then
            run "vm-group-$g" sudo gpasswd -d "$USER_NAME" "$g"
        else
            say "    · $USER_NAME not in $g group — skip"
        fi
    done
    say "    · removed. KVM kernel modules are in-tree (nothing to uninstall there)."
    say "    · the dropped groups need a fresh login to take effect."
}

do_isaac() {
    say ">>> Isaac Sim / Isaac Lab"
    # The cache is owned by the container's internal UID 1234, not by the user —
    # it MUST be removed with sudo or rm hits permission-denied.
    reclaim isaac-cache "$HOME/docker/isaac-sim" sudo
    reclaim isaac-lab   "$HOME/robotics/IsaacLab"
    # Drop the parent ~/docker only if now empty (don't nuke unrelated containers).
    if [ -d "$HOME/docker" ] && [ -z "$(ls -A "$HOME/docker" 2>/dev/null)" ]; then
        run isaac-dockerdir rmdir "$HOME/docker"
    fi
    reclaim isaac-launcher "$HOME/.local/bin/isaac-sim"
    # xorg-xauth was added solely for Isaac Lab's X11 forwarding.
    remove_pkgs isaac-xauth xorg-xauth
}

do_ros2() {
    say ">>> ROS 2 Humble (container wrapper)"
    # Remove the cached image(s) first (only possible while docker is still here).
    # Includes a leftover osrf/ros:jazzy-desktop-full from the pre-Humble setup.
    if command -v docker >/dev/null 2>&1; then
        local img found=0
        for img in osrf/ros:humble-desktop-full osrf/ros:jazzy-desktop-full; do
            if docker image inspect "$img" >/dev/null 2>&1; then
                run ros2-image docker rmi "$img"; found=1
            fi
        done
        [ "$found" -eq 0 ] && say "    · no ros2 image pulled — skip"
    else
        say "    · docker already gone — its images went with it"
    fi
    reclaim ros2-launcher "$HOME/.local/bin/ros2-humble"
    reclaim ros2-launcher-old "$HOME/.local/bin/ros2-jazzy"   # pre-Humble name
    reclaim ros2-ddsprofile "$HOME/.config/ros2/fastdds-udp-only.xml"
    # Drop the ~/.config/ros2 dir only if now empty (don't nuke other ROS configs).
    if [ -d "$HOME/.config/ros2" ] && [ -z "$(ls -A "$HOME/.config/ros2" 2>/dev/null)" ]; then
        run ros2-cfgdir rmdir "$HOME/.config/ros2"
    fi
    # ~/robotics/ws is the user's own workspace — never delete it. Drop the empty
    # ~/robotics only if nothing else (IsaacLab/ws) lives under it.
    if [ -d "$HOME/robotics" ] && [ -z "$(ls -A "$HOME/robotics" 2>/dev/null)" ]; then
        run ros2-roboticsdir rmdir "$HOME/robotics"
    fi
}

do_anaconda() {
    say ">>> Anaconda"
    remove_pkgs anaconda-pkg anaconda
    reclaim anaconda-fish "$HOME/.config/fish/conf.d/conda.fish"
    say "    · note: your conda ENVS/data (if under ~/anaconda3 or \$CONDA_PREFIX) are left in place."
}

do_cuda() {
    say ">>> CUDA toolkit + cuDNN (driver is left installed)"
    remove_pkgs cuda-pkgs cuda cudnn
    reclaim cuda-profile /etc/profile.d/cuda.sh sudo
}

do_lerobot() {
    say ">>> LeRobot conda env (override env name via LEROBOT_ENV=…)"
    if ! command -v conda >/dev/null 2>&1; then
        say "    · conda not found — nothing to remove."
        return
    fi
    local env_name="${LEROBOT_ENV:-lerobot}"
    local conda_base; conda_base="$(conda info --base 2>/dev/null)"
    if conda env list 2>/dev/null | awk '{print $1}' | grep -qx "$env_name"; then
        # Tally the env size before removal (envs/<name> is a regular directory).
        local envpath="$conda_base/envs/$env_name"
        if [ -d "$envpath" ]; then
            local kb; kb=$(du -sk "$envpath" 2>/dev/null | awk '{print $1}'); kb=${kb:-0}
            RECLAIMED_KB=$((RECLAIMED_KB + kb))
            say "    · $envpath  ($(human_kb "$kb"))"
        fi
        run lerobot-env conda env remove -y -n "$env_name"
    else
        say "    · conda env '$env_name' not present — skip"
    fi
    say "    · Anaconda itself is untouched (run 'anaconda' component to remove it)."
    # The LeRobot clone the install component created (default ~/lerobot, override
    # LEROBOT_DIR). Removed by default for install/uninstall symmetry. Safety opt-out:
    # LEROBOT_KEEP_CLONE=1 leaves the directory alone (use this if you've written
    # branches/calibration files/datasets into the clone you want to preserve).
    local clone="${LEROBOT_DIR:-$HOME/lerobot}"
    if [ -d "$clone" ]; then
        if [ "${LEROBOT_KEEP_CLONE:-0}" = "1" ]; then
            local kb; kb=$(du -sk "$clone" 2>/dev/null | awk '{print $1}'); kb=${kb:-0}
            say "    · LEROBOT_KEEP_CLONE=1 → leaving clone in place: $clone  ($(human_kb "$kb"))"
        else
            # Loud warning if the working tree has uncommitted/untracked changes,
            # so the user sees what's about to disappear before reclaim deletes it.
            # (The interactive top-level prompt is the real gate; this just informs.)
            if [ -d "$clone/.git" ] && command -v git >/dev/null 2>&1; then
                local dirty; dirty=$(git -C "$clone" status --porcelain 2>/dev/null | wc -l)
                if [ "${dirty:-0}" -gt 0 ]; then
                    say "    · WARNING: $clone has $dirty uncommitted/untracked file(s)."
                    say "      Aborting THIS step only — set LEROBOT_KEEP_CLONE=1 to skip"
                    say "      clone removal, or commit/stash/discard changes and re-run."
                    return
                fi
            fi
            reclaim lerobot-clone "$clone"
        fi
    fi
}

do_uv() {
    say ">>> uv environment artifacts (venv + build cache + uv-managed Pythons)"
    # uv (the binary at /usr/bin/uv) is a pacman package — keeping it costs no disk.
    # This component clears the things that grow large: the user's primary venv, uv's
    # build cache (gigabytes after compiling native wheels), and any uv-managed Python
    # interpreters. The pacman package is left alone — sudo pacman -Rns uv if wanted.
    reclaim uv-venv "$HOME/.venv"
    # Build cache: prefer 'uv cache clean' (uv-aware) and measure before pruning.
    if command -v uv >/dev/null 2>&1 && [ -d "$HOME/.cache/uv" ]; then
        local kb; kb=$(du -sk "$HOME/.cache/uv" 2>/dev/null | awk '{print $1}'); kb=${kb:-0}
        RECLAIMED_KB=$((RECLAIMED_KB + kb))
        say "    · $HOME/.cache/uv  ($(human_kb "$kb"))"
        run uv-cache uv cache clean
    else
        reclaim uv-cache "$HOME/.cache/uv"
    fi
    # Uv-managed Python interpreters live under ~/.local/share/uv/python.
    if command -v uv >/dev/null 2>&1 && [ -d "$HOME/.local/share/uv/python" ]; then
        local kb; kb=$(du -sk "$HOME/.local/share/uv" 2>/dev/null | awk '{print $1}'); kb=${kb:-0}
        RECLAIMED_KB=$((RECLAIMED_KB + kb))
        say "    · $HOME/.local/share/uv  ($(human_kb "$kb"))"
        run uv-python uv python uninstall --all
        reclaim uv-share-leftover "$HOME/.local/share/uv"
    else
        reclaim uv-share "$HOME/.local/share/uv"
    fi
    # The shim symlink uv creates for managed Pythons (e.g. ~/.local/bin/python3.12 ->
    # uv's managed interpreter). Harmless if absent.
    reclaim uv-py-shim "$HOME/.local/bin/python3.12"
    say "    · uv binary itself is left in place (pacman package — no disk cost)."
    say "      to drop uv entirely too:  sudo pacman -Rns uv"
}

do_icons() {
    say ">>> Switch GTK icon theme back to the caelestia default"
    # First remove the system dconf LOCK install.sh wrote (it pins the icon theme so
    # upgrades/caelestia can't reset it). While that lock is in place gsettings can't
    # change the key, so this MUST come before the gsettings set below. We drop our
    # local.d files + the lock and rebuild the db; the profile's system-db:local line
    # is harmless and left in place.
    if [ -f /etc/dconf/db/local.d/locks/icon-theme ] || [ -f /etc/dconf/db/local.d/10-icon-theme ]; then
        run icons-unlock sudo rm -f /etc/dconf/db/local.d/locks/icon-theme /etc/dconf/db/local.d/10-icon-theme
        run icons-dconf-update sudo dconf update
    else
        say "    · no icon-theme dconf lock present — skip"
    fi
    # Restore the prior icon theme (Papirus-Dark; override with ICON_THEME=<name>)
    # and drop the gtk-icon-theme-name override lines so gsettings/caelestia decide.
    local default="${ICON_THEME:-Papirus-Dark}"
    command -v gsettings >/dev/null && \
        run icons-gsettings gsettings set org.gnome.desktop.interface icon-theme "$default"
    local f
    for f in "$HOME/.config/gtk-3.0/settings.ini" "$HOME/.config/gtk-4.0/settings.ini"; do
        [ -f "$f" ] && run_sh icons-ini "sed -i '/^gtk-icon-theme-name=/d' '$f'"
    done
    say "    · icon theme restored to $default (Sweet/candy packages kept)."
    say "    · re-apply the Sweet icons:        bash setup-home.sh nautilus"
    say "    · to also remove the packages:     paru -Rns candy-icons-git sweet-folders-icons-git"
}

do_inputremap() {
    say ">>> input-remapper (the root daemon + the AUR package + presets)"
    # The root daemon autoloads presets at login; stop & disable it before pulling
    # the package so nothing keeps a uinput device open.
    run inputremap-svc sudo systemctl disable --now input-remapper.service
    remove_pkgs inputremap-pkg input-remapper
    # Presets/config live under ~/.config; v2 uses input-remapper-2 (older builds
    # used plain input-remapper). Both are user-owned, so no sudo needed.
    reclaim inputremap-cfg2 "$HOME/.config/input-remapper-2"
    reclaim inputremap-cfg  "$HOME/.config/input-remapper"
    say "    · removed. The Razer side keys now come from the mouse's onboard memory"
    say "      (set via Razer Synapse on Windows), so no remapper is needed on Linux."
}

do_extras() {
    say ">>> Unused apps (Zed, Dolphin, Inkscape, Kate, HyprKCS) + their home data"
    # All were explicitly installed with nothing depending on them (Required By:
    # None), so -Rns is safe; it also sweeps now-orphaned deps (e.g. the hyprkcs
    # debug split). Dolphin goes because the daily file manager here is nautilus.
    remove_pkgs extras-pkgs zed dolphin inkscape kate hyprkcs-git hyprkcs-git-debug
    # The home-side config/cache/state pacman never tracks (see the package-management
    # Learn page) — clear it so the removal is truly clean.
    reclaim zed-config   "$HOME/.config/zed"
    reclaim zed-cache    "$HOME/.cache/zed"
    reclaim zed-share    "$HOME/.local/share/zed"
    reclaim dolphin-rc   "$HOME/.config/dolphinrc"
    reclaim dolphin-share "$HOME/.local/share/dolphin"
    reclaim dolphin-state "$HOME/.local/state/dolphinstaterc"
    reclaim dolphin-fb   "$HOME/.local/state/UserFeedback.org.kde.dolphin"
    reclaim inkscape-cfg "$HOME/.config/inkscape"
    reclaim kate-config  "$HOME/.config/kate"
    reclaim kate-rc      "$HOME/.config/katerc"
    reclaim kate-virc    "$HOME/.config/katevirc"
    reclaim kate-tools   "$HOME/.config/kate-externaltoolspluginrc"
    reclaim kate-share   "$HOME/.local/share/kate"
    reclaim kate-state   "$HOME/.local/state/katestaterc"
    reclaim kate-fb      "$HOME/.local/state/UserFeedback.org.kde.kate"
    reclaim hyprkcs-cfg  "$HOME/.config/hyprkcs"
}

do_fastfetch() {
    # Reverts fastfetch back to the OS ASCII logo. We keep the helper binary
    # (~/.local/bin/fastfetch-logo) and the chafa/ffmpeg packages — they're
    # cheap and any future logo set goes through the same helper. Use the
    # helper's own --none flag when present (it knows to unwind the
    # fish_greeting animation hook too); otherwise fall back to a manual sweep.
    if [ "$DRY_RUN" -eq 1 ]; then
        say "    [dry-run] fastfetch-logo --none  (or manual sweep if helper missing)"
        return 0
    fi
    if [ -x "$HOME/.local/bin/fastfetch-logo" ]; then
        "$HOME/.local/bin/fastfetch-logo" --none
    else
        local cfg="$HOME/.config/fastfetch/config.jsonc"
        if [ -f "$cfg" ] && command -v jq >/dev/null; then
            local tmp; tmp=$(mktemp)
            jq '.logo = null' "$cfg" > "$tmp" && mv "$tmp" "$cfg"
        fi
        rm -f "$HOME/.config/fastfetch/logo.sixel" \
              "$HOME/.config/fastfetch"/animated.{gif,mp4,webm,mkv,mov} 2>/dev/null || true
        # Strip the fish_greeting marker + the chafa playback line just below it.
        local fg="$HOME/.config/fish/functions/fish_greeting.fish"
        [ -f "$fg" ] && sed -i '/fastfetch-logo: animated playback/,+1d' "$fg"
    fi
    say "    · fastfetch logo cleared. Helper at ~/.local/bin/fastfetch-logo stays."
}

do_tablet() {
    say ">>> Weylus + uinput plumbing"
    # Drop whichever weylus variant landed (install.sh uses weylus-community-bin,
    # but if someone built from source via 'weylus' or pulled 'weylus-bin' we
    # clean those too — they all conflict and only one can be present at a time).
    remove_pkgs weylus-pkgs weylus-community-bin weylus-bin weylus weylus-git weylus-community-git
    # uinput artefacts the install component wrote.
    [ -f /etc/udev/rules.d/60-weylus-uinput.rules ] && \
        run weylus-udev sudo rm -f /etc/udev/rules.d/60-weylus-uinput.rules
    [ -f /etc/modules-load.d/uinput.conf ] && \
        run weylus-modules sudo rm -f /etc/modules-load.d/uinput.conf
    # Drop the user from the uinput group; remove the group itself if it ends up
    # empty (so the next 'tablet' install starts from a clean slate).
    if id -nG "$USER_NAME" 2>/dev/null | tr ' ' '\n' | grep -qx uinput; then
        run weylus-group sudo gpasswd -d "$USER_NAME" uinput
    else
        say "    · $USER_NAME not in uinput group — skip"
    fi
    if getent group uinput >/dev/null 2>&1; then
        local members; members=$(getent group uinput | awk -F: '{print $4}')
        if [ -z "$members" ]; then
            run weylus-group-del sudo groupdel uinput
        else
            say "    · uinput group still has members ($members) — leaving it"
        fi
    fi
    # Reload udev so the (now-removed) rule stops applying; the uinput device node
    # reverts to root-only on next boot. modprobe -r is fine but not required.
    if [ "$DRY_RUN" -eq 0 ]; then
        sudo udevadm control --reload-rules 2>/dev/null || true
    fi
    # Weylus state (per-user access codes, certificates) — small but worth clearing
    # for a clean removal.
    reclaim weylus-state  "$HOME/.local/share/weylus"
    reclaim weylus-config "$HOME/.config/weylus"
    say "    · removed. gst-plugin-pipewire stays (other apps use it)."
    say "    · the group change needs a fresh login to take effect."
}

# ---- arg parsing ------------------------------------------------------------
SELECTED=()
ALL_NAMES=(); for row in "${COMPONENTS[@]}"; do ALL_NAMES+=("${row%%|*}"); done

is_component() { local n; for n in "${ALL_NAMES[@]}"; do [ "$n" = "$1" ] && return 0; done; return 1; }

for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        -y|--yes)  ASSUME_YES=1 ;;
        all)       SELECTED=("${ALL_NAMES[@]}") ;;
        -h|--help)
            say "usage: uninstall.sh [--dry-run] [--yes] [all | <component>...]"
            say "components: ${ALL_NAMES[*]}"; exit 0 ;;
        *)
            if is_component "$arg"; then SELECTED+=("$arg")
            else say "Unknown component '$arg'. Known: ${ALL_NAMES[*]}"; exit 1; fi ;;
    esac
done

# ---- interactive menu (no components on the command line) -------------------
if [ "${#SELECTED[@]}" -eq 0 ]; then
    hr; say "Interactive uninstaller — pick what to remove."
    [ "$DRY_RUN" -eq 1 ] && say "(dry-run: nothing will actually be removed)"
    hr
    i=1
    for row in "${COMPONENTS[@]}"; do
        say "  $i) ${row%%|*} — ${row#*|}"
        i=$((i+1))
    done
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

# De-duplicate while preserving order.
UNIQ=(); for s in "${SELECTED[@]}"; do
    case " ${UNIQ[*]} " in *" $s "*) ;; *) UNIQ+=("$s") ;; esac
done
SELECTED=("${UNIQ[@]}")

# ---- confirm + run ----------------------------------------------------------
hr
say "Will uninstall: ${SELECTED[*]}"
[ "$DRY_RUN" -eq 1 ] && say "Mode: DRY-RUN (no changes)."
hr
if [ "$ASSUME_YES" -eq 0 ] && [ "$DRY_RUN" -eq 0 ]; then
    read -rp "Proceed? This removes packages and deletes data. [y/N]: " ok
    case "$ok" in y|Y|yes|YES) ;; *) say "Aborted."; exit 0 ;; esac
fi

for name in "${SELECTED[@]}"; do
    hr
    "do_${name}"
done

# ---- summary ----------------------------------------------------------------
hr
if [ "$DRY_RUN" -eq 1 ]; then
    say "Dry-run complete — nothing was changed."
else
    say "Done. Approx space reclaimed: $(human_kb "$RECLAIMED_KB")."
    if [ "${#FAILED[@]}" -eq 0 ]; then
        say "All steps succeeded."
    else
        say "Completed with issues in: ${FAILED[*]}"
        say "Re-run is safe — already-removed pieces are skipped."
    fi
    say "If you removed 'docker', log out/in once so the dropped group takes effect."
fi
