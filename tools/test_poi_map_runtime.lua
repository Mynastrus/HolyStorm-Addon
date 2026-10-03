-- Runtime fakes for pooled POI World Map and Minimap lifecycle.
local workspace=(arg[0]:gsub("tools[/\\]test_poi_map_runtime.lua$",""))
local entries={{poiID="poi-one",revision=1,revisionID="r-one",mapID=84,x=.25,y=.75,name="One",icon="marker",color={r=1,g=.8,b=0,a=1},target="PERSONAL"},{poiID="poi-two",revision=1,revisionID="r-two",mapID=84,x=.75,y=.25,name="Two",icon="marker",color={r=1,g=.8,b=0,a=1},target="PERSONAL"}}
local settings={worldMapEnabled=true,minimapEnabled=true,worldMapSize=22,minimapSize=18}
local stats={transform=0,context=0,projection=0,minimapFrames=0,worldFrames=0,providerAdds=0,providerRemoves=0}
local function fakeTexture()return{SetTexture=function()end,SetBlendMode=function()end,SetPoint=function()end,SetAllPoints=function()end,SetSize=function()end,SetVertexColor=function()end,SetTexCoord=function()end}end
local function fakeFrame(kind,parent)
 local frame={kind=kind,parent=parent,shown=false,level=1,width=100,height=100}
 function frame:SetFrameLevel(level)self.level=level end;function frame:GetFrameLevel()return self.level end
 function frame:CreateTexture()return fakeTexture()end;function frame:SetScript()end;function frame:RegisterForClicks()end
 function frame:SetSize(w,h)self.width,self.height=w,h end;function frame:GetWidth()return self.width end;function frame:GetHeight()return self.height end
 function frame:Show()self.shown=true end;function frame:Hide()self.shown=false end;function frame:ClearAllPoints()end;function frame:SetPoint()end
 function frame:SetTexCoord()end;function frame:SetPosition(x,y)self.x,self.y=x,y end
 return frame
end
local canvas={mapID=84,pins={},cursor=0}
function canvas:GetMapID()return self.mapID end
function canvas:RemoveAllPinsByTemplate()
 self.cursor=0;for _,pin in ipairs(self.pins)do pin:OnReleased()end
end
function canvas:AcquirePin(_,entry)
 self.cursor=self.cursor+1;local pin=self.pins[self.cursor]
 if not pin then pin=fakeFrame("world-pin");pin.icon=fakeTexture();pin.glow=fakeTexture();pin.OnAcquired=HolyStormPOIPinMixin.OnAcquired;pin.OnReleased=HolyStormPOIPinMixin.OnReleased;self.pins[self.cursor]=pin;stats.worldFrames=stats.worldFrames+1 end
 stats.worldAcquire=(stats.worldAcquire or 0)+1
 pin:OnAcquired(entry);return pin
end
local world={canvas=canvas,shown=false}
function world:HookScript(event,callback)self[event]=callback end
function world:IsVisible()return self.shown end
function world:AddDataProvider(provider)self.provider=provider;stats.providerAdds=stats.providerAdds+1;provider:RefreshAllData()end
function world:RemoveDataProvider(provider)if self.provider==provider then provider:RemoveAllData();self.provider=nil;stats.providerRemoves=stats.providerRemoves+1 end end
local minimap=fakeFrame("minimap");function minimap:GetFrameLevel()return self.level end
GameTooltip={Hide=function()end}
WorldMapFrame=world;Minimap=minimap;MapCanvasPinMixin={};MapCanvasDataProviderMixin={GetMap=function()return canvas end}
function CreateFromMixins(...)local object={};for index=1,select("#",...)do for key,value in pairs(select(index,...))do object[key]=value end end;return object end
function CreateFrame(kind,name,parent)if parent==Minimap then stats.minimapFrames=stats.minimapFrames+1 end;return fakeFrame(kind,parent)end
local locale=setmetatable({},{__index=function(_,key)return key end})
local addon={Utils={Now=function()return 100 end,TableCount=function(t)local n=0;for _ in pairs(t or{})do n=n+1 end;return n end},Events={Register=function()end,UnregisterOwner=function()end,Emit=function()end},Logger={Write=function(_,_,_,_,message,context)if message=="World map POI provider unavailable"then print("map failure",context and context.reason)end end},MapLinks={temporaryMarker=nil,poiProviders={},minimapUpdaters={}}}
function addon.MapLinks:RegisterPOIProvider(id,provider)self.poiProviders[id]=provider;return true end
function addon.MapLinks:UnregisterPOIProvider(id)self.poiProviders[id]=nil;return true end
function addon.MapLinks:RegisterMinimapUpdater(id,callback)self.minimapUpdaters[id]=callback;return true end
function addon.MapLinks:SetMinimapUpdaterActive(id,active)self.minimapActive=self.minimapActive or{};self.minimapActive[id]=active==true;return true end
function addon.MapLinks:UnregisterMinimapUpdater(id)self.minimapUpdaters[id]=nil;return true end
function addon.MapLinks:GetMinimapContext()stats.context=stats.context+1;return{mapID=84,x=.5,y=.5,width=100,height=100,radius=100,pixelRadius=40,rotate=true,facing=.5}end
function addon.MapLinks:TransformCoordinate(source,x,y,target)stats.transform=stats.transform+1;if source==999 then return nil,"UNSUPPORTED"end;if source==target then return x,y,"DIRECT"end;if target==85 then return x*.5,y*.5,"TRANSFORMED"end;return nil,"UNSUPPORTED"end
function addon.MapLinks:ProjectToMinimap(_,_,_,_,context,x,y,mode)stats.projection=stats.projection+1;return(x-context.x)*40,(context.y-y)*40,mode,context.mapID,x,y end
local function copy(value)if type(value)~="table"then return value end;local result={};for key,child in pairs(value)do result[key]=copy(child)end;return result end
local poi={}
function poi:GetVisible()return copy(entries)end;function poi:GetSettings()return settings end
function poi:GetIcon()return{texture="test-icon"}end;function poi:GetRemaining()return nil end
function poi:GetTooltip(entry)return entry.name,"",{category="note",target=entry.target,remaining=nil,map="Zone"}end
function poi:CanMutate()return true end
addon.POI=poi
function addon:CallCapability()return true end
function LibStub(name)if name=="AceAddon-3.0"then return{GetAddon=function()return addon end}elseif name=="AceLocale-3.0"then return{GetLocale=function()return locale end}end end

