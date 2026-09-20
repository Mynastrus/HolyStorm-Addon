local HolyStorm = LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local L = LibStub("AceLocale-3.0"):GetLocale("Holy_Storm_Policy")
local Registry = HolyStorm.PermissionRegistry
local Engine = HolyStorm.PermissionEngine
local Groups = HolyStorm.GroupManager
local Filters = HolyStorm.FilterManager
local State = HolyStorm.PolicyState
local Page = HolyStorm:RegisterRequiredModule("PermissionsUI")

HolyStorm:ApplyModuleMetadata(Page, {
    displayName = L["PERMISSIONS_TITLE"], internalName = "permissionsUI", version = "2.3.0",
    category = "required", description = L["PERMISSIONS_DESC"], permissions = { "permissions-manage" },
    dependencies = { "core", "ui" }, enabledByDefault = true,
})

local tabs = {
    "GENERAL", "MEMBERS", "PERMISSIONS", "PERMISSION_MATRIX", "RULES_FILTERS",
    "MANAGERS", "EFFECTIVE_MEMBERS", "MODULE_SETTINGS", "ANALYSIS", "STATUS",
}

local errorKeys = {
    SYSTEM_GROUP = "ERROR_SYSTEM_GROUP",
    SYSTEM_INVARIANT = "ERROR_SYSTEM_INVARIANT",
    FULL_ACCESS_GROUP = "ERROR_FULL_ACCESS_GROUP",
    GUILD_LEADER_REQUIRED = "ERROR_GUILD_LEADER_REQUIRED",
    PERMISSION_DENIED = "ERROR_PERMISSION_DENIED",
    STATE_NOT_VALID = "ERROR_STATE_NOT_VALID",
    UNCHANGED = "ERROR_UNCHANGED",
    MANAGER_CYCLE = "ERROR_MANAGER_CYCLE",
    INVALID_GROUP = "ERROR_INVALID_GROUP",
    INVALID_GROUP_NAME = "ERROR_INVALID_GROUP_NAME",
    NOT_FOUND = "ERROR_NOT_FOUND",
    TOO_MANY_MEMBERSHIPS = "ERROR_TOO_MANY_MEMBERSHIPS",
    INVALID_MODULE = "ERROR_INVALID_MODULE",
}

