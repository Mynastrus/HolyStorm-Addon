local addonVersion = "2.1.0"
local HolyStorm = LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local L = LibStub("AceLocale-3.0"):GetLocale("Holy_Storm_SavedVariables")

local SavedVariables = HolyStorm:RegisterRequiredModule("SavedVariables")
HolyStorm:ApplyModuleMetadata(SavedVariables, {
    displayName = L["DISPLAY_NAME"], internalName = "savedVariables", version = addonVersion,
    category = "required", description = L["DESCRIPTION"], permissions = { "savedvariables-read" },
    dependencies = { "core", "options" }, enabledByDefault = true,
})

local MAX_DEPTH, MAX_LINES, MAX_TREE_NODES = 32, 5000, 5000

local function SerializeKey(key)
    local keyType = type(key)
    if keyType == "string" then
        return string.format("%q", key)
    end
    if keyType == "number" or keyType == "boolean" then
        return tostring(key)
    end

    -- Lua also permits tables, functions, threads and userdata as table keys.
    -- This page is a diagnostic viewer, so represent those keys safely instead
    -- of recursively serializing them or exposing them to the output line cap.
    return string.format("%q", "<" .. keyType .. ": " .. tostring(key) .. ">")
end

local function SerializeScalar(value)
    local valueType = type(value)
    if valueType == "string" then
        return string.format("%q", value)
    end
    if valueType == "number" or valueType == "boolean" or valueType == "nil" then
        return tostring(value)
    end
    return string.format("%q", "<" .. valueType .. ": " .. tostring(value) .. ">")
end

local function DisplayKey(key)
    local keyType = type(key)
    if keyType == "string" then return key end
    if keyType == "number" or keyType == "boolean" then return "[" .. tostring(key) .. "]" end
    return "<" .. keyType .. ": " .. tostring(key) .. ">"
end

local function SortedKeys(value)
    local keys = {}
    for key in pairs(value) do table.insert(keys, key) end
    table.sort(keys, function(left, right)
        local leftType, rightType = type(left), type(right)
        if leftType ~= rightType then return leftType < rightType end
        return tostring(left) < tostring(right)
    end)
    return keys
end

local function AppendLine(owner, lines, value)
    if owner.lineCount >= MAX_LINES then return false end
    table.insert(lines, value)
    owner.lineCount = owner.lineCount + 1
    return true
end

local function AppendSerialized(owner, value, depth, visited, lines, prefix, trailingComma)
    if owner.lineCount >= MAX_LINES then return false end

    local indent = string.rep("  ", depth)
    local suffix = trailingComma and "," or ""
    if type(value) ~= "table" then
        return AppendLine(owner, lines, indent .. prefix .. SerializeScalar(value) .. suffix)
    end
    if visited[value] then
        return AppendLine(owner, lines, indent .. prefix .. string.format("%q", L["CIRCULAR_REFERENCE"]) .. suffix)
    end
    if depth >= MAX_DEPTH then
        return AppendLine(owner, lines, indent .. prefix .. string.format("%q", L["MAX_DEPTH"]) .. suffix)
    end

    local keys = SortedKeys(value)
    if #keys == 0 then
        return AppendLine(owner, lines, indent .. prefix .. L["EMPTY_TABLE"] .. suffix)
    end

    visited[value] = true
    if not AppendLine(owner, lines, indent .. prefix .. "{") then
        visited[value] = nil
        return false
    end
    for _, key in ipairs(keys) do
        local keyText = SerializeKey(key)
        if not AppendSerialized(owner, value[key], depth + 1, visited, lines, "[" .. keyText .. "] = ", true) then
            visited[value] = nil
            return false
        end
    end
    visited[value] = nil
    return AppendLine(owner, lines, indent .. "}" .. suffix)
end

function SavedVariables:Serialize(value, depth, visited, lines)
    if type(value) ~= "table" then return SerializeScalar(value) end
    AppendSerialized(self, value, depth, visited, lines, "", false)
end

function SavedVariables:GetOutputText(variableName)
    local value = _G[variableName]
    if value == nil then return L["NOT_LOADED"] end
    self.lineCount = 0
    local lines = {}
    local serialized = self:Serialize(value, 0, {}, lines)
    if serialized then table.insert(lines, serialized) end
    if self.lineCount >= MAX_LINES then table.insert(lines, string.format(L["TRUNCATED"], MAX_LINES)) end
    return table.concat(lines, "\n")
end

