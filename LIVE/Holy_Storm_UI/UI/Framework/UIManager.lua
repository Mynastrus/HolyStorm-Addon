local addonVersion="2.0.0"
local HolyStorm=LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local localeLibrary=LibStub("AceLocale-3.0",true)

local UIManager={
    version=addonVersion,driver=nil,pages={},views={},viewOrder={},dirty={},scheduled={},initializedExtensions={},
    Layout=HolyStorm.UILayout,Components=HolyStorm.UIComponents,
}

local function validId(id)return type(id)=="string"and#id>0 and#id<=128 and id:match("^[%w_%.%-:]+$")~=nil end
local function copyDefinition(source)local result={};for key,value in pairs(source or{})do if type(key)~="string"or key:sub(1,1)~="_"then result[key]=value end end;return result end
local function requirement(value,checker)
    if type(value)=="table"then for _,item in ipairs(value)do if not checker(item)then return false end end;return true end
    return value==nil or checker(value)
end

function UIManager:InitializeExtension(definition)
    if not self.driver or type(definition)~="table"or self.initializedExtensions[definition.id]then return false end
    local ok=HolyStorm.Utils.SafeCall("ui-extension:"..definition.id,definition.initialize,definition)
    if ok then self.initializedExtensions[definition.id]=true end
    return ok
end
function UIManager:FlushExtensions()
    if not self.driver then return 0 end
    local count=0;for _,definition in ipairs(HolyStorm:GetUIExtensions())do if self:InitializeExtension(definition)then count=count+1 end end;return count
end
function UIManager:SetDriver(driver)
    self.driver=driver;HolyStorm.State:Set("uiReady",driver~=nil)
    HolyStorm.Events:Register("HS_UI_STATUS_REQUESTED","ui-manager-status",function(_,text)if UIManager.driver then UIManager.driver:SetStatusText(text)end end)
    if HolyStorm.Administration and HolyStorm.Administration.RefreshNavigation then HolyStorm.Administration:RefreshNavigation()end
    self:RefreshViewAvailability();self:FlushExtensions();return true
end

-- Low-level compatibility contract. Feature UI should normally use RegisterView.
function UIManager:RegisterPage(id,frame,title,refresh,events)
    if not validId(id)or not frame then return false,"INVALID_PAGE"end
    if self.pages[id]then self:UnregisterPage(id)end
    self.pages[id]={id=id,frame=frame,title=title,refresh=refresh};self.dirty[id]=true
    if type(events)=="table"then for _,event in ipairs(events)do HolyStorm.Events:Register(event,"ui:"..id,function()UIManager:MarkDirty(id)end)end end
    if self.driver then self.driver:RegisterPage(id,frame,title,function()UIManager:RefreshPage(id)end)end
    return true
end
function UIManager:UnregisterPage(id)
    HolyStorm.Events:UnregisterOwner("ui:"..tostring(id));if self.driver and self.driver.UnregisterPage then self.driver:UnregisterPage(id)end
    self.pages[id],self.dirty[id],self.scheduled[id]=nil,nil,nil
end
function UIManager:MarkDirty(id,deferVisible)
    if not self.pages[id]then return false end;self.dirty[id]=true
    if not deferVisible and self.driver and self.driver.pages and self.driver.pages[id]and self.driver.pages[id].frame:IsShown()and not self.scheduled[id]then
        self.scheduled[id]=true;local function refresh()UIManager.scheduled[id]=nil;UIManager:RefreshPage(id)end
        if C_Timer and C_Timer.After then C_Timer.After(.05,refresh)else refresh()end
    end
    return true
end
function UIManager:RefreshPage(id,force)
    local page=self.pages[id];if not page or(not force and not self.dirty[id])then return false end
    self.dirty[id]=nil;if page.refresh then local ok=HolyStorm.Utils.SafeCall("ui:"..id,page.refresh);return ok end;return true
end
function UIManager:ShowPage(id)
    if not self.driver or not self.pages[id]then return false end;self.driver:ShowPage(id);self:RefreshPage(id);return true
end

function UIManager:LocalizeView(view,key,fallback)
    if not key then return fallback end
    if type(view.locale)=="table"and view.locale[key]~=nil then return view.locale[key]end
    if type(view.localize)=="function"then local ok,value=HolyStorm.Utils.SafeCall("ui-view.locale:"..view.id,view.localize,key);if ok and value~=nil then return value end end
    if view.localeName and localeLibrary and localeLibrary.GetLocale then local locale=localeLibrary:GetLocale(view.localeName,true);if locale and locale[key]~=nil then return locale[key]end end
    return fallback or key
