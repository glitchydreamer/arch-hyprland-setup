#!/usr/bin/env bash
# ============================================================================
# setup-home.sh — recreates the *home-directory* half of the Arch + Hyprland +
# caelestia setup. No sudo, no packages: just user-owned config files, scripts,
# and git defaults. Interactive + component-based, the mirror of install.sh.
# Run this FIRST, then install.sh for the system half.
#
#     bash ~/Documents/hyprland-rice/arch/setup-home.sh            # menu
#     bash ~/Documents/hyprland-rice/arch/setup-home.sh hyprland scripts
#     bash ~/Documents/hyprland-rice/arch/setup-home.sh --yes all
#     bash ~/Documents/hyprland-rice/arch/setup-home.sh --dry-run all  # preview
#
# Flags:
#   --dry-run   show which files each component WOULD write; touch nothing.
#   --yes / -y  skip the confirmation prompt.
#   all         select every component.
#
# Generalizable: the desktop monitor connector + its current mode are detected at
# runtime (works whether your ultrawide lands on DP-1, DP-2, HDMI-A-1, ...), so
# this isn't pinned to one machine. Idempotent — safe to re-run.
#
# Assumes caelestia is already installed (~/.config/hypr -> caelestia tree).
# ============================================================================
set -uo pipefail

CAE="$HOME/.config/caelestia"
BIN="$HOME/.local/bin"
DRY_RUN=0
ASSUME_YES=0

say() { echo -e "$*"; }
hr()  { echo "------------------------------------------------------------"; }
# In dry-run, announce a component's outputs and bail out of the body.
dry() { [ "$DRY_RUN" -eq 1 ] && { say "    [dry-run] would write: $*"; return 0; }; return 1; }

# Set key=value under [Settings] in a GTK settings.ini (create/append as needed).
set_ini_key() {
    local f="$1" k="$2" v="$3"
    mkdir -p "$(dirname "$f")"
    grep -q '^\[Settings\]' "$f" 2>/dev/null || printf '[Settings]\n' >> "$f"
    if grep -qE "^$k=" "$f" 2>/dev/null; then
        sed -i -E "s|^$k=.*|$k=$v|" "$f"
    else
        sed -i "/^\[Settings\]/a $k=$v" "$f"
    fi
}

# ============================================================================
# Components — a row here + a matching do_<name>() teaches setup-home a new one.
# ============================================================================
COMPONENTS=(
    "hyprland|Hyprland overrides (hypr-vars, hypr-user) + per-host monitor configs & active symlink"
    "caelestia|Caelestia shell.json tweaks (weather/dashboard temperature in °C, not °F)"
    "nautilus|Sweet icons: synthwave Sweet-Purple folders + candy app icons as the GTK icon theme (ICON_THEME=<variant> to pick another)"
    # (the daily file manager is nautilus; the old 'dolphin' tweak component was removed)
    "scripts|~/.local/bin helpers: select-monitors.sh, hdr-toggle, dualsense-audio, ros2-humble, moveit2-humble, vnc-server, remote, lerobot-verify, fastfetch-logo"
    "fastfetch|Point fastfetch at a custom image / GIF / video logo via the fastfetch-logo helper (interactive: just give it the file path)"
    "fish|Fish dev-env additions (~/.config/fish/conf.d/dev-env.fish)"
    "wireplumber|WirePlumber drop-in so the DualSense auto-switches to its headphone jack"
    "git|Global git defaults (branch, autoSetupRemote, rerere, editor, ...)"
    "lerobot|Conda env 'lerobot' with LeRobot for SO-arm 101 real hardware (feetech extras + cmake-4 hook). Editable install from ~/lerobot if present (else PyPI). Overrides: LEROBOT_DIR / LEROBOT_ENV / LEROBOT_EXTRAS / LEROBOT_PY"
)

do_hyprland() {
    if [ ! -e "$HOME/.config/hypr/hyprland.conf" ]; then
        say "!!! caelestia not detected (~/.config/hypr/hyprland.conf missing)."
        say "!!! Install caelestia first; these files plug into its config tree."
    fi
    # Detect the desktop display + its current mode. Prefer a connected non-eDP
    # output; fall back to DP-1 / 1080p60 if Hyprland isn't running.
    local DESK_CONN="DP-1" DESK_MODE="1920x1080@60" c w h r
    if command -v hyprctl >/dev/null && [ -n "${HYPRLAND_INSTANCE_SIGNATURE-}" ]; then
        read -r c w h r < <(hyprctl monitors -j | jq -r \
            '([.[] | select(.name|test("eDP")|not)] + .)[0] | "\(.name) \(.width) \(.height) \(.refreshRate)"')
        [ -n "${c:-}" ] && [ "$c" != null ] && DESK_CONN="$c" && DESK_MODE="${w}x${h}@${r}"
    fi
    say ">>> Desktop display detected: $DESK_CONN @ $DESK_MODE"
    dry "$CAE/{hypr-vars,hypr-user,hypr-monitors-desktop,hypr-monitors-laptop}.conf + hypr-monitors.conf symlink" && return
    mkdir -p "$CAE"

    cat > "$CAE/hypr-vars.conf" <<'EOF'
# User variable overrides — sourced after caelestia's variables.conf,
# before keybinds.conf, so the $kb* app launchers pick these up.

# Most-used apps on single Super (Super+W / C / E / T)
$browser      = firefox
$editor       = code
$fileExplorer = nautilus

# Cursor — sweet-cursors installed via AUR (see install.sh).
$cursorTheme = sweet-cursors
$cursorSize  = 24
EOF

    cat > "$CAE/hypr-user.conf" <<'EOF'
# ============================================================================
# User Hyprland overrides — sourced LAST, so anything here wins.
# Generated by setup-home.sh. Primary display is auto-detected by hdr-toggle.
# ============================================================================

# --- Stuck / duplicate cursor fixes -----------------------------------------
# The cursor frozen at screen centre is an NVIDIA software-cursor artifact. The
# fix is a CPU cursor buffer WITH hardware cursors enabled. (Forcing
# no_hardware_cursors=true actually *caused* the stale software cursor, so it is
# explicitly off here.) Harmless on non-NVIDIA.
cursor {
    no_hardware_cursors = false
    use_cpu_buffer = true
}
# Secondary: the DualSense touchpad also registers as an absolute pointer that
# parks a cursor at centre when the controller is plugged in. The authoritative
# fix is the libinput udev rule from install.sh; this disables it in Hyprland
# too (applied when the device attaches — replug/relogin to take effect).
device {
    name = sony-interactive-entertainment-dualsense-wireless-controller-touchpad
    enabled = false
}

# --- Per-host monitor config (roaming SSD: desktop / laptop eDP-1) -----------
# hypr-monitors.conf is a symlink flipped by select-monitors.sh at login.
source = $cConf/hypr-monitors.conf
exec-once = ~/.local/bin/select-monitors.sh

# --- App launchers on Super+<letter> ----------------------------------------
# $browser/$editor/$fileExplorer handle Super+W/C/E via hypr-vars.conf.
# Super+G shipped as github-desktop (not installed) → retarget to Chrome.
unbind = Super, G
bind   = Super, G, exec, app2unit -- google-chrome-stable

# Caelestia's idle Super+Alt+E → nemo (not installed); drop it.
unbind = Super+Alt, E

# --- App launchers on Super+Shift+<letter> ----------------------------------
bind = Super+Shift, B, exec, app2unit -- brave
bind = Super+Shift, E, exec, app2unit -- microsoft-edge-stable
bind = Super+Shift, A, exec, app2unit -- antigravity
bind = Super+Shift, D, exec, app2unit -- claude-desktop
bind = Super+Shift, K, exec, app2unit -- kwrite
bind = Super+Shift, I, exec, app2unit -- systemsettings
bind = Super+Shift, N, exec, app2unit -- nvidia-settings
bind = Super+Shift, P, exec, app2unit -- missioncenter
bind = Super+Shift, U, exec, app2unit -- plasma-discover
bind = Super+Shift, Z, exec, app2unit -- zen-browser
bind = Super+Shift, V, exec, app2unit -- obsidian

# --- Caelestia panel toggles -------------------------------------------------
bind = Super+Shift, Y, exec, qs -c caelestia ipc call drawers toggle bar
bind = Super+Shift, O, exec, qs -c caelestia ipc call drawers toggle dashboard
bind = Super+Shift, J, exec, qs -c caelestia ipc call drawers toggle utilities

# --- Minimize / restore (scratchpad-as-minimize) ----------------------------
bind = Super, H,       movetoworkspacesilent, special:minimized
bind = Super+Shift, H, togglespecialworkspace, minimized

# NOTE: half-screen snaps (Super+Ctrl+arrows) are intentionally omitted — that
# chord is caelestia's workspace prev/next, and a float-based snap is unreliable
# on the dwindle layout. Reach for tiling resize (Super+Alt+arrows) instead.

# --- HDR toggle on the primary (non-eDP) display ----------------------------
bind = Super+Ctrl+Alt, H, exec, ~/.local/bin/hdr-toggle
EOF

    cat > "$CAE/hypr-monitors-desktop.conf" <<EOF
# Desktop: external ultrawide on $DESK_CONN (auto-detected at setup time).
# 10-bit SDR (sRGB), VRR off (overrides global misc { vrr = 1 }) → locked refresh.
# HDR is opt-in per session via Super+Ctrl+Alt+H (hdr-toggle).
monitor = $DESK_CONN, $DESK_MODE, 0x0, 1, bitdepth, 10, cm, srgb, vrr, 0

# Optional second monitor: Acer VG240YS (1080p165), PORTRAIT, to the RIGHT of the
# ultrawide. A monitor rule is inert until that output is actually plugged in, so
# this is safe to leave active — the Acer just comes up rotated and placed when
# attached. transform 3 = 90° counter-clockwise; if it ends up rotated the wrong
# way, change to "transform, 1" (90° clockwise) and run \`hyprctl reload\`. The panel
# is natively 8-bit, so bitdepth 10 is dithered (not true 10-bit) — drop it if the
# monitor ever fails to light at 10-bit. Assumes the Acer lands on DP-2; if it comes
# up landscape/auto instead, its connector differs — check \`hyprctl monitors\` and
# update the name here (or switch to a desc: match).
monitor = DP-2, 1920x1080@165, 3440x0, 1, transform, 3, bitdepth, 10, vrr, 0

monitor = , preferred, auto, 1
EOF

    cat > "$CAE/hypr-monitors-laptop.conf" <<'EOF'
# Laptop: internal panel on eDP-1. 8-bit (panel max), VRR inherits global misc{vrr=1}.
monitor = eDP-1, 2560x1600@240, 0x0, 1.25
monitor = , preferred, auto, 1
EOF

    # Point the active symlink at the right file for the machine we're on now.
    if [ -e /sys/class/drm/card*-eDP-1/status ] 2>/dev/null && \
       grep -qx connected /sys/class/drm/card*-eDP-1/status 2>/dev/null; then
        ln -sfn hypr-monitors-laptop.conf "$CAE/hypr-monitors.conf"
    else
        ln -sfn hypr-monitors-desktop.conf "$CAE/hypr-monitors.conf"
    fi
}

