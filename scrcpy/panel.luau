--!nonstrict
-- omen/scrcpy panel: one controller over three tabs (control / devices / settings).
--
-- Everything here is declarative. The panel never touches adb or scrcpy: it
-- publishes commands on the state bus (lib/shared.luau) and renders the
-- service's published state. Panel-local state is limited to the active tab,
-- draft slider values, text being typed and a few confirmations.

local S = require("./lib/shared.luau")
local T = S.T
local A = require("./lib/args.luau")
local Devices = require("./lib/devices.luau")
local Presets = require("./lib/presets.luau")

local open = false
local activeTab = "control"
local advancedOpen = false
local showCommand = false
local edit = {} -- draft slider values, cleared when the preset changes
local lastPreset = nil
local confirmResetAt = 0
local pairHost = ""
local pairCode = ""
local connectAddr = ""

local TABS = {
    { id = "control", label = "CONTROL" },
    { id = "devices", label = "DEVICES" },
    { id = "settings", label = "SETTINGS" },
}

local render -- forward declaration: click handlers repaint the panel

local CODECS = {
    { value = "h264", label = "H.264" },
    { value = "h265", label = "H.265" },
    { value = "av1", label = "AV1" },
    { value = "vp8", label = "VP8" },
    { value = "vp9", label = "VP9" },
}

local AUDIO_SOURCES = {
    { value = "output", label = "Device output" },
    { value = "playback", label = "Playback" },
    { value = "mic", label = "Microphone" },
    { value = "mic-unprocessed", label = "Mic · unprocessed" },
    { value = "mic-camcorder", label = "Mic · camcorder" },
    { value = "mic-voice-recognition", label = "Mic · voice recognition" },
    { value = "mic-voice-communication", label = "Mic · voice chat" },
    { value = "voice-call", label = "Voice call" },
    { value = "voice-call-uplink", label = "Voice call · uplink" },
    { value = "voice-call-downlink", label = "Voice call · downlink" },
    { value = "mic-performance", label = "Mic · performance" },
    { value = "voice-performance", label = "Voice · performance" },
}

local AUDIO_CODECS = {
    { value = "opus", label = "Opus" },
    { value = "aac", label = "AAC" },
    { value = "flac", label = "FLAC" },
    { value = "raw", label = "Raw" },
}

local RECORD_FORMATS = {
    { value = "mp4", label = "MP4" },
    { value = "mkv", label = "MKV" },
    { value = "m4a", label = "M4A" },
    { value = "mka", label = "MKA" },
    { value = "opus", label = "Opus" },
    { value = "aac", label = "AAC" },
    { value = "flac", label = "FLAC" },
    { value = "wav", label = "WAV" },
}

local VIDEO_SOURCES = {
    { value = "display", label = "Display" },
    { value = "camera", label = "Camera" },
}

local FACINGS = {
    { value = "back", label = "Back" },
    { value = "front", label = "Front" },
    { value = "external", label = "External" },
}

local KEYBOARD_MODES = {
    { value = "disabled", label = "Off" },
    { value = "sdk", label = "SDK" },
    { value = "uhid", label = "UHID" },
    { value = "aoa", label = "AOA" },
}

local MOUSE_MODES = KEYBOARD_MODES

local GAMEPAD_MODES = {
    { value = "disabled", label = "Off" },
    { value = "uhid", label = "UHID" },
    { value = "aoa", label = "AOA" },
}

local ORIENTATIONS = {
    { value = "0", label = "Natural" },
    { value = "90", label = "90°" },
    { value = "180", label = "180°" },
    { value = "270", label = "270°" },
}

-- ── state ────────────────────────────────────────────────────────────────────

local function snapshot()
    return {
        devices = noctalia.state.get("devices") or {},
        selected = tostring(noctalia.state.get("selected") or ""),
        sessions = noctalia.state.get("sessions") or {},
        eff = noctalia.state.get("effective") or {},
        caps = noctalia.state.get("capabilities") or {},
        blocked = noctalia.state.get("blocked") or {},
        hints = noctalia.state.get("hints") or {},
        notice = noctalia.state.get("notice"),
        preset = tostring(noctalia.state.get("activePreset") or "Default"),
        hasLast = noctalia.state.get("hasLast") == true,
        known = noctalia.state.get("known") or {},
    }
end

local function setFeature(key, value)
    S.send("set-feature", { key = key, value = value })
end

local function statusOf(st)
    return S.statusOf(st.sessions, st.selected, st.devices)
end

local function selectedDevice(st)
    return Devices.find(st.devices, st.selected)
end

local function activeSessions(st)
    return S.activeSessions(st.sessions)
end

local function toneColor(tone)
    return T.tone[tone or "info"] or T.tone.info
end

-- ── small builders ───────────────────────────────────────────────────────────

local function note(text, color, maxLines)
    return S.note(text, color, maxLines)
end

local function section(title, trailing)
    return S.sectionHead(title, trailing)
end

local function chip(text, color)
    return S.badge(text, color)
end

local function divider()
    return ui.separator({ thickness = 1, color = T.color.text, opacity = 0.10, spacing = 0 })
end

local function iconButton(glyph, tooltip, onClick, variant)
    return S.iconButton(glyph, tooltip, onClick, variant)
end

-- ── header / tabs / notice ───────────────────────────────────────────────────

