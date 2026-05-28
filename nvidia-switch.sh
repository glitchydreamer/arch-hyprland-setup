#!/usr/bin/env bash
# ============================================================================
# nvidia-switch.sh — switch the WHOLE NVIDIA stack (driver + userspace, and
# optionally CUDA/cuDNN) between the rolling "latest" and a pinned older
# version, or purge it entirely. Built to make Isaac Sim / Isaac Lab usable on
# Arch by dropping to the driver Isaac validates (580.x) and back.
#
#     bash ~/Documents/arch-hyprland-setup/nvidia-switch.sh              # menu
#     bash ~/Documents/arch-hyprland-setup/nvidia-switch.sh status       # report
#     bash ~/Documents/arch-hyprland-setup/nvidia-switch.sh downgrade    # -> 580.76.05
#     bash ~/Documents/arch-hyprland-setup/nvidia-switch.sh downgrade 580.95.05
#     bash ~/Documents/arch-hyprland-setup/nvidia-switch.sh latest       # -> repo newest
#     bash ~/Documents/arch-hyprland-setup/nvidia-switch.sh purge        # remove ALL nvidia
#     bash ~/Documents/arch-hyprland-setup/nvidia-switch.sh --dry-run downgrade
#
# Flags:  --dry-run  print every command, change nothing.
#         --yes/-y   skip confirmations (still prints the plan + recovery note).
#         --with-cuda  also move CUDA/cuDNN (default: leave them; CUDA 13.x runs
#                      on driver 580, so they usually don't need to move).
#
# WHY this is more dangerous than the other scripts in this repo: NVIDIA drives
# the display (early-KMS MODULES in the initramfs + nvidia_drm.modeset=1 +
# systemd-boot). A bad swap can leave you at a black screen. So:
#   * every package swap is ONE atomic `pacman -U`/`-S` transaction — the system
#     is never left without a driver mid-step (except `purge`, which is meant to);
#   * the initramfs is rebuilt and the boot default is steered every time;
#   * a recovery note is printed BEFORE you reboot. Read it.
#
# WHY a downgrade also drags in a second kernel: driver 580 will NOT build
# against the bleeding-edge `linux` kernel (7.0), so `downgrade` installs
# `linux-lts` + `nvidia-open-dkms` (dkms recompiles the module per-kernel) and
# makes linux-lts the boot default. `nvidia-utils` is a single GLOBAL version, so
# after a downgrade the WHOLE system runs on 580 until you switch back — you
# can't run 595 on one kernel and 580 on another.
#
# Run as your normal user (it calls sudo itself). Read-only `status` needs no sudo.
# ============================================================================
set -uo pipefail

if [ "$(id -u)" -eq 0 ]; then
    echo "Run as your normal user, not root (the script calls sudo itself)." >&2
    exit 1
fi

DRY_RUN=0
ASSUME_YES=0
WITH_CUDA=0
FAILED=()

# Default downgrade target: the closest 580.x Arch ever packaged to Isaac Sim
# 5.1's validated 580.65.06 (Arch never shipped exactly .65.06). Override by
# passing a version, e.g. `downgrade 580.95.05`.
DEFAULT_NV_VER="580.76.05"

# Packages that make up the NVIDIA userspace (one global version, shared by all
# kernels). The kernel-module package differs: prebuilt `nvidia-open` for the
# repo-latest path, `nvidia-open-dkms` for the pinned-older path.
NV_USERSPACE=(nvidia-utils lib32-nvidia-utils opencl-nvidia)

PACMAN_CONF=/etc/pacman.conf
MKINITCPIO=/etc/mkinitcpio.conf
PIN_BEGIN="# >>> nvidia-switch pin >>>"
PIN_END="# <<< nvidia-switch pin <<<"

# This machine boots a Unified Kernel Image (UKI): mkinitcpio presets bundle
# kernel+initramfs+cmdline into a single .efi under /boot/EFI/Linux/, which
# systemd-boot auto-discovers (there are no type-1 loader entries). The boot
# default is therefore selected by UKI filename ("id"), e.g. arch-linux.efi.
EFI_LINUX_DIR=/boot/EFI/Linux
LINUX_UKI_ID="arch-linux.efi"
LTS_UKI_ID="arch-linux-lts.efi"
LTS_PRESET=/etc/mkinitcpio.d/linux-lts.preset
# This machine's bootloader is Limine (manual config — its pacman hook only
# redeploys the EFI binaries, it does NOT generate entries). Limine does not
# auto-discover the UKIs under /boot/EFI/Linux, so an entry must be added by hand.
# bootctl/systemd-boot is kept as a fallback for other machines.
LIMINE_CONF=/boot/limine/limine.conf

