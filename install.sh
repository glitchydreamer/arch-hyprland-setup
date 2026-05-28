#!/usr/bin/env bash
# ============================================================================
# install.sh — rebuilds the system-level half of the Arch + Hyprland + caelestia
# setup on a fresh minimal install (NVIDIA + GDM).
#
# Run setup-home.sh FIRST (it writes the home-dir configs, no sudo). THIS script
# does the sudo-gated parts: packages (repo + AUR), CUDA
# (matched to your driver) + cuDNN, CUDA PATH, group membership, and switching
# the login shell to fish.
#
#     bash ~/Documents/arch-hyprland-setup/setup-home.sh   # 1. home configs
#     bash ~/Documents/arch-hyprland-setup/install.sh      # 2. system (this)
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

pac() {  # install a group; record failure but keep going
    local group="$1"; shift
    echo -e "\n>>> pacman: $group"
    sudo pacman -S --needed --noconfirm "$@" || FAILED+=("pacman:$group")
}

# Make sure an AUR helper exists. A truly fresh minimal install has neither
# paru nor yay; bootstrap yay from the AUR (clone + makepkg) if needed.
ensure_aur_helper() {
    if command -v paru >/dev/null; then HELPER=paru; return; fi
    if command -v yay  >/dev/null; then HELPER=yay;  return; fi
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
    [ -n "$HELPER" ] || { FAILED+=("aur:no-helper"); return 1; }
    "$HELPER" -S --needed "$@"
}

