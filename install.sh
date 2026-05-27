#!/usr/bin/env bash
# ============================================================================
# install.sh — rebuilds the system-level half of the Arch + Hyprland + caelestia
# setup on a fresh minimal install (NVIDIA RTX 3060 desktop, GDM, DP-1).
#
# The home-dir configs (Hyprland overrides, ~/.local/bin scripts, git, fish,
# dolphin) are already written by Claude. THIS script does the sudo-gated parts:
# packages (repo + AUR), the DualSense udev fix, CUDA path, Docker + NVIDIA
# runtime, group membership, and switching the login shell to fish.
#
# Run it as your normal user (it calls sudo itself where needed):
#     bash ~/Documents/arch-hyprland-setup/install.sh
#
# Safe to re-run: every step uses --needed / is idempotent.
# ============================================================================
set -uo pipefail

if [ "$(id -u)" -eq 0 ]; then
    echo "Run as your normal user, not root (the script calls sudo itself)." >&2
    exit 1
fi

USER_NAME="$(id -un)"
FAILED=()

pac() {  # install a group; record failure but keep going
    local group="$1"; shift
    echo -e "\n>>> pacman: $group"
    sudo pacman -S --needed --noconfirm "$@" || FAILED+=("pacman:$group")
}

echo "### Refreshing package databases"
sudo pacman -Syu --noconfirm || FAILED+=("pacman -Syu")

# --- Build / compilers / debug ----------------------------------------------
pac build base-devel clang lld lldb cmake ninja meson ccache gdb valgrind \
          cppcheck doxygen graphviz boost eigen onetbb

# --- CUDA + cuDNN (large) ----------------------------------------------------
pac cuda cuda cudnn

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
echo -e "\n>>> AUR via paru"
paru -S --needed sweet-cursors-git sweet-cursors-hyprcursor-git \
                 brave-bin microsoft-edge-stable-bin claude-desktop-bin \
    || FAILED+=("paru:aur")

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

Next:
  1. Set your git identity name:
       git config --global user.name "Your Name"
  2. Log out and back in (group + shell changes need a fresh session).
  3. Verify the ghost cursor is gone and sweet-cursors renders:
       hyprctl reload
  4. ROS 2 Jazzy (pulls ~6.4GB on first use):  ros2-jazzy pull
EOF
