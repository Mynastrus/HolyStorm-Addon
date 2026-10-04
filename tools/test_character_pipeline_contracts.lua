-- Static architecture guards for the five persisted character producers.
local repository=arg[0]:gsub("tools[/\\]test_character_pipeline_contracts.lua$","")
local producers={
 {block="equipment",path="LIVE/Holy_Storm_Equipment/Equipment.lua",version="snapshotVersion=4",workflow="EQUIPMENT_UPDATE",mergeBeforeStart=true},
 {block="mythicPlus",path="LIVE/Holy_Storm_MythicPlus/MythicPlus.lua",version="SNAPSHOT_VERSION = 5",workflow="SNAPSHOT_MYTHICPLUS",mergeBeforeStart=true},
 {block="raid",path="LIVE/Holy_Storm_Raids/Raids.lua",version="snapshotVersion=3",workflow="SNAPSHOT_RAIDS",mergeBeforeStart=false},
 {block="delves",path="LIVE/Holy_Storm_Delves/Delves.lua",version="snapshotVersion=3",workflow="SNAPSHOT_DELVES",mergeBeforeStart=true},
 {block="stats",path="LIVE/Holy_Storm_Characters/Stats.lua",version="snapshotVersion=2",workflow="SNAPSHOT_STATS",mergeBeforeStart=true},
}
local function read(path)local file=assert(io.open(repository..path,"rb"));local value=file:read("*a");file:close();return value end
local forbidden={"HolyStormDB","HS_Player_DB","SendAddonMessage","C_ChatInfo.SendAddonMessage","HolyStorm.Sync:Publish","HolyStorm.Sync:Send"}
for _,producer in ipairs(producers)do
 local source=read(producer.path)
 assert(source:find("CharacterScans:RegisterProvider",1,true),producer.block.." registers a CharacterScanManager provider")
 assert(source:find("CharacterScans:Request",1,true),producer.block.." routes automatic/manual work through CharacterScanManager")
 assert(source:find("PlayerData:WriteOwnedBlock",1,true),producer.block.." commits through PlayerData")
 assert(source:find(producer.version,1,true),producer.block.." declares its persisted schema version")
 assert(source:find("mergeBeforeStart%s*=%s*"..tostring(producer.mergeBeforeStart)),producer.block.." declares whether its provider safely merges before the first task")
 assert(not source:find("PLAYER_LOGIN",1,true)and not source:find("PLAYER_ENTERING_WORLD",1,true),producer.block.." has no login-triggered snapshot scan")
 for _,token in ipairs(forbidden)do assert(not source:find(token,1,true),producer.block.." bypasses persistence or central Sync with "..token)end
 if producer.block=="equipment"then
  assert(source:find('"Equipment.Scan"',1,true)and source:find('"Equipment.ConfirmScan"',1,true)and source:find('"Equipment.StabilityCompare"',1,true),"Equipment retains its A/B stability workflow")
  assert(source:find('debounce=1',1,true)and source:find('fingerprint(c.data.snapshot)~=fingerprint(old)',1,true),"Equipment debounce and no-op comparison remain explicit")
 else
  assert(source:find('Snapshots:Queue',1,true),producer.block.." uses the shared SnapshotManager workflow")
 end
end
local snapshotManager=read("LIVE/Holy_Storm/Persistence/SnapshotManager.lua")
assert(snapshotManager:find("timeoutSeconds=30",1,true)and snapshotManager:find("recordValidationResult",1,true),"generic snapshots have bounded ASYNC waits and shared validation diagnostics")
local characterScans=read("LIVE/Holy_Storm/Core/Tasks/CharacterScanManager.lua")
assert(characterScans:find("function CharacterScans:RequestAll",1,true)and characterScans:find("function CharacterScans:RequestBlocks",1,true),"global and individual refreshes use the serialized scan manager")
assert(not characterScans:find("INITIAL_MISSING_BLOCK",1,true)and not characterScans:find("INITIAL_STALE_BLOCK",1,true),"missing/stale state cannot synthesize login scans")
local commands=read("LIVE/Holy_Storm/Core/Commands/Commands.lua")
assert(commands:find("manager:Request",1,true)and commands:find("manager:GetDeclarations",1,true),"slash commands use the canonical declaration and block request paths")
local ui=read("LIVE/Holy_Storm_Characters/UI/StoredFeatureTabs.lua")
assert(not ui:find("CharacterScans:Request",1,true)and not ui:find("Snapshots:Queue",1,true),"opening/rendering stored feature tabs does not start a scan")
print("Character producer schema, persistence/Sync boundaries, login, refresh, and workflow contracts passed")
