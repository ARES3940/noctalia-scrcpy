--!nonstrict
-- omen/scrcpy panel. Session 1 scaffold: themed layout, real state wiring.
-- Sessions 3-6 fill the device list, pairing form, toggles and presets.
local S = require("./lib/shared.luau")
local T = S.T

local function deviceRows(devices)
    if type(devices) ~= "table" or #devices == 0 then
        return { S.empty(T.copy.noDevices) }
    end
    local rows = {}
    for _, device in ipairs(devices) do
        table.insert(rows, S.card({
            ui.row({ gap = 6, align = "center" }, {
                S.dot("connected"),
                S.value(device.label or device.serial or "device"),
                ui.spacer({ flexGrow = 1 }),
                S.micro(device.state or "device", T.color.muted, 56),
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
            ui.button({
                text = T.copy.pair,
                variant = "outline",
                controlSize = "sm",
                onClick = function() S.send("pair-dialog") end,
            }),
            ui.spacer({ flexGrow = 1 }),
        }),

        S.sectionRule(),
        S.micro(T.copy.sessions),
        ui.column({ gap = T.layout.rowGap }, sessionRows(sessions)),
        S.errorLine(notice),
        S.sectionRule(),
        S.micro(T.copy.build, T.color.muted),
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

noctalia.state.watch("sessions", render)
noctalia.state.watch("devices", render)
noctalia.state.watch("notice", render)
render()
