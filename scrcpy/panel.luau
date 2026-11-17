--!nonstrict
-- omen/scrcpy panel: devices, pairing, sessions and an argv preview.
local S = require("./lib/shared.luau")
local T = S.T
local A = require("./lib/args.luau")
local Devices = require("./lib/devices.luau")

local pairHost = ""
local pairCode = ""

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
                    text = "USE",
                    variant = "outline",
                    controlSize = "sm",
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
            }),
            S.errorLine(session.error),
        }))
    end
    return rows
end

local function argsRow()
    local defaults = noctalia.state.get("defaults") or {}
    local argv = A.build({ settings = defaults })
    local test = noctalia.state.get("selftest") or {}
    return S.card({
        ui.row({ gap = 6, align = "center" }, {
            S.micro("ARGV PREVIEW"),
            ui.spacer({ flexGrow = 1 }),
            S.micro(tostring(test.passed or 0) .. " PASS / " .. tostring(test.failed or 0) .. " FAIL",
                (test.failed or 0) > 0 and T.color.error or T.color.success),
        }),
        ui.label({
            text = A.preview(argv),
            fontSize = T.size.micro,
            fontFamily = T.font.value,
            color = T.color.muted,
            maxLines = 3,
        }),
    })
end

local function render()
    local devices = noctalia.state.get("devices") or {}
    local sessions = noctalia.state.get("sessions") or {}
    local notice = noctalia.state.get("notice")

    local children = {
        S.header(T.copy.panelTitle, S.micro(T.copy.subtitle, T.color.accent)),
        S.sectionRule(),

        S.micro(T.copy.devices),
        ui.column({ gap = T.layout.rowGap }, deviceRows(devices)),

        ui.row({ gap = 8, align = "center" }, {
            ui.button({
                text = T.copy.refresh,
                variant = "outline",
                controlSize = "sm",
                onClick = function() S.send("refresh") end,
            }),
            ui.spacer({ flexGrow = 1 }),
        }),

        S.sectionRule(),
        S.micro(T.copy.pairing),
        S.card({
            ui.input({
                key = "pair-host",
                value = pairHost,
                placeholder = "192.168.0.11:38377",
                controlSize = "sm",
                onChange = function(value) pairHost = value end,
            }),
            ui.input({
                key = "pair-code",
                value = pairCode,
                placeholder = "123456",
                controlSize = "sm",
                onChange = function(value) pairCode = value end,
            }),
            ui.button({
                text = T.copy.pair,
                variant = "primary",
                controlSize = "sm",
                onClick = function() S.send("pair", { host = pairHost, code = pairCode }) end,
            }),
        }),

        S.sectionRule(),
        S.micro(T.copy.sessions),
        ui.column({ gap = T.layout.rowGap }, sessionRows(sessions)),

        S.sectionRule(),
        argsRow(),
        ui.button({
            text = "COPY ARGS",
            variant = "ghost",
            controlSize = "sm",
            onClick = function()
                local argv = A.build({ settings = noctalia.state.get("defaults") or {} })
                noctalia.copyToClipboard(A.preview(argv), "text/plain")
            end,
        }),
        S.errorLine(notice),
        S.sectionRule(),
        ui.button({
            text = T.copy.openSettings,
            variant = "ghost",
            controlSize = "sm",
            onClick = function() noctalia.openSettings() end,
        }),
    }

    panel.render(ui.column({
        gap = T.layout.panelGap,
        padding = 12,
        fill = "surface_container/0.75",
        radius = T.size.radius,
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

noctalia.state.watch("devices", render)
noctalia.state.watch("sessions", render)
noctalia.state.watch("notice", render)
render()
