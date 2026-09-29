local addonVersion="2.1.0"
local HolyStorm=LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local L=LibStub("AceLocale-3.0"):GetLocale("Holy_Storm")
local Snapshots={version=addonVersion,registered={}}

-- DE: Kompatibilitaetsadapter fuer bestehende Module. Snapshot-Ablaeufe besitzen
-- keine eigene Queue mehr, sondern werden als drei echte Workflow-Tasks registriert.
-- EN: Compatibility adapter for existing modules. Snapshot flows no longer own a
-- queue; they are registered as three real workflow tasks.
function Snapshots:Fingerprint(value)return HolyStorm.PlayerData:FingerprintSnapshot(value)end
local function context(task)local w=HolyStorm.Workflows.workflows[task.workflowId];return w and w.context end
function Snapshots:Register(id)
 if self.registered[id]then return true end;local prefix="Snapshot."..id
 HolyStorm.Tasks:RegisterTaskType(prefix..".Scan",{name=string.format(L["TASK_SNAPSHOT_SCAN"],id),localizedNameKey="TASK_SNAPSHOT_SCAN",module=id,priority=50,executionMode="MULTI",execute=function(task)local c=context(task);if not c then error("missing workflow context")end;local result=c.data.scanner();if type(result)=="table"and result.workflowAction then return result end;return{snapshot=result}end})
 HolyStorm.Tasks:RegisterTaskType(prefix..".Validate",{name=string.format(L["TASK_SNAPSHOT_VALIDATE"],id),localizedNameKey="TASK_SNAPSHOT_VALIDATE",module=id,priority=50,executionMode="MULTI",execute=function(task)local c=context(task);local scan=c and c.results.scan;if not c or not c.data or type(scan)~="table"then error("missing scan result")end;local valid,reason=c.data.validator(scan.snapshot);if not valid then return{workflowAction="RETRY",gotoStep=1,delay=c.data.options.retryDelay or 2.5,maxRetries=c.data.options.maxRetries or 3,reason=reason or"INVALID_SNAPSHOT"}end;local fp=Snapshots:Fingerprint(scan.snapshot);if not fp then error("snapshot fingerprint failed")end;c.data.fingerprint=fp;return{valid=true,status="VALID"}end})
 HolyStorm.Tasks:RegisterTaskType(prefix..".Commit",{name=string.format(L["TASK_SNAPSHOT_COMMIT"],id),localizedNameKey="TASK_SNAPSHOT_COMMIT",module=id,priority=50,executionMode="MULTI",execute=function(task)local c=context(task);local scan=c and c.results.scan;if not c or not c.data or type(scan)~="table"then error("missing validated scan result")end;local committed,reason=c.data.commit(scan.snapshot,c.data.fingerprint);if type(committed)=="table"and committed.workflowAction then return committed end;if committed==false then if reason=="UNCHANGED"then return{workflowAction="COMPLETE",unchanged=true,status="UNCHANGED"}end;error("snapshot commit failed: "..tostring(reason or"UNKNOWN"))end;return{committed=true,status="COMMITTED"}end})
 HolyStorm.Workflows:Register("SNAPSHOT_"..string.upper(id),{name=string.format(L["WORKFLOW_SNAPSHOT"],id),localizedNameKey="WORKFLOW_SNAPSHOT",module=id,priority=50,allowParallel=false,steps={{id="scan",taskType=prefix..".Scan"},{id="validate",taskType=prefix..".Validate"},{id="commit",taskType=prefix..".Commit"}}})
 self.registered[id]=true;return true
end
function Snapshots:Queue(id,scanner,validator,commit,options)
 if type(id)~="string"or type(scanner)~="function"or type(validator)~="function"or type(commit)~="function"then return false end;options=options or{};self:Register(id)
local function startupActive() return HolyStorm.Tasks and type(HolyStorm.Tasks.IsStartupActive)=="function" and HolyStorm.Tasks:IsStartupActive() or false end
 local workflowId=HolyStorm.Workflows:Request("SNAPSHOT_"..string.upper(id),{priority=options.priority or 50,debounce=options.delay or options.debounce or 1,startupPhase=options.startupPhase or(startupActive() and 3 or nil),triggerSource=options.triggerSource or(HolyStorm.Events and HolyStorm.Events.currentEvent)or options.source or id,context={scanner=scanner,validator=validator,commit=commit,options=options}});return workflowId~=nil,workflowId
end
function Snapshots:Cancel(id)local workflowId=HolyStorm.Workflows.activeByType["SNAPSHOT_"..string.upper(tostring(id))];return workflowId and HolyStorm.Workflows:Cancel(workflowId,"MODULE_DISABLED")or false end
HolyStorm.Snapshots=Snapshots
