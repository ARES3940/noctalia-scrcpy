--!nonstrict
-- omen/scrcpy panel: devices, pairing, per-feature toggles, sessions, argv preview.
local S = require("./lib/shared.luau")
local T = S.T
local A = require("./lib/args.luau")
local Devices = require("./lib/devices.luau")

local pairHost = ""
local pairCode = ""

local function setFeature(key, value)
    S.send("set-feature", { key = key, value = value })
end

local function featureRow(key, label, control)
    local blocked = noctalia.state.get("blocked") or {}
    local hints = noctalia.state.get("hints") or {}
    local reason = blocked[key]
    local children = {
        S.micro(label, reason and "on_surface/0.45" or T.color.muted, 84),
    }
    if control then table.insert(children, control) end
    if reason then
        table.insert(children, ui.label({
            text = reason, fontSize = T.size.micro, fontFamily = T.font.label,
            color = T.color.error, maxLines = 2, flexGrow = 1,
        }))
    elseif hints[key] then
        table.insert(children, ui.label({
            text = hints[key], fontSize = T.size.micro, fontFamily = T.font.label,
            color = T.color.error, maxLines = 1, flexGrow = 1,
        }))
    end
    return ui.row({ gap = 6, align = "center" }, children)
end

local function toggleRow(key, label)
    local effective = noctalia.state.get("effective") or {}
    local blocked = noctalia.state.get("blocked") or {}
    return featureRow(key, label, ui.toggle({
        checked = effective[key] == true,
        enabled = blocked[key] == nil,
        controlSize = "sm",
        onChange = function(value) setFeature(key, value == "true") end,
    }))
end

local function selectRow(key, label, options)
    local effective = noctalia.state.get("effective") or {}
    local blocked = noctalia.state.get("blocked") or {}
    local selected = tostring(effective[key] or options[1])
    local index = 0
    for i, option in ipairs(options) do
        if option == selected then index = i - 1 end
    end
    return featureRow(key, label, ui.select({
        options = options,
        selectedIndex = index,
        enabled = blocked[key] == nil,
        controlSize = "sm",
        flexGrow = 1,
        onChange = function(value)
            local i = (tonumber(value) or 0) + 1
            setFeature(key, options[i] or options[1])
        end,
    }))
end

local function sliderRow(key, label, minValue, maxValue, stepValue)
    local effective = noctalia.state.get("effective") or {}
    local blocked = noctalia.state.get("blocked") or {}
    return featureRow(key, label, ui.slider({
        min = minValue, max = maxValue, step = stepValue,
        value = tonumber(effective[key]) or minValue,
        enabled = blocked[key] == nil,
        controlSize = "sm",
        flexGrow = 1,
        onChange = function(value) setFeature(key, tonumber(value) or minValue) end,
    }))
end

local function deviceRows(devices)
    if type(devices) ~= "table" or #devices == 0 then
        return { S.empty(T.copy.noDevices) }
    end
    local rows = {}
    for _, device in ipairs(devices) do
        local state = device.state == "device" and "connected" or "disconnected"
        table.insert(rows, S.card({
            ui.row({ gap = 6, align = "center" }, {
                S.dot(state),
                ui.column({ gap = 1, flexGrow = 1 }, {
                    S.value(Devices.label(device)),
                    S.micro(device.wireless and "WIRELESS" or "USB", T.color.muted),
                }),
                ui.button({
                    text = "USE", variant = "outline", controlSize = "sm",
                    enabled = device.state == "device",
                    onClick = function() S.send("connect", { serial = device.serial }) end,
                }),
            }),
        }))
    end
    return rows
end

local function sessionRows(sessions)
    if type(sessions) ~= "table" or #sessions == 0 then
        return { S.empty(T.copy.noSessions) }
    end
    local rows = {}
    for _, session in ipairs(sessions) do
        table.insert(rows, S.card({
            ui.row({ gap = 6, align = "center" }, {
                S.dot(session.state == "recording" and "recording" or "mirroring"),
                S.value(session.kind or "mirror"),
                ui.spacer({ flexGrow = 1 }),
                S.micro(session.state or "?", T.color.muted, 56),
                ui.button({
                    text = "STOP", variant = "outline", controlSize = "sm",
                    onClick = function() S.send("stop", { id = session.id }) end,
                }),
            }),
            S.errorLine(session.error),
        }))
    end
    return rows
end

local function argsRow()
    local effective = noctalia.state.get("effective") or {}
    local argv = A.build({ settings = effective })
    local test = noctalia.state.get("selftest") or {}
    return S.card({
        ui.row({ gap = 6, align = "center" }, {
            S.micro("ARGV PREVIEW"),
            ui.spacer({ flexGrow = 1 }),
            S.micro(tostring(test.passed or 0) .. " PASS / " .. tostring(test.failed or 0) .. " FAIL",
                (test.failed or 0) > 0 and T.color.error or T.color.success),
        }),
        ui.label({
            text = A.preview(argv), fontSize = T.size.micro, fontFamily = T.font.value,
            color = T.color.muted, maxLines = 3,
        }),
    })
