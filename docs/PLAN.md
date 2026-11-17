# PLAN.md — Noctalia plugin: scrcpy controller over wireless ADB

Status: **Phase 0 (research) complete. Awaiting approval before any plugin code is written.**

> Plan-mode note: this file lives in the allowed plan directory. On approval it is copied into the
> project repo as the first commit of Session 1 (`docs/PLAN.md` or repo-root `PLAN.md`).

---

## 0. TL;DR — what Phase 0 changed about the brief

The brief was written against the **Noctalia v4 (QML/Quickshell) plugin model**. The installed shell is
**Noctalia v5.5.0**, whose plugin API is **Luau-only**, and the community registry **explicitly rejects
QML/Quickshell plugins**:

> "No QML or Quickshell plugins. Plugins are written in Luau against the Noctalia plugin API, and all UI
> is drawn through that API. A plugin that ships QML, or launches Quickshell (`qs`) or any other UI
> runtime to draw what the API does not offer, will be rejected."
> — `noctalia-dev/community-plugins` README

So the requested file layout (`Main.qml`, `BarWidget.qml`, `Panel.qml`, `Settings.qml`, "Quickshell
Process") **cannot ship to the registry**. The plan below keeps every *functional* requirement from the
brief and re-implements it in the v5 model:

| Brief (v4/QML) | Plan (v5/Luau) |
| --- | --- |
| `Main.qml` owns adb + scrcpy processes | `[[service]] manager.luau` — the only entry that spawns processes; owns adb + scrcpy + session state |
| `BarWidget.qml` state icon | `[[widget]] bar.luau` — `barWidget.render(ui.*)` tree, four states |
| `Panel.qml` device list, pairing, toggles, presets | `[[panel]] panel.luau` — `panel.render(ui.*)` tree, interactive controls |
| `Settings.qml` + manifest `defaultSettings` | Manifest `[[setting]]` schema (rendered by Noctalia in *Settings → Plugins*) + a panel "overrides" section persisted in the plugin data dir |
| "one pure function settings → args" | `lib/args.luau` — pure module, no I/O, unit-tested by a self-test service |
| "Quickshell screencopy thumbnail" | **Dropped** — the v5 plugin API exposes no screencopy/screenshot function (verified against `noctalia.d.luau` and the runtime API docs). Only `ui.pixelStream` exists, which needs a companion process (extra deps). |

Everything else in the brief is kept: full scrcpy flag coverage, presets, wireless pairing flow, mdns
discovery, multi-session support, USB-only / V4L2 gating with reasons, error surfacing, IPC handlers,
argv-array-only command building, no Hyprland edits (documented in README instead).

---

## 1. Phase 0 findings

### 1.1 Environment (verified on this machine)

| Item | Value | How verified |
| --- | --- | --- |
| Noctalia | **v5.5.0 (5.5.0-1-dirty)**, binary `/usr/bin/noctalia` | `noctalia --version` |
| Docs tree that matches | **current tree** `docs.noctalia.dev/noctalia/…`; the legacy tree is *Noctalia Shell (v4)*, which no longer applies | docs site index |
| Quickshell | 0.3.2 (`qs`) | `qs --version` |
| Plugin API levels supported by this shell | **3 – 53** (v5.5.0 docs); the rolling `main` docs say 3 – 55, but 54/55 are marked "Unreleased" | `/noctalia/v5.5.0/plugins/development/plugin-api/` vs the unversioned rolling page |
| scrcpy | **5.0.1** (`/usr/bin/scrcpy`) — a *new major* vs the 2.x/3.x the brief assumed | `scrcpy --version` |
| adb | **1.0.41 / 37.0.0p1-android-tools** (`android-tools`) | `adb version` |
| v4l2loopback | **already loaded** (`v4l2loopback 81920 1`), `exclusive_caps = N,N,N,…` | `lsmod`, `/sys/module/v4l2loopback/parameters/exclusive_caps` |
| Loopback device | **`/dev/video10`**, card label `scrcpy-panel` (the device androidconnect uses for its preview) | `/sys/class/video4linux/video10/name`, `ls /dev/video*` |
| User groups | `omen sys network … video storage …` → **user is in `video`**, so `/dev/video10` is accessible | `id -nG` |
| Compositor | **Hyprland 0.57.2**, Wayland session | `hyprctl version` |
| Image tooling (for the required thumbnail) | `magick`, `convert`, `ffmpeg` present; `cwebp` absent (ImageMagick can write WebP) | `command -v` |
| Git / GitHub identity | git `user.name = ARES3940`, `user.email = ahamedtashin@gmail.com`; GitHub MCP token is authenticated as **ARES3940** (Ahmed Tashin) | `git config`, `github.get_me` |
| Local user / existing plugin author | user `omen`; existing plugin id **`omen/remote-monitor`** | `~/.local/share/noctalia/plugins/remote-monitor/plugin.toml` |

### 1.2 Where Noctalia v5 plugins actually live (brief said `~/.config/noctalia/plugins/`)

- Local dev plugins: **`~/.local/share/noctalia/plugins/<plugin>/`** (`$XDG_DATA_HOME/noctalia/plugins/`)
- `~/.config/noctalia/plugins/` **does not exist** on this machine.
- The existing plugin `omen/remote-monitor` lives in `~/.local/share/noctalia/plugins/remote-monitor/`
  (files: `plugin.toml`, `shared.luau`, `theme.luau`, `bar.*.luau`, `panel.detail.luau`, `collect.*.luau`,
  `desktop.*.luau`, `translations/en.json`, `assets/`).
- Config: `~/.config/noctalia/config.toml`; the existing plugin's bar widgets are registered as
  `type = "omen/remote-monitor:bar_armbian"` / `bar_proxmox`.

### 1.3 Conventions adopted from `omen/remote-monitor`

- `--!nonstrict` header on every file; `require("./x.luau")` modules (API 22).
- `theme.luau` = single source of tokens (sizes, fonts, palette **role names**, copy strings, motion).
  Palette roles only (`primary`, `on_surface`, `surface_container/0.88`, `on_surface/0.16`) — **no hard-coded hex**.
- `shared.luau` = pure helpers + `ui.*` builders (`micro`, `meta`, `value`, `dot`, `card`, `errorLine`).
- Cross-entry data via `noctalia.state.set/watch`; config via `noctalia.getConfig`.
- English-only identifiers/comments/copy, `translations/en.json` for `label_key`/`description_key`.

### 1.4 The existing "scrcpy plugin for Noctalia" — `demencia89/androidconnect`

Found in the community registry (`noctalia-dev/community-plugins` → `androidconnect/`, v2.4.1,
`plugin_api = 43`). It is the only scrcpy-related plugin there.

**License: `GPL-2.0-only`** → **no code may be copied into an MIT-licensed plugin.** Reuse is limited to
ideas and to the public CLI surface. (Its README states it is "Based on WerWolv's original Noctalia KDE
Connect plugin", also GPL.)

What it does:

- Bar widget, panel, service, control-center shortcut; Python companion (`backend.py`, 51 KB).
- Device discovery, ADB device control, wireless pairing (incl. QR), KDE Connect integration
  (battery, notifications, file sharing/SFTP, find-phone), screenshots, recordings.
- **Embedded live scrcpy preview** in the panel via `scrcpy --v4l2-sink=/dev/video10` + `ffmpeg` + a
  `SOCK_SEQPACKET`/`SCM_RIGHTS` companion feeding Noctalia's `ui.pixelStream`.
- "Open in window" launches standalone scrcpy.

What it does **not** do (the gap this project fills):

- **No scrcpy feature coverage**: no codec/quality/fps/bitrate/buffer controls, no audio source/codec,
  no virtual display (`--new-display`), no camera source (`--video-source=camera`), no HID modes
  (`--keyboard/--mouse/--gamepad`), no OTG, no screen-off/stay-awake/power-off options, no clipboard
  control, no presets, no multi-session management.
- **No standalone scrcpy option builder**: it launches scrcpy with a fixed argument set.
- It is a *KDE Connect + preview* plugin, not a scrcpy control surface.

Caveat for us: it defaults to `/dev/video10` for its preview loopback — the same device we would use for
the "Webcam" preset. README must tell the user to pick a different loopback node if both are installed.

### 1.5 scrcpy 5.0.1 flag audit (every flag in the brief's table checked against `scrcpy --help`)

**Every flag in the brief's table exists in 5.0.1.** Nothing was renamed or removed. 5.0 *adds* a lot:

| Brief feature | Flags verified in 5.0.1 | Notes / 5.0 additions |
| --- | --- | --- |
| Quality/fps/codec | `--max-size` (`-m`), `--video-bit-rate` (`-b`), `--max-fps`, `--video-codec`, `--video-encoder`, `--video-buffer` | codecs now `h264,h265,av1,vp8,vp9`; adds `--video-codec-options`, `--min-size-alignment`, `--ignore-video-encoder-constraints`, `--no-downsize-on-error`, `--hwdec`, `--no-mipmaps` |
| Audio | `--no-audio`, `--audio-source`, `--audio-codec`, `--audio-bit-rate`, `--audio-buffer` | codec list is now `opus,aac,flac,raw`; sources expanded to 12 values (`output,playback,mic,mic-unprocessed,mic-camcorder,mic-voice-recognition,mic-voice-communication,voice-call,voice-call-uplink,voice-call-downlink,mic-performance,voice-performance`); adds `--audio-encoder`, `--audio-codec-options`, `--audio-output-buffer`, `--audio-dup`, `--no-audio-playback`, `--require-audio` |
| Recording | `--record=FILE` (`-r`), `--record-format`, `--no-playback` (`-N`) | formats now `mp4,mkv,m4a,mka,opus,aac,flac,wav` (audio containers are new); adds `--record-orientation`, `--pause-on-exit` |
| Virtual display | `--new-display[=WxH/DPI]`, `--start-app`, `--no-vd-system-decorations` | adds `--no-vd-destroy-content`; needs **Android 14+** (this phone is Android 17 → OK) |
| Screen off / awake | `--turn-screen-off` (`-S`), `--stay-awake` (`-w`), `--power-off-on-close`, `--screen-off-timeout` | adds `--no-power-on`, `--disable-screensaver`, `--keep-active` |
| Clipboard | default sync, `--no-clipboard-autosync` | adds `--legacy-paste` |
| Camera | `--video-source=camera`, `--camera-facing`, `--camera-size`, `--camera-id` | facing now `front,back,external`; adds `--camera-ar`, `--camera-fps`, `--camera-high-speed`, `--camera-torch`, `--camera-zoom`; needs **Android 12+** (OK here) |
| Webcam (V4L2) | `--v4l2-sink=/dev/videoN` | adds `--v4l2-buffer`; Linux-only |
| HID | `--keyboard=uhid`, `--mouse=uhid`, `--gamepad=uhid` | 5.0 adds the `sdk` mode for keyboard/mouse; `--gamepad` accepts `disabled,uhid,aoa` |
| OTG / AOA | `--otg`, `--keyboard=aoa`, `--mouse=aoa` | **USB only** — to be disabled over wifi |

Extra 5.0 flags worth exposing in the panel (not in the brief, cheap to add):
`--always-on-top`, `--fullscreen`, `--window-title/--window-x/--window-y/--window-width/--window-height/--window-borderless`,
`--display-id`, `--display-orientation`, `--display-ime-policy`, `--orientation`, `--capture-orientation`, `--crop`,
`--show-touches`, `--no-control`, `--no-video`, `--no-window`, `--flex-display`, `--render-fit`, `--background-color`,
`--shortcut-mod`, `--mouse-bind`, `--prefer-text`, `--raw-key-events`, `--no-key-repeat`, `--no-mouse-hover`,
`--print-fps`, `--time-limit`, `--push-target`, `--no-cleanup`, `--kill-adb-on-close`, `--tcpip`, `--tunnel-host/--tunnel-port`,
`--select-usb/--select-tcpip`, `--port`, `--verbosity`, `--list-*` helpers.

**Nothing in the brief's table is missing or renamed in 5.0.1.**

### 1.6 Wireless ADB facts (verified)

- `adb pair HOST[:PORT] [PAIRING CODE]` — non-interactive with the code. `adb mdns services`, `adb mdns check`.
- A device **is connected right now**, over wireless ADB:
  `adb-c297c4b2-xIfLEq._adb-tls-connect._tcp  device  product:lavender model:Redmi_Note_7`
  `adb mdns services` → `adb-c297c4b2-xIfLEq  _adb-tls-connect._tcp  192.168.0.11:38377`
- Device: **Redmi Note 7 (lavender), Android 17 (SDK 37)** → camera mirroring (Android 12+), virtual display
  (Android 14+), UHID and `--max-fps` are all supported. OTG/AOA still USB-only.
- `adb connect 192.168.0.11:38377` **adds a second serial** for the same phone alongside the mDNS one
  (verified: two `device` rows, then `adb disconnect` restored the single row).
  → the plugin must **dedupe by transport/product**, not by serial, and should prefer the `ip:port` serial
  for `scrcpy -s` (stable for the session) while still showing the mDNS name.
- The wireless-debugging **port changes when wireless debugging is toggled** → stale-port handling must
  re-run `adb mdns services` and offer reconnect, exactly as the brief requires.

### 1.7 Noctalia v5 runtime constraints (verified in the shell's own source, `noctalia-dev/noctalia`)

These drive the process model:

1. **`noctalia.runAsync(cmd, callback)` has a default timeout of 5 s** (`kDefaultCommandTimeout = 5000`,
   max 60 s, `src/scripting/luau_host.cpp`). A long-lived scrcpy session **cannot** be started through
   the callback path — it would be killed after 5 s.
2. `noctalia.runAsync(argv)` **without** a callback is a *detached* launch (double-fork + `setsid`), no
   timeout, no output capture. Cap: **32 concurrent detached commands** (`kMaxGlobalDetachedCommands`).
3. The plugin API exposes **no PID and no kill handle**. `noctalia.processMatches(cb, …)` only reports
   whether a command line matches.
4. `noctalia.state` is the **only** in-process cross-entry channel (in-memory, plain data, `set/get/watch`).
5. There is **no screencopy / screenshot / window-capture API** for plugins (checked `noctalia.d.luau`:
   the only capture-ish primitive is `ui.pixelStream`, which requires a companion process speaking the
   `SOCK_SEQPACKET` + `SCM_RIGHTS` shared-buffer protocol).
6. `noctalia.runAsync` with an **argv table** (API 24) executes the program directly — exactly what the
   brief demands ("build args as an ARRAY, never a shell string").

### 1.8 Registry requirements (community-plugins, `community` profile)

- Required files: `README.md`, `thumbnail.webp` (**960×540**, WebP, ≤ 512 KB), `translations/en.json`,
  `plugin.toml` + entry scripts. (`preview.png` is **not** a registry artefact — corrected.)
- Plugin dir name = the id segment after `/`; both id segments must match `[a-z0-9][a-z0-9._-]*`.
- `catalog.toml` at the repo root is **generated by CI — never hand-edited**.
- Manifest: `id`, `name`, `version` (strict `MAJOR.MINOR.PATCH`), `plugin_api` (mandatory),
  `author`, `license`, `description` (**≤ 120 chars**), `icon`, `tags`, `dependencies`.
- `dependencies` must list every external command the plugin shells out to.
- ≤ 200 files per plugin directory; `README` and manifest prose must be English.
- Editor setup: `noctalia.d.luau` (from official-plugins) + `.luaurc` with `nonstrict`.

---

## 2. Target architecture

### 2.1 Entries

```
[[service]] id = "manager"   entry = "manager.luau"     # owns adb + scrcpy processes, session state
[[widget]]  id = "bar"       entry = "bar.luau"         # state icon, click → panel, right-click → quick actions
[[panel]]   id = "panel"     entry = "panel.luau"       # devices, pairing, toggles, presets, sessions
[[shortcut]]id = "toggle"    entry = "shortcut.luau"    # control-center tile → toggles the panel
```

**`plugin_api = 53`** — the newest level that runs on the installed v5.5.0 (v5.5.0 docs: supported range
**3–53**). Levels **54** (`noctalia.compositor.*`) and **55** (`ui.ring`) are still marked *Unreleased*
in the rolling docs; a manifest declaring them cannot be enabled on v5.5.0 ("targets plugin API X,
supported range 3-53"). Declaring 53 requires Noctalia **v5.5.0+** and gives us, for free:
`onSuspend()`/`onResume()` on the service (API 48 — re-run mdns/reconnect after sleep),
`layer = "follow"` on the panel (API 49 — follows the shell's floating-panel layer), `ui.label` `shadow`
(API 51) and `clip` on flex containers (API 52). We do **not** need APIs 54/55 for anything in this
project: the compositor event stream is redundant with PID-file liveness, and there is no gauge.

### 2.2 Process model (the important part)

- **Only `manager.luau` spawns anything.** The panel and the widget never start processes; they send
  commands and watch state.
- **Command channel (in-process, no spawn):** `noctalia.state.set("cmd", { seq = n, action = …, payload = … })`.
  `manager.luau` does `noctalia.state.watch("cmd", …)` and dispatches. `seq` is monotonic so every
  command is a distinct value (the store only notifies on change). The same dispatcher is reached by
  external IPC (`onIpc`) so keybinds and panel actions share one code path.
- **Starting scrcpy** (detached, because of the 5 s callback timeout):

  ```lua
  -- argv table; nothing is ever interpolated into a shell string
  { "sh", "-c", 'pid=$1; log=$2; shift 2; echo $$ > "$pid"; exec "$@" > "$log" 2>&1',
    "noctalia-scrcpy", pidPath, logPath, "scrcpy", <built args…> }
  ```
  `sh` writes its own PID, then `exec`s scrcpy → the PID file holds scrcpy's PID; stdout+stderr go to a
  log file in the plugin data dir. `$@` carries the scrcpy argv as positional parameters → **no user
  value ever reaches the shell parser**.
- **Stopping:** read the PID file → `kill -TERM <pid>` (shell builtin, no extra binary) → the manager
  polls `/proc/<pid>` and escalates to `SIGKILL` if it is still alive after ~2 s.
- **Liveness:** `noctalia.fileExists("/proc/" .. pid)`.
- **Error surfacing:** when the PID disappears, read the log file and surface its last non-empty line
  (e.g. `error: device '192.168.0.11:38377' not found`, `device unauthorized`).
- **Cleanup:** `manager.luau` defines `onExit(signal, reason)` and stops every session it owns when the
  plugin is disabled/uninstalled/reloaded (API 17). Sessions survive a Noctalia **SIGKILL** — documented
  in the README (stop them with the widget/panel or `pkill -f noctalia-scrcpy`).

### 2.3 Data flow

```
panel.luau ──state("cmd")──▶ manager.luau ──▶ adb / scrcpy processes
    ▲                             │
    └──state("sessions"|"devices")─┘   (noctalia.state.set, watched by panel + bar)
```

`noctalia.state` carries plain data only (strings/numbers/booleans/tables) — session records are
`{ id, kind, serial, state, error, pid, startedAtMs }`, device records are `{ serial, label, transport, model, state }`.

### 2.4 Settings model

- **Defaults** = manifest `[[setting]]` blocks → they appear in *Settings → Plugins* and are read with
  `noctalia.getConfig(key)`. A plugin can read but not write them.
- **Overrides** = a JSON file in `noctalia.pluginDataDir()` written by the panel (feature toggles,
  presets, known devices, last session). Effective value = override ?? default.
- The panel shows the effective value and offers "reset to defaults".

---

## 3. File layout (repo `ARES3940/noctalia-scrcpy`, plugin dir `scrcpy/`)

```
noctalia-scrcpy/
├── catalog.toml                 # generated by CI for the community repo; for our own repo we keep one
├── README.md                    # repo readme (source layout + install as a custom git source)
├── .luaurc                      # nonstrict mode
├── .gitignore                   # noctalia.d.luau, .venv, …
└── scrcpy/
    ├── plugin.toml              # manifest: id, name, version, plugin_api 53, entries, settings
    ├── README.md                # plugin page (registry requirement)
    ├── thumbnail.webp           # 960×540 (registry requirement)
    ├── translations/en.json     # every label_key/description_key
    ├── manager.luau             # [[service]] processes, adb, sessions, IPC dispatcher
    ├── bar.luau                 # [[widget]] state icon + quick actions
    ├── panel.luau               # [[panel]] devices, pairing, toggles, presets, sessions
    ├── shortcut.luau            # [[shortcut]] control-center tile
    ├── lib/
    │   ├── args.luau            # PURE: settings → argv array (the one true builder)
    │   ├── presets.luau         # PURE: the five presets
    │   ├── devices.luau         # PURE: parse `adb devices -l` / `adb mdns services`
    │   ├── errors.luau          # PURE: adb/scrcpy output → short readable message
    │   ├── theme.luau           # tokens (colours/sizes/copy) — palette roles only
    │   ├── shared.luau          # ui.* builders shared by panel + widget
    │   └── selftest.luau        # PURE: assertions over lib/args.luau fixtures
    └── assets/
        └── (icons/graphics if needed)
```

Local dev install (no registry): drop the `scrcpy/` directory into
`~/.local/share/noctalia/plugins/scrcpy/`, or add the repo as a `path` source:

```sh
noctalia msg plugins source add dev path ~/Projects/Xcreen/noctalia-scrcpy
noctalia msg plugins enable omen/scrcpy
```

---

## 4. Settings schema (manifest `[[setting]]`, plugin-level)

Defaults below; the panel writes overrides on top of them.

| key | type | default | notes |
| --- | --- | --- | --- |
| `device_serial` | string | `""` | last used device serial |
| `record_dir` | folder | `~/Videos` | where `--record` writes |
| `max_size` | int | `1024` | `--max-size` |
| `video_bit_rate` | int | `8000` | kbps → `--video-bit-rate` |
| `max_fps` | int | `60` | `--max-fps` |
| `video_codec` | select | `h264` | h264/h265/av1/vp8/vp9 |
| `video_encoder` | string | `""` | empty = device default |
| `video_buffer_ms` | int | `0` | `--video-buffer` |
| `audio_enabled` | bool | `true` | false → `--no-audio` |
| `audio_source` | select | `output` | 12 values from 5.0 |
| `audio_codec` | select | `opus` | opus/aac/flac/raw |
| `audio_bit_rate` | int | `128` | kbps |
| `audio_buffer_ms` | int | `50` | |
| `record_enabled` | bool | `false` | `--record` |
| `record_format` | select | `mp4` | mp4/mkv/m4a/mka/… |
| `record_only` | bool | `false` | `--no-playback --no-window` |
| `new_display` | bool | `false` | `--new-display` |
| `new_display_size` | string | `1920x1080` | `WxH` |
| `new_display_dpi` | int | `240` | |
| `vd_no_system_decorations` | bool | `false` | `--no-vd-system-decorations` |
| `start_app` | string | `""` | `--start-app` |
| `turn_screen_off` | bool | `false` | `--turn-screen-off` |
| `stay_awake` | bool | `true` | `--stay-awake` |
| `power_off_on_close` | bool | `false` | |
| `screen_off_timeout` | int | `0` | 0 = leave device value |
| `clipboard_autosync` | bool | `true` | false → `--no-clipboard-autosync` |
| `show_touches` | bool | `false` | `--show-touches` |
| `no_control` | bool | `false` | `--no-control` |
| `video_source` | select | `display` | display/camera |
| `camera_facing` | select | `back` | front/back/external |
| `camera_size` | string | `""` | e.g. `1920x1080` |
| `camera_id` | string | `""` | |
| `camera_fps` | int | `0` | 0 = device default |
| `v4l2_enabled` | bool | `false` | webcam preset |
| `v4l2_sink` | string | `/dev/video10` | `--v4l2-sink` |
| `keyboard_mode` | select | `disabled` | disabled/sdk/uhid/aoa |
| `mouse_mode` | select | `disabled` | disabled/sdk/uhid/aoa |
| `gamepad_mode` | select | `disabled` | disabled/uhid/aoa |
| `otg` | bool | `false` | **USB only** |
| `always_on_top` | bool | `false` | `--always-on-top` |
| `fullscreen` | bool | `false` | `-f` |
| `window_title` | string | `noctalia-scrcpy` | `--window-title` (also the Hyprland rule hook) |
| `window_width` / `window_height` | int | `0` | 0 = automatic |
| `display_id` | int | `0` | `--display-id` |
| `orientation` | select | `0` | 0/90/180/270 |

### Presets (implemented in `lib/presets.luau`, applied as overrides)

| Preset | Effect |
| --- | --- |
| **Default** | manifest defaults, audio on, display mirror |
| **Gaming** | `--max-fps 60`, `--video-bit-rate 12M`, `--video-buffer 0`, `--audio-buffer 20`, `stay_awake`, keyboard/mouse `uhid` |
| **Low bandwidth** | `--max-size 480`, `--video-bit-rate 1M`, `--max-fps 15`, `--no-audio`, `--video-codec h264` |
| **Webcam** | `--video-source camera --camera-facing back`, `--v4l2-sink /dev/video10`, `--no-window` |
| **Record only** | `--record <dir>/<name>.mp4`, `--no-playback --no-window`, no control |

### Feature gating (with the reason shown in the UI)

| Option | Disabled when | Reason text shown |
| --- | --- | --- |
| `--otg`, `--keyboard=aoa`, `--mouse=aoa`, `--gamepad=aoa` | device is not USB | "AOA/OTG needs a USB connection" |
| `--v4l2-sink` | no `/dev/videoN` loopback, or the node is not writable | "No writable V4L2 loopback device" |
| camera options | device Android < 12 | "Camera mirroring needs Android 12+" |
| `--new-display` | device Android < 14 | "Virtual display needs Android 14+" |
| `--max-fps` | device Android < 10 | "Frame-rate limit needs Android 10+" |
| everything | `scrcpy`/`adb` missing | "scrcpy not found" / "adb not found" |

Device "USB-ness" is decided by the adb serial: a serial containing `:` (ip:port) or an mDNS
`._adb-tls-connect._tcp` name = **wireless**; anything else = USB.

---

## 5. Error handling (short, readable)

| Condition | Message |
| --- | --- |
| `scrcpy` not on PATH | "scrcpy not found — install the scrcpy package" |
| `adb` not on PATH | "adb not found — install android-tools" |
| device `unauthorized` | "Device unauthorized — accept the ADB prompt on the phone" |
| device `offline` | "Device offline — reconnect the phone" |
| stale port / not found | "Wireless port changed — rediscovering" → re-runs mdns, offers **Reconnect** |
| `adb pair` fails | "Pairing failed: <last line of adb output>" |
| scrcpy exits | "scrcpy exited: <last log line>" |
| v4l2 sink busy | "V4L2 device busy — pick another loopback node" |

---

## 6. Session-by-session plan (one branch + one PR per session)

Branch naming `session/N-<slug>`; each PR targets `main` in `ARES3940/noctalia-scrcpy`.
Every session ends with the plugin **enabled and manually verified** in the running Noctalia.

| # | Goal | Files | Done when |
| --- | --- | --- | --- |
| **1** | Repo + manifest + skeleton UI | `plugin.toml`, `translations/en.json`, `lib/theme.luau`, `lib/shared.luau`, `bar.luau`, `panel.luau`, `shortcut.luau`, `manager.luau` (stub), `README.md`, `thumbnail.webp`, `catalog.toml` | Plugin enables with `plugin_api = 53` (this also verifies the installed binary's real supported range), bar widget shows a placeholder icon, panel opens with a themed placeholder |
| **2** | Pure arg builder + presets + self-test | `lib/args.luau`, `lib/presets.luau`, `lib/selftest.luau`, panel "effective args" row | Self-test service logs PASS for all fixtures; panel shows the exact argv for the current settings |
| **3** | Device layer | `lib/devices.luau`, manager adb calls, panel device list + pair form, known-device persistence | Pairing walkthrough works against the real phone; device list shows the Redmi Note 7 once (dedup verified) |
| **4** | Session manager | manager launch/stop/liveness/log, session records, panel session list, cleanup on exit | A real mirror starts over wifi, stops cleanly, and a deliberate bad serial shows "scrcpy exited: …" |
| **5** | Feature toggles + gating | `lib/args.luau` (all flags), panel toggle/select rows, gating + reasons | Every flag in the brief's table is reachable; USB-only and V4L2 rows are greyed out with reasons |
| **6** | Presets + overrides persistence | `lib/presets.luau` wiring, override JSON, panel preset buttons, reset-to-defaults | The five presets produce the documented argv; overrides survive a plugin reload |
| **7** | Bar states, quick actions, IPC, docs | `bar.luau` states, right-click context menu, `onIpc` handlers, README (install, pairing walkthrough, feature table, known limits, Hyprland window rules), thumbnail | Widget shows disconnected/connected/mirroring/recording; `noctalia msg plugin omen/scrcpy:manager all …` works; README complete |

Optional **PR #8**: open the publication PR against `noctalia-dev/community-plugins` (single PR,
plugin dir `scrcpy/`, `translations/en.json`, `thumbnail.webp`, README).

---

## 7. Testing strategy — real vs reasoned

**Tested for real in Phase 0:** Noctalia version/API range, plugin directory layout, existing plugin
conventions, scrcpy 5.0.1 `--help`/`--version`, adb 37 CLI surface, `adb devices -l` (device present),
`adb mdns services` (service found), `adb connect`/`disconnect` (duplicate-serial behaviour), device
Android/model props, v4l2loopback state and `/dev/video10`, Noctalia source facts (5 s callback timeout,
detached semantics, 32-command cap, no PID handle, no screencopy API), registry validator rules.

**Will be tested for real during implementation (a phone is available):** pairing flow, connect,
mirror start/stop, recording to a file, camera source, virtual display, HID modes, error paths
(unauthorized/offline/stale port), multi-session (mirror + camera), V4L2 sink.

**Reasoned only, cannot be tested here / needs the phone or a plugin reload:** the Noctalia-specific
mechanics — the `noctalia.state` command bus, detached launch + PID-file mechanics under the plugin
runtime, `onExit` cleanup, panel/widget re-render behaviour on state change.

**No test runner is installed** (no `luau`, `luau-analyze`, `lune`) and package installs are out of
scope → unit tests are implemented as `lib/selftest.luau`, run by a service entry that logs
`PASS/FAIL` into the Noctalia log (Session 2). This is the honest "unit-test it if feasible" answer
for this box.

---

## 8. Risks

| Risk | Mitigation |
| --- | --- |
| The brief's QML architecture is not publishable | Rewritten in Luau (Section 0); verified against the registry README |
| `plugin_api = 53` drops Noctalia v5.4.x users | Explicit choice ("use the latest API"); a brand-new plugin has no older revision for a `[[plugin.release]]` catalog fallback. Keeping 43 would retain v5.4.x — raise if compatibility matters more. |
| Scrcpy 5.0 is a new major vs the brief's expectations | Every flag re-verified against the installed binary (Section 1.5); builder defaults are conservative |
| `runAsync` callback path kills long processes at 5 s | Detached launch + PID file (Section 2.2); validated by the self-test + a real session test |
| Detached scrcpy survives a Noctalia SIGKILL | `onExit` cleanup for graceful paths; README documents manual cleanup |
| Plugin cannot write its own manifest settings | Overrides JSON in `pluginDataDir()`; manifest defaults stay read-only |
| Cross-entry command bus is unconventional (`noctalia.state` used for commands) | Purely internal, documented; IPC path (`onIpc`) is the public interface and shares the same dispatcher |
| `/dev/video10` is androidconnect's preview device | Our V4L2 default is configurable and the README warns about the clash |
| `scrcpy` window placement on Hyprland | Not touched (per the brief); README documents optional `windowrule` snippets |
| Registry CI (English prose, thumbnail 960×540, translation keys) | Checked against `validate-plugins.py` before each PR |

---

## 9. Open questions (to resolve in order)

1. **Plugin id / repo owner.** The GitHub account available to me is `ARES3940`, but the existing plugin
   uses the author id `omen`. Default in this plan: **id `omen/scrcpy`**, repo `ARES3940/noctalia-scrcpy`
   (the only account I can create repos/PRs with). The registry convention is "the author part is your
   GitHub handle", so `ares3940/scrcpy` is the cleaner publishable choice — **your call.**
2. **Live panel thumbnail**: dropped (no API exists). Alternative if wanted: a v4l2loopback +
   `ui.pixelStream` companion (needs `python3`/`ffmpeg`, breaking the "scrcpy + adb only" rule).
3. **Registry publication target**: publish to `noctalia-dev/community-plugins` (one PR at the end),
   or keep it a personal git source only?

---

## 10. Publishing checklist (community-plugins)

- [ ] `scrcpy/plugin.toml` — valid manifest, **`plugin_api = 53`**, `description` ≤ 120 chars
- [ ] `scrcpy/translations/en.json` — every `label_key`/`description_key` resolves
- [ ] `scrcpy/thumbnail.webp` — exactly 960×540, ≤ 512 KB
- [ ] `scrcpy/README.md` — English, `Plugin` table, usage, requirements (exact dependency names),
      settings, IPC, notes, and the `noctalia msg panel-toggle <id>` command
- [ ] `dependencies` lists every external command used (`adb`, `scrcpy`)
- [ ] `catalog.toml` — generated by CI, not hand-edited
- [ ] Optional `noctalia.d.luau` fetch for luau-lsp (gitignored)

---

## 11. Non-goals (agreed in the brief)

- No `sudo`, no package installs, no kernel module changes, no Hyprland config edits.
- No reimplementation of scrcpy features — we only build argument vectors.
- No QML, no Quickshell, no `qs` subprocess.
- Dependencies stay at `adb` + `scrcpy` (plus `/bin/sh` for PID-file process control, documented).
