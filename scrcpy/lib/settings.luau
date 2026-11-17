--!nonstrict
-- Reads the manifest-declared defaults into a plain table.
-- Keeping the list here means the shipped validator can see that every declared
-- setting is consumed. Per-session overrides are merged in Session 6.

local KEYS = {
    "device_serial",
    "max_size", "video_bit_rate", "max_fps", "video_codec", "video_encoder", "video_buffer_ms",
    "audio_enabled", "audio_source", "audio_codec", "audio_bit_rate", "audio_buffer_ms",
    "record_enabled", "record_format", "record_dir", "record_only",
    "new_display", "new_display_size", "new_display_dpi", "vd_no_system_decorations", "start_app",
    "turn_screen_off", "stay_awake", "power_off_on_close", "screen_off_timeout",
    "clipboard_autosync", "show_touches", "no_control",
    "video_source", "camera_facing", "camera_size", "camera_id", "camera_fps",
    "v4l2_enabled", "v4l2_sink",
    "keyboard_mode", "mouse_mode", "gamepad_mode", "otg",
    "always_on_top", "fullscreen", "window_title", "window_width", "window_height",
    "display_id", "orientation",
}

local M = {}

M.keys = KEYS

function M.readAll()
    local out = {}
    for _, key in ipairs(KEYS) do
        out[key] = noctalia.getConfig(key)
    end
    return out
end

--- Merge a sparse override table over a settings table (pure).
function M.merge(base, overrides)
    local out = {}
    for key, value in pairs(base or {}) do out[key] = value end
    for key, value in pairs(overrides or {}) do out[key] = value end
    return out
end

return M