end

local function render()
    local devices = noctalia.state.get("devices") or {}
    local sessions = noctalia.state.get("sessions") or {}
    local notice = noctalia.state.get("notice")
    local blocked = noctalia.state.get("blocked") or {}

    local children = {
        S.header(T.copy.panelTitle, S.micro(T.copy.subtitle, T.color.accent)),
        S.errorLine(blocked.all),
        S.sectionRule(),

        S.micro(T.copy.devices),
        ui.column({ gap = T.layout.rowGap }, deviceRows(devices)),

        ui.row({ gap = 8, align = "center" }, {
            ui.button({
                text = T.copy.refresh, variant = "outline", controlSize = "sm",
                onClick = function() S.send("refresh") end,
            }),
            ui.spacer({ flexGrow = 1 }),
        }),

        S.sectionRule(),
        S.micro(T.copy.pairing),
        S.card({
            ui.input({
                key = "pair-host", value = pairHost, placeholder = "192.168.0.11:41645",
                controlSize = "sm", onChange = function(value) pairHost = value end,
            }),
            ui.input({
                key = "pair-code", value = pairCode, placeholder = "123456",
                controlSize = "sm", onChange = function(value) pairCode = value end,
            }),
            ui.button({
                text = T.copy.pair, variant = "primary", controlSize = "sm",
                onClick = function() S.send("pair", { host = pairHost, code = pairCode }) end,
            }),
        }),

        S.sectionRule(),
        S.micro("FEATURES"),
        sliderRow("max_size", "MAX SIZE", 240, 4096, 8),
        sliderRow("video_bit_rate", "VIDEO KBPS", 100, 20000, 100),
        sliderRow("max_fps", "MAX FPS", 1, 120, 1),
        selectRow("video_codec", "CODEC", { "h264", "h265", "av1", "vp8", "vp9" }),
        toggleRow("audio_enabled", "AUDIO"),
        toggleRow("record_enabled", "RECORD"),
        toggleRow("record_only", "RECORD ONLY"),
        toggleRow("new_display", "VIRTUAL DISPLAY"),
        toggleRow("turn_screen_off", "SCREEN OFF"),
        toggleRow("stay_awake", "STAY AWAKE"),
        toggleRow("clipboard_autosync", "CLIPBOARD"),
        selectRow("video_source", "SOURCE", { "display", "camera" }),
        selectRow("camera_facing", "CAMERA", { "front", "back", "external" }),
        toggleRow("v4l2_enabled", "WEBCAM"),
        selectRow("keyboard_mode", "KEYBOARD", { "disabled", "sdk", "uhid", "aoa" }),
        selectRow("mouse_mode", "MOUSE", { "disabled", "sdk", "uhid", "aoa" }),
        toggleRow("otg", "OTG (USB)"),

        S.sectionRule(),
        S.micro(T.copy.sessions),
        ui.row({ gap = 6, align = "center" }, {
            ui.button({
                text = "START", variant = "primary", controlSize = "sm",
                onClick = function() S.send("start", { kind = "mirror" }) end,
            }),
            ui.button({
                text = "RECORD", variant = "outline", controlSize = "sm",
                onClick = function() S.send("start-recording") end,
            }),
            ui.button({
                text = "CAMERA", variant = "outline", controlSize = "sm",
                onClick = function()
                    S.send("start", { kind = "camera", settings = { video_source = "camera" } })
                end,
            }),
        }),
        ui.column({ gap = T.layout.rowGap }, sessionRows(sessions)),

        S.sectionRule(),
        argsRow(),
        ui.button({
            text = "COPY ARGS", variant = "ghost", controlSize = "sm",
            onClick = function()
                local argv = A.build({ settings = noctalia.state.get("effective") or {} })
                noctalia.copyToClipboard(A.preview(argv), "text/plain")
            end,
        }),
        S.errorLine(notice),
        S.sectionRule(),
        ui.button({
            text = T.copy.openSettings, variant = "ghost", controlSize = "sm",
            onClick = function() noctalia.openSettings() end,
        }),
    }

    panel.render(ui.column({
        gap = T.layout.panelGap, padding = 12,
        fill = "surface_container/0.75", radius = T.size.radius,
    }, {
        ui.scroll({ flexGrow = 1, gap = T.layout.panelGap }, children),
    }))
end

function onOpen(context)
    S.send("panel-open")
    render()
end

function onClose()
    S.send("panel-close")
end

for _, key in ipairs({ "devices", "sessions", "notice", "effective", "blocked", "hints", "capabilities" }) do
    noctalia.state.watch(key, render)
end
render()
