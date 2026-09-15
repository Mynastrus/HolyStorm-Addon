local addonVersion = "5.0.1"
local HolyStorm = LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local Core = HolyStorm.PermissionCore
local State = {
    version=addonVersion,
    status={VALID="VALID",CATCHING_UP="CATCHING_UP",RECOVERY_REQUIRED="RECOVERY_REQUIRED",CONFLICT="CONFLICT",UNINITIALIZED="UNINITIALIZED"},
    maxHistory=100,maxRejected=100,maxObjects=500,sequence=0,
}

function State:GetGuildId()
    local guild=HolyStorm.Data.GuildStore:GetCurrent()
    return guild and guild.id or (HolyStorm.Data.GuildStore.GetGuildId and HolyStorm.Data.GuildStore:GetGuildId())
end
function State:GetStates()
    local global=HolyStorm.db.global; global.permissionStates=type(global.permissionStates)=="table" and global.permissionStates or {}; return global.permissionStates
end
function State:GetState(guildId) return self:GetStates()[guildId or self:GetGuildId()] end
function State:GetStateStore()
    local state=self:GetState(); return state and {groups=state.groups,roles=state.groups,version=state.version} or {groups={},roles={},version=0}
end
function State:GetStore(kind,scope)
    if scope=="local" then
        if kind=="rules" then return HolyStorm.db.profile.rules.localRules elseif kind=="filters" then return HolyStorm.db.profile.filters.localFilters end
    end
    local state=self:GetState(); if state and state[kind] then return state[kind] end
    if kind=="groups" then return {} elseif kind=="rules" then return HolyStorm.db.global.rules.global elseif kind=="filters" then return HolyStorm.db.global.filters.global end
end
function State:NewRevisionId(guildId,version)
    self.sequence=self.sequence+1
    local actor=UnitGUID("player") or "unknown"
    return string.format("rev-%s-%d-%x-%x",tostring(guildId):gsub("[^%w]","_"),version,Core.Now()%0x7fffffff,(self.sequence+math.random(0,0x7fffffff))%0x7fffffff).."-"..actor
end
function State:BindCompatibility(state)
    HolyStorm.db.global.permissions.groups=state.groups
    HolyStorm.db.global.permissions.roles=state.groups
    HolyStorm.db.global.permissions.version=state.version
    HolyStorm.db.global.filters.global=state.filters
    HolyStorm.db.global.rules.global=state.rules
end
function State:Snapshot(state) return {groups=Core.Copy(state.groups),filters=Core.Copy(state.filters),rules=Core.Copy(state.rules),modules=Core.Copy(state.modules)} end

function State:CreateState(guildId)
    local firstGuild=next(self:GetStates())==nil
    local legacy=firstGuild and HolyStorm.db.global.permissions and (HolyStorm.db.global.permissions.groups or HolyStorm.db.global.permissions.roles)
    local state={guildId=guildId,groups=self:MigrateLegacyGroups(legacy),filters=firstGuild and Core.Copy(HolyStorm.db.global.filters.global or {}) or {},rules=firstGuild and Core.Copy(HolyStorm.db.global.rules.global or {}) or {},modules={},version=0,revisionID=nil,previousRevisionID=nil,history={},status=self.status.UNINITIALIZED,lastSync=0,missingRevisions={}}
    self:EnsureSystemGroups(state); self:GetStates()[guildId]=state; return state
