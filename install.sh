#!/usr/bin/env bash
# ============================================================================
# install.sh — rebuilds the system-level half of the Arch + Hyprland + caelestia
# setup on a fresh minimal install (NVIDIA + GDM).
#
# Run setup-home.sh FIRST (it writes the home-dir configs, no sudo). THIS script
# does the sudo-gated parts: packages (repo + AUR), the DualSense udev fix, CUDA
# (matched to your driver) + cuDNN, CUDA PATH, Docker + NVIDIA runtime, group
# membership, and switching the login shell to fish.
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

# --- Node toolchain ----------------------------------------------------------
pac node pnpm yarn

# --- Editors -----------------------------------------------------------------
pac editors neovim zed

# --- Containers / robotics (ROS runs via the jazzy Docker image) -------------
pac containers docker docker-buildx nvidia-container-toolkit

# --- Embedded / serial -------------------------------------------------------
pac embedded picocom minicom arduino-cli stlink openocd wireshark-qt

# --- Audio -------------------------------------------------------------------
pac audio pavucontrol easyeffects

# --- GPU / gaming (multilib is already enabled) ------------------------------
pac gpu lib32-nvidia-utils gamemode lib32-gamemode mangohud lib32-mangohud nvidia-settings

# --- Multimedia --------------------------------------------------------------
pac media haruna obs-studio gimp inkscape okular gwenview swayimg

# --- Terminal productivity ---------------------------------------------------
pac terminal fzf ripgrep fd bat zoxide lazygit github-cli tmux tree yq

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

echo -e "\n### DualSense audio fix (udev rule + helper)"
sudo tee /usr/local/bin/dualsense-audio-fix.sh >/dev/null <<'EOF'
#!/usr/bin/env bash
# DualSense reports PCM Playback Volume = 0 on connect; bump it to 100.
# Retries briefly because the ALSA card may not be registered the instant udev fires.
for _ in $(seq 1 10); do
    CARD=$(awk '/DualSense Wireless Controller/{n=$1;gsub(/[^0-9]/,"",n);print n;exit}' /proc/asound/cards)
    if [ -n "${CARD:-}" ]; then
        amixer -c "$CARD" cset numid=4 100 && exit 0
    fi
    sleep 1
done
exit 0
EOF
sudo chmod +x /usr/local/bin/dualsense-audio-fix.sh

sudo tee /etc/udev/rules.d/99-dualsense-audio.rules >/dev/null <<'EOF'
# Fix muted DualSense output on connect (USB 054c:0ce6, Edge 054c:0df2).
ACTION=="add", SUBSYSTEM=="sound", ATTRS{idVendor}=="054c", ATTRS{idProduct}=="0ce6", RUN+="/usr/bin/systemd-run --no-block /usr/local/bin/dualsense-audio-fix.sh"
ACTION=="add", SUBSYSTEM=="sound", ATTRS{idVendor}=="054c", ATTRS{idProduct}=="0df2", RUN+="/usr/bin/systemd-run --no-block /usr/local/bin/dualsense-audio-fix.sh"
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

echo -e "\n### Docker: NVIDIA runtime + enable service + group"
if command -v docker >/dev/null; then
    sudo nvidia-ctk runtime configure --runtime=docker || FAILED+=("nvidia-ctk")
    sudo systemctl enable --now docker || FAILED+=("docker enable")
fi

echo -e "\n### Group membership (docker, serial, wireshark)"
sudo usermod -aG docker,uucp,lock,wireshark "$USER_NAME" \
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
  5. ROS 2 Jazzy (pulls ~6.4GB on first use):  ros2-jazzy pull
EOF
