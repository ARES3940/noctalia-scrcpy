--!nonstrict
-- omen/scrcpy bar widget: one status glyph, REC or a session count, and a
-- tooltip with the details. Left click opens the full panel, right click the
-- quick-actions panel.

local S = require("./lib/shared.luau")
local T = S.T

local function read()
    local sessions = noctalia.state.get("sessions") or {}
    local devices = noctalia.state.get("devices") or {}
    local selected = tostring(noctalia.state.get("selected") or "")
    return S.statusOf(sessions, selected, devices), sessions, devices, selected
end

local function deviceLabel(devices, selected)
    for _, device in ipairs(devices) do
        if device.serial == selected then
            if device.model and device.model ~= "" then return device.model end
            return device.serial
        end
    end
    return "No device"
end

local function tooltipRows(state, sessions, devices, selected)
    local def = S.statusDef(state)
    local rows = {
        { key = "State", value = def.label },
        { key = "Device", value = deviceLabel(devices, selected) },
    }

    local active = S.activeSessions(sessions)
    if #active > 0 then
        rows[#rows + 1] = { key = "Sessions", value = tostring(#active) }
        for _, session in ipairs(active) do
            local kind = string.upper(session.mode or (session.recordFile and "record" or session.kind or "mirror"))
            local detail = kind .. " · " .. S.elapsed(session.startedAt)
            if session.recordFile then detail = detail .. " · REC" end
            rows[#rows + 1] = { key = session.state == "starting" and "Starting" or "Running", value = detail }
        end
        local last = active[#active]
        if last and last.recordFile then
            rows[#rows + 1] = { key = "Recording", value = last.recordFile }
        end
    end

    for _, session in ipairs(sessions) do
        if session.error then
            rows[#rows + 1] = { key = "Error", value = session.error }
        end
    end

    return rows
end

local function render()
    local state, sessions, devices, selected = read()
    local def = S.statusDef(state)
    local active = S.activeSessions(sessions)
    local vertical = barWidget.isVertical()

    local children = {
        ui.glyph({ name = def.glyph, size = T.size.icon, color = def.color }),
    }

    if #active > 1 then
        children[#children + 1] = ui.label({
            text = tostring(#active),
            fontSize = T.size.barLabel,
            fontFamily = T.font.value,
            fontWeight = "bold",
            color = def.color,
            maxLines = 1,
        })
    elseif state == "recording" and not vertical then
        children[#children + 1] = ui.label({
            text = "REC",
            fontSize = T.size.barLabel,
            fontFamily = T.font.label,
            fontWeight = "bold",
            color = def.color,
            maxLines = 1,
        })
    elseif state == "mirroring" and not vertical then
        children[#children + 1] = ui.label({
            text = S.elapsed(active[1] and active[1].startedAt),
            fontSize = T.size.barLabel,
            fontFamily = T.font.value,
            color = T.color.muted,
            maxLines = 1,
        })
    end

    local container = vertical and ui.column or ui.row
    barWidget.render(container({ gap = 4, align = "center" }, children))
    barWidget.setTooltip(tooltipRows(state, sessions, devices, selected))
end

function update()
    render()
end

function onClick()
    noctalia.togglePanel("omen/scrcpy:panel")
end

-- A right-click quick panel replaces panel.openContextMenu(), which only works
-- from a panel's own pointer callback.
function onRightClick()
    noctalia.togglePanel("omen/scrcpy:quick")
end

noctalia.setUpdateInterval(1000)
noctalia.state.watch("sessions", render)
noctalia.state.watch("devices", render)
noctalia.state.watch("selected", render)
noctalia.state.watch("notice", render)
render()
