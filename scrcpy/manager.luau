--!nonstrict
-- omen/scrcpy service: owns state, adb discovery, settings and scrcpy sessions.
--
-- State published for every entry (panel, bar, quick, shortcut):
--   devices      array of merged adb devices (see lib/devices.luau)
--   selected     serial of the chosen device ("" when none)
--   sessions     array of session rows (starting/running/stopping/stopped/error)
--   effective    defaults merged with the user's overrides
--   capabilities probe results used by gating
--   blocked      key -> reason (controls are disabled)
--   hints        key -> hint (control stays usable)
--   notice       { text, tone, seq } or nil
--   hasLast      whether "start last session" can do anything
--
-- Entries talk to this service through the "cmd" state key (see lib/shared.luau)
-- or through `noctalia msg plugin omen/scrcpy:manager all <event> [payload]`.

local PLUGIN = "omen/scrcpy"
local A = require("./lib/args.luau")
local Devices = require("./lib/devices.luau")
local Gating = require("./lib/gating.luau")
local Presets = require("./lib/presets.luau")
local Settings = require("./lib/settings.luau")
local Selftest = require("./lib/selftest.luau")

local defaults = Settings.readAll()
local dataDir = noctalia.pluginDataDir()
local knownPath = dataDir and (dataDir .. "/known.json") or nil
local overridesPath = dataDir and (dataDir .. "/overrides.json") or nil
local selectionPath = dataDir and (dataDir .. "/selection.json") or nil

local sessions = {}
local known = {}
local overrides = {}
local activePreset = "Default"
local devices = {}
local selection = { serial = "", product = "" }
local notice = nil
local hasLast = false
local lastSpec = nil
local dirtyAt = nil
local lastSdkSerial, lastSdkAt = "", 0
local caps = {
    adb = false, scrcpy = false, wireless = true,
    androidSdk = 0, v4l2Writable = false, deviceSelected = false,
}
local panelOpen = false
local discovering = false
local lastDiscover = 0
local DISCOVER_OPEN_MS = 3000
local DISCOVER_IDLE_MS = 15000
local NOTICE_MS = 9000
local SAVE_DEBOUNCE_MS = 500
local SDK_TTL_MS = 30000
local EXIT_GRACE_MS = 8000
local KILL_GRACE_MS = 2500

local function effective()
    return Settings.merge(defaults, overrides)
end

local function publish()
    local blocked, hints = Gating.evaluate(caps)
    noctalia.state.set("devices", devices)
    noctalia.state.set("selected", selection.serial or "")
    noctalia.state.set("sessions", sessions)
    noctalia.state.set("known", known)
    noctalia.state.set("panelOpen", panelOpen)
    noctalia.state.set("effective", effective())
    noctalia.state.set("capabilities", caps)
    noctalia.state.set("blocked", blocked)
    noctalia.state.set("hints", hints)
    noctalia.state.set("activePreset", activePreset)
    noctalia.state.set("notice", notice)
    noctalia.state.set("hasLast", hasLast)
end

local function setNotice(text, tone, sticky)
    local now = noctalia.nowMs()
    notice = {
        text = tostring(text or ""),
        tone = tone or "info",
        seq = (notice and notice.seq or 0) + 1,
        at = now,
        expiresAt = sticky and 0 or (now + NOTICE_MS),
    }
    publish()
end

local function clearNotice()
    if not notice then return end
    notice = nil
    publish()
end

-- ── persistence ──────────────────────────────────────────────────────────────

local function loadJson(path)
    if not path then return nil end
    local raw = noctalia.readFile(path)
    if not raw or raw == "" then return nil end
    local decoded = noctalia.json.decode(raw)
    if type(decoded) ~= "table" then return nil end
    return decoded
end

local function saveJson(path, value)
    if not path then return end
    local encoded = noctalia.json.encode(value)
    if encoded then noctalia.writeFile(path, encoded) end
end

local function loadKnown()
    known = loadJson(knownPath) or {}
end

local function saveKnown()
    saveJson(knownPath, known)
end

