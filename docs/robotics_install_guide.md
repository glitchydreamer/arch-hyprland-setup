# Robotics Stack Installation Guide — Arch Linux + Hyprland (Caelestia)
**Date:** 28 May 2026  
**Target System:** Arch Linux (rolling) · Hyprland + Caelestia · NVIDIA GPU

---

> [!IMPORTANT]
> **Install order matters.** Follow the numbered sections in sequence — each layer depends on the previous one.

> [!NOTE]
> **Architecture decision:** Since Arch Linux is a rolling-release distro and **not** officially supported by ROS 2 or NVIDIA Isaac**, the most stable approach is:
> - Install Docker Engine + NVIDIA Container Toolkit **natively** on Arch
> - Run Isaac Sim + Isaac Lab **natively via pip** (they support any Linux with GLIBC ≥ 2.35)
> - Run ROS 2 Jazzy + Isaac ROS **inside Docker containers** (official images, no dependency conflicts)

---

## Prerequisites

Before starting, ensure your system has:

```bash
# Update system fully
sudo pacman -Syu

# Verify NVIDIA proprietary drivers are installed
nvidia-smi
# You should see your GPU info and driver version (≥ 535.x recommended, 570+ ideal)

# Verify GLIBC version (need ≥ 2.35 for Isaac Sim pip)
ldd --version
# Arch Linux rolling should be well above 2.35

# Install essential tools
sudo pacman -S --needed base-devel git curl wget python python-pip
```

> [!WARNING]
> **Do NOT use `nouveau` drivers.** You must have the proprietary `nvidia` drivers installed. If you haven't:
> ```bash
> sudo pacman -S nvidia nvidia-utils nvidia-settings lib32-nvidia-utils
> # Reboot after installation
> sudo reboot
> ```

---

## 1. Docker Engine (NOT Docker Desktop)

> [!IMPORTANT]
> **Use Docker Engine (CLI), NOT Docker Desktop.** Docker Desktop on Arch is experimental and has known issues with Wayland/Hyprland compositors. Docker Engine is rock-solid and is what NVIDIA's container stack requires.

### Install

```bash
# Install Docker from official Arch repos
sudo pacman -S docker docker-compose docker-buildx

# Enable and start Docker daemon
sudo systemctl enable --now docker.service

# Add your user to the docker group (avoids needing sudo for every docker command)
sudo usermod -aG docker $USER

# IMPORTANT: Log out and log back in for group membership to take effect
# Or run: newgrp docker (for the current session only)
```

### Verify

```bash
# Test Docker (after re-login)
docker run --rm hello-world
```

> [!TIP]
> **Hyprland/Wayland note:** Docker Engine is headless — it doesn't care about your display server. No Wayland-specific configuration needed.

### Optional: Configure Docker Storage

If you want Docker to use a different storage location (e.g., SSD):

```bash
sudo mkdir -p /etc/docker
sudo tee /etc/docker/daemon.json <<EOF
{
  "data-root": "/path/to/your/ssd/docker-data"
}
EOF
sudo systemctl restart docker
```

---

## 2. NVIDIA Container Toolkit

> [!NOTE]
> On Arch Linux, the NVIDIA Container Toolkit is available in the **official `extra` repository** — no AUR needed!

### Install

```bash
# Install from official Arch repos
sudo pacman -S nvidia-container-toolkit

# Configure Docker to use NVIDIA runtime
sudo nvidia-ctk runtime configure --runtime=docker

# Restart Docker to apply changes
sudo systemctl restart docker
```

### Verify

```bash
# Test GPU access inside a container
docker run --rm --gpus all nvidia/cuda:12.6.3-base-ubuntu24.04 nvidia-smi
```

You should see your GPU info printed from **inside** the container. If this works, your Docker + NVIDIA GPU stack is ready.

> [!CAUTION]
> **Known issue:** On systems using `systemd` cgroup drivers, containers can lose GPU access when `systemctl daemon-reload` is run. Avoid running `daemon-reload` while GPU containers are active. If this happens, restart the affected containers.

---

## 3. NVIDIA Isaac Sim 5.1

Isaac Sim can be installed **natively via pip** on any Linux with Python 3.11 and GLIBC ≥ 2.35. Arch Linux meets both requirements.

### Prerequisites

```bash
# Install Python 3.11 (Arch may have 3.12+ as default)
# Check current Python version
python --version

# If you need Python 3.11 specifically, install it
# Option A: From AUR
yay -S python311  # or paru -S python311

# Option B: Use pyenv (recommended for managing multiple Python versions)
sudo pacman -S pyenv
pyenv install 3.11.12
pyenv local 3.11.12
```

