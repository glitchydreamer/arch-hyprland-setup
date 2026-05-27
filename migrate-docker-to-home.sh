#!/usr/bin/env bash
# ============================================================================
# migrate-docker-to-home.sh — move an EXISTING Docker install's storage off the
# small (~50G) root partition onto /home, so the big Isaac Sim image fits.
#
# install.sh already configures this for FRESH installs (data-root +
# containerd-snapshotter=false). Use THIS only when Docker already has data under
# /var/lib and you need to relocate it. Run as your normal user (calls sudo).
# Safe to re-run / idempotent. Reversible: drop the keys from daemon.json + restart.
#
# Why two changes are needed:
#   - data-root -> /home/docker-data
#   - containerd-snapshotter=false: with the containerd image store ON
#     (Storage Driver: overlayfs), layers live under /var/lib/containerd and
#     data-root is IGNORED. Disabling it falls back to the overlay2 graph driver,
#     which honors data-root.
# ============================================================================
set -uo pipefail

NEWROOT=/home/docker-data
DJSON=/etc/docker/daemon.json

echo ">>> Stopping docker"
sudo systemctl stop docker docker.socket 2>/dev/null || true

echo ">>> Writing $DJSON: data-root=$NEWROOT + containerd-snapshotter=false (keep nvidia runtime)"
sudo install -d -m 0711 "$NEWROOT"
sudo python - "$DJSON" "$NEWROOT" <<'PY'
import json, sys, os
path, newroot = sys.argv[1], sys.argv[2]
d = {}
if os.path.exists(path):
    try:
        with open(path) as f: d = json.load(f)
    except Exception: d = {}
d["data-root"] = newroot
d.setdefault("features", {})["containerd-snapshotter"] = False
with open(path, "w") as f: json.dump(d, f, indent=2)
print("wrote", json.dumps(d))
PY

echo ">>> Reclaiming orphaned containerd image layers (failed pulls) + old graph dir"
sudo systemctl stop containerd 2>/dev/null || true
sudo rm -rf /var/lib/containerd/io.containerd.snapshotter.v1.overlayfs/snapshots/* \
            /var/lib/containerd/io.containerd.content.v1.content/* 2>/dev/null || true
sudo rm -rf /var/lib/docker 2>/dev/null || true   # unused now that data-root moved
sudo systemctl start containerd 2>/dev/null || true

echo ">>> Starting docker"
sudo systemctl start docker
sleep 2

echo ">>> Verify (want: Storage Driver: overlay2  +  Docker Root Dir: /home/docker-data):"
docker info 2>/dev/null | grep -iE "Storage Driver|Docker Root Dir"
echo ">>> Root partition free space now:"
df -h / | awk 'NR==2{print "  / used "$3" of "$2" ("$5"), "$4" free"}'
echo ">>> Now re-pull:  isaac-sim pull"
