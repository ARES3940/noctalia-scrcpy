--!nonstrict
-- Pure parsers for `adb devices -l` and `adb mdns services`, plus dedupe.
-- No I/O: the service feeds them captured stdout.

local M = {}

--- True for wireless serials (ip:port or an mDNS TLS service name).
function M.isWireless(serial)
    if type(serial) ~= "string" then return false end
    return serial:find(":", 1, true) ~= nil
        or serial:find("._adb-tls-connect._tcp", 1, true) ~= nil
end

--- Parse `adb devices -l`.
function M.parseDevices(stdout)
    local out = {}
    for line in string.gmatch(stdout or "", "[^\r\n]+") do
        local serial, state = line:match("^(%S+)%s+(%S+)")
        if serial and serial ~= "List" and state then
            local device = {
                serial = serial,
                state = state,
                wireless = M.isWireless(serial),
                model = "",
                product = "",
                transport = "",
                endpoint = "",
            }
            for key, value in string.gmatch(line, "([%a]+):(%S+)") do
                if key == "model" then device.model = value:gsub("_", " ")
                elseif key == "product" then device.product = value
                elseif key == "device" then device.device = value
                elseif key == "transport_id" then device.transport = value end
            end
            table.insert(out, device)
        end
    end
    return out
end

--- Parse `adb mdns services`.
function M.parseMdns(stdout)
    local out = {}
    for line in string.gmatch(stdout or "", "[^\r\n]+") do
        local name, service, endpoint = line:match("^(%S+)%s+(%S+)%s+(%S+)")
        if name and name ~= "List" and service and endpoint then
            local host, port = endpoint:match("^(.+):(%d+)$")
            table.insert(out, {
                name = name,
                service = service,
                endpoint = endpoint,
                host = host or "",
                port = port or "",
            })
        end
    end
    return out
end

--- Merge mdns endpoints into devices and collapse duplicates of one phone.
-- adb 37 lists an mDNS phone both as `adb-…._adb-tls-connect._tcp` and, after
-- `adb connect`, as `ip:port` — both point at the same physical device.
function M.merge(devices, mdns)
    local byName = {}
    for _, entry in ipairs(mdns or {}) do
        byName[entry.name] = entry
        -- adb devices uses "<mdns name>.<service>" as the serial.
        byName[entry.name .. "." .. entry.service] = entry
    end

    local best = {}
    for _, device in ipairs(devices or {}) do
        local info = byName[device.serial]
        if info then
            device.endpoint = info.endpoint
            device.host = info.host
            device.port = info.port
        end
        local key = device.product ~= "" and device.product
            or (device.model ~= "" and device.model or device.serial)
        local previous = best[key]
        if not previous then
            best[key] = device
        else
            -- Prefer an explicit ip:port serial, then any wireless serial.
            -- Keep discovery metadata from whichever serial carries it.
            if device.endpoint == "" and previous.endpoint ~= "" then
                device.endpoint, device.host, device.port = previous.endpoint, previous.host, previous.port
            elseif previous.endpoint == "" and device.endpoint ~= "" then
                previous.endpoint, previous.host, previous.port = device.endpoint, device.host, device.port
            end
            local prefersIp = device.serial:find(":", 1, true) ~= nil
                and previous.serial:find(":", 1, true) == nil
            local prefersWireless = device.wireless and not previous.wireless
            if prefersIp or prefersWireless then best[key] = device end
        end
    end

    local out = {}
    for _, device in pairs(best) do table.insert(out, device) end
    table.sort(out, function(a, b) return a.serial < b.serial end)
    return out
end

function M.label(device)
    if not device then return "unknown" end
    if device.model and device.model ~= "" then return device.model end
    return device.serial
end

return M
