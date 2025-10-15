
# Idle Slideshow for GNOME (Ubuntu)

A tiny Bash daemon that shows a **full-screen slideshow from your folders when you’re idle**, and closes **immediately** on the first mouse/keyboard activity. Works on GNOME (Wayland/X11). Uses the lightweight **imv** image viewer.

## Highlights

* Uses GNOME Mutter’s **IdleMonitor** over D-Bus to read the current idle time — no hacks.
* Slideshow via **imv** with duration (`-t`), scaling (`-s`), recursion (`-r`), and optional window title (`-w`).
* “**Always on top**” + fullscreen for X11/XWayland windows using EWMH (_NET_WM_STATE) via `wmctrl`.
* Random order (shuffle) and robust extension filter using `find -regextype posix-extended`.
* Ships with sensible defaults; easy to tweak.


## Requirements

```bash
sudo apt install imv wmctrl dbus libglib2.0-bin findutils
```

* `imv` provides `-t/-s/-r/-w` options (and `imv-wayland` / `imv-x11` wrappers are commonly packaged).
* `wmctrl` manipulates EWMH/NetWM states (fullscreen, above) **for X11/XWayland windows**.
* `dbus` & `gdbus` are used to query Mutter’s IdleMonitor.
* `findutils` for the regex-based file scan.


## Install

1. Put the script at `~/.local/bin/wayland-slideshow.sh` and make it executable:

```bash
chmod +x ~/.local/bin/wayland-slideshow.sh
```

2. (Optional) Start on login — create a desktop entry:

```ini
# ~/.config/autostart/idle-slideshow.desktop
[Desktop Entry]
Type=Application
Name=Idle Slideshow
Exec=/home/$USER/.local/bin/wayland-slideshow.sh
X-GNOME-Autostart-enabled=true
```


## Configuration

Edit the top of the script:

```bash
DIRS=( "$HOME/Pictures/DigitalArt" )  # one or more folders
IDLE_LIMIT_MS=$((5*60*1000))          # idle threshold (ms)
DURATION=8                             # seconds per slide (imv -t)
ORDER="shuffle"                        # "shuffle" or "natural"
TITLE="Idle Slideshow"                 # imv window title (-w or config)
SCALING=full                           # none|shrink|full|crop (imv -s)
ALWAYS_ON_TOP=1                        # try to keep above others (X11/XWayland)

CHECK_EVERY_IDLE=0.5                   # poll interval when waiting for idle (s)
CHECK_EVERY_ACTIVE=0.08                # poll interval while slideshow is running (s)
ACTIVE_EDGE_MS=500                     # treat as “active” if idletime < this
EXTS="jpg|jpeg|png|webp|gif|bmp|tif|tiff|avif"
```

### Window title

If you prefer configuring the title in `imv` instead of `-w`, add to `~/.config/imv/config`:

```ini
[options]
title_text = Idle Slideshow
```

(See `imv(5)` for config keys.) ([Arch Manual Pages][5])


## How it works

* The script polls GNOME Mutter’s **IdleMonitor** (`org.gnome.Mutter.IdleMonitor.GetIdletime`) over D-Bus. When `idletime ≥ threshold`, it starts **imv**; when it drops below a small edge (user activity), it kills imv immediately. The IdleMonitor methods/signals are defined in Mutter’s D-Bus interface.
* File list is built with `find -regextype posix-extended -iregex '.*\.(jpg|png|…)$'` (case-insensitive, NUL-safe).
* On Wayland, “always on top” is applied by launching **imv-x11** (XWayland) and then setting EWMH flags with `wmctrl` (`_NET_WM_STATE_ABOVE`, fullscreen). Pure Wayland windows don’t expose global stacking control; `wmctrl` only targets X11/XWayland.


## Quick test

* Run the script:

```bash
~/.local/bin/wayland-slideshow.sh
```

* Temporarily lower idle threshold for testing:

```bash
IDLE_LIMIT_MS=$((10*1000))  # 10 seconds
```

* Sanity-check GNOME idletime from a terminal:

```bash
dbus-send --print-reply --dest=org.gnome.Mutter.IdleMonitor \
  /org/gnome/Mutter/IdleMonitor/Core org.gnome.Mutter.IdleMonitor.GetIdletime
```

(Should return `uint64 <milliseconds>`.)


## Troubleshooting

**Black screen instead of images**

1. Make sure your folders actually contain files matching `EXTS`.
2. Try plain imv to rule out viewer issues:

```bash
imv -t 8 -s full "$HOME/Pictures/DigitalArt"
```

`-t/-s/-r/-w` are documented in `imv(1)`.

**“Always on top” doesn’t stick on Wayland**
That flag is an X11 EWMH state. It applies to X11/XWayland windows; native Wayland windows don’t support global stacking control via `wmctrl`. Ensure the script picked **imv-x11** (or force X11).

**Ordering looks odd**
In “natural” mode, order comes from the OS/filesystem. For random order, keep `ORDER="shuffle"`. If you need strict numeric sorting, pre-build the list and pass it to `imv -t`. (imv also has `imv-dir`, but we drive our own list for full control.)


## Advanced

* **IPC control:** `imv-msg <pid> <command>` can send commands (e.g., `quit`, `slideshow 5`) to a running instance. Handy if you want to close gracefully or change duration live.
* **Performance tuning:**

  * Faster close on activity → reduce `CHECK_EVERY_ACTIVE` to `0.05`.
  * Lower CPU when idle → increase `CHECK_EVERY_IDLE` (e.g., `1.0`).
* **Multiple sources:** add more folders to `DIRS=( … )`.

## License

MIT (or Unlicense)
