# Isaac Sim + Isaac Lab (NVIDIA robotics simulation)

> **Route (2026-05-27): containerized (Docker).** The earlier conda/native install
> was [abandoned](#appendix-the-abandoned-conda-route) after Isaac Sim 5.1's RTX
> renderer segfaulted on this box's NVIDIA **595** driver and Arch's rolling
> userspace kept breaking NVIDIA's prebuilt `.so`s (libxml2 soname, `os-release`
> parsing). The official **Docker container** sidesteps all of that: it ships a
> matched Ubuntu 22.04 userspace and its **own** Vulkan loader, and shares only
> the host *kernel* driver through the NVIDIA Container Toolkit. That removes the
> Arch packaging problems outright and is the best shot at the RTX crash, since
> that crash was in a userspace renderer plugin running against Arch's mismatched
> userspace — not in the kernel driver itself.

## Why container, not source build

| | Container (chosen) | Source / native |
|---|---|---|
| Userspace | NVIDIA's matched Ubuntu 22.04 | Arch rolling — broke libxml2, `os-release`, CMake |
| Vulkan loader | Bundled in the image | System loader (the suspected RTX-crash factor) |
| Kernel driver | Host's (shared via Container Toolkit) | Host's |
| ROS 2 | Isaac's bundled Jazzy bridge, or Isaac Lab `ros2` profile | hand-wired |
| Upgrades | `docker pull` a new tag | re-fight Arch ABI drift every rolling update |

A source build keeps running against Arch userspace, so it would reintroduce
exactly the breakage that killed the conda route. The container is the robust,
reproducible path.

## Prerequisites (all handled by `install.sh`)