local function keys(value)
    local out = {}
    for key in pairs(value or {}) do out[#out + 1] = key end
    table.sort(out, function(left, right) return tostring(left) < tostring(right) end)
    return out
end

local function arrayContains(values, wanted)
    for _, value in ipairs(values or {}) do if value == wanted then return true end end
    return false
end

local function setArrayValue(values, id, enabled)
    local set = {}
    for _, value in ipairs(values or {}) do set[value] = true end
    set[id] = enabled and true or nil
    return keys(set)
end

local function displayTime(value)
    return value and date("%Y-%m-%d %H:%M", value) or "-"
end

function Page:GetGroups()
    local out = {}
    local search = string.lower(self.search:GetText() or "")
    for _, group in pairs(Groups:GetGroups()) do
        local name = HolyStorm.PolicyUI:DisplayGroupName(group)
        if search == "" or string.lower(name .. " " .. group.id):find(search, 1, true) then out[#out + 1] = group end
    end
    table.sort(out, function(left, right)
        if left.system ~= right.system then return left.system end
        return HolyStorm.PolicyUI:DisplayGroupName(left) < HolyStorm.PolicyUI:DisplayGroupName(right)
    end)
    return out
end

function Page:CanMutate(permission)
    local status = State:GetPermissionStateStatus()
    return status.status == State.status.VALID and Engine:HasPermission(nil, nil, permission)
end

function Page:CanEditGroup()
    if not self.draft then return false end
    if self.isNew then return self:CanMutate("groups-create") end
    local actor = Engine:Actor()
    return Engine:CanManageGroup(actor.accountUUID, actor.characterUUID, self.draft.id)
end

function Page:CanEditMembers()
    if not self.draft or self.isNew then return false end
    if self.draft.id == Groups.systemIds.LEADERSHIP and not Engine:IsActualGuildLeader() then return false end
    local actor = Engine:Actor()
    local state = State:GetState()
    if state and Engine:IsManagedBy(state, actor, self.draft.id) then return true end
    return self:CanMutate("groups-manage-members")
end

function Page:CanEditPermissions()
    return self.draft ~= nil and not self.isNew
        and self.draft.id ~= Groups.systemIds.LEADERSHIP
        and self:CanEditGroup() and self:CanMutate("permissions-manage")
end

function Page:ErrorMessage(reason)
    local key = errorKeys[reason]
    return key and L[key] or string.format(L["INVALID"], tostring(reason))
end

function Page:Select(group)
    self.selectedId = group and group.id
    self.isNew = group and Groups:GetGroup(group.id) == nil or false
    self.draft = group and HolyStorm.Utils.DeepCopy(group) or nil
    self.baseRevision = State:GetPermissionStateStatus().revisionID
    if self.deleteButton then
        self.deleteButton:SetEnabled(group and not self.isNew and not group.system and self:CanMutate("groups-delete") or false)
    end
    self:RefreshDetails()
end

function Page:RefreshList()
    local summaries = Engine:GetGroupSummaries()
    self.list:SetItems(self:GetGroups(), function(group)
        local summary = summaries[group.id] or {}
        return string.format("%s%s  (%d / %d / %d / %d)",
            group.system and "|TInterface\\Buttons\\LockButton-Locked-Up:12|t " or "",
            HolyStorm.PolicyUI:DisplayGroupName(group), summary.effectiveMembers or 0,
            summary.explicitMembers or 0, summary.filters or 0, summary.permissions or 0)
    end)
end

function Page:EnsurePermissionChecks()
    if not self.permissionsFrame then return end
    local definitions = Registry:GetPermissions()
    local query = string.lower(self.permissionSearch and self.permissionSearch:GetText() or "")
    local visible = 0
    for _, id in ipairs(keys(definitions)) do
        local permissionId = id
        local definition = definitions[id]
        local check = self.permissionChecks[id]
        if not check then
            check = CreateFrame("CheckButton", nil, self.permissionsFrame, "UICheckButtonTemplate")
            self.permissionChecks[id] = check
            check:SetScript("OnClick", function(widget)
                if Page.draft and Page:CanEditPermissions() then Page.draft.permissions[permissionId] = widget:GetChecked() and true or nil end
            end)
            check:SetScript("OnEnter", function(widget)
                GameTooltip:SetOwner(widget, "ANCHOR_RIGHT")
                GameTooltip:AddLine(L[definition.labelKey] or permissionId)
                GameTooltip:AddLine(L[definition.descriptionKey] or permissionId, nil, nil, nil, true)
                GameTooltip:AddLine(permissionId, .6, .6, .6)
                GameTooltip:AddLine(definition.module or "Core", .6, .6, .6)
                GameTooltip:Show()
            end)
            check:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end
        local categoryKey = "CATEGORY_" .. definition.category:gsub("[^%w]", "_"):upper()
        local label = (L[definition.labelKey] or permissionId) .. "  [" .. (L[categoryKey] or definition.category) .. "]"
        check.text:SetText(label)
        local matches = query == "" or string.lower(label .. " " .. permissionId .. " " .. (definition.module or "")):find(query, 1, true)
        check:SetShown(matches and true or false)
        if matches then
            check:ClearAllPoints()
            check:SetPoint("TOPLEFT", (visible % 3) * 220, -30 - math.floor(visible / 3) * 27)
            visible = visible + 1
        end
    end
    self.permissionsFrame:SetHeight(math.max(1000, 50 + math.ceil(visible / 3) * 27))
end

function Page:ShowTab(id)
    self.activeTab = id
    for key, frame in pairs(self.tabFrames) do frame:SetShown(key == id) end
    for key, button in pairs(self.tabButtons) do button:SetEnabled(key ~= id) end
    self:RefreshDetails()
end

function Page:RefreshDetails()
    local draft = self.draft
    if not draft then
        for _, frame in pairs(self.tabFrames) do frame:Hide() end
        self.empty:Show()
        return
    end
    self.empty:Hide()
    local active = self.activeTab or "GENERAL"
    for key, frame in pairs(self.tabFrames) do frame:SetShown(key == active) end

    if active == "GENERAL" then
        self.nameEdit:SetText(draft.nameKey and (L[draft.nameKey] or draft.name) or draft.name or "")
        self.descEdit:SetText(draft.description or "")
        local editable = not draft.system and self:CanEditGroup()
        self.nameEdit:SetEnabled(editable)
        self.descEdit:SetEnabled(editable)
        self.generalInfo:SetText(string.format("%s: %s\n%s: %s\n%s: %s\n%s: %s\n%s: %s",
            L["INTERNAL_ID"], draft.id, L["TYPE"], draft.system and L["SYSTEM_GROUP"] or L["CUSTOM_GROUP"],
            L["CREATOR"], draft.creator or "-", L["CREATED_AT"], displayTime(draft.createdAt),
            L["MODIFIED_AT"], displayTime(draft.modifiedAt)))
    elseif active == "MEMBERS" then
        local help = draft.system and L["SYSTEM_ACTION_HELP"] or L["ACCOUNT_MEMBERSHIP_HELP"]
        if draft.id == Groups.systemIds.LEADERSHIP then help = help .. "\n" .. L["LEADERSHIP_ACTION_HELP"] end
        self.memberText:SetText(string.format("%s:\n%s\n\n%s:\n%s\n\n%s:\n%s\n\n%s",
            L["CHARACTER_MEMBERS"], table.concat(keys(draft.characterMembers), "\n"),
            L["ACCOUNT_MEMBERS"], table.concat(keys(draft.accountMembers), "\n"),
            L["GUILD_RANK"], table.concat(keys(draft.guildRanks), ", "), help))
        local canEdit = self:CanEditMembers()
        self.addCharacterButton:SetEnabled(canEdit)
        self.addAccountButton:SetEnabled(canEdit)
        self.addRankButton:SetEnabled(canEdit)
        self.removeMembershipButton:SetEnabled(canEdit)
    elseif active == "PERMISSIONS" then
        self:EnsurePermissionChecks()
        local leadership = draft.id == Groups.systemIds.LEADERSHIP
        self.fullAccess:SetShown(leadership)
        for id, check in pairs(self.permissionChecks) do
            check:SetChecked(leadership or draft.permissions[id] == true)
            check:SetEnabled(self:CanEditPermissions())
        end
        local unknown = {}
        for id in pairs(draft.permissions or {}) do if not Registry:GetPermission(id) then unknown[#unknown + 1] = id end end
        table.sort(unknown)
        local text = L["FULL_ACCESS"] .. " — " .. L["FULL_ACCESS_HELP"]
        if #unknown > 0 then text = text .. "\n" .. L["UNKNOWN_PERMISSIONS"] .. ": " .. table.concat(unknown, ", ") end
        self.fullAccess:SetText(text)
    elseif active == "PERMISSION_MATRIX" then
        self:RefreshMatrix()
    elseif active == "RULES_FILTERS" then
        self.ruleList:Refresh()
        self.filterList:Refresh()
        self.filterMode:SetValue(draft.filterOperator, L["LOGIC_" .. draft.filterOperator])
        if self:CanEditMembers() then UIDropDownMenu_EnableDropDown(self.filterMode) else UIDropDownMenu_DisableDropDown(self.filterMode) end
    elseif active == "MANAGERS" then
        self.managerList:Refresh()
    elseif active == "EFFECTIVE_MEMBERS" then
        local lines = { L["NAME"] .. " | " .. L["GUILD_RANK"] .. " | " .. L["MAIN_TWINK"] .. " | " .. L["SOURCES"] }
        local query = string.lower(self.memberSearch:GetText() or "")
        for _, entry in ipairs(Engine:GetEffectiveMembers(draft.id)) do
            local searchable = string.lower((entry.name or "") .. " " .. (entry.rank or "") .. " " .. (entry.accountUUID or ""))
            if query == "" or searchable:find(query, 1, true) then
                local sources = {}
                for _, reason in ipairs(entry.reasons) do sources[#sources + 1] = HolyStorm.PolicyUI:DisplayMembershipReason(reason) end
                lines[#lines + 1] = string.format("%s | %s | %s | %s", entry.name, entry.rank or "-",
                    entry.isMain and L["MAIN"] or L["ALT"], table.concat(sources, ", "))
            end
        end
        if #lines == 1 then lines[#lines + 1] = L["EMPTY_MEMBERS"] end
        self.effectiveText:SetText(table.concat(lines, "\n"))
    elseif active == "MODULE_SETTINGS" then
        self:RefreshModules()
    elseif active == "ANALYSIS" then
        self:Analyze()
    elseif active == "STATUS" then
        local status = State:GetPermissionStateStatus()
        local statusLabel = L["STATE_" .. tostring(status.status)] or status.status or "-"
        local text = string.format(L["STATE_DETAILS_FORMAT"], tostring(status.guildId or "-"), statusLabel,
            status.version or 0, status.revisionID or "-", status.previousRevisionID or "-",
            tostring(status.lastSync or 0), tostring(status.changedBy and (status.changedBy.characterUUID or status.changedBy.accountUUID) or "-"),
            tostring(status.changedAt or "-"), status.historyLength or 0, status.rejectedLength or 0,
            tostring(status.missingRevisions and (status.missingRevisions.target or status.missingRevisions.after) or "-"),
            tostring(status.fork and (status.fork.remoteRevision or status.fork.reason) or "-"))
        if status.catchup then
            text = text .. "\n" .. string.format(L["CATCHUP_FORMAT"], tostring(status.catchup.requestedAfter or "-"),
                status.catchup.receivedCount or 0, status.catchup.validatedCount or 0, tostring(status.catchup.respondingPeer or "-"))
        end
        self.statusText:SetText(text)
    end
end

function Page:CommitEdits()
    if not self.draft or self.draft.system then return end
    self.draft.name = self.nameEdit:GetText()
    self.draft.nameKey = nil
    self.draft.description = self.descEdit:GetText()
end

function Page:Save()
    if not self.draft then return end
    if self.baseRevision ~= State:GetPermissionStateStatus().revisionID then
        HolyStorm.Events:Emit("HS_UI_STATUS_REQUESTED", L["STALE_EDITOR"])
        return
    end
    self:CommitEdits()
    local ok, result
    if self.isNew then
        ok, result = Groups:CreateGroup({ id = self.draft.id, name = self.draft.name, description = self.draft.description })
    else
        ok, result = Groups:SaveGroup(self.draft)
    end
    if ok then
        self:Select(Groups:GetGroup(self.draft.id))
        self:RefreshList()
        HolyStorm.Events:Emit("HS_UI_STATUS_REQUESTED", L["SAVED"])
    else
        HolyStorm.Events:Emit("HS_UI_STATUS_REQUESTED", self:ErrorMessage(result))
    end
end

function Page:RefreshMatrix()
    local matrix = Engine:GetPermissionMatrix()
    local query = string.lower(self.matrixSearch and self.matrixSearch:GetText() or "")
    local header = { L["PERMISSION_ID"], L["NAME"], L["MODULE"], L["DEFAULT_GROUPS"] }
    for _, id in ipairs(matrix.groupIds) do header[#header + 1] = HolyStorm.PolicyUI:DisplayGroupName(matrix.groups[id]) end
    local lines = { table.concat(header, " | ") }
    local firstVisible
    for _, row in ipairs(matrix.rows) do
        local definition = row.definition
        local name = L[definition.labelKey] or row.permissionId
        local description = L[definition.descriptionKey] or ""
        local searchable = string.lower(table.concat({ row.permissionId, name, description, definition.module or "", definition.category or "" }, " "))
        if query == "" or searchable:find(query, 1, true) then
            firstVisible = firstVisible or row.permissionId
            local defaultNames = {}
            for _, groupId in ipairs(matrix.groupIds) do
                if row.assignments[groupId].default then defaultNames[#defaultNames + 1] = HolyStorm.PolicyUI:DisplayGroupName(matrix.groups[groupId]) end
            end
            local values = { row.permissionId, name, definition.module or "-",
                #defaultNames > 0 and table.concat(defaultNames, ", ") or L["NONE"] }
            for _, groupId in ipairs(matrix.groupIds) do
                local assignment = row.assignments[groupId]
                values[#values + 1] = assignment.protected and L["MATRIX_FULL_ACCESS"]
                    or assignment.direct and L["MATRIX_ASSIGNED"] or L["MATRIX_EMPTY"]
            end
            lines[#lines + 1] = table.concat(values, " | ")
        end
    end
    if #lines == 1 then lines[#lines + 1] = L["EMPTY_PERMISSIONS"] end
    self.matrixText:SetText(table.concat(lines, "\n"))
    if not self.selectedPermissionId or not Registry:GetPermission(self.selectedPermissionId) then self.selectedPermissionId = firstVisible end
    local detail = self.selectedPermissionId and Engine:GetPermissionDetail(self.selectedPermissionId)
    if not detail then self.matrixDetail:SetText(L["NO_SELECTION"]); return end
    local definition = detail.definition
    self.matrixPermission:SetValue(detail.id, L[definition.labelKey] or detail.id)
    local function groupNames(ids)
        local names = {}
        for _, id in ipairs(ids or {}) do names[#names + 1] = HolyStorm.PolicyUI:DisplayGroupName(detail.groups[id]) end
        return #names > 0 and table.concat(names, ", ") or L["NONE"]
    end
    local categoryKey = "CATEGORY_" .. tostring(definition.category or "Core"):gsub("[^%w]", "_"):upper()
    self.matrixDetail:SetText(string.format(L["PERMISSION_DETAIL_FORMAT"], detail.id,
        L[definition.labelKey] or detail.id, L[definition.descriptionKey] or detail.id,
        definition.module or "-", L[categoryKey] or definition.category or "-",
        groupNames(detail.defaultGroupIds), groupNames(detail.directGroupIds),
        groupNames(detail.effectiveGroupIds), detail.available and L["ALLOWED"] or L["DENIED"]))
end

function Page:RefreshModules()
    self.moduleList:Refresh()
end

function Page:Analyze()
    if not self.analysisText or not self.draft then return end
    local guid = self.analysisGuid:GetText()
    if guid == "" then guid = UnitGUID("player") end
    local playerId = HolyStorm.Data.PlayerStore:GetCharacterOwner(guid) or guid
    local reasons = Engine:GetMembershipReasons(self.draft, playerId, guid)
    local lines = { HolyStorm.PolicyUI:DisplayGroupName(self.draft), L["CHARACTER_ID"] .. ": " .. tostring(guid) }
    for _, reason in ipairs(reasons) do lines[#lines + 1] = HolyStorm.PolicyUI:DisplayMembershipReason(reason) end
    if #reasons == 0 then lines[#lines + 1] = L["NONE"] end
    lines[#lines + 1] = "\n" .. L["PERMISSIONS"] .. ": " .. table.concat(keys(Engine:GetEffectivePermissions(playerId, guid)), ", ")
    self.analysisText:SetText(table.concat(lines, "\n"))
end

function Page:Render()
    if not self.page:IsShown() then return end
    self:RefreshList()
    local current = self.selectedId and Groups:GetGroup(self.selectedId)
    if self.selectedId and not current and not self.isNew then self:Select(nil)
    elseif current and not self.draft then self:Select(current)
    else self:RefreshDetails() end
    local valid = State:GetPermissionStateStatus().status == State.status.VALID
    self.newButton:SetEnabled(valid and self:CanMutate("groups-create"))
    self.duplicateButton:SetEnabled(valid and self.draft ~= nil and self:CanMutate("groups-create"))
    self.saveButton:SetEnabled(valid and self.draft ~= nil and (self:CanEditGroup() or self:CanEditMembers() or self:CanEditPermissions()))
    self.resetButton:SetEnabled(valid and self:CanMutate("permissions-reset"))
    self.readOnly:SetText(valid and "" or L["STATE_READ_ONLY"])
    if self.draft and self.baseRevision ~= State:GetPermissionStateStatus().revisionID then
        self.readOnly:SetText(L["STALE_EDITOR"])
        self.saveButton:SetEnabled(false)
    end
end

function Page:DeletionSummary(id)
    local impact = Groups:GetGroupDeletionImpact(id)
    if not impact then return L["NONE"] end
    return string.format(L["GROUP_DELETE_IMPACT"],
        impact.characterMembers + impact.accountMembers + impact.guildRanks,
        impact.filters, impact.rules, impact.permissions, #(impact.managerReferences or {}))
end

function Page:OnInitialize()
    local UI = HolyStorm:GetModule("UI", true)
    local page = CreateFrame("Frame", nil, UI.content)
    self.page = page
    local title = HolyStorm.PolicyUI:Label(page, L["PERMISSIONS_TITLE"], "GameFontHighlightLarge")
    title:SetPoint("TOPLEFT", 14, -12)
    self.search = HolyStorm.PolicyUI:Edit(page, 190, function() Page:RefreshList() end)
    self.search:SetPoint("TOPLEFT", 14, -42)
    local columns = HolyStorm.PolicyUI:Label(page, L["GROUP_COUNT_COLUMNS"])
    columns:SetPoint("TOPLEFT", 14, -67)
    self.list = HolyStorm.PolicyUI:CreateList(page, function(group) Page:Select(group) end)
    self.list:SetPoint("TOPLEFT", 14, -86)
    self.list:SetSize(200, 416)

    self.newButton = HolyStorm.PolicyUI:Button(page, L["NEW"], 62, function()
        Page:Select({ id = HolyStorm.PolicyUI:NewId("group"), name = L["CUSTOM_GROUP"], description = "",
            permissions = {}, characterMembers = {}, accountMembers = {}, guildRanks = {},
            ruleIds = {}, filterIds = {}, managerGroupIds = {}, filterOperator = "AND" })
    end)
    self.newButton:SetPoint("BOTTOMLEFT", 14, 50)
    self.duplicateButton = HolyStorm.PolicyUI:Button(page, L["DUPLICATE"], 90, function()
        if not Page.draft then return end
        Page:Select({ id = HolyStorm.PolicyUI:NewId("group"),
            name = HolyStorm.PolicyUI:DisplayGroupName(Page.draft) .. " " .. L["COPY_SUFFIX"],
            description = Page.draft.description or "", permissions = {}, characterMembers = {},
            accountMembers = {}, guildRanks = {}, ruleIds = {}, filterIds = {}, managerGroupIds = {},
            filterOperator = "AND" })
    end)
    self.duplicateButton:SetPoint("LEFT", self.newButton, "RIGHT", 4, 0)
    self.deleteButton = HolyStorm.PolicyUI:Button(page, L["DELETE"], 70, function()
        if Page.draft then
            StaticPopup_Show("HOLYSTORM_GROUP_DELETE", HolyStorm.PolicyUI:DisplayGroupName(Page.draft),
                Page:DeletionSummary(Page.draft.id), Page.draft.id)
        end
    end)
    self.deleteButton:SetPoint("TOPLEFT", 14, -530)
    self.deleteButton:SetEnabled(false)

    self.empty = HolyStorm.PolicyUI:Label(page, L["NO_SELECTION"], "GameFontHighlight")
    self.empty:SetPoint("TOPLEFT", 235, -100)
    self.tabFrames, self.tabButtons = {}, {}
    for index, id in ipairs(tabs) do
        local tabId = id
        local button = HolyStorm.PolicyUI:Button(page, L[tabId], 122, function() Page:ShowTab(tabId) end)
        button:SetPoint("TOPLEFT", 220 + ((index - 1) % 5) * 124, -42 - math.floor((index - 1) / 5) * 27)
        self.tabButtons[tabId] = button
        local frame = CreateFrame("Frame", nil, page)
        frame:SetPoint("TOPLEFT", 225, -102)
        frame:SetPoint("BOTTOMRIGHT", -14, 82)
        frame:Hide()
        self.tabFrames[tabId] = frame
    end

    local general = self.tabFrames.GENERAL
    local nameLabel = HolyStorm.PolicyUI:Label(general, L["NAME"]); nameLabel:SetPoint("TOPLEFT")
    self.nameEdit = HolyStorm.PolicyUI:Edit(general, 300); self.nameEdit:SetPoint("TOPLEFT", 0, -20)
    local descriptionLabel = HolyStorm.PolicyUI:Label(general, L["DESCRIPTION"]); descriptionLabel:SetPoint("TOPLEFT", 0, -55)
    self.descEdit = HolyStorm.PolicyUI:Edit(general, 500); self.descEdit:SetPoint("TOPLEFT", 0, -75)
    self.generalInfo = HolyStorm.PolicyUI:Label(general, ""); self.generalInfo:SetPoint("TOPLEFT", 0, -115)

    local members = self.tabFrames.MEMBERS
    self.memberText = HolyStorm.PolicyUI:Label(members, ""); self.memberText:SetPoint("TOPLEFT"); self.memberText:SetPoint("RIGHT")
    self.characterSelector = HolyStorm.PolicyUI:CreateSelector(members, 210, function() return HolyStorm.PolicyUI:CharacterItems() end)
    self.characterSelector:SetPoint("BOTTOMLEFT", -15, 8)
    self.addCharacterButton = HolyStorm.PolicyUI:Button(members, L["ADD_CHARACTER"], 125, function()
        local id = Page.characterSelector:GetValue()
        if Page.draft and id and Page:CanEditMembers() then Page.draft.characterMembers[id] = true; Page:RefreshDetails() end
    end)
    self.addCharacterButton:SetPoint("LEFT", self.characterSelector, "RIGHT", -12, 0)
    self.accountSelector = HolyStorm.PolicyUI:CreateSelector(members, 210, function() return HolyStorm.PolicyUI:AccountItems() end)
    self.accountSelector:SetPoint("LEFT", self.addCharacterButton, "RIGHT", -12, 0)
    self.addAccountButton = HolyStorm.PolicyUI:Button(members, L["ADD_ACCOUNT"], 115, function()
        local id = Page.accountSelector:GetValue()
        if Page.draft and id and Page:CanEditMembers() then Page.draft.accountMembers[id] = true; Page:RefreshDetails() end
    end)
    self.addAccountButton:SetPoint("LEFT", self.accountSelector, "RIGHT", -12, 0)
    self.removeSource = HolyStorm.PolicyUI:CreateSelector(members, 210, function()
        local out = {}
        if Page.draft then
            for id in pairs(Page.draft.characterMembers) do out[#out + 1] = { value = "character\031" .. id, label = L["MANUAL"] .. ": " .. id } end
            for id in pairs(Page.draft.accountMembers) do out[#out + 1] = { value = "account\031" .. id, label = L["MANUAL"] .. ": " .. id } end
            for id in pairs(Page.draft.guildRanks) do out[#out + 1] = { value = "guild-rank\031" .. id, label = L["GUILD_RANK"] .. ": " .. id } end
        end
        return out
    end)
    self.removeSource:SetPoint("BOTTOMLEFT", -15, -22)
    self.removeMembershipButton = HolyStorm.PolicyUI:Button(members, L["REMOVE_SOURCE"], 145, function()
        local source, id = tostring(Page.removeSource:GetValue() or ""):match("^(.-)\031(.+)$")
        if Page.draft and source and Page:CanEditMembers() then
            local map = source == "character" and Page.draft.characterMembers
                or source == "account" and Page.draft.accountMembers or Page.draft.guildRanks
            map[tonumber(id) or id] = nil
            Page:RefreshDetails()
        end
    end)
    self.removeMembershipButton:SetPoint("LEFT", self.removeSource, "RIGHT", -12, 0)
    self.rankSelector = HolyStorm.PolicyUI:CreateSelector(members, 180, function()
        local out, guild = {}, HolyStorm.Data.GuildStore:GetCurrent()
        for index, name in pairs(guild and guild.ranks or {}) do out[#out + 1] = { value = index - 1, label = name } end
        return out
    end)
    self.rankSelector:SetPoint("LEFT", self.removeMembershipButton, "RIGHT", -12, 0)
    self.addRankButton = HolyStorm.PolicyUI:Button(members, L["ADD_GUILD_RANK"], 120, function()
        local rank = Page.rankSelector:GetValue()
        if Page.draft and rank ~= nil and Page:CanEditMembers() then Page.draft.guildRanks[rank] = true; Page:RefreshDetails() end
    end)
    self.addRankButton:SetPoint("LEFT", self.rankSelector, "RIGHT", -12, 0)

    local permissions = self.tabFrames.PERMISSIONS
    self.permissionSearch = HolyStorm.PolicyUI:Edit(permissions, 240, function() Page:EnsurePermissionChecks(); Page:RefreshDetails() end)
    self.permissionSearch:SetPoint("TOPLEFT")
    local permissionScroll = CreateFrame("ScrollFrame", nil, permissions, "UIPanelScrollFrameTemplate")
    permissionScroll:SetPoint("TOPLEFT", 0, -28); permissionScroll:SetPoint("BOTTOMRIGHT", -28, 26)
    self.permissionsFrame = CreateFrame("Frame", nil, permissionScroll); self.permissionsFrame:SetSize(680, 1000)
    permissionScroll:SetScrollChild(self.permissionsFrame)
    self.permissionChecks = {}
    self.fullAccess = HolyStorm.PolicyUI:Label(permissions, L["FULL_ACCESS"] .. " — " .. L["FULL_ACCESS_HELP"])
    self.fullAccess:SetPoint("BOTTOMLEFT")
    self:EnsurePermissionChecks()

    local rulesFilters = self.tabFrames.RULES_FILTERS
    local rulesLabel = HolyStorm.PolicyUI:Label(rulesFilters, L["RULES_TITLE"]); rulesLabel:SetPoint("TOPLEFT")
    self.ruleList = HolyStorm.PolicyUI:CreateCheckList(rulesFilters, function()
        local out = {}
        for id, rule in pairs(Filters:GetRules("global")) do
            out[#out + 1] = { value = id, label = rule.name,
                checked = Page.draft and arrayContains(Page.draft.ruleIds, id), disabled = not Page:CanEditMembers() }
        end
        table.sort(out, function(left, right) return left.label < right.label end)
        return out
    end, function(id, checked)
        if Page.draft and Page:CanEditMembers() then Page.draft.ruleIds = setArrayValue(Page.draft.ruleIds, id, checked) end
    end)
    self.ruleList:SetPoint("TOPLEFT", 0, -25); self.ruleList:SetSize(300, 400)
    local filtersLabel = HolyStorm.PolicyUI:Label(rulesFilters, L["FILTERS_TITLE"]); filtersLabel:SetPoint("TOPLEFT", 330, 0)
    self.filterMode = HolyStorm.PolicyUI:CreateSelector(rulesFilters, 130, function()
        return { { value = "AND", label = L["LOGIC_AND"] }, { value = "OR", label = L["LOGIC_OR"] } }
    end, function(value) if Page.draft and Page:CanEditMembers() then Page.draft.filterOperator = value end end)
    self.filterMode:SetPoint("TOPLEFT", 315, -18)
    self.filterList = HolyStorm.PolicyUI:CreateCheckList(rulesFilters, function()
        local out = {}
        for id, filter in pairs(Filters:GetFilters("global")) do
            out[#out + 1] = { value = id, label = filter.name,
                checked = Page.draft and arrayContains(Page.draft.filterIds, id), disabled = not Page:CanEditMembers() }
        end
        table.sort(out, function(left, right) return left.label < right.label end)
        return out
    end, function(id, checked)
        if Page.draft and Page:CanEditMembers() then Page.draft.filterIds = setArrayValue(Page.draft.filterIds, id, checked) end
    end)
    self.filterList:SetPoint("TOPLEFT", 330, -62); self.filterList:SetSize(300, 365)

    local managers = self.tabFrames.MANAGERS
    local managersLabel = HolyStorm.PolicyUI:Label(managers, L["MANAGER_GROUPS"]); managersLabel:SetPoint("TOPLEFT")
    local managerHelp = HolyStorm.PolicyUI:Label(managers, L["MANAGEMENT_HELP"])
    managerHelp:SetPoint("TOPLEFT", 0, -24); managerHelp:SetPoint("RIGHT")
    self.managerList = HolyStorm.PolicyUI:CreateCheckList(managers, function()
        local out = {}
        for _, item in ipairs(HolyStorm.PolicyUI:GroupItems(Page.draft and Page.draft.id)) do
            item.checked = Page.draft and arrayContains(Page.draft.managerGroupIds, item.value)
            item.disabled = item.disabled or Page.draft.system or not Page:CanEditGroup()
            out[#out + 1] = item
        end
        return out
    end, function(id, checked)
        if Page.draft and not Page.draft.system and Page:CanEditGroup() then Page.draft.managerGroupIds = setArrayValue(Page.draft.managerGroupIds, id, checked) end
    end)
    self.managerList:SetPoint("TOPLEFT", 0, -55)

    self.memberSearch = HolyStorm.PolicyUI:Edit(self.tabFrames.EFFECTIVE_MEMBERS, 240, function() Page:RefreshDetails() end)
    self.memberSearch:SetPoint("TOPLEFT")
    local effectiveScroll, effectiveText = HolyStorm.PolicyUI:CreateTextPanel(self.tabFrames.EFFECTIVE_MEMBERS)
    effectiveScroll:SetPoint("TOPLEFT", 0, -30); effectiveScroll:SetPoint("BOTTOMRIGHT")
    self.effectiveText = effectiveText

    local matrix = self.tabFrames.PERMISSION_MATRIX
    self.matrixSearch = HolyStorm.PolicyUI:Edit(matrix, 230, function() Page:RefreshMatrix() end)
    self.matrixSearch:SetPoint("TOPLEFT")
    self.matrixPermission = HolyStorm.PolicyUI:CreateSelector(matrix, 300, function()
        local out = {}
        for id, definition in pairs(Registry:GetPermissions()) do out[#out + 1] = { value = id, label = L[definition.labelKey] or id } end
        table.sort(out, function(left, right) return left.label < right.label end)
        return out
    end, function(id) Page.selectedPermissionId = id; Page:RefreshMatrix() end)
    self.matrixPermission:SetPoint("TOPLEFT", 230, 16)
    local matrixScroll, matrixText = HolyStorm.PolicyUI:CreateTextPanel(matrix)
    matrixScroll:SetPoint("TOPLEFT", 0, -30); matrixScroll:SetPoint("BOTTOMRIGHT", -28, 112)
    self.matrixText = matrixText
    self.matrixDetail = HolyStorm.PolicyUI:Label(matrix, "")
    self.matrixDetail:SetPoint("BOTTOMLEFT", 0, 0); self.matrixDetail:SetPoint("RIGHT"); self.matrixDetail:SetJustifyV("BOTTOM")

    local moduleHelp = HolyStorm.PolicyUI:Label(self.tabFrames.MODULE_SETTINGS, L["MODULE_MODEL_HELP"])
    moduleHelp:SetPoint("TOPLEFT"); moduleHelp:SetPoint("RIGHT")
    self.moduleList = HolyStorm.PolicyUI:CreateCheckList(self.tabFrames.MODULE_SETTINGS, function()
        local out = {}
        for _, metadata in ipairs(HolyStorm:GetModuleEntries()) do
            local id = metadata and metadata.internalName
            if id and metadata.category == "optional" then
                out[#out + 1] = { value = id, label = metadata.displayName or id,
                    checked = State:IsGuildModuleEnabled(id), disabled = not Page:CanMutate("modules-manage") }
            end
        end
        return out
    end, function(id, checked)
        local ok, reason = State:SetGuildModuleEnabled(id, checked)
        if not ok then HolyStorm.Events:Emit("HS_UI_STATUS_REQUESTED", Page:ErrorMessage(reason)) end
    end)
    self.moduleList:SetPoint("TOPLEFT", 0, -38)

    local analysis = self.tabFrames.ANALYSIS
    self.analysisGuid = HolyStorm.PolicyUI:Edit(analysis, 300); self.analysisGuid:SetPoint("TOPLEFT")
    local analyze = HolyStorm.PolicyUI:Button(analysis, L["ANALYSIS"], 90, function() Page:Analyze() end)
    analyze:SetPoint("LEFT", self.analysisGuid, "RIGHT", 5, 0)
    self.analysisText = HolyStorm.PolicyUI:Label(analysis, ""); self.analysisText:SetPoint("TOPLEFT", 0, -38); self.analysisText:SetPoint("RIGHT")
    self.statusText = HolyStorm.PolicyUI:Label(self.tabFrames.STATUS, ""); self.statusText:SetPoint("TOPLEFT"); self.statusText:SetPoint("RIGHT")

    self.saveButton = HolyStorm.PolicyUI:Button(page, L["SAVE"], 100, function() Page:Save() end)
    self.saveButton:SetPoint("BOTTOMRIGHT", -120, 18)
    local discard = HolyStorm.PolicyUI:Button(page, L["DISCARD"], 100, function()
        Page:Select(Page.selectedId and Groups:GetGroup(Page.selectedId))
        HolyStorm.Events:Emit("HS_UI_STATUS_REQUESTED", L["DISCARDED"])
    end)
    discard:SetPoint("LEFT", self.saveButton, "RIGHT", 6, 0)
    self.resetButton = HolyStorm.PolicyUI:Button(page, L["RESTORE_DEFAULTS"], 150, function()
        StaticPopup_Show("HOLYSTORM_PERMISSION_RESET")
    end)
    self.resetButton:SetPoint("BOTTOMLEFT", 225, 18)
    self.readOnly = HolyStorm.PolicyUI:Label(page, ""); self.readOnly:SetPoint("BOTTOMLEFT", 225, 48); self.readOnly:SetPoint("RIGHT", -14, 0)

    StaticPopupDialogs["HOLYSTORM_PERMISSION_RESET"] = {
        text = L["CONFIRM_PERMISSION_RESET"], button1 = L["YES"], button2 = L["NO"],
        OnAccept = function()
            local ok, reason = State:RestoreDefaults()
            HolyStorm.Events:Emit("HS_UI_STATUS_REQUESTED", ok and L["RESET_COMPLETE"] or Page:ErrorMessage(reason))
            Page:Render()
        end,
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }
    StaticPopupDialogs["HOLYSTORM_GROUP_DELETE"] = {
        text = L["CONFIRM_GROUP_DELETE"], button1 = L["DELETE"], button2 = L["NO"],
        OnAccept = function(_, id)
            local ok, reason = Groups:DeleteGroup(id)
            if ok then Page:Select(nil); Page:RefreshList()
            else HolyStorm.Events:Emit("HS_UI_STATUS_REQUESTED", Page:ErrorMessage(reason)) end
        end,
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }

    self.activeTab = "GENERAL"
    HolyStorm.Administration:RegisterSection({
        id = "permissions", category = "permissions",
        displayName = L["PERMISSIONS_TITLE"], displayNameKey = "PERMISSIONS_TITLE",
        description = L["PERMISSIONS_DESC"], descriptionKey = "PERMISSIONS_DESC", order = 10,
        requiredPermission = { "groups-create", "groups-edit", "groups-delete", "groups-manage-members",
            "permissions-manage", "permissions-reset", "modules-manage", "policy-inspect" },
        owner = "Core", page = page, icon = "Interface\\Icons\\Achievement_GuildPerk_EverybodysFriend",
        refresh = function() Page:Render() end,
        events = { "HS_GROUP_UPDATED", "HS_GROUP_DELETED", "HS_EFFECTIVE_MEMBERSHIP_CHANGED",
            "HS_EFFECTIVE_PERMISSIONS_CHANGED", "HS_FILTER_UPDATED", "HS_FILTER_DELETED",
            "HS_RULE_UPDATED", "HS_RULE_DELETED", "HS_PERMISSION_REGISTERED", "HS_PERMISSIONS_STATE_UPDATED",
            "HS_PERMISSIONS_CATCHUP_STARTED", "HS_PERMISSIONS_CATCHUP_COMPLETED",
            "HS_PERMISSIONS_RECOVERY_REQUIRED", "HS_PERMISSIONS_CONFLICT_DETECTED",
            "HS_ROSTER_UPDATED", "HS_CHARACTER_UPDATED" },
    })
end
