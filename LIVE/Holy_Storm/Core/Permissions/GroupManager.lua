local addonVersion = "5.1.0"
local HolyStorm = LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local Core = HolyStorm.PermissionCore
local Groups = { version=addonVersion, systemIds={LEADERSHIP="guild-leadership",OFFICERS="officers",MEMBER="guild-member"} }
Groups.systemIds.GUILD_MASTER = Groups.systemIds.LEADERSHIP
Groups.systemIds.USERS = Groups.systemIds.MEMBER

local function normalizeRanks(value)
    local result = {}
    for rank, enabled in pairs(type(value) == "table" and value or {}) do
        if enabled == true and tonumber(rank) then result[tonumber(rank)] = true end
    end
    return result
end

function Groups:GetDefaultGroups()
    local ids = self.systemIds
    local function permissionsFor(groupId)
        local permissions = {}
        for id, definition in pairs(HolyStorm.PermissionRegistry.keys) do
            if definition.defaults and definition.defaults[groupId] == true then permissions[id] = true end
        end
        return permissions
    end
    local defaults = {
        [ids.LEADERSHIP]={id=ids.LEADERSHIP,nameKey="GROUP_GUILD_LEADERSHIP",descriptionKey="GROUP_DESC_GUILD_LEADERSHIP",creator="System",system=true,systemRule="GUILD_LEADER",permissions={},characterMembers={},accountMembers={},guildRanks={},filterIds={},ruleIds={},filterOperator="AND",managerGroupIds={}},
        [ids.OFFICERS]={id=ids.OFFICERS,nameKey="GROUP_OFFICERS",descriptionKey="GROUP_DESC_OFFICERS",creator="System",system=true,systemRule="OFFICER",permissions={},characterMembers={},accountMembers={},guildRanks={},filterIds={},ruleIds={},filterOperator="AND",managerGroupIds={ids.LEADERSHIP}},
        [ids.MEMBER]={id=ids.MEMBER,nameKey="GROUP_GUILD_MEMBER",descriptionKey="GROUP_DESC_GUILD_MEMBER",creator="System",system=true,systemRule="GUILD_MEMBER",permissions={},characterMembers={},accountMembers={},guildRanks={},filterIds={},ruleIds={},filterOperator="AND",managerGroupIds={ids.LEADERSHIP}},
    }
    for _, group in pairs(defaults) do group.permissions = permissionsFor(group.id == ids.OFFICERS and "officers" or group.id == ids.MEMBER and "member" or "leadership") end
    return defaults
end

function Groups:ApplyRegisteredDefaults(state, definition)
    if not state or not definition or type(definition.defaults) ~= "table" then return end
    for groupId, enabled in pairs(definition.defaults) do
        local group = state.groups and state.groups[groupId]
        if enabled == true and group and type(group.permissions) == "table" and group.permissions[definition.id] == nil then group.permissions[definition.id] = true end
    end
end

function Groups:NormalizeGroup(group, current)
    if type(group) ~= "table" or not Core.ValidId(group.id) then return nil, "INVALID_GROUP" end
    local result = Core.Copy(group)
    result.name = type(result.name) == "string" and result.name or result.id
    result.description = type(result.description) == "string" and result.description or ""
    result.permissions = Core.NormalizeSet(result.permissions)
    for old, new in pairs(HolyStorm.PermissionRegistry.legacyIds) do if result.permissions[old] then result.permissions[old]=nil; result.permissions[new]=true end end
    result.characterMembers = Core.NormalizeSet(result.characterMembers)
    result.accountMembers = Core.NormalizeSet(result.accountMembers)
    result.guildRanks = normalizeRanks(result.guildRanks or result.rankRules)
    result.filterIds = Core.NormalizeArray(result.filterIds)
    result.ruleIds = Core.NormalizeArray(result.ruleIds)
    result.managerGroupIds = Core.NormalizeArray(result.managerGroupIds)
    result.filterOperator = result.filterOperator == "OR" and "OR" or "AND"
    result.createdAt = current and current.createdAt or tonumber(result.createdAt) or Core.Now()
    result.creator = current and current.creator or result.creator or (UnitGUID("player") or "System")
    result.modifiedAt = current and current.modifiedAt or tonumber(result.modifiedAt) or Core.Now()
    result.modifiedBy = current and current.modifiedBy or result.modifiedBy or UnitGUID("player")
    result.manual, result.rankRules = nil, nil
    return result
