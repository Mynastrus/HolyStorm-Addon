local root=(arg[0]:gsub("tools[/\\]test_character_scan_manager.lua$","")).."LIVE/Holy_Storm/"
unpack=unpack or table.unpack
local metadata,queued,logs,listeners={},{},{},{}
local present={identity=true,raid=true}
local HolyStorm={Utils={},Tasks={definitions={}},Events={},PlayerData={},AddonLoader={}}
function HolyStorm:GetAddon()return self end
function LibStub(name)if name=="AceAddon-3.0"then return HolyStorm end;return{GetLocale=function()return setmetatable({},{__index=function(_,key)return key end})end}end
function HolyStorm.Utils.DeepCopy(value)if type(value)~="table"then return value end;local out={};for key,child in pairs(value)do out[key]=HolyStorm.Utils.DeepCopy(child)end;return out end
function HolyStorm.Utils.TableCount(value)local count=0;for _ in pairs(value or{})do count=count+1 end;return count end
function HolyStorm.Utils.Now()return 100 end
function HolyStorm.Utils.SafeCall(_,callback,...)return pcall(callback,...)end
HolyStorm.Logger={Write=function(_,level,source,category,message,context)logs[#logs+1]={level=level,source=source,category=category,message=message,context=context}end}
function HolyStorm.Tasks:RegisterTaskType(id,definition)self.definitions[id]=definition end
function HolyStorm.Tasks:Queue(id,options)queued[#queued+1]={id=id,options=options};return"task-"..#queued,"QUEUED"end
function HolyStorm.Events:Register(event,_,callback)listeners[event]=callback end
function HolyStorm.Events:Emit()end
function HolyStorm.PlayerData:GetMetadata(_,block)return present[block]and{version=1}or nil end
function HolyStorm.AddonLoader:GetCharacterDataDefinitions()return{{block="equipment",capability="character.scan.equipment",addonId="equipment",order=10},{block="raid",capability="character.scan.raids",addonId="raids",order=30}}end
function UnitGUID()return"Player-Local"end

assert(loadfile(root.."Core/Tasks/CharacterScanManager.lua"))();local scans=HolyStorm.CharacterScans;scans:Initialize()
assert(not listeners.PLAYER_ENTERING_WORLD and listeners.PLAYER_LOGIN,"initial acquisition is tied to true login, not PLAYER_ENTERING_WORLD")
local started={};scans:RegisterProvider("Equipment",{block="equipment",capability="character.scan.equipment",order=10,request=function(_,reason)started[#started+1]={block="equipment",reason=reason};return"wf-equipment-"..#started end});scans:RegisterProvider("Raids",{block="raid",capability="character.scan.raids",order=30,request=function(_,reason)started[#started+1]={block="raid",reason=reason};return"wf-raid-"..#started end})

assert(scans:QueueMissingBlocks()and#scans.queue==1 and scans.queue[1].block=="equipment","a missing equipment block queues exactly one initial scan")
scans:QueueMissingBlocks();assert(#scans.queue==1,"repeated initial discovery merges the same missing block")
assert(scans:Advance()and scans.active.block=="equipment"and#started==1,"the first missing block starts")
scans:Request("equipment","PLAYER_EQUIPMENT_CHANGED",true,{order=10});scans:Request("equipment","SOCKET_INFO_UPDATE",true,{order=10});assert(#scans.queue==1 and scans.pending.equipment.reasons.PLAYER_EQUIPMENT_CHANGED and scans.pending.equipment.reasons.SOCKET_INFO_UPDATE,"events during a running scan merge into one pending dirty request")
scans:Request("raid","BOSS_KILL",true,{order=30});assert(#started==1,"a second feature scan cannot start while CHARACTER_SCAN is occupied")
local firstWorkflow=scans.active.workflowId;assert(scans:Finish({workflowId=firstWorkflow},"COMPLETED"));assert(scans:Advance()and scans.active.block=="raid"and#started==2,"another pending block gets a fair turn after the first workflow finishes")
assert(scans:Finish({workflowId=scans.active.workflowId},"COMPLETED"));assert(scans:Advance()and scans.active.block=="equipment"and#started==3,"the merged dirty rescan is retained and runs after the other pending block")

scans.active=nil;scans.pending={};scans.queue={};present.equipment=true;present.raid=true;assert(scans:QueueMissingBlocks()and#scans.queue==0,"existing valid blocks do not receive an initial scan")
present.equipment=nil;present.raid=nil;assert(scans:QueueMissingBlocks()and#scans.queue==2,"multiple missing blocks are discovered");scans:Advance();assert(scans.active.block=="equipment");local activeId=scans.active.workflowId;scans:Advance();assert(scans.active.workflowId==activeId,"Advance cannot overlap an active workflow")

local projectRoot=arg[0]:gsub("tools[/\\]test_character_scan_manager.lua$","")
local eventContracts={
 {path="LIVE/Holy_Storm_Equipment/Equipment.lua",events={"PLAYER_EQUIPMENT_CHANGED","UNIT_INVENTORY_CHANGED","SOCKET_INFO_UPDATE"}},
 {path="LIVE/Holy_Storm_Raids/Raids.lua",events={"UPDATE_INSTANCE_INFO","BOSS_KILL","ENCOUNTER_END"}},
 {path="LIVE/Holy_Storm_MythicPlus/MythicPlus.lua",events={"CHALLENGE_MODE_COMPLETED","CHALLENGE_MODE_MAPS_UPDATE","MYTHIC_PLUS_CURRENT_AFFIX_UPDATE","MYTHIC_PLUS_NEW_WEEKLY_RECORD"}},
 {path="LIVE/Holy_Storm_Delves/Delves.lua",events={"WEEKLY_REWARDS_UPDATE","DELVES_ACCOUNT_DATA_ELEMENT_CHANGED","ACTIVE_DELVE_DATA_UPDATE"}},
}
for _,contract in ipairs(eventContracts)do local file=assert(io.open(projectRoot..contract.path,"rb"));local source=file:read("*a");file:close();assert(not source:find("PLAYER_ENTERING_WORLD",1,true),contract.path.." must not scan on PLAYER_ENTERING_WORLD");assert(source:find("CharacterScans:Request",1,true),contract.path.." routes events through the central scan queue");for _,event in ipairs(contract.events)do assert(source:find(event,1,true),contract.path.." keeps event "..event)end end
print("Central missing-block acquisition, serialization and dirty-event merge tests passed")
