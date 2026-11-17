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
    subtitle = 10.5,
    section = 9.5,
    body = 12,
    micro = 9.5,
    value = 11,
    barLabel = 10,
    icon = 14,
    dot = 5,
    accentWidth = 2,
    accentHeight = 16,
    radius = 6,
    cardRadius = 5,
    pillRadius = 4,
}

T.color = {
    text = "on_surface",
    muted = "on_surface_variant",
    accent = "primary",
    card = "surface_container/0.55",
    cardBorder = "outline_variant/0.35",
    overlay = "surface_container_high/0.45",
    track = "on_surface/0.10",
    error = "error",
    success = "tertiary",
    warning = "secondary",
}

T.tone = {
    info = "primary",
    success = "tertiary",
    warning = "secondary",
    error = "error",
}

T.layout = {
    panelGap = 10,
    panelPadding = 12,
    cardGap = 7,
    cardPadding = 10,
    rowGap = 4,
    labelWidth = 100,
    valueWidth = 76,
}

T.copy = {
    title = "SCRCPY",
    noDevice = "No device selected",
    noDevices = "No devices found",
    devices = "DEVICES",
    sessions = "SESSIONS",
    presets = "PRESETS",
    pairing = "PAIR A NEW PHONE",
    remembered = "REMEMBERED",
    features = "FEATURES",
    noSessions = "No active sessions",
    stop = "STOP",
    settings = "PLUGIN SETTINGS",
}

T.status = {
    disconnected = { color = "on_surface_variant", glyph = "device-mobile-off", label = "OFFLINE" },
    connected = { color = "tertiary", glyph = "device-mobile", label = "READY" },
    mirroring = { color = "primary", glyph = "device-mobile", label = "MIRRORING" },
    recording = { color = "error", glyph = "player-record", label = "REC" },
}

T.kind = {
    mirror = { glyph = "device-mobile", label = "MIRROR", color = "primary" },
    record = { glyph = "player-record", label = "RECORD", color = "error" },
    camera = { glyph = "camera", label = "CAMERA", color = "primary" },
    webcam = { glyph = "video", label = "WEBCAM", color = "primary" },
}

return T
