# System maintenance & upgrades — the "rolling release" survival guide

**Goal of this page:** kill the scariest Arch myth ("upgrade and it breaks, don't
upgrade and it *also* breaks") and replace it with a calm, repeatable routine. By
the end you'll know exactly what `pacman -Syu` does to your machine, why the
**pinned** packages on this system (NVIDIA 580, PipeWire 1.6.5) survive every
upgrade untouched, and what the *real* long-term risk of pinning is. This builds on
[Arch Linux & pacman](01-arch-and-pacman.md) and the
[package-management cheat-sheet](10-package-management.md).

## The paradox — and why it's false

The fear goes like this:

> *"If I upgrade, it'll update my pinned drivers/kernel/audio and break Isaac Sim
> and my controller. If I **don't** upgrade for 6 months and then do, the giant
> jump breaks everything. I'm damned either way."*

The hidden assumption is that **upgrading is the dangerous act**. It isn't. On a
rolling-release distro the danger is almost entirely about *how often* and *how
completely* you upgrade:

| Habit | What happens | Risk |
|---|---|---|
| **Frequent, full** `-Syu` (weekly-ish) | a *small* set of packages moves each time | **Low** — one thing breaks at most, today, and everyone else hit it today too |
| **Rare, full** `-Syu` (every few months) | *hundreds* of packages move at once; core libraries bump their soname; the keyring may have expired | **High** — many breakages cascade simultaneously |
| **Partial** `-Sy <pkg>` (update one thing, not the rest) | you pull a new package against *old* libraries | **Highest** — the classic "I broke my Arch" |

So the resolution is the opposite of the instinct: **upgrade *often*. Frequency is
the safety mechanism, not the threat.** Skipping updates to "stay safe" is what
quietly accumulates the breakage you're afraid of.

## What `pacman -Syu` actually does

Arch is **rolling release**: there is no "Arch 22.04 → 24.04" jump. There's just one
ever-moving stream, and `-Syu` snaps your machine to the current point in it.

```bash
sudo pacman -Syu      # -S sync, -y refresh package lists, -u upgrade everything
```

The thing that breaks long-delayed upgrades is the **soname bump**. Shared
libraries carry a version in their filename (`libfoo.so.2` → `libfoo.so.3`). When a
core library like `glibc`, `icu`, or `openssl` bumps, *everything compiled against
the old version must be rebuilt or replaced*. In a full repo upgrade pacman replaces
them all together, atomically — fine. The danger is anything that *wasn't* in the
transaction: locally-built **AUR** packages and **DKMS** kernel modules (like your
NVIDIA driver) that were compiled against the old library and now find it gone.

Frequent upgrades keep each soname jump small and isolated. A 6-month upgrade stacks
dozens of them into one transaction.

!!! danger "The cardinal sin: the partial upgrade"
    **Never** run `sudo pacman -Sy <something>` on its own. The `-y` refreshes the
    *list* of available packages, and installing one new package against your still-old
    system pulls it (and *its* fresh dependencies) into an otherwise-stale install — an
    instant library mismatch. The rule is absolute: **always `-Syu`, never `-Sy`.**
    If you only wanted to *install* a package, plain `sudo pacman -S <pkg>` (no `-y`)
    is safe; pair a refresh with a full upgrade or not at all.

## What's pinned on *this* machine

This system deliberately freezes two stacks, via `IgnorePkg` lines in
`/etc/pacman.conf`:

```ini
IgnorePkg = nvidia-open-dkms nvidia-utils lib32-nvidia-utils opencl-nvidia nvidia-settings
IgnorePkg = libpipewire pipewire pipewire-audio pipewire-alsa pipewire-pulse pipewire-jack gst-plugin-pipewire alsa-card-profiles
```

| Pinned stack | Held at | Why | Details |
|---|---|---|---|
| **NVIDIA driver** | `580.119.02` | newer drivers (595+) segfault Isaac Sim's RTX renderer | [NVIDIA on Linux](05-nvidia.md) |
| **PipeWire audio** | `1.6.5` | `1.6.6` broke the DualSense controller speaker | [Audio on Linux](06-audio.md) |

And the kernel picture:

```text
linux       7.0.11   (mainline — installed, kept as a fallback)
linux-lts   6.18.34  (LTS — what you actually boot)
```

You boot **linux-lts** because the LTS series moves slowly, which keeps the pinned
580 driver buildable for far longer (more on that below). Each kernel needs its
matching headers (`linux-headers`, `linux-lts-headers`) for the NVIDIA DKMS module to
build — `install.sh` keeps those in sync for you automatically (see *Letting the
scripts do it for you*, below).

## How `IgnorePkg` interacts with upgrades — your pins are safe

This is the part that dissolves the original fear. `IgnorePkg` is **persistent and
automatic**:

- Every `sudo pacman -Syu` upgrades everything **except** the listed packages. NVIDIA
  stays at 580.119.02 and PipeWire stays at 1.6.5 *on every single upgrade*, with no
  action from you, until **you** delete the line. You'll see pacman print
  `warning: nvidia-utils: ignoring package upgrade (580.119.02-1 => …)` — that's the
  pin working, not an error.
- **pacman will not silently build a broken system.** If some package you're upgrading
  ever *hard-requires* a newer PipeWire than 1.6.5, pacman **refuses the whole
  transaction** and prints a dependency conflict, leaving your system untouched and the
  decision to you. The pin can stall an upgrade, but it can't quietly corrupt one.

So a routine weekly `-Syu` will *not* touch your drivers or audio. The scenario you
were worried about — "the upgrade updates the driver and breaks Isaac" — simply can't
happen while the `IgnorePkg` line is there.

## The real risk of *permanent* pinning (worth understanding)

Pinning isn't "set and forget forever." Two slow-moving issues to keep an eye on:

1. **NVIDIA 580 (DKMS) vs. a moving kernel.** Your driver is not a fixed binary — it's
   a **DKMS** module that *recompiles itself against the kernel's source headers*
   every time a kernel updates. Two distinct things can go wrong here, and it's worth
   keeping them separate:
   - **Missing headers (the common, fully-fixable one).** DKMS can only build if the
     kernel's matching `-headers` package is installed (`linux` needs `linux-headers`,
     `linux-lts` needs `linux-lts-headers`). If a kernel is installed *without* its
     headers, the build is skipped, `mkinitcpio` bakes a **module-less** boot image,
     and that kernel boots with no GPU driver. This is exactly what bit the mainline
     `linux` kernel on this box. **`install.sh` now prevents and repairs this
     automatically** — see the next section.
   - **Driver too old for the kernel API (the slow, real limit).** Eventually a kernel
     series bumps an internal API that 580 can no longer compile against *even with
     headers present* → `Error! Bad return status for module build on kernel …`. That's
     your cue to *also* hold the kernel (add it to `IgnorePkg`), move the driver with
     `nvidia-switch.sh latest`, or simply boot the kernel that still builds. The
     self-heal below detects this and prints those exact options instead of leaving a
     silent landmine.
   - This is exactly *why* you boot LTS: its slow cadence buys 580 a long, stable life.

