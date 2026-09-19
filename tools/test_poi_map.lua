local root = (arg[0]:gsub("tools[/\\]test_poi_map.lua$", "")) .. "LIVE/Holy_Storm/"
local function read(path)
    local file = assert(io.open(root .. path, "r"))
    local value = file:read("*a")
    file:close()
    return value
end

local xml = read("Modules/POI/Map.xml")
assert(not xml:find("inherits=\"MapCanvasPinTemplate\"", 1, true), "POI must not inherit the removed global pin template")
assert(xml:find("MapCanvasPinMixin", 1, true) and xml:find("HolyStormPOIPinMixin", 1, true), "POI pin must use explicit MapCanvas mixins")

local map = read("Modules/POI/Map.lua")
assert(map:find("MapCanvasPinMixin", 1, true) and map:find("canvas:AcquirePin(\"HolyStormPOIPinTemplate\"", 1, true), "POI must acquire registered pins through MapCanvas")
assert(map:find("MAPCANVAS_NOT_READY", 1, true) and map:find("worldMapFailed", 1, true), "POI refresh must guard unavailable MapCanvas infrastructure")
assert(map:find("pcall(self.worldProvider.RefreshAllData", 1, true), "POI refresh must contain provider failures")

local toc = read("Holy_Storm.toc")
assert(toc:find("## RequiredDeps: Blizzard_MapCanvas", 1, true), "TOC must load Blizzard MapCanvas first")
assert((toc:find("Modules/POI/Map.lua", 1, true) or toc:find("Modules\\POI\\Map.lua", 1, true)) and (toc:find("Modules/POI/Map.xml", 1, true) or toc:find("Modules\\POI\\Map.xml", 1, true)), "POI map files must be in the TOC")
print("POI MapCanvas template, refresh guard and load-order checks passed")
