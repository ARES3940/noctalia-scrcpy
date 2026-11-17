--!nonstrict
-- Pure capability gating: which features are available for the current device.
-- No I/O: the service supplies the capability snapshot.

local M = {}

--- @param caps table {
--   adb = bool, scrcpy = bool, wireless = bool,
--   androidSdk = number, v4l2Writable = bool, deviceSelected = bool,
-- }
--- @return blocked table<key, reason>, hints table<key, hint>
function M.evaluate(caps)
    caps = caps or {}
    local blocked, hints = {}, {}
    local sdk = tonumber(caps.androidSdk) or 0
    local wireless = caps.wireless == true

    if caps.adb == false then
        blocked.all = "adb not found — install android-tools"
        return blocked, hints
    end
    if caps.scrcpy == false then
        blocked.all = "scrcpy not found — install scrcpy"
        return blocked, hints
    end
    if caps.deviceSelected == false then
        blocked.device = "No device ready"
        return blocked, hints
    end

    -- USB-only: adb over tcpip cannot carry AOA/OTG.
    if wireless then
        blocked.otg = "OTG needs a USB connection"
        hints.keyboard_mode = "AOA needs USB; SDK and UHID work over wifi"
        hints.mouse_mode = "AOA needs USB; SDK and UHID work over wifi"
        hints.gamepad_mode = "AOA needs USB; UHID works over wifi"
    end

    -- V4L2 needs a writable loopback node.
    if caps.v4l2Writable ~= true then
        blocked.v4l2_enabled = "No writable V4L2 loopback device"
        blocked.v4l2_sink = "No writable V4L2 loopback device"
    end

    -- The embedded preview additionally needs the companion toolchain.
    if caps.python3 == false or caps.ffmpeg == false then
        blocked.embedded = "Embedded preview needs python3 and ffmpeg"
    elseif caps.v4l2Writable ~= true then
        blocked.embedded = "Embedded preview needs a writable V4L2 loopback device"
    end

    -- Android version floors reported by scrcpy --help.
    if sdk > 0 and sdk < 29 then
        blocked.max_fps = "Frame-rate limit needs Android 10+"
    end
    if sdk > 0 and sdk < 31 then
        blocked.video_source = "Camera mirroring needs Android 12+"
        blocked.camera_facing = "Camera mirroring needs Android 12+"
        blocked.camera_size = "Camera mirroring needs Android 12+"
        blocked.camera_id = "Camera mirroring needs Android 12+"
    end
    if sdk > 0 and sdk < 34 then
        blocked.new_display = "Virtual display needs Android 14+"
        blocked.new_display_size = "Virtual display needs Android 14+"
        blocked.new_display_dpi = "Virtual display needs Android 14+"
        blocked.vd_no_system_decorations = "Virtual display needs Android 14+"
    end

    return blocked, hints
end

--- Last-line validation before a launch. Unlike evaluate(), which disables
-- controls, this rejects an actual settings snapshot; it also catches stale
-- overrides and values typed into the manifest settings view.
--- @param settings table effective settings
--- @param caps table capability snapshot
--- @param serial string? selected adb serial
--- @return { string } problems (empty when the launch may proceed)
function M.validate(settings, caps, serial)
    settings = settings or {}
    caps = caps or {}
    local out = {}
    local function add(message)
        out[#out + 1] = message
    end

    if caps.adb == false then add("adb not found — install android-tools") end
    if caps.scrcpy == false then add("scrcpy not found — install scrcpy") end
    if serial == nil or serial == "" then add("No device ready — select one in Devices") end

    if caps.wireless == true then
        if settings.otg == true then add("OTG needs a USB connection") end
        local labels = { keyboard_mode = "Keyboard", mouse_mode = "Mouse", gamepad_mode = "Gamepad" }
        for _, field in ipairs({ "keyboard_mode", "mouse_mode", "gamepad_mode" }) do
            if settings[field] == "aoa" then
                add(labels[field] .. " AOA mode needs USB — use SDK or UHID")
            end
        end
    end

    if settings.v4l2_enabled == true and caps.v4l2Writable ~= true then
        add("No writable V4L2 loopback device")
    end
    if settings.embedded == true then
        if caps.python3 == false or caps.ffmpeg == false then
            add("Embedded preview needs python3 and ffmpeg")
        end
    end

    local sdk = tonumber(caps.androidSdk) or 0
    if settings.video_source == "camera" and sdk > 0 and sdk < 31 then
        add("Camera mirroring needs Android 12+")
    end
    if settings.new_display == true and sdk > 0 and sdk < 34 then
        add("Virtual display needs Android 14+")
    end

    return out
end

return M
