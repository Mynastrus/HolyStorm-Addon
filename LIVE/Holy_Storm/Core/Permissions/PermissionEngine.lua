local addonVersion = "5.0.0"
local HolyStorm = LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local Core = HolyStorm.PermissionCore
local Engine = { version=addonVersion, permissionCache={}, membershipCache={}, generation=0 }

function Engine:BuildContext(accountUUID,characterUUID,target,projection)
    local localAccount=(HolyStorm.TwinkCore and HolyStorm.TwinkCore:GetLocalAccountUUID()) or HolyStorm.Data.PlayerStore:GetLocalPlayerId()
    accountUUID=accountUUID or localAccount
    characterUUID=characterUUID or (accountUUID==localAccount and UnitGUID("player"))
    projection=projection or{}
    local character=projection.character or(characterUUID and HolyStorm.Data.CharacterStore:Get(characterUUID))
    local guild=projection.guild or HolyStorm.Data.GuildStore:GetCurrent();local member=characterUUID and guild and guild.roster and guild.roster[characterUUID]
    return {accountUUID=accountUUID,playerId=accountUUID,characterUUID=characterUUID,guid=characterUUID,player=projection.player,character=character,guild=guild,member=member,target=target}
end
function Engine:Actor(accountUUID,characterUUID)
    return {accountUUID=accountUUID or (HolyStorm.TwinkCore and HolyStorm.TwinkCore:GetLocalAccountUUID()) or HolyStorm.Data.PlayerStore:GetLocalPlayerId(),characterUUID=characterUUID or UnitGUID("player")}
end
function Engine:IsActualGuildLeader(accountUUID,characterUUID)
    local guild=HolyStorm.Data.GuildStore:GetCurrent()
    if characterUUID then local member=guild and guild.roster and guild.roster[characterUUID]; return member and member.rankIndex==0 or false end
    local localAccount=(HolyStorm.TwinkCore and HolyStorm.TwinkCore:GetLocalAccountUUID()) or HolyStorm.Data.PlayerStore:GetLocalPlayerId()
    if not accountUUID or accountUUID==localAccount then
        local playerGuid=UnitGUID("player"); local member=guild and guild.roster and guild.roster[playerGuid]
        if member then return member.rankIndex==0 end
        local _,_,rank=GetGuildInfo("player"); return IsInGuild() and rank==0
    end
    local characters=HolyStorm.TwinkCore and HolyStorm.TwinkCore:GetCharactersForAccount(accountUUID) or {}
    for guid in pairs(characters) do local member=guild and guild.roster and guild.roster[guid]; if member and member.rankIndex==0 then return true end end
    return false
end

