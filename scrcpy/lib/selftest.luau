--!nonstrict
-- Pure unit tests for the argv builder. No phone, no shell, no I/O.
-- The manager service runs this at load and logs PASS/FAIL to the Noctalia log.

local A = require("./args.luau")
local P = require("./presets.luau")

local M = {}

local function contains(list, value)
    for _, item in ipairs(list) do
        if item == value then return true end
    end
    return false
end

local function base()
    return {
        device_serial = "",
        max_size = 1024,
        video_bit_rate = 8000,
        max_fps = 60,
        video_codec = "h264",
        video_encoder = "",
        video_buffer_ms = 0,
        audio_enabled = true,
        audio_source = "output",
        audio_codec = "opus",
        audio_bit_rate = 128,
        audio_buffer_ms = 50,
        record_enabled = false,
        record_format = "mp4",
        record_dir = "~/Videos",
        record_only = false,
        new_display = false,
        new_display_size = "1920x1080",
        new_display_dpi = 240,
        vd_no_system_decorations = false,
        start_app = "",
        turn_screen_off = false,
        stay_awake = true,
        power_off_on_close = false,
        screen_off_timeout = 0,
        clipboard_autosync = true,
        show_touches = false,
        no_control = false,
        video_source = "display",
        camera_facing = "back",
        camera_size = "",
        camera_id = "",
        camera_fps = 0,
        v4l2_enabled = false,
        v4l2_sink = "/dev/video10",
        keyboard_mode = "disabled",
        mouse_mode = "disabled",
        gamepad_mode = "disabled",
        otg = false,
        always_on_top = false,
        fullscreen = false,
        window_title = "noctalia-scrcpy",
        window_width = 0,
        window_height = 0,
        display_id = 0,
        orientation = "0",
    }
end

local function with(overrides)
    local settings = base()
    for key, value in pairs(overrides or {}) do settings[key] = value end
    return settings
end

