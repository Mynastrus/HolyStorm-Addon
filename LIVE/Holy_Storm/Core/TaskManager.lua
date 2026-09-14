local addonVersion = "3.0.0"
local HolyStorm = LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local L = LibStub("AceLocale-3.0"):GetLocale("Holy_Storm")

-- DE: Ein Scheduler, eine logische Queue. Registrierte Typen besitzen stabile IDs,
-- Laufzeitinstanzen eigene IDs. Blockierte Tasks werden uebersprungen, nie gepollt.
-- EN: One scheduler and one logical queue. Registered types have stable IDs while
-- runtime instances have unique IDs. Blocked tasks are skipped, never busy-polled.
local Tasks = {
    version=addonVersion, registry={}, queue={}, tasks={}, mergeIndex={}, history={},
    recurring={}, performance={}, eventHistory={}, lastRun={}, sequence=0, runtimeSequence=0,
    paused=false, runningTaskId=nil, timer=nil, timerDue=nil, maxHistory=250,
    maxEventHistory=300, maxTriggerHistory=20,
}
Tasks.ExecutionMode={UNIQUE="UNIQUE",MERGE="UNIQUE",MULTI="MULTI",MERGE_BY_KEY="MERGE_BY_KEY"}
Tasks.Status={REGISTERED="REGISTERED",QUEUED="QUEUED",WAITING="WAITING",BLOCKED="BLOCKED",READY="READY",RUNNING="RUNNING",WAITING_ASYNC="WAITING_ASYNC",COMPLETED="COMPLETED",FAILED="FAILED",CANCELLED="CANCELLED"}
Tasks.ASYNC={}
local function clock()return GetTime and GetTime()or 0 end
local function wall()return HolyStorm.Utils.Now()end
local function copy(v)return HolyStorm.Utils.DeepCopy(v)end
local function mergeId(id,mode,key)if mode=="MULTI"then return nil elseif mode=="MERGE_BY_KEY"then return id.."\031"..tostring(key)end return id end
local function sortQueue(a,b)local n=clock();local ap=a.priority-math.min(10,math.floor(math.max(0,n-a.queuedClock)/30));local bp=b.priority-math.min(10,math.floor(math.max(0,n-b.queuedClock)/30));if ap==bp then return a.sequence<b.sequence end return ap<bp end
local function addLimited(t,v,n)t[#t+1]=v;while #t>n do table.remove(t,1)end end
local function clean(task)local r=copy(task);r.callback,r.timer=nil,nil;return r end
local function referenced(self,id)for _,task in ipairs(self.queue)do for _,dep in ipairs(task.dependencies or{})do local depId=type(dep)=="table"and dep.taskId or dep;if depId==id then return true end end end;return false end
local function archived(self,id)for _,candidate in ipairs(self.history)do if candidate==id then return true end end;return false end
local function archive(self,id)
 if#self.history>=math.max(1,self.maxHistory)then table.remove(self.history,1)end;self.history[#self.history+1]=id
 -- DE/EN: completed dependency results outlive history eviction only while referenced.
 for taskId,task in pairs(self.tasks)do if taskId~=id and(task.status=="COMPLETED"or task.status=="FAILED"or task.status=="CANCELLED")and not archived(self,taskId)and not referenced(self,taskId)then self.tasks[taskId]=nil end end
end

function Tasks:Initialize()
 local s=HolyStorm.db and HolyStorm.db.profile and HolyStorm.db.profile.taskManager or{}
 self.maxHistory=tonumber(s.historyLimit)or self.maxHistory;self.maxEventHistory=tonumber(s.eventHistoryLimit)or self.maxEventHistory;self.maxTriggerHistory=tonumber(s.triggerHistoryLimit)or self.maxTriggerHistory
 HolyStorm.Events:Register("PLAYER_REGEN_ENABLED","task-manager",function()Tasks:Wake("PLAYER_REGEN_ENABLED")end)
 HolyStorm.Events:Register("HS_STATE_CHANGED","task-manager",function()Tasks:Wake("HS_STATE_CHANGED")end)
end

-- DE/EN Public API: definitions are contracts identified by stable registry IDs.
function Tasks:RegisterTaskType(id,d)
 if type(id)~="string"or id==""or type(d)~="table"or type(d.execute)~="function"then return false,"INVALID_TASK_DEFINITION"end
 local mode=d.executionMode or"UNIQUE";if not self.ExecutionMode[mode]then return false,"INVALID_EXECUTION_MODE"end
 local old=self.registry[id];if old and old.execute~=d.execute and not d.replace then return false,"TASK_TYPE_ALREADY_REGISTERED"end
 self.registry[id]={registryId=id,name=d.name or id,localizedNameKey=d.localizedNameKey or id,module=d.module or"Core",priority=tonumber(d.priority)or 50,executionMode=mode,conditions=copy(d.conditions or{}),dependencies=copy(d.dependencies or{}),maxRetries=math.max(0,tonumber(d.maxRetries)or 0),execute=d.execute,failurePolicy=d.failurePolicy or"FAIL",metadata=copy(d.metadata or{})};return true
end
function Tasks:GetTaskType(id)return self.registry[id]end
local function trigger(self,t,s,m)s=tostring(s or"UNKNOWN");t.triggerCount=t.triggerCount+1;t.triggerSources[s]=(t.triggerSources[s]or 0)+1;t.lastTriggeredAt=wall();if self.maxTriggerHistory>0 then addLimited(t.triggerHistory,{source=s,at=t.lastTriggeredAt,metadata=copy(m)},self.maxTriggerHistory)end end

-- DE: Queue implementiert UNIQUE, MULTI und MERGE_BY_KEY generisch. Ein Merge
-- veraendert nie die Fachprioritaet; er aktualisiert Trigger und Debounce.
-- EN: Queue implements UNIQUE, MULTI and MERGE_BY_KEY generically. A merge never
-- changes business priority; it updates trigger accounting and debounce only.
function Tasks:Queue(id,o)
 local d=self.registry[id];if not d then return nil,"UNKNOWN_TASK_TYPE"end;o=o or{};local mode=o.executionMode or d.executionMode;local key=o.mergeKey;if mode=="MERGE_BY_KEY"and key==nil then return nil,"MERGE_KEY_REQUIRED"end
 local index=mergeId(id,mode,key);local existing=index and self.tasks[self.mergeIndex[index]]
 if existing and(existing.status=="QUEUED"or existing.status=="WAITING"or existing.status=="BLOCKED"or existing.status=="READY")then
  trigger(self,existing,o.triggerSource,o.triggerMetadata);if o.debounce~=nil or o.delay~=nil then existing.notBefore=clock()+math.max(0,tonumber(o.debounce or o.delay)or 0)end
  local p=self.performance[id]or{runs=0,totalDuration=0,maxDuration=0,errors=0,merges=0,triggers=0};p.merges=p.merges+1;self.performance[id]=p
  HolyStorm.Logger:Write("DEBUG",existing.module,"task","Task merged: "..id,{taskId=existing.uniqueId,workflowId=existing.workflowId,triggerCount=existing.triggerCount,triggerSource=o.triggerSource},existing.workflowId or existing.uniqueId);if o.triggerSource then self:RecordEvent(o.triggerSource,existing.module,{taskId=existing.uniqueId,workflowId=existing.workflowId,triggeredTask=id})end;HolyStorm.Events:Emit("HS_TASK_MERGED",existing);self:Schedule();return existing.uniqueId,"MERGED"
 end
 self.runtimeSequence=self.runtimeSequence+1;self.sequence=self.sequence+1;local n,ts=clock(),wall();local uid=string.format("task_%08X_%04X",ts%0xFFFFFFFF,self.runtimeSequence%0xFFFF)
 local notBefore=n+math.max(0,tonumber(o.delay or o.debounce)or 0);local cooldown=math.max(0,tonumber(o.cooldown)or 0);if self.lastRun[id]then notBefore=math.max(notBefore,self.lastRun[id]+cooldown)end
 local task={uniqueId=uid,taskType=id,registryId=id,name=d.name,localizedNameKey=d.localizedNameKey,module=o.module or d.module,workflowId=o.workflowId,workflowStep=o.workflowStep,priority=tonumber(o.priority)or d.priority,status="QUEUED",createdAt=ts,queuedAt=ts,createdClock=n,queuedClock=n,startedAt=nil,finishedAt=nil,triggerCount=0,triggerSources={},triggerHistory={},conditions=copy(o.conditions or d.conditions),dependencies=copy(o.dependencies or d.dependencies),executionMode=mode,mergeKey=key,retryCount=tonumber(o.retryCount)or 0,maxRetries=tonumber(o.maxRetries)or d.maxRetries,metadata=copy(o.metadata or d.metadata),lastError=nil,blockReason=nil,notBefore=notBefore,cooldown=cooldown,sequence=self.sequence,callback=o.execute or d.execute,result=nil,indexKey=index}
 trigger(self,task,o.triggerSource,o.triggerMetadata);self.tasks[uid]=task;self.queue[#self.queue+1]=task;if index then self.mergeIndex[index]=uid end;table.sort(self.queue,sortQueue)
 HolyStorm.Logger:Write("DEBUG",task.module,"task","Task requested: "..id,{taskId=uid,workflowId=task.workflowId,triggerSource=o.triggerSource},task.workflowId or uid);if o.triggerSource then self:RecordEvent(o.triggerSource,task.module,{taskId=uid,workflowId=task.workflowId,triggeredTask=id})end;HolyStorm.Events:Emit("HS_TASK_QUEUED",task);self:Schedule();return uid,"QUEUED"
end

-- Backward-compatible adapter: legacy callers still use the sole global queue.
function Tasks:Enqueue(id,callback,o)o=o or{};if not self.registry[id]then local module=id:match("^([^.]+)")or"Legacy";self:RegisterTaskType(id,{name=o.name or string.format(L["TASK_GENERIC"],id),localizedNameKey=o.localizedNameKey or"TASK_GENERIC",module=o.module or module,priority=o.priority or 50,executionMode=o.executionMode or"UNIQUE",execute=callback})end;o.execute=callback;o.triggerSource=o.triggerSource or(HolyStorm.Events and HolyStorm.Events.currentEvent)or"LEGACY_ENQUEUE";o.delay=o.delay or o.debounce;if o.combat~="allow"then o.conditions=copy(o.conditions or{});o.conditions[#o.conditions+1]="NOT_IN_COMBAT"end;local rid=self:Queue(id,o);return rid~=nil,rid end

-- DE: Nicht erfuellte Conditions sind Wartezustaende, keine Fehler. Der Scheduler
-- prueft danach weitere Tasks. EN: Failed conditions are waiting states, not
-- errors. The scheduler proceeds to inspect other tasks.
function Tasks:CheckConditions(task)
 if task.cooldown and task.cooldown>0 and self.lastRun[task.registryId]then task.notBefore=math.max(task.notBefore,self.lastRun[task.registryId]+task.cooldown)end
 if task.notBefore>clock()then return false,"DEBOUNCE"end
 for _,c in ipairs(task.conditions or{})do local kind,expected,fn;if type(c)=="string"then kind,expected=c,true elseif type(c)=="function"then fn=c elseif type(c)=="table"then kind,expected,fn=c.type or c.state,c.expected~=false,c.check end;local ok,value,reason=true,true,nil
  if fn then ok,value,reason=HolyStorm.Utils.SafeCall("task.condition:"..task.registryId,fn,task)
  elseif kind=="NOT_IN_COMBAT"then value=not(InCombatLockdown and InCombatLockdown())
  elseif kind=="PLAYER_LOGGED_IN"then value=HolyStorm.State:Is("playerLoggedIn")
  elseif kind=="PLAYER_READY"then value=HolyStorm.State:Is("playerReady")
  elseif kind=="NOT_LOADING"then value=not HolyStorm.State:Is("loading")
  elseif kind=="NOT_ZONING"then value=not HolyStorm.State:Is("zoning")
  elseif kind=="GUILD_AVAILABLE"then value=HolyStorm.State:Is("guildAvailable")
  elseif kind and HolyStorm.State:Get(kind)~=nil then value=HolyStorm.State:Is(kind)==expected end
  if kind and not fn and kind~="NOT_IN_COMBAT"and kind~="PLAYER_LOGGED_IN"and kind~="PLAYER_READY"and kind~="NOT_LOADING"and kind~="NOT_ZONING"and kind~="GUILD_AVAILABLE"and HolyStorm.State:Get(kind)==nil then value,reason=false,"UNKNOWN_CONDITION:"..kind end
  if not ok or not value then return false,reason or kind or"CUSTOM_CONDITION"end
 end return true
end
function Tasks:CheckDependencies(task)
 for _,dep in ipairs(task.dependencies or{})do
  if type(dep)=="table"and dep.step then local workflow=HolyStorm.Workflows and HolyStorm.Workflows.workflows[task.workflowId];local value=workflow and workflow.context and workflow.context.results[dep.step];local complete=value~=nil;if complete and dep.resultKey then complete=type(value)=="table"and value[dep.resultKey]==dep.expected end;if not complete then return false,"DEPENDENCY_WAITING:STEP:"..tostring(dep.step)end
  else local id=type(dep)=="table"and(dep.taskId or dep.registryId)or dep;local wanted;if type(dep)=="table"then wanted=dep.result end;local found,complete=false,false
  if self.tasks[id]then found=true;complete=self.tasks[id].status=="COMPLETED"and(wanted==nil or self.tasks[id].result==wanted)
  else for _,candidate in pairs(self.tasks)do if candidate.registryId==id and candidate.workflowId==task.workflowId then found=true;if candidate.status=="COMPLETED"and(wanted==nil or candidate.result==wanted)then complete=true end end end end
  if not complete then return false,(found and"DEPENDENCY_WAITING:"or"DEPENDENCY_MISSING:")..tostring(id)end
  end
 end return true
end
function Tasks:SelectRunnable()
 table.sort(self.queue,sortQueue);local earliest
 for _,task in ipairs(self.queue)do local ok,reason=self:CheckConditions(task);if ok then ok,reason=self:CheckDependencies(task)end;if ok then task.status,task.blockReason="READY",nil;return task end
  local newStatus=reason=="DEBOUNCE"and"WAITING"or"BLOCKED";local changed=task.status~=newStatus or task.blockReason~=reason;task.status,task.blockReason=newStatus,reason;if reason=="DEBOUNCE"then earliest=earliest and math.min(earliest,task.notBefore)or task.notBefore end;if changed then HolyStorm.Events:Emit(newStatus=="BLOCKED"and"HS_TASK_BLOCKED"or"HS_TASK_WAITING",task,reason)end
 end return nil,earliest
end
function Tasks:RemoveQueued(task)for i,x in ipairs(self.queue)do if x==task then table.remove(self.queue,i);return end end end
function Tasks:Schedule(at)if self.paused or self.runningTaskId or#self.queue==0 then return end;local due=at or clock();if self.timer and self.timerDue and self.timerDue<=due then return end;if self.timer then self.timer:Cancel()end;self.timerDue=due;self.timer=C_Timer.NewTimer(math.max(0,due-clock()),function()Tasks.timer,Tasks.timerDue=nil,nil;Tasks:Process()end)end
function Tasks:Wake(source)HolyStorm.Logger:Write("DEBUG","TaskManager","scheduler","Scheduler wake",{triggerSource=source});self:Schedule(clock())end
-- DE: Es laeuft konservativ genau ein Task. ASYNC gibt den UI-Thread sofort frei;
-- der Besitzer beendet spaeter ueber Complete(runtimeId,...).
-- EN: Conservatively, exactly one task runs. ASYNC releases the UI thread at once;
-- the owner later finishes it through Complete(runtimeId,...).
function Tasks:Process()
 if self.paused or self.runningTaskId then return end;local task,earliest=self:SelectRunnable();if not task then if earliest then self:Schedule(earliest)end return end;self:RemoveQueued(task);self.runningTaskId=task.uniqueId;task.status,task.startedAt,task.startedClock="RUNNING",wall(),clock();HolyStorm.Events:Emit("HS_TASK_STARTED",task);HolyStorm.Logger:Write("DEBUG",task.module,"task","Task started: "..task.registryId,{taskId=task.uniqueId,workflowId=task.workflowId},task.workflowId or task.uniqueId)
 local ok,result,extra=HolyStorm.Utils.SafeCall("task:"..task.registryId,task.callback,task);if ok and result==self.ASYNC then task.status="WAITING_ASYNC";HolyStorm.Events:Emit("HS_TASK_WAITING",task,"ASYNC");return end;self:Complete(task.uniqueId,ok,result,extra)
end
function Tasks:Complete(uid,success,result,extra)
 local task=self.tasks[uid];if not task or(task.status~="RUNNING"and task.status~="WAITING_ASYNC")then return false end;task.finishedAt,task.finishedClock=wall(),clock();task.duration=math.max(0,task.finishedClock-(task.startedClock or task.finishedClock));task.result,task.extraResult=result,extra;task.status=success and"COMPLETED"or"FAILED";task.lastError=success and nil or tostring(result);self.lastRun[task.registryId]=task.finishedClock;if task.indexKey and self.mergeIndex[task.indexKey]==uid then self.mergeIndex[task.indexKey]=nil end;self.runningTaskId=nil
 local p=self.performance[task.registryId]or{runs=0,totalDuration=0,maxDuration=0,errors=0,merges=0,triggers=0};p.runs=p.runs+1;p.totalDuration=p.totalDuration+task.duration;p.maxDuration=math.max(p.maxDuration,task.duration);p.triggers=p.triggers+task.triggerCount;if not success then p.errors=p.errors+1 end;self.performance[task.registryId]=p;archive(self,uid)
 HolyStorm.Logger:Write(success and"DEBUG"or"ERROR",task.module,"task",success and("Task completed: "..task.registryId)or("Task failed: "..task.registryId),{taskId=uid,workflowId=task.workflowId,duration=task.duration,error=task.lastError},task.workflowId or uid);HolyStorm.Events:Emit(success and"HS_TASK_COMPLETED"or"HS_TASK_FAILED",task,result,extra);self:Schedule(clock());return true
end
function Tasks:Cancel(id,reason)local task=self.tasks[id]or(self.mergeIndex[id]and self.tasks[self.mergeIndex[id]]);if not task or task.status=="COMPLETED"or task.status=="FAILED"or task.status=="CANCELLED"then return false end;if task.uniqueId==self.runningTaskId then self.runningTaskId=nil end;self:RemoveQueued(task);task.status="CANCELLED";task.finishedAt=wall();task.lastError=reason or"CANCELLED";if task.indexKey and self.mergeIndex[task.indexKey]==task.uniqueId then self.mergeIndex[task.indexKey]=nil end;archive(self,task.uniqueId);HolyStorm.Events:Emit("HS_TASK_CANCELLED",task,reason);self:Schedule(clock());return true end
-- DE/EN Public controls: Pause/Resume affect dispatch only; Cancel/Clear are eventful and observable.
function Tasks:Pause()if self.paused then return false end;self.paused=true;if self.timer then self.timer:Cancel();self.timer,self.timerDue=nil,nil end;HolyStorm.Events:Emit("HS_TASK_QUEUE_PAUSED");return true end
function Tasks:Resume()if not self.paused then return false end;self.paused=false;HolyStorm.Events:Emit("HS_TASK_QUEUE_RESUMED");self:Schedule(clock());return true end
function Tasks:IsPaused()return self.paused end
function Tasks:ClearQueue()local ids={};for _,t in ipairs(self.queue)do ids[#ids+1]=t.uniqueId end;for _,id in ipairs(ids)do self:Cancel(id,"QUEUE_CLEARED")end;return#ids end
function Tasks:CancelAll()self:ClearQueue();for id in pairs(self.recurring)do self:CancelRecurring(id)end;if self.runningTaskId then self:Cancel(self.runningTaskId,"ADDON_DISABLED")end end
function Tasks:ScheduleRecurring(id,interval,callback,o)interval=tonumber(interval);if type(id)~="string"or type(callback)~="function"or not interval or interval<1 then return false end;self:CancelRecurring(id);o=copy(o or{});self.recurring[id]=C_Timer.NewTicker(interval,function()o.triggerSource="RECURRING:"..id;Tasks:Enqueue(id,callback,o)end);return true end
function Tasks:CancelRecurring(id)local t=self.recurring[id];if t then t:Cancel();self.recurring[id]=nil;return true end;return false end
function Tasks:RecordEvent(event,module,context)addLimited(self.eventHistory,{timestamp=wall(),event=event,module=module,workflowId=context and context.workflowId,taskId=context and context.taskId,triggeredTask=context and context.triggeredTask},self.maxEventHistory)end
function Tasks:GetTask(id)return self.tasks[id]and clean(self.tasks[id])or nil end
function Tasks:GetQueue()local out={};for _,t in ipairs(self.queue)do out[#out+1]=clean(t)end;return out end
function Tasks:GetLiveTasks()local out={};for _,t in pairs(self.tasks)do if t.status~="COMPLETED"and t.status~="FAILED"and t.status~="CANCELLED"then out[#out+1]=clean(t)end end;table.sort(out,function(a,b)return a.sequence<b.sequence end);return out end
function Tasks:GetHistory()local out={};for i=#self.history,1,-1 do local t=self.tasks[self.history[i]];if t then out[#out+1]=clean(t)end end;return out end
function Tasks:GetPerformance()local out=copy(self.performance);for id,p in pairs(out)do p.averageDuration=p.runs>0 and p.totalDuration/p.runs or 0;p.module=self.registry[id]and self.registry[id].module or"-"end;return out end
function Tasks:GetEventHistory()return copy(self.eventHistory)end
HolyStorm.Tasks,HolyStorm.TaskManager=Tasks,Tasks
