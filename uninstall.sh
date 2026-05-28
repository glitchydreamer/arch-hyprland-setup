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
    "isaac|Isaac Sim container caches, the IsaacLab clone, the isaac-sim launcher, xorg-xauth"
    "ros2|The ros2-jazzy launcher + its Docker image (image only if Docker is still present)"
    "anaconda|Anaconda (AUR) + the conda fish init; leaves your project envs' data under ~/anaconda3 if external"
    "cuda|CUDA toolkit + cuDNN + the /etc/profile.d/cuda.sh PATH (leaves the NVIDIA driver alone)"
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
    say ">>> ROS 2 Jazzy (container wrapper)"
    # Remove the cached image first (only possible while docker is still here).
    if command -v docker >/dev/null 2>&1; then
        if docker image inspect osrf/ros:jazzy-desktop-full >/dev/null 2>&1; then
            run ros2-image docker rmi osrf/ros:jazzy-desktop-full
        else
            say "    · ros2 image not pulled — skip"
        fi
    else
        say "    · docker already gone — its images went with it"
    fi
    reclaim ros2-launcher "$HOME/.local/bin/ros2-jazzy"
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
