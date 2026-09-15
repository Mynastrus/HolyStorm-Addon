local addonVersion = "5.1.0"
local HolyStorm = LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local Registry = HolyStorm.PermissionRegistry
local Permissions = {
    version=addonVersion,
    keys=Registry.keys,
    legacyIds=Registry.legacyIds,
    systemIds=HolyStorm.Policy.systemIds,
}

function Permissions:RegisterPermission(definition) return Registry:RegisterPermission(definition) end
function Permissions:Register(id,definition) return Registry:Register(id,definition) end
function Permissions:GetPermission(id) return Registry:GetPermission(id) end
function Permissions:GetPermissions() return Registry:GetPermissions() end
function Permissions:GetPermissionDefinitions() return Registry:GetPermissions() end
function Permissions:NormalizePermissionId(id) return Registry:NormalizePermissionId(id) end
function Permissions:GetDefaultGroups() return HolyStorm.Policy:GetDefaultGroups() end
function Permissions:GetStore() return HolyStorm.Policy:GetStateStore() end
function Permissions:IsActualGuildLeader(playerId,guid) return HolyStorm.Policy:IsActualGuildLeader(playerId,guid) end
Permissions.IsGuildLeader = Permissions.IsActualGuildLeader
function Permissions:GetMembershipReasons(group,playerId,guid,context) return HolyStorm.Policy:GetMembershipReasons(group,playerId,guid,context) end
function Permissions:Has(permission,playerId,guid) return HolyStorm.Policy:HasPermission(playerId,guid,self:NormalizePermissionId(permission)) end
Permissions.HasPermission = Permissions.Has
function Permissions:IsAuthorizedSender(sender,permission)
    local guid=HolyStorm.Data.GuildStore:ResolveSenderGuid(sender)
    return guid and self:Has(permission,HolyStorm.TwinkCore and HolyStorm.TwinkCore:GetAccountUUIDForCharacter(guid) or guid,guid) or false
end
function Permissions:GetRoles() return HolyStorm.Policy:GetGroups() end
function Permissions:CanManage() return self:Has("permissions-manage") end
function Permissions:SaveGroup(group) return HolyStorm.Policy:SaveGroup(group) end
function Permissions:DeleteGroup(id) return HolyStorm.Policy:DeleteGroup(id) end
function Permissions:CreateRole(id,name,rights) return HolyStorm.Policy:CreateGroup({id=id,name=name,permissions=rights}) end
function Permissions:UpdateRole(id,name,rights)
    local group=HolyStorm.Policy:GetGroup(id); if not group then return false end
    group.name=name or group.name; group.permissions=rights or group.permissions; return HolyStorm.Policy:SaveGroup(group)
end
function Permissions:DeleteRole(id) return HolyStorm.Policy:DeleteGroup(id) end
function Permissions:AssignRole(subjectId,groupId,assigned)
    if assigned==false then return HolyStorm.Policy:RemoveMembership(groupId,"account",subjectId) end
    return HolyStorm.Policy:AddAccountMembership(groupId,subjectId)
end
function Permissions:Initialize() end

HolyStorm.Permissions = Permissions
HolyStorm.PermissionManager = Permissions
function HolyStorm:HasPermission(permission,playerId,guid) return Permissions:Has(permission,playerId,guid) end