do_caelestia() {
    # Caelestia reads ~/.config/caelestia/shell.json. The weather/dashboard panel
    # defaults to Fahrenheit (services.useFahrenheit = true); flip it to Celsius.
    # Merge into the existing JSON so other keys (bar, appearance, ...) are kept.
    local f="$CAE/shell.json"
    dry "$f: merge services.useFahrenheit=false (weather in °C)" && return
    mkdir -p "$CAE"
    python3 - "$f" <<'PY'
import json, sys
f = sys.argv[1]
try:
    with open(f) as fh:
        cfg = json.load(fh)
except (FileNotFoundError, json.JSONDecodeError):
    cfg = {}
cfg.setdefault("services", {})["useFahrenheit"] = False
with open(f, "w") as fh:
    json.dump(cfg, fh, indent=4)
    fh.write("\n")
PY
    say ">>> shell.json: weather set to Celsius (services.useFahrenheit=false)."
    # Caelestia watches shell.json and hot-reloads it — no restart needed.
}

do_nautilus() {
    # "Sweet" icons for nautilus & all GTK apps. Two pieces from the 'theme' install
    # component combine into ONE setting:
    #   · candy-icons      — the rainbow/gradient APP icons
    #   · Sweet-<variant>  — coloured FOLDER icons that already Inherit candy-icons
    # So selecting a Sweet-folders variant gives synthwave folders + candy app icons
    # at once. Default Sweet-Purple (synthwave); override with e.g.
    #   ICON_THEME=Sweet-Rainbow bash setup-home.sh nautilus
    # Variants: Sweet-{Purple,Purple-Filled,Rainbow,Red,Blue,Teal,Yellow,Mars}(-Filled).
    #
    # Icons only, no window theme: nautilus is GTK4/libadwaita, whose colours come
    # solely from caelestia's global ~/.config/gtk-4.0/gtk.css palette (gtk-theme /
    # GTK_THEME are ignored), so a per-app window theme isn't feasible.
    # Switch back to the caelestia default with:  bash uninstall.sh icons
    local variant="${ICON_THEME:-Sweet-Purple}"
    dry "icon-theme=$variant (gsettings + gtk-3.0/gtk-4.0 settings.ini)" && return
    if [ ! -d "/usr/share/icons/$variant" ] && [ ! -d "$HOME/.local/share/icons/$variant" ]; then
        say "!!! icon theme '$variant' not installed — run 'bash install.sh theme' (candy-icons + sweet-folders) first."
        return
    fi
    command -v gsettings >/dev/null && \
        gsettings set org.gnome.desktop.interface icon-theme "$variant" 2>/dev/null || true
    set_ini_key "$HOME/.config/gtk-3.0/settings.ini" gtk-icon-theme-name "$variant"
    set_ini_key "$HOME/.config/gtk-4.0/settings.ini" gtk-icon-theme-name "$variant"
    say ">>> GTK icon theme set to $variant (Sweet folders + candy app icons; nautilus & other GTK apps)."
    say "    · relaunch to see them:  nautilus -q   then reopen nautilus."
    say "    · make it STICK across upgrades (system dconf lock so caelestia/GTK can't"
    say "      reset it to Papirus-Dark):  ICON_THEME=$variant bash install.sh theme"
    say "    · switch back to caelestia default:  bash uninstall.sh icons"
}

do_scripts() {
    dry "$BIN/{select-monitors.sh,hdr-toggle,dualsense-audio}" && return
    mkdir -p "$BIN"

    cat > "$BIN/select-monitors.sh" <<'EOF'
#!/usr/bin/env bash
# Flip ~/.config/caelestia/hypr-monitors.conf to the right per-host file.
# Laptop = a connected eDP-1 panel exists; otherwise desktop.
set -eu
dir="$HOME/.config/caelestia"
link="$dir/hypr-monitors.conf"
target=hypr-monitors-desktop.conf
for f in /sys/class/drm/card*-eDP-1/status; do
    [ -r "$f" ] || continue
    if [ "$(cat "$f")" = "connected" ]; then
        target=hypr-monitors-laptop.conf
        break
    fi
done
current=$(readlink "$link" 2>/dev/null || true)
if [ "$current" != "$target" ]; then
    ln -sfn "$target" "$link"
    [ -n "${HYPRLAND_INSTANCE_SIGNATURE-}" ] && hyprctl reload >/dev/null
fi
EOF

    cat > "$BIN/hdr-toggle" <<'EOF'
#!/usr/bin/env bash
# Toggle HDR <-> sRGB on the primary (non-eDP) display, live (no reload).
# Bound to Super+Ctrl+Alt+H. Detects the monitor and its current mode, so it
# works on any connector/resolution.
set -euo pipefail
MON=$(hyprctl monitors -j | jq -r '([.[] | select(.name|test("eDP")|not)] + .)[0].name')
read -r W H R X Y S STATE < <(hyprctl monitors -j | jq -r --arg m "$MON" \
    '.[] | select(.name==$m) | "\(.width) \(.height) \(.refreshRate) \(.x) \(.y) \(.scale) \(.colorManagementPreset)"')
MODE="${W}x${H}@${R}"
case "$STATE" in
  srgb|unknown)
    hyprctl keyword monitor "$MON, $MODE, ${X}x${Y}, $S, bitdepth, 10, cm, hdr, sdrbrightness, 1.5, sdrsaturation, 1.0"
    notify-send -i video-display "HDR enabled" "$MON • HDR10 / BT.2020"
    ;;
  *)
    hyprctl keyword monitor "$MON, $MODE, ${X}x${Y}, $S, bitdepth, 10, cm, srgb, vrr, 0"
    notify-send -i video-display "HDR disabled" "$MON • sRGB / 10-bit"
    ;;
