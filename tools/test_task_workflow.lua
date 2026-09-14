-- Offline contract tests for the Holy Storm scheduler. Run with: lua tools/test_task_workflow.lua
local root=(arg[0]:gsub("tools[/\\]test_task_workflow.lua$","")).."LIVE/Holy_Storm/"
local monotonic,epoch=0,100000
function GetTime()return monotonic end
function time()return epoch+math.floor(monotonic)end
function InCombatLockdown()return false end
local timers={}
C_Timer={NewTimer=function(delay,callback)local t={cancelled=false,due=monotonic+delay,callback=callback};function t:Cancel()self.cancelled=true end;timers[#timers+1]=t;return t end,NewTicker=function(_,callback)local t={callback=callback};function t:Cancel()self.cancelled=true end;return t end}
local HolyStorm={db={profile={taskManager={}}}}
function HolyStorm:GetAddon()return self end
function HolyStorm:GetLocale()return setmetatable({TASK_GENERIC="Task: %s"},{__index=function(_,key)return key end})end
HolyStorm.Utils={}
function HolyStorm.Utils.DeepCopy(value,seen)if type(value)~="table"then return value end;seen=seen or{};if seen[value]then return seen[value]end;local out={};seen[value]=out;for k,v in pairs(value)do out[HolyStorm.Utils.DeepCopy(k,seen)]=HolyStorm.Utils.DeepCopy(v,seen)end;return out end
function HolyStorm.Utils.Now()return time()end
function HolyStorm.Utils.SafeCall(_,fn,...)local args={...};return xpcall(function()return fn(table.unpack(args))end,function(e)return e end)end
HolyStorm.Events={listeners={}}
function HolyStorm.Events:Register(event,owner,callback)self.listeners[event]=self.listeners[event]or{};self.listeners[event][owner]=callback end
function HolyStorm.Events:Emit(event,...)for _,callback in pairs(self.listeners[event]or{})do callback(event,...)end end
HolyStorm.Logger={history={}}
function HolyStorm.Logger:Write(level,source,category,message,context,correlationId)self.history[#self.history+1]={level=level,source=source,category=category,message=message,context=context,correlationId=correlationId}end
HolyStorm.State={values={playerLoggedIn=true,playerReady=true,guildAvailable=true}}
function HolyStorm.State:Is(key)return self.values[key]==true end
function HolyStorm.State:Get(key)return self.values[key]end
function LibStub()return HolyStorm end
assert(loadfile(root.."Core/TaskManager.lua"))()
assert(loadfile(root.."Core/WorkflowManager.lua"))()
HolyStorm.Tasks:Initialize();HolyStorm.Workflows:Initialize()
local function processAll(limit)for _=1,limit or 100 do if#HolyStorm.Tasks.queue==0 and not HolyStorm.Tasks.runningTaskId then return end;HolyStorm.Tasks.timer,HolyStorm.Tasks.timerDue=nil,nil;HolyStorm.Tasks:Process();local earliest;for _,task in ipairs(HolyStorm.Tasks.queue)do if task.blockReason=="DEBOUNCE"then earliest=earliest and math.min(earliest,task.notBefore)or task.notBefore end end;if earliest and earliest>monotonic then monotonic=earliest end end;local pending={};for _,task in ipairs(HolyStorm.Tasks.queue)do local dep=task.dependencies and task.dependencies[1];pending[#pending+1]=task.registryId..":"..tostring(task.blockReason).." dep="..tostring(dep).." depStatus="..tostring(dep and HolyStorm.Tasks.tasks[dep]and HolyStorm.Tasks.tasks[dep].status)end;error("scheduler did not drain: "..table.concat(pending,","))end

assert(HolyStorm.Tasks:RegisterTaskType("Test.Unique",{execute=function()return true end,executionMode="UNIQUE"}))
local a=HolyStorm.Tasks:Queue("Test.Unique",{triggerSource="A"});local b,state=HolyStorm.Tasks:Queue("Test.Unique",{triggerSource="B"});assert(a==b and state=="MERGED"and HolyStorm.Tasks.tasks[a].triggerCount==2);processAll()
assert(HolyStorm.Tasks:RegisterTaskType("Test.Multi",{execute=function()return true end,executionMode="MULTI"}));local m1=HolyStorm.Tasks:Queue("Test.Multi");local m2=HolyStorm.Tasks:Queue("Test.Multi");assert(m1~=m2);processAll()
assert(HolyStorm.Tasks:RegisterTaskType("Test.Key",{execute=function()return true end,executionMode="MERGE_BY_KEY"}));local k1=HolyStorm.Tasks:Queue("Test.Key",{mergeKey=15});local k2=HolyStorm.Tasks:Queue("Test.Key",{mergeKey=15});local k3=HolyStorm.Tasks:Queue("Test.Key",{mergeKey=22});assert(k1==k2 and k1~=k3);processAll()
local order={};HolyStorm.Tasks:RegisterTaskType("Test.Low",{priority=75,execute=function()order[#order+1]="low"end});HolyStorm.Tasks:RegisterTaskType("Test.High",{priority=10,execute=function()order[#order+1]="high"end});HolyStorm.Tasks:Queue("Test.Low");HolyStorm.Tasks:Queue("Test.High");processAll();assert(order[1]=="high"and order[2]=="low")
HolyStorm.State.values.playerReady=false;HolyStorm.Tasks:RegisterTaskType("Test.Blocked",{conditions={"PLAYER_READY"},priority=0,execute=function()error("must remain blocked")end});HolyStorm.Tasks:RegisterTaskType("Test.Runnable",{priority=50,execute=function()order[#order+1]="runnable"end});local blocked=HolyStorm.Tasks:Queue("Test.Blocked");HolyStorm.Tasks:Queue("Test.Runnable");HolyStorm.Tasks.timer=nil;HolyStorm.Tasks:Process();assert(HolyStorm.Tasks.tasks[blocked].status=="BLOCKED"and order[#order]=="runnable");HolyStorm.Tasks:Cancel(blocked);HolyStorm.State.values.playerReady=true
local dep=HolyStorm.Tasks:Queue("Test.Unique");local dependent=HolyStorm.Tasks:Queue("Test.Multi",{dependencies={dep}});processAll();assert(HolyStorm.Tasks.tasks[dependent].status=="COMPLETED")
HolyStorm.Tasks:RegisterTaskType("Test.Error",{execute=function()error("isolated")end});local failure=HolyStorm.Tasks:Queue("Test.Error");HolyStorm.Tasks:Queue("Test.Unique");processAll();assert(HolyStorm.Tasks.tasks[failure].status=="FAILED")
HolyStorm.Tasks:RegisterTaskType("Test.Async",{execute=function()return HolyStorm.Tasks.ASYNC end});local async=HolyStorm.Tasks:Queue("Test.Async");HolyStorm.Tasks.timer=nil;HolyStorm.Tasks:Process();assert(HolyStorm.Tasks.tasks[async].status=="WAITING_ASYNC");assert(HolyStorm.Tasks:Complete(async,true,{ready=true}))
HolyStorm.Tasks:Pause();local paused=HolyStorm.Tasks:Queue("Test.Multi");HolyStorm.Tasks:Process();assert(HolyStorm.Tasks.tasks[paused].status=="QUEUED");HolyStorm.Tasks:Resume();processAll()
local requested=false;HolyStorm.Tasks:RegisterTaskType("WF.One",{executionMode="MULTI",execute=function(task)if not requested then requested=true;HolyStorm.Workflows:Request("TEST_WORKFLOW",{triggerSource="DURING_RUN"})end;return 1 end});HolyStorm.Tasks:RegisterTaskType("WF.Two",{executionMode="MULTI",execute=function()return 2 end});assert(HolyStorm.Workflows:Register("TEST_WORKFLOW",{allowParallel=false,steps={{id="one",taskType="WF.One"},{id="two",taskType="WF.Two"}}}));local wf=HolyStorm.Workflows:Request("TEST_WORKFLOW",{triggerSource="TEST"});processAll();assert(HolyStorm.Workflows.workflows[wf].status=="COMPLETED"and#HolyStorm.Workflows.history==2)
local retries=0;HolyStorm.Tasks:RegisterTaskType("WF.Retry",{executionMode="MULTI",execute=function()retries=retries+1;if retries==1 then return{workflowAction="RETRY",gotoStep=1,delay=.1,maxRetries=2}end;return true end});HolyStorm.Workflows:Register("RETRY_WORKFLOW",{steps={{id="retry",taskType="WF.Retry"}}});local retryWorkflow=HolyStorm.Workflows:Request("RETRY_WORKFLOW");processAll();assert(retries==2 and HolyStorm.Workflows.workflows[retryWorkflow].status=="COMPLETED")
local skipped=false;HolyStorm.Tasks:RegisterTaskType("WF.Fail",{executionMode="MULTI",execute=function()error("expected")end});HolyStorm.Tasks:RegisterTaskType("WF.After",{executionMode="MULTI",execute=function()skipped=true end});HolyStorm.Workflows:Register("SKIP_WORKFLOW",{steps={{id="fail",taskType="WF.Fail",failurePolicy="SKIP"},{id="after",taskType="WF.After"}}});local skipWorkflow=HolyStorm.Workflows:Request("SKIP_WORKFLOW");processAll();assert(skipped and HolyStorm.Workflows.workflows[skipWorkflow].status=="COMPLETED")
print("Task/workflow tests passed")