### Create Virtual Environment & Install

```bash
# Create a dedicated virtual environment for Isaac Sim
python3.11 -m venv ~/isaac-sim-venv
source ~/isaac-sim-venv/bin/activate

# Upgrade pip
pip install --upgrade pip

# Install Isaac Sim 5.1 with all extras
pip install 'isaacsim[all,extscache]==5.1.0' \
    --extra-index-url https://pypi.nvidia.com
```

> [!NOTE]
> The download is large (~12 GB+). The `extscache` extra pre-caches extension dependencies. This may take 15-30 minutes depending on your internet speed.

### Verify

```bash
# Activate the venv
source ~/isaac-sim-venv/bin/activate

# Run the compatibility checker
isaacsim compatibility-check

# Launch Isaac Sim (headless test)
isaacsim --headless
```

> [!TIP]
> **Wayland/Hyprland compatibility:** Isaac Sim's GUI uses the NVIDIA Omniverse Kit runtime. For best results with Hyprland:
> ```bash
> # If you encounter display issues, force X11 backend via XWayland
> env GDK_BACKEND=x11 isaacsim
> ```
> Alternatively, Isaac Sim's headless mode (`--headless`) works perfectly regardless of display server — ideal for training workloads.

---

## 4. NVIDIA Isaac Lab

Isaac Lab builds on top of Isaac Sim. It provides reinforcement learning and robot learning frameworks.

### Install (Source Method — Recommended by NVIDIA)

```bash
# Activate the same virtual environment as Isaac Sim
source ~/isaac-sim-venv/bin/activate

# Clone Isaac Lab repository
git clone https://github.com/isaac-sim/IsaacLab.git ~/IsaacLab
cd ~/IsaacLab

# Run the official installer script
# This installs Isaac Lab and all its dependencies
./isaaclab.sh --install
```

### Install RL Libraries (Optional — Pick What You Need)

```bash
cd ~/IsaacLab

# Install individual RL frameworks as needed:
./isaaclab.sh -i rl_games     # RL-Games
./isaaclab.sh -i rsl_rl       # RSL-RL (ETH Zurich)
./isaaclab.sh -i sb3           # Stable-Baselines3
./isaaclab.sh -i skrl          # SKRL
```

### VS Code Integration (Optional)

```bash
# Generate VS Code settings for proper IntelliSense
cd ~/IsaacLab
python -m isaaclab --generate-vscode-settings
```

### Verify

```bash
source ~/isaac-sim-venv/bin/activate
cd ~/IsaacLab

# Run the basic empty scene tutorial
python scripts/tutorials/00_sim/create_empty.py

# Run headless to verify GPU simulation works
python scripts/tutorials/00_sim/create_empty.py --headless
```

---

## 5. ROS 2 Jazzy

> [!IMPORTANT]
> **Arch Linux is NOT officially supported for ROS 2.** Building from source on Arch is fragile due to rolling dependencies. **The recommended approach is Docker**, which gives you a stable Ubuntu 24.04 environment with official ROS 2 Jazzy packages.

### Option A: Docker (Recommended — Bug-Free)

```bash
# Pull the official ROS 2 Jazzy desktop image
docker pull ros:jazzy-desktop

# Run an interactive ROS 2 Jazzy container with GPU support
docker run -it --rm \
    --gpus all \
    --network host \
    --ipc host \
    --pid host \
    -e DISPLAY=$DISPLAY \
    -e WAYLAND_DISPLAY=$WAYLAND_DISPLAY \
    -e XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR \
    -v /tmp/.X11-unix:/tmp/.X11-unix \
    -v $XDG_RUNTIME_DIR/$WAYLAND_DISPLAY:$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY \
    -v ~/ros2_ws:/root/ros2_ws \
    --name ros2-jazzy \
    ros:jazzy-desktop \
    bash
```

Inside the container:

```bash
# Verify ROS 2 installation
source /opt/ros/jazzy/setup.bash
ros2 --help

# Test with a simple demo
ros2 run demo_nodes_cpp talker &
ros2 run demo_nodes_cpp listener
```

