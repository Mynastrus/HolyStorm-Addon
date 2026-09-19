local root = (arg[0]:gsub("tools[/\\]test_data_manager.lua$", "")) .. "LIVE/Holy_Storm/"

local logEntries, emitted = {}, {}
local HolyStorm = {
    db = { global={}, profile={}, char={} },
    Data = { CharacterStore={} },
    Logger = {},
    Events = {},
}

function LibStub(name)
    if name == "AceAddon-3.0" then return { GetAddon=function() return HolyStorm end } end
    error("Unexpected library: " .. tostring(name))
end

function HolyStorm.Logger:Write(level, source, category, message, context)
    logEntries[#logEntries + 1] = { level=level, source=source, category=category, message=message, context=context }
end

function HolyStorm.Events:Emit(event, ...)
    emitted[#emitted + 1] = { event=event, args={...} }
    if event == "HS_DM_TX_COMMITTED" then
        assert(HolyStorm.db.global.phase1Tx.value ~= 1, "commit event must run after replacement")
    end
end

function HolyStorm.Data.CharacterStore:Get() return nil end

assert(loadfile(root .. "Persistence/Database.lua"))()
HolyStorm.Database.initialized = true
local DataManager = HolyStorm.DataManager
assert(DataManager.schemas == nil and DataManager.migrations == nil, "registries must not expose mutable internals")

local function countEvent(name)
    local count = 0
    for _, entry in ipairs(emitted) do if entry.event == name then count = count + 1 end end
    return count
end

local function validateData(data)
    if type(data) ~= "table" then return false, "NOT_A_TABLE" end
    if data.forbidden then return false, "FORBIDDEN_VALUE", { field="forbidden" } end
    if data.items ~= nil and type(data.items) ~= "table" then return false, "INVALID_ITEMS" end
    return true
end

-- Schema registry and schema metadata.
HolyStorm.db.global.phase1Core = { schemaVersion=1, items={ one={ value=1 } }, untouched="original" }
local originalCore = HolyStorm.db.global.phase1Core
local registered = DataManager:RegisterSchema({
    id="phase1.core",
    owner="DataManagerTest",
    version=3,
    validate=validateData,
    storage={ backend="database", scope="global", path="phase1Core" },
    metadata={ purpose="contract", nested={ safe=true } },
    event="HS_DM_MIGRATED",
    migrations={
        { fromVersion=1, toVersion=2, migrate=function(data) data.stepTwo=true end },
        { fromVersion=2, toVersion=3, migrate=function(data) data.stepThree=true; return true end },
    },
})
assert(registered.ok and registered.changed and registered.schema == "phase1.core" and registered.version == 3, "schema registration result")
assert(HolyStorm.db.global.phase1Core == originalCore and originalCore.schemaVersion == 1 and not originalCore.stepTwo, "registration must not migrate live data")
local duplicate = DataManager:RegisterSchema({ id="phase1.core", owner="Other", version=1, validate=function() return true end, storage={scope="global",path="other"} })
assert(not duplicate.ok and duplicate.errorCode == "SCHEMA_ALREADY_REGISTERED", "duplicate schema")
assert(DataManager:RegisterSchema({ id="bad id", owner="Test", version=1, validate=function() return true end, storage={scope="global",path="bad"} }).errorCode == "INVALID_SCHEMA_ID", "invalid schema id")
assert(DataManager:RegisterSchema({ id="bad-version", owner="Test", version=0, validate=function() return true end, storage={scope="global",path="bad"} }).errorCode == "INVALID_SCHEMA_VERSION", "invalid schema version")
assert(DataManager:RegisterSchema({ id="bad-validator", owner="Test", version=1, storage={scope="global",path="bad"} }).errorCode == "INVALID_SCHEMA_VALIDATOR", "validator required")
local unknownValue, unknownResult = DataManager:Get("phase1.unknown")
assert(unknownValue == nil and not unknownResult.ok and unknownResult.errorCode == "UNKNOWN_SCHEMA", "unknown schema")
local metadata, metadataResult = DataManager:GetMetadata("phase1.core")
assert(metadataResult.ok and metadata.id == "phase1.core" and metadata.owner == "DataManagerTest" and metadata.version == 3 and metadata.metadata.nested.safe, "schema metadata")
metadata.metadata.nested.safe = false
assert((DataManager:GetMetadata("phase1.core")).metadata.nested.safe == true, "schema metadata must be defensive")

-- Migration registry, paths, rollback, validation, and atomic replacement.
local duplicateMigration = DataManager:RegisterMigration("phase1.core", 1, 2, function() end)
assert(not duplicateMigration.ok and duplicateMigration.errorCode == "MIGRATION_ALREADY_REGISTERED", "duplicate migration")
local backwardMigration = DataManager:RegisterMigration("phase1.core", 2, 1, function() end)
assert(not backwardMigration.ok and backwardMigration.errorCode == "INVALID_MIGRATION_STEP", "backward migration")
local migrated = DataManager:RunMigrations("phase1.core")
assert(migrated.ok and migrated.changed and migrated.fromVersion == 1 and migrated.toVersion == 3, "multi-step migration")
assert(HolyStorm.db.global.phase1Core ~= originalCore and HolyStorm.db.global.phase1Core.schemaVersion == 3 and HolyStorm.db.global.phase1Core.stepTwo and HolyStorm.db.global.phase1Core.stepThree, "successful atomic migration")
assert(originalCore.schemaVersion == 1 and not originalCore.stepTwo and originalCore.untouched == "original", "successful migration must not mutate old table")
assert(countEvent("HS_DM_MIGRATED") == 1, "migration commit event")

HolyStorm.db.global.phase1Simple = { schemaVersion=1, value=4 }
assert(DataManager:RegisterSchema({ id="phase1.simple", owner="Test", version=2, validate=validateData, storage={scope="global",path="phase1Simple"} }).ok)
assert(DataManager:RegisterMigration("phase1.simple", 1, 2, function(data) data.value=data.value+1 end).ok)
local simple = DataManager:RunMigrations("phase1.simple")
assert(simple.ok and HolyStorm.db.global.phase1Simple.schemaVersion == 2 and HolyStorm.db.global.phase1Simple.value == 5, "simple v1 to v2 migration")

HolyStorm.db.global.phase1Gap = { schemaVersion=1, items={} }
assert(DataManager:RegisterSchema({ id="phase1.gap", owner="Test", version=3, validate=validateData, storage={scope="global",path="phase1Gap"} }).ok)
assert(DataManager:RegisterMigration("phase1.gap", 1, 2, function(data) data.partial=true end).ok)
local gapPointer = HolyStorm.db.global.phase1Gap
local gap = DataManager:RunMigrations("phase1.gap")
assert(not gap.ok and gap.errorCode == "MIGRATION_PATH_MISSING" and HolyStorm.db.global.phase1Gap == gapPointer and not gapPointer.partial, "missing path rollback")

HolyStorm.db.global.phase1Throw = { schemaVersion=1, value="safe" }
assert(DataManager:RegisterSchema({ id="phase1.throw", owner="Test", version=2, validate=validateData, storage={scope="global",path="phase1Throw"}, migrations={{fromVersion=1,toVersion=2,migrate=function(data) data.value="dirty"; error("boom") end}} }).ok)
local throwPointer = HolyStorm.db.global.phase1Throw
local thrown = DataManager:RunMigrations("phase1.throw")
assert(not thrown.ok and thrown.errorCode == "MIGRATION_ERROR" and HolyStorm.db.global.phase1Throw == throwPointer and throwPointer.value == "safe" and throwPointer.schemaVersion == 1, "migration error rollback")

HolyStorm.db.global.phase1InvalidMigration = { schemaVersion=1, items={} }
assert(DataManager:RegisterSchema({ id="phase1.invalid-migration", owner="Test", version=2, validate=validateData, storage={scope="global",path="phase1InvalidMigration"}, migrations={{fromVersion=1,toVersion=2,migrate=function(data) data.forbidden=true end}} }).ok)
local invalidMigrationPointer = HolyStorm.db.global.phase1InvalidMigration
local invalidMigration = DataManager:RunMigrations("phase1.invalid-migration")
assert(not invalidMigration.ok and invalidMigration.errorCode == "VALIDATION_FAILED" and invalidMigration.validationCode == "FORBIDDEN_VALUE", "post-migration validation")
assert(HolyStorm.db.global.phase1InvalidMigration == invalidMigrationPointer and not invalidMigrationPointer.forbidden and invalidMigrationPointer.schemaVersion == 1, "validation failure rollback")

-- Defensive reads and missing values.
local firstRead, firstReadResult = DataManager:Get("phase1.core")
assert(firstReadResult.ok and firstReadResult.exists and firstRead.items.one.value == 1, "safe get")
firstRead.items.one.value = 99
assert(HolyStorm.db.global.phase1Core.items.one.value == 1, "get must not expose live root")
local secondRead = DataManager:GetCopy("phase1.core")
assert(secondRead.items.one.value == 1 and secondRead ~= firstRead and secondRead.items ~= firstRead.items, "reads must be independent")
local missing, missingResult = DataManager:Get("phase1.core", "missing")
assert(missing == nil and missingResult.ok and missingResult.exists == false, "missing key")
local exists, existsResult = DataManager:Exists("phase1.core", {"items", "one"})
assert(exists and existsResult.ok, "nested key exists")
assert(DataManager:Exists("phase1.core", "missing") == false, "missing key does not exist")

assert(DataManager:RegisterSchema({ id="phase1.missing", owner="Test", version=1, validate=validateData, default=function() return {schemaVersion=1,items={}} end, storage={scope="global",path="phase1Missing"} }).ok)
local absent, absentResult = DataManager:Get("phase1.missing")
assert(absent == nil and absentResult.ok and absentResult.exists == false and HolyStorm.db.global.phase1Missing == nil, "read must not apply defaults")

-- Transactions, commits, validation rollback, copy isolation, and events.
HolyStorm.db.global.phase1Tx = { schemaVersion=1, value=1, nested={ flag=true }, items={} }
assert(DataManager:RegisterSchema({ id="phase1.tx", owner="Test", version=1, validate=validateData, storage={scope="global",path="phase1Tx"}, event="HS_DM_TX_COMMITTED" }).ok)
local txOriginal = HolyStorm.db.global.phase1Tx
local updated = DataManager:Update("phase1.tx", nil, function(draft) draft.value=2 end, {actor="test"})
assert(updated.ok and updated.changed and updated.errorCode == nil and updated.schema == "phase1.tx" and updated.version == 1, "successful update result")
assert(HolyStorm.db.global.phase1Tx ~= txOriginal and txOriginal.value == 1 and HolyStorm.db.global.phase1Tx.value == 2, "update atomic replacement")
local afterUpdate = HolyStorm.db.global.phase1Tx
local unchanged = DataManager:Transaction("phase1.tx", nil, function() end)
assert(unchanged.ok and not unchanged.changed and HolyStorm.db.global.phase1Tx == afterUpdate and countEvent("HS_DM_TX_COMMITTED") == 1, "unchanged transaction")
local mutatorPointer = HolyStorm.db.global.phase1Tx
local mutatorError = DataManager:Update("phase1.tx", nil, function(draft) draft.value=8; error("mutator failed") end)
assert(not mutatorError.ok and mutatorError.errorCode == "MUTATOR_ERROR" and HolyStorm.db.global.phase1Tx == mutatorPointer and mutatorPointer.value == 2, "mutator rollback")
local validationPointer = HolyStorm.db.global.phase1Tx
local validationError = DataManager:Update("phase1.tx", nil, function(draft) draft.forbidden=true end)
assert(not validationError.ok and validationError.errorCode == "VALIDATION_FAILED" and HolyStorm.db.global.phase1Tx == validationPointer and not validationPointer.forbidden, "validator rollback")
local committed = DataManager:Commit("phase1.tx", "value", 3, {actor="test"})
assert(committed.ok and committed.changed and committed.value == 3 and HolyStorm.db.global.phase1Tx.value == 3 and countEvent("HS_DM_TX_COMMITTED") == 2, "commit and success-only event")
local external = { flag="owned-by-caller" }
assert(DataManager:Commit("phase1.tx", "nested", external).ok)
external.flag = "mutated"
assert(HolyStorm.db.global.phase1Tx.nested.flag == "owned-by-caller", "commit input must be detached")
local badVersion = DataManager:Commit("phase1.tx", nil, { schemaVersion=9, items={} })
assert(not badVersion.ok and badVersion.errorCode == "SCHEMA_VERSION_MISMATCH" and HolyStorm.db.global.phase1Tx.schemaVersion == 1, "schema version validation")
assert(countEvent("HS_DM_TX_COMMITTED") == 3, "failed commits emit no event")

local defaultUpdate = DataManager:Update("phase1.missing", nil, function(draft) draft.items.created=true end)
assert(defaultUpdate.ok and defaultUpdate.changed and HolyStorm.db.global.phase1Missing.items.created, "default factory transaction")

-- Copy safety: nested arrays/maps/mixed tables, nil, shared references, unsupported values, cycles, and metatables.
local shared = { value=7 }
local source = setmetatable({ array={1,2,{deep=true}}, map={alpha="a", [4]="n"}, mixed={[1]="first", named=shared}, alias=shared, missing=nil }, {__index={inherited=true}})
local copied, copyResult = DataManager:SafeCopy(source)
assert(copyResult.ok and copied.array[3].deep and copied.map.alpha == "a" and copied.map[4] == "n" and copied[1] == nil, "nested copy")
assert(copied.mixed.named == copied.alias and copied.mixed.named ~= shared, "shared references remain shared but detached")
assert(getmetatable(copied) == nil and copied.inherited == nil and copied.missing == nil, "metatables and nil values")
local nilCopy, nilCopyResult = DataManager:SafeCopy(nil)
assert(nilCopy == nil and nilCopyResult.ok, "nil copy")
copied.array[3].deep = false
assert(source.array[3].deep == true, "nested copy isolation")
local unsupported, unsupportedResult = DataManager:SafeCopy({ callback=function() end })
assert(unsupported == nil and unsupportedResult.errorCode == "COPY_UNSUPPORTED_TYPE", "unsupported type rejected")
local cyclic = {}; cyclic.self = cyclic
local cycleCopy, cycleResult = DataManager:SafeCopy(cyclic)
assert(cycleCopy == nil and cycleResult.errorCode == "COPY_CYCLE", "cycles explicitly rejected")

-- A realistic roster read copies only the requested subtree, not its persistence root.
local roster = { schemaVersion=1, guild={roster={}, ranks={ [1]="Member" }} }
for index = 1, 250 do
    roster.guild.roster["Player-" .. index] = { guid="Player-" .. index, name="Member-" .. index, identity={class="PALADIN", level=80}, history={lastSeen=index, flags={online=index % 2 == 0}} }
end
roster.unrelated = { large={ nested={ value=true } } }
HolyStorm.db.global.phase1Roster = roster
assert(DataManager:RegisterSchema({ id="phase1.roster", owner="DataManagerTest", version=1, validate=function(data) return type(data)=="table" and type(data.roster)=="table" end, storage={scope="global",path="phase1Roster"} }).ok)
local rosterRead, rosterResult = DataManager:Get("phase1.roster", {"guild", "roster"})
assert(rosterResult.ok and rosterResult.exists and rosterRead["Player-250"].history.flags.online == true, "large roster subtree safe read")
rosterRead["Player-1"].identity.level = 1
assert(roster.guild.roster["Player-1"].identity.level == 80 and rosterRead.unrelated == nil, "roster read is detached and scoped")

assert(#logEntries >= 7, "structured failures must be logged")
for _, entry in ipairs(logEntries) do
    assert(entry.source == "DataManager" and entry.category == "persistence" and type(entry.context) == "table" and entry.context.operation and entry.context.errorCode, "structured logging contract")
end

print("DataManager schema, migration, rollback, safe-read, transaction, event, logging and copy tests passed")
