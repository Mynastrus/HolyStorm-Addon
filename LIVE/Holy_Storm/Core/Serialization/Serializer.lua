local addonVersion = "1.0.0"
local HolyStorm = LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local Serializer = { version=addonVersion, limits = { depth = 12, entries = 10000, bytes = 262144, string = 65535 } }
function Serializer:Serialize(value)
    local seen, entries = {}, 0
    local function encode(child, depth)
        if depth > Serializer.limits.depth then return nil, "maximum depth exceeded" end
        local kind = type(child)
        if kind == "nil" then return "n" end
        if kind == "boolean" then return child and "b1" or "b0" end
        if kind == "number" then if child ~= child or child == math.huge or child == -math.huge then return nil, "invalid number" end; return "d" .. tostring(child) .. ";" end
        if kind == "string" then if #child > Serializer.limits.string then return nil, "string too large" end; return "s" .. #child .. ":" .. child end
        if kind ~= "table" or seen[child] then return nil, "unsupported or circular value" end
        seen[child] = true; local parts, count, keys = {}, 0, {}
        for key in pairs(child) do if type(key)~="string" and type(key)~="number" then seen[child]=nil; return nil,"unsupported table key" end; keys[#keys+1]=key end
        table.sort(keys,function(a,b) if type(a)==type(b) then return tostring(a)<tostring(b) end; return type(a)<type(b) end)
        for _,key in ipairs(keys) do local item=child[key]
            entries = entries + 1; if entries > Serializer.limits.entries then seen[child] = nil; return nil, "too many entries" end
            local encodedKey, keyError = encode(key, depth + 1); if not encodedKey then seen[child] = nil; return nil, keyError end
            local encodedItem, itemError = encode(item, depth + 1); if not encodedItem then seen[child] = nil; return nil, itemError end
            count = count + 1; parts[#parts + 1] = encodedKey; parts[#parts + 1] = encodedItem
        end
        seen[child] = nil; return "t" .. count .. "{" .. table.concat(parts) .. "}"
    end
    local encoded, err = encode(value, 0); if encoded and #encoded > self.limits.bytes then return nil, "payload too large" end; return encoded, err
end
function Serializer:Deserialize(text)
    if type(text) ~= "string" or #text > self.limits.bytes then return nil, "invalid payload" end
    local position, entries = 1, 0; local read
    read = function(depth)
        if depth > Serializer.limits.depth then return nil, false end
        local kind = text:sub(position, position); position = position + 1
        if kind == "n" then return nil, true end
        if kind == "b" then local token = text:sub(position, position); position = position + 1; return token == "1", token == "0" or token == "1" end
        if kind == "d" then local stop = text:find(";", position, true); if not stop then return nil, false end; local number = tonumber(text:sub(position, stop - 1)); position = stop + 1; return number, number ~= nil end
        if kind == "s" then
            local stop = text:find(":", position, true); if not stop then return nil, false end
            local length = tonumber(text:sub(position, stop - 1)); if not length or length < 0 or length > Serializer.limits.string then return nil, false end
            position = stop + 1; local value = text:sub(position, position + length - 1); if #value ~= length then return nil, false end; position = position + length; return value, true
        end
        if kind ~= "t" then return nil, false end
        local stop = text:find("{", position, true); if not stop then return nil, false end
        local count = tonumber(text:sub(position, stop - 1)); if not count or count < 0 or count > Serializer.limits.entries then return nil, false end
        position = stop + 1; local result = {}
        for _ = 1, count do
            entries = entries + 1; if entries > Serializer.limits.entries then return nil, false end
            local key, keyValid = read(depth + 1); local value, valueValid = read(depth + 1)
            if not keyValid or not valueValid or key == nil then return nil, false end; result[key] = value
        end
        if text:sub(position, position) ~= "}" then return nil, false end; position = position + 1; return result, true
    end
    local value, valid = read(0); if not valid or position <= #text then return nil, "malformed payload" end; return value
end
function Serializer:Copy(value) local encoded = self:Serialize(value); return encoded and self:Deserialize(encoded) or nil end
HolyStorm.Serializer = Serializer