# ---- helpers ----------------------------------------------------------------
say() { echo -e "$*"; }
hr()  { echo "------------------------------------------------------------"; }

# echo + run (unless dry-run); record FAILED tag but never abort.
run() {
    local tag="$1"; shift
    if [ "$DRY_RUN" -eq 1 ]; then say "    [dry-run] $*"; return 0; fi
    say "    + $*"
    "$@" || FAILED+=("$tag")
}
# same, but the command is a shell string (pipes / redirection / sudo tee).
run_sh() {
    local tag="$1"; shift
    if [ "$DRY_RUN" -eq 1 ]; then say "    [dry-run] $*"; return 0; fi
    say "    + $*"
    bash -c "$*" || FAILED+=("$tag")
}

# Resolve the Arch Linux Archive download URL for <pkg> at <pkgver>, picking the
# highest pkgrel available. Echoes the URL or nothing.
ala_url() {
    local p="$1" ver="$2" letter="${1:0:1}" file
    file=$(curl -fsSL "https://archive.archlinux.org/packages/$letter/$p/" 2>/dev/null \
        | grep -oE "${p}-${ver}-[0-9]+-x86_64\.pkg\.tar\.zst" \
        | sort -V | tail -1)
    [ -n "$file" ] && echo "https://archive.archlinux.org/packages/$letter/$p/$file"
}

# Add the IgnorePkg pin block (idempotent). Args: the package names to pin.
add_pin() {
    local pkgs="$*"
    if grep -qF "$PIN_BEGIN" "$PACMAN_CONF" 2>/dev/null; then
        say "    · pin block already present — refreshing it"
        del_pin
    fi
    say "    · pinning (IgnorePkg) so -Syu won't undo the swap: $pkgs"
    if [ "$DRY_RUN" -eq 1 ]; then say "    [dry-run] insert IgnorePkg block after [options]"; return; fi
    # Insert right after the [options] header so it's in the active section.
    local block
    printf -v block '%s\\nIgnorePkg = %s\\n%s' "$PIN_BEGIN" "$pkgs" "$PIN_END"
    sudo sed -i "0,/^\[options\]/s//[options]\n$block/" "$PACMAN_CONF" \
        || FAILED+=("pin-add")
}

# Remove our pin block (leaves any other IgnorePkg lines, e.g. the PipeWire pin).
del_pin() {
    grep -qF "$PIN_BEGIN" "$PACMAN_CONF" 2>/dev/null || { say "    · no nvidia pin to remove"; return; }
    say "    · removing the nvidia IgnorePkg pin block"
    if [ "$DRY_RUN" -eq 1 ]; then say "    [dry-run] sed -i delete pin block"; return; fi
    sudo sed -i "/$PIN_BEGIN/,/$PIN_END/d" "$PACMAN_CONF" || FAILED+=("pin-del")
}

# Rebuild the initramfs / UKIs for every installed kernel preset (early-KMS
# nvidia modules get re-embedded). `mkinitcpio -P` walks all presets in
# /etc/mkinitcpio.d, so this regenerates arch-linux.efi (and arch-linux-lts.efi
# once its preset is UKI-enabled by ensure_lts_uki_preset).
regen_initramfs() { run mkinitcpio sudo mkinitcpio -P; }

