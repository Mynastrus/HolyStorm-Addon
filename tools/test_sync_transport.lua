local root = (arg[0]:gsub("tools[/\\]test_sync_transport.lua$", "")) .. "LIVE/Holy_Storm/"
local calls, queueState = {}, { queues = {} }
local function key(prefix, distribution, target)
    return table.concat({ prefix, distribution, target or "" }, "\031")
end
local aceComm = { Embed = function(_, target)
    target.SendCommMessage = function(_, prefix, message, distribution, targetName, priority, callback, callbackArg)
        calls[#calls + 1] = { prefix = prefix, message = message, distribution = distribution, target = targetName, priority = priority }
        if message == "reject" then if callback then callback(callbackArg, 0, 0, nil, "refused") end; return end
        if callback then callback(callbackArg, #message, #message, true) end
    end
end }
local aceQueue = { queues = queueState.queues, Embed = function(_, target)
    local send = target.SendCommMessage
    target.SendCommMessage = function(owner, prefix, message, distribution, targetName, priority, callback, callbackArg)
        local queueKey = key(prefix, distribution, targetName)
        queueState.queues[queueKey] = queueState.queues[queueKey] or { ALERT = {}, NORMAL = {}, BULK = {} }
        table.insert(queueState.queues[queueKey][priority], { message = message })
        return send(owner, prefix, message, distribution, targetName, priority, callback, callbackArg)
    end
end }
local status = {
    ["AceCommQueue-1.0"] = { loaded = true, version = 7 },
    ["LibGuildRoster-1.0"] = { loaded = true, version = 4 },
}
HolyStorm = { Libraries = { GetStatus = function() return status end } }
function LibStub(name, silent)
    if name == "AceComm-3.0" then return aceComm end
    if name == "AceCommQueue-1.0" then return aceQueue end
    if silent then return nil end
    error("unexpected library " .. name)
end
local addon = { SyncTransport = nil, Libraries = { GetStatus = function() return status end } }
local addonLib = { GetAddon = function() return addon end }
local realLibStub = LibStub
function LibStub(name, silent)
    if name == "AceAddon-3.0" then return addonLib end
    return realLibStub(name, silent)
end
assert(loadfile(root .. "Sync/SyncTransport.lua"))()
local transport = addon.SyncTransport
local comms = { prefix = "HolyStormSync", available = true }
assert(transport:Initialize(comms), "adapter initializes with AceComm and AceCommQueue")
assert(transport:MapPriority(60) == "ALERT" and transport:MapPriority(70) == "NORMAL" and transport:MapPriority(100) == "BULK", "TaskManager priority maps to ACQ buckets")
local callbackCount = 0
local callback = function(_, sent, total, result) assert(sent == total and result == true); callbackCount = callbackCount + 1 end
assert(transport:SendGuild("HolyStormSync", "frame-guild", 60, callback), "guild frame queues")
assert(transport:SendWhisper("HolyStormSync", "frame-whisper", "Beta-Realm", 70, callback), "whisper frame queues")
assert(calls[1].distribution == "GUILD" and calls[1].priority == "ALERT", "guild delivery uses ALERT")
assert(calls[2].distribution == "WHISPER" and calls[2].target == "Beta-Realm" and calls[2].priority == "NORMAL", "whisper delivery retains target and mapped priority")
assert(callbackCount == 2 and transport.sent == 2 and transport.queued == 2, "terminal callbacks update adapter counters")
local rejected
local accepted, rejectReason = transport:SendGuild("HolyStormSync", "reject", 100, function(_, sent, total, result, reason) rejected = sent == 0 and total == 0 and result == nil and reason == "refused" end)
assert(not accepted and rejectReason == "refused" and rejected and transport.failures == 1, "queue refusal completes and reports the send failure")
local diagnostics = transport:GetDiagnostics()
assert(diagnostics.backend == "AceCommQueue-1.0/AceComm-3.0" and diagnostics.aceCommQueue.available and diagnostics.aceCommQueue.version == 7, "transport backend and version exposed")
assert(diagnostics.libGuildRoster.available and diagnostics.libGuildRoster.usedForPeerResolution == false, "roster library is diagnostic only")
assert(diagnostics.queueCount == 2 and diagnostics.queuedAlert == 1 and diagnostics.queuedNormal == 1, "queue diagnostics include this prefix's queued work")
comms.available = false
local suppressed
assert(transport:SendGuild("HolyStormSync", "frame-after-shutdown", 70, function(_, sent, total, result, reason) suppressed = sent == 0 and total == 0 and result == nil and reason == "suppressed" end), "shutdown race is safely accepted by queue")
assert(suppressed and transport.suppressed == 1, "shutdown drain is suppressed with a terminal callback")
assert(not transport:Cancel("anything"), "per-message cancellation is explicitly unsupported")
local missingAddon = { Libraries = { GetStatus = function() return {} end } }
HolyStorm = missingAddon
aceQueue = nil
local unavailableAddon = { SyncTransport = nil }
addon = unavailableAddon
assert(loadfile(root .. "Sync/SyncTransport.lua"))()
assert(not unavailableAddon.SyncTransport:Initialize({}), "missing queue library fails closed")
assert(unavailableAddon.SyncTransport.lastFailure.reason == "TRANSPORT_LIBRARY_UNAVAILABLE", "unavailable backend is diagnostic")
print("Sync transport adapter tests passed")