- Docker + `docker-buildx` + `nvidia-container-toolkit` (the `containers` group).
- `nvidia-ctk runtime configure --runtime=docker` + the docker service enabled.
- Your user in the `docker` group (**log out/in once** for it to take effect).
- **Docker storage on `/home`.** The root partition is small (~50G) and the Isaac
  Sim image is ~20GB extracted — pulling it onto root fails with *no space left on
  device*. Two `daemon.json` keys fix this, both set by `install.sh`:
  `"data-root": "/home/docker-data"` **and**
  `"features": {"containerd-snapshotter": false}`. The second is essential — with
  the containerd image store enabled (`Storage Driver: overlayfs`), layers go to
  `/var/lib/containerd` on root and `data-root` is *ignored*; disabling it falls
  back to the `overlay2` graph driver, which honors `data-root`. On an existing
  system, run [`migrate-docker-to-home.sh`](https://github.com/glitchydreamer/arch-hyprland-setup/blob/main/migrate-docker-to-home.sh)
  (sets both keys, reclaims the orphaned partial layers, restarts docker). Verify with
  `docker info | grep -E "Storage Driver|Docker Root"` → want `overlay2` +
  `/home/docker-data`.

Sanity check the GPU is visible inside Docker:

```fish
docker run --rm --runtime=nvidia --gpus all ubuntu nvidia-smi
```

> **NGC pull may need a login.** `nvcr.io/nvidia/isaac-sim:5.1.0` is public but
> NGC sometimes still requires an authenticated pull. If `docker pull` 401s, get
> a free API key at <https://ngc.nvidia.com> → *Setup → API Key*, then
> `docker login nvcr.io` (username `$oauthtoken`, password = the key).

## Isaac Sim — the container

`install.sh` does the one-time setup: pulls `nvcr.io/nvidia/isaac-sim:5.1.0`,
creates the host cache/data dirs under `~/docker/isaac-sim` (owned `1234:1234`,
the container's internal UID), and installs the **`isaac-sim`** launcher in
`~/.local/bin` (a sibling of `ros2-jazzy`). The persistent cache dirs mean shader
compiles and asset downloads survive across `--rm` container runs.

### The `isaac-sim` launcher

```fish
isaac-sim pull        # docker pull the image
isaac-sim compat      # run NVIDIA's compatibility_check (GPU/driver/Vulkan)
isaac-sim headless    # runheadless.sh — WebRTC livestream (the realistic GUI on Wayland)
isaac-sim shell       # drop into a bash shell inside the container
isaac-sim stop        # stop/remove a running container
```

It runs the container with `--gpus all`, the cache mounts, `ACCEPT_EULA=Y` /
`PRIVACY_CONSENT=Y`, and — for ROS — `--network=host --ipc=host` plus
`ROS_DISTRO=jazzy` so the bundled bridge lines up with your `ros2-jazzy`
container (see [below](#ros-2-jazzy-integration)).

**Start here** to validate the GPU path actually renders (this is what failed on
the conda route):

```fish
isaac-sim compat        # expect a PASS for GPU, driver, and Vulkan
```

The native Isaac Sim window does not play well with Wayland; the supported way
to "see" it is the **WebRTC livestream** from `isaac-sim headless` (open the
Omniverse Streaming Client or the WebRTC browser client against `localhost`).
Headless training/inference needs no display at all.

## Isaac Lab — the container

Isaac Lab ships its own Dockerfile that builds **on top of** the Isaac Sim image,
driven by `docker/container.py`. The repo must live under `/home` (a Docker mount
requirement). `install.sh` clones it to `~/robotics/IsaacLab`.

```fish
cd ~/robotics/IsaacLab

./docker/container.py start base      # build + start (detached). use `ros2` for the ROS profile
./docker/container.py enter base      # bash into the running container
# inside: ./isaaclab.sh -p scripts/tutorials/00_sim/create_empty.py --headless
./docker/container.py stop  base      # stop + remove
```

> **X11 forwarding needs `xauth` on the host.** `container.py` runs `xauth` on the
> Arch host to build the `.xauth` file it mounts in; without it you get *"xauth is
> not installed … the temporary .xauth file does not exist"*. Install `xorg-xauth`
> (in `install.sh`). On pure Wayland you can instead skip it by setting
> `X11_FORWARDING_ENABLED=0` in `docker/.container.cfg` and using livestream.

Profiles:

- **`base`** — Isaac Lab only.
- **`ros2`** — adds ROS 2 **Humble** (`ros-base`, `rmw_fastrtps_cpp`), sourced in
  `.bashrc`. Configured via `docker/.env.ros2` and `docker/.ros/`.

> **Distro note.** Isaac Lab's `ros2` profile is **Humble**, but your standalone
> `ros2-jazzy` container and Isaac Sim's *bundled* bridge are **Jazzy**. For
> Jazzy↔Jazzy work, prefer Isaac Sim's bundled bridge over the Isaac Lab Humble
> profile — cross-distro DDS is wire-level only and unsupported.

Volumes (`logs`, `data_storage`, `docs/_build`) are retrievable to
`docker/artifacts` with `./docker/container.py copy`.

## ROS 2 Jazzy integration

ROS 2 Jazzy runs in [its own container](index.md#74-ros-2-jazzy-via-docker)
(`~/.local/bin/ros2-jazzy`). Isaac Sim's `isaacsim.ros2.bridge` extension ships
its **own internal ROS 2 Jazzy** (FastDDS, in `…/isaacsim.ros2.bridge/jazzy/lib`),
so no host ROS install is needed. The two containers talk over **DDS**:

- Both run **`--network host --ipc host`**. `--network host` shares the network
  namespace; **`--ipc host` is essential** because FastDDS uses shared-memory
  (`/dev/shm`) transport between same-host endpoints. The classic symptom of a
  missing `--ipc host` is *topics appear in `ros2 topic list` but no data flows*.
- Both default to **`rmw_fastrtps_cpp`** and the same **`ROS_DOMAIN_ID`** (0).
- `ROS_DISTRO=jazzy` is set for the Isaac container — it both selects the bundled
  Jazzy libs and skips the `get_ubuntu_version()` autodetect that crashed on Arch.

> **Cross-UID `/dev/shm`.** The Isaac container runs as internal UID `1234`; your
> `ros2-jazzy` runs as root inside its container. With `--ipc host` they share
> `/dev/shm`, but FastDDS SHM segments are owned per-UID, so a mismatch can deny
> SHM and silently fall back to UDP over loopback — which still works under
> `--network host`. If SHM matters, force UDP on both ends instead:
> `export FASTDDS_BUILTIN_TRANSPORTS=UDPv4`.

### Verify the link

```fish
# terminal 1 — Isaac Sim with a ROS2 publisher graph (bundled bridge)
isaac-sim headless        # then enable isaacsim.ros2.bridge + a ROS2 publisher
```

```fish
# terminal 2 — the ROS 2 Jazzy container should SEE and RECEIVE the topics
ros2-jazzy run "ros2 topic list"          # should list Isaac's topics
ros2-jazzy run "ros2 topic echo /clock"   # should stream (proves --ipc host)
```

If `topic list` is empty: confirm `ROS_DOMAIN_ID` matches and no firewall blocks
loopback multicast. If `list` works but `echo` hangs: the `/dev/shm` path — fall
back to UDP as above.

---

## Appendix: the abandoned conda route

> Kept as a record. **Do not follow this** — it's the route that broke. It's here
> only because the individual fixes (libxml2, `get_ubuntu_version`) might help if
> the bundled-container libs ever exhibit the same symptoms.

The original install put `isaacsim[all,extscache]==5.1.0` + Isaac Lab into a
Python 3.11 **conda env** (`isaaclab`, ~20 GB) against the host GPU. It was
deleted 2026-05-27. Problems hit, in order:

1. **CMake ≥ 4 rejects `cmake_minimum_required < 3.5`** (via `egl_probe` ←
   `robomimic`). Workaround: `set -x CMAKE_POLICY_VERSION_MINIMUM 3.5` before
   `./isaaclab.sh --install`.
2. **`libxml2.so.2: cannot open shared object file`** — Arch's libxml2 2.15
   bumped the soname to `.so.16`; Isaac's prebuilt `.so`s want `.so.2`. Workaround:
   `conda install -c conda-forge libxml2=2.13` + a fish `activate.d` hook adding
   `$CONDA_PREFIX/lib` to `LD_LIBRARY_PATH` (conda doesn't add it; fish sources
   only `*.fish` hooks, not `*.sh`).
3. **`isaacsim.ros2.bridge` → `'NoneType' object has no attribute 'split'`** —
   `get_ubuntu_version()` parses `/etc/os-release`, which on rolling Arch has no
   `VERSION_ID`. Workaround: `set -x ROS_DISTRO jazzy` (skips the autodetect), or
   patch `ros2_common.py` to `return "jazzy"` when `VERSION_ID` is falsy.
4. **RTX renderer SIGSEGV** in `librtx.scenedb.plugin.so!carbOnPluginStartup` on
   driver **595.71.05** — the showstopper. System Vulkan was healthy and it
   wasn't a stale cache; the crash was a userspace RTX-plugin↔Arch-userspace/595
   incompatibility. Only non-rendering headless runs worked. This is the reason
   the route was dropped and the container route adopted.

## Useful URLs

- Isaac Sim container install: <https://docs.isaacsim.omniverse.nvidia.com/5.1.0/installation/install_container.html>
- Isaac Lab Docker guide: <https://isaac-sim.github.io/IsaacLab/main/source/deployment/docker.html>
- Isaac Lab deployment index: <https://isaac-sim.github.io/IsaacLab/main/source/deployment/index.html>
- Isaac Lab docs: <https://isaac-sim.github.io/IsaacLab/>
- Isaac Sim docs: <https://docs.isaacsim.omniverse.nvidia.com/>