# Workaround: PipeWire 1.6.6 broke DualSense USB audio (built-in speaker AND the
# 3.5mm headphone jack go silent — the kernel delivers frames but nothing sounds).
# Pin to the last-good 1.6.5 until upstream fixes it. Self-limiting and idempotent:
#   - only acts when the INSTALLED pipewire is in the known-bad range (so a fresh
#     install with an already-fixed repo version is left alone),
#   - downgrades only if the good packages are still in the pacman cache,
#   - the IgnorePkg pin stops the next `pacman -Syu` from re-pulling the breakage.
# Remove the IgnorePkg line + drop this call once a fixed PipeWire ships.
BAD_PW_REGEX='^1:1\.6\.6'   # extend if new bad versions appear; clear when fixed
# NOTE: alsa-card-profiles is versioned in lockstep with PipeWire (1:1.6.x) and
# holds the ACP channel/profile data. Its 1.6.6 build breaks the DualSense 3.5mm
# headphone channel map (jack silent, speaker fine) — it MUST be pinned/downgraded
# alongside the pipewire-named packages, or the jack stays dead after the pin.
PW_PKGS=(libpipewire pipewire pipewire-audio pipewire-alsa pipewire-pulse pipewire-jack gst-plugin-pipewire alsa-card-profiles)
pin_pipewire_dualsense() {
    command -v pipewire >/dev/null || { echo ">>> No pipewire installed — skipping DualSense pin."; return; }
    local cur; cur=$(pacman -Q pipewire 2>/dev/null | awk '{print $2}')
    echo ">>> PipeWire installed: ${cur:-unknown}"
    if ! printf '%s' "$cur" | grep -qE "$BAD_PW_REGEX"; then
        echo ">>> Not in the known-bad range — no DualSense workaround needed."
        return
    fi
    echo ">>> PipeWire $cur is the DualSense-breaking version — applying workaround."
    # Downgrade from cache if the good set is present.
    local good=() p f
    for p in "${PW_PKGS[@]}"; do
        f=$(ls -1 /var/cache/pacman/pkg/"$p"-1:1.6.5-*.pkg.tar.zst 2>/dev/null | tail -1)
        [ -n "$f" ] && good+=("$f")
    done
    if [ "${#good[@]}" -eq "${#PW_PKGS[@]}" ]; then
        sudo pacman -U --noconfirm "${good[@]}" || FAILED+=("pipewire-downgrade")
    else
        echo ">>> 1.6.5 not fully cached — can't auto-downgrade. Pinning to stop"
        echo ">>> further breakage; downgrade manually from an archive if needed."
        FAILED+=("pipewire-downgrade:no-cache")
    fi
    # Pin so `pacman -Syu` won't re-pull the broken version.
    local pin="IgnorePkg = ${PW_PKGS[*]}"
    if ! grep -qF "$pin" /etc/pacman.conf; then
        sudo sed -i "0,/^\[options\]/s//[options]\n$pin/" /etc/pacman.conf \
            || FAILED+=("pipewire-pin")
    fi
    systemctl --user restart pipewire pipewire-pulse wireplumber 2>/dev/null || true
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
    maxc=$(nvidia-smi | grep -oP 'CUDA Version:\s*\K[0-9]+\.[0-9]+' | head -1)
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

echo "### Refreshing package databases"
sudo pacman -Syu --noconfirm || FAILED+=("pacman -Syu")

# --- Prerequisites: git, GitHub CLI, ssh, then an AUR helper -----------------
# Done up front so `gh auth login` + `git push` are available the moment the
# script finishes, and so the AUR steps below have a helper to use.
pac prereqs git base-devel github-cli openssh
ensure_aur_helper
echo ">>> AUR helper: ${HELPER:-none}"

# --- Build / compilers / debug ----------------------------------------------
pac build base-devel clang lld lldb cmake ninja meson ccache gdb valgrind \
          cppcheck doxygen graphviz boost eigen onetbb

# --- CUDA + cuDNN (large, driver-matched) ------------------------------------
install_cuda

# --- Python scientific stack -------------------------------------------------
pac python python-pip python-pipx python-virtualenv python-numpy python-scipy \
           python-pandas python-scikit-learn python-matplotlib python-h5py \
           jupyterlab ipython python-pytest mypy ruff python-pylint python-black

# --- Anaconda (general ML/Python; configured for fish) -----------------------
install_anaconda

# --- Node toolchain ----------------------------------------------------------
pac node pnpm yarn

# --- Editors -----------------------------------------------------------------
pac editors neovim zed

# --- Embedded / serial -------------------------------------------------------
pac embedded picocom minicom arduino-cli stlink openocd wireshark-qt

# --- Audio -------------------------------------------------------------------
# alsa-utils: aplay/speaker-test for low-level audio debugging (DualSense jack).
pac audio pavucontrol easyeffects alsa-utils
# DualSense audio: pin PipeWire off the 1.6.6 regression (no-op when not affected)
pin_pipewire_dualsense

# --- GPU / gaming (multilib is already enabled) ------------------------------
pac gpu lib32-nvidia-utils gamemode lib32-gamemode mangohud lib32-mangohud nvidia-settings

# --- Multimedia --------------------------------------------------------------
pac media haruna obs-studio gimp inkscape okular gwenview swayimg

# --- Terminal productivity ---------------------------------------------------
pac terminal fzf ripgrep fd bat zoxide lazygit github-cli tmux tree yq rsync

# --- KDE "settings app" + Dolphin --------------------------------------------
pac kde dolphin systemsettings discover kinfocenter

# --- Display inspection tools (per docs/display.md) --------------------------
# (edid-decode isn't packaged in the repos; `drm_info -i` covers EDID parsing.)
pac display drm-info wdisplays wlr-randr brightnessctl nm-connection-editor

# --- AUR (sweet-cursors fixes the ghost-cursor theme; browsers; claude) ------
echo -e "\n>>> AUR via ${HELPER:-(none)}"
aur sweet-cursors-git sweet-cursors-hyprcursor-git \
    brave-bin microsoft-edge-stable-bin claude-desktop-bin \
    || FAILED+=("aur:apps")

# ============================================================================
# System files
# ============================================================================

# NOTE: the DualSense AUDIO fix is no longer a root udev/amixer hack. On modern
# PipeWire this controller is UCM/profile-based (no ALSA mixer controls), and
# the real issue is profile/port routing — handled in the user session by the
# WirePlumber drop-in + `dualsense-audio` helper that setup-home.sh installs.

echo -e "\n### DualSense touchpad: stop it acting as a second (centred) cursor"
# The controller's touchpad registers as an absolute pointer that parks a cursor
# at screen centre. hypr-user.conf disables it in Hyprland; this libinput rule
# is the belt-and-suspenders version (ignored before any compositor sees it).
sudo tee /etc/udev/rules.d/71-dualsense-touchpad-ignore.rules >/dev/null <<'EOF'
SUBSYSTEM=="input", ATTRS{name}=="Sony Interactive Entertainment DualSense Wireless Controller Touchpad", ENV{LIBINPUT_IGNORE_DEVICE}="1"
EOF
sudo udevadm control --reload-rules

echo -e "\n### CUDA PATH for login shells (/etc/profile.d/cuda.sh)"
if [ -d /opt/cuda ]; then
    sudo tee /etc/profile.d/cuda.sh >/dev/null <<'EOF'
export CUDA_HOME=/opt/cuda
export PATH="$CUDA_HOME/bin:$PATH"
EOF
fi

# ============================================================================
# Services / groups / shell
# ============================================================================

echo -e "\n### Group membership (serial, wireshark)"
sudo usermod -aG uucp,lock,wireshark "$USER_NAME" \
    || FAILED+=("usermod groups")

echo -e "\n### Login shell -> fish"
if [ "$(getent passwd "$USER_NAME" | cut -d: -f7)" != /usr/bin/fish ]; then
    sudo chsh -s /usr/bin/fish "$USER_NAME" || FAILED+=("chsh fish")
fi

# ============================================================================
echo -e "\n============================================================"
if [ ${#FAILED[@]} -eq 0 ]; then
    echo "All steps completed."
else
    echo "Completed with issues in: ${FAILED[*]}"
    echo "Re-run is safe (everything uses --needed / is idempotent)."
fi
cat <<'EOF'

Next (gh + an AUR helper are now installed, so the only auth step is manual):
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

To cleanly remove a component later (Docker, CUDA, Anaconda, ...), use the
interactive uninstaller:  bash ~/Documents/arch-hyprland-setup/uninstall.sh
EOF