> [!TIP]
> **Create a persistent development container** so you don't lose work:
> ```bash
> # Create (first time)
> docker create -it \
>     --gpus all \
>     --network host \
>     --ipc host \
>     --pid host \
>     -e DISPLAY=$DISPLAY \
>     -e WAYLAND_DISPLAY=$WAYLAND_DISPLAY \
>     -e XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR \
>     -v /tmp/.X11-unix:/tmp/.X11-unix \
>     -v $XDG_RUNTIME_DIR/$WAYLAND_DISPLAY:$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY \
>     -v ~/ros2_ws:/root/ros2_ws \
>     --name ros2-dev \
>     ros:jazzy-desktop \
>     bash
>
> # Start and attach
> docker start -ai ros2-dev
> ```

### Option B: Distrobox (Hybrid Approach)

[Distrobox](https://github.com/89luca89/distrobox) lets you run a containerized Ubuntu environment that integrates tightly with your host Arch system — apps can access your home directory, GPU, display, etc., almost transparently.

```bash
# Install distrobox
sudo pacman -S distrobox

# Create an Ubuntu 24.04 container with ROS 2 Jazzy
distrobox create --name ros2-jazzy \
    --image ubuntu:24.04 \
    --nvidia

# Enter the container
distrobox enter ros2-jazzy

# Inside distrobox: Install ROS 2 Jazzy (Ubuntu packages work here!)
sudo apt update && sudo apt install -y software-properties-common curl
sudo curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key \
    -o /usr/share/keyrings/ros-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] \
    http://packages.ros.org/ros2/ubuntu noble main" | \
    sudo tee /etc/apt/sources.list.d/ros2.list > /dev/null
sudo apt update
sudo apt install -y ros-jazzy-desktop

# Source ROS 2
echo "source /opt/ros/jazzy/setup.bash" >> ~/.bashrc
source ~/.bashrc
```

### Option C: AUR (Not Recommended — Fragile)

```bash
# Only if you must have native ROS 2 on Arch
# Using an AUR helper like yay or paru:
yay -S ros2-jazzy

# WARNING: This may take hours to compile and can break with Arch updates
```

---

## 6. NVIDIA Isaac ROS (Release 3.2)

Isaac ROS runs inside Docker containers built on Ubuntu with ROS 2 Humble/Jazzy. This is the official and **only supported** way to run Isaac ROS.

### Prerequisites

Ensure you have completed:
- ✅ Section 1 (Docker Engine)
- ✅ Section 2 (NVIDIA Container Toolkit)
- A working `docker run --gpus all` setup

### Install Isaac ROS Dev Environment

```bash
# Create workspace directory
mkdir -p ~/workspaces/isaac_ros-dev/src
cd ~/workspaces/isaac_ros-dev

# Clone the Isaac ROS common repo (contains the dev environment scripts)
git clone -b release-3.2 https://github.com/NVIDIA-ISAAC-ROS/isaac_ros_common.git src/isaac_ros_common

# Set up environment variables
echo "export ISAAC_ROS_WS=~/workspaces/isaac_ros-dev" >> ~/.bashrc
source ~/.bashrc
```

### Build and Launch the Dev Container

```bash
cd $ISAAC_ROS_WS/src/isaac_ros_common

# Launch the Isaac ROS development container
# This script automatically:
# - Pulls/builds the Isaac ROS Docker image
# - Mounts your workspace
# - Configures GPU access
./scripts/run_dev.sh $ISAAC_ROS_WS
```

### Inside the Isaac ROS Container

```bash
# Source ROS 2 (already done automatically in the container)
source /opt/ros/humble/setup.bash  # Isaac ROS 3.2 uses Humble

# Build Isaac ROS packages you need
cd /workspaces/isaac_ros-dev
colcon build --symlink-install

# Example: Install and test a specific Isaac ROS package
# (inside the container)
sudo apt update
sudo apt install -y ros-humble-isaac-ros-visual-slam
```

### Set Up Isaac Apt Repository (Inside Container)

If you need additional Isaac ROS packages from NVIDIA's apt repository:

```bash
# Inside the Isaac ROS dev container:

# Set locale
sudo apt update && sudo apt install -y locales
sudo locale-gen en_US en_US.UTF-8
sudo update-locale LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8
export LANG=en_US.UTF-8

# Install dependencies
sudo apt install -y software-properties-common curl

# Add the Isaac ROS apt repository
curl -sSL https://isaac.download.nvidia.com/isaac-ros/repos.key | \
    sudo apt-key add -
echo "deb https://isaac.download.nvidia.com/isaac-ros/release-3.2 $(lsb_release -cs) main" | \
    sudo tee /etc/apt/sources.list.d/isaac-ros.list

sudo apt update
```

---

## Quick Reference: Verification Checklist

Run these checks to verify your entire stack:

```bash
# 1. Docker
docker --version
docker run --rm hello-world

# 2. NVIDIA Container Toolkit
docker run --rm --gpus all nvidia/cuda:12.6.3-base-ubuntu24.04 nvidia-smi

# 3. Isaac Sim
source ~/isaac-sim-venv/bin/activate
isaacsim compatibility-check

# 4. Isaac Lab
source ~/isaac-sim-venv/bin/activate
python -c "import isaaclab; print('Isaac Lab OK')"

# 5. ROS 2 Jazzy (inside Docker/Distrobox)
docker run --rm ros:jazzy-desktop ros2 --help

# 6. Isaac ROS (inside dev container)
cd $ISAAC_ROS_WS/src/isaac_ros_common
./scripts/run_dev.sh $ISAAC_ROS_WS
# Then inside: ros2 pkg list | grep isaac
```

---

## Arch Linux + Hyprland Specific Tips

### Wayland/XWayland Considerations

| Component | Display Server | Notes |
|-----------|---------------|-------|
| Docker Engine | None (daemon) | No display needed |
| NVIDIA CTK | None (runtime) | No display needed |
| Isaac Sim GUI | XWayland | Use `env GDK_BACKEND=x11 isaacsim` if needed |
| Isaac Sim Headless | None | Works perfectly |
| ROS 2 (rviz2, rqt) | XWayland in Docker | Pass `-e DISPLAY` and X11 socket |
| Isaac ROS | Inside Docker | Container handles display |

### Enable XWayland (if not already)

In your Hyprland config (`~/.config/hypr/hyprland.conf`):

```
xwayland {
    force_zero_scaling = true
}
```

### GPU Container Access Permissions

If you encounter GPU access issues in containers:

```bash
# Check that nvidia-uvm module is loaded
lsmod | grep nvidia_uvm

# If not loaded:
sudo modprobe nvidia_uvm

# Make it persistent across reboots
echo "nvidia_uvm" | sudo tee /etc/modules-load.d/nvidia-uvm.conf
```

---

## Troubleshooting

### Docker: Permission denied

```bash
# If you get "permission denied" connecting to Docker daemon:
sudo usermod -aG docker $USER
# Then log out and log back in completely (not just a new terminal!)
```

### NVIDIA Container: "could not select device driver"

```bash
# Ensure nvidia-container-toolkit is properly configured
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker

# Verify the daemon.json has nvidia runtime
cat /etc/docker/daemon.json
```

### Isaac Sim: Missing libraries

```bash
# Arch Linux may need these for Isaac Sim's Omniverse Kit
sudo pacman -S --needed vulkan-icd-loader lib32-vulkan-icd-loader \
    libxkbcommon libxrandr libxcursor libxi

# Also ensure you have the NVIDIA Vulkan ICD
sudo pacman -S nvidia-utils  # provides nvidia_icd.json
```

### ROS 2 GUI apps in Docker not displaying

```bash
# Allow X11 connections from Docker
xhost +local:docker

# Make sure to pass display environment variables when running the container
# (see the docker run commands in Section 5)
```

---

## Version Matrix (As of 28 May 2026)

| Component | Version | Install Method |
|-----------|---------|---------------|
| Docker Engine | Latest (Arch repos) | `pacman -S docker` |
| NVIDIA Container Toolkit | 1.19.x (Arch repos) | `pacman -S nvidia-container-toolkit` |
| Isaac Sim | 5.1.0 | `pip install isaacsim[all]==5.1.0` |
| Isaac Lab | main (compatible w/ IsaacSim 5.1) | `pip install isaacsim-isaaclab` |
| ROS 2 Jazzy | Latest patch | Docker: `ros:jazzy-desktop` |
| Isaac ROS | Release 3.2 | Docker dev container |
| NVIDIA GPU Driver | ≥ 535.x (570+ recommended) | `pacman -S nvidia` |
| Python | 3.11 (for Isaac Sim) | `pyenv` or AUR |
| CUDA (in containers) | 12.x | Handled by container images |

---

> [!TIP]
> **Pro tip:** Consider using a shell alias or script to quickly enter your ROS 2 development environment:
> ```bash
> # Add to ~/.bashrc or ~/.zshrc
> alias ros2env='docker start -ai ros2-dev 2>/dev/null || docker run -it --gpus all --network host --ipc host -v ~/ros2_ws:/root/ros2_ws --name ros2-dev ros:jazzy-desktop bash'
> alias isaac='source ~/isaac-sim-venv/bin/activate'
> ```
