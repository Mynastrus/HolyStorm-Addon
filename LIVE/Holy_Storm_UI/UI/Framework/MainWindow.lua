local addonVersion = "2.6.0"
local HolyStorm = LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local L = LibStub("AceLocale-3.0"):GetLocale("Holy_Storm_UI")

local UI = HolyStorm:RegisterRequiredModule("UI")
UI.dashboardProviders = {}
UI.pageContextHeaders = UI.pageContextHeaders or {}
HolyStorm:ApplyModuleMetadata(UI, {
    displayName = L["DISPLAY_NAME"], internalName = "ui", version = addonVersion,
    category = "required", description = L["DESCRIPTION"], permissions = { { id = "ui-render", category = "Core" } },
    dependencies = { "core" }, enabledByDefault = true,
})

local UNKNOWN = "|cff888888\226\128\147|r"
local CLASS_FALLBACK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local SPEC_FALLBACK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

function UI:OnInitialize()
    local frame = CreateFrame("Frame", "HolyStormMainFrame", UIParent, "ButtonFrameTemplate")
    frame:SetSize(900, 560)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetFrameLevel(200)
    frame:SetClampedToScreen(true)
    frame:SetClampRectInsets(-62, 58, 18, -15)
    frame:SetMovable(true)
    frame:SetResizable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        UI:SaveWindowPosition()
    end)
    frame:HookScript("OnSizeChanged", function() UI:SaveWindowSize() end)
    if frame.SetResizeBounds then frame:SetResizeBounds(650, 420) else frame:SetMinResize(650, 420) end
    frame:Hide()

    local titleParent = frame.TitleContainer or frame.Header or frame.TopTileStreaks or frame
    local title = titleParent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmallOutline")
    title:SetPoint("LEFT", titleParent, "LEFT", 6, -2)
    title:SetPoint("RIGHT", titleParent, "RIGHT", -40, 2)
    title:SetJustifyH("LEFT")
    title:SetText(L["WINDOW_TITLE"])
    if frame.TitleText then frame.TitleText:Hide() end
    local portrait = frame.portrait or frame.Portrait or (frame.PortraitContainer and frame.PortraitContainer.portrait)
    if portrait then
        local iconPath = HolyStorm.Libraries and HolyStorm.Libraries.ADDON_ICON
        local iconSet = iconPath and pcall(portrait.SetTexture, portrait, iconPath)
        if not iconSet then pcall(portrait.SetTexture, portrait, HolyStorm.Libraries and HolyStorm.Libraries.ADDON_ICON_FALLBACK or "Interface\\Icons\\INV_Misc_QuestionMark") end
        if portrait.SetTexCoord then portrait:SetTexCoord(0, 1, 0, 1) end
    end

    if not tContains(UISpecialFrames, "HolyStormMainFrame") then table.insert(UISpecialFrames, "HolyStormMainFrame") end
    local aceGUI = LibStub("AceGUI-3.0")
    local inset = frame.Inset or frame
    local content = CreateFrame("Frame", nil, frame)
    content:SetPoint("TOPLEFT", inset, "TOPLEFT", 5, -5)
    content:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -5, 30)
    local contextHeaderSlot=CreateFrame("Frame",nil,inset)
    contextHeaderSlot:SetPoint("TOPLEFT",inset,"TOPLEFT",5,-5);contextHeaderSlot:SetPoint("TOPRIGHT",inset,"TOPRIGHT",-5,-5);contextHeaderSlot:SetHeight(1);contextHeaderSlot:Hide()

    local scroll = aceGUI:Create("ScrollFrame")
    scroll:SetLayout("List")
    scroll.frame:SetParent(content)
    scroll.frame:SetAllPoints(content)
    local dashboardGroup
    local function updateScrollLayout(_, width, height)
        scroll:SetWidth(width)
        scroll:SetHeight(height)
        if dashboardGroup then dashboardGroup:SetHeight(math.max(380, height - 8)) end
        scroll:DoLayout()
        if UI.LayoutDashboard then UI:LayoutDashboard() end
    end
    content:HookScript("OnSizeChanged", updateScrollLayout)
    updateScrollLayout(nil, content:GetWidth(), content:GetHeight())
    local page = aceGUI:Create("SimpleGroup")
    page:SetFullWidth(true)
    page:SetLayout("List")
    scroll:AddChild(page)
    local dashboard = {}
    dashboardGroup = aceGUI:Create("SimpleGroup")
    dashboardGroup:SetFullWidth(true)
    dashboardGroup:SetHeight(math.max(380, content:GetHeight() - 8)); dashboardGroup.noAutoHeight = true
    dashboardGroup:SetLayout("Fill")
    page:AddChild(dashboardGroup)
    table.insert(dashboard, dashboardGroup.frame)

    local identity = aceGUI:Create("SimpleGroup")
    identity:SetFullWidth(true); identity:SetLayout("Flow"); identity:SetHeight(84); identity.noAutoHeight = true
    local classIcon = aceGUI:Create("Icon")
    classIcon:SetImage(CLASS_FALLBACK_ICON); classIcon:SetImageSize(64, 64); classIcon:SetWidth(78); classIcon:SetHeight(74)
    classIcon.frame:EnableMouse(false)
    local specIcon = aceGUI:Create("Icon")
    specIcon:SetImage(SPEC_FALLBACK_ICON); specIcon:SetImageSize(64, 64); specIcon:SetWidth(78); specIcon:SetHeight(74)
    specIcon.frame:EnableMouse(false)
    local identityText = aceGUI:Create("SimpleGroup")
    identityText:SetLayout("List"); identityText:SetRelativeWidth(0.70); identityText:SetHeight(70); identityText.noAutoHeight = true
    local characterName = aceGUI:Create("Label")
    characterName:SetText(UNKNOWN); characterName:SetFontObject(GameFontHighlightLarge); characterName:SetFullWidth(true); characterName:SetHeight(30)
    identityText:AddChild(characterName)
    local specialization = aceGUI:Create("Label")
    specialization:SetText(UNKNOWN); specialization:SetFontObject(GameFontHighlight); specialization:SetFullWidth(true); specialization:SetHeight(24)
    identityText:AddChild(specialization)
    local characterDetails = aceGUI:Create("Label")
    characterDetails:SetText(""); characterDetails:SetFontObject(GameFontHighlightSmall); characterDetails:SetFullWidth(true); characterDetails:SetHeight(18)
    identityText:AddChild(characterDetails)

    local dashboardWidgets = {identity=identity,identityText=identityText,classIcon=classIcon,specIcon=specIcon,name=characterName,specialization=specialization,details=characterDetails}
    self:BuildHomeDashboard(dashboardGroup.frame, dashboardWidgets)

    local status = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    status:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 10); status:SetText(string.format(L["STATUS_BAR_READY"], HolyStorm.version))
    local syncActivity = CreateFrame("Button", nil, frame)
    syncActivity:SetSize(170, 24); syncActivity:SetPoint("BOTTOM", frame, "BOTTOM", 0, 7); syncActivity:Hide()
    local syncSpinner = syncActivity:CreateTexture(nil, "ARTWORK")
    syncSpinner:SetSize(13, 13); syncSpinner:SetPoint("LEFT", syncActivity, "LEFT", 4, 0); if syncSpinner.SetTexture then syncSpinner:SetTexture("Interface\\Buttons\\UI-RefreshButton") end
    local syncLabel = syncActivity:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    syncLabel:SetPoint("LEFT", syncSpinner, "RIGHT", 5, 0); syncLabel:SetText(L["SYNC_RUNNING"])
    local syncRotation = 0
    -- WoW Texture:SetRotation uses negative angles for clockwise motion.
    syncActivity:SetScript("OnUpdate", function(_, elapsed) syncRotation = (syncRotation - elapsed * 5) % (math.pi * 2); syncSpinner:SetRotation(syncRotation) end)
    local syncTooltip = GameTooltip
    syncActivity:SetScript("OnEnter", function(button)
        local activity = HolyStorm.Sync and HolyStorm.Sync:GetActivity()
        local operation = activity and activity.activeOperations and activity.activeOperations[1]
        local descriptionKey = "SYNC_ACTIVITY_TRANSFER"
        if operation then
            local domain = operation.domain
            local entity = type(operation.entity) == "string" and operation.entity or ""
            if operation.characterUUID then
                descriptionKey = "SYNC_ACTIVITY_CHARACTER"
            elseif domain == "poi" or entity:match("^[Pp][Oo][Ii]@") then
                descriptionKey = "SYNC_ACTIVITY_POI"
            elseif domain == "guild-position" or domain == "positions" then
                descriptionKey = "SYNC_ACTIVITY_POSITIONS"
            end
        end
        syncTooltip:SetOwner(button, "ANCHOR_TOP")
        syncTooltip:ClearLines()
        syncTooltip:SetText(L["SYNC_TOOLTIP_TITLE"])
        syncTooltip:AddLine(L[descriptionKey], .8, .8, .8, true)
        syncTooltip:Show()
    end)
    syncActivity:SetScript("OnLeave", function() GameTooltip:Hide() end)
    local updated = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    updated:SetPoint("RIGHT", frame, "BOTTOMRIGHT", -190, 10); updated:SetJustifyH("RIGHT"); updated:SetText(L["DASHBOARD_UPDATE_UNKNOWN"])
    local refresh = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    refresh:SetSize(158, 26); refresh:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -24, 4); refresh:SetText(L["DASHBOARD_REFRESH"])
    refresh:SetScript("OnClick", function() UI:RefreshCharacterData() end)
    refresh:SetScript("OnEnter", function(button) GameTooltip:SetOwner(button, "ANCHOR_TOP"); GameTooltip:SetText(L["DASHBOARD_REFRESH_TOOLTIP"]); GameTooltip:Show() end)
    refresh:SetScript("OnLeave", function() GameTooltip:Hide() end)
    local resize = CreateFrame("Button", nil, frame)
    resize:SetSize(16, 16); resize:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -4, 4); resize:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resize:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" then return end
        local left, top = frame:GetLeft(), frame:GetTop()
        if left and top then
            frame:ClearAllPoints()
            frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
        end
        frame:StartSizing("BOTTOMRIGHT")
    end)
    resize:SetScript("OnMouseUp", function() frame:StopMovingOrSizing(); UI:SaveWindowSize() end)

    self.frame, self.content, self.scroll, self.page, self.pages = frame, content, scroll, page, {}
    self.contentInset,self.contextHeaderSlot,self.activeContextHeaderPage=inset,contextHeaderSlot,nil
    self.dashboardElements, self.dashboardWidgets, self.windowTitle, self.status = dashboard, dashboardWidgets, title, status
    self.syncActivityButton, self.syncActivityLabel, self.syncSpinner = syncActivity, syncLabel, syncSpinner
    self.syncActivityTooltip = syncTooltip
    self.updatedStatus, self.refreshButton = updated, refresh
    self:LoadWindowState()
    self:CreateRightDock()
    self:RegisterDashboardEvents()
    if HolyStorm.Events and type(HolyStorm.Events.Register) == "function" then HolyStorm.Events:Register("HS_SYNC_ACTIVITY_UPDATED", "ui-sync-activity", function() UI:RefreshSyncActivity() end) end
    frame:HookScript("OnShow", function() UI:SetRightDockVisible(true) end)
    frame:HookScript("OnHide", function() UI:SetRightDockVisible(false) end)
    self:SetRightDockVisible(false)
    frame:HookScript("OnSizeChanged",function()UI:LayoutPageContextHeader()end)
    contextHeaderSlot:HookScript("OnSizeChanged",function(_,width)
        if width~=UI.contextHeaderWidth then UI.contextHeaderWidth=width;UI:LayoutPageContextHeader()end
    end)
    HolyStorm.UI:SetDriver(self)
    self:RefreshSyncActivity()
    self:RefreshDashboard()
