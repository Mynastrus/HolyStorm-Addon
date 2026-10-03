-- Regression for the Retail M+ boss event reaching the lazy-loaded Raid module.
local root=(arg[0]:gsub("tools[/\\]test_raid_trigger_routing.lua$",""))
local callbacks,requests,logs={}, {}, {}
local module,provider,raidLoadCalls,snapshotQueues,statisticsDiscoveries
module=nil;provider=nil;raidLoadCalls=0;snapshotQueues=0;statisticsDiscoveries=0
local instanceType="party"
local function copy(value,seen)if type(value)~="table"then return value end;seen=seen or{};if seen[value]then return seen[value]end;local out={};seen[value]=out;for key,item in pairs(value)do out[copy(key,seen)]=copy(item,seen)end;return out end
local HolyStorm={Utils={DeepCopy=copy,Now=function()return 100 end},Events={},Logger={},CharacterScans={},Snapshots={},PlayerData={RegisterBlock=function()end},Data={CharacterStore={GetBlock=function()end,GetBlockMetadata=function()end}}}
function HolyStorm.Logger:Write(level,source,category,message,context)logs[#logs+1]={level=level,source=source,category=category,message=message,context=context}end
function HolyStorm.Events:Register(event,owner,callback)self.listeners=self.listeners or{};self.listeners[event]=self.listeners[event]or{};self.listeners[event][owner]=callback;callbacks[event]=self.listeners[event]end
function HolyStorm.Events:UnregisterOwner(owner)for event,bucket in pairs(self.listeners or{})do bucket[owner]=nil end end
function HolyStorm.Events:Emit(event,...)
 local bucket=self.listeners[event];if not bucket then return end;local list={};for owner,callback in pairs(bucket)do list[#list+1]={owner,callback}end
 for _,entry in ipairs(list)do entry[2](event,...)end
end
function HolyStorm.CharacterScans:RegisterProvider(_,definition)provider=definition;return true end
function HolyStorm.CharacterScans:Request(block,reason,sync)
 requests[#requests+1]={block=block,reason=reason,sync=sync};return true,"QUEUED"
end
function HolyStorm.Snapshots:Queue()snapshotQueues=snapshotQueues+1;return true,"wf-test"end
function HolyStorm.Snapshots:Cancel()end
function HolyStorm:RegisterModule(_,factory)module={};factory(module)end
function HolyStorm:ApplyModuleMetadata(target,metadata)target.metadata=metadata;target.loadContext=self:GetAddonLoadContext(metadata.id)end
function HolyStorm:RegisterCapability()end
function HolyStorm:GetAddonLoadContext(id)return self.AddonLoader:GetLoadContext(id)end
local loaded={Holy_Storm=true}
C_AddOns={
 GetNumAddOns=function()return 1 end,
 GetAddOnInfo=function(index)assert(index==1);return"Holy_Storm_Raids"end,
 GetAddOnMetadata=function(name,key)assert(name=="Holy_Storm_Raids");return({["X-HolyStorm-ID"]="raids",["X-HolyStorm-LoadOnEvent"]="ENCOUNTER_END",["X-HolyStorm-CharacterBlock"]="raid",["X-HolyStorm-CharacterCapability"]="character.scan.raids"})[key]end,
 IsAddOnLoaded=function(name)return loaded[name]==true end,
 LoadAddOn=function(name)
  assert(name=="Holy_Storm_Raids");raidLoadCalls=raidLoadCalls+1;loaded[name]=true
  assert(loadfile(root.."LIVE/Holy_Storm_Raids/Raids.lua"))()
  module:OnInitialize();module:OnEnable();return true
 end,
}
function IsInInstance()return instanceType~="none",instanceType end
function GetTime()return 100 end
function GetStatisticsCategoryList()statisticsDiscoveries=statisticsDiscoveries+1;return{}end
function LibStub(name)if name=="AceAddon-3.0"then return{GetAddon=function()return HolyStorm end}elseif name=="AceLocale-3.0"then return{GetLocale=function()return setmetatable({},{__index=function(_,key)return key end})end}end;error("unexpected library "..tostring(name))end
assert(loadfile(root.."LIVE/Holy_Storm/Core/Registry/AddonLoader.lua"))()
HolyStorm.AddonLoader:Initialize()
assert(callbacks.ENCOUNTER_END and callbacks.ENCOUNTER_END["addon-loader:ENCOUNTER_END"],"the Raid addon declares ENCOUNTER_END as its lazy-load event")

-- The reported M+ event lazy-loads Raids, but its load context must not scan the Raid domain.
HolyStorm.Events:Emit("ENCOUNTER_END",501,"Dungeon Boss",8,5,1)
assert(raidLoadCalls==1 and module.loadContext.trigger=="ENCOUNTER_END"and module.loadContext.arguments[5]==1,"the lazy loader carries the ENCOUNTER_END success payload into the module")
assert(#requests==0 and snapshotQueues==0 and statisticsDiscoveries==0,"an M+ ENCOUNTER_END loads Raids without starting discovery or a Raid snapshot")
HolyStorm.Events:Emit("CHALLENGE_MODE_COMPLETED")
HolyStorm.Events:Emit("CRITERIA_UPDATE")
HolyStorm.Events:Emit("STATISTIC_UPDATE")
HolyStorm.Events:Emit("BOSS_KILL",501,"Dungeon Boss")
assert(#requests==0 and snapshotQueues==0 and statisticsDiscoveries==0,"M+, criteria, statistics and generic boss events do not request Raid work")

-- Raid-only events still request one scan; failed encounters do not.
instanceType="raid"
HolyStorm.Events:Emit("ENCOUNTER_END",9001,"Raid Boss",16,20,0)
assert(#requests==0,"an unsuccessful Raid encounter does not refresh lifetime progress")
HolyStorm.Events:Emit("ENCOUNTER_END",9001,"Raid Boss",16,20,1)
assert(#requests==1 and requests[1].block=="raid"and requests[1].reason=="ENCOUNTER_END","a successful Raid encounter requests the Raid character scan")
local generation=module.raidScanGeneration
HolyStorm.CharacterScans.active={block="raid",workflowId="wf-active"};module.activeRaidRun={workflowId="wf-active",commitStarted=false}
module.raidInfoRequestPendingUntil=150
HolyStorm.Events:Emit("UPDATE_INSTANCE_INFO")
assert(#requests==1 and module.raidScanGeneration==generation,"the expected RequestRaidInfo response folds into the active scan without invalidating its partial work")
HolyStorm.Events:Emit("ENCOUNTER_END",9002,"Next Raid Boss",16,20,1)
assert(#requests==2 and requests[2].block=="raid"and requests[2].reason=="ENCOUNTER_END"and module.raidScanGeneration==generation,"a newer Raid event is queued once after the active scan while preserving its in-flight progress")
HolyStorm.CharacterScans.active=nil;module.activeRaidRun=nil
HolyStorm.Events:Emit("ENCOUNTER_END",9003,"Following Raid Boss",16,20,1)
assert(#requests==3 and module.raidScanGeneration==generation+1,"a Raid event outside an active scan advances the scan generation and starts a fresh scan")
instanceType="party";HolyStorm.Events:Emit("UPDATE_INSTANCE_INFO")
assert(#requests==3,"UPDATE_INSTANCE_INFO while in M+ cannot request a Raid scan")
HolyStorm.AddonLoader:Shutdown()
print("Raid lazy-load, M+ encounter routing, Raid-only refresh and active-scan coalescing tests passed")
