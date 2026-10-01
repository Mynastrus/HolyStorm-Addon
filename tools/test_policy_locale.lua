local activeLocale = arg[1] or "enUS"
local scriptPath = arg[0]:gsub("\\", "/")
local workspace = scriptPath:match("^(.*)/tools/[^/]+$") or "."
local addonRoot = workspace .. "/LIVE/Holy_Storm/"
local uiRoot = workspace .. "/LIVE/Holy_Storm_UI/"

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
    assert(loadfile(uiRoot.."UI/Administration/Locales/"..locale..".lua","t",environment))()
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
    local source=read(uiRoot..relativePath)
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

local function balancedTable(source,openIndex)
    local depth,quote,escaped,lineComment=0,nil,false,false
    for index=openIndex,#source do
        local character=source:sub(index,index)
        if lineComment then
            if character=="\n"then lineComment=false end
        elseif quote then
            if escaped then escaped=false elseif character=="\\"then escaped=true elseif character==quote then quote=nil end
        elseif source:sub(index,index+1)=="--"then
            lineComment=true
        elseif character=="\""or character=="'"then
            quote=character
        elseif character=="{"then
            depth=depth+1
        elseif character=="}"then
            depth=depth-1
            if depth==0 then return source:sub(openIndex,index),index end
        end
    end
    error("Unclosed permissions table")
end