esac
EOF

    cat > "$BIN/dualsense-audio" <<'EOF'
#!/usr/bin/env bash
# Route a DualSense controller's audio to the 3.5mm headphone jack and make it
# the default output. The DualSense exposes Speaker vs Headphones as separate
# PipeWire/UCM *profiles*; the jack only produces sound on a Headphones profile.
# Run this when earphones in the controller jack are silent.
set -euo pipefail
CARD=$(pactl list cards short | awk '/Sony|DualSense/{print $2; exit}')
[ -n "${CARD:-}" ] || { echo "No DualSense card found." >&2; exit 1; }
pactl set-card-profile "$CARD" 'HiFi (Headphones, Mic)'
sleep 0.5
SINK=$(pactl list sinks short | awk '/Sony|DualSense/{print $2; exit}')
[ -n "${SINK:-}" ] || { echo "No DualSense sink after profile switch." >&2; exit 1; }
pactl set-default-sink "$SINK"
pactl set-sink-mute   "$SINK" 0
pactl set-sink-volume "$SINK" 70%
command -v notify-send >/dev/null && notify-send -i audio-headphones "DualSense audio" "Routed to 3.5mm headphones"
EOF

    # ros2-humble: thin wrapper around the osrf/ros:humble-desktop-full container.
    # Humble (NOT Jazzy) on purpose — it matches Isaac Sim's BUNDLED ROS 2 bridge,
    # which is Humble / Fast DDS 2.6. A Jazzy container crashed Isaac: the two
    # distros encode the ros_discovery_info graph message differently, so Isaac's
    # listener mis-deserialized it and aborted. --network host + a shared
    # ROS_DOMAIN_ID/RMW let it share a DDS domain with Isaac's bridge (Isaac runs
    # natively on driver 580; the NVIDIA Container Toolkit injects that same driver,
    # so --gpus all works).
    cat > "$BIN/ros2-humble" <<'EOF'
#!/usr/bin/env bash
# Thin wrapper around the osrf/ros:humble-desktop-full Docker image.
# WHY Humble, not Jazzy: Isaac Sim's bundled ROS 2 bridge is Humble (Fast DDS 2.6).
# A Jazzy container (Fast DDS 2.14) crashed Isaac because the two distros serialize
# the rmw_dds_common ros_discovery_info (ParticipantEntitiesInfo) graph message
# differently (XCDR v2 vs v1) — Isaac's discovery listener mis-read a length field,
# tried a huge allocation and aborted. Matching the distro removes the mismatch.
#
# Host ~/robotics/ws is mounted at /root/ws. GPU + X11/Wayland sockets forwarded.
# --network host + matching ROS_DOMAIN_ID/RMW let this container share a Fast DDS
# domain with Isaac's bridge.
#
# A Fast DDS XML profile forces UDP-only transport (useBuiltinTransports=false +
# a single UDPv4 transport). Discovery already rides UDP fine across the
# host↔container boundary, but the default shared-MEMORY data transport silently
# drops every sample because native Isaac (UID 1000) and the container (root) can't
# share /dev/shm segments — so `ros2 topic echo`/`hz` saw a publisher but zero data.
# On Jazzy we used FASTDDS_BUILTIN_TRANSPORTS=UDPv4, but that env var doesn't exist
# in Humble's Fast DDS 2.6 (added in 2.10/Iron), so we use the XML profile instead.
set -euo pipefail

IMAGE="osrf/ros:humble-desktop-full"
NAME="ros2-humble"
WS="$HOME/robotics/ws"
PROFILE="$HOME/.config/ros2/fastdds-udp-only.xml"
mkdir -p "$WS" "$(dirname "$PROFILE")"

# Fast DDS 2.6 transport profile: replace the builtin transports (which include
# shared memory) with one UDPv4 transport. Written once — delete it to regenerate.
if [ ! -f "$PROFILE" ]; then
  cat > "$PROFILE" <<'PROFILEEOF'
<?xml version="1.0" encoding="UTF-8" ?>
<dds xmlns="http://www.eprosima.com/XMLSchemas/fastRTPS_Profiles">
  <profiles>
    <transport_descriptors>
      <transport_descriptor>
        <transport_id>udp_only</transport_id>
        <type>UDPv4</type>
      </transport_descriptor>
    </transport_descriptors>
    <participant profile_name="udp_only_participant" is_default_profile="true">
      <rtps>
        <userTransports>
          <transport_id>udp_only</transport_id>
        </userTransports>
        <useBuiltinTransports>false</useBuiltinTransports>
      </rtps>
    </participant>
  </profiles>
</dds>
PROFILEEOF
fi

run_args=(
  --gpus all
  -e DISPLAY="${DISPLAY:-}"
  -e WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-}"
  -e XDG_RUNTIME_DIR=/tmp
  -e QT_X11_NO_MITSHM=1
  -e ROS_DOMAIN_ID="${ROS_DOMAIN_ID:-0}"
  -e RMW_IMPLEMENTATION="${RMW_IMPLEMENTATION:-rmw_fastrtps_cpp}"
  -e FASTRTPS_DEFAULT_PROFILES_FILE=/opt/fastdds-udp-only.xml
  -v "$PROFILE":/opt/fastdds-udp-only.xml:ro
  -v /tmp/.X11-unix:/tmp/.X11-unix
  -v "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/${WAYLAND_DISPLAY:-wayland-1}":"/tmp/${WAYLAND_DISPLAY:-wayland-1}"
  -v "$WS":/root/ws
  --network host
  --ipc host
)

# X11 GUI (rviz2/rqt): this Hyprland/Xwayland session starts X with no auth cookie,
# so X clients can't connect until the local root user (the container runs as root)
# is allow-listed. Idempotent; a no-op if xhost is missing or the grant already exists.
if [ -n "${DISPLAY:-}" ] && command -v xhost >/dev/null 2>&1; then
  xhost +SI:localuser:root >/dev/null 2>&1 || true
fi

cmd="${1:-shell}"
case "$cmd" in
  shell)
    if docker ps --format '{{.Names}}' | grep -qx "$NAME"; then
      exec docker exec -it "$NAME" bash
    fi
    exec docker run -it --rm --name "$NAME" "${run_args[@]}" "$IMAGE" bash
    ;;
  run)   shift; exec docker run -it --rm --name "$NAME" "${run_args[@]}" "$IMAGE" bash -lc "$*" ;;
  attach) exec docker exec -it "$NAME" bash ;;
  stop)  exec docker stop "$NAME" ;;
  pull)  exec docker pull "$IMAGE" ;;
  *) echo "usage: ros2-humble [shell|run \"<cmd>\"|attach|stop|pull]" >&2; exit 1 ;;
esac
EOF

    # moveit2-humble: sibling of ros2-humble for the official MoveIt 2 Humble tutorial
    # container (moveit/moveit2:humble-humble-tutorial-source). It deliberately REUSES
    # ros2-humble's Fast DDS UDP-only profile and ~/robotics/ws workspace so MoveIt 2,
    # the ros2-humble container, and Isaac Sim's bundled Humble bridge all share one
    # DDS domain + workspace and nothing drops samples. (The upstream MoveIt
    # docker-compose has no UDP-only profile, so it would silently fail to exchange
    # data with native Isaac across the host↔container boundary.) Same root user, so
    # the X11/Wayland/GPU mounts carry over unchanged; the image's prebuilt MoveIt
    # overlay (/root/ws_moveit) is sourced on entry and left untouched by the mount.
    cat > "$BIN/moveit2-humble" <<'EOF'
