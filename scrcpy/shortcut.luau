--!nonstrict
-- omen/scrcpy control-center shortcut.
local T = require("./lib/theme.luau")

local function render()
    shortcut.setLabel(T.copy.panelTitle)
    shortcut.setIcon("device-mobile")
    local sessions = noctalia.state.get("sessions") or {}
    shortcut.setActive(type(sessions) == "table" and #sessions > 0)
end

function onClick()
    noctalia.togglePanel("omen/scrcpy:panel")
end

noctalia.state.watch("sessions", render)
render()
