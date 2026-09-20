local addonVersion = "2.0.0"
local HolyStorm = LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local L = LibStub("AceLocale-3.0"):GetLocale("Holy_Storm_GuildEvents")
if HolyStorm.PermissionRegistry then HolyStorm.PermissionRegistry:RegisterLegacyAlias("calendar.read","calendar-read");HolyStorm.PermissionRegistry:RegisterLegacyAlias("calendar.manage","calendar-manage")end
local metadata = { id = "GuildEvents", name = "Calendar", internalName = "guildEvents", displayName = L["DISPLAY_NAME"], description = L["DESCRIPTION"], version = addonVersion, moduleType = "feature", category="feature", permissions = {{id="calendar-read",category="Calendar",defaults={member=true}}}, dependencies = { "core" }, ui = { page = "guildEvents", navigation = true }, enabledByDefault = false, ruleFields={
    {id="calendar.title",type="string",name=L["RULE_FIELD_TITLE"],nameKey="RULE_FIELD_TITLE",description=L["RULE_FIELD_TITLE_DESC"],descriptionKey="RULE_FIELD_TITLE_DESC",category=L["DISPLAY_NAME"],resolver=function(context)return context.target and context.target.calendarEvent and context.target.calendarEvent.title end},
    {id="calendar.description",type="string",name=L["RULE_FIELD_DESCRIPTION"],nameKey="RULE_FIELD_DESCRIPTION",description=L["RULE_FIELD_DESCRIPTION_DESC"],descriptionKey="RULE_FIELD_DESCRIPTION_DESC",category=L["DISPLAY_NAME"],resolver=function(context)return context.target and context.target.calendarEvent and context.target.calendarEvent.description end},
} }

