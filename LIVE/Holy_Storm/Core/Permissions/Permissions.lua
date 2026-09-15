local addonVersion="4.3.0"
local HolyStorm=LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local Permissions={version=addonVersion,systemIds={LEADERSHIP="guild-leadership",OFFICERS="officers",MEMBER="guild-member"},keys={}}
Permissions.systemIds.GUILD_MASTER=Permissions.systemIds.LEADERSHIP;Permissions.systemIds.USERS=Permissions.systemIds.MEMBER
local definitions={
 ["groups-create"]="Administration",["groups-edit"]="Administration",["groups-delete"]="Administration",["groups-manage-members"]="Administration",["permissions-manage"]="Administration",["permissions-reset"]="Administration",["filters-create"]="Administration",["filters-edit"]="Administration",["filters-delete"]="Administration",["rules-manage"]="Administration",["policy-inspect"]="Administration",["modules-manage"]="Administration",
 ["core-settings-read"]="Core",["core-settings-write"]="Core",["settings-read"]="Core",["settings-write"]="Core",["ui-render"]="Core",["sync-send"]="Sync",["sync-receive"]="Sync",["player-read"]="Core",["savedvariables-read"]="Core",["savedvariables-write"]="Core",["professions-read"]="Core",["guild-roster-read"]="Roster",["roster-manage"]="Roster",
 ["news-view"]="News",["news-create"]="News",["news-edit"]="News",["news-delete"]="News",["news-publish"]="News",["news-read-receipts"]="News",["guide-view"]="News",["guide-create"]="News",["guide-edit"]="News",["guide-delete"]="News",["guide-publish"]="News",["calendar-read"]="Calendar",["calendar-manage"]="Calendar",["raids-read"]="Raid",["mythicplus-read"]="Mythic+",["delves-read"]="Delves",["equipment-read"]="Equipment",["logs-view"]="Logs",["logs-clear"]="Logs",["taskmanager-view"]="Task Manager",["taskmanager-control"]="Task Manager",["tasks-view"]="Task Manager",["twinks-assign"]="Administration",["twinks-remove"]="Administration",["poi-view"]="POI",["poi-create-personal"]="POI",["poi-create-guild"]="POI",["poi-create-group"]="POI",["poi-create-raid"]="POI",["poi-edit-own"]="POI",["poi-edit-any"]="POI",["poi-delete-own"]="POI",["poi-delete-any"]="POI",["poi-create"]="POI",["poi-edit"]="POI",["poi-delete"]="POI",["position-view"]="Positions",["position-share"]="Positions",
}
local legacy={
 ["roles.manage"]="groups-edit",["permissions.manage"]="permissions-manage",["filters.manage_global"]="filters-edit",["rules.manage_global"]="rules-manage",["policy.inspect"]="policy-inspect",["core.settings.read"]="core-settings-read",["core.settings.write"]="core-settings-write",["ui.render"]="ui-render",["sync.send"]="sync-send",["guild.roster.read"]="guild-roster-read",["roster.manage"]="roster-manage",["news.create"]="news-create",["news.edit"]="news-edit",["news.delete"]="news-delete",["news.read_receipts"]="news-read-receipts",["calendar.read"]="calendar-read",["calendar.manage"]="calendar-manage",["raids.read"]="raids-read",["mythicplus.read"]="mythicplus-read",["delves.read"]="delves-read",["equipment.read"]="equipment-read",["logs.view"]="logs-view",["logs.clear"]="logs-clear",["taskmanager.view"]="taskmanager-view",["taskmanager.control"]="taskmanager-control",["tasks.view"]="tasks-view",["twinks.assign"]="twinks-assign",["twinks.remove"]="twinks-remove",["poi.create"]="poi-create",["poi.edit"]="poi-edit",["poi.delete"]="poi-delete",
}
Permissions.legacyIds=legacy
local function keyFor(prefix,id)return prefix..id:gsub("[^%w]","_"):upper()end
function Permissions:RegisterPermission(definition)
 if type(definition)~="table"or type(definition.id)~="string"or not definition.id:match("^[a-z][a-z0-9%-]*$")then return false,"INVALID_PERMISSION_ID"end
 local d=HolyStorm.Utils.DeepCopy(definition);d.category=d.category or"Core";d.module=d.module or"Core";d.labelKey=d.labelKey or keyFor("PERMISSION_",d.id);d.descriptionKey=d.descriptionKey or keyFor("PERMISSION_DESC_",d.id);self.keys[d.id]=d;if HolyStorm.Events then HolyStorm.Events:Emit("HS_PERMISSION_REGISTERED",d.id)end;return true
