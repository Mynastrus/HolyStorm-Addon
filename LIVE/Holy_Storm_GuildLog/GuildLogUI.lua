local HolyStorm = LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local L = LibStub("AceLocale-3.0"):GetLocale("Holy_Storm_GuildLog")
local UI = { version = "2.0.0", rowHeight = 26, rows = {}, sourceEvents = {}, filteredEvents = {}, searchIndex = {} }

local function lower(value) return string.lower(tostring(value or "")) end
local function safeText(value)
    local text = tostring(value or ""):gsub("||", "\001")
    text = text:gsub("|H.-|h(.-)|h", "%1"):gsub("|T.-|t", ""):gsub("|A.-|a", "")
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|.", "")
    return text:gsub("\001", "|"):gsub("[\r\n]", " ")
end
local function button(parent, label, width, callback)
    local value = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    value:SetSize(width, 24); value:SetText(label); value:SetScript("OnClick", callback)
    return value
end
local function edit(parent, width)
    local value = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    value:SetAutoFocus(false); value:SetSize(width, 22); value:SetTextInsets(6, 6, 0, 0)
    return value
end
local function tooltip(owner, title, description)
    owner:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText(title); if description then GameTooltip:AddLine(description, 1, 1, 1, true) end; GameTooltip:Show() end)
    owner:SetScript("OnLeave", function() GameTooltip:Hide() end)
end
local function validDate(value, endOfDay)
    value = tostring(value or "")
    if value == "" then return nil end
    local year, month, day = value:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
    if not year then return false end
    local stamp = time({ year = tonumber(year), month = tonumber(month), day = tonumber(day), hour = endOfDay and 23 or 0, min = endOfDay and 59 or 0, sec = endOfDay and 59 or 0 })
    if not stamp or date("%Y-%m-%d", stamp) ~= value then return false end
    return stamp
end
local function htmlEscape(value)
    return safeText(value):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"):gsub("'", "&#39;")
end
local function csv(value) return '"' .. safeText(value):gsub('"', '""') .. '"' end
local function bbEscape(value) return safeText(value):gsub("%[", "&#91;"):gsub("%]", "&#93;") end

function UI:CategoryLabel(module, category)
    return module and module:GetCategoryLabel(category) or L["CATEGORY_OTHER"]
end

function UI:CurrentGuildId()
    local guild = HolyStorm.Data.GuildStore:GetCurrent()
    return guild and guild.id
end

