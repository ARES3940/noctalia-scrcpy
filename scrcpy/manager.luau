--!nonstrict
-- omen/scrcpy service: owns state, adb discovery, settings and scrcpy sessions.
-- Session 4 adds detached process launch, PID-file liveness, stop and errors.

local PLUGIN = "omen/scrcpy"
local A = require("./lib/args.luau")
local Devices = require("./lib/devices.luau")
local Gating = require("./lib/gating.luau")
local Settings = require("./lib/settings.luau")
local Selftest = require("./lib/selftest.luau")

local defaults = Settings.readAll()
local dataDir = noctalia.pluginDataDir()
local knownPath = dataDir and (dataDir .. "/known.json") or nil

local sessions = {}
local known = {}
local overrides = {}
local caps = {
    adb = false, scrcpy = false, wireless = true,
    androidSdk = 0, v4l2Writable = false, deviceSelected = false,
}
local panelOpen = false
local discovering = false
local lastDiscover = 0
local lastSpec = nil
local DISCOVER_INTERVAL_MS = 3000
local EXIT_GRACE_MS = 10000
local KILL_GRACE_MS = 2000

local function effective()
    return Settings.merge(defaults, overrides)
end

local function publish()
    local blocked, hints = Gating.evaluate(caps)
    noctalia.state.set("sessions", sessions)
    noctalia.state.set("known", known)
    noctalia.state.set("panelOpen", panelOpen)
    noctalia.state.set("effective", effective())
    noctalia.state.set("capabilities", caps)
    noctalia.state.set("blocked", blocked)
    noctalia.state.set("hints", hints)
end

local function selectedSerial()
    if lastSpec and lastSpec.serial and lastSpec.serial ~= "" then return lastSpec.serial end
    for _, device in ipairs(noctalia.state.get("devices") or {}) do
        if device.state == "device" then return device.serial end
    end
    return tostring(defaults.device_serial or "")
end

local function refreshCapabilities()
    caps.adb = noctalia.commandExists("adb")
    caps.scrcpy = noctalia.commandExists("scrcpy")
    local serial = selectedSerial()
    caps.deviceSelected = serial ~= ""
    caps.wireless = Devices.isWireless(serial)

    local v4l2Path = tostring(effective().v4l2_sink or "/dev/video10")
    noctalia.runAsync({ "sh", "-c", 'test -w "$1"', "sh", v4l2Path }, function(result)
        caps.v4l2Writable = result.exitCode == 0
        publish()
    end)

    if caps.adb and serial ~= "" then
        noctalia.runAsync({ "adb", "-s", serial, "shell", "getprop", "ro.build.version.sdk" }, function(result)
            caps.androidSdk = tonumber(noctalia.string.trim(result.stdout)) or 0
            publish()
        end)
    end
    publish()
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
    local found = Devices.merge(deviceRows, mdnsRows)
    local seen = {}
    for _, device in ipairs(found) do
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
    for _, item in pairs(previous) do
        if item.serial and not seen[item.serial] then
            for _, device in ipairs(found) do
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
    local rows, services = {}, {}
    local pending = 2
    local function done()
        pending = pending - 1
        if pending == 0 then
            discovering = false
            afterDiscovery(rows, services)
        end
    end
    if not noctalia.runAsync({ "adb", "devices", "-l" }, function(result)
        rows = Devices.parseDevices(result.stdout)
        if result.timedOut then setNotice("adb devices timed out") end
        done()
    end) then rows = {}; done() end
    if not noctalia.runAsync({ "adb", "mdns", "services" }, function(result)
        services = Devices.parseMdns(result.stdout)
        done()
    end) then services = {}; done() end
end

local function adbAction(argv, success)
    if not noctalia.runAsync(argv, function(result)
        local text = result.stdout ~= "" and result.stdout or result.stderr
        if result.exitCode == 0 then
            setNotice(success .. (text ~= "" and (": " .. text) or ""))
        else
            setNotice("adb failed: " .. (text ~= "" and text or ("exit " .. tostring(result.exitCode))))
        end
        discover()
        refreshCapabilities()
    end) then setNotice("adb not found — install android-tools") end
end

-- ── scrcpy sessions ──────────────────────────────────────────────────────────