#!/usr/bin/env bash
# Thin wrapper around the moveit/moveit2:humble-humble-tutorial-source Docker image
# (the official MoveIt 2 Humble tutorial container — MoveIt + colcon overlay prebuilt).
#
# WHY this works with the rest of the stack: MoveIt 2 here is Humble, so it speaks the
# same Fast DDS 2.6 / XCDR wire format as Isaac Sim's bundled bridge AND the
# ros2-humble container — no cross-distro discovery mismatch (see ros2-humble for the
# Jazzy crash story). It deliberately SHARES two things with ros2-humble so all three
# (Isaac ⇄ ros2-humble ⇄ moveit2) sit on one DDS domain and one workspace:
#   * the SAME ~/.config/ros2/fastdds-udp-only.xml profile — forces UDP-only transport
#     so samples aren't silently dropped over the default shared-MEMORY path (native
#     Isaac is UID 1000, the container is root → they can't share /dev/shm segments).
#   * the SAME host ~/robotics/ws workspace, mounted at /root/ws.
# --network host + matching ROS_DOMAIN_ID/RMW complete the shared domain. The MoveIt
# image's own prebuilt overlay lives at /root/ws_moveit inside the image (a different
# dir from the /root/ws workspace mount, so neither clobbers the other); this helper
# sources it for you on entry.
# GPU works via --gpus all (NVIDIA Container Toolkit injects the native 580 driver).
set -euo pipefail

IMAGE="moveit/moveit2:humble-humble-tutorial-source"
NAME="moveit2-humble"
WS="$HOME/robotics/ws"
PROFILE="$HOME/.config/ros2/fastdds-udp-only.xml"
mkdir -p "$WS" "$(dirname "$PROFILE")"

# Fast DDS 2.6 transport profile: replace the builtin transports (which include
# shared memory) with one UDPv4 transport. Shared with ros2-humble — that helper
# writes it first in most sessions; we write it here too so moveit2-humble works
# standalone. Delete the file to regenerate.
if [ ! -f "$PROFILE" ]; then
  cat > "$PROFILE" <<'PROFILEEOF'
<?xml version="1.0" encoding="UTF-8" ?>
<dds xmlns="http://www.eprosima.com/XMLSchemas/fastRTPS_Profiles">
  <profiles>
    <transport_descriptors>
      <transport_descriptor>
        <transport_id>udp_only</transport_id>
        <type>UDPv4</type>
      </transport_descriptor>
    </transport_descriptors>
    <participant profile_name="udp_only_participant" is_default_profile="true">
      <rtps>
        <userTransports>
          <transport_id>udp_only</transport_id>
        </userTransports>
        <useBuiltinTransports>false</useBuiltinTransports>
      </rtps>
    </participant>
  </profiles>
</dds>
PROFILEEOF
fi

# Source the image's prebuilt MoveIt overlay if present, else the ROS base. Used as
# the interactive shell's rcfile and as the prefix for `run`.
SOURCE_OVERLAY='if [ -f /opt/ws_moveit/install/setup.bash ]; then source /opt/ws_moveit/install/setup.bash; elif [ -f /root/ws_moveit/install/setup.bash ]; then source /root/ws_moveit/install/setup.bash; else source /opt/ros/humble/setup.bash; fi'

run_args=(
  --gpus all
  -e DISPLAY="${DISPLAY:-}"
  -e WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-}"
  -e XDG_RUNTIME_DIR=/tmp
  -e QT_X11_NO_MITSHM=1
  -e ROS_DOMAIN_ID="${ROS_DOMAIN_ID:-0}"
  -e RMW_IMPLEMENTATION="${RMW_IMPLEMENTATION:-rmw_fastrtps_cpp}"
  -e FASTRTPS_DEFAULT_PROFILES_FILE=/opt/fastdds-udp-only.xml
  -v "$PROFILE":/opt/fastdds-udp-only.xml:ro
  -v /tmp/.X11-unix:/tmp/.X11-unix
  -v "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/${WAYLAND_DISPLAY:-wayland-1}":"/tmp/${WAYLAND_DISPLAY:-wayland-1}"
  -v "$WS":/root/ws
  --network host
  --ipc host
)

# X11 GUI (rviz2/rqt): this Hyprland/Xwayland session starts X with no auth cookie,
# so X clients can't connect until the local root user (the container runs as root)
# is allow-listed. Idempotent; a no-op if xhost is missing or the grant already exists.
if [ -n "${DISPLAY:-}" ] && command -v xhost >/dev/null 2>&1; then
  xhost +SI:localuser:root >/dev/null 2>&1 || true
fi

cmd="${1:-shell}"
case "$cmd" in
  shell)
    if docker ps --format '{{.Names}}' | grep -qx "$NAME"; then
      exec docker exec -it "$NAME" bash -c "$SOURCE_OVERLAY; exec bash"
    fi
    exec docker run -it --rm --name "$NAME" "${run_args[@]}" "$IMAGE" bash -c "$SOURCE_OVERLAY; exec bash"
    ;;
  run)   shift; exec docker run -it --rm --name "$NAME" "${run_args[@]}" "$IMAGE" bash -lc "$SOURCE_OVERLAY; $*" ;;
  attach) exec docker exec -it "$NAME" bash -c "$SOURCE_OVERLAY; exec bash" ;;
  stop)  exec docker stop "$NAME" ;;
  pull)  exec docker pull "$IMAGE" ;;
  *) echo "usage: moveit2-humble [shell|run \"<cmd>\"|attach|stop|pull]" >&2; exit 1 ;;
esac
EOF

    # vnc-server: share THIS Hyprland session over VNC via wayvnc (install.sh 'remote').
    cat > "$BIN/vnc-server" <<'EOF'
#!/usr/bin/env bash
# Share this Hyprland desktop over VNC (wayvnc). Other PCs connect with any VNC
# viewer (Windows: TigerVNC/RealVNC; Linux: remmina/vinagre).
#
#   vnc-server                # bind localhost only (SECURE — reach via SSH tunnel)
#   vnc-server --lan          # expose on the LAN (0.0.0.0) — only on trusted networks
#   vnc-server [--lan] DP-1   # share a specific monitor (default: wayvnc's first)
#
# Secure pattern (default localhost), from the client machine:
#   ssh -L 5900:localhost:5900 <user>@<this-ip>     # then point the viewer at localhost:5900
set -euo pipefail
addr=127.0.0.1
[ "${1:-}" = "--lan" ] && { addr=0.0.0.0; shift; }
out="${1:-}"
command -v wayvnc >/dev/null || { echo "wayvnc not installed — run: bash install.sh remote" >&2; exit 1; }
if [ -n "$out" ]; then exec wayvnc -o "$out" "$addr" 5900; fi
exec wayvnc "$addr" 5900
EOF

    # remote: flip SSH (and stop VNC) on/off per session. sshd is left OFF by
    # default — idle cost is tiny, but off = smaller attack surface.
    cat > "$BIN/remote" <<'EOF'
#!/usr/bin/env bash
# Turn remote access ON only while you need it, OFF when done.
#   remote on       start sshd (accept SSH logins) + show how to reach this box
#   remote off      stop sshd, and stop any running wayvnc (VNC server)
#   remote status   what's listening right now + this box's LAN IP
# sshd is NOT enabled at boot by design. To make it always-on instead:
#   sudo systemctl enable --now sshd
set -euo pipefail
myip() { command ip -4 -o addr show scope global 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -1; }
case "${1:-status}" in
  on)
    sudo systemctl start sshd
    echo "sshd  : ON    →  ssh $USER@$(myip)"
    echo "VNC   : run 'vnc-server' when you want screen sharing (on-demand, localhost)"
    ;;
  off)
    sudo systemctl stop sshd
    pkill -x wayvnc 2>/dev/null && echo "wayvnc: stopped" || true
    echo "sshd  : OFF"
    ;;
  status)
    echo "sshd  : $(systemctl is-active sshd 2>/dev/null)"
    if pgrep -x wayvnc >/dev/null 2>&1; then echo "wayvnc: running"; else echo "wayvnc: not running"; fi
    echo "IP    : $(myip)"
    ss -tlnH 2>/dev/null | awk '$4 ~ /:(22|5900)$/ {print "  listening "$4}'
    ;;
  *) echo "usage: remote [on|off|status]" >&2; exit 1 ;;
esac
EOF

    cat > "$BIN/lerobot-verify" <<'EOF'
#!/usr/bin/env bash
# No-hardware sanity check for the LeRobot conda env. Re-runnable any time;
# also called automatically at the end of `setup-home.sh lerobot`. The env
# name and clone dir can be overridden (matches the install component).
set -u
ENV_NAME="${LEROBOT_ENV:-lerobot}"
CONDA_BASE="$(command -v conda >/dev/null && conda info --base 2>/dev/null)"
if [ -z "$CONDA_BASE" ]; then
    echo "conda not found — install Anaconda first." >&2; exit 1
