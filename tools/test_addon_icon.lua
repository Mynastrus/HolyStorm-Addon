local script = arg[0]:gsub("\\", "/")
local root = script:match("^(.*)/tools/[^/]+$") or "."

local function read(path)
    local file = assert(io.open(path, "rb"), path)
    local value = file:read("*a")
    file:close()
    return value
end

local core = read(root .. "/LIVE/Holy_Storm/Core/Infrastructure/Libraries.lua")
local toc = read(root .. "/LIVE/Holy_Storm/Holy_Storm.toc")
local mainWindow = read(root .. "/LIVE/Holy_Storm_UI/UI/Framework/MainWindow.lua")
local assetPath = root .. "/LIVE/Holy_Storm/Images/minimap_logo.png"
local asset = assert(io.open(assetPath, "rb"), assetPath)
local header = asset:read(24)
asset:close()

local canonical = "Interface\\AddOns\\Holy_Storm\\Images\\minimap_logo.png"
local canonicalSource = "Interface\\\\AddOns\\\\Holy_Storm\\\\Images\\\\minimap_logo.png"
assert(core:find('ADDON_ICON = "' .. canonicalSource .. '"', 1, true), "core exposes the one canonical icon path")
assert(core:find('ADDON_ICON_FALLBACK = "Interface\\\\Icons\\\\INV_Misc_QuestionMark"', 1, true), "core retains a Blizzard fallback")
assert(core:find("icon = self.ADDON_ICON or self.ADDON_ICON_FALLBACK", 1, true), "the configured LDB icon is canonical")
assert(not core:find("icon = \"Interface\\\\Icons\\\\INV_Misc_QuestionMark\"", 1, true), "question mark is not the configured launcher icon")
assert(select(2, core:gsub("Interface\\\\AddOns\\\\Holy_Storm\\\\Images\\\\minimap_logo.png", "")) == 1, "Lua code contains one hardcoded addon-icon path")
assert(toc:find("## IconTexture: " .. canonical, 1, true), "Retail addon metadata uses the same icon asset")
assert(mainWindow:find("HolyStorm.Libraries and HolyStorm.Libraries.ADDON_ICON", 1, true), "main frame reads the shared icon path")
assert(mainWindow:find("ADDON_ICON_FALLBACK", 1, true), "main frame keeps a failure fallback")
assert(mainWindow:find("frame.portrait or frame.Portrait", 1, true), "main icon occupies the native ButtonFrame portrait slot")
assert(mainWindow:find("SetImage(model.specIcon)", 1, true), "specialization icon remains a separate dashboard widget")
assert(mainWindow:find("identityText:SetRelativeWidth(0.70)", 1, true), "identity text fits beside both existing identity icons at the minimum width")
assert(header:sub(1, 8) == "\137PNG\r\n\26\n", "canonical addon asset is a PNG")
local width, height = header:byte(17) * 16777216 + header:byte(18) * 65536 + header:byte(19) * 256 + header:byte(20), header:byte(21) * 16777216 + header:byte(22) * 65536 + header:byte(23) * 256 + header:byte(24)
assert(width == 1024 and height == 1024, "WoW texture dimensions are power-of-two and square")

local pngCount = 0
for _, addon in ipairs({ "Holy_Storm", "Holy_Storm_UI", "Holy_Storm_Chat", "Holy_Storm_Characters", "Holy_Storm_Equipment", "Holy_Storm_Raids", "Holy_Storm_MythicPlus", "Holy_Storm_Delves", "Holy_Storm_Calendar", "Holy_Storm_Professions", "Holy_Storm_Guild", "Holy_Storm_GuildLog", "Holy_Storm_News", "Holy_Storm_Achievements", "Holy_Storm_POI", "Holy_Storm_Positions" }) do
    local candidate = io.open(root .. "/LIVE/" .. addon .. "/Images/minimap_logo.png", "rb")
    if candidate then pngCount = pngCount + 1; candidate:close() end
end
assert(pngCount == 1, "only the core addon package contains the Holy Storm icon asset")

local dashboard = read(root .. "/tools/test_dashboard.lua")
for _, source in ipairs({ "GetDashboardSummary", "HS_CHARACTER_UPDATED", "HS_EQUIPMENT_UPDATED", "HS_MYTHICPLUS_UPDATED", "HS_RAIDLOCKS_UPDATED" }) do
    assert(dashboard:find(source, 1, true), "dashboard data contract remains covered: " .. source)
end
local scans = read(root .. "/LIVE/Holy_Storm_UI/UI/Framework/MainWindow.lua")
assert(not scans:find("C_Timer.NewTicker", 1, true) and not scans:find("HS_Player_DB", 1, true), "icon and UI integration add no dashboard scan or polling")

print("Canonical addon icon asset and integration tests passed")