local function tableEntries(block)
    local entries,start={},2
    local braces,brackets,parentheses,quote,escaped,lineComment=0,0,0,nil,false,false
    for index=2,#block-1 do
        local character=block:sub(index,index)
        if lineComment then
            if character=="\n"then lineComment=false end
        elseif quote then
            if escaped then escaped=false elseif character=="\\"then escaped=true elseif character==quote then quote=nil end
        elseif block:sub(index,index+1)=="--"then
            lineComment=true
        elseif character=="\""or character=="'"then
            quote=character
        elseif character=="{"then braces=braces+1
        elseif character=="}"then braces=braces-1
        elseif character=="["then brackets=brackets+1
        elseif character=="]"then brackets=brackets-1
        elseif character=="("then parentheses=parentheses+1
        elseif character==")"then parentheses=parentheses-1
        elseif character==","and braces==0 and brackets==0 and parentheses==0 then
            entries[#entries+1]=block:sub(start,index-1);start=index+1
        end
    end
    local last=block:sub(start,#block-1)
    if last:match("%S")then entries[#entries+1]=last end
    return entries
end

local function checkPermissionEntry(entry,source)
    if entry:match("^%s*permission%s*%(")then return end
    local id=entry:match("^%s*[\"']([a-z][a-z0-9%-]*)[\"']%s*$")or entry:match("id%s*=%s*[\"']([a-z][a-z0-9%-]*)[\"']")
    if not id then return end
    local labelKey=entry:match("labelKey%s*=%s*[\"']([^\"']+)[\"']")
    local descriptionKey=entry:match("descriptionKey%s*=%s*[\"']([^\"']+)[\"']")
    local hasLabel=entry:match("[%s,]label%s*=")~=nil
    local hasDescription=entry:match("[%s,]description%s*=")~=nil
    if labelKey then requireKey(labelKey,source.." permission "..id)elseif not hasLabel then requireKey(permissionKey("PERMISSION_",id),source.." permission "..id)end
    if descriptionKey then requireKey(descriptionKey,source.." permission "..id)elseif not hasDescription then requireKey(permissionKey("PERMISSION_DESC_",id),source.." permission "..id)end
end

local sourceFiles={}
local sourceProcess=assert(io.popen('rg --files "'..workspace..'/LIVE" -g "*.lua"',"r"),"permission source enumeration failed")
for path in sourceProcess:lines()do sourceFiles[#sourceFiles+1]=path end
assert(sourceProcess:close(),"permission source enumeration failed")
for _,path in ipairs(sourceFiles)do
    local source=read(path)
    if source:find("RegisterModule",1,true)or source:find("ApplyModuleMetadata",1,true)or source:find("RegisterRequiredModule",1,true)then
        local cursor=1
        while true do
            local first,last=source:find("permissions%s*=%s*{",cursor)
            if not first then break end
            local open=source:find("{",first,true)
            local block,close=balancedTable(source,open)
            for _,entry in ipairs(tableEntries(block))do checkPermissionEntry(entry,path)end
            cursor=close+1
        end
    end
end

local guildLocalePaths={
    enUS={"Locales/enUS.lua","Locales/GuildManagement_enUS.lua","Locales/Activity_enUS.lua"},
    deDE={"Locales/deDE.lua","Locales/GuildManagement_deDE.lua","Locales/Activity_deDE.lua"},
}
local function loadGuildLocale(locale)
    local values,ace={},{}
    function ace:NewLocale(namespace,requestedLocale)
        assert(namespace=="Holy_Storm_GuildRoster"and requestedLocale==locale)
        return values
    end
    local environment=setmetatable({LibStub=function(name)assert(name=="AceLocale-3.0");return ace end},{__index=_G})
    for _,relativePath in ipairs(guildLocalePaths[locale])do assert(loadfile(workspace.."/LIVE/Holy_Storm_Guild/"..relativePath,"t",environment))()end
    return values
end
local guildEnglish,guildGerman=loadGuildLocale("enUS"),loadGuildLocale("deDE")
local guildManagementSource=read(workspace.."/LIVE/Holy_Storm_Guild/GuildManagement.lua")
for id in guildManagementSource:gmatch("permission%s*%(%s*[\"']([a-z][a-z0-9%-]*)[\"']")do
    for localeName,values in pairs({enUS=guildEnglish,deDE=guildGerman})do
        for _,key in ipairs({permissionKey("PERMISSION_",id),permissionKey("PERMISSION_DESC_",id)})do
            assert(values[key]~=nil,localeName.." is missing "..key.." used by registered Guild Management permission "..id)
        end
    end
end
assert(read(uiRoot.."UI/Administration/Permissions.lua"):find("label=definition.label or L[definition.labelKey]or id",1,true),"the permission selector must use localized labels already resolved by module registration before looking up Policy locale keys")

for category in pairs(categories)do requireKey("CATEGORY_"..category:gsub("[^%w]","_"):upper(),"category "..category)end
requireKey("CATEGORY_CHARACTERS","Characters permissions")
for _,key in ipairs({"CATEGORY_ACTIVITY","CATEGORY_ACTIVITY_POINTS","CATEGORY_ABSENCES","CATEGORY_NOTES"})do requireKey(key,"guild-management permission categories")end
local managementSource=read(workspace.."/LIVE/Holy_Storm_Guild/GuildManagement.lua")
for _,id in ipairs({"guild.notes","guild.absences","guild.activity","guild.activityPoints"})do assert(managementSource:find('"'..id..'"',1,true),"Guild Management must use stable permission category ID "..id)end
assert(not read(uiRoot.."UI/Administration/Permissions.lua"):find('definition.category or"Core"):gsub',1,true),"Policy categories must not derive locale IDs from display text")
for _,key in ipairs({
    "GROUP_GUILD_LEADERSHIP","GROUP_OFFICERS","GROUP_GUILD_MEMBER",
    "GROUP_DESC_GUILD_LEADERSHIP","GROUP_DESC_OFFICERS","GROUP_DESC_GUILD_MEMBER",
    "GENERAL","MEMBERS","PERMISSIONS","PERMISSION_MATRIX","RULES_FILTERS","MANAGERS","EFFECTIVE_MEMBERS","MODULE_SETTINGS","ANALYSIS","STATUS",
    "PERMISSION_ID","DEFAULT_GROUPS","MATRIX_FULL_ACCESS","MATRIX_ASSIGNED","MATRIX_EMPTY","PERMISSION_DETAIL_FORMAT",
    "MEMBERSHIP_MANUAL","MEMBERSHIP_SOURCE_FORMAT","CHARACTER_ID","EMPTY_MEMBERS","EMPTY_PERMISSIONS","GROUP_DELETE_IMPACT",
})do requireKey(key,"dynamic policy UI lookup")end
for _,value in ipairs({"SYSTEM","GUILD_RANK","MANUAL","FILTER","RULE","CHARACTER","ACCOUNT"})do requireKey("MEMBERSHIP_"..value,"membership source")end
for _,value in ipairs({"VALID","CATCHING_UP","RECOVERY_REQUIRED","CONFLICT","UNINITIALIZED"})do requireKey("STATE_"..value,"policy state status")end
for _,value in ipairs({"AND","OR","NOT"})do requireKey("LOGIC_"..value,"rule logic")end
for _,value in ipairs({"=","!=",">",">=","<","<=","CONTAINS","NOT_CONTAINS","STARTS_WITH","ENDS_WITH","IN","NOT_IN","BETWEEN","NOT_BETWEEN","TRUE","FALSE","EXISTS","NOT_EXISTS"})do requireKey("OP_"..value,"rule operator")end
for _,value in ipairs({"PASS","FAIL","UNKNOWN"})do requireKey("RESULT_"..value,"rule preview result")end
requireKey("REFERENCE_GROUP","filter reference kind")
requireKey("REFERENCE_CONTEXT","filter reference kind")
requireKey("REFERENCE_MODULE","filter reference kind")

GAME_LOCALE = activeLocale
function GetLocale() return activeLocale end
local reportedErrors = {}
function geterrorhandler() return function(message)reportedErrors[#reportedErrors+1]=tostring(message)end end
dofile(addonRoot.."Libs/LibStub/LibStub.lua")
dofile(addonRoot.."Libs/AceLocale-3.0/AceLocale-3.0.lua")
dofile(uiRoot.."UI/Administration/Locales/enUS.lua")
dofile(uiRoot.."UI/Administration/Locales/deDE.lua")
assert(#reportedErrors==0,table.concat(reportedErrors,"\n"))
local L=LibStub("AceLocale-3.0"):GetLocale("Holy_Storm_Policy")
for _,key in ipairs({"CATEGORY_CHARACTERS","PERMISSION_MATRIX","MODULE_SETTINGS","MATCHES_WITH_UNKNOWN","STATE_DETAILS_FORMAT"})do assert(L[key]~=key,activeLocale.." is missing translation for "..key)end
assert(english.PERMISSION_TWINKS_MANAGE_MANUAL_ASSIGNMENTS=="Manage manual twink assignments","enUS manual twink permission label changed unexpectedly")
assert(english.PERMISSION_TWINKS_MANAGE_MANUAL_ASSIGNMENTS_DESC=="Allows creating, changing, and removing manual twink assignments.","enUS manual twink permission description changed unexpectedly")
assert(german.PERMISSION_TWINKS_MANAGE_MANUAL_ASSIGNMENTS=="Manuelle Twink-Zuordnungen verwalten","deDE manual twink permission label changed unexpectedly")
assert(german.PERMISSION_TWINKS_MANAGE_MANUAL_ASSIGNMENTS_DESC=="Erlaubt das Erstellen, Ändern und Entfernen manueller Twink-Zuordnungen.","deDE manual twink permission description changed unexpectedly")
assert(#reportedErrors==0,table.concat(reportedErrors,"\n"))
print("Policy locale completeness and AceLocale runtime checks passed for "..activeLocale..".")
