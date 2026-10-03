local addonVersion="1.2.0"
local HolyStorm=LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local MapLinks={version=addonVersion,poiProviders={},minimapUpdaters={},minimapElapsed=0}

function MapLinks:RegisterPOIProvider(id,provider)if type(id)~="string"or type(provider)~="table"then return false end;self.poiProviders[id]=provider;return true end
function MapLinks:ResolvePOI(id)for providerId,provider in pairs(self.poiProviders)do if provider.get then local ok,poi=HolyStorm.Utils.SafeCall("poi.resolve:"..providerId,provider.get,id);if ok and poi then return poi,provider,providerId end end end end
function MapLinks:ListPOIs()
 local out,seen={},{};for providerId,provider in pairs(self.poiProviders)do if provider.list then local ok,items=HolyStorm.Utils.SafeCall("poi.list:"..providerId,provider.list);if ok and type(items)=="table"then for _,poi in pairs(items)do local id=poi and(poi.id or poi.poiId or poi.poiID);if type(id)=="string"and id~=""and not seen[id]then seen[id]=true;out[#out+1]={id=id,name=poi.name or id,category=poi.category,mapID=poi.mapID,creator=poi.creator or poi.creatorName,creatorGuid=poi.creatorGuid,provider=providerId}end end end end end;table.sort(out,function(a,b)return string.lower(a.name)<string.lower(b.name)end);return out
end
function MapLinks:OpenPOI(id)local poi,provider,providerId=self:ResolvePOI(id);if not poi then return false,"POI_UNAVAILABLE"end;if provider.open then local ok,result,reason=HolyStorm.Utils.SafeCall("poi.open:"..providerId,provider.open,id,poi);return ok and result or false,ok and reason or"POI_UNAVAILABLE"end;if poi.mapID and poi.x and poi.y then return self:OpenCoordinate(poi.mapID,poi.x,poi.y,poi.name)end;return false,"POI_UNAVAILABLE"end
local function finite(value)
 value=tonumber(value)
 return value~=nil and value==value and value~=math.huge and value~=-math.huge
end
local function getXY(position)
 if not position or type(position.GetXY)~="function"then return nil end
 local ok,x,y=pcall(position.GetXY,position)
 if not ok or not finite(x)or not finite(y)then return nil end
 return tonumber(x),tonumber(y)
end
function MapLinks:IsValidMapID(mapID)
 mapID=tonumber(mapID)
 return finite(mapID)and mapID>0 and mapID%1==0
end
function MapLinks:IsValidCoordinate(mapID,x,y)
 mapID,x,y=tonumber(mapID),tonumber(x),tonumber(y)
 return self:IsValidMapID(mapID)and finite(x)and x>=0 and x<=1 and finite(y)and y>=0 and y<=1
end
function MapLinks:GetMapParent(mapID)
 if not self:IsValidMapID(mapID)or not C_Map or type(C_Map.GetMapInfo)~="function"then return nil end
 local ok,info=pcall(C_Map.GetMapInfo,tonumber(mapID))
 return ok and type(info)=="table"and self:IsValidMapID(info.parentMapID)and tonumber(info.parentMapID)or nil
end
function MapLinks:IsMapRelated(firstMapID,secondMapID)
 if not self:IsValidMapID(firstMapID)or not self:IsValidMapID(secondMapID)then return false end
 firstMapID,secondMapID=tonumber(firstMapID),tonumber(secondMapID)
 if firstMapID==secondMapID then return true end
 local function hasAncestor(mapID,wanted)
  local seen={};for _=1,100 do
   if seen[mapID]then return false end;seen[mapID]=true
   mapID=self:GetMapParent(mapID);if not mapID then return false end
   if mapID==wanted then return true end
  end
  return false
 end
 return hasAncestor(firstMapID,secondMapID)or hasAncestor(secondMapID,firstMapID)
end
function MapLinks:GetPlayerPosition()
 if not C_Map or type(C_Map.GetBestMapForUnit)~="function"or type(C_Map.GetPlayerMapPosition)~="function"then return nil,"MAP_UNAVAILABLE"end
 local ok,mapID=pcall(C_Map.GetBestMapForUnit,"player")
 if not ok or not self:IsValidMapID(mapID)then return nil,"MAP_UNAVAILABLE"end
 local got,position=pcall(C_Map.GetPlayerMapPosition,mapID,"player")
 if not got then return nil,"POSITION_UNAVAILABLE"end
 local x,y=getXY(position)
 if not self:IsValidCoordinate(mapID,x,y)then return nil,"POSITION_UNAVAILABLE"end
 return tonumber(mapID),x,y
end
function MapLinks:TransformCoordinate(sourceMapID,x,y,targetMapID)
 sourceMapID,targetMapID=tonumber(sourceMapID),tonumber(targetMapID)
 if not self:IsValidCoordinate(sourceMapID,x,y)or not self:IsValidMapID(targetMapID)then return nil,"INVALID_COORDINATE"end
 if sourceMapID==targetMapID then return tonumber(x),tonumber(y),"DIRECT"end
 if not C_Map or type(C_Map.GetWorldPosFromMapPos)~="function"or type(C_Map.GetMapPosFromWorldPos)~="function"or type(CreateVector2D)~="function"then return nil,"TRANSFORM_UNAVAILABLE"end
 local ok,point=pcall(CreateVector2D,tonumber(x),tonumber(y));if not ok or not point then return nil,"TRANSFORM_FAILED"end
 local worldOK,continentID,worldPosition=pcall(C_Map.GetWorldPosFromMapPos,sourceMapID,point)
 if not worldOK or not self:IsValidMapID(continentID)or not worldPosition then return nil,"TRANSFORM_FAILED"end
 local mapOK,resultMapID,mapPosition=pcall(C_Map.GetMapPosFromWorldPos,continentID,worldPosition,targetMapID)
 if not mapOK or tonumber(resultMapID)~=targetMapID then return nil,"TRANSFORM_FAILED"end
 local tx,ty=getXY(mapPosition)
 if not self:IsValidCoordinate(targetMapID,tx,ty)then return nil,"TRANSFORM_FAILED"end
 return tx,ty,"TRANSFORMED"
end
function MapLinks:GetMinimapContext()
 if not C_Map or type(C_Map.GetBestMapForUnit)~="function"or type(C_Map.GetPlayerMapPosition)~="function"or type(C_Map.GetMapWorldSize)~="function"or not C_Minimap or type(C_Minimap.GetViewRadius)~="function"or not Minimap then return nil,"API_UNAVAILABLE"end
 local ok,mapID=pcall(C_Map.GetBestMapForUnit,"player");if not ok or not self:IsValidMapID(mapID)then return nil,"MAP_UNAVAILABLE"end
 local posOK,player=pcall(C_Map.GetPlayerMapPosition,mapID,"player");local px,py=getXY(posOK and player)
 if not self:IsValidCoordinate(mapID,px,py)then return nil,"PLAYER_POSITION"end
 local sizeOK,width,height=pcall(C_Map.GetMapWorldSize,mapID);local radiusOK,radius=pcall(C_Minimap.GetViewRadius)
 if not sizeOK or not finite(width)or not finite(height)or width<=0 or height<=0 or not radiusOK or not finite(radius)or radius<=0 then return nil,"API_UNAVAILABLE"end
 local widthOK,pixelWidth=pcall(Minimap.GetWidth,Minimap);local heightOK,pixelHeight=pcall(Minimap.GetHeight,Minimap)
 if not widthOK or not heightOK or not finite(pixelWidth)or not finite(pixelHeight)or pixelWidth<=0 or pixelHeight<=0 then return nil,"MINIMAP_UNAVAILABLE"end
 local rotate,facing=false,0
 if type(GetCVarBool)=="function"then local rotateOK,value=pcall(GetCVarBool,"rotateMinimap");rotate=rotateOK and value==true end
 if rotate and C_Minimap and type(C_Minimap.IsRotateMinimapIgnored)=="function"then
  local ignoreOK,ignored=pcall(C_Minimap.IsRotateMinimapIgnored);if ignoreOK and ignored==true then rotate=false end
 end
 if rotate then
  if type(GetPlayerFacing)~="function"then return nil,"ROTATION_UNAVAILABLE"end
  local facingOK,value=pcall(GetPlayerFacing);if facingOK and finite(value)then facing=tonumber(value)else return nil,"ROTATION_UNAVAILABLE"end
 end
 return{mapID=tonumber(mapID),x=px,y=py,width=tonumber(width),height=tonumber(height),radius=tonumber(radius),pixelRadius=math.min(pixelWidth,pixelHeight)*.46,rotate=rotate,facing=facing}
end
function MapLinks:ProjectToMinimap(sourceMapID,x,y,currentMapOnly,context,transformedX,transformedY,transformMode)
 sourceMapID=tonumber(sourceMapID);context=context or self:GetMinimapContext()
 if not context then return nil,"API_UNAVAILABLE"end
 if currentMapOnly and not self:IsMapRelated(sourceMapID,context.mapID)then return nil,"CURRENT_MAP_ONLY"end
 local tx,ty,mode=transformedX,transformedY,transformMode
 if tx==nil or ty==nil then tx,ty,mode=self:TransformCoordinate(sourceMapID,x,y,context.mapID)end
 if not tx then return nil,ty or mode end
 local dx,north=(tx-context.x)*context.width,(context.y-ty)*context.height
 if context.rotate then local c,s=math.cos(context.facing),math.sin(context.facing);dx,north=dx*c-north*s,dx*s+north*c end
 local distance=math.sqrt(dx*dx+north*north)
 if distance>context.radius then return nil,"OUT_OF_RANGE"end
 return dx/context.radius*context.pixelRadius,north/context.radius*context.pixelRadius,mode,context.mapID,tx,ty
end
function MapLinks:RegisterMinimapUpdater(id,callback)
 if type(id)~="string"or type(callback)~="function"then return false end;self.minimapUpdaters[id]=callback;if not self.minimapDriver and Minimap and CreateFrame then self.minimapDriver=CreateFrame("Frame",nil,Minimap);self.minimapDriver:SetScript("OnUpdate",function(_,elapsed)MapLinks.minimapElapsed=MapLinks.minimapElapsed+elapsed;if MapLinks.minimapElapsed>=.25 then MapLinks.minimapElapsed=0;for owner,update in pairs(MapLinks.minimapUpdaters)do HolyStorm.Utils.SafeCall("minimap.update:"..owner,update)end end end)end;return true
end
function MapLinks:UnregisterMinimapUpdater(id)self.minimapUpdaters[id]=nil end
function MapLinks:SetTemporaryMarker(mapID,x,y,options)
 if not self:IsValidCoordinate(mapID,x,y)then return false,"INVALID_COORDINATE"end;options=options or{};self.temporaryMarker={poiID="temporary-coordinate",mapID=tonumber(mapID),x=tonumber(x),y=tonumber(y),name=options.label,status="ACTIVE",target="PERSONAL",temporary=true,localOnly=true,createdAt=HolyStorm.Utils.Now(),expiresAt=options.timeout and(HolyStorm.Utils.Now()+math.max(1,tonumber(options.timeout)or 0))or nil};HolyStorm.Events:Emit("HS_MAP_TEMPORARY_MARKER_CHANGED",self.temporaryMarker);return true,self.temporaryMarker
end
function MapLinks:ClearTemporaryMarker()if not self.temporaryMarker then return false end;self.temporaryMarker=nil;HolyStorm.Events:Emit("HS_MAP_TEMPORARY_MARKER_CHANGED",nil);return true end
function MapLinks:OpenCoordinate(mapID,x,y,label)
 mapID,x,y=tonumber(mapID),tonumber(x),tonumber(y);if not self:IsValidCoordinate(mapID,x,y)then return false,"INVALID_COORDINATE"end
 if C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates then pcall(function()local point=UiMapPoint.CreateFromCoordinates(mapID,x,y);if point then C_Map.SetUserWaypoint(point);if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then C_SuperTrack.SetSuperTrackedUserWaypoint(true)end end end)end
 local opened=false;if OpenWorldMap then opened=pcall(OpenWorldMap,mapID)elseif WorldMapFrame and WorldMapFrame.SetMapID then opened=pcall(function()WorldMapFrame:SetMapID(mapID);WorldMapFrame:Show()end)end;if not opened then return false,"MAP_UNAVAILABLE"end
 self:SetTemporaryMarker(mapID,x,y,{label=label,timeout=300});HolyStorm.Events:Emit("HS_MAP_LINK_OPENED",self.temporaryMarker);return true
end
HolyStorm.MapLinks=MapLinks
