local addonVersion="1.0.0"
local HolyStorm=LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local L=LibStub("AceLocale-3.0"):GetLocale("Holy_Storm_Positions")
local Map={version=addonVersion,worldProvider=nil,minimapPins={},renderState={},loggedFailures={},installed=false}
local classTexture="Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"
local guildTexture="Interface\\Icons\\Achievement_GuildPerk_EverybodysFriend"
local function age(timestamp)return math.max(0,HolyStorm.Utils.Now()-(timestamp or 0))end
function Map:GetRenderState(guid)self.renderState[guid]=self.renderState[guid]or{};return self.renderState[guid]end
function Map:GetStyle(entry)
 local summary=HolyStorm.GuildPositions:GetCharacterSummary(entry.characterUUID);local settings=HolyStorm.GuildPositions:GetSettings();if settings.markerStyle=="CLASS"and summary.classFile and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[summary.classFile]then local color=RAID_CLASS_COLORS and RAID_CLASS_COLORS[summary.classFile]or{r=.25,g=.78,b=.92};return classTexture,CLASS_ICON_TCOORDS[summary.classFile],color end;return guildTexture,{0,1,0,1},{r=.25,g=.78,b=.92}
end
function Map:ConfigureVisual(frame,entry,size)
 local texture,coords,color=self:GetStyle(entry);frame.entry=entry;frame:SetSize(size,size);frame.icon:SetTexture(texture);frame.icon:SetTexCoord(coords[1],coords[2],coords[3],coords[4]);frame.border:SetVertexColor(color.r or 1,color.g or 1,color.b or 1,1)
