local addonVersion = "2.3.1"
local HolyStorm = LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local L = LibStub("AceLocale-3.0"):GetLocale("Holy_Storm_UI")

local UI = HolyStorm:RegisterRequiredModule("UI")
UI.dashboardProviders = {}
HolyStorm:ApplyModuleMetadata(UI, {
    displayName = L["DISPLAY_NAME"], internalName = "ui", version = addonVersion,
    category = "required", description = L["DESCRIPTION"], permissions = { "ui-render" },
    dependencies = { "core" }, enabledByDefault = true,
})

local UNKNOWN = "|cff888888\226\128\147|r"
local SPEC_FALLBACK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local RAID_SHORT = { MYTHIC="M", HEROIC="H", NORMAL="N", LFR="LFR" }

local function numberText(value)
    value=tonumber(value);if value==nil then return UNKNOWN end
    return value%1==0 and tostring(value)or string.format("%.1f",value)
end

function UI:BuildDashboardModel()
    local characterUI=HolyStorm.CharacterUI;local guid=UnitGUID and UnitGUID("player")
    local summary=characterUI and characterUI.GetDashboardSummary and characterUI:GetDashboardSummary(guid)or nil
    local best=summary and summary.bestRaid;local raidText=UNKNOWN
    if best and RAID_SHORT[best.difficulty]and tonumber(best.killed)and tonumber(best.total)then raidText=string.format("%s %d/%d",RAID_SHORT[best.difficulty],best.killed,best.total)end
    local specText=UNKNOWN
    if summary then specText=(summary.specName or UNKNOWN).." \226\128\147 "..(summary.className or UNKNOWN)end
    return{name=summary and summary.coloredName or UNKNOWN,specialization=specText,specIcon=summary and summary.specIcon or SPEC_FALLBACK_ICON,itemLevel=numberText(summary and summary.itemLevel),mythicPlusRating=numberText(summary and summary.mythicPlusRating),bestRaid=raidText}
end

function UI:RefreshDashboard()
    if not self.dashboardWidgets then return false end
    local model=self:BuildDashboardModel();local widgets=self.dashboardWidgets
    widgets.icon:SetImage(model.specIcon);widgets.name:SetText(model.name);widgets.specialization:SetText(model.specialization)
    widgets.itemLevel:SetText(model.itemLevel);widgets.mythicPlusRating:SetText(model.mythicPlusRating);widgets.bestRaid:SetText(model.bestRaid)
    if self.scroll then self.scroll:DoLayout()end
    return true
end

function UI:RegisterDashboardEvents()
    for _,event in ipairs({"HS_CHARACTER_UPDATED","HS_STATS_UPDATED","HS_EQUIPMENT_UPDATED","HS_MYTHICPLUS_UPDATED","HS_RAIDLOCKS_UPDATED"})do
        HolyStorm.Events:Register(event,"ui-dashboard",function(_,guid)if not guid or guid==UnitGUID("player")then UI:RefreshDashboard()end end)
    end
