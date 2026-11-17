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
        blocked.all = "No device selected"
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

return M
