# fastfetch with a custom image / GIF / video

caelestia ships [fastfetch](https://github.com/fastfetch-cli/fastfetch)
(`fastfetch-git` from the AUR) and a stock config that draws the OS ASCII
logo. This page explains how to swap that for a real bitmap of any image —
or even a still frame from an animated GIF or a video — via the
**`fastfetch-logo`** helper this repo's `setup-home.sh` installs.

The helper hides a surprising amount of complexity: terminal image protocols
(sixel vs chafa block-art vs kitty), the chafa-vs-foot cell-size mismatch,
and a real foot bug that nukes sixel pixels whenever later text shares a row
with them. None of that needs to be in your head day-to-day — but knowing
why the helper picks the defaults it does makes it obvious how to tune it.

---

## The 30-second recipe

```bash
# one-time, on a fresh machine
bash install.sh terminal media      # installs chafa + ffmpeg
bash setup-home.sh scripts          # writes ~/.local/bin/fastfetch-logo

# any time you want to change the logo
fastfetch-logo ~/Pictures/Wallpapers/whatever.jpg
fastfetch-logo --animate ~/Videos/loop.mp4    # gif/video, animated on shell start
fastfetch-logo --none                          # revert to OS ASCII
```

The interactive flow lives in `setup-home.sh fastfetch` — it prompts for a
path, asks "animate?" for GIF/video, and forwards to the helper. Re-runnable
any time.

---

## What `fastfetch-logo` actually does

1. **Detects the file type** from MIME (`file -b --mime-type`) and falls back
   to the extension. Three categories: still image, animated GIF, video.
2. **For GIF / video**: runs `ffmpeg -ss T -vframes 1` to extract a single
   frame (default T = 1 s; override with `--frame`). Treats the extracted
   PNG as a still image.
3. **Pre-renders to sixel via chafa**: `chafa --format=sixel --size=WxH
   --animate=off SRC > ~/.config/fastfetch/logo.sixel`. Default size is
   `70x18`, override with `--size`.
4. **Rewrites `~/.config/fastfetch/config.jsonc`** (with `jq`, preserving
   the rest of the config) to point at the sixel file:
   ```jsonc
   "logo": {
     "source": "~/.config/fastfetch/logo.sixel",
     "type": "raw",
     "position": "top",
     "width": 84, "height": 22,
     "padding": { "top": 1, "left": 2, "right": 4 }
   }
   ```

`type: raw` tells fastfetch to dump the file's bytes verbatim — no
re-encoding via fastfetch's imagemagick coder (which we tried, and which
silently crops images on the way through). The bytes are valid sixel; foot
renders them natively.

For **`--animate`**, the helper takes a different branch: it copies the
GIF/video into `~/.config/fastfetch/animated.<ext>`, clears the fastfetch
logo to `null`, and wires this line into `fish_greeting.fish` just before
the existing `fastfetch` call:

```fish
    # fastfetch-logo: animated playback
    chafa --animate=on --duration=3 --format=sixel --size=70x18 '~/.config/fastfetch/animated.mp4'
```

So every new shell plays the clip for 3 s (override with `--duration N`),
then fastfetch runs underneath. `--none` strips both the marker line and
the chafa line.

---

## Why `position: top` is the default — the foot row-clear bug

The most painful part of building this helper was discovering that foot
**wipes sixel pixels on any cell-row where it later draws text**, even
when the text is in a different column from the image.

What we saw: with `position: left` (the fastfetch default — logo on the
left, modules on the right, in parallel rows), only the **bottom 3 rows of
the image survived** — exactly the rows below where the modules box ended.
Foot wasn't clipping by cell or pixel; it was clearing entire cell-rows of
sixel when subsequent text touched those rows.

The fix is to ensure no text is printed on the rows the sixel occupies:
- `position: top` puts the logo above the modules. Modules never share rows
  with the image, so foot never clears the pixels.
- `position: left` works fine in kitty and ghostty — their image protocols
  don't have the same behavior.