# Give linux-lts its own UKI preset, mirroring the linux preset, so `mkinitcpio
# -P` produces a *bootable* /boot/EFI/Linux/arch-linux-lts.efi. The stock
# linux-lts.preset emits a bare initramfs .img that systemd-boot can't boot on a
# UKI-only setup. Idempotent: skips if the preset already targets a UKI.
ensure_lts_uki_preset() {
    [ -f "$LTS_PRESET" ] || { say "    ! $LTS_PRESET missing (is linux-lts installed?) — skip UKI preset"; return; }
    if grep -qE '^[[:space:]]*default_uki=' "$LTS_PRESET"; then
        say "    · linux-lts already has a UKI preset — leaving it"
        return
    fi
    say "    · rewriting $LTS_PRESET to emit a UKI ($LTS_UKI_ID)"
    if [ "$DRY_RUN" -eq 1 ]; then say "    [dry-run] write UKI preset for linux-lts"; return; fi
    sudo tee "$LTS_PRESET" >/dev/null <<EOF
# mkinitcpio preset for 'linux-lts' — UKI output (managed by nvidia-switch.sh)
ALL_kver="/boot/vmlinuz-linux-lts"
PRESETS=('default')
default_uki="$EFI_LINUX_DIR/$LTS_UKI_ID"
default_options="--splash /usr/share/systemd/bootctl/splash-arch.bmp"
EOF
    [ $? -eq 0 ] || FAILED+=("lts-uki-preset")
}

# Remove an installed NVIDIA kernel-module package that would otherwise block the
# swap. pacman will NOT auto-remove a version-pinned conflicting package under
# --noconfirm (the prebuilt `nvidia-open` hard-pins `nvidia-utils=<its version>`,
# so downgrading nvidia-utils is rejected with "breaks dependency ... required by
# nvidia-open"). Removing it first clears that; the *running* module stays loaded
# in RAM until reboot, so the desktop keeps working. -Rdd skips the dep check
# (the pinned dep is exactly what we're changing; the pkg is a leaf).
remove_module_pkg() {
    local tag="$1"; shift
    local present; present=$(installed_of "$@")
    if [ -z "$present" ]; then say "    · no conflicting module pkg of [$*] installed — skip"; return; fi
    say "    · removing conflicting module pkg(s): $present (running module persists in RAM)"
    run "$tag" sudo pacman -Rdd --noconfirm $present
}

# Which bootloader is in use? Limine (manual config) here; bootctl elsewhere.
boot_kind() {
    [ -f "$LIMINE_CONF" ] && { echo limine; return; }
    command -v bootctl >/dev/null 2>&1 && { echo systemd-boot; return; }
    echo unknown
}

# Add a "Arch Linux (linux-lts)" entry to limine.conf, cloning the cmdline from
# the existing linux entry (so root=, modeset, etc. carry over). Idempotent.
limine_ensure_lts_entry() {
    grep -q "$LTS_UKI_ID" "$LIMINE_CONF" 2>/dev/null && { say "    · limine linux-lts entry already present"; return; }
    local cmdline; cmdline=$(grep -m1 -E '^[[:space:]]*cmdline:' "$LIMINE_CONF" | sed -E 's/^[[:space:]]*cmdline:[[:space:]]*//')
    say "    · adding 'Arch Linux (linux-lts)' entry to $LIMINE_CONF"
    if [ "$DRY_RUN" -eq 1 ]; then say "    [dry-run] append lts entry (cmdline: $cmdline)"; return; fi
    sudo tee -a "$LIMINE_CONF" >/dev/null <<EOF

/Arch Linux (linux-lts)
    protocol: efi
    path: boot():/EFI/Linux/$LTS_UKI_ID
    cmdline: $cmdline
EOF
    [ $? -eq 0 ] || FAILED+=("limine-lts-entry")
}

# Set Limine's default_entry (1-based, by file order of top-level '/' entries).
# Arg: "lts" or "linux". Manages a single top-level default_entry: directive.
limine_set_default() {
    local want="$1" n=0 target=0 line
    while IFS= read -r line; do
        case "$line" in
            /*) n=$((n+1))
                if [ "$want" = lts ]   && printf '%s' "$line" | grep -q 'linux-lts' && [ "$target" -eq 0 ]; then target=$n; fi
                if [ "$want" = linux ] && ! printf '%s' "$line" | grep -q 'linux-lts' && [ "$target" -eq 0 ]; then target=$n; fi
                ;;
        esac
    done < "$LIMINE_CONF"
    if [ "$target" -eq 0 ]; then
        if [ "$DRY_RUN" -eq 1 ]; then
            say "    [dry-run] would set default_entry to the $want entry (added just above)"; return
        fi
        say "    ! couldn't find the $want entry in limine.conf — set default manually."; FAILED+=("limine-default"); return
    fi
    say "    · limine default_entry -> $target ($want)"
    if [ "$DRY_RUN" -eq 1 ]; then return; fi
    if grep -qE '^[[:space:]]*default_entry:' "$LIMINE_CONF"; then
        sudo sed -i -E "s/^[[:space:]]*default_entry:.*/default_entry: $target/" "$LIMINE_CONF" || FAILED+=("limine-default")
    else
        sudo sed -i "1i default_entry: $target" "$LIMINE_CONF" || FAILED+=("limine-default")
    fi
}

