local root=(arg[0]:gsub("tools[/\\]test_startup_storm.lua$","")).."LIVE/Holy_Storm/"
local mono,wall=0,1000
local function copy(value,seen)if type(value)~="table"then return value end;seen=seen or{};if seen[value]then return seen[value]end;local out={};seen[value]=out;for key,child in pairs(value)do out[copy(key,seen)]=copy(child)end;return out end
local HolyStorm={db={profile={}},Utils={},Events={},State={},Logger={rows={}}}
function LibStub(name)
	if name=="AceLocale-3.0" then
		return {GetLocale=function()return setmetatable({},{__index=function(_,key)return key end})end}
	end
	return {GetAddon=function()return HolyStorm end}
end
function GetTime()return mono end
function HolyStorm.Utils.Now()wall=wall+1;return wall end
function HolyStorm.Utils.DeepCopy(value)return copy(value)end
function HolyStorm.Utils.SafeCall(_,fn,...)local result={pcall(fn,...)};local ok=table.remove(result,1);return ok,table.unpack(result)end
function HolyStorm.Logger:Write(...)self.rows[#self.rows+1]={...}end
function HolyStorm.Events:Register()end
function HolyStorm.Events:Emit()end
function HolyStorm.State:Is()return true end
function HolyStorm.State:Get()return true end
C_Timer={NewTimer=function(_,callback)return{Cancel=function()end,callback=callback}end}
assert(loadfile(root.."Core/Tasks/TaskManager.lua"))()
local Tasks=HolyStorm.Tasks;Tasks:Initialize();Tasks:BeginStartup("RELOAD")
local runs={identity=0,guild=0,policy=0,twink=0,sync=0,position=0};local function register(id,phase,dependencies,fn)Tasks:RegisterTaskType(id,{executionMode="UNIQUE",execute=fn,priority=phase})end
register("startup.identity",1,nil,function()runs.identity=runs.identity+1;return true end)
register("startup.guild",2,{"startup.identity"},function()runs.guild=runs.guild+1;return true end)
register("startup.policy",3,{"startup.guild"},function()runs.policy=runs.policy+1;return true end)
register("startup.twink",3,{"startup.policy"},function()runs.twink=runs.twink+1;return true end)
register("startup.sync",4,{"startup.policy"},function()runs.sync=runs.sync+1;return true end)
register("startup.position",4,{"startup.sync"},function()runs.position=runs.position+1;return true end)
local identity=Tasks:Queue("startup.identity",{startupPhase=1,triggerSource="PLAYER_LOGIN"})
for index=1,100 do local id,status=Tasks:Queue("startup.identity",{startupPhase=1,triggerSource="IDENTITY_"..index});assert(id==identity and status=="MERGED")end
local guild=Tasks:Queue("startup.guild",{startupPhase=2,dependencies={"startup.identity"},triggerSource="GUILD_ROSTER_UPDATE"})
for index=1,100 do local id,status=Tasks:Queue("startup.guild",{startupPhase=2,dependencies={"startup.identity"},triggerSource="ROSTER_"..index});assert(id==guild and status=="MERGED")end
local policy=Tasks:Queue("startup.policy",{startupPhase=3,dependencies={"startup.guild"},triggerSource="POLICY"})
local twink=Tasks:Queue("startup.twink",{startupPhase=3,dependencies={"startup.policy"},triggerSource="TWINK"})
local sync=Tasks:Queue("startup.sync",{startupPhase=4,dependencies={"startup.policy"},triggerSource="SYNC_READY"})
local position=Tasks:Queue("startup.position",{startupPhase=4,dependencies={"startup.sync"},triggerSource="POSITION_UPDATE"})
for index=1,100 do local id,status=Tasks:Queue("startup.sync",{startupPhase=4,dependencies={"startup.policy"},triggerSource="SYNC_"..index});assert(id==sync and status=="MERGED") end
for index=1,100 do local id,status=Tasks:Queue("startup.position",{startupPhase=4,dependencies={"startup.sync"},triggerSource="POSITION_"..index});assert(id==position and status=="MERGED") end
assert(#Tasks.queue==6,"startup burst created duplicate queue entries")
assert(Tasks:GetStartupMetrics().peakQueue==6 and Tasks:GetStartupMetrics().merged==400,"startup metrics did not capture the burst")
Tasks:Process();assert(runs.identity==1,"identity did not run in phase 1")
Tasks:Process();assert(Tasks.tasks[guild].blockReason=="STARTUP_PHASE:PHASE_2" or Tasks.tasks[guild].blockReason=="DEPENDENCY_WAITING:startup.identity","guild task lacks a concrete startup block reason")
mono=.5;Tasks:Process();assert(runs.guild==1,"guild task did not run in phase 2")
Tasks:Process();assert(Tasks.tasks[policy].blockReason=="STARTUP_PHASE:PHASE_3" or Tasks.tasks[policy].blockReason=="DEPENDENCY_WAITING:startup.guild","policy task lacks a concrete startup block reason")
mono=1;Tasks:Process();assert(runs.policy==1,"policy task did not run after guild")
Tasks:Process();assert(runs.twink==1,"twink task did not run after policy")
mono=2;Tasks:Process();assert(runs.sync==1,"sync task did not run in phase 4")
Tasks:Process();assert(runs.position==1,"position task did not run after sync")
assert(Tasks:GetStartupMetrics().executed==6,"startup execution metric mismatch")
print("Startup storm phases, dedupe, dependencies, metrics and blocking reasons passed")
