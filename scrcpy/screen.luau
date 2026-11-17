--!nonstrict
-- Embedded preview panel: an interactive phone view fed by the manager's
-- pixel-stream companion. No scrcpy native window is involved.

local S = require("./lib/shared.luau")
local T = S.T
local Devices = require("./lib/devices.luau")

local open = false
local dragging = false
local downX, downY, lastX, lastY = 0.5, 0.5, 0.5, 0.5

local function state()
    return {
        devices = noctalia.state.get("devices") or {},
        selected = noctalia.state.get("selected") or "",
        sessions = noctalia.state.get("sessions") or {},
        preview = noctalia.state.get("preview") or {},
        caps = noctalia.state.get("capabilities") or {},
        blocked = noctalia.state.get("blocked") or {},
        notice = noctalia.state.get("notice"),
    }
end

local function selectedDevice(st)
    return Devices.find(st.devices, st.selected) or Devices.pick(st.devices, st.selected)
end

local function previewSession(st)
    local id = st.preview.sessionId
    if id == nil or id == "" then return nil end
    for _, session in ipairs(st.sessions) do
        if session.id == id then return session end
    end
    return nil
end

-- ── pointer / keyboard handlers (global names keep the stream stable) ───────

function onPixelDown(x, y)
    dragging = true
    downX = tonumber(x) or 0.5
    downY = tonumber(y) or 0.5
    lastX, lastY = downX, downY
end

function onPixelMove(x, y)
    lastX = tonumber(x) or lastX
    lastY = tonumber(y) or lastY
end

function onPixelUp(x, y)
    if not dragging then return end
    lastX = tonumber(x) or lastX
    lastY = tonumber(y) or lastY
    dragging = false
    local dx, dy = math.abs(lastX - downX), math.abs(lastY - downY)
    if dx < 0.02 and dy < 0.02 then
        S.send("preview-tap", { x = lastX, y = lastY })
    else
        S.send("preview-swipe", { x1 = downX, y1 = downY, x2 = lastX, y2 = lastY })
    end
end

function onPixelCancel()
    dragging = false
end

function onPixelBack()
    S.send("preview-key", { key = "back" })
end

function onPixelHome()
    S.send("preview-key", { key = "home" })
end

function onPixelScroll(dx, dy)
    local steps = tonumber(dy) or 0
    if steps > 0 then S.send("preview-key", { key = "down" })
    elseif steps < 0 then S.send("preview-key", { key = "up" }) end
end

function onPixelText(text)
    S.send("preview-text", { text = text })
end

function onPixelKey(chord, pressed)
    if pressed == "true" then S.send("preview-key", { key = chord }) end
end

-- ── UI ──────────────────────────────────────────────────────────────────────

local function header(st)
    local device = selectedDevice(st)
    local subtitle = device and (Devices.label(device) .. " · " .. tostring(device.endpoint or device.serial))
        or "No device selected"
    local status = st.preview.active and "mirroring" or "connected"
    if not device then status = "disconnected" end

    local trailing = {
        S.pill(status, S.statusDef(status).color),
        S.iconButton("adjustments", "Plugin settings", function() S.send("open-settings") end),
    }
    if noctalia.getSetting("shell.show_close_buttons") ~= false then
        trailing[#trailing + 1] = S.iconButton("x", "Close", function() panel.close() end)
    end

    return ui.row({ align = "center", justify = "space_between", gap = 8 }, {
        ui.row({ align = "center", gap = 8, flexGrow = 1 }, {
            ui.box({ width = 3, height = 22, fill = T.color.accent, radius = 2 }),
            ui.column({ gap = 0, flexGrow = 1 }, {
                ui.label({
                    text = "SCRCPY · PREVIEW",
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
                }),
            }),
        }),
        ui.row({ align = "center", gap = 4 }, trailing),
    })
end

local function previewFrame(st)
    local pv = st.preview
    local width = tonumber(pv.width) or 320
    local height = tonumber(pv.height) or 640
    if pv.active and pv.socket and pv.socket ~= "" then
        return ui.pixelStream({
            key = "phone-stream-" .. tostring(pv.sessionId),
            path = tostring(pv.socket),
            width = width,
            height = height,
            radius = T.size.cardRadius,
            onPointerDown = "onPixelDown",
            onPointerMove = "onPixelMove",
            onPointerUp = "onPixelUp",
            onPointerCancel = "onPixelCancel",
            onRightClick = "onPixelBack",
            onMiddleClick = "onPixelHome",
            onScroll = "onPixelScroll",
            onTextInput = "onPixelText",
            onKeyEvent = "onPixelKey",
        })
    end
    return ui.column({
        key = "phone-placeholder",
        width = width,
        height = height,
        align = "center",
        justify = "center",
        gap = 8,
        radius = T.size.cardRadius,
        fill = T.color.card,
        border = T.color.cardBorder,
        borderWidth = 1,
    }, {
        ui.glyph({ name = "device-mobile-off", size = 30, color = T.color.muted }),
        ui.label({
            text = "NO LIVE PREVIEW",
            fontSize = T.size.section,
            fontFamily = T.font.label,
            fontWeight = "bold",
            color = T.color.muted,
            maxLines = 1,
        }),
        S.note("Start a mirror to show the phone here", "on_surface/0.45", 2),
    })
end

local function navigation()
    local buttons = {
        { key = "nav-back", glyph = "arrow-left", label = "BACK", keycode = "back" },
        { key = "nav-home", glyph = "home", label = "HOME", keycode = "home" },
        { key = "nav-recents", glyph = "squares", label = "RECENTS", keycode = "recents" },
    }
    local row = {}
    for _, item in ipairs(buttons) do
        row[#row + 1] = ui.button({
            key = item.key,
            text = item.label,
            glyph = item.glyph,
            variant = "default",
            controlSize = "sm",
            flexGrow = 1,
            enabled = noctalia.state.get("preview") ~= nil and noctalia.state.get("preview").active == true,
            tooltip = "Android " .. item.label:lower(),
            onClick = function() S.send("preview-key", { key = item.keycode }) end,
        })
    end
    return ui.row({ gap = 6 }, row)