So the helper defaults to `top`. You can pass `--position left` if you're
on a kitty-protocol terminal.

---

## Sizing — chafa cells vs foot cells

`chafa --size=WxH` is in chafa "characters" — chafa internally assumes a
~10×20 px cell. Foot at JetBrains Mono 12pt with `dpi-aware=no` uses
roughly **8×17 px** per cell. So the actual on-screen footprint is:

| `--size` | chafa pixel output | in foot (8×17 px cells) |
|---|---|---|
| 50×12 | 430×240 | ≈ 54×14 cells |
| 60×16 | 570×320 | ≈ 71×19 cells |
| 70×18 | 640×360 | ≈ 80×21 cells |
| 80×22 | 790×440 | ≈ 99×26 cells |
| 100×28 | 1000×560 | ≈ 125×33 cells |

The aspect comes out right in every row (1.78:1 — matches a 16:9 source),
because chafa preserves aspect by default. What changes is how many rows
of foot the rendered image consumes. The helper multiplies the JSON
`width`/`height` by ~1.2× to reserve that bigger footprint.

**Tuning heuristic**: bigger `--size` = sharper image, but at some point
the image overflows the viewport vertically. With the Caelestia banner
(5 rows) above and the modules (11 rows) below, you want the image to fit
in roughly `terminal_rows - 16` rows of foot, i.e. `--size H` where the
"in foot" height column above stays under that budget. On a maximised
foot at this font, ~22 rows is the sweet spot.

---

## Why not sixel directly from fastfetch?

Tried it. fastfetch's built-in `type: sixel` uses imagemagick (the only
image library it links) for sixel encoding, and **imagemagick's sixel coder
crop-fills the image** instead of preserving aspect — slicing roughly the
top half of a 16:9 source off when targeting a ~1.5:1 cell area. There's
no JSON knob to switch it to preserve-aspect.

chafa's CLI **does** preserve aspect, and writes plain sixel bytes that
fastfetch can dump via `type: raw`. So the architecture is:

```
chafa --format=sixel --size=…  →  ~/.config/fastfetch/logo.sixel
                                            ↓
                                fastfetch (type: raw)  →  foot
```

This bypasses fastfetch's imagemagick path entirely.

---

## Why not chafa block-art (`type: chafa`)?

Two reasons:

1. **Pixelated.** chafa block-art renders each cell as a Unicode block
   character with a colour — at best it looks like a low-res mosaic. Sixel
   draws real pixels.
2. **`chafa` the binary isn't a runtime dep of fastfetch.** fastfetch dlopens
   `libchafa.so` if present, and silently falls back to ASCII if not — which
   bit us early on (`fastfetch --list-features` listed `chafa`, but the
   `chafa` package wasn't installed, so the dlopen failed silently and we
   got the Arch logo). On a clean rebuild this lives in `install.sh
   terminal` so the trap doesn't reset.

---

## Other terminals

| Terminal | Sixel | Kitty protocol | Recommended `--position` |
|---|---|---|---|
| foot | ✅ native | ❌ | `top` (avoid row-clear bug) |
| kitty | ✅ | ✅ | `left` |
| ghostty | ✅ | ✅ | `left` |
| Konsole | ✅ | ✅ | `left` |
| Alacritty | ❌ | ❌ | use `--type chafa` (block-art) |
| vscode terminal | ❌ | ❌ | fastfetch falls back to ASCII |

The helper always renders sixel — if you spend most of your time in a
sixel-capable terminal it just works. In Alacritty or vscode you'll see
the OS ASCII fallback (fastfetch refuses image logos in pipe mode and
on terminals without graphics support).

---

## Reverting

```bash
fastfetch-logo --none         # config.jsonc, sixel file, animation hook — all gone
```

Or via the uninstaller component:

```bash
bash uninstall.sh fastfetch   # same effect; keeps the helper binary itself
```

`chafa` and `ffmpeg` stay (cheap, useful for other things). The helper
binary stays so you can re-set a logo without re-running `setup-home.sh
scripts`.
