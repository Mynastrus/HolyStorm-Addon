-- Runtime fakes for pooled POI World Map and Minimap lifecycle.
local workspace=(arg[0]:gsub("tools[/\\]test_poi_map_runtime.lua$",""))
local entries={{poiID="poi-one",revision=1,revisionID="r-one",mapID=84,x=.25,y=.75,name="One",icon="marker",color={r=1,g=.8,b=0,a=1},target="PERSONAL"},{poiID="poi-two",revision=1,revisionID="r-two",mapID=84,x=.75,y=.25,name="Two",icon="marker",color={r=1,g=.8,b=0,a=1},target="PERSONAL"}}
local settings={worldMapEnabled=true,minimapEnabled=true,worldMapSize=22,minimapSize=18}
local stats={transform=0,context=0,projection=0,minimapFrames=0,worldFrames=0,providerAdds=0,providerRemoves=0,worldAcquire=0,worldRemove=0,setMapID=0}
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
local canvas={mapID=84,pins={},activePins={}}
function canvas:GetMapID()return self.mapID end
function canvas:GetNumActivePinsByTemplate()local n=0;for _ in pairs(self.activePins)do n=n+1 end;return n end
function canvas:RemoveAllPinsByTemplate()for pin in pairs(self.activePins)do pin.active=false;pin:OnReleased()end;self.activePins={}end
function canvas:AcquirePin(_,entry)
 local pin;for _,candidate in ipairs(self.pins)do if not candidate.active then pin=candidate;break end end
 if not pin then pin=fakeFrame("world-pin");pin.icon=fakeTexture();pin.glow=fakeTexture();pin.OnAcquired=HolyStormPOIPinMixin.OnAcquired;pin.OnReleased=HolyStormPOIPinMixin.OnReleased;self.pins[#self.pins+1]=pin;stats.worldFrames=stats.worldFrames+1 end
 stats.worldAcquire=stats.worldAcquire+1;pin.active=true;self.activePins[pin]=true;pin:OnAcquired(entry);return pin
end
function canvas:RemovePin(pin)if self.activePins[pin]then self.activePins[pin]=nil;pin.active=false;pin:OnReleased();stats.worldRemove=stats.worldRemove+1 end end
local world={canvas=canvas,shown=false,dataProviders={}}
function world:HookScript(event,callback)self[event]=callback end
function world:IsVisible()return self.shown end
function world:AddDataProvider(provider)self.provider=provider;self.dataProviders[provider]=true;stats.providerAdds=stats.providerAdds+1;if provider.OnAdded then provider:OnAdded(self)end;provider:RefreshAllData()end
function world:RemoveDataProvider(provider)if self.provider==provider then provider:RemoveAllData();self.dataProviders[provider]=nil;self.provider=nil;stats.providerRemoves=stats.providerRemoves+1 end end
function world:SetMapID(mapID)stats.setMapID=stats.setMapID+1;canvas.mapID=mapID;for provider in pairs(self.dataProviders)do if provider.OnMapChanged then provider:OnMapChanged()end end end
function world:GetMapID()return canvas:GetMapID()end
function world:AcquirePin(template,entry)return canvas:AcquirePin(template,entry)end
function world:RemovePin(pin)return canvas:RemovePin(pin)end
function world:RemoveAllPinsByTemplate(template)return canvas:RemoveAllPinsByTemplate(template)end
function world:GetNumActivePinsByTemplate(template)return canvas:GetNumActivePinsByTemplate(template)end
local minimap=fakeFrame("minimap");function minimap:GetFrameLevel()return self.level end
GameTooltip={Hide=function()end}
WorldMapFrame=world;Minimap=minimap;MapCanvasPinMixin={};MapCanvasDataProviderMixin={GetMap=function(self)return self.mapCanvas end,OnAdded=function(self,map)self.mapCanvas=map end}
function CreateFromMixins(...)local object={};for index=1,select("#",...)do for key,value in pairs(select(index,...))do object[key]=value end end;return object end
function CreateFrame(kind,name,parent)if parent==Minimap then stats.minimapFrames=stats.minimapFrames+1 end;return fakeFrame(kind,parent)end
local mapParents={[84]=85,[85]=1,[86]=85,[200]=201,[201]=1}
C_Map={GetMapInfo=function(mapID)if mapID==84 or mapID==85 or mapID==86 or mapID==1 or mapID==200 or mapID==201 then return{mapID=mapID,parentMapID=mapParents[mapID]}end end}
local locale=setmetatable({},{__index=function(_,key)return key end})
local addon={Utils={Now=function()return 100 end,TableCount=function(t)local n=0;for _ in pairs(t or{})do n=n+1 end;return n end},Events={Register=function()end,UnregisterOwner=function()end,Emit=function()end},Logger={Write=function(_,_,_,_,message,context)if message=="World map POI provider unavailable"then print("map failure",context and context.reason)end end},MapLinks={temporaryMarker=nil,poiProviders={},minimapUpdaters={}}}
function addon.MapLinks:RegisterPOIProvider(id,provider)self.poiProviders[id]=provider;return true end
function addon.MapLinks:UnregisterPOIProvider(id)self.poiProviders[id]=nil;return true end
function addon.MapLinks:RegisterMinimapUpdater(id,callback)self.minimapUpdaters[id]=callback;return true end
function addon.MapLinks:SetMinimapUpdaterActive(id,active)self.minimapActive=self.minimapActive or{};self.minimapActive[id]=active==true;return true end
function addon.MapLinks:UnregisterMinimapUpdater(id)self.minimapUpdaters[id]=nil;return true end
function addon.MapLinks:GetMinimapContext()stats.context=stats.context+1;return{mapID=84,x=.5,y=.5,width=100,height=100,radius=100,pixelRadius=40,rotate=true,facing=.5}end
function addon.MapLinks:IsValidMapID(mapID)return type(mapID)=="number"and mapID>0 and mapID%1==0 end
function addon.MapLinks:IsValidCoordinate(mapID,x,y)return self:IsValidMapID(mapID)and type(x)=="number"and x==x and x>=0 and x<=1 and type(y)=="number"and y==y and y>=0 and y<=1 end
function addon.MapLinks:IsMapRelated(first,second)
 if first==second then return true end
 local function ancestor(mapID,wanted)local seen={};for _=1,20 do if seen[mapID]then return false end;seen[mapID]=true;mapID=mapParents[mapID];if mapID==wanted then return true end;if not mapID then return false end end;return false end
 return ancestor(first,second)or ancestor(second,first)
end
function addon.MapLinks:TransformCoordinate(source,x,y,target)stats.transform=stats.transform+1;if not self:IsValidCoordinate(source,x,y)or not self:IsValidMapID(target)then return nil,"INVALID_COORDINATE"end;if source==target then return x,y,"DIRECT"end;if source==84 and target==85 then return x*.5,y*.5,"TRANSFORMED"end;if source==84 and target==1 then return x*.1,y*.1,"TRANSFORMED"end;return nil,"UNSUPPORTED"end
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
assert(Map:Initialize()and stats.providerAdds==0,"repeated initialization remains safe before the World Map opens")
world.shown=true;world.OnShow(world)
assert(world.provider and stats.providerAdds==1,"opening the World Map installs its provider on demand")
assert(addon.MapLinks.minimapActive.poi==true,"POI enables minimap work only while visible POIs and minimap display are active")
assert(#Map.activeEntries==2,"map snapshots both POIs")
assert(stats.worldFrames==2 and stats.minimapFrames==2 and canvas:GetNumActivePinsByTemplate("HolyStormPOIPinTemplate")==2,"opening the World Map immediately creates pooled pins from the active POIs")
assert(stats.context==1 and stats.projection==2 and stats.transform==2,"one validated Minimap context and shared coordinate transforms serve the initial OnShow pass")
assert(Map:GetRenderState("poi-one").worldPin and Map:GetRenderState("poi-one").transform=="DIRECT" and Map:GetWorldMapDiagnostics().exactMapMatches==2,"exact source-map POIs render and are counted")
local acquisitions=stats.worldAcquire;world.shown=false;world.shown=true;world.OnShow(world);assert(stats.providerAdds==1 and stats.worldAcquire==acquisitions,"repeated map close/open events do not duplicate providers or pins")
assert(Map:Refresh("IDEMPOTENT"));assert(stats.worldFrames==2 and stats.worldAcquire==acquisitions and stats.minimapFrames==2 and stats.context==3 and stats.projection==6 and stats.transform==2,"refresh reuses active pins and cached transforms")
assert(Map:Refresh("IDEMPOTENT_AGAIN"));assert(stats.worldFrames==2 and stats.worldAcquire==acquisitions and stats.transform==2,"repeated refresh is idempotent")
local contexts=stats.context;assert(Map:RefreshMinimap(false)==false and stats.context==contexts,"shared updater obeys the one-second throttle")
addon.Utils.Now=function()return 102 end;assert(Map:RefreshMinimap(false));assert(stats.context==contexts+1 and stats.minimapFrames==2,"elapsed Minimap pass reuses marker frames")
settings.minimapEnabled=false;Map:Refresh();assert(addon.MapLinks.minimapActive.poi==false,"disabling POI minimap markers stops its shared updater");for _,pin in ipairs(Map.minimapPins)do assert(not pin.shown and pin.entry==nil,"Minimap disable hides and resets pooled pins")end
settings.minimapEnabled=true;world:SetMapID(85);local navigations=stats.setMapID;assert(Map:GetWorldMapDiagnostics().viewedMapID==85 and Map:GetRenderState("poi-one").worldPin and Map:GetRenderState("poi-one").transform=="TRANSFORMED","child source POI transforms to its parent map on Blizzard's map-change callback");assert(stats.setMapID==navigations,"POI provider refresh never changes the viewed map")
entries[2].mapID=200;Map:Refresh("UNRELATED_TEST");assert(not Map:GetRenderState("poi-two").worldPin and Map:GetWorldMapDiagnostics().skippedUnsupportedTransformations==1,"unrelated map POI does not render")
entries[2].mapID=86;Map:Refresh("UNSUPPORTED_PARENT_TEST");assert(not Map:GetRenderState("poi-two").worldPin and stats.setMapID==navigations,"unsupported related-map transform is skipped without navigation")
entries[2].mapID=999;Map:Refresh("INVALID_SOURCE_MAP");assert(not Map:GetRenderState("poi-two").worldPin and Map:GetWorldMapDiagnostics().invalidMapIDs==1,"invalid source map IDs never reach AcquirePin")
local beforeInvalid=stats.worldAcquire;world:SetMapID(nil);assert(Map:GetWorldMapDiagnostics().viewedMapID==nil and Map:GetWorldMapDiagnostics().lastRenderingFailureReason=="VIEWED_MAP_UNAVAILABLE" and stats.worldAcquire==beforeInvalid,"nil viewed map clears stale pins and cannot reach AcquirePin")
world:SetMapID(84);entries[2].mapID=84;entries[2].x=math.huge;Map:Refresh("INVALID_COORDINATE");assert(not Map:GetRenderState("poi-two").worldPin and Map:GetWorldMapDiagnostics().invalidCoordinates==1,"invalid coordinates never reach AcquirePin")
entries[2].x=.75;Map:Refresh("RESTORE_COORDINATE");assert(Map:GetRenderState("poi-two").worldPin and canvas:GetNumActivePinsByTemplate("HolyStormPOIPinTemplate")==2,"restored valid data reuses the released pin pool")
local worldAcquired=stats.worldAcquire;settings.worldMapEnabled=false;Map:Refresh("WORLD_MAP_DISABLED");assert(not Map:GetRenderState("poi-one").worldPin and Map:GetWorldMapDiagnostics().activePins==0 and stats.worldAcquire==worldAcquired,"World Map setting removes only World Map pins")
assert(Map:GetRenderState("poi-one").minimapPin and Map:GetRenderState("poi-two").minimapPin,"disabling World Map markers leaves independently enabled Minimap markers intact: "..tostring(Map:GetRenderState("poi-one").minimapPin).."/"..tostring(Map:GetRenderState("poi-two").minimapPin).." active="..tostring(Map:GetWorldMapDiagnostics().activePins))
settings.worldMapEnabled=true;Map:Refresh("WORLD_MAP_ENABLED");assert(Map:GetRenderState("poi-one").worldPin,"World Map re-enables without changing Minimap state")
assert(Map:Shutdown());assert(not world.provider and stats.providerRemoves==1 and addon.MapLinks.minimapUpdaters.poi==nil and addon.MapLinks.minimapActive.poi==false and addon.MapLinks.poiProviders["holy-storm-poi"]==nil,"shutdown unregisters world map, Minimap, and MapLinks providers")
assert(Map:Initialize() and Map:Refresh("REINITIALIZE"));assert(stats.providerAdds==2 and stats.providerRemoves==1 and stats.worldFrames==2 and Map:GetWorldMapDiagnostics().providerRegistrationCount==2,"reinitialization adds one provider and reuses pooled frames")
assert(Map:Refresh("REPEATED_MAP_CHANGE"));assert(stats.providerAdds==2 and Map:GetWorldMapDiagnostics().activePins==2,"repeated map refreshes leave exactly one active pin per visible POI")
print("POI World Map assertion contract, exact/parent/unrelated map rendering, validation, idempotent provider and pin lifecycle, Minimap independence and diagnostics tests passed")
