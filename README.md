# quickScreenShot

A polished, native screenshot utility built with **Quickshell** for Wayland
compositors. It ships with a modern overlay UI, shader-based dimming, bouncy
animations and intelligent window snapping, and works with **Hyprland**,
**MangoWM** and **Umbriel** through a small compositor abstraction layer.

![License](https://img.shields.io/badge/License-MIT-blue.svg)
![Wayland](https://img.shields.io/badge/Wayland-Native-green.svg)
![Quickshell](https://img.shields.io/badge/Built%20With-Quickshell-cba6f7.svg)
![Compositors](https://img.shields.io/badge/Compositors-Hyprland%20%7C%20MangoWM%20%7C%20Umbriel-blue.svg)

## ✨ Features

* **Capture modes:** region (drag to select), window (hover to select), screen
  (whole output) and temp (clipboard only).
* **Optional annotation:** hands the capture to Noctalia, Satty or Gradia when
  one of them is installed.
* **Optional notifications:** uses Noctalia when available, then falls back to
  libnotify, or stays silent.
* **Optional KDE Connect:** push screenshots directly to your phone.
* **Compositor aware:** monitors, windows and pointer position are read from
  the running compositor (Hyprland, MangoWM or Umbriel).
* **Themable:** colors, spacing, animation and integrations live in a single
  `theme.toml`.

## 📦 Requirements

Required:

1. A Wayland compositor with `wlr-screencopy` support (Hyprland, MangoWM,
   Umbriel, or another wlroots-based compositor).
2. [`quickshell`](https://quickshell.org/) 0.3 or newer.
3. `grim` for the actual capture.
4. `wl-clipboard` for clipboard output.

Optional:

5. [`noctalia`](https://github.com/noctalia-dev/noctalia) for built-in image
   annotation and notifications.
6. `satty` or `gradia` if you prefer a standalone annotation tool.
7. `libnotify` (`notify-send`) if you want notifications without Noctalia.
8. `kdeconnect` for the Share toggle.

> Satty, Gradia, libnotify and KDE Connect are never required. Missing tools are
> simply skipped.

## 🚀 Installation

Clone the repository into your Quickshell configuration directory:

```sh
git clone https://github.com/CheikhNaro/quickScreenShot.git \
  ~/.config/quickshell/quickScreenShot
```

Or keep it anywhere and pass its path directly:

```sh
git clone https://github.com/CheikhNaro/quickScreenShot.git ~/quickScreenShot
qs -p ~/quickScreenShot
```

Test it once:

```sh
qs -c quickScreenShot -n
```

## ⚙️ Compositor configuration

The utility is launched with Quickshell and reads `QSS_MODE` and `QSS_ACTION`
from the environment:

| Variable     | Values                  | Effect                                   |
| ------------ | ----------------------- | ---------------------------------------- |
| `QSS_MODE`   | `region`, `window`      | Initial selection mode (default `region`) |
| `QSS_ACTION` | `edit`, `temp`, `share` | Pre-select an action                      |

The older `HQF_MODE` / `HQF_ACTION` names are still accepted.

### Hyprland

`~/.config/hypr/hyprland.conf`:

```ini
# Open quickScreenShot
bind = SUPER SHIFT, S, exec, qs -c quickScreenShot -n
# Start in window mode
bind = SUPER SHIFT, W, exec, env QSS_MODE=window qs -c quickScreenShot -n
# Copy to clipboard only
bind = SUPER SHIFT, C, exec, env QSS_ACTION=temp qs -c quickScreenShot -n
# Open with annotation
bind = SUPER SHIFT, E, exec, env QSS_ACTION=edit qs -c quickScreenShot -n
```

### MangoWM

`~/.config/mango/config.conf` (or any included module):

```ini
bind=SUPER,S,spawn,qs -c quickScreenShot -n
bind=SUPER,W,spawn,env QSS_MODE=window qs -c quickScreenShot -n
bind=SUPER,C,spawn,env QSS_ACTION=temp qs -c quickScreenShot -n
bind=SUPER,E,spawn,env QSS_ACTION=edit qs -c quickScreenShot -n
```

MangoWM does not mark a focused monitor, so quickScreenShot uses the pointer
position to choose the active output.

### Umbriel

`~/.config/umbriel/config.toml`:

```toml
[keybinds]
"Mod+S" = "spawn qs -c quickScreenShot -n"
"Mod+W" = "spawn env QSS_MODE=window qs -c quickScreenShot -n"
"Mod+C" = "spawn env QSS_ACTION=temp qs -c quickScreenShot -n"
"Mod+E" = "spawn env QSS_ACTION=edit qs -c quickScreenShot -n"
```

`spawn` runs its command through the shell, so the environment prefix works as
written.

### Other compositors

On any other wlroots-based compositor, region and temp captures still work from
the Quickshell screen list. Window mode requires one of the three supported
compositors above.

## ⌨️ Overlay shortcuts

The bar exposes these modes:

* **Region** — drag to select an area.
* **Window** — hover a window and click to capture it.
* **Screen** — click to capture the whole output immediately.
* **Temp** — copy to the clipboard without writing a file. Use it for quick
  pastes that you do not want to keep in `~/Pictures/Screenshots`.
* **Edit** — open the capture in the annotation tool before saving.

| Key       | Action                          |
| --------- | ------------------------------- |
| Drag      | Select a region                 |
| `w`       | Window selection mode           |
| `r`       | Region selection mode           |
| `s`       | Capture the whole screen        |
| `e`       | Toggle annotation               |
| `t`       | Toggle clipboard-only mode      |
| `k`       | Toggle KDE Connect sharing      |
| `Esc`, `q`| Quit without capturing          |

## 🎨 Configuration

Copy `theme.toml` to one of these locations (first match wins):

1. `~/.config/quickScreenShot/theme.toml`
2. `~/.config/quickshell/quickScreenShot/theme.toml`

Otherwise the bundled `theme.toml` is used. Changes apply the next time the
overlay opens.

```toml
accent = "#cba6f7"
accentText = "#11111b"
dimOpacity = 0.6
borderRadius = 10
outlineThickness = 2
bottomMargin = 60
animations = true

# "auto" picks the first available: noctalia, satty, gradia.
# Other values: "noctalia", "satty", "gradia", "none".
annotationTool = "auto"

# "auto" (noctalia, then notify-send), "noctalia", "libnotify" or "none".
notifications = "auto"
```

### Annotation

With `annotationTool = "auto"`:

* `noctalia msg annotate` is used when Noctalia is installed. The raw capture
  is opened in Noctalia's editor, which applies its own save/copy settings.
* Otherwise `satty` is used, then `gradia`.
* `none` saves the capture without opening an editor.

### Notifications

With `notifications = "auto"`, Noctalia is preferred and `notify-send` is the
fallback. Set `notifications = "none"` to disable them completely.

### Noctalia color sync

`scripts/sync_theme.py` copies the current Noctalia palette into
`~/.config/quickScreenShot/theme.toml`, creating that file from the bundled
`theme.toml` the first time. Only the color keys are rewritten, so custom
spacing, hooks and integration choices are preserved.

Run it manually:

```sh
python3 ~/.config/quickshell/quickScreenShot/scripts/sync_theme.py
```

To sync automatically, copy `extras/noctalia/quickscreenshot-colors.json` to
`~/.config/noctalia/templates/`, then register it in
`~/.config/noctalia/theme.toml` (use absolute paths):

```toml
[theme.templates.user.quickscreenshot-colors]
enabled     = true
input_path  = "/home/you/.config/noctalia/templates/quickscreenshot-colors.json"
output_path = "/home/you/.cache/noctalia/quickscreenshot-colors.json"
post_hook   = "python3 /home/you/.config/quickshell/quickScreenShot/scripts/sync_theme.py"
hook_async  = true
```

Noctalia regenerates the palette on every wallpaper/scheme change and runs the
hook, so the overlay follows the desktop theme.

### Post-save hook

`[hooks] postSaveHook` runs a command after a successful save. Placeholders:
`%f` full path, `%n` filename, `%d` directory, `%t` timestamp.

## 🛠 Troubleshooting

**Black or empty overlay, or the window never appears**

Some GPU/driver combinations fail to share DMA-BUF buffers. Launch with
DMABUF disabled:

```sh
QS_DISABLE_DMABUF=1 qs -c quickScreenShot -n
```

**Window mode selects nothing**

Window mode relies on compositor IPC:

* Hyprland: `hyprctl`
* MangoWM: `mmsg`
* Umbriel: `umbriel`

Check that the matching command is in `PATH` and answers outside the overlay.

**No annotation or notification appears**

Install Noctalia, Satty, Gradia or `libnotify`, or set the corresponding option
explicitly in `theme.toml`.

## 🙏 Credits

quickScreenShot began as a fork of
[HyprQuickshot](https://github.com/JamDon2/HyprQuickshot) by JamDon2 and was
extended with a custom Quickshell UI, compositor abstraction and integration
options. The original MIT license and copyright notices are preserved.
