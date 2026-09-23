local addonVersion = "2.0.0"
local HolyStorm = LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local L = LibStub("AceLocale-3.0"):GetLocale("Holy_Storm_GuildLog")
local metadata = { id = "guildLog", name = "GuildLog", displayName = L["DISPLAY_NAME"], description = L["DESCRIPTION"], version = addonVersion, moduleType = "feature", category="feature", permissions = { "guild-roster-read" }, dependencies = { "core" }, ui = { page = "guildLog", navigation = true }, enabledByDefault = true }

HolyStorm:RegisterModule(metadata, function(GuildLog)
    HolyStorm:ApplyModuleMetadata(GuildLog, metadata)
    function GuildLog:GetDatabase()
        return HolyStorm.Data.GuildLogStore:GetDatabase()
    end
    function GuildLog:Add(eventType, message)
        HolyStorm.Data.GuildLogStore:Add(eventType, message)
    end
    function GuildLog:Scan()
        self.pending = nil; if not IsInGuild() then return end
        local database, current = self:GetDatabase(), {}
        for index = 1, GetNumGuildMembers() do
            local name, rank, _, level, _, _, note, officerNote, _, _, _, _, _, _, _, _, guid = GetGuildRosterInfo(index)
            if guid then current[guid] = { name = name or "-", rank = rank or "-", level = level or 0, note = note, officerNote = officerNote } end
        end
        if not database.snapshot then HolyStorm.Data.GuildLogStore:SetSnapshot(current); self:Render(); return end
        for guid, member in pairs(current) do
            local old = database.snapshot[guid]
            if not old then self:Add("join", string.format(L["EVENT_JOIN"], member.name)) else
                if old.level ~= member.level then self:Add("level", string.format(L["EVENT_LEVEL"], member.name, member.level)) end
                if old.rank ~= member.rank then self:Add("rank", string.format(L["EVENT_RANK"], member.name, old.rank, member.rank)) end
                if old.note ~= member.note then self:Add("note", string.format(L["EVENT_NOTE"], member.name)) end
                if old.officerNote ~= member.officerNote then self:Add("officerNote", string.format(L["EVENT_OFFICER_NOTE"], member.name)) end
            end
        end
        for guid, member in pairs(database.snapshot) do if not current[guid] then self:Add("leave", string.format(L["EVENT_LEAVE"], member.name)) end end
        HolyStorm.Data.GuildLogStore:SetSnapshot(current); self:Render()
    end
    function GuildLog:QueueScan()
        HolyStorm.Tasks:Enqueue("guildlog.scan", function() if GuildLog:IsEnabled() then GuildLog:Scan() end end, { priority=8, debounce=1, cooldown=1 })
    end
    function GuildLog:Render()
        if not self.page or not self.page:IsShown() then return end
        local colors = { join = "ff40ff40", leave = "ffff4040", level = "ff40c7eb", rank = "ffffd100", note = "ffffa500", officerNote = "ffc080ff" }
        local entries = self:GetDatabase().entries; self.text:SetText(#entries == 0 and L["EMPTY"] or "")
        if #entries > 0 then
            local lines = {}; for _, entry in ipairs(entries) do table.insert(lines, "|cff999999" .. date("%d.%m.%Y %H:%M", entry.timestamp) .. "|r  |c" .. (colors[entry.eventType] or "ffffffff") .. entry.message .. "|r") end
            self.text:SetText(table.concat(lines, "\n"))
        end
        self.content:SetHeight(math.max(self.scroll:GetHeight(), self.text:GetStringHeight() + 12))
    end
    function GuildLog:InitializeUI()
        local UI = HolyStorm:GetModule("UI", true); local page = CreateFrame("Frame", nil, UI.content)
        local heading = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge"); heading:SetPoint("TOPLEFT", page, "TOPLEFT", 18, -18); heading:SetText(L["HEADING"])
        local scroll = CreateFrame("ScrollFrame", nil, page, "UIPanelScrollFrameTemplate"); scroll:SetPoint("TOPLEFT", page, "TOPLEFT", 18, -52); scroll:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -28, 16)
        local content = CreateFrame("Frame", nil, scroll); content:SetSize(1, 1); scroll:SetScrollChild(content)
        local text = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); text:SetPoint("TOPLEFT", content, "TOPLEFT", 4, -4); text:SetPoint("TOPRIGHT", content, "TOPRIGHT", -4, -4); text:SetJustifyH("LEFT"); text:SetJustifyV("TOP")
        scroll:SetScript("OnSizeChanged", function(self) content:SetWidth(self:GetWidth()); GuildLog:Render() end)
        self.page, self.scroll, self.content, self.text = page, scroll, content, text
        HolyStorm.UI:RegisterPage("guildLog", page, L["WINDOW_TITLE"], function() GuildLog:QueueScan(); GuildLog:Render() end, { "HS_GUILD_LOG_UPDATED" })
        HolyStorm.UI:AddNavigation("guildLog", 5, "Interface\\Icons\\INV_Misc_Note_05", L["NAVIGATION_TITLE"], L["NAVIGATION_DESCRIPTION"], function() HolyStorm.UI:ShowPage("guildLog") end)
    end
    function GuildLog:OnInitialize()
        HolyStorm.Data.GuildLogStore:Initialize()
        HolyStorm:RegisterUIExtension("guildLog",{id="guild.log",order=5,initialize=function()GuildLog:InitializeUI()end})
    end
    function GuildLog:OnEnable()
        HolyStorm.Commands:RegisterSubcommand("log",{help=L["COMMAND_HELP"],execute=function()if not HolyStorm.UI or not HolyStorm.UI:ShowPage("guildLog")then HolyStorm.Commands:PrintUserMessage(L["COMMAND_UNAVAILABLE"])end end})
        HolyStorm.Events:Register("GUILD_ROSTER_UPDATE","guild-log",function() GuildLog:QueueScan() end); HolyStorm.Events:Register("PLAYER_ENTERING_WORLD","guild-log",function() GuildLog:QueueScan() end); HolyStorm.Events:Register("PLAYER_GUILD_UPDATE","guild-log",function() GuildLog:QueueScan() end)
    end
    function GuildLog:OnDisable() HolyStorm.Events:UnregisterOwner("guild-log"); HolyStorm.Tasks:Cancel("guildlog.scan"); HolyStorm.Commands:UnregisterSubcommand("log") end
end)
