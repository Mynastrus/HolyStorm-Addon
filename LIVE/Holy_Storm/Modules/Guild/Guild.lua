local addonVersion = "2.2.0"
local HolyStorm = LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local L = LibStub("AceLocale-3.0"):GetLocale("Holy_Storm_GuildRoster")

HolyStorm:RegisterModule({
    id = "GuildRoster", name = "GuildRoster", displayName = L["DISPLAY_NAME"], internalName = "guildRoster", version = addonVersion,
    moduleType = "feature", category = "required", description = L["DESCRIPTION"], permissions = {{id="guild-roster-read",category="Roster",defaults={member=true}}, {id="roster-manage",category="Roster",defaults={officers=true}}},
    dependencies = { "core", "ui", "options" }, ui = { page = "guildRoster", navigation = true },
    data = { stores = { "GuildStore", "CharacterStore" } }, enabledByDefault = true,
    ruleFields = {
        {id="guild.rank",aliases={"guildRank"},type="string",name=L["RULE_FIELD_GUILD_RANK"],nameKey="RULE_FIELD_GUILD_RANK",description=L["RULE_FIELD_GUILD_RANK_DESC"],descriptionKey="RULE_FIELD_GUILD_RANK_DESC",category=L["DISPLAY_NAME"],dependencies={"roster"},resolver=function(context)return(context.member and context.member.rank)or(context.character and context.character.guildRank)end},
        {id="guild.rankIndex",type="number",name=L["RULE_FIELD_GUILD_RANK_INDEX"],nameKey="RULE_FIELD_GUILD_RANK_INDEX",description=L["RULE_FIELD_GUILD_RANK_INDEX_DESC"],descriptionKey="RULE_FIELD_GUILD_RANK_INDEX_DESC",category=L["DISPLAY_NAME"],dependencies={"roster"},resolver=function(context)return(context.member and context.member.rankIndex)or(context.character and context.character.guildRankIndex)end},
        {id="player.online",aliases={"online"},type="boolean",name=L["RULE_FIELD_ONLINE"],nameKey="RULE_FIELD_ONLINE",description=L["RULE_FIELD_ONLINE_DESC"],descriptionKey="RULE_FIELD_ONLINE_DESC",category=L["DISPLAY_NAME"],dependencies={"roster"},resolver=function(context)return context.member and context.member.online end},
        {id="player.afk",type="boolean",name=L["RULE_FIELD_AFK"],nameKey="RULE_FIELD_AFK",description=L["RULE_FIELD_AFK_DESC"],descriptionKey="RULE_FIELD_AFK_DESC",category=L["DISPLAY_NAME"],dependencies={"roster"},resolver=function(context)if not context.member then return nil,"MISSING_ROSTER"end;return context.member.status=="AFK"or context.member.status==1 end},
        {id="player.dnd",type="boolean",name=L["RULE_FIELD_DND"],nameKey="RULE_FIELD_DND",description=L["RULE_FIELD_DND_DESC"],descriptionKey="RULE_FIELD_DND_DESC",category=L["DISPLAY_NAME"],dependencies={"roster"},resolver=function(context)if not context.member then return nil,"MISSING_ROSTER"end;return context.member.status=="DND"or context.member.status==2 end},
    },
}, function(GuildRoster)

HolyStorm.FilterManager:RegisterTemplate("GuildRoster",{id="template-online",name=L["FILTER_TEMPLATE_ONLINE"],description=L["FILTER_TEMPLATE_ONLINE_DESC"],rules={field="player.online",operator="true"}})

local function setColumnText(fontString, text, color)
    fontString:SetText(text or L["UNKNOWN_VALUE"])
    fontString:SetTextColor(color[1], color[2], color[3])
end

local statusTextures = {
    offline = "Interface\\COMMON\\Indicator-Gray",
    online = "Interface\\COMMON\\Indicator-Green",
    afk = "Interface\\COMMON\\Indicator-Yellow",
    dnd = "Interface\\COMMON\\Indicator-Red",
}

function GuildRoster:FormatOfflineDuration(seconds)
    if not seconds or seconds <= 0 then return L["OFFLINE"] end
    if seconds >= 86400 then return string.format(L["OFFLINE_FOR"], string.format(L["DAYS"], math.floor(seconds / 86400))) end
    if seconds >= 3600 then return string.format(L["OFFLINE_FOR"], string.format(L["HOURS"], math.floor(seconds / 3600))) end
    return string.format(L["OFFLINE_FOR"], string.format(L["MINUTES"], math.max(1, math.floor(seconds / 60))))
end

function GuildRoster:GetSettings()
    local settings = HolyStorm.Database:Get("guildRoster", "profile")
    if settings.showOffline == nil then HolyStorm.Database:Set("guildRoster.showOffline", true, "profile") end
    if settings.groupTwinks == nil then HolyStorm.Database:Set("guildRoster.groupTwinks", true, "profile") end
    return settings
end

function GuildRoster:CreateColumn(parent, left, right)
    local text = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("LEFT", parent, left < 0 and "RIGHT" or "LEFT", left, 0)
    text:SetPoint("RIGHT", parent, "RIGHT", right, 0)
    text:SetJustifyH("LEFT")
    return text
end

function GuildRoster:CreateRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(22)
    row:EnableMouse(true)
    row.highlight = row:CreateTexture(nil, "BACKGROUND")
    row.highlight:SetAllPoints()
    row.highlight:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    row.highlight:SetBlendMode("ADD")
    row.highlight:SetAlpha(0.8)
    row.highlight:Hide()
    row:SetScript("OnEnter", function(self) self.highlight:Show() end)
    row:SetScript("OnLeave", function(self) self.highlight:Hide() end)
    row.indicator = row:CreateTexture(nil, "ARTWORK")
    row.indicator:SetSize(14, 14); row.indicator:SetPoint("LEFT", row, "LEFT", 8, 0)
    row.classIcon=row:CreateTexture(nil,"ARTWORK");row.classIcon:SetSize(16,16);row.classIcon:SetPoint("LEFT",row,"LEFT",27,0);row.classIcon:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
    row.twinkArrow = row:CreateTexture(nil, "ARTWORK")
    row.twinkArrow:SetSize(10, 10); row.twinkArrow:SetPoint("LEFT", row, "LEFT", 50, 0)
    row.twinkArrow:SetTexture("Interface\\Buttons\\Arrow-Up-Up")
    row.twinkArrow:SetRotation(-math.pi / 2)
    row.twinkArrow:Hide()
    row.name = self:CreateColumn(row, 46, -500); row.rank = self:CreateColumn(row, -490, -385)
    row.level = self:CreateColumn(row, -375, -330); row.realm = self:CreateColumn(row, -320, -220); row.realm:SetWordWrap(false)
    row.zone = self:CreateColumn(row, -210, -110); row.status = self:CreateColumn(row, -100, -10)
    return row
end

function GuildRoster:CreateMemberMenu()
    local menu = CreateFrame("Frame", "HolyStormGuildMemberMenu", UIParent, "BasicFrameTemplateWithInset")
    menu:SetSize(360, 424); menu:SetFrameStrata("DIALOG"); menu:SetToplevel(true); menu:SetClampedToScreen(true); menu:SetMovable(true); menu:EnableMouse(true); menu:RegisterForDrag("LeftButton"); menu:Hide()
    menu:SetScript("OnDragStart", function(self) self:StartMoving() end)
    menu:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    if not tContains(UISpecialFrames, "HolyStormGuildMemberMenu") then table.insert(UISpecialFrames, "HolyStormGuildMemberMenu") end
    menu.title = menu:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    menu.title:SetPoint("TOPLEFT", menu, "TOPLEFT", 20, -28); menu.title:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -42, -28); menu.title:SetJustifyH("LEFT")
    menu.detail = menu:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    menu.detail:SetPoint("TOPLEFT", menu.title, "BOTTOMLEFT", 0, -6); menu.detail:SetJustifyH("LEFT")
    menu.zone = menu:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    menu.zone:SetPoint("TOPLEFT", menu.detail, "BOTTOMLEFT", 0, -16); menu.zone:SetJustifyH("LEFT")
    menu.rank = menu:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    menu.rank:SetPoint("TOPLEFT", menu.zone, "BOTTOMLEFT", 0, -12); menu.rank:SetJustifyH("LEFT")
    menu.lastSeen = menu:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    menu.lastSeen:SetPoint("TOPLEFT", menu.rank, "BOTTOMLEFT", 0, -12); menu.lastSeen:SetJustifyH("LEFT")

    local function createNoteBox(label, top)
        local labelText = menu:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        labelText:SetPoint("TOPLEFT", menu, "TOPLEFT", 20, top); labelText:SetText(label); labelText:SetTextColor(1, 0.82, 0)
        local box = CreateFrame("Frame", nil, menu, "BackdropTemplate")
        box:SetPoint("TOPLEFT", labelText, "BOTTOMLEFT", 0, -4); box:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -20, 0); box:SetHeight(58)
        box:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        box.text = box:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        box.text:SetPoint("TOPLEFT", box, "TOPLEFT", 8, -7); box.text:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -8, 7); box.text:SetJustifyH("LEFT"); box.text:SetJustifyV("TOP"); box.text:SetWordWrap(true)
        box.edit = CreateFrame("EditBox", nil, box)
        box.edit:SetPoint("TOPLEFT", box, "TOPLEFT", 8, -7); box.edit:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -8, 7)
        box.edit:SetFontObject(GameFontHighlight); box.edit:SetMultiLine(true); box.edit:SetAutoFocus(false); box.edit:SetMaxLetters(0); box.edit:SetJustifyH("LEFT"); box.edit:SetJustifyV("TOP")
        box.edit:SetScript("OnEscapePressed", function() menu:Hide() end); box.edit:Hide()
        return box
    end
    menu.note = createNoteBox(L["MEMBER_NOTE"], -154)
    menu.officerNote = createNoteBox(L["MEMBER_OFFICER_NOTE"], -244)
    menu.rankButton = CreateFrame("Button", nil, menu, "UIPanelButtonTemplate")
    menu.rankButton:SetSize(120, 21); menu.rankButton:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -20, -96); menu.rankButton:SetText(L["MEMBER_CHANGE_RANK"]); menu.rankButton:Hide()
    menu.rankButton:SetScript("OnClick", function() GuildRoster:ShowRankMenu(menu) end)
    menu.rankApply = CreateFrame("Button", nil, menu, "SecureActionButtonTemplate,UIPanelButtonTemplate")
    menu.rankApply:SetSize(120, 21); menu.rankApply:SetPoint("RIGHT", menu.rankButton, "LEFT", -4, 0); menu.rankApply:SetText(L["MEMBER_APPLY_RANK"]); menu.rankApply:Hide()
    menu.save = CreateFrame("Button", nil, menu, "UIPanelButtonTemplate")
    menu.save:SetSize(112, 24); menu.save:SetPoint("BOTTOMRIGHT", menu, "BOTTOMRIGHT", -20, 16); menu.save:SetText(L["MEMBER_SAVE"]); menu.save:Hide()
    menu.save:SetScript("OnClick", function()
        local member = menu.member
        if not member then return end
        HolyStorm.Actions:Execute("guild.save-notes", member.index, menu.note.edit:GetText(), menu.officerNote.edit:GetText(), menu.canEditNote, menu.canEditOfficerNote)
    end)
    menu.close = CreateFrame("Button", nil, menu, "UIPanelCloseButton")
    menu.close:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -4, -4)
    self.memberMenu = menu
