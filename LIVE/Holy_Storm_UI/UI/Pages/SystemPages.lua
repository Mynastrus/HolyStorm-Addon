local HolyStorm = LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local L = LibStub("AceLocale-3.0"):GetLocale("Holy_Storm_Options")

local SystemPages = { pages={} }

local function text(parent, value, font, x, y, width)
    local line = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    line:SetPoint("TOPLEFT", x or 18, y or -18)
    if width then line:SetWidth(width) end
    line:SetJustifyH("LEFT")
    line:SetText(value or "")
    return line
end

local function clear(parent)
    for _, child in ipairs(parent.lines or {}) do child:Hide() end
    parent.lines = {}
end

local function add(parent, value, font, width)
    local y = -18 - #parent.lines * 22
    parent.lines[#parent.lines+1] = text(parent, value, font, 18, y, width)
end

function SystemPages:BuildHelp(parent)
    local page = CreateFrame("Frame", nil, parent)
    local title = text(page, L["SYSTEM_HELP_TITLE"], "GameFontHighlightLarge", 18, -18)
    local function refresh()
        clear(page);title:Show();page.lines={title}
        add(page, L["SYSTEM_HELP_HINT"], "GameFontHighlightSmall", 780)
        local grouped = {}
        for _, command in ipairs(HolyStorm.Commands:GetRegisteredCommands()) do
            grouped[command.group] = grouped[command.group] or {}
            grouped[command.group][#grouped[command.group]+1] = command
        end
        local groups = {}; for group in pairs(grouped) do groups[#groups+1] = group end; table.sort(groups)
        for _, group in ipairs(groups) do
            add(page, group, "GameFontNormal")
            for _, command in ipairs(grouped[group]) do
                local syntax=command.syntax
                if #(command.aliases or{})>0 then local aliases={};for _,alias in ipairs(command.aliases)do aliases[#aliases+1]="/hs "..alias end;syntax=syntax.." ("..string.format(L["SYSTEM_HELP_ALIASES"],table.concat(aliases,", "))..")"end
                add(page, string.format(L["SYSTEM_HELP_COMMAND"], syntax, command.description or ""), "GameFontHighlightSmall", 820)
            end
        end
    end
    refresh()
    return page, refresh
end

function SystemPages:BuildInfo(parent)
    local page = CreateFrame("Frame", nil, parent)
    local title = text(page, L["SYSTEM_INFO_TITLE"], "GameFontHighlightLarge", 18, -18)
    local function refresh()
        clear(page);title:Show();page.lines={title}
        local info = HolyStorm.Commands:GetInfo()
        add(page, string.format(L["SYSTEM_INFO_VERSION"], info.version))
        if info.channel then add(page, string.format(L["SYSTEM_INFO_CHANNEL"], info.channel)) end
        add(page, string.format(L["SYSTEM_INFO_PROFILE"], info.profile or "-"))
        add(page, string.format(L["SYSTEM_INFO_GUILD"], info.guild or L["SYSTEM_VALUE_NONE"]))
        add(page, string.format(L["SYSTEM_INFO_MODULES"], #info.modules))
        for _, moduleName in ipairs(info.modules) do add(page, "  "..moduleName, "GameFontHighlightSmall") end
    end
    refresh()
    return page, refresh
end

function SystemPages:GetStatus()
    local task = HolyStorm.Tasks and HolyStorm.Tasks:GetDiagnostics() or {active=0,queued=0}
    local workflow = HolyStorm.Workflows and HolyStorm.Workflows:GetDiagnostics() or {active=0}
    local sync = HolyStorm.Sync and HolyStorm.Sync:GetDiagnostics() or {idle=true,activeRequests=0}
    local modules = {}
    for _, entry in ipairs(HolyStorm:GetModuleEntries()) do
        local module = HolyStorm:GetLoadedModuleById(entry.id)
        modules[#modules+1] = {name=entry.displayName or entry.id,loaded=module~=nil,enabled=module~=nil and(not module.IsEnabled or module:IsEnabled())}
    end
    table.sort(modules,function(a,b)return a.name<b.name end)
    local warningCount,errorCount=0,0
    for _, entry in ipairs(HolyStorm.Logger and HolyStorm.Logger:GetHistory() or {}) do
        if entry.level=="WARN"then warningCount=warningCount+1 elseif entry.level=="ERROR"then errorCount=errorCount+1 end
    end
    local guild=HolyStorm.Data and HolyStorm.Data.GuildStore and HolyStorm.Data.GuildStore:GetCurrent()
    return {addonReady=HolyStorm.State and HolyStorm.State:Is("addonLoaded")or false,guild=guild and(guild.name or guild.id)or nil,syncIdle=sync.idle==true,syncRequests=sync.activeRequests or 0,tasks=task.active or 0,queued=task.queued or 0,workflows=workflow.active or 0,modules=modules,warnings=warningCount,errors=errorCount}
end

function SystemPages:BuildStatus(parent)
    local page = CreateFrame("Frame", nil, parent)
    local title = text(page, L["SYSTEM_STATUS_TITLE"], "GameFontHighlightLarge", 18, -18)
    local function refresh()
        clear(page);title:Show();page.lines={title}
        local status=self:GetStatus()
        add(page,string.format(L["SYSTEM_STATUS_ADDON"],status.addonReady and L["SYSTEM_VALUE_READY"]or L["SYSTEM_VALUE_NOT_READY"]))
        add(page,string.format(L["SYSTEM_STATUS_GUILD"],status.guild or L["SYSTEM_VALUE_NONE"]))
        add(page,string.format(L["SYSTEM_STATUS_SYNC"],status.syncIdle and L["SYSTEM_VALUE_IDLE"]or L["SYSTEM_VALUE_ACTIVE"],status.syncRequests))
        add(page,string.format(L["SYSTEM_STATUS_TASKS"],status.tasks,status.queued))
        add(page,string.format(L["SYSTEM_STATUS_WORKFLOWS"],status.workflows))
        add(page,string.format(L["SYSTEM_STATUS_LOGS"],status.warnings,status.errors))
        add(page,L["SYSTEM_STATUS_MODULES"],"GameFontNormal")
        for _, module in ipairs(status.modules) do
            local state=not module.loaded and L["SYSTEM_MODULE_NOT_LOADED"]or module.enabled and L["SYSTEM_MODULE_ENABLED"]or L["SYSTEM_MODULE_DISABLED"]
            add(page,string.format(L["SYSTEM_STATUS_MODULE"],module.name,state),"GameFontHighlightSmall",780)
        end
    end
    refresh()
    return page, refresh
end

function SystemPages:Initialize()
    local UI=HolyStorm:GetModule("UI",true);if not UI then return false end
    for _,definition in ipairs({
        {id="system-help",title=L["SYSTEM_HELP_TITLE"],build=self.BuildHelp},
        {id="system-info",title=L["SYSTEM_INFO_TITLE"],build=self.BuildInfo},
        {id="system-status",title=L["SYSTEM_STATUS_TITLE"],build=self.BuildStatus},
    }) do
        local page,refresh=definition.build(self,UI.content)
        self.pages[definition.id]=page
        UI:RegisterPage(definition.id,page,definition.title,function()refresh()end)
    end
    return true
end

HolyStorm:RegisterUIExtension("SystemPages",{id="system.pages",order=1,initialize=function()SystemPages:Initialize()end})