local function loadOverrides()
    local decoded = loadJson(overridesPath)
    if not decoded then return end
    overrides = type(decoded.settings) == "table" and decoded.settings or {}
    activePreset = tostring(decoded.preset or "Default")
end

local function saveOverrides()
    dirtyAt = nil
    saveJson(overridesPath, { settings = overrides, preset = activePreset })
end

local function markOverridesDirty()
    dirtyAt = noctalia.nowMs()
end

local function loadSelection()
    local decoded = loadJson(selectionPath)
    if decoded then
        selection.serial = tostring(decoded.serial or "")
        selection.product = tostring(decoded.product or "")
    else
        selection.serial = tostring(defaults.device_serial or "")
    end
end

local function saveSelection()
    saveJson(selectionPath, { serial = selection.serial, product = selection.product })
end

-- ── selection ────────────────────────────────────────────────────────────────

local function selectDevice(device, persist)
    selection.serial = device and device.serial or ""
    selection.product = device and device.product or ""
    if persist ~= false then saveSelection() end
    publish()
end

--- The chosen device, rematched across a changed wireless port.
-- mDNS endpoints change port on every reconnect, so the serial that was saved
-- is often stale; the product is stable for the same phone.
local function resolveSelected()
    local chosen = Devices.find(devices, selection.serial)
    if chosen then
        if selection.product ~= chosen.product then
            selection.product = chosen.product or ""
            saveSelection()
        end
        return chosen
    end
    if selection.product and selection.product ~= "" then
        for _, device in ipairs(devices) do
            if device.product == selection.product and device.state == "device" then
                selection.serial = device.serial
                saveSelection()
                return device
            end
        end
    end
    return nil
end

local function selectedSerial()
    local device = resolveSelected()
    return device and device.serial or ""
end

--- Auto-select the only ready phone when nothing is chosen yet.
local function autoSelect()
    if selection.serial ~= "" then return false end
    local ready
    for _, device in ipairs(devices) do
        if Devices.isReady(device) then
            if ready then return false end
            ready = device
        end
    end
    if not ready then return false end
    selection.serial = ready.serial
    selection.product = ready.product or ""
    saveSelection()
    return true
end

-- ── capabilities ─────────────────────────────────────────────────────────────

local function probeV4l2()
    local path = tostring(effective().v4l2_sink or "/dev/video10")
    local started = noctalia.runAsync({ "sh", "-c", 'test -w "$1"', "sh", path }, function(result)
        caps.v4l2Writable = result.exitCode == 0
        publish()
    end)
    if not started then caps.v4l2Writable = false end
end

local function probeSdk(serial, force)
    local now = noctalia.nowMs()
    if not caps.adb or serial == "" or serial == nil then
        caps.androidSdk = 0
        return
    end
    if not force and serial == lastSdkSerial and now - lastSdkAt < SDK_TTL_MS then return end
    lastSdkSerial, lastSdkAt = serial, now
    local started = noctalia.runAsync({ "adb", "-s", serial, "shell", "getprop", "ro.build.version.sdk" },
        function(result)
            if result.exitCode ~= 0 then return end
            caps.androidSdk = tonumber(noctalia.string.trim(result.stdout)) or 0
            publish()
        end)
    if not started then caps.androidSdk = 0 end
end

local function refreshCapabilities(forceSdk)
    caps.adb = noctalia.commandExists("adb")
    caps.scrcpy = noctalia.commandExists("scrcpy")
    local device = resolveSelected()
    caps.deviceSelected = device ~= nil and device.state == "device"
    local serial = device and device.serial or ""
    caps.wireless = serial ~= "" and Devices.isWireless(serial) or true
    probeV4l2()
    probeSdk(serial, forceSdk)
    publish()
end

-- ── discovery ────────────────────────────────────────────────────────────────

