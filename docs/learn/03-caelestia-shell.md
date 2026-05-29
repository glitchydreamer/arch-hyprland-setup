# The caelestia shell

**Goal of this page:** understand what a "desktop shell" is, what caelestia adds
on top of Hyprland, and — most importantly — the **config override model** that
keeps your customisations from being destroyed on updates. This last part is the
single most important practical rule on the whole machine.

## Window manager vs desktop shell

[Hyprland](02-wayland-and-hyprland.md) arranges windows, but it draws almost no
*furniture* — no taskbar, no clock, no app menu, no notification popups. A bare
Hyprland session is just your apps tiled on a wallpaper.

A **desktop shell** provides that furniture. On GNOME/KDE the shell and the
window manager ship together as one product. In the Wayland tiling world they're
separate, swappable pieces — and here the shell is **caelestia**.

caelestia is built on **Quickshell**, a toolkit for building desktop shells in
QML (a declarative UI language). caelestia provides:

- a vertical **bar** (left edge) — workspaces, clock, status,
- an app **launcher** (fuzzy search, <span class="keys">Super</span>+<span class="keys">Space</span>),
- **notifications**, a **control center** panel, wallpaper management, a color
  scheme manager, and a lock screen.

```mermaid
flowchart TD
    H[Hyprland<br/>tiles windows, reads keybinds] --> C[caelestia / Quickshell<br/>draws bar, launcher, panels]
    C --> V[What you see:<br/>furniture + your tiled apps]
```

So: **Hyprland is the engine; caelestia is the dashboard.** You could remove
caelestia and Hyprland would still tile windows — you'd just have no bar.

## The golden rule: never edit the upstream tree

Here's the critical part. caelestia installs its own config into a package tree:

```
~/.local/share/caelestia/        ← caelestia's files (UPSTREAM — do not edit)
~/.config/hypr  ──symlink──▶  ~/.local/share/caelestia/hypr
```

Notice `~/.config/hypr` — the place Hyprland normally reads its config — is a
**symlink** (a pointer) into caelestia's package tree. That means:

!!! danger "The golden rule"
    **Never edit anything under `~/.local/share/caelestia/`.** When caelestia
    updates, that whole tree is overwritten — your changes would vanish. This is
    the #1 way newcomers lose work on a setup like this.

So how do you customise anything? Through an **override layer**.

## How the override model works

caelestia is designed to *source* (read in) your personal files **last**, after
its own defaults. Because Hyprland applies config top-to-bottom and "last write
wins," anything in your override file beats the default.

Your overrides live in a user-owned directory that caelestia never overwrites:

```
~/.config/caelestia/
├── hypr-vars.conf      # variable overrides (e.g. $browser = firefox)
├── hypr-user.conf      # everything else — sourced LAST, so it always wins
├── hypr-monitors*.conf # per-machine monitor config (see Displays page)
└── shell.json          # the SHELL's settings (bar, dashboard, weather, ...)
```

The `*.conf` files all configure **Hyprland** (the window manager). The shell
itself — the bar, the dashboard, the weather panel — is a separate program
(Quickshell) that reads its own settings from **`shell.json`**, covered next.

The load order is what makes it work:

```mermaid
flowchart LR
    A["caelestia variables.conf"] --> B["YOUR hypr-vars.conf<br/>(override variables)"]
    B --> C["caelestia keybinds.conf<br/>(uses the variables)"]
    C --> D["YOUR hypr-user.conf<br/>(sourced LAST — wins)"]
```

Two override techniques you'll see:

1. **Override a variable.** caelestia binds <span class="keys">Super</span>+W to
   "launch `$browser`". Your `hypr-vars.conf` sets `$browser = firefox` *before*
   the bind is defined, so the existing bind silently picks up your value — no
   rebinding needed.

