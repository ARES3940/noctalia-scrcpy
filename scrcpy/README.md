# Scrcpy Control

Control [scrcpy](https://github.com/Genymobile/scrcpy) from Noctalia: start and stop screen mirroring,
record the phone, stream a camera or a webcam, and use HID input — all over wireless ADB. The plugin is
a controller and launcher. scrcpy draws its own native window; the panel never embeds video.

## Plugin

| Field | Value |
| --- | --- |
| ID | `omen/scrcpy` |
| Version | 0.1.0 |
| Plugin API | 53 or newer (Noctalia v5.5.0+) |
| Entries | Service: `manager`; bar widget: `bar`; panels: `panel`, `quick`; shortcut: `toggle` |
| License | MIT |

## Requirements

- **adb** — Android Debug Bridge (package `android-tools` on Arch/CachyOS).
- **scrcpy** — version 5.0.1 or newer is recommended; every flag listed below was verified against 5.0.1.
- Wireless debugging enabled on the phone, and the computer authorised once on the phone.
- Optional: `v4l2loopback` loaded with a writable `/dev/videoN` node for webcam output (the plugin does
  not load kernel modules or use sudo).
- No QML, Quickshell, Python, or additional runtime is used.

## Usage

1. Enable **Scrcpy Control** in *Settings → Plugins* (or
   `noctalia msg plugins enable omen/scrcpy`).
2. Add **Scrcpy Control → bar** in the bar widget picker. The icon shows one of four states:
   offline, ready, mirroring, recording.
3. Click the icon to open the main panel; right-click opens a compact quick-actions panel with
   START MIRROR, START RECORDING, START LAST SESSION and STOP LAST SESSION. The control-center
   shortcut `toggle` opens the main panel.
4. Open the panels directly with:

```sh
noctalia msg panel-toggle omen/scrcpy:panel
noctalia msg panel-toggle omen/scrcpy:quick
```

### Pairing a phone over wifi

1. On the phone: *Developer options → Wireless debugging → Pair device with pairing code*.
2. In the panel, open **PAIR**, enter the `ip:port` shown by the phone and the 6-digit pairing code,
   then submit. The plugin runs `adb pair <ip:port> <code>`.
3. In *Wireless debugging* on the phone, read the connection port (different from the pairing port).
   The panel's device list discovers it with `adb mdns services` while the panel is open, and connecting
   runs `adb connect <ip:port>`.
4. If wireless debugging was toggled off and on, the port changes. The panel detects the stale serial,
   re-runs mdns discovery and offers **Reconnect**.
5. Known devices are remembered locally. Devices are deduplicated: adb 37 lists an mDNS-discovered
   phone both as `adb-…._adb-tls-connect._tcp` and as `ip:port` after `adb connect`; the panel shows it once.

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
| HID | `--keyboard=uhid`, `--mouse=uhid`, `--gamepad=uhid` | yes |
| OTG / AOA | `--otg`, `--keyboard=aoa`, `--mouse=aoa` | **no, USB only** |

USB-only options are disabled with the reason shown when the selected device is wireless. Webcam output
is disabled when no writable `/dev/videoN` exists.

### Presets

`Default`, `Gaming (low latency)`, `Low bandwidth`, `Webcam`, `Record only`.

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
| `mouse_mode` | `disabled` | `gamepad_mode` | `disabled` |
| `otg` | `false` | `always_on_top` | `false` |
| `fullscreen` | `false` | `window_title` | `noctalia-scrcpy` |
| `window_width` | `0` | `window_height` | `0` |
| `display_id` | `0` | `orientation` | `0` |

## IPC

The `manager` service accepts events over the plugin IPC channel:

```sh
noctalia msg plugin omen/scrcpy:manager all toggle-panel
noctalia msg plugin omen/scrcpy:manager all start-last
noctalia msg plugin omen/scrcpy:manager all stop-last
noctalia msg plugin omen/scrcpy:manager all start-recording
```

Keybinds can call these directly. `toggle-panel` opens the main panel. The panel and bar also use an
in-process command bus (`noctalia.state`), so no extra process is spawned for UI actions.

## Performance notes

- Discovery polls adb only while the main panel is open; the service ticks once per second.
- The service publishes plain state snapshots to the bar and panel; no polling of processes by the UI.
- The argv builder and gating rules are pure modules, so the unit suite runs without a device.

## Notes

- **Processes:** the service launches scrcpy detached and records its PID in a private data directory.
  Stopping a session sends `SIGTERM` to that PID, escalating to `SIGKILL` if needed. Only sessions
  owned by this plugin are stopped. A Noctalia `SIGKILL` cannot run cleanup; in that rare case use
  `pkill -f noctalia-scrcpy` to clear leftovers.
- **Files:** overrides, known devices, PID files and per-session logs live in Noctalia's per-plugin
  data directory. Pairing codes are passed as command arguments and are never stored.
- **Network:** `adb pair/connect/mdns` talks only to the local phone. No cloud calls, analytics or
  remote downloads. Discovery polls adb only while the panel is open.
- **Multiple sessions:** each launch is an independent process that can be stopped separately, for
  example a mirror plus a camera session.
- **Errors:** a failed scrcpy launch surfaces the last line of its log (`device unauthorized`, stale
  port, codec failure, and so on).

### Optional Hyprland window rules (documented, not applied)

The plugin never edits your Hyprland config. To float and place the scrcpy window, add rules like these
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