fi
# shellcheck disable=SC1091
. "$CONDA_BASE/etc/profile.d/conda.sh"
if ! conda env list | awk '{print $1}' | grep -qx "$ENV_NAME"; then
    echo "conda env '$ENV_NAME' not present — run setup-home.sh lerobot first." >&2; exit 1
fi
conda activate "$ENV_NAME"
exec python - "$ENV_NAME" <<'PY'
import importlib, sys, pathlib, shutil, os
env = sys.argv[1] if len(sys.argv) > 1 else "?"
fails = 0
def ok(s):  print(f"  ✓  {s}")
def bad(s): global fails; fails += 1; print(f"  ✗  {s}")
def hdr(s): print(); print("="*60); print(f" {s}"); print("="*60)

hdr(f"1. ENV ({env})")
ok(f"python {sys.version.split()[0]}  ({sys.executable})")

hdr("2. CMAKE-POLICY HOOK (Arch cmake-4 workaround)")
hook = pathlib.Path(os.environ["CONDA_PREFIX"]) / "etc/conda/activate.d/cmake_policy.sh"
(ok if hook.exists() else bad)(f"hook file: {hook}")
v = os.environ.get("CMAKE_POLICY_VERSION_MINIMUM", "")
(ok if v else bad)(f"CMAKE_POLICY_VERSION_MINIMUM={v or '(unset!)'}")

hdr("3. LEROBOT (editable from clone?)")
try:
    import lerobot
    p = pathlib.Path(lerobot.__file__).resolve()
    ok(f"lerobot {lerobot.__version__}")
    ok(f"loaded from {p}")
    (ok if "lerobot/src/lerobot" in str(p) else bad)(
        "editable install" if "lerobot/src/lerobot" in str(p) else "site-packages (PyPI install — clone not in use)")
except Exception as e:
    bad(f"lerobot import: {e}")

hdr("4. PYTORCH + CUDA")
try:
    import torch, torchvision
    ok(f"torch {torch.__version__}  (cuda build {torch.version.cuda})")
    (ok if torch.cuda.is_available() else bad)(f"cuda.is_available()={torch.cuda.is_available()}")
    if torch.cuda.is_available():
        ok(f"device: {torch.cuda.get_device_name(0)}  sm_{''.join(map(str, torch.cuda.get_device_capability(0)))}")
    ok(f"torchvision {torchvision.__version__}")
except Exception as e:
    bad(f"torch stack: {e}")

hdr("5. FEETECH SDK (SO-arm 101 motor bus)")
try:
    import scservo_sdk
    from scservo_sdk import PortHandler, PacketHandler, GroupSyncRead, GroupSyncWrite, COMM_SUCCESS
    ok(f"scservo_sdk loaded from {pathlib.Path(scservo_sdk.__file__).parent}")
    ok(f"PortHandler / PacketHandler / GroupSyncRead/Write all importable (COMM_SUCCESS={COMM_SUCCESS})")
except Exception as e:
    bad(f"scservo_sdk: {e}")

hdr("6. LEROBOT SO-arm 100/101 MODULES (no hardware needed)")
# SO-100 and SO-101 share `so_follower` / `so_leader` — they use identical
# Feetech STS3215 servos and mechanics, so one wrapper covers both.
for m in [
    "lerobot.motors.feetech",
    "lerobot.robots.so_follower",
    "lerobot.robots.bi_so_follower",
    "lerobot.teleoperators.so_leader",
    "lerobot.cameras.opencv",
    "lerobot.datasets.lerobot_dataset",
    "lerobot.policies.factory",
]:
    try: importlib.import_module(m); ok(m)
    except Exception as e: bad(f"{m}  ← {type(e).__name__}: {str(e)[:80]}")

def ver(modname):
    # Some packages (pynput) don't expose __version__ on the top-level module;
    # importlib.metadata is the canonical way to get a version regardless.
    try:
        import importlib.metadata as md
        return md.version(modname.replace("_", "-"))
    except Exception:
        return getattr(importlib.import_module(modname), "__version__", "?")

hdr("7. DATASET STACK (HF datasets + video)")
for m in ["datasets", "pandas", "pyarrow", "av"]:
    try:
        importlib.import_module(m); ok(f"{m} {ver(m)}")
    except Exception as e:
        bad(f"{m}  ← {e}  (try: pip install -e \"~/lerobot[dataset]\")")

hdr("7b. CLI-SCRIPT EXTRAS (hardware + viz from core_scripts)")
for m, hint in [
    ("rerun",  "pip install -e \"~/lerobot[viz]\"      # live visualization"),
    ("pynput", "pip install -e \"~/lerobot[hardware]\" # keyboard teleop"),
]:
    try:
        importlib.import_module(m); ok(f"{m} {ver(m)}")
    except Exception as e:
        bad(f"{m}  ← {e}  ({hint})")

hdr("8. CAMERAS (OpenCV)")
try:
    import cv2
    ok(f"opencv {cv2.__version__}  headless")
except Exception as e: bad(f"cv2: {e}")

hdr("9. CLI ENTRY POINTS")
for cmd in ["lerobot-record", "lerobot-replay", "lerobot-teleoperate",
            "lerobot-train", "lerobot-eval", "lerobot-calibrate", "lerobot-find-port"]:
    path = shutil.which(cmd)
    (ok if path else bad)(f"{cmd}{' → '+path if path else ''}")

print()
print("="*60)
if fails:
    print(f" FAIL — {fails} check(s) did not pass. See markers above.")
    sys.exit(1)
else:
    print(" PASS — env is ready for SO-arm 101 work (plug in & follow LeRobot docs).")
PY
EOF

    # fastfetch-logo — set fastfetch's logo to any image / animated GIF / video.
    # Pre-renders to sixel via chafa (true bitmap quality in foot/ghostty/kitty
    # & graceful fallback elsewhere). Defaults pick the safe layout (position:
    # top) because foot wipes sixel pixels on rows where it later prints text —
    # putting modules underneath the image dodges that bug. See
    # docs/learn/12-fastfetch-logo.md for the full story.
    cat > "$BIN/fastfetch-logo" <<'EOF'
#!/usr/bin/env bash
# fastfetch-logo — point fastfetch at a custom image / animated GIF / video.
#
#   fastfetch-logo PATH                   # auto: image/gif/video → sixel logo
#   fastfetch-logo --size WxH PATH        # chafa render size (default 70x18)
#   fastfetch-logo --frame T PATH         # static frame at T seconds (gif/video)
#   fastfetch-logo --animate PATH         # animated playback via fish_greeting
#   fastfetch-logo --position top|left    # default: top (avoids foot row-clear)
#   fastfetch-logo --none                 # revert to OS ASCII logo
#   fastfetch-logo --info                 # show current logo state
#
# Defaults are tuned for foot at JetBrains Mono 12pt (cell ≈ 8×17 px). The
# --size argument is in *chafa chars* (chafa assumes ~10×20 px cells), so the
# helper scales up width/height in the fastfetch config to match foot's actual
# cell footprint. Bigger --size = sharper but may overflow the viewport.
set -euo pipefail

CFG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/fastfetch"
CFG="$CFG_DIR/config.jsonc"
SIXEL="$CFG_DIR/logo.sixel"
ANIM_MARK="# fastfetch-logo: animated playback"   # marker in fish_greeting

SIZE="70x18"
POSITION="top"
FRAME_TIME="1"
DURATION="3"
MODE="set"          # set | none | info | animate
SRC=""

usage() { sed -n '2,15p' "$0" | sed 's/^# \?//'; }

while [ $# -gt 0 ]; do
    case "$1" in
        --size)      SIZE="$2"; shift 2 ;;
        --position)  POSITION="$2"; shift 2 ;;
        --frame)     FRAME_TIME="$2"; shift 2 ;;
        --duration)  DURATION="$2"; shift 2 ;;
        --animate)   MODE="animate"; shift ;;
        --none)      MODE="none"; shift ;;
        --info)      MODE="info"; shift ;;
        -h|--help)   usage; exit 0 ;;
        -*)          echo "Unknown option: $1" >&2; exit 2 ;;
        *)           SRC="$1"; shift ;;
    esac
