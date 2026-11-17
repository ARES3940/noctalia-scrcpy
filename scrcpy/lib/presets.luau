--!nonstrict
-- Pure preset definitions. A preset is a sparse table of setting overrides.

local M = {}

M.order = { "Default", "Gaming", "Low bandwidth", "Webcam", "Record only" }

-- Panel buttons are narrow; keep the preset's real name for the tooltip.
M.short = {
    ["Low bandwidth"] = "Low data",
    ["Record only"] = "Record",
}

function M.label(name)
    return M.short[name] or name
end

M.presets = {
    Default = {},

    Gaming = {
        max_fps = 60,
        video_bit_rate = 12000,
        video_buffer_ms = 0,
        audio_buffer_ms = 20,
        stay_awake = true,
        keyboard_mode = "uhid",
        mouse_mode = "uhid",
        gamepad_mode = "uhid",
    },

    ["Low bandwidth"] = {
        max_size = 480,
        video_bit_rate = 1000,
        max_fps = 15,
        audio_enabled = false,
        video_codec = "h264",
    },

    Webcam = {
        video_source = "camera",
        camera_facing = "back",
        v4l2_enabled = true,
        v4l2_sink = "/dev/video10",
    },

    ["Record only"] = {
        record_enabled = true,
        record_only = true,
        stay_awake = true,
    },
}

function M.get(name)
    return M.presets[name] or {}
end

return M