end

function GuildRoster:ShowRankMenu(menu)
    local member = menu.member
    if InCombatLockdown() or not (member and member.guid and _G.C_GuildInfo and _G.C_GuildInfo.IsGuildRankAssignmentAllowed) then return end
    if not self.rankDropdown then self.rankDropdown = CreateFrame("Frame", "HolyStormGuildRosterRankDropdown", UIParent, "UIDropDownMenuTemplate") end
    UIDropDownMenu_Initialize(self.rankDropdown, function(_, level)
        if level ~= 1 then return end
        local currentOrder = _G.C_GuildInfo.GetGuildRankOrder and _G.C_GuildInfo.GetGuildRankOrder(member.guid) or (member.rankIndex + 1)
        for rankOrder = 1, GuildControlGetNumRanks() do
            if _G.C_GuildInfo.IsGuildRankAssignmentAllowed(member.guid, rankOrder) then
                local selectedOrder = rankOrder
                local info = UIDropDownMenu_CreateInfo()
                info.text = GuildControlGetRankName(selectedOrder)
                info.checked = selectedOrder == currentOrder
                info.func = function() GuildRoster:PrepareRankChange(menu, selectedOrder) end
                UIDropDownMenu_AddButton(info, level)
            end
        end
    end, "MENU")
    ToggleDropDownMenu(1, nil, self.rankDropdown, "cursor", 0, 0)