end

local function statusCard(st)
    local pv = st.preview
    local session = previewSession(st)
    local rows = {
        { "SOURCE", pv.active and "LIVE" or "IDLE" },
        { "SIZE", tostring(pv.width or 0) .. " × " .. tostring(pv.height or 0) },
        { "RATE", tostring(pv.fps or 0) .. " fps" },
        { "SESSION", session and ("#" .. tostring(session.id)) or "—" },
    }
    local children = {
        S.sectionHead("PREVIEW", S.badge(pv.active and "LIVE" or "IDLE", pv.active and "primary" or "muted")),
    }
    for _, row in ipairs(rows) do
        children[#children + 1] = ui.row({ align = "center", justify = "space_between", gap = 8 }, {
            S.micro(row[1]),
            S.value(row[2], T.color.text),
        })
    end
    if session and session.startedAt then
        children[#children + 1] = ui.row({ align = "center", justify = "space_between", gap = 8 }, {
            S.micro("ELAPSED"),
            S.value(S.elapsed(session.startedAt), T.color.text),
        })
    end
    return S.card(children)
end

local function render()
    if not open then return end
    local st = state()
    local pv = st.preview

    local right = {
        statusCard(st),
        S.sectionHead("CONTROLS"),
        ui.button({
            text = pv.active and "STOP PREVIEW" or "START PREVIEW",
            glyph = pv.active and "player-stop" or "player-play",
            variant = pv.active and "destructive" or "primary",
            controlSize = "md",
            tooltip = pv.active and "Stop the embedded preview and mirror" or "Mirror the phone into this panel",
            onClick = function()
                if pv.active then S.send("stop-preview")
                else S.send("start-embedded") end
            end,
        }),
        ui.button({
            text = "OPEN IN WINDOW",
            glyph = "external-link",
            variant = "default",
            controlSize = "sm",
            tooltip = "Use a native scrcpy window instead",
            onClick = function()
                S.send("stop-preview")
                S.send("start", { kind = "mirror" })
            end,
        }),
        ui.button({
            text = "FULL CONTROLS",
            glyph = "list",
            variant = "default",
            controlSize = "sm",
            tooltip = "Open the main control panel",
            onClick = function() noctalia.togglePanel("omen/scrcpy:panel") end,
        }),
        S.note("Tap, drag, type and use Back / Home / Recents directly on the preview.", T.color.muted, 3),
    }
    if st.blocked.embedded then right[#right + 1] = S.errorLine(st.blocked.embedded, 3) end
    if pv.error and pv.error ~= "" then right[#right + 1] = S.errorLine(pv.error, 4) end
    if st.notice then right[#right + 1] = S.note(st.notice.text, T.color.muted, 2) end

    local body = ui.row({ gap = 14, align = "start", flexGrow = 1 }, {
        ui.column({ gap = 8 }, {
            previewFrame(st),
            navigation(),
        }),
        ui.column({ gap = 10, flexGrow = 1 }, right),
    })

    panel.render(ui.column({
        gap = 10,
        padding = T.layout.panelPadding,
        flexGrow = 1,
    }, {
        header(st),
        ui.separator({ thickness = 1, color = T.color.text, opacity = 0.12, spacing = 0 }),
        body,
    }))
end

function onOpen()
    open = true
    S.send("preview-open")
    panel.setWantsSecondTicks(true)
    render()
end

function onClose()
    open = false
    S.send("preview-close")
    panel.setWantsSecondTicks(false)
end

function update()
    if open then render() end
end