local function publishAfterDiscovery(deviceRows, mdnsRows)
    local previous = resolveSelected()
    local found = Devices.merge(deviceRows, mdnsRows)
    devices = found
    autoSelect()
    resolveSelected()

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
    for _, item in pairs(known) do
        if item.serial and not seen[item.serial] then
            for _, device in ipairs(found) do
                if item.product ~= "" and device.product == item.product
                    and device.serial ~= item.serial then
                    item.serial = device.serial
                    item.endpoint = device.endpoint
                    item.updatedAt = noctalia.nowMs()
                    break
                end
            end
        end
    end
    saveKnown()

    local device = resolveSelected()
    caps.deviceSelected = device ~= nil and device.state == "device"
    local serial = device and device.serial or ""
    caps.wireless = serial ~= "" and Devices.isWireless(serial) or true
    if previous and device and previous.serial ~= device.serial then
        setNotice("Reconnected " .. Devices.label(device) .. " on a new port", "success")
    end
    if serial ~= "" then probeSdk(serial, true) end
    publish()
end

local function discover()
    if discovering then return end
    if not caps.adb then
        refreshCapabilities()
        return
    end
    discovering = true
    lastDiscover = noctalia.nowMs()
    local rows, services = {}, {}
    local pending = 2
    local function done()
        pending = pending - 1
        if pending == 0 then
            discovering = false
            publishAfterDiscovery(rows, services)
        end
    end
    local startedDevices = noctalia.runAsync({ "adb", "devices", "-l" }, function(result)
        rows = Devices.parseDevices(result.stdout)
        if result.timedOut then setNotice("adb devices timed out", "warning") end
        done()
    end)
    if not startedDevices then rows = {}; done() end
    local startedMdns = noctalia.runAsync({ "adb", "mdns", "services" }, function(result)
        services = Devices.parseMdns(result.stdout)
        done()
    end)
    if not startedMdns then services = {}; done() end
end

local function adbAction(argv, success, failPrefix)
    if not caps.adb then
        setNotice("adb not found — install android-tools", "error", true)
        return
    end
    if not noctalia.runAsync(argv, function(result)
        local text = noctalia.string.trim(result.stdout or "")
        if text == "" then text = noctalia.string.trim(result.stderr or "") end
        if result.exitCode == 0 then
            setNotice(success .. (text ~= "" and (" · " .. text) or ""), "success")
        else
            setNotice((failPrefix or "adb failed") .. ": " .. (text ~= "" and text or ("exit " .. tostring(result.exitCode))), "error", true)
        end
        discover()
        refreshCapabilities(false)
    end) then
        setNotice("adb not found — install android-tools", "error", true)
    end
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
    if hard or session.state == "starting" then
        signal(session.pid, "KILL")
        session.state = "stopped"
        session.endedAt = noctalia.nowMs()
        return
    end
    session.state = "stopping"
    session.killAt = noctalia.nowMs() + KILL_GRACE_MS
    signal(session.pid, "TERM")
end

--- Record file for a session, with the shell-free absolute directory.
local function recordFileFor(settings, id)
    local dir = tostring(settings.record_dir or "~/Videos")
    dir = noctalia.expandPath(dir):gsub("/+$", "")
    local format = tostring(settings.record_format or "mp4")
    if dir == "" then dir = "/tmp" end
    noctalia.mkdirAll(dir)
    return dir .. "/scrcpy-" .. id .. "." .. format
end

