#!/usr/bin/env bash
# ============================================================================
# nvidia-switch.sh — switch the WHOLE NVIDIA stack (driver + userspace, and
# optionally CUDA/cuDNN) between the rolling "latest" and a pinned older
# version, or purge it entirely. Built to make Isaac Sim / Isaac Lab usable on
# Arch by dropping to the driver Isaac validates (580.x) and back.
#
#     bash ~/Documents/arch-hyprland-setup/nvidia-switch.sh              # menu
#     bash ~/Documents/arch-hyprland-setup/nvidia-switch.sh status       # report
#     bash ~/Documents/arch-hyprland-setup/nvidia-switch.sh downgrade    # -> 580.119.02
#     bash ~/Documents/arch-hyprland-setup/nvidia-switch.sh downgrade 580.95.05
#     bash ~/Documents/arch-hyprland-setup/nvidia-switch.sh latest       # -> repo newest
#     bash ~/Documents/arch-hyprland-setup/nvidia-switch.sh cuda         # align CUDA to driver
#     bash ~/Documents/arch-hyprland-setup/nvidia-switch.sh purge        # remove ALL nvidia
#     bash ~/Documents/arch-hyprland-setup/nvidia-switch.sh --dry-run downgrade
#
# Flags:  --dry-run  print every command, change nothing.
#         --yes/-y   skip confirmations (still prints the plan + recovery note).
#
# CUDA/cuDNN are handled by the separate `cuda` action (run AFTER rebooting into
# the target driver): the driver caps the max CUDA, and that ceiling is only
# readable from nvidia-smi once the new module is loaded.
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
FAILED=()

# Default downgrade target: the NEWEST 580.x in the archive. Isaac Sim 5.1 needs
# the 580 *branch* (validates 580.65.06; Arch never shipped exactly that), and the
# newest point release is what compiles against current kernels. The older
# 580.76.05 does NOT build against linux-lts 6.18 (a DRM .fb_create API change,
# kernel commit 81112eaac559); 580.105.08+ added the conftest for it. Override by
# passing a version, e.g. `downgrade 580.105.08`.
DEFAULT_NV_VER="580.119.02"

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

# True iff an EXACT package name is installed (ignores `provides` — `pacman -Q
# nvidia-open` would otherwise resolve to nvidia-open-dkms via provides). Uses a
# captured list + case match, NOT `pacman -Qq | grep -q`: under `set -o pipefail`
# grep -q's early exit gives pacman a SIGPIPE (141), which pipefail reports as a
# failure — silently making installed packages look absent.
is_installed() {
    case $'\n'"$(pacman -Qq 2>/dev/null)"$'\n' in *$'\n'"$1"$'\n'*) return 0 ;; *) return 1 ;; esac
}

# Print only the truly-installed subset of a package list (exact names).
installed_of() { local p; for p in "$@"; do is_installed "$p" && echo "$p"; done; }

# Echo the installed "pkgver-pkgrel" for an EXACT package name, or nothing.
exact_ver() { is_installed "$1" && pacman -Q "$1" 2>/dev/null | awk '{print $2}'; }