end
function State:UpgradeState(state)
    local previousSchema=tonumber(state.schemaVersion) or 0
    state.groups=type(state.groups)=="table" and state.groups or {}; state.filters=type(state.filters)=="table" and state.filters or {}; state.rules=type(state.rules)=="table" and state.rules or {}; state.modules=type(state.modules)=="table" and state.modules or {}; state.history=type(state.history)=="table" and state.history or {}
    for id,group in pairs(state.groups) do local normalized=self:NormalizeGroup(group,group); if normalized then state.groups[id]=normalized else state.groups[id]=nil end end
    self:EnsureSystemGroups(state)
    local defaults=self:GetDefaultGroups(); local ids=self.systemIds
    if previousSchema<3 then for _,id in ipairs({ids.OFFICERS,ids.MEMBER}) do for permission,enabled in pairs(defaults[id].permissions) do if enabled and (permission:match("^news%-") or permission:match("^guide%-")) then state.groups[id].permissions[permission]=true end end end end
    if previousSchema<4 then for _,id in ipairs({ids.OFFICERS,ids.MEMBER}) do for permission,enabled in pairs(defaults[id].permissions) do if enabled and permission:match("^poi%-") then state.groups[id].permissions[permission]=true end end end end
    if previousSchema<5 then for _,id in ipairs({ids.OFFICERS,ids.MEMBER}) do for permission,enabled in pairs(defaults[id].permissions) do if enabled and permission:match("^position%-") then state.groups[id].permissions[permission]=true end end end end
    state.schemaVersion=5; return state
end
function State:ValidateSnapshot(snapshot)
    if type(snapshot)~="table" or type(snapshot.groups)~="table" or type(snapshot.filters)~="table" or type(snapshot.rules)~="table" or type(snapshot.modules)~="table" then return false,"INVALID_SNAPSHOT" end
    local count=0
    for id,group in pairs(snapshot.groups) do count=count+1; if count>self.maxObjects or id~=group.id then return false,"INVALID_GROUP_INDEX" end; local ok,err=self:ValidateGroup(group,snapshot); if not ok then return false,err end end
    local defaults=self:GetDefaultGroups()
    for id,definition in pairs(defaults) do local group=snapshot.groups[id]; if not group or group.system~=true then return false,"MISSING_SYSTEM_GROUP" end; if group.systemRule~=definition.systemRule or group.nameKey~=definition.nameKey or group.creator~="System" then return false,"SYSTEM_INVARIANT" end end
    for id,group in pairs(snapshot.groups) do if group.system and not defaults[id] then return false,"UNKNOWN_SYSTEM_GROUP" end end
    if self:HasManagerCycle(snapshot.groups) then return false,"MANAGER_CYCLE" end
    for id,filter in pairs(snapshot.filters) do if id~=filter.id or not Core.ValidId(id) then return false,"INVALID_FILTER" end; local ok,err=HolyStorm.Rules:Validate(filter.root or filter.rules); if not ok then return false,err end end
    for id,rule in pairs(snapshot.rules) do if id~=rule.id or not Core.ValidId(id) then return false,"INVALID_RULE" end; local ok,err=HolyStorm.Rules:Validate(rule.root or rule.rules); if not ok then return false,err end end
    return true
end

function State:ApplyChange(snapshot,change)
    local nextState=Core.Copy(snapshot); local action=change.action
    if action=="BASELINE" then nextState=Core.Copy(change.snapshot)
    elseif action=="GROUP_UPSERT" then nextState.groups[change.group.id]=Core.Copy(change.group)
    elseif action=="GROUP_DELETE" then nextState.groups[change.groupId]=nil
    elseif action=="FILTER_UPSERT" then nextState.filters[change.filter.id]=Core.Copy(change.filter)
    elseif action=="FILTER_DELETE" then nextState.filters[change.filterId]=nil
    elseif action=="RULE_UPSERT" then nextState.rules[change.rule.id]=Core.Copy(change.rule)
    elseif action=="RULE_DELETE" then nextState.rules[change.ruleId]=nil
    elseif action=="MODULE_SET" then nextState.modules[change.moduleId]=change.enabled==true
    elseif action=="RESET" then nextState.groups=self:GetDefaultGroups(); nextState.filters={}; nextState.rules={}; nextState.modules={}
    else return nil,"UNKNOWN_ACTION" end
    return nextState
