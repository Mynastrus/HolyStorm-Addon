local root=(arg[0]:gsub("tools[/\\]test_logs.lua$","")).."LIVE/Holy_Storm/"
local uiRoot=(arg[0]:gsub("tools[/\\]test_logs.lua$","")).."LIVE/Holy_Storm_UI/"
local clock=1000
unpack=unpack or table.unpack
local function copy(value,seen)if type(value)~="table"then return value end;seen=seen or{};if seen[value]then return seen[value]end;local out={};seen[value]=out;for key,child in pairs(value)do out[copy(key,seen)]=copy(child,seen)end;return out end
local locale=setmetatable({LOG_EXPORT_TITLE="Holy Storm %s - Log Export",LOG_EXPORT_TIME="Time",LOG_EXPORT_MODULES="Modules",LOG_EXPORT_FILTER="Filter",NO_LOG_ENTRIES="No log entries"},{__index=function(_,key)return key end})
local HolyStorm={version="5.3.2",db={profile={logs={autoScroll=false,level="ALL",module="ALL",category="ALL",direction="ALL",event="ALL",search=""}},global={logs={entries={}}}},Utils={DeepCopy=copy,Now=function()clock=clock+1;return clock end},Events={Emit=function()end}}
local Logs
function HolyStorm:RegisterRequiredModule()Logs={};return Logs end
function HolyStorm:ApplyModuleMetadata()end
function LibStub(name)if name=="AceAddon-3.0"then return{GetAddon=function()return HolyStorm end}elseif name=="AceLocale-3.0"then return{GetLocale=function()return locale end}end end
function date(_,timestamp)return tostring(timestamp)end
assert(loadfile(root.."Core/Logging/Logger.lua"))();HolyStorm.Logger:Initialize(false)
HolyStorm.Database={Get=function(_,path)local value=HolyStorm.db.profile;for key in path:gmatch("[^%.]+")do value=value and value[key]end;return value end,Set=function(_,path,value)local target=HolyStorm.db.profile;local keys={};for key in path:gmatch("[^%.]+")do keys[#keys+1]=key end;for index=1,#keys-1 do target[keys[index]]=target[keys[index]]or{};target=target[keys[index]]end;target[keys[#keys]]=value;return true end}
assert(loadfile(uiRoot.."UI/Pages/Logs.lua"))();Logs:LoadSettings()

HolyStorm.Logger:Write("DEBUG","Core","database","Database opened",{reason="LOGIN"})
HolyStorm.Logger:Write("INFO","MythicPlus","task","Snapshot completed",{taskId="task-1"},"wf-1")
HolyStorm.Logger:Write("WARN","Sync","payload","Payload delayed",{direction="SEND",from="Alpha-Realm",to="Beta-Realm",domain="character",objectId="Player-A\031mythicPlus",messageKind="PAYLOAD",transmissionId="tx-send",version=14},"corr-send")
HolyStorm.Logger:Write("ERROR","Sync","payload","Payload rejected",{direction="RECEIVE",from="Beta-Realm",to="Alpha-Realm",domain="character",objectId="Player-A\031equipment",messageKind="PAYLOAD",transmissionId="tx-recv",version=15},"corr-recv")
HolyStorm.Logger:Write("DEBUG","MythicPlus","event","Event received",{event="MYTHIC_PLUS_CURRENT_AFFIX_UPDATE",eventName="MYTHIC_PLUS_CURRENT_AFFIX_UPDATE"})
table.insert(HolyStorm.Logger.history,{timestamp=clock,level="INFO",message="Legacy entry without context"})
assert(#Logs:GetFiltered()==6,"normal and legacy log entries are visible")
local levels={};for _,entry in ipairs(HolyStorm.Logger.history)do levels[entry.level]=true end;assert(levels.DEBUG and levels.INFO and levels.WARN and levels.ERROR,"all log levels are retained")

Logs:SetFilter("module","Sync");assert(#Logs:GetFiltered()==2,"module filter")
Logs:ResetFilters(true);Logs:SetFilter("category","task");assert(#Logs:GetFiltered()==1,"category filter")
Logs:ResetFilters(true);Logs:SetFilter("event","MYTHIC_PLUS_CURRENT_AFFIX_UPDATE");assert(#Logs:GetFiltered()==1,"structured event filter")
Logs:ResetFilters(true);Logs:SetFilter("direction","SEND");assert(#Logs:GetFiltered()==1 and Logs:GetFiltered()[1].correlationId=="corr-send","direction filter")
Logs:SetFilter("module","Sync");Logs:SetFilter("category","payload");assert(#Logs:GetFiltered()==1,"combined filters")
Logs:ResetFilters(true);Logs:SetFilter("search","equipment");assert(#Logs:GetFiltered()==1 and Logs:GetFiltered()[1].context.direction=="RECEIVE","text search includes structured object IDs")
Logs:ResetFilters(true);assert(#Logs:GetFiltered()==6 and Logs.filters.level=="ALL"and Logs.filters.search=="","filter reset")

Logs:SetFilter("direction","SEND");local csv=Logs:Export("csv",false);local json=Logs:Export("json",false);local text=Logs:Export("text",false);assert(csv:find("direction,from,to",1,true)and csv:find("tx-send",1,true)and not csv:find("tx-recv",1,true),"CSV exports filtered structured fields");assert(json:find('"transmissionId":"tx-send"',1,true)and json:find('"correlationId":"corr-send"',1,true),"JSON retains transmission and correlation IDs");assert(text:find("Alpha%-Realm")and text:find("1",1,true),"text export remains available");assert(Logs:Export("csv",true):find("tx-recv",1,true),"all-entry export bypasses UI filters")
local details=Logs:FormatDetails({timestamp=1,level="INFO",source="Old",category="general",message="Old",context={nested={value=3},missing=false}});assert(details:find("nested.value: 3",1,true)and not details:find("table:",1,true),"context details are structured and legacy-safe")
HolyStorm.db.profile.logs.module="Sync";HolyStorm.db.profile.logs.category="payload";Logs.filters=nil;Logs:LoadSettings();assert(Logs.filters.module=="Sync"and Logs.filters.category=="payload"and Logs.autoScroll==false,"filter persistence")
Logs.filters.module="RemovedModule";Logs:EnsureValidFilters();assert(Logs.filters.module=="ALL","stale persisted filters fall back to ALL")
function CreateFrame()local frame={};function frame:SetScript(_,callback)self.callback=callback end;function frame:RegisterEvent()end;function frame:UnregisterEvent()end;return frame end
HolyStorm.Utils.SafeCall=function(_,callback,...)callback(...);return true end;HolyStorm.Tasks={RecordEvent=function()end}
assert(loadfile(root.."Core/Events/EventBus.lua"))();local observed=0;HolyStorm.Events:Register("MYTHIC_PLUS_CURRENT_AFFIX_UPDATE","MythicPlus",function()observed=observed+1 end);HolyStorm.Events:Register("HS_MYTHICPLUS_UPDATED","CharacterOverview",function()observed=observed+1 end);HolyStorm.Events:Register("HS_TASK_QUEUED","technical",function()observed=observed+1 end);HolyStorm.Events:Emit("MYTHIC_PLUS_CURRENT_AFFIX_UPDATE");HolyStorm.Events:Emit("HS_MYTHICPLUS_UPDATED");HolyStorm.Events:Emit("HS_TASK_QUEUED")
local externalEvent,internalEvent,technicalEvent=false,false,false;for _,entry in ipairs(HolyStorm.Logger.history)do local name=entry.context and entry.context.eventName;if name=="MYTHIC_PLUS_CURRENT_AFFIX_UPDATE"then externalEvent=true elseif name=="HS_MYTHICPLUS_UPDATED"then internalEvent=true elseif name=="HS_TASK_QUEUED"then technicalEvent=true end end;assert(observed==3 and externalEvent and internalEvent and not technicalEvent,"event diagnostics must include useful events without duplicating technical task traffic")
print("Log levels, filtering, persistence, details and structured export tests passed")