local function nextId()
    return tostring(noctalia.nowMs()) .. "-" .. tostring(math.random(100, 999))
end

local function readPid(path)
    if not path then return nil end
    local raw = noctalia.readFile(path)
    if not raw then return nil end
    local pid = tonumber(noctalia.string.trim(raw))
    if not pid or pid <= 1 then return nil end
    return pid
end

local function alive(pid)
    if not pid then return false end
    return noctalia.fileExists("/proc/" .. tostring(pid))
end

local function lastLogLine(path)
    if not path then return nil end
    local raw = noctalia.readFile(path)
    if not raw then return nil end
    local last, errorLine
    for line in string.gmatch(raw, "[^\r\n]+") do
        last = line
        -- scrcpy prints its help/version line last on failure; the useful
        -- message is the ERROR line above it.
        if string.match(line, "^ERROR:") or string.match(line, "^error:")
            or string.find(string.lower(line), "failed", 1, true) then
            errorLine = line
        end
    end
    return errorLine or last
end

local function signal(pid, name)
    if not pid then return end
    noctalia.runAsync({ "sh", "-c", 'kill -' .. name .. ' "$1" 2>/dev/null', "noctalia-scrcpy-kill", tostring(pid) })
end

local function stopSession(session, hard)
    if not session then return end
    if hard then
        signal(session.pid, "KILL")
        session.state = "stopped"
        session.error = session.error or "stopped (forced)"
        return
    end
    session.state = "stopping"
    session.killAt = noctalia.nowMs() + KILL_GRACE_MS
    signal(session.pid, "TERM")
end

local function startSession(kind, overrides, serial)
    local id = nextId()
    local settings = effective()
    local recordFile = nil
    if kind == "record" then
        local dir = tostring(settings.record_dir or "~/Videos"):gsub("/+$", "")
        recordFile = dir .. "/scrcpy-" .. id .. ".mp4"
    end
    local argv = A.build({
        settings = settings,
        serial = serial or settings.device_serial,
        recordFile = recordFile,
        sessionId = id,
    })
    local session = {
        id = id,
        kind = kind or "mirror",
        serial = serial or settings.device_serial or "",
        argv = argv,
        state = "starting",
        error = nil,
        startedAt = noctalia.nowMs(),
        pidPath = dataDir and (dataDir .. "/session-" .. id .. ".pid") or nil,
        logPath = dataDir and (dataDir .. "/session-" .. id .. ".log") or nil,
    }
    table.insert(sessions, session)

    -- Detached launch with a PID file: runAsync's callback path has a 5 s
    -- timeout and would kill a long-lived mirror. The fixed shim keeps every
    -- scrcpy argument as a separate positional parameter (no shell string).
    local shim = 'pid=$1; log=$2; shift 2; echo $$ > "$pid"; exec "$@" > "$log" 2>&1'
    local cmd = { "sh", "-c", shim, "noctalia-scrcpy", session.pidPath, session.logPath }
    for _, arg in ipairs(argv) do table.insert(cmd, arg) end

    if not noctalia.runAsync(cmd) then
        session.state = "error"
        session.error = "Could not launch scrcpy (process limit or scrcpy missing)"
    else
        setNotice("Starting " .. session.kind .. " session " .. id)
    end
    publish()
    return session
end

local function findSession(id)
    for _, session in ipairs(sessions) do
        if session.id == id then return session end
    end
    return nil
end

local function lastActive()
    for i = #sessions, 1, -1 do
        local state = sessions[i].state
        if state ~= "stopped" and state ~= "error" then return sessions[i] end
    end
    return nil
end

