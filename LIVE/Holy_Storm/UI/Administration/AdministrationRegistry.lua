local addonVersion = "1.0.0"
local HolyStorm = LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local Administration = { version=addonVersion, sections={}, active={}, initialized=false }

local function copy(value)
    local result={}
    for key,item in pairs(value or {}) do
        if (key=="requiredPermission" or key=="events") and type(item)=="table" then result[key]=HolyStorm.Utils.DeepCopy(item)
        else result[key]=item end
    end
    return result
end
local function validId(id) return type(id)=="string" and id:match("^[%w%-_]+$")~=nil end

function Administration:CanAccess(section)
    local permission=section.requiredPermission
    if permission then
        local allowed=false
        if type(permission)=="table" then
            for _,id in ipairs(permission) do if HolyStorm.PermissionEngine:HasPermission(nil,nil,id) then allowed=true; break end end
        else allowed=HolyStorm.PermissionEngine:HasPermission(nil,nil,permission) end
        if not allowed then return false,"PERMISSION_DENIED" end
    end
    if section.moduleId then
        local entry=HolyStorm.GetModuleEntry and HolyStorm:GetModuleEntry(section.moduleId)
        if not entry then return false,"MODULE_UNAVAILABLE" end
        if HolyStorm.PolicyState and not HolyStorm.PolicyState:IsGuildModuleEnabled(section.moduleId) then return false,"MODULE_DISABLED" end
    end
    if section.isAvailable then
        local ok,available=HolyStorm.Utils.SafeCall("administration.available:"..section.id,section.isAvailable,section)
        if not ok or not available then return false,"SECTION_UNAVAILABLE" end
    end
    return true
end

function Administration:ActivateSection(id)
    local section=self.sections[id]; if not section or self.active[id] then return section~=nil end
    local available=self:CanAccess(section); if not available then return false end
    if not section.page and section.build then
        local ok,page=HolyStorm.Utils.SafeCall("administration.build:"..id,section.build,section)
        if not ok or not page then return false end
        section.page=page
    end
    if not section.page then return false end
    local title=section.displayName or section.displayNameKey or section.id
    local description=section.description or section.descriptionKey or title
    HolyStorm.UI:RegisterPage(section.id,section.page,title,function() if section.render then section.render(section) end end,section.events)
    HolyStorm.UI:AddNavigation(section.id,section.order,section.icon or "Interface\\Icons\\INV_Misc_Gear_01",title,description,function() HolyStorm.UI:ShowPage(section.id) end)
    self.active[id]=true
    return true
end

function Administration:DeactivateSection(id)
    if not self.active[id] then return false end
    HolyStorm.UI:UnregisterPage(id); HolyStorm.UI:RemoveNavigation(id); self.active[id]=nil; return true
end

function Administration:RefreshSections()
    for id,section in pairs(self.sections) do
        local available=self:CanAccess(section)
        if available then self:ActivateSection(id) else self:DeactivateSection(id) end
    end
end

function Administration:Initialize()
    if self.initialized then return end
    self.initialized=true
    for _,event in ipairs({"HS_EFFECTIVE_PERMISSIONS_CHANGED","HS_PERMISSIONS_STATE_UPDATED","HS_GROUP_UPDATED"}) do
        HolyStorm.Events:Register(event,"administration-registry",function() Administration:RefreshSections() end)
    end
end

function Administration:RegisterSection(definition)
    if type(definition)~="table" or not validId(definition.id) or (not definition.page and type(definition.build)~="function") or (definition.render~=nil and type(definition.render)~="function") or (definition.isAvailable~=nil and type(definition.isAvailable)~="function") then return false,"INVALID_ADMINISTRATION_SECTION" end
    if self.sections[definition.id] then return false,"ADMINISTRATION_SECTION_EXISTS" end
    local section=copy(definition); section.order=tonumber(section.order) or 100; section.owner=section.owner or section.moduleId or "Core"; self.sections[section.id]=section
    self:Initialize(); self:ActivateSection(section.id); HolyStorm.Events:Emit("HS_ADMINISTRATION_SECTION_REGISTERED",section.id)
    return true
end
function Administration:UnregisterSection(id)
    if not self.sections[id] then return false,"NOT_FOUND" end
    self:DeactivateSection(id); self.sections[id]=nil; HolyStorm.Events:Emit("HS_ADMINISTRATION_SECTION_UNREGISTERED",id); return true
end
function Administration:GetSection(id) local section=self.sections[id]; return section and copy(section) end
function Administration:GetSections(visibleOnly)
    local result={}; for id,section in pairs(self.sections) do if not visibleOnly or self.active[id] then result[#result+1]=copy(section) end end
    table.sort(result,function(left,right) if left.order==right.order then return left.id<right.id end; return left.order<right.order end); return result
end

HolyStorm.Administration = Administration
function HolyStorm:RegisterAdministrationSection(definition) return Administration:RegisterSection(definition) end
function HolyStorm:GetAdministrationSections(visibleOnly) return Administration:GetSections(visibleOnly) end
