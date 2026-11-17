--!nonstrict
-- omen/scrcpy service: owns state, settings, adb discovery and the command bus.
-- Session 3 adds real device discovery, pairing and connect. Session 4 adds
-- detached scrcpy sessions.

local PLUGIN = "omen/scrcpy"
local A = require("./lib/args.luau")
local Devices = require("./lib/devices.luau")
local Settings = require("./lib/settings.luau")
local Selftest = require("./lib/selftest.luau")

local defaults = Settings.readAll()
local dataDir = noctalia.pluginDataDir()
local knownPath = dataDir and (dataDir .. "/known.json") or nil

local sessions = {}
local devices = {}
local known = {}
local panelOpen = false
local discovering = false
local lastDiscover = 0
local DISCOVER_INTERVAL_MS = 3000

local function publish()
    noctalia.state.set("sessions", sessions)
    noctalia.state.set("devices", devices)
    noctalia.state.set("known", known)
    noctalia.state.set("panelOpen", panelOpen)
end

local function setNotice(text)
    noctalia.state.set("notice", text)
end

local function loadKnown()
    if not knownPath then return end
    local raw = noctalia.readFile(knownPath)
    if not raw then return end
    local decoded = noctalia.json.decode(raw)
    if type(decoded) == "table" then known = decoded end
end

local function saveKnown()
    if not knownPath then return end
    local encoded = noctalia.json.encode(known)
    if encoded then noctalia.writeFile(knownPath, encoded) end
end

local function afterDiscovery(deviceRows, mdnsRows)
    local previous = {}
    for key, item in pairs(known) do previous[key] = item end

    devices = Devices.merge(deviceRows, mdnsRows)
    local seen = {}
    for _, device in ipairs(devices) do
        seen[device.serial] = true
        local key = device.product ~= "" and device.product or device.serial
        known[key] = {
            serial = device.serial,
            label = Devices.label(device),
            product = device.product,
            endpoint = device.endpoint,
            updatedAt = noctalia.nowMs(),
        }
    end

    -- A known wireless serial that vanished while the same phone is still
    -- present under a different serial means wireless debugging restarted.
    for _, item in pairs(previous) do
        if item.serial and not seen[item.serial] then
            for _, device in ipairs(devices) do
                if item.product ~= "" and device.product == item.product then
                    setNotice("Wireless port changed for " .. tostring(item.label) .. " — reconnect")
                    break
                end
            end
        end
    end

    saveKnown()
    publish()
end

local function discover()
    if discovering then return end
    discovering = true
    lastDiscover = noctalia.nowMs()
    local deviceRows, mdnsRows = {}, {}
    local pending = 2

    local function done()
        pending = pending - 1
        if pending == 0 then
            discovering = false
            afterDiscovery(deviceRows, mdnsRows)
        end
    end

    local accepted = noctalia.runAsync({ "adb", "devices", "-l" }, function(result)
        deviceRows = Devices.parseDevices(result.stdout)
        if result.timedOut then setNotice("adb devices timed out") end
        done()
    end)
    if not accepted then deviceRows = {}; done() end

    accepted = noctalia.runAsync({ "adb", "mdns", "services" }, function(result)
        mdnsRows = Devices.parseMdns(result.stdout)
        done()
    end)
    if not accepted then mdnsRows = {}; done() end
end

local function adbAction(argv, successNotice)
    local accepted = noctalia.runAsync(argv, function(result)
        local text = result.stdout ~= "" and result.stdout or result.stderr
        if result.exitCode == 0 then
            setNotice(successNotice .. (text ~= "" and (": " .. text) or ""))
        else
            setNotice("adb failed: " .. (text ~= "" and text or ("exit " .. tostring(result.exitCode))))
        end
        discover()
    end)
    if not accepted then setNotice("adb not found — install android-tools") end
end

local function dispatch(event, payload)
    local p = type(payload) == "table" and payload or {}
    if type(payload) == "string" then
        -- External IPC passes one string; panel commands pass a table.
        local host, code = payload:match("^(%S+)%s+(%S+)$")
        if host and code then
            p = { host = host, code = code }
        else
            p = { serial = payload }
        end
    end
    if event == "toggle-panel" then
        noctalia.togglePanel("omen/scrcpy:panel")
    elseif event == "panel-open" then
        panelOpen = true
        discover()
        publish()
    elseif event == "panel-close" then
        panelOpen = false
        publish()
    elseif event == "refresh" then
        discover()
    elseif event == "pair" then
        local host = tostring(p.host or "")
        local code = tostring(p.code or "")
        if host == "" or code == "" then
            setNotice("Enter the pairing ip:port and the 6-digit code")
        else
            adbAction({ "adb", "pair", host, code }, "Paired")
        end
    elseif event == "connect" then
        local serial = tostring(p.serial or "")
        if serial == "" then
            setNotice("Select a device first")
        else
            adbAction({ "adb", "connect", serial }, "Connected")
        end
    elseif event == "preview-args" then
        noctalia.state.set("argvPreview", A.build({ settings = defaults }))
    elseif event == "ping" then
        noctalia.state.set("lastPong", noctalia.nowMs())
    else
        noctalia.log(PLUGIN .. ": unknown command " .. tostring(event))
    end
end

noctalia.state.watch("cmd", function(cmd)
    if type(cmd) ~= "table" or type(cmd.action) ~= "string" then return end
    dispatch(cmd.action, cmd.payload)
end)

function onIpc(event, payload)
    dispatch(event, payload)
end

function onSuspend()
    discovering = false
end

function onResume()
    -- Wireless ADB connections do not survive sleep.
    discover()
end

function onExit(_signal, reason)
    noctalia.log(PLUGIN .. ": exit (" .. tostring(reason or "unknown") .. ")")
end

function update()
    if panelOpen and noctalia.nowMs() - lastDiscover >= DISCOVER_INTERVAL_MS then
        discover()
    end
end

loadKnown()
local passed, failed, failures = Selftest.run()
noctalia.log(string.format("%s: args self-test: %d passed, %d failed", PLUGIN, passed, failed))
for _, name in ipairs(failures) do noctalia.log(PLUGIN .. ": FAIL " .. name) end
noctalia.state.set("defaults", defaults)
noctalia.state.set("selftest", { passed = passed, failed = failed })

noctalia.setUpdateInterval(1000)
publish()
