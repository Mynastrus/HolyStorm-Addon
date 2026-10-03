local root=(arg[0]:gsub("tools[/\\]test_delves.lua$","")).."LIVE/Holy_Storm_Delves/"
local Module={};local events,providers,capabilities={}, {}, {};local blockDefinition;local commits={}
local playerReady=false;local HolyStorm={Utils={Now=function()return 100 end},Data={CharacterStore={}},Snapshots={},Events={},PlayerData={},CharacterScans={},State={Is=function(_,name)return name=="playerReady"and playerReady end}}
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
Enum={WeeklyRewardChestThresholdType={World=6}}
local activities={{id=10,index=1,type=6,progress=0,threshold=3,level=0},{id=11,index=2,type=6,progress=3,threshold=3,level=1}}
C_WeeklyRewards={GetActivities=function(kind)assert(kind==6);return activities end,AreRewardsForCurrentRewardPeriod=function()return true end,HasAvailableRewards=function()return false end}
C_DelvesUI={GetCurrentDelvesSeasonNumber=function()return 4 end,GetCompanionInfoForActivePlayer=function()error("incomplete companion IDs are not scanned")end}
C_DateAndTime={GetWeeklyResetStartTime=function()return 1790812800 end}
assert(loadfile(root.."Delves.lua"))()
assert(blockDefinition and blockDefinition.schemaVersion==3 and blockDefinition.snapshotVersion==3 and type(blockDefinition.validate)=="function","Delves PlayerData block declares v3 snapshot contract")
assert(#HolyStorm.metadata.permissions==1 and HolyStorm.metadata.permissions[1]=="sync-send","Delves has no view permission")
Module:OnInitialize();Module:OnEnable()
assert(events.WEEKLY_REWARDS_UPDATE and not events.DELVES_ACCOUNT_DATA_ELEMENT_CHANGED and not events.ACTIVE_DELVE_DATA_UPDATE,"only the weekly reward update triggers persisted data scans")
events.WEEKLY_REWARDS_UPDATE.callback()
assert(HolyStorm.CharacterScans.lastRequest==nil,"the first weekly reward event is treated as login data availability, not a character change")
events.WEEKLY_REWARDS_UPDATE.callback()
assert(HolyStorm.CharacterScans.lastRequest.block=="delves" and HolyStorm.CharacterScans.lastRequest.reason=="WEEKLY_REWARDS_UPDATE","later weekly reward changes use CharacterScanManager")
local provider=providers.delves.definition;assert(provider.needsRefresh==nil and provider.request(true,"MANUAL_COMMAND")=="delves-wf" and HolyStorm.Snapshots.options.priority==6,"manual provider enters the normal SnapshotManager workflow without snapshot-driven auto scans")
local snapshot=HolyStorm.Snapshots.scanner();assert(HolyStorm.Snapshots.validator(snapshot),"available current data validates")
assert(snapshot.snapshotVersion==3 and snapshot.schemaVersion==3 and snapshot.seasonNumber==4 and snapshot.weeklyIdentity==1790812800,"season and authoritative weekly reset identity are stored")
assert(snapshot.greatVaultWorld.progress==1 and snapshot.greatVaultWorld.activities[1].progress==0 and snapshot.greatVaultWorld.activities[1].threshold==3,"Great Vault World activity progress is kept distinct from Delves progression")
assert(snapshot.greatVault.rewardAvailable==false and snapshot.greatVault.currentPeriod==true,"reward availability is Great Vault-wide state for the current period")
assert(snapshot.companion==nil and snapshot.bountiful==nil and snapshot.nemesis==nil and snapshot.treasureMap==nil and snapshot.flute==nil,"unsupported fields are omitted instead of persisted as placeholder values")
assert(HolyStorm.Snapshots.commit(snapshot) and #commits==1,"valid data commits through PlayerData")
local lastValid=commits[1].snapshot
C_WeeklyRewards.GetActivities=function()return{}end
snapshot=HolyStorm.Snapshots.scanner();assert(HolyStorm.Snapshots.validator(snapshot),"API-confirmed empty activity list is valid")
assert(snapshot.greatVaultWorld.progress==0 and#snapshot.greatVaultWorld.activities==0,"known empty World activities remain a valid zero")
C_WeeklyRewards.GetActivities=function()return nil end
assert(HolyStorm.Snapshots.scanner()==nil,"unavailable activity data does not become empty")
C_WeeklyRewards.GetActivities=function()error("API unavailable")end
assert(HolyStorm.Snapshots.scanner()==nil,"API errors do not create a snapshot")
C_WeeklyRewards.GetActivities=function()return activities end
C_WeeklyRewards.AreRewardsForCurrentRewardPeriod=function()return false end
assert(HolyStorm.Snapshots.scanner()==nil,"previous-period Great Vault data is not committed as current")
C_WeeklyRewards.AreRewardsForCurrentRewardPeriod=function()return true end
C_DateAndTime.GetWeeklyResetStartTime=nil
assert(HolyStorm.Snapshots.scanner()==nil,"missing reset identity is unknown, not inferred from local calendar")
C_DateAndTime.GetWeeklyResetStartTime=function()return 1790812800 end
C_DelvesUI.GetCurrentDelvesSeasonNumber=function()return nil end
assert(HolyStorm.Snapshots.scanner()==nil,"season not ready cannot overwrite current snapshot")
assert(#commits==1 and commits[1].snapshot==lastValid,"unknown results preserve last valid committed snapshot")
C_DelvesUI.GetCurrentDelvesSeasonNumber=function()return 4 end
local invalid={snapshotVersion=3,schemaVersion=3,seasonNumber=4,weeklyIdentity=1790812800,greatVault={currentPeriod=true,rewardAvailable=false},greatVaultWorld={progress=0,activities={},completed={1}}}
assert(not HolyStorm.Snapshots.validator(invalid),"inconsistent completion list fails validation")
local handler=capabilities["character.scan.additional"];assert(type(handler)=="function");handler(Module,true,"CAPABILITY");assert(HolyStorm.CharacterScans.lastRequest.block=="delves","capability requests use the central scan manager")
Module:OnDisable();assert(not events.WEEKLY_REWARDS_UPDATE,"feature event handlers are removed on disable")
playerReady=true;Module:OnEnable();events.WEEKLY_REWARDS_UPDATE.callback();assert(HolyStorm.CharacterScans.lastRequest.block=="delves","a Delves module loaded after login scans on its first actual weekly reward update");Module:OnDisable()
print("Delves API readiness, known-empty, reset identity, last-valid and lifecycle tests passed")
