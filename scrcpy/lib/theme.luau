--!nonstrict
-- Presentation tokens for omen/scrcpy.
-- One place for colour roles, type, density, copy and status glyphs.
-- Colours are Noctalia palette roles only; nothing is hard-coded.

local T = {}

T.font = {
    label = "Noto Sans",
    value = "Noto Sans Mono",
}

T.size = {
    panelTitle = 14,
    section = 10,
    body = 12,
    micro = 10,
    value = 11,
    barLabel = 10.5,
    dot = 6,
    accentWidth = 2,
    accentHeight = 14,
    radius = 3,
}

T.color = {
    text = "on_surface",
    muted = "on_surface_variant",
    accent = "primary",
    cardFill = "surface_container/0.88",
    cardBorder = "on_surface/0.16",
    track = "on_surface/0.10",
    error = "error",
    success = "tertiary",
}

T.layout = {
    panelGap = 8,
    cardGap = 6,
    cardPadding = 10,
    sectionGap = 4,
    labelWidth = 96,
    rowGap = 6,
}

T.copy = {
    panelTitle = "SCRCPY",
    subtitle = "WIRELESS ADB",
    noDevices = "No devices — open pairing to add one",
    devices = "DEVICES",
    sessions = "SESSIONS",
    pairing = "PAIRING",
    presets = "PRESETS",
    noSessions = "No active sessions",
    connecting = "CONNECTING",
    refresh = "REFRESH",
    pair = "PAIR",
    stop = "STOP",
    start = "START",
    openSettings = "SETTINGS",
    build = "Scaffold ready",
}

T.status = {
    disconnected = { color = "on_surface_variant", glyph = "device-mobile-off", label = "OFFLINE" },
    connected = { color = "tertiary", glyph = "device-mobile", label = "READY" },
    mirroring = { color = "primary", glyph = "video", label = "MIRRORING" },
    recording = { color = "error", glyph = "player-record", label = "REC" },
}

return T
