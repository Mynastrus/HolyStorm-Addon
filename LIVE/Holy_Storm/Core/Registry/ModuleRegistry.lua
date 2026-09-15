local addonVersion = "2.1.0"
local HolyStorm = LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local L = LibStub("AceLocale-3.0"):GetLocale("Holy_Storm")

HolyStorm.moduleRegistryVersion = addonVersion
HolyStorm.optionalModuleFactories = {}
HolyStorm.moduleCapabilities = {}

local function copyMetadata(metadata)
    local copy = {}
    for key, value in pairs(metadata or {}) do copy[key] = value end
    return copy
end

function HolyStorm:NormalizeModuleMetadata(metadata, fallbackId, defaultCategory)
    assert(type(metadata) == "table", L["ERROR_OPTIONAL_MODULE_METADATA"] or "Invalid module metadata")
    local normalized = copyMetadata(metadata)
    normalized.id = normalized.id or fallbackId or normalized.internalName
    normalized.internalName = normalized.internalName or normalized.id
    normalized.name = normalized.name or normalized.internalName
    normalized.displayName = normalized.displayName or normalized.name
    normalized.description = normalized.description or normalized.displayName
    normalized.version = normalized.version or "0.0.0"
    normalized.moduleType = normalized.moduleType or (normalized.category == "core" and "core" or "feature")
    normalized.category = normalized.category or defaultCategory or "required"
    normalized.dependencies = type(normalized.dependencies) == "table" and normalized.dependencies or {}
    normalized.capabilities = type(normalized.capabilities) == "table" and normalized.capabilities or {}
    normalized.ui = type(normalized.ui) == "table" and normalized.ui or {}
    normalized.options = type(normalized.options) == "table" and normalized.options or {}
    normalized.administration = type(normalized.administration) == "table" and normalized.administration or {}
    normalized.data = type(normalized.data) == "table" and normalized.data or {}
    normalized.sync = type(normalized.sync) == "table" and normalized.sync or {}
    normalized.permissions = type(normalized.permissions) == "table" and normalized.permissions or {}
    assert(type(normalized.id) == "string" and normalized.id ~= "", L["ERROR_MODULE_INTERNAL_NAME"])
    assert(type(normalized.name) == "string" and normalized.name ~= "", L["ERROR_MODULE_INTERNAL_NAME"])
    assert(type(normalized.displayName) == "string", L["ERROR_MODULE_DISPLAY_NAME"])
    assert(type(normalized.description) == "string", L["ERROR_MODULE_DISPLAY_NAME"])
    assert(type(normalized.version) == "string", L["ERROR_MODULE_VERSION"])
    assert(type(normalized.moduleType) == "string" and normalized.moduleType ~= "", L["ERROR_MODULE_INTERNAL_NAME"])
    assert(type(normalized.category) == "string" and normalized.category ~= "", L["ERROR_MODULE_INTERNAL_NAME"])
    return normalized
end

function HolyStorm:RegisterModulePermissions(metadata)
    local registry = HolyStorm.PermissionRegistry
    if not registry then return end
    for _, entry in ipairs(metadata.permissions or {}) do
        local definition
        if type(entry) == "table" then
            definition = HolyStorm.Utils.DeepCopy(entry)
        elseif type(entry) == "string" and not registry:GetPermission(entry) then
            definition = { id = entry }
        end
        if definition then
            definition.module = definition.module or metadata.id
            definition.owner = definition.owner or definition.module
            definition.category = definition.category or metadata.name or "Feature"
            registry:RegisterPermission(definition)
        end
    end
end

function HolyStorm:ApplyModuleMetadata(module, metadata)
    local normalized = self:NormalizeModuleMetadata(metadata, module and module:GetName(), "required")
    module.metadata = normalized
    module.version = normalized.version
    return normalized
end

function HolyStorm:RegisterRequiredModule(moduleName)
    local module = self:NewModule(moduleName, "AceEvent-3.0")
    self.Modules[moduleName] = module
    return module
end

function HolyStorm:RegisterModule(metadata, factory)
    local normalized = self:NormalizeModuleMetadata(metadata, nil, metadata and metadata.category or "optional")
    assert(type(factory) == "function", L["ERROR_OPTIONAL_MODULE_FACTORY"])
    if normalized.category == "optional" then
        self.optionalModuleFactories[normalized.id] = { factory = factory, metadata = normalized }
        return normalized
    end
    self:RegisterModulePermissions(normalized)
    local module = self:NewModule(normalized.id, "AceEvent-3.0")
    self.Modules[normalized.id] = module
    self:ApplyModuleMetadata(module, normalized)
    factory(module)
    return module
end

function HolyStorm:RegisterCapability(moduleName, capability, handler)
    assert(type(moduleName) == "string" and type(capability) == "string", "Invalid module capability")
    assert(type(handler) == "function", "Invalid capability handler")
    self.moduleCapabilities[capability] = self.moduleCapabilities[capability] or {}
    self.moduleCapabilities[capability][moduleName] = handler