end

function Groups:MigrateLegacyGroups(groups)
    local defaults = self:GetDefaultGroups()
    local aliases = {SYSTEM_GUILD_MASTER=self.systemIds.LEADERSHIP,guild_leader=self.systemIds.LEADERSHIP,SYSTEM_OFFICERS=self.systemIds.OFFICERS,SYSTEM_USERS=self.systemIds.MEMBER,users=self.systemIds.MEMBER}
    local migrated = Core.Copy(defaults)
    for oldId, group in pairs(type(groups) == "table" and groups or {}) do
        local id = aliases[oldId] or oldId
        if type(group) == "table" then
            local candidate
            if defaults[id] then
                candidate = Core.Copy(migrated[id])
                if id ~= self.systemIds.LEADERSHIP then
                    candidate.permissions = {}
                    for permission, enabled in pairs(group.permissions or {}) do if enabled and permission ~= "*" then candidate.permissions[HolyStorm.PermissionRegistry:NormalizePermissionId(permission)] = true end end
                end
            else
                candidate = Core.Copy(group); candidate.id=id; candidate.system=false; candidate.systemRule=nil; candidate.nameKey=nil; candidate.creator=candidate.createdBy or candidate.creator or "Legacy"
            end
            candidate.characterMembers = candidate.characterMembers or {}; candidate.accountMembers = candidate.accountMembers or {}
            for subject, enabled in pairs(group.manual or {}) do
                if enabled then
                    local account = HolyStorm.TwinkCore and HolyStorm.TwinkCore:GetAccount(subject)
                    if account then candidate.accountMembers[subject]=true else candidate.characterMembers[subject]=true end
                end
            end
            candidate.guildRanks = candidate.guildRanks or group.rankRules or {}
            local normalized = self:NormalizeGroup(candidate, defaults[id])
            if normalized then
                if defaults[id] then normalized.system=true; normalized.systemRule=defaults[id].systemRule; normalized.nameKey=defaults[id].nameKey; normalized.descriptionKey=defaults[id].descriptionKey; normalized.creator="System" end
                migrated[id] = normalized
            end
        end
    end
    return migrated
end

function Groups:EnsureSystemGroups(state)
    local defaults = self:GetDefaultGroups()
    for id, definition in pairs(defaults) do
        local existing = state.groups[id]
        if not existing then state.groups[id] = Core.Copy(definition) else
            existing.id=id; existing.system=true; existing.systemRule=definition.systemRule; existing.nameKey=definition.nameKey; existing.descriptionKey=definition.descriptionKey; existing.creator="System"
            existing.permissions=type(existing.permissions)=="table" and existing.permissions or Core.Copy(definition.permissions)
            existing.characterMembers=type(existing.characterMembers)=="table" and existing.characterMembers or {}; existing.accountMembers=type(existing.accountMembers)=="table" and existing.accountMembers or {}; existing.guildRanks=type(existing.guildRanks)=="table" and existing.guildRanks or {}
            existing.filterIds=type(existing.filterIds)=="table" and existing.filterIds or {}; existing.ruleIds=type(existing.ruleIds)=="table" and existing.ruleIds or {}; existing.managerGroupIds=type(existing.managerGroupIds)=="table" and existing.managerGroupIds or Core.Copy(definition.managerGroupIds)
        end
    end
    for id, group in pairs(state.groups) do if group.system and not defaults[id] then group.system=false; group.systemRule=nil; group.nameKey=nil end end
end

