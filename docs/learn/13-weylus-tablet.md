# iPad / Android tablet as a drawing pad (Weylus)

[Weylus](https://github.com/H-M-H/Weylus) is the Linux equivalent of
SuperDisplay / spacedesk / Astropad: a small web-server you run on the
desktop, opened in a browser on a tablet or phone, that turns the mobile
device into a **graphics tablet** (with pen pressure on Apple Pencil and
S-Pen) or a plain **touchscreen** pointing into the live desktop. Great
for taking handwritten notes into Xournal++ / OneNote-via-browser /
Krita without buying a Wacom.

This repo installs the **community-maintained fork**, not the original
Weylus, for a reason explained below.

---

## The 30-second recipe

```bash
bash install.sh tablet          # ~2 MB binary + uinput plumbing
# log out + back in (the uinput group needs a fresh session)

weylus                          # opens the GUI on the desktop
# - set an "Access code"
# - leave the network defaults (port 1701)
# - press Start

# now on the tablet, on the SAME wifi as the desktop:
#   open  http://<desktop-ip>:1701  in Safari/Chrome/Firefox
#   enter the access code
#   tap "Window" and pick the app you want the tablet to control
```

That's it — your tablet is now a pen-pressure-aware graphics tablet for
the chosen window. Drag with one finger for the pen, two fingers to
scroll, pinch to zoom (if the target app supports it). To stop, close
the Weylus GUI on the desktop.

---

## Why the *Community Edition* fork, not upstream Weylus

Upstream `H-M-H/Weylus` froze in October 2022 at v0.11.4 and the author
is no longer responsive. The AUR `weylus` source build pulls
`syntex_pos 0.42.0` as a transitive dependency, which uses
`RustcEncodable` / `RustcDecodable` derive macros — those were removed
from rustc years ago. Result: every `paru -S weylus` ends in

```
error: cannot find derive macro `RustcEncodable` in this scope
   --> .../syntex_pos-0.42.0/src/lib.rs
```

and an aborted build. The pinned `weylus-bin` is even older (a 2021
binary) and similarly stale.

**[`electronstudio/WeylusCommunityEdition`](https://github.com/electronstudio/WeylusCommunityEdition)**
is the community fork that's actively maintained — fresh release in
2026, Wayland portal support, updated GStreamer pipeline. The AUR
package `weylus-community-bin` ships its prebuilt Linux tarball, so we
sidestep the Rust build path entirely. `install.sh tablet` uses that
package; it `conflicts` with the legacy variants so the AUR helper does
the swap cleanly if you already had one.

---

## The uinput plumbing — what the installer actually wires up

For Weylus to move the cursor and synthesize pen / keyboard events, it
writes to the kernel's `/dev/uinput` device. That node is root-only by
default. Three pieces fix it:

1. **`/etc/udev/rules.d/60-weylus-uinput.rules`** —
   ```
   KERNEL=="uinput", GROUP="uinput", MODE="0660", OPTIONS+="static_node=uinput"
   ```
   The `static_node=uinput` part is subtle: it tells systemd-udev to
   create the device node up front (before the kernel module is loaded
   on demand) so that Weylus doesn't race against a lazy modprobe.
2. **`/etc/modules-load.d/uinput.conf`** — one line `uinput`, autoloads
   the module at boot.
3. **`usermod -aG uinput $USER`** — your user joins the new group.

The last step is **the one that needs a logout/login** — group changes
only show up in newly-spawned login sessions. Verify with
`groups | tr ' ' '\n' | grep uinput`. If Weylus complains about
permission denied on `/dev/uinput`, that's almost always what it is.

`bash uninstall.sh tablet` reverses all three pieces (and removes the
group if it ends up empty), so re-running `install.sh tablet` later
starts from a clean slate.

---

## Wayland vs X11 capture

Weylus has to capture the desktop image and stream it to the tablet
browser. On Wayland (Hyprland here) it goes through the
**xdg-desktop-portal screencast** interface, which is what
`xdg-desktop-portal-hyprland` (already part of caelestia) implements.
That portal hands GStreamer a PipeWire stream — which Weylus can only
decode if **`gst-plugin-pipewire`** is installed. The `tablet`
component installs it explicitly so you don't have to remember.

What this looks like in practice on first run:

1. You press Start in the Weylus GUI.
2. A KDE/GTK desktop-portal dialog pops up: "Weylus wants to share your
   screen — pick a window or the full desktop". Click the target.
3. The tablet browser starts receiving frames.

If you don't see the portal dialog, or the tablet shows a black
rectangle, the chain is almost always one of:

- `gst-plugin-pipewire` not installed → `pacman -Q gst-plugin-pipewire`
- portal not running →
  `systemctl --user status xdg-desktop-portal-hyprland`
- you picked "X11" capture in the Weylus GUI on a Wayland session →
  switch it to PipeWire in **Capturable inputs**.

On X11 Weylus has its own native capture (`xcomposite`) and the portal
path isn't used. Hyprland is Wayland, so the portal path is the one
you'll be on here.

---

## Pen pressure — what works where

| Tablet OS | Browser | Pressure? | Notes |
|---|---|---|---|
| iPadOS 13+ | Safari | ✅ | Apple Pencil; Pointer Events API exposes `pressure` |
| iPadOS | Chrome | ✅ | Same backend as Safari (WebKit), same result |
| Android | Chrome 80+ | ✅ | S-Pen, Wacom Bamboo styli — works for anything reporting `azimuth/tiltX/Y/pressure` |
| Android | Firefox | ⚠️ | Pressure can be flaky on older Firefox; try Chrome first |
| Any | Touch-only | n/a | Pure capacitive touch = a clicky pointer; no pressure |

The pressure value the desktop app sees depends on whether the app
itself reads `PRESSURE` from the synthesized X11/uinput tablet
events. **Krita**, **Xournal++**, **Inkscape**, and **Pinta** all do;
**OneNote in the browser** does not — there's no canvas-side API to
forward to. That's a limitation of the target app, not of Weylus.

---

## Latency tuning

The defaults stream H.264 at the desktop's native resolution. For
sketching that's fine on a fast LAN (≤30 ms). If you see lag:

- **In the Weylus GUI**: drop "FPS limit" to 30 (saves bandwidth, no
  visible loss for drawing).
- **In the tablet browser settings (gear icon)**: lower the resolution
  to 1280×720. The decoded latency on iPadOS Safari is the main bottleneck.
- **Hardware codec**: the community fork honours `VAAPI` / `NVENC` if
  the host has it. Set `Video codec → h264_nvenc` if you've got an
  NVIDIA card (we do — this box runs the 580 driver with NVENC).
- **Avoid wifi double-NAT**: tablet hotspot + desktop wifi through the
  same router is fine; mobile hotspot from the phone to both is not.

---

## Ports + firewall

Weylus listens on:

- **TCP 1701** — the HTTP server (the page you open on the tablet).
- **TCP 9001** — the WebSocket the tablet uses for input + video frames.

Default Arch has no firewall; if you've added `ufw` or `firewalld`
later (we haven't — see `install.sh remote` for the SSH-side
philosophy), allow both ports for **the LAN interface only**. Don't
expose them to the public internet; the access code is the only auth.

---

## Reverting

```bash
bash uninstall.sh tablet
```

Removes the package, the udev rule, the modules-load file, drops you
from the `uinput` group, removes the group if it ends up empty, and
clears `~/.local/share/weylus` (access-code / certificate state). Keeps
`gst-plugin-pipewire` (shared with audio + screen recording).

If you want to switch to the legacy upstream Weylus for some reason
(downside: it doesn't compile from source, and `weylus-bin` is 5 years
stale), uninstall first then `paru -S weylus-bin` — but you almost
certainly don't want this.