end
function State:AuthorizeChange(state,change,actor)
    if not actor or not Core.ValidId(actor.characterUUID) then return false,"INVALID_ACTOR" end
    local action,groups=change.action,state.groups
    if action=="BASELINE" then return self:IsActualGuildLeader(actor.accountUUID,actor.characterUUID),"GUILD_LEADER_REQUIRED" end
    if action=="RESET" then return self:HasPermissionInState(state,actor.accountUUID,actor.characterUUID,"permissions-reset") and true or false,"PERMISSION_DENIED" end
    if action=="GROUP_DELETE" then local group=groups[change.groupId]; if not group then return false,"NOT_FOUND" end; if group.system then return false,"SYSTEM_GROUP" end; return self:HasPermissionInState(state,actor.accountUUID,actor.characterUUID,"groups-delete"),"PERMISSION_DENIED" end
    if action=="GROUP_UPSERT" then
        local incoming,current=change.group,groups[change.group.id]
        if current and current.system and (incoming.id~=current.id or incoming.system~=true or incoming.nameKey~=current.nameKey or incoming.systemRule~=current.systemRule) then return false,"SYSTEM_INVARIANT" end
        local leadershipChanged=current and incoming.id==self.systemIds.LEADERSHIP and (not Core.Same(incoming.characterMembers,current.characterMembers) or not Core.Same(incoming.accountMembers,current.accountMembers) or not Core.Same(incoming.guildRanks,current.guildRanks) or not Core.Same(incoming.filterIds,current.filterIds) or not Core.Same(incoming.ruleIds,current.ruleIds) or incoming.filterOperator~=current.filterOperator)
        if leadershipChanged and not self:IsActualGuildLeader(actor.accountUUID,actor.characterUUID) then return false,"GUILD_LEADER_REQUIRED" end
        if not current then return self:HasPermissionInState(state,actor.accountUUID,actor.characterUUID,"groups-create"),"PERMISSION_DENIED" end
        if not Core.Same(incoming.permissions,current.permissions) and not self:HasPermissionInState(state,actor.accountUUID,actor.characterUUID,"permissions-manage") then return false,"PERMISSION_DENIED" end
        local membershipChanged=not Core.Same(incoming.characterMembers,current.characterMembers) or not Core.Same(incoming.accountMembers,current.accountMembers) or not Core.Same(incoming.guildRanks,current.guildRanks)
        if membershipChanged and not (self:IsManagedBy(state,actor,incoming.id) or self:HasPermissionInState(state,actor.accountUUID,actor.characterUUID,"groups-manage-members")) then return false,"PERMISSION_DENIED" end
        return self:CanManageGroup(actor.accountUUID,actor.characterUUID,incoming.id,state),"PERMISSION_DENIED"
    end
    if action=="FILTER_UPSERT" then local permission=state.filters[change.filter.id] and "filters-edit" or "filters-create"; return self:HasPermissionInState(state,actor.accountUUID,actor.characterUUID,permission),"PERMISSION_DENIED" end
    if action=="FILTER_DELETE" then return self:HasPermissionInState(state,actor.accountUUID,actor.characterUUID,"filters-delete"),"PERMISSION_DENIED" end
    if action=="RULE_UPSERT" or action=="RULE_DELETE" then return self:HasPermissionInState(state,actor.accountUUID,actor.characterUUID,"rules-manage"),"PERMISSION_DENIED" end
    if action=="MODULE_SET" then return self:HasPermissionInState(state,actor.accountUUID,actor.characterUUID,"modules-manage"),"PERMISSION_DENIED" end
    return false,"UNKNOWN_ACTION"
end
function State:ValidateRevision(revision)
    return type(revision)=="table" and tonumber(revision.version) and Core.ValidId(revision.revisionID) and (revision.previousRevisionID==nil or Core.ValidId(revision.previousRevisionID)) and type(revision.changedBy)=="table" and Core.ValidId(revision.changedBy.characterUUID) and Core.ValidId(revision.changedBy.accountUUID) and tonumber(revision.changedAt) and type(revision.change)=="table" and type(revision.change.action)=="string"
