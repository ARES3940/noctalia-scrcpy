--!nonstrict
-- Shared helpers: command bus + small declarative ui.* builders.
-- Entry runtimes are isolated VMs, so the sequence counter is per entry;
-- the manager watches the "cmd" state key published here.

local T = require("./theme.luau")

local M = {}
M.T = T

local cmdSeq = 0

function M.send(action, payload)
    cmdSeq = cmdSeq + 1
    -- The manager may see identical commands from different entries; the nonce
    -- guarantees the published value differs even when the payload does not.
    local nonce = tostring(noctalia.nowMs()) .. ":" .. tostring(math.random(1000, 999999))
    noctalia.state.set("cmd", { seq = cmdSeq, nonce = nonce, action = action, payload = payload })
end

function M.statusDef(state)
    return T.status[state] or T.status.disconnected
end

function M.kindDef(kind)
    return T.kind[kind] or T.kind.mirror
end

function M.statusText(state)
    return M.statusDef(state).label
end

function M.micro(text, color, width)
    return ui.label({
        text = string.upper(tostring(text)),
        fontSize = T.size.micro,
        fontFamily = T.font.label,
        fontWeight = "bold",
        color = color or T.color.muted,
        width = width,
        maxLines = 1,
    })
end

function M.value(text, color, width)
    return ui.label({
        text = tostring(text),
        fontSize = T.size.value,
        fontFamily = T.font.value,
        color = color or T.color.text,
        width = width,
        maxLines = 1,
    })
end

--- Sentence-case secondary copy. Unlike micro() it is not uppercased.
function M.note(text, color, maxLines)
    return ui.label({
        text = tostring(text or ""),
        fontSize = T.size.micro,
        fontFamily = T.font.label,
        color = color or T.color.muted,
        maxLines = maxLines or 2,
    })
end

--- One-line monospace text, for argv and paths.
function M.code(text, color, maxLines)
    return ui.label({
        text = tostring(text or ""),
        fontSize = T.size.micro,
        fontFamily = T.font.value,
        color = color or T.color.muted,
        maxLines = maxLines or 1,
    })
end

--- Sessions that are starting, running or stopping.
function M.activeSessions(sessions)
    local out = {}
    for _, session in ipairs(sessions or {}) do
        if session.state ~= "stopped" and session.state ~= "error" then
            out[#out + 1] = session
        end
    end
    return out
end

--- Bar / header status: recording > mirroring > connected > disconnected.
function M.statusOf(sessions, selected, devices)
    local mirroring, recording = false, false
    for _, session in ipairs(sessions or {}) do
        if session.state == "running" or session.state == "starting" then
            if session.kind == "record" or session.recordFile then
                recording = true
            else
                mirroring = true
            end
        end
    end
    if recording then return "recording" end
    if mirroring then return "mirroring" end
    for _, device in ipairs(devices or {}) do
        if device.serial == selected and device.state == "device" then return "connected" end
    end
    return "disconnected"
end

function M.dot(state, size)
    return ui.glyph({
        name = M.statusDef(state).glyph,
        size = size or T.size.icon,
        color = M.statusDef(state).color,
    })
end

function M.pill(text, color, fill)
    local role = color or T.color.muted
    return ui.row({
        align = "center",
        gap = 4,
        paddingH = 6,
        paddingV = 2,
        radius = T.size.pillRadius,
        fill = fill or (role .. "/0.14"),
    }, {
        ui.glyph({ name = "circle-filled", size = T.size.dot, color = role }),
        ui.label({
            text = string.upper(tostring(text)),
            fontSize = T.size.micro,
            fontFamily = T.font.label,
            fontWeight = "bold",
            color = role,
            maxLines = 1,
        }),
    })
end

function M.badge(text, color)
    return ui.row({
        align = "center",
        paddingH = 5,
        paddingV = 1,
        radius = T.size.pillRadius,
        fill = (color or T.color.muted) .. "/0.12",
    }, {
        ui.label({
            text = string.upper(tostring(text)),
            fontSize = T.size.micro,
            fontFamily = T.font.label,
            fontWeight = "bold",
            color = color or T.color.muted,
            maxLines = 1,
        }),
    })
end

function M.header(title, trailing)
    return ui.row({ align = "center", justify = "space_between", gap = 8 }, {
        ui.row({ gap = 6, align = "center" }, {
            ui.box({
                width = T.size.accentWidth,
                height = T.size.accentHeight,
                fill = T.color.accent,
                radius = 1,
            }),
            ui.label({
                text = title,
                fontSize = T.size.panelTitle,
                fontFamily = T.font.label,
                fontWeight = "bold",
                color = T.color.text,
                maxLines = 1,
            }),
        }),
        trailing,
    })
end

function M.sectionHead(title, trailing)
    return ui.row({ align = "center", gap = 6 }, {
        ui.label({
            text = string.upper(tostring(title)),
            fontSize = T.size.section,
            fontFamily = T.font.label,
            fontWeight = "bold",
            color = T.color.muted,
            maxLines = 1,
        }),
        ui.spacer({ flexGrow = 1 }),
        trailing,
    })
end

function M.card(children, onClick)
    local props = {
        gap = T.layout.cardGap,
        padding = T.layout.cardPadding,
        fill = T.color.card,
        radius = T.size.cardRadius,
        border = T.color.cardBorder,
        borderWidth = 1,
    }
    if onClick then props.onClick = onClick end
    return ui.column(props, children)
end

function M.rule()
    return ui.separator({ thickness = 1, color = T.color.text, opacity = 0.12, spacing = 0 })
end

function M.errorLine(err, maxLines)
    if not err then return nil end
    return ui.label({
        text = tostring(err),
        fontSize = T.size.micro,
        fontFamily = T.font.value,
        color = T.color.error,
        maxLines = maxLines or 2,
    })
end

function M.empty(text)
    return ui.label({
        text = tostring(text),
        fontSize = T.size.micro,
        fontFamily = T.font.label,
        color = "on_surface/0.45",
        maxLines = 2,
    })
end

function M.iconButton(glyph, tooltip, onClick, variant)
    return ui.button({
        glyph = glyph,
        variant = variant or "ghost",
        controlSize = "sm",
        tooltip = tooltip,
        onClick = onClick,
    })
end

--- Short duration for a session started at an epoch-ms timestamp.
function M.elapsed(startedAt)
    local seconds = math.max(0, math.floor((noctalia.nowMs() - (startedAt or 0)) / 1000))
    return string.format("%02d:%02d", math.floor(seconds / 60), seconds % 60)
end

return M
