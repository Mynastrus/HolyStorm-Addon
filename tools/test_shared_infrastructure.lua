local script = arg[0]:gsub("\\", "/")
local root = script:match("^(.*)/tools/[^/]+$") or "."
local core = root .. "/LIVE/Holy_Storm/"
local ui = root .. "/LIVE/Holy_Storm_UI/"

local function read(path)
    local file = assert(io.open(path, "rb"))
    local value = file:read("*a")
    file:close()
    return value
end

local names = {
    ["LibDataBroker-1.1"] = "Libs/LibDataBroker-1.1/LibDataBroker-1.1.lua",
    ["LibDBIcon-1.0"] = "Libs/LibDBIcon-1.0/LibDBIcon-1.0.lua",
    ["LibSharedMedia-3.0"] = "Libs/LibSharedMedia-3.0/LibSharedMedia-3.0.lua",
    ["AceComm-3.0"] = "Libs/AceComm-3.0/AceComm-3.0.lua",
    ["AceCommQueue-1.0"] = "Libs/AceCommQueue-1.0/AceCommQueue-1.0.lua",
    ["LibGuildRoster-1.0"] = "Libs/LibGuildRoster-1.0/LibGuildRoster-1.0.lua",
}
local toc = read(core .. "Holy_Storm.toc")
assert(read(core .. names["LibSharedMedia-3.0"]):find('"LibSharedMedia-3.0", 12000002', 1, true), "current LibSharedMedia release is embedded")
for name, path in pairs(names) do
    local source = read(core .. path)
    assert(source:find(name, 1, true), name .. " source is embedded")
    assert(toc:find(path:gsub("/", "\\"), 1, true), name .. " is loaded by Core")
    for addonToc in io.popen('dir /s /b "' .. root:gsub("/", "\\") .. '\\LIVE\\*.toc"'):lines() do
        if not addonToc:find("Holy_Storm.toc", 1, true) then
            local other = read(addonToc)
            assert(not other:find(name, 1, true), name .. " must not be duplicated in feature TOC " .. addonToc)
        end
    end
end
assert(toc:find("Libs\\AceComm-3.0\\ChatThrottleLib.lua", 1, true), "AceComm throttle dependency is loaded first")
assert(toc:find("Libs\\LibStub\\LibStub.lua", 1, true), "central LibStub remains present")
assert(toc:find("Libs\\CallbackHandler-1.0\\CallbackHandler-1.0.lua", 1, true), "central CallbackHandler remains present")
local _, libStubEntries = toc:gsub("Libs\\LibStub\\LibStub.lua", "")
local _, callbackEntries = toc:gsub("Libs\\CallbackHandler%-1%.0\\CallbackHandler%-1%.0.lua", "")
assert(libStubEntries == 1, "only one Core LibStub entry")
assert(callbackEntries == 1, "only one Core CallbackHandler entry")
assert(read(core .. "Libs/AceCommQueue-1.0/LICENSE"):find("MIT License", 1, true), "AceCommQueue license packaged")
assert(read(core .. "Libs/LibGuildRoster-1.0/LICENSE"):find("MIT License", 1, true), "LibGuildRoster license packaged")
assert(read(core .. "Libs/AceComm-3.0/LICENSE.txt"):find("All rights reserved", 1, true), "Ace3 dependency license packaged")
assert(read(core .. "Libs/LibSharedMedia-3.0/COPYING.txt"):find("GNU LESSER GENERAL PUBLIC LICENSE", 1, true), "LGPL license packaged")

local persisted = { minimap = { showIcon = true, minimapPos = 220 } }
local dataObject, registerCount, showCount, hideCount
local libraries = {}
for _, name in ipairs({ "LibQTip-1.0", "LibDataBroker-1.1", "LibDBIcon-1.0", "LibSharedMedia-3.0", "AceComm-3.0", "AceCommQueue-1.0", "LibGuildRoster-1.0" }) do
    libraries[name] = { name = name }
end
libraries["LibDataBroker-1.1"].NewDataObject = function(_, name, object)
    assert(name == "HolyStorm")
    dataObject = object
    return object
end
libraries["LibDBIcon-1.0"].Register = function(_, name, object, settings)
    assert(name == "HolyStorm" and object == dataObject and settings == persisted.minimap)
    registerCount = (registerCount or 0) + 1