function UI:CreatePopup()
    if self.filterPopup then return self.filterPopup end
    local popup = CreateFrame("Frame", nil, self.frame, "BackdropTemplate")
    popup:SetSize(320, 410); popup:SetFrameStrata("DIALOG"); popup:SetFrameLevel(self.frame:GetFrameLevel() + 20)
    popup:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    popup:SetBackdropColor(.035, .045, .065, .98); popup:SetBackdropBorderColor(.28, .34, .44, 1)
    popup:SetPoint("TOPRIGHT", self.filterButton, "BOTTOMRIGHT", 0, -4)
    local title = popup:CreateFontString(nil, "OVERLAY", "GameFontNormal"); title:SetPoint("TOPLEFT", 12, -10); title:SetText(L["FILTER_TITLE"])
    local y = -34; self.categoryChecks = {}
    local availableCategories = self.module and self.module:GetCategories() or { "join", "leave", "promotion", "demotion", "notes", "achievement", "level", "birthday", "anniversary", "absence", "other" }
    popup:SetHeight(410 + math.max(0, math.ceil(#availableCategories / 2) - 5) * 23)
    for index, category in ipairs(availableCategories) do
        local column = (index - 1) % 2; local check = CreateFrame("CheckButton", nil, popup, "UICheckButtonTemplate"); check:SetSize(22, 22); check:SetPoint("TOPLEFT", 8 + column * 154, y)
        check.text:SetText(self:CategoryLabel(self.module, category)); check.text:ClearAllPoints(); check.text:SetPoint("LEFT", check, "RIGHT", 2, 0)
        check:SetScript("OnClick", function(buttonFrame)
            self.filters.categories = self.filters.categories or {}
            if buttonFrame:GetChecked() then self.filters.categories[category] = true else self.filters.categories[category] = nil end
            self:UpdateFilterBadge(); self:QueueFilter(true)
        end)
        self.categoryChecks[category] = check
        if column == 1 or index == #availableCategories then y = y - 23 end
    end
    local fromLabel = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); fromLabel:SetPoint("TOPLEFT", 12, y - 4); fromLabel:SetText(L["FILTER_FROM"])
    local toLabel = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); toLabel:SetPoint("LEFT", fromLabel, "RIGHT", 136, 0); toLabel:SetText(L["FILTER_TO"])
    local from = edit(popup, 130); from:SetPoint("TOPLEFT", 12, y - 26); from:SetText(self.filters.fromText or "")
    local to = edit(popup, 130); to:SetPoint("LEFT", from, "RIGHT", 10, 0); to:SetText(self.filters.toText or "")
    tooltip(from, L["FILTER_FROM"], L["DATE_FILTER_HELP"]); tooltip(to, L["FILTER_TO"], L["DATE_FILTER_HELP"])
    local actorLabel = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); actorLabel:SetPoint("TOPLEFT", 12, y - 57); actorLabel:SetText(L["FILTER_ACTOR"])
    local actor = edit(popup, 284); actor:SetPoint("TOPLEFT", 12, y - 79); actor:SetText(self.filters.actor or "")
    local subjectLabel = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); subjectLabel:SetPoint("TOPLEFT", 12, y - 109); subjectLabel:SetText(L["FILTER_SUBJECT"])
    local subject = edit(popup, 284); subject:SetPoint("TOPLEFT", 12, y - 131); subject:SetText(self.filters.subject or "")
    local stateLabel = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); stateLabel:SetPoint("TOPLEFT", 12, y - 162); stateLabel:SetText(L["FILTER_RECONSTRUCTION"])
    local state = CreateFrame("Frame", nil, popup, "UIDropDownMenuTemplate"); state:SetPoint("TOPLEFT", 0, y - 185); UIDropDownMenu_SetWidth(state, 260)
    local stateOptions = { "ALL", "RECONSTRUCTED", "AUTHORITATIVE" }
    UIDropDownMenu_Initialize(state, function(_, level)
        if level ~= 1 then return end
        for _, value in ipairs(stateOptions) do
            local chosen = value; local info = UIDropDownMenu_CreateInfo(); info.text = L["FILTER_STATE_" .. chosen]; info.checked = (self.filters.state or "ALL") == chosen
            info.func = function() self.filters.state = chosen; UIDropDownMenu_SetText(state, L["FILTER_STATE_" .. chosen]); self:UpdateFilterBadge(); self:QueueFilter(true) end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    UIDropDownMenu_SetText(state, L["FILTER_STATE_" .. (self.filters.state or "ALL")])
    local reset = button(popup, L["FILTER_RESET"], 132, function()
        self.filters = { categories = {}, state = "ALL" }; self:HideFilterPopup(); self:UpdateFilterBadge(); self:QueueFilter(true)
    end); reset:SetPoint("BOTTOMLEFT", 12, 12); tooltip(reset, L["FILTER_RESET"], L["FILTER_RESET_TOOLTIP"])
    local close = button(popup, L["CLOSE"], 132, function() self:HideFilterPopup() end); close:SetPoint("LEFT", reset, "RIGHT", 10, 0)
    local function changed()
        self.filters.fromText, self.filters.toText = from:GetText(), to:GetText()
        self.filters.actor, self.filters.subject = actor:GetText(), subject:GetText()
        self:UpdateFilterBadge(); self:QueueFilter(true)
    end
    for _, field in ipairs({ from, to, actor, subject }) do field:SetScript("OnTextChanged", function(_, user) if user then changed() end end) end
    self.filterPopup, self.fromInput, self.toInput, self.actorInput, self.subjectInput, self.stateDropdown = popup, from, to, actor, subject, state
    self:SyncFilterPopup()
    return popup
end

function UI:SyncFilterPopup()
    if not self.filterPopup then return end
    for category, check in pairs(self.categoryChecks or {}) do check:SetChecked(self.filters.categories and self.filters.categories[category] == true or false) end
    if self.fromInput then self.fromInput:SetText(self.filters.fromText or ""); self.toInput:SetText(self.filters.toText or ""); self.actorInput:SetText(self.filters.actor or ""); self.subjectInput:SetText(self.filters.subject or "") end
    if self.stateDropdown then UIDropDownMenu_SetText(self.stateDropdown, L["FILTER_STATE_" .. (self.filters.state or "ALL")]) end
end

function UI:HideFilterPopup() if self.filterPopup then self.filterPopup:Hide() end end

function UI:ActiveFilterCount()
    local count = 0
    for _ in pairs(self.filters.categories or {}) do count = count + 1 end
    if self.filters.fromText and self.filters.fromText ~= "" then count = count + 1 end
    if self.filters.toText and self.filters.toText ~= "" then count = count + 1 end
    if self.filters.actor and self.filters.actor ~= "" then count = count + 1 end
    if self.filters.subject and self.filters.subject ~= "" then count = count + 1 end
    if self.filters.state and self.filters.state ~= "ALL" then count = count + 1 end
    return count
end

function UI:UpdateFilterBadge()
    if self.filterBadge then
        local count = self:ActiveFilterCount()
        self.filterBadge:SetText(count > 0 and tostring(count) or "")
        self.filterBadge:SetShown(count > 0)
    end
end

function UI:CreateExportPopup()
    if self.exportPopup then return self.exportPopup end
    local popup = CreateFrame("Frame", nil, self.frame, "BackdropTemplate")
    popup:SetSize(238, 190); popup:SetFrameStrata("DIALOG"); popup:SetFrameLevel(self.frame:GetFrameLevel() + 20)
    popup:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    popup:SetBackdropColor(.035, .045, .065, .98); popup:SetBackdropBorderColor(.28, .34, .44, 1)
    popup:SetPoint("TOPRIGHT", self.exportButton, "BOTTOMRIGHT", 0, -4)
    local title = popup:CreateFontString(nil, "OVERLAY", "GameFontNormal"); title:SetPoint("TOPLEFT", 12, -10); title:SetText(L["EXPORT_FORMAT"])
    self.exportFormat, self.exportScope = self.exportFormat or "csv", self.exportScope or "FILTERED"
    self.formatChecks, self.scopeChecks = {}, {}
    local formats = { "bbcode", "html", "csv" }
    local y = -32
    for _, format in ipairs(formats) do
        local value = format; local check = CreateFrame("CheckButton", nil, popup, "UIRadioButtonTemplate"); check:SetPoint("TOPLEFT", 8, y); check:SetChecked(self.exportFormat == value)
        check.text:SetText(L["EXPORT_FORMAT_" .. string.upper(value)]); check:SetScript("OnClick", function() self.exportFormat = value; self:SyncExportPopup() end); self.formatChecks[value] = check; y = y - 24
    end
    local scopeTitle = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); scopeTitle:SetPoint("TOPLEFT", 12, y - 2); scopeTitle:SetText(L["EXPORT_SCOPE"])
    y = y - 22
    for _, scope in ipairs({ "ALL", "FILTERED" }) do
        local value = scope; local check = CreateFrame("CheckButton", nil, popup, "UIRadioButtonTemplate"); check:SetPoint("TOPLEFT", 8, y); check:SetChecked(self.exportScope == value)
        check.text:SetText(L["EXPORT_SCOPE_" .. value]); check:SetScript("OnClick", function() self.exportScope = value; self:SyncExportPopup() end); self.scopeChecks[value] = check; y = y - 24
    end
    local export = button(popup, L["EXPORT"], 92, function() self:ShowExport(self.module, self.exportFormat, self.exportScope); popup:Hide() end); export:SetPoint("BOTTOMRIGHT", -10, 10)
    self.exportPopup = popup; self:SyncExportPopup(); return popup
