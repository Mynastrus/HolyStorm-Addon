local addonVersion="1.0.1"
local HolyStorm=LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")

-- DE: Workflows besitzen nur Kontext und Zustandsuebergaenge. Schritte werden immer
-- als zentrale Tasks ausgefuehrt; Fortschritt entsteht ausschliesslich durch Events.
-- EN: Workflows own context and transitions only. Steps always execute as central
-- tasks and progress exclusively in response to task events.
local Workflows={version=addonVersion,registry={},workflows={},activeByType={},history={},performance={},sequence=0,maxHistory=100}
Workflows.Status={REGISTERED="REGISTERED",QUEUED="QUEUED",WAITING="WAITING",READY="READY",RUNNING="RUNNING",WAITING_ASYNC="WAITING_ASYNC",PAUSED="PAUSED",COMPLETED="COMPLETED",FAILED="FAILED",CANCELLED="CANCELLED"}
local function now()return HolyStorm.Utils.Now()end
local function clock()return GetTime and GetTime()or 0 end
local function addLimited(t,v,n)t[#t+1]=v;while#t>n do table.remove(t,1)end end
local function archive(self,id)local old;if#self.history>=self.maxHistory then old=table.remove(self.history,1)end;self.history[#self.history+1]=id;if old and old~=id then self.workflows[old]=nil end end
local function addSource(w,s)s=tostring(s or"UNKNOWN");w.triggerCount=w.triggerCount+1;w.triggerSources[s]=(w.triggerSources[s]or 0)+1 end
local function public(w)local result=HolyStorm.Utils.DeepCopy(w);result.definition=nil;result.context=nil;result.tasks={};for _,id in ipairs(w.completedTasks or{})do local task=HolyStorm.Tasks.tasks[id];if task then result.tasks[#result.tasks+1]={uniqueId=id,registryId=task.registryId,status=task.status,blockReason=task.blockReason,lastError=task.lastError}end end;for _,id in ipairs(w.pendingTasks or{})do local task=HolyStorm.Tasks.tasks[id];if task then result.tasks[#result.tasks+1]={uniqueId=id,registryId=task.registryId,status=task.status,blockReason=task.blockReason,lastError=task.lastError}end end;return result end

function Workflows:Initialize()
 local s=HolyStorm.db.profile.taskManager or{};self.maxHistory=tonumber(s.workflowHistoryLimit)or self.maxHistory
 HolyStorm.Events:Register("HS_TASK_STARTED","workflow-manager",function(_,task)Workflows:OnTaskStarted(task)end)
 HolyStorm.Events:Register("HS_TASK_WAITING","workflow-manager",function(_,task)Workflows:OnTaskWaiting(task)end)
 HolyStorm.Events:Register("HS_TASK_BLOCKED","workflow-manager",function(_,task)Workflows:OnTaskWaiting(task)end)
 HolyStorm.Events:Register("HS_TASK_COMPLETED","workflow-manager",function(_,task,result)Workflows:OnTaskFinished(task,true,result)end)
 HolyStorm.Events:Register("HS_TASK_FAILED","workflow-manager",function(_,task,result)Workflows:OnTaskFinished(task,false,result)end)
 HolyStorm.Events:Register("HS_TASK_CANCELLED","workflow-manager",function(_,task)Workflows:OnTaskCancelled(task)end)
 HolyStorm.Events:Register("HS_TASK_QUEUE_PAUSED","workflow-manager",function()for _,w in pairs(Workflows.workflows)do if w.status~="COMPLETED"and w.status~="FAILED"and w.status~="CANCELLED"then w.statusBeforePause=w.status;w.status="PAUSED";HolyStorm.Events:Emit("HS_WORKFLOW_PAUSED",w)end end end)
 HolyStorm.Events:Register("HS_TASK_QUEUE_RESUMED","workflow-manager",function()for _,w in pairs(Workflows.workflows)do if w.status=="PAUSED"then w.status=w.statusBeforePause or"WAITING";w.statusBeforePause=nil;HolyStorm.Events:Emit("HS_WORKFLOW_WAITING",w,"QUEUE_PAUSED")end end end)
end

-- DE/EN Public API: steps reference stable task IDs and may branch through results.
function Workflows:Register(workflowType,d)
 if type(workflowType)~="string"or type(d)~="table"or type(d.steps)~="table"or#d.steps==0 then return false,"INVALID_WORKFLOW_DEFINITION"end
 for i,step in ipairs(d.steps)do if type(step)~="table"or type(step.taskType)~="string"or not HolyStorm.Tasks:GetTaskType(step.taskType)then return false,"UNKNOWN_STEP_"..i end end
 self.registry[workflowType]={workflowType=workflowType,name=d.name or workflowType,localizedNameKey=d.localizedNameKey or workflowType,module=d.module or"Core",priority=tonumber(d.priority)or 50,allowParallel=d.allowParallel==true,debounce=tonumber(d.debounce)or 0,steps=HolyStorm.Utils.DeepCopy(d.steps),failurePolicy=d.failurePolicy or"ABORT",metadata=HolyStorm.Utils.DeepCopy(d.metadata or{})};return true
end
-- DE: Request verdichtet Trigger vor dem ersten Schritt per Debounce. Nach Beginn
-- wird unabhaengig von der Triggerzahl nur ein Pending-Restart vorgemerkt.
-- EN: Request coalesces triggers before the first step via debounce. Once running,
-- any number of triggers creates at most one pending restart.
function Workflows:Request(workflowType,o)
 local d=self.registry[workflowType];if not d then return nil,"UNKNOWN_WORKFLOW"end;o=o or{};local id=self.activeByType[workflowType];local w=id and self.workflows[id]
 if w and not d.allowParallel and w.status~="COMPLETED"and w.status~="FAILED"and w.status~="CANCELLED"then
  addSource(w,o.triggerSource)
  local perf=self.performance[workflowType]or{runs=0,totalDuration=0,maxDuration=0,errors=0,merges=0,triggers=0,module=d.module};perf.merges=perf.merges+1;self.performance[workflowType]=perf
  local task=w.currentTaskId and HolyStorm.Tasks.tasks[w.currentTaskId]
  if task and(task.status=="QUEUED"or task.status=="WAITING"or task.status=="BLOCKED"or task.status=="READY")and w.currentStep==1 then task.notBefore=clock()+math.max(0,tonumber(o.debounce)or d.debounce);task.triggerCount=task.triggerCount+1;local s=tostring(o.triggerSource or"UNKNOWN");task.triggerSources[s]=(task.triggerSources[s]or 0)+1;if HolyStorm.Tasks.maxTriggerHistory>0 then task.triggerHistory[#task.triggerHistory+1]={source=s,at=now()};while#task.triggerHistory>HolyStorm.Tasks.maxTriggerHistory do table.remove(task.triggerHistory,1)end end;local taskPerf=HolyStorm.Tasks.performance[task.registryId]or{runs=0,totalDuration=0,maxDuration=0,errors=0,merges=0,triggers=0};taskPerf.merges=taskPerf.merges+1;HolyStorm.Tasks.performance[task.registryId]=taskPerf;HolyStorm.Tasks:RecordEvent(s,task.module,{taskId=task.uniqueId,workflowId=w.workflowId,triggeredTask=task.registryId});HolyStorm.Logger:Write("DEBUG",task.module,"task","Task merged: "..task.registryId,{taskId=task.uniqueId,workflowId=w.workflowId,triggerCount=task.triggerCount,triggerSource=s},w.workflowId);HolyStorm.Events:Emit("HS_TASK_MERGED",task);HolyStorm.Tasks:Schedule();return id,"MERGED"end
  w.pendingRestart=true;w.restartOptions=HolyStorm.Utils.DeepCopy(o);HolyStorm.Events:Emit("HS_WORKFLOW_RESTART_PENDING",w);return id,"RESTART_PENDING"
 end
 return self:Start(workflowType,o)
end
function Workflows:Start(workflowType,o)
 local d=self.registry[workflowType];if not d then return nil,"UNKNOWN_WORKFLOW"end;o=o or{};self.sequence=self.sequence+1;local id=string.format("wf_%08X_%04X",now()%0xFFFFFFFF,self.sequence%0xFFFF)
 local taskOrder={};for _,step in ipairs(d.steps)do local taskType=HolyStorm.Tasks:GetTaskType(step.taskType);taskOrder[#taskOrder+1]=taskType and taskType.name or step.taskType end
 local w={workflowId=id,workflowType=workflowType,name=d.name,localizedNameKey=d.localizedNameKey,module=d.module,status="QUEUED",priority=tonumber(o.priority)or d.priority,createdAt=now(),createdClock=clock(),startedAt=nil,finishedAt=nil,currentTask=nil,currentTaskId=nil,currentStep=0,totalTasks=#d.steps,taskOrder=taskOrder,completedTasks={},pendingTasks={},triggerCount=0,triggerSources={},pendingRestart=false,metadata=HolyStorm.Utils.DeepCopy(o.metadata or d.metadata),context={results={},data=HolyStorm.Utils.DeepCopy(o.context or{}),retryCounts={}},lastError=nil,definition=d,restartOptions=nil}
 addSource(w,o.triggerSource);self.workflows[id]=w;if not d.allowParallel then self.activeByType[workflowType]=id end;HolyStorm.Logger:Write("DEBUG",w.module,"workflow","Workflow queued: "..workflowType,{workflowId=id,triggerSource=o.triggerSource},id);HolyStorm.Events:Emit("HS_WORKFLOW_QUEUED",w);self:QueueStep(w,1,tonumber(o.debounce)or d.debounce,o.triggerSource);return id,"QUEUED"
end
-- DE: QueueStep ruft keinen Modulschritt direkt auf. Er stellt einen Task ein;
-- TASK_* Events treiben den naechsten Zustandsuebergang.
-- EN: QueueStep never calls a module step directly. It queues a task and TASK_*
-- events drive the next transition.
function Workflows:QueueStep(w,index,delay,source,retryCount)
 local step=w.definition.steps[index];if not step then return self:Finish(w,true)end;w.currentStep=index;w.currentStepId=step.id or step.taskType;local taskType=HolyStorm.Tasks:GetTaskType(step.taskType);w.currentTask=taskType and taskType.name or step.taskType;w.status=delay and delay>0 and"WAITING"or"READY"
 local taskId,reason=HolyStorm.Tasks:Queue(step.taskType,{workflowId=w.workflowId,workflowStep=index,priority=step.priority or w.priority,delay=delay or step.delay,conditions=step.conditions,dependencies=step.dependencies,executionMode="MULTI",retryCount=retryCount or 0,maxRetries=step.maxRetries,triggerSource=source or("WORKFLOW:"..w.workflowType),metadata={stepId=step.id,workflowType=w.workflowType}})
 if not taskId then return self:Finish(w,false,reason)end;w.currentTaskId=taskId;w.pendingTasks[#w.pendingTasks+1]=taskId;HolyStorm.Events:Emit("HS_WORKFLOW_STEP_CHANGED",w,index,step);return taskId
end
function Workflows:OnTaskStarted(task)local w=task.workflowId and self.workflows[task.workflowId];if not w then return end;if not w.startedAt then w.startedAt=now();w.startedClock=clock();HolyStorm.Events:Emit("HS_WORKFLOW_STARTED",w)end;w.status="RUNNING"end
function Workflows:OnTaskWaiting(task)local w=task.workflowId and self.workflows[task.workflowId];if w then w.status=task.status=="WAITING_ASYNC"and"WAITING_ASYNC"or"WAITING";HolyStorm.Events:Emit("HS_WORKFLOW_WAITING",w,task.blockReason)end end
function Workflows:OnTaskCancelled(task)local w=task.workflowId and self.workflows[task.workflowId];if w and w.status~="CANCELLED"then self:Cancel(w.workflowId,"TASK_CANCELLED")end end
-- DE: Kontrollierte Resultate koennen Retry/Goto/Complete ausloesen. Lua-Fehler
-- verwenden die deklarierte Policy ABORT, RETRY, SKIP oder alternate.
-- EN: Controlled results may request Retry/Goto/Complete. Lua failures use the
-- declared ABORT, RETRY, SKIP or alternate policy.
function Workflows:OnTaskFinished(task,success,result)
 local w=task.workflowId and self.workflows[task.workflowId];if not w or w.currentTaskId~=task.uniqueId then return end;for i,id in ipairs(w.pendingTasks)do if id==task.uniqueId then table.remove(w.pendingTasks,i);break end end
 if success then w.completedTasks[#w.completedTasks+1]=task.uniqueId;w.context.results[w.currentStepId or w.currentTask]=result end;local step=w.definition.steps[w.currentStep]
 if not success then local p=step.failurePolicy or w.definition.failurePolicy;if p=="SKIP"then return self:QueueStep(w,w.currentStep+1,0,"FAILURE_SKIP")end;if p=="RETRY"then local key="failure:"..(step.id or tostring(w.currentStep));local count=(w.context.retryCounts[key]or 0)+1;w.context.retryCounts[key]=count;if count<=(step.maxRetries or task.maxRetries or 0)then return self:QueueStep(w,w.currentStep,step.retryDelay or 1,"FAILURE_RETRY",count)end end;if type(p)=="table"and p.alternate then return self:QueueStep(w,p.alternate,0,"FAILURE_ALTERNATE")end;return self:Finish(w,false,task.lastError or result)end
 local action=type(result)=="table"and result.workflowAction
 if action=="RETRY"then local key=step.id or tostring(w.currentStep);local count=(w.context.retryCounts[key]or 0)+1;w.context.retryCounts[key]=count;if count>(tonumber(result.maxRetries)or task.maxRetries or 3)then return self:Finish(w,false,result.reason or"RETRY_LIMIT")end;return self:QueueStep(w,tonumber(result.gotoStep)or w.currentStep,tonumber(result.delay)or 1,"VALIDATION_RETRY",count)
 elseif action=="COMPLETE"then return self:Finish(w,true)
 elseif action=="GOTO"then return self:QueueStep(w,tonumber(result.gotoStep),tonumber(result.delay)or 0,"WORKFLOW_BRANCH")end
 local nextStep=w.currentStep+1;if type(step.onResult)=="function"then local ok,value=HolyStorm.Utils.SafeCall("workflow.result:"..w.workflowType,step.onResult,result,w.context,w);if not ok then return self:Finish(w,false,value)end;if value==false then return self:Finish(w,true)elseif tonumber(value)then nextStep=value end end;return self:QueueStep(w,nextStep,0,"TASK_COMPLETED")
end
function Workflows:Finish(w,success,err)
 w.status=success and"COMPLETED"or"FAILED";w.finishedAt=now();w.finishedClock=clock();w.duration=math.max(0,w.finishedClock-(w.startedClock or w.createdClock));w.lastError=err and tostring(err)or nil;w.currentTaskId=nil;if self.activeByType[w.workflowType]==w.workflowId then self.activeByType[w.workflowType]=nil end;archive(self,w.workflowId);local perf=self.performance[w.workflowType]or{runs=0,totalDuration=0,maxDuration=0,errors=0,merges=0,triggers=0,module=w.module};perf.runs=perf.runs+1;perf.totalDuration=perf.totalDuration+w.duration;perf.maxDuration=math.max(perf.maxDuration,w.duration);perf.triggers=perf.triggers+w.triggerCount;if not success then perf.errors=perf.errors+1 end;self.performance[w.workflowType]=perf;HolyStorm.Logger:Write(success and"DEBUG"or"ERROR",w.module,"workflow",success and("Workflow completed: "..w.workflowType)or("Workflow failed: "..w.workflowType),{workflowId=w.workflowId,error=w.lastError,duration=w.duration},w.workflowId);HolyStorm.Events:Emit(success and"HS_WORKFLOW_COMPLETED"or"HS_WORKFLOW_FAILED",w)
 local restart,o=w.pendingRestart,w.restartOptions;w.context=nil;if restart then o=o or{};o.triggerSource=o.triggerSource or"PENDING_RESTART";self:Start(w.workflowType,o)end;return success
end
function Workflows:Cancel(id,reason)local w=self.workflows[id];if not w or w.status=="COMPLETED"or w.status=="FAILED"or w.status=="CANCELLED"then return false end;w.status="CANCELLED";w.finishedAt=now();w.lastError=reason or"CANCELLED";local taskId=w.currentTaskId;w.currentTaskId=nil;if taskId then HolyStorm.Tasks:Cancel(taskId,"WORKFLOW_CANCELLED")end;if self.activeByType[w.workflowType]==id then self.activeByType[w.workflowType]=nil end;w.context=nil;archive(self,id);HolyStorm.Events:Emit("HS_WORKFLOW_CANCELLED",w);return true end
function Workflows:Restart(id)local w=self.workflows[id];if not w then return nil end;if w.status~="COMPLETED"and w.status~="FAILED"and w.status~="CANCELLED"then self:Cancel(id,"MANUAL_RESTART")end;return self:Start(w.workflowType,{triggerSource="MANUAL_RESTART",metadata=w.metadata})end
function Workflows:ClearPendingRestart(id)local w=self.workflows[id];if not w then return false end;w.pendingRestart=false;w.restartOptions=nil;HolyStorm.Events:Emit("HS_WORKFLOW_RESTART_CLEARED",w);return true end
function Workflows:Get(id)return self.workflows[id]and public(self.workflows[id])or nil end
function Workflows:IsRunning(workflowType)local id=self.activeByType[workflowType];return id,self.workflows[id]end
function Workflows:GetLive()local out={};for _,w in pairs(self.workflows)do if w.status~="COMPLETED"and w.status~="FAILED"and w.status~="CANCELLED"then out[#out+1]=public(w)end end;table.sort(out,function(a,b)return a.createdAt<b.createdAt end);return out end
function Workflows:GetHistory()local out={};for i=#self.history,1,-1 do local w=self.workflows[self.history[i]];if w then out[#out+1]=public(w)end end;return out end
function Workflows:GetPerformance()local out=HolyStorm.Utils.DeepCopy(self.performance);for _,p in pairs(out)do p.averageDuration=p.runs>0 and p.totalDuration/p.runs or 0 end;return out end
HolyStorm.Workflows,HolyStorm.WorkflowManager=Workflows,Workflows