end

function HolyStorm:CallCapability(capability, ...)
    local handlers = self.moduleCapabilities[capability]
    if not handlers then return {} end
    local results = {}
    for moduleName, handler in pairs(handlers) do
        local module = self:GetModule(moduleName, true)
        if module and module:IsEnabled() then local ok,result=HolyStorm.Utils.SafeCall("capability:"..capability..":"..moduleName,handler,module,...); if ok then results[moduleName]=result else HolyStorm.Logger:ERROR("ModuleRegistry","Capability %s failed in %s",capability,moduleName) end end
    end
    return results
end

function HolyStorm:RegisterOptionalModule(moduleName, metadata, factory)
    assert(type(moduleName) == "string", L["ERROR_OPTIONAL_MODULE_NAME"])
    assert(type(metadata) == "table", L["ERROR_OPTIONAL_MODULE_METADATA"])
    assert(type(factory) == "function", L["ERROR_OPTIONAL_MODULE_FACTORY"])

    local normalized = self:NormalizeModuleMetadata(metadata, moduleName, "optional")
    self.optionalModuleFactories[moduleName] = {
        factory = factory,
        metadata = normalized,
    }
end

function HolyStorm:IsOptionalModuleEnabled(moduleName)
    return self.Database:Get("optionalModules." .. moduleName, "profile") == true
end

function HolyStorm:SetOptionalModuleEnabled(moduleName, enabled)
    return self.Database:Set("optionalModules." .. moduleName, enabled == true, "profile")
end

function HolyStorm:CreateOptionalModule(moduleName)
    local registration = self.optionalModuleFactories[moduleName]

    if not registration then
        return nil
    end

    local module = self:GetModule(moduleName, true)

    if module then
        return module
    end

    module = self:NewModule(moduleName)
    self:RegisterModulePermissions(registration.metadata)
    self:ApplyModuleMetadata(module, registration.metadata)
    local ok, err = HolyStorm.Utils.SafeCall("module:" .. moduleName, registration.factory, module)
    if not ok then HolyStorm.Logger:ERROR("ModuleRegistry", "Module %s failed to load: %s", moduleName, tostring(err)); return nil end
    self.Modules[moduleName] = module
    self:ProtectModule(module)
    return module
end

function HolyStorm:ProtectModule(module)
    if not module or module.holyStormProtected then return end; module.holyStormProtected=true
    for _,methodName in ipairs({"OnInitialize","OnEnable","OnDisable"}) do
        local original=module[methodName]
        if type(original)=="function" then
            module[methodName]=function(self,...)
                if methodName=="OnInitialize" then
                    for _,dependency in ipairs((self.metadata and self.metadata.dependencies) or {}) do
                        local available=dependency=="core" or (dependency=="ui" and HolyStorm:GetModule("UI",true)~=nil) or (dependency=="options" and HolyStorm:GetModule("Options",true)~=nil) or (dependency=="synchronization" and HolyStorm.Sync~=nil)
                        if not available then HolyStorm.Logger:WARN("ModuleRegistry","%s disabled: dependency %s is unavailable",self:GetName(),dependency); self:SetEnabledState(false); return end
                    end
                end
                local ok,err=HolyStorm.Utils.SafeCall((self.metadata and self.metadata.internalName or self:GetName())..":"..methodName,original,self,...)
                if not ok then HolyStorm.Logger:ERROR("ModuleRegistry","%s failed in %s: %s",self:GetName(),methodName,tostring(err)); if methodName~="OnDisable" then self:SetEnabledState(false) end end
            end
        end
    end
end

function HolyStorm:ProtectRegisteredModules() for _,module in self:IterateModules() do self:ProtectModule(module) end end

function HolyStorm:LoadConfiguredOptionalModules()
    for moduleName in pairs(self.optionalModuleFactories) do
        if self:IsOptionalModuleEnabled(moduleName) then
            self:CreateOptionalModule(moduleName)
        end
    end
end

function HolyStorm:GetModuleEntries()
    local entries = {
        self:NormalizeModuleMetadata(self.metadata, self.metadata and self.metadata.internalName or "core", "core"),
    }

    for _, module in self:IterateModules() do
        table.insert(entries, module.metadata)
    end

    for moduleName, registration in pairs(self.optionalModuleFactories) do
        if not self:GetModule(moduleName, true) then
            table.insert(entries, registration.metadata)
        end
    end

    table.sort(entries, function(left, right)
        return left.displayName < right.displayName
    end)

    return entries
end

function HolyStorm:GetModuleEntry(id)
    if type(id) ~= "string" then return nil end
    for _, metadata in ipairs(self:GetModuleEntries()) do
        if metadata.id == id or metadata.internalName == id then return metadata end
    end
    return nil
end
