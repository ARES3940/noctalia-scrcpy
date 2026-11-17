--!nonstrict
-- Small right-click quick-actions panel for omen/scrcpy.
local S = require("./lib/shared.luau")
local T = S.T

local function render()
    local sessions = noctalia.state.get("sessions") or {}
    local active = false
    for _, session in pairs(sessions) do
        if session.state == "running" or session.state == "starting" then active = true end
    end

    panel.render(ui.column({ gap = 6, padding = 10, fill = "surface_container/0.9", radius = T.size.radius }, {
        S.header("SCRCPY", S.micro(active and "ACTIVE" or "READY", T.color.accent)),
        S.sectionRule(),
        ui.button({
            text = "START MIRROR", variant = "primary", controlSize = "sm",
            onClick = function() S.send("start", { kind = "mirror" }); panel.close() end,
        }),
        ui.button({
            text = "START RECORDING", variant = "outline", controlSize = "sm",
            onClick = function() S.send("start-recording"); panel.close() end,
        }),
        ui.button({
            text = "START LAST SESSION", variant = "outline", controlSize = "sm",
            onClick = function() S.send("start-last"); panel.close() end,
        }),
        ui.button({
            text = "STOP LAST SESSION", variant = "destructive", controlSize = "sm",
            enabled = active,
            onClick = function() S.send("stop-last"); panel.close() end,
        }),
        S.sectionRule(),
        ui.button({
            text = "OPEN FULL PANEL", variant = "ghost", controlSize = "sm",
            onClick = function() noctalia.togglePanel("omen/scrcpy:panel") end,
        }),
    }))
end

function onOpen(context)
    render()
end

for _, key in ipairs({ "sessions", "notice" }) do
    noctalia.state.watch(key, render)
end
render()
