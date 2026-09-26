local root = (arg[0]:gsub("tools[/\\]test_comms_receive_limits.lua$", "")) .. "LIVE/Holy_Storm/"
local clock, events, logs, timers = 1000, {}, {}, {}
local locale = setmetatable({}, { __index = function(_, key) return key end })
local HolyStorm = {
    Utils = { Now = function() return clock end },
    Serializer = { limits = { bytes = 262144 } }, Logger = {},
    Tasks = { definitions = {} }, Events = { listeners = {} },
}
function HolyStorm:GetAddon() return self end
function HolyStorm:GetLocale() return locale end
function LibStub(name)
    if name == "AceLocale-3.0" then return { GetLocale = function() return locale end } end
    return HolyStorm
end
function HolyStorm.Logger:Write(level, source, category, message, context, correlationId)
    logs[#logs + 1] = { level = level, source = source, category = category, message = message, context = context, correlationId = correlationId }
end
function HolyStorm.Logger:WARN(source, message) self:Write("WARN", source, "general", message) end
function HolyStorm.Tasks:RegisterTaskType(id, definition) self.definitions[id] = definition end
function HolyStorm.Tasks:Queue(id, options) return id .. "-queued" end
function HolyStorm.Tasks:Cancel() return true end
function HolyStorm.Events:Register(event, _, callback) self.listeners[event] = callback end
function HolyStorm.Events:Emit(event, ...)
    events[#events + 1] = { event, ... }
    local callback = self.listeners[event]
    if callback then callback(event, ...) end
end
function HolyStorm.Events:UnregisterOwner() end
function CreateFrame()
    return { SetScript = function() end, RegisterEvent = function() end, UnregisterEvent = function() end }
end
C_Timer = { NewTimer = function(delay, callback)
    local timer = { delay = delay, callback = callback, cancelled = false }
    function timer:Cancel() self.cancelled = true end
    timers[#timers + 1] = timer
    return timer
end }
C_ChatInfo = { RegisterAddonMessagePrefix = function() return true end }
function GetUnitName() return "Alpha-Realm" end
function Ambiguate(name, mode)
    if mode == "none" and not name:find("-", 1, true) then return name .. "-Realm" end
    return name
end
function IsInGuild() return true end
function IsInRaid() return false end
function IsInGroup() return false end
HolyStorm.SyncTransport = {
    Initialize = function() return true end,
    GetDiagnostics = function() return {} end,
}

assert(loadfile(root .. "Sync/Comms.lua"))()
local Comms = HolyStorm.Comms
assert(Comms:Initialize())
local function frame(id, part, total, chunk, channel, sender)
    return Comms:OnMessage(Comms.prefix, table.concat({ "HSC1", id, part, total, chunk }, "|"), channel or "GUILD", sender or "Beta-Realm")
end
local function id(n) return "HSC1-" .. tostring(n) .. "-" .. tostring(n) end
local function transferKey(sender, channel, transmissionId)
    local name, realm = sender:match("^([^-]+)%-(.+)$")
    name, realm = (name or sender):lower():gsub("[%s%-']", ""), realm and realm:lower():gsub("[%s%-']", "")
    local identity = realm and (name .. "-" .. realm) or name
    return identity .. "\031" .. channel .. "\031" .. transmissionId
end
local function clearTransfers()
    clock = clock + 31
    Comms:Cleanup()
    assert(Comms.incomingCount == 0 and next(Comms.incoming) == nil, "expiry clears all active transfer state")
end
local function eventCount()
    local count = 0
    for _, event in ipairs(events) do if event[1] == "HS_COMMS_MESSAGE" then count = count + 1 end end
    return count
end

-- Single-piece and out-of-order multi-piece messages are delivered once.
assert(frame(id(1), 1, 1, "one") and eventCount() == 1, "normal one-fragment transfer completes")
assert(frame(id(2), 2, 2, "world") and frame(id(2), 1, 2, "hello ") and eventCount() == 2, "out-of-order transfer completes")
assert(Comms.incomingCount == 0 and Comms.receiveCounters.completedTransfers == 2, "completion releases all counters")

-- Duplicate indexes replace in place and account only their byte delta.
local duplicateId = id(3)
frame(duplicateId, 1, 3, "abcd")
frame(duplicateId, 1, 3, "abcd")
assert(Comms.incoming[transferKey("Beta-Realm", "GUILD", duplicateId)].receivedParts == 1 and Comms.incoming[transferKey("Beta-Realm", "GUILD", duplicateId)].receivedBytes == 4, "identical duplicate does not inflate counters")
frame(duplicateId, 2, 3, "efgh")
frame(duplicateId, 1, 3, "abcdefgh")
local packet = Comms.incoming[transferKey("Beta-Realm", "GUILD", duplicateId)]
assert(packet.receivedParts == 2 and packet.receivedBytes == 12, "larger replacement adds only its byte delta")
frame(duplicateId, 1, 3, "x")
assert(packet.receivedParts == 2 and packet.receivedBytes == 5, "smaller replacement subtracts its byte delta")
assert(Comms.receiveCounters.duplicateFragments == 3, "all repeated indexes are counted")
clearTransfers()

-- All currently producible frames fit the chosen receive ceilings.
local maximumPayload = string.rep("z", 220)
local maxId = id(4)
local emittedBeforeMax = eventCount()
for part = 1, 300 do frame(maxId, part, 300, maximumPayload) end
assert(eventCount() == emittedBeforeMax + 1, "maximum legitimate 300 x 220-byte transfer completes")
local maxEvent = events[#events]
assert(maxEvent[2] == string.rep("z", 66000) and #maxEvent[2] == 66000, "maximum legitimate payload is byte exact")
assert(Comms.incomingCount == 0 and Comms.receiveCounters.completedTransfers == 3, "maximum transfer leaves no incomplete state")

-- Structural, channel, sender and frame-size rejects allocate no transfer.
local beforeRejectEvents = eventCount()
local function rejected(message, channel, sender)
    Comms:OnMessage(Comms.prefix, message, channel or "GUILD", sender or "Gamma-Realm")
    assert(eventCount() == beforeRejectEvents, "rejected frame never emits a Sync payload")
end
rejected("HSC1|HSC1-9-9|0|1|x")
rejected("HSC1|HSC1-9-9|-1|1|x")
rejected("HSC1|HSC1-9-9|2|1|x")
rejected("HSC1|HSC1-9-9|1|0|x")
rejected("HSC1|HSC1-9-9|1.5|2|x")
rejected("HSC1|HSC1-9-9|1|2.5|x")
rejected("HSC1|HSC1-9-9|1|301|x")
rejected("HSC1|bad-id|1|1|x")
rejected("HSC1|HSC1-9-9|1|1|" .. string.rep("x", 221))
rejected("HSC1|HSC1-9-9|1|1|x", "SAY")
rejected("HSC1|HSC1-9-9|1|1|x", "GUILD", "")
rejected("HSC1|HSC1-9-9|1|1|x", "GUILD", string.rep("N", 129))
rejected("HSC1|HSC1-9-9|1|1|x", string.rep("C", 33), "Gamma-Realm")
assert(Comms.incomingCount == 0 and Comms.receiveCounters.excessivePartCount == 1, "malformed and excessive frames allocate no state")
local mismatchId = id(8)
frame(mismatchId, 1, 2, "a")
frame(mismatchId, 2, 3, "b")
assert(not Comms.incoming[transferKey("Beta-Realm", "GUILD", mismatchId)] and Comms.receiveCounters.malformedFrames > 0, "changed part count discards prior partial state")

-- Exercise byte-limit overflow, including a duplicate replacement whose delta
-- would exceed the limit. Restore the producer-derived limit afterwards.
local originalByteLimit = Comms.receiveLimits.maxPayloadBytes
Comms.receiveLimits.maxPayloadBytes = 10
local overflowId = id(5)
frame(overflowId, 1, 2, string.rep("a", 8))
frame(overflowId, 2, 2, "bcx")
assert(Comms.incomingCount == 0, "aggregate byte overflow discards the transfer")
Comms.receiveLimits.maxPayloadBytes = 10
local replaceOverflowId = id(6)
frame(replaceOverflowId, 1, 3, string.rep("a", 6))
frame(replaceOverflowId, 2, 3, string.rep("b", 4))
frame(replaceOverflowId, 1, 3, string.rep("c", 7))
assert(not Comms.incoming[transferKey("Beta-Realm", "GUILD", replaceOverflowId)], "overflowing replacement discards the partial transfer")
assert(Comms.receiveCounters.oversizedTransfers == 2, "both aggregate overflows are counted")
Comms.receiveLimits.maxPayloadBytes = originalByteLimit
clearTransfers()

-- Same ID from distinct senders and channels has independent state.
local sharedId = id(7)
frame(sharedId, 1, 2, "a", "GUILD", "Delta-Realm")
frame(sharedId, 1, 2, "b", "WHISPER", "Delta-Realm")
frame(sharedId, 1, 2, "c", "GUILD", "Epsilon-Realm")
assert(Comms.incomingCount == 3, "sender and channel participate in transfer identity")
clearTransfers()

-- Per-sender cap evicts that sender's oldest; global cap evicts globally oldest.
local startSenderEvictions = Comms.receiveCounters.senderCapEvictions
for n = 1, 17 do frame(id(100 + n), 1, 2, "x", "GUILD", "Cap-Realm") end
assert(Comms.incomingCount == 16 and Comms.incomingBySender["cap-realm"] == 16, "per-sender state remains within cap")
assert(not Comms.incoming[transferKey("Cap-Realm", "GUILD", id(101))] and Comms.receiveCounters.senderCapEvictions == startSenderEvictions + 1, "per-sender eviction removes its oldest transfer")
clearTransfers()
local startGlobalEvictions = Comms.receiveCounters.globalCapEvictions
for n = 1, 65 do frame(id(1000 + n), 1, 2, "x", "GUILD", "Peer" .. string.format("%03d", n) .. "-Realm") end
assert(Comms.incomingCount == 64 and Comms.receiveCounters.globalCapEvictions == startGlobalEvictions + 1, "global state remains within cap")
assert(not Comms.incoming[transferKey("Peer001-Realm", "GUILD", id(1001))], "global eviction removes the oldest transfer deterministically")
clearTransfers()
assert(Comms.receiveCounters.expiredTransfers >= 80 and Comms.incomingCount == 0, "expiry releases global and sender counters")

-- Stress bounded state with many peers and abandoned transfers.
local stressEvents = eventCount()
for sender = 1, 120 do
    for sequence = 1, 4 do
        frame(id(10000 + sender * 10 + sequence), 1, 2, string.rep("s", 220), "GUILD", "Stress-" .. tostring(sender) .. "-Realm")
        assert(Comms.incomingCount <= Comms.receiveLimits.maxIncomplete, "stress global cap invariant")
        for _, count in pairs(Comms.incomingBySender) do assert(count <= Comms.receiveLimits.maxPerSender, "stress sender cap invariant") end
    end
end
local activeFragments = 0
for _, active in pairs(Comms.incoming) do
    activeFragments = activeFragments + active.receivedParts
    assert(active.receivedBytes <= Comms.receiveLimits.maxPayloadBytes, "stress transfer byte invariant")
    assert(active.receivedParts <= Comms.receiveLimits.maxFragments, "stress transfer fragment invariant")
end
assert(Comms.incomingCount == 64 and activeFragments <= 64 and eventCount() == stressEvents, "stress keeps bounded fragments and emits no incomplete payload")
clearTransfers()
local diagnostics = Comms:GetDiagnostics()
assert(diagnostics.activeIncompleteTransfers == 0 and diagnostics.peakIncompleteTransfers <= 64 and diagnostics.expiredTransfers > 0, "diagnostics report bounded peak and cleanup")
assert(diagnostics.malformedFrames > 0 and diagnostics.oversizedFragments > 0 and diagnostics.globalCapEvictions > 0 and diagnostics.senderCapEvictions > 0, "diagnostics expose rejects and evictions")
print("Comms bounded receive-state tests passed")