end

function GuildRoster:PrepareRankChange(menu, targetOrder)
    local member = menu.member
    if InCombatLockdown() or not member then return end
    local currentOrder = _G.C_GuildInfo.GetGuildRankOrder and _G.C_GuildInfo.GetGuildRankOrder(member.guid) or (member.rankIndex + 1)
    if targetOrder == currentOrder then menu.rankApply:Hide(); return end
    local command = targetOrder < currentOrder and "/guildpromote " or "/guilddemote "
    local macroLines = {}
    for _ = 1, math.abs(targetOrder - currentOrder) do table.insert(macroLines, command .. (member.name or "")) end
    menu.rankApply:SetAttribute("type", "macro")
    menu.rankApply:SetAttribute("macrotext", table.concat(macroLines, "\n"))
    menu.rankApply:SetText(L["MEMBER_APPLY_RANK"] .. ": " .. (GuildControlGetRankName(targetOrder) or ""))
    menu.rankApply:Show()
end

function GuildRoster:ShowGuildMemberMenu(row, member)
    if not self.memberMenu then self:CreateMemberMenu() end
    local menu = self.memberMenu
    local classColor = RAID_CLASS_COLORS[member.classFileName] or NORMAL_FONT_COLOR
    menu.title:SetText(member.name or L["UNKNOWN_VALUE"]); menu.title:SetTextColor(classColor.r, classColor.g, classColor.b)
    menu.detail:SetText(string.format(L["MEMBER_LEVEL_CLASS"], member.level or 0, member.className or L["UNKNOWN_VALUE"]))
    menu.zone:SetText(L["MEMBER_ZONE"] .. " " .. (member.zone or L["UNKNOWN_VALUE"]))
    menu.rank:SetText(L["MEMBER_RANK"] .. " " .. (member.rank or L["UNKNOWN_VALUE"]))
    menu.lastSeen:SetText(L["MEMBER_LAST_SEEN"] .. " " .. (member.online and L["ONLINE"] or self:FormatOfflineDuration(member.status)))
    local note = member.note and member.note ~= "" and member.note or L["NO_NOTE"]
    local officerNote = member.officerNote and member.officerNote ~= "" and member.officerNote or L["NO_NOTE"]
    local policyCanManage=(HolyStorm.PermissionEngine or HolyStorm.Policy):Can("roster-manage")
    menu.canEditNote = policyCanManage and (((_G.CanEditPublicNote and _G.CanEditPublicNote()) or (_G.CanEditOfficerNote and _G.CanEditOfficerNote()))==true)
    menu.canEditOfficerNote = policyCanManage and ((_G.CanEditOfficerNote and _G.CanEditOfficerNote())==true)
    menu.member = member
    menu.note.text:SetText(note); menu.note.edit:SetText(member.note or ""); menu.note.text:SetShown(not menu.canEditNote); menu.note.edit:SetShown(menu.canEditNote)
    menu.officerNote.text:SetText(officerNote); menu.officerNote.edit:SetText(member.officerNote or ""); menu.officerNote.text:SetShown(not menu.canEditOfficerNote); menu.officerNote.edit:SetShown(menu.canEditOfficerNote)
    menu.save:SetShown(menu.canEditNote or menu.canEditOfficerNote)
    local canChangeRank = false
    if member.guid and _G.C_GuildInfo and _G.C_GuildInfo.IsGuildRankAssignmentAllowed and _G.GuildControlGetNumRanks then
        for rankOrder = 1, GuildControlGetNumRanks() do
            if _G.C_GuildInfo.IsGuildRankAssignmentAllowed(member.guid, rankOrder) then canChangeRank = true; break end
        end
    end
    menu.rankButton:SetShown(policyCanManage and canChangeRank and not InCombatLockdown())
    menu.rankApply:Hide()
    menu:ClearAllPoints(); menu:SetPoint("TOPLEFT", row, "BOTTOMLEFT", 18, 2); menu:Show(); menu:Raise()
