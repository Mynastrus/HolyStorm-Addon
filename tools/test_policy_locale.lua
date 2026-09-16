local activeLocale = arg[1] or "enUS"
local scriptPath = arg[0]:gsub("\\", "/")
local workspace = scriptPath:match("^(.*)/tools/[^/]+$") or "."
local addonRoot = workspace .. "/LIVE/Holy_Storm/"

local function read(path)
    local file=assert(io.open(path,"r"));local content=file:read("*a");file:close();return content
end

local function loadDefinitions(locale)
    local values={}
    local ace={}
    function ace:NewLocale(namespace,requestedLocale)
        assert(namespace=="Holy_Storm_Policy" and requestedLocale==locale)
        return values
    end
    local environment=setmetatable({LibStub=function(name)assert(name=="AceLocale-3.0");return ace end},{__index=_G})
    assert(loadfile(addonRoot.."UI/Administration/Locales/"..locale..".lua","t",environment))()
    return values
end

local english,german=loadDefinitions("enUS"),loadDefinitions("deDE")
for key in pairs(english)do assert(german[key]~=nil,"deDE is missing Holy_Storm_Policy key "..key)end
for key in pairs(german)do assert(english[key]~=nil,"enUS is missing Holy_Storm_Policy key "..key)end

local function requireKey(key,source)
    assert(english[key]~=nil,"enUS is missing "..key.." used by "..source)
    assert(german[key]~=nil,"deDE is missing "..key.." used by "..source)
end

for _,relativePath in ipairs({
    "UI/Framework/Components/PolicyUI.lua",
    "UI/Administration/AdministrationRegistry.lua",
    "UI/Administration/Permissions.lua",
    "UI/Administration/Rules.lua",
    "UI/Administration/Filters.lua",
    "UI/Administration/PolicyInspector.lua",
})do
    local source=read(addonRoot..relativePath)
    for key in source:gmatch('L%["([^"\r\n]+)"%]')do requireKey(key,relativePath)end
end

local permissionIds,categories={},{}
local registrySource=read(addonRoot.."Core/Permissions/PermissionRegistry.lua")
local definitionBlock=assert(registrySource:match("local definitions%s*=%s*{(.-)}%s*Registry%.legacyIds"))
for id,category in definitionBlock:gmatch('%["([^"]+)"%]%s*=%s*"([^"]+)"')do permissionIds[id]=true;categories[category]=true end

for tocLine in io.lines(addonRoot.."Holy_Storm.toc")do
    local relativePath=tocLine:gsub("\\","/")
    if relativePath:match("^Modules/.+%.lua$")then
        local source=read(addonRoot..relativePath)
        for id,category in source:gmatch('id%s*=%s*"([a-z][a-z0-9%-]+)"%s*,%s*category%s*=%s*"([^"]+)"')do permissionIds[id]=true;categories[category]=true end
    end
end

local function permissionKey(prefix,id)return prefix..id:gsub("[^%w]","_"):upper()end
for id in pairs(permissionIds)do
    requireKey(permissionKey("PERMISSION_",id),"permission "..id)
    requireKey(permissionKey("PERMISSION_DESC_",id),"permission "..id)
end
for category in pairs(categories)do requireKey("CATEGORY_"..category:gsub("[^%w]","_"):upper(),"category "..category)end
requireKey("CATEGORY_CHARACTERS","Characters permissions")
for _,key in ipairs({
    "GROUP_GUILD_LEADERSHIP","GROUP_OFFICERS","GROUP_GUILD_MEMBER",
    "GROUP_DESC_GUILD_LEADERSHIP","GROUP_DESC_OFFICERS","GROUP_DESC_GUILD_MEMBER",
    "GENERAL","MEMBERS","PERMISSIONS","PERMISSION_MATRIX","RULES_FILTERS","MANAGERS","EFFECTIVE_MEMBERS","MODULE_SETTINGS","ANALYSIS","STATUS",
})do requireKey(key,"dynamic policy UI lookup")end
for _,value in ipairs({"VALID","CATCHING_UP","RECOVERY_REQUIRED","CONFLICT","UNINITIALIZED"})do requireKey("STATE_"..value,"policy state status")end
for _,value in ipairs({"AND","OR","NOT"})do requireKey("LOGIC_"..value,"rule logic")end
for _,value in ipairs({"=","!=",">",">=","<","<=","CONTAINS","NOT_CONTAINS","STARTS_WITH","ENDS_WITH","IN","NOT_IN","BETWEEN","NOT_BETWEEN","TRUE","FALSE","EXISTS","NOT_EXISTS"})do requireKey("OP_"..value,"rule operator")end

GAME_LOCALE = activeLocale
function GetLocale() return activeLocale end
local reportedErrors = {}
function geterrorhandler() return function(message)reportedErrors[#reportedErrors+1]=tostring(message)end end
dofile(addonRoot.."Libs/LibStub/LibStub.lua")
dofile(addonRoot.."Libs/AceLocale-3.0/AceLocale-3.0.lua")
dofile(addonRoot.."UI/Administration/Locales/enUS.lua")
dofile(addonRoot.."UI/Administration/Locales/deDE.lua")
assert(#reportedErrors==0,table.concat(reportedErrors,"\n"))
local L=LibStub("AceLocale-3.0"):GetLocale("Holy_Storm_Policy")
for _,key in ipairs({"CATEGORY_CHARACTERS","PERMISSION_MATRIX","MODULE_SETTINGS","MATCHES_WITH_UNKNOWN","STATE_DETAILS_FORMAT"})do assert(L[key]~=key,activeLocale.." is missing translation for "..key)end
assert(#reportedErrors==0,table.concat(reportedErrors,"\n"))
print("Policy locale completeness and AceLocale runtime checks passed for "..activeLocale..".")
