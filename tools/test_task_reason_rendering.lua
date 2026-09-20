local script=arg[0]:gsub("\\","/")
local workspace=script:match("^(.*)/tools/[^/]+$")or"."
local missingReasons=0
local locale=setmetatable({
 DISPLAY_NAME="Tasks",DESCRIPTION="Tasks",
 REASON_DEBOUNCE="Debounce",REASON_NOT_IN_COMBAT="Combat",REASON_PLAYER_LOGGED_IN="Login",REASON_PLAYER_READY="Ready",REASON_GUILD_AVAILABLE="Guild",REASON_NOT_LOADING="Loading",REASON_NOT_ZONING="Zoning",REASON_ASYNC="Async",
 REASON_STARTUP_PHASE="Startup: %s",REASON_DEPENDENCY_WAITING="Waiting: %s",REASON_DEPENDENCY_MISSING="Missing: %s",REASON_UNKNOWN_CONDITION="Unknown: %s",
},{__index=function(_,key)if tostring(key):match("^REASON_")then missingReasons=missingReasons+1 end;return key end})
local modules={}
local HolyStorm={}
function HolyStorm:GetAddon()return self end
function HolyStorm:RegisterRequiredModule(name)local module={};modules[name]=module;return module end
function HolyStorm:ApplyModuleMetadata()end
function LibStub(name)if name=="AceLocale-3.0"then return{GetLocale=function()return locale end}end;return HolyStorm end

assert(loadfile(workspace.."/LIVE/Holy_Storm_UI/UI/Pages/TaskManager.lua"))()
local page=modules.TaskManagerUI
assert(page:FormatReason(nil)=="-","nil reason must render as an empty diagnostic")
assert(page:FormatReason(true)=="true","boolean reason must render as raw text")
assert(page:FormatReason("nil")=="nil","stringified nil error must fall back to raw text")
assert(page:FormatReason("DEBOUNCE")=="Debounce","known simple reason must be localized")
assert(page:FormatReason("STARTUP_PHASE:PHASE_2")=="Startup: PHASE_2","known structured reason must be localized")
assert(page:FormatReason("FUTURE_REASON")=="FUTURE_REASON","unknown reason must fall back to raw text")
assert(missingReasons==0,"reason rendering must never probe AceLocale with unknown dynamic keys")

print("TaskManager reason rendering whitelist and fallbacks passed")
