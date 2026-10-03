local addonVersion = "1.1.0"
local HolyStorm = LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local Events = { version=addonVersion, listeners = {}, frame = nil, runtimeMetrics={dispatchCount=0,events={}} }
local function isInternal(event) return event:sub(1, 3) == "HS_" end
local function isTechnicalInternal(event)
    return event:sub(1, 7) == "HS_LOG_" or event:sub(1, 8) == "HS_TASK_" or event:sub(1, 12) == "HS_WORKFLOW_"
end
function Events:Initialize()
    if self.frame then return end
    self.frame = CreateFrame("Frame")
    self.frame:SetScript("OnEvent", function(_, event, ...) Events:Emit(event, ...) end)
end
function Events:Register(event, owner, callback)
    if type(event) ~= "string" or (type(owner) ~= "string" and type(owner) ~= "table") or type(callback) ~= "function" then return false end
    self:Initialize(); local bucket = self.listeners[event]
    if not bucket then
        bucket = {}; self.listeners[event] = bucket
        if not isInternal(event) then local ok=pcall(self.frame.RegisterEvent,self.frame,event); if not ok then self.listeners[event]=nil; if HolyStorm.Logger then HolyStorm.Logger:WARN("EventBus","Unsupported event %s",event) end; return false end end
    end
    bucket[owner] = callback; return true
end
function Events:Unregister(event, owner)
    local bucket = self.listeners[event]; if not bucket then return false end
    bucket[owner] = nil
    if not next(bucket) then self.listeners[event] = nil; if not isInternal(event) and self.frame then pcall(self.frame.UnregisterEvent,self.frame,event) end end
    return true
end
function Events:UnregisterOwner(owner) local events={}; for event,bucket in pairs(self.listeners) do if bucket[owner] then events[#events+1]=event end end; for _,event in ipairs(events) do self:Unregister(event,owner) end end
local function eventMetric(events,event)
 if#event>128 then event=event:sub(1,128)end
 local metric=events[event];if metric then return metric end
 local count=0;for _ in pairs(events)do count=count+1 end
 if count>=512 then event="OTHER";metric=events[event];if metric then return metric end end
 metric={count=0,lastSeen=0,tasksRequested=0,tasksStarted=0,tasksCompleted=0,tasksFailed=0,workflowsRequested=0,workflowsStarted=0,workflowsCompleted=0,workflowsFailed=0};events[event]=metric;return metric
end
local followOnFields={tasksRequested=true,tasksStarted=true,tasksCompleted=true,tasksFailed=true,workflowsRequested=true,workflowsStarted=true,workflowsCompleted=true,workflowsFailed=true}
function Events:RecordFollowOn(event,kind)
 local metric=self.runtimeMetrics.events[event];if not metric then return false end
 if followOnFields[kind]then metric[kind]=metric[kind]+1 end
 return true
end
function Events:GetRuntimeMetrics()return self.runtimeMetrics end
function Events:ResetRuntimeMetrics()self.runtimeMetrics={dispatchCount=0,events={}};return true end
function Events:Emit(event, ...)
    local stats=self.runtimeMetrics;local metric=eventMetric(stats.events,event);metric.count=metric.count+1;metric.lastSeen=HolyStorm.Utils.Now();stats.dispatchCount=stats.dispatchCount+1
    if HolyStorm.UI and HolyStorm.UI.runtimeEventMonitorVisible then HolyStorm.UI:NotifyRuntimeEvent()end
    local bucket = self.listeners[event]; if not bucket then return end
    if HolyStorm.Tasks and HolyStorm.Tasks.RecordEvent then
        local first=select(1,...)
        for owner in pairs(bucket) do
            local source=type(owner)=="string" and owner or "unknown"
            HolyStorm.Tasks:RecordEvent(event, source, type(first)=="table" and {taskId=first.uniqueId,workflowId=first.workflowId,triggeredTask=first.registryId} or nil)
            if not isTechnicalInternal(event) and HolyStorm.Logger then HolyStorm.Logger:Write("DEBUG", source, "event", "Event received: " .. event, { listener=source,event=event,eventName=event }) end
        end
    end
    local callbacks = {}; for owner, callback in pairs(bucket) do callbacks[#callbacks + 1] = { owner, callback } end
    local args = { ... }
    for _, entry in ipairs(callbacks) do
        local previousEvent,previousOwner=self.currentEvent,self.currentOwner;self.currentEvent,self.currentOwner=event,entry[1]
        local ok, err = HolyStorm.Utils.SafeCall("event:" .. event, entry[2], event, unpack(args))
        self.currentEvent,self.currentOwner=previousEvent,previousOwner
        if not ok and HolyStorm.Logger then HolyStorm.Logger:ERROR("EventBus", "%s (%s)", tostring(err), tostring(entry[1])) end
    end
end
Events.Subscribe, Events.Unsubscribe = Events.Register, Events.Unregister
HolyStorm.Events, HolyStorm.EventManager = Events, Events