end
function Permissions:Register(id,definition)definition=HolyStorm.Utils.DeepCopy(definition or{});definition.id=id;return self:RegisterPermission(definition)end
for id,category in pairs(definitions)do Permissions:RegisterPermission({id=id,module="Core",category=category})end
for _,id in ipairs({"achievement-view","achievement-create","achievement-edit","achievement-delete","achievement-publish","achievement-award","achievement-revoke","achievement-admin","achievement-test"})do Permissions:RegisterPermission({id=id,module="Achievements",category="Achievements"})end
function Permissions:NormalizePermissionId(id)return legacy[id]or id end
function Permissions:GetPermissionDefinitions()return HolyStorm.Utils.DeepCopy(self.keys)end
function Permissions:GetStore()return HolyStorm.Policy and HolyStorm.Policy:GetStateStore()or HolyStorm.db.global.permissions end
function Permissions:GetDefaultGroups()
 local ids=self.systemIds
 local defaults={
  [ids.LEADERSHIP]={id=ids.LEADERSHIP,nameKey="GROUP_GUILD_LEADERSHIP",descriptionKey="GROUP_DESC_GUILD_LEADERSHIP",creator="System",system=true,systemRule="GUILD_LEADER",permissions={},characterMembers={},accountMembers={},guildRanks={},filterIds={},ruleIds={},filterOperator="AND",managerGroupIds={}},
  [ids.OFFICERS]={id=ids.OFFICERS,nameKey="GROUP_OFFICERS",descriptionKey="GROUP_DESC_OFFICERS",creator="System",system=true,systemRule="OFFICER",permissions={["news-view"]=true,["news-create"]=true,["news-edit"]=true,["news-delete"]=true,["news-publish"]=true,["news-read-receipts"]=true,["guide-view"]=true,["guide-create"]=true,["guide-edit"]=true,["guide-delete"]=true,["guide-publish"]=true,["poi-view"]=true,["poi-create-personal"]=true,["poi-create-guild"]=true,["poi-create-group"]=true,["poi-create-raid"]=true,["poi-edit-own"]=true,["poi-edit-any"]=true,["poi-delete-own"]=true,["poi-delete-any"]=true,["position-view"]=true,["position-share"]=true,["calendar-manage"]=true,["roster-manage"]=true,["filters-create"]=true,["filters-edit"]=true,["rules-manage"]=true},characterMembers={},accountMembers={},guildRanks={},filterIds={},ruleIds={},filterOperator="AND",managerGroupIds={ids.LEADERSHIP}},
  [ids.MEMBER]={id=ids.MEMBER,nameKey="GROUP_GUILD_MEMBER",descriptionKey="GROUP_DESC_GUILD_MEMBER",creator="System",system=true,systemRule="GUILD_MEMBER",permissions={["guild-roster-read"]=true,["news-view"]=true,["guide-view"]=true,["poi-view"]=true,["poi-create-personal"]=true,["position-view"]=true,["position-share"]=true,["calendar-read"]=true,["raids-read"]=true,["mythicplus-read"]=true,["delves-read"]=true,["equipment-read"]=true,["logs-view"]=true,["tasks-view"]=true},characterMembers={},accountMembers={},guildRanks={},filterIds={},ruleIds={},filterOperator="AND",managerGroupIds={ids.LEADERSHIP}},
 }
 defaults[ids.MEMBER].permissions["achievement-view"]=true
 for _,permission in ipairs({"achievement-view","achievement-create","achievement-edit","achievement-delete","achievement-publish","achievement-award","achievement-revoke","achievement-admin","achievement-test"})do defaults[ids.OFFICERS].permissions[permission]=true end
 return defaults
end
function Permissions:IsActualGuildLeader(playerId,guid)
 local guild=HolyStorm.Data.GuildStore:GetCurrent();if guid then local member=guild and guild.roster and guild.roster[guid];return member and member.rankIndex==0 or false end
 local localAccount=HolyStorm.TwinkCore and HolyStorm.TwinkCore:GetLocalAccountUUID()or HolyStorm.Data.PlayerStore:GetLocalPlayerId();if not playerId or playerId==localAccount then local playerGuid=UnitGUID("player");local member=guild and guild.roster and guild.roster[playerGuid];if member then return member.rankIndex==0 end;local _,_,rank=GetGuildInfo("player");return IsInGuild()and rank==0 end
 local characters=HolyStorm.TwinkCore and HolyStorm.TwinkCore:GetCharactersForAccount(playerId)or{};for characterGuid in pairs(characters)do local member=guild and guild.roster and guild.roster[characterGuid];if member and member.rankIndex==0 then return true end end;return false
end
Permissions.IsGuildLeader=Permissions.IsActualGuildLeader
function Permissions:GetMembershipReasons(group,playerId,guid,context)return HolyStorm.Policy and HolyStorm.Policy:GetMembershipReasons(group,playerId,guid,context)or{}end
function Permissions:Has(permission,playerId,guid)return HolyStorm.Policy and HolyStorm.Policy:HasPermission(playerId,guid,self:NormalizePermissionId(permission))or self:IsActualGuildLeader(playerId,guid)end
Permissions.HasPermission=Permissions.Has
function Permissions:IsAuthorizedSender(sender,permission)local guid=HolyStorm.Data.GuildStore:ResolveSenderGuid(sender);return guid and self:Has(permission,HolyStorm.TwinkCore and HolyStorm.TwinkCore:GetAccountUUIDForCharacter(guid)or guid,guid)or false end
function Permissions:GetRoles()return HolyStorm.Policy and HolyStorm.Policy:GetGroups()or{}end
function Permissions:CanManage()return self:Has("permissions-manage")end
function Permissions:SaveGroup(group)return HolyStorm.Policy:SaveGroup(group)end
function Permissions:DeleteGroup(id)return HolyStorm.Policy:DeleteGroup(id)end
function Permissions:CreateRole(id,name,rights)return HolyStorm.Policy:CreateGroup({id=id,name=name,permissions=rights})end
function Permissions:UpdateRole(id,name,rights)local group=HolyStorm.Policy:GetGroup(id);if not group then return false end;group.name=name or group.name;group.permissions=rights or group.permissions;return HolyStorm.Policy:SaveGroup(group)end
function Permissions:DeleteRole(id)return HolyStorm.Policy:DeleteGroup(id)end
function Permissions:AssignRole(subjectId,groupId,assigned)if assigned==false then return HolyStorm.Policy:RemoveMembership(groupId,"account",subjectId)end;return HolyStorm.Policy:AddAccountMembership(groupId,subjectId)end
function Permissions:Initialize()end
HolyStorm.Permissions,HolyStorm.PermissionManager,HolyStorm.PermissionRegistry=Permissions,Permissions,Permissions
function HolyStorm:HasPermission(permission,playerId,guid)return Permissions:Has(permission,playerId,guid)end