2. **PipeWire 1.6.5** is lower-risk — it's userspace and fairly self-contained. The
   worst case is the dependency-conflict above: some future app demands a newer
   PipeWire, pacman refuses to upgrade *that app*, and you choose between unpinning
   PipeWire or skipping the app.

!!! note "Pins are temporary holds, not monuments"
    Each pin exists to wait out a specific upstream bug. When Isaac Sim supports a
    newer driver, or a PipeWire ≥ 1.6.6 fixes the DualSense regression, you delete the
    relevant `IgnorePkg` line and let that stack catch up in one controlled step. Pinning
    is "pause until it's safe," not "freeze forever."

## Your safety nets (you can always get back)

Even a bad upgrade is recoverable on this machine:

- **A second kernel as a *console* fallback.** A second installed kernel (`linux`,
  mainline) lets you boot *something* from the Limine menu if an LTS update won't
  boot. **Caveat that bites on this box:** while the NVIDIA driver is pinned at **580**,
  mainline `linux` (now 7.0) is **too new for 580 to compile against**, so that kernel
  boots to a TTY with **no GPU driver** — fine for command-line repair, but Hyprland
  won't start there. So the mainline kernel is an *emergency console*, not a graphical
  fallback. If you don't want it (it also fails its DKMS build noisily on every
  upgrade), removing it is clean and supported — `linux-lts` is the only kernel inside
  580's support window anyway:
  ```bash
  sudo pacman -Rns linux linux-headers   # keep only linux-lts (the 580/Isaac kernel)
  ```
  The package cache + `downgrade` + Limine UKIs (below) are the real recovery path for a
  single-kernel system.
- **The package cache is a time machine.** Every `.pkg.tar.zst` you've ever installed
  sits in `/var/cache/pacman/pkg/`. To roll a single package back to a cached version,
  the `downgrade` tool (AUR) makes it a one-liner. (Don't `pacman -Scc` away the *whole*
  cache if you might need to revert — `sudo paccache -r` keeps the last 3 instead.)
