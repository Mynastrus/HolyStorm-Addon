local addonVersion="1.0.0"
local HolyStorm=LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local L=LibStub("AceLocale-3.0"):GetLocale("Holy_Storm_TaskManager")
local Page=HolyStorm:RegisterRequiredModule("TaskManagerUI")
HolyStorm:ApplyModuleMetadata(Page,{displayName=L["DISPLAY_NAME"],internalName="taskManagerUI",version=addonVersion,category="required",description=L["DESCRIPTION"],permissions={"tasks-view"},dependencies={"core","ui"},enabledByDefault=true})
local views={"LIVE_TASKS","QUEUE","WORKFLOWS","HISTORY","PERFORMANCE","EVENT_MONITOR","DEPENDENCIES"}
local ROW_HEIGHT=20
local MAX_VISIBLE_ROWS=32
local REFRESH_DELAY=.1
local refreshEvents={"HS_TASK_QUEUED","HS_TASK_MERGED","HS_TASK_STARTED","HS_TASK_RESUMED","HS_TASK_WAITING","HS_TASK_BLOCKED","HS_TASK_COMPLETED","HS_TASK_FAILED","HS_TASK_CANCELLED","HS_TASK_QUEUE_PAUSED","HS_TASK_QUEUE_RESUMED","HS_WORKFLOW_QUEUED","HS_WORKFLOW_STARTED","HS_WORKFLOW_STEP_CHANGED","HS_WORKFLOW_WAITING","HS_WORKFLOW_PAUSED","HS_WORKFLOW_COMPLETED","HS_WORKFLOW_FAILED","HS_WORKFLOW_CANCELLED","HS_WORKFLOW_RESTART_PENDING","HS_SYNC_ACTIVITY_UPDATED","HS_CHARACTER_SCAN_COMPLETED","HS_CHARACTER_SNAPSHOT_STATUS_CHANGED"}
local columns={
 LIVE_TASKS={{"status","COL_STATUS",86},{"name","COL_TASK",150},{"module","COL_MODULE",90},{"workflow","COL_WORKFLOW",135},{"priority","COL_PRIORITY",58},{"triggers","COL_TRIGGERS",58},{"created","COL_CREATED",72},{"waiting","COL_WAITING",62},{"runtime","COL_RUNTIME",62},{"block","COL_BLOCK",150}},
 QUEUE={{"position","QUEUE",45},{"status","COL_STATUS",78},{"name","COL_TASK",170},{"module","COL_MODULE",90},{"workflow","COL_WORKFLOW",140},{"priority","COL_PRIORITY",58},{"triggers","COL_TRIGGERS",58},{"waiting","COL_WAITING",70},{"block","COL_BLOCK",165}},
 WORKFLOWS={{"status","COL_STATUS",86},{"name","COL_WORKFLOW",170},{"module","COL_MODULE",90},{"step","COL_STEP",155},{"progress","COL_PROGRESS",76},{"restart","COL_RESTART",85},{"runtime","COL_RUNTIME",70},{"triggers","COL_TRIGGERS",60}},
 HISTORY={{"status","COL_STATUS",86},{"kind","DETAILS",82},{"name","COL_TASK",190},{"module","COL_MODULE",100},{"workflow","COL_WORKFLOW",150},{"runtime","COL_RUNTIME",75},{"triggers","COL_TRIGGERS",65},{"block","COL_BLOCK",170}},
 PERFORMANCE={{"name","COL_TASK",180},{"module","COL_MODULE",90},{"status","COL_STATUS",95},{"requested","COL_REQUESTED",75},{"automatic","COL_AUTOMATIC",75},{"manual","COL_MANUAL",65},{"started","COL_STARTED",65},{"completed","COL_COMPLETED",75},{"failed","COL_FAILED",60},{"cancelled","COL_CANCELLED",75},{"retries","COL_RETRIES",65},{"queueWait","COL_QUEUE_WAIT",90},{"average","COL_AVERAGE",90},{"maximum","COL_MAXIMUM",90},{"merges","COL_MERGES",80},{"triggers","COL_TRIGGERS",70}},
 EVENT_MONITOR={{"event","COL_EVENT",220},{"count","COL_COUNT",65},{"lastSeen","COL_LAST_SEEN",85},{"tasksRequested","COL_TASK_REQUESTS",95},{"tasksStarted","COL_TASKS_STARTED",90},{"workflowsRequested","COL_WORKFLOW_REQUESTS",110},{"workflowsStarted","COL_WORKFLOWS_STARTED",105}},
 DEPENDENCIES={{"status","COL_STATUS",90},{"name","COL_TASK",220},{"dependency","COL_DEPENDENCY",260},{"workflow","COL_WORKFLOW",180}},
}
local function elapsed(started,finished)if not started then return"-"end;return string.format("%.2fs",math.max(0,(finished or HolyStorm.Utils.Now())-started))end
local function measured(value)return type(value)=="number"and string.format("%.3fs",math.max(0,value))or"-"end
local function stamp(value)return value and date("%H:%M:%S",value)or"-"end
local function yes(value)return value and L["TRUE"]or L["FALSE"]end
local function status(value)return L["STATUS_"..tostring(value)]or tostring(value or"-")end
local reasonLabels={
 DEBOUNCE=L["REASON_DEBOUNCE"],NOT_IN_COMBAT=L["REASON_NOT_IN_COMBAT"],PLAYER_LOGGED_IN=L["REASON_PLAYER_LOGGED_IN"],PLAYER_READY=L["REASON_PLAYER_READY"],GUILD_AVAILABLE=L["REASON_GUILD_AVAILABLE"],NOT_LOADING=L["REASON_NOT_LOADING"],NOT_ZONING=L["REASON_NOT_ZONING"],ASYNC=L["REASON_ASYNC"],
}
local reasonTemplates={STARTUP_PHASE=L["REASON_STARTUP_PHASE"],DEPENDENCY_WAITING=L["REASON_DEPENDENCY_WAITING"],DEPENDENCY_MISSING=L["REASON_DEPENDENCY_MISSING"],UNKNOWN_CONDITION=L["REASON_UNKNOWN_CONDITION"]}
function Page:FormatReason(value)
 if value==nil then return"-"end;if type(value)~="string"then return tostring(value)end
 local label=reasonLabels[value];if label then return label end
 local kind,id=value:match("^([A-Z_]+):(.*)$");local template=kind and reasonTemplates[kind];if template then return string.format(template,id)end
 return value