done

need() { command -v "$1" >/dev/null || { echo "Missing dep: $1 (install.sh terminal & media)" >&2; exit 1; }; }
need jq

ensure_config() {
    mkdir -p "$CFG_DIR"
    [ -f "$CFG" ] || printf '{ "$schema": "https://github.com/fastfetch-cli/fastfetch/raw/dev/doc/json_schema.json", "logo": null }\n' > "$CFG"
}

revert_fish_greeting() {
    local fg="$HOME/.config/fish/functions/fish_greeting.fish"
    [ -f "$fg" ] || return 0
    grep -q "$ANIM_MARK" "$fg" || return 0
    # Drop the marker line and the chafa line just below it.
    sed -i "/$ANIM_MARK/,+1d" "$fg"
}

case "$MODE" in
    info)
        ensure_config
        echo "config: $CFG"
        echo "sixel:  $SIXEL$([ -f "$SIXEL" ] && echo " ($(du -h "$SIXEL" | cut -f1))")"
        echo "logo block:"
        jq '.logo // "null (OS ASCII fallback)"' "$CFG"
        fg="$HOME/.config/fish/functions/fish_greeting.fish"
        if [ -f "$fg" ] && grep -q "$ANIM_MARK" "$fg"; then
            echo "fish_greeting: animated playback ACTIVE"
            grep -A1 "$ANIM_MARK" "$fg" | sed 's/^/  /'
        fi
        exit 0
        ;;
    none)
        ensure_config
        tmp=$(mktemp)
        jq '.logo = null' "$CFG" > "$tmp" && mv "$tmp" "$CFG"
        rm -f "$SIXEL" "$CFG_DIR/animated."{gif,mp4,webm,mkv,mov} 2>/dev/null || true
        revert_fish_greeting
        echo "Logo cleared (OS ASCII fallback). fish_greeting animation removed."
        exit 0
        ;;
esac

[ -n "$SRC" ] || { usage; exit 2; }
[ -e "$SRC" ] || { echo "File not found: $SRC" >&2; exit 1; }
SRC="$(realpath "$SRC")"

