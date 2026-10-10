local root=(arg[0]:gsub("tools[/\\]test_mythicplus.lua$",""))
local featureRoot=root.."LIVE/Holy_Storm_MythicPlus/"
local Module={};local registeredEvents={};local capabilities={};local requested={maps=0,rewards=0};local workflows={created=0,merged=0,active=false,queueCalls=0};local commits,emitted,blockEvents=0,{},{ };local logEntries={}
local playerReady=false;local HolyStorm={Utils={Now=function()return 100 end},Data={CharacterStore={}},Snapshots={},Events={},Logger={},PlayerData={},State={Is=function(_,name)return name=="playerReady"and playerReady end}}
function HolyStorm.Logger:Write(level,source,category,message,context)logEntries[#logEntries+1]={level=level,source=source,category=category,message=message,context=context}end
HolyStorm.CharacterScans={providers={},requests={}}
function HolyStorm.CharacterScans:RegisterProvider(_,definition)self.providers[definition.block]=definition;return true end
function HolyStorm.CharacterScans:Request(block,reason,sync)self.requests[#self.requests+1]={block=block,reason=reason,sync=sync};return true,"QUEUED"end
function HolyStorm.PlayerData:RegisterBlock(block,definition)blockEvents[block]=definition.event;self.blockSchema=definition.schemaVersion;self.blockValidator=definition.validate;return true end
function HolyStorm.PlayerData:WriteOwnedBlock(_,block,snapshot)commits=commits+1;emitted[#emitted+1]={event=blockEvents[block],block=block,snapshot=snapshot};return true end
function HolyStorm:RegisterModule(metadata,callback)self.metadata=metadata;callback(Module)end
function HolyStorm:ApplyModuleMetadata()end
function HolyStorm:RegisterCapability(_,name,handler)capabilities[name]=handler end
function HolyStorm.Data.CharacterStore:GetBlock()end
function HolyStorm.Snapshots:Queue(_,scanner,validator,commit,options)workflows.queueCalls=workflows.queueCalls+1;workflows.scanner,workflows.validator,workflows.commit=scanner,validator,commit;workflows.lastDelay=options.delay;workflows.options=options;if workflows.active then workflows.merged=workflows.merged+1;return true,"MERGED"end;workflows.active=true;workflows.created=workflows.created+1;return true,"wf-"..workflows.created end
function HolyStorm.Snapshots:Cancel()end
function HolyStorm.Events:Register(event,_,callback)registeredEvents[event]=callback end
function HolyStorm.Events:UnregisterOwner()registeredEvents={}end
function LibStub(name)if name=="AceAddon-3.0"then return{GetAddon=function()return HolyStorm end}elseif name=="AceLocale-3.0"then return{GetLocale=function()return setmetatable({},{__index=function(_,key)return key end})end}end end
function UnitGUID()return"PLAYER-GUID"end

local date={year=2026,month=9,monthDay=30,hour=10,minute=20,weekday=4}
local function run(level,score,duration)
 return{level=level,dungeonScore=score,durationSec=duration,completionDate=date,affixIDs={101,102},members={}}
end
local pool={20,4,99}
local weeklyActivities={{id=1,index=1,progress=2,threshold=3,level=5,activityTierID=1,type=8},{id=2,index=2,progress=8,threshold=8,level=8,activityTierID=2,type=8}}
local dungeonScores={[4]={155,{{name="Tracked Affix One",score=155,level=6,durationSec=1200,overTime=false}}},[20]={0,{}},[99]={50,{{name="Tracked Affix Two",score=50,level=2,durationSec=1900,overTime=true}}}}
local bestRuns={[4]={run(6,155,1200),run(7,140,1800)},[99]={nil,run(2,50,1900)}}
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
assert(metadata.id=="mythicPlus"and metadata.name=="MythicPlus"and metadata.version=="2.4.1","module metadata identifies the audited producer")
assert(metadata.data.schemaVersion==5 and HolyStorm.PlayerData.blockSchema==5,"optional affix details advance the persisted snapshot schema")
assert(metadata.sync.domains[1]=="character"and metadata.permissions[1]=="sync-send"and metadata.permissions[2]=="sync-receive","Mythic+ uses only the standard character sync permissions")
Module:OnInitialize();Module:OnEnable()
assert(registeredEvents.CHALLENGE_MODE_COMPLETED and registeredEvents.MYTHIC_PLUS_NEW_WEEKLY_RECORD and registeredEvents.WEEKLY_REWARDS_UPDATE and not registeredEvents.CHALLENGE_MODE_MAPS_UPDATE,"only persisted character-progression events are registered; map-pool availability does not scan character snapshots")
assert(not registeredEvents.MYTHIC_PLUS_CURRENT_AFFIX_UPDATE and not registeredEvents.PLAYER_ENTERING_WORLD,"transient affix changes and generic login are not direct triggers")

local snapshot=Module:Collect()
local snapshotValid,snapshotReason=Module:Validate(snapshot);assert(snapshotValid,"complete dynamic seasonal and weekly data validates: "..tostring(snapshotReason))
assert(snapshot.snapshotVersion==5 and snapshot.schemaVersion==5 and snapshot.seasonId==18 and snapshot.displaySeasonId==3,"season identity uses Blizzard season APIs")
assert(snapshot.overallScore==0,"known zero rating remains a valid rating")
assert(snapshot.poolComplete and snapshot.dungeonCount==3 and #snapshot.dungeons==3,"all maps from Blizzard's dynamic pool are included without a hardcoded size")
assert(snapshot.dungeons[1].challengeMapId==4 and snapshot.dungeons[2].challengeMapId==20 and snapshot.dungeons[3].challengeMapId==99,"map-ID ordering is deterministic")
local timed=snapshot.dungeons[1]
assert(timed.bestInTime.level==6 and timed.bestInTime.score==155 and timed.bestInTime.affixIDs[1]==101,"the API-selected in-time record is retained without re-ranking")
assert(timed.bestInTime.completionDate.day==30 and timed.bestInTime.overTime==false and timed.bestOverTime.overTime==true,"Retail CalendarTime.monthDay is normalized to the stored day field and each best slot keeps its timed state")
assert(timed.bestOverTime.level==7 and timed.bestOverTime.score==140,"the separate API-selected overtime record is retained")
assert(timed.score==155 and timed.affixScores[1].name=="Tracked Affix One"and timed.affixScores[1].category==nil,"dungeon score and seasonal tracked-affix information stay direct and uncategorized")
assert(snapshot.dungeons[2].score==0 and snapshot.dungeons[2].bestInTime==nil and snapshot.dungeons[2].bestOverTime==nil,"successful nil best-run slots mean known no completion and a zero map score")
assert(type(snapshot.dungeons[2].affixScores)=="table"and #snapshot.dungeons[2].affixScores==0,"an API-confirmed empty affix list remains distinct from unavailable affix detail")
assert(snapshot.ownedKey==nil and snapshot.affixes==nil and snapshot.currentRun==nil,"volatile key, rotation affixes, and active run are not persisted")
assert(snapshot.weeklyIdentity==1790812800 and snapshot.greatVaultMythicPlus.progress==1 and #snapshot.greatVaultMythicPlus.activities==2,"Great Vault thresholds are stored separately from seasonal scores and run counts")
assert(snapshot.greatVaultMythicPlus.activities[2].threshold==8,"vault thresholds remain threshold metadata and are not labeled as eight runs")

assert(Module.NeedsBootstrapRefresh==nil and HolyStorm.CharacterScans.providers.mythicPlus.needsRefresh==nil,"snapshot age and season context never start a producer scan")

local zero=Module:Collect();assert(Module:Validate(zero),"rating zero is accepted")
C_ChallengeMode.GetOverallDungeonScore=function()return 2750 end
local positive=Module:Collect();assert(Module:Validate(positive)and positive.overallScore==2750,"a positive overall rating is valid and preserved")
C_ChallengeMode.GetOverallDungeonScore=function()return 0 end
local currentSeason=C_MythicPlus.GetCurrentSeason
C_MythicPlus.GetCurrentSeason=function()return nil end
local noSeason,seasonReason,seasonDiagnostics=Module:Collect();local seasonValid,seasonValidationReason,seasonRetryable=Module:Validate(noSeason,seasonReason,seasonDiagnostics)
assert(not seasonValid and seasonValidationReason=="UNKNOWN_MYTHICPLUS_SEASON"and seasonRetryable==true,"unavailable season is UNKNOWN and can become ready after the map request")
C_MythicPlus.GetCurrentSeason=currentSeason
C_ChallengeMode.GetMapTable=function()return nil end
local noPool,poolReason,poolDiagnostics=Module:Collect();local poolValid,poolValidationReason,poolRetryable=Module:Validate(noPool,poolReason,poolDiagnostics)
assert(not poolValid and poolValidationReason=="DUNGEON_POOL_NOT_READY"and poolRetryable==true,"an unavailable dungeon pool remains UNKNOWN and is retryable")
local secretPool={4};local previousSecretCheck=issecretvalue;issecretvalue=function(value)return value==secretPool end;C_ChallengeMode.GetMapTable=function()return secretPool end
local protectedPool,protectedPoolReason,protectedPoolDiagnostics=Module:Collect();assert(protectedPool==nil and protectedPoolReason=="DUNGEON_POOL_NOT_READY"and protectedPoolDiagnostics.maps==0,"secret pool values are rejected without reading their length")
issecretvalue=previousSecretCheck
C_ChallengeMode.GetMapTable=function()return{}end
local emptyPool,emptyPoolReason,emptyPoolDiagnostics=Module:Collect();local emptyPoolValid,emptyPoolValidationReason,emptyPoolRetryable=Module:Validate(emptyPool,emptyPoolReason,emptyPoolDiagnostics)
assert(not emptyPoolValid and emptyPoolValidationReason=="DUNGEON_POOL_NOT_READY"and emptyPoolRetryable==true and emptyPoolDiagnostics.maps==0,"an empty uninitialized pool is UNKNOWN rather than a confirmed zero-dungeon snapshot")
C_ChallengeMode.GetMapTable=function()return pool end
local savedMapInfo=C_ChallengeMode.GetMapUIInfo;C_ChallengeMode.GetMapUIInfo=function()return nil end
local noMapInfo,mapInfoReason,mapInfoDiagnostics=Module:Collect();local mapInfoValid,mapInfoValidationReason,mapInfoRetryable=Module:Validate(noMapInfo,mapInfoReason,mapInfoDiagnostics)
assert(not mapInfoValid and mapInfoValidationReason=="DUNGEON_MAP_INFO_NOT_READY"and mapInfoRetryable==true,"map metadata MayReturnNothing is a bounded readiness retry")
C_ChallengeMode.GetMapUIInfo=savedMapInfo
local savedBest=bestRuns[4];local malformedRun=run(6,155,1200);malformedRun.completionDate={year=2026,month=9,hour=10,minute=20,weekday=4};bestRuns[4]={malformedRun,nil}
local malformed,malformedReason,malformedDiagnostics=Module:Collect();local malformedValid,malformedValidationReason,malformedRetryable=Module:Validate(malformed,malformedReason,malformedDiagnostics)
assert(not malformedValid and malformedValidationReason=="INVALID_BEST_RUN_COMPLETION_DATE"and malformedRetryable==false and malformedDiagnostics.mapId==4,"a malformed CalendarTime is a permanent, field-specific failure with map context")
bestRuns[4]=savedBest
local persistedMalformed=Module:Collect();persistedMalformed.dungeons[1].bestInTime.completionDate={year=2026,month=9,hour=10,minute=20,weekday=4}
local persistedValid,persistedReason,persistedRetryable=Module:Validate(persistedMalformed)
assert(not persistedValid and persistedReason=="INVALID_BEST_RUN_COMPLETION_DATE"and persistedRetryable==false,"stored or synchronized malformed records retain the same field-specific reason ID")
local currentPeriod=C_WeeklyRewards.AreRewardsForCurrentRewardPeriod;C_WeeklyRewards.AreRewardsForCurrentRewardPeriod=function()return false end
local oldVault=Module:Collect();assert(oldVault and not oldVault.weeklyIdentity and not oldVault.greatVaultMythicPlus and Module:Validate(oldVault),"previous reward-period data is omitted without blocking valid seasonal progression");C_WeeklyRewards.AreRewardsForCurrentRewardPeriod=currentPeriod
C_ChallengeMode.GetOverallDungeonScore=function()return nil end
local nilRating,nilRatingReason,nilRatingDiagnostics=Module:Collect();local nilRatingValid,nilRatingValidationReason,nilRatingRetryable=Module:Validate(nilRating,nilRatingReason,nilRatingDiagnostics)
assert(not nilRatingValid and nilRatingValidationReason=="UNKNOWN_MYTHICPLUS_RATING"and nilRatingRetryable==true,"rating nil is UNKNOWN and cannot replace last-valid data")
issecretvalue=function(value)return value=="SECRET"end;C_ChallengeMode.GetOverallDungeonScore=function()return"SECRET"end
assert(Module:Collect()==nil,"secret/protected rating values are rejected before numeric conversion")
issecretvalue=nil;C_ChallengeMode.GetOverallDungeonScore=function()return 0 end
C_MythicPlus.GetSeasonBestAffixScoreInfoForMap=function()return nil,nil end
local unknownAffixSnapshot=Module:Collect();assert(unknownAffixSnapshot and Module:Validate(unknownAffixSnapshot),"MayReturnNothing affix detail stays unknown without blocking an authoritative map score")
assert(unknownAffixSnapshot.dungeons[1].score==155 and unknownAffixSnapshot.dungeons[1].affixScores==nil,"run score remains sourced from the Blizzard-selected best record while unavailable affix detail stays nil")
C_MythicPlus.GetSeasonBestAffixScoreInfoForMap=function(id)local item=dungeonScores[id];return item[2],item[1]end
pool={4,4};assert(Module:Collect()==nil,"duplicate challenge map IDs invalidate the pool")
pool={20,4,99};C_ChallengeMode.GetMapTable=function()return{4,20}end
local smaller=Module:Collect();assert(smaller and smaller.dungeonCount==2,"the current Blizzard pool may shrink and is never checked against a fixed dungeon count")
C_ChallengeMode.GetMapTable=function()return pool end

local provider=assert(HolyStorm.CharacterScans.providers.mythicPlus)
provider.request(true,"MANUAL_COMMAND");assert(requested.maps==1 and requested.rewards==1 and workflows.created==1,"an explicit manual scan requests Blizzard's asynchronous map and reward data through the central workflow")
assert(workflows.options.maxRetries==3 and workflows.options.retryDelay==2.5 and workflows.options.onValidationFailure and workflows.options.fingerprint==false,"retry diagnostics remain configured while the unused full-snapshot fingerprint is disabled")
workflows.options.onValidationFailure("DUNGEON_POOL_NOT_READY","RETRY",1,3,{season=18,rating=0,maps=0,expectedMaps=8,mapId=4})
local validationLog=logEntries[#logEntries]
assert(validationLog.level=="WARN"and validationLog.source=="MythicPlus"and validationLog.message=="MythicPlus validation: RETRY"and validationLog.context.reason=="DUNGEON_POOL_NOT_READY"and validationLog.context.season==18 and validationLog.context.rating==0 and validationLog.context.maps==0 and validationLog.context.expectedMaps==8 and validationLog.context.mapId==4 and validationLog.context.retryCount==1 and validationLog.context.maxRetries==3,"diagnostic log preserves reason ID, known zero, compact map context, and retry bounds")
provider.request(true,"CAPABILITY");assert(requested.maps==2 and requested.rewards==2 and workflows.created==1 and workflows.merged==1,"a manual scan requests fresh Retail data while reusing the serialized workflow")
provider.request(true,"CHALLENGE_MODE_COMPLETED",{MANUAL_COMMAND=true});assert(requested.maps==3 and requested.rewards==3 and workflows.merged==2,"a manual request merged with an automatic event still requests fresh map and reward data")
local pending=workflows.scanner();assert(workflows.validator(pending),"the queued scan re-collects and validates current API data")
assert(workflows.commit(pending)and commits==1 and emitted[1].event=="HS_MYTHICPLUS_UPDATED"and emitted[1].block=="mythicPlus","commit uses PlayerData's owned-block contract")
local before=#HolyStorm.CharacterScans.requests
registeredEvents.CHALLENGE_MODE_COMPLETED("CHALLENGE_MODE_COMPLETED");registeredEvents.MYTHIC_PLUS_NEW_WEEKLY_RECORD("MYTHIC_PLUS_NEW_WEEKLY_RECORD");registeredEvents.WEEKLY_REWARDS_UPDATE("WEEKLY_REWARDS_UPDATE");assert(#HolyStorm.CharacterScans.requests==before,"pre-ready Challenge Mode and score events are ignored, along with the initial vault availability event")
playerReady=true;registeredEvents.CHALLENGE_MODE_COMPLETED("CHALLENGE_MODE_COMPLETED");registeredEvents.MYTHIC_PLUS_NEW_WEEKLY_RECORD("MYTHIC_PLUS_NEW_WEEKLY_RECORD");registeredEvents.WEEKLY_REWARDS_UPDATE("WEEKLY_REWARDS_UPDATE");assert(#HolyStorm.CharacterScans.requests==before+3,"relevant post-ready progression and weekly events enter CharacterScanManager")
registeredEvents.WEEKLY_REWARDS_UPDATE("WEEKLY_REWARDS_UPDATE");assert(#HolyStorm.CharacterScans.requests==before+4,"subsequent weekly reward updates enter CharacterScanManager")
Module:OnDisable();playerReady=false;Module.loadContext={reason="event",trigger="CHALLENGE_MODE_COMPLETED"};Module:OnEnable();assert(#HolyStorm.CharacterScans.requests==before+4,"lazy-load event context cannot start a producer before playerReady")
Module:OnDisable();Module.loadContext=nil;playerReady=true;Module:OnEnable();registeredEvents.WEEKLY_REWARDS_UPDATE("WEEKLY_REWARDS_UPDATE");assert(#HolyStorm.CharacterScans.requests==before+5,"a module loaded after login treats its first weekly rewards event as a real change")
Module:OnDisable();playerReady=false;Module:OnEnable();playerReady=true;assert(not registeredEvents.HS_STATE_PLAYERREADY,"readiness alone must not release the initial weekly-event guard");registeredEvents.WEEKLY_REWARDS_UPDATE("WEEKLY_REWARDS_UPDATE");assert(#HolyStorm.CharacterScans.requests==before+5,"the first weekly event remains protected when readiness precedes the initial reward event");registeredEvents.WEEKLY_REWARDS_UPDATE("WEEKLY_REWARDS_UPDATE");assert(#HolyStorm.CharacterScans.requests==before+6,"a subsequent weekly event after readiness enters CharacterScanManager")
capabilities["character.scan.mythicplus"](Module,true);assert(#HolyStorm.CharacterScans.requests==before+7,"manual capability refresh follows the same centralized scan path")
Module:OnDisable();assert(not registeredEvents.CHALLENGE_MODE_COMPLETED,"event handlers are removed on disable")
print("Mythic+ Retail snapshot, season, pool, best-run, vault, readiness, and workflow tests passed")
