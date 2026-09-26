local root = (arg[0]:gsub("tools[/\\]test_sync_protocol_contract.lua$", ""))
local function read(path)
    local file = assert(io.open(root .. path, "rb"))
    local value = file:read("*a")
    file:close()
    return value
end

local ace = read("LIVE/Holy_Storm/Libs/AceComm-3.0/AceComm-3.0.lua")
local queue = read("LIVE/Holy_Storm/Libs/AceCommQueue-1.0/AceCommQueue-1.0.lua")
local comms = read("LIVE/Holy_Storm/Sync/Comms.lua")
local transport = read("LIVE/Holy_Storm/Sync/SyncTransport.lua")
local serializer = read("LIVE/Holy_Storm/Core/Serialization/Serializer.lua")

assert(ace:find('local maxtextlen = 255', 1, true), "AceComm uses the 255-byte API ceiling")
assert(ace:find('maxtextlen = maxtextlen - 1', 1, true), "AceComm reserves a byte for multipart markers")
for _, marker in ipairs({ 'MSG_MULTI_FIRST = "\\001"', 'MSG_MULTI_NEXT  = "\\002"', 'MSG_MULTI_LAST  = "\\003"', 'MSG_ESCAPE = "\\004"' }) do
    assert(ace:find(marker, 1, true), "AceComm multipart marker exists: " .. marker)
end
assert(ace:find('prefix.."\\t"..distribution.."\\t"..sender', 1, true), "AceComm receive spool is per prefix, channel, sender")
assert(ace:find('spool[key] = message', 1, true) and ace:find('spool[key] = nil', 1, true), "AceComm starts and clears an unnumbered receive spool")
assert(ace:find('AceComm.callbacks:Fire(prefix, tconcat(olddata, ""), distribution, sender)', 1, true), "AceComm emits only after its LAST marker")
assert(not ace:find("multipart_spool.*timeout", 1, false), "embedded AceComm source has no receive spool expiry")

assert(queue:find('local MAJOR, MINOR = "AceCommQueue-1.0", 7', 1, true), "audited AceCommQueue minor is 7")
assert(queue:find("Per-(prefix, dist, target) queue tables", 1, true), "AceCommQueue serializes complete messages by target")
assert(queue:find("item.originalSend, item.commObj", 1, true), "AceCommQueue delegates logical messages to AceComm")
assert(queue:find("retryAttempts = 3", 1, true) and queue:find("retryDelay = 1", 1, true), "retry defaults are explicit in the embedded source")

assert(comms:find('protocol="HSC1",chunkSize=220,maxQueue=300', 1, true), "current HSC1 limits remain explicit")
assert(comms:find('fragmentTimeout=30', 1, true), "HSC1 fragments expire")
assert(comms:find('if #message>255 then', 1, true), "full HSC1 frame is checked before AceComm")
assert(not comms:find("SendCommMessage", 1, true) and not comms:find("C_ChatInfo.SendAddonMessage(", 1, true), "Comms does not bypass SyncTransport")
assert(transport:find('queue.Embed, queue, comms', 1, true), "adapter installs AceCommQueue after AceComm")
assert(serializer:find('bytes = 262144', 1, true), "serialized Sync payload safety limit remains 262144 bytes")

-- With a ten-digit clock and ordinary serial, 220 payload bytes plus the
-- longest 300-fragment header stays within the game's 255-byte API cap.
local id = "HSC1-2000000000-99999"
local frame = table.concat({ "HSC1", id, 300, 300, string.rep("x", 220) }, "|")
assert(#frame <= 255, "maximum outbound HSC1 frame fits one AceComm message")

for _, sample in ipairs({ {100, 1, 1}, {1000, 5, 4}, {10000, 46, 40}, {50000, 228, 197} }) do
    local oldFrames, aceChunks = math.ceil(sample[1] / 220), math.ceil((sample[1] + 5) / 254)
    assert(oldFrames == sample[2] and aceChunks == sample[3], "synthetic framing estimate for " .. sample[1] .. " bytes")
end

print("Sync protocol and embedded transport contract tests passed")