end

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
    if portrait then portrait:SetTexture("Interface\\Icons\\Spell_Holy_HolyBolt") end

    if not tContains(UISpecialFrames, "HolyStormMainFrame") then table.insert(UISpecialFrames, "HolyStormMainFrame") end
    local aceGUI = LibStub("AceGUI-3.0")
    local inset = frame.Inset or frame
    local content = CreateFrame("Frame", nil, frame)
    content:SetPoint("TOPLEFT", inset, "TOPLEFT", 5, -5)
    content:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -5, 5)

    local scroll = aceGUI:Create("ScrollFrame")
    scroll:SetLayout("List")
    scroll.frame:SetParent(content)
    scroll.frame:SetAllPoints(content)
    local function updateScrollLayout(_, width, height)
        scroll:SetWidth(width)
        scroll:SetHeight(height)
        scroll:DoLayout()
    end
    content:HookScript("OnSizeChanged", updateScrollLayout)
    updateScrollLayout(nil, content:GetWidth(), content:GetHeight())
    local page = aceGUI:Create("SimpleGroup")
    page:SetFullWidth(true)
    page:SetLayout("List")
    scroll:AddChild(page)
    local dashboard = {}
    local dashboardGroup = aceGUI:Create("SimpleGroup")
    dashboardGroup:SetFullWidth(true)
    dashboardGroup:SetLayout("List")
    page:AddChild(dashboardGroup)
    table.insert(dashboard, dashboardGroup.frame)

    local identity = aceGUI:Create("SimpleGroup")
    identity:SetFullWidth(true); identity:SetLayout("Flow"); identity:SetHeight(84); identity.noAutoHeight = true
    dashboardGroup:AddChild(identity)
    local specIcon = aceGUI:Create("Icon")
    specIcon:SetImage(SPEC_FALLBACK_ICON); specIcon:SetImageSize(64, 64); specIcon:SetWidth(78); specIcon:SetHeight(74)
    specIcon.frame:EnableMouse(false)
    identity:AddChild(specIcon)
    local identityText = aceGUI:Create("SimpleGroup")
    identityText:SetLayout("List"); identityText:SetRelativeWidth(0.82); identityText:SetHeight(70); identityText.noAutoHeight = true
    identity:AddChild(identityText)
    local characterName = aceGUI:Create("Label")
    characterName:SetText(UNKNOWN); characterName:SetFontObject(GameFontHighlightLarge); characterName:SetFullWidth(true); characterName:SetHeight(30)
    identityText:AddChild(characterName)
    local specialization = aceGUI:Create("Label")
    specialization:SetText(UNKNOWN); specialization:SetFontObject(GameFontHighlight); specialization:SetFullWidth(true); specialization:SetHeight(24)
    identityText:AddChild(specialization)

    local statistics = aceGUI:Create("SimpleGroup")
    statistics:SetFullWidth(true); statistics:SetLayout("Flow"); statistics:SetHeight(86); statistics.noAutoHeight = true
    dashboardGroup:AddChild(statistics)
    local values = {}
    for _, definition in ipairs({
        { "itemLevel", "DASHBOARD_ITEM_LEVEL" },
        { "mythicPlusRating", "DASHBOARD_MYTHICPLUS_RATING" },
        { "bestRaid", "DASHBOARD_BEST_RAID" },
    }) do
        local column = aceGUI:Create("SimpleGroup")
        column:SetLayout("List"); column:SetRelativeWidth(0.333); column:SetHeight(76); column.noAutoHeight = true
        statistics:AddChild(column)
        local label = aceGUI:Create("Label")
        label:SetText(L[definition[2]]); label:SetFontObject(GameFontNormal); label:SetFullWidth(true); label:SetJustifyH("CENTER"); label:SetHeight(24)
        column:AddChild(label)
        local value = aceGUI:Create("Label")
        value:SetText(UNKNOWN); value:SetFontObject(GameFontHighlightLarge); value:SetFullWidth(true); value:SetJustifyH("CENTER"); value:SetHeight(34)
        column:AddChild(value)
        values[definition[1]] = value
    end

    local status = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    status:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 10); status:SetText(string.format(L["STATUS_BAR_READY"], HolyStorm.version))
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
    self.dashboardElements, self.dashboardWidgets, self.windowTitle, self.status = dashboard, { icon=specIcon, name=characterName, specialization=specialization, itemLevel=values.itemLevel, mythicPlusRating=values.mythicPlusRating, bestRaid=values.bestRaid }, title, status
    self:LoadWindowState()
    self:CreateRightDock()
    self:RegisterDashboardEvents()
    frame:HookScript("OnShow", function() UI:SetRightDockVisible(true) end)
    frame:HookScript("OnHide", function() UI:SetRightDockVisible(false) end)
    self:SetRightDockVisible(false)
    HolyStorm.UI:SetDriver(self)
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

function UI:UnregisterPage(id)
    local page=self.pages[id]
    if not page then return false end
    page.frame:Hide(); self.pages[id]=nil; return true
end

function UI:HideRegisteredPages()
    for _, page in pairs(self.pages) do page.frame:Hide() end
end

function UI:ShowPage(id)
    local page = self.pages[id]
    if not page then return end
    if self.optionsContainer then self.optionsContainer.frame:Hide() end
    self.scroll.frame:Hide(); self:HideRegisteredPages(); self.frame:Show()
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
function UI:ShowModules() if self.optionsContainer then self.optionsContainer.frame:Hide() end; self:HideRegisteredPages(); self.scroll.frame:Show(); self.page.frame:Show(); self.windowTitle:SetText(L["WINDOW_TITLE"]); self:SetReadyStatus(); self:SetRightDockSelected("home"); self:ShowNewsPortal() end
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
    self:HideRegisteredPages(); self.scroll.frame:Hide(); self.frame:Show(); self.windowTitle:SetText(L["WINDOW_TITLE_OPTIONS"]); self:SetRightDockSelected("options"); self.optionsContainer.frame:Show()
end
