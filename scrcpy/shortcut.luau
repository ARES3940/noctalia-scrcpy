--!nonstrict
-- omen/scrcpy shortcut: one tile that starts or stops the last mirror.
-- With no phone ready it opens the panel instead, so pairing is one click away.

local S = require("./lib/shared.luau")
local Devices = require("./lib/devices.luau")

local function read()
    local sessions = noctalia.state.get("sessions") or {}
    local devices = noctalia.state.get("devices") or {}
    local selected = tostring(noctalia.state.get("selected") or "")
    return sessions, devices, selected, S.statusOf(sessions, selected, devices)
end

local function refresh()
    local sessions, devices, selected, state = read()
    local active = #S.activeSessions(sessions) > 0
    local ready = Devices.isReady(Devices.find(devices, selected))

    shortcut.setLabel("Scrcpy")
    shortcut.setIcon(state == "recording" and "player-record" or "device-mobile", "device-mobile")
    shortcut.setActive(active)
    -- Always clickable: with no phone ready, onClick opens the panel to pair.
    shortcut.setEnabled(true)
end

function update()
    refresh()
end

function onClick()
    local sessions, devices, selected, state = read()
    if #S.activeSessions(sessions) > 0 then
        S.send("stop-last")
        return
    end
    if Devices.isReady(Devices.find(devices, selected)) then
        S.send("start", { kind = "mirror" })
    else
        noctalia.togglePanel("omen/scrcpy:panel")
    end
end

noctalia.setUpdateInterval(1000)
noctalia.state.watch("sessions", refresh)
noctalia.state.watch("devices", refresh)
noctalia.state.watch("selected", refresh)
refresh()