end

function GuildRoster:CreateHeader(parent)
    local header = CreateFrame("Frame", nil, parent)
    header:SetHeight(24); header:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -70); header:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -70)
    header.indicator = self:CreateColumn(header, 10, -500); header.name = self:CreateColumn(header, 46, -500); header.rank = self:CreateColumn(header, -490, -385)
    header.level = self:CreateColumn(header, -375, -330); header.realm = self:CreateColumn(header, -320, -220); header.realm:SetWordWrap(false)
    header.zone = self:CreateColumn(header, -210, -110); header.status = self:CreateColumn(header, -100, -10)
    for _, column in ipairs({ "name", "rank", "level", "realm", "zone", "status" }) do
        header[column]:SetFontObject(GameFontNormalSmall); header[column]:SetText(L["COLUMN_" .. string.upper(column)]); header[column]:SetTextColor(1, 0.82, 0)
    end
end

function GuildRoster:ShowCharacter(member)
    return member and member.guid and HolyStorm.CharacterUI:OpenCharacter(member.guid,"summary")or false
end

function GuildRoster:OnInitialize()
    HolyStorm.Actions:Register("guild.save-notes", "GuildRoster", function(index, publicNote, officerNote, canEditPublic, canEditOfficer)
        if not (HolyStorm.PermissionEngine or HolyStorm.Policy):Can("roster-manage") then return false end
        if canEditPublic and _G.GuildRosterSetPublicNote then _G.GuildRosterSetPublicNote(index, publicNote) end
        if canEditOfficer and _G.GuildRosterSetOfficerNote then _G.GuildRosterSetOfficerNote(index, officerNote) end
        GuildRoster:RequestAndRefresh()
    end, { combatSafe=false, priority=0 })
    local UI = HolyStorm:GetModule("UI", true)
    local page = CreateFrame("Frame", nil, UI.content)
    local refresh = CreateFrame("Button", nil, UI.frame)
    refresh:SetSize(18, 18); refresh:SetPoint("RIGHT", UI.content, "TOPRIGHT", -20, 18)
    refresh:SetNormalTexture("Interface\\Buttons\\UI-RefreshButton")
    refresh:SetPushedTexture("Interface\\Buttons\\UI-RefreshButton")
    refresh:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    refresh:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_LEFT"); GameTooltip:SetText(L["REFRESH_TOOLTIP"]); GameTooltip:Show() end)
    refresh:SetScript("OnLeave", function() GameTooltip:Hide() end)
    refresh:SetScript("OnClick", function() GuildRoster:RequestAndRefresh() end)
    refresh:Hide()
    page:HookScript("OnShow", function() refresh:Show() end)
    page:HookScript("OnHide", function() refresh:Hide() end)
    self.filterBar=HolyStorm.PolicyUI:CreateFilterBar(page,"guildRoster",function()GuildRoster:Refresh()end);self.filterBar:SetPoint("TOPLEFT",page,"TOPLEFT",0,-6);self.filterBar:SetPoint("TOPRIGHT",page,"TOPRIGHT",-20,-6)
    self:CreateHeader(page)
    local scroll = CreateFrame("ScrollFrame", nil, page, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -94); scroll:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -28, 16)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1); scroll:SetScrollChild(content)
    scroll:SetScript("OnSizeChanged", function(self) content:SetWidth(self:GetWidth()) end)
    content:SetWidth(scroll:GetWidth())
    self.page, self.ui, self.refreshButton, self.scrollContent, self.rows = page, UI, refresh, content, {}
    HolyStorm.UI:RegisterPage("guildRoster", page, L["WINDOW_TITLE"], function() GuildRoster:Refresh() end, { "HS_ROSTER_UPDATED" })
    HolyStorm.UI:AddNavigation("guildRoster", 3, "Interface\\Icons\\INV_Misc_GroupLooking", L["NAVIGATION_TITLE"], L["NAVIGATION_DESCRIPTION"], function() GuildRoster:RequestAndRefresh(); HolyStorm.UI:ShowPage("guildRoster") end)
