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

### `libxml2.so.2: cannot open shared object file` — dozens of extensions fail

Launching `isaacsim` (or any GUI/asset path) spams errors and disables the
**asset converter**, **URDF/MJCF importers**, and the **CAD converters**
(`omni.kit.asset_converter`, `isaacsim.asset.importer.{urdf,mjcf}`,
`omni.kit.converter.*`, `omni.services.convert.*`). Every traceback ends in:

```
OSError: libxml2.so.2: cannot open shared object file: No such file or directory
```

Cause: Isaac Sim's prebuilt `.so`s are linked against the old **`libxml2.so.2`**
soname. Arch's `libxml2` is now **2.15**, which bumped the soname to
`libxml2.so.16` — so `.so.2` simply doesn't exist on the system anymore.

Fix: install an older libxml2 (≤ 2.13, still provides `.so.2`) **into the conda
env** and put the env's `lib` on the loader path. No sudo — it's all env-local.

```fish
conda install -n isaaclab -c conda-forge "libxml2=2.13" -y
```

conda does **not** add `$CONDA_PREFIX/lib` to `LD_LIBRARY_PATH`, so add an
activation hook (fish integration sources only `*.fish`, not `*.sh`):

```fish
# ~/anaconda3/envs/isaaclab/etc/conda/activate.d/zz_isaacsim_libpath.fish
set -gx _ISAACSIM_OLD_LD_LIBRARY_PATH $LD_LIBRARY_PATH
if set -q LD_LIBRARY_PATH
    set -gx LD_LIBRARY_PATH "$CONDA_PREFIX/lib:$LD_LIBRARY_PATH"
else
    set -gx LD_LIBRARY_PATH "$CONDA_PREFIX/lib"
end
```

with a matching `deactivate.d/zz_isaacsim_libpath.fish` that restores it. Then
re-activate the env (`conda deactivate; conda activate isaaclab`) and verify:
`python -c "import ctypes; ctypes.CDLL('libxml2.so.2')"` should be silent.

### `isaacsim.ros2.bridge` fails: `'NoneType' object has no attribute 'split'`

The ROS 2 bridge calls `get_ubuntu_version()`, which parses `/etc/os-release`;
Arch is rolling and has no `VERSION_ID`, so it returns `None` and crashes that
extension. It's non-fatal to Isaac Sim itself, but the bridge stays disabled.

