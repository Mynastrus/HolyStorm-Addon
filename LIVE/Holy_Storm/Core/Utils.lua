local addonVersion = "1.1.0"
local HolyStorm = LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local Utils = { version=addonVersion }
function Utils.Trim(value) return type(value) == "string" and value:match("^%s*(.-)%s*$") or "" end
function Utils.Now() return GetServerTime and GetServerTime() or time and time() or 0 end
function Utils.Clamp(value, minimum, maximum) return math.max(minimum, math.min(maximum, value)) end
function Utils.DeepCopy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}; if seen[value] then return seen[value] end
    local copy = {}; seen[value] = copy
    for key, child in pairs(value) do copy[Utils.DeepCopy(key, seen)] = Utils.DeepCopy(child, seen) end
    return copy
end
function Utils.ApplyDefaults(target, defaults)
    target = type(target) == "table" and target or {}
    for key, value in pairs(defaults or {}) do
        if target[key] == nil then target[key] = Utils.DeepCopy(value)
        elseif type(value) == "table" then target[key] = Utils.ApplyDefaults(target[key], value) end
    end
    return target
end
function Utils.TableCount(value) local count = 0; if type(value) == "table" then for _ in pairs(value) do count = count + 1 end end; return count end
function Utils.SafeCall(source, callback, ...)
    if type(callback) ~= "function" then return false, "callback is not a function" end
    local args = { ... }
    return xpcall(function() return callback(unpack(args)) end, function(message)
        local handler = geterrorhandler and geterrorhandler()
        if handler then handler("Holy Storm [" .. tostring(source) .. "]: " .. tostring(message)) end
        return message
    end)
end
HolyStorm.Utils = Utils
