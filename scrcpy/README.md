# Scrcpy Control

Control [scrcpy](https://github.com/Genymobile/scrcpy) from Noctalia: mirror the phone inside an
interactive embedded preview, or launch scrcpy in its own window; record, stream a camera or a webcam,
and use HID input — all over wireless ADB. The plugin is a controller and launcher. Embedded mode
feeds a V4L2 loopback and displays it with Noctalia's `ui.pixelStream`; no native scrcpy window opens.

## Plugin

| Field | Value |
| --- | --- |
| ID | `omen/scrcpy` |
| Version | 0.3.0 |
| Plugin API | 53 or newer (Noctalia v5.5.0+); pixel stream API 40+ |
| Entries | Service: `manager`; bar widget: `bar`; panels: `panel`, `screen`, `quick`; shortcut: `toggle` |
| License | MIT |

## Requirements

- **adb** — Android Debug Bridge (package `android-tools` on Arch/CachyOS).
- **scrcpy** — version 5.0.1 or newer is recommended; every flag listed below was verified against 5.0.1.
- Wireless debugging enabled on the phone, and the computer authorised once on the phone.
- **Embedded preview only:** `python3`, `ffmpeg`, and `v4l2loopback` loaded with a writable,
  unused `/dev/videoN` node (default `/dev/video10`). Native-window mirroring, recording and camera
  need only adb and scrcpy.
- The plugin does not load kernel modules, use sudo, or install packages. No QML or Quickshell is used.

## Usage

1. Enable **Scrcpy Control** in *Settings → Plugins* (or
   `noctalia msg plugins enable omen/scrcpy`).
2. Add **Scrcpy Control → bar** in the bar widget picker. The widget shows one glyph and one of
   four states: offline, ready, mirroring (with elapsed time), recording (`REC`). Its tooltip lists
   the state, the selected phone, each active session and any error.
3. Click the widget to open the main panel; right-click opens the quick-actions panel. The
   control-center shortcut `toggle` starts or stops a mirror in one click and falls back to the
   panel when no phone is ready.
4. Open the panels directly with:

```sh
noctalia msg panel-open omen/scrcpy:panel
noctalia msg panel-open omen/scrcpy:screen
noctalia msg panel-open omen/scrcpy:quick
```

### Embedded preview

`START MIRROR` now starts an **embedded** session: scrcpy writes the phone display to the configured
V4L2 loopback with `--v4l2-sink=… --no-window --v4l2-buffer=0`, and a small Python companion serves
those frames to the `screen` panel. Taps, drags, typing and Back / Home / Recents go back to the phone
over `adb shell input`. The preview panel opens automatically when an embedded mirror starts; closing
it stops the preview and its mirror. Use `WINDOW` (or `OPEN IN WINDOW` in the preview panel) for the
traditional native scrcpy window.

The preview is tied to one loopback node. It cannot run at the same time as `WEBCAM` mode or another
plugin using the same `/dev/videoN` (for example AndroidConnect). The companion is written for this
plugin from the public Noctalia pixel-stream protocol; AndroidConnect's GPL code is neither copied
nor linked.

### Main panel

The panel is 420 × 600 and has three tabs:

| Tab | What it holds |
| --- | --- |
| **Control** | Selected phone, `START MIRROR` (embedded), `REC`, `CAMERA`, `WEBCAM`, `WINDOW`, record-while-mirroring, restart last session, live sessions with elapsed time and stop, presets, and a two-line summary of the session defaults |
| **Devices** | Connected devices with `USE` / `CONNECT` / `MIRROR`, the pairing form, a manual `ip:port` connect, and remembered devices with forget |
| **Settings** | Video, audio, recording, display, input and screen, camera and webcam, window options, an **Advanced** disclosure (buffers, encoder, virtual-display DPI, OTG, window size, orientation), the exact command preview, and reset-overrides |

Edits apply to sessions started from then on. A preset fills the overrides in one click; the
selected preset is highlighted and turns into `CUSTOM` after a manual edit. All overrides are
saved to the plugin data directory (debounced), not to the Noctalia settings file.

### Device selection

- The only ready phone is selected automatically.
- The selection is stored in `selection.json` together with the phone's `product`, because wireless
  debugging changes the `ip:port` on every reconnect. When the saved serial disappears, the panel
  matches the same `product` on the new port and shows a "reconnected on a new port" notice.
- Sessions, the bar and the quick panel all read the same selection, so they agree on the phone.

### Recording

`REC` starts a record-only session: scrcpy writes the file without opening a window
(`--no-playback --no-window`). Recordings go to `record_dir` (`~/Videos` by default); `~` is expanded
by the service, and the directory is created if needed. Files are named
`scrcpy-<session-id>.<format>`. The finished path is shown in the session row and the bar tooltip.

### Pairing a phone over wifi

1. On the phone: *Developer options → Wireless debugging → Pair device with pairing code*.
2. In the panel's **Devices** tab, enter the `ip:port` shown by the phone and the 6-digit pairing
   code, then press **PAIR**. The plugin runs `adb pair <ip:port> <code>`.
3. In *Wireless debugging* on the phone, read the connection port (different from the pairing port).
   The device list discovers it with `adb mdns services` while the panel is open; **CONNECT** runs
   `adb connect <ip:port>`.
4. If wireless debugging was toggled off and on, the port changes. The saved serial is matched by
   the phone's `product` name, so the panel re-selects the same phone on its new port and says so.
5. Known devices are remembered locally. Devices are deduplicated: adb 37 lists an mDNS-discovered
   phone both as `adb-…._adb-tls-connect._tcp` and as `ip:port` after `adb connect`; the list shows
   it once.

## Feature coverage

Every feature is implemented by passing a flag to scrcpy. The plugin never reimplements a scrcpy feature.

| Feature | scrcpy flags | Wireless |
| --- | --- | --- |
| Quality / fps / codec | `--max-size`, `--video-bit-rate`, `--max-fps`, `--video-codec`, `--video-encoder`, `--video-buffer` | yes |
| Audio | `--no-audio`, `--audio-source`, `--audio-codec`, `--audio-bit-rate`, `--audio-buffer` | yes |
| Recording | `--record=FILE`, `--record-format`, `--no-playback` | yes |
| Virtual display | `--new-display=WxH/DPI`, `--start-app`, `--no-vd-system-decorations` | yes (Android 14+) |
| Screen off / awake | `--turn-screen-off`, `--stay-awake`, `--power-off-on-close`, `--screen-off-timeout` | yes |
| Clipboard | default sync, `--no-clipboard-autosync` | yes |
| Camera | `--video-source=camera`, `--camera-facing`, `--camera-size`, `--camera-id` | yes (Android 12+) |
| Webcam | `--v4l2-sink=/dev/videoN` | yes (needs v4l2loopback) |
| Embedded preview | `--v4l2-sink`, `--no-window`, `--v4l2-buffer=0` + pixel-stream companion | yes (needs v4l2loopback, python3, ffmpeg) |
| HID | `--keyboard=uhid`, `--mouse=uhid`, `--gamepad=uhid` | yes |
| OTG / AOA | `--otg`, `--keyboard=aoa`, `--mouse=aoa` | **no, USB only** |

USB-only options are disabled with the reason shown when the selected device is wireless. Webcam output
is disabled when no writable `/dev/videoN` exists.

### Presets

`Default`, `Gaming (low latency)`, `Low bandwidth` (labelled **Low data** in the panel),
`Webcam`, `Record only` (labelled **Record**).

## Settings

Open *Settings → Plugins → Scrcpy Control*. Defaults are seeded from the manifest; the panel stores
per-device overrides in the plugin data directory. Values with a unit: `video_bit_rate` and
`audio_bit_rate` are in **kbps**, all `*ms` settings are in **milliseconds**, `screen_off_timeout` is in
**seconds**, `max_size` is in **pixels**.

| Key | Default | Key | Default |
| --- | --- | --- | --- |
| `device_serial` | `""` | `record_dir` | `~/Videos` |
| `max_size` | `1024` | `video_bit_rate` | `8000` |
| `max_fps` | `60` | `video_codec` | `h264` |
| `video_encoder` | `""` | `video_buffer_ms` | `0` |
| `audio_enabled` | `true` | `audio_source` | `output` |
| `audio_codec` | `opus` | `audio_bit_rate` | `128` |
| `audio_buffer_ms` | `50` | `record_enabled` | `false` |
| `record_format` | `mp4` | `record_only` | `false` |
| `new_display` | `false` | `new_display_size` | `1920x1080` |
| `new_display_dpi` | `240` | `vd_no_system_decorations` | `false` |
| `start_app` | `""` | `turn_screen_off` | `false` |
| `stay_awake` | `true` | `power_off_on_close` | `false` |
| `screen_off_timeout` | `0` | `clipboard_autosync` | `true` |
| `show_touches` | `false` | `no_control` | `false` |
| `video_source` | `display` | `camera_facing` | `back` |
| `camera_size` | `""` | `camera_id` | `""` |
| `camera_fps` | `0` | `v4l2_enabled` | `false` |
| `v4l2_sink` | `/dev/video10` | `keyboard_mode` | `disabled` |
| `preview_width` | `320` | `preview_height` | `640` |
| `preview_fps` | `30` | | |
| `mouse_mode` | `disabled` | `gamepad_mode` | `disabled` |
| `otg` | `false` | `always_on_top` | `false` |
| `fullscreen` | `false` | `window_title` | `noctalia-scrcpy` |
| `window_width` | `0` | `window_height` | `0` |
| `display_id` | `0` | `orientation` | `0` |

## IPC

The `manager` service accepts events over the plugin IPC channel:

```sh
noctalia msg plugin omen/scrcpy:manager all toggle-panel
noctalia msg plugin omen/scrcpy:manager all refresh
noctalia msg plugin omen/scrcpy:manager all start-last
noctalia msg plugin omen/scrcpy:manager all stop-last
noctalia msg plugin omen/scrcpy:manager all start-embedded
noctalia msg plugin omen/scrcpy:manager all stop-preview
noctalia msg plugin omen/scrcpy:manager all preview-tap '{"x":0.5,"y":0.5}'
noctalia msg plugin omen/scrcpy:manager all preview-key '{"key":"back"}'
noctalia msg plugin omen/scrcpy:manager all start-recording
noctalia msg plugin omen/scrcpy:manager all start '{"kind":"mirror","extras":{"video_source":"camera"}}'
noctalia msg plugin omen/scrcpy:manager all stop '{"id":"<session-id>"}'
noctalia msg plugin omen/scrcpy:manager all connect '{"serial":"192.168.0.11:5555"}'
noctalia msg plugin omen/scrcpy:manager all pair '{"host":"192.168.0.11:37123","code":"123456"}'
```

`start` accepts the same keys a session can override; the payload is JSON or a plain `ip:port`
string. Keybinds can call these directly. The panel, quick panel, bar and shortcut also use an
in-process command bus (`noctalia.state`), so no extra process is spawned for UI actions.

## Performance notes

- Discovery polls adb only while the main panel is open; the service ticks once per second.
- The service publishes plain state snapshots to the bar and panel; no polling of processes by the UI.
- The argv builder and gating rules are pure modules, so the unit suite runs without a device.

## Notes

- **Processes:** the service launches scrcpy detached with an argv array (never a shell string) and
  records its PID in a private data directory.
  Stopping a session sends `SIGTERM` to that PID, escalating to `SIGKILL` if needed. Only sessions
  owned by this plugin are stopped. A Noctalia `SIGKILL` cannot run cleanup; in that rare case use
  `pkill -f noctalia-scrcpy` to clear leftovers.
- **Files:** overrides, known devices, the current selection, PID files and per-session logs live in
  Noctalia's per-plugin data directory. The embedded preview adds a private `preview-<id>.sock`,
  `.pid` and `.log` there; the socket is removed when the companion exits. Pairing codes are passed
  as command arguments and are never stored.
- **Embedded processes:** the manager owns both the scrcpy session and `preview.py`. Companion frames
  go straight from ffmpeg through a sealed shared-memory buffer to the shell; no pixels pass through
  Lua. A dead companion is reported in the preview panel and stops its mirror.
- **Network:** `adb pair/connect/mdns` talks only to the local phone. No cloud calls, analytics or
  remote downloads. Discovery polls adb only while the panel is open.
- **Multiple sessions:** each launch is an independent process that can be stopped separately, for
  example a mirror plus a camera session.
- **Errors:** a failed scrcpy launch surfaces the `ERROR:` line of its log (`device unauthorized`,
  stale port, codec failure, and so on) in a notice and on the session row; successful stops end as
  `stopped`, not `error`.

### Optional Hyprland window rules (documented, not applied)

The plugin never edits your Hyprland config. The embedded preview needs no window rules; for the
optional native-window mode, to float and place the scrcpy window add rules like these
to `~/.config/hypr/hyprland.conf` and reload Hyprland:

```conf
windowrule = float, match:title ^noctalia-scrcpy
windowrule = size 540 1170, match:title ^noctalia-scrcpy
windowrule = move 1380 60, match:title ^noctalia-scrcpy
windowrule = bordercolor rgba(89b4faee) 3, match:title ^noctalia-scrcpy
```

Change `window_title` in the plugin settings if you want a different match string.

## Known limits

- scrcpy always opens its own native window; there is no embedded video in the panel.
- OTG/AOA cannot work over wifi; v4l2loopback must be loaded by an administrator if it is not already.
- The wireless debugging port changes when wireless debugging is toggled; reconnect from the panel.
- `v4l2loopback` device `/dev/video10` may already be used by another plugin (for example
  `demencia89/androidconnect`), which also defaults to it. Pick a different node if so.
- Fractional scaling and every phone/codec combination have not been tested.