end
libraries["LibDBIcon-1.0"].IsRegistered = function(_, name) return name == "HolyStorm" end
libraries["LibDBIcon-1.0"].Show = function(_, name) assert(name == "HolyStorm"); showCount = (showCount or 0) + 1 end
libraries["LibDBIcon-1.0"].Hide = function(_, name) assert(name == "HolyStorm"); hideCount = (hideCount or 0) + 1 end
libraries["LibSharedMedia-3.0"].Fetch = function(_, category, key) return category .. ":" .. key end
libraries["LibSharedMedia-3.0"].List = function(_, category) return { category } end
libraries["LibSharedMedia-3.0"].Register = function() return true end

local stub = { minors = {} }
local driver = { frame = { shown = false } }
function driver.frame:IsShown() return self.shown end
function driver.frame:Hide() self.shown = false end
local HolyStorm = { version = "test", UI = { driver = driver } }
for index, name in ipairs({ "LibQTip-1.0", "LibDataBroker-1.1", "LibDBIcon-1.0", "LibSharedMedia-3.0", "AceComm-3.0", "AceCommQueue-1.0", "LibGuildRoster-1.0" }) do stub.minors[name] = index end
setmetatable(stub, { __call = function(_, name, silent)
    if name == "AceAddon-3.0" then return { GetAddon = function() return HolyStorm end } end
    if name == "AceLocale-3.0" then return { GetLocale = function() return { CORE_DISPLAY_NAME = "Holy Storm", OPEN_HOLY_STORM = "Open Holy Storm", LEFT_CLICK_TO_OPEN_HOLY_STORM = "Left-click to open Holy Storm" } end } end
    if libraries[name] then return libraries[name] end
    if silent then return nil end
    error("unexpected library: " .. tostring(name))
end })
LibStub = stub

HolyStorm.Database = {}
function HolyStorm.Database:Get(path) if path == "minimap" then return persisted.minimap end end
function HolyStorm.Database:Set(path, value) if path == "minimap.showIcon" then persisted.minimap.showIcon = value; return true end end
function HolyStorm.UI:Open() driver.frame.shown = true; return true end

assert(loadfile(core .. "Core/Infrastructure/Libraries.lua"))()
local manager = HolyStorm.Libraries
assert(manager:Initialize())
assert(dataObject and dataObject.type == "launcher", "canonical launcher exists and is a launcher")
assert(dataObject.text == "Holy Storm vtest", "launcher displays current version")
assert(registerCount == 1, "one minimap launcher registration")
dataObject.OnClick(dataObject, "LeftButton")
assert(driver.frame.shown, "launcher opens UI")
dataObject.OnClick(dataObject, "LeftButton")
assert(not driver.frame.shown, "launcher toggles UI closed")
manager:SetMinimapVisible(false)
assert(not persisted.minimap.showIcon and persisted.minimap.hide and hideCount == 1, "hide choice persists in profile DB and hides icon")
manager:SetMinimapVisible(true)
assert(persisted.minimap.showIcon and not persisted.minimap.hide and showCount == 1, "show choice persists in profile DB and shows icon")
assert(manager:FetchMedia("font", "Example") == "font:Example", "shared media is exposed centrally")
assert(manager:GetStatus()["LibQTip-1.0"].version == 1, "library diagnostics report loaded LibQTip version")

local options = read(ui .. "UI/Pages/Options.lua")
assert(options:find("HolyStorm.Libraries:GetMinimapVisible()", 1, true), "normal option reads central setting")
assert(options:find("HolyStorm.Libraries:SetMinimapVisible(value)", 1, true), "normal option writes central setting")
local en = read(ui .. "UI/Pages/OptionsLocales/enUS.lua")
local de = read(ui .. "UI/Pages/OptionsLocales/deDE.lua")
assert(en:find('L["SHOW_MINIMAP_ICON"] = "Show minimap icon"', 1, true), "enUS option localization")
assert(de:find('L["SHOW_MINIMAP_ICON"] = "Minimap-Symbol anzeigen"', 1, true), "deDE option localization")
local sync = read(core .. "Sync/Comms.lua")
assert(sync:find("C_ChatInfo.SendAddonMessage", 1, true), "existing Sync transport stays in place")
local guild = read(core .. "Persistence/GuildStore.lua")
assert(guild:find("GuildStore", 1, true), "existing Holy Storm GuildStore remains present")
assert(not toc:find("DeltaSync", 1, true), "DeltaSync is not integrated")
print("Shared infrastructure tests passed")
