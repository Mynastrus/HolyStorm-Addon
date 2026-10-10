-- Focused end-to-end Delves producer test through CharacterScanManager,
-- SnapshotManager, WorkflowManager, PlayerData commit, and runtime diagnostics.
local repository=arg[0]:gsub("tools[/\\]test_delves_workflow.lua$","")
local coreRoot=repository.."LIVE/Holy_Storm/"
local monotonic,epoch=0,1900000000
function GetTime()return monotonic end
function time()return epoch+math.floor(monotonic)end
function InCombatLockdown()return false end
local Module={}
local timers={}
C_Timer={NewTimer=function(delay,callback)local timer={cancelled=false,due=monotonic+delay,callback=callback};function timer:Cancel()self.cancelled=true end;timers[#timers+1]=timer;return timer end,NewTicker=function(_,callback)local timer={callback=callback};function timer:Cancel()self.cancelled=true end;return timer end}
local HolyStorm={db={profile={taskManager={}}}}
function HolyStorm:GetAddon()return self end
function HolyStorm:GetLocale()return setmetatable({},{__index=function(_,key)return key end})end
function HolyStorm:IsModuleAvailable()return true end
function HolyStorm:ApplyModuleMetadata()end
function HolyStorm:RegisterModule(_,callback)callback(Module);return true end
function HolyStorm:RegisterCapability(_,id,callback)self.capabilities=self.capabilities or{};self.capabilities[id]=callback;return true end
HolyStorm.Utils={}
function HolyStorm.Utils.DeepCopy(value,seen)if type(value)~="table"then return value end;seen=seen or{};if seen[value]then return seen[value]end;local out={};seen[value]=out;for key,child in pairs(value)do out[HolyStorm.Utils.DeepCopy(key,seen)]=HolyStorm.Utils.DeepCopy(child,seen)end;return out end
function HolyStorm.Utils.TableCount(value)local count=0;for _ in pairs(value or{})do count=count+1 end;return count end
function HolyStorm.Utils.Now()return time()end
function HolyStorm.Utils.SafeCall(_,callback,...)local args={...};return xpcall(function()return callback(table.unpack(args))end,function(err)return tostring(err)end)end
HolyStorm.Events={listeners={}}
function HolyStorm.Events:Register(event,owner,callback)self.listeners[event]=self.listeners[event]or{};self.listeners[event][owner]=callback end
function HolyStorm.Events:UnregisterOwner(owner)for _,listeners in pairs(self.listeners)do listeners[owner]=nil end end
function HolyStorm.Events:Emit(event,...)for _,callback in pairs(self.listeners[event]or{})do callback(event,...)end end
HolyStorm.Logger={history={}}
function HolyStorm.Logger:Write(level,source,category,message,context)self.history[#self.history+1]={level=level,source=source,category=category,message=message,context=context}end
HolyStorm.State={values={playerLoggedIn=true,playerReady=true,guildAvailable=true,guildRosterReady=false}}
function HolyStorm.State:Is(key)return self.values[key]==true end
function LibStub()return HolyStorm end

assert(loadfile(coreRoot.."Core/Tasks/TaskManager.lua"))()
assert(loadfile(coreRoot.."Core/Workflows/WorkflowManager.lua"))()
assert(loadfile(coreRoot.."Core/Serialization/Serializer.lua"))()
HolyStorm.Events.listeners.PLAYER_LOGIN={}
local ownedBlocks={}
HolyStorm.PlayerData={}
function HolyStorm.PlayerData:RegisterBlock()return true end
function HolyStorm.PlayerData:FingerprintSnapshot(value)
 local ignored={updatedAt=true,committedAt=true,receivedAt=true,originCreatedAt=true,receivedFrom=true,transport=true,transportMetadata=true,syncMetadata=true,schemaVersion=true,snapshotVersion=true}
 local function comparable(item,isRoot)if type(item)~="table"then return item end;local out={};for key,child in pairs(item)do if not(isRoot and ignored[key])then out[key]=comparable(child,false)end end;return out end
 return HolyStorm.Serializer:Serialize(comparable(value,true))
end
function HolyStorm.PlayerData:WriteOwnedBlock(guid,block,snapshot)
 local character=ownedBlocks[guid]or{};local fingerprint=self:FingerprintSnapshot(snapshot);local previous=character[block]
 if previous and previous.fingerprint==fingerprint then return false,"UNCHANGED"end
 local version=previous and previous.metadata.version+1 or 1
 character[block]={data=HolyStorm.Utils.DeepCopy(snapshot),fingerprint=fingerprint,metadata={version=version,originCreatedAt=time()}}
 ownedBlocks[guid]=character;return true
end
HolyStorm.Data={CharacterStore={}}
function HolyStorm.Data.CharacterStore:GetBlock(guid,block)local record=ownedBlocks[guid]and ownedBlocks[guid][block];return record and HolyStorm.Utils.DeepCopy(record.data),record and HolyStorm.Utils.DeepCopy(record.metadata)end
function UnitGUID()return"Player-Delves-Test"end
Enum={WeeklyRewardChestThresholdType={World=6}}
local season=4
C_DelvesUI={GetCurrentDelvesSeasonNumber=function()return season end}
C_DateAndTime={GetWeeklyResetStartTime=function()return 1900000000 end}
local worldActivities={{id=801,index=1,type=6,progress=0,threshold=3,level=4},{id=802,index=2,type=6,progress=3,threshold=3,level=8}}
C_WeeklyRewards={AreRewardsForCurrentRewardPeriod=function()return false end,HasAvailableRewards=function()return false end,GetActivities=function(kind)assert(kind==6);return worldActivities end}

assert(loadfile(coreRoot.."Persistence/SnapshotManager.lua"))()
local snapshotFingerprintCalls=0;local originalSnapshotFingerprint=HolyStorm.Snapshots.Fingerprint
HolyStorm.Snapshots.Fingerprint=function(self,value)snapshotFingerprintCalls=snapshotFingerprintCalls+1;return originalSnapshotFingerprint(self,value)end
assert(loadfile(coreRoot.."Core/Tasks/CharacterScanManager.lua"))()
assert(loadfile(repository.."LIVE/Holy_Storm_Delves/Delves.lua"))()
HolyStorm.Tasks:Initialize();HolyStorm.Workflows:Initialize();HolyStorm.CharacterScans:Initialize()
Module:OnInitialize();Module:OnEnable()
local function processAll(limit)
 for _=1,limit or 100 do
  if#HolyStorm.Tasks.queue==0 and not HolyStorm.Tasks.runningTaskId then return end
  HolyStorm.Tasks.timer,HolyStorm.Tasks.timerDue=nil,nil;HolyStorm.Tasks:Process()
  local earliest;for _,task in ipairs(HolyStorm.Tasks.queue)do if task.blockReason=="DEBOUNCE"then earliest=earliest and math.min(earliest,task.notBefore)or task.notBefore end end
  if earliest and earliest>monotonic then monotonic=earliest end
 end
 error("Delves workflow scheduler did not drain")
end
local function request(reason)assert(HolyStorm.CharacterScans:Request("delves",reason or"MANUAL_COMMAND",false,{manual=true,order=40}));processAll()end
local function stored()local data,meta=HolyStorm.Data.CharacterStore:GetBlock("Player-Delves-Test","delves");return data,meta end
local function seed(data,version,originCreatedAt)
 local character=ownedBlocks["Player-Delves-Test"]or{};character.delves={data=HolyStorm.Utils.DeepCopy(data),fingerprint=HolyStorm.PlayerData:FingerprintSnapshot(data),metadata={version=version,originCreatedAt=originCreatedAt}};ownedBlocks["Player-Delves-Test"]=character
end
local old={snapshotVersion=3,schemaVersion=3,seasonNumber=4,weeklyIdentity=1890000000,greatVault={currentPeriod=true,rewardAvailable=false},greatVaultWorld={progress=1,completed={1},activities={{id=701,index=1,progress=3,threshold=3,level=6}}},updatedAt=1890000000}
seed(old,7,1890000010)
local oldStored,oldMeta=stored();assert(oldStored.weeklyIdentity~=C_DateAndTime.GetWeeklyResetStartTime(),"test begins with a readable previous-reset snapshot")

-- A successful current identity replaces stale data only at the atomic commit.
assert(HolyStorm.CharacterScans:Request("delves","MANUAL_COMMAND",false,{manual=true,order=40}));local activeQueue=HolyStorm.CharacterScans.pending.delves;local duringRefresh,duringRefreshMeta=stored();assert(activeQueue and duringRefresh.weeklyIdentity==oldStored.weeklyIdentity and duringRefreshMeta.version==7,"cached values stay stored while a refresh is queued")
processAll();local current,currentMeta=stored();assert(current.weeklyIdentity==1900000000 and current.seasonNumber==4 and current.greatVaultWorld.progress==1 and currentMeta.version==8 and currentMeta.originCreatedAt>oldMeta.originCreatedAt,"validated current snapshot atomically replaces the previous-week block")
assert(snapshotFingerprintCalls==0,"Delves avoids the redundant SnapshotManager fingerprint; PlayerData still performs its required equality check at commit")

-- A scan with no semantic changes is successful without a revision/timestamp bump.
local currentOrigin=currentMeta.originCreatedAt;request("MANUAL_COMMAND");local unchanged,unchangedMeta=stored();assert(unchangedMeta.version==8 and unchangedMeta.originCreatedAt==currentOrigin and unchanged.weeklyIdentity==1900000000,"unchanged scans do not advance origin revision or timestamp")

-- The false period flag is valid when no previous reward is available; an
-- unclaimed old reward makes only its ambiguous World subsection unknown.
local runtimeSnapshot,optionalReason,optionalDiagnostics=Module:Collect();assert(runtimeSnapshot and runtimeSnapshot.greatVault.currentPeriod==false and runtimeSnapshot.greatVaultWorld.progress==1 and HolyStorm.Snapshots.registered.delves,"no-reward current progress validates despite the false reward-period flag")
C_WeeklyRewards.HasAvailableRewards=function()return true end
local previousReward,previousReason,previousDiagnostics=Module:Collect();assert(previousReward and previousReward.weeklyIdentity==1900000000 and previousReward.greatVault.rewardAvailable and previousReward.greatVaultWorld==nil and Module:Validate(previousReward,previousReason,previousDiagnostics),"an old available Vault reward keeps activity data unknown but permits the current identity snapshot")
C_WeeklyRewards.HasAvailableRewards=function()return false end

-- Optional World API failures still commit an identity snapshot with unknown
-- values, never a fabricated empty progress list.
local activitiesFunction=C_WeeklyRewards.GetActivities;C_WeeklyRewards.GetActivities=nil
request("MANUAL_COMMAND");local withoutWorld,withoutWorldMeta=stored();assert(withoutWorld.weeklyIdentity==1900000000 and withoutWorld.greatVaultWorld==nil and withoutWorldMeta.version==9,"optional World API absence commits only known fields")
C_WeeklyRewards.GetActivities=activitiesFunction

-- A genuinely delayed required season API retries through SnapshotManager and
-- eventually succeeds within its default retry bound.
HolyStorm.CharacterScans:ResetRuntimeMetrics();local readyCalls=0;C_DelvesUI.GetCurrentDelvesSeasonNumber=function()readyCalls=readyCalls+1;if readyCalls==1 then return nil end;return season end
assert(HolyStorm.CharacterScans:Request("delves","MANUAL_COMMAND",false,{manual=true,order=40}));processAll();local afterReady,afterReadyMeta=stored();local readyMetrics=HolyStorm.CharacterScans:GetRuntimeMetrics().byBlock.delves
assert(readyCalls==2 and afterReadyMeta.version==10 and readyMetrics.requested==1 and readyMetrics.started==1 and readyMetrics.completed==1 and readyMetrics.failedAfterStart==0 and readyMetrics.retryCount==1,"required data readiness retries once, then commits a new valid snapshot")

-- Exhaustion reports the actual API/stage and preserves the last valid block.
HolyStorm.CharacterScans:ResetRuntimeMetrics();local beforeFailure,beforeFailureMeta=stored();C_DelvesUI.GetCurrentDelvesSeasonNumber=function()return nil end
request("MANUAL_COMMAND");local retained,retainedMeta=stored();local failureMetrics=HolyStorm.CharacterScans:GetRuntimeMetrics().byBlock.delves;local failureState=HolyStorm.CharacterScans:GetDiagnostics().runtimeStates.delves
assert(retained.weeklyIdentity==beforeFailure.weeklyIdentity and retained.seasonNumber==beforeFailure.seasonNumber and retainedMeta.version==beforeFailureMeta.version and retainedMeta.originCreatedAt==beforeFailureMeta.originCreatedAt,"required-data failure leaves the last committed snapshot and metadata unchanged")
assert(failureMetrics.requested==1 and failureMetrics.started==1 and failureMetrics.failedAfterStart==1 and failureMetrics.startFailure==0 and failureMetrics.cancelled==0 and failureMetrics.retryCount==3,"failed running scan metrics count three bounded retries separately from admission failure")
assert(failureState.lastError=="DELVES_API_NOT_READY"and failureState.lastFailureStage=="SEASON"and failureState.lastFailureAPI=="C_DelvesUI.GetCurrentDelvesSeasonNumber"and failureState.retryCount==3,"runtime diagnostics retain the precise terminal API failure")

-- A failed first scan leaves a true missing state instead of writing a shell.
HolyStorm.CharacterScans:ResetRuntimeMetrics();ownedBlocks["Player-Delves-Test"].delves=nil;request("MANUAL_COMMAND");local missing,missingMeta=stored();local missingState=HolyStorm.CharacterScans:GetDiagnostics().runtimeStates.delves
assert(missing==nil and missingMeta==nil and missingState.state=="ERROR"and missingState.lastError=="DELVES_API_NOT_READY","failed first scan remains missing and exposes an error")

-- Candidate validation failure uses the real producer callback, records its
-- field-level lastError/stage, and never reaches PlayerData commit.
C_DelvesUI.GetCurrentDelvesSeasonNumber=function()return season end
local invalid={snapshotVersion=3,schemaVersion=3,seasonNumber=4,weeklyIdentity=1900000000,greatVault={currentPeriod=false,rewardAvailable=false},greatVaultWorld={progress=0,completed={1},activities={}}}
local validationBaseline={snapshotVersion=3,schemaVersion=3,seasonNumber=4,weeklyIdentity=1900000000,greatVault={currentPeriod=false,rewardAvailable=false}}
seed(validationBaseline,12,1900000001);local validationOld,validationOldMeta=stored();HolyStorm.CharacterScans:ResetRuntimeMetrics()
local originalCollect=Module.Collect;Module.Collect=function()return invalid end;request("MANUAL_COMMAND");Module.Collect=originalCollect
local validationAfter,validationAfterMeta=stored();local validationState=HolyStorm.CharacterScans:GetDiagnostics().runtimeStates.delves;local validationMetrics=HolyStorm.CharacterScans:GetRuntimeMetrics().byBlock.delves
assert(validationMetrics.failedAfterStart==1 and validationState.lastError=="INVALID_DELVES_COMPLETION"and validationState.lastFailureStage=="VALIDATION"and validationState.retryCount==0,"validation failure exposes its exact field reason, stage, and retry count")
assert(validationAfter.weeklyIdentity==validationOld.weeklyIdentity and validationAfterMeta.version==validationOldMeta.version and validationAfterMeta.originCreatedAt==validationOldMeta.originCreatedAt,"validation failure preserves revision, origin timestamp, and the last valid snapshot")

-- Post-playerReady reward updates merge into one normal automatic scan.
HolyStorm.CharacterScans:ResetRuntimeMetrics();local eventRevision=validationAfterMeta.version
HolyStorm.Events:Emit("WEEKLY_REWARDS_UPDATE");HolyStorm.Events:Emit("WEEKLY_REWARDS_UPDATE")
assert(HolyStorm.CharacterScans.pending.delves and HolyStorm.CharacterScans:GetRuntimeMetrics().byBlock.delves.requested==2,"repeated post-ready reward updates are requested and coalesced before workflow start")
processAll();local eventMetrics=HolyStorm.CharacterScans:GetRuntimeMetrics().byBlock.delves;local _,eventMeta=stored()
assert(eventMetrics.automatic==2 and eventMetrics.started==1 and eventMetrics.completed==1 and eventMetrics.failedAfterStart==0 and eventMeta.version==eventRevision+1,"coalesced real Blizzard events run one successful scan and one revision")

Module:OnDisable()
print("Delves end-to-end workflow, last-valid, retry, diagnostic and metrics tests passed")