function Groups:ValidateGroup(group, snapshot)
    if type(group)~="table" or not Core.ValidId(group.id) or type(group.name or group.nameKey)~="string" or (group.description~=nil and type(group.description)~="string") or type(group.permissions)~="table" or type(group.characterMembers)~="table" or type(group.accountMembers)~="table" or type(group.guildRanks)~="table" or type(group.filterIds)~="table" or type(group.ruleIds)~="table" or type(group.managerGroupIds)~="table" then return false,"INVALID_GROUP" end
    if not group.nameKey and (#group.name==0 or #group.name>128) then return false,"INVALID_GROUP_NAME" end
    if #(group.description or "")>1024 then return false,"INVALID_GROUP_DESCRIPTION" end
    if HolyStorm.Utils.TableCount(group.characterMembers)+HolyStorm.Utils.TableCount(group.accountMembers)+HolyStorm.Utils.TableCount(group.guildRanks)>500 then return false,"TOO_MANY_MEMBERSHIPS" end
    for permission,value in pairs(group.permissions) do if value~=true or type(permission)~="string" or not Core.ValidId(permission) then return false,"INVALID_PERMISSION:"..tostring(permission) end end
    for subject,value in pairs(group.characterMembers) do if not Core.ValidId(subject) or value~=true then return false,"INVALID_CHARACTER_MEMBERSHIP" end end
    for subject,value in pairs(group.accountMembers) do if not Core.ValidId(subject) or value~=true then return false,"INVALID_ACCOUNT_MEMBERSHIP" end end
    for rank,value in pairs(group.guildRanks) do if tonumber(rank)==nil or value~=true then return false,"INVALID_GUILD_RANK" end end
    for _,id in ipairs(group.filterIds) do if not snapshot.filters[id] then return false,"MISSING_FILTER:"..id end end
    for _,id in ipairs(group.ruleIds) do if not snapshot.rules[id] then return false,"MISSING_RULE:"..id end end
    for _,id in ipairs(group.managerGroupIds) do if id==group.id or not snapshot.groups[id] then return false,"INVALID_MANAGER:"..id end end
    return true
end
function Groups:HasManagerCycle(groups)
    local visiting, done = {}, {}
    local function visit(id)
        if visiting[id] then return true end; if done[id] then return false end; visiting[id]=true
        for _, manager in ipairs(groups[id] and groups[id].managerGroupIds or {}) do if visit(manager) then return true end end
        visiting[id]=nil; done[id]=true; return false
    end
    for id in pairs(groups) do if visit(id) then return true end end
    return false
end

function Groups:GetGroups() return Core.Copy(self:GetStore("groups") or {}) end
function Groups:GetGroup(id) local group=(self:GetStore("groups") or {})[id]; return group and Core.Copy(group) end
function Groups:CreateGroup(definition)
    local id=definition and definition.id or string.format("group-%x-%x",Core.Now(),math.random(0,0x7fffffff))
    local group,err=self:NormalizeGroup({id=id,name=definition and definition.name or id,description=definition and definition.description or "",permissions=definition and definition.permissions or {},characterMembers={},accountMembers={},guildRanks={},filterIds={},ruleIds={},managerGroupIds={},filterOperator="AND",creator=UnitGUID("player")})
    if not group then return false,err end
    local ok,result=self:CommitChange({action="GROUP_UPSERT",group=group}); if ok then Core.Log("INFO","groups","Group created",{groupId=group.id}) end; return ok,result
end
function Groups:SaveGroup(group)
    local current=self:GetGroup(group and group.id); local normalized,err=self:NormalizeGroup(group,current); if not normalized then return false,err end
    if current and Core.Same(normalized,current) then return false,"UNCHANGED" end
    normalized.modifiedAt=Core.Now(); normalized.modifiedBy=UnitGUID("player")
    local ok,result=self:CommitChange({action="GROUP_UPSERT",group=normalized}); if ok then Core.Log("INFO","groups","Group changed",{groupId=normalized.id}) end; return ok,ok and self:GetGroup(normalized.id) or result
end
function Groups:UpdateGroup(id,changes)
    local group=self:GetGroup(id); if not group then return false,"NOT_FOUND" end
    for key,value in pairs(changes or {}) do if key~="id" and key~="system" and key~="systemRule" then group[key]=Core.Copy(value) end end
    return self:SaveGroup(group)
end
function Groups:GetGroupUsage(id)
    local usage={}; for groupId,group in pairs(self:GetStore("groups") or {}) do for _,managerId in ipairs(group.managerGroupIds or {}) do if managerId==id then usage[#usage+1]={kind="manager",id=groupId} end end end; return usage
end
function Groups:DeleteGroup(id) if #self:GetGroupUsage(id)>0 then return false,"GROUP_IN_USE" end; local ok,result=self:CommitChange({action="GROUP_DELETE",groupId=id}); if ok then Core.Log("INFO","groups","Group deleted",{groupId=id}) end; return ok,result end
function Groups:AddMembership(groupId,source,id)
    if source=="system" then return false,"SYSTEM_MEMBERSHIP" end
    if source=="filter" then return self:AttachFilter(groupId,id) end
    local group=self:GetGroup(groupId); if not group then return false,"NOT_FOUND" end
    local map=source=="character" and group.characterMembers or source=="account" and group.accountMembers or (source=="guildRank" or source=="guild-rank") and group.guildRanks
    if not map then return false,"INVALID_MEMBERSHIP_SOURCE" end
    local key=(source=="guildRank" or source=="guild-rank") and tonumber(id) or id; if key==nil then return false,"INVALID_MEMBERSHIP" end
    if map[key] then return false,"UNCHANGED" end; map[key]=true; local ok,result=self:SaveGroup(group); if ok then Core.Log("INFO","membership","Membership added",{groupId=groupId,source=source,id=id}) end; return ok,result
end
function Groups:RemoveMembership(groupId,source,id)
    if source=="system" then return false,"SYSTEM_MEMBERSHIP" end
    if source=="filter" then return self:DetachFilter(groupId,id) end
    local group=self:GetGroup(groupId); if not group then return false,"NOT_FOUND" end
    local map=source=="character" and group.characterMembers or source=="account" and group.accountMembers or (source=="guildRank" or source=="guild-rank") and group.guildRanks
    if not map then return false,"INVALID_MEMBERSHIP_SOURCE" end
    local key=(source=="guildRank" or source=="guild-rank") and tonumber(id) or id; if not map[key] then return false,"UNCHANGED" end; map[key]=nil; local ok,result=self:SaveGroup(group); if ok then Core.Log("INFO","membership","Membership removed",{groupId=groupId,source=source,id=id}) end; return ok,result
end
function Groups:AddCharacterMembership(groupId,id) return self:AddMembership(groupId,"character",id) end
function Groups:AddAccountMembership(groupId,id) return self:AddMembership(groupId,"account",id) end
function Groups:AddGuildRankMembership(groupId,id) return self:AddMembership(groupId,"guildRank",id) end
function Groups:SetGroupPermissions(groupId,permissions) local group=self:GetGroup(groupId); if not group then return false,"NOT_FOUND" end; group.permissions=Core.NormalizeSet(permissions); return self:SaveGroup(group) end
function Groups:SetGroupManagers(groupId,managerIds) local group=self:GetGroup(groupId); if not group then return false,"NOT_FOUND" end; group.managerGroupIds=Core.NormalizeArray(managerIds); return self:SaveGroup(group) end
function Groups:AddManagerGroup(groupId,managerId) local group=self:GetGroup(groupId); if not group then return false,"NOT_FOUND" end; if Core.ArrayContains(group.managerGroupIds,managerId) then return false,"UNCHANGED" end; group.managerGroupIds[#group.managerGroupIds+1]=managerId; return self:SaveGroup(group) end
function Groups:RemoveManagerGroup(groupId,managerId) local group=self:GetGroup(groupId); if not group then return false,"NOT_FOUND" end; local nextIds={}; for _,id in ipairs(group.managerGroupIds) do if id~=managerId then nextIds[#nextIds+1]=id end end; if #nextIds==#group.managerGroupIds then return false,"UNCHANGED" end; group.managerGroupIds=nextIds; return self:SaveGroup(group) end

HolyStorm.PermissionComponents = HolyStorm.PermissionComponents or {}
HolyStorm.PermissionComponents.Groups = Groups