end

function GuildRoster:OnEnable()
    local Options = HolyStorm:GetModule("Options", true)
    if not Options then return end
    Options:RegisterOptionsTab("guildRoster", {
        type = "group", name = L["OPTIONS_TAB_TITLE"], order = 4,
        args = {
            showOffline = {
                type = "toggle", name = L["OPTION_SHOW_OFFLINE"], desc = L["OPTION_SHOW_OFFLINE_DESC"], order = 1,
                get = function() return GuildRoster:GetSettings().showOffline end,
                set = function(_, value) HolyStorm.Database:Set("guildRoster.showOffline", value, "profile"); GuildRoster:Refresh() end,
            },
            groupTwinks = {
                type = "toggle", name = L["OPTION_GROUP_TWINKS"], desc = L["OPTION_GROUP_TWINKS_DESC"], order = 2,
                get = function() return GuildRoster:GetSettings().groupTwinks end,
                set = function(_, value) HolyStorm.Database:Set("guildRoster.groupTwinks", value, "profile"); GuildRoster:Refresh() end,
            },
        },
    })
    HolyStorm.Events:Register("GUILD_ROSTER_UPDATE", "guild-ui", function() HolyStorm.UI:MarkDirty("guildRoster") end)
    HolyStorm.Events:Register("PLAYER_GUILD_UPDATE", "guild-ui", function() HolyStorm.UI:MarkDirty("guildRoster") end)
