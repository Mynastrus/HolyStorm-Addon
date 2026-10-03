local addonVersion="1.1.0"
local HolyStorm=LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")

-- DE: Workflows besitzen nur Kontext und Zustandsuebergaenge. Schritte werden immer
-- als zentrale Tasks ausgefuehrt; Fortschritt entsteht ausschliesslich durch Events.
-- EN: Workflows own context and transitions only. Steps always execute as central
-- tasks and progress exclusively in response to task events.
local Workflows={version=addonVersion,registry={},workflows={},activeByType={},history={},performance={},sequence=0,maxHistory=100,runtimeMetrics={requested=0,started=0,completed=0,failed=0,cancelled=0,byModule={},byTrigger={}}}
Workflows.Status={REGISTERED="REGISTERED",QUEUED="QUEUED",WAITING="WAITING",READY="READY",RUNNING="RUNNING",WAITING_ASYNC="WAITING_ASYNC",PAUSED="PAUSED",COMPLETED="COMPLETED",FAILED="FAILED",CANCELLED="CANCELLED"}
local function now()return HolyStorm.Utils.Now()end
local function clock()return GetTime and GetTime()or 0 end
local function addLimited(t,v,n)t[#t+1]=v;while#t>n do table.remove(t,1)end end
local function archive(self,id)local old;if#self.history>=self.maxHistory then old=table.remove(self.history,1)end;self.history[#self.history+1]=id;if old and old~=id then self.workflows[old]=nil end end
local function addSource(w,s)s=tostring(s or"UNKNOWN");w.triggerCount=w.triggerCount+1;w.triggerSources[s]=(w.triggerSources[s]or 0)+1 end
local publicFields={"workflowId","workflowType","name","localizedNameKey","module","status","priority","startupPhase","createdAt","createdClock","startedAt","startedClock","finishedAt","finishedClock","duration","currentTask","currentTaskId","currentStep","currentStepId","totalTasks","taskOrder","completedTasks","pendingTasks","triggerCount","triggerSources","triggerCategory","triggerName","pendingRestart","metadata","lastError","failureContext","statusBeforePause"}
local function public(w)local result={};for _,field in ipairs(publicFields)do local value=w[field];result[field]=type(value)=="table"and HolyStorm.Utils.DeepCopy(value)or value end;result.tasks={};for _,id in ipairs(w.completedTasks or{})do local task=HolyStorm.Tasks.tasks[id];if task then result.tasks[#result.tasks+1]={uniqueId=id,registryId=task.registryId,status=task.status,blockReason=task.blockReason,lastError=task.lastError}end end;for _,id in ipairs(w.pendingTasks or{})do local task=HolyStorm.Tasks.tasks[id];if task then result.tasks[#result.tasks+1]={uniqueId=id,registryId=task.registryId,status=task.status,blockReason=task.blockReason,lastError=task.lastError}end end;return result end
local function compactMetadata(value)local out={};for key,item in pairs(type(value)=="table"and value or{})do if type(item)=="string"or type(item)=="number"or type(item)=="boolean"then out[key]=item end end;return out end
local function metricBucket(map,key)
 key=tostring(key or"UNKNOWN");if#key>128 then key=key:sub(1,128)end;if map[key]then return map[key]end;local count=0;for _ in pairs(map)do count=count+1 end;if count>=256 then key="OTHER";if map[key]then return map[key]end end;local bucket={};map[key]=bucket;return bucket
end
local function increment(map,key,field)local bucket=metricBucket(map,key);bucket[field]=(bucket[field]or 0)+1 end
local function performanceBucket(self,id,module)
 local perf=self.performance[id]
 if not perf then perf={runs=0,totalDuration=0,maxDuration=0,errors=0,merges=0,triggers=0,requested=0,started=0,completed=0,failed=0,cancelled=0,module=module};self.performance[id]=perf end
 return perf
end

function Workflows:Initialize()
 local s=HolyStorm.db.profile.taskManager or{};self.maxHistory=tonumber(s.workflowHistoryLimit)or self.maxHistory
 HolyStorm.Events:Register("HS_TASK_STARTED","workflow-manager",function(_,task)Workflows:OnTaskStarted(task)end)
 HolyStorm.Events:Register("HS_TASK_RESUMED","workflow-manager",function(_,task)local w=task.workflowId and Workflows.workflows[task.workflowId];if w and w.status=="PAUSED"then w.statusBeforePause="RUNNING"else Workflows:OnTaskStarted(task)end end)
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
  local requestSource=o.triggerSource or(HolyStorm.Events and HolyStorm.Events.currentEvent)or"SYSTEM";local requestCategory,requestName=HolyStorm.Tasks:ClassifyTrigger(requestSource);addSource(w,requestSource);self.runtimeMetrics.requested=self.runtimeMetrics.requested+1;increment(self.runtimeMetrics.byModule,w.module,"requested");increment(self.runtimeMetrics.byTrigger,requestCategory..":"..requestName,"requested");if HolyStorm.Tasks.RecordStartupMetric then HolyStorm.Tasks:RecordStartupMetric("workflowRequests")end;if HolyStorm.Events.RecordFollowOn then HolyStorm.Events:RecordFollowOn(requestName,"workflowsRequested")end
  local perf=performanceBucket(self,workflowType,d.module);perf.merges=perf.merges+1;self.performance[workflowType]=perf
  local task=w.currentTaskId and HolyStorm.Tasks.tasks[w.currentTaskId]
  if task and not task.startedAt and(task.status=="QUEUED"or task.status=="WAITING"or task.status=="BLOCKED"or task.status=="READY")and w.currentStep==1 then task.notBefore=clock()+math.max(0,tonumber(o.debounce)or d.debounce);task.triggerCount=task.triggerCount+1;local s=tostring(o.triggerSource or"UNKNOWN");task.triggerSources[s]=(task.triggerSources[s]or 0)+1;if HolyStorm.Tasks.maxTriggerHistory>0 then task.triggerHistory[#task.triggerHistory+1]={source=s,at=now()};while#task.triggerHistory>HolyStorm.Tasks.maxTriggerHistory do table.remove(task.triggerHistory,1)end end;local taskPerf=HolyStorm.Tasks.performance[task.registryId]or{runs=0,totalDuration=0,maxDuration=0,errors=0,merges=0,triggers=0};taskPerf.merges=taskPerf.merges+1;HolyStorm.Tasks.performance[task.registryId]=taskPerf;HolyStorm.Tasks:RecordEvent(s,task.module,{taskId=task.uniqueId,workflowId=w.workflowId,triggeredTask=task.registryId});HolyStorm.Logger:Write("DEBUG",task.module,"task","Task merged: "..task.registryId,{taskId=task.uniqueId,workflowId=w.workflowId,triggerCount=task.triggerCount,triggerSource=s},w.workflowId);HolyStorm.Events:Emit("HS_TASK_MERGED",task);HolyStorm.Tasks:Schedule();return id,"MERGED"end
  w.pendingRestart=true;w.restartOptions=HolyStorm.Utils.DeepCopy(o);HolyStorm.Events:Emit("HS_WORKFLOW_RESTART_PENDING",w);return id,"RESTART_PENDING"
 end
 return self:Start(workflowType,o)
end
function Workflows:Start(workflowType,o)
 local d=self.registry[workflowType];if not d then return nil,"UNKNOWN_WORKFLOW"end;o=o or{};self.sequence=self.sequence+1;local id=string.format("wf_%08X_%04X",now()%0xFFFFFFFF,self.sequence%0xFFFF)
 local taskOrder={};for _,step in ipairs(d.steps)do local taskType=HolyStorm.Tasks:GetTaskType(step.taskType);taskOrder[#taskOrder+1]=taskType and taskType.name or step.taskType end
 local source=o.triggerSource or(HolyStorm.Events and HolyStorm.Events.currentEvent)or"SYSTEM";local category,triggerName=HolyStorm.Tasks:ClassifyTrigger(source);local perf=performanceBucket(self,workflowType,d.module);perf.requested=perf.requested+1
 local w={workflowId=id,workflowType=workflowType,name=d.name,localizedNameKey=d.localizedNameKey,module=d.module,status="QUEUED",priority=tonumber(o.priority)or d.priority,startupPhase=o.startupPhase,createdAt=now(),createdClock=clock(),startedAt=nil,finishedAt=nil,currentTask=nil,currentTaskId=nil,currentStep=0,totalTasks=#d.steps,taskOrder=taskOrder,completedTasks={},pendingTasks={},triggerCount=0,triggerSources={},triggerCategory=category,triggerName=triggerName,pendingRestart=false,metadata=HolyStorm.Utils.DeepCopy(o.metadata or d.metadata),context={results={},data=HolyStorm.Utils.DeepCopy(o.context or{}),retryCounts={}},lastError=nil,definition=d,restartOptions=nil}
 addSource(w,source);self.runtimeMetrics.requested=self.runtimeMetrics.requested+1;increment(self.runtimeMetrics.byModule,w.module,"requested");increment(self.runtimeMetrics.byTrigger,category..":"..triggerName,"requested");if HolyStorm.Tasks.RecordStartupMetric then HolyStorm.Tasks:RecordStartupMetric("workflowRequests")end;if HolyStorm.Events.RecordFollowOn then HolyStorm.Events:RecordFollowOn(triggerName,"workflowsRequested")end;self.workflows[id]=w;if not d.allowParallel then self.activeByType[workflowType]=id end;HolyStorm.Logger:Write("DEBUG",w.module,"workflow","Workflow queued: "..workflowType,{workflowId=id,triggerSource=source,triggerCategory=category},id);HolyStorm.Events:Emit("HS_WORKFLOW_QUEUED",w);self:QueueStep(w,1,tonumber(o.debounce)or d.debounce,source);return id,"QUEUED"
end
-- DE: QueueStep ruft keinen Modulschritt direkt auf. Er stellt einen Task ein;
-- TASK_* Events treiben den naechsten Zustandsuebergang.
-- EN: QueueStep never calls a module step directly. It queues a task and TASK_*
-- events drive the next transition.
function Workflows:QueueStep(w,index,delay,source,retryCount)
 local step=w.definition.steps[index];if not step then return self:Finish(w,true)end;w.currentStep=index;w.currentStepId=step.id or step.taskType;local taskType=HolyStorm.Tasks:GetTaskType(step.taskType);w.currentTask=taskType and taskType.name or step.taskType;w.status=delay and delay>0 and"WAITING"or"READY"
 local taskId,reason=HolyStorm.Tasks:Queue(step.taskType,{workflowId=w.workflowId,workflowStep=index,startupPhase=step.startupPhase or w.startupPhase,priority=step.priority or w.priority,delay=delay or step.delay,conditions=step.conditions,dependencies=step.dependencies,executionMode="MULTI",retryCount=retryCount or 0,maxRetries=step.maxRetries,timeoutSeconds=step.timeoutSeconds,triggerSource=source or("WORKFLOW:"..w.workflowType),metadata={stepId=step.id,workflowType=w.workflowType}})
 if not taskId then return self:Finish(w,false,reason)end;w.currentTaskId=taskId;w.pendingTasks[#w.pendingTasks+1]=taskId;HolyStorm.Events:Emit("HS_WORKFLOW_STEP_CHANGED",w,index,step);return taskId
end
function Workflows:OnTaskStarted(task)local w=task.workflowId and self.workflows[task.workflowId];if not w then return end;if not w.startedAt then w.startedAt=now();w.startedClock=clock();self.runtimeMetrics.started=self.runtimeMetrics.started+1;increment(self.runtimeMetrics.byModule,w.module,"started");increment(self.runtimeMetrics.byTrigger,(w.triggerCategory or"SYSTEM")..":"..(w.triggerName or"SYSTEM"),"started");local perf=performanceBucket(self,w.workflowType,w.module);perf.started=perf.started+1;if HolyStorm.Tasks.RecordStartupMetric then HolyStorm.Tasks:RecordStartupMetric("workflowsStarted")end;if HolyStorm.Events.RecordFollowOn then HolyStorm.Events:RecordFollowOn(w.triggerName,"workflowsStarted")end;HolyStorm.Events:Emit("HS_WORKFLOW_STARTED",w)end;w.status="RUNNING"end
function Workflows:OnTaskWaiting(task)local w=task.workflowId and self.workflows[task.workflowId];if w then w.status=task.status=="WAITING_ASYNC"and"WAITING_ASYNC"or"WAITING";HolyStorm.Events:Emit("HS_WORKFLOW_WAITING",w,task.blockReason)end end
function Workflows:OnTaskCancelled(task)local w=task.workflowId and self.workflows[task.workflowId];if w and w.status~="CANCELLED"then self:Cancel(w.workflowId,"TASK_CANCELLED")end end
-- DE: Kontrollierte Resultate koennen Retry/Goto/Complete ausloesen. Lua-Fehler
-- verwenden die deklarierte Policy ABORT, RETRY, SKIP oder alternate.
-- EN: Controlled results may request Retry/Goto/Complete. Lua failures use the
-- declared ABORT, RETRY, SKIP or alternate policy.
function Workflows:OnTaskFinished(task,success,result)
 local w=task.workflowId and self.workflows[task.workflowId];if not w or w.currentTaskId~=task.uniqueId then return end;for i,id in ipairs(w.pendingTasks)do if id==task.uniqueId then table.remove(w.pendingTasks,i);break end end
 if success then w.completedTasks[#w.completedTasks+1]=task.uniqueId;w.context.results[w.currentStepId or w.currentTask]=result end;local step=w.definition.steps[w.currentStep]
  if not success then local p=step.failurePolicy or w.definition.failurePolicy;if p=="SKIP"then return self:QueueStep(w,w.currentStep+1,0,"FAILURE_SKIP")end;if p=="RETRY"then local key="failure:"..(step.id or tostring(w.currentStep));local count=(w.context.retryCounts[key]or 0)+1;w.context.retryCounts[key]=count;if count<=(step.maxRetries or task.maxRetries or 0)then return self:QueueStep(w,w.currentStep,step.retryDelay or 1,"FAILURE_RETRY",count)end;return self:Finish(w,false,task.lastError or result,task,"TASK_RETRY_EXHAUSTED",count)end;if type(p)=="table"and p.alternate then return self:QueueStep(w,p.alternate,0,"FAILURE_ALTERNATE")end;return self:Finish(w,false,task.lastError or result,task,task.lastError=="TASK_TIMEOUT"and"TASK_TIMEOUT"or"TASK_FAILED")end
 local action=type(result)=="table"and result.workflowAction
  if action=="RETRY"then local key=step.id or tostring(w.currentStep);local count=(w.context.retryCounts[key]or 0)+1;w.context.retryCounts[key]=count;if count>(tonumber(result.maxRetries)or task.maxRetries or 3)then return self:Finish(w,false,result.reason or"RETRY_LIMIT",task,"WORKFLOW_RETRY_EXHAUSTED",count,result)end;return self:QueueStep(w,tonumber(result.gotoStep)or w.currentStep,tonumber(result.delay)or 1,"VALIDATION_RETRY",count)
  elseif action=="FAIL"then return self:Finish(w,false,result.reason or"WORKFLOW_FAILED",task,"WORKFLOW_ACTION_FAIL",nil,result)
 elseif action=="COMPLETE"then return self:Finish(w,true)
 elseif action=="GOTO"then return self:QueueStep(w,tonumber(result.gotoStep),tonumber(result.delay)or 0,"WORKFLOW_BRANCH")end
  local nextStep=w.currentStep+1;if type(step.onResult)=="function"then local ok,value=HolyStorm.Utils.SafeCall("workflow.result:"..w.workflowType,step.onResult,result,w.context,w);if not ok then return self:Finish(w,false,value,task,"RESULT_HANDLER_FAILED")end;if value==false then return self:Finish(w,true)elseif tonumber(value)then nextStep=value end end;return self:QueueStep(w,nextStep,0,"TASK_COMPLETED")
end
local function dependencyDescription(task,step)
 local deps=task and task.dependencies or step and step.dependencies;if type(deps)~="table"or#deps==0 then return task and task.blockReason or"NONE"end
 local out={};for _,dep in ipairs(deps)do if type(dep)=="table"then out[#out+1]=tostring(dep.step or dep.taskId or dep.registryId or dep.type or"UNKNOWN")else out[#out+1]=tostring(dep)end end;return table.concat(out,",")
end
function Workflows:BuildFailureContext(w,err,task,errorType,attempt,result)
 local step=w.definition and w.definition.steps[w.currentStep];local data=w.context and w.context.data or{};local activeScan=HolyStorm.CharacterScans and HolyStorm.CharacterScans.active;local scanOwned=activeScan and activeScan.workflowId==w.workflowId
 local lastSuccessfulStage=data.lastSuccessfulStage
 if not lastSuccessfulStage and w.context and w.context.results and w.definition then for index=1,math.max(0,(w.currentStep or 1)-1)do local previous=w.definition.steps[index];local resultValue=previous and w.context.results[previous.id or previous.taskType];if resultValue~=nil and not(type(resultValue)=="table"and resultValue.workflowAction=="RETRY")then lastSuccessfulStage=previous.id or previous.taskType end end end
 local retryCount=tonumber(task and task.retryCount);if attempt~=nil then retryCount=math.max(0,(tonumber(attempt)or 1)-1)elseif retryCount==nil then retryCount=0 end;local taskTimeout=task and(task.timeoutSeconds or task.timeout)or"NOT_CONFIGURED";local workflowTimeout=w.definition and(w.definition.timeoutSeconds or w.definition.timeout)or"NOT_CONFIGURED"
 return{workflowId=w.workflowId,workflowType=w.workflowType,currentStep=w.currentStep,currentStepId=w.currentStepId,currentTask=w.currentTask,failedTask=task and task.registryId or w.currentTask,taskId=task and task.uniqueId,taskStatus=task and task.status,dependency=dependencyDescription(task,step),attempt=retryCount+1,retryCount=retryCount,maxRetries=task and task.maxRetries,elapsed=math.max(0,clock()-(w.startedClock or w.createdClock)),timeout=taskTimeout,taskTimeout=taskTimeout,workflowTimeout=workflowTimeout,errorType=errorType or(task and task.lastError=="TASK_TIMEOUT"and"TASK_TIMEOUT"or task and task.status=="FAILED"and"TASK_FAILED"or"WORKFLOW_FAILED"),reason=tostring(err or"UNKNOWN"),workflowAction=type(result)=="table"and result.workflowAction or nil,characterScanOwned=scanOwned==true,characterScanBlock=scanOwned and activeScan.block or nil,characterScanWorkflowId=scanOwned and activeScan.workflowId or nil,candidateState=data.candidateState or"UNKNOWN",candidateReason=data.candidateReason,lastSuccessfulStage=lastSuccessfulStage}
end
function Workflows:Finish(w,success,err,task,errorType,attempt,result)
 w.finishedAt=now();w.finishedClock=clock();w.duration=math.max(0,w.finishedClock-(w.startedClock or w.createdClock));w.lastError=err and tostring(err)or nil
 if not success then w.failureContext=self:BuildFailureContext(w,err,task,errorType,attempt,result)end
 w.status=success and"COMPLETED"or"FAILED";w.currentTaskId=nil;if self.activeByType[w.workflowType]==w.workflowId then self.activeByType[w.workflowType]=nil end;archive(self,w.workflowId);local perf=self.performance[w.workflowType]or{runs=0,totalDuration=0,maxDuration=0,errors=0,merges=0,triggers=0,module=w.module};perf.runs=perf.runs+1;perf.totalDuration=perf.totalDuration+w.duration;perf.maxDuration=math.max(perf.maxDuration,w.duration);perf.triggers=perf.triggers+w.triggerCount;if not success then perf.errors=perf.errors+1 end;self.performance[w.workflowType]=perf
 if success then self.runtimeMetrics.completed=self.runtimeMetrics.completed+1;increment(self.runtimeMetrics.byModule,w.module,"completed");increment(self.runtimeMetrics.byTrigger,(w.triggerCategory or"SYSTEM")..":"..(w.triggerName or"SYSTEM"),"completed");if HolyStorm.Tasks.RecordStartupMetric then HolyStorm.Tasks:RecordStartupMetric("workflowsCompleted")end;if HolyStorm.Events.RecordFollowOn then HolyStorm.Events:RecordFollowOn(w.triggerName,"workflowsCompleted")end;perf.completed=(perf.completed or 0)+1 else self.runtimeMetrics.failed=self.runtimeMetrics.failed+1;increment(self.runtimeMetrics.byModule,w.module,"failed");increment(self.runtimeMetrics.byTrigger,(w.triggerCategory or"SYSTEM")..":"..(w.triggerName or"SYSTEM"),"failed");if HolyStorm.Tasks.RecordStartupMetric then HolyStorm.Tasks:RecordStartupMetric("workflowsFailed")end;if HolyStorm.Events.RecordFollowOn then HolyStorm.Events:RecordFollowOn(w.triggerName,"workflowsFailed")end;perf.failed=(perf.failed or 0)+1 end
 local context=success and{workflowId=w.workflowId,workflowType=w.workflowType,duration=w.duration}or w.failureContext;context.error=w.lastError;context.duration=w.duration;HolyStorm.Logger:Write(success and"DEBUG"or"ERROR",w.module,"workflow",success and("Workflow completed: "..w.workflowType)or("Workflow failed: "..w.workflowType),context,w.workflowId);HolyStorm.Events:Emit(success and"HS_WORKFLOW_COMPLETED"or"HS_WORKFLOW_FAILED",w)
 local restart,o=w.pendingRestart,w.restartOptions;w.context,w.definition,w.restartOptions=nil,nil,nil;w.pendingRestart=false;w.metadata=compactMetadata(w.metadata);if restart then o=o or{};o.triggerSource=o.triggerSource or"PENDING_RESTART";self:Start(w.workflowType,o)end;return success
end
function Workflows:Cancel(id,reason)local w=self.workflows[id];if not w or w.status=="COMPLETED"or w.status=="FAILED"or w.status=="CANCELLED"then return false end;w.status="CANCELLED";w.finishedAt=now();w.finishedClock=clock();w.duration=math.max(0,w.finishedClock-(w.startedClock or w.createdClock));w.lastError=reason or"CANCELLED";self.runtimeMetrics.cancelled=self.runtimeMetrics.cancelled+1;increment(self.runtimeMetrics.byModule,w.module,"cancelled");increment(self.runtimeMetrics.byTrigger,(w.triggerCategory or"SYSTEM")..":"..(w.triggerName or"SYSTEM"),"cancelled");performanceBucket(self,w.workflowType,w.module).cancelled=performanceBucket(self,w.workflowType,w.module).cancelled+1;if HolyStorm.Tasks.RecordStartupMetric then HolyStorm.Tasks:RecordStartupMetric("workflowsCancelled")end;local taskId=w.currentTaskId;w.currentTaskId=nil;if taskId then HolyStorm.Tasks:Cancel(taskId,"WORKFLOW_CANCELLED")end;if self.activeByType[w.workflowType]==id then self.activeByType[w.workflowType]=nil end;archive(self,id);HolyStorm.Events:Emit("HS_WORKFLOW_CANCELLED",w);w.context,w.definition,w.restartOptions=nil,nil,nil;w.pendingRestart=false;w.metadata=compactMetadata(w.metadata);return true end
function Workflows:Restart(id)local w=self.workflows[id];if not w then return nil end;if w.status~="COMPLETED"and w.status~="FAILED"and w.status~="CANCELLED"then self:Cancel(id,"MANUAL_RESTART")end;return self:Start(w.workflowType,{triggerSource="MANUAL_RESTART",metadata=w.metadata})end
function Workflows:ClearPendingRestart(id)local w=self.workflows[id];if not w then return false end;w.pendingRestart=false;w.restartOptions=nil;HolyStorm.Events:Emit("HS_WORKFLOW_RESTART_CLEARED",w);return true end
function Workflows:Get(id)return self.workflows[id]and public(self.workflows[id])or nil end
function Workflows:IsRunning(workflowType)local id=self.activeByType[workflowType];return id,self.workflows[id]end
function Workflows:GetLive()local out={};for _,w in pairs(self.workflows)do if w.status~="COMPLETED"and w.status~="FAILED"and w.status~="CANCELLED"then out[#out+1]=public(w)end end;table.sort(out,function(a,b)return a.createdAt<b.createdAt end);return out end
function Workflows:GetHistory()local out={};for i=#self.history,1,-1 do local w=self.workflows[self.history[i]];if w then out[#out+1]=public(w)end end;return out end
function Workflows:GetPerformance()local out={};for id,p in pairs(self.performance)do out[id]={runs=p.runs,totalDuration=p.totalDuration,maxDuration=p.maxDuration,errors=p.errors,merges=p.merges,triggers=p.triggers,requested=p.requested or 0,started=p.started or 0,completed=p.completed or 0,failed=p.failed or 0,cancelled=p.cancelled or 0,averageDuration=p.runs>0 and(p.totalDuration or 0)/p.runs or 0,module=p.module}end;return out end
function Workflows:IsIdle()local active=0;for _,w in pairs(self.workflows)do if w.status~="COMPLETED"and w.status~="FAILED"and w.status~="CANCELLED"then active=active+1 end end;return active==0 end
function Workflows:GetRuntimeMetrics()return self.runtimeMetrics end
function Workflows:ResetRuntimeMetrics()self.runtimeMetrics={requested=0,started=0,completed=0,failed=0,cancelled=0,byModule={},byTrigger={}};self.performance={};return true end
function Workflows:GetDiagnostics()local active=0;for _,w in pairs(self.workflows)do if w.status~="COMPLETED"and w.status~="FAILED"and w.status~="CANCELLED"then active=active+1 end end;return{active=active,history=#self.history,historyLimit=self.maxHistory,idle=self:IsIdle(),metrics=self.runtimeMetrics}end
HolyStorm.Workflows,HolyStorm.WorkflowManager=Workflows,Workflows
