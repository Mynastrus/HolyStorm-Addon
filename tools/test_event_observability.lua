local root=(arg[0]:gsub("tools[/\\]test_event_observability.lua$","")).."LIVE/Holy_Storm/"
unpack=unpack or table.unpack
local now=1200
local frames={}
local HolyStorm={Utils={}}
HolyStorm.UI={runtimeEventMonitorVisible=false,eventRefreshes=0}
function HolyStorm.UI:NotifyRuntimeEvent()self.eventRefreshes=self.eventRefreshes+1;return true end
HolyStorm.Tasks={schedulerWakes=0}
function HolyStorm.Tasks:Wake()self.schedulerWakes=self.schedulerWakes+1 end
function HolyStorm:GetAddon()return self end
function HolyStorm.Utils.Now()return now end
function HolyStorm.Utils.SafeCall(_,callback,...)
 local result={pcall(callback,...)}
 if not result[1]then return false,result[2]end
 table.remove(result,1);return true,unpack(result)
end
function CreateFrame()
 local frame={}
 function frame:SetScript(_,callback)self.callback=callback end
 function frame:RegisterEvent(event)self.registered=event end
 function frame:UnregisterEvent(event)if self.registered==event then self.registered=nil end end
 frames[#frames+1]=frame;return frame
end
function LibStub()return HolyStorm end

assert(loadfile(root.."Core/Events/EventBus.lua"))()
local Events=HolyStorm.Events
local payload={privateText="must not enter metric history"}
Events:Emit("TEST_EVENT",payload)
local metrics=Events:GetRuntimeMetrics()
assert(metrics.dispatchCount==1 and metrics.events.TEST_EVENT.count==1 and metrics.events.TEST_EVENT.lastSeen==now,"event dispatches aggregate count and last-seen time")
assert(HolyStorm.UI.eventRefreshes==0,"closed Event Monitor does not schedule refresh work")
for key,value in pairs(metrics.events.TEST_EVENT)do assert(type(value)~="table"and key~="payload","event metrics must contain counters only, never payloads")end
assert(metrics.events.TEST_EVENT.tasksRequested==0 and metrics.events.TEST_EVENT.workflowsStarted==0,"event aggregates initialize follow-on counters")
assert(HolyStorm.Tasks.schedulerWakes==0,"event aggregation does not wake the task scheduler")
Events:RecordFollowOn("TEST_EVENT","tasksRequested")
Events:RecordFollowOn("TEST_EVENT","workflowsStarted")
assert(metrics.events.TEST_EVENT.tasksRequested==1 and metrics.events.TEST_EVENT.workflowsStarted==1,"event follow-on work is attributed centrally")
local delivered
assert(Events:Register("TEST_EVENT","test-owner",function(_,value)delivered=value end))
HolyStorm.UI.runtimeEventMonitorVisible=true;now=1201;Events:Emit("TEST_EVENT",payload)
assert(delivered==payload and metrics.dispatchCount==2 and metrics.events.TEST_EVENT.count==2 and metrics.events.TEST_EVENT.lastSeen==now,"event instrumentation preserves normal event delivery")
assert(HolyStorm.UI.eventRefreshes==1,"visible Event Monitor receives a coalesced refresh notification")
assert(Events:ResetRuntimeMetrics()and Events:GetRuntimeMetrics().dispatchCount==0 and next(Events:GetRuntimeMetrics().events)==nil,"reset clears only volatile event aggregates")
print("Payload-free event dispatch and follow-on aggregation tests passed")
