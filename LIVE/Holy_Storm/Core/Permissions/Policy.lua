local addonVersion = "5.0.0"
local HolyStorm = LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local Components = HolyStorm.PermissionComponents

local Policy = {
    version=addonVersion,
    status=Components.State.status,
    systemIds=Components.Groups.systemIds,
    maxHistory=Components.State.maxHistory,
    maxRejected=Components.State.maxRejected,
    maxObjects=Components.State.maxObjects,
    sequence=0,
    permissionCache={},
    membershipCache={},
    generation=0,
}

local ordered = { Components.State, Components.Groups, Components.Filters, Components.Engine, Components.Sync }
for _, component in ipairs(ordered) do
    for name, implementation in pairs(component) do
        if type(implementation) == "function" then Policy[name] = implementation end
    end
end

local function publicView(component)
    local view = { version=component.version }
    for name, implementation in pairs(component) do
        if type(implementation) == "function" then
            local method = implementation
            view[name] = function(_, ...) return method(Policy, ...) end
        else
            view[name] = implementation
        end
    end
    return view
end

HolyStorm.Policy = Policy
HolyStorm.PolicyState = publicView(Components.State)
HolyStorm.GroupManager = publicView(Components.Groups)
HolyStorm.FilterManager = publicView(Components.Filters)
HolyStorm.PermissionEngine = publicView(Components.Engine)
HolyStorm.PermissionSync = publicView(Components.Sync)