# Steer the boot default to the wanted kernel. Arg: "lts" or "" (=linux).
# Dispatches on the bootloader. For the target UKI it refuses to set a default
# that points at a non-existent image (would be unbootable).
set_boot_default() {
    local want="$1" id img kind
    if [ "$want" = "lts" ]; then id="$LTS_UKI_ID"; else id="$LINUX_UKI_ID"; fi
    img="$EFI_LINUX_DIR/$id"
    say "    · discovered UKIs:"; ls -1 "$EFI_LINUX_DIR"/*.efi 2>/dev/null | sed 's/^/        /'
    if [ "$DRY_RUN" -ne 1 ] && [ ! -f "$img" ]; then
        say "    ! $img does not exist — NOT changing the boot default (would be unbootable)."
        FAILED+=("boot-default:no-uki"); return
    fi
    kind=$(boot_kind); say "    · bootloader: $kind"
    case "$kind" in
        limine)
            [ "$want" = "lts" ] && limine_ensure_lts_entry
            limine_set_default "${want:-linux}"
            say "    · (Limine timeout is shown so you can pick the other kernel for recovery)" ;;
        systemd-boot)
            run bootctl-default sudo bootctl set-default "$id"; say "    · boot default -> $id" ;;
        *)  say "    ! unknown bootloader — set your default to boot $id manually." ;;
    esac
}

# Print only the installed subset of a package list (so -R/-U don't choke).
installed_of() { local p; for p in "$@"; do pacman -Qq "$p" >/dev/null 2>&1 && echo "$p"; done; }

confirm() {  # $1 = prompt; honours --yes
    [ "$ASSUME_YES" -eq 1 ] && return 0
    [ "$DRY_RUN" -eq 1 ] && return 0
    local ok; read -rp "$1 [y/N]: " ok
    case "$ok" in y|Y|yes|YES) return 0 ;; *) say "Aborted."; return 1 ;; esac
}

# ============================================================================
# Actions
# ============================================================================

do_status() {
    hr; say ">>> NVIDIA stack status"; hr
    say "Booted kernel:   $(uname -r)"
    say "Driver (smi):    $(command -v nvidia-smi >/dev/null && nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null || echo 'n/a — no module loaded')"
    say "Max CUDA (smi):  $(command -v nvidia-smi >/dev/null && (nvidia-smi 2>/dev/null | grep -oP 'CUDA Version:\s*\K[0-9.]+' | head -1) || echo n/a)"
    say ""
    say "Installed packages:"
    local p
    for p in nvidia-open nvidia-open-dkms nvidia-utils lib32-nvidia-utils opencl-nvidia nvidia-settings cuda cudnn; do
        printf '    %-22s %s\n' "$p" "$(pacman -Q "$p" 2>/dev/null | awk '{print $2}' || echo '-')"
    done
    say ""
    say "Kernels / dkms:"
    for p in linux linux-headers linux-lts linux-lts-headers dkms; do
        printf '    %-22s %s\n' "$p" "$(pacman -Q "$p" 2>/dev/null | awk '{print $2}' || echo '-')"
    done
    command -v dkms >/dev/null 2>&1 && { say "    dkms status:"; dkms status 2>/dev/null | sed 's/^/        /'; }
    say ""
    say "initramfs MODULES line: $(grep -E '^MODULES=' "$MKINITCPIO" 2>/dev/null)"
    say "nvidia IgnorePkg pin:   $(grep -A1 "$PIN_BEGIN" "$PACMAN_CONF" 2>/dev/null | grep IgnorePkg || echo 'none')"
    say "UKIs present:           $(ls -1 "$EFI_LINUX_DIR"/*.efi 2>/dev/null | xargs -r -n1 basename | paste -sd' ' - || echo none)"
    say ""
    say "Bootloader: $(boot_kind)"
    if [ -f "$LIMINE_CONF" ]; then
        say "  limine entries / default:"
        { grep -nE '^[[:space:]]*default_entry:|^/' "$LIMINE_CONF" 2>/dev/null | sed 's/^/    /'; } || true
    elif command -v bootctl >/dev/null 2>&1; then
        bootctl list 2>/dev/null | grep -iE 'title|default' | sed 's/^/    /' | head -20
    fi
    hr
}

do_downgrade() {
    local ver="${1:-$DEFAULT_NV_VER}"
    hr; say ">>> DOWNGRADE the NVIDIA stack to $ver (for Isaac Sim / Lab)"; hr
    say "This will, in order:"
    say "  1. install linux-lts + linux-lts-headers + dkms (additive; your current"
    say "     'linux' $(pacman -Q linux 2>/dev/null | awk '{print $2}') kernel stays installed),"
    say "  2. atomically swap nvidia-open(prebuilt)+595 userspace -> nvidia-open-dkms"
    say "     $ver + matching nvidia-utils/lib32/opencl from the Arch Linux Archive,"
    [ "$WITH_CUDA" -eq 1 ] && say "  2b. also move cuda+cudnn to the $ver-era archive (--with-cuda),"
    say "  3. pin all of it (IgnorePkg) so -Syu can't pull it back to 595,"
    say "  4. rebuild the initramfs and make linux-lts the boot default."
    say ""
    say "AFTER THIS: the whole system runs on driver $ver. Your 'linux' 7.0 entry"
    say "will have NO nvidia module (580 can't build on 7.0) — boot linux-lts. Keep"
    say "the 'linux' entry only as a TTY recovery option. Revert with: latest"
    say ""
    confirm "Proceed with the downgrade to $ver?" || return

    # 0. clear any stale pin from a previous (possibly failed) run so it can't
    # block the -Syu/-U below with IgnorePkg prompts. Re-pinned after success.
    say "\n### 0/4  clear any stale nvidia pin"
    del_pin

    # 1. second kernel + dkms (full sync = the Arch-correct, no-partial-upgrade way)
    say "\n### 1/4  linux-lts + headers + dkms"
    run kernel-lts sudo pacman -Syu --needed --noconfirm linux-lts linux-lts-headers dkms

    # 2. resolve ALA URLs for the whole 580 set, then ONE atomic transaction.
    say "\n### 2/4  resolve $ver packages from the Arch Linux Archive"
    local urls=() u missing=0
    for p in nvidia-open-dkms "${NV_USERSPACE[@]}"; do
        u=$(ala_url "$p" "$ver")
        if [ -n "$u" ]; then say "    · $p -> $u"; urls+=("$u")
        else say "    ! could not find $p-$ver in the archive"; missing=1; fi
    done
    if [ "$WITH_CUDA" -eq 1 ]; then
        say "    (cuda/cudnn move requested — resolving newest archived builds <= driver era)"
        say "    ! NOTE: pick cuda/cudnn versions by hand if the auto-pick is wrong; CUDA 13.x"
        say "    ! already runs on driver 580, so leaving them is usually fine."
    fi
    if [ "$missing" -eq 1 ]; then
        say "    ! aborting: not all $ver packages are in the archive. Try another 580.x"
        say "    ! (see https://archive.archlinux.org/packages/n/nvidia-utils/)."
        FAILED+=("downgrade:missing-pkgs"); return
    fi
    say "\n### swap to $ver"
    # Remove the prebuilt nvidia-open first (pacman won't auto-remove a
    # version-pinned conflict under --noconfirm — see remove_module_pkg). Then -U
    # the 580 set: pacman fetches each pkg + .sig, verifies, and downgrades the
    # userspace + installs the dkms module in one transaction. dkms builds the 580
    # module for linux-lts (its attempt against 'linux' 7.0 may fail — expected,
    # which is exactly why you boot linux-lts).
    remove_module_pkg nv-rm-open nvidia-open nvidia
    run nv-swap sudo pacman -U --noconfirm "${urls[@]}"

    # verify the swap actually applied before pinning / touching boot. If not,
    # restore nvidia-open so the system stays consistent on 595.
    if [ "$DRY_RUN" -ne 1 ] && ! pacman -Qq nvidia-open-dkms >/dev/null 2>&1; then
        say "    ! SWAP FAILED — nvidia-open-dkms is not installed."
        say "    ! restoring nvidia-open to keep the system consistent on the current driver..."
        sudo pacman -S --needed --noconfirm nvidia-open || say "    ! restore also failed — run 'nvidia-switch.sh latest' from a TTY."
        FAILED+=("downgrade:swap-failed")
        say "    ! aborting the downgrade (no pin, no boot change made)."
        return
    fi

    # 3. pin (only reached on a verified swap)
    say "\n### 3/4  pin the swapped packages"
    local pin_set=(nvidia-open-dkms "${NV_USERSPACE[@]}")
    [ "$WITH_CUDA" -eq 1 ] && pin_set+=(cuda cudnn)
    add_pin "${pin_set[@]}"

    # 4. UKI preset for linux-lts + rebuild + boot default
    say "\n### 4/4  linux-lts UKI + initramfs + boot default -> linux-lts"
    ensure_lts_uki_preset
    regen_initramfs
    set_boot_default lts

    hr
    say "DOWNGRADE staged. RECOVERY NOTE — read before rebooting:"
    say "  * Reboot and pick the linux-lts entry (it's now the default)."
    say "  * If the desktop doesn't come up, at the boot menu choose the 'linux'"
    say "    7.0 entry to reach a TTY, then run:  nvidia-switch.sh latest"
    say "  * Verify after reboot:  nvidia-smi   (should read $ver)"
    say "  * Then test Isaac: native BINARY download first; if Arch userspace"
    say "    breaks it, fall back to the Docker container (toolkit injects 580)."
}

do_latest() {
    hr; say ">>> RESTORE the NVIDIA stack to the repo-latest (prebuilt nvidia-open)"; hr
    say "Removes the version pin, pulls the newest nvidia-open + userspace from the"
    say "official repos (resolves nvidia-open-dkms -> nvidia-open), rebuilds the"
    say "initramfs, and points the boot default back at the 'linux' kernel."
    say "linux-lts/dkms are LEFT installed (harmless); remove later with uninstall.sh."
    say ""
    confirm "Proceed back to repo-latest NVIDIA?" || return

    say "\n### 1/3  drop the pin, then sync to repo-latest"
    del_pin
    # Remove the dkms module first (same conflict reason as the downgrade, in
    # reverse), then full-sync the repo-latest prebuilt set. Running module stays
    # in RAM until reboot.
    remove_module_pkg nv-rm-dkms nvidia-open-dkms
    run nv-latest sudo pacman -Syu --needed --noconfirm \
        nvidia-open nvidia-utils lib32-nvidia-utils opencl-nvidia
    if [ "$WITH_CUDA" -eq 1 ]; then
        say "    · restoring cuda + cudnn to repo-latest"
        run cuda-latest sudo pacman -S --needed --noconfirm cuda cudnn
    fi

    say "\n### 2/3  rebuild initramfs"
    regen_initramfs

    say "\n### 3/3  boot default -> linux"
    set_boot_default ""

    hr
    say "RESTORED. Reboot into the 'linux' kernel, then verify:  nvidia-smi"
}

do_purge() {
    hr; say ">>> PURGE — remove EVERYTHING NVIDIA (driver, userspace, CUDA, cuDNN)"; hr
    say "!!  This leaves the machine with NO GPU driver. GDM / Hyprland / Wayland"
    say "!!  will NOT start after a reboot until you reinstall (run 'latest')."
    say "!!  Do this from a TTY, and reinstall before you reboot into the desktop."
    say ""
    if [ "$ASSUME_YES" -eq 0 ] && [ "$DRY_RUN" -eq 0 ]; then
        local phrase; read -rp "Type  PURGE NVIDIA  to confirm: " phrase
        [ "$phrase" = "PURGE NVIDIA" ] || { say "Aborted."; return; }
    fi

    say "\n### 1/4  drop the pin"
    del_pin

    say "\n### 2/4  remove nvidia + cuda packages"
    local pkgs; mapfile -t pkgs < <(installed_of \
        nvidia-open nvidia-open-dkms nvidia-utils lib32-nvidia-utils \
        opencl-nvidia nvidia-settings cuda cudnn)
    if [ "${#pkgs[@]}" -eq 0 ]; then
        say "    · nothing nvidia/cuda installed — skip"
    else
        say "    · removing: ${pkgs[*]}"
        run nv-purge sudo pacman -Rns --noconfirm "${pkgs[@]}"
    fi
    run cuda-profile sudo rm -f /etc/profile.d/cuda.sh

    say "\n### 3/4  strip nvidia early-KMS modules from the initramfs config"
    if grep -qE '^MODULES=.*nvidia' "$MKINITCPIO" 2>/dev/null; then
        # Surgically drop only the nvidia tokens (keeps any other modules), then
        # tidy the leftover spaces inside the parens.
        run_sh mkinitcpio-modules \
            "sudo sed -i -E 's/[[:space:]]*nvidia(_modeset|_uvm|_drm)?//g; s/MODULES=\\([[:space:]]+/MODULES=(/; s/[[:space:]]+\\)/)/' $MKINITCPIO"
        say "    · MODULES now: $(grep -E '^MODULES=' "$MKINITCPIO" 2>/dev/null)"
    else
        say "    · no nvidia entries in MODULES — skip"
    fi
    regen_initramfs

    say "\n### 4/4  done"
    hr
    say "PURGED. (nvidia_drm.modeset=1 may remain on the kernel cmdline — harmless"
    say "with no driver; remove it from your bootloader config if you like.)"
    say "Reinstall BEFORE rebooting into the GUI:  nvidia-switch.sh latest"
}

# ============================================================================
# Arg parsing + menu
# ============================================================================
ACTIONS=(
    "status|Read-only report: driver, packages, kernels, dkms, pin, boot default"
    "downgrade|Switch the whole stack to 580.x (+ linux-lts) for Isaac Sim / Lab"
    "latest|Restore the repo-latest NVIDIA (prebuilt nvidia-open) + boot linux"
    "purge|Remove ALL nvidia + CUDA (leaves NO driver — TTY/recovery only)"
)
ALL_NAMES=(); for row in "${ACTIONS[@]}"; do ALL_NAMES+=("${row%%|*}"); done
is_action() { local n; for n in "${ALL_NAMES[@]}"; do [ "$n" = "$1" ] && return 0; done; return 1; }

ACTION=""
ARG=""
for a in "$@"; do
    case "$a" in
        --dry-run)   DRY_RUN=1 ;;
        -y|--yes)    ASSUME_YES=1 ;;
        --with-cuda) WITH_CUDA=1 ;;
        -h|--help)
            say "usage: nvidia-switch.sh [--dry-run] [--yes] [--with-cuda] <action> [version]"
            say "actions: ${ALL_NAMES[*]}"; exit 0 ;;
        *)
            if is_action "$a"; then ACTION="$a"
            elif [ -n "$ACTION" ] && [ -z "$ARG" ]; then ARG="$a"   # version for downgrade
            else say "Unknown argument '$a'. Actions: ${ALL_NAMES[*]}"; exit 1; fi ;;
    esac
done

if [ -z "$ACTION" ]; then
    hr; say "NVIDIA stack switcher — pick an action."
    [ "$DRY_RUN" -eq 1 ] && say "(dry-run: nothing will actually change)"
    hr
    i=1; for row in "${ACTIONS[@]}"; do say "  $i) ${row%%|*} — ${row#*|}"; i=$((i+1)); done
    say "  q) quit"; hr
    read -rp "Enter a number or action name: " reply
    case "$reply" in
        q|Q|"") say "Nothing selected — exiting."; exit 0 ;;
        *)
            if [[ "$reply" =~ ^[0-9]+$ ]] && [ "$reply" -ge 1 ] && [ "$reply" -le "${#ALL_NAMES[@]}" ]; then
                ACTION="${ALL_NAMES[$((reply-1))]}"
            elif is_action "$reply"; then ACTION="$reply"
            else say "Invalid choice."; exit 1; fi ;;
    esac
fi

[ "$DRY_RUN" -eq 1 ] && { hr; say "Mode: DRY-RUN (no changes)."; }

case "$ACTION" in
    status)    do_status ;;
    downgrade) do_downgrade "$ARG" ;;
    latest)    do_latest ;;
    purge)     do_purge ;;
esac

hr
if [ "${#FAILED[@]}" -eq 0 ]; then
    say "Action '$ACTION' completed."
else
    say "Action '$ACTION' completed with issues in: ${FAILED[*]}"
    say "Re-run is safe — pins/packages already in the target state are skipped."
fi
[ "$DRY_RUN" -eq 1 ] && say "(dry-run: nothing was changed)"
exit 0