function Engine:GetMembershipReasonsForState(state,group,accountUUID,characterUUID,context)
    local reasons={}; if type(group)~="table" then return reasons end
    context=context or self:BuildContext(accountUUID,characterUUID); local member=context.member
    local characterMembers=type(group.characterMembers)=="table" and group.characterMembers or {}; local accountMembers=type(group.accountMembers)=="table" and group.accountMembers or {}; local guildRanks=type(group.guildRanks)=="table" and group.guildRanks or {}; local filterIds=type(group.filterIds)=="table" and group.filterIds or {}; local ruleIds=type(group.ruleIds)=="table" and group.ruleIds or {}
    if group.id==self.systemIds.MEMBER and member then reasons[#reasons+1]={type="SYSTEM",source="SYSTEM",id="GUILD_MEMBER",protected=true,reason="SYSTEM:GUILD_MEMBER"} end
    if group.id==self.systemIds.OFFICERS and member and member.rankIndex==1 then reasons[#reasons+1]={type="GUILD_RANK",source="GUILD_RANK",id=1,name=member.rank,protected=true,reason="SYSTEM:OFFICER_RANK"} end
    if group.id==self.systemIds.LEADERSHIP and member and member.rankIndex==0 then reasons[#reasons+1]={type="SYSTEM",source="SYSTEM",id="GUILD_LEADER",protected=true,reason="SYSTEM:GUILD_LEADER"} end
    if characterUUID and characterMembers[characterUUID] then reasons[#reasons+1]={type="CHARACTER",source="MANUAL",id=characterUUID,reason="CHARACTER:"..characterUUID} end
    if accountUUID and accountMembers[accountUUID] then reasons[#reasons+1]={type="ACCOUNT",source="MANUAL",id=accountUUID,reason="ACCOUNT:"..accountUUID} end
    if member and guildRanks[member.rankIndex] then reasons[#reasons+1]={type="GUILD_RANK",source="GUILD_RANK",id=member.rankIndex,name=member.rank,reason="GUILD_RANK:"..tostring(member.rankIndex)} end
    if #filterIds>0 then
        local matched=group.filterOperator~="OR"; local traces={}
        for _,filterId in ipairs(filterIds) do
            local filter=state.filters[filterId]; local ok,trace,status=filter and self:ApplyFilter(filter,context) or false
            traces[#traces+1]={id=filterId,name=filter and filter.name,result=ok,status=status,trace=trace}
            if group.filterOperator=="OR" then matched=matched or ok elseif not ok then matched=false end
        end
        if matched then for _,entry in ipairs(traces) do if entry.result then reasons[#reasons+1]={type="FILTER",source="FILTER",id=entry.id,name=entry.name,trace=entry.trace,status=entry.status,reason="FILTER:"..entry.id} end end end
    end
    for _,ruleId in ipairs(ruleIds) do local rule=state.rules[ruleId]; local matched,trace,status=rule and self:EvaluateRule(rule,context) or false; if matched then reasons[#reasons+1]={type="RULE",source="RULE",id=ruleId,name=rule.name,trace=trace,status=status,reason="RULE:"..ruleId} end end
    return reasons
end
function Engine:GetMembershipReasons(group,accountUUID,characterUUID,context)
    local state=self:GetState(); return state and self:GetMembershipReasonsForState(state,group,accountUUID,characterUUID,context) or {}
end
function Engine:GetEffectiveGroupsForState(state,accountUUID,characterUUID,context)
    local groups={};context=context or self:BuildContext(accountUUID,characterUUID)
    for id,group in pairs(state and state.groups or {}) do local reasons=self:GetMembershipReasonsForState(state,group,context.accountUUID,context.characterUUID,context); if #reasons>0 then groups[id]={id=id,name=group.name,nameKey=group.nameKey,reasons=reasons,permissions=Core.Copy(type(group.permissions)=="table" and group.permissions or {})} end end
    return groups
end
function Engine:GetEffectiveGroups(accountUUID,characterUUID,force)
    local state=self:GetState(); if not state then return {} end
    local context=self:BuildContext(accountUUID,characterUUID); local key=tostring(context.accountUUID).."\031"..tostring(context.characterUUID)
    if not force and self.membershipCache[key] then return Core.Copy(self.membershipCache[key]) end
    local groups=self:GetEffectiveGroupsForState(state,context.accountUUID,context.characterUUID); self.membershipCache[key]=groups; return Core.Copy(groups)
end
function Engine:IsMemberOfGroup(groupId,accountUUID,characterUUID,state)
    state=state or self:GetState(); local group=state and state.groups[groupId]; if not group then return false,{} end
    local reasons=self:GetMembershipReasonsForState(state,group,accountUUID,characterUUID); return #reasons>0,reasons
end
function Engine:HasPermissionInState(state,accountUUID,characterUUID,permission)
    permission=HolyStorm.PermissionRegistry:NormalizePermissionId(permission)
    if self:IsActualGuildLeader(accountUUID,characterUUID) then return true end
    local groups=self:GetEffectiveGroupsForState(state,accountUUID,characterUUID)
    if groups[self.systemIds.LEADERSHIP] then return true end
    for _,group in pairs(groups) do if group.permissions[permission] then return true end end
    return false
end
function Engine:GetEffectivePermissions(accountUUID,characterUUID)
    local state=self:GetState(); if not state then return {} end
    local context=self:BuildContext(accountUUID,characterUUID); local key=tostring(context.accountUUID).."\031"..tostring(context.characterUUID)
    if self.permissionCache[key] then return Core.Copy(self.permissionCache[key]) end
    local result={}; local groups=self:GetEffectiveGroupsForState(state,context.accountUUID,context.characterUUID)
    if self:IsActualGuildLeader(context.accountUUID,context.characterUUID) or groups[self.systemIds.LEADERSHIP] then
        for permission in pairs(HolyStorm.PermissionRegistry.keys) do result[permission]=true end
        result["*"]=true
    else
        for _,group in pairs(groups) do for permission in pairs(group.permissions) do result[permission]=true end end
    end
    self.permissionCache[key]=result; return Core.Copy(result)
end
function Engine:HasPermission(accountUUID,characterUUID,permission)
    if permission==nil then permission=characterUUID; if type(accountUUID)=="table" then characterUUID=accountUUID.characterUUID or accountUUID.guid; accountUUID=accountUUID.accountUUID or accountUUID.playerId else characterUUID=nil end end
    permission=HolyStorm.PermissionRegistry:NormalizePermissionId(permission); local state=self:GetState()
    if not state or state.status~=self.status.VALID then return self:IsActualGuildLeader(accountUUID,characterUUID) and permission~="permissions-reset" end
    return self:HasPermissionInState(state,accountUUID,characterUUID,permission)
end
function Engine:Can(permission,accountUUID,characterUUID,target) return self:HasPermission(accountUUID,characterUUID,permission) end
function Engine:Explain(permission,accountUUID,characterUUID,target)
    local groups=self:GetEffectiveGroups(accountUUID,characterUUID); local grants={}; local normalized=HolyStorm.PermissionRegistry:NormalizePermissionId(permission)
    for id,group in pairs(groups) do if id==self.systemIds.LEADERSHIP or group.permissions[normalized] then grants[#grants+1]={groupId=id,name=group.name,nameKey=group.nameKey,reasons=group.reasons} end end
    local allowed=self:Can(permission,accountUUID,characterUUID,target); return {permission=permission,allowed=allowed,groups=groups,grants=grants,reason=allowed and "GRANTED_BY_GROUP" or "NO_GROUP_GRANTS_PERMISSION",target=target,state=self:GetPermissionStateStatus()}
end
function Engine:IsManagedBy(state,actor,groupId)
    local group=state.groups[groupId]; if not group then return false end
    for _,managerId in ipairs(group.managerGroupIds or {}) do if #self:GetMembershipReasonsForState(state,state.groups[managerId],actor.accountUUID,actor.characterUUID)>0 then return true end end
    return false
end
function Engine:CanManageGroup(actorAccount,actorCharacter,groupId,state)
    state=state or self:GetState(); if not state or not state.groups[groupId] then return false end
    if self:IsActualGuildLeader(actorAccount,actorCharacter) then return true end
    local actor={accountUUID=actorAccount,characterUUID=actorCharacter}
    return self:IsManagedBy(state,actor,groupId) or self:HasPermissionInState(state,actorAccount,actorCharacter,"groups-edit")
end
function Engine:Invalidate(reason)
    self.generation=self.generation+1; self.permissionCache={}; self.membershipCache={}; HolyStorm.Events:Emit("HS_POLICY_UPDATED",reason,self.generation); HolyStorm.Events:Emit("HS_EFFECTIVE_PERMISSIONS_CHANGED",reason)
    if HolyStorm.Tasks and HolyStorm.Tasks.GetTaskType and HolyStorm.Tasks:GetTaskType("Policy.RecalculateEffectiveMemberships") then HolyStorm.Tasks:Queue("Policy.RecalculateEffectiveMemberships",{triggerSource=reason or "POLICY_INVALIDATE",debounce=.2}) end
end
function Engine:GetEffectiveMembers(groupId)
    local group=self:GetGroup(groupId); local out={}; if not group then return out end
    local guild=HolyStorm.Data.GuildStore:GetCurrent()
    for guid,member in pairs(guild and guild.roster or {}) do local accountUUID=HolyStorm.TwinkCore and HolyStorm.TwinkCore:GetAccountUUIDForCharacter(guid) or HolyStorm.Data.PlayerStore:GetCharacterOwner(guid); local membership=self:GetMembershipReasons(group,accountUUID,guid); if #membership>0 then local character=HolyStorm.Data.CharacterStore:Get(guid) or {}; out[#out+1]={characterUUID=guid,accountUUID=accountUUID,name=member.name or character.name or guid,classFile=character.classFile or member.classFile,rank=member.rank,rankIndex=member.rankIndex,isMain=accountUUID and HolyStorm.TwinkCore and HolyStorm.TwinkCore:GetAccountMain(accountUUID)==guid,reasons=membership} end end
    table.sort(out,function(a,b) return tostring(a.name)<tostring(b.name) end); return out
end
function Engine:GetGroupSummaries()
    local groups=self:GetGroups(); local out={}
    for id,group in pairs(groups) do out[id]={id=id,name=group.name,nameKey=group.nameKey,system=group.system==true,creator=group.creator,description=group.description,effectiveMembers=0,explicitMembers=HolyStorm.Utils.TableCount(group.characterMembers)+HolyStorm.Utils.TableCount(group.accountMembers)+HolyStorm.Utils.TableCount(group.guildRanks),filters=#group.filterIds,permissions=HolyStorm.Utils.TableCount(group.permissions)} end
    local guild=HolyStorm.Data.GuildStore:GetCurrent(); for guid in pairs(guild and guild.roster or {}) do local accountUUID=HolyStorm.TwinkCore and HolyStorm.TwinkCore:GetAccountUUIDForCharacter(guid) or HolyStorm.Data.PlayerStore:GetCharacterOwner(guid); for id in pairs(self:GetEffectiveGroups(accountUUID,guid)) do if out[id] then out[id].effectiveMembers=out[id].effectiveMembers+1 end end end
    return out
end
function Engine:GetGroupSummary(groupId) return self:GetGroupSummaries()[groupId] end
function Engine:GetPermissionMatrix()
    local groups=self:GetGroups(); local groupIds=Core.TableKeys(groups); local rows={}
    local aliases={[self.systemIds.LEADERSHIP]="leadership",[self.systemIds.OFFICERS]="officers",[self.systemIds.MEMBER]="member"}
    for permissionId,definition in pairs(HolyStorm.PermissionRegistry:GetPermissions()) do
        local grants,assignments={},{ }
        for _,groupId in ipairs(groupIds) do
            local direct=groups[groupId].permissions[permissionId]==true
            local default=definition.defaults and (definition.defaults[groupId]==true or definition.defaults[aliases[groupId]]==true) or false
            assignments[groupId]={direct=direct,effective=groupId==self.systemIds.LEADERSHIP or direct,default=default,protected=groupId==self.systemIds.LEADERSHIP}
            grants[groupId]=assignments[groupId].effective
        end
        rows[#rows+1]={permissionId=permissionId,definition=definition,grants=grants,assignments=assignments}
    end
    table.sort(rows,function(a,b) return a.permissionId<b.permissionId end); return {groups=groups,groupIds=groupIds,rows=rows}
end
function Engine:GetPermissionDetail(permissionId,accountUUID,characterUUID)
    local definition=HolyStorm.PermissionRegistry:GetPermission(permissionId); if not definition then return nil end
    local matrix=self:GetPermissionMatrix(); local row
    for _,candidate in ipairs(matrix.rows) do if candidate.permissionId==definition.id then row=candidate; break end end
    local defaults,direct,effective={},{},{}
    for _,groupId in ipairs(matrix.groupIds) do
        local assignment=row.assignments[groupId]
        if assignment.default then defaults[#defaults+1]=groupId end
        if assignment.direct then direct[#direct+1]=groupId end
        if assignment.effective then effective[#effective+1]=groupId end
    end
    return {id=definition.id,definition=definition,registered=true,available=self:HasPermission(accountUUID,characterUUID,definition.id),defaultGroupIds=defaults,directGroupIds=direct,effectiveGroupIds=effective,groups=matrix.groups}
end
function Engine:Recalculate()
    local state=self:GetState();local guild=HolyStorm.Data.GuildStore.GetCurrentRosterSummary and HolyStorm.Data.GuildStore:GetCurrentRosterSummary() or HolyStorm.Data.GuildStore:GetCurrent()
    if not state then return false end
    local blocks={}
    local function addDependencies(object)
        local root=object and(object.root or object.rules or object)
        for _,dependency in ipairs(HolyStorm.Rules:GetDependencies(root)) do
            if dependency=="identity"or dependency=="equipment"or dependency=="mythicPlus"or dependency=="raid"or dependency=="delves"or dependency=="stats"or dependency=="profile"or dependency=="professions"or dependency=="addon"or dependency=="demands" then blocks[dependency]=true end
        end
    end
    for _,group in pairs(state.groups or{}) do
        for _,filterId in ipairs(group.filterIds or{}) do addDependencies(state.filters and state.filters[filterId]) end
        for _,ruleId in ipairs(group.ruleIds or{}) do addDependencies(state.rules and state.rules[ruleId]) end
    end
    local blockList={};for blockId in pairs(blocks)do blockList[#blockList+1]=blockId end;table.sort(blockList)
    for guid in pairs(guild and guild.roster or{})do
        local account=HolyStorm.TwinkCore and HolyStorm.TwinkCore:GetAccountUUIDForCharacter(guid)or HolyStorm.Data.PlayerStore:GetCharacterOwner(guid)or guid
        local character=HolyStorm.Data.CharacterStore.GetProjection and HolyStorm.Data.CharacterStore:GetProjection(guid,blockList)or HolyStorm.Data.CharacterStore:Get(guid)
        local context=self:BuildContext(account,guid,nil,{guild=guild,character=character})
        local groups=self:GetEffectiveGroupsForState(state,account,guid,context);local key=tostring(account).."\031"..tostring(guid);self.membershipCache[key]=groups
    end
    HolyStorm.Events:Emit("HS_EFFECTIVE_MEMBERSHIP_CHANGED"); return true
end

HolyStorm.PermissionComponents = HolyStorm.PermissionComponents or {}
HolyStorm.PermissionComponents.Engine = Engine
