local addonVersion="1.1.0"
local HolyStorm=LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local L=LibStub("AceLocale-3.0"):GetLocale("Holy_Storm_POI")
local Map={version=addonVersion,worldProvider=nil,minimapPins={},activeWorldPins={},renderState={},activeEntries={},transformCache={},elapsed=0,installed=false,initialized=false,lastMinimapRefresh=0,lastMinimapSignature=nil,worldMapUnavailableLogged=false,worldMapFailed=false,worldMapDiagnostics={viewedMapID=nil,localActivePOICount=0,scopeVisiblePOICount=0,exactMapMatches=0,transformedParentMatches=0,skippedUnsupportedTransformations=0,invalidMapIDs=0,invalidCoordinates=0,acquiredPins=0,activePins=0,providerRegistrationCount=0,lastRefreshReason="INITIALIZE",lastRenderingFailureReason=nil}}
local function remaining(seconds)if not seconds then return L["POI_PERMANENT"]end;if seconds<60 then return string.format(L["POI_SECONDS"],math.ceil(seconds))elseif seconds<3600 then return string.format(L["POI_MINUTES"],math.ceil(seconds/60))end;return string.format(L["POI_HOURS"],math.ceil(seconds/3600))end
function Map:GetEntries()
 local out=HolyStorm.POI:GetVisible();local marker=HolyStorm.MapLinks.temporaryMarker;if marker then if marker.expiresAt and marker.expiresAt<=HolyStorm.Utils.Now()then HolyStorm.MapLinks:ClearTemporaryMarker()else marker.name=marker.name or L["POI_TEMPORARY_MARKER"];marker.icon="marker";marker.color={r=1,g=.82,b=0,a=1};marker.category="note";marker.creatorName=UnitName("player");out[#out+1]=marker end end;return out
end
function Map:ShowTooltip(owner,entry)
 local title,description,meta=HolyStorm.POI:GetTooltip(entry);if entry.temporary then title,description,meta=entry.name,nil,{category=L["POI_TEMPORARY"],creator=UnitName("player"),remaining=entry.expiresAt and(entry.expiresAt-HolyStorm.Utils.Now()),target="PERSONAL",map=HolyStorm.POI:GetMapName(entry.mapID)}end
 GameTooltip:SetOwner(owner,"ANCHOR_CURSOR_RIGHT");GameTooltip:SetText(title or entry.poiID);if description and description~=""then GameTooltip:AddLine(description,1,1,1,true)end
 GameTooltip:AddDoubleLine(L["POI_TOOLTIP_CATEGORY"],meta.category or"-",1,.82,0,1,1,1);GameTooltip:AddDoubleLine(L["POI_TOOLTIP_TARGET"],L["POI_TARGET_"..meta.target]or meta.target,1,.82,0,1,1,1)
 if meta.map then GameTooltip:AddDoubleLine(L["POI_TOOLTIP_MAP"],meta.map,1,.82,0,1,1,1)end;if meta.creator then GameTooltip:AddDoubleLine(L["POI_TOOLTIP_CREATOR"],meta.creator,1,.82,0,1,1,1)end
 if meta.createdAt then GameTooltip:AddDoubleLine(L["POI_TOOLTIP_CREATED"],date(L["DATE_FORMAT"],meta.createdAt),1,.82,0,1,1,1)end
 if meta.updatedAt and meta.updatedAt~=meta.createdAt then GameTooltip:AddDoubleLine(L["POI_TOOLTIP_UPDATED"],date(L["DATE_FORMAT"],meta.updatedAt),1,.82,0,1,1,1)end
 GameTooltip:AddDoubleLine(L["POI_TOOLTIP_LIFETIME"],remaining(meta.remaining),1,.82,0,1,1,1);GameTooltip:Show()
end
function Map:ConfirmDelete(entry)if not StaticPopupDialogs then return end;StaticPopupDialogs.HOLYSTORM_POI_DELETE={text=L["POI_CONFIRM_DELETE"],button1=YES,button2=NO,OnAccept=function()HolyStorm.POI:Delete(entry.poiID,entry.revision)end,timeout=0,whileDead=true,hideOnEscape=true};StaticPopup_Show("HOLYSTORM_POI_DELETE",entry.name)end
function Map:OpenContext(owner,entry)
 if not MenuUtil or not MenuUtil.CreateContextMenu then HolyStorm:CallCapability("poi.open",entry.poiID);return end;MenuUtil.CreateContextMenu(owner,function(_,root)root:CreateTitle(entry.name);root:CreateButton(L["POI_DETAILS"],function()HolyStorm:CallCapability("poi.open",entry.poiID)end);root:CreateButton(L["POI_SHOW_ON_MAP"],function()HolyStorm.POI:Open(entry.poiID)end);if not entry.temporary then root:CreateButton(L["POI_HIDE_LOCAL"],function()HolyStorm.POI:SetHidden(entry.poiID,true)end);if HolyStorm.POI:CanMutate(entry,"edit")then root:CreateButton(L["POI_EDIT"],function()HolyStorm:CallCapability("poi.edit",entry.poiID)end)end;if entry.target~="PERSONAL"then root:CreateButton(L["POI_SHARE"],function()HolyStorm.POI:Share(entry.poiID)end)end;if HolyStorm.POI:CanMutate(entry,"delete")then root:CreateButton(entry.target=="PERSONAL"and L["POI_DELETE_LOCAL"]or L["POI_DELETE_GLOBAL"],function()Map:ConfirmDelete(entry)end)end else root:CreateButton(L["POI_CLEAR_TEMPORARY"],function()HolyStorm.MapLinks:ClearTemporaryMarker();Map:Refresh()end)end end)
end
function Map:ConfigureVisual(frame,entry,size)
 frame.entry=entry;frame:SetSize(size,size);local icon=HolyStorm.POI:GetIcon(entry);frame.icon:SetTexture(icon and icon.texture or"Interface\\Icons\\INV_Misc_Map_01");frame.icon:SetTexCoord(.07,.93,.07,.93);local c=entry.color or{r=1,g=.82,b=0,a=1};frame.glow:SetVertexColor(c.r or 1,c.g or 1,c.b or 1,c.a or 1)
end
function Map:GetRenderState(id)self.renderState[id]=self.renderState[id]or{};return self.renderState[id]end
function Map:IsValidMapID(mapID)
 if not HolyStorm.MapLinks:IsValidMapID(mapID)or not C_Map or type(C_Map.GetMapInfo)~="function"then return false end
 local ok,info=pcall(C_Map.GetMapInfo,tonumber(mapID));return ok and type(info)=="table"
end
function Map:IsValidWorldCoordinate(mapID,x,y)return self:IsValidMapID(mapID)and HolyStorm.MapLinks:IsValidCoordinate(mapID,x,y)end
function Map:Transform(entry,targetMapID)
 local revisionKey=tostring(entry.revisionID or entry.revision)..":"..tostring(entry.mapID);local cache=self.transformCache[entry.poiID]
 if not cache or cache.revision~=revisionKey then cache={revision=revisionKey,targets={}};self.transformCache[entry.poiID]=cache end
 local cached=cache.targets[targetMapID];if cached then return cached.x,cached.y,cached.mode end
 local x,y,mode=HolyStorm.MapLinks:TransformCoordinate(entry.mapID,entry.x,entry.y,targetMapID)
 if x then
  if HolyStorm.Utils.TableCount(cache.targets)>=8 then cache.targets={}end
  cache.targets[targetMapID]={x=x,y=y,mode=mode}
 end
 return x,y,mode
end
function Map:TransformForWorldMap(entry,targetMapID)
 if not self:IsValidMapID(entry.mapID)then return nil,nil,"INVALID_MAP_ID"end
 if not HolyStorm.MapLinks:IsValidCoordinate(entry.mapID,entry.x,entry.y)then return nil,nil,"INVALID_COORDINATE"end
 if not self:IsValidMapID(targetMapID)then return nil,nil,"INVALID_VIEWED_MAP"end
 if tonumber(entry.mapID)~=tonumber(targetMapID)then
  if type(HolyStorm.MapLinks.IsMapRelated)~="function"or not HolyStorm.MapLinks:IsMapRelated(entry.mapID,targetMapID)then return nil,nil,"UNRELATED_MAP"end
 end
 local x,y,mode=self:Transform(entry,targetMapID)
 if not x then return nil,nil,y or mode or"TRANSFORM_UNAVAILABLE"end
 if not self:IsValidWorldCoordinate(targetMapID,x,y)then return nil,nil,"TRANSFORM_INVALID_COORDINATE"end
 return x,y,mode
end
local function conciseReason(reason)
 reason=tostring(reason or "UNKNOWN"):gsub("\r"," "):gsub("\n"," ")
 return #reason>160 and reason:sub(1,160)or reason
end
function Map:GetWorldMapDiagnostics()
 local source=self.worldMapDiagnostics;local result={};for key,value in pairs(source)do result[key]=value end
 result.providerRegistered=self.installed==true;result.worldMapEnabled=HolyStorm.POI and HolyStorm.POI:GetSettings().worldMapEnabled==true
 return result
end
function Map:SetRefreshReason(reason)self.worldMapDiagnostics.lastRefreshReason=conciseReason(reason or "POI_CHANGED")end
function Map:ClearWorldMapPins(canvas)
 canvas=canvas or(self.worldProvider and self.worldProvider:GetMap())
 if canvas then
  if type(canvas.RemoveAllPinsByTemplate)=="function"then pcall(canvas.RemoveAllPinsByTemplate,canvas,"HolyStormPOIPinTemplate")
  elseif type(canvas.RemovePin)=="function"then for _,pin in pairs(self.activeWorldPins)do pcall(canvas.RemovePin,canvas,pin)end end
 end
 self.activeWorldPins={};self.worldMapDiagnostics.activePins=0
 for _,entry in ipairs(self.activeEntries)do local state=self:GetRenderState(entry.poiID);state.worldPin=false;state.viewedMapID=nil;state.transform=nil;state.transformedX=nil;state.transformedY=nil end
end
function Map:RefreshWorldMap(provider,reason)
 local diagnostics=self.worldMapDiagnostics
 diagnostics.lastRefreshReason=conciseReason(reason or "WORLD_MAP_REFRESH")
 diagnostics.lastRenderingFailureReason=nil;diagnostics.exactMapMatches=0;diagnostics.transformedParentMatches=0;diagnostics.skippedUnsupportedTransformations=0;diagnostics.invalidMapIDs=0;diagnostics.invalidCoordinates=0;diagnostics.acquiredPins=0
 diagnostics.localActivePOICount=0;diagnostics.scopeVisiblePOICount=#self.activeEntries
 for _,entry in ipairs(self.activeEntries)do if entry.target=="PERSONAL"and not entry.temporary then diagnostics.localActivePOICount=diagnostics.localActivePOICount+1 end end
 local ok,reasonValue=pcall(function()
  local canvas=provider and provider:GetMap();local viewed=canvas and type(canvas.GetMapID)=="function"and canvas:GetMapID()or nil
  if not self:IsValidMapID(viewed)then
   diagnostics.viewedMapID=nil;if viewed~=nil then diagnostics.invalidMapIDs=diagnostics.invalidMapIDs+1 end
   diagnostics.lastRenderingFailureReason=viewed==nil and "VIEWED_MAP_UNAVAILABLE"or "INVALID_VIEWED_MAP";self:ClearWorldMapPins(canvas);return
  end
  diagnostics.viewedMapID=tonumber(viewed)
  if not canvas or type(canvas.AcquirePin)~="function"or type(canvas.RemovePin)~="function"then diagnostics.lastRenderingFailureReason="MAPCANVAS_PIN_API_UNAVAILABLE";self:ClearWorldMapPins(canvas);return end
  for _,entry in ipairs(self.activeEntries)do local state=self:GetRenderState(entry.poiID);state.worldPin=false;state.viewedMapID=viewed;state.transform=nil;state.transformedX=nil;state.transformedY=nil end
  local nextPins={};local settings=HolyStorm.POI:GetSettings()
  if settings.worldMapEnabled then
   for _,entry in ipairs(self.activeEntries)do
    local x,y,mode=self:TransformForWorldMap(entry,viewed);local state=self:GetRenderState(entry.poiID);state.worldPin=false;state.viewedMapID=viewed;state.transform=mode
    if x and self:IsValidWorldCoordinate(viewed,x,y)then
     if mode=="DIRECT"then diagnostics.exactMapMatches=diagnostics.exactMapMatches+1 else diagnostics.transformedParentMatches=diagnostics.transformedParentMatches+1 end
     local pin=self.activeWorldPins[entry.poiID]
     if pin then self:ConfigureVisual(pin,entry,settings.worldMapSize)else pin=canvas:AcquirePin("HolyStormPOIPinTemplate",entry);if not pin then error("ACQUIRE_PIN_FAILED")end;diagnostics.acquiredPins=diagnostics.acquiredPins+1 end
     pin:SetPosition(x,y);nextPins[entry.poiID]=pin;state.worldPin=true;state.transformedX=x;state.transformedY=y
    else
     state.transformedX=nil;state.transformedY=nil
     if mode=="INVALID_MAP_ID"or mode=="INVALID_VIEWED_MAP"then diagnostics.invalidMapIDs=diagnostics.invalidMapIDs+1 elseif mode=="INVALID_COORDINATE"or mode=="TRANSFORM_INVALID_COORDINATE"then diagnostics.invalidCoordinates=diagnostics.invalidCoordinates+1 else diagnostics.skippedUnsupportedTransformations=diagnostics.skippedUnsupportedTransformations+1 end
    end
   end
  end
  for id,pin in pairs(self.activeWorldPins)do if not nextPins[id]then canvas:RemovePin(pin)end end
  self.activeWorldPins=nextPins
  if type(canvas.GetNumActivePinsByTemplate)=="function"then local countOK,count=pcall(canvas.GetNumActivePinsByTemplate,canvas,"HolyStormPOIPinTemplate");diagnostics.activePins=countOK and tonumber(count)or HolyStorm.Utils.TableCount(nextPins)else diagnostics.activePins=HolyStorm.Utils.TableCount(nextPins)end
 end)
 if not ok then
  diagnostics.lastRenderingFailureReason=conciseReason(reasonValue);self:ClearWorldMapPins(provider and provider:GetMap())
 end
end
function Map:RefreshMinimap(force)
 local settings=HolyStorm.POI:GetSettings();if not settings.minimapEnabled or#self.activeEntries==0 then for _,entry in ipairs(self.activeEntries)do self:GetRenderState(entry.poiID).minimapPin=false end;for _,pin in ipairs(self.minimapPins)do pin.entry=nil;pin:Hide()end;return true end
 local time=HolyStorm.Utils.Now();if not force and time-self.lastMinimapRefresh<1 then return false end;self.lastMinimapRefresh=time
 local entries=self.activeEntries;local context=HolyStorm.MapLinks:GetMinimapContext();local used,visible,parts=0,{},{}
 for _,entry in ipairs(self.activeEntries)do self:GetRenderState(entry.poiID).minimapPin=false end
 if context then for _,entry in ipairs(entries)do
  local tx,ty,mode=self:Transform(entry,context.mapID);local x,y,mapID
  if tx then x,y,mode,mapID=HolyStorm.MapLinks:ProjectToMinimap(entry.mapID,entry.x,entry.y,false,context,tx,ty,mode)end
  local state=self:GetRenderState(entry.poiID);state.minimapPin=false;state.minimapTransform=mode
  if x then visible[#visible+1]={entry=entry,x=x,y=y,mapID=mapID};parts[#parts+1]=table.concat({entry.poiID,entry.revisionID or entry.revision,string.format("%.5f",x),string.format("%.5f",y)},":")end
 end end
 local signature=table.concat({context and context.mapID or"none",context and string.format("%.4f:%.4f:%s:%.4f",context.x,context.y,tostring(context.rotate),context.facing)or"",settings.minimapEnabled and settings.minimapSize or 0,table.concat(parts,"|")},";")
 if signature==self.lastMinimapSignature then for _,pinData in ipairs(visible)do local state=self:GetRenderState(pinData.entry.poiID);state.minimapPin=true;state.minimapViewedMapID=pinData.mapID end;return true end;self.lastMinimapSignature=signature
 for _,pinData in ipairs(visible)do local entry=pinData.entry;used=used+1;local pin=self.minimapPins[used]
  if not pin then pin=CreateFrame("Button",nil,Minimap);pin:SetFrameLevel(Minimap:GetFrameLevel()+5);pin.glow=pin:CreateTexture(nil,"BACKGROUND");pin.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border");pin.glow:SetBlendMode("ADD");pin.glow:SetPoint("CENTER");pin.icon=pin:CreateTexture(nil,"ARTWORK");pin.icon:SetAllPoints();pin:SetScript("OnEnter",function(p)Map:ShowTooltip(p,p.entry)end);pin:SetScript("OnLeave",function()GameTooltip:Hide()end);pin:SetScript("OnClick",function(p,button)if button=="RightButton"then Map:OpenContext(p,p.entry)else HolyStorm:CallCapability("poi.open",p.entry.poiID)end end);pin:RegisterForClicks("LeftButtonUp","RightButtonUp");self.minimapPins[used]=pin end
  self:ConfigureVisual(pin,entry,settings.minimapSize);pin.glow:SetSize(settings.minimapSize+12,settings.minimapSize+12);pin:ClearAllPoints();pin:SetPoint("CENTER",Minimap,"CENTER",pinData.x,pinData.y);pin:Show();local state=self:GetRenderState(entry.poiID);state.minimapPin=true;state.minimapViewedMapID=pinData.mapID
 end
 for index=used+1,#self.minimapPins do self.minimapPins[index]:Hide();self.minimapPins[index].entry=nil end
 return true
end
function Map:UpdateMinimapUpdater()
 local settings=HolyStorm.POI:GetSettings()
 return HolyStorm.MapLinks:SetMinimapUpdaterActive("poi",self.initialized and Minimap~=nil and settings.minimapEnabled==true and#self.activeEntries>0)
end
function Map:LogWorldMapFailure(reason)
 if self.worldMapUnavailableLogged then return end
 self.worldMapUnavailableLogged=true
 self.worldMapDiagnostics.lastRenderingFailureReason=conciseReason(reason)
 if HolyStorm.Logger then HolyStorm.Logger:Write("WARN","POI","map","World map POI provider unavailable",{reason=reason})end
end
function Map:IsWorldMapVisible()
 local frame=WorldMapFrame;if not frame then return false end
 local query=frame.IsVisible or frame.IsShown;if type(query)~="function"then return false end
 local ok,visible=pcall(query,frame);return ok and visible==true
end
function Map:HookWorldMap()
 if self.worldMapHooked then if self:IsWorldMapVisible()then self:InstallWorldMap()end;return true end
 if not WorldMapFrame or type(WorldMapFrame.HookScript)~="function"then return false end
 self.worldMapShowHook=function()
  if not Map.initialized then return end
  Map:InstallWorldMap();Map:Refresh("WORLD_MAP_SHOW")
 end
 WorldMapFrame:HookScript("OnShow",self.worldMapShowHook);self.worldMapHooked=true
 if self:IsWorldMapVisible()then self:InstallWorldMap();self:Refresh()end
 return true
end
function Map:Refresh(reason)
 if not self.initialized then return false end
 self.worldMapDiagnostics.lastRefreshReason=conciseReason(reason or self.worldMapDiagnostics.lastRefreshReason or "POI_CHANGED")
 self.activeEntries=self:GetEntries();self:UpdateMinimapUpdater();local active={};for _,entry in ipairs(self.activeEntries)do active[entry.poiID]=true end;for id in pairs(self.renderState)do if not active[id]then self.renderState[id]=nil;self.transformCache[id]=nil end end
 local worldVisible=self:IsWorldMapVisible();if worldVisible and not self.worldProvider then self:InstallWorldMap()end
 if worldVisible and self.worldProvider and not self.worldMapFailed then self:RefreshWorldMap(self.worldProvider,self.worldMapDiagnostics.lastRefreshReason)end
 self:RefreshMinimap(true);HolyStorm.Events:Emit("HS_POI_MAP_REFRESHED");return true
end
function Map:InstallWorldMap()
 if self.installed or self.worldMapFailed then return false end
 if not self:IsWorldMapVisible()then return false,"WORLD_MAP_HIDDEN"end
 if not WorldMapFrame or not MapCanvasDataProviderMixin or not MapCanvasPinMixin or not CreateFromMixins or type(WorldMapFrame.AddDataProvider)~="function"or type(WorldMapFrame.RemoveDataProvider)~="function"then self:LogWorldMapFailure("MAPCANVAS_NOT_READY");return false end
 local provider=CreateFromMixins(MapCanvasDataProviderMixin)
 function provider:RemoveAllData()Map:ClearWorldMapPins(self:GetMap())end
 function provider:RefreshAllData()if not Map:IsWorldMapVisible()then return end;Map:RefreshWorldMap(self,Map.worldMapDiagnostics.lastRefreshReason)end
 function provider:OnMapChanged()Map:RefreshWorldMap(self,"WORLD_MAP_CHANGED")end
 local ok,reason=pcall(WorldMapFrame.AddDataProvider,WorldMapFrame,provider)
 if not ok then if type(WorldMapFrame.RemoveDataProvider)=="function"then pcall(WorldMapFrame.RemoveDataProvider,WorldMapFrame,provider)end;self:LogWorldMapFailure(reason);return false end
 self.worldProvider=provider;self.installed=true;self.worldMapDiagnostics.providerRegistrationCount=self.worldMapDiagnostics.providerRegistrationCount+1;self.worldMapUnavailableLogged=false;return true
end
function Map:Initialize()
 if self.initialized then return true end;self.initialized=true;self.worldMapFailed=false;self.lastMinimapSignature=nil;HolyStorm.MapLinks:RegisterPOIProvider("holy-storm-poi",{get=function(id)local entry=HolyStorm.POI:Get(id);return HolyStorm.POI:CanView(entry)and entry or nil end,list=function()return HolyStorm.POI:GetVisible()end,open=function(id)return HolyStorm.POI:Open(id)end});self.activeEntries=self:GetEntries();self:HookWorldMap();HolyStorm.MapLinks:RegisterMinimapUpdater("poi",function()Map:RefreshMinimap(false)end);self:UpdateMinimapUpdater();HolyStorm.Events:Register("ADDON_LOADED","poi-map-load",function(_,name)if name=="Blizzard_WorldMap"then Map:HookWorldMap();Map:Refresh()end end);for _,event in ipairs({"HS_POI_CREATED","HS_POI_UPDATED","HS_POI_DELETED","HS_POI_EXPIRED","HS_POI_LIST_CHANGED","HS_POI_VISIBILITY_CHANGED","HS_POI_FILTER_CHANGED","HS_POI_SYNCED","HS_MAP_TEMPORARY_MARKER_CHANGED","ZONE_CHANGED_NEW_AREA"})do HolyStorm.Events:Register(event,"poi-map",function()HolyStorm.POI:Refresh(event)end)end
 return true
end
function Map:Shutdown()
 if not self.initialized then return false end
 if self.installed and self.worldProvider and WorldMapFrame and type(WorldMapFrame.RemoveDataProvider)=="function"then pcall(WorldMapFrame.RemoveDataProvider,WorldMapFrame,self.worldProvider)end
 self.worldProvider=nil;self.installed=false;self.worldMapFailed=false;self.initialized=false;self.activeEntries={};self.transformCache={};self.renderState={};self.lastMinimapSignature=nil
 HolyStorm.MapLinks:SetMinimapUpdaterActive("poi",false);HolyStorm.MapLinks:UnregisterMinimapUpdater("poi");HolyStorm.MapLinks:UnregisterPOIProvider("holy-storm-poi");HolyStorm.Events:UnregisterOwner("poi-map-load");HolyStorm.Events:UnregisterOwner("poi-map")
 for _,pin in ipairs(self.minimapPins)do pin.entry=nil;pin:Hide()end;return true
end
HolyStorm.POIMap=Map

HolyStormPOIPinMixin={}
function HolyStormPOIPinMixin:OnAcquired(entry)Map:ConfigureVisual(self,entry,HolyStorm.POI:GetSettings().worldMapSize);self.glow:SetSize(HolyStorm.POI:GetSettings().worldMapSize+14,HolyStorm.POI:GetSettings().worldMapSize+14);self:Show()end
function HolyStormPOIPinMixin:OnReleased()self.entry=nil;self:Hide();GameTooltip:Hide()end
function HolyStormPOIPinMixin:OnMouseEnter()if self.entry then Map:ShowTooltip(self,self.entry)end end
function HolyStormPOIPinMixin:OnMouseLeave()GameTooltip:Hide()end
function HolyStormPOIPinMixin:OnClick(button)if not self.entry then return end;if button=="RightButton"then Map:OpenContext(self,self.entry)else HolyStorm:CallCapability("poi.open",self.entry.poiID)end end