end
function Map:ShowTooltip(owner,entry)
 local summary=HolyStorm.GuildPositions:GetCharacterSummary(entry.characterUUID);GameTooltip:SetOwner(owner,"ANCHOR_CURSOR_RIGHT");local color=summary.classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[summary.classFile];GameTooltip:SetText(summary.name or entry.characterUUID,color and color.r or 1,color and color.g or 1,color and color.b or 1);local identity={summary.class,summary.race,summary.role};local compact={};for _,value in ipairs(identity)do if value and value~=""then compact[#compact+1]=value end end;if#compact>0 then GameTooltip:AddLine(table.concat(compact," · "),1,1,1)end;if summary.rank then GameTooltip:AddDoubleLine(L["TOOLTIP_RANK"],summary.rank,1,.82,0,1,1,1)end;local status=(summary.status==1 or summary.status=="AFK")and L["STATUS_AFK"]or(summary.status==2 or summary.status=="DND")and L["STATUS_DND"];if status then GameTooltip:AddDoubleLine(L["TOOLTIP_STATUS"],status,1,.82,0,1,1,1)end;if summary.mainName and summary.mainGuid~=summary.characterUUID then GameTooltip:AddDoubleLine(summary.isShadowMain and L["TOOLTIP_GUILD_MAIN"]or L["TOOLTIP_MAIN"],summary.mainName,1,.82,0,1,1,1)end;if summary.itemLevel and summary.itemLevel>0 then GameTooltip:AddDoubleLine(L["TOOLTIP_ITEM_LEVEL"],string.format("%.1f",summary.itemLevel),1,.82,0,1,1,1)end;if summary.raidProgress then local text=string.format("%d/%d %s",summary.raidProgress.killed or 0,summary.raidProgress.total or 0,summary.raidProgress.difficulty or"");GameTooltip:AddDoubleLine(L["TOOLTIP_RAID"],HolyStorm.CharacterUI:ColorDifficulty(summary.raidProgress.difficulty,text),1,.82,0,1,1,1)end;if summary.mythicScore and summary.mythicScore>0 then GameTooltip:AddDoubleLine(L["TOOLTIP_MYTHIC"],string.format("%.1f",summary.mythicScore),1,.82,0,1,1,1)end;GameTooltip:AddDoubleLine(L["TOOLTIP_POSITION_AGE"],string.format(L["SECONDS_AGO"],age(entry.timestamp)),1,.82,0,.75,.75,.75);GameTooltip:Show()
end
function Map:OpenAsPOI(entry)
 local summary=HolyStorm.GuildPositions:GetCharacterSummary(entry.characterUUID);HolyStorm:CallCapability("poi.create",{mapID=entry.mapID,x=entry.x,y=entry.y,name=string.format(L["POI_NAME"],summary.name or entry.characterUUID),description="",target="PERSONAL",category="note",icon="marker",color={r=1,g=.82,b=0,a=1}})
end
function Map:OpenContext(owner,entry)
 HolyStorm.CharacterActions:CreateContextMenu(owner,entry.characterUUID,{{text=L["ACTION_CREATE_POI"],enabled=true,callback=function()Map:OpenAsPOI(entry)end}})
end
function Map:HandleClick(owner,button)if not owner.entry then return end;if button=="RightButton"then self:OpenContext(owner,owner.entry)else HolyStorm.CharacterActions:Open(owner.entry.characterUUID)end end
function Map:PlaceWorldPin(provider,entry)
 local canvas=provider:GetMap();local viewed=canvas and canvas:GetMapID();if not viewed then return end;local state=self:GetRenderState(entry.characterUUID);state.worldPin=false;state.viewedMapID=viewed;local settings=HolyStorm.GuildPositions:GetSettings();if settings.currentMapOnly and entry.mapID~=viewed then state.reason="CURRENT_MAP_ONLY";return end;local x,y,mode=HolyStorm.MapLinks:TransformCoordinate(entry.mapID,entry.x,entry.y,viewed);state.transform=mode;state.reason=x and nil or mode;if not x then local key=entry.characterUUID..":"..viewed..":"..tostring(mode);if not self.loggedFailures[key]then self.loggedFailures[key]=true;HolyStorm.Logger:Write("DEBUG","Positions","map","Guild position transformation unavailable",{characterUUID=entry.characterUUID,sourceMapID=entry.mapID,viewedMapID=viewed,reason=mode})end;return end;local pin=canvas:AcquirePin("HolyStormGuildPositionPinTemplate",entry);pin:SetPosition(x,y);provider.pins[entry.characterUUID]=pin;state.worldPin=true;state.transformedX,state.transformedY=x,y
end
function Map:InstallWorldMap()
 if self.installed or not WorldMapFrame or not MapCanvasDataProviderMixin or not CreateFromMixins then return false end;local provider=CreateFromMixins(MapCanvasDataProviderMixin);provider.pins={};function provider:RemoveGuid(guid)local pin=self.pins[guid];if not pin then return end;local canvas=self:GetMap();if canvas and canvas.RemovePin then canvas:RemovePin(pin)else pin:Hide()end;self.pins[guid]=nil end;function provider:RemoveAllData()if self:GetMap()then self:GetMap():RemoveAllPinsByTemplate("HolyStormGuildPositionPinTemplate")end;self.pins={}end;function provider:RefreshGuid(guid)self:RemoveGuid(guid);if not HolyStorm.GuildPositions:GetSettings().worldMapEnabled then return end;local entry=HolyStorm.GuildPositions:Get(guid);if entry then Map:PlaceWorldPin(self,entry)else Map:GetRenderState(guid).worldPin=false end end;function provider:RefreshAllData()self:RemoveAllData();if not HolyStorm.GuildPositions:GetSettings().worldMapEnabled then return end;for _,entry in ipairs(HolyStorm.GuildPositions:GetVisible())do Map:PlaceWorldPin(self,entry)end end;WorldMapFrame:AddDataProvider(provider);self.worldProvider=provider;self.installed=true;return true
end
function Map:RefreshMinimapOne(guid,entry)
 local pin=self.minimapPins[guid];local state=self:GetRenderState(guid);state.minimapPin=false;if not entry or not HolyStorm.GuildPositions:GetSettings().minimapEnabled then if pin then pin:Hide()end;return end;local settings=HolyStorm.GuildPositions:GetSettings();local x,y,mode,mapID=HolyStorm.MapLinks:ProjectToMinimap(entry.mapID,entry.x,entry.y,settings.currentMapOnly);state.minimapTransform=mode;state.reason=x and state.reason or mode;if not x then if pin then pin:Hide()end;return end;if not pin then pin=CreateFrame("Button",nil,Minimap);pin:SetFrameLevel(Minimap:GetFrameLevel()+7);pin.border=pin:CreateTexture(nil,"BACKGROUND");pin.border:SetTexture("Interface\\Buttons\\UI-ActionButton-Border");pin.border:SetBlendMode("ADD");pin.border:SetPoint("CENTER");pin.icon=pin:CreateTexture(nil,"ARTWORK");pin.icon:SetAllPoints();pin:RegisterForClicks("LeftButtonUp","RightButtonUp");pin:SetScript("OnEnter",function(p)Map:ShowTooltip(p,p.entry)end);pin:SetScript("OnLeave",function()GameTooltip:Hide()end);pin:SetScript("OnClick",function(p,button)Map:HandleClick(p,button)end);self.minimapPins[guid]=pin end;self:ConfigureVisual(pin,entry,settings.minimapSize);pin.border:SetSize(settings.minimapSize+14,settings.minimapSize+14);pin:ClearAllPoints();pin:SetPoint("CENTER",Minimap,"CENTER",x,y);pin:Show();state.minimapPin=true;state.viewedMapID=mapID
end
function Map:RefreshMinimap(guid)
 if guid then self:RefreshMinimapOne(guid,HolyStorm.GuildPositions:Get(guid));return end;local seen={};for _,entry in ipairs(HolyStorm.GuildPositions:GetVisible())do seen[entry.characterUUID]=true;self:RefreshMinimapOne(entry.characterUUID,entry)end;for characterUUID in pairs(self.minimapPins)do if not seen[characterUUID]then self:RefreshMinimapOne(characterUUID,nil)end end
end
function Map:Refresh(guid)
 if self.worldProvider then if guid and self.worldProvider.RefreshGuid then self.worldProvider:RefreshGuid(guid)else self.worldProvider:RefreshAllData()end end;self:RefreshMinimap(guid);HolyStorm.Events:Emit("HS_GUILD_POSITION_MAP_REFRESHED",guid)
end
function Map:Initialize()
 self:InstallWorldMap();HolyStorm.MapLinks:RegisterMinimapUpdater("guild-positions",function()Map:RefreshMinimap()end);HolyStorm.Events:Register("ADDON_LOADED","guild-position-map-load",function(_,name)if name=="Blizzard_WorldMap"then Map:InstallWorldMap();Map:Refresh()end end);HolyStorm.Events:Register("HS_GUILD_POSITIONS_CLEARED","guild-position-map",function()Map:Refresh()end);HolyStorm.Events:Register("HS_POSITION_SETTINGS_CHANGED","guild-position-map-settings",function()Map:Refresh()end)
end
HolyStorm.GuildPositionMap=Map

HolyStormGuildPositionPinMixin={}
function HolyStormGuildPositionPinMixin:OnAcquired(entry)Map:ConfigureVisual(self,entry,HolyStorm.GuildPositions:GetSettings().worldMapSize);self.border:SetSize(HolyStorm.GuildPositions:GetSettings().worldMapSize+16,HolyStorm.GuildPositions:GetSettings().worldMapSize+16);self:Show()end
function HolyStormGuildPositionPinMixin:OnReleased()self.entry=nil;self:Hide();GameTooltip:Hide()end
function HolyStormGuildPositionPinMixin:OnEnter()if self.entry then Map:ShowTooltip(self,self.entry)end end
function HolyStormGuildPositionPinMixin:OnLeave()GameTooltip:Hide()end
function HolyStormGuildPositionPinMixin:OnClick(button)Map:HandleClick(self,button)end
