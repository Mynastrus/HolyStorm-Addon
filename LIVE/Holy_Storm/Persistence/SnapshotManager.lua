local addonVersion="2.0.1"
local HolyStorm=LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local L=LibStub("AceLocale-3.0"):GetLocale("Holy_Storm")
local Snapshots={version=addonVersion,registered={},fingerprints={}}

-- DE: Kompatibilitaetsadapter fuer bestehende Module. Snapshot-Ablaeufe besitzen
-- keine eigene Queue mehr, sondern werden als drei echte Workflow-Tasks registriert.
-- EN: Compatibility adapter for existing modules. Snapshot flows no longer own a
-- queue; they are registered as three real workflow tasks.
function Snapshots:Fingerprint(value)local c=HolyStorm.Utils.DeepCopy(value);if type(c)=="table"then c.updatedAt=nil;c.version=nil;c.snapshotVersion=nil end;return HolyStorm.Serializer:Serialize(c)end
local function context(task)local w=HolyStorm.Workflows.workflows[task.workflowId];return w and w.context end
function Snapshots:Register(id)
 if self.registered[id]then return true end;local prefix="Snapshot."..id
 HolyStorm.Tasks:RegisterTaskType(prefix..".Scan",{name=string.format(L["TASK_SNAPSHOT_SCAN"],id),localizedNameKey="TASK_SNAPSHOT_SCAN",module=id,priority=50,executionMode="MULTI",execute=function(task)local c=context(task);if not c then error("missing workflow context")end;return{snapshot=c.data.scanner()}end})
 HolyStorm.Tasks:RegisterTaskType(prefix..".Validate",{name=string.format(L["TASK_SNAPSHOT_VALIDATE"],id),localizedNameKey="TASK_SNAPSHOT_VALIDATE",module=id,priority=50,executionMode="MULTI",execute=function(task)local c=context(task);local scan=c and c.results.scan;local valid,reason=c.data.validator(scan and scan.snapshot);if not valid then return{workflowAction="RETRY",gotoStep=1,delay=c.data.options.retryDelay or 2.5,maxRetries=c.data.options.maxRetries or 3,reason=reason}end;local fp=Snapshots:Fingerprint(scan.snapshot);if not fp then error("snapshot fingerprint failed")end;if Snapshots.fingerprints[id]==fp then return{workflowAction="COMPLETE",unchanged=true}end;c.data.fingerprint=fp;return{valid=true}end})
 HolyStorm.Tasks:RegisterTaskType(prefix..".Commit",{name=string.format(L["TASK_SNAPSHOT_COMMIT"],id),localizedNameKey="TASK_SNAPSHOT_COMMIT",module=id,priority=50,executionMode="MULTI",execute=function(task)local c=context(task);local scan=c and c.results.scan;local committed=c.data.commit(scan.snapshot,c.data.fingerprint);if committed~=false then Snapshots.fingerprints[id]=c.data.fingerprint end;return{committed=committed~=false}end})
 HolyStorm.Workflows:Register("SNAPSHOT_"..string.upper(id),{name=string.format(L["WORKFLOW_SNAPSHOT"],id),localizedNameKey="WORKFLOW_SNAPSHOT",module=id,priority=50,allowParallel=false,steps={{id="scan",taskType=prefix..".Scan"},{id="validate",taskType=prefix..".Validate"},{id="commit",taskType=prefix..".Commit"}}})
 self.registered[id]=true;return true
end
function Snapshots:Queue(id,scanner,validator,commit,options)
 if type(id)~="string"or type(scanner)~="function"or type(validator)~="function"or type(commit)~="function"then return false end;options=options or{};self:Register(id)
local function startupActive() return HolyStorm.Tasks and type(HolyStorm.Tasks.IsStartupActive)=="function" and HolyStorm.Tasks:IsStartupActive() or false end
local function startupPhase(id)
	if id=="equipment" or id=="raids" then return 2 end
	if id=="mythicplus" or id=="stats" or id=="delves" or id=="professions" then return 3 end
	return 4
end
 local workflowId=HolyStorm.Workflows:Request("SNAPSHOT_"..string.upper(id),{priority=options.priority or 50,debounce=options.delay or options.debounce or 1,startupPhase=options.startupPhase or(startupActive() and startupPhase(id)or nil),triggerSource=options.triggerSource or(HolyStorm.Events and HolyStorm.Events.currentEvent)or options.source or id,context={scanner=scanner,validator=validator,commit=commit,options=HolyStorm.Utils.DeepCopy(options)}});return workflowId~=nil,workflowId
end
function Snapshots:Cancel(id)local workflowId=HolyStorm.Workflows.activeByType["SNAPSHOT_"..string.upper(tostring(id))];return workflowId and HolyStorm.Workflows:Cancel(workflowId,"MODULE_DISABLED")or false end
HolyStorm.Snapshots=Snapshots
