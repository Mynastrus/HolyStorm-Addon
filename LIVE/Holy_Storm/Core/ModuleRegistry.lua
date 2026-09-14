local addonVersion = "2.0.0"
local HolyStorm = LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local L = LibStub("AceLocale-3.0"):GetLocale("Holy_Storm")

HolyStorm.moduleRegistryVersion = addonVersion
HolyStorm.optionalModuleFactories = {}
HolyStorm.moduleCapabilities = {}

function HolyStorm:ApplyModuleMetadata(module, metadata)
    assert(type(metadata.displayName) == "string", L["ERROR_MODULE_DISPLAY_NAME"])
    assert(type(metadata.internalName) == "string", L["ERROR_MODULE_INTERNAL_NAME"])
    assert(type(metadata.version) == "string", L["ERROR_MODULE_VERSION"])

    module.metadata = metadata
    module.version = metadata.version
end

function HolyStorm:RegisterRequiredModule(moduleName)
    local module = self:NewModule(moduleName, "AceEvent-3.0")
    self.Modules[moduleName] = module
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

    self.optionalModuleFactories[moduleName] = {
        factory = factory,
        metadata = metadata,
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
        self.metadata,
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