local function header(st)
    local def = S.statusDef(statusOf(st))
    local device = selectedDevice(st)
    local subtitle
    if device then
        local address = tostring(device.endpoint or "")
        if address == "" then address = device.wireless and "Wireless" or "USB" end
        subtitle = Devices.label(device) .. " · " .. address
    elseif #st.devices > 0 then
        subtitle = "Select a device"
    else
        subtitle = "Wireless ADB"
    end

    local trailing = {
        S.pill(def.label, def.color),
        iconButton("video", "Open embedded preview", function()
            if noctalia.state.get("screenOpen") ~= true then
                S.send("preview-open")
                noctalia.togglePanel("omen/scrcpy:screen")
            end
        end),
        iconButton("refresh", "Rescan devices", function()
            S.send("refresh")
        end),
    }
    if noctalia.getSetting("shell.show_close_buttons") ~= false then
        trailing[#trailing + 1] = iconButton("x", "Close", function()
            panel.close()
        end)
    end

    return ui.row({ align = "center", justify = "space_between", gap = 8 }, {
        ui.row({ align = "center", gap = 8, flexGrow = 1 }, {
            ui.box({ width = 3, height = 22, fill = T.color.accent, radius = 2 }),
            ui.column({ gap = 0, flexGrow = 1 }, {
                ui.label({
                    text = T.copy.title,
                    fontSize = T.size.panelTitle,
                    fontFamily = T.font.label,
                    fontWeight = "bold",
                    color = T.color.text,
                    maxLines = 1,
                }),
                ui.label({
                    text = subtitle,
                    fontSize = T.size.micro,
                    fontFamily = T.font.value,
                    color = T.color.muted,
                    maxLines = 1,
                    maxWidth = 220,
                }),
            }),
        }),
        ui.row({ align = "center", gap = 4 }, trailing),
    })
end

local function tabButton(tab)
    local active = activeTab == tab.id
    return ui.column({
        key = "tab-" .. tab.id,
        flexGrow = 1,
        align = "center",
        gap = 4,
        paddingV = 6,
        radius = T.size.cardRadius,
        fill = active and (T.color.accent .. "/0.08") or nil,
        onClick = function()
            if activeTab ~= tab.id then
                activeTab = tab.id
                render()
            end
        end,
    }, {
        ui.label({
            text = tab.label,
            fontSize = T.size.micro,
            fontFamily = T.font.label,
            fontWeight = "bold",
            color = active and T.color.accent or T.color.muted,
            maxLines = 1,
        }),
        ui.box({
            width = 18,
            height = 2,
            radius = 1,
            fill = active and T.color.accent or T.color.text,
            opacity = active and 1 or 0,
        }),
    })
end