end

function UI:SyncExportPopup()
    for value, check in pairs(self.formatChecks or {}) do check:SetChecked(value == self.exportFormat) end
    for value, check in pairs(self.scopeChecks or {}) do check:SetChecked(value == self.exportScope) end
end

function UI:CreateExportDialog()
    if self.exportDialog then return self.exportDialog end
    local dialog = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    dialog:SetSize(720, 510); dialog:SetPoint("CENTER"); dialog:SetFrameStrata("DIALOG")
    dialog:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", edgeSize = 24, insets = { left = 8, right = 8, top = 8, bottom = 8 } })
    local title = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); title:SetPoint("TOPLEFT", 24, -22); title:SetText(L["EXPORT_TITLE"])
    local close = button(dialog, L["CLOSE"], 86, function() dialog:Hide() end); close:SetPoint("BOTTOMRIGHT", -28, 22)
    local hint = dialog:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); hint:SetPoint("BOTTOMLEFT", 26, 28); hint:SetText(L["EXPORT_COPY_HELP"])
    local scroll = CreateFrame("ScrollFrame", nil, dialog, "UIPanelScrollFrameTemplate"); scroll:SetPoint("TOPLEFT", 24, -48); scroll:SetPoint("BOTTOMRIGHT", -42, 56)
    local box = CreateFrame("EditBox", nil, scroll); box:SetMultiLine(true); box:SetAutoFocus(false); box:SetFontObject("ChatFontNormal"); box:SetWidth(640); box:SetScript("OnEscapePressed", function() dialog:Hide() end); scroll:SetScrollChild(box)
    self.exportDialog, self.exportEdit, self.exportScroll = dialog, box, scroll
    return dialog