assert(loadfile(workspace.."LIVE/Holy_Storm_POI/Map.lua"))()
local Map=addon.POIMap;assert(Map:Initialize());assert(not world.provider and stats.providerAdds==0 and stats.transform==0,"login loads POIs without installing a hidden World Map provider or transforming coordinates")
world.shown=true;world.OnShow(world)
assert(world.provider and stats.providerAdds==1,"opening the World Map installs its provider on demand")
assert(addon.MapLinks.minimapActive.poi==true,"POI enables minimap work only while visible POIs and minimap display are active")
assert(#Map.activeEntries==2,"map snapshots both POIs")
assert(stats.worldFrames==2 and stats.minimapFrames==2,"opening the World Map immediately creates pooled pins from the active POIs: world="..stats.worldFrames.." acquired="..tostring(stats.worldAcquire).." minimap="..stats.minimapFrames)
assert(stats.context==1 and stats.projection==2 and stats.transform==2,"one validated Minimap context and shared coordinate transforms serve the initial OnShow pass")
assert(Map:Refresh());assert(stats.worldFrames==2 and stats.minimapFrames==2 and stats.context==2 and stats.projection==4 and stats.transform==2,"explicit refresh reuses both pin pools and cached transforms")
assert(Map:Refresh());assert(stats.worldFrames==2 and stats.minimapFrames==2 and stats.transform==2,"refresh reuses both pin pools and cached transforms")
local contexts=stats.context;assert(Map:RefreshMinimap(false)==false and stats.context==contexts,"shared updater obeys the one-second throttle")
addon.Utils.Now=function()return 102 end;assert(Map:RefreshMinimap(false));assert(stats.context==contexts+1 and stats.minimapFrames==2,"elapsed Minimap pass reuses marker frames")
settings.minimapEnabled=false;Map:Refresh();assert(addon.MapLinks.minimapActive.poi==false,"disabling POI minimap markers stops its shared updater");for _,pin in ipairs(Map.minimapPins)do assert(not pin.shown and pin.entry==nil,"Minimap disable hides and resets pooled pins")end
settings.minimapEnabled=true;canvas.mapID=85;assert(canvas:GetMapID()==85 and Map.worldProvider~=nil);Map:Refresh();assert(Map:GetRenderState("poi-one").viewedMapID==85 and Map:GetRenderState("poi-one").worldPin,"map switch uses exact transformed coordinates: viewed="..tostring(Map:GetRenderState("poi-one").viewedMapID).." world="..tostring(Map:GetRenderState("poi-one").worldPin))
entries[2].mapID=999;Map:Refresh();assert(not Map:GetRenderState("poi-two").worldPin,"unsupported map transform hides the World Map marker")
settings.worldMapEnabled=false;Map:Refresh();assert(not Map:GetRenderState("poi-one").worldPin,"World Map setting independently removes visible pins")
assert(Map:Shutdown());assert(not world.provider and stats.providerRemoves==1 and addon.MapLinks.minimapUpdaters.poi==nil and addon.MapLinks.minimapActive.poi==false and addon.MapLinks.poiProviders["holy-storm-poi"]==nil,"shutdown unregisters world map, Minimap, and MapLinks providers")
assert(Map:Initialize() and Map:Refresh());assert(stats.providerAdds==2 and stats.worldFrames==2,"repeated open/close reuses the World Map pool without leaking frames")
print("POI map runtime pin reuse, minimap throttling, transform caching, map switching, setting independence and teardown tests passed")
