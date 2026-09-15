local activeLocale = arg[1] or "enUS"
local scriptPath = arg[0]:gsub("\\", "/")
local workspace = scriptPath:match("^(.*)/tools/[^/]+$") or "."
local addonRoot = workspace .. "/LIVE/Holy_Storm/"

GAME_LOCALE = activeLocale
function GetLocale()
    return activeLocale
end

local reportedErrors = {}
function geterrorhandler()
    return function(message)
        reportedErrors[#reportedErrors + 1] = tostring(message)
    end
end

dofile(addonRoot .. "Libs/LibStub/LibStub.lua")
dofile(addonRoot .. "Libs/AceLocale-3.0/AceLocale-3.0.lua")
dofile(addonRoot .. "UI/Administration/Locales/enUS.lua")
dofile(addonRoot .. "UI/Administration/Locales/deDE.lua")

assert(#reportedErrors == 0, table.concat(reportedErrors, "\n"))

local L = LibStub("AceLocale-3.0"):GetLocale("Holy_Storm_Policy")
local requiredKeys = {
    "GROUP_COUNT_COLUMNS",
    "PERMISSION_MATRIX",
    "MODULE_SETTINGS",
    "REMOVE_SOURCE",
    "FULL_ACCESS",
    "FULL_ACCESS_HELP",
    "PERMISSION_CALENDAR_MANAGE",
    "PERMISSION_DESC_CALENDAR_MANAGE",
    "CATEGORY_CALENDAR",
}

for _, key in ipairs(requiredKeys) do
    assert(L[key] ~= key, activeLocale .. " is missing translation for " .. key)
end

assert(#reportedErrors == 0, table.concat(reportedErrors, "\n"))
print("Policy AceLocale runtime check passed for " .. activeLocale .. ".")
