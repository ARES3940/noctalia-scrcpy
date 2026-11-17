# noctalia-scrcpy

Development repo for [`omen/scrcpy`](scrcpy/README.md), a Noctalia v5 Luau plugin that controls
[scrcpy](https://github.com/Genymobile/scrcpy) over wireless ADB.

The plugin itself lives in [`scrcpy/`](scrcpy/); that directory is the unit published to the Noctalia
community plugin registry. The design and session plan are in [`docs/PLAN.md`](docs/PLAN.md).

## Layout

```
scrcpy/                  plugin directory (id: omen/scrcpy, plugin_api 53)
  plugin.toml            manifest, entries, setting schema
  README.md              plugin store page
  thumbnail.webp         960x540 store artwork
  translations/en.json   setting labels
  manager.luau           service: processes, adb, sessions, IPC
  bar.luau               bar widget
  panel.luau             panel
  shortcut.luau          control-center shortcut
  lib/                   pure helpers (args, presets, theme, UI)
docs/PLAN.md             research findings and session-by-session plan
```

## Develop locally

Add this checkout as a `path` source and enable the plugin:

```sh
noctalia msg plugins source add dev path ~/Projects/Xcreen
noctalia msg plugins enable omen/scrcpy
```

`.luau` edits hot-reload. Manifest changes need `noctalia msg config-reload`. To check declared
settings against actual `getConfig()` calls:

```sh
noctalia plugins lint scrcpy
```

## Sessions

One branch and one pull request per session, targeting `main`:

1. Scaffold (this state) — manifest, theme, skeleton UI, thumbnail, plan
2. Pure `settings → argv` builder + presets + self-test
3. Device layer — mdns discovery, pairing, connect, dedupe, known devices
4. Session manager — launch/stop, liveness, errors, multiple sessions
5. Feature toggles and gating (USB-only, V4L2)
6. Presets and persisted overrides
7. Bar states, quick actions, IPC handlers, README polish
8. Publication PR to `noctalia-dev/community-plugins` (one PR, `scrcpy/` directory)

## Requirements

- Noctalia v5.5.0+ (plugin API 53)
- `adb` and `scrcpy` on the computer; no other runtime dependencies
- Python is **not** required; the plugin is pure Luau

## License

MIT — see the plugin's `plugin.toml`. No code was reused from GPL-licensed Noctalia plugins.
