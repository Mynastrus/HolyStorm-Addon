local addonVersion = "1.1.0"
local HolyStorm = LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")

local Database = { version=addonVersion, areas = {}, diagnosticSources = {}, initialized = false }

function Database:Initialize()
    self.initialized = false
    local legacy = type(HolyStormDB) == "table" and HolyStormDB.profiles == nil and HolyStorm.Utils.DeepCopy(HolyStormDB) or nil
    HolyStorm.db = LibStub("AceDB-3.0"):New("HolyStormDB", HolyStorm.Data.Schema.defaults, true)
    HS_Player_DB = type(HS_Player_DB) == "table" and HS_Player_DB or {}
    if legacy then
        if legacy.enabled ~= nil then HolyStorm.db.profile.enabled = legacy.enabled == true end
        if type(legacy.optionalModules) == "table" then HolyStorm.db.profile.optionalModules = HolyStorm.Utils.ApplyDefaults(legacy.optionalModules, HolyStorm.Data.Schema.defaults.profile.optionalModules) end
    end
    local ok, err = HolyStorm.Data.Migrations:Run(HolyStorm.db.global, HolyStorm.db.global.schemaVersion, legacy)
    if not ok then error("Holy Storm database: " .. tostring(err)) end
    self.initialized = true
    self:RegisterDiagnosticSource("HolyStormDB",function()return HolyStorm.db end)
    self:RegisterDiagnosticSource("HS_Player_DB",function()return HS_Player_DB end)
end

function Database:IsInitialized() return self.initialized == true and type(HolyStorm.db) == "table" end
function Database:GetHandle() return self:IsInitialized() and HolyStorm.db or nil end
function Database:RegisterDiagnosticSource(id, getter)
    if type(id)~="string"or id==""or type(getter)~="function"then return false end
    self.diagnosticSources[id]=getter;return true
