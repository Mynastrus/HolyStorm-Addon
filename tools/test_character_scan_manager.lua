local root=(arg[0]:gsub("tools[/\\]test_character_scan_manager.lua$","")).."LIVE/Holy_Storm/"
unpack=unpack or table.unpack
local metadata,queued,logs,listeners={},{},{},{}
local clock=100000
local blockMetadata={identity={version=1,updatedAt=clock},mythicPlus={version=1,updatedAt=clock-10},raid={version=1,updatedAt=clock-10}}
local blockSnapshots={mythicPlus={dungeons={{affixScores={}}}}};local inspectMythic=false
local HolyStorm={Utils={},Tasks={definitions={}},Events={},PlayerData={},AddonLoader={}}
function HolyStorm:GetAddon()return self end
function LibStub(name)if name=="AceAddon-3.0"then return HolyStorm end;return{GetLocale=function()return setmetatable({},{__index=function(_,key)return key end})end}end
function HolyStorm.Utils.DeepCopy(value)if type(value)~="table"then return value end;local out={};for key,child in pairs(value)do out[key]=HolyStorm.Utils.DeepCopy(child)end;return out end
function HolyStorm.Utils.TableCount(value)local count=0;for _ in pairs(value or{})do count=count+1 end;return count end
function HolyStorm.Utils.Now()return clock end
function HolyStorm.Utils.SafeCall(_,callback,...)return pcall(callback,...)end
HolyStorm.Logger={Write=function(_,level,source,category,message,context)logs[#logs+1]={level=level,source=source,category=category,message=message,context=context}end}
function HolyStorm.Tasks:RegisterTaskType(id,definition)self.definitions[id]=definition end
function HolyStorm.Tasks:Queue(id,options)queued[#queued+1]={id=id,options=options};return"task-"..#queued,"QUEUED"end
function HolyStorm.Events:Register(event,_,callback)listeners[event]=callback end
function HolyStorm.Events:Emit()end
function HolyStorm.PlayerData:GetMetadata(_,block)return blockMetadata[block]end
function HolyStorm.PlayerData:GetBlock(_,block)return blockSnapshots[block]end
function HolyStorm.PlayerData:GetBlockFreshness(_,block)local meta=blockMetadata[block];local staleAfter=21600;local updatedAt=meta and(tonumber(meta.updatedAt)or 0)or nil;local age=updatedAt and clock-updatedAt or nil;return{metadata=meta,metadataExists=meta~=nil,stale=not meta or age>staleAfter,updatedAt=updatedAt,staleAfter=staleAfter,age=age}end
function HolyStorm.AddonLoader:GetCharacterDataDefinitions()return{{block="equipment",capability="character.scan.equipment",addonId="equipment",order=10},{block="mythicPlus",capability="character.scan.mythicplus",addonId="mythicPlus",order=20,inspectFresh=inspectMythic},{block="raid",capability="character.scan.raids",addonId="raids",order=30}}end
function UnitGUID()return"Player-Local"end

assert(loadfile(root.."Core/Tasks/CharacterScanManager.lua"))();local scans=HolyStorm.CharacterScans;scans:Initialize()
assert(not listeners.PLAYER_ENTERING_WORLD and listeners.PLAYER_LOGIN,"initial acquisition is tied to true login, not PLAYER_ENTERING_WORLD")
assert(HolyStorm.Tasks.definitions["CharacterScan.InitialBootstrap"]and not HolyStorm.Tasks.definitions["CharacterScan.InitialMissing"],"the internal bootstrap task is named for missing and stale discovery")
local started={};scans:RegisterProvider("Equipment",{block="equipment",capability="character.scan.equipment",order=10,request=function(_,reason)started[#started+1]={block="equipment",reason=reason};return"wf-equipment-"..#started end});scans:RegisterProvider("Raids",{block="raid",capability="character.scan.raids",order=30,request=function(_,reason)started[#started+1]={block="raid",reason=reason};return"wf-raid-"..#started end})
scans:RegisterProvider("MythicPlus",{block="mythicPlus",capability="character.scan.mythicplus",order=20,request=function(_,reason)started[#started+1]={block="mythicPlus",reason=reason};return"wf-mythicplus-"..#started end})

assert(scans:QueueBootstrapBlocks()and#scans.queue==1 and scans.queue[1].block=="equipment"and scans.queue[1].reason=="INITIAL_MISSING_BLOCK","a missing block queues exactly one missing initial scan")
scans:QueueBootstrapBlocks();assert(#scans.queue==1,"repeated bootstrap discovery merges the same missing block without a refresh loop")
local equipmentDecision=logs[#logs-2].context;assert(equipmentDecision.block=="equipment"and equipmentDecision.provider=="Equipment"and equipmentDecision.addonId=="equipment"and not equipmentDecision.metadataExists and equipmentDecision.stale and equipmentDecision.queued and equipmentDecision.reason=="INITIAL_MISSING_BLOCK"and equipmentDecision.skipReason=="NONE"and equipmentDecision.staleAfter==21600,"missing-block bootstrap logging records the complete decision")
assert(scans:Advance()and scans.active.block=="equipment"and#started==1 and started[1].reason=="INITIAL_MISSING_BLOCK","the missing block starts with its bootstrap reason")
assert(scans:Finish({workflowId=scans.active.workflowId},"COMPLETED"))

scans.active=nil;scans.pending={};scans.queue={};blockMetadata.equipment={version=1,updatedAt=clock-10};assert(scans:QueueBootstrapBlocks()and#scans.queue==0,"existing fresh blocks do not receive an initial scan")
local freshDecision=logs[#logs-2].context;assert(freshDecision.block=="equipment"and freshDecision.metadataExists and not freshDecision.stale and not freshDecision.queued and freshDecision.reason=="FRESH"and freshDecision.skipReason=="BLOCK_FRESH"and freshDecision.updatedAt==clock-10 and freshDecision.age==10,"fresh-block bootstrap logging records timestamp and age")

scans.active=nil;scans.pending={};scans.queue={};blockMetadata.equipment.updatedAt=clock-21601;blockMetadata.mythicPlus.updatedAt=clock-21602;blockMetadata.raid.updatedAt=clock-21603
assert(scans:QueueBootstrapBlocks()and#scans.queue==3 and scans.queue[1].block=="equipment"and scans.queue[2].block=="mythicPlus"and scans.queue[3].block=="raid","multiple stale blocks are queued in stable provider order")
assert(scans.queue[1].reason=="INITIAL_STALE_BLOCK"and scans.queue[2].reason=="INITIAL_STALE_BLOCK"and scans.queue[3].reason=="INITIAL_STALE_BLOCK","stale blocks retain the stale bootstrap reason")
assert(scans:Advance()and scans.active.block=="equipment"and started[#started].reason=="INITIAL_STALE_BLOCK","a stale block starts its provider workflow")
local activeId=scans.active.workflowId;scans:Advance();assert(scans.active.workflowId==activeId,"multiple stale blocks never overlap")
scans:Request("equipment","PLAYER_EQUIPMENT_CHANGED",true,{order=10});scans:Request("equipment","SOCKET_INFO_UPDATE",true,{order=10});scans:Request("raid","BOSS_KILL",true,{order=30});assert(scans.active.workflowId==activeId and scans.pending.equipment.reasons.PLAYER_EQUIPMENT_CHANGED and scans.pending.raid.reasons.BOSS_KILL,"events during an initial stale scan merge without creating a parallel workflow")
assert(scans:Finish({workflowId=activeId},"COMPLETED"));assert(scans:Advance()and scans.active.block=="mythicPlus"and started[#started].reason=="INITIAL_STALE_BLOCK","the stale Mythic+ workflow starts only after the prior workflow releases")
assert(scans:Finish({workflowId=scans.active.workflowId},"COMPLETED"));assert(scans:Advance()and scans.active.block=="raid"and started[#started].reason=="INITIAL_STALE_BLOCK","the stale Raid workflow is started serially")
assert(scans:Finish({workflowId=scans.active.workflowId},"COMPLETED"));assert(scans:Advance()and scans.active.block=="equipment","the dirty rescan is retained after all earlier bootstrap work")

scans.active=nil;scans.pending={};scans.queue={};blockMetadata.equipment=nil;blockMetadata.mythicPlus.updatedAt=clock-21601;blockMetadata.raid.updatedAt=clock
assert(scans:QueueBootstrapBlocks()and#scans.queue==2 and scans.queue[1].block=="equipment"and scans.queue[1].reason=="INITIAL_MISSING_BLOCK"and scans.queue[2].block=="mythicPlus"and scans.queue[2].reason=="INITIAL_STALE_BLOCK","mixed missing and stale blocks are queued together in stable order")
local queuedBeforeLogin=#queued;listeners.PLAYER_LOGIN();assert(queued[#queued].id=="CharacterScan.InitialBootstrap"and#queued==queuedBeforeLogin+1,"login schedules the renamed bootstrap task exactly once")

scans.active=nil;scans.pending={};scans.queue={};blockMetadata.equipment={version=1,updatedAt=clock};blockMetadata.mythicPlus={version=1,updatedAt=clock};blockMetadata.raid={version=1,updatedAt=clock};inspectMythic=true;scans.providers.mythicPlus=nil
local loadCalls=0;function HolyStorm.AddonLoader:LoadById(addonId,context)assert(addonId=="mythicPlus"and context.block=="mythicPlus");loadCalls=loadCalls+1;scans:RegisterProvider("MythicPlus",{block="mythicPlus",capability="character.scan.mythicplus",addonId="mythicPlus",order=20,needsRefresh=function(snapshot)for _,dungeon in pairs(snapshot.dungeons or{})do if next(dungeon.affixScores or{})then for _,entry in pairs(dungeon.affixScores)do if entry.category=="TYRANNICAL"or entry.category=="FORTIFIED"then return false,"BLOCK_FRESH"end end;return true,"AFFIX_CATEGORIES_UNRESOLVED"end end;return false,"BLOCK_FRESH"end,request=function(_,reason)started[#started+1]={block="mythicPlus",reason=reason};return"wf-mythicplus-lod"end});return true end
blockSnapshots.mythicPlus={dungeons={{affixScores={{name="Unresolved"}}}}};assert(scans:QueueBootstrapBlocks()and loadCalls==1 and#scans.queue==1 and scans.queue[1].block=="mythicPlus"and scans.queue[1].reason=="INITIAL_INCOMPLETE_BLOCK","a fresh structurally incomplete LoD block loads its provider and queues one refresh")
scans:QueueBootstrapBlocks();assert(loadCalls==1 and#scans.queue==1,"repeated bootstrap inspection merges the incomplete block without reloading or looping")
assert(scans:Advance()and scans.active.block=="mythicPlus"and started[#started].reason=="INITIAL_INCOMPLETE_BLOCK","the LoD provider starts the incomplete-block workflow")
assert(scans:Finish({workflowId=scans.active.workflowId},"COMPLETED"));scans.active=nil;scans.pending={};scans.queue={};blockSnapshots.mythicPlus={dungeons={{affixScores={{category="TYRANNICAL"},{category="FORTIFIED"}}}}};assert(scans:QueueBootstrapBlocks()and#scans.queue==0,"a fresh complete Mythic+ block does not scan again")

local projectRoot=arg[0]:gsub("tools[/\\]test_character_scan_manager.lua$","")
local eventContracts={
 {path="LIVE/Holy_Storm_Equipment/Equipment.lua",events={"PLAYER_EQUIPMENT_CHANGED","UNIT_INVENTORY_CHANGED","SOCKET_INFO_UPDATE"}},
 {path="LIVE/Holy_Storm_Raids/Raids.lua",events={"UPDATE_INSTANCE_INFO","BOSS_KILL","ENCOUNTER_END"}},
 {path="LIVE/Holy_Storm_MythicPlus/MythicPlus.lua",events={"CHALLENGE_MODE_COMPLETED","CHALLENGE_MODE_MAPS_UPDATE","MYTHIC_PLUS_CURRENT_AFFIX_UPDATE","MYTHIC_PLUS_NEW_WEEKLY_RECORD"}},
 {path="LIVE/Holy_Storm_Delves/Delves.lua",events={"WEEKLY_REWARDS_UPDATE","DELVES_ACCOUNT_DATA_ELEMENT_CHANGED","ACTIVE_DELVE_DATA_UPDATE"}},
}
for _,contract in ipairs(eventContracts)do local file=assert(io.open(projectRoot..contract.path,"rb"));local source=file:read("*a");file:close();assert(not source:find("PLAYER_ENTERING_WORLD",1,true),contract.path.." must not scan on PLAYER_ENTERING_WORLD");assert(source:find("CharacterScans:Request",1,true),contract.path.." routes events through the central scan queue");for _,event in ipairs(contract.events)do assert(source:find(event,1,true),contract.path.." keeps event "..event)end end
print("Central missing/stale bootstrap, serialization and dirty-event merge tests passed")
