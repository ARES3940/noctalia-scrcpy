--!nonstrict
-- omen/scrcpy bar widget: one state icon, tooltip with details.
local S = require("./lib/shared.luau")
local T = S.T

local function currentState(sessions, devices)
    local hasDevice = false
    for _, device in pairs(devices or {}) do
        if device.state == "device" then hasDevice = true end
    end
    for _, session in pairs(sessions or {}) do
        if session.state == "running" or session.state == "starting" then
            if session.kind == "record" then return "recording" end
            return "mirroring"
        end
    end
    if hasDevice then return "connected" end
    return "disconnected"
end

local function render()
    local sessions = noctalia.state.get("sessions") or {}
    local devices = noctalia.state.get("devices") or {}
    local state = currentState(sessions, devices)
    local def = S.statusDef(state)

    local container = barWidget.isVertical() and ui.column or ui.row
    barWidget.render(container({ gap = 4, align = "center" }, {
        ui.glyph({ name = def.glyph, size = 14, color = def.color }),
        ui.label({
            text = T.copy.panelTitle,
            fontSize = T.size.barLabel,
            fontFamily = T.font.label,
            fontWeight = "bold",
            color = T.color.muted,
        }),
    }))

    local rows = { { "STATE", def.label }, { "DEVICES", tostring(type(devices) == "table" and #devices or 0) } }
    for _, session in pairs(sessions) do
        table.insert(rows, { "SESSION", tostring(session.kind or "mirror") .. " " .. tostring(session.state or "?") })
        if session.error then table.insert(rows, { "ERROR", tostring(session.error) }) end
    end
    barWidget.setTooltip(rows)
end

function update()
    render()
end

function onClick()
    noctalia.togglePanel("omen/scrcpy:panel")
end

-- Right-click opens a compact quick-actions panel. panel.openContextMenu() is
-- panel-only in the Noctalia API, so a second small panel is the supported way
-- to offer quick actions from a bar widget.
function onRightClick()
    noctalia.togglePanel("omen/scrcpy:quick")
end

noctalia.setUpdateInterval(1000)
noctalia.state.watch("sessions", render)
noctalia.state.watch("devices", render)
render()
