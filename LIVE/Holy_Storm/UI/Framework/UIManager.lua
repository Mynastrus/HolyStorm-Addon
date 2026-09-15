local addonVersion = "1.2.0"
local HolyStorm = LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local UIManager = { version=addonVersion, driver=nil, pages={}, dirty={}, scheduled={} }
function UIManager:SetDriver(driver)
    self.driver=driver; HolyStorm.State:Set("uiReady",driver~=nil)
    HolyStorm.Events:Register("HS_UI_STATUS_REQUESTED","ui-manager-status",function(_,text) if UIManager.driver then UIManager.driver:SetStatusText(text) end end)
    return true
end
function UIManager:RegisterPage(id,frame,title,refresh,events)
    if type(id)~="string" or not frame then return false end
    self.pages[id]={id=id,frame=frame,title=title,refresh=refresh}; self.dirty[id]=true
    if type(events)=="table" then for _,event in ipairs(events) do HolyStorm.Events:Register(event,"ui:"..id,function() UIManager:MarkDirty(id) end) end end
    if self.driver then self.driver:RegisterPage(id,frame,title,function() UIManager:RefreshPage(id) end) end; return true
end
function UIManager:UnregisterPage(id) HolyStorm.Events:UnregisterOwner("ui:"..tostring(id)); if self.driver and self.driver.UnregisterPage then self.driver:UnregisterPage(id) end; self.pages[id],self.dirty[id],self.scheduled[id]=nil,nil,nil end
function UIManager:MarkDirty(id, deferVisible)
    if not self.pages[id] then return false end; self.dirty[id]=true
    if not deferVisible and self.driver and self.driver.pages and self.driver.pages[id] and self.driver.pages[id].frame:IsShown() and not self.scheduled[id] then self.scheduled[id]=true;local function refresh()UIManager.scheduled[id]=nil;UIManager:RefreshPage(id)end;if C_Timer and C_Timer.After then C_Timer.After(.05,refresh)else refresh()end end;return true
end
function UIManager:RefreshPage(id,force)
    local page=self.pages[id]; if not page or (not force and not self.dirty[id]) then return false end
    self.dirty[id]=nil; if page.refresh then local ok=HolyStorm.Utils.SafeCall("ui:"..id,page.refresh); return ok end; return true
end
function UIManager:ShowPage(id)
    if not self.driver or not self.pages[id] then return false end; self.driver:ShowPage(id); self:RefreshPage(id); return true
end
function UIManager:Open() if self.driver then self.driver:Open(); return true end; return false end
function UIManager:AddNavigation(...) return self.driver and self.driver:AddRightDockIcon(...) or false end
function UIManager:RemoveNavigation(id) return self.driver and self.driver.RemoveRightDockIcon and self.driver:RemoveRightDockIcon(id) or false end
function UIManager:RegisterDashboardProvider(...) return self.driver and self.driver:RegisterDashboardProvider(...) or false end
function UIManager:SetStatusText(text) if self.driver then self.driver:SetStatusText(text) end end
function UIManager:ShowOptions(name) if self.driver then self.driver:ShowOptions(name); return true end; return false end
function UIManager:GetVisiblePage()
    if not self.driver or not self.driver.pages then return nil end; for id,page in pairs(self.driver.pages) do if page.frame:IsShown() then return id end end
end
HolyStorm.UI = UIManager