local function tabs()
    local children = {}
    for _, tab in ipairs(TABS) do children[#children + 1] = tabButton(tab) end
    return ui.column({ gap = 2 }, {
        ui.row({ gap = 2, align = "stretch" }, children),
        divider(),
    })
end

local function noticeNode(st)
    local n = st.notice
    if type(n) ~= "table" or tostring(n.text or "") == "" then return nil end
    local color = toneColor(n.tone)
    return ui.row({
        key = "notice",
        align = "center",
        gap = 7,
        paddingH = 8,
        paddingV = 6,
        radius = T.size.cardRadius,
        fill = color .. "/0.10",
        border = color .. "/0.30",
        borderWidth = 1,
    }, {
        ui.glyph({
            name = n.tone == "error" and "alert-circle" or "info-circle",
            size = 13,
            color = color,
        }),
        ui.label({
            text = tostring(n.text),
            fontSize = T.size.micro,
            fontFamily = T.font.label,
            color = color,
            flexGrow = 1,
            maxLines = 2,
        }),
        iconButton("x", "Dismiss", function()
            S.send("clear-notice")
            render()
        end),
    })
end

-- ── control tab ──────────────────────────────────────────────────────────────

local function launchKind(kind, extras)
    S.send("start", { kind = kind, extras = extras })
    render()
end

local function launchCard(st)
    local device = selectedDevice(st)
    local ready = Devices.isReady(device)
    local blocked = st.blocked
    local canLaunch = ready and blocked.all == nil and blocked.device == nil
    local cameraBlocked = blocked.video_source

    local deviceLine
    if device then
        local badges = {
            chip(device.wireless and "WIFI" or "USB", device.wireless and "primary" or "tertiary"),
        }
        deviceLine = ui.row({ align = "center", gap = 8 }, {
            ui.glyph({
                name = ready and "device-mobile" or "device-mobile-off",
                size = 18,
                color = ready and T.color.accent or T.color.muted,
            }),
            ui.column({ gap = 1, flexGrow = 1 }, {
                ui.label({
                    text = Devices.label(device),
                    fontSize = 12.5,
                    fontFamily = T.font.label,
                    fontWeight = "semibold",
                    color = T.color.text,
                    maxLines = 1,
                }),
                ui.label({
                    text = device.endpoint ~= "" and tostring(device.endpoint) or tostring(device.serial),
                    fontSize = T.size.micro,
                    fontFamily = T.font.value,
                    color = T.color.muted,
                    maxLines = 1,
                }),
            }),
            ui.row({ gap = 4, align = "center" }, badges),
        })
    else
        deviceLine = ui.row({ align = "center", gap = 8 }, {
            ui.glyph({ name = "device-mobile-off", size = 18, color = T.color.muted }),
            ui.column({ gap = 1, flexGrow = 1 }, {
                ui.label({
                    text = #st.devices > 0 and "Select a device" or T.copy.noDevice,
                    fontSize = 12.5,
                    fontFamily = T.font.label,
                    fontWeight = "semibold",
                    color = T.color.text,
                    maxLines = 1,
                }),
                note(#st.devices > 0
                    and "Open Devices and pick the phone to control"
                    or "Pair a phone over wireless ADB to begin"),
            }),
            ui.button({
                text = "DEVICES",
                variant = "outline",
                controlSize = "sm",
                onClick = function()
                    activeTab = "devices"
                    render()
                end,
            }),
        })
    end

    local mirror = ui.button({
        text = "START MIRROR",
        glyph = "player-play",
        variant = "primary",
        controlSize = "md",
        enabled = canLaunch,
        tooltip = canLaunch and "Mirror the phone inside the embedded preview panel" or (blocked.all or blocked.device),
        onClick = function()
            S.send("start-embedded")
        end,
    })

    local function quick(text, glyph, kind, extras, enabled, tooltip)
        return ui.button({
            text = text,
            glyph = glyph,
            variant = "outline",
            controlSize = "sm",
            flexGrow = 1,
            enabled = enabled,
            tooltip = tooltip,
            onClick = function() launchKind(kind, extras) end,
        })
    end

    local v4l2Ready = st.caps.v4l2Writable == true
    local windowButton = ui.button({
        text = "WINDOW",
        glyph = "external-link",
        variant = "default",
        controlSize = "sm",
        flexGrow = 1,
        enabled = canLaunch,
        tooltip = "Open a native scrcpy window instead of the embedded preview",
        onClick = function() launchKind("mirror") end,
    })
    local quickRow = ui.column({ gap = 5 }, {
        ui.row({ gap = 5, align = "stretch" }, {
            quick("REC", "player-record", "record", nil, canLaunch, "Record only, no window"),
            quick("CAMERA", "camera", "mirror", { video_source = "camera" },
                canLaunch and cameraBlocked == nil, cameraBlocked or "Mirror the camera"),
        }),
        ui.row({ gap = 5, align = "stretch" }, {
            quick("WEBCAM", "video", "mirror", {
                video_source = "camera",
                v4l2_enabled = true,
                v4l2_sink = tostring(st.eff.v4l2_sink or "/dev/video10"),
                no_control = false,
            }, canLaunch and cameraBlocked == nil and v4l2Ready,
                (not v4l2Ready and "No writable V4L2 loopback device") or cameraBlocked or "Publish the camera to a V4L2 sink"),
            windowButton,
        }),
    })

    local recordOn = st.eff.record_enabled == true
    local recordRow = ui.row({ align = "center", gap = 8 }, {
        ui.glyph({
            name = "player-record",
            size = 12,
            color = recordOn and T.color.error or T.color.muted,
        }),
        ui.label({
            text = "Record while mirroring",
            fontSize = T.size.micro,
            fontFamily = T.font.label,
            color = recordOn and T.color.text or T.color.muted,
            flexGrow = 1,
            maxLines = 1,
        }),
        ui.toggle({
            key = "toggle-record-while-mirroring",
            checked = recordOn,
            onChange = function(value)
                setFeature("record_enabled", value == "true")
                render()
            end,
        }),
    })

    local children = {
        deviceLine,
        divider(),
        mirror,
        quickRow,
        recordRow,
    }

    if recordOn then
        children[#children + 1] = ui.row({ align = "center", gap = 6 }, {
            ui.glyph({ name = "folder", size = 12, color = T.color.muted }),
            note(tostring(st.eff.record_dir or "~/Videos") .. " · " .. string.upper(tostring(st.eff.record_format or "mp4")), T.color.muted, 1),
        })
    end

    if st.hasLast then
        children[#children + 1] = ui.button({
            text = "RESTART LAST SESSION",
            glyph = "rotate",
            variant = "ghost",
            controlSize = "sm",
            enabled = canLaunch,
            onClick = function()
                S.send("start-last")
                render()
            end,
        })
    end

    if blocked.all or blocked.device then
        children[#children + 1] = note(blocked.all or blocked.device, T.color.error, 2)
    elseif not ready and #st.devices > 0 then
        children[#children + 1] = note("A phone is connected but not selected yet — pick it in Devices.", T.color.warning, 2)
    end

    return S.card(children)
end

local function sessionRow(st, session)
    local active = session.state ~= "stopped" and session.state ~= "error"
    local kind = session.mode or (session.recordFile and "record" or session.kind or "mirror")
    local def = S.kindDef(kind)
    local stateColor = "on_surface_variant"
    if session.state == "running" then stateColor = "tertiary" end
    if session.state == "starting" or session.state == "stopping" then stateColor = "primary" end
    if session.state == "error" then stateColor = "error" end

    local right = {
        chip(active and (session.state == "starting" and "STARTING" or session.state == "stopping" and "STOPPING" or "LIVE") or session.state, stateColor),
    }
    if active then
        right[#right + 1] = iconButton("player-stop", "Stop session", function()
            S.send("stop", { id = session.id })
            render()
        end)
    end

    local title = ui.row({ align = "center", gap = 7, flexGrow = 1 }, {
        ui.glyph({ name = def.glyph, size = 13, color = def.color }),
        ui.label({
            text = def.label,
            fontSize = T.size.micro,
            fontFamily = T.font.label,
            fontWeight = "bold",
            color = T.color.text,
            maxLines = 1,
        }),
        ui.label({
            text = active and S.elapsed(session.startedAt) or "ended",
            fontSize = T.size.value,
            fontFamily = T.font.value,
            color = T.color.muted,
            maxLines = 1,
        }),
    })

    local children = {
        ui.row({ align = "center", justify = "space_between", gap = 6 }, {
            title,
            ui.row({ align = "center", gap = 4 }, right),
        }),
    }
    if session.recordFile then
        children[#children + 1] = note(session.recordFile, T.color.muted, 1)
    end
    if session.error then
        children[#children + 1] = note(session.error, T.color.error, 3)
    end
    return ui.column({
        key = "session-" .. tostring(session.id),
        gap = 4,
        paddingH = 8,
        paddingV = 6,
        radius = T.size.cardRadius,
        fill = T.color.card,
    }, children)
end

local function sessionsSection(st)
    local all = st.sessions
    if #all == 0 then return nil end
    local rows = {}
    for i = #all, 1, -1 do rows[#rows + 1] = sessionRow(st, all[i]) end
    local active = #activeSessions(st)
    return ui.column({ gap = 6 }, {
        section("SESSIONS", S.micro(tostring(active) .. " ACTIVE")),
        ui.column({ gap = 5 }, rows),
    })
end

local function presetButton(st, name)
    return ui.button({
        key = "preset-" .. name,
        text = Presets.label(name),
        variant = "default",
        controlSize = "sm",
        flexGrow = 1,
        selected = st.preset == name,
        tooltip = name,
        onClick = function()
            S.send("apply-preset", { preset = name })
            edit = {}
            render()
        end,
    })
end

local function defaultsSummary(st)
    local eff = st.eff
    local size = tonumber(eff.max_size) or 0
    local fps = tonumber(eff.max_fps) or 0
    local bitrate = tonumber(eff.video_bit_rate) or 0
    local audio = eff.audio_enabled == true
    local record = eff.record_enabled == true
    local virtual = eff.new_display == true
    local keyboard = tostring(eff.keyboard_mode or "disabled")
    local mouse = tostring(eff.mouse_mode or "disabled")

    local input
    if keyboard == "disabled" and mouse == "disabled" then
        input = "Input off"
    else
        input = "Input " .. (keyboard == "disabled" and "—" or string.upper(keyboard))
            .. "/" .. (mouse == "disabled" and "—" or string.upper(mouse))
    end

    local first = table.concat({
        size > 0 and (size .. " px") or "Native",
        fps > 0 and (fps .. " fps") or "Unlimited fps",
        string.upper(tostring(eff.video_codec or "h264")),
        bitrate > 0 and (bitrate .. " Kbps") or "Default bit rate",
    }, "  ·  ")

    local second = table.concat({
        audio and ("Audio " .. string.upper(tostring(eff.audio_codec or "opus")) .. " " .. tostring(eff.audio_bit_rate or 128) .. "K") or "Audio off",
        record and ("Rec " .. string.upper(tostring(eff.record_format or "mp4"))) or "Rec off",
        virtual and tostring(eff.new_display_size or "1920x1080") or "Display",
        input,
    }, " · ")

    return ui.column({ gap = 3 }, {
        S.sectionHead("SESSION DEFAULTS", ui.button({
            text = "EDIT",
            variant = "ghost",
            controlSize = "sm",
            onClick = function()
                activeTab = "settings"
                render()
            end,
        })),
        ui.label({
            text = first,
            fontSize = T.size.value,
            fontFamily = T.font.value,
            color = T.color.text,
            maxLines = 1,
        }),
        ui.label({
            text = second,
            fontSize = T.size.micro,
            fontFamily = T.font.value,
            color = T.color.muted,
            maxLines = 1,
        }),
    })
end

local function presetsSection(st)
    local row1, row2 = {}, {}
    for i, name in ipairs(Presets.order) do
        if i <= 3 then row1[#row1 + 1] = presetButton(st, name)
        else row2[#row2 + 1] = presetButton(st, name) end
    end
    -- Keep the second row on the same three-column grid as the first.
    row2[#row2 + 1] = ui.box({ flexGrow = 1, height = 1 })
    local trailing = st.preset == "Custom" and S.micro("CUSTOM") or nil
    return ui.column({ gap = 6 }, {
        section("PRESETS", trailing),
        ui.row({ gap = 5 }, row1),
        ui.row({ gap = 5 }, row2),
    })
end

local function controlTab(st)
    local children = { launchCard(st) }
    local sessions = sessionsSection(st)
    if sessions then children[#children + 1] = sessions end
    children[#children + 1] = presetsSection(st)
    children[#children + 1] = defaultsSummary(st)
    return ui.column({ gap = 10 }, children)
end

-- ── devices tab ──────────────────────────────────────────────────────────────

local function deviceRow(st, device)
    local ready = Devices.isReady(device)
    local selected = device.serial == st.selected
    local badges = {
        chip(device.wireless and "WIFI" or "USB", device.wireless and "primary" or "tertiary"),
    }
    if selected then badges[#badges + 1] = chip("SELECTED", "primary") end

    local children = {
        ui.row({ align = "center", gap = 8 }, {
            ui.glyph({
                name = ready and "device-mobile" or "device-mobile-off",
                size = 18,
                color = ready and (selected and T.color.accent or T.color.text) or T.color.muted,
            }),
            ui.column({ gap = 1, flexGrow = 1 }, {
                ui.label({
                    text = Devices.label(device),
                    fontSize = 12.5,
                    fontFamily = T.font.label,
                    fontWeight = "semibold",
                    color = T.color.text,
                    maxLines = 1,
                }),
                ui.label({
                    text = device.endpoint ~= "" and tostring(device.endpoint) or tostring(device.serial),
                    fontSize = T.size.micro,
                    fontFamily = T.font.value,
                    color = T.color.muted,
                    maxLines = 1,
                }),
            }),
            ui.row({ gap = 4, align = "center" }, badges),
        }),
    }

    local actions = {}
    if not ready and device.wireless then
        actions[#actions + 1] = ui.button({
            text = "CONNECT",
            variant = "outline",
            controlSize = "sm",
            onClick = function()
                S.send("connect", { serial = device.endpoint ~= "" and device.endpoint or device.serial })
                render()
            end,
        })
    elseif ready and selected then
        actions[#actions + 1] = ui.button({
            text = "MIRROR",
            glyph = "player-play",
            variant = "outline",
            controlSize = "sm",
            onClick = function()
                S.send("start", { kind = "mirror", serial = device.serial })
                render()
            end,
        })
    end
    if not selected then
        actions[#actions + 1] = ui.button({
            text = "USE",
            variant = "outline",
            controlSize = "sm",
            enabled = ready,
            onClick = function()
                S.send("select", { serial = device.serial })
                render()
            end,
        })
    end
    if #actions > 0 then
        children[#children + 1] = ui.row({ gap = 5, justify = "end", align = "center" }, actions)
    end

    return ui.column({
        key = "device-" .. tostring(device.serial),
        gap = 6,
        padding = 9,
        radius = T.size.cardRadius,
        fill = selected and (T.color.accent .. "/0.08") or T.color.card,
        border = selected and (T.color.accent .. "/0.40") or T.color.cardBorder,
        borderWidth = 1,
        onClick = function()
            if ready and not selected then
                S.send("select", { serial = device.serial })
                render()
            end
        end,
    }, children)
end

local function devicesList(st)
    if #st.devices == 0 then
        return ui.column({ gap = 4 }, {
            section("CONNECTED", S.micro("0 FOUND")),
            note("No devices found. Enable wireless debugging, then pair below.", "on_surface/0.45", 2),
        })
    end
    local rows = {}
    for _, device in ipairs(st.devices) do rows[#rows + 1] = deviceRow(st, device) end
    return ui.column({ gap = 6 }, {
        section("CONNECTED", S.micro(tostring(#st.devices) .. " FOUND")),
        ui.column({ gap = 6 }, rows),
    })
end

local function pairCard(st)
    return S.card({
        ui.row({ align = "center", gap = 7 }, {
            ui.glyph({ name = "qrcode", size = 14, color = T.color.accent }),
            ui.label({
                text = T.copy.pairing,
                fontSize = T.size.micro,
                fontFamily = T.font.label,
                fontWeight = "bold",
                color = T.color.text,
                maxLines = 1,
            }),
        }),
        note("Android 11+ · Wireless debugging → Pair device with pairing code.", T.color.muted, 2),
        ui.row({ gap = 6, align = "center" }, {
            ui.input({
                key = "pair-host",
                placeholder = "192.168.0.11:37123",
                controlSize = "sm",
                flexGrow = 1,
                onChange = function(value) pairHost = value end,
            }),
            ui.input({
                key = "pair-code",
                placeholder = "123456",
                controlSize = "sm",
                width = 92,
                onChange = function(value) pairCode = value end,
            }),
        }),
        ui.button({
            text = "PAIR",
            glyph = "link-plus",
            variant = "outline",
            controlSize = "sm",
            onClick = function()
                S.send("pair", { host = noctalia.string.trim(pairHost), code = noctalia.string.trim(pairCode) })
                render()
            end,
        }),
    })
end

local function connectCard(st)
    return S.card({
        section("MANUAL CONNECT"),
        note("A phone already paired with this machine, or one with adb tcpip enabled.", T.color.muted, 2),
        ui.row({ gap = 6, align = "center" }, {
            ui.input({
                key = "manual-addr",
                placeholder = "192.168.0.11:5555",
                controlSize = "sm",
                flexGrow = 1,
                onChange = function(value) connectAddr = value end,
            }),
            ui.button({
                text = "CONNECT",
                variant = "outline",
                controlSize = "sm",
                onClick = function()
                    local address = noctalia.string.trim(connectAddr)
                    if address ~= "" then S.send("connect", { serial = address }) end
                    render()
                end,
            }),
        }),
    })
end

local function rememberedList(st)
    local rows = {}
    local entries = {}
    for key, item in pairs(st.known) do
        entries[#entries + 1] = { key = key, item = item }
    end
    table.sort(entries, function(a, b)
        return (a.item.updatedAt or 0) > (b.item.updatedAt or 0)
    end)

    for _, entry in ipairs(entries) do
        local item = entry.item
        local current = Devices.find(st.devices, tostring(item.serial or ""))
        local ready = Devices.isReady(current)
        local trailing = {}
        if ready then trailing[#trailing + 1] = chip("READY", "tertiary") end
        trailing[#trailing + 1] = iconButton("link", "Connect", function()
            S.send("connect", { serial = tostring(item.endpoint ~= "" and item.endpoint or item.serial) })
            render()
        end)
        trailing[#trailing + 1] = iconButton("trash", "Forget this device", function()
            S.send("forget", { key = entry.key })
            render()
        end)

        local children = {
            ui.row({ align = "center", gap = 8 }, {
                ui.glyph({
                    name = "device-mobile",
                    size = 13,
                    color = ready and T.color.success or T.color.muted,
                }),
                ui.column({ gap = 1, flexGrow = 1 }, {
                    ui.label({
                        text = tostring(item.label or entry.key),
                        fontSize = T.size.body,
                        fontFamily = T.font.label,
                        color = T.color.text,
                        maxLines = 1,
                    }),
                    ui.label({
                        text = tostring(item.endpoint ~= "" and item.endpoint or item.serial or ""),
                        fontSize = T.size.micro,
                        fontFamily = T.font.value,
                        color = T.color.muted,
                        maxLines = 1,
                    }),
                }),
                ui.row({ gap = 2, align = "center" }, trailing),
            }),
        }
        rows[#rows + 1] = ui.column({
            key = "known-" .. entry.key,
            gap = 2,
            paddingV = 3,
        }, children)
    end

    if #rows == 0 then
        return ui.column({ gap = 4 }, {
            section(T.copy.remembered),
            note("Devices appear here after the first connection.", "on_surface/0.45", 2),
        })
    end
    return ui.column({ gap = 4 }, {
        section(T.copy.remembered, S.micro(tostring(#rows))),
        ui.column({ gap = 2 }, rows),
    })
end

local function devicesTab(st)
    return ui.column({ gap = 12 }, {
        devicesList(st),
        pairCard(st),
        connectCard(st),
        rememberedList(st),
    })
end

-- ── settings tab ─────────────────────────────────────────────────────────────

local function formatValue(value, unit)
    if unit and unit ~= "" then return tostring(value) .. " " .. unit end
    return tostring(value)
end

local function sliderRow(st, key, label, min, max, step, unit)
    local blocked = st.blocked[key]
    local value = tonumber(edit[key]) or tonumber(st.eff[key]) or min
    local children = {
        ui.row({ align = "center", gap = 6 }, {
            ui.label({
                text = label,
                fontSize = T.size.body,
                fontFamily = T.font.label,
                color = blocked and "on_surface/0.45" or T.color.text,
                flexGrow = 1,
                maxLines = 1,
            }),
            ui.label({
                text = formatValue(value, unit),
                fontSize = T.size.value,
                fontFamily = T.font.value,
                color = blocked and T.color.muted or T.color.accent,
                maxLines = 1,
            }),
        }),
        ui.slider({
            key = "slider-" .. key,
            min = min,
            max = max,
            step = step or 1,
            value = value,
            enabled = not blocked,
            onChange = function(raw)
                edit[key] = tonumber(raw)
                render()
            end,
            onDragEnd = function()
                if edit[key] ~= nil then setFeature(key, edit[key]) end
            end,
        }),
    }
    if blocked then children[#children + 1] = note(blocked, T.color.error, 2) end
    return ui.column({ key = "row-" .. key, gap = 3, paddingV = 4 }, children)
end

local function toggleRow(st, key, label, hint)
    local blocked = st.blocked[key]
    local copy = {
        ui.label({
            text = label,
            fontSize = T.size.body,
            fontFamily = T.font.label,
            color = blocked and "on_surface/0.45" or T.color.text,
            maxLines = 2,
        }),
    }
    if hint then copy[#copy + 1] = note(hint, "on_surface/0.45", 2) end
    if blocked then copy[#copy + 1] = note(blocked, T.color.error, 2) end
    return ui.row({ key = "toggle-row-" .. key, align = "center", gap = 10, paddingV = 3 }, {
        ui.column({ gap = 1, flexGrow = 1 }, copy),
        ui.toggle({
            key = "toggle-" .. key,
            checked = st.eff[key] == true,
            enabled = not blocked,
            onChange = function(value)
                setFeature(key, value == "true")
                render()
            end,
        }),
    })
end

local function selectRow(st, key, label, options)
    local blocked = st.blocked[key]
    local labels, current = {}, tostring(st.eff[key] or "")
    local selectedIndex = -1
    for index, option in ipairs(options) do
        labels[index] = option.label
        if tostring(option.value) == current then selectedIndex = index - 1 end
    end
    return ui.row({ key = "select-row-" .. key, align = "center", gap = 10, paddingV = 4 }, {
        ui.label({
            text = label,
            fontSize = T.size.body,
            fontFamily = T.font.label,
            color = blocked and "on_surface/0.45" or T.color.text,
            flexGrow = 1,
            maxLines = 1,
        }),
        ui.select({
            key = "select-" .. key,
            options = labels,
            selectedIndex = selectedIndex >= 0 and selectedIndex or 0,
            width = 150,
            controlSize = "sm",
            enabled = not blocked,
            onChange = function(_index, text)
                for _, option in ipairs(options) do
                    if option.label == text then
                        setFeature(key, option.value)
                        break
                    end
                end
                render()
            end,
        }),
    })
end

local function textRow(st, key, label, placeholder, hint)
    local blocked = st.blocked[key]
    local current = tostring(st.eff[key] or "")
    local function apply()
        local value = edit[key]
        if value ~= nil then setFeature(key, value) end
        render()
    end
    local children = {
        ui.label({
            text = label,
            fontSize = T.size.body,
            fontFamily = T.font.label,
            color = blocked and "on_surface/0.45" or T.color.text,
            maxLines = 1,
        }),
        ui.row({ gap = 5, align = "center" }, {
            ui.input({
                key = "input-" .. key .. "-" .. current,
                value = current,
                placeholder = placeholder,
                controlSize = "sm",
                flexGrow = 1,
                enabled = not blocked,
                submitOnEnter = true,
                onChange = function(value) edit[key] = value end,
                onSubmit = function(value)
                    edit[key] = value
                    apply()
                end,
            }),
            iconButton("check", "Apply", apply),
        }),
    }
    if hint then children[#children + 1] = note(hint, "on_surface/0.45", 2) end
    return ui.column({ key = "text-row-" .. key, gap = 3, paddingV = 4 }, children)
end

local function recordDirRow(st)
    local current = tostring(st.eff.record_dir or "~/Videos")
    local expanded = noctalia.expandPath(current)
    local row = textRow(st, "record_dir", "Save recordings to", "/home/you/Videos", nil)
    if expanded ~= current then
        row = ui.column({ gap = 2 }, {
            row,
            note("Resolves to " .. expanded, "on_surface/0.45", 1),
        })
    end
    return row
end

local function commandCard(st)
    local settings = st.eff
    local argv = A.build({
        settings = settings,
        serial = st.selected ~= "" and st.selected or nil,
        recordDir = noctalia.expandPath(tostring(settings.record_dir or "~/Videos")),
    })
    local text = A.preview(argv)
    return S.card({
        ui.row({ align = "center", justify = "space_between", gap = 6 }, {
            section("COMMAND"),
            ui.row({ gap = 4 }, {
                ui.button({
                    text = showCommand and "HIDE" or "SHOW",
                    variant = "ghost",
                    controlSize = "sm",
                    onClick = function()
                        showCommand = not showCommand
                        render()
                    end,
                }),
                iconButton("copy", "Copy command", function()
                    noctalia.copyToClipboard(text, "text/plain")
                end),
            }),
        }),
        showCommand
            and ui.label({
                text = text,
                fontSize = 9,
                fontFamily = T.font.value,
                color = T.color.muted,
                maxLines = 6,
            })
            or note("The exact argv a new session would launch.", "on_surface/0.45", 1),
    })
end

local function settingsTab(st)
    local nodes = {}
    local function add(item)
        if item then nodes[#nodes + 1] = item end
    end

    add(ui.row({ align = "center", justify = "space_between", gap = 6 }, {
        note("Edits apply to new sessions", T.color.muted, 1),
        ui.button({
            text = advancedOpen and "HIDE ADVANCED" or "ADVANCED",
            glyph = "adjustments",
            variant = "ghost",
            controlSize = "sm",
            selected = advancedOpen,
            onClick = function()
                advancedOpen = not advancedOpen
                render()
            end,
        }),
    }))

    add(section("VIDEO"))
    add(sliderRow(st, "max_size", "Max resolution", 240, 4096, 16, "px"))
    add(sliderRow(st, "video_bit_rate", "Video bit rate", 100, 20000, 100, "Kbps"))
    add(sliderRow(st, "max_fps", "Frame rate cap", 1, 120, 1, "fps"))
    add(selectRow(st, "video_codec", "Codec", CODECS))

    add(divider())
    add(section("AUDIO"))
    add(toggleRow(st, "audio_enabled", "Forward audio"))
    if st.eff.audio_enabled ~= false then
        add(selectRow(st, "audio_source", "Source", AUDIO_SOURCES))
        add(selectRow(st, "audio_codec", "Codec", AUDIO_CODECS))
        add(sliderRow(st, "audio_bit_rate", "Audio bit rate", 8, 512, 8, "Kbps"))
    end

    add(divider())
    add(section("RECORDING"))
    add(toggleRow(st, "record_enabled", "Record sessions", "Also available on the Control tab"))
    if st.eff.record_enabled == true then
        add(selectRow(st, "record_format", "Container", RECORD_FORMATS))
        add(recordDirRow(st))
        add(toggleRow(st, "record_only", "Record only", "No playback window"))
    end

    add(divider())
    add(section("DISPLAY"))
    add(toggleRow(st, "new_display", "Virtual display", "Mirror into a separate Android display"))
    if st.eff.new_display == true then
        add(textRow(st, "new_display_size", "Display size", "1920x1080"))
    end
    add(textRow(st, "start_app", "Launch app", "com.example.app", "Package name, started after connecting"))

    add(divider())
    add(section("INPUT & SCREEN"))
    add(toggleRow(st, "turn_screen_off", "Turn phone screen off"))
    add(toggleRow(st, "stay_awake", "Keep phone awake"))
    add(toggleRow(st, "power_off_on_close", "Power off on close"))
    add(toggleRow(st, "clipboard_autosync", "Clipboard sync"))
    add(selectRow(st, "keyboard_mode", "Keyboard", KEYBOARD_MODES))
    add(selectRow(st, "mouse_mode", "Mouse", MOUSE_MODES))
    add(selectRow(st, "gamepad_mode", "Gamepad", GAMEPAD_MODES))

    add(divider())
    add(section("CAMERA & WEBCAM"))
    add(selectRow(st, "video_source", "Source", VIDEO_SOURCES))
    if st.eff.video_source == "camera" then
        add(selectRow(st, "camera_facing", "Facing", FACINGS))
        add(textRow(st, "camera_size", "Camera size", "1920x1080", "Optional WxH capture size"))
        add(toggleRow(st, "v4l2_enabled", "Publish to V4L2", "Expose the phone camera as a webcam"))
        if st.eff.v4l2_enabled == true then
            add(textRow(st, "v4l2_sink", "V4L2 device", "/dev/video10"))
        end
    end

    add(divider())
    add(section("WINDOW"))
    add(toggleRow(st, "always_on_top", "Always on top"))
    add(toggleRow(st, "fullscreen", "Start fullscreen"))
    add(textRow(st, "window_title", "Window title", "noctalia-scrcpy"))

    if advancedOpen then
        add(divider())
        add(section("ADVANCED"))
        add(sliderRow(st, "video_buffer_ms", "Video buffer", 0, 5000, 50, "ms"))
        add(sliderRow(st, "audio_buffer_ms", "Audio buffer", 0, 5000, 10, "ms"))
        add(textRow(st, "video_encoder", "Video encoder", "encoder name"))
        add(sliderRow(st, "new_display_dpi", "Virtual display DPI", 72, 640, 4, "dpi"))
        add(toggleRow(st, "vd_no_system_decorations", "No virtual display decorations"))
        add(sliderRow(st, "screen_off_timeout", "Screen-off timeout", 0, 3600, 5, "s"))
        add(toggleRow(st, "show_touches", "Show touch points"))
        add(toggleRow(st, "no_control", "Mirror without control"))
        add(toggleRow(st, "otg", "OTG mode", "USB only"))
        add(textRow(st, "camera_id", "Camera id", "0"))
        add(sliderRow(st, "camera_fps", "Camera frame rate", 0, 120, 1, "fps"))
        add(sliderRow(st, "window_width", "Window width", 0, 4096, 16, "px"))
        add(sliderRow(st, "window_height", "Window height", 0, 4096, 16, "px"))
        add(sliderRow(st, "display_id", "Display id", 0, 16, 1, ""))
        add(selectRow(st, "orientation", "Orientation", ORIENTATIONS))
    end

    add(divider())
    add(commandCard(st))
    add(ui.button({
        text = "RESET ALL OVERRIDES",
        glyph = "rotate",
        variant = confirmResetAt > 0 and "destructive" or "ghost",
        controlSize = "sm",
        onClick = function()
            if confirmResetAt > 0 then
                S.send("reset-overrides")
                confirmResetAt = 0
                edit = {}
            else
                confirmResetAt = noctalia.nowMs()
            end
            render()
        end,
    }))

    return ui.column({ gap = 8 }, nodes)
end

-- ── footer ───────────────────────────────────────────────────────────────────

local function probeDot(ok)
    return ui.box({
        width = 5,
        height = 5,
        radius = 3,
        fill = ok and T.color.success or T.color.error,
    })
end

local function footer(st)
    local sdk = tonumber(st.caps.androidSdk) or 0
    local summary = {
        probeDot(st.caps.adb == true),
        S.micro("ADB"),
        probeDot(st.caps.scrcpy == true),
        S.micro("SCRCPY"),
    }
    if sdk > 0 then summary[#summary + 1] = S.micro("· ANDROID " .. tostring(sdk)) end

    local trailing = {}
    if confirmResetAt > 0 then
        trailing[#trailing + 1] = ui.button({
            text = "CONFIRM RESET",
            variant = "destructive",
            controlSize = "sm",
            onClick = function()
                S.send("reset-overrides")
                confirmResetAt = 0
                edit = {}
                render()
            end,
        })
    end
    trailing[#trailing + 1] = iconButton("adjustments", "Plugin settings", function()
        S.send("open-settings")
    end)
    trailing[#trailing + 1] = iconButton("list", "Show the scrcpy command", function()
        activeTab = "settings"
        showCommand = not showCommand
        render()
    end)

    return ui.row({ align = "center", justify = "space_between", gap = 8 }, {
        ui.row({ align = "center", gap = 6 }, summary),
        ui.row({ align = "center", gap = 2 }, trailing),
    })
end

-- ── render ───────────────────────────────────────────────────────────────────

function render()
    local st = snapshot()
    if st.preset ~= lastPreset then
        edit = {}
        lastPreset = st.preset
    end

    local body
    if activeTab == "devices" then
        body = devicesTab(st)
    elseif activeTab == "settings" then
        body = settingsTab(st)
    else
        body = controlTab(st)
    end

    local children = {
        header(st),
        tabs(),
    }
    local n = noticeNode(st)
    if n then children[#children + 1] = n end
    children[#children + 1] = ui.scroll({
        key = "scroll-" .. activeTab,
        flexGrow = 1,
        gap = 10,
        paddingH = 2,
    }, { body })
    children[#children + 1] = divider()
    children[#children + 1] = footer(st)

    local tree = ui.column({
        gap = 8,
        padding = T.layout.panelPadding,
        flexGrow = 1,
    }, children)
    panel.render(tree)
end

function onOpen()
    open = true
    confirmResetAt = 0
    S.send("panel-open")
    panel.setWantsSecondTicks(true)
    render()
end

function onClose()
    open = false
    S.send("panel-close")
    panel.setWantsSecondTicks(false)
end

function update()
    if not open then return end
    if confirmResetAt > 0 and noctalia.nowMs() - confirmResetAt > 4000 then
        confirmResetAt = 0
    end
    render()
end