Fix (primary): set **`ROS_DISTRO=jazzy`** before launch — the bridge only runs
that autodetect when `ROS_DISTRO` is unset (`extension.py` line ~53), so setting
it skips the broken path *and* selects the bundled internal Jazzy libraries.
This is wired into the `zz_isaacsim_ros2.*` activation hook — see
[Connecting Isaac Sim to the dockerized ROS 2 Jazzy](#connecting-isaac-sim-to-the-dockerized-ros-2-jazzy)
for the full bridge↔Docker setup.

Fix (belt-and-suspenders, survives a stale shell): patch the autodetect so it
can't crash. In `…/isaacsim.ros2.bridge/isaacsim/ros2/bridge/impl/ros2_common.py`,
`get_ubuntu_version()` does `version.split(".")` on a `None` `VERSION_ID`. Guard it:

```python
version = os_release.get("VERSION_ID")
# Arch / rolling distros have no VERSION_ID; avoid crashing and default to jazzy.
if not version:
    carb.log_warn("os-release has no VERSION_ID (rolling distro?); defaulting ROS distro to 'jazzy'")
    return "jazzy"
major_version = version.split(".")[0]
```

This edit lives in `site-packages`, so **re-apply it after any
`pip install --upgrade isaacsim`** (or reinstall of the env).

### GUI / RTX renderer SIGSEGV in `librtx.scenedb.plugin.so` (driver 595)

**Open issue (unresolved).** Launching the windowed `isaacsim` app — or any
path that initialises the RTX renderer (e.g. `SimulationApp({"headless": True})`
with the default experience, which waits for a viewport) — segfaults during
renderer startup:

```
librtx.scenedb.plugin.so!carbOnPluginStartup+0x3b4de
…
Segmentation fault (core dumped)
```

The crash is in NVIDIA's RTX scene-renderer plugin while it builds its
shader/material tables, **not** in anything Arch-specific or ROS-related. Ruled
out so far:

- System **Vulkan is healthy** — `vulkaninfo --summary` succeeds (NVIDIA
  proprietary 595.71.05, Vulkan 1.4.329, single clean `nvidia_icd.json`).
- **Not a stale cache** — `~/.cache/ov` is nearly empty (the renderer dies
  before populating it); clearing it changes nothing.
- The driver is **595.71.05**, and Isaac Sim 5.1's own startup check warns it is
  newer than the validated range (recommended ~535.x; "latest may work but is
  not fully tested"). Prime suspect: RTX-renderer incompatibility with the 595
  driver branch.

**What still works:** headless runs that don't render. `./isaaclab.sh -p
scripts/tutorials/00_sim/create_empty.py --headless` runs clean for minutes
(`Using device: cuda:0`, PhysX stepping) because the `isaaclab.python.headless.kit`
experience defers RTX scenedb until rendering is actually requested.

**Implication for ROS 2:** non-rendering bridge traffic (clock, TF, joint
states, twist commands) should be fine headless; any camera/RTX-sensor topic
needs the renderer and is blocked until this is resolved.

Likely fix paths (not yet attempted — driver changes are a system-level
decision): try a validated NVIDIA driver branch (550.x / 535.x), or wait for an
Isaac Sim point release that supports 595.

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

## Connecting Isaac Sim to the dockerized ROS 2 Jazzy

Isaac Sim runs **natively**; ROS 2 Jazzy runs in the
[Docker container](index.md#74-ros-2-jazzy-via-docker). They talk over **DDS**,
not a shared filesystem. Key facts that make this work here:

- **No host ROS 2 install needed.** Isaac Sim's `isaacsim.ros2.bridge` extension
  ships its *own* internal ROS 2 Jazzy (FastDDS + CycloneDDS RMW, in
  `…/isaacsim.ros2.bridge/jazzy/lib`). The bridge uses those libs directly.
- **Both ends are Jazzy + `rmw_fastrtps_cpp` + `ROS_DOMAIN_ID=0`** → wire-compatible.
- The container runs **`--network host`**, so it shares the host network
  namespace and DDS discovery happens over localhost.

### What's configured (one-time, already done)

**Isaac side** — a conda activation hook
(`~/anaconda3/envs/isaaclab/etc/conda/activate.d/zz_isaacsim_ros2.{fish,sh}`)
exports, on `conda activate isaaclab`:

```fish
set -gx ROS_DISTRO jazzy            # also skips the Arch get_ubuntu_version() crash
set -gx RMW_IMPLEMENTATION rmw_fastrtps_cpp
```

and `zz_isaacsim_libpath.*` adds the bundled `jazzy/lib` to `LD_LIBRARY_PATH`.
Setting `ROS_DISTRO` is what fixes the bridge crash described above — the bridge
only runs the (broken on Arch) Ubuntu autodetect when `ROS_DISTRO` is unset.

**Container side** — [`~/.local/bin/ros2-jazzy`](index.md#74-ros-2-jazzy-via-docker)
runs with **`--network host --ipc host`**. The `--ipc host` is essential:
`--network host` alone shares the network namespace but **not** `/dev/shm`, and
FastDDS uses shared-memory transport for same-host endpoints. Without it the
classic symptom is *topics show up in `ros2 topic list` but no data arrives*.

### Verify the link

Publish from Isaac Sim, subscribe from the container (or vice-versa). Quick test
using a standalone Isaac Sim ROS 2 sample, then in the container:

```fish
# terminal 1 — native Isaac Sim publishing a clock/tf/camera via an OmniGraph
#             ROS2 node, or any isaacsim.ros2.bridge sample, e.g.:
conda activate isaaclab
isaacsim isaacsim.exp.full.kit   # enable the ROS2 Bridge extension + a ROS2 publisher graph
```

```bash
# terminal 2 — the container should SEE and RECEIVE the topics
ros2-jazzy run "ros2 topic list"          # should list Isaac's topics
ros2-jazzy run "ros2 topic echo /clock"   # should stream data (proves --ipc host works)
```

If `topic list` shows nothing: check `ROS_DOMAIN_ID` matches on both ends and
that no firewall blocks loopback multicast. If `topic list` works but `echo`
hangs: that's the `/dev/shm` issue — confirm the container was (re)started after
the `--ipc host` change (`ros2-jazzy stop` then relaunch).

### Gotchas / alternatives

- **RMW must match.** Both default to FastDDS here. If you switch one to
  CycloneDDS (`rmw_cyclonedds_cpp`), switch the other too.
- **Pure-UDP fallback.** If SHM keeps misbehaving, force UDP on both ends
  instead of `--ipc host`: `export FASTDDS_BUILTIN_TRANSPORTS=UDPv4`.
- **Multiple machines / domains.** Bump `ROS_DOMAIN_ID` (0–101) identically on
  both ends to isolate from other ROS 2 traffic on the LAN.

## Useful URLs

- Isaac Lab pip install guide: <https://isaac-sim.github.io/IsaacLab/main/source/setup/installation/pip_installation.html>
- Isaac Lab docs: <https://isaac-sim.github.io/IsaacLab/>
- Isaac Sim docs: <https://docs.isaacsim.omniverse.nvidia.com/>
- Isaac Lab GitHub: <https://github.com/isaac-sim/IsaacLab>
