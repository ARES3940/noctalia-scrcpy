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
    noctalia.state.set("cmd", { seq = cmdSeq, action = action, payload = payload })
end

function M.statusDef(state)
    return T.status[state] or T.status.disconnected
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

function M.dot(state, size)
    return ui.glyph({
        name = M.statusDef(state).glyph,
        size = size or T.size.dot,
        color = M.statusDef(state).color,
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

function M.card(children, onClick)
    local props = {
        gap = T.layout.cardGap,
        padding = T.layout.cardPadding,
        fill = T.color.cardFill,
        radius = T.size.radius,
        border = T.color.cardBorder,
        borderWidth = 1,
    }
    if onClick then props.onClick = onClick end
    return ui.column(props, children)
end

function M.sectionRule()
    return ui.separator({ thickness = 1, color = T.color.text, opacity = 0.14, spacing = 0 })
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

return M