2. **`unbind` then `bind`.** To change a key caelestia already defined (e.g.
   <span class="keys">Super</span>+G pointed at an app you don't have), your
   `hypr-user.conf` does `unbind = Super, G` then `bind = Super, G, exec, ...`.
   Because it's sourced last, your version is the final word.

This is why the [keybinds reference](../keybinds.md) keeps stressing *which file*
a bind lives in — it determines whether you override a variable or rebind a key.

## The shell's own settings: `shell.json`

The `hypr-*.conf` files tune the *window manager*. The **shell** (the bar,
dashboard, notifications, and the **weather panel**) is a Quickshell program with
a completely separate config: **`~/.config/caelestia/shell.json`**, plain JSON.
You set a key and the shell hot-reloads — no logout, no `hyprctl reload`.

The settings are grouped (`appearance`, `bar`, `background`, `services`, …). One
worth knowing: the dashboard's weather panel **defaults to Fahrenheit**. To show
**Celsius**, set `services.useFahrenheit` to `false`:

```json
{
    "services": {
        "useFahrenheit": false
    }
}
```

You don't normally edit this by hand — the **`caelestia` component** of
`setup-home.sh` merges the setting in for you (it deep-merges, so your other
`shell.json` keys are preserved):

```bash
bash setup-home.sh caelestia
```

!!! tip "Discovering shell.json keys"
    The full list of settings (and their JSON paths) lives in caelestia's type
    definitions at `/usr/lib/qt6/qml/Caelestia/Config/caelestia-config.qmltypes`.
    Each config group (`ServiceConfig`, `BarConfig`, …) maps to a top-level key in
    `shell.json`. That's how `useFahrenheit` — a property of `ServiceConfig` — is
    reached as `services.useFahrenheit`.

## Theming GTK apps (and the libadwaita catch)

You'll eventually want to restyle a GTK app — say give **nautilus** (the GNOME
file manager) a different look. Two separate things are involved, and they behave
very differently:

- **Icons** are easy and global. The GTK *icon theme* is one system-wide setting
  (`gsettings set org.gnome.desktop.interface icon-theme <name>`, mirrored into
  `~/.config/gtk-{3,4}.0/settings.ini`). Install an icon set (e.g. the rainbow
  **candy-icons** from the AUR) and point that setting at it — nautilus and every
  other **GTK** app pick it up. KDE/Qt apps (Dolphin, System Settings) have their
  *own* icon setting, and caelestia's bar is QML, so neither is affected. On this
  machine that's the `theme` component of `install.sh` (installs the icons) plus
  the `nautilus` component of `setup-home.sh` (sets them).

- **Window colours are the hard part — because of libadwaita.** Modern GNOME apps
  (nautilus included) are built with **libadwaita**, which deliberately *ignores*
  the system GTK theme **and** the `GTK_THEME` environment variable. It takes its
  colours from exactly one place: the `@define-color` rules in
  **`~/.config/gtk-4.0/gtk.css`**. On this system **caelestia writes that file**
  from its active colour scheme — so all libadwaita apps already match your
  desktop palette.

!!! warning "Why you can't theme one libadwaita app on its own"
    Because libadwaita reads colours from that single global `gtk-4.0/gtk.css`,
    there's no reliable way to give *only* nautilus a different theme. You can
    recolour **all** libadwaita apps by overwriting that palette — but it's global,
    and caelestia may rewrite the file when its scheme changes. The `GTK_THEME`
    env-var trick (and per-app `.desktop` overrides) work for plain GTK3/GTK4 apps
    but **not** for libadwaita ones. So the practical answer for "theme nautilus"
    is: change its **icons** (works), and leave window colours to caelestia.

## Who writes these override files?

You could write them by hand, but on this machine they're generated by the
**`setup-home.sh`** script — it *is* the source of truth for your overrides,
your `~/.local/bin` helper scripts, fish config, and more. The workflow is: edit
the script, re-run it, and it rewrites the files. That keeps the configuration
**reproducible** rather than a pile of hand-edits no one remembers. See
[Reproducibility](08-reproducibility.md).

!!! tip "Caelestia auto-reloads"
    Save an override file and caelestia's config-watcher reloads Hyprland for
    you (or run `hyprctl reload`). No logout needed for most config changes.

## Want a more conventional desktop?

A common beginner wish is a **horizontal taskbar at the bottom** like Windows.
caelestia's bar is architecturally *vertical* and has no "move to bottom" knob —
making it horizontal means forking its QML. The pragmatic path is to swap in
**waybar** (a standalone bar that does horizontal placement, pinned apps,
right-click menus) and keep the rest of caelestia. The
[Coming from Ubuntu](../coming-from-ubuntu.md) guide covers this and other
"where did my Ubuntu feature go" questions in detail.

---

**Next:** [Displays: resolution, refresh, HDR →](04-displays.md) — the theory of
getting a great picture out of your monitor.