local function tickSessions()
    local now = noctalia.nowMs()
    local changed = false
    for i = #sessions, 1, -1 do
        local session = sessions[i]
        local pid = readPid(session.pidPath)
        if pid then session.pid = pid end

        if session.state ~= "stopped" and session.state ~= "error" then
            if not alive(pid) then
                if session.state == "starting" and now - session.startedAt < 1000 then
                    -- Give the detached process time to write its PID file.
                else
                    local last = lastLogLine(session.logPath)
                    session.error = last or "scrcpy exited without a message"
                    session.state = "error"
                    changed = true
                end
            elseif session.state == "stopping" and now >= (session.killAt or 0) then
                stopSession(session, true)
                changed = true
            elseif session.state == "starting" and pid then
                session.state = "running"
                changed = true
            end
        end

        if session.state == "stopped" or session.state == "error" then
            if not session.exitedAt then session.exitedAt = now; changed = true end
            if now - session.exitedAt > EXIT_GRACE_MS then
                if session.pidPath then noctalia.removeFile(session.pidPath) end
                if session.logPath then noctalia.removeFile(session.logPath) end
                table.remove(sessions, i)
                changed = true
            end
        end
    end
    if changed then publish() end
end

-- ── IPC / command bus ────────────────────────────────────────────────────────

local function dispatch(event, payload)
    local p = type(payload) == "table" and payload or {}
    if type(payload) == "string" then
        local decoded = noctalia.json.decode(payload)
        if type(decoded) == "table" then
            p = decoded
        else
            local host, code = payload:match("^(%S+)%s+(%S+)$")
            if host and code then p = { host = host, code = code } else p = { serial = payload } end
        end
    end

    if event == "toggle-panel" then
        noctalia.togglePanel("omen/scrcpy:panel")
    elseif event == "panel-open" then
        panelOpen = true
        discover()
        refreshCapabilities()
        publish()
    elseif event == "panel-close" then
        panelOpen = false
        publish()
    elseif event == "refresh" then
        discover()
    elseif event == "pair" then
        local host, code = tostring(p.host or ""), tostring(p.code or "")
        if host == "" or code == "" then
            setNotice("Enter the pairing ip:port and the 6-digit code")
        else
            adbAction({ "adb", "pair", host, code }, "Paired")
        end
    elseif event == "connect" then
        local serial = tostring(p.serial or "")
        if serial == "" then setNotice("Select a device first")
        else adbAction({ "adb", "connect", serial }, "Connected") end
    elseif event == "start" then
        local serial = tostring(p.serial or "")
        if serial == "" then
            for _, device in ipairs(noctalia.state.get("devices") or {}) do
                serial = device.serial
                break
            end
        end
        lastSpec = { kind = tostring(p.kind or "mirror"), settings = p.settings, serial = serial }
        startSession(lastSpec.kind, p.settings, serial)
    elseif event == "start-recording" then
        lastSpec = { kind = "record", settings = nil, serial = tostring(p.serial or "") }
        startSession("record", { record_enabled = true, record_only = true }, lastSpec.serial)
    elseif event == "start-last" then
        if lastSpec then
            startSession(lastSpec.kind, lastSpec.settings, lastSpec.serial)
        else
            setNotice("No previous session to restart")
        end
    elseif event == "stop" then
        local session = findSession(tostring(p.id or ""))
        if session then stopSession(session, false) else setNotice("Session not found") end
    elseif event == "stop-last" then
        local session = lastActive()
        if session then stopSession(session, false) else setNotice("No active session") end
    elseif event == "set-feature" then
        local key = tostring(p.key or "")
        if key ~= "" then
            overrides[key] = p.value
            publish()
        end
    elseif event == "set-overrides" then
        overrides = type(p.settings) == "table" and p.settings or {}
        publish()
    elseif event == "preview-args" then
        noctalia.state.set("argvPreview", A.build({ settings = effective() }))
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
    discover()
end

function onExit(_signal, reason)
    for _, session in ipairs(sessions) do
        if session.pid then signal(session.pid, "TERM") end
    end
    noctalia.log(PLUGIN .. ": exit (" .. tostring(reason or "unknown") .. ")")
end

function update()
    if panelOpen and noctalia.nowMs() - lastDiscover >= DISCOVER_INTERVAL_MS then discover() end
    tickSessions()
end

loadKnown()
refreshCapabilities()
local passed, failed, failures = Selftest.run()
noctalia.log(string.format("%s: args self-test: %d passed, %d failed", PLUGIN, passed, failed))
for _, name in ipairs(failures) do noctalia.log(PLUGIN .. ": FAIL " .. name) end
noctalia.state.set("defaults", defaults)
noctalia.state.set("selftest", { passed = passed, failed = failed })

noctalia.setUpdateInterval(1000)
publish()