end

function GuildRoster:OnDisable() HolyStorm.Events:UnregisterOwner("guild-ui") end

function GuildRoster:RequestAndRefresh()
    if _G.GuildRoster then _G.GuildRoster() end
    HolyStorm.Tasks:Enqueue("guild.ui-refresh", function() HolyStorm.Data.GuildStore:RefreshFromBlizzard(); GuildRoster:Refresh() end, { priority=1, debounce=0.3, cooldown=1 })
end

function GuildRoster:Refresh()
    if not self.page or not self.page:IsShown() then return end
    if not IsInGuild() then HolyStorm.Events:Emit("HS_UI_STATUS_REQUESTED",L["NO_GUILD"]); self:RenderRows({}); return end
    local settings, guild = self:GetSettings(), HolyStorm.Data.GuildStore:GetCurrent()
    local members, memberCount = {}, 0
    for _, stored in pairs(guild and guild.roster or {}) do
        memberCount = memberCount + 1
        if settings.showOffline or stored.online then local c=HolyStorm.Data.CharacterStore:Get(stored.guid);table.insert(members, { index=stored.index,guid=stored.guid,name=stored.name,rank=stored.rank,rankIndex=stored.rankIndex or math.huge,level=stored.level,className=stored.class,zone=stored.zone,note=stored.note,officerNote=stored.officerNote,online=stored.online,status=stored.status,isMobile=stored.isMobile,classFileName=stored.classFile,itemLevel=c and c.itemLevel,mythicScore=c and c.mythicPlus and c.mythicPlus.overallScore,addonVersion=c and c.addon and c.addon.version }) end
    end
    if self.filterBar then members=self.filterBar:Apply(members)end
    table.sort(members, function(left, right)
        if left.online ~= right.online then return left.online end
        if left.rankIndex ~= right.rankIndex then return left.rankIndex < right.rankIndex end
        return (left.name or "") < (right.name or "")
    end)
    if not settings.groupTwinks then
        HolyStorm.Events:Emit("HS_UI_STATUS_REQUESTED",memberCount > 0 and string.format(L["STATUS_MEMBER_COUNT"], memberCount) or L["NO_MEMBERS"])
        self:RenderRows(members)
        return
    end
    local membersByGuid, twinksByOwner, twinkOwners = {}, {}, {}
    for _, member in ipairs(members) do
        if member.guid then membersByGuid[member.guid] = member end
    end
    self.lastMembersByGuid = membersByGuid
    for guid in pairs(membersByGuid)do local identity=HolyStorm.TwinkCore:GetRosterIdentity(guid,guild);if identity and identity.guildMain and identity.guildMain~=guid and membersByGuid[identity.guildMain]then twinkOwners[guid]=identity.guildMain;twinksByOwner[identity.guildMain]=twinksByOwner[identity.guildMain]or{};table.insert(twinksByOwner[identity.guildMain],membersByGuid[guid])end end
    local groupedMembers = {}
    for _, member in ipairs(members) do
        if not twinkOwners[member.guid] then
            table.insert(groupedMembers, member)
            local twinks = twinksByOwner[member.guid]
            if twinks then
                table.sort(twinks, function(left, right) return (left.name or "") < (right.name or "") end)
                for _, twink in ipairs(twinks) do twink.isTwink = true; table.insert(groupedMembers, twink) end
            end
        end
    end
    HolyStorm.Events:Emit("HS_UI_STATUS_REQUESTED",memberCount > 0 and string.format(L["STATUS_MEMBER_COUNT"], memberCount) or L["NO_MEMBERS"])
    self:RenderRows(groupedMembers)
