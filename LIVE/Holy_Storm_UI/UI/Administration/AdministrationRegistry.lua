local addonVersion = "2.1.0"
local HolyStorm = LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local localeLibrary = LibStub("AceLocale-3.0", true)
local L = localeLibrary and localeLibrary.GetLocale and localeLibrary:GetLocale("Holy_Storm_Policy") or setmetatable({}, { __index=function(_, key) return key end })

local Administration = {
    version=addonVersion,
    sections={}, categories={}, activeId=nil, initialized=false,
    host=nil, tree=nil, hostRegistered=false, navigationRegistered=false,
}

local DEFAULT_CATEGORIES = {
    general={ order=10, titleKey="ADMIN_CATEGORY_GENERAL" },
    permissions={ order=20, titleKey="ADMIN_CATEGORY_PERMISSIONS" },
    groups={ order=30, titleKey="ADMIN_CATEGORY_GROUPS" },
    rules={ order=40, titleKey="ADMIN_CATEGORY_RULES" },
    filters={ order=50, titleKey="ADMIN_CATEGORY_FILTERS" },
    modules={ order=60, titleKey="ADMIN_CATEGORY_MODULES" },
    system={ order=70, titleKey="ADMIN_CATEGORY_SYSTEM" },
}

local function validId(id)
    return type(id)=="string" and #id>0 and #id<=96 and id:match("^[%w_%.%-:]+$")~=nil
end

local function copyDefinition(source)
    local result={}
    for key,value in pairs(source or {}) do
        if (key=="permission" or key=="requiredPermission" or key=="events" or key=="availabilityEvents" or key=="requires") and type(value)=="table" then
            result[key]=HolyStorm.Utils.DeepCopy(value)
        elseif key:sub(1,1)~="_" then
            result[key]=value
        end
    end
    return result
end

local function resolveLocale(section, key, fallback)
    if not key then return fallback end
    if type(section.locale)=="table" and section.locale[key] then return section.locale[key] end
    if type(section.localize)=="function" then
        local ok,value=HolyStorm.Utils.SafeCall("administration.locale:"..section.id,section.localize,key)
        if ok and type(value)=="string" then return value end
    end
    if section.localeName and localeLibrary and localeLibrary.GetLocale then
        local locale=localeLibrary:GetLocale(section.localeName,true)
        if locale and locale[key] then return locale[key] end
    end
    return L[key] or fallback or key
end

function Administration:GetTitle(section)
    return section.title or section.displayName or resolveLocale(section,section.titleKey or section.displayNameKey,section.id)
end

function Administration:GetDescription(section)
    return section.description or resolveLocale(section,section.descriptionKey,self:GetTitle(section))
end

function Administration:RegisterCategory(id, definition)
    if not validId(id) or (definition~=nil and type(definition)~="table") then return false,"INVALID_ADMINISTRATION_CATEGORY" end
    local category=HolyStorm.Utils.DeepCopy(definition or {})
    category.id=id; category.order=tonumber(category.order) or 1000; category.titleKey=category.titleKey or "ADMIN_CATEGORY_"..id:upper()
    self.categories[id]=category
    if self.initialized and next(self.sections) then self:RefreshNavigation() end
    return true
end

function Administration:GetCategory(id)
    local category=self.categories[id]
    return category and HolyStorm.Utils.DeepCopy(category) or nil
end

function Administration:GetCategoryTitle(id)
    local category=self.categories[id] or {id=id,titleKey="ADMIN_CATEGORY_"..tostring(id):upper()}
    return category.title or resolveLocale(category,category.titleKey,id)
end

function Administration:IsModuleAvailable(moduleId)
    if not moduleId then return true end
    if HolyStorm.IsModuleAvailable then return HolyStorm:IsModuleAvailable(moduleId,true) end
    local module=HolyStorm.GetModule and HolyStorm:GetModule(moduleId,true)
    return module~=nil and (not module.IsEnabled or module:IsEnabled())
end

