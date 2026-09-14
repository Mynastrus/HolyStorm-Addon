local addonVersion = "2.2.1"
local HolyStorm = LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local L = LibStub("AceLocale-3.0"):GetLocale("Holy_Storm_UI")

local UI = HolyStorm:RegisterRequiredModule("UI")
UI.dashboardProviders = {}
HolyStorm:ApplyModuleMetadata(UI, {
    displayName = L["DISPLAY_NAME"], internalName = "ui", version = addonVersion,
    category = "required", description = L["DESCRIPTION"], permissions = { "ui-render" },
    dependencies = { "core" }, enabledByDefault = true,
})

local function addTooltip(button, text)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(text)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
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
    local root = page.content
    local dashboard = {}
    local function remember(object) table.insert(dashboard, object); return object end
    local dashboardGroup = aceGUI:Create("SimpleGroup")
    dashboardGroup:SetFullWidth(true)
    dashboardGroup:SetLayout("Flow")
    page:AddChild(dashboardGroup)
    remember(dashboardGroup.frame)

    local description = aceGUI:Create("Label")
    description:SetText(L["WINDOW_DESCRIPTION"])
    description:SetFontObject(GameFontHighlightLarge)
    description:SetFullWidth(true)
    description:SetJustifyH("CENTER")
    description:SetHeight(46)
    dashboardGroup:AddChild(description)
    local heading = aceGUI:Create("Heading")
    heading:SetText(L["NEWS_PORTAL_TITLE"])
    heading:SetFullWidth(true)
    dashboardGroup:AddChild(heading)
    local liveContent = aceGUI:Create("SimpleGroup")
    liveContent:SetFullWidth(true); liveContent:SetLayout("List"); dashboardGroup:AddChild(liveContent); remember(liveContent.frame)

    local articleFrame = CreateFrame("Frame", nil, root)
    articleFrame:SetAllPoints(root); articleFrame:Hide()
    local articleTitle = articleFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    articleTitle:SetPoint("TOPLEFT", articleFrame, "TOPLEFT", 28, -72); articleTitle:SetTextColor(0.25, 0.78, 0.92)
    local articleText = articleFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    articleText:SetPoint("TOPLEFT", articleTitle, "BOTTOMLEFT", 0, -24); articleText:SetPoint("RIGHT", articleFrame, "RIGHT", -56, 0)
    articleText:SetJustifyH("LEFT"); articleText:SetJustifyV("TOP")
    local back = CreateFrame("Button", nil, articleFrame)
    back:SetSize(24, 24); back:SetPoint("BOTTOMLEFT", articleFrame, "BOTTOMLEFT", 28, 30)
    back:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up")
    back:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Down")
    back:SetScript("OnClick", function() UI:ShowNewsPortal() end)
    addTooltip(back, L["NEWS_BACK_TOOLTIP"])

    local entries = {
        { icon = "Interface\\Icons\\INV_Misc_Note_05", title = L["NEWS_WELCOME_TITLE"], summary = L["NEWS_WELCOME_SUMMARY"], detail = L["NEWS_WELCOME_DETAIL"] },
        { icon = "Interface\\Icons\\INV_Misc_GroupLooking", title = L["NEWS_MODULES_TITLE"], summary = L["NEWS_MODULES_SUMMARY"], detail = L["NEWS_MODULES_DETAIL"] },
        { icon = "Interface\\Icons\\INV_Misc_Gear_01", title = L["NEWS_PROFILES_TITLE"], summary = L["NEWS_PROFILES_SUMMARY"], detail = L["NEWS_PROFILES_DETAIL"] },
    }
    for _, entry in ipairs(entries) do
        local card = aceGUI:Create("InlineGroup")
        card:SetTitle("")
        card:SetLayout("Flow")
        card:SetRelativeWidth(0.32)
        card:SetHeight(133)
        card.frame:EnableMouse(true)
        local highlight = CreateFrame("Frame", nil, card.frame, "BackdropTemplate")
        highlight:SetPoint("TOPLEFT", card.content, "TOPLEFT", -10, 10)
        highlight:SetPoint("BOTTOMRIGHT", card.content, "BOTTOMRIGHT", 10, -10)
        highlight:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12 })
        highlight:SetBackdropBorderColor(1, 0.82, 0, 0.9)
        highlight:SetFrameLevel(card.frame:GetFrameLevel() + 2)
        highlight:Hide()
        card.frame:SetScript("OnEnter", function() highlight:Show() end)
        card.frame:SetScript("OnLeave", function() highlight:Hide() end)
        card.frame:SetScript("OnMouseUp", function(_, button)
            if button == "LeftButton" then UI:ShowNewsArticle(entry) end
        end)
        dashboardGroup:AddChild(card)

        local icon = aceGUI:Create("Icon")
        icon:SetImage(entry.icon)
        icon:SetImageSize(58, 58)
        icon:SetWidth(58)
        icon:SetHeight(74)
        icon.image:ClearAllPoints()
        icon.image:SetPoint("TOPLEFT", icon.frame, "TOPLEFT", 0, 0)
        icon.frame:EnableMouse(false)
        for _, region in ipairs({ icon.frame:GetRegions() }) do
            if region:GetDrawLayer() == "HIGHLIGHT" then region:Hide() end
        end
        card:AddChild(icon)
        local spacer = aceGUI:Create("Label")
        spacer:SetWidth(8)
        spacer:SetHeight(74)
        card:AddChild(spacer)

        local textColumn = aceGUI:Create("SimpleGroup")
        textColumn:SetLayout("List")
        textColumn:SetRelativeWidth(0.63)
        textColumn:SetHeight(74)
        textColumn.noAutoHeight = true
        card:AddChild(textColumn)

        local cardTitle = aceGUI:Create("Label")
        cardTitle:SetText(entry.title)
        cardTitle:SetFontObject(GameFontNormal)
        cardTitle:SetFullWidth(true)
        cardTitle:SetHeight(18)
        cardTitle:SetJustifyV("TOP")
        cardTitle.label:SetTextColor(1, 0.82, 0)
        textColumn:AddChild(cardTitle)
        local titleSpacer = aceGUI:Create("SimpleGroup")
        titleSpacer:SetFullWidth(true)
        titleSpacer:SetHeight(10)
        titleSpacer.noAutoHeight = true
        textColumn:AddChild(titleSpacer)
        local text = aceGUI:Create("Label")
        text:SetText(entry.summary)
        text:SetFullWidth(true)
        text:SetJustifyV("TOP")
        textColumn:AddChild(text)
    end

    local modulesTitle = aceGUI:Create("Heading")
    modulesTitle:SetText(L["MODULE_LIST_TITLE"])
    modulesTitle:SetFullWidth(true)
    dashboardGroup:AddChild(modulesTitle)
    for _, metadata in ipairs(HolyStorm:GetModuleEntries()) do
        local line = aceGUI:Create("Label")
        line:SetText(string.format(L["MODULE_LIST_ENTRY"], metadata.displayName, metadata.version))
        line:SetFullWidth(true)
        dashboardGroup:AddChild(line)
    end
    local commandsTitle = aceGUI:Create("Heading")
    commandsTitle:SetText(L["COMMAND_LIST_TITLE"])
    commandsTitle:SetFullWidth(true)
    dashboardGroup:AddChild(commandsTitle)
    local commands = {
        { label = L["COMMAND_OPEN_LABEL"], action = function() UI:Open() end },
        { label = L["COMMAND_OPTIONS_LABEL"], action = function() HolyStorm:GetModule("Options", true):Open() end },
        { label = L["COMMAND_HELP_LABEL"], action = function() SlashCmdList.HOLYSTORM("?") end },
        { label = L["RELOAD_UI_LABEL"], action = ReloadUI },
    }
    for index, command in ipairs(commands) do
        local button = aceGUI:Create("Button")
        button:SetText(command.label); button:SetFullWidth(true); button:SetCallback("OnClick", command.action); dashboardGroup:AddChild(button)
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
    self.dashboardElements, self.dashboardContent, self.newsArticleFrame, self.newsArticleTitle, self.newsArticleText, self.windowTitle, self.status = dashboard, liveContent, articleFrame, articleTitle, articleText, title, status
    self:LoadWindowState()
    self:CreateRightDock()
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
function UI:RefreshDashboardProviders()
    if not self.dashboardContent then return end; self.dashboardContent:ReleaseChildren(); local ids={};for id in pairs(self.dashboardProviders)do ids[#ids+1]=id end;table.sort(ids)
    for _,id in ipairs(ids)do local ok,entries,unavailable=HolyStorm.Utils.SafeCall("dashboard:"..id,self.dashboardProviders[id]);if ok then if unavailable then local note=LibStub("AceGUI-3.0"):Create("Label");note:SetText(unavailable);note:SetFullWidth(true);self.dashboardContent:AddChild(note)end;for _,entry in ipairs(entries or{})do local item=LibStub("AceGUI-3.0"):Create("Button");item:SetText((entry.title or"")..(entry.summary and("  |cffb8b8b8"..entry.summary.."|r")or""));item:SetFullWidth(true);item:SetCallback("OnClick",entry.onClick);self.dashboardContent:AddChild(item)end end end
end
function UI:ShowNewsPortal() self.newsArticleFrame:Hide(); for _, element in ipairs(self.dashboardElements) do element:Show() end; self:RefreshDashboardProviders() end
function UI:ShowNewsArticle(entry) for _, element in ipairs(self.dashboardElements) do element:Hide() end; self.newsArticleTitle:SetText(entry.title); self.newsArticleText:SetText(entry.detail); self.newsArticleFrame:Show(); self.scroll:SetScroll(0) end
function UI:ShowOptions(appName)
    if not self.optionsContainer then
        self.optionsContainer = LibStub("AceGUI-3.0"):Create("SimpleGroup")
        self.optionsContainer:SetLayout("Fill"); self.optionsContainer.frame:SetParent(self.content); self.optionsContainer.frame:SetAllPoints(self.content)
        LibStub("AceConfigDialog-3.0"):Open(appName, self.optionsContainer)
    end
    self:HideRegisteredPages(); self.scroll.frame:Hide(); self.frame:Show(); self.windowTitle:SetText(L["WINDOW_TITLE_OPTIONS"]); self:SetRightDockSelected("options"); self.optionsContainer.frame:Show()
end