end

function GuildRoster:RenderRows(members)
    for _, row in ipairs(self.rows) do row:Hide() end
    for index, member in ipairs(members) do
        local row = self.rows[index]
        if not row then row = self:CreateRow(self.scrollContent); self.rows[index] = row end
        row:ClearAllPoints(); row:SetPoint("TOPLEFT", self.scrollContent, "TOPLEFT", 0, -((index - 1) * 22)); row:SetPoint("TOPRIGHT", self.scrollContent, "TOPRIGHT", 0, -((index - 1) * 22))
        local classColor = RAID_CLASS_COLORS[member.classFileName] or NORMAL_FONT_COLOR
        local state, stateColor = "offline", { 0.55, 0.55, 0.55 }
        if member.online then
            state, stateColor = "online", { 0.25, 0.9, 0.25 }
            if member.status == "AFK" or member.status == 1 then state, stateColor = "afk", { 1, 0.82, 0.2 } end
            if member.status == "DND" or member.status == 2 then state, stateColor = "dnd", { 0.95, 0.2, 0.2 } end
        end
        local characterName = member.name and member.name:match("^([^-]+)") or L["UNKNOWN_VALUE"]
        local realm = member.name and member.name:match("%-([^%-]+)$") or L["UNKNOWN_VALUE"]
        row.indicator:SetTexture(statusTextures[state])
        local coords=CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[member.classFileName];if coords then row.classIcon:SetTexCoord(unpack(coords));row.classIcon:Show()else row.classIcon:Hide()end
        row.indicator:Show()
        row.twinkArrow:SetShown(member.isTwink)
        row.name:ClearAllPoints()
        row.name:SetPoint("LEFT", row, "LEFT", member.isTwink and 64 or 46, 0)
        row.name:SetPoint("RIGHT", row, "RIGHT", -500, 0)
        setColumnText(row.name, characterName, { classColor.r, classColor.g, classColor.b })
        setColumnText(row.rank, member.rank, { 1, 1, 1 }); setColumnText(row.level, member.level and tostring(member.level), { 1, 1, 1 })
        setColumnText(row.realm, realm, { 1, 1, 1 }); setColumnText(row.zone, member.zone, { 1, 1, 1 })
        setColumnText(row.status, member.online and L[string.upper(state)] or self:FormatOfflineDuration(member.status), stateColor)
        row:SetScript("OnMouseUp", function(_, button)
            if button == "RightButton" then GuildRoster:ShowGuildMemberMenu(row, member) elseif button == "LeftButton" then GuildRoster:ShowCharacter(member) end
        end)
        row:SetScript("OnEnter",function(frame)frame.highlight:Show();GameTooltip:SetOwner(frame,"ANCHOR_RIGHT");GameTooltip:AddLine(member.name or"-");GameTooltip:AddDoubleLine("Item level",string.format("%.1f",member.itemLevel or 0));GameTooltip:AddDoubleLine("Mythic+",string.format("%.1f",member.mythicScore or 0));GameTooltip:AddDoubleLine("Holy Storm",member.addonVersion or"not installed / unknown");GameTooltip:AddDoubleLine("Zone",member.online and(member.zone or"-")or GuildRoster:FormatOfflineDuration(member.status));GameTooltip:Show()end);row:SetScript("OnLeave",function(frame)frame.highlight:Hide();GameTooltip:Hide()end)
        row:Show()
    end
    self.scrollContent:SetHeight(math.max(1, #members * 22))
end
end)