function M.run()
    local passed, failed = 0, 0
    local failures = {}

    local function check(name, condition)
        if condition then
            passed = passed + 1
        else
            failed = failed + 1
            table.insert(failures, name)
        end
    end

    local function build(settings, opts)
        local o = opts or {}
        o.settings = settings or base()
        return A.build(o)
    end

    -- Shape ---------------------------------------------------------------
    local default = build()
    check("argv is an array starting with scrcpy", default[1] == "scrcpy" and #default > 1)
    local allStrings = true
    for _, arg in ipairs(default) do
        if type(arg) ~= "string" then allStrings = false end
    end
    check("every argv element is a string", allStrings)
    check("window title always present", contains(default, "--window-title=noctalia-scrcpy"))
    check("no record flag by default", not contains(default, "--record=~/Videos/scrcpy-1.mp4"))

    -- Video ----------------------------------------------------------------
    check("max size", contains(build(with({ max_size = 480 })), "--max-size=480"))
    check("bitrate uses K suffix", contains(default, "--video-bit-rate=8000K"))
    check("max fps", contains(default, "--max-fps=60"))
    check("codec", contains(default, "--video-codec=h264"))
    check("encoder", contains(build(with({ video_encoder = "c2.qti.avc.encoder" })), "--video-encoder=c2.qti.avc.encoder"))
    check("video buffer", contains(build(with({ video_buffer_ms = 80 })), "--video-buffer=80"))
    check("display id omitted when zero", not contains(default, "--display-id=0"))
    check("display id when set", contains(build(with({ display_id = 2 })), "--display-id=2"))
    check("orientation when set", contains(build(with({ orientation = "90" })), "--orientation=90"))

    -- Audio ----------------------------------------------------------------
    local noAudio = build(with({ audio_enabled = false }))
    check("--no-audio when disabled", contains(noAudio, "--no-audio"))
    check("no audio source when disabled", not contains(noAudio, "--audio-source=output"))
    check("audio source", contains(default, "--audio-source=output"))
    check("audio codec", contains(default, "--audio-codec=opus"))
    check("audio bitrate K suffix", contains(default, "--audio-bit-rate=128K"))
    check("audio buffer", contains(default, "--audio-buffer=50"))

    -- Recording ------------------------------------------------------------
    local record = build(with({ record_enabled = true, record_format = "mkv" }), { sessionId = "7" })
    check("record path", contains(record, "--record=~/Videos/scrcpy-7.mkv"))
    check("record format", contains(record, "--record-format=mkv"))
    check("explicit record file wins", contains(A.build({
        settings = with({ record_enabled = true }),
        recordFile = "/tmp/capture.mp4",
    }), "--record=/tmp/capture.mp4"))
    local recordOnly = build(with({ record_enabled = true, record_only = true }))
    check("no playback", contains(recordOnly, "--no-playback"))
    check("no window for record only", contains(recordOnly, "--no-window"))

    -- Virtual display ------------------------------------------------------
    local vd = build(with({ new_display = true, vd_no_system_decorations = true, start_app = "org.example.game" }))
    check("new display size and dpi", contains(vd, "--new-display=1920x1080/240"))
    check("no system decorations", contains(vd, "--no-vd-system-decorations"))
    check("start app", contains(vd, "--start-app=org.example.game"))

    -- Screen / clipboard ---------------------------------------------------
    local screen = build(with({
        turn_screen_off = true, stay_awake = true, power_off_on_close = true,
        screen_off_timeout = 30, clipboard_autosync = false, show_touches = true, no_control = true,
    }))
    check("turn screen off", contains(screen, "--turn-screen-off"))
    check("stay awake", contains(screen, "--stay-awake"))
    check("power off on close", contains(screen, "--power-off-on-close"))
    check("screen off timeout", contains(screen, "--screen-off-timeout=30"))
    check("clipboard autosync off", contains(screen, "--no-clipboard-autosync"))
    check("show touches", contains(screen, "--show-touches"))
    check("read only", contains(screen, "--no-control"))

    -- Camera / webcam ------------------------------------------------------
    local camera = build(with({
        video_source = "camera", camera_facing = "front",
        camera_size = "1920x1080", camera_id = "3", camera_fps = 30,
    }))
    check("camera source", contains(camera, "--video-source=camera"))
    check("camera facing", contains(camera, "--camera-facing=front"))
    check("camera size", contains(camera, "--camera-size=1920x1080"))
    check("camera id", contains(camera, "--camera-id=3"))
    check("camera fps", contains(camera, "--camera-fps=30"))

    local v4l2 = build(with({ v4l2_enabled = true, v4l2_sink = "/dev/video9" }))
    check("v4l2 sink", contains(v4l2, "--v4l2-sink=/dev/video9"))
    check("v4l2 implies no window", contains(v4l2, "--no-window"))

    -- HID / OTG ------------------------------------------------------------
    local hid = build(with({ keyboard_mode = "uhid", mouse_mode = "sdk", gamepad_mode = "uhid", otg = true }))
    check("keyboard uhid", contains(hid, "--keyboard=uhid"))
    check("mouse sdk", contains(hid, "--mouse=sdk"))
    check("gamepad uhid", contains(hid, "--gamepad=uhid"))
    check("otg", contains(hid, "--otg"))

    -- Device / window ------------------------------------------------------
    check("serial from opts", contains(A.build({ settings = base(), serial = "192.168.0.11:38377" }), "--serial=192.168.0.11:38377"))
    check("serial from settings", contains(build(with({ device_serial = "usb-device" })), "--serial=usb-device"))
    local window = build(with({
        always_on_top = true, fullscreen = true,
        window_width = 540, window_height = 960,
    }))
    check("always on top", contains(window, "--always-on-top"))
    check("fullscreen", contains(window, "--fullscreen"))
    check("window width", contains(window, "--window-width=540"))
    check("window height", contains(window, "--window-height=960"))

    -- Presets --------------------------------------------------------------
    local function presetArgs(name)
        local s = base()
        for key, value in pairs(P.get(name)) do s[key] = value end
        return A.build({ settings = s })
    end
    check("Gaming preset uses uhid", contains(presetArgs("Gaming"), "--keyboard=uhid"))
    check("Low bandwidth disables audio", contains(presetArgs("Low bandwidth"), "--no-audio"))
    check("Low bandwidth caps size", contains(presetArgs("Low bandwidth"), "--max-size=480"))
    check("Webcam preset uses camera", contains(presetArgs("Webcam"), "--video-source=camera"))
    check("Webcam preset uses v4l2", contains(presetArgs("Webcam"), "--v4l2-sink=/dev/video10"))
    check("Record only preset records", contains(presetArgs("Record only"), "--record=~/Videos/scrcpy-1.mp4"))
    check("Record only preset hides window", contains(presetArgs("Record only"), "--no-window"))
    check("all five presets declared", #P.order == 5 and P.presets[P.order[1]] ~= nil
        and P.presets[P.order[5]] ~= nil)

    -- Device parsing / dedupe ---------------------------------------------
    local D = require("./devices.luau")
    local sampleDevices = table.concat({
        "List of devices attached",
        "192.168.0.11:38377     device product:lavender model:Redmi_Note_7 device:lavender transport_id:3",
        "adb-c297c4b2-xIfLEq._adb-tls-connect._tcp device product:lavender model:Redmi_Note_7 device:lavender transport_id:1",
        "emulator-5554  unauthorized",
        "",
    }, "\n")
    local parsed = D.parseDevices(sampleDevices)
    check("parses three adb device rows", #parsed == 3)
    check("parses device model", parsed[1].model == "Redmi Note 7")
    check("detects ip wireless serial", D.isWireless("192.168.0.11:38377"))
    check("detects mdns wireless serial", D.isWireless("adb-x._adb-tls-connect._tcp"))
    check("detects usb serial", not D.isWireless("emulator-5554"))
    local mdns = D.parseMdns("List of discovered mdns services\nadb-c297c4b2-xIfLEq\t_adb-tls-connect._tcp\t192.168.0.11:38377\n")
    check("parses mdns endpoint", #mdns == 1 and mdns[1].host == "192.168.0.11" and mdns[1].port == "38377")
    local merged = D.merge(parsed, mdns)
    check("dedupes mDNS and ip serials", #merged == 2)
    check("prefers ip:port serial", merged[1].serial == "192.168.0.11:38377")
    check("attaches endpoint from mdns", merged[1].endpoint == "192.168.0.11:38377")

    -- Capability gating ----------------------------------------------------
    local G = require("./gating.luau")
    local function caps(overrides)
        local c = { adb = true, scrcpy = true, wireless = false, androidSdk = 37,
            v4l2Writable = true, deviceSelected = true }
        for k, v in pairs(overrides or {}) do c[k] = v end
        return c
    end
    local capable, hints = G.evaluate(caps())
    check("nothing blocked on a capable USB device", next(capable) == nil and next(hints) == nil)
    local wifiBlocked, wifiHints = G.evaluate(caps({ wireless = true }))
    check("OTG blocked over wifi", wifiBlocked.otg ~= nil)
    check("AOA hint over wifi", wifiHints.keyboard_mode ~= nil)
    check("UHID still allowed over wifi", wifiBlocked.keyboard_mode == nil)
    check("V4L2 blocked without loopback", G.evaluate(caps({ v4l2Writable = false })).v4l2_enabled ~= nil)
    local old = G.evaluate(caps({ androidSdk = 28 }))
    check("max fps blocked below Android 10", old.max_fps ~= nil)
    check("camera blocked below Android 12", old.video_source ~= nil)
    check("virtual display blocked below Android 14", old.new_display ~= nil)
    check("everything blocked without adb", G.evaluate(caps({ adb = false })).all ~= nil)

    return passed, failed, failures
end

return M