function Administration:IsCapabilityAvailable(capability, moduleId)
    if not capability then return true end
    if HolyStorm.IsCapabilityAvailable then return HolyStorm:IsCapabilityAvailable(capability,moduleId) end
    local handlers=HolyStorm.moduleCapabilities and HolyStorm.moduleCapabilities[capability]
    if type(handlers)~="table" then return false end
    if moduleId then return handlers[moduleId]~=nil end
    return next(handlers)~=nil
end

function Administration:IsGuildModuleEnabled(moduleId)
    if not HolyStorm.PolicyState then return true end
    local identifiers={[moduleId]=true}
    local module=HolyStorm.GetLoadedModuleById and HolyStorm:GetLoadedModuleById(moduleId)
    local metadata=module and module.metadata or nil
    if metadata then identifiers[metadata.id]=true; identifiers[metadata.internalName]=true end
    for id in pairs(identifiers) do if id and not HolyStorm.PolicyState:IsGuildModuleEnabled(id) then return false end end
    return true
end

local function checkRequirement(value, checker)
    if type(value)=="table" then
        for _,item in ipairs(value) do if not checker(item) then return false end end
        return true
    end
    return not value or checker(value)
end

function Administration:IsSectionAvailable(idOrSection)
    local section=type(idOrSection)=="table" and idOrSection or self.sections[idOrSection]
    if not section then return false,"NOT_FOUND" end
    local permission=section.permission or section.requiredPermission
    if permission then
        local allowed=section.permissionMode=="all"
        if type(permission)=="table" then
            if #permission==0 then allowed=true end
            for _,permissionId in ipairs(permission) do
                local granted=HolyStorm.PermissionEngine:HasPermission(nil,nil,permissionId)
                if section.permissionMode=="all" and not granted then allowed=false; break end
                if section.permissionMode~="all" and granted then allowed=true; break end
            end
        else
            allowed=HolyStorm.PermissionEngine:HasPermission(nil,nil,permission)
        end
        if not allowed then return false,"PERMISSION_DENIED" end
    end
    local requires=section.requires or {}
    local requiredModule=requires.module or section.moduleId
    if not checkRequirement(requiredModule,function(moduleId)return self:IsModuleAvailable(moduleId)end) then return false,"MODULE_UNAVAILABLE" end
    if requiredModule and HolyStorm.PolicyState then
        if not checkRequirement(requiredModule,function(moduleId)return self:IsGuildModuleEnabled(moduleId)end) then return false,"MODULE_DISABLED" end
    end
    if not checkRequirement(requires.capability,function(capability)return self:IsCapabilityAvailable(capability,type(requiredModule)=="string" and requiredModule or nil)end) then return false,"CAPABILITY_UNAVAILABLE" end
    if section.isAvailable then
        local ok,available,reason=HolyStorm.Utils.SafeCall("administration.available:"..section.id,section.isAvailable,section,self:GetContext(section))
        if not ok or available==false then return false,reason or "SECTION_UNAVAILABLE" end
    end
    return true
end
Administration.CanAccess = Administration.IsSectionAvailable

function Administration:GetContext(section, parent)
    return { administration=self, section=section, parent=parent, ui=HolyStorm.UI, addon=HolyStorm }
end