end
function Database:GetDiagnosticSources()
    local ids={};for id in pairs(self.diagnosticSources)do ids[#ids+1]=id end;table.sort(ids);return ids
end
function Database:GetDiagnosticSource(id)
    local getter=self.diagnosticSources[id];if not getter then return nil end
    local ok,value=pcall(getter);return ok and value or nil
end

function Database:GetRoot(scope)
    if not self:IsInitialized() then return nil end
    if scope == "character" or scope == "char" then return HolyStorm.db.char end
    return HolyStorm.db[scope or "profile"]
end

function Database:Get(path, scope)
    local value = self:GetRoot(scope)
    if type(value) ~= "table" then return nil end
    for segment in string.gmatch(path or "", "[^%.]+") do
        if type(value) ~= "table" then return nil end
        value = value[segment]
    end
    return value
end

function Database:Set(path, value, scope)
    local target, segments = self:GetRoot(scope), {}
    for segment in string.gmatch(path or "", "[^%.]+") do segments[#segments + 1] = segment end
    if type(target) ~= "table" then return false, "DATABASE_NOT_INITIALIZED" end
    if #segments == 0 then return false end
    for index = 1, #segments - 1 do
        local key = segments[index]
        target[key] = type(target[key]) == "table" and target[key] or {}
        target = target[key]
    end
    local key = segments[#segments]
    if target[key] == value then return false end
    target[key] = value
    if HolyStorm.Events then HolyStorm.Events:Emit("HS_CONFIG_CHANGED", path, value, scope or "profile") end
    return true
end

function Database:RegisterArea(id, scope, defaults)
    if type(id) ~= "string" or not ({ global=true, profile=true, character=true })[scope] then return false end
    self.areas[id] = { scope=scope, defaults=defaults or {} }
    return true
end

function Database:GetArea(id, guid)
    local area = self.areas[id]
    if not area then error("Unknown data area: " .. tostring(id)) end
    if area.scope == "character" then
        guid = guid or UnitGUID("player")
        if type(guid) ~= "string" then error("Character data needs a GUID") end
        local record = HolyStorm.Data.CharacterStore:GetOrCreate(guid)
        record[id] = HolyStorm.Utils.ApplyDefaults(record[id], area.defaults)
        return record[id]
    end
    local root = self:GetRoot(area.scope)
    root[id] = HolyStorm.Utils.ApplyDefaults(root[id], area.defaults)
    return root[id]
end

function Database:SetAreaValue(id, key, value, guid)
    local area = self:GetArea(id, guid)
    if area[key] == value then return false end
    area[key] = value
    HolyStorm.Events:Emit("HS_DATA_CHANGED", id, key, value, guid)
    return true
end

HolyStorm.Database = Database

-- DataManager is the public persistence contract. Database remains its
-- low-level AceDB backend during the incremental store migration.
local DataManager = {
    version = addonVersion,
    contractVersion = 1,
}

local schemaRegistry, migrationRegistry = {}, {}
local maxCopyDepth = 128
local allowedCopyTypes = { ["nil"]=true, boolean=true, number=true, string=true }
local allowedKeyTypes = { boolean=true, number=true, string=true }

local function copyPath(path, length)
    local parts={"$root"}
    for index=1,length do parts[#parts+1]=tostring(path[index]) end
    return table.concat(parts,".")
end

local function copyValue(value, copies, active, depth, maxDepth, path, pathLength)
    local valueType = type(value)
    if allowedCopyTypes[valueType] then return value end
    if valueType ~= "table" then return nil, "COPY_UNSUPPORTED_TYPE", copyPath(path,pathLength) .. " contains " .. valueType end
    if depth > maxDepth then return nil, "COPY_DEPTH_EXCEEDED", copyPath(path,pathLength) end
    if active[value] then return nil, "COPY_CYCLE", copyPath(path,pathLength) end
    if copies[value] then return copies[value] end
    local result = {}
    copies[value] = result
    active[value] = true
    for key, child in pairs(value) do
        local keyType = type(key)
        if not allowedKeyTypes[keyType] then
            active[value] = nil
            return nil, "COPY_UNSUPPORTED_KEY", copyPath(path,pathLength) .. " contains " .. keyType .. " key"
        end
        pathLength=pathLength+1;path[pathLength]=key
        local childCopy, errorCode, detail = copyValue(child, copies, active, depth + 1, maxDepth, path, pathLength)
        path[pathLength]=nil;pathLength=pathLength-1
        if errorCode then active[value] = nil; return nil, errorCode, detail end
        result[key] = childCopy
    end
    active[value] = nil
    return result
end

local function deepEqual(left, right, visited)
    if left == right then return true end
    if type(left) ~= type(right) or type(left) ~= "table" then return false end
    visited = visited or {}
    if visited[left] == right then return true end
    visited[left] = right
    for key, value in pairs(left) do if not deepEqual(value, right[key], visited) then return false end end
    for key in pairs(right) do if left[key] == nil then return false end end
    return true
end

local function normalizePath(value, allowEmpty)
    if value == nil or value == "" then return allowEmpty and {} or nil end
    local result = {}
    if type(value) == "string" then
        for segment in string.gmatch(value, "[^%.]+") do result[#result + 1] = segment end
    elseif type(value) == "table" then
        for index, segment in ipairs(value) do
            if type(segment) ~= "string" or segment == "" then return nil end
            result[index] = segment
        end
    else
        return nil
    end
    if #result == 0 and not allowEmpty then return nil end
    return result
end

local function resultFor(schema, schemaId, operation, ok, changed, fields)
    local result = { ok=ok == true, changed=changed == true, operation=operation, schema=schema and schema.id or schemaId, version=schema and schema.version or nil }
    for key, value in pairs(fields or {}) do result[key] = value end
    return result
end

function DataManager:_Log(level, result)
    if not HolyStorm.Logger or type(HolyStorm.Logger.Write) ~= "function" then return end
    local context = { schema=result.schema, version=result.version, fromVersion=result.fromVersion, toVersion=result.toVersion, operation=result.operation, errorCode=result.errorCode, detail=result.error }
    pcall(HolyStorm.Logger.Write, HolyStorm.Logger, level or "WARN", "DataManager", "persistence", "DataManager operation failed", context)
end

function DataManager:_Failure(schema, schemaId, operation, errorCode, detail, fields, level)
    fields = fields or {}
    fields.errorCode = errorCode
    fields.error = tostring(detail or errorCode)
    local result = resultFor(schema, schemaId, operation, false, false, fields)
    if level then self:_Log(level, result) end
    return result
end

function DataManager:_Success(schema, operation, changed, fields)
    return resultFor(schema, schema and schema.id, operation, true, changed, fields)
end

function DataManager:SafeCopy(value)
    local copied, errorCode, detail = copyValue(value, {}, {}, 0, maxCopyDepth, {}, 0)
    if errorCode then return nil, self:_Failure(nil, nil, "copy", errorCode, detail) end
    return copied, resultFor(nil, nil, "copy", true, false)
end

function DataManager:_Copy(value, schema, operation)
    local copied, errorCode, detail = copyValue(value, {}, {}, 0, maxCopyDepth, {}, 0)
    if errorCode then return nil, self:_Failure(schema, schema and schema.id, operation, errorCode, detail, nil, "WARN") end
    return copied
end

function DataManager:_Schema(schemaId, operation)
    local schema = type(schemaId) == "string" and schemaRegistry[schemaId] or nil
    if schema then return schema end
    return nil, self:_Failure(nil, schemaId, operation, "UNKNOWN_SCHEMA", schemaId)
end

function DataManager:_ValidateStorage(storage)
    if type(storage) ~= "table" then return nil, "INVALID_SCHEMA_STORAGE" end
    local backend = storage.backend or "database"
    if backend ~= "database" and backend ~= "player" then return nil, "INVALID_SCHEMA_BACKEND" end
    local scope = storage.scope
    if backend == "database" then
        scope = scope or "global"
        if scope == "char" then scope = "character" end
        if not ({ global=true, profile=true, character=true })[scope] then return nil, "INVALID_SCHEMA_SCOPE" end
    elseif scope ~= nil then
        return nil, "INVALID_SCHEMA_SCOPE"
    end
    local path = normalizePath(storage.path, backend ~= "database")
    if not path then return nil, "INVALID_SCHEMA_PATH" end
    return { backend=backend, scope=scope, path=path }
end

function DataManager:RegisterSchema(definition)
    local operation = "register-schema"
    if type(definition) ~= "table" then return self:_Failure(nil, nil, operation, "INVALID_SCHEMA", "definition must be a table") end
    local id = definition.id
    if type(id) ~= "string" or #id == 0 or #id > 128 or not string.match(id, "^[%w][%w_%.%-:]*$") then return self:_Failure(nil, id, operation, "INVALID_SCHEMA_ID", id) end
    if schemaRegistry[id] then return self:_Failure(schemaRegistry[id], id, operation, "SCHEMA_ALREADY_REGISTERED", id, nil, "WARN") end
    if type(definition.owner) ~= "string" or definition.owner == "" then return self:_Failure(nil, id, operation, "INVALID_SCHEMA_OWNER", definition.owner) end
    local version = tonumber(definition.version)
    if not version or version < 1 or version % 1 ~= 0 then return self:_Failure(nil, id, operation, "INVALID_SCHEMA_VERSION", definition.version) end
    if type(definition.validate) ~= "function" then return self:_Failure(nil, id, operation, "INVALID_SCHEMA_VALIDATOR", type(definition.validate)) end
    if definition.default ~= nil and type(definition.default) ~= "function" then return self:_Failure(nil, id, operation, "INVALID_DEFAULT_FACTORY", type(definition.default)) end
    if definition.event ~= nil and (type(definition.event) ~= "string" or definition.event == "") then return self:_Failure(nil, id, operation, "INVALID_SCHEMA_EVENT", definition.event) end
    if definition.metadata ~= nil and type(definition.metadata) ~= "table" then return self:_Failure(nil, id, operation, "INVALID_SCHEMA_METADATA", type(definition.metadata)) end
    if definition.migrations ~= nil and type(definition.migrations) ~= "table" then return self:_Failure(nil, id, operation, "INVALID_SCHEMA_MIGRATIONS", type(definition.migrations)) end
    if definition.versionField ~= nil and definition.versionField ~= false and (type(definition.versionField) ~= "string" or definition.versionField == "") then return self:_Failure(nil, id, operation, "INVALID_VERSION_FIELD", definition.versionField) end
    local storage, storageError = self:_ValidateStorage(definition.storage)
    if not storage then return self:_Failure(nil, id, operation, storageError, storageError) end
    local metadata, metadataError = self:_Copy(definition.metadata or {}, nil, operation)
    if not metadata then return metadataError end
    local pendingMigrations = {}
    for index, migration in ipairs(definition.migrations or {}) do
        if type(migration) ~= "table" or type(migration.migrate) ~= "function" then return self:_Failure(nil, id, operation, "INVALID_MIGRATION", index) end
        local fromVersion, toVersion = tonumber(migration.fromVersion), tonumber(migration.toVersion)
        if not fromVersion or fromVersion < 0 or fromVersion % 1 ~= 0 or not toVersion or toVersion ~= fromVersion + 1 or toVersion > version then return self:_Failure(nil, id, operation, "INVALID_MIGRATION_STEP", index) end
        if pendingMigrations[fromVersion] then return self:_Failure(nil, id, operation, "MIGRATION_ALREADY_REGISTERED", fromVersion) end
        pendingMigrations[fromVersion] = { fromVersion=fromVersion, toVersion=toVersion, migrate=migration.migrate }
    end
    local schema = {
        id=id, owner=definition.owner, version=version, validate=definition.validate, default=definition.default,
        metadata=metadata, storage=storage, versionField=definition.versionField == nil and "schemaVersion" or definition.versionField, event=definition.event,
    }
    schemaRegistry[id] = schema
    migrationRegistry[id] = pendingMigrations
    return self:_Success(schema, operation, true)
end

function DataManager:RegisterMigration(schemaId, fromVersion, toVersion, migrate)
    local operation = "register-migration"
    local schema, schemaError = self:_Schema(schemaId, operation)
    if not schema then return schemaError end
    fromVersion, toVersion = tonumber(fromVersion), tonumber(toVersion)
    if not fromVersion or fromVersion < 0 or fromVersion % 1 ~= 0 or not toVersion or toVersion ~= fromVersion + 1 or toVersion > schema.version or type(migrate) ~= "function" then
        return self:_Failure(schema, schemaId, operation, "INVALID_MIGRATION_STEP", tostring(fromVersion) .. "->" .. tostring(toVersion), { fromVersion=fromVersion, toVersion=toVersion }, "WARN")
    end
    local migrations = migrationRegistry[schemaId]
    if migrations[fromVersion] then return self:_Failure(schema, schemaId, operation, "MIGRATION_ALREADY_REGISTERED", tostring(fromVersion) .. "->" .. tostring(toVersion), { fromVersion=fromVersion, toVersion=toVersion }, "WARN") end
    migrations[fromVersion] = { fromVersion=fromVersion, toVersion=toVersion, migrate=migrate }
    return self:_Success(schema, operation, true, { fromVersion=fromVersion, toVersion=toVersion })
end

function DataManager:_BackendRoot(storage)
    if storage.backend == "database" then
        local root = Database:GetRoot(storage.scope)
        if type(root) ~= "table" then return nil, "DATABASE_NOT_INITIALIZED" end
        return root
    end
    if storage.backend == "player" then
        if type(HS_Player_DB) ~= "table" then return nil, "DATABASE_NOT_INITIALIZED" end
        return HS_Player_DB
    end
    return nil, "INVALID_SCHEMA_BACKEND"
end

function DataManager:_ReadLive(schema)
    local value, errorCode = self:_BackendRoot(schema.storage)
    if not value then return nil, false, errorCode end
    for _, segment in ipairs(schema.storage.path) do
        if type(value) ~= "table" then return nil, false end
        value = value[segment]
        if value == nil then return nil, false end
    end
    return value, true
end

function DataManager:_ReplaceLive(schema, value)
    local storage = schema.storage
    if #storage.path == 0 then
        if storage.backend == "player" then HS_Player_DB = value; return true end
        return false, "ROOT_REPLACE_UNSUPPORTED"
    end
    local root, rootError = self:_BackendRoot(storage)
    if not root then return false, rootError end
    local parent = root
    for index = 1, #storage.path - 1 do
        local segment = storage.path[index]
        local child = parent[segment]
        if child == nil then
            child = {}
            local cursor = child
            for nested = index + 1, #storage.path - 1 do local nextChild = {}; cursor[storage.path[nested]] = nextChild; cursor = nextChild end
            cursor[storage.path[#storage.path]] = value
            parent[segment] = child
            return true
        end
        if type(child) ~= "table" then return false, "STORAGE_PATH_CONFLICT" end
        parent = child
    end
    parent[storage.path[#storage.path]] = value
    return true
end

function DataManager:_NormalizeKey(key)
    if key == nil then return {} end
    if type(key) == "string" or type(key) == "number" then return { key } end
    if type(key) ~= "table" then return nil end
    local result = {}
    for index, segment in ipairs(key) do
        if type(segment) ~= "string" and type(segment) ~= "number" then return nil end
        result[index] = segment
    end
    return result
end

function DataManager:_ValueAt(root, keyPath)
    local value = root
    for _, segment in ipairs(keyPath) do
        if type(value) ~= "table" then return nil, false end
        value = value[segment]
        if value == nil then return nil, false end
    end
    return value, true
end

function DataManager:_SetAt(root, keyPath, value)
    if #keyPath == 0 then return value end
    if type(root) ~= "table" then return nil, "KEY_PARENT_NOT_TABLE" end
    local parent = root
    for index = 1, #keyPath - 1 do
        local segment = keyPath[index]
        if parent[segment] == nil then parent[segment] = {} end
        if type(parent[segment]) ~= "table" then return nil, "KEY_PARENT_NOT_TABLE" end
        parent = parent[segment]
    end
    parent[keyPath[#keyPath]] = value
    return root
end

function DataManager:_DataVersion(schema, data)
    if schema.versionField == false then return schema.version end
    if type(data) ~= "table" then return nil end
    local version = tonumber(data[schema.versionField])
    if not version or version < 0 or version % 1 ~= 0 then return nil end
    return version
end

function DataManager:_Validate(schema, data, context, operation)
    local version = self:_DataVersion(schema, data)
    if version ~= schema.version then return self:_Failure(schema, schema.id, operation, version and "SCHEMA_VERSION_MISMATCH" or "SCHEMA_VERSION_MISSING", version, { dataVersion=version }, "WARN") end
    local called, accepted, validatorCode, detail = pcall(schema.validate, data, context or {})
    if not called then return self:_Failure(schema, schema.id, operation, "VALIDATOR_ERROR", accepted, nil, "ERROR") end
    if type(accepted) == "table" then
        if accepted.ok == true then return true end
        return self:_Failure(schema, schema.id, operation, "VALIDATION_FAILED", accepted.error or accepted.errorCode, { validationCode=accepted.errorCode, validationDetail=accepted.detail }, "WARN")
    end
    if accepted ~= true then return self:_Failure(schema, schema.id, operation, "VALIDATION_FAILED", detail or validatorCode, { validationCode=validatorCode, validationDetail=detail }, "WARN") end
    return true
end

function DataManager:_Default(schema, context, operation)
    if type(schema.default) ~= "function" then return nil, self:_Failure(schema, schema.id, operation, "DATA_NOT_FOUND", schema.id) end
    local called, value = pcall(schema.default, context or {})
    if not called then return nil, self:_Failure(schema, schema.id, operation, "DEFAULT_FACTORY_ERROR", value, nil, "ERROR") end
    if type(value) ~= "table" then return nil, self:_Failure(schema, schema.id, operation, "INVALID_DEFAULT_VALUE", type(value), nil, "WARN") end
    local copied, copyError = self:_Copy(value, schema, operation)
    if not copied then return nil, copyError end
    return copied
end

function DataManager:Get(schemaId, key)
    local operation = "get"
    local schema, schemaError = self:_Schema(schemaId, operation)
    if not schema then return nil, schemaError end
    local keyPath = self:_NormalizeKey(key)
    if not keyPath then return nil, self:_Failure(schema, schemaId, operation, "INVALID_KEY", type(key)) end
    local root, exists, readError = self:_ReadLive(schema)
    if readError then return nil, self:_Failure(schema, schemaId, operation, readError, readError) end
    if not exists then return nil, self:_Success(schema, operation, false, { exists=false }) end
    local value, valueExists = self:_ValueAt(root, keyPath)
    if not valueExists then return nil, self:_Success(schema, operation, false, { exists=false }) end
    local copied, copyError = self:_Copy(value, schema, operation)
    if copied == nil and value ~= nil then return nil, copyError end
    return copied, self:_Success(schema, operation, false, { exists=true })
end

function DataManager:GetCopy(schemaId, key) return self:Get(schemaId, key) end

function DataManager:Exists(schemaId, key)
    local operation = "exists"
    local schema, schemaError = self:_Schema(schemaId, operation)
    if not schema then return false, schemaError end
    local keyPath = self:_NormalizeKey(key)
    if not keyPath then return false, self:_Failure(schema, schemaId, operation, "INVALID_KEY", type(key)) end
    local root, exists, readError = self:_ReadLive(schema)
    if readError then return false, self:_Failure(schema, schemaId, operation, readError, readError) end
    if exists then _, exists = self:_ValueAt(root, keyPath) end
    return exists == true, self:_Success(schema, operation, false, { exists=exists == true })
end

function DataManager:GetMetadata(schemaId)
    local operation = "get-metadata"
    local schema, schemaError = self:_Schema(schemaId, operation)
    if not schema then return nil, schemaError end
    local descriptor = { id=schema.id, owner=schema.owner, version=schema.version, versionField=schema.versionField, event=schema.event, metadata=schema.metadata, storage=schema.storage }
    local copied, copyError = self:_Copy(descriptor, schema, operation)
    if not copied then return nil, copyError end
    return copied, self:_Success(schema, operation, false)
end

function DataManager:_EmitCommitted(schema, result, context)
    if not schema.event or not HolyStorm.Events or type(HolyStorm.Events.Emit) ~= "function" then return end
    local called, eventError = pcall(HolyStorm.Events.Emit, HolyStorm.Events, schema.event, schema.id, result, context or {})
    if not called then
        result.eventError = tostring(eventError)
        self:_Log("ERROR", self:_Failure(schema, schema.id, "event", "EVENT_HANDLER_ERROR", eventError))
    end
end

function DataManager:_CommitRoot(schema, oldRoot, working, keyPath, operation, context, fields)
    if type(working) ~= "table" then return self:_Failure(schema, schema.id, operation, "INVALID_SCHEMA_ROOT", type(working), fields, "WARN") end
    local detached, copyError = self:_Copy(working, schema, operation)
    if not detached then return copyError end
    local validation = self:_Validate(schema, detached, context, operation)
    if validation ~= true then return validation end
    if oldRoot ~= nil and deepEqual(oldRoot, detached) then
        local unchanged = self:_Success(schema, operation, false, fields)
        local value = self:_ValueAt(detached, keyPath)
        unchanged.value = self:_Copy(value, schema, operation)
        return unchanged
    end
    local replaced, replaceError = self:_ReplaceLive(schema, detached)
    if not replaced then return self:_Failure(schema, schema.id, operation, "PERSISTENCE_REPLACE_FAILED", replaceError, fields, "ERROR") end
    local committed = self:_Success(schema, operation, true, fields)
    local value = self:_ValueAt(detached, keyPath)
    committed.value = self:_Copy(value, schema, operation)
    self:_EmitCommitted(schema, committed, context)
    return committed
end

function DataManager:Commit(schemaId, key, value, context)
    local operation = "commit"
    local schema, schemaError = self:_Schema(schemaId, operation)
    if not schema then return schemaError end
    local keyPath = self:_NormalizeKey(key)
    if not keyPath then return self:_Failure(schema, schemaId, operation, "INVALID_KEY", type(key)) end
    local liveRoot, exists, readError = self:_ReadLive(schema)
    if readError then return self:_Failure(schema, schemaId, operation, readError, readError) end
    local working, workingError
    if exists then working, workingError = self:_Copy(liveRoot, schema, operation) else working, workingError = self:_Default(schema, context, operation) end
    if not working then return workingError end
    local proposed, proposedError = self:_Copy(value, schema, operation)
    if proposed == nil and value ~= nil then return proposedError end
    working, proposedError = self:_SetAt(working, keyPath, proposed)
    if not working then return self:_Failure(schema, schemaId, operation, proposedError, proposedError, nil, "WARN") end
    return self:_CommitRoot(schema, exists and liveRoot or nil, working, keyPath, operation, context)
end

function DataManager:Update(schemaId, key, mutator, context)
    local operation = "update"
    local schema, schemaError = self:_Schema(schemaId, operation)
    if not schema then return schemaError end
    if type(mutator) ~= "function" then return self:_Failure(schema, schemaId, operation, "INVALID_MUTATOR", type(mutator)) end
    local keyPath = self:_NormalizeKey(key)
    if not keyPath then return self:_Failure(schema, schemaId, operation, "INVALID_KEY", type(key)) end
    local liveRoot, exists, readError = self:_ReadLive(schema)
    if readError then return self:_Failure(schema, schemaId, operation, readError, readError) end
    local working, workingError
    if exists then working, workingError = self:_Copy(liveRoot, schema, operation) else working, workingError = self:_Default(schema, context, operation) end
    if not working then return workingError end
    local draft, draftExists = self:_ValueAt(working, keyPath)
    if not draftExists and #keyPath > 0 then draft = nil end
    local called, decision, abortCode, abortDetail = pcall(mutator, draft, context or {})
    if not called then return self:_Failure(schema, schemaId, operation, "MUTATOR_ERROR", decision, nil, "ERROR") end
    if decision == false then return self:_Failure(schema, schemaId, operation, "TRANSACTION_ABORTED", abortDetail or abortCode, { transactionCode=abortCode }, "WARN") end
    if decision ~= nil and decision ~= true then
        local replacement, replacementError = self:_Copy(decision, schema, operation)
        if replacement == nil and decision ~= nil then return replacementError end
        working, replacementError = self:_SetAt(working, keyPath, replacement)
        if not working then return self:_Failure(schema, schemaId, operation, replacementError, replacementError, nil, "WARN") end
    end
    return self:_CommitRoot(schema, exists and liveRoot or nil, working, keyPath, operation, context)
end

function DataManager:Transaction(schemaId, key, mutator, context) return self:Update(schemaId, key, mutator, context) end

function DataManager:RunMigrations(schemaId, context)
    local operation = "migrate"
    local schema, schemaError = self:_Schema(schemaId, operation)
    if not schema then return schemaError end
    if schema.versionField == false then return self:_Failure(schema, schemaId, operation, "SCHEMA_NOT_VERSIONED", schemaId, nil, "WARN") end
    local liveRoot, exists, readError = self:_ReadLive(schema)
    if readError then return self:_Failure(schema, schemaId, operation, readError, readError) end
    if not exists then return self:_Failure(schema, schemaId, operation, "DATA_NOT_FOUND", schemaId) end
    local fromVersion = self:_DataVersion(schema, liveRoot)
    if fromVersion == nil then return self:_Failure(schema, schemaId, operation, "SCHEMA_VERSION_MISSING", schema.versionField, nil, "WARN") end
    if fromVersion > schema.version then return self:_Failure(schema, schemaId, operation, "SCHEMA_VERSION_NEWER", fromVersion, { fromVersion=fromVersion, toVersion=schema.version }, "WARN") end
    if fromVersion == schema.version then return self:_Success(schema, operation, false, { fromVersion=fromVersion, toVersion=schema.version }) end
    local working, copyError = self:_Copy(liveRoot, schema, operation)
    if not working then return copyError end
    local current = fromVersion
    while current < schema.version do
        local migration = migrationRegistry[schemaId] and migrationRegistry[schemaId][current]
        if not migration or migration.toVersion ~= current + 1 then return self:_Failure(schema, schemaId, operation, "MIGRATION_PATH_MISSING", tostring(current) .. "->" .. tostring(current + 1), { fromVersion=current, toVersion=current + 1 }, "WARN") end
        local called, replacement, migrationCode, migrationDetail = pcall(migration.migrate, working, context or {})
        if not called then return self:_Failure(schema, schemaId, operation, "MIGRATION_ERROR", replacement, { fromVersion=current, toVersion=migration.toVersion }, "ERROR") end
        if replacement == false then return self:_Failure(schema, schemaId, operation, "MIGRATION_REJECTED", migrationDetail or migrationCode, { fromVersion=current, toVersion=migration.toVersion, migrationCode=migrationCode }, "ERROR") end
        if replacement ~= nil and replacement ~= true then
            if type(replacement) ~= "table" then return self:_Failure(schema, schemaId, operation, "INVALID_MIGRATION_RESULT", type(replacement), { fromVersion=current, toVersion=migration.toVersion }, "ERROR") end
            local replacementCopy, replacementError = self:_Copy(replacement, schema, operation)
            if not replacementCopy then return replacementError end
            working = replacementCopy
        end
        working[schema.versionField] = migration.toVersion
        current = migration.toVersion
    end
    return self:_CommitRoot(schema, liveRoot, working, {}, operation, context, { fromVersion=fromVersion, toVersion=current })
end

-- Compatibility surface from the former stub. Reads are defensive and no
-- longer initialize missing data; writes retain the legacy Database behavior.
function DataManager:RegisterArea(...) return Database:RegisterArea(...) end

function DataManager:GetArea(id, guid)
    local area = Database.areas[id]
    if not area then return nil end
    local value
    if area.scope == "character" then
        guid = guid or UnitGUID("player")
        local record = type(guid) == "string" and HolyStorm.Data.CharacterStore:Get(guid) or nil
        value = record and record[id]
    else
        local root = Database:GetRoot(area.scope)
        value = root and root[id]
    end
    if value == nil then value = area.defaults end
    local copied = self:SafeCopy(value)
    return copied
end

function DataManager:Set(...) return Database:SetAreaValue(...) end

HolyStorm.DataManager = DataManager

HolyStorm.ConfigManager = {
    RegisterDefaults=function(_,scope,defaults) local root=Database:GetRoot(scope); HolyStorm.Utils.ApplyDefaults(root,defaults or {}); return true end,
    Get=function(_,...) return Database:Get(...) end,
    Set=function(_,...) return Database:Set(...) end,
}
