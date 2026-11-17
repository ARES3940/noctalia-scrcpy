--!nonstrict
-- omen/scrcpy service. Session 1 skeleton: owns state and the command bus.
-- Session 3 adds adb discovery/pairing; Session 4 replaces launch/stop stubs
-- with the real detached-process + PID-file manager.

local PLUGIN = "omen/scrcpy"

local sessions = {}
local devices = {}
local panelOpen = false

local function publish()
    noctalia.state.set("sessions", sessions)
    noctalia.state.set("devices", devices)
    noctalia.state.set("panelOpen", panelOpen)
end

local function dispatch(event, payload)
    if event == "toggle-panel" then
        noctalia.togglePanel("omen/scrcpy:panel")
    elseif event == "panel-open" then
        panelOpen = true
        publish()
    elseif event == "panel-close" then
        panelOpen = false
        publish()
    elseif event == "refresh" or event == "pair-dialog" then
        -- Discovery and pairing land in Session 3.
        noctalia.state.set("notice", "Available in the next session")
    elseif event == "ping" then
        noctalia.state.set("lastPong", noctalia.nowMs())
    else
        noctalia.log(PLUGIN .. ": unknown command " .. tostring(event))
    end
end

-- Panel and bar send commands in-process through the plugin state channel.
noctalia.state.watch("cmd", function(cmd)
    if type(cmd) ~= "table" or type(cmd.action) ~= "string" then return end
    dispatch(cmd.action, cmd.payload)
end)

-- External interface: keybinds use `noctalia msg plugin omen/scrcpy:manager all <event> [payload]`.
function onIpc(event, payload)
    dispatch(event, payload)
end

function onSuspend()
    noctalia.log(PLUGIN .. ": suspend")
end

function onResume()
    -- Session 3 re-runs mdns discovery and reconnects here.
    noctalia.log(PLUGIN .. ": resume")
end

function onExit(_signal, reason)
    -- Session 4 stops every owned scrcpy session here.
    noctalia.log(PLUGIN .. ": exit (" .. tostring(reason or "unknown") .. ")")
end

function update()
    -- Session 3 polls adb here, but only while panelOpen is true.
end

noctalia.setUpdateInterval(1000)
publish()
