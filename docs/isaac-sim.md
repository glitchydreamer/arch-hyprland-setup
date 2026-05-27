# Isaac Sim + Isaac Lab (NVIDIA robotics simulation)

NVIDIA's [Isaac Sim](https://developer.nvidia.com/isaac/sim) (Omniverse-based
robotics simulator) and [Isaac Lab](https://isaac-sim.github.io/IsaacLab/)
(the RL/learning framework on top of it) are installed **as pip/conda packages**
into a dedicated conda environment — *not* the system Python, *not* the ROS 2
Docker image. This is a separate stack from [ROS 2 Jazzy](index.md#74-ros-2-jazzy-via-docker):
ROS 2 lives in Docker; Isaac runs natively against the host GPU.

> **Why conda and not Docker / system Python?** Isaac Sim ships wheels only for
> **Python 3.10/3.11**, and the system interpreter here is **3.14** (see
> [§6.2](index.md#62-python-3145)) — no 3.14 wheels exist, so a bare
> `pip install isaacsim` against system Python fails to resolve. A pinned 3.11
> conda env sidesteps that without downgrading anything system-wide. The pip
> install path (vs. the Omniverse Launcher) is NVIDIA's current recommended flow
> and keeps everything in one `pip freeze`-able place.

## What's installed

| Thing | Value |
|---|---|
| Conda env name | **`isaaclab`** (`~/anaconda3/envs/isaaclab`, ~20 GB) |
| Python | 3.11 |
| Isaac Sim | `isaacsim[all,extscache]==5.1.0` (from `https://pypi.nvidia.com`) |
| PyTorch | `torch==2.7.0+cu128`, `torchvision==0.22.0+cu128` (CUDA 12.8 wheels) |
| Isaac Lab repo | `~/IsaacLab` (cloned from GitHub, editable install, ~346 MB) |
| Verified on | RTX 3060 12 GB, driver 595.71 (CUDA 13.2 capable), glibc 2.43 |

Isaac Sim 5.x requires **GLIBC ≥ 2.35** — Arch is rolling and well past that
(2.43 here), so no concern. The CUDA 12.8 PyTorch wheels bundle their own CUDA
runtime libraries, so they're independent of the system `/opt/cuda` toolkit
([§6.1](index.md#61-dev-toolchain)) — the two don't have to match.

## Install from scratch

The login shell is **fish**; commands below are fish syntax. `conda` is already
a fish function (initialised via `conda init fish`), so `conda activate` works.

### 1. Create the environment

```fish
conda create -n isaaclab python=3.11 -y
conda activate isaaclab
pip install --upgrade pip
```

### 2. Isaac Sim (large — ~10 GB of wheels, the kit cache alone is ~3 GB)

```fish
pip install "isaacsim[all,extscache]==5.1.0" --extra-index-url https://pypi.nvidia.com
```

### 3. PyTorch — force the cu128 build

Step 2 pulls in a default `torch` as a dependency, but it resolves to the
**cu126** build. Reinstall over it with the cu128 wheels Isaac Lab targets:

```fish
pip install -U torch==2.7.0 torchvision==0.22.0 --index-url https://download.pytorch.org/whl/cu128
```

Verify: `python -c "import torch; print(torch.__version__, torch.version.cuda)"`
should print `2.7.0+cu128 12.8`.

### 4. Clone and install Isaac Lab

```fish
git clone https://github.com/isaac-sim/IsaacLab.git ~/IsaacLab
cd ~/IsaacLab
set -x CMAKE_POLICY_VERSION_MINIMUM 3.5   # see gotcha below — required on Arch
./isaaclab.sh --install
```

`./isaaclab.sh --install` does editable `pip install`s of all the `isaaclab_*`
extensions plus learning frameworks (rl_games, rsl_rl, sb3, skrl, robomimic).
Build tools (`cmake`, `gcc`, `make`) come from `base-devel`, already present per
[`install.sh`](https://github.com/glitchydreamer/arch-hyprland-setup/blob/main/install.sh).

### 5. Verify

```fish
set -x OMNI_KIT_ACCEPT_EULA YES   # see gotcha below
cd ~/IsaacLab
./isaaclab.sh -p scripts/tutorials/00_sim/create_empty.py --headless
```

A successful run logs `Using device: cuda:0`, boots Omniverse Kit, and starts
stepping a PhysX sim. `create_empty.py` loops until you close it (no "finished"
message — that's expected); Ctrl-C to stop. First launch is slow: it compiles
shaders and warms the asset cache.

## Arch-specific gotchas (all hit during this install)

### `egl_probe` fails to build: "Compatibility with CMake < 3.5 has been removed"

`./isaaclab.sh --install` pulls `robomimic`, which depends on `egl_probe`, whose
`CMakeLists.txt` declares an ancient `cmake_minimum_required`. Arch ships **CMake
4.x** (4.3.3 here), which **removed** policy compatibility below 3.5 — so the
build errors out with `make: *** No targets specified` and the whole install
fails.

Fix: set `CMAKE_POLICY_VERSION_MINIMUM=3.5` before running the install (step 4
above), which tells modern CMake to tolerate the old minimum.

```fish
set -x CMAKE_POLICY_VERSION_MINIMUM 3.5
./isaaclab.sh --install
```

### Headless runs hang on the EULA prompt

A non-interactive run (headless, no TTY on stdin) stops at
`Do you accept the EULA? (Yes/No):` and dies with `EOF when reading a line`.
Accept it via env var:

```fish
set -x OMNI_KIT_ACCEPT_EULA YES
```

Worth adding to `dev-env.fish` if you run Isaac headless often
([§6.2 fish additions](index.md#1-file-layout-where-things-live)).

### `pip install isaacsim` "could not find a version" against system Python

The base/system interpreter is **3.14**, which has no Isaac Sim wheels. Always
install inside the `isaaclab` 3.11 conda env — never the system Python.

### Harmless pip resolver warnings

The install prints `ERROR: pip's dependency resolver does not currently take
into account…` about `psutil` (Isaac Sim pins `5.9.8`, robomimic wants `7.x`).
Non-fatal — the sim runs fine. Likewise `packaging` is pinned to `23.0` by
Isaac Sim against a newer `wheel`; also harmless.

## Day-to-day use

```fish
conda activate isaaclab
cd ~/IsaacLab

# Run any Isaac Lab script through the launcher (sets up the Python env)
./isaaclab.sh -p scripts/tutorials/00_sim/create_empty.py --headless

# Train an example agent (rsl_rl)
./isaaclab.sh -p scripts/reinforcement_learning/rsl_rl/train.py --task=Isaac-Ant-v0 --headless

# Standalone Isaac Sim app
isaacsim
```

`--headless` is the safe default on this box. The Isaac Sim **GUI** renders via
Vulkan and historically prefers X11 — under pure **Wayland/Hyprland** the
windowed app can misbehave. If the GUI is needed, launch it through XWayland
(`env -u WAYLAND_DISPLAY isaacsim`) or stick to headless + a separate viewer.
Headless training/inference is unaffected and uses the GPU directly (`cuda:0`).

## Useful URLs

- Isaac Lab pip install guide: <https://isaac-sim.github.io/IsaacLab/main/source/setup/installation/pip_installation.html>
- Isaac Lab docs: <https://isaac-sim.github.io/IsaacLab/>
- Isaac Sim docs: <https://docs.isaacsim.omniverse.nvidia.com/>
- Isaac Lab GitHub: <https://github.com/isaac-sim/IsaacLab>