# Reclaim space: prune the pacman cache of superseded NVIDIA/CUDA/container
# package files — every version of these families EXCEPT the one currently
# installed. This is where a driver/CUDA swap's old versions pile up (the install
# tree itself has no duplicates — pacman replaces in place). Scoped to these
# families so it's predictable; for a full cache trim use `paccache -ruk0`.
NV_CACHE_FAMILIES="nvidia-utils nvidia-open nvidia-open-dkms lib32-nvidia-utils opencl-nvidia nvidia-settings cuda cudnn libnvidia-container nvidia-container-toolkit linux-firmware-nvidia"
clean_cache() {
    say "\n### reclaim: prune old NVIDIA/CUDA packages from the pacman cache"
    local cache=/var/cache/pacman/pkg pkg cur f base rel rest2 fver fname kb=0 ksz
    local victims=()
    for pkg in $NV_CACHE_FAMILIES; do
        cur=$(exact_ver "$pkg")
        for f in "$cache/$pkg"-*-*.pkg.tar.zst; do
            [ -e "$f" ] || continue
            base=$(basename "$f" .pkg.tar.zst)        # name-ver-rel-arch
            rest2=${base%-*}; rest2=${rest2%-*}        # name-ver
            rel=${base%-*}; rel=${rel##*-}             # rel
            fver=${rest2##*-}; fname=${rest2%-*}       # ver / name
            [ "$fname" = "$pkg" ] || continue          # exact family (not a longer name)
            [ -n "$cur" ] && [ "$fver-$rel" = "$cur" ] && continue  # keep installed version
            victims+=("$f")
        done
    done
    if [ "${#victims[@]}" -eq 0 ]; then say "    · cache already free of old NVIDIA/CUDA packages"; return; fi
    for f in "${victims[@]}"; do
        ksz=$(du -k "$f" 2>/dev/null | awk '{print $1}'); kb=$((kb + ${ksz:-0}))
        say "    · $(basename "$f")"
    done
    say "    · reclaiming ~$((kb/1024)) MB"
    if [ "$DRY_RUN" -eq 1 ]; then say "    [dry-run] sudo rm the above (+ .sig)"; return; fi
    local rmlist=(); for f in "${victims[@]}"; do rmlist+=("$f" "$f.sig"); done
    run cache-rm sudo rm -f "${rmlist[@]}"
}

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
    say "  3. pin all of it (IgnorePkg) so -Syu can't pull it back to 595,"
    say "  4. rebuild the initramfs and make linux-lts the boot default,"
    say "  5. prune the old NVIDIA packages from the pacman cache (reclaim space)."
    say ""
    say "AFTER THIS: the whole system runs on driver $ver. Your 'linux' 7.0 entry"
    say "will have NO nvidia module (580 can't build on 7.0) — boot linux-lts. Keep"
    say "the 'linux' entry only as a TTY recovery option. Revert with: latest"
    say "CUDA/cuDNN are NOT touched here — the driver caps the max CUDA, and that"
    say "ceiling is only readable once the new driver is LOADED. So after rebooting,"
    say "run 'nvidia-switch.sh cuda' to align CUDA/cuDNN to the new driver + reclaim."
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
    # nvidia-settings ships libnvidia-gtk3 / libnvidia-wayland-client, which the
    # NVIDIA Container Toolkit injects by the DRIVER version — so it MUST match the
    # driver, or `docker --gpus all` fails mounting libnvidia-gtk3.so.<ver>.
    # Include it (and pin it) only if it's actually installed.
    say "\n### 2/4  resolve $ver packages from the Arch Linux Archive"
    local swap_pkgs=(nvidia-open-dkms "${NV_USERSPACE[@]}")
    is_installed nvidia-settings && swap_pkgs+=(nvidia-settings)
    local urls=() u missing=0 p
    for p in "${swap_pkgs[@]}"; do
        u=$(ala_url "$p" "$ver")
        if [ -n "$u" ]; then say "    · $p -> $u"; urls+=("$u")
        else say "    ! could not find $p-$ver in the archive"; missing=1; fi
    done
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

    # verify the swap BEFORE pinning / touching boot. Two failure modes:
    #  (a) the package didn't install at all -> restore nvidia-open;
    #  (b) the package installed but the DKMS MODULE failed to BUILD (dkms shows
    #      'added', not 'installed') -> the driver version can't compile against
    #      this kernel. This is the trap that bricked the first attempt: do NOT
    #      pin or change the boot default, or you reboot into a driverless kernel.
    if [ "$DRY_RUN" -ne 1 ]; then
        if ! pacman -Qq nvidia-open-dkms >/dev/null 2>&1; then
            say "    ! SWAP FAILED — nvidia-open-dkms is not installed."
            say "    ! restoring nvidia-open to keep the system consistent..."
            sudo pacman -S --needed --noconfirm nvidia-open || say "    ! restore failed — run 'nvidia-switch.sh latest' from a TTY."
            FAILED+=("downgrade:swap-failed")
            say "    ! aborting (no pin, no boot change made)."
            return
        fi
        say "    · dkms status: $(dkms status nvidia 2>/dev/null | paste -sd'; ' -)"
        if ! dkms status nvidia 2>/dev/null | grep -q ': installed'; then
            say "    ! SWAP INCOMPLETE — nvidia-open-dkms $ver installed but the DKMS"
            say "    ! MODULE FAILED TO BUILD (status 'added', not 'installed'). Driver"
            say "    ! $ver cannot compile against your kernel. Try a NEWER 580, e.g.:"
            say "    !     nvidia-switch.sh downgrade 580.119.02"
            say "    ! Build log: /var/lib/dkms/nvidia/$ver/build/make.log"
            say "    ! NOT pinning and NOT changing the boot default (would boot driverless)."
            FAILED+=("downgrade:dkms-build-failed")
            return
        fi
    fi

    # 3. pin (only reached on a verified swap) — pin exactly what we swapped,
    # including nvidia-settings, so -Syu can't drag any of it back to 595.
    say "\n### 3/5  pin the swapped packages"
    add_pin "${swap_pkgs[@]}"

    # 4. UKI preset for linux-lts + rebuild + boot default
    say "\n### 4/5  linux-lts UKI + initramfs + boot default -> linux-lts"
    ensure_lts_uki_preset
    regen_initramfs
    set_boot_default lts

    # 5. reclaim cache space from the superseded driver versions
    say "\n### 5/5  reclaim cache"
    clean_cache

    hr
    say "DOWNGRADE staged. RECOVERY NOTE — read before rebooting:"
    say "  * Reboot and pick the linux-lts entry (it's now the default)."
    say "  * If the desktop doesn't come up, at the boot menu choose the 'linux'"
    say "    7.0 entry to reach a TTY, then run:  nvidia-switch.sh latest"
    say "  * Verify after reboot:  nvidia-smi   (should read $ver)"
    say "  * Align CUDA to the new driver + reclaim space:  nvidia-switch.sh cuda"
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

    say "\n### 1/4  drop the pin, then sync to repo-latest"
    del_pin
    # Remove the dkms module first (same conflict reason as the downgrade, in
    # reverse), then full-sync the repo-latest prebuilt set. Running module stays
    # in RAM until reboot.
    remove_module_pkg nv-rm-dkms nvidia-open-dkms
    # include nvidia-settings if installed so it returns to the repo version too
    # (it ships driver-versioned libs the container toolkit injects).
    local latest_set=(nvidia-open nvidia-utils lib32-nvidia-utils opencl-nvidia)
    is_installed nvidia-settings && latest_set+=(nvidia-settings)
    run nv-latest sudo pacman -Syu --needed --noconfirm "${latest_set[@]}"

    say "\n### 2/4  rebuild initramfs"
    regen_initramfs

    say "\n### 3/4  boot default -> linux"
    set_boot_default ""

    say "\n### 4/4  reclaim cache"
    clean_cache

    hr
    say "RESTORED. Reboot into the 'linux' kernel, then verify:  nvidia-smi"
    say "To bring CUDA/cuDNN back up to the latest driver's ceiling + reclaim the"
    say "old toolkit's space, after reboot run:  nvidia-switch.sh cuda"
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

    say "\n### 3/5  strip nvidia early-KMS modules from the initramfs config"
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

    say "\n### 4/5  reclaim cache (all NVIDIA/CUDA packages — none are installed now)"
    clean_cache

    say "\n### 5/5  done"
    hr
    say "PURGED. (nvidia_drm.modeset=1 may remain on the kernel cmdline — harmless"
    say "with no driver; remove it from your bootloader config if you like.)"
    say "Reinstall BEFORE rebooting into the GUI:  nvidia-switch.sh latest"
}

# Align CUDA + cuDNN to the CURRENTLY LOADED driver. Run AFTER rebooting into the
# target driver — the ceiling is read from nvidia-smi, which needs the module
# loaded. Compares CUDA MAJOR versions: CUDA "minor-version compatibility" means a
# newer-MINOR toolkit (e.g. 13.2) runs fine on an older-minor driver of the SAME
# major (13.0), so we keep the repo toolkit in that case — only a MAJOR mismatch
# needs an older cuda from the AUR. Also REPAIRS a missing opencl-nvidia (it's
# driver userspace, not just a cuda dep) so the cuda dependency is satisfiable.
do_cuda() {
    hr; say ">>> Align CUDA + cuDNN to the loaded NVIDIA driver"; hr
    if ! command -v nvidia-smi >/dev/null 2>&1 || ! nvidia-smi >/dev/null 2>&1; then
        say "! No working NVIDIA driver is loaded — boot into your target driver first,"
        say "! then re-run. (CUDA's max version is the loaded driver's ceiling.)"
        FAILED+=("cuda:no-driver"); return
    fi
    local maxc repoc inst maxmaj repomaj nvver
    maxc=$(nvidia-smi | grep -oP 'CUDA Version:\s*\K[0-9]+\.[0-9]+' | head -1)
    repoc=$(pacman -Si cuda 2>/dev/null | awk -F': +' '/^Version/{print $2}' | grep -oP '^[0-9]+\.[0-9]+')
    inst=$(exact_ver cuda); maxmaj=${maxc%%.*}; repomaj=${repoc%%.*}
    say "Driver ceiling: CUDA $maxc | repo cuda: $repoc | installed: ${inst:-none}"

    # 0. REPAIR: opencl-nvidia is part of the driver userspace (pinned). If it's
    # missing (e.g. an earlier -Rns cascade removed it), reinstall it at the
    # driver's version from the archive — otherwise cuda's opencl-nvidia dep can't
    # be met (the repo copy is a different version and pinned/ignored).
    if is_installed nvidia-utils && ! is_installed opencl-nvidia; then
        nvver=$(exact_ver nvidia-utils)            # e.g. 580.119.02-1
        say "\n### 0  repair: reinstall opencl-nvidia $nvver (driver userspace) from the archive"
        local ou; ou=$(ala_url opencl-nvidia "${nvver%-*}")   # ala_url wants bare pkgver
        if [ -n "$ou" ]; then run opencl-repair sudo pacman -U --noconfirm "$ou"
        else say "    ! couldn't find opencl-nvidia $nvver in the archive — install it manually."; FAILED+=("cuda:opencl-repair"); fi
    fi

    confirm "Install/align CUDA+cuDNN for driver ceiling $maxc?" || return

    say "\n### install CUDA matched to the driver (by MAJOR version)"
    if [ -z "$maxc" ] || [ -z "$repoc" ]; then
        say "    ! couldn't read versions — installing repo cuda/cudnn as-is."
        run cuda-install sudo pacman -S --needed --noconfirm cuda cudnn
    elif [ "$repomaj" -le "$maxmaj" ] 2>/dev/null; then
        say "    · repo cuda major ($repomaj) <= driver major ($maxmaj): compatible via CUDA"
        say "      minor-version compatibility — installing repo cuda $repoc + cudnn (no downgrade)."
        run cuda-install sudo pacman -S --needed --noconfirm cuda cudnn
    else
        local helper; helper=$(command -v paru || command -v yay)
        say "    · repo cuda MAJOR ($repomaj) > driver MAJOR ($maxmaj) — needs an older cuda."
        # switch versions: drop cuda/cudnn ONLY (plain -R, never -s — -s would
        # cascade into opencl-nvidia/driver stack), then build the AUR major.
        local present; present=$(installed_of cuda cudnn)
        [ -n "$present" ] && run cuda-remove sudo pacman -R --noconfirm $present
        if [ -n "$helper" ]; then
            if [ "$DRY_RUN" -eq 1 ]; then say "    [dry-run] $helper -S --needed cuda-$maxc cudnn";
            else "$helper" -S --needed --noconfirm "cuda-$maxc" cudnn || FAILED+=("cuda:aur-$maxc"); fi
        else
            say "    ! no AUR helper (paru/yay) — install cuda-$maxc manually."; FAILED+=("cuda:no-helper")
        fi
    fi

    say "\n### reclaim cache"
    clean_cache
    hr
    say "CUDA done. Verify:  nvcc --version  and  nvidia-smi  (toolkit runs on the"
    say "$maxc driver via minor-version compatibility)."
}

# ============================================================================
# Arg parsing + menu
# ============================================================================
ACTIONS=(
    "status|Read-only report: driver, packages, kernels, dkms, pin, boot default"
    "downgrade|Switch the whole stack to 580.x (+ linux-lts) for Isaac Sim / Lab"
    "latest|Restore the repo-latest NVIDIA (prebuilt nvidia-open) + boot linux"
    "cuda|Align CUDA+cuDNN to the LOADED driver (clean-swap + reclaim; run post-reboot)"
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
        -h|--help)
            say "usage: nvidia-switch.sh [--dry-run] [--yes] <action> [version]"
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
    cuda)      do_cuda ;;
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