HolyStorm:RegisterModule(metadata, function(Events)
    HolyStorm:ApplyModuleMetadata(Events, metadata)

    function Events:GetDatabase()
        return HolyStorm.Database:Get("guildEvents", "global")
    end

    local function GetEventTimestamp(event)
        return time({ year = event.year, month = event.month, day = event.monthDay, hour = event.hour, min = event.minute })
    end

    local UNKNOWN_STATUS = "UNKNOWN"
    local calendarStatusNames = { "Invited", "Available", "Declined", "Confirmed", "Out", "Standby", "Signedup", "NotSignedup", "Tentative" }

    -- Calendar invite fields can be Secret Values in restricted WoW 12.x states.
    -- Normalize while access is known to be legal; inaccessible values never leave
    -- this boundary and therefore cannot reach UI comparisons or persisted fingerprints.
    local function NormalizeCalendarStatus(status)
        local isSecretValue, canAccessValue = _G.issecretvalue, _G.canaccessvalue
        if type(isSecretValue) == "function" and isSecretValue(status) then
            if type(canAccessValue) ~= "function" or canAccessValue(status) ~= true then return UNKNOWN_STATUS end
        elseif type(canAccessValue) == "function" and canAccessValue(status) ~= true then
            return UNKNOWN_STATUS
        end
        if status == nil then return UNKNOWN_STATUS end
        local calendarStatus = _G.Enum and _G.Enum.CalendarStatus
        for _, name in ipairs(calendarStatusNames) do
            if status == (calendarStatus and calendarStatus[name]) or status == string.upper(name) then
                return string.upper(name)
            end
        end
        return UNKNOWN_STATUS
    end

    local function HasStatus(status, name)
        return NormalizeCalendarStatus(status) == string.upper(name)
    end

    local function IsSignedUp(invite)
        return invite and (HasStatus(invite.inviteStatus, "Confirmed") or HasStatus(invite.inviteStatus, "Signedup") or HasStatus(invite.inviteStatus, "Tentative") or HasStatus(invite.inviteStatus, "Standby") or HasStatus(invite.inviteStatus, "Declined") or HasStatus(invite.inviteStatus, "Out"))
    end

    local function IsActiveParticipant(invite)
        return invite and (HasStatus(invite.inviteStatus, "Confirmed") or HasStatus(invite.inviteStatus, "Signedup") or HasStatus(invite.inviteStatus, "Tentative") or HasStatus(invite.inviteStatus, "Standby"))
    end

    local function IsEventLocked(event, details)
        details = details or (event and event.details)
        return (event and event.isLocked) or (details and (details.isLocked or details.locked)) or false
    end

    local function GetStatusLabel(status)
        local normalized = NormalizeCalendarStatus(status)
        if normalized == "CONFIRMED" then return L["STATUS_CONFIRMED"] end
        if normalized == "SIGNEDUP" then return L["STATUS_SIGNEDUP"] end
        if normalized == "TENTATIVE" then return L["STATUS_TENTATIVE"] end
        if normalized == "STANDBY" then return L["STATUS_STANDBY"] end
        if normalized == "DECLINED" or normalized == "OUT" then return L["STATUS_NOT_ATTENDING"] end
        if normalized == UNKNOWN_STATUS then return L["STATUS_UNKNOWN"] end
        return "-"
    end

    local function GetStatusColor(status)
        local normalized = NormalizeCalendarStatus(status)
        if normalized == UNKNOWN_STATUS then return "|cffb3b3b3", 0.7, 0.7, 0.7 end
        if normalized == "CONFIRMED" or normalized == "SIGNEDUP" then return "|cff40ff40", 0.25, 1, 0.25 end
        if normalized == "TENTATIVE" or normalized == "STANDBY" then return "|cffffa619", 1, 0.65, 0.1 end
        return "|cffff4d4d", 1, 0.3, 0.3
    end

    function Events:NormalizeCalendarStatus(status) return NormalizeCalendarStatus(status) end
    function Events:HasStatus(status, name) return HasStatus(status, name) end
    function Events:IsSignedUp(invite) return IsSignedUp(invite) end
    function Events:IsActiveParticipant(invite) return IsActiveParticipant(invite) end
    function Events:GetStatusLabel(status) return GetStatusLabel(status) end

    local function GetShortDescription(event)
        local description = (event.description or L["NO_DESCRIPTION"]):gsub("[\r\n]+", " ")
        return #description > 100 and description:sub(1, 97) .. "..." or description
    end

    local roleCoords = { TANK = { 0, 19 / 64, 22 / 64, 41 / 64 }, HEALER = { 20 / 64, 39 / 64, 1 / 64, 20 / 64 }, DAMAGER = { 20 / 64, 39 / 64, 22 / 64, 41 / 64 } }

    function Events:BuildGuildMemberIndex()
        local members = {}
        for index = 1, GetNumGuildMembers() do
            local name, _, _, _, className, _, _, _, online, _, classFile, _, _, _, _, _, guid = GetGuildRosterInfo(index)
            if guid then members[guid] = { name = name, online = online, className = className, classFile = classFile } end
        end
        self.guildMembers = members
    end

    function Events:GetRole(invite)
        if invite.guid == UnitGUID("player") then
            local specialization = GetSpecialization and GetSpecialization()
            return specialization and GetSpecializationRole(specialization) or nil
        end
        local raidIndex = UnitInRaid and UnitInRaid(invite.name)
        if type(raidIndex) == "number" then return UnitGroupRolesAssigned("raid" .. raidIndex) end
        for partyIndex = 1, 4 do
            local name, realm = UnitName("party" .. partyIndex)
            if name and (name == invite.name or (realm and name .. "-" .. realm == invite.name)) then return UnitGroupRolesAssigned("party" .. partyIndex) end
        end
    end

    function Events:GetRaidProgress(invite, event)
        if not event.raidInfo or not invite.guid then return L["NO_RAID_PROGRESS"] end
        local raids = HolyStorm:GetModule("Raids", true)
        if not raids or not raids:IsEnabled() then return L["NO_RAID_PROGRESS"] end
        local data = raids:GetCharacterSnapshot(invite.guid); local best
        for _, lockout in ipairs(data and data.lockouts or {}) do
            if lockout.name == event.raidInfo.name then
                local killed = 0; for _, boss in ipairs(lockout.bosses or {}) do if boss.killed then killed = killed + 1 end end
                if not best or lockout.difficultyId > best.difficultyId or (lockout.difficultyId == best.difficultyId and killed > best.killed) then best = { difficultyId = lockout.difficultyId or 0, difficultyName = lockout.difficultyName or "", killed = killed, total = #(lockout.bosses or {}) } end
            end
        end
        return best and string.format(L["RAID_PROGRESS"], best.difficultyName, best.killed, best.total) or L["NO_RAID_PROGRESS"]
    end

    function Events:GetFingerprint(event)
        local attendees = {}
        for _, invite in ipairs(event.allInvites or {}) do
            table.insert(attendees, table.concat({ invite.name or "", NormalizeCalendarStatus(invite.inviteStatus), invite.classFilename or "" }, "\031"))
        end
        table.sort(attendees)
        return table.concat({ event.title or "", tostring(event.year), tostring(event.month), tostring(event.monthDay), tostring(event.hour), tostring(event.minute), event.description or "", table.concat(attendees, "\030") }, "\029")
    end

    function Events:UpdateNotification()
        local UI = HolyStorm:GetModule("UI", true); local entry = UI and UI.rightDockEntries and UI.rightDockEntries.guildEvents
        if not entry then return end
        if not self.notification then
            local badge = CreateFrame("Frame", nil, entry.slot, "BackdropTemplate")
            badge:SetSize(16, 16); badge:SetPoint("TOPRIGHT", entry.slot, "TOPRIGHT", 5, 5); badge:SetFrameLevel(entry.slot:GetFrameLevel() + 10)
            badge:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 8 })
            badge:SetBackdropColor(0.8, 0.08, 0.08, 1); badge:SetBackdropBorderColor(1, 0.82, 0.2, 1)
            local label = badge:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); label:SetPoint("CENTER"); label:SetText(L["NOTIFICATION_MARKER"])
            self.notification = badge
        end
        self.notification:SetShown(self:GetDatabase().unread)
    end

    function Events:StoreSnapshot(events)
        local database, current = self:GetDatabase(), {}
        for _, event in ipairs(events) do current[tostring(event.eventID or GetEventTimestamp(event))] = self:GetFingerprint(event) end
        if not database.snapshot then HolyStorm.Database:Set("guildEvents.snapshot", current, "global"); return false end
        local changed = false
        for id, fingerprint in pairs(current) do if database.snapshot[id] ~= fingerprint then changed = true; break end end
        if not changed then for id in pairs(database.snapshot) do if not current[id] then changed = true; break end end end
        HolyStorm.Database:Set("guildEvents.snapshot", current, "global")
        return changed
    end

    function Events:FinishRefresh(events)
        local changed = self:StoreSnapshot(events); local database = self:GetDatabase()
        local selectedEventId = self.detail:IsShown() and self.selectedEvent and self.selectedEvent.eventID
        if self.markReadAfterRefresh then HolyStorm.Database:Set("guildEvents.unread", false, "global") elseif changed then HolyStorm.Database:Set("guildEvents.unread", true, "global") end
        self.markReadAfterRefresh, self.isRefreshing = false, false
        self.events = events; self:SetLoading(false); self:UpdateNotification(); HolyStorm.Events:Emit("HS_CALENDAR_UPDATED", events, changed)
        if selectedEventId then
            for _, event in ipairs(events) do if event.eventID == selectedEventId then self:ShowDetails(event); break end end
        end
    end

    function Events:CanAutoRefresh()
        if InCombatLockdown and InCombatLockdown() then return false end
        if _G.CalendarFrame and _G.CalendarFrame:IsShown() then return false end
        return not (_G.C_Calendar and _G.C_Calendar.IsEventOpen and _G.C_Calendar.IsEventOpen())
    end

    function Events:QueueAutomaticRefresh(delay)
        if self.pendingRefresh or self.isRefreshing or not self:CanAutoRefresh() then return end
        self.pendingRefresh = true
        HolyStorm.Tasks:Enqueue("calendar.auto-refresh", function()
            self.pendingRefresh = false
            if self:IsEnabled() and self:CanAutoRefresh() then self:Refresh(false, true) end
        end, { priority=9, debounce=delay or 0, cooldown=1 })
    end

    function Events:SetLoading(visible, completed, total)
        local UI = HolyStorm:GetModule("UI", true)
        if not UI or not self.page:IsShown() then return end
        if not visible then UI:SetReadyStatus(); return end
        if total and total > 0 then
            UI:SetStatusText(string.format(L["LOADING_PROGRESS"], completed or 0, total))
        else
            UI:SetStatusText(L["LOADING"])
        end
    end

    function Events:GetCard(index)
        local card = self.cards[index]
        if card then return card end
        card = CreateFrame("Button", nil, self.content, "BackdropTemplate")
        card:SetBackdrop({ bgFile = "Interface\\FrameGeneral\\UI-Background-Rock", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 12, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
        card:SetBackdropColor(0.04, 0.05, 0.06, 0.94); card:SetBackdropBorderColor(0.42, 0.42, 0.42, 1)
        card:SetScript("OnClick", function(button) Events:ShowDetails(button.event) end)
        card:SetScript("OnEnter", function(button) button:SetBackdropBorderColor(1, 0.82, 0, 0.9) end)
        card:SetScript("OnLeave", function(button) button:SetBackdropBorderColor(0.42, 0.42, 0.42, 1) end)
        card.iconFrame = CreateFrame("Frame", nil, card, "BackdropTemplate"); card.iconFrame:SetSize(64, 64); card.iconFrame:SetPoint("TOPLEFT", card, "TOPLEFT", 14, -14); card.iconFrame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 10 }); card.iconFrame:SetBackdropColor(0, 0, 0, 0.85); card.iconFrame:SetBackdropBorderColor(0.65, 0.65, 0.65, 1)
        card.icon = card.iconFrame:CreateTexture(nil, "ARTWORK"); card.icon:SetPoint("TOPLEFT", card.iconFrame, "TOPLEFT", 5, -5); card.icon:SetPoint("BOTTOMRIGHT", card.iconFrame, "BOTTOMRIGHT", -5, 5); card.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        card.title = card:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); card.title:SetPoint("TOPLEFT", card.iconFrame, "TOPRIGHT", 12, 0); card.title:SetPoint("TOPRIGHT", card, "TOPRIGHT", -12, 0); card.title:SetJustifyH("LEFT"); card.title:SetTextColor(1, 0.82, 0)
        card.description = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); card.description:SetPoint("TOPLEFT", card.title, "BOTTOMLEFT", 0, -8); card.description:SetPoint("TOPRIGHT", card, "TOPRIGHT", -12, 0); card.description:SetJustifyH("LEFT"); card.description:SetJustifyV("TOP")
        card.dateIcon = card:CreateTexture(nil, "OVERLAY"); card.dateIcon:SetSize(16, 16); card.dateIcon:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 14, 11); card.dateIcon:SetTexture("Interface\\Calendar\\UI-Calendar-Event-PVP")
        card.date = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); card.date:SetPoint("LEFT", card.dateIcon, "RIGHT", 5, 0); card.date:SetTextColor(0.25, 0.78, 0.92); card.date:SetJustifyH("LEFT")
        card.timeIcon = card:CreateTexture(nil, "OVERLAY"); card.timeIcon:SetSize(16, 16); card.timeIcon:SetPoint("BOTTOM", card, "BOTTOM", -42, 11); card.timeIcon:SetTexture("Interface\\Icons\\INV_Misc_PocketWatch_01")
        card.time = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); card.time:SetPoint("LEFT", card.timeIcon, "RIGHT", 5, 0); card.time:SetTextColor(0.25, 0.78, 0.92); card.time:SetJustifyH("LEFT")
        card.players = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); card.players:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -14, 12); card.players:SetTextColor(0.72, 0.72, 0.72); card.players:SetJustifyH("RIGHT")
        card.playersIcon = card:CreateTexture(nil, "OVERLAY"); card.playersIcon:SetSize(16, 16); card.playersIcon:SetPoint("RIGHT", card.players, "LEFT", -5, 0); card.playersIcon:SetTexture("Interface\\FriendsFrame\\UI-Toast-FriendOnlineIcon")
        self.cards[index] = card
        return card
    end

    function Events:Render()
        if not self.page or not self.page:IsShown() or self.detail:IsShown() then return end
        local events, width = {}, self.scroll:GetWidth();for _,event in ipairs(self.events)do if not self.filterBar or self.filterBar:Matches({calendarEvent=event})then events[#events+1]=event end end; local columns = width >= 620 and 2 or 1
        local cardWidth = math.max(1, (width - 36 - ((columns - 1) * 12)) / columns)
        for index, event in ipairs(events) do
            local card = self:GetCard(index); local column = (index - 1) % columns; local row = math.floor((index - 1) / columns)
            card:ClearAllPoints(); card:SetSize(cardWidth, 124); card:SetPoint("TOPLEFT", self.content, "TOPLEFT", 12 + column * (cardWidth + 12), -12 - row * 136)
            card.event = event; card.icon:SetTexture(event.texture or "Interface\\Icons\\INV_Misc_Note_05"); card.title:SetText(event.title or L["UNTITLED"])
            local timestamp = GetEventTimestamp(event)
            card.date:SetText(date("%a, %d.%m.%Y", timestamp)); card.time:SetText(date("%H:%M", timestamp)); card.players:SetText(string.format(L["SIGNUPS"], event.signupCount or 0)); card.description:SetText(GetShortDescription(event)); card:Show()
        end
        for index = #events + 1, #self.cards do self.cards[index]:Hide() end
        self.empty:SetShown(#events == 0); if #events == 0 then self.empty:SetText(L["EMPTY"]) end
        self.content:SetHeight(math.max(self.scroll:GetHeight(), math.ceil(#events / columns) * 136 + 12))
    end

    local function CreatePlayerActionButton(parent, iconPath, tooltip)
        local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
        button:SetSize(24, 24); button:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 8 }); button:SetBackdropColor(0.05, 0.05, 0.05, 0.9); button:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
        button.icon = button:CreateTexture(nil, "ARTWORK"); button.icon:SetPoint("TOPLEFT", button, "TOPLEFT", 3, -3); button.icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -3, 3); button.icon:SetTexture(iconPath)
        button:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(1, 0.82, 0, 1); GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText(tooltip); GameTooltip:Show() end)
        button:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(0.5, 0.5, 0.5, 1); GameTooltip:Hide() end)
        return button
    end

    function Events:CreatePlayerRow(index)
        local row = self.playerRows[index]
        if row then return row end
        row = CreateFrame("Frame", nil, self.playerPanel)
        row.online = row:CreateTexture(nil, "OVERLAY"); row.online:SetSize(14, 14); row.online:SetPoint("LEFT", row, "LEFT", 0, 0)
        row.classIcon = row:CreateTexture(nil, "OVERLAY"); row.classIcon:SetSize(18, 18); row.classIcon:SetPoint("LEFT", row.online, "RIGHT", 6, 0); row.classIcon:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
        row.roleIcon = row:CreateTexture(nil, "OVERLAY"); row.roleIcon:SetSize(18, 18); row.roleIcon:SetPoint("LEFT", row.classIcon, "RIGHT", 5, 0); row.roleIcon:SetTexture("Interface\\LFGFrame\\UI-LFG-ICON-ROLES")
        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); row.name:SetPoint("LEFT", row.roleIcon, "RIGHT", 8, 0); row.name:SetWidth(235); row.name:SetJustifyH("LEFT")
        row.raid = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); row.raid:SetPoint("LEFT", row.name, "RIGHT", 12, 0); row.raid:SetWidth(220); row.raid:SetJustifyH("LEFT")
        row.status = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); row.status:SetPoint("RIGHT", row, "RIGHT", 0, 0); row.status:SetJustifyH("RIGHT")
        row.confirm = CreatePlayerActionButton(row, "Interface\\RaidFrame\\ReadyCheck-Ready", L["PLAYER_CONFIRM"]); row.confirm:SetPoint("RIGHT", row, "RIGHT", -56, 0)
        row.standby = CreatePlayerActionButton(row, "Interface\\Icons\\INV_Misc_PocketWatch_01", L["PLAYER_STANDBY"]); row.standby:SetPoint("RIGHT", row, "RIGHT", -28, 0)
        row.decline = CreatePlayerActionButton(row, "Interface\\RaidFrame\\ReadyCheck-NotReady", L["PLAYER_DECLINE"]); row.decline:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        self.playerRows[index] = row
        return row
    end

    function Events:RenderAceDetails(event)
        local aceGUI, layout = self.aceGUI, self.detailLayout
        if not aceGUI or not layout then return end
        self.infoPanel:Hide(); self.playerPanel:Hide(); layout.frame:Show(); layout:ReleaseChildren(); self.responseButtons = {}

        local function Label(text, width, color, image, imageSize)
            local label = aceGUI:Create("Label"); label:SetText(text or "")
            if width == "full" then label:SetFullWidth(true) elseif width then label:SetRelativeWidth(width) end
            if color then label:SetColor(unpack(color)) end
            if image then label:SetImage(image); label:SetImageSize(imageSize or 16, imageSize or 16) end
            return label
        end
        local function Icon(path, size, tooltip, callback, disabled, ...)
            local icon = aceGUI:Create("Icon"); icon:SetImage(path, ...); icon:SetImageSize(size, size); icon:SetWidth(size + 8); icon:SetHeight(size + 8)
            if tooltip then icon:SetCallback("OnEnter", function(widget) GameTooltip:SetOwner(widget.frame, "ANCHOR_TOP"); GameTooltip:SetText(tooltip); GameTooltip:Show() end); icon:SetCallback("OnLeave", function() GameTooltip:Hide() end) end
            if callback then icon:SetCallback("OnClick", callback) end
            icon:SetDisabled(disabled and true or false)
            return icon
        end

        local left = aceGUI:Create("InlineGroup"); left:SetTitle(""); left:SetRelativeWidth(0.49); left:SetLayout("List"); layout:AddChild(left)
        local right = aceGUI:Create("InlineGroup"); right:SetTitle(string.format(L["PLAYERS"], #event.invites)); right:SetRelativeWidth(0.49); right:SetLayout("List"); layout:AddChild(right)

        local header = aceGUI:Create("SimpleGroup"); header:SetFullWidth(true); header:SetLayout("Flow"); left:AddChild(header)
        header:AddChild(Icon(event.texture or "Interface\\Icons\\INV_Misc_Note_05", 64, nil, nil, false))
        local headerText = aceGUI:Create("SimpleGroup"); headerText:SetRelativeWidth(0.82); headerText:SetLayout("List"); header:AddChild(headerText)
        headerText:AddChild(Label("|cffffd100" .. (event.title or L["UNTITLED"]) .. "|r", "full"))
        local timestamp = GetEventTimestamp(event)
        headerText:AddChild(Label(date("%a, %d.%m.%Y", timestamp), "full", { 0.25, 0.78, 0.92 }, "Interface\\Calendar\\UI-Calendar-Event-PVP"))
        headerText:AddChild(Label(date("%H:%M", timestamp), "full", { 0.25, 0.78, 0.92 }, "Interface\\Icons\\INV_Misc_PocketWatch_01"))
        left:AddChild(Label(event.description or L["NO_DESCRIPTION"], "full"))

        local response = aceGUI:Create("SimpleGroup"); response:SetFullWidth(true); response:SetLayout("Flow"); left:AddChild(response)
        response:AddChild(Label(L["RESPONSE_HEADING"], "full"))
        local details, inviteType = event.details or {}, _G.Enum and _G.Enum.CalendarInviteType
        local enabled = not IsEventLocked(event, details) and not self.responsePending
        for _, action in ipairs({ "signup", "tentative" }) do
            local button = aceGUI:Create("Button"); button:SetWidth(118); button:SetText(L["RESPONSE_" .. string.upper(action)]); button.action = action; button:SetDisabled(not enabled)
            button:SetCallback("OnClick", function() Events:Respond(Events.selectedEvent, action) end); response:AddChild(button); table.insert(self.responseButtons, button)
        end

        if #event.invites == 0 then right:AddChild(Label(L["NO_PLAYERS"], "full")); return end
        self:BuildGuildMemberIndex()
        for _, invite in ipairs(event.invites) do
            local member = invite.guid and self.guildMembers[invite.guid] or nil; local record = invite.guid and HolyStorm.Data.CharacterStore:Get(invite.guid) or nil
            local classFile = invite.classFilename or (member and member.classFile) or (record and record.classFile); local color = classFile and RAID_CLASS_COLORS[classFile]
            local row = aceGUI:Create("SimpleGroup"); row:SetFullWidth(true); row:SetLayout("Flow"); right:AddChild(row)
            row:AddChild(Icon(member and member.online and "Interface\\FriendsFrame\\StatusIcon-Online" or "Interface\\FriendsFrame\\StatusIcon-Offline", 14))
            local coords = classFile and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classFile]
            if coords then row:AddChild(Icon("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES", 18, nil, nil, false, unpack(coords))) end
            local role = roleCoords[self:GetRole(invite)]
            if role then row:AddChild(Icon("Interface\\LFGFrame\\UI-LFG-ICON-ROLES", 18, nil, nil, false, unpack(role))) end
            local name = invite.name or (member and member.name) or L["UNKNOWN_PLAYER"]; local nameColor = color and string.format("|cff%02x%02x%02x", math.floor(color.r * 255), math.floor(color.g * 255), math.floor(color.b * 255)) or "|cffffffff"
            row:AddChild(Label(nameColor .. name .. "|r", 0.29))
            row:AddChild(Label(self:GetRaidProgress(invite, event), 0.19))
            local statusColor = GetStatusColor(invite.inviteStatus)
            row:AddChild(Label(statusColor .. GetStatusLabel(invite.inviteStatus) .. "|r", 0.18))
            if event.canEdit then
                local canManage = not IsEventLocked(event)
                row:AddChild(Icon("Interface\\RaidFrame\\ReadyCheck-Ready", 20, L["PLAYER_CONFIRM"], function() Events:SetPlayerStatus(event, invite, "Confirmed") end, not canManage))
                row:AddChild(Icon("Interface\\Icons\\INV_Misc_PocketWatch_01", 20, L["PLAYER_STANDBY"], function() Events:SetPlayerStatus(event, invite, "Standby") end, not canManage))
                row:AddChild(Icon("Interface\\RaidFrame\\ReadyCheck-NotReady", 20, L["PLAYER_DECLINE"], function() Events:SetPlayerStatus(event, invite, "Declined") end, not canManage))
            end
        end
    end

    function Events:ShowDetails(event)
        if not event then return end
        self.scroll:Hide(); self.heading:Hide();if self.filterBar then self.filterBar:Hide()end; self.detail:Show()
        if self.detailLayout then self.selectedEvent = event; self:RenderAceDetails(event); return end
        self.detailIcon:SetTexture(event.texture or "Interface\\Icons\\INV_Misc_Note_05"); self.detailTitle:SetText(event.title or L["UNTITLED"])
        local timestamp = GetEventTimestamp(event)
        self.detailDate:SetText(date("%a, %d.%m.%Y", timestamp)); self.detailTime:SetText(date("%H:%M", timestamp)); self.detailDescription:SetText(event.description or L["NO_DESCRIPTION"])
        self.selectedEvent = event; self:UpdateResponseButtons(event)
        self.playerHeading:SetText(string.format(L["PLAYERS"], #event.invites))
        self:BuildGuildMemberIndex()
        for index, invite in ipairs(event.invites) do
            local row = self:CreatePlayerRow(index); row:ClearAllPoints(); row:SetHeight(22); row:SetPoint("TOPLEFT", self.playerHeading, "BOTTOMLEFT", 0, -10 - ((index - 1) * 22)); row:SetPoint("RIGHT", self.playerPanel, "RIGHT", -16, 0)
            local member = invite.guid and self.guildMembers[invite.guid] or nil; local record = invite.guid and HolyStorm.Data.CharacterStore:Get(invite.guid) or nil
            local classFile = invite.classFilename or (member and member.classFile) or (record and record.classFile); local color = classFile and RAID_CLASS_COLORS[classFile]
            row.name:SetText(invite.name or (member and member.name) or L["UNKNOWN_PLAYER"]); if color then row.name:SetTextColor(color.r, color.g, color.b) else row.name:SetTextColor(1, 1, 1) end
            row.online:SetTexture(member and member.online and "Interface\\FriendsFrame\\StatusIcon-Online" or "Interface\\FriendsFrame\\StatusIcon-Offline")
            local classCoords = classFile and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classFile]; if classCoords then row.classIcon:SetTexCoord(unpack(classCoords)); row.classIcon:Show() else row.classIcon:Hide() end
            local roleCoordsForPlayer = roleCoords[self:GetRole(invite)]; if roleCoordsForPlayer then row.roleIcon:SetTexCoord(unpack(roleCoordsForPlayer)); row.roleIcon:Show() else row.roleIcon:Hide() end
            local _, statusR, statusG, statusB = GetStatusColor(invite.inviteStatus)
            row.raid:SetText(self:GetRaidProgress(invite, event)); row.status:SetText(GetStatusLabel(invite.inviteStatus)); row.status:SetTextColor(statusR, statusG, statusB)
            local canManage = event.canEdit and not IsEventLocked(event)
            row.status:ClearAllPoints(); row.status:SetPoint("RIGHT", row, "RIGHT", event.canEdit and -92 or 0, 0)
            row.confirm:SetShown(event.canEdit); row.standby:SetShown(event.canEdit); row.decline:SetShown(event.canEdit)
            if canManage then row.confirm:Enable(); row.standby:Enable(); row.decline:Enable() else row.confirm:Disable(); row.standby:Disable(); row.decline:Disable() end
            for _, button in ipairs({ row.confirm, row.standby, row.decline }) do button.icon:SetDesaturated(not canManage); button.icon:SetAlpha(canManage and 1 or 0.35) end
            row.confirm:SetScript("OnClick", function() Events:SetPlayerStatus(event, invite, "Confirmed") end); row.standby:SetScript("OnClick", function() Events:SetPlayerStatus(event, invite, "Standby") end); row.decline:SetScript("OnClick", function() Events:SetPlayerStatus(event, invite, "Declined") end); row:Show()
        end
        for index = #event.invites + 1, #self.playerRows do self.playerRows[index]:Hide() end
        self.noPlayers:SetShown(#event.invites == 0)
    end

    function Events:UpdateResponseButtons(event)
        local details, inviteType = event.details or {}, _G.Enum and _G.Enum.CalendarInviteType
        local isSignup = inviteType and details.inviteType == inviteType.Signup
        local enabled = not IsEventLocked(event, details) and not self.responsePending
        for _, button in ipairs(self.responseButtons) do
            local shown = button.action ~= "remove" or isSignup
            if button.SetDisabled then button.frame:SetShown(shown); button:SetDisabled(not enabled) else button:SetShown(shown); if enabled then button:Enable() else button:Disable() end end
        end
    end

    function Events:Respond(event, action)
        if not event or self.responsePending or IsEventLocked(event) or InCombatLockdown() then return end
        local calendar, selection = _G.C_Calendar, event.selection
        if not calendar or not selection or not calendar.OpenEvent or not calendar.OpenEvent(selection.offsetMonths, selection.monthDay, selection.eventIndex) then return end
        self.responsePending = true; self:UpdateResponseButtons(event)
        HolyStorm.Tasks:Enqueue("calendar.respond", function()
            local liveDetails = calendar.GetEventInfo and calendar.GetEventInfo()
            if IsEventLocked(event, liveDetails) then
                event.details, event.isLocked, Events.responsePending = liveDetails, true, false
                if calendar.CloseEvent then calendar.CloseEvent() end
                Events:ShowDetails(event)
                return
            end
            if action == "signup" then
                local ownInviteIndex
                for inviteIndex = 1, calendar.GetNumInvites and calendar.GetNumInvites() or 0 do
                    local invite = calendar.EventGetInvite(inviteIndex)
                    if invite and (invite.inviteIsMine or invite.guid == UnitGUID("player")) then ownInviteIndex = inviteIndex; break end
                end
                local statuses = _G.Enum and _G.Enum.CalendarStatus
                if ownInviteIndex and statuses and calendar.EventCanEdit and calendar.EventCanEdit() and calendar.EventSetInviteStatus then
                    calendar.EventSetInviteStatus(ownInviteIndex, statuses.Confirmed)
                else
                    local inviteType = _G.Enum and _G.Enum.CalendarInviteType
                    if inviteType and event.details and event.details.inviteType == inviteType.Signup then calendar.EventSignUp() else calendar.EventAvailable() end
                end
            elseif action == "tentative" then
                calendar.EventTentative()
            end
            Events:FinishCalendarAction(calendar, 1)
        end, { priority=0, debounce=0.25, combat="defer" })
    end

    function Events:FinishCalendarAction(calendar, attempt)
        if calendar.IsActionPending and calendar.IsActionPending() and attempt < 20 then
            HolyStorm.Tasks:Enqueue("calendar.finish.pending", function() Events:FinishCalendarAction(calendar, attempt + 1) end, { priority=0, debounce=0.2, combat="defer" }); return
        end
        HolyStorm.Tasks:Enqueue("calendar.finish.close", function()
            if calendar.CloseEvent then calendar.CloseEvent() end
            Events.responsePending = false; Events:Refresh(true)
        end, { priority=0, debounce=0.3, combat="defer" })
    end

    function Events:SetPlayerStatus(event, invite, statusName)
        if not event or self.responsePending or not event.canEdit or IsEventLocked(event) or InCombatLockdown() then return end
        local calendar, selection, statuses = _G.C_Calendar, event.selection, _G.Enum and _G.Enum.CalendarStatus
        if not calendar or not selection or not statuses or not calendar.OpenEvent or not calendar.OpenEvent(selection.offsetMonths, selection.monthDay, selection.eventIndex) then return end
        self.responsePending = true; self:UpdateResponseButtons(event)
        HolyStorm.Tasks:Enqueue("calendar.set-status", function()
            local liveDetails = calendar.GetEventInfo and calendar.GetEventInfo()
            if IsEventLocked(event, liveDetails) then
                event.details, event.isLocked, Events.responsePending = liveDetails, true, false
                if calendar.CloseEvent then calendar.CloseEvent() end
                Events:ShowDetails(event)
                return
            end
            local targetStatus = statuses[statusName]
            local inviteType = _G.Enum and _G.Enum.CalendarInviteType
            if statusName == "Declined" and inviteType and event.details and event.details.inviteType == inviteType.Signup then targetStatus = statuses.Out end
            if calendar.EventGetStatusOptions and invite.index then
                local available = {}; for _, option in ipairs(calendar.EventGetStatusOptions(invite.index)) do available[option.status] = true end
                if not available[targetStatus] then targetStatus = available[statuses.Declined] and statuses.Declined or (available[statuses.Out] and statuses.Out) end
            end
            if calendar.EventSetInviteStatus and calendar.EventCanEdit and calendar.EventCanEdit() and invite.index and targetStatus then calendar.EventSetInviteStatus(invite.index, targetStatus) end
            Events:FinishCalendarAction(calendar, 1)
        end, { priority=0, debounce=0.25, combat="defer" })
    end

    function Events:ShowList()
        if self.detailLayout then self.detailLayout.frame:Hide() end
        self.detail:Hide(); self.heading:Show();if self.filterBar then self.filterBar:Show()end; self.scroll:Show(); self:Render()
    end

    function Events:LoadEventDetails(events, index)
        if index > #events then self:FinishRefresh(events); return end
        self:SetLoading(true, index - 1, #events)
        local event, calendar = events[index], _G.C_Calendar
        event.invites, event.allInvites, event.signupCount = {}, {}, 0
        local selection = event.selection
        if not selection or not calendar.OpenEvent or not calendar.OpenEvent(selection.offsetMonths, selection.monthDay, selection.eventIndex) then
            self:LoadEventDetails(events, index + 1); return
        end
        local function CollectDetails(attempt)
            if not Events:IsEnabled() then return end
            if calendar.AreNamesReady and not calendar.AreNamesReady() and attempt < 10 then
                HolyStorm.Tasks:Enqueue("calendar.names-ready", function() CollectDetails(attempt + 1) end, { priority=2, debounce=0.2, combat="defer" }); return
            end
            local details = calendar.GetEventInfo and calendar.GetEventInfo(); event.details = details; event.isLocked = details and (details.isLocked or details.locked) or false; event.canEdit = (HolyStorm.PermissionEngine or HolyStorm.Policy):Can("calendar-manage") and calendar.EventCanEdit and calendar.EventCanEdit() or false; event.description = details and details.description or nil
            event.raidInfo = calendar.GetRaidInfo and calendar.GetRaidInfo(selection.offsetMonths, selection.monthDay, selection.eventIndex) or nil
            if calendar.GetNumInvites and calendar.EventGetInvite then
                for inviteIndex = 1, calendar.GetNumInvites() do
                    local invite = calendar.EventGetInvite(inviteIndex)
                    if invite then
                        local entry = { index = inviteIndex, name = invite.name, level = invite.level, className = invite.className, classFilename = invite.classFilename, inviteStatus = NormalizeCalendarStatus(invite.inviteStatus), inviteIsMine = invite.inviteIsMine, guid = invite.guid }
                        table.insert(event.allInvites, entry)
                        if IsActiveParticipant(entry) then event.signupCount = event.signupCount + 1 end
                        if IsSignedUp(entry) or entry.inviteStatus == UNKNOWN_STATUS then table.insert(event.invites, entry) end
                    end
                end
            end
            if calendar.CloseEvent then calendar.CloseEvent() end
            Events:LoadEventDetails(events, index + 1)
        end
        HolyStorm.Tasks:Enqueue("calendar.collect-details", function() CollectDetails(1) end, { priority=2, debounce=0.2, combat="defer" })
    end

    function Events:Refresh(markRead, automatic)
        if not self.page then return end
        if self.isRefreshing then return end
        if automatic and not self:CanAutoRefresh() then return end
        self.isRefreshing, self.markReadAfterRefresh = true, markRead or false
        self:SetLoading(true)
        if not automatic and self.page:IsShown() and not self.detail:IsShown() then self:ShowList() end
        local calendar = _G.C_Calendar
        if not calendar or not calendar.OpenCalendar then self.isRefreshing = false; self:SetLoading(false); return end
        calendar.OpenCalendar()
        HolyStorm.Tasks:Enqueue("calendar.open", function()
            if not Events:IsEnabled() or not calendar.GetNumGuildEvents or not calendar.GetGuildEventInfo then Events.isRefreshing = false; Events:SetLoading(false); return end
            local events = {}
            for index = 1, calendar.GetNumGuildEvents() do
                local event = calendar.GetGuildEventInfo(index)
                if event then event.selection = calendar.GetGuildEventSelectionInfo and calendar.GetGuildEventSelectionInfo(index); table.insert(events, event) end
            end
            table.sort(events, function(left, right) return GetEventTimestamp(left) < GetEventTimestamp(right) end)
            Events:LoadEventDetails(events, 1)
        end, { priority=3, debounce=1, combat="defer" })
    end

    function Events:InitializeUI()
        local UI = HolyStorm:GetModule("UI", true); local aceGUI = LibStub("AceGUI-3.0"); local page = CreateFrame("Frame", nil, UI.content)
        local heading = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge"); heading:SetPoint("TOPLEFT", page, "TOPLEFT", 18, -18); heading:SetText(L["HEADING"])
        local filterBar=HolyStorm.PolicyUI:CreateFilterBar(page,"calendar",function()Events:Render()end);filterBar:SetPoint("TOPLEFT",14,-42);filterBar:SetPoint("TOPRIGHT",-20,-42)
        local scroll = CreateFrame("ScrollFrame", nil, page, "UIPanelScrollFrameTemplate"); scroll:SetPoint("TOPLEFT", page, "TOPLEFT", 18, -98); scroll:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -28, 16)
        local content = CreateFrame("Frame", nil, scroll); content:SetSize(1, 1); scroll:SetScrollChild(content)
        local empty = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); empty:SetPoint("TOPLEFT", content, "TOPLEFT", 12, -12); empty:SetJustifyH("LEFT")
        local detail = CreateFrame("Frame", nil, page); detail:SetPoint("TOPLEFT", page, "TOPLEFT", 18, -52); detail:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -28, 16); detail:Hide()
        local back = CreateFrame("Button", nil, detail, "BackdropTemplate"); back:SetSize(28, 28); back:SetPoint("TOPLEFT", page, "TOPLEFT", 20, -16); back:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 8 }); back:SetBackdropColor(0.06, 0.06, 0.06, 0.9); back:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
        local backIcon = back:CreateTexture(nil, "ARTWORK"); backIcon:SetPoint("TOPLEFT", back, "TOPLEFT", 4, -4); backIcon:SetPoint("BOTTOMRIGHT", back, "BOTTOMRIGHT", -4, 4); backIcon:SetTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up")
        back:SetScript("OnClick", function() Events:ShowList() end); back:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(1, 0.82, 0, 1); GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText(L["BACK"]); GameTooltip:Show() end); back:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(0.5, 0.5, 0.5, 1); GameTooltip:Hide() end)
        local infoPanel = CreateFrame("Frame", nil, detail, "BackdropTemplate"); infoPanel:SetPoint("TOPLEFT", detail, "TOPLEFT", 0, 0); infoPanel:SetPoint("BOTTOMRIGHT", detail, "CENTER", -10, 0); infoPanel:SetBackdrop({ bgFile = "Interface\\FrameGeneral\\UI-Background-Rock", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 12, insets = { left = 4, right = 4, top = 4, bottom = 4 } }); infoPanel:SetBackdropColor(0.04, 0.05, 0.06, 0.82); infoPanel:SetBackdropBorderColor(0.42, 0.42, 0.42, 1)
        local playerPanel = CreateFrame("Frame", nil, detail, "BackdropTemplate"); playerPanel:SetPoint("TOPLEFT", detail, "CENTER", 10, 0); playerPanel:SetPoint("BOTTOMRIGHT", detail, "BOTTOMRIGHT", 0, 0); playerPanel:SetBackdrop({ bgFile = "Interface\\FrameGeneral\\UI-Background-Rock", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 12, insets = { left = 4, right = 4, top = 4, bottom = 4 } }); playerPanel:SetBackdropColor(0.04, 0.05, 0.06, 0.82); playerPanel:SetBackdropBorderColor(0.42, 0.42, 0.42, 1)
        local detailIcon = infoPanel:CreateTexture(nil, "ARTWORK"); detailIcon:SetSize(64, 64); detailIcon:SetPoint("TOPLEFT", infoPanel, "TOPLEFT", 18, -18); detailIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        local detailTitle = infoPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge"); detailTitle:SetPoint("TOPLEFT", detailIcon, "TOPRIGHT", 14, 2); detailTitle:SetPoint("TOPRIGHT", infoPanel, "TOPRIGHT", -16, 2); detailTitle:SetJustifyH("LEFT"); detailTitle:SetTextColor(1, 0.82, 0)
        local detailDateIcon = infoPanel:CreateTexture(nil, "OVERLAY"); detailDateIcon:SetSize(16, 16); detailDateIcon:SetPoint("TOPLEFT", detailTitle, "BOTTOMLEFT", 0, -7); detailDateIcon:SetTexture("Interface\\Calendar\\UI-Calendar-Event-PVP")
        local detailDate = infoPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); detailDate:SetPoint("LEFT", detailDateIcon, "RIGHT", 6, 0); detailDate:SetTextColor(0.25, 0.78, 0.92)
        local detailTimeIcon = infoPanel:CreateTexture(nil, "OVERLAY"); detailTimeIcon:SetSize(16, 16); detailTimeIcon:SetPoint("TOPLEFT", detailDateIcon, "BOTTOMLEFT", 0, -5); detailTimeIcon:SetTexture("Interface\\Icons\\INV_Misc_PocketWatch_01")
        local detailTime = infoPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); detailTime:SetPoint("LEFT", detailTimeIcon, "RIGHT", 6, 0); detailTime:SetTextColor(0.25, 0.78, 0.92)
        local detailDescription = infoPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); detailDescription:SetPoint("TOPLEFT", detailIcon, "BOTTOMLEFT", 0, -24); detailDescription:SetPoint("TOPRIGHT", infoPanel, "TOPRIGHT", -18, -106); detailDescription:SetHeight(108); detailDescription:SetJustifyH("LEFT"); detailDescription:SetJustifyV("TOP")
        local responseHeading = infoPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); responseHeading:SetPoint("TOPLEFT", detailDescription, "BOTTOMLEFT", 0, -14); responseHeading:SetText(L["RESPONSE_HEADING"])
        local responseButtons = {}; local responseActions = { "signup", "tentative" }
        for index, action in ipairs(responseActions) do
            local responseAction = action
            local button = CreateFrame("Button", nil, infoPanel, "UIPanelButtonTemplate"); button:SetSize(118, 24); button:SetPoint("TOPLEFT", responseHeading, "BOTTOMLEFT", (index - 1) * 124, -8); button:SetText(L["RESPONSE_" .. string.upper(responseAction)]); button.action = responseAction
            button:SetScript("OnClick", function() Events:Respond(Events.selectedEvent, responseAction) end); responseButtons[index] = button
        end
        local playerHeading = playerPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); playerHeading:SetPoint("TOPLEFT", playerPanel, "TOPLEFT", 18, -18)
        local noPlayers = playerPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); noPlayers:SetPoint("TOPLEFT", playerHeading, "BOTTOMLEFT", 0, -10); noPlayers:SetText(L["NO_PLAYERS"])
        local detailLayout = aceGUI:Create("SimpleGroup"); detailLayout.frame:SetParent(detail); detailLayout.frame:SetAllPoints(detail); detailLayout.frame:SetFrameLevel(detail:GetFrameLevel() + 5); detailLayout:SetLayout("Flow"); detailLayout.frame:Hide()
        self.page, self.heading, self.filterBar, self.scroll, self.content, self.empty, self.detail, self.detailIcon, self.detailTitle, self.detailDate, self.detailTime, self.detailDescription, self.infoPanel, self.playerPanel, self.playerHeading, self.noPlayers, self.responseButtons, self.cards, self.playerRows, self.events, self.aceGUI, self.detailLayout = page, heading, filterBar, scroll, content, empty, detail, detailIcon, detailTitle, detailDate, detailTime, detailDescription, infoPanel, playerPanel, playerHeading, noPlayers, responseButtons, {}, {}, {}, aceGUI, detailLayout
        content:SetWidth(scroll:GetWidth()); scroll:SetScript("OnSizeChanged", function(frame) content:SetWidth(frame:GetWidth()); Events:Render() end)
        HolyStorm.UI:RegisterPage("guildEvents", page, L["WINDOW_TITLE"], function() Events:Render() end, { "HS_CALENDAR_UPDATED" })
        HolyStorm.UI:AddNavigation("guildEvents", 6, "Interface\\Icons\\INV_Misc_Note_05", L["DISPLAY_NAME"], L["DESCRIPTION"], function() Events:QueueAutomaticRefresh(0); HolyStorm.UI:ShowPage("guildEvents") end)
        local function onCalendarEvent(event)
            if event == "PLAYER_LOGIN" or (event == "PLAYER_ENTERING_WORLD" and not Events.loginCheckQueued) then
                Events.loginCheckQueued = true; Events:QueueAutomaticRefresh(5); return
            end
            if event == "CALENDAR_UPDATE_GUILD_EVENTS" then Events:QueueAutomaticRefresh(2) end
        end
        HolyStorm.Events:Register("CALENDAR_UPDATE_GUILD_EVENTS","calendar",onCalendarEvent); HolyStorm.Events:Register("PLAYER_LOGIN","calendar",onCalendarEvent); HolyStorm.Events:Register("PLAYER_ENTERING_WORLD","calendar",onCalendarEvent)
        HolyStorm.Tasks:ScheduleRecurring("calendar.periodic",300,function() if Events:IsEnabled() then Events:QueueAutomaticRefresh() end end,{priority=10,cooldown=300})
        self:UpdateNotification()
    end
    function Events:OnInitialize()
        if type(HolyStorm.Database:Get("guildEvents","global"))~="table"then HolyStorm.Database:Set("guildEvents",{unread=false},"global")end
        HolyStorm:RegisterUIExtension("GuildEvents",{id="calendar.page",order=6,initialize=function()Events:InitializeUI()end})
    end
    function Events:OnDisable() HolyStorm.Events:UnregisterOwner("calendar"); HolyStorm.Tasks:Cancel("calendar.auto-refresh"); HolyStorm.Tasks:CancelRecurring("calendar.periodic") end
end)
