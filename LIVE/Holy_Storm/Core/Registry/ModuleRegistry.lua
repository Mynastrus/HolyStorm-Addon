local addonVersion = "2.2.0"
local HolyStorm = LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local L = LibStub("AceLocale-3.0"):GetLocale("Holy_Storm")

HolyStorm.moduleRegistryVersion = addonVersion
HolyStorm.optionalModuleFactories = {}
HolyStorm.moduleCapabilities = {}
HolyStorm.pendingModulePermissions = HolyStorm.pendingModulePermissions or {}
HolyStorm.pendingAdministrationSections = HolyStorm.pendingAdministrationSections or {}

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
    normalized.ruleFields = type(normalized.ruleFields) == "table" and normalized.ruleFields or {}
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
    if not registry then self.pendingModulePermissions[metadata.id]=metadata; return 0 end
    local registered=0
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
            if registry:RegisterPermission(definition) then registered=registered+1 end
        end
    end
    self.pendingModulePermissions[metadata.id]=nil
    return registered
end

function HolyStorm:FlushModulePermissions()
    if not self.PermissionRegistry then return 0 end
    local ids={}; for id in pairs(self.pendingModulePermissions) do ids[#ids+1]=id end; table.sort(ids)
    local registered=0; for _,id in ipairs(ids) do registered=registered+self:RegisterModulePermissions(self.pendingModulePermissions[id]) end
    return registered
end

function HolyStorm:RegisterModuleRuleFields(metadata)
    if not HolyStorm.Rules or type(metadata)~="table" then return 0 end
    local registered=0
    for key,entry in pairs(metadata.ruleFields or {}) do
        if type(entry)=="table" then
            local definition=HolyStorm.Utils.DeepCopy(entry)
            local fieldID=definition.id or (type(key)=="string" and key or nil)
            local aliases=definition.aliases
            definition.id,definition.aliases=nil,nil
            local ok=fieldID and HolyStorm.Rules:RegisterField(metadata.id,fieldID,definition)
            if ok then
                registered=registered+1
                for _,aliasID in ipairs(type(aliases)=="table" and aliases or {}) do HolyStorm.Rules:RegisterAlias(metadata.id,aliasID,fieldID) end
            end
        end
    end
    return registered
end

function HolyStorm:RegisterModuleAdministration(metadata)
    if type(metadata)~="table" or type(metadata.administration)~="table" then return 0 end
    local definitions=metadata.administration.id and {metadata.administration} or metadata.administration
    local registered=0
    for _,entry in ipairs(definitions) do
        if type(entry)=="table" then
            local definition=copyMetadata(entry)
            definition.owner=definition.owner or metadata.id
            definition.moduleId=definition.moduleId or metadata.id
            definition.requires=type(definition.requires)=="table" and HolyStorm.Utils.DeepCopy(definition.requires) or {}
            definition.requires.module=definition.requires.module or metadata.id
            local key=tostring(definition.owner)..":"..tostring(definition.id)
            if self.Administration then
                local ok,reason=self.Administration:RegisterSection(definition)
                if ok or reason=="ADMINISTRATION_SECTION_EXISTS" then registered=registered+1 end
                self.pendingAdministrationSections[key]=nil
            else
                self.pendingAdministrationSections[key]=definition
            end
        end
    end
    return registered
end

function HolyStorm:FlushAdministrationSections()
    if not self.Administration then return 0 end
    local keys={}; for key in pairs(self.pendingAdministrationSections) do keys[#keys+1]=key end; table.sort(keys)
    local registered=0
    for _,key in ipairs(keys) do
        local definition=self.pendingAdministrationSections[key]
        local ok,reason=self.Administration:RegisterSection(definition)
        if ok or reason=="ADMINISTRATION_SECTION_EXISTS" then self.pendingAdministrationSections[key]=nil; registered=registered+1 end
    end
    return registered
end

function HolyStorm:ApplyModuleMetadata(module, metadata)
    local normalized = self:NormalizeModuleMetadata(metadata, module and module:GetName(), "required")
    module.metadata = normalized
    module.version = normalized.version
    self:RegisterModulePermissions(normalized)
    self:RegisterModuleRuleFields(normalized)
    self:RegisterModuleAdministration(normalized)
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
    if self.Events then self.Events:Emit("HS_CAPABILITY_REGISTERED",capability,moduleName) end
    return true
end

function HolyStorm:UnregisterCapability(moduleName, capability)
    local handlers=self.moduleCapabilities[capability]
    if not handlers or not handlers[moduleName] then return false end
    handlers[moduleName]=nil; if not next(handlers) then self.moduleCapabilities[capability]=nil end
    if self.Events then self.Events:Emit("HS_CAPABILITY_UNREGISTERED",capability,moduleName) end
    return true
end

function HolyStorm:GetLoadedModuleById(id)
    if type(id)~="string" then return nil end
    local direct=self:GetModule(id,true); if direct then return direct end
    for name,module in self:IterateModules() do
        local metadata=module.metadata or {}
        if name==id or metadata.id==id or metadata.internalName==id or metadata.name==id then return module end
    end
end

function HolyStorm:IsModuleAvailable(id, requireEnabled)
    local module=self:GetLoadedModuleById(id)
    if not module then return false end
    return requireEnabled==false or not module.IsEnabled or module:IsEnabled()
end

function HolyStorm:IsCapabilityAvailable(capability, moduleId)
    local handlers=self.moduleCapabilities[capability]
    if type(handlers)~="table" then return false end
    for owner in pairs(handlers) do
        local module=self:GetLoadedModuleById(owner)
        local metadata=module and module.metadata or {}
        local ownerMatches=not moduleId or owner==moduleId or metadata.id==moduleId or metadata.internalName==moduleId or metadata.name==moduleId
        if ownerMatches and module and (not module.IsEnabled or module:IsEnabled()) then return true end
    end
    return false
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
    local result=self.Database:Set("optionalModules." .. moduleName, enabled == true, "profile")
    if self.Events then self.Events:Emit("HS_MODULE_AVAILABILITY_CHANGED",moduleName,enabled==true,"profile") end
    return result
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
        if type(original)=="function" or methodName=="OnEnable" or methodName=="OnDisable" then
            module[methodName]=function(self,...)
                if methodName=="OnInitialize" then
                    for _,dependency in ipairs((self.metadata and self.metadata.dependencies) or {}) do
                        local available=dependency=="core" or (dependency=="ui" and HolyStorm:GetModule("UI",true)~=nil) or (dependency=="options" and HolyStorm:GetModule("Options",true)~=nil) or (dependency=="synchronization" and HolyStorm.Sync~=nil)
                        if not available then HolyStorm.Logger:WARN("ModuleRegistry","%s disabled: dependency %s is unavailable",self:GetName(),dependency); self:SetEnabledState(false); return end
                    end
                end
                if methodName=="OnEnable" then HolyStorm:RegisterModuleRuleFields(self.metadata) end
                local ok,err=true
                if original then ok,err=HolyStorm.Utils.SafeCall((self.metadata and self.metadata.internalName or self:GetName())..":"..methodName,original,self,...) end
                if methodName=="OnDisable" and self.metadata then
                    if HolyStorm.Rules then HolyStorm.Rules:UnregisterOwner(self.metadata.id) end
                end
                if (methodName=="OnEnable" or methodName=="OnDisable") and HolyStorm.Events then HolyStorm.Events:Emit("HS_MODULE_AVAILABILITY_CHANGED",self.metadata and self.metadata.id or self:GetName(),methodName=="OnEnable","lifecycle") end
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