end

function UI:Export(module, format, options)
    if not module then return nil, "MODULE_UNAVAILABLE" end
    options = options or {}
    local scope = options.scope or "FILTERED"
    self.filters = self.filters or { categories = {}, state = "ALL" }
    if self.frame and (self.sourceDirty or self.filterDirty or self.indexing) then self:QueueFilter(false); return nil, "FILTER_INDEX_PENDING" end
    if not self.frame then self:RebuildSource(module) end
    local events
    if scope == "ALL" then
        events = self.sourceEvents
    elseif self.frame then
        events = self.filteredEvents
    else
        local query = lower(self.query or "")
        local from, to = validDate(self.filters.fromText, false), validDate(self.filters.toText, true)
        events = {}
        for index, event in ipairs(self.sourceEvents or {}) do if self:Matches(module, event, index, query, from, to) then events[#events + 1] = event end end
    end
    local rows = {}
    for _, event in ipairs(events or {}) do
        rows[#rows + 1] = {
            timestamp = module:FormatTimestamp(event.timestamp, true), category = self:CategoryLabel(module, module:GetCategory(event)),
            actor = event.actor and self:PlainName(event.actor) or "",
            subject = event.subject and self:PlainName(event.subject) or "", text = module:FormatEvent(event, false),
            state = event.resolutionState == "RECONSTRUCTED" and L["RECONSTRUCTED"] or L["AUTHORITATIVE"],
        }
    end
    format = lower(format or "csv")
    if format == "csv" then
        local output = { table.concat({ csv(L["EXPORT_COLUMN_TIMESTAMP"]), csv(L["EXPORT_COLUMN_CATEGORY"]), csv(L["EXPORT_COLUMN_ACTOR"]), csv(L["EXPORT_COLUMN_SUBJECT"]), csv(L["EXPORT_COLUMN_EVENT"]), csv(L["EXPORT_COLUMN_STATE"]) }, ",") }
        for _, row in ipairs(rows) do output[#output + 1] = table.concat({ csv(row.timestamp), csv(row.category), csv(row.actor), csv(row.subject), csv(row.text), csv(row.state) }, ",") end
        return table.concat(output, "\r\n")
    elseif format == "html" then
        local output = { '<!doctype html><html lang="' .. htmlEscape(GetLocale and GetLocale() or "enUS") .. '"><head><meta charset="utf-8"><title>' .. htmlEscape(L["DISPLAY_NAME"]) .. '</title><style>body{font:14px sans-serif;margin:2rem;color:#20242c}table{border-collapse:collapse;width:100%}th,td{border-bottom:1px solid #d7dbe2;padding:.45rem;text-align:left}th{background:#edf0f4}</style></head><body><h1>' .. htmlEscape(L["DISPLAY_NAME"]) .. '</h1><table><thead><tr>' }
        for _, key in ipairs({ "EXPORT_COLUMN_TIMESTAMP", "EXPORT_COLUMN_CATEGORY", "EXPORT_COLUMN_ACTOR", "EXPORT_COLUMN_SUBJECT", "EXPORT_COLUMN_EVENT", "EXPORT_COLUMN_STATE" }) do output[#output + 1] = "<th>" .. htmlEscape(L[key]) .. "</th>" end
        output[#output + 1] = "</tr></thead><tbody>"
        for _, row in ipairs(rows) do output[#output + 1] = "<tr>"; for _, key in ipairs({ "timestamp", "category", "actor", "subject", "text", "state" }) do output[#output + 1] = "<td>" .. htmlEscape(row[key]) .. "</td>" end; output[#output + 1] = "</tr>" end
        output[#output + 1] = "</tbody></table></body></html>"
        return table.concat(output)
    elseif format == "bbcode" then
        local output = { "[b]" .. bbEscape(L["DISPLAY_NAME"]) .. "[/b]" }
        for index, row in ipairs(rows) do local color = module.categoryColors[module:GetCategory(events[index]) or "other"] or module.categoryColors.other; output[#output + 1] = "[b]" .. bbEscape(row.timestamp) .. "[/b]  [color=#" .. color .. "]" .. string.char(226, 150, 160) .. "[/color] " .. bbEscape(row.text) .. (row.state == L["RECONSTRUCTED"] and ("  [i]" .. bbEscape(row.state) .. "[/i]") or "") end
        return table.concat(output, "\n")
    end
    return nil, "UNSUPPORTED_FORMAT"
end

function UI:PlainName(identity)
    if type(identity) ~= "table" then return "" end
    if identity.guid then
        local guild = HolyStorm.Data.GuildStore:GetCurrent(); local member = guild and guild.roster and guild.roster[identity.guid]
        local character = HolyStorm.Data.CharacterStore:Get(identity.guid)
        return safeText((member and member.name) or (character and (character.fullName or character.name)) or identity.name or identity.guid)
    end
    return safeText(identity.name)
end

function UI:ShowExport(module, format, scope)
    local value, reason = self:Export(module, format, { scope = scope })
    if not value and reason == "FILTER_INDEX_PENDING" then self.pendingExport = { format = format, scope = scope }; return true end
    if not value then HolyStorm.Logger:Write("WARN", "GuildLog", "export", "GuildLog export rejected", { reason = reason, format = format }); return false end
    local dialog = self:CreateExportDialog(); local lines = 1; value:gsub("\n", function() lines = lines + 1 end)
    self.exportEdit:SetHeight(math.max(self.exportScroll:GetHeight(), lines * 14 + 20)); self.exportEdit:SetText(value); dialog:Show(); self.exportEdit:HighlightText(); self.exportEdit:SetFocus()
    return true
end

function UI:QueueFilter(markDirty)
    if markDirty then self.filterDirty = true end
    if not HolyStorm.Tasks:GetTaskType("GuildLog.Filter") then self:ApplyFilters(self.module); return end
    HolyStorm.Tasks:Queue("GuildLog.Filter", { mergeKey = "guildLog-view", debounce = .12, priority = 28, triggerSource = "GUILD_LOG_FILTER", metadata = { rebuild = self.sourceDirty == true } })
end

function UI:RebuildSource(module)
    local guildId = self:CurrentGuildId()
    self.sourceEvents = guildId and HolyStorm.Data.GuildLogStore:List(guildId) or {}
    self.searchIndex = {}
    for index, event in ipairs(self.sourceEvents) do
        self.searchIndex[index] = module:BuildSearchText(event)
    end
    self.sourceDirty, self.filterDirty = false, true
end

function UI:Matches(module, event, index, query, from, to)
    if from == false or to == false or from and to and from > to then return false end
    if from and event.timestamp < from or to and event.timestamp > to then return false end
    local selected = self.filters.categories or {}
    if next(selected) and not selected[module:GetCategory(event)] then return false end
    if self.filters.state == "RECONSTRUCTED" and event.resolutionState ~= "RECONSTRUCTED" then return false end
    if self.filters.state == "AUTHORITATIVE" and event.resolutionState ~= "AUTHORITATIVE" then return false end
    if query ~= "" and not self.searchIndex[index]:find(query, 1, true) then return false end
    local actorQuery, subjectQuery = lower(self.filters.actor), lower(self.filters.subject)
    if actorQuery ~= "" and not lower(self:PlainName(event.actor)):find(actorQuery, 1, true) then return false end
    if subjectQuery ~= "" and not lower(self:PlainName(event.subject)):find(subjectQuery, 1, true) then return false end
    return true
end

function UI:ApplyFilters(module)
    if not module then return false end
    if self.sourceDirty or self.indexing then return false end
    local query = lower(self.search and self.search:GetText() or self.query or "")
    local from, to = validDate(self.filters.fromText, false), validDate(self.filters.toText, true)
    local filtered = {}
    for index, event in ipairs(self.sourceEvents) do if self:Matches(module, event, index, query, from, to) then filtered[#filtered + 1] = event end end
    self.filteredEvents, self.filterDirty = filtered, false
    self:RenderRows(module)
    return true
end

function UI:ReconstructedTooltip(row, event, module)
    GameTooltip:SetOwner(row, "ANCHOR_TOP")
    GameTooltip:SetText(L["RECONSTRUCTED"])
    GameTooltip:AddLine(L["RECONSTRUCTED_EXPLANATION"], .85, .9, 1, true)
    GameTooltip:AddLine(string.format(L["PROVENANCE_SOURCE"], tostring(event.provenance and event.provenance.source or L["UNKNOWN_VALUE"])), .8, .8, .8, true)
    GameTooltip:AddLine(L["EXACT_TIME_UNKNOWN"], .8, .8, .8, true)
    if not event.actor then GameTooltip:AddLine(L["ACTOR_UNKNOWN"], .8, .8, .8, true) end
    if event.type == "RANK_CHANGED" then
        GameTooltip:AddLine(string.format(L["PREVIOUS_RANK"], tostring(event.data.oldRank or L["UNKNOWN_VALUE"])), .8, .8, .8, true)
        GameTooltip:AddLine(string.format(L["CURRENT_RANK"], tostring(event.data.newRank or L["UNKNOWN_VALUE"])), .8, .8, .8, true)
    end
    local observation = event.provenance and event.provenance.observation
    if observation then GameTooltip:AddLine(string.format(L["OBSERVATION_WINDOW"], module:FormatTimestamp(observation.from, true), module:FormatTimestamp(observation.to, true)), .8, .8, .8, true) end
    GameTooltip:AddLine(string.format(L["LOCAL_CAPTURE_TIME"], module:FormatTimestamp(event.capturedAt, true)), .8, .8, .8, true)
    GameTooltip:Show()
end

function UI:CreateRow(parent, module)
    local row = CreateFrame("Button", nil, parent); row:SetHeight(self.rowHeight); row:EnableMouse(true)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    row.time = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); row.time:SetPoint("LEFT", 4, 0); row.time:SetWidth(116); row.time:SetJustifyH("LEFT")
    row.marker = row:CreateTexture(nil, "OVERLAY"); row.marker:SetSize(7, 7); row.marker:SetPoint("LEFT", row.time, "RIGHT", 8, 0)
    row.state = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); row.state:SetPoint("RIGHT", -8, 0); row.state:SetJustifyH("RIGHT")
    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); row.text:SetPoint("LEFT", row.marker, "RIGHT", 8, 0); row.text:SetPoint("RIGHT", row.state, "LEFT", -8, 0); row.text:SetJustifyH("LEFT"); row.text:SetWordWrap(false)
    if row.text.SetHyperlinksEnabled then
        row.text:SetHyperlinksEnabled(true)
        row.text:SetScript("OnHyperlinkClick", function(_, link, _, mouseButton) if HolyStorm.RichLinks then HolyStorm.RichLinks:HandleHyperlink(link, mouseButton, row.text) end end)
        row.text:SetScript("OnHyperlinkEnter", function(_, link) if HolyStorm.RichLinks then HolyStorm.RichLinks:ShowTooltip(row.text, link) end end)
        row.text:SetScript("OnHyperlinkLeave", function() GameTooltip:Hide() end)
    end
    row:SetScript("OnEnter", function(frame) if frame.event and frame.event.resolutionState == "RECONSTRUCTED" then self:ReconstructedTooltip(frame, frame.event, module) end end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return row
end

function UI:RenderRows(module)
    if not self.content or not self.scroll then return end
    local width = math.max(1, self.scroll:GetWidth() - 6); self.content:SetWidth(width)
    local count = #self.filteredEvents; self.content:SetHeight(math.max(self.scroll:GetHeight(), count * self.rowHeight + 8))
    local offset = self.scroll.GetVerticalScroll and self.scroll:GetVerticalScroll() or 0
    local first = math.max(1, math.floor(offset / self.rowHeight) + 1)
    local visibleCount = math.max(1, math.ceil((self.scroll:GetHeight() or 300) / self.rowHeight) + 2)
    local last = math.min(count, first + visibleCount - 1)
    for index = 1, visibleCount do
        local eventIndex = first + index - 1; local row = self.rows[index]
        if eventIndex <= last then
            if not row then row = self:CreateRow(self.content, module); self.rows[index] = row end
            local event = self.filteredEvents[eventIndex]; row.event = event; row:SetWidth(width); row:ClearAllPoints(); row:SetPoint("TOPLEFT", 0, -((eventIndex - 1) * self.rowHeight + 4))
            row.time:SetText(module:FormatTimestamp(event.timestamp, false))
            local category = module:GetCategory(event); local color = module.categoryColors[category] or module.categoryColors.other
            local red, green, blue = tonumber(color:sub(1, 2), 16) / 255, tonumber(color:sub(3, 4), 16) / 255, tonumber(color:sub(5, 6), 16) / 255
            row.marker:SetColorTexture(red, green, blue, 1)
            row.state:SetText(event.resolutionState == "RECONSTRUCTED" and L["RECONSTRUCTED"] or "")
            row.text:SetText(module:FormatEvent(event, true)); row:Show()
        elseif row then row.event = nil; row:Hide() end
    end
    if self.empty then self.empty:SetShown(count == 0) end
    if self.resultCount then self.resultCount:SetText(string.format(L["RESULT_COUNT"], count, #self.sourceEvents)) end
end

function UI:Build(module, parent)
    self.module, self.filters = module, self.filters or { categories = {}, state = "ALL" }
    self.sourceDirty = true; self.rows = {}
    local frame = CreateFrame("Frame", nil, parent); self.frame = frame
    local toolbar = CreateFrame("Frame", nil, frame); toolbar:SetPoint("TOPLEFT", 12, -10); toolbar:SetPoint("TOPRIGHT", -12, -10); toolbar:SetHeight(30)
    local filter = button(toolbar, L["FILTER"], 86, function()
        local popup = self:CreatePopup(); self:SyncFilterPopup(); popup:SetShown(not popup:IsShown())
    end); filter:SetPoint("RIGHT", toolbar, "RIGHT", 0, 0); self.filterButton = filter
    local badge = toolbar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); badge:SetPoint("RIGHT", filter, "RIGHT", -7, 0); self.filterBadge = badge
    local export = button(toolbar, L["EXPORT"], 86, function()
        local popup = self:CreateExportPopup(); popup:SetShown(not popup:IsShown())
    end); export:SetPoint("RIGHT", filter, "LEFT", -6, 0); self.exportButton = export
    local search = edit(toolbar, 260); search:SetPoint("LEFT", toolbar, "LEFT", 2, 0); search:SetPoint("RIGHT", export, "LEFT", -8, 0); search:SetText(self.query or ""); search:SetScript("OnTextChanged", function(_, user) if user then self.query = search:GetText(); self:QueueFilter(false) end end); self.search = search
    local hint = search:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); hint:SetPoint("LEFT", search, "LEFT", 8, 0); hint:SetText(search:GetText() == "" and L["SEARCH_PLACEHOLDER"] or ""); self.searchHint = hint
    search:HookScript("OnTextChanged", function() hint:SetText(search:GetText() == "" and L["SEARCH_PLACEHOLDER"] or "") end)
    local resultCount = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); resultCount:SetPoint("TOPLEFT", 16, -46); resultCount:SetJustifyH("LEFT"); self.resultCount = resultCount
    local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate"); scroll:SetPoint("TOPLEFT", 12, -64); scroll:SetPoint("BOTTOMRIGHT", -26, 12); scroll:EnableMouseWheel(true)
    local content = CreateFrame("Frame", nil, scroll); content:SetSize(1, 1); scroll:SetScrollChild(content); self.scroll, self.content = scroll, content
    scroll:SetScript("OnVerticalScroll", function() self:RenderRows(module) end)
    scroll:SetScript("OnMouseWheel", function(_, delta) scroll:SetVerticalScroll(math.max(0, scroll:GetVerticalScroll() - delta * self.rowHeight * 3)); self:RenderRows(module) end)
    scroll:SetScript("OnSizeChanged", function() self:RenderRows(module) end)
    local empty = content:CreateFontString(nil, "OVERLAY", "GameFontDisable"); empty:SetPoint("TOPLEFT", 8, -8); empty:SetText(L["EMPTY"]); self.empty = empty
    self:UpdateFilterBadge(); self:QueueFilter(true)
    return frame
end

function UI:Refresh(module)
    self.module = module or self.module
    if not self.frame then return false end
    self.sourceDirty = true
    self:QueueFilter(true)
    return true
end

function UI:RunFilterTask()
    local module = self.module
    if not module then return false end
    if self.sourceDirty then
        local guildId = self:CurrentGuildId()
        self.indexing = { events = guildId and HolyStorm.Data.GuildLogStore:List(guildId) or {}, cursor = 1 }
        self.sourceEvents, self.searchIndex = self.indexing.events, {}
        self.sourceDirty = false
    end
    if self.indexing then
        local stop = math.min(#self.indexing.events, self.indexing.cursor + 299)
        for index = self.indexing.cursor, stop do self.searchIndex[index] = module:BuildSearchText(self.indexing.events[index]) end
        self.indexing.cursor = stop + 1
        if self.indexing.cursor <= #self.indexing.events then
            HolyStorm.Tasks:Queue("GuildLog.Filter", { mergeKey = "guildLog-view", delay = .01, priority = 28, triggerSource = "GUILD_LOG_INDEX_CHUNK" })
            return true
        end
        self.indexing = nil; self.filterDirty = true
    end
    local applied = self:ApplyFilters(module)
    if self.pendingExport then local pending = self.pendingExport; self.pendingExport = nil; self:ShowExport(module, pending.format, pending.scope) end
    return applied
end

HolyStorm.GuildLogUI = UI