local function startSession(kind, extras, serial)
    serial = tostring(serial or "")
    if serial == "" then serial = selectedSerial() end

    local settings = Settings.merge(effective(), extras or {})
    if kind == "record" then
        settings.record_enabled = true
        settings.record_only = true
    end

    -- What the session is for, independent of how it was launched: the panels
    -- show it as the row label (and the bar tooltip).
    local mode = "mirror"
    if kind == "record" then
        mode = "record"
    elseif settings.video_source == "camera" then
        local v4l2 = settings.v4l2_enabled == true or settings.v4l2_enabled == "true"
        mode = v4l2 and "webcam" or "camera"
    end

    local problems = Gating.validate(settings, caps, serial)
    if #problems > 0 then
        setNotice(table.concat(problems, " · "), "error", true)
        return nil
    end

    local id = nextId()
    local recordFile
    if settings.record_enabled == true or settings.record_enabled == "true" then
        recordFile = recordFileFor(settings, id)
    end

    local argv = A.build({
        settings = settings,
        serial = serial,
        recordFile = recordFile,
        recordDir = recordFile == nil and noctalia.expandPath(tostring(settings.record_dir or "~/Videos")) or nil,
        sessionId = id,
    })
    local session = {
        id = id,
        kind = kind or "mirror",
        mode = mode,
        serial = serial,
        argv = argv,
        recordFile = recordFile,
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
        session.endedAt = noctalia.nowMs()
        session.error = "Could not launch scrcpy (process limit or scrcpy missing)"
        setNotice(session.error, "error", true)
    else
        lastSpec = { kind = kind or "mirror", extras = extras or {}, serial = serial }
        hasLast = true
        local device = Devices.find(devices, serial)
        local label = device and Devices.label(device) or serial
        setNotice(string.upper(mode) .. " session started · " .. label, "info")
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
                elseif session.state == "stopping" then
                    session.state = "stopped"
                    session.endedAt = now
                    changed = true
                else
                    local line = lastLogLine(session.logPath)
                    session.error = line or "scrcpy exited without a message"
                    session.state = "error"
                    session.endedAt = now
                    setNotice(session.error, "error", true)
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

        if (session.state == "stopped" or session.state == "error") and not session.endedAt then
            session.endedAt = now
            changed = true
        end
        if session.endedAt and now - session.endedAt > EXIT_GRACE_MS then
            if session.pidPath then noctalia.removeFile(session.pidPath) end
            if session.logPath then noctalia.removeFile(session.logPath) end
            table.remove(sessions, i)
            changed = true
        end
    end
    if changed then publish() end
end

-- ── command bus / IPC ────────────────────────────────────────────────────────

local function decodePayload(payload)
    if type(payload) == "table" then return payload end
    if type(payload) ~= "string" or payload == "" then return {} end
    local decoded = noctalia.json.decode(payload)
    if type(decoded) == "table" then return decoded end
    local host, code = payload:match("^(%S+)%s+(%S+)$")
    if host and code then return { host = host, code = code } end
    return { serial = payload }
end

local function dispatch(event, payload)
    local p = decodePayload(payload)
    event = tostring(event or "")

    if event == "toggle-panel" then
        noctalia.togglePanel(PLUGIN .. ":panel")
    elseif event == "open-quick" then
        noctalia.togglePanel(PLUGIN .. ":quick")
    elseif event == "panel-open" then
        panelOpen = true
        publish()
        discover()
        refreshCapabilities(false)
    elseif event == "panel-close" then
        panelOpen = false
        publish()
    elseif event == "refresh" then
        discover()
        refreshCapabilities(false)
    elseif event == "select" then
        local serial = tostring(p.serial or "")
        local device = Devices.find(devices, serial)
        if device == nil and serial ~= "" then
            setNotice("That device is no longer connected", "warning")
        else
            selectDevice(device, true)
            refreshCapabilities(true)
        end
    elseif event == "pair" then
        local host, code = tostring(p.host or ""), tostring(p.code or "")
        if host == "" or code == "" then
            setNotice("Enter the pairing ip:port and the 6-digit code", "warning", true)
        else
            adbAction({ "adb", "pair", host, code }, "Paired", "Pairing failed")
        end
    elseif event == "connect" then
        local serial = tostring(p.serial or p.endpoint or "")
        if serial == "" then
            setNotice("Select a device first", "warning")
        else
            adbAction({ "adb", "connect", serial }, "Connected", "Connect failed")
        end
    elseif event == "disconnect" then
        local serial = tostring(p.serial or selectedSerial())
        if serial == "" then
            setNotice("Select a device first", "warning")
        else
            adbAction({ "adb", "disconnect", serial }, "Disconnected", "Disconnect failed")
        end
    elseif event == "forget" then
        local key = tostring(p.key or "")
        if key ~= "" and known[key] then
            known[key] = nil
            saveKnown()
            publish()
            setNotice("Forgot " .. key, "info")
        end
    elseif event == "start" then
        local serial = tostring(p.serial or "")
        if serial == "" then serial = selectedSerial() end
        if serial == "" then autoSelect(); serial = selectedSerial() end
        startSession(tostring(p.kind or "mirror"), type(p.extras) == "table" and p.extras or nil, serial)
    elseif event == "start-recording" then
        local serial = tostring(p.serial or "")
        if serial == "" then serial = selectedSerial() end
        startSession("record", nil, serial)
    elseif event == "start-last" then
        if lastSpec then
            local serial = p.serial and tostring(p.serial) or lastSpec.serial
            startSession(lastSpec.kind, lastSpec.extras, serial)
        else
            setNotice("No previous session to restart", "warning")
        end
    elseif event == "stop" then
        local session = findSession(tostring(p.id or ""))
        if session then
            stopSession(session, false)
            publish()
        else
            setNotice("Session not found", "warning")
        end
    elseif event == "stop-last" then
        local session = lastActive()
        if session then
            stopSession(session, false)
            publish()
        else
            setNotice("No active session", "warning")
        end
    elseif event == "clear-notice" then
        clearNotice()
    elseif event == "set-feature" then
        local key = tostring(p.key or "")
        if key ~= "" and Settings.keys ~= nil then
            overrides[key] = p.value
            activePreset = "Custom"
            markOverridesDirty()
            publish()
        end
    elseif event == "set-overrides" then
        overrides = type(p.settings) == "table" and p.settings or {}
        activePreset = tostring(p.preset or "Custom")
        markOverridesDirty()
        publish()
    elseif event == "apply-preset" then
        local name = tostring(p.preset or "Default")
        overrides = {}
        for key, value in pairs(Presets.get(name)) do overrides[key] = value end
        activePreset = name
        saveOverrides()
        setNotice("Preset applied · " .. name, "info")
    elseif event == "reset-overrides" then
        overrides = {}
        activePreset = "Default"
        saveOverrides()
        setNotice("Defaults restored", "info")
    elseif event == "open-settings" then
        noctalia.openSettings()
    elseif event == "preview-args" then
        local settings = effective()
        noctalia.state.set("argvPreview", A.build({
            settings = settings,
            serial = selectedSerial(),
            recordDir = noctalia.expandPath(tostring(settings.record_dir or "~/Videos")),
        }))
    elseif event == "ping" then
        noctalia.state.set("lastPong", noctalia.nowMs())
    else
        noctalia.log(PLUGIN .. ": unknown command " .. event)
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

function onConfigChanged()
    defaults = Settings.readAll()
    refreshCapabilities(true)
    setNotice("Settings reloaded", "info")
end

function onExit(_signal, reason)
    for _, session in ipairs(sessions) do
        if session.pid then signal(session.pid, "TERM") end
    end
    if dirtyAt then saveOverrides() end
    noctalia.log(PLUGIN .. ": exit (" .. tostring(reason or "unknown") .. ")")
end

function update()
    local now = noctalia.nowMs()
    local interval = panelOpen and DISCOVER_OPEN_MS or DISCOVER_IDLE_MS
    if now - lastDiscover >= interval then discover() end
    tickSessions()
    if dirtyAt and now - dirtyAt >= SAVE_DEBOUNCE_MS then saveOverrides() end
    if notice and (notice.expiresAt or 0) > 0 and now > notice.expiresAt then
        notice = nil
        publish()
    end
    if panelOpen then publish() end
end

loadKnown()
loadOverrides()
loadSelection()
refreshCapabilities(true)
local passed, failed, failures = Selftest.run()
noctalia.log(string.format("%s: self-test: %d passed, %d failed", PLUGIN, passed, failed))
for _, name in ipairs(failures) do noctalia.log(PLUGIN .. ": FAIL " .. name) end
noctalia.state.set("defaults", defaults)
noctalia.state.set("selftest", { passed = passed, failed = failed })

noctalia.setUpdateInterval(1000)
publish()
discover()