mime=$(file -b --mime-type "$SRC" 2>/dev/null || echo "")
ext="${SRC##*.}"; ext="${ext,,}"
case "$mime" in
    image/gif)     kind=gif ;;
    image/*)       kind=image ;;
    video/*)       kind=video ;;
    *)
        case "$ext" in
            jpg|jpeg|png|webp|bmp|tiff|tif) kind=image ;;
            gif)                             kind=gif ;;
            mp4|mkv|webm|mov|avi)            kind=video ;;
            *) echo "Unsupported type: $mime ($ext)" >&2; exit 1 ;;
        esac ;;
esac

if [ "$MODE" = "animate" ]; then
    [ "$kind" = "image" ] && { echo "--animate needs a GIF or video (got still image)." >&2; exit 1; }
    need chafa
    ensure_config
    # Copy source so the original can move/disappear without breaking the shell.
    dst_ext="${SRC##*.}"
    dst="$CFG_DIR/animated.$dst_ext"
    install -m 0644 "$SRC" "$dst"
    # Clear the fastfetch logo (image is played by fish_greeting before fastfetch).
    tmp=$(mktemp)
    jq '.logo = null' "$CFG" > "$tmp" && mv "$tmp" "$CFG"
    rm -f "$SIXEL"
    # Wire the playback into fish_greeting (idempotent — revert first).
    fg="$HOME/.config/fish/functions/fish_greeting.fish"
    revert_fish_greeting
    if [ -f "$fg" ]; then
        # Insert the chafa playback line just BEFORE the existing fastfetch call.
        if grep -q 'fastfetch' "$fg"; then
            awk -v mark="    $ANIM_MARK" \
                -v cmd="    chafa --animate=on --duration=$DURATION --format=sixel --size=$SIZE '$dst'" \
                '/fastfetch/ && !done { print mark; print cmd; done=1 } { print }' \
                "$fg" > "${fg}.new" && mv "${fg}.new" "$fg"
        else
            printf '\n%s\n%s\n' "    $ANIM_MARK" \
                "    chafa --animate=on --duration=$DURATION --format=sixel --size=$SIZE '$dst'" >> "$fg"
        fi
    fi
    echo "Animated playback wired into fish_greeting."
    echo "  source : $dst"
    echo "  size   : $SIZE     duration: ${DURATION}s"
    echo "Open a new fish shell to see it play, then fastfetch runs underneath."
    exit 0
fi

# Static-frame path: image / gif-first-frame / video-frame.
need chafa
ensure_config

if [ "$kind" = "gif" ] || [ "$kind" = "video" ]; then
    need ffmpeg
    tmp_frame=$(mktemp --suffix=.png)
    trap 'rm -f "$tmp_frame"' EXIT
    echo ">>> Extracting frame at ${FRAME_TIME}s from $(basename "$SRC")"
    ffmpeg -y -hide_banner -loglevel error -ss "$FRAME_TIME" -i "$SRC" -vframes 1 "$tmp_frame" \
        || { echo "Frame extraction failed." >&2; exit 1; }
    render_src="$tmp_frame"
else
    render_src="$SRC"
fi

echo ">>> Rendering sixel via chafa (size=$SIZE, $kind)"
chafa --format=sixel --size="$SIZE" --animate=off "$render_src" > "$SIXEL"

# Compensate for the chafa-vs-foot cell-aspect mismatch (chafa assumes ~10×20 px,
# foot's actual is ~8×17). Multiply both by 1.2 + round up — slightly generous so
# modules don't overlap the sixel; extra empty cells are harmless.
chafa_w="${SIZE%x*}"; chafa_h="${SIZE#*x}"
ff_w=$(awk "BEGIN{print int($chafa_w*1.2)+1}")
ff_h=$(awk "BEGIN{print int($chafa_h*1.2)+1}")

# Keep the source as a literal tilde path so the config is portable across homes.
src_path="~/.config/fastfetch/logo.sixel"
tmp=$(mktemp)
jq --arg src "$src_path" --arg pos "$POSITION" \
   --argjson w "$ff_w" --argjson h "$ff_h" \
   '.logo = {source: $src, type: "raw", position: $pos, width: $w, height: $h, padding: {top:1, left:2, right:4}}' \
   "$CFG" > "$tmp" && mv "$tmp" "$CFG"

# A previously-active animated playback would shadow the new static logo.
revert_fish_greeting

cat <<MSG

Done.
  sixel    : $SIXEL ($(du -h "$SIXEL" | cut -f1))
  position : $POSITION    chafa size: $SIZE    fastfetch cell area: ${ff_w}×${ff_h}

Open a NEW foot terminal and run \`fastfetch\`.
  - clipped? try a smaller --size (e.g. --size 60x14)
  - pixelated? try a larger --size (e.g. --size 90x24) — too big = clip
  - foot's cell aspect (~8×17 px) drives the math; ghostty/kitty differ.
MSG
EOF

    chmod +x "$BIN/select-monitors.sh" "$BIN/hdr-toggle" "$BIN/dualsense-audio" "$BIN/ros2-humble" "$BIN/moveit2-humble" "$BIN/vnc-server" "$BIN/remote" "$BIN/lerobot-verify" "$BIN/fastfetch-logo"
}

do_fastfetch() {
    # Interactive: prompt for a media path, then call ~/.local/bin/fastfetch-logo.
    # No path supplied → leave the current config untouched. Idempotent.
    if [ ! -x "$BIN/fastfetch-logo" ]; then
        say "!!! fastfetch-logo helper not found at $BIN. Run the 'scripts' component first."
        return 1
    fi
    if ! command -v fastfetch >/dev/null; then
        say "!!! fastfetch isn't installed yet (it ships with caelestia; install.sh covers it via the AUR if needed)."
        return 1
    fi
    if ! command -v chafa >/dev/null; then
        say "!!! chafa missing — run 'install.sh terminal' first (or sudo pacman -S chafa)."
        return 1
    fi

    say "\n### fastfetch logo (image / animated GIF / video)"
    say "Supply a path to an image (jpg/png/webp/bmp), an animated GIF, or a video file."
    say "Leave empty to skip (keeps the existing logo); type 'none' to revert to the OS ASCII."

    if [ "$DRY_RUN" -eq 1 ]; then
        say "    [dry-run] would prompt for a path and call $BIN/fastfetch-logo"
        return 0
    fi

    local path mode_choice extra=()
    read -rp "  Media path: " path
    [ -z "$path" ] && { say "    · no path given — keeping current logo."; return 0; }
    if [ "$path" = "none" ]; then
        "$BIN/fastfetch-logo" --none
        return 0
    fi

    # Quick kind detection so we can offer animated playback for GIF/video.
    local kind=image
    case "$(file -b --mime-type "$path" 2>/dev/null)" in
        image/gif) kind=gif ;;
        image/*)   kind=image ;;
        video/*)   kind=video ;;
    esac

    if [ "$kind" != "image" ]; then
        read -rp "  '$path' is a $kind. Animate it on shell startup? [y/N]: " mode_choice
        case "$mode_choice" in y|Y|yes|YES) extra+=(--animate) ;; esac
    fi

    local size
    read -rp "  chafa --size [70x18]: " size
    [ -n "$size" ] && extra+=(--size "$size")

    "$BIN/fastfetch-logo" "${extra[@]}" "$path"
}

do_fish() {
    dry "$HOME/.config/fish/conf.d/dev-env.fish" && return
    mkdir -p "$HOME/.config/fish/conf.d"
    cat > "$HOME/.config/fish/conf.d/dev-env.fish" <<'EOF'
# Personal dev-env additions (caelestia owns config.fish — don't edit that).

# PATH: personal scripts + CUDA
fish_add_path -g $HOME/.local/bin
if test -d /opt/cuda/bin
    fish_add_path -g /opt/cuda/bin
    set -gx CUDA_HOME /opt/cuda
end

# Tooling shortcuts
abbr -ag lg lazygit

# zoxide (smarter cd) — only if installed
if type -q zoxide
    zoxide init fish | source
end
EOF
}

do_wireplumber() {
    # The controller ships with ACP auto-profile/auto-port OFF, so plugging
    # earphones into its jack never moves audio off the internal speaker. Turn
    # them on so WirePlumber follows the jack. (Manual fallback: `dualsense-audio`.)
    dry "~/.config/wireplumber/wireplumber.conf.d/51-dualsense-headphones.conf" && return
    mkdir -p "$HOME/.config/wireplumber/wireplumber.conf.d"
    cat > "$HOME/.config/wireplumber/wireplumber.conf.d/51-dualsense-headphones.conf" <<'EOF'
monitor.alsa.rules = [
  {
    matches = [
      { device.name = "~alsa_card.usb-Sony.*DualSense.*" }
    ]
    actions = {
      update-props = {
        api.acp.auto-profile = true
        api.acp.auto-port    = true
      }
    }
  }
]
EOF
}

do_git() {
    dry "global git config (init.defaultBranch, push.autoSetupRemote, ...)" && return
    git config --global init.defaultBranch main
    git config --global push.autoSetupRemote true
    git config --global pull.rebase false
    git config --global fetch.prune true
    git config --global rerere.enabled true
    git config --global core.editor nvim
}

do_lerobot() {
    # LeRobot conda env, focused on real SO-arm 101 hardware (Feetech STS3215 servos).
    # The cmake fix below is the Arch-specific catch: Arch ships cmake 4.x which
    # removed compatibility with cmake_minimum_required < 3.5. Without the env var,
    # nested CMake builds inside pip wheels (egl-probe via robomimic, and a few
    # others) abort at "Compatibility with CMake < 3.5 has been removed". The fix is
    # written as a conda activate.d hook so EVERY subsequent 'pip install' in this
    # env inherits it — not just the first one.
    if ! command -v conda >/dev/null 2>&1; then
        say "    · conda not found. Install Anaconda first (install.sh anaconda) and re-run."
        return
    fi
    local env_name="${LEROBOT_ENV:-lerobot}"
    # Default extras: 'feetech' covers SO-arm 100/101 servo I/O. 'core_scripts'
    # is upstream's composite umbrella for the user-facing CLI tools
    # (lerobot-record, lerobot-replay, lerobot-calibrate, lerobot-teleoperate);
    # it expands to [dataset, hardware, viz], which together bring HF datasets +
    # pandas + pyarrow (via dataset; also pulls torchcodec + av so dataset video
    # recording works), pynput + pyserial + deepdiff for keyboard/serial control
    # (via hardware), and rerun-sdk for live visualization (via viz). Add
    # 'smolvla' for HF's small VLA policy. Deliberately NOT [all] — that drags
    # in hf-libero → robomimic → egl-probe (the cmake-4 hot zone) plus
    # simulators you don't need.
    local extras="${LEROBOT_EXTRAS:-feetech,core_scripts}"
    # LeRobot upstream now requires Python >= 3.12 (per its pyproject.toml).
    # Override with LEROBOT_PY if you need to pin to an older lerobot release.
    local py="${LEROBOT_PY:-3.12}"

    # Install source: prefer an editable install from a local clone (LEROBOT_DIR or
    # ~/lerobot) because the examples/, scripts/, and src/lerobot/scripts/ entry
    # points the HF docs reference for SO-arm 101 calibration/teleop/recording
    # only exist in the clone — not in the PyPI wheel. `git pull` keeps it current.
    #
    # Source-mode resolution (in order):
    #   1. $LEROBOT_DIR contains pyproject.toml         → editable, use as-is
    #   2. $LEROBOT_DIR exists but isn't a LeRobot tree → PyPI (refuse to overwrite)
    #   3. LEROBOT_NO_CLONE=1                           → PyPI (explicit opt-out)
    #   4. otherwise                                    → git clone HF/lerobot, then editable
    # If the clone step itself fails (no network, etc.) we fall back to PyPI silently.
    local clone="${LEROBOT_DIR:-$HOME/lerobot}"
    local repo_url="${LEROBOT_REPO:-https://github.com/huggingface/lerobot.git}"
    local mode pip_target need_clone=0
    if [ -f "$clone/pyproject.toml" ]; then
        mode="editable from existing clone at $clone"
    elif [ -e "$clone" ]; then
        say "    · WARNING: $clone exists but is not a LeRobot clone (no pyproject.toml)."
        say "      Refusing to touch it; falling back to PyPI install."
        mode="PyPI (refused to overwrite non-clone dir)"
    elif [ "${LEROBOT_NO_CLONE:-0}" = "1" ]; then
        mode="PyPI (LEROBOT_NO_CLONE=1)"
    else
        mode="editable from fresh clone at $clone"
        need_clone=1
    fi
    case "$mode" in
        editable*) pip_target="-e $clone[$extras]" ;;
        *)         pip_target="lerobot[$extras]"   ;;
    esac
    say "    · target: env=$env_name, python=$py, source=$mode"

    if [ "$DRY_RUN" -eq 1 ]; then
        say "    [dry-run] conda create -n $env_name python=$py"
        say "    [dry-run] write activate.d/cmake_policy.sh (CMAKE_POLICY_VERSION_MINIMUM=3.5)"
        [ "$need_clone" -eq 1 ] && say "    [dry-run] git clone $repo_url $clone"
        say "    [dry-run] pip install -U pip setuptools wheel"
        say "    [dry-run] pip install $pip_target"
        return
    fi

    # Clone now (before conda activate, so a clone failure doesn't waste the env).
    if [ "$need_clone" -eq 1 ]; then
        if ! command -v git >/dev/null 2>&1; then
            say "    · git not found — falling back to PyPI install."
            mode="PyPI (git missing)"
            pip_target="lerobot[$extras]"
        else
            say "    · cloning $repo_url → $clone …"
            if git clone "$repo_url" "$clone"; then
                say "    · clone OK."
            else
                say "    · git clone failed — falling back to PyPI install."
                mode="PyPI (clone failed)"
                pip_target="lerobot[$extras]"
                # In case partial files landed, drop them so a re-run can retry.
                [ -d "$clone" ] && rm -rf "$clone"
            fi
        fi
    fi

    # Source conda so 'conda activate' works inside this non-login bash.
    local conda_base; conda_base="$(conda info --base)"
    # shellcheck disable=SC1091
    . "$conda_base/etc/profile.d/conda.sh"

    if conda env list | awk '{print $1}' | grep -qx "$env_name"; then
        say "    · env '$env_name' already exists — reusing it"
    else
        say "    · creating env '$env_name' with Python $py …"
        conda create -y -n "$env_name" "python=$py"
    fi

    # Persist the cmake-policy fix as an activate hook (the Arch cmake-4 gotcha).
    local hookdir="$conda_base/envs/$env_name/etc/conda/activate.d"
    mkdir -p "$hookdir"
    cat > "$hookdir/cmake_policy.sh" <<'HOOK'
# Arch ships cmake 4.x which removed support for cmake_minimum_required < 3.5.
# This env var tells nested CMake invocations (from pip/setup.py builds) to
# accept the old minimum. Needed for egl-probe and similar legacy C++ wheels.
export CMAKE_POLICY_VERSION_MINIMUM=3.5
HOOK

    conda activate "$env_name"

    say "    · upgrading pip/setuptools/wheel inside '$env_name' …"
    python -m pip install --upgrade pip setuptools wheel

    say "    · installing $pip_target (heavy: PyTorch + native builds; minutes)…"
    # shellcheck disable=SC2086  # intentional word-splitting so -e + path are 2 args
    if ! pip install $pip_target; then
        conda deactivate
        say
        say "!!! pip install failed for $pip_target."
        say "    The conda env '$env_name' was created but does NOT contain a working"
        say "    LeRobot install. Common causes:"
        say "      - lerobot requires a newer Python than '$py' (check pyproject.toml in"
        say "        the clone; bump with LEROBOT_PY=<ver> ./setup-home.sh lerobot)"
        say "      - a transitive build dep needs a system package missing on this host"
        say "      - the cmake-4 policy env var didn't apply (rare; the activate hook is"
        say "        only sourced by 'conda activate', which this script just did)"
        say "    To rebuild from scratch, drop the env and re-run:"
        say "      LEROBOT_KEEP_CLONE=1 ./uninstall.sh lerobot   # keeps ~/lerobot"
        say "      ./setup-home.sh lerobot                       # try again"
        return 1
    fi

    conda deactivate

    say "    · done. Activate any time with:  conda activate $env_name"
    if [ -f "$clone/pyproject.toml" ]; then
        say "    · editable install — \`import lerobot\` points at $clone."
        say "      Track upstream: cd $clone && git pull   (no reinstall needed)."
    fi
    say
    say "    SO-arm 101 next steps (real hardware):"
    say "      1. Plug the Feetech controller (USB). Find its serial port:"
    say "           ls /dev/ttyACM* /dev/ttyUSB*"
    # Detect whether the user is already in 'uucp' (Arch's serial group). The
    # install.sh 'groups' component is the canonical place to add it (alongside
    # lock + wireshark); we just inform here, since setup-home.sh runs no sudo.
    if id -nG "$USER" 2>/dev/null | tr ' ' '\n' | grep -qx uucp; then
        say "      2. Serial-port permission: \xE2\x9C\x93 already in 'uucp' group — nothing to do."
    else
        say "      2. Serial-port permission: NOT in 'uucp' group. Add it (one of):"
        say "           ./install.sh groups            # canonical (adds uucp + lock + wireshark)"
        say "           sudo usermod -aG uucp \"\$USER\"  # uucp only"
        say "         Either way, log out and back in for the group to take effect."
    fi
    say "      3. Quick sanity-check inside the env:"
    say "           conda activate $env_name && python -c 'import lerobot; print(lerobot.__version__)'"
    say "         …or a thorough no-hardware verification of every component:"
    say "           lerobot-verify"
    say "      4. To add more extras later (e.g. smolvla policy):"
    if [ -f "$clone/pyproject.toml" ]; then
        say "           conda activate $env_name && pip install -e \"$clone[feetech,dataset,smolvla]\""
    else
        say "           conda activate $env_name && pip install 'lerobot[feetech,dataset,smolvla]'"
    fi
    say "         (the cmake-4 env var is already active via the activate hook)."

    # Run the no-hardware verification automatically so a fresh install ends
    # with a clear PASS/FAIL banner. Only runs if the helper exists — i.e. user
    # has run `setup-home.sh scripts` (or all) at least once.
    if [ -x "$HOME/.local/bin/lerobot-verify" ]; then
        say
        say "    Running no-hardware verification (lerobot-verify) …"
        LEROBOT_ENV="$env_name" "$HOME/.local/bin/lerobot-verify" || \
            say "    (verification reported failures — see markers above)"
    else
        say
        say "    (Tip: run \`./setup-home.sh scripts\` to install the lerobot-verify helper.)"
    fi
}

# ============================================================================
# Arg parsing + interactive menu (shared shape with install.sh)
# ============================================================================
SELECTED=()
ALL_NAMES=(); for row in "${COMPONENTS[@]}"; do ALL_NAMES+=("${row%%|*}"); done
is_component() { local n; for n in "${ALL_NAMES[@]}"; do [ "$n" = "$1" ] && return 0; done; return 1; }

for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        -y|--yes)  ASSUME_YES=1 ;;
        all)       SELECTED=("${ALL_NAMES[@]}") ;;
        -h|--help)
            say "usage: setup-home.sh [--dry-run] [--yes] [all | <component>...]"
            say "components: ${ALL_NAMES[*]}"; exit 0 ;;
        *)
            if is_component "$arg"; then SELECTED+=("$arg")
            else say "Unknown component '$arg'. Known: ${ALL_NAMES[*]}"; exit 1; fi ;;
    esac
done

if [ "${#SELECTED[@]}" -eq 0 ]; then
    hr; say "Interactive home setup — pick what to write."
    [ "$DRY_RUN" -eq 1 ] && say "(dry-run: nothing will actually be written)"
    hr
    i=1
    for row in "${COMPONENTS[@]}"; do say "  $i) ${row%%|*} — ${row#*|}"; i=$((i+1)); done
    say "  a) all of the above"
    say "  q) quit"
    hr
    read -rp "Enter numbers (space/comma separated), 'a', or 'q': " reply
    case "$reply" in
        q|Q|"") say "Nothing selected — exiting."; exit 0 ;;
        a|A)    SELECTED=("${ALL_NAMES[@]}") ;;
        *)
            reply=${reply//,/ }
            for tok in $reply; do
                if [[ "$tok" =~ ^[0-9]+$ ]] && [ "$tok" -ge 1 ] && [ "$tok" -le "${#ALL_NAMES[@]}" ]; then
                    SELECTED+=("${ALL_NAMES[$((tok-1))]}")
                else
                    say "  (ignoring invalid choice '$tok')"
                fi
            done ;;
    esac
fi

[ "${#SELECTED[@]}" -eq 0 ] && { say "Nothing selected — exiting."; exit 0; }
in_selected() { local s; for s in "${SELECTED[@]}"; do [ "$s" = "$1" ] && return 0; done; return 1; }

hr
say "Will set up: ${SELECTED[*]}"
[ "$DRY_RUN" -eq 1 ] && say "Mode: DRY-RUN (no changes)."
hr
if [ "$ASSUME_YES" -eq 0 ] && [ "$DRY_RUN" -eq 0 ]; then
    read -rp "Proceed? [y/N]: " ok
    case "$ok" in y|Y|yes|YES) ;; *) say "Aborted."; exit 0 ;; esac
fi

# Run selected components in canonical order.
for row in "${COMPONENTS[@]}"; do
    name="${row%%|*}"
    if in_selected "$name"; then hr; "do_${name}"; fi
done

# Apply live if we wrote Hyprland/scripts config inside a running session.
if [ "$DRY_RUN" -eq 0 ] && { in_selected hyprland || in_selected scripts; } \
   && command -v hyprctl >/dev/null && [ -n "${HYPRLAND_INSTANCE_SIGNATURE-}" ]; then
    [ -x "$BIN/select-monitors.sh" ] && "$BIN/select-monitors.sh" || true
    hyprctl reload >/dev/null 2>&1 || true
    say ">>> Hyprland reloaded."
fi

hr
[ "$DRY_RUN" -eq 1 ] && say "(dry-run: nothing was changed)"
cat <<EOF

Home setup complete.

Set your git identity (not done automatically):
    git config --global user.name  "Your Name"
    git config --global user.email "you@example.com"

Next: run the system half ->  bash $(dirname "$0")/install.sh
  (it installs git, the GitHub CLI, and an AUR helper up front, so afterward the
   only auth step left is:  gh auth login  &&  git push)
EOF
