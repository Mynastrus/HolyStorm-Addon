local root=(arg[0]:gsub("tools[/\\]test_mythicplus.lua$",""))
local featureRoot=root.."LIVE/Holy_Storm_MythicPlus/"
local Module={};local registeredEvents={};local capabilities={};local requested={maps=0,rewards=0};local workflows={created=0,merged=0,active=false,queueCalls=0};local commits,emitted,blockEvents=0,{},{ }
local HolyStorm={Utils={Now=function()return 100 end},Data={CharacterStore={}},Snapshots={},Events={},Logger={},PlayerData={}}
HolyStorm.CharacterScans={providers={},requests={}}
function HolyStorm.CharacterScans:RegisterProvider(_,definition)self.providers[definition.block]=definition;return true end
function HolyStorm.CharacterScans:Request(block,reason,sync)self.requests[#self.requests+1]={block=block,reason=reason,sync=sync};return true,"QUEUED"end
function HolyStorm.PlayerData:RegisterBlock(block,definition)blockEvents[block]=definition.event;self.blockSchema=definition.schemaVersion;self.blockValidator=definition.validate;return true end
function HolyStorm.PlayerData:WriteOwnedBlock(_,block,snapshot)commits=commits+1;emitted[#emitted+1]={event=blockEvents[block],block=block,snapshot=snapshot};return true end
function HolyStorm:RegisterModule(metadata,callback)self.metadata=metadata;callback(Module)end
function HolyStorm:ApplyModuleMetadata()end
function HolyStorm:RegisterCapability(_,name,handler)capabilities[name]=handler end
function HolyStorm.Data.CharacterStore:GetBlock()end
function HolyStorm.Snapshots:Queue(_,scanner,validator,commit,options)workflows.queueCalls=workflows.queueCalls+1;workflows.scanner,workflows.validator,workflows.commit=scanner,validator,commit;workflows.lastDelay=options.delay;if workflows.active then workflows.merged=workflows.merged+1;return true,"MERGED"end;workflows.active=true;workflows.created=workflows.created+1;return true,"wf-"..workflows.created end
function HolyStorm.Snapshots:Cancel()end
function HolyStorm.Events:Register(event,_,callback)registeredEvents[event]=callback end
function HolyStorm.Events:UnregisterOwner()registeredEvents={}end
function LibStub(name)if name=="AceAddon-3.0"then return{GetAddon=function()return HolyStorm end}elseif name=="AceLocale-3.0"then return{GetLocale=function()return setmetatable({},{__index=function(_,key)return key end})end}end end
function UnitGUID()return"PLAYER-GUID"end

local date={year=2026,month=9,day=30,hour=10,minute=20,weekday=4}
local function run(level,score,duration)
 return{level=level,dungeonScore=score,durationSec=duration,completionDate=date,affixIDs={101,102},members={}}
end
local pool={20,4,99}
local weeklyActivities={{id=1,index=1,progress=2,threshold=3,level=5,activityTierID=1,type=8},{id=2,index=2,progress=8,threshold=8,level=8,activityTierID=2,type=8}}
local dungeonScores={[4]={155,{{name="Tracked Affix One",score=155,level=6,durationSec=1200,overTime=false}}},[20]={0,{}},[99]={50,{{name="Tracked Affix Two",score=50,level=2,durationSec=1900,overTime=true}}}}
local bestRuns={[4]={run(6,145,1200),run(7,140,1800)},[99]={nil,run(2,50,1900)}}
C_MythicPlus={
 GetCurrentSeason=function()return 18 end,GetCurrentUIDisplaySeason=function()return 3 end,
 RequestMapInfo=function()requested.maps= requested.maps+1 end,RequestRewards=function()requested.rewards=requested.rewards+1 end,
 GetSeasonBestAffixScoreInfoForMap=function(id)local item=dungeonScores[id];return item and item[2],item and item[1]end,
 GetSeasonBestForMap=function(id)local item=bestRuns[id];return item and item[1],item and item[2]end,
}
C_ChallengeMode={
 GetOverallDungeonScore=function()return 0 end,GetMapTable=function()return pool end,
 GetMapUIInfo=function(id)return"Dungeon "..id,100+id,1800,200+id,300+id,400+id end,
 GetDungeonScoreRarityColor=function()return{r=1,g=1,b=1}end,
}
Enum={WeeklyRewardChestThresholdType={MythicPlus=12}}
C_DateAndTime={GetWeeklyResetStartTime=function()return 1790812800 end}
C_WeeklyRewards={
 AreRewardsForCurrentRewardPeriod=function()return true end,
 GetActivities=function(kind)assert(kind==12,"only Mythic+ reward activities are requested");return weeklyActivities end,
}

assert(loadfile(featureRoot.."MythicPlus.lua"))()
local metadata=HolyStorm.metadata
assert(metadata.id=="mythicPlus"and metadata.name=="MythicPlus"and metadata.version=="2.3.0","module metadata identifies the audited producer")
assert(metadata.data.schemaVersion==4 and HolyStorm.PlayerData.blockSchema==4,"breaking seasonal run semantics advance the persisted schema")
assert(metadata.sync.domains[1]=="character"and metadata.permissions[1]=="sync-send"and metadata.permissions[2]=="sync-receive","Mythic+ uses only the standard character sync permissions")
Module:OnInitialize();Module:OnEnable()
assert(registeredEvents.CHALLENGE_MODE_COMPLETED and registeredEvents.CHALLENGE_MODE_MAPS_UPDATE and registeredEvents.MYTHIC_PLUS_NEW_WEEKLY_RECORD and registeredEvents.WEEKLY_REWARDS_UPDATE,"only persisted-progression events are registered")
assert(not registeredEvents.MYTHIC_PLUS_CURRENT_AFFIX_UPDATE and not registeredEvents.PLAYER_ENTERING_WORLD,"transient affix changes and generic login are not direct triggers")

local snapshot=Module:Collect()
local snapshotValid,snapshotReason=Module:Validate(snapshot);assert(snapshotValid,"complete dynamic seasonal and weekly data validates: "..tostring(snapshotReason))
assert(snapshot.snapshotVersion==4 and snapshot.schemaVersion==4 and snapshot.seasonId==18 and snapshot.displaySeasonId==3,"season identity uses Blizzard season APIs")
assert(snapshot.overallScore==0,"known zero rating remains a valid rating")
assert(snapshot.poolComplete and snapshot.dungeonCount==3 and #snapshot.dungeons==3,"all maps from Blizzard's dynamic pool are included without a hardcoded size")
assert(snapshot.dungeons[1].challengeMapId==4 and snapshot.dungeons[2].challengeMapId==20 and snapshot.dungeons[3].challengeMapId==99,"map-ID ordering is deterministic")
local timed=snapshot.dungeons[1]
assert(timed.bestInTime.level==6 and timed.bestInTime.score==145 and timed.bestInTime.affixIDs[1]==101,"the API-selected in-time record is retained without re-ranking")
assert(timed.bestOverTime.level==7 and timed.bestOverTime.score==140,"the separate API-selected overtime record is retained")
assert(timed.score==155 and timed.affixScores[1].name=="Tracked Affix One"and timed.affixScores[1].category==nil,"dungeon score and seasonal tracked-affix information stay direct and uncategorized")
assert(snapshot.dungeons[2].score==0 and snapshot.dungeons[2].bestInTime==nil and snapshot.dungeons[2].bestOverTime==nil,"known no-completion map score zero is distinct from unavailable API data")
assert(snapshot.ownedKey==nil and snapshot.affixes==nil and snapshot.currentRun==nil,"volatile key, rotation affixes, and active run are not persisted")
assert(snapshot.weeklyIdentity==1790812800 and snapshot.greatVaultMythicPlus.progress==1 and #snapshot.greatVaultMythicPlus.activities==2,"Great Vault thresholds are stored separately from seasonal scores and run counts")
assert(snapshot.greatVaultMythicPlus.activities[2].threshold==8,"vault thresholds remain threshold metadata and are not labeled as eight runs")

local old=Module:Collect();C_MythicPlus.GetCurrentSeason=function()return 19 end
local refresh,reason=Module:NeedsBootstrapRefresh(old);assert(refresh and reason=="SEASON_MISMATCH","bootstrap refreshes a stored snapshot after a season change")
C_MythicPlus.GetCurrentSeason=function()return 18 end
C_DateAndTime.GetWeeklyResetStartTime=function()return 1790812801 end
refresh,reason=Module:NeedsBootstrapRefresh(old);assert(refresh and reason=="WEEKLY_RESET_MISMATCH","current vault data refreshes after the shared weekly reset identity changes")
C_DateAndTime.GetWeeklyResetStartTime=function()return 1790812800 end

local zero=Module:Collect();assert(Module:Validate(zero),"rating zero is accepted")
local currentPeriod=C_WeeklyRewards.AreRewardsForCurrentRewardPeriod;C_WeeklyRewards.AreRewardsForCurrentRewardPeriod=function()return false end
local oldVault=Module:Collect();assert(oldVault and not oldVault.weeklyIdentity and not oldVault.greatVaultMythicPlus and Module:Validate(oldVault),"previous reward-period data is omitted without blocking valid seasonal progression");C_WeeklyRewards.AreRewardsForCurrentRewardPeriod=currentPeriod
C_ChallengeMode.GetOverallDungeonScore=function()return nil end
assert(Module:Collect()==nil,"a nil rating is unavailable and cannot replace last-valid data")
issecretvalue=function(value)return value=="SECRET"end;C_ChallengeMode.GetOverallDungeonScore=function()return"SECRET"end
assert(Module:Collect()==nil,"secret/protected rating values are rejected before numeric conversion")
issecretvalue=nil;C_ChallengeMode.GetOverallDungeonScore=function()return 0 end
C_MythicPlus.GetSeasonBestAffixScoreInfoForMap=function(id)if id==20 then return nil,nil end;local item=dungeonScores[id];return item[2],item[1]end
assert(Module:Collect()==nil,"one missing per-map score response blocks partial seasonal pool commits")
C_MythicPlus.GetSeasonBestAffixScoreInfoForMap=function(id)local item=dungeonScores[id];return item[2],item[1]end
pool={4,4};assert(Module:Collect()==nil,"duplicate challenge map IDs invalidate the pool")
pool={20,4,99};C_ChallengeMode.GetMapTable=function()return{4,20}end
local smaller=Module:Collect();assert(smaller and smaller.dungeonCount==2,"the current Blizzard pool may shrink and is never checked against a fixed dungeon count")
C_ChallengeMode.GetMapTable=function()return pool end

local provider=assert(HolyStorm.CharacterScans.providers.mythicPlus)
provider.request(true,"INITIAL_MISSING_BLOCK");assert(requested.maps==1 and requested.rewards==1 and workflows.created==1,"bootstrap requests Blizzard's asynchronous map and seasonal score data through the central workflow")
local pending=workflows.scanner();assert(workflows.validator(pending),"the queued scan re-collects and validates current API data")
assert(workflows.commit(pending)and commits==1 and emitted[1].event=="HS_MYTHICPLUS_UPDATED"and emitted[1].block=="mythicPlus","commit uses PlayerData's owned-block contract")
local before=#HolyStorm.CharacterScans.requests
for _,name in ipairs({"CHALLENGE_MODE_COMPLETED","CHALLENGE_MODE_MAPS_UPDATE","MYTHIC_PLUS_NEW_WEEKLY_RECORD","WEEKLY_REWARDS_UPDATE"})do registeredEvents[name](name)end
assert(#HolyStorm.CharacterScans.requests==before+4,"completion, score update, map update, and vault update enter CharacterScanManager")
capabilities["character.scan.mythicplus"](Module,true);assert(#HolyStorm.CharacterScans.requests==before+5,"manual capability refresh follows the same centralized scan path")
Module:OnDisable();assert(not registeredEvents.CHALLENGE_MODE_COMPLETED,"event handlers are removed on disable")
print("Mythic+ Retail snapshot, season, pool, best-run, vault, readiness, and workflow tests passed")