function Administration:GetSections(visibleOnly)
    local result={}
    for _,section in pairs(self.sections) do
        if not visibleOnly or self:IsSectionAvailable(section) then result[#result+1]=copyDefinition(section) end
    end
    table.sort(result,function(left,right)
        local leftCategory=self.categories[left.category] or {}; local rightCategory=self.categories[right.category] or {}
        local leftOrder,rightOrder=tonumber(leftCategory.order)or 1000,tonumber(rightCategory.order)or 1000
        if leftOrder~=rightOrder then return leftOrder<rightOrder end
        if left.category~=right.category then return self:GetCategoryTitle(left.category)<self:GetCategoryTitle(right.category) end
        if left.order~=right.order then return left.order<right.order end
        local leftTitle,rightTitle=self:GetTitle(left),self:GetTitle(right)
        if leftTitle~=rightTitle then return leftTitle<rightTitle end
        return left.id<right.id
    end)
    return result
end

function Administration:GetSection(id)
    local section=self.sections[id]
    return section and copyDefinition(section) or nil
end

function Administration:GetNavigationModel()
    local categories,byId={},{}
    for _,section in ipairs(self:GetSections(true)) do
        local category=byId[section.category]
        if not category then
            category={ id=section.category, value="category:"..section.category, text=self:GetCategoryTitle(section.category), children={} }
            categories[#categories+1]=category; byId[section.category]=category
        end
        category.children[#category.children+1]={ id=section.id, value="section:"..section.id, text=self:GetTitle(section), icon=section.icon }
    end
    return categories
end

function Administration:GetTreeValue(id)
    local section=self.sections[id]
    return section and ("category:"..section.category.."\001section:"..id) or nil
end

function Administration:SelectTreeSection(id)
    if not self.tree then return end
    local value=self:GetTreeValue(id); if not value then return end
    local status=self.tree.status or self.tree.localstatus
    status.groups["category:"..self.sections[id].category]=true
    status.selected=value
    self.tree:RefreshTree(true)
end

function Administration:EnsureSectionBuilt(section)
    if section._frame then return true end
    local parent=self.tree and self.tree.content or self.host
    local page=section.page
    if not page and section.build then
        local ok,result=HolyStorm.Utils.SafeCall("administration.build:"..section.id,section.build,parent,self:GetContext(section,parent))
        if not ok or not result then return false,"BUILD_FAILED" end
        page=result; section._builtByHost=true
    end
    if not page then return false,"MISSING_PAGE" end
    section._widget=type(page)=="table" and page.frame and page or nil
    section._frame=section._widget and section._widget.frame or page
    if section._frame.SetParent and parent then section._frame:SetParent(parent) end
    if section._frame.ClearAllPoints then section._frame:ClearAllPoints() end
    if section._frame.SetAllPoints and parent then section._frame:SetAllPoints(parent) end
    if section._frame.Hide then section._frame:Hide() end
    return true
end

function Administration:HideSection(id)
    local section=id and self.sections[id]
    if not section then return false end
    if section.hide then HolyStorm.Utils.SafeCall("administration.hide:"..id,section.hide,section,self:GetContext(section,section._frame)) end
    if section._frame and section._frame.Hide then section._frame:Hide() end
    return true
end

function Administration:ShowSection(id)
    local section=self.sections[id]
    if not section or not self:IsSectionAvailable(section) then return false end
    local built=self:EnsureSectionBuilt(section); if not built then return false end
    if self.activeId and self.activeId~=id then self:HideSection(self.activeId) end
    self.activeId=id
    if section._frame.Show then section._frame:Show() end
    if section.show then HolyStorm.Utils.SafeCall("administration.show:"..id,section.show,section,self:GetContext(section,section._frame)) end
    self:Refresh(id,true)
    self:SelectTreeSection(id)
    return true
end

function Administration:Refresh(id, force)
    if not id then
        self:RefreshNavigation()
        id=self.activeId
    end
    local section=id and self.sections[id]
    if not section or not self:IsSectionAvailable(section) then return false end
    if section._frame and (force or id==self.activeId) and section.refresh then
        local ok=HolyStorm.Utils.SafeCall("administration.refresh:"..id,section.refresh,section,self:GetContext(section,section._frame))
        return ok
    end
    return true
end

function Administration:OnTreeSelected(value)
    local id=type(value)=="string" and value:match("section:([^\001]+)$")
    if id then self:ShowSection(id); return end
    local categoryId=type(value)=="string" and value:match("^category:(.+)$")
    if categoryId then
        for _,section in ipairs(self:GetSections(true)) do if section.category==categoryId then self:ShowSection(section.id); return end end
    end
end

function Administration:EnsureHost()
    if self.host then return true end
    local driver=HolyStorm.UI and HolyStorm.UI.driver
    if not driver or not driver.content or not CreateFrame then return false end
    local host=CreateFrame("Frame",nil,driver.content); host:Hide()
    local tree=HolyStorm.UI.Components and HolyStorm.UI.Components:CreateTreeGroup(host)or nil
    if not tree then local aceGUI=LibStub("AceGUI-3.0",true);if not aceGUI then return false end;tree=aceGUI:Create("TreeGroup")end
    tree:SetLayout("Fill"); tree:SetTreeWidth(210); tree.frame:SetParent(host); tree.frame:SetAllPoints(host)
    tree:EnableButtonTooltips(false)
    tree:SetCallback("OnGroupSelected",function(_,_,value)Administration:OnTreeSelected(value)end)
    tree:SetCallback("OnButtonEnter",function(_,_,value,button)
        local id=type(value)=="string" and value:match("section:([^\001]+)$"); local section=id and Administration.sections[id]
        if section and GameTooltip then GameTooltip:SetOwner(button,"ANCHOR_RIGHT");GameTooltip:SetText(Administration:GetTitle(section));GameTooltip:AddLine(Administration:GetDescription(section),.9,.9,.9,true);GameTooltip:Show()end
    end)
    tree:SetCallback("OnButtonLeave",function()if GameTooltip then GameTooltip:Hide()end end)
    host:HookScript("OnShow",function()Administration:OnHostShown()end)
    host:HookScript("OnHide",function()Administration:HideSection(Administration.activeId)end)
    self.host,self.tree=host,tree
    if HolyStorm.UI.RegisterView then
        local ok=HolyStorm.UI:RegisterView({id="administration",owner="ui.administration",title=L["ADMINISTRATION_TITLE"],page=host,refresh=function()Administration:OnHostShown()end})
        if not ok then return false end
    else HolyStorm.UI:RegisterPage("administration",host,L["ADMINISTRATION_TITLE"],function()Administration:OnHostShown()end)end
    self.hostRegistered=true
    return true
end

function Administration:OnHostShown()
    self:RefreshNavigation()
    if self.activeId then self:ShowSection(self.activeId) end
end

function Administration:RefreshNavigation()
    local visible=self:GetSections(true)
    local first=visible[1] and visible[1].id
    local currentValid=self.activeId and self:IsSectionAvailable(self.activeId)
    local switched=not currentValid
    if not currentValid then
        if self.activeId then self:HideSection(self.activeId) end
        self.activeId=first
    end
    if self:EnsureHost() then
        self.tree:SetTree(self:GetNavigationModel())
        if self.activeId then self:SelectTreeSection(self.activeId) end
        if #visible>0 and not self.navigationRegistered then
            HolyStorm.UI:AddNavigation("administration",90,"Interface\\Icons\\INV_Misc_Gear_01",L["ADMINISTRATION_TITLE"],L["ADMINISTRATION_DESCRIPTION"],function()Administration:Open()end)
            self.navigationRegistered=true
        elseif #visible==0 and self.navigationRegistered then
            HolyStorm.UI:RemoveNavigation("administration"); self.navigationRegistered=false
        end
        if #visible==0 and self.host.IsShown and self.host:IsShown() and HolyStorm.UI.ShowHome then HolyStorm.UI:ShowHome() end
        if #visible>0 and switched and self.host.IsShown and self.host:IsShown() then self:ShowSection(self.activeId) end
    end
    HolyStorm.Events:Emit("HS_ADMINISTRATION_NAVIGATION_UPDATED",#visible,self.activeId)
    return visible
end
Administration.RefreshSections = Administration.RefreshNavigation

function Administration:Open(sectionId)
    self:RefreshNavigation()
    if sectionId and self:IsSectionAvailable(sectionId) then self.activeId=sectionId end
    if not self.activeId then return false,"NO_AVAILABLE_SECTION" end
    if self:EnsureHost() then HolyStorm.UI:ShowPage("administration") end
    return self:ShowSection(self.activeId)
end

function Administration:DestroySection(section)
    if not section then return end
    self:HideSection(section.id)
    if section.destroy then HolyStorm.Utils.SafeCall("administration.destroy:"..section.id,section.destroy,section,self:GetContext(section,section._frame))
    elseif section._builtByHost and section._widget then
        local aceGUI=LibStub("AceGUI-3.0",true); if aceGUI then aceGUI:Release(section._widget) end
    end
    section._frame,section._widget,section._builtByHost=nil,nil,nil
end

function Administration:RegisterSection(definition)
    if type(definition)~="table" or not validId(definition.id) or (not definition.page and type(definition.build)~="function") then return false,"INVALID_ADMINISTRATION_SECTION" end
    for _,callback in ipairs({"build","show","hide","refresh","render","destroy","isAvailable"}) do if definition[callback]~=nil and type(definition[callback])~="function" then return false,"INVALID_ADMINISTRATION_SECTION" end end
    if self.sections[definition.id] then return false,"ADMINISTRATION_SECTION_EXISTS" end
    local section=copyDefinition(definition)
    section.order=tonumber(section.order) or 100
    section.category=section.category or "general"
    section.owner=section.owner or section.moduleId or "Core"
    section.permission=section.permission or section.requiredPermission
    section.refresh=section.refresh or section.render
    section.requires=type(section.requires)=="table" and section.requires or {}
    if section.moduleId and not section.requires.module then section.requires.module=section.moduleId end
    local initialFrame=type(section.page)=="table" and section.page.frame or section.page
    if initialFrame and initialFrame.Hide then initialFrame:Hide() end
    self.sections[section.id]=section
    self:Initialize()
    if type(section.events)=="table" then
        for _,event in ipairs(section.events) do
            HolyStorm.Events:Register(event,"administration:section:"..section.id,function()Administration:Refresh(section.id)end)
        end
    end
    if type(section.availabilityEvents)=="table" then
        for _,event in ipairs(section.availabilityEvents) do HolyStorm.Events:Register(event,"administration:availability:"..section.id,function()Administration:RefreshNavigation()end) end
    end
    self:RefreshNavigation()
    HolyStorm.Events:Emit("HS_ADMINISTRATION_SECTION_REGISTERED",section.id)
    return true
end

function Administration:UnregisterSection(id)
    local section=self.sections[id]
    if not section then return false,"NOT_FOUND" end
    HolyStorm.Events:UnregisterOwner("administration:section:"..id)
    HolyStorm.Events:UnregisterOwner("administration:availability:"..id)
    local wasActive=self.activeId==id
    self:DestroySection(section); self.sections[id]=nil
    if wasActive then self.activeId=nil end
    self:RefreshNavigation()
    HolyStorm.Events:Emit("HS_ADMINISTRATION_SECTION_UNREGISTERED",id)
    return true
end

function Administration:UnregisterOwner(owner)
    local ids={}
    for id,section in pairs(self.sections) do if section.owner==owner then ids[#ids+1]=id end end
    table.sort(ids); for _,id in ipairs(ids) do self:UnregisterSection(id) end
    return #ids
end

function Administration:Initialize()
    if self.initialized then return end
    self.initialized=true
    for id,definition in pairs(DEFAULT_CATEGORIES) do self:RegisterCategory(id,definition) end
    for _,event in ipairs({"HS_EFFECTIVE_PERMISSIONS_CHANGED","HS_PERMISSIONS_STATE_UPDATED","HS_GROUP_UPDATED","HS_MODULE_AVAILABILITY_CHANGED","HS_CAPABILITY_REGISTERED","HS_CAPABILITY_UNREGISTERED","HS_ROSTER_UPDATED","PLAYER_GUILD_UPDATE"}) do
        HolyStorm.Events:Register(event,"administration-host",function()Administration:RefreshNavigation()end)
    end
    if HolyStorm.FlushAdministrationSections then HolyStorm:FlushAdministrationSections() end
end

HolyStorm.Administration = Administration
Administration:Initialize()
function HolyStorm:RegisterAdministrationSection(definition) return Administration:RegisterSection(definition) end
function HolyStorm:UnregisterAdministrationSection(id) return Administration:UnregisterSection(id) end
function HolyStorm:GetAdministrationSections(visibleOnly) return Administration:GetSections(visibleOnly) end