end
function UIManager:GetViewTitle(view)return view.title or self:LocalizeView(view,view.titleKey,view.id)end
function UIManager:GetViewContext(view,parent)return{ui=self,view=view,parent=parent,addon=HolyStorm,layout=self.Layout,components=self.Components}end
function UIManager:IsViewAvailable(idOrView)
    local view=type(idOrView)=="table"and idOrView or self.views[idOrView];if not view then return false,"NOT_FOUND"end
    local requires=type(view.requires)=="table"and view.requires or{}
    local moduleRequirement=requires.module or view.moduleId
    if not requirement(moduleRequirement,function(moduleId)return not HolyStorm.IsModuleAvailable or HolyStorm:IsModuleAvailable(moduleId,true)end)then return false,"MODULE_UNAVAILABLE"end
    if not requirement(requires.capability,function(capability)return not HolyStorm.IsCapabilityAvailable or HolyStorm:IsCapabilityAvailable(capability,type(moduleRequirement)=="string"and moduleRequirement or nil)end)then return false,"CAPABILITY_UNAVAILABLE"end
    if view.isAvailable then local ok,available,reason=HolyStorm.Utils.SafeCall("ui-view.available:"..view.id,view.isAvailable,view,self:GetViewContext(view));if not ok or available==false then return false,reason or"VIEW_UNAVAILABLE"end end
    return true
end
function UIManager:AttachView(view)
    if not view._frame then return false,"MISSING_VIEW_FRAME"end
    if not self.pages[view.id]then
        local refresh=function()if view.refresh then return view.refresh(view,self:GetViewContext(view,view._frame))end;return true end
        self:RegisterPage(view.id,view._frame,self:GetViewTitle(view),refresh,view.events)
    end
    local navigation=view.navigation
    if navigation and not view._navigation then
        self:AddNavigation(view.id,navigation.order or view.order or 100,navigation.icon or view.icon,navigation.title or self:GetViewTitle(view),navigation.description or self:LocalizeView(view,view.descriptionKey,view.description or self:GetViewTitle(view)),function()UIManager:ShowView(view.id)end)
        view._navigation=true
    end
    return true
end
function UIManager:MaterializeView(view)
    if view._frame then return self:AttachView(view)end;if not self.driver then return false,"UI_NOT_READY"end
    local available,reason=self:IsViewAvailable(view);if not available then return false,reason end
    local parent=self.driver.content;local result=view.page or view.frame
    if not result and view.build then local ok,built=HolyStorm.Utils.SafeCall("ui-view.build:"..view.id,view.build,parent,self:GetViewContext(view,parent));if not ok then return false,"BUILD_FAILED"end;result=built end
    if not result and view.layout then result=self.Components:Build(parent,view.layout,self:GetViewContext(view,parent))end
    local frame=type(result)=="table"and result.frame or result;if not frame then return false,"MISSING_VIEW_FRAME"end
    view._object=type(result)=="table"and result.frame and result or nil;view._frame=frame
    if frame.SetParent then frame:SetParent(parent)end;if frame.Hide then frame:Hide()end
    self:AttachView(view)
    if view.onCreate then HolyStorm.Utils.SafeCall("ui-view.create:"..view.id,view.onCreate,view,self:GetViewContext(view,frame))end
    return true