end
function State:EmitChangeEvents(change)
    local action=change.action
    if action=="GROUP_UPSERT" then HolyStorm.Events:Emit("HS_GROUP_UPDATED",change.group.id)
    elseif action=="GROUP_DELETE" then HolyStorm.Events:Emit("HS_GROUP_DELETED",change.groupId)
    elseif action=="FILTER_UPSERT" then HolyStorm.Events:Emit("HS_FILTER_UPDATED",change.filter.id)
    elseif action=="FILTER_DELETE" then HolyStorm.Events:Emit("HS_FILTER_DELETED",change.filterId)
    elseif action=="RULE_UPSERT" then HolyStorm.Events:Emit("HS_RULE_UPDATED",change.rule.id)
    elseif action=="RULE_DELETE" then HolyStorm.Events:Emit("HS_RULE_DELETED",change.ruleId) end
end
function State:RecordRejected(revision,sender,reason)
    local state=self:GetState(); if not state then return end
    state.rejectedRevisions=state.rejectedRevisions or {}; state.rejectedRevisions[#state.rejectedRevisions+1]={revisionID=revision and revision.revisionID,sender=sender or (revision and revision.changedBy and revision.changedBy.characterUUID),reason=reason,timestamp=Core.Now()}
    while #state.rejectedRevisions>self.maxRejected do table.remove(state.rejectedRevisions,1) end
    HolyStorm.Events:Emit("HS_PERMISSIONS_REVISION_REJECTED",reason); Core.Log("WARN","revision","Permission revision rejected",{revisionID=revision and revision.revisionID,reason=reason,sender=sender})
end
function State:CommitSnapshot(state,snapshot,revision)
    state.groups,state.filters,state.rules,state.modules=snapshot.groups,snapshot.filters,snapshot.rules,snapshot.modules; state.previousRevisionID=revision.previousRevisionID; state.revisionID=revision.revisionID; state.version=revision.version; state.changedBy=Core.Copy(revision.changedBy); state.changedAt=revision.changedAt; state.status=self.status.VALID; state.lastSync=Core.Now(); state.history[#state.history+1]=Core.Copy(revision)
    while #state.history>self.maxHistory do table.remove(state.history,1) end
    self:EnsureSystemGroups(state)
    if self:GetState(state.guildId)==state then
        self:BindCompatibility(state)
        if revision.change.action=="FILTER_UPSERT" or revision.change.action=="FILTER_DELETE" or revision.change.action=="RULE_UPSERT" or revision.change.action=="RULE_DELETE" or revision.change.action=="RESET" then HolyStorm.Rules:RebuildDemands() end
        self:Invalidate(revision.change.action); self:EmitChangeEvents(revision.change); HolyStorm.Events:Emit("HS_PERMISSIONS_REVISION_APPLIED",Core.Copy(revision)); HolyStorm.Events:Emit("HS_PERMISSIONS_STATE_UPDATED",state.guildId,state.version,state.revisionID)
    end
    return true
end
function State:ApplyRevision(state,revision)
    if not self:ValidateRevision(revision) then self:RecordRejected(revision,nil,"INVALID_REVISION"); return false,"INVALID_REVISION" end
    if revision.revisionID==state.revisionID then return true,"DUPLICATE" end
    if revision.version==state.version and revision.previousRevisionID==state.previousRevisionID and revision.revisionID~=state.revisionID then state.status=self.status.CONFLICT; state.fork={localRevision=state.revisionID,remoteRevision=revision.revisionID,version=revision.version}; self:RecordRejected(revision,nil,"FORK"); HolyStorm.Events:Emit("HS_PERMISSIONS_CONFLICT_DETECTED",Core.Copy(state.fork)); Core.Log("ERROR","revision","Permission revision fork detected",state.fork); return false,"FORK" end
    if revision.version~=state.version+1 or revision.previousRevisionID~=state.revisionID then return false,"MISSING_PREDECESSOR" end
    local allowed,reason=self:AuthorizeChange(state,revision.change,revision.changedBy); if not allowed then self:RecordRejected(revision,nil,reason); Core.Log("WARN","authority","Permission revision actor unauthorized",{revisionID=revision.revisionID,reason=reason}); return false,reason end
    local snapshot,err=self:ApplyChange(self:Snapshot(state),revision.change); if not snapshot then self:RecordRejected(revision,nil,err); return false,err end
    local valid,validationError=self:ValidateSnapshot(snapshot); if not valid then self:RecordRejected(revision,nil,validationError); return false,validationError end
    return self:CommitSnapshot(state,snapshot,revision)
end
function State:CommitChange(change,actor)
    local state=self:GetState(); if not state or state.status~=self.status.VALID then return false,"STATE_NOT_VALID" end
    actor=actor or self:Actor(); local allowed,reason=self:AuthorizeChange(state,change,actor); if not allowed then Core.Log("WARN","authority","Permission change rejected",{action=change.action,reason=reason}); return false,reason end
    local snapshot,err=self:ApplyChange(self:Snapshot(state),change); if not snapshot then return false,err end
    local valid,validationError=self:ValidateSnapshot(snapshot); if not valid then return false,validationError end
    if Core.Same(snapshot,self:Snapshot(state)) then return false,"UNCHANGED" end
    local revision={version=state.version+1,revisionID=self:NewRevisionId(state.guildId,state.version+1),previousRevisionID=state.revisionID,changedBy=Core.Copy(actor),changedAt=Core.Now(),action=change.action,change=Core.Copy(change)}
    self:CommitSnapshot(state,snapshot,revision); HolyStorm.Sync:Publish("permissions",state.guildId,"PERMISSION_REVISION_CREATED")
    Core.Log("INFO","revision","Permission revision created",{version=revision.version,revisionID=revision.revisionID,action=change.action,groupId=change.groupId or (change.group and change.group.id),filterId=change.filterId or (change.filter and change.filter.id),ruleId=change.ruleId or (change.rule and change.rule.id)})
    return true,Core.Copy(revision)
end

function State:SetGuildModuleEnabled(moduleId,enabled) if not Core.ValidId(moduleId) then return false,"INVALID_MODULE" end; return self:CommitChange({action="MODULE_SET",moduleId=moduleId,enabled=enabled==true}) end
function State:IsGuildModuleEnabled(moduleId) local state=self:GetState(); return not state or state.modules[moduleId]~=false end
function State:RestoreDefaults() local ok,result=self:CommitChange({action="RESET"}); if ok then Core.Log("INFO","administration","Permission factory reset completed",{revisionID=result.revisionID,version=result.version}) end; return ok,result end
function State:GetPermissionStateStatus()
    local state=self:GetState(); if not state then return {status=self.status.UNINITIALIZED,version=0} end
    return {guildId=state.guildId,status=state.status,version=state.version,revisionID=state.revisionID,previousRevisionID=state.previousRevisionID,changedBy=Core.Copy(state.changedBy),changedAt=state.changedAt,historyLength=#state.history,rejectedLength=#(state.rejectedRevisions or {}),oldestRevisionID=state.history[1] and state.history[1].revisionID,missingRevisions=Core.Copy(state.missingRevisions),fork=Core.Copy(state.fork),lastSync=state.lastSync,recovery=Core.Copy(state.recovery),catchup=Core.Copy(state.catchup),catchupReason=state.catchupReason}
end
function State:GetRevisionHistory() local state=self:GetState(); return Core.Copy(state and state.history or {}) end
function State:GetRejectedRevisions() local state=self:GetState(); return Core.Copy(state and state.rejectedRevisions or {}) end

HolyStorm.PermissionComponents = HolyStorm.PermissionComponents or {}
HolyStorm.PermissionComponents.State = State
