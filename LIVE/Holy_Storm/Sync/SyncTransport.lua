local addonVersion = "1.0.0"
local HolyStorm = LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")

local Transport = {
    version = addonVersion,
    available = false,
    comms = nil,
    queue = nil,
    attempts = 0,
    queued = 0,
    sent = 0,
    failures = 0,
    suppressed = 0,
    lastFailure = nil,
}

-- TaskManager uses smaller numbers for higher priority. Preserve its broad
-- ordering in AceCommQueue's ALERT > NORMAL > BULK buckets.
function Transport:MapPriority(priority)
    priority = tonumber(priority) or 70
    if priority <= 65 then return "ALERT" end
    if priority < 90 then return "NORMAL" end
    return "BULK"
end

function Transport:Initialize(comms)
    if self.comms == comms and self.embedded then
        self.available = true
        return true
    end

    local aceComm = LibStub("AceComm-3.0", true)
    local queue = LibStub("AceCommQueue-1.0", true)
    if not aceComm or type(aceComm.Embed) ~= "function" or not queue or type(queue.Embed) ~= "function" then
        self.available = false
        self.lastFailure = { reason = "TRANSPORT_LIBRARY_UNAVAILABLE" }
        return false, "TRANSPORT_LIBRARY_UNAVAILABLE"
    end

    local embedded, embedError = pcall(aceComm.Embed, aceComm, comms)
    if not embedded then
        self.available = false
        self.lastFailure = { reason = "ACECOMM_EMBED_FAILED", error = tostring(embedError) }
        return false, "ACECOMM_EMBED_FAILED"
    end
    local aceSend = comms.SendCommMessage
    if type(aceSend) ~= "function" then
        self.available = false
        self.lastFailure = { reason = "ACECOMM_EMBED_FAILED" }
        return false, "ACECOMM_EMBED_FAILED"
    end

    -- AceCommQueue must wrap the last SendCommMessage wrapper. A queued send
    -- drained after addon shutdown is deliberately suppressed with its required
    -- (0, 0, nil) callback so it cannot deadlock the shared queue.
    comms.SendCommMessage = function(owner, prefix, message, distribution, target, priority, callback, callbackArg)
        if not owner.available then
            if callback then callback(callbackArg, 0, 0, nil, "suppressed") end
            return
        end
        return aceSend(owner, prefix, message, distribution, target, priority, callback, callbackArg)
    end
    local queueEmbedded, queueError = pcall(queue.Embed, queue, comms)
    if not queueEmbedded then
        self.available = false
        self.lastFailure = { reason = "QUEUE_EMBED_FAILED", error = tostring(queueError) }
        return false, "QUEUE_EMBED_FAILED"
    end

    self.comms, self.queue, self.embedded = comms, queue, true
    self.available = true
    self.lastFailure = nil
    return true
end

function Transport:IsAvailable()
    return self.available == true and self.comms ~= nil and self.queue ~= nil
end

function Transport:Send(prefix, message, distribution, target, taskPriority, callback, callbackArg, context)
    if not self:IsAvailable() then
        self.lastFailure = { reason = "TRANSPORT_UNAVAILABLE", context = context }
        return false, "TRANSPORT_UNAVAILABLE"
    end

    local priority = self:MapPriority(taskPriority)
    local outcome
    local function onComplete(arg, sent, total, sendResult, reason)
        if (sent == 0 and total == 0) or (sent and total and total > 0 and sent >= total) then
            outcome = { sent = sent, total = total, result = sendResult, reason = reason }
            if sendResult == false or (reason and reason ~= "suppressed") then
                self.failures = self.failures + 1
                self.lastFailure = {
                    reason = reason or "SEND_REFUSED",
                    prefix = prefix,
                    distribution = distribution,
                    target = target,
                    priority = priority,
                    context = context,
                }
            elseif reason == "suppressed" then
                self.suppressed = self.suppressed + 1
            else
                self.sent = self.sent + 1
            end
            if callback then callback(arg, sent, total, sendResult, reason) end
        end
    end

    self.attempts = self.attempts + 1
    local ok, err = pcall(self.comms.SendCommMessage, self.comms, prefix, message, distribution, target, priority, onComplete, callbackArg)
    if not ok then
        if not outcome then onComplete(callbackArg, 0, 0, false, "send-error") end
        if not outcome then
            self.lastFailure = { reason = "SEND_ERROR", error = tostring(err), prefix = prefix, distribution = distribution, target = target, priority = priority, context = context }
        end
        return false, "SEND_ERROR"
    end

    if outcome and (outcome.result == false or (outcome.reason and outcome.reason ~= "suppressed")) then
        return false, outcome.reason or "SEND_REFUSED"
    end
    self.queued = self.queued + 1
    return true, priority
end

function Transport:SendGuild(prefix, message, taskPriority, callback, callbackArg, context)
    return self:Send(prefix, message, "GUILD", nil, taskPriority, callback, callbackArg, context)
end

function Transport:SendWhisper(prefix, message, target, taskPriority, callback, callbackArg, context)
    if type(target) ~= "string" or target == "" then return false, "INVALID_TARGET" end
    return self:Send(prefix, message, "WHISPER", target, taskPriority, callback, callbackArg, context)
end

function Transport:Cancel()
    -- AceCommQueue-1.0 exposes no per-message cancellation API. Shutdown uses
    -- the suppression callback above; TaskManager owns work not yet submitted.
    return false, "CANCELLATION_UNSUPPORTED"
end

function Transport:GetDiagnostics()
    local status = HolyStorm.Libraries and HolyStorm.Libraries:GetStatus() or {}
    local acqStatus = status["AceCommQueue-1.0"] or {}
    local rosterStatus = status["LibGuildRoster-1.0"] or {}
    local result = {
        backend = self:IsAvailable() and "AceCommQueue-1.0/AceComm-3.0" or "unavailable",
        aceCommQueue = { available = acqStatus.loaded == true, version = acqStatus.version },
        libGuildRoster = { available = rosterStatus.loaded == true, version = rosterStatus.version, usedForPeerResolution = false },
        peerBackend = "HolyStorm.Data.GuildStore + Sync presence",
        attempts = self.attempts,
        queued = self.queued,
        sent = self.sent,
        failures = self.failures,
        suppressed = self.suppressed,
        lastFailure = self.lastFailure,
        queueCount = 0,
        queuedAlert = 0,
        queuedNormal = 0,
        queuedBulk = 0,
        inFlight = 0,
    }
    if not self.queue or type(self.queue.queues) ~= "table" then return result end
    local prefix = self.comms and self.comms.prefix
    local queuePrefix = type(prefix) == "string" and (prefix .. "\031") or nil
    for key, queue in pairs(self.queue.queues) do
        if queuePrefix and key:sub(1, #queuePrefix) == queuePrefix then
            result.queueCount = result.queueCount + 1
            result.queuedAlert = result.queuedAlert + #(queue.ALERT or {})
            result.queuedNormal = result.queuedNormal + #(queue.NORMAL or {})
            result.queuedBulk = result.queuedBulk + #(queue.BULK or {})
            if queue.inFlight then result.inFlight = result.inFlight + 1 end
        end
    end
    result.queuedMessages = result.queuedAlert + result.queuedNormal + result.queuedBulk
    return result
end

HolyStorm.SyncTransport = Transport