end
function UIManager:RegisterView(definition)
    if type(definition)~="table"or not validId(definition.id)or type(definition.owner)~="string"or definition.owner==""then return false,"INVALID_VIEW"end
    if self.views[definition.id]or self.pages[definition.id]then return false,"VIEW_ID_EXISTS"end
    if not definition.page and not definition.frame and type(definition.build)~="function"and type(definition.layout)~="table"then return false,"INVALID_VIEW"end
    for _,callback in ipairs({"build","refresh","destroy","isAvailable","localize","onCreate","onShow","onHide"})do if definition[callback]~=nil and type(definition[callback])~="function"then return false,"INVALID_VIEW"end end
    local view=copyDefinition(definition);view.order=tonumber(view.order)or 100;self.views[view.id]=view;self.viewOrder[#self.viewOrder+1]=view.id
    table.sort(self.viewOrder,function(left,right)local a,b=self.views[left],self.views[right];return a.order<b.order or a.order==b.order and left<right end)
    if type(view.availabilityEvents)=="table"then for _,event in ipairs(view.availabilityEvents)do HolyStorm.Events:Register(event,"ui-view-availability:"..view.id,function()UIManager:RefreshViewAvailability(view.id)end)end end
    self:MaterializeView(view);if HolyStorm.Events then HolyStorm.Events:Emit("HS_UI_VIEW_REGISTERED",view.id,view.owner)end;return true
end
function UIManager:GetView(id)local view=self.views[id];return view and copyDefinition(view)or nil end
function UIManager:GetViews(availableOnly)
    local result={};for _,id in ipairs(self.viewOrder)do local view=self.views[id];if not availableOnly or self:IsViewAvailable(view)then result[#result+1]=copyDefinition(view)end end;return result
end
function UIManager:ShowView(id)
    local view=self.views[id];if not view then return false,"NOT_FOUND"end
    if not view._frame then local ok,reason=self:MaterializeView(view);if not ok then return false,reason end end
    local ok=self:ShowPage(id);if ok and view.onShow then HolyStorm.Utils.SafeCall("ui-view.show:"..id,view.onShow,view,self:GetViewContext(view,view._frame))end;return ok
end
function UIManager:UnregisterView(id)
    local view=self.views[id];if not view then return false,"NOT_FOUND"end
    if view.onHide then HolyStorm.Utils.SafeCall("ui-view.hide:"..id,view.onHide,view,self:GetViewContext(view,view._frame))end
    if view.destroy then HolyStorm.Utils.SafeCall("ui-view.destroy:"..id,view.destroy,view,self:GetViewContext(view,view._frame))elseif view._object and view._object.Destroy then view._object:Destroy()elseif view._frame and view._frame.Hide then view._frame:Hide()end
    if view._navigation then self:RemoveNavigation(id)end;self:UnregisterPage(id);HolyStorm.Events:UnregisterOwner("ui-view-availability:"..id);self.views[id]=nil
    for index,value in ipairs(self.viewOrder)do if value==id then table.remove(self.viewOrder,index);break end end
    if HolyStorm.Events then HolyStorm.Events:Emit("HS_UI_VIEW_UNREGISTERED",id,view.owner)end;return true
end
function UIManager:UnregisterViewOwner(owner)
    local ids={};for id,view in pairs(self.views)do if view.owner==owner then ids[#ids+1]=id end end;table.sort(ids);for _,id in ipairs(ids)do self:UnregisterView(id)end;return#ids
end
function UIManager:RefreshViewAvailability(id)
    local ids=id and{id}or self.viewOrder
    for _,viewId in ipairs(ids)do local view=self.views[viewId];if view then local available=self:IsViewAvailable(view);if available and not self.pages[view.id]then self:MaterializeView(view)elseif not available and self.pages[view.id]then if view.onHide then HolyStorm.Utils.SafeCall("ui-view.hide:"..view.id,view.onHide,view,self:GetViewContext(view,view._frame))end;if view._navigation then self:RemoveNavigation(view.id);view._navigation=nil end;if self:GetVisiblePage()==view.id then self:ShowHome()end;self:UnregisterPage(view.id);if view._frame.Hide then view._frame:Hide()end end end end
end

function UIManager:Open()if self.driver then self.driver:Open();return true end;return false end
function UIManager:ShowHome()if self.driver and self.driver.ShowModules then self.driver:ShowModules();return true end;return false end
function UIManager:AddNavigation(...)return self.driver and self.driver:AddRightDockIcon(...)or false end
function UIManager:RemoveNavigation(id)return self.driver and self.driver.RemoveRightDockIcon and self.driver:RemoveRightDockIcon(id)or false end
function UIManager:RegisterDashboardProvider(...)return self.driver and self.driver:RegisterDashboardProvider(...)or false end
function UIManager:SetStatusText(text)if self.driver then self.driver:SetStatusText(text)end end
function UIManager:ShowOptions(name)if self.driver then self.driver:ShowOptions(name);return true end;return false end
function UIManager:GetVisiblePage()if not self.driver or not self.driver.pages then return nil end;for id,page in pairs(self.driver.pages)do if page.frame:IsShown()then return id end end end

HolyStorm.UI=UIManager
HolyStorm.Events:Register("HS_UI_EXTENSION_REGISTERED","ui-extensions",function(_,_,definition)UIManager:InitializeExtension(definition)end)
