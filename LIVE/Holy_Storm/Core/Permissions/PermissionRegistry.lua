local addonVersion = "5.0.0"
local HolyStorm = LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")

local Core = HolyStorm.PermissionCore or {}
HolyStorm.PermissionCore = Core

function Core.Copy(value) return HolyStorm.Utils.DeepCopy(value) end
function Core.Now() return HolyStorm.Utils.Now() end
function Core.ValidId(id)
    return type(id) == "string" and #id > 0 and #id <= 96 and id:match("^[%w_%.%-:]+$") ~= nil
end
function Core.Same(left, right)
    local serializedLeft = HolyStorm.Serializer:Serialize(left)
    local serializedRight = HolyStorm.Serializer:Serialize(right)
    return serializedLeft ~= nil and serializedLeft == serializedRight
end
function Core.ArrayContains(values, wanted)
    for _, value in ipairs(values or {}) do if value == wanted then return true end end
    return false
end
function Core.NormalizeSet(value)
    local result = {}
    for key, enabled in pairs(type(value) == "table" and value or {}) do
        if enabled == true and type(key) == "string" then result[key] = true end
    end
    return result
end
function Core.NormalizeArray(value)
    local seen, result = {}, {}
    for _, id in ipairs(type(value) == "table" and value or {}) do
        if Core.ValidId(id) and not seen[id] then seen[id] = true; result[#result + 1] = id end
    end
    table.sort(result)
    return result
end
function Core.TableKeys(value)
    local result = {}
    for key in pairs(value or {}) do result[#result + 1] = key end
    table.sort(result)
    return result
end
function Core.Log(level, category, message, context)
    HolyStorm.Logger:Write(level, "Policy", category, message, context)
end

local Registry = { version = addonVersion, keys = {} }
local definitions = {
    ["groups-create"]="Administration",["groups-edit"]="Administration",["groups-delete"]="Administration",["groups-manage-members"]="Administration",["permissions-manage"]="Administration",["permissions-reset"]="Administration",["filters-create"]="Administration",["filters-edit"]="Administration",["filters-delete"]="Administration",["rules-manage"]="Administration",["policy-inspect"]="Administration",["modules-manage"]="Administration",
    ["core-settings-read"]="Core",["core-settings-write"]="Core",["settings-read"]="Core",["settings-write"]="Core",["ui-render"]="Core",["sync-send"]="Sync",["sync-receive"]="Sync",["player-read"]="Core",["savedvariables-read"]="Core",["savedvariables-write"]="Core",["professions-read"]="Core",["guild-roster-read"]="Roster",["roster-manage"]="Roster",
    ["news-view"]="News",["news-create"]="News",["news-edit"]="News",["news-delete"]="News",["news-publish"]="News",["news-read-receipts"]="News",["guide-view"]="News",["guide-create"]="News",["guide-edit"]="News",["guide-delete"]="News",["guide-publish"]="News",["calendar-read"]="Calendar",["calendar-manage"]="Calendar",["raids-read"]="Raid",["mythicplus-read"]="Mythic+",["delves-read"]="Delves",["equipment-read"]="Equipment",["logs-view"]="Logs",["logs-clear"]="Logs",["taskmanager-view"]="Task Manager",["taskmanager-control"]="Task Manager",["tasks-view"]="Task Manager",["twinks-assign"]="Administration",["twinks-remove"]="Administration",["poi-view"]="POI",["poi-create-personal"]="POI",["poi-create-guild"]="POI",["poi-create-group"]="POI",["poi-create-raid"]="POI",["poi-edit-own"]="POI",["poi-edit-any"]="POI",["poi-delete-own"]="POI",["poi-delete-any"]="POI",["poi-create"]="POI",["poi-edit"]="POI",["poi-delete"]="POI",["position-view"]="Positions",["position-share"]="Positions",
}
Registry.legacyIds = {
    ["roles.manage"]="groups-edit",["permissions.manage"]="permissions-manage",["filters.manage_global"]="filters-edit",["rules.manage_global"]="rules-manage",["policy.inspect"]="policy-inspect",["core.settings.read"]="core-settings-read",["core.settings.write"]="core-settings-write",["ui.render"]="ui-render",["sync.send"]="sync-send",["guild.roster.read"]="guild-roster-read",["roster.manage"]="roster-manage",["news.create"]="news-create",["news.edit"]="news-edit",["news.delete"]="news-delete",["news.read_receipts"]="news-read-receipts",["calendar.read"]="calendar-read",["calendar.manage"]="calendar-manage",["raids.read"]="raids-read",["mythicplus.read"]="mythicplus-read",["delves.read"]="delves-read",["equipment.read"]="equipment-read",["logs.view"]="logs-view",["logs.clear"]="logs-clear",["taskmanager.view"]="taskmanager-view",["taskmanager.control"]="taskmanager-control",["tasks.view"]="tasks-view",["twinks.assign"]="twinks-assign",["twinks.remove"]="twinks-remove",["poi.create"]="poi-create",["poi.edit"]="poi-edit",["poi.delete"]="poi-delete",
}

local function keyFor(prefix, id) return prefix .. id:gsub("[^%w]", "_"):upper() end
function Registry:RegisterPermission(definition)
    if type(definition) ~= "table" or type(definition.id) ~= "string" or not definition.id:match("^[a-z][a-z0-9%-]*$") then return false, "INVALID_PERMISSION_ID" end
    local normalized = Core.Copy(definition)
    normalized.category = normalized.category or "Core"
    normalized.module = normalized.module or "Core"
    normalized.labelKey = normalized.labelKey or keyFor("PERMISSION_", normalized.id)
    normalized.descriptionKey = normalized.descriptionKey or keyFor("PERMISSION_DESC_", normalized.id)
    self.keys[normalized.id] = normalized
    if HolyStorm.Events then HolyStorm.Events:Emit("HS_PERMISSION_REGISTERED", normalized.id) end
    return true
end
function Registry:Register(id, definition)
    definition = Core.Copy(definition or {}); definition.id = id
    return self:RegisterPermission(definition)
end
function Registry:GetPermission(id)
    local definition = self.keys[self:NormalizePermissionId(id)]
    return definition and Core.Copy(definition)
end
function Registry:GetPermissions() return Core.Copy(self.keys) end
Registry.GetPermissionDefinitions = Registry.GetPermissions
function Registry:NormalizePermissionId(id) return self.legacyIds[id] or id end

for id, category in pairs(definitions) do Registry:RegisterPermission({ id=id, module="Core", category=category }) end
for _, id in ipairs({"achievement-view","achievement-create","achievement-edit","achievement-delete","achievement-publish","achievement-award","achievement-revoke","achievement-admin","achievement-test"}) do
    Registry:RegisterPermission({ id=id, module="Achievements", category="Achievements" })
end

HolyStorm.PermissionRegistry = Registry
HolyStorm.PermissionComponents = HolyStorm.PermissionComponents or {}
HolyStorm.PermissionComponents.Registry = Registry
