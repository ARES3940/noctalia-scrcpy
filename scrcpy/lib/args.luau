--!nonstrict
-- Pure settings -> scrcpy argv builder. No I/O, no noctalia.* calls.
-- Every flag is a separate array element: the array is passed straight to
-- noctalia.runAsync(argv), so nothing is ever parsed by a shell.
-- Flag spellings verified against scrcpy 5.0.1 --help.

local M = {}

local function num(value, fallback)
    if type(value) == "number" then return value end
    if type(value) == "string" then return tonumber(value) or fallback end
    return fallback
end

local function str(value, fallback)
    if type(value) == "string" and value ~= "" then return value end
    return fallback
end

local function enabled(value, fallback)
    if type(value) == "boolean" then return value end
    if value == "true" then return true end
    if value == "false" then return false end
    return fallback == true
end

--- Build the scrcpy argument vector.
-- @param opts table {
--   settings = effective settings table,
--   serial   = optional adb serial (overrides settings.device_serial),
--   recordFile = optional explicit --record path,
--   sessionId  = optional short id used in a generated record filename,
-- }
-- @return array of strings, starting with "scrcpy"
function M.build(opts)
    opts = opts or {}
    local s = opts.settings or {}
    local out = { "scrcpy" }

    local function add(flag)
        table.insert(out, flag)
    end

    -- Device ---------------------------------------------------------------
    local serial = str(opts.serial, str(s.device_serial, ""))
    if serial ~= "" then add("--serial=" .. serial) end

    -- Video ----------------------------------------------------------------
    local maxSize = num(s.max_size, 0)
    if maxSize > 0 then add("--max-size=" .. tostring(maxSize)) end

    local bitrate = num(s.video_bit_rate, 0)
    if bitrate > 0 then add("--video-bit-rate=" .. tostring(bitrate) .. "K") end

    local maxFps = num(s.max_fps, 0)
    if maxFps > 0 then add("--max-fps=" .. tostring(maxFps)) end

    add("--video-codec=" .. str(s.video_codec, "h264"))

    local encoder = str(s.video_encoder, "")
    if encoder ~= "" then add("--video-encoder=" .. encoder) end

    local videoBuffer = num(s.video_buffer_ms, 0)
    if videoBuffer > 0 then add("--video-buffer=" .. tostring(videoBuffer)) end

    -- Audio ----------------------------------------------------------------
    if not enabled(s.audio_enabled, true) then
        add("--no-audio")
    else
        add("--audio-source=" .. str(s.audio_source, "output"))
        add("--audio-codec=" .. str(s.audio_codec, "opus"))
        add("--audio-bit-rate=" .. tostring(num(s.audio_bit_rate, 128)) .. "K")
        local audioBuffer = num(s.audio_buffer_ms, 0)
        if audioBuffer > 0 then add("--audio-buffer=" .. tostring(audioBuffer)) end
    end

    -- Recording ------------------------------------------------------------
    if enabled(s.record_enabled, false) then
        local format = str(s.record_format, "mp4")
        local file = str(opts.recordFile, "")
        if file == "" then
            local dir = str(s.record_dir, "~/Videos"):gsub("/+$", "")
            file = dir .. "/scrcpy-" .. str(opts.sessionId, "1") .. "." .. format
        end
        add("--record=" .. file)
        add("--record-format=" .. format)
        if enabled(s.record_only, false) then
            add("--no-playback")
            add("--no-window")
        end
    end

    -- Virtual display ------------------------------------------------------
    if enabled(s.new_display, false) then
        local size = str(s.new_display_size, "1920x1080")
        local dpi = num(s.new_display_dpi, 0)
        add("--new-display=" .. size .. (dpi > 0 and ("/" .. tostring(dpi)) or ""))
        if enabled(s.vd_no_system_decorations, false) then add("--no-vd-system-decorations") end
    end

    local startApp = str(s.start_app, "")
    if startApp ~= "" then add("--start-app=" .. startApp) end

    -- Screen ---------------------------------------------------------------
    if enabled(s.turn_screen_off, false) then add("--turn-screen-off") end
    if enabled(s.stay_awake, false) then add("--stay-awake") end
    if enabled(s.power_off_on_close, false) then add("--power-off-on-close") end
    local timeout = num(s.screen_off_timeout, 0)
    if timeout > 0 then add("--screen-off-timeout=" .. tostring(timeout)) end
    if not enabled(s.clipboard_autosync, true) then add("--no-clipboard-autosync") end
    if enabled(s.show_touches, false) then add("--show-touches") end
    if enabled(s.no_control, false) then add("--no-control") end

    -- Camera / webcam ------------------------------------------------------
    if str(s.video_source, "display") == "camera" then
        add("--video-source=camera")
        add("--camera-facing=" .. str(s.camera_facing, "back"))
        local cameraSize = str(s.camera_size, "")
        if cameraSize ~= "" then add("--camera-size=" .. cameraSize) end
        local cameraId = str(s.camera_id, "")
        if cameraId ~= "" then add("--camera-id=" .. cameraId) end
        local cameraFps = num(s.camera_fps, 0)
        if cameraFps > 0 then add("--camera-fps=" .. tostring(cameraFps)) end
    end

    if enabled(s.v4l2_enabled, false) then
        add("--v4l2-sink=" .. str(s.v4l2_sink, "/dev/video10"))
        -- A webcam sink does not need a local video window.
        add("--no-window")
    end

    -- HID ------------------------------------------------------------------
    for _, spec in ipairs({
        { value = str(s.keyboard_mode, "disabled"), prefix = "--keyboard=" },
        { value = str(s.mouse_mode, "disabled"), prefix = "--mouse=" },
        { value = str(s.gamepad_mode, "disabled"), prefix = "--gamepad=" },
    }) do
        if spec.value ~= "disabled" then add(spec.prefix .. spec.value) end
    end
    if enabled(s.otg, false) then add("--otg") end

    -- Window ---------------------------------------------------------------
    if enabled(s.always_on_top, false) then add("--always-on-top") end
    if enabled(s.fullscreen, false) then add("--fullscreen") end
    add("--window-title=" .. str(s.window_title, "noctalia-scrcpy"))
    local width = num(s.window_width, 0)
    if width > 0 then add("--window-width=" .. tostring(width)) end
    local height = num(s.window_height, 0)
    if height > 0 then add("--window-height=" .. tostring(height)) end

    local displayId = num(s.display_id, 0)
    if displayId > 0 then add("--display-id=" .. tostring(displayId)) end
    local orientation = tostring(s.orientation or "0")
    if orientation ~= "0" then add("--orientation=" .. orientation) end

    return out
end

--- Display-only: a readable one-line preview of an argv array.
-- Never use the return value to launch anything; pass the array instead.
function M.preview(argv)
    return table.concat(argv or {}, " ")
end

return M
