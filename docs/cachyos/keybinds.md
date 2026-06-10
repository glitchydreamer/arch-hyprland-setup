# Keybinds (CachyOS)

The keybinds are **identical to the Arch build** — they're written into
`~/.config/caelestia/hypr-user.conf` by `setup-home.sh hyprland`, which is the same
generator (minus the DualSense bits). For the full annotated list — caelestia's
defaults plus the app launchers and panel toggles added here — see the
[Arch keybinds page](../arch/keybinds.md).

## The essentials

| Keys | Action |
|---|---|
| Tap **Super** | caelestia launcher (the "spotlight") |
| **Super + W / C / E / T** | browser / editor / file manager / terminal |
| **Super + Q** | close window · **Super + F** fullscreen |
| **Super + Shift + B/E/D/...** | extra app launchers (brave, edge, claude-desktop, …) |
| **Super + Shift + P** | mission-center (Task Manager) |
| **Super + Ctrl + Alt + H** | toggle HDR ↔ sRGB on the primary display |
| **Super + H** / **Super + Shift + H** | minimize / restore (scratchpad) |

## What's different from Arch

Nothing in the binds themselves. The only behavioural difference is upstream: this
is a **newer caelestia** layout where the base Hyprland config lives in
`~/.config/hypr/hyprland/*.conf` (e.g. `keybinds.conf`, `misc.conf`) rather than a
flat tree — but the **override mechanism is unchanged**: `hyprland.conf` still
sources `~/.config/caelestia/hypr-vars.conf` and `hypr-user.conf` last, so your
binds and overrides win without touching the upstream tree. See the
[caelestia golden rule](../common/caelestia-shell.md#the-golden-rule-never-edit-the-upstream-tree).

!!! note "Package name vs binary name"
    The launcher binds call the **binary**, which isn't always the package name
    (e.g. `microsoft-edge-stable`, `missioncenter`). Same gotcha as Arch — see the
    [package-name-vs-binary note](../arch/keybinds.md#package-name-vs-binary-name-gotcha).

## Adding your own keybinds

Same mechanism as Arch, byte-for-byte: drop your `bind` lines into
`~/.config/caelestia/hypr-user.conf` (sourced last, so they win) and run
`hyprctl reload`. Apps, system commands, workspaces, window actions — all one file.
Full how-to with the syntax, per-category examples, overriding caelestia defaults,
conflict-checking, and how to make a bind survive a fresh reinstall:
[Arch keybinds → Adding your own keybinds](../arch/keybinds.md#adding-your-own-keybinds).
