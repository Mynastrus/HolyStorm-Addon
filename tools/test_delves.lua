local root=(arg[0]:gsub("tools[/\\]test_delves.lua$","")).."LIVE/Holy_Storm_Delves/"
local Module={};local events,providers,capabilities={}, {}, {};local blockDefinition;local commits={}
local HolyStorm={Utils={Now=function()return 100 end},Data={CharacterStore={}},Snapshots={},Events={},PlayerData={},CharacterScans={}}
function HolyStorm.PlayerData:RegisterBlock(id,definition)assert(id=="delves");blockDefinition=definition;return true end
function HolyStorm.PlayerData:WriteOwnedBlock(_,block,snapshot)commits[#commits+1]={block=block,snapshot=snapshot};return true end
function HolyStorm.Data.CharacterStore:GetBlock()end
function HolyStorm.Snapshots:Queue(_,scanner,validator,commit,options)self.scanner,self.validator,self.commit,self.options=scanner,validator,commit,options;return true,"delves-wf"end
function HolyStorm.Snapshots:Cancel()end
function HolyStorm.CharacterScans:RegisterProvider(owner,definition)providers[definition.block]={owner=owner,definition=definition};return true end
function HolyStorm.CharacterScans:Request(block,reason,sync)self.lastRequest={block=block,reason=reason,sync=sync};return true,"QUEUED"end
function HolyStorm.Events:Register(event,owner,callback)events[event]={owner=owner,callback=callback}end
function HolyStorm.Events:UnregisterOwner(owner)for event,entry in pairs(events)do if entry.owner==owner then events[event]=nil end end end
function HolyStorm:RegisterModule(metadata,callback)self.metadata=metadata;callback(Module)end
function HolyStorm:ApplyModuleMetadata()end
function HolyStorm:RegisterCapability(_,id,callback)capabilities[id]=callback end
local locale=setmetatable({DISPLAY_NAME="Delves",DESCRIPTION="Delves",RULE_FIELD_STATUS="Status",RULE_FIELD_STATUS_DESC="Status"},{__index=function(_,key)return key end})
function LibStub(name)if name=="AceAddon-3.0"then return{GetAddon=function()return HolyStorm end}elseif name=="AceLocale-3.0"then return{GetLocale=function()return locale end}end end
function UnitGUID()return"Player-Local"end
function date()return"2026-W40"end
local weeklyActivities={{id=10,index=1,type=6,progress=0,threshold=3,level=0},{id=11,index=2,type=6,progress=3,threshold=3,level=1}}
Enum={WeeklyRewardChestThresholdType={World=6}}
C_WeeklyRewards={GetActivities=function(kind)assert(kind==6);return weeklyActivities end,HasAvailableRewards=function()return false end}
C_DelvesUI={GetCurrentDelvesSeasonNumber=function()return 4 end,GetCompanionInfoForActivePlayer=function()return 7 end,GetFactionForCompanion=function()return 3 end,GetTraitTreeForCompanion=function()return 12 end}
assert(loadfile(root.."Delves.lua"))()
assert(blockDefinition and blockDefinition.schemaVersion==2 and blockDefinition.snapshotVersion==2 and type(blockDefinition.validate)=="function","Delves PlayerData block declares its snapshot contract")
Module:OnInitialize();Module:OnEnable()
assert(events.WEEKLY_REWARDS_UPDATE and events.DELVES_ACCOUNT_DATA_ELEMENT_CHANGED and events.ACTIVE_DELVE_DATA_UPDATE,"Delves listens to weekly and active Delves update triggers")
events.WEEKLY_REWARDS_UPDATE.callback("WEEKLY_REWARDS_UPDATE")
assert(HolyStorm.CharacterScans.lastRequest.block=="delves" and HolyStorm.CharacterScans.lastRequest.reason=="WEEKLY_REWARDS_UPDATE","automatic updates use CharacterScanManager")
local provider=providers.delves.definition;local workflowId=provider.request(true,"MANUAL_COMMAND")
assert(workflowId=="delves-wf" and HolyStorm.Snapshots.options.priority==6,"manual provider enters the same SnapshotManager workflow")
local snapshot=HolyStorm.Snapshots.scanner();assert(HolyStorm.Snapshots.validator(snapshot),"available Delves data validates")
assert(snapshot.snapshotVersion==2 and snapshot.seasonNumber==4 and snapshot.weeklyProgress==1 and snapshot.weeklyRewardAvailable==false,"known zero activity and unavailable reward are represented distinctly")
assert(snapshot.activities[1].progress==0 and snapshot.activities[1].threshold==3 and snapshot.companion.id==7,"weekly activity and confirmed companion identity are retained")
assert(snapshot.bountiful.status=="unknown" and snapshot.companion.level.status=="unknown","unsupported Delves fields remain explicitly unknown")
assert(HolyStorm.Snapshots.commit(snapshot) and #commits==1,"valid Delves snapshot commits through PlayerData")

local lastValid=commits[1].snapshot
C_WeeklyRewards.GetActivities=function()return nil end
assert(HolyStorm.Snapshots.scanner()==nil,"unavailable activity data does not become an empty table")
local unavailableValid=HolyStorm.Snapshots.validator(nil);assert(not unavailableValid,"unavailable API result fails validation")
assert(#commits==1 and commits[1].snapshot==lastValid,"unavailable scan preserves the last committed snapshot")
C_WeeklyRewards.GetActivities=function()error("API unavailable")end
assert(HolyStorm.Snapshots.scanner()==nil and #commits==1,"API failure cannot publish or replace the last valid snapshot")
C_WeeklyRewards.GetActivities=function()return{}end
C_WeeklyRewards.HasAvailableRewards=nil
snapshot=HolyStorm.Snapshots.scanner();assert(HolyStorm.Snapshots.validator(snapshot),"confirmed empty activity results remain valid")
assert(snapshot.weeklyProgress==0 and snapshot.weeklyRewardAvailable.status=="unknown","known empty progression differs from unknown reward availability")
local handler=capabilities["character.scan.additional"];assert(type(handler)=="function");handler(Module,true,"CAPABILITY");assert(HolyStorm.CharacterScans.lastRequest.block=="delves","capability requests use the central scan manager")
Module:OnDisable();assert(not events.WEEKLY_REWARDS_UPDATE,"feature event handlers are removed on disable")
print("Delves unknown/empty, last-valid, trigger and lifecycle tests passed")
