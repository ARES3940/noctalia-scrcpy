--!nonstrict
-- Small right-click quick-actions panel for omen/scrcpy.
-- Kept to one screen: launch the three common modes, see and stop what runs,
-- and jump to the full panel for devices and settings.

local S = require("./lib/shared.luau")
local T = S.T
local Devices = require("./lib/devices.luau")

local open = false
local render

local function read()
    local sessions = noctalia.state.get("sessions") or {}
    local devices = noctalia.state.get("devices") or {}
    local selected = tostring(noctalia.state.get("selected") or "")
    return {
        state = S.statusOf(sessions, selected, devices),
        sessions = sessions,
        devices = devices,
        selected = selected,
        eff = noctalia.state.get("effective") or {},
        caps = noctalia.state.get("capabilities") or {},
        blocked = noctalia.state.get("blocked") or {},
        hasLast = noctalia.state.get("hasLast") == true,
    }
end

local function device(st)
    return Devices.find(st.devices, st.selected)
end

local function launch(kind, extras)
    S.send("start", { kind = kind, extras = extras })
    panel.close()
end

local function render()
    local st = read()
    local def = S.statusDef(st.state)
    local selected = device(st)
    local ready = Devices.isReady(selected)
    local blocked = st.blocked
    local canLaunch = ready and blocked.all == nil and blocked.device == nil
    local cameraBlocked = blocked.video_source
    local active = S.activeSessions(st.sessions)

    local children = {
        ui.row({ align = "center", justify = "space_between", gap = 6 }, {
            ui.row({ align = "center", gap = 6 }, {
                ui.box({ width = 3, height = 15, fill = T.color.accent, radius = 2 }),
                ui.label({
                    text = T.copy.title,
                    fontSize = 12,
                    fontFamily = T.font.label,
                    fontWeight = "bold",
                    color = T.color.text,
                    maxLines = 1,
                }),
            }),
            S.pill(def.label, def.color),
        }),
        ui.row({ align = "center", gap = 6 }, {
            ui.glyph({
                name = ready and "device-mobile" or "device-mobile-off",
                size = 13,
                color = ready and T.color.accent or T.color.muted,
            }),
            ui.label({
                text = selected and Devices.label(selected) or "No device selected",
                fontSize = T.size.micro,
                fontFamily = T.font.label,
                color = ready and T.color.text or T.color.muted,
                flexGrow = 1,
                maxLines = 1,
            }),
        }),
        S.rule(),
        ui.button({
            text = "START MIRROR",
            glyph = "player-play",
            variant = "primary",
            controlSize = "md",
            enabled = canLaunch,
            tooltip = canLaunch and "Mirror the display" or (blocked.all or blocked.device),
            onClick = function() launch("mirror") end,
        }),
        ui.row({ gap = 5, align = "stretch" }, {
            ui.button({
                text = "REC",
                glyph = "player-record",
                variant = "default",
                controlSize = "sm",
                flexGrow = 1,
                enabled = canLaunch,
                tooltip = "Record only, no window",
                onClick = function() launch("record") end,
            }),
            ui.button({
                text = "CAMERA",
                glyph = "camera",
                variant = "default",
                controlSize = "sm",
                flexGrow = 1,
                enabled = canLaunch and cameraBlocked == nil,
                tooltip = cameraBlocked or "Mirror the camera",
                onClick = function() launch("mirror", { video_source = "camera" }) end,
            }),
        }),
    }

    if active[1] then
        children[#children + 1] = ui.column({ gap = 4 }, {
            ui.row({ align = "center", justify = "space_between", gap = 6 }, {
                S.micro("ACTIVE", T.color.muted),
                ui.button({
                    text = "STOP ALL",
                    variant = "ghost",
                    controlSize = "sm",
                    onClick = function()
                        for _, session in ipairs(active) do
                            S.send("stop", { id = session.id })
                        end
                        render()
                    end,
                }),
            }),
            ui.column({ gap = 3 }, (function()
                local rows = {}
                for i = #active, 1, -1 do
                    local session = active[i]
                    local kind = session.mode or (session.recordFile and "record" or session.kind or "mirror")
                    local kd = S.kindDef(kind)
                    rows[#rows + 1] = ui.row({
                        key = "quick-session-" .. tostring(session.id),
                        align = "center",
                        gap = 6,
                        paddingH = 6,
                        paddingV = 4,
                        radius = T.size.pillRadius,
                        fill = T.color.card,
                    }, {
                        ui.glyph({ name = kd.glyph, size = 11, color = kd.color }),
                        ui.label({
                            text = kd.label,
                            fontSize = T.size.micro,
                            fontFamily = T.font.label,
                            fontWeight = "bold",
                            color = T.color.text,
                            maxLines = 1,
                        }),
                        ui.label({
                            text = S.elapsed(session.startedAt),
                            fontSize = T.size.micro,
                            fontFamily = T.font.value,
                            color = T.color.muted,
                            flexGrow = 1,
                            maxLines = 1,
                        }),
                        S.iconButton("player-stop", "Stop", function()
                            S.send("stop", { id = session.id })
                            render()
                        end),
                    })
                end
                return rows
            end)()),
        })
    elseif st.hasLast then
        children[#children + 1] = ui.button({
            text = "RESTART LAST SESSION",
            glyph = "rotate",
            variant = "ghost",
            controlSize = "sm",
            enabled = canLaunch,
            onClick = function()
                S.send("start-last")
                panel.close()
            end,
        })
    end

    children[#children + 1] = S.rule()
    children[#children + 1] = ui.row({ align = "center", justify = "space_between", gap = 6 }, {
        ui.button({
            text = "FULL PANEL",
            glyph = "layout-grid",
            variant = "ghost",
            controlSize = "sm",
            onClick = function()
                noctalia.togglePanel("omen/scrcpy:panel")
                panel.close()
            end,
        }),
        S.iconButton("adjustments", "Plugin settings", function()
            S.send("open-settings")
            panel.close()
        end),
    })

    panel.render(ui.column({
        gap = 7,
        padding = 11,
        flexGrow = 1,
    }, children))
end

function onOpen()
    open = true
    S.send("refresh")
    panel.setWantsSecondTicks(true)
    render()
end

function onClose()
    open = false
    panel.setWantsSecondTicks(false)
end

function update()
    if not open then return end
    render()
end

for _, key in ipairs({ "sessions", "devices", "selected", "effective", "capabilities", "blocked", "hasLast", "notice" }) do
    noctalia.state.watch(key, function()
        if open then render() end
    end)
end