end

function UI:RefreshSyncActivity()
    local activity = HolyStorm.Sync and HolyStorm.Sync:GetActivity()
    local active = activity and activity.active == true
    if self.syncActivityButton then self.syncActivityButton:SetShown(active) end
    return active == true
end

function UI:SetRightDockVisible(visible)
    if self.rightDock then self.rightDock:SetShown(visible) end
end

function UI:SetRightDockSelected(id)
    for entryId, entry in pairs(self.rightDockEntries) do entry.glow:SetShown(entryId == id) end
end

function UI:SetStatusText(text)
    self.status:SetText(text)
end

function UI:SetReadyStatus()
    self:SetStatusText(string.format(L["STATUS_BAR_READY"], HolyStorm.version))
end

function UI:AddRightDockIcon(id, order, iconPath, tooltipTitle, tooltipDescription, onClick)
    if self.rightDockEntries and self.rightDockEntries[id] then self:RemoveRightDockIcon(id) end
    local slot = CreateFrame("Frame", nil, self.rightDockContent, "BackdropTemplate")
    slot:SetSize(42, 38)
    slot:SetFrameLevel(self.rightDockContent:GetFrameLevel() + 2)
    slot:SetBackdrop({ bgFile = "Interface\\FrameGeneral\\UI-Background-Rock", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 12, insets = { left = 2, right = 2, top = 2, bottom = 2 } })
    local button = CreateFrame("Button", nil, slot)
    button:SetSize(32, 32); button:SetPoint("CENTER", slot, "CENTER", 3, 0); button:SetNormalTexture("Interface\\Buttons\\UI-Quickslot2")
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", button, "TOPLEFT", 4, -4); icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -4, 4); icon:SetTexture(iconPath); icon:SetTexCoord(0.07, 0.93, 0.07, 0.93); icon:SetBlendMode("ADD")
    local glow = button:CreateTexture(nil, "OVERLAY")
    glow:SetPoint("CENTER", button); glow:SetSize(56, 56); glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border"); glow:SetBlendMode("ADD"); glow:SetVertexColor(1, 0.82, 0.2); glow:Hide()
    button:SetScript("OnClick", function() self:SetRightDockSelected(id); onClick() end)
    button:SetScript("OnEnter", function() GameTooltip:SetOwner(slot, "ANCHOR_LEFT"); GameTooltip:AddLine(tooltipTitle); GameTooltip:AddLine(tooltipDescription, 0.9, 0.9, 0.9, true); GameTooltip:Show() end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    self.rightDockEntries[id] = { id=id, order=tonumber(order)or 100, slot=slot, glow=glow }
    self:LayoutRightDock()
    return true
end

function UI:RemoveRightDockIcon(id)
    local entry=self.rightDockEntries and self.rightDockEntries[id]
    if not entry then return false end
    entry.slot:Hide(); entry.slot:SetParent(nil); self.rightDockEntries[id]=nil; self:LayoutRightDock(); return true
end

function UI:ScrollRightDock(delta)
    if not self.rightDockScroll then return end
    local maximum=self.rightDockScroll:GetVerticalScrollRange()or 0
    self.rightDockScroll:SetVerticalScroll(math.max(0,math.min(maximum,(self.rightDockScroll:GetVerticalScroll()or 0)+delta)))
    self:UpdateRightDockArrows()
end

function UI:UpdateRightDockArrows()
    if not self.rightDockScroll then return end
    local offset=self.rightDockScroll:GetVerticalScroll()or 0;local maximum=self.rightDockScroll:GetVerticalScrollRange()or 0
    self.rightDockUp:SetEnabled(offset>0);self.rightDockDown:SetEnabled(offset<maximum-1)
end

function UI:LayoutRightDock()
    if not self.rightDock then return end
    local height=math.max(150,(self.frame:GetHeight()or 560)-96);self.rightDock:SetHeight(height)
    local entries={};for _,entry in pairs(self.rightDockEntries or{})do entries[#entries+1]=entry end;table.sort(entries,function(a,b)if a.order==b.order then return a.id<b.id end;return a.order<b.order end)
    for index,entry in ipairs(entries)do entry.slot:ClearAllPoints();entry.slot:SetPoint("TOPLEFT",self.rightDockContent,"TOPLEFT",2,-((index-1)*40));entry.slot:Show()end
    self.rightDockContent:SetHeight(math.max(height-32,#entries*40));self.rightDockScroll:UpdateScrollChildRect();local maximum=self.rightDockScroll:GetVerticalScrollRange()or 0;if self.rightDockScroll:GetVerticalScroll()>maximum then self.rightDockScroll:SetVerticalScroll(maximum)end;self:UpdateRightDockArrows()
end

function UI:CreateRightDock()
    self.rightDockEntries = {}
    local dock=CreateFrame("Frame",nil,UIParent);dock:SetPoint("TOPLEFT",self.frame,"TOPRIGHT",-6,-48);dock:SetWidth(48);dock:SetFrameStrata("MEDIUM");dock:SetFrameLevel(math.max(1,self.frame:GetFrameLevel()-20));local scroll=CreateFrame("ScrollFrame",nil,dock);scroll:SetPoint("TOPLEFT",0,-16);scroll:SetPoint("BOTTOMRIGHT",0,16);scroll:EnableMouseWheel(true);local content=CreateFrame("Frame",nil,scroll);content:SetWidth(46);content:SetHeight(1);scroll:SetScrollChild(content);local up=CreateFrame("Button",nil,dock,"UIPanelScrollUpButtonTemplate");up:SetSize(24,16);up:SetPoint("TOP",0,0);up:SetScript("OnClick",function()UI:ScrollRightDock(-80)end);local down=CreateFrame("Button",nil,dock,"UIPanelScrollDownButtonTemplate");down:SetSize(24,16);down:SetPoint("BOTTOM",0,0);down:SetScript("OnClick",function()UI:ScrollRightDock(80)end);scroll:SetScript("OnMouseWheel",function(_,delta)UI:ScrollRightDock(delta>0 and-80 or 80)end);scroll:SetScript("OnVerticalScroll",function()UI:UpdateRightDockArrows()end);self.rightDock,self.rightDockScroll,self.rightDockContent,self.rightDockUp,self.rightDockDown=dock,scroll,content,up,down
    self:AddRightDockIcon("home", 1, "Interface\\Icons\\INV_Misc_Note_05", L["RIGHT_DOCK_HOME_TITLE"], L["RIGHT_DOCK_HOME_DESCRIPTION"], function() UI:Open() end)
    self:AddRightDockIcon("options", 2, "Interface\\Icons\\INV_Misc_Gear_01", L["RIGHT_DOCK_OPTIONS_TITLE"], L["RIGHT_DOCK_OPTIONS_DESCRIPTION"], function() HolyStorm:GetModule("Options", true):Open() end)
    self.frame:HookScript("OnSizeChanged",function()UI:LayoutRightDock()end)
    self:LayoutRightDock()
    self:SetRightDockSelected("home")
end

function UI:RegisterPage(id, pageFrame, title, onShow)
    self.pages[id] = { frame = pageFrame, title = title, onShow = onShow }
    pageFrame:SetParent(self.content)
    pageFrame:SetAllPoints(self.content)
    pageFrame:Hide()
end

function UI:EnsurePageContextHeader(id)
    local definition=self.pageContextHeaders[id]
    if not definition or definition.frame or not self.contextHeaderSlot then return definition and definition.frame~=nil end
    local content=CreateFrame("Frame",nil,self.contextHeaderSlot);content:SetAllPoints(self.contextHeaderSlot);content:Hide()
    definition.frame=content
    local ok=HolyStorm.Utils.SafeCall("ui.context-header.build:"..id,definition.build,content,self)
    if not ok then content:Hide();content:SetParent(nil);definition.frame=nil;return false end
    return true
end

function UI:RegisterPageContextHeader(id,owner,definition)
    if type(id)~="string"or id==""or type(owner)~="string"or owner==""or type(definition)~="table"or type(definition.build)~="function"or type(definition.layout)~="function"or type(definition.height)~="function"then return false,"INVALID_PAGE_CONTEXT_HEADER"end
    if self.pageContextHeaders[id]then return false,self.pageContextHeaders[id].owner==owner and"PAGE_CONTEXT_HEADER_EXISTS"or"PAGE_CONTEXT_HEADER_OWNER_CONFLICT"end
    self.pageContextHeaders[id]={owner=owner,build=definition.build,layout=definition.layout,height=definition.height}
    self:EnsurePageContextHeader(id)
    if not self.pageContextHeaders[id].frame and self.contextHeaderSlot then self.pageContextHeaders[id]=nil;return false,"PAGE_CONTEXT_HEADER_BUILD_FAILED"end
    if self.activeContextHeaderPage==id then self:LayoutPageContextHeader()end
    return true
end

function UI:UnregisterPageContextHeader(id,owner)
    local definition=self.pageContextHeaders[id]
    if not definition then return false end
    if owner and definition.owner~=owner then return false,"OWNER_MISMATCH"end
    if definition.frame then definition.frame:Hide();definition.frame:SetParent(nil)end
    self.pageContextHeaders[id]=nil
    if self.activeContextHeaderPage==id then self.activeContextHeaderPage=nil;self:LayoutPageContextHeader()end
    return true
end

function UI:SetActiveContextHeaderPage(id)
    self.activeContextHeaderPage=id
    self:LayoutPageContextHeader()
end

function UI:LayoutPageContextHeader()
    local slot,inset,content=self.contextHeaderSlot,self.contentInset,self.content
    if not slot or not inset or not content then return false end
    local active=self.activeContextHeaderPage and self.pageContextHeaders[self.activeContextHeaderPage]
    for id,definition in pairs(self.pageContextHeaders)do if definition.frame then definition.frame:SetShown(definition==active)end end
    if not active or not self:EnsurePageContextHeader(self.activeContextHeaderPage)then
        slot:Hide();content:ClearAllPoints();content:SetPoint("TOPLEFT",inset,"TOPLEFT",5,-5);content:SetPoint("BOTTOMRIGHT",inset,"BOTTOMRIGHT",-5,30)
        return true
    end
    local width=math.max(1,slot:GetWidth()or content:GetWidth()or 1)
    local ok,height=HolyStorm.Utils.SafeCall("ui.context-header.height:"..self.activeContextHeaderPage,active.height,width)
    height=ok and math.max(1,math.min(240,tonumber(height)or 1))or 1
    slot:SetHeight(height);slot:Show();active.frame:Show()
    content:ClearAllPoints();content:SetPoint("TOPLEFT",inset,"TOPLEFT",5,-(11+height));content:SetPoint("BOTTOMRIGHT",inset,"BOTTOMRIGHT",-5,30)
    HolyStorm.Utils.SafeCall("ui.context-header.layout:"..self.activeContextHeaderPage,active.layout,active.frame,width,height)
    return true
end

function UI:UnregisterPage(id)
    local page=self.pages[id]
    if not page then return false end
    self:UnregisterPageContextHeader(id)
    page.frame:Hide(); self.pages[id]=nil; return true
end

function UI:HideRegisteredPages()
    for _, page in pairs(self.pages) do page.frame:Hide() end
end

function UI:ShowPage(id)
    local page = self.pages[id]
    if not page then return end
    if self.optionsContainer then self.optionsContainer.frame:Hide() end
    self.scroll.frame:Hide(); self:HideRegisteredPages(); self.frame:Show();self:SetActiveContextHeaderPage(id)
    self.windowTitle:SetText(page.title); self:SetRightDockSelected(id); page.frame:Show()
    if page.onShow then page.onShow() end
end

function UI:GetWindowSettings() return HolyStorm.Database:Get("window", "profile") or {} end
function UI:LoadWindowState()
    if not self.frame then return end
    local settings = self:GetWindowSettings()
    if settings.saveSize and settings.size then self.frame:SetSize(settings.size.width, settings.size.height) end
    if settings.savePosition and settings.position then self.frame:ClearAllPoints(); self.frame:SetPoint(settings.position.point, UIParent, settings.position.relativePoint, settings.position.x, settings.position.y) end
end
function UI:SaveWindowPosition()
    if not self:GetWindowSettings().savePosition or not self.frame then return end
    local point, _, relativePoint, x, y = self.frame:GetPoint(1)
    if point then HolyStorm.Database:Set("window.position", { point = point, relativePoint = relativePoint, x = x, y = y }, "profile") end
end
function UI:SaveWindowSize()
    if self:GetWindowSettings().saveSize and self.frame then HolyStorm.Database:Set("window.size", { width = self.frame:GetWidth(), height = self.frame:GetHeight() }, "profile") end
end
function UI:ResetWindowPosition() HolyStorm.Database:Set("window.position", nil, "profile"); if self.frame then self.frame:ClearAllPoints(); self.frame:SetPoint("CENTER") end end
function UI:ResetWindowSize() HolyStorm.Database:Set("window.size", nil, "profile"); if self.frame then self.frame:SetSize(900, 560) end end
function UI:Open() if self.frame then if not self.frame:IsShown() then self:LoadWindowState() end; self.frame:Show(); self:ShowModules() end end
function UI:ShowModules() self:SetActiveContextHeaderPage(nil);if self.optionsContainer then self.optionsContainer.frame:Hide() end; self:HideRegisteredPages(); self.scroll.frame:Show(); self.page.frame:Show(); self.windowTitle:SetText(L["WINDOW_TITLE"]); self:SetReadyStatus(); self:SetRightDockSelected("home"); self:ShowNewsPortal() end
function UI:RegisterDashboardProvider(id,provider) if type(id)~="string" or type(provider)~="function" then return false end; self.dashboardProviders[id]=provider; return true end
function UI:RefreshDashboardProviders() return self:RefreshDashboard() end
function UI:ShowNewsPortal() for _,element in ipairs(self.dashboardElements or{})do element:Show()end;return self:RefreshDashboard()end
function UI:ShowNewsArticle() return self:ShowNewsPortal() end
function UI:ShowOptions(appName)
    if not self.optionsContainer then
        self.optionsContainer = LibStub("AceGUI-3.0"):Create("SimpleGroup")
        self.optionsContainer:SetLayout("Fill"); self.optionsContainer.frame:SetParent(self.content); self.optionsContainer.frame:SetAllPoints(self.content)
        LibStub("AceConfigDialog-3.0"):Open(appName, self.optionsContainer)
    end
    self:SetActiveContextHeaderPage(nil);self:HideRegisteredPages(); self.scroll.frame:Hide(); self.frame:Show(); self.windowTitle:SetText(L["WINDOW_TITLE_OPTIONS"]); self:SetRightDockSelected("options"); self.optionsContainer.frame:Show()
end
