-- Deterministic Statistics traversal and cache-work budget regression.
local root=(arg[0]:gsub("tools[/\\]test_raid_workflow_continuation.lua$",""))
local calls={apiCalls=0,categories=0,categoryInfo=0,categoryCounts=0,entries=0,achievementInfo=0,valueReads=0,instances=0,instanceInfo=0,selectInstance=0,encounters=0,savedInstances=0,savedEncounters=0}
local logs,Module={},nil
local locale=setmetatable({UNKNOWN="Unknown"},{__index=function(_,key)return key end})
local function copy(value,seen)if type(value)~="table"then return value end;seen=seen or{};if seen[value]then return seen[value]end;local out={};seen[value]=out;for key,item in pairs(value)do out[copy(key,seen)]=copy(item,seen)end;return out end
local storedSnapshot,commitCount,fakeTime=nil,0,0
local apiExtraTime=0
local HolyStorm={Utils={DeepCopy=copy,Now=function()return 1000 end},Events={},Logger={},PlayerData={},Tasks={schedulerYieldDelay=1/60},Data={CharacterStore={GetBlock=function()return copy(storedSnapshot)end}},Snapshots={}}
function HolyStorm.Logger:Write(level,source,category,message,context)logs[#logs+1]={level=level,source=source,category=category,message=message,context=context}end
function HolyStorm.PlayerData:RegisterBlock()return true end
function HolyStorm.PlayerData:WriteOwnedBlock(_,block,snapshot)assert(block=="raid");commitCount=commitCount+1;storedSnapshot=copy(snapshot);return true end
function HolyStorm:RegisterModule(_,factory)Module={};factory(Module)end
function HolyStorm:ApplyModuleMetadata(target,metadata)target.metadata=metadata end
function HolyStorm:RegisterCapability()end
function HolyStorm.Events:Register()end
function HolyStorm.Snapshots:Queue(id,scanner,validator,commit,options)self.id,self.scanner,self.validator,self.commit,self.options=id,scanner,validator,commit,options;return true,"wf-performance"end
local blockReads=0
function HolyStorm.Data.CharacterStore:GetBlock()blockReads=blockReads+1;return copy(storedSnapshot)end
function HolyStorm.Data.CharacterStore:GetBlockMetadata()return nil end
function LibStub(name)if name=="AceAddon-3.0"then return{GetAddon=function()return HolyStorm end}elseif name=="AceLocale-3.0"then return{GetLocale=function()return locale end}end;error("unexpected library "..tostring(name))end
function UnitGUID()return"Player-Performance"end

local selectedTier=1
local raidName="Storm Test Raid"
local bosses={}
for index=1,8 do bosses[index]={id=5000+index,name="Storm Boss "..index}end
local savedInstances={
 {difficultyId=14,difficultyName="Normal",kills={true,true,true,true,true,true,true,false}},
 {difficultyId=15,difficultyName="Heroic",kills={true,true,true,true,true,true,true,true}},
}
function GetTime()return fakeTime end
function GetTimePreciseSec()return fakeTime+calls.apiCalls*.0003+apiExtraTime end
function EJ_GetNumTiers()calls.apiCalls=calls.apiCalls+1;return 1 end
function EJ_GetCurrentTier()calls.apiCalls=calls.apiCalls+1;return 1 end
function EJ_GetTierInfo()calls.apiCalls=calls.apiCalls+1;return"Storm Fixture"end
function EJ_SelectTier(tier)calls.apiCalls=calls.apiCalls+1;selectedTier=tier end
function EJ_GetInstanceByIndex(index,isRaid)calls.apiCalls=calls.apiCalls+1;calls.instances=calls.instances+1;if selectedTier==1 and index==1 and isRaid then return 900,raidName end end
function EJ_SelectInstance()calls.apiCalls=calls.apiCalls+1;calls.selectInstance=calls.selectInstance+1 end
function EJ_GetInstanceInfo()calls.apiCalls=calls.apiCalls+1;calls.instanceInfo=calls.instanceInfo+1;return nil,nil,nil,nil,nil,nil,nil,nil,true end
function EJ_GetEncounterInfoByIndex(index)calls.apiCalls=calls.apiCalls+1;calls.encounters=calls.encounters+1;local boss=bosses[index];if boss then return boss.name,nil,boss.id end end
function GetNumSavedInstances()calls.apiCalls=calls.apiCalls+1;return#savedInstances end
function GetSavedInstanceInfo(index)calls.apiCalls=calls.apiCalls+1;calls.savedInstances=calls.savedInstances+1;local instance=savedInstances[index];return raidName,8000+index,3600,instance.difficultyId,true,false,nil,true,20,instance.difficultyName,#instance.kills,0 end
function GetSavedInstanceEncounterInfo(index,bossIndex)calls.apiCalls=calls.apiCalls+1;calls.savedEncounters=calls.savedEncounters+1;local boss=bosses[bossIndex];return boss.name,boss.id,savedInstances[index].kills[bossIndex]end
function GetDifficultyInfo(id)calls.apiCalls=calls.apiCalls+1;return({[17]="Raid Finder",[14]="Normal",[15]="Heroic",[16]="Mythic"})[id]end

local statisticRows,statisticsById={},{}
statisticRows[1]={id=700000,name="Storm Boss 1 (Normal: Storm Test Raid)",value="9"};statisticsById[700000]=statisticRows[1]
for index=2,1025 do statisticRows[index]={id=700000+index,name="Other Boss "..index.." (Mythic: Other Raid "..index..")",value="1"};statisticsById[statisticRows[index].id]=statisticRows[index]end
local categoryIds={};for index=1,96 do categoryIds[index]=index==1 and 9001 or 9000+index end
function GetStatisticsCategoryList()calls.apiCalls=calls.apiCalls+1;calls.categories=calls.categories+1;return categoryIds end
function GetCategoryInfo(id)calls.apiCalls=calls.apiCalls+1;calls.categoryInfo=calls.categoryInfo+1;if id==9001 then return raidName,-1 end;return"Generic Statistics "..id,-1 end
function GetCategoryNumAchievements(id)calls.apiCalls=calls.apiCalls+1;calls.categoryCounts=calls.categoryCounts+1;if id==9001 then return#statisticRows end;return 0 end
function GetStatistic(id,index)
 calls.apiCalls=calls.apiCalls+1;if index~=nil then calls.entries=calls.entries+1;if id~=9001 then return nil,false,nil end;local row=statisticRows[index];return row and row.value,false,row and row.id end
 calls.valueReads=calls.valueReads+1;local row=statisticsById[id];return row and row.value
end
function GetAchievementInfo(id)calls.apiCalls=calls.apiCalls+1;calls.achievementInfo=calls.achievementInfo+1;local row=statisticsById[id];if row then return id,row.name end end

assert(loadfile(root.."LIVE/Holy_Storm_Raids/Raids.lua"))()

-- Exercise the real orchestration contracts, rather than a stubbed GOTO loop.
local eventCounts={}
HolyStorm.db={profile={taskManager={}}}
HolyStorm.State={Is=function(_,key)return key=="playerReady"or key=="playerLoggedIn"end,Get=function(_,key)return key=="playerReady"or key=="playerLoggedIn"end}
HolyStorm.Utils.SafeCall=function(_,fn,...)local args={...};return xpcall(function()return fn(table.unpack(args))end,function(e)return e end)end
HolyStorm.Events.listeners={}
function HolyStorm.Events:UnregisterOwner(owner)for _,bucket in pairs(self.listeners)do bucket[owner]=nil end end
function HolyStorm.Events:Register(event,owner,callback)self.listeners[event]=self.listeners[event]or{};self.listeners[event][owner]=callback end
function HolyStorm.Events:Emit(event,...)eventCounts[event]=(eventCounts[event]or 0)+1;for _,fn in pairs(self.listeners[event]or{})do fn(event,...)end end
local timers={}
C_Timer={NewTimer=function(delay,callback)local t={due=fakeTime+delay,callback=callback};function t:Cancel()self.cancelled=true end;timers[#timers+1]=t;return t end}
HolyStorm.PlayerData.FingerprintSnapshot=function()error("Raid does not need a duplicate fingerprint")end
assert(loadfile(root.."LIVE/Holy_Storm/Core/Tasks/TaskManager.lua"))()
assert(loadfile(root.."LIVE/Holy_Storm/Core/Workflows/WorkflowManager.lua"))()
assert(loadfile(root.."LIVE/Holy_Storm/Persistence/SnapshotManager.lua"))()
HolyStorm.Tasks:Initialize();HolyStorm.Workflows:Initialize();Module:OnEnable()
local function pumpFrame()
 local timer;for _,candidate in ipairs(timers)do if not candidate.cancelled and(not timer or candidate.due<timer.due)then timer=candidate end end
 assert(timer,"workflow has no scheduler wake")
 fakeTime=math.max(fakeTime+1/60,timer.due);timer.cancelled=true
 local before=calls.apiCalls;local logsBefore=#logs;local eventsBefore=eventCounts.HS_TASK_STARTED or 0
 local run=Module.activeRaidRun;local workState=run and run.workState
 local beforeSlices=run and run.slices
 local beforeRestarts=run and run.restarts
 timer.callback()
 assert(calls.apiCalls-before<=1,"one API call per scheduler frame")
 if run and run.slices>beforeSlices and not run.scanComplete then
  if run.restarts==beforeRestarts then assert(run.workState==workState,"a continuation preserves the exact context")end
  if beforeSlices>0 and run.restarts==beforeRestarts and HolyStorm.Tasks.tasks[run.scanTaskId].status=="WAITING"then
   assert(#logs==logsBefore and(eventCounts.HS_TASK_STARTED or 0)==eventsBefore,"resumed collection produces no logs or lifecycle events")
  end
  -- Reentrant/late scheduler invocations in this same rendered frame do not
  -- drain the continuation. The next deadline is relative to now.
  local slices=run.slices
  for _=1,4 do HolyStorm.Tasks:Process()end
  assert(run.slices==slices,"same-frame scheduler backlog cannot burst")
 end
end
local function drain(limit)
 for _=1,limit or 10000 do
  if not HolyStorm.Workflows.activeByType.SNAPSHOT_RAIDS and #HolyStorm.Tasks.queue==0 then return end
  pumpFrame()
 end
 error("workflow must end")
end
local function summaries(id)
 local count,summary=0,nil
 for _,entry in ipairs(logs)do if entry.message=="RAID_SCAN_PERFORMANCE"and entry.context.workflowId==id then count=count+1;summary=entry.context end end
 return count,summary
end
local queued,workflowId=Module:Queue(false,0,false,true,"MANUAL_COMMAND");assert(queued)
local firstRun=Module.activeRaidRun;drain()
local scanTasks=HolyStorm.Tasks.performance["Snapshot.raids.Scan"]
print(string.format("Raid fixture: scan lifecycles=%d, API calls=%d, task events=%d/%d/%d, workflow completed IDs=%d, logs=%d, slices=%d",scanTasks.requested,calls.apiCalls,eventCounts.HS_TASK_QUEUED or 0,eventCounts.HS_TASK_STARTED or 0,eventCounts.HS_TASK_COMPLETED or 0,#HolyStorm.Workflows.workflows[workflowId].completedTasks,#logs,firstRun.slices))
assert(scanTasks.requested==1 and scanTasks.started==1 and scanTasks.completed==1 and#HolyStorm.Workflows.workflows[workflowId].completedTasks==3)
assert(commitCount==1 and storedSnapshot.lifetime.bosses[5001].difficulties.NORMAL.kills==9 and storedSnapshot.bestProgress.difficultyId==15)
local summaryCount,summary=summaries(workflowId)
assert(summaryCount==1 and summary.taskLifecycleCount==3 and summary.catalogBuilds==1 and summary.slices==firstRun.slices and summary.ejCalls+summary.statisticCalls+summary.savedInstanceCalls==calls.apiCalls)
assert(blockReads==1 and summary.totalWallMs>summary.totalLuaMs and summary.maxSliceMs<1 and summary.restarts==0)
for _,key in ipairs({"totalWallMs","totalLuaMs","slices","maxSliceMs","taskLifecycleCount","catalogBuilds","ejCalls","statisticCalls","savedInstanceCalls","restarts","followUpQueued","expectedInstanceInfoEvents","unexpectedRaidEvents"})do assert(type(summary[key])=="number",key)end
local publicSummary=Module:GetScanPerformance();publicSummary.slices=-1;assert(Module:GetScanPerformance().slices>0,"diagnostic readers cannot mutate counters")

-- Cached refresh with an outstanding RaidInfo response: old committed data
-- stays readable and no saved-instance API runs until the signal arrives.
function IsInInstance()return false,"none"end
local raidInfoRequests=0
function RequestRaidInfo()raidInfoRequests=raidInfoRequests+1 end
local previous=storedSnapshot;local oldSaved=calls.savedInstances+calls.savedEncounters
local _,waitingWorkflow=Module:Queue(false,0,true,true,"MANUAL_COMMAND")
for _=1,1000 do
 pumpFrame()
 local run=Module.activeRaidRun;local task=run and HolyStorm.Tasks.tasks[run.scanTaskId]
 if task and task.status=="WAITING_ASYNC"then break end
end
local waitingRun=Module.activeRaidRun;local waitingId=waitingRun.scanTaskId
assert(HolyStorm.Tasks.tasks[waitingId].status=="WAITING_ASYNC"and HolyStorm.Tasks.suspendedCount==1)
assert(storedSnapshot==previous and commitCount==1 and calls.savedInstances+calls.savedEncounters==oldSaved)
HolyStorm.Tasks:RegisterTaskType("Fixture.Other",{execute=function()return true end})
local unrelated=HolyStorm.Tasks:Queue("Fixture.Other");pumpFrame();assert(HolyStorm.Tasks.tasks[unrelated].status=="COMPLETED","waiting Raid scan does not block other tasks")
HolyStorm.Events:Emit("UPDATE_INSTANCE_INFO")
assert(HolyStorm.Workflows.workflows[waitingWorkflow].status=="RUNNING"and waitingRun.instanceInfoReady and HolyStorm.Tasks.tasks[waitingId].uniqueId==waitingId and HolyStorm.Tasks.suspendedCount==0)
drain()
local n,warm=summaries(waitingWorkflow)
assert(n==1 and warm.expectedInstanceInfoEvents==1 and warm.restarts==0 and warm.taskLifecycleCount==3 and warm.catalogBuilds==0)
assert(warm.ejCalls==1 and warm.statisticCalls==1 and warm.savedInstanceCalls==19 and warm.slices<60 and raidInfoRequests==1)
assert(commitCount==2 and storedSnapshot.lifetime.bosses[5001].difficulties.NORMAL.kills==9)
print(string.format("Cached Raid fixture: slices=%d, EJ=%d, Statistics=%d, saved instances=%d",warm.slices,warm.ejCalls,warm.statisticCalls,warm.savedInstanceCalls))

-- One slow operation is not followed by another API, even with numerical
-- budget remaining. Counters and maxSliceMs record the actual expensive call.
local normalStatistic=GetStatistic
GetStatistic=function(id,index)if index==nil then apiExtraTime=apiExtraTime+.020 end;return normalStatistic(id,index)end
local _,slowWorkflow=Module:Queue(false,0,false,true,"MANUAL_COMMAND");drain()
local _,slow=summaries(slowWorkflow);assert(slow.maxSliceMs>=20 and slow.statisticCalls==1)
GetStatistic=normalStatistic

-- Missing asynchronous response times out without Validate/Commit or any
-- replacement snapshot. A late response is consumed outside the Raid filter.
previous=storedSnapshot;local previousCommits=commitCount
local _,timeoutWorkflow=Module:Queue(false,0,true,true,"MANUAL_COMMAND");drain()
assert(HolyStorm.Workflows.workflows[timeoutWorkflow].status=="FAILED"and storedSnapshot==previous and commitCount==previousCommits)
assert(summaries(timeoutWorkflow)==1 and HolyStorm.Tasks.suspendedCount==0)
HolyStorm.Events:Emit("UPDATE_INSTANCE_INFO");assert(not Module.activeRaidRun)

-- Actual CharacterScanManager producer routing: no login/MISSING/STALE scans,
-- and a storm of genuine Raid events makes exactly one pending follow-up.
assert(loadfile(root.."LIVE/Holy_Storm/Core/Tasks/CharacterScanManager.lua"))()
HolyStorm.CharacterScans:Initialize();Module:OnInitialize()
HolyStorm.Events:Emit("PLAYER_LOGIN");assert(not Module.activeRaidRun and#HolyStorm.CharacterScans.queue==0)
HolyStorm.CharacterScans:SetRuntimeState("raid","MISSING");HolyStorm.CharacterScans:SetRuntimeState("raid","STALE")
assert(not Module.activeRaidRun and#HolyStorm.CharacterScans.queue==0)
HolyStorm.CharacterScans:Request("raid","MANUAL_COMMAND",false);pumpFrame()
local ownedRun=Module.activeRaidRun;assert(ownedRun and HolyStorm.CharacterScans.active.workflowId==ownedRun.workflowId)
function IsInInstance()return true,"raid"end
HolyStorm.Events:Emit("UPDATE_INSTANCE_INFO")
for _=1,12 do HolyStorm.Events:Emit("ENCOUNTER_END",9001,"Boss",16,20,1)end
assert(#HolyStorm.CharacterScans.queue==1 and ownedRun.followUpQueued==1 and ownedRun.unexpectedRaidEvents==12 and ownedRun.expectedInstanceInfoEvents==1)
local startedBefore=HolyStorm.CharacterScans.metrics.byBlock.raid.started
local responded={}
for _=1,1000 do
 local run=Module.activeRaidRun
 if run and run.raidInfoRequested and not responded[run.workflowId]then responded[run.workflowId]=true;HolyStorm.Events:Emit("UPDATE_INSTANCE_INFO")end
 if not run and not HolyStorm.CharacterScans.active and#HolyStorm.CharacterScans.queue==0 and#HolyStorm.Tasks.queue==0 then break end
 pumpFrame()
end
assert(HolyStorm.CharacterScans.metrics.byBlock.raid.started==startedBefore+1 and#HolyStorm.CharacterScans.queue==0 and not HolyStorm.CharacterScans.active,"exactly one follow-up scan completes")
assert(summaries(ownedRun.workflowId)==1)

-- A failed mapped value read retries through validation, but each retry still
-- has one collection task; no partial write/sync replaces the old snapshot.
previous=storedSnapshot;previousCommits=commitCount
GetStatistic=function(id,index)if index==nil then error("fixture unavailable value")end;return normalStatistic(id,index)end
local _,failedWorkflow=Module:Queue(false,0,false,true,"MANUAL_COMMAND");drain()
assert(HolyStorm.Workflows.workflows[failedWorkflow].status=="FAILED"and storedSnapshot==previous and commitCount==previousCommits)
local failedCount,failed=summaries(failedWorkflow);assert(failedCount==1 and failed.restarts==5 and failed.catalogBuilds==0)
GetStatistic=normalStatistic
previous=storedSnapshot;previousCommits=commitCount
local normalSavedInfo=GetSavedInstanceInfo
GetSavedInstanceInfo=function()apiExtraTime=apiExtraTime+.020;error("fixture saved instance exception")end
local _,exceptionWorkflow=Module:Queue(false,0,false,true,"MANUAL_COMMAND");drain()
local exceptionCount,exceptionSummary=summaries(exceptionWorkflow)
assert(exceptionCount==1 and exceptionSummary.status=="FAILED"and exceptionSummary.maxSliceMs>=20 and exceptionSummary.savedInstanceCalls==2 and storedSnapshot==previous and commitCount==previousCommits,"uncaught expensive API failures preserve the old snapshot and remain measured")
GetSavedInstanceInfo=normalSavedInfo
previous=storedSnapshot;previousCommits=commitCount
local _,cancelledWorkflow=Module:Queue(false,0,false,true,"MANUAL_COMMAND");pumpFrame();Module:OnDisable()
assert(HolyStorm.Workflows.workflows[cancelledWorkflow].status=="CANCELLED"and storedSnapshot==previous and commitCount==previousCommits and summaries(cancelledWorkflow)==1,"disable cancels without a partial commit and publishes one terminal summary")
print("Real Raid workflow continuation, counters, async response/timeout, coalesced follow-up and atomic failure tests passed")
