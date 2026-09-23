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
local function parseSemVer(value)
    if type(value)~="string"then return nil end
    value=value:gsub("^v","");local coreAndPre,build=value:match("^(.-)%+(.+)$");if coreAndPre then if not build:match("^[0-9A-Za-z%.%-]+$")or build:sub(1,1)=="."or build:sub(-1)=="."or build:find("..",1,true)then return nil end;value=coreAndPre end
    local core,pre=value:match("^([^%-]+)%-(.+)$");core=core or value;pre=pre or""
    local major,minor,patch=core:match("^(%d+)%.(%d+)%.(%d+)$")
    if not major then return nil end
    if major:match("^0%d")or minor:match("^0%d")or patch:match("^0%d")then return nil end
    local parsed={major=tonumber(major),minor=tonumber(minor),patch=tonumber(patch),prerelease={}}
    if pre~=""then if pre:sub(1,1)=="."or pre:sub(-1)=="."or pre:find("..",1,true)then return nil end;for identifier in pre:gmatch("[^%.]+")do if not identifier:match("^[0-9A-Za-z%-]+$")or identifier:match("^0%d+$")then return nil end;parsed.prerelease[#parsed.prerelease+1]=identifier end end
    return parsed
end
function Utils.CompareSemanticVersions(left,right)
    local a,b=parseSemVer(left),parseSemVer(right);if not a or not b then return nil,"INCOMPARABLE_VERSION"end
    for _,field in ipairs({"major","minor","patch"})do if a[field]~=b[field]then return a[field]>b[field]and 1 or-1 end end
    if#a.prerelease==0 and#b.prerelease>0 then return 1 elseif#b.prerelease==0 and#a.prerelease>0 then return-1 end
    for index=1,math.max(#a.prerelease,#b.prerelease)do local x,y=a.prerelease[index],b.prerelease[index];if x==nil then return-1 elseif y==nil then return 1 elseif x~=y then local xn,yn=tonumber(x),tonumber(y);if xn and yn then return xn>yn and 1 or-1 elseif xn then return-1 elseif yn then return 1 else return x>y and 1 or-1 end end end
    return 0
end
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