- **The keyring.** If you *do* leave it months and signatures start failing, the fix is
  `sudo pacman -Sy archlinux-keyring` first, *then* the full `-Su`. Updating regularly
  avoids this entirely.

## Letting the scripts do it for you — the self-heal + `install.sh health`

The "watch the DKMS line and react" ritual is good to *understand*, but you don't
have to do it by hand. `install.sh` is built to be **rolling-release self-healing**:
every time you run it (for *any* component), the mandatory prereq step does a
**full upgrade with every installed kernel's headers folded into the same
transaction**, then rebuilds DKMS modules and regenerates the boot images. Concretely:

1. **Keyring first.** It pulls `archlinux-keyring` at the front of the upgrade, so a
   long gap between updates can't fail the whole thing on an expired signing key.
2. **Headers in lockstep.** It detects each installed kernel (`linux`, `linux-lts`, …)
   and adds its `-headers` to the `-Syu`. So when a kernel rolls forward, its headers
   roll with it and DKMS builds against the right version *in the same transaction* —
   the "new kernel, no GPU driver" trap can't form. (It only adds headers that are
   real repo packages, so a custom/AUR kernel never aborts the upgrade.)
3. **Post-upgrade self-heal.** It runs `dkms autoinstall` for every kernel that has
   headers and, if anything new was built, regenerates the initramfs/UKI with
   `mkinitcpio -P`. Then it **verifies** every kernel actually has its module and, if
   one genuinely can't be built (driver-too-old case), prints the concrete options
   rather than failing silently.

Because all of that lives in the always-run prereqs, **re-running `install.sh`
repairs a botched upgrade** — including the exact state this box was left in (mainline
`linux` updated without `linux-headers`): the next run installs the headers, rebuilds
NVIDIA for that kernel, and regenerates its UKI.

For a one-shot doctor with no app install:

```bash
bash install.sh health
```

`health` does the same kernel/headers/DKMS repair, then prints a read-only report:
a kernel ↔ headers ↔ DKMS matrix, orphaned packages, failed systemd units, pending
`.pacnew` config merges, and the active `IgnorePkg` pins (so you remember what's held
on purpose). It changes nothing except the auto-repair; the report half is pure
inspection.

!!! tip "You can still do it by hand"
    Nothing about the scripts stops you running `sudo pacman -Syu` yourself — the
    self-heal just makes the script path safe to lean on. If you upgrade manually and
    later see a kernel/driver oddity, `bash install.sh health` is the quickest "fix
    what you can, tell me what you can't" button.

## The update ritual

A safe, boring routine — do this weekly-ish (or just run `bash install.sh health`,
which automates steps 2–3 and 6):

1. **Read the news first.** Glance at the [archlinux.org](https://archlinux.org) front
   page for "manual intervention required" notices — the rare breaking changes are
   *always* announced there before they land. (Optional: install `informant`, which
   blocks `-Syu` until you've read unread news.)
2. **Full upgrade, never partial:** `sudo pacman -Syu`.
3. **Watch the DKMS output** for the NVIDIA module rebuild. A successful build prints
   `done.`; a failure is loud (see risk #1 above).
4. **Note pinned-package warnings** — `ignoring package upgrade` lines are expected and
   healthy; they confirm 580 / 1.6.5 stayed put.
5. **Reboot if the kernel or driver moved** (so the running kernel matches the installed
   modules). For everyday app updates, no reboot needed.
6. **Occasionally sweep up:** `pacman -Qdtq | sudo pacman -Rns -` for orphans and
   `sudo paccache -r` to trim the cache (see
   [package management](10-package-management.md)).

!!! tip "Don't fear the rolling release — befriend it"
    The mental shift from Ubuntu is this: there's no "big scary version upgrade" to dread
    once every two years. There's just a small, routine top-up you do often. Do it
    weekly, skim the news, watch the DKMS line, and Arch is *more* stable than a distro
    you upgrade in terrifying once-a-cycle leaps.

---

**Where to go next:** the [NVIDIA](05-nvidia.md) and [Audio](06-audio.md) pages explain
*why* each pin exists and how `nvidia-switch.sh` swaps the driver stack safely; the
[package-management cheat-sheet](10-package-management.md) has the day-to-day
query/remove/clean commands; and the [troubleshooting mindset](09-troubleshooting-mindset.md)
page is your guide for the day something *does* go sideways. Unsure of a term? The
[Glossary](glossary.md) has you covered.