local function BuildTreeOptions(owner, value, depth, ancestors)
    local args = {}
    local keys = SortedKeys(value)
    if #keys == 0 then
        args.empty = { type = "description", name = L["EMPTY_TABLE"], order = 1 }
        return args
    end

    for index, key in ipairs(keys) do
        if owner.treeNodeCount >= MAX_TREE_NODES then
            args.truncated = {
                type = "description",
                name = string.format(L["TREE_TRUNCATED"], MAX_TREE_NODES),
                order = index,
            }
            break
        end

        owner.treeNodeCount = owner.treeNodeCount + 1
        local child = value[key]
        local entryId = "entry_" .. owner.treeNodeCount
        local keyText = DisplayKey(key)
        if type(child) ~= "table" then
            args[entryId] = {
                type = "description",
                name = keyText .. " = " .. SerializeScalar(child),
                order = index,
            }
        elseif ancestors[child] then
            args[entryId] = {
                type = "description",
                name = keyText .. " = " .. L["CIRCULAR_REFERENCE"],
                order = index,
            }
        elseif depth >= MAX_DEPTH then
            args[entryId] = {
                type = "description",
                name = keyText .. " = " .. L["MAX_DEPTH"],
                order = index,
            }
        else
            ancestors[child] = true
            local childArgs = BuildTreeOptions(owner, child, depth + 1, ancestors)
            ancestors[child] = nil
            args[entryId] = {
                type = "group",
                name = keyText,
                order = index,
                childGroups = "tree",
                args = childArgs,
            }
        end
    end
    return args
end

function SavedVariables:InvalidateTree()
    self.treeVariable = nil
    self.treeOptions = nil
end

function SavedVariables:EnsureTreeOptions()
    if self.treeVariable == self.selectedVariable and self.treeOptions then return end

    local value = _G[self.selectedVariable]
    self.treeNodeCount = 0
    if value == nil then
        self.treeOptions = {
            notLoaded = { type = "description", name = L["NOT_LOADED"], order = 1 },
        }
    elseif type(value) == "table" then
        local ancestors = { [value] = true }
        self.treeOptions = BuildTreeOptions(self, value, 0, ancestors)
    else
        self.treeOptions = {
            value = { type = "description", name = SerializeScalar(value), order = 1 },
        }
    end
    self.treeVariable = self.selectedVariable

    if self.optionsTab and self.optionsTab.args.treeView then
        self.optionsTab.args.treeView.args = self.treeOptions
    end
end

function SavedVariables:OnInitialize()
    local Options = HolyStorm:GetModule("Options", true)
    local UI = HolyStorm:GetModule("UI", true)
    self.selectedVariable = "HolyStormDB"
    self.optionsTab = {
        type = "group", name = L["OPTIONS_TAB_TITLE"], order = 3, childGroups = "tab",
        args = {
            database = {
                type = "select", name = L["SELECT_LABEL"], order = 1, width = "double",
                values = { HolyStormDB = L["DATABASE_HOLYSTORM"], HS_Player_DB = L["DATABASE_PLAYERS"], HS_GuildLog_DB = L["DATABASE_GUILD_LOG"] },
                get = function() return SavedVariables.selectedVariable end,
                set = function(_, value)
                    SavedVariables.selectedVariable = value
                    SavedVariables:InvalidateTree()
                    LibStub("AceConfigRegistry-3.0"):NotifyChange("HolyStormOptions")
                end,
            },
            refresh = {
                type = "execute", name = L["REFRESH"], desc = L["REFRESH_TOOLTIP"], order = 2,
                func = function()
                    SavedVariables:InvalidateTree()
                    LibStub("AceConfigRegistry-3.0"):NotifyChange("HolyStormOptions")
                end,
            },
            treeView = {
                type = "group", order = 3, childGroups = "tree", args = {},
                name = function()
                    SavedVariables:EnsureTreeOptions()
                    return L["TREE_VIEW"]
                end,
            },
            textView = {
                type = "group", name = L["TEXT_VIEW"], order = 4,
                args = {
                    content = {
                        type = "input", name = L["CONTENT"], desc = L["CONTENT_DESCRIPTION"], order = 1,
                        multiline = 24, width = "full",
                        get = function() return SavedVariables:GetOutputText(SavedVariables.selectedVariable) end,
                        set = function() return false end,
                    },
                },
            },
        },
    }
    Options:RegisterOptionsTab("savedVariables", self.optionsTab)
    local function updateContentHeight(_, _, height)
        self.optionsTab.args.textView.args.content.multiline = math.max(8, math.floor((height - 210) / 14))
        LibStub("AceConfigRegistry-3.0"):NotifyChange("HolyStormOptions")
    end
    UI.content:HookScript("OnSizeChanged", updateContentHeight)
    updateContentHeight(nil, nil, UI.content:GetHeight())
end