end
local function reason(value)return Page:FormatReason(value)end
local function flatten(value,depth,seen)
 if type(value)~="table"then return tostring(value==nil and"-"or value)end;depth=depth or 0;seen=seen or{};if seen[value]then return"<"..L["CYCLE"]..">"end;if depth>=4 then return"<"..L["NESTED_TRUNCATED"]..">"end;seen[value]=true;local out={};for k,v in pairs(value)do out[#out+1]=tostring(k).."="..flatten(v,depth+1,seen)end;seen[value]=nil;table.sort(out);return"{"..table.concat(out,", ").."}"
end
local function compactDiagnostic(value)
 local function render(item,depth,seen)
  if type(item)~="table"then local text=tostring(item==nil and"-"or item);if#text>96 then return text:sub(1,93).."..."end;return text end
  if seen[item]then return"<"..L["CYCLE"]..">"end;if depth>=3 then return"<"..L["NESTED_TRUNCATED"]..">"end;seen[item]=true;local keys={};for key in pairs(item)do keys[#keys+1]=key end;table.sort(keys,function(a,b)return tostring(a)<tostring(b)end);local out={};for _,key in ipairs(keys)do out[#out+1]=tostring(key).."="..render(item[key],depth+1,seen)end;seen[item]=nil;return"{"..table.concat(out,", ").."}"
 end
 local text=render(value,0,{});if#text>720 then return text:sub(1,717).."..."end;return text
end
local fieldLabels={uniqueId="FIELD_UNIQUE_ID",registryId="FIELD_REGISTRY_ID",workflowId="FIELD_WORKFLOW_ID",workflowType="FIELD_WORKFLOW_TYPE",status="FIELD_STATUS",module="FIELD_MODULE",priority="FIELD_PRIORITY",currentTask="FIELD_CURRENT_TASK",currentStep="FIELD_CURRENT_STEP",blockReason="FIELD_BLOCK_REASON",lastError="FIELD_LAST_ERROR",createdAt="FIELD_CREATED_AT",startedAt="FIELD_STARTED_AT",finishedAt="FIELD_FINISHED_AT",triggerCount="FIELD_TRIGGER_COUNT",pendingRestart="FIELD_PENDING_RESTART",triggerCategory="FIELD_TRIGGER_CATEGORY",triggerName="FIELD_TRIGGER_NAME",queueWait="FIELD_QUEUE_WAIT",duration="FIELD_EXECUTION_TIME",asyncWaitDuration="FIELD_ASYNC_WAIT",executionDuration="FIELD_EXECUTION_TIME"}
local function matches(row,search,module,workflow)local hay=string.lower(table.concat({row.name or"",row.module or"",row.status or"",row.workflow or"",row.event or"",row.block or""}," "));return(search==""or hay:find(search,1,true))and(module==""or string.lower(row.module or""):find(module,1,true))and(workflow==""or string.lower(row.workflow or""):find(workflow,1,true))end

function Page:GetLayout(view)
 local path="taskManager.columns."..view;local layout=HolyStorm.Database:Get(path,"profile");if type(layout)~="table"then HolyStorm.Database:Set(path,{widths={},hidden={},order={}},"profile");layout=HolyStorm.Database:Get(path,"profile")end;layout.widths=type(layout.widths)=="table"and layout.widths or{};layout.hidden=type(layout.hidden)=="table"and layout.hidden or{};layout.order=type(layout.order)=="table"and layout.order or{};return layout
end
function Page:GetColumns()
 local defs=columns[self.view];local layout=self:GetLayout(self.view);local byKey={};for _,d in ipairs(defs)do byKey[d[1]]=d end;local result={}
 for _,key in ipairs(layout.order)do if byKey[key]then result[#result+1]=byKey[key];byKey[key]=nil end end;for _,d in ipairs(defs)do if byKey[d[1]]then result[#result+1]=d end end;return result
end
local function metricRow(name,module,kind,counters)
 counters=counters or{}
 local failedLabel=counters.failedAfterStart~=nil and L["METRIC_FAILED_AFTER_START"]or L["METRIC_FAILED"]
 local lines={L["METRIC_REQUESTED"]..": "..tostring(counters.requested or 0),L["METRIC_AUTOMATIC"]..": "..tostring(counters.automatic or 0),L["METRIC_MANUAL"]..": "..tostring(counters.manual or 0),L["METRIC_STARTED"]..": "..tostring(counters.started or 0),L["METRIC_COMPLETED"]..": "..tostring(counters.completed or 0),failedLabel..": "..tostring(counters.failedAfterStart or counters.failed or counters.errors or 0),L["METRIC_CANCELLED"]..": "..tostring(counters.cancelled or 0),L["METRIC_RETRIES"]..": "..tostring(counters.retryCount or counters.retried or 0)}
 if counters.startFailed~=nil then lines[#lines+1]=L["METRIC_START_FAILURES"]..": "..tostring(counters.startFailed)end
 if counters.logicalScans~=nil then lines[#lines+1]=L["METRIC_LOGICAL_SCANS"]..": "..tostring(counters.logicalScans)end
 if counters.taskLifecycles~=nil then lines[#lines+1]=L["METRIC_TASK_LIFECYCLES"]..": "..tostring(counters.taskLifecycles)end
 if counters.commits~=nil then lines[#lines+1]=L["METRIC_COMMITS"]..": "..tostring(counters.commits)end
 if counters.noOpScans~=nil then lines[#lines+1]=L["METRIC_NOOP_SCANS"]..": "..tostring(counters.noOpScans)end
 if counters.lastDuration~=nil then lines[#lines+1]=L["METRIC_LAST_SCAN_DURATION"]..": "..string.format("%.3fs",counters.lastDuration)end
 if counters.totalScanDuration~=nil then lines[#lines+1]=L["METRIC_TOTAL_SCAN_DURATION"]..": "..string.format("%.3fs",counters.totalScanDuration)end
 if counters.maxScanDuration~=nil then lines[#lines+1]=L["METRIC_MAX_SCAN_DURATION"]..": "..string.format("%.3fs",counters.maxScanDuration)end
 if counters.lastLuaMs~=nil then lines[#lines+1]=L["METRIC_LAST_LUA"]..": "..string.format("%.3fms",counters.lastLuaMs)end
 if counters.totalLuaMs~=nil then lines[#lines+1]=L["METRIC_TOTAL_LUA"]..": "..string.format("%.3fms",counters.totalLuaMs)end
 if counters.maxLuaMs~=nil then lines[#lines+1]=L["METRIC_MAX_LUA"]..": "..string.format("%.3fms",counters.maxLuaMs)end
 if counters.maxTaskMs~=nil then lines[#lines+1]=L["METRIC_MAX_TASK_LUA"]..": "..string.format("%.3fms",counters.maxTaskMs)end
 if counters.lastQueueWait~=nil then lines[#lines+1]=L["METRIC_LAST_QUEUE_WAIT"]..": "..string.format("%.3fs",counters.lastQueueWait)end
 if counters.totalQueueWait~=nil and counters.lastQueueWait~=nil then lines[#lines+1]=L["METRIC_PRODUCER_QUEUE_WAIT"]..": "..string.format("%.3fs",counters.totalQueueWait)end
 if counters.maxQueueWait~=nil and counters.lastQueueWait~=nil then lines[#lines+1]=L["METRIC_MAX_QUEUE_WAIT"]..": "..string.format("%.3fs",counters.maxQueueWait)end
 if counters.runs~=nil then lines[#lines+1]=L["METRIC_RUNS"]..": "..tostring(counters.runs)end
 if counters.totalDuration~=nil then lines[#lines+1]=L["METRIC_TOTAL_EXECUTION"]..": "..string.format("%.3fs",counters.totalDuration)end
 if counters.totalElapsed~=nil then lines[#lines+1]=L["METRIC_TOTAL_ELAPSED"]..": "..string.format("%.3fs",counters.totalElapsed)end
 if counters.totalQueueWait~=nil then lines[#lines+1]=L["METRIC_TOTAL_QUEUE_WAIT"]..": "..string.format("%.3fs",counters.totalQueueWait)end
 if counters.maxQueueWait~=nil then lines[#lines+1]=L["METRIC_MAX_QUEUE_WAIT"]..": "..string.format("%.3fs",counters.maxQueueWait)end
 if counters.averageQueueWait then lines[#lines+1]=L["METRIC_QUEUE_WAIT"]..": "..string.format("%.3fs",counters.averageQueueWait)end
 if counters.averageDuration then lines[#lines+1]=L["METRIC_EXECUTION"]..": "..string.format("%.3fs",counters.averageDuration)end
 if counters.maxDuration then lines[#lines+1]=L["METRIC_MAXIMUM"]..": "..string.format("%.3fs",counters.maxDuration)end
 if counters.merges then lines[#lines+1]=L["METRIC_MERGES"]..": "..tostring(counters.merges)end
 if counters.triggers then lines[#lines+1]=L["METRIC_TRIGGERS"]..": "..tostring(counters.triggers)end
 return{name=name,module=module or"-",status=kind or"-",requested=counters.requested or 0,automatic=counters.automatic or 0,manual=counters.manual or 0,started=counters.started or 0,logicalScans=counters.logicalScans or counters.started or 0,taskLifecycles=counters.taskLifecycles or 0,commits=counters.commits or 0,noOpScans=counters.noOpScans or 0,completed=counters.completed or 0,failed=counters.failedAfterStart or counters.failed or counters.errors or 0,cancelled=counters.cancelled or 0,retries=counters.retryCount or counters.retried or 0,queueWait=counters.averageQueueWait and string.format("%.3fs",counters.averageQueueWait)or"-",average=counters.averageDuration and string.format("%.3fs",counters.averageDuration)or"-",maximum=counters.maxDuration and string.format("%.3fs",counters.maxDuration)or"-",merges=counters.merges or 0,triggers=counters.triggers or 0,details=table.concat(lines,"\n"),kind="performance",object=counters}
end
local function combineCounters(target,source)
 for _,key in ipairs({"requested","started","completed","failed","errors","cancelled","retried","automatic","manual"})do target[key]=(target[key]or 0)+(source and source[key]or 0)end
end
function Page:BuildData()
 local rows={};local taskMap={}
 if self.view=="LIVE_TASKS"or self.view=="DEPENDENCIES"then
  for _,t in ipairs(HolyStorm.Tasks:GetLiveTasks())do taskMap[t.uniqueId]=t;if self.view=="DEPENDENCIES"then for _,dep in ipairs(t.dependencies or{})do rows[#rows+1]={status=status(t.status),name=t.name,dependency=type(dep)=="table"and(dep.taskId or dep.registryId)or dep,workflow=t.workflowId or"-",object=t,kind="task"}end end;if self.view=="LIVE_TASKS"then rows[#rows+1]={status=status(t.status),name=t.name,module=t.module,workflow=t.workflowId or"-",priority=t.priority,triggers=t.triggerCount,created=stamp(t.createdAt),waiting=t.queueWait and measured(t.queueWait)or elapsed(t.queuedAt,t.startedAt),runtime=measured(t.duration or t.executionDuration),block=reason(t.blockReason),object=t,kind="task"}end end
 elseif self.view=="QUEUE"then for i,t in ipairs(HolyStorm.Tasks:GetQueue())do rows[#rows+1]={position=i,status=status(t.status),name=t.name,module=t.module,workflow=t.workflowId or"-",priority=t.priority,triggers=t.triggerCount,waiting=elapsed(t.queuedAt),block=reason(t.blockReason),object=t,kind="task"}end
 elseif self.view=="WORKFLOWS"then for _,w in ipairs(HolyStorm.Workflows:GetLive())do rows[#rows+1]={status=status(w.status),name=w.name,module=w.module,step=w.currentTask or"-",progress=string.format("%d/%d",#w.completedTasks,w.totalTasks or 0),restart=yes(w.pendingRestart),runtime=elapsed(w.startedAt or w.createdAt,w.finishedAt),triggers=w.triggerCount,workflow=w.workflowId,object=w,kind="workflow"}end
 elseif self.view=="HISTORY"then
  for _,t in ipairs(HolyStorm.Tasks:GetHistory())do rows[#rows+1]={status=status(t.status),kind=L["KIND_TASK"],name=t.name,module=t.module,workflow=t.workflowId or"-",runtime=measured(t.duration),triggers=t.triggerCount,block=reason(t.lastError),object=t,objectKind="task"}end
  for _,w in ipairs(HolyStorm.Workflows:GetHistory())do rows[#rows+1]={status=status(w.status),kind=L["KIND_WORKFLOW"],name=w.name,module=w.module,workflow=w.workflowId,runtime=elapsed(w.startedAt,w.finishedAt),triggers=w.triggerCount,block=reason(w.lastError),object=w,objectKind="workflow"}end
 elseif self.view=="PERFORMANCE"then
  local taskMetrics=HolyStorm.Tasks:GetRuntimeMetrics();local workflowMetrics=HolyStorm.Workflows:GetRuntimeMetrics();local startup=HolyStorm.Tasks:GetStartupMetrics();local sync=HolyStorm.Sync and HolyStorm.Sync:GetRuntimeMetrics()or{};local syncDiagnostics=HolyStorm.Sync and HolyStorm.Sync:GetDiagnostics()or{};local scan=HolyStorm.CharacterScans and HolyStorm.CharacterScans:GetRuntimeMetrics()or{byBlock={}};local scanDiagnostics=HolyStorm.CharacterScans and HolyStorm.CharacterScans:GetDiagnostics()or{}
  local taskLive=HolyStorm.Tasks:GetLiveTasks();local activeTasks,waitingTasks=0,0;for _,t in ipairs(taskLive)do if t.status=="RUNNING"or t.status=="WAITING_ASYNC"then activeTasks=activeTasks+1 else waitingTasks=waitingTasks+1 end end
  local activeWorkflows=0;for _,w in ipairs(HolyStorm.Workflows:GetLive())do activeWorkflows=activeWorkflows+1 end
  local allIdle=HolyStorm.Tasks:IsIdle()and HolyStorm.Workflows:IsIdle()and(not HolyStorm.CharacterScans or HolyStorm.CharacterScans:IsIdle())and(not HolyStorm.Sync or(sync.queued or 0)==0 and not sync.active)
  local stateRow=metricRow(L["RUNTIME_STATE"],"Core",allIdle and L["RUNTIME_IDLE"]or L["RUNTIME_ACTIVE"]);stateRow.details=table.concat({L["ACTIVE_TASKS"]..": "..activeTasks,L["WAITING_TASKS"]..": "..waitingTasks,L["ACTIVE_WORKFLOWS"]..": "..activeWorkflows,L["SYNC_ACTIVITY"]..": "..(sync.active and L["RUNTIME_ACTIVE"]or L["RUNTIME_IDLE"]).." ("..(sync.queued or 0)..")"}, "\n");rows[#rows+1]=stateRow
  local schedulerRow=metricRow(L["SCHEDULER_METRICS"],"TaskManager","Runtime",{requested=taskMetrics.scheduler.wakeRequested,started=taskMetrics.scheduler.runs});schedulerRow.details=table.concat({L["SCHEDULER_WAKE_REQUESTED"]..": "..taskMetrics.scheduler.wakeRequested,L["SCHEDULER_RUNS"]..": "..taskMetrics.scheduler.runs,L["SCHEDULER_COALESCED"]..": "..taskMetrics.scheduler.coalescedWakes,L["SCHEDULER_BUDGET_EXHAUSTIONS"]..": "..taskMetrics.scheduler.budgetExhaustions,L["SCHEDULER_QUEUE_SCANS"]..": "..taskMetrics.scheduler.queueScans,L["SCHEDULER_QUEUE_CHECKS"]..": "..taskMetrics.scheduler.queueChecks,L["SCHEDULER_TASKS_SELECTED"]..": "..taskMetrics.scheduler.tasksSelected,L["SCHEDULER_IDLE_TRANSITIONS"]..": "..taskMetrics.scheduler.idleTransitions},"\n");rows[#rows+1]=schedulerRow
  local startupElapsed=startup.startedAt and math.max(0,(startup.backgroundReadyAt or(GetTime and GetTime())or startup.startedAt)-startup.startedAt)or 0
  local startupRow=metricRow(L["STARTUP_METRICS"],startup.reason or L["STARTUP_METRICS"],startup.active and L["RUNTIME_ACTIVE"]or L["RUNTIME_IDLE"],{requested=startup.tasksRequested,started=startup.tasksStarted,completed=startup.tasksCompleted,failed=startup.tasksFailed,cancelled=startup.tasksCancelled,retried=startup.taskRetries,triggers=startup.schedulerRuns});startupRow.details=table.concat({L["STARTUP_TASKS"]..": "..(startup.tasksRequested or 0).."/"..(startup.tasksStarted or 0).."/"..(startup.tasksCompleted or 0).."/"..(startup.tasksFailed or 0),L["STARTUP_WORKFLOWS"]..": "..(startup.workflowRequests or 0).."/"..(startup.workflowsStarted or 0).."/"..(startup.workflowsCompleted or 0).."/"..(startup.workflowsFailed or 0),L["STARTUP_SYNC"]..": "..(startup.syncJobsRequested or 0).."/"..(startup.syncJobsStarted or 0).."/"..(startup.syncJobsCompleted or 0).."/"..(startup.syncJobsFailed or 0),L["STARTUP_PRODUCERS"]..": "..(startup.producerScansRequested or 0).."/"..(startup.producerScansStarted or 0).."/"..(startup.producerScansCompleted or 0).."/"..(startup.producerScansFailed or 0).."/"..(startup.producerScanStartFailures or 0),L["STARTUP_SCHEDULER"]..": "..(startup.schedulerRuns or 0),L["STARTUP_UI_REFRESHES"]..": "..(startup.uiRefreshes or 0),L["STARTUP_PEAK_QUEUE"]..": "..(startup.peakQueue or 0),L["STARTUP_DURATION"]..": "..string.format("%.2fs",startupElapsed)},"\n");rows[#rows+1]=startupRow
  local syncRow=metricRow(L["SYNC_ACTIVITY"],"Sync",sync.active and L["RUNTIME_ACTIVE"]or L["RUNTIME_IDLE"],{requested=sync.requested,started=sync.started,completed=sync.completed,failed=sync.failed,retried=sync.retried});syncRow.details=table.concat({L["SYNC_QUEUED"]..": "..(sync.queued or 0),L["SYNC_ACTIVE"]..": "..tostring(sync.active),L["SYNC_DIAGNOSTIC_ACTIVITY_COUNT"]..": "..tostring(syncDiagnostics.activityCount or 0),L["SYNC_DIAGNOSTIC_ACTIVITY_IDS"]..": "..compactDiagnostic(syncDiagnostics.activeActivityIds),L["SYNC_DIAGNOSTIC_ACTIVE_TRANSFER"]..": "..compactDiagnostic(syncDiagnostics.activeTransfer),L["SYNC_DIAGNOSTIC_ACTIVE_REQUEST"]..": "..compactDiagnostic(syncDiagnostics.activeRequest),L["SYNC_DIAGNOSTIC_ACTIVE_CATCHUP_JOB"]..": "..compactDiagnostic(syncDiagnostics.activeCatchUpJob),L["SYNC_DIAGNOSTIC_TERMINAL_FETCH"]..": "..compactDiagnostic(syncDiagnostics.lastTerminalFetch),L["SYNC_DIAGNOSTIC_CATCHUP"]..": "..tostring(syncDiagnostics.catchUpQueueLength or syncDiagnostics.catchUpQueued or 0).." / "..compactDiagnostic(syncDiagnostics.queuedCatchUpJobs),L["SYNC_DIAGNOSTIC_ACTIVITY_DOMAIN_PHASE"]..": "..tostring(syncDiagnostics.activityDomain or "-").." / "..tostring(syncDiagnostics.activityPhase or "-"),L["SYNC_DIAGNOSTIC_ACTIVITY_AGE"]..": "..tostring(syncDiagnostics.activityAge or "-"),L["SYNC_DIAGNOSTIC_ACTIVITY_MISMATCH"]..": "..tostring(syncDiagnostics.activityStateMismatch==true),L["SYNC_DIAGNOSTIC_PENDING_PAYLOADS"]..": "..tostring(syncDiagnostics.pendingPayloads or 0),L["SYNC_DIAGNOSTIC_TRANSPORT"]..": "..compactDiagnostic(syncDiagnostics.transport),L["METRIC_REQUESTED"]..": "..(sync.requested or 0),L["METRIC_STARTED"]..": "..(sync.started or 0),L["METRIC_COMPLETED"]..": "..(sync.completed or 0),L["METRIC_FAILED"]..": "..(sync.failed or 0),L["METRIC_RETRIES"]..": "..(sync.retried or 0)},"\n");rows[#rows+1]=syncRow
  local taskRow=metricRow(L["ACTIVE_TASKS"],"TaskManager","Runtime");taskRow.details=L["ACTIVE_TASKS"]..": "..activeTasks.."\n"..L["WAITING_TASKS"]..": "..waitingTasks;rows[#rows+1]=taskRow
  local workflowsRow=metricRow(L["ACTIVE_WORKFLOWS"],"WorkflowEngine","Runtime");workflowsRow.details=L["ACTIVE_WORKFLOWS"]..": "..activeWorkflows;rows[#rows+1]=workflowsRow
  local moduleRows={}
  for module,counters in pairs(taskMetrics.tasks.byModule)do moduleRows[module]=moduleRows[module]or{};combineCounters(moduleRows[module],counters)end
  for module,counters in pairs(workflowMetrics.byModule)do moduleRows[module]=moduleRows[module]or{};combineCounters(moduleRows[module],counters)end
  for module,counters in pairs(moduleRows)do rows[#rows+1]=metricRow(L["MODULE_TOTAL"],module,"Aggregate",counters)end
  local triggerRows={}
  for trigger,counters in pairs(taskMetrics.tasks.byTrigger)do triggerRows[trigger]=triggerRows[trigger]or{};combineCounters(triggerRows[trigger],counters)end
  for trigger,counters in pairs(workflowMetrics.byTrigger)do triggerRows[trigger]=triggerRows[trigger]or{};combineCounters(triggerRows[trigger],counters)end
  for trigger,counters in pairs(triggerRows)do rows[#rows+1]=metricRow(L["TRIGGER_TOTAL"].." "..trigger,"-","Aggregate",counters)end
  local runtimeStates=scanDiagnostics.runtimeStates or{}
  local producerBlocks={"equipment","mythicPlus","raid","delves","stats"};for _,block in ipairs(producerBlocks)do if not scan.byBlock[block]then scan.byBlock[block]={requested=0,automatic=0,manual=0,started=0,logicalScans=0,completed=0,failed=0,failedAfterStart=0,startFailed=0,startFailure=0,admissionFailure=0,cancelled=0,retryCount=0,taskLifecycles=0,commits=0,noOpScans=0,lastDuration=0,totalDuration=0,maxDuration=0,lastLuaMs=0,totalLuaMs=0,maxLuaMs=0,maxTaskMs=0,lastQueueWait=0,totalQueueWait=0,maxQueueWait=0,triggers={}}end end
  for block,counters in pairs(scan.byBlock or{})do
   local key=string.lower(tostring(block));local label=L["PRODUCER_"..string.upper(block)]or block;local state=runtimeStates[block]or runtimeStates[key]or{}
   local producerRow=metricRow(L["PRODUCER_SCANS"].." "..label,"CharacterScan","Producer",{requested=counters.requested,automatic=counters.automatic,manual=counters.manual,started=counters.started,logicalScans=counters.logicalScans,taskLifecycles=counters.taskLifecycles,commits=counters.commits,noOpScans=counters.noOpScans,lastDuration=counters.lastDuration,totalScanDuration=counters.totalDuration,maxScanDuration=counters.maxDuration,lastLuaMs=counters.lastLuaMs,totalLuaMs=counters.totalLuaMs,maxLuaMs=counters.maxLuaMs,maxTaskMs=counters.maxTaskMs,lastQueueWait=counters.lastQueueWait,totalQueueWait=counters.totalQueueWait,maxQueueWait=counters.maxQueueWait,completed=counters.completed,failed=counters.failed,failedAfterStart=counters.failedAfterStart,startFailed=counters.startFailure or counters.startFailed,admissionFailure=counters.admissionFailure,cancelled=counters.cancelled,retryCount=counters.retryCount})
   producerRow.details=producerRow.details.."\n"..L["PRODUCER_LOGIN_SCANS"]..": "..(scan.loginProducerScans or 0).."\n"..L["PRODUCER_TRIGGERS"]..": "..flatten(counters.triggers).."\n"..L["PRODUCER_LAST_ERROR"]..": "..compactDiagnostic(state.lastError).."\n"..L["PRODUCER_FAILURE_STAGE"]..": "..compactDiagnostic(state.lastFailureStage).."\n"..L["PRODUCER_FAILURE_API"]..": "..compactDiagnostic(state.lastFailureAPI).."\n"..L["PRODUCER_FAILURE_DETAIL"]..": "..compactDiagnostic(state.lastFailureDetail)
   rows[#rows+1]=producerRow
   if next(state)then local runtimeRow=metricRow(L["PRODUCER_RUNTIME"]..": "..label,"CharacterScan",status(state.state));runtimeRow.details=table.concat({L["PRODUCER_STATE"]..": "..tostring(state.state or"-"),L["PRODUCER_REASON"]..": "..compactDiagnostic(state.reason),L["PRODUCER_LAST_ERROR"]..": "..compactDiagnostic(state.lastError),L["PRODUCER_FAILURE_STAGE"]..": "..compactDiagnostic(state.lastFailureStage),L["PRODUCER_FAILURE_API"]..": "..compactDiagnostic(state.lastFailureAPI),L["PRODUCER_FAILURE_DETAIL"]..": "..compactDiagnostic(state.lastFailureDetail),L["METRIC_RETRIES"]..": "..tostring(state.retryCount or 0)},"\n");rows[#rows+1]=runtimeRow end
  end
  local raidModule=HolyStorm.GetLoadedModuleById and HolyStorm:GetLoadedModuleById("raids")
  local raidSummary=raidModule and raidModule.GetScanPerformance and raidModule:GetScanPerformance()
  if raidSummary then
   local raidRow=metricRow(L["RAID_SCAN_PERFORMANCE"],"Raid",status(raidSummary.status),{runs=1,averageDuration=raidSummary.totalLuaMs/1000,maxDuration=raidSummary.maxSliceMs/1000})
   local function values(keys)local out={};for _,key in ipairs(keys)do out[#out+1]=key.."="..tostring(raidSummary[key]or 0)end;return table.concat(out,", ")end
   raidRow.object=raidSummary
   raidRow.details=table.concat({
    L["RAID_SCAN_TIME"]..": "..values({"totalWallMs","totalLuaMs","maxSliceMs"}),
    L["RAID_SCAN_WORK"]..": "..values({"slices","taskLifecycleCount","restarts"}),
    L["RAID_SCAN_APIS"]..": "..values({"catalogBuilds","ejCalls","statisticCalls","savedInstanceCalls"}),
    L["RAID_SCAN_EVENTS"]..": "..values({"followUpQueued","expectedInstanceInfoEvents","unexpectedRaidEvents"}),
   },"\n")
   rows[#rows+1]=raidRow
  end
  for id,p in pairs(HolyStorm.Tasks:GetPerformance())do rows[#rows+1]=metricRow(id,p.module,L["TASK_KIND"],p)end
  for id,p in pairs(HolyStorm.Workflows:GetPerformance())do rows[#rows+1]=metricRow(id,p.module,L["WORKFLOW_KIND"],p)end
 elseif self.view=="EVENT_MONITOR"then
  local metrics=HolyStorm.Events:GetRuntimeMetrics();for event,e in pairs(metrics.events)do rows[#rows+1]={event=event,count=e.count,lastSeen=stamp(e.lastSeen),tasksRequested=e.tasksRequested,tasksStarted=e.tasksStarted,workflowsRequested=e.workflowsRequested,workflowsStarted=e.workflowsStarted,details=table.concat({L["COL_COUNT"]..": "..e.count,L["COL_LAST_SEEN"]..": "..stamp(e.lastSeen),L["COL_TASK_REQUESTS"]..": "..e.tasksRequested,L["COL_TASKS_STARTED"]..": "..e.tasksStarted,L["COL_WORKFLOW_REQUESTS"]..": "..e.workflowsRequested,L["COL_WORKFLOWS_STARTED"]..": "..e.workflowsStarted},"\n"),kind="event",object=e}end
 end
 local search=string.lower(self.search:GetText()or"");local module=string.lower(self.moduleFilter:GetText()or"");local workflow=string.lower(self.workflowFilter:GetText()or"");local filtered={};for _,row in ipairs(rows)do if matches(row,search,module,workflow)then filtered[#filtered+1]=row end end
 local key=self.sortKey;if key then table.sort(filtered,function(a,b)local av,bv=a[key],b[key];if av==bv then return tostring(a.name or a.event or"")<tostring(b.name or b.event or"")end;if self.sortAscending then return tostring(av or"")<tostring(bv or"")else return tostring(av or"")>tostring(bv or"")end end)elseif self.view=="PERFORMANCE"then table.sort(filtered,function(a,b)return tostring(a.name)<tostring(b.name)end)elseif self.view=="EVENT_MONITOR"then table.sort(filtered,function(a,b)if a.count==b.count then return a.event<b.event end;return a.count>b.count end)end;return filtered
end
function Page:MoveColumn(key,direction)local layout=self:GetLayout(self.view);local defs=self:GetColumns();layout.order={};local index;for i,d in ipairs(defs)do layout.order[i]=d[1];if d[1]==key then index=i end end;if index then local target=math.max(1,math.min(#layout.order,index+direction));layout.order[index],layout.order[target]=layout.order[target],layout.order[index]end;self:Render()end
function Page:HeaderClick(key,button)if button=="RightButton"then self:GetLayout(self.view).hidden[key]=true;self:Render();return end;if IsShiftKeyDown()then self:MoveColumn(key,-1);return elseif IsControlKeyDown()then self:MoveColumn(key,1);return end;if self.sortKey==key then self.sortAscending=not self.sortAscending else self.sortKey,self.sortAscending=key,true end;self:RenderRows()end
function Page:BuildHeaders()
 for _,h in ipairs(self.headers)do h:Hide()end;local x=0;local layout=self:GetLayout(self.view)
 for _,d in ipairs(self:GetColumns())do if not layout.hidden[d[1]]then local h=self.headers[#self.visibleHeaders+1]or CreateFrame("Button",nil,self.header,"BackdropTemplate");self.headers[#self.visibleHeaders+1]=h;self.visibleHeaders[#self.visibleHeaders+1]=h;h:Show();h:ClearAllPoints();h:SetPoint("TOPLEFT",x,0);local width=layout.widths[d[1]]or d[3];h:SetSize(width,22);h:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8x8"});h:SetBackdropColor(.12,.12,.12,.95);h:RegisterForClicks("LeftButtonUp","RightButtonUp");h:SetScript("OnClick",function(_,button)Page:HeaderClick(d[1],button)end);h.text=h.text or h:CreateFontString(nil,"OVERLAY","GameFontNormalSmall");h.text:ClearAllPoints();h.text:SetPoint("LEFT",4,0);h.text:SetPoint("RIGHT",-7,0);h.text:SetText(L[d[2]]or d[2]);h.text:SetJustifyH("LEFT")
   h:SetScript("OnEnter",function(self)GameTooltip:SetOwner(self,"ANCHOR_TOP");GameTooltip:SetText(L["HEADER_HINT"]);GameTooltip:Show()end);h:SetScript("OnLeave",function()GameTooltip:Hide()end)
   local grip=h.grip or CreateFrame("Button",nil,h);h.grip=grip;grip:SetPoint("TOPRIGHT");grip:SetPoint("BOTTOMRIGHT");grip:SetWidth(6);grip:SetScript("OnMouseDown",function()grip.startX=GetCursorPosition()/UIParent:GetEffectiveScale();grip.startWidth=h:GetWidth();grip:SetScript("OnUpdate",function()local current=GetCursorPosition()/UIParent:GetEffectiveScale();layout.widths[d[1]]=math.max(40,grip.startWidth+current-grip.startX);h:SetWidth(layout.widths[d[1]])end)end);grip:SetScript("OnMouseUp",function()grip:SetScript("OnUpdate",nil);Page:Render()end);x=x+width+1 end end
 GameTooltip:Hide()
end
function Page:ShowDetails(row)
 if row and self.data then for _,current in ipairs(self.data)do if current.kind==row.kind and current.name==row.name and current.module==row.module and current.event==row.event then row=current;break end end end
 self.selected=row;local o=row and row.object;if not o then self.detail:SetText(L["NO_SELECTION"]);return end;local lines={L["DETAILS"]..": "..tostring(row.name or row.event or"-")};if row.details then lines[#lines+1]=row.details end
 for _,key in ipairs({"uniqueId","registryId","workflowId","workflowType","status","module","priority","currentTask","currentStep","blockReason","lastError","createdAt","startedAt","finishedAt","triggerCount","triggerCategory","triggerName","queueWait","duration","executionDuration","asyncWaitDuration","pendingRestart"})do if o[key]~=nil then local value=o[key];if key=="status"then value=status(value)elseif key=="blockReason"or key=="lastError"then value=reason(value)end;lines[#lines+1]=(L[fieldLabels[key]]or key)..": "..tostring(value)end end
 if o.triggerSources then lines[#lines+1]=L["TRIGGER_SOURCES"]..": "..flatten(o.triggerSources)end;if o.triggerHistory then lines[#lines+1]=L["TRIGGER_HISTORY"]..": "..flatten(o.triggerHistory)end;if o.conditions then lines[#lines+1]=L["CONDITIONS"]..": "..flatten(o.conditions)end;if o.dependencies then lines[#lines+1]=L["TASK_DEPENDENCIES"]..": "..flatten(o.dependencies)end;if o.executionMode then lines[#lines+1]=L["MERGE_MODE"]..": "..o.executionMode end;if o.retryCount then lines[#lines+1]=L["RETRIES"]..": "..o.retryCount.."/"..(o.maxRetries or 0)end;if o.taskOrder then lines[#lines+1]=L["TASK_ORDER"]..": "..flatten(o.taskOrder)end;if o.completedTasks then lines[#lines+1]=L["COMPLETED_TASKS"]..": "..flatten(o.completedTasks)end;if o.pendingTasks then lines[#lines+1]=L["PENDING_TASKS"]..": "..flatten(o.pendingTasks)end;if o.tasks then lines[#lines+1]=L["WORKFLOW_TASKS"]..": "..flatten(o.tasks)end;if o.metadata then lines[#lines+1]=L["METADATA"]..": "..flatten(o.metadata)end
 local correlation=o.workflowId or o.uniqueId;if correlation then local logs={};for _,e in ipairs(HolyStorm.Logger:GetHistory())do if e.correlationId==correlation or e.context and(e.context.taskId==o.uniqueId or e.context.workflowId==correlation)then logs[#logs+1]=string.format("[%s/%s] %s",e.level,e.source,e.message)end end;if#logs>0 then lines[#lines+1]=L["LOGS"]..":";for i=math.max(1,#logs-5),#logs do lines[#lines+1]=logs[i]end end end;self.detail:SetText(table.concat(lines,"\n"))
end
function Page:RenderRows(rebuildData)
 if self.paintingRows then return end
 self.paintingRows=true
 if rebuildData~=false then self.data=self:BuildData()end
 local data=self.data or{}
 for _,r in ipairs(self.rows)do r:Hide()end
 local defs=self:GetColumns()
 local layout=self:GetLayout(self.view)
 local totalHeight=math.max(1,#data*ROW_HEIGHT)
 self.rowContent:SetHeight(totalHeight)
 if#data==0 then self.empty:Show()else self.empty:Hide()end
 local scrollOffset=self.scroll and self.scroll:GetVerticalScroll()or 0
 local viewportHeight=self.scroll and self.scroll:GetHeight()or 300
 local maxScroll=math.max(0,totalHeight-viewportHeight)
 scrollOffset=math.max(0,math.min(scrollOffset,maxScroll))
 local firstIndex=math.floor(scrollOffset/ROW_HEIGHT)+1
 local visibleCount=math.min(MAX_VISIBLE_ROWS,math.ceil(viewportHeight/ROW_HEIGHT)+2)
 for slot=1,visibleCount do
  local dataIndex=firstIndex+slot-1
  local row=data[dataIndex]
  if not row then break end
  local r=self.rows[slot]
  if not r then
   r=CreateFrame("Button",nil,self.rowContent)
   r:SetHeight(ROW_HEIGHT)
   r.cells={}
   r.highlight=r:CreateTexture(nil,"BACKGROUND")
   r.highlight:SetAllPoints()
   r.highlight:SetColorTexture(.15,.35,.5,.22)
   r:SetHighlightTexture(r.highlight)
   self.rows[slot]=r
  end
  r:Show()
  r:ClearAllPoints()
  r:SetPoint("TOPLEFT",0,-((dataIndex-1)*ROW_HEIGHT))
  r:SetPoint("RIGHT",self.rowContent,"RIGHT")
  r:SetScript("OnClick",function()Page:ShowDetails(row)end)
  local x,cellIndex=0,0
  for _,d in ipairs(defs)do
   if not layout.hidden[d[1]]then
    cellIndex=cellIndex+1
    local cell=r.cells[cellIndex]or r:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    r.cells[cellIndex]=cell
    cell:Show()
    cell:ClearAllPoints()
    local width=layout.widths[d[1]]or d[3]
    cell:SetPoint("TOPLEFT",x+4,-3)
    cell:SetWidth(width-8)
    cell:SetJustifyH("LEFT")
    cell:SetWordWrap(false)
    cell:SetText(tostring(row[d[1]]or"-"))
    x=x+width+1
   end
  end
  for n=cellIndex+1,#r.cells do r.cells[n]:Hide()end
 end
 if rebuildData~=false then self:ShowDetails(self.selected)end
 self.paintingRows=false
end
function Page:RequestRefresh()
 if not self.page or not self.page:IsShown()then return end
 if self.refreshPending then return end
 self.refreshPending=true
 self.refreshElapsed=0
 self.page:SetScript("OnUpdate",function(frame,delta)
  Page.refreshElapsed=Page.refreshElapsed+delta
  if Page.refreshElapsed<REFRESH_DELAY then return end
  frame:SetScript("OnUpdate",nil)
  Page.refreshPending=false
  HolyStorm.UI:MarkDirty("taskManager")
 end)
end
function Page:Render()if not self.page:IsShown()or not HolyStorm.Policy:Can("taskmanager-view")and not HolyStorm.Policy:Can("tasks-view")then return end;self.visibleHeaders={};self:BuildHeaders();self:RenderRows();self.pause:SetText(HolyStorm.Tasks:IsPaused()and L["RESUME"]or L["PAUSE"])
end
function Page:SelectView(view)self.view=view;HolyStorm.UI.runtimeEventMonitorVisible=view=="EVENT_MONITOR"and self.page:IsShown();self.selected=nil;if self.scroll then self.scroll:SetVerticalScroll(0)end;for key,b in pairs(self.tabs)do b:SetEnabled(key~=view)end;self:Render()end
local function button(parent,text,width,point,callback)local b=CreateFrame("Button",nil,parent,"UIPanelButtonTemplate");b:SetSize(width,23);b:SetPoint(unpack(point));b:SetText(text);b:SetScript("OnClick",callback);return b end
function Page:OnInitialize()
 local UI=HolyStorm:GetModule("UI",true);local p=CreateFrame("Frame",nil,UI.content);self.page=p;self.view="LIVE_TASKS";self.headers,self.rows,self.tabs={}, {}, {}
 local searchLabel=p:CreateFontString(nil,"OVERLAY","GameFontNormalSmall");searchLabel:SetPoint("TOPLEFT",14,-10);searchLabel:SetText(L["SEARCH"]);local search=CreateFrame("EditBox",nil,p,"InputBoxTemplate");search:SetSize(155,22);search:SetPoint("TOPLEFT",14,-28);search:SetAutoFocus(false);search:SetScript("OnTextChanged",function()Page:RenderRows()end);self.search=search
 local moduleLabel=p:CreateFontString(nil,"OVERLAY","GameFontNormalSmall");moduleLabel:SetPoint("TOPLEFT",180,-10);moduleLabel:SetText(L["MODULE_FILTER"]);local module=CreateFrame("EditBox",nil,p,"InputBoxTemplate");module:SetSize(110,22);module:SetPoint("TOPLEFT",180,-28);module:SetAutoFocus(false);module:SetScript("OnTextChanged",function()Page:RenderRows()end);self.moduleFilter=module
 local workflowLabel=p:CreateFontString(nil,"OVERLAY","GameFontNormalSmall");workflowLabel:SetPoint("TOPLEFT",305,-10);workflowLabel:SetText(L["WORKFLOW_FILTER"]);local workflow=CreateFrame("EditBox",nil,p,"InputBoxTemplate");workflow:SetSize(110,22);workflow:SetPoint("TOPLEFT",305,-28);workflow:SetAutoFocus(false);workflow:SetScript("OnTextChanged",function()Page:RenderRows()end);self.workflowFilter=workflow
 button(p,L["RESET_COLUMNS"],130,{"TOPLEFT",430,-27},function()HolyStorm.Database:Set("taskManager.columns."..Page.view,nil,"profile");Page:Render()end)
 for index,view in ipairs(views)do local x=14+((index-1)%4)*150;local y=-58-math.floor((index-1)/4)*26;local b=button(p,L[view],145,{"TOPLEFT",x,y},function()Page:SelectView(view)end);self.tabs[view]=b end
 local header=CreateFrame("Frame",nil,p);header:SetPoint("TOPLEFT",14,-114);header:SetPoint("TOPRIGHT",-28,-114);header:SetHeight(22);self.header=header
 local scroll=CreateFrame("ScrollFrame",nil,p,"UIPanelScrollFrameTemplate");scroll:SetPoint("TOPLEFT",header,"BOTTOMLEFT",0,-2);scroll:SetPoint("BOTTOMRIGHT",p,"BOTTOMRIGHT",-30,204);local content=CreateFrame("Frame",nil,scroll);content:SetSize(1,1);scroll:SetScrollChild(content);scroll:HookScript("OnSizeChanged",function(s)content:SetWidth(s:GetWidth());Page:RenderRows(false)end);scroll:HookScript("OnVerticalScroll",function()Page:RenderRows(false)end);self.scroll,self.rowContent=scroll,content
 local empty=p:CreateFontString(nil,"OVERLAY","GameFontHighlight");empty:SetPoint("TOPLEFT",scroll,12,-12);empty:SetText(L["EMPTY"]);self.empty=empty
 local detail=p:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");detail:SetPoint("TOPLEFT",14,-398);detail:SetPoint("BOTTOMRIGHT",-22,73);detail:SetJustifyH("LEFT");detail:SetJustifyV("TOP");detail:SetText(L["NO_SELECTION"]);self.detail=detail
 self.pause=button(p,L["PAUSE"],120,{"BOTTOMLEFT",14,18},function()if not HolyStorm.Policy:Can("taskmanager-control")then return end;if HolyStorm.Tasks:IsPaused()then HolyStorm.Tasks:Resume()else HolyStorm.Tasks:Pause()end;Page:Render()end)
 button(p,L["CANCEL_WORKFLOW"],160,{"BOTTOMLEFT",140,18},function()local o=Page.selected and Page.selected.object;if o and(o.workflowId or o.workflowType)then Page.pendingWorkflow=o.workflowType and o.workflowId or o.workflowId;StaticPopup_Show("HOLYSTORM_CANCEL_WORKFLOW")end end)
 button(p,L["RESTART_WORKFLOW"],160,{"BOTTOMLEFT",306,18},function()if not HolyStorm.Policy:Can("taskmanager-control")then return end;local o=Page.selected and Page.selected.object;local id=o and(o.workflowType and o.workflowId or o.workflowId);if id then HolyStorm.Workflows:Restart(id)end end)
 button(p,L["CLEAR_RESTART"],190,{"BOTTOMLEFT",14,45},function()if not HolyStorm.Policy:Can("taskmanager-control")then return end;local o=Page.selected and Page.selected.object;local id=o and(o.workflowType and o.workflowId or o.workflowId);if id then HolyStorm.Workflows:ClearPendingRestart(id)end end)
 button(p,L["CLEAR_QUEUE"],140,{"BOTTOMLEFT",210,45},function()StaticPopup_Show("HOLYSTORM_CLEAR_TASK_QUEUE")end)
 button(p,L["RESET_RUNTIME_METRICS"],180,{"BOTTOMRIGHT",-14,18},function()if not HolyStorm.Policy:Can("tasks-view")and not HolyStorm.Policy:Can("taskmanager-view")then return end;HolyStorm.Tasks:ResetRuntimeMetrics();Page:Render()end)
 StaticPopupDialogs["HOLYSTORM_CLEAR_TASK_QUEUE"]={text=L["CONFIRM_CLEAR_QUEUE"],button1=L["YES"],button2=L["NO"],OnAccept=function()if HolyStorm.Policy:Can("taskmanager-control")then HolyStorm.Tasks:ClearQueue()end end,timeout=0,whileDead=true,hideOnEscape=true,preferredIndex=3}
 StaticPopupDialogs["HOLYSTORM_CANCEL_WORKFLOW"]={text=L["CONFIRM_CANCEL_WORKFLOW"],button1=L["YES"],button2=L["NO"],OnAccept=function()if Page.pendingWorkflow and HolyStorm.Policy:Can("taskmanager-control")then HolyStorm.Workflows:Cancel(Page.pendingWorkflow,"MANUAL_CANCEL")end;Page.pendingWorkflow=nil end,timeout=0,whileDead=true,hideOnEscape=true,preferredIndex=3}
 HolyStorm.UI:RegisterPage("taskManager",p,L["WINDOW_TITLE"],function()Page:Render()end)
 for _,event in ipairs(refreshEvents)do HolyStorm.Events:Register(event,"ui:taskManager:coalesced",function()Page:RequestRefresh()end)end
 HolyStorm.UI:AddNavigation("taskManager",13,"Interface\\Icons\\INV_Engineering_90_Circuitry",L["DISPLAY_NAME"],L["DESCRIPTION"],function()HolyStorm.UI:ShowPage("taskManager")end);p:HookScript("OnSizeChanged",function(_,_,height)detail:ClearAllPoints();detail:SetPoint("TOPLEFT",14,-(height-162));detail:SetPoint("BOTTOMRIGHT",-22,73)end);p:HookScript("OnShow",function()HolyStorm.UI.runtimeEventMonitorVisible=Page.view=="EVENT_MONITOR"end);p:HookScript("OnHide",function(frame)HolyStorm.UI.runtimeEventMonitorVisible=false;frame:SetScript("OnUpdate",nil);Page.refreshPending=false end)
end
