local addonVersion="1.1.0"
local HolyStorm=LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local L=LibStub("AceLocale-3.0"):GetLocale("Holy_Storm_POI")
local DataManager=HolyStorm.DataManager
local POI={version=addonVersion,categories={},icons={},targets={PERSONAL=true,GUILD=true,GROUP=true,RAID=true},statuses={ACTIVE=true,DELETED=true},sequence=0,maxEntries=1000,maxName=120,maxDescription=4000,maxCustomCategory=80,tombstoneRetention=180*24*60*60,maxGuildTombstones=2000,currentContext=nil,lastResync=nil,guildDiscoveryStarted=false,expiredNotified={}}
local defaults={schemaVersion=1,worldMapEnabled=true,minimapEnabled=true,worldMapSize=22,minimapSize=18,maxSynced=500,hidden={},categoryVisible={},targetVisible={}}

local function copy(value)return HolyStorm.Utils.DeepCopy(value)end
local function now()return HolyStorm.Utils.Now()end
local function finite(value)value=tonumber(value);return value~=nil and value==value and value~=math.huge and value~=-math.huge end
local function validId(value)return type(value)=="string"and#value>0 and#value<=160 and value:match("^[%w%-_]+$")~=nil end
local function account(guid)return HolyStorm.TwinkCore and HolyStorm.TwinkCore:GetAccountUUIDForCharacter(guid)or HolyStorm.Data.PlayerStore:GetCharacterOwner(guid)end
local function permission(target,action)
 if target=="GUILD"then return"poi-"..action.."-guild"end
 if target=="GROUP"or target=="RAID"then return"poi-"..action.."-"..string.lower(target)end
end
local function log(level,message,context)HolyStorm.Logger:Write(level,"POI","state",message,context)end
local function defaultSettings()return copy(defaults)end

DataManager:RegisterSchema({
 id="poi-settings",owner="POI",version=1,storage={backend="database",scope="profile",path={"poi"}},
 default=defaultSettings,
 validate=function(value)
  if type(value)~="table"or value.schemaVersion~=1 or type(value.worldMapEnabled)~="boolean"or type(value.minimapEnabled)~="boolean"or not finite(value.worldMapSize)or value.worldMapSize<12 or value.worldMapSize>48 or not finite(value.minimapSize)or value.minimapSize<10 or value.minimapSize>36 or not finite(value.maxSynced)or value.maxSynced<50 or value.maxSynced>1000 or value.maxSynced%1~=0 then return false end
  for _,field in ipairs({"hidden","categoryVisible","targetVisible"})do if type(value[field])~="table"then return false end;for key,enabled in pairs(value[field])do if type(key)~="string"or type(enabled)~="boolean"then return false end end end
  return true
 end,
 event="HS_POI_SETTINGS_COMMITTED",metadata={purpose="local-poi-display-settings"},
})

function POI:RegisterCategory(id,definition)
 if not validId(id)or type(definition)~="table"then return false end
 self.categories[id]=copy(definition);self.categories[id].id=id;return true
end
function POI:RegisterIcon(id,definition)
 if not validId(id)or type(definition)~="table"or(type(definition.texture)~="string"and type(definition.texture)~="number")then return false end
 self.icons[id]=copy(definition);self.icons[id].id=id;return true
end
function POI:GetCategories()
 local out={};for _,value in pairs(self.categories)do out[#out+1]=copy(value)end
 table.sort(out,function(a,b)return tostring(a.nameKey or a.id)<tostring(b.nameKey or b.id)end);return out
end
function POI:GetIcons()
 local out={};for _,value in pairs(self.icons)do out[#out+1]=copy(value)end
 table.sort(out,function(a,b)return tostring(a.id)<tostring(b.id)end);return out
end
function POI:InitializeSettings()
 local value=DataManager:Get("poi-settings")
 if type(value)=="table"and tonumber(value.schemaVersion)and value.schemaVersion>1 then self.settingsAvailable=false;return false,"SCHEMA_VERSION_NEWER"end
 local result=DataManager:Update("poi-settings",nil,function(settings)
  settings=type(settings)=="table"and settings or defaultSettings()
  for key,default in pairs(defaults)do if settings[key]==nil then settings[key]=copy(default)end end
  settings.schemaVersion=1
  if type(settings.worldMapEnabled)~="boolean"then settings.worldMapEnabled=defaults.worldMapEnabled end
  if type(settings.minimapEnabled)~="boolean"then settings.minimapEnabled=defaults.minimapEnabled end
  settings.worldMapSize=finite(settings.worldMapSize)and math.max(12,math.min(48,tonumber(settings.worldMapSize)))or defaults.worldMapSize
  settings.minimapSize=finite(settings.minimapSize)and math.max(10,math.min(36,tonumber(settings.minimapSize)))or defaults.minimapSize
  settings.maxSynced=finite(settings.maxSynced)and math.max(50,math.min(1000,math.floor(tonumber(settings.maxSynced))))or defaults.maxSynced
  local function normalizeFlags(value)local clean={};for key,enabled in pairs(type(value)=="table"and value or{})do if type(key)=="string"and type(enabled)=="boolean"then clean[key]=enabled end end;return clean end
  settings.hidden=normalizeFlags(settings.hidden);settings.categoryVisible=normalizeFlags(settings.categoryVisible);settings.targetVisible=normalizeFlags(settings.targetVisible)
  return settings
 end,{reason="POI_SETTINGS_MIGRATION"})
 self.settingsAvailable=result and result.ok==true;return self.settingsAvailable,self.settingsAvailable and nil or result and result.errorCode
end
function POI:GetSettings()
 local settings=DataManager:Get("poi-settings")
 if type(settings)~="table"then return defaultSettings()end
 settings=HolyStorm.Utils.ApplyDefaults(settings,defaults)
 if HolyStorm.Settings then
  for _,key in ipairs({"worldMapEnabled","minimapEnabled","worldMapSize","minimapSize","maxSynced"})do local value=HolyStorm.Settings:Get("poi."..key);if value~=nil then settings[key]=value end end
  for key in pairs(self.categories)do local value=HolyStorm.Settings:Get("poi.categoryVisible."..key);if value~=nil then settings.categoryVisible[key]=value end end
  for key in pairs(self.targets)do local value=HolyStorm.Settings:Get("poi.targetVisible."..key);if value~=nil then settings.targetVisible[key]=value end end
 end
 return settings
end
function POI:UpdateSettings(mutator)
 if self.settingsAvailable==false then return false,"SETTINGS_UNAVAILABLE"end
 local result=DataManager:Update("poi-settings",nil,function(settings)
  if type(settings)~="table"then settings=defaultSettings()end
  for key,default in pairs(defaults)do if settings[key]==nil then settings[key]=copy(default)end end
  local accepted,reason=mutator(settings);if accepted==false then return false,reason end
  return settings
 end,{reason="POI_SETTINGS_UPDATE"})
 return result and result.ok==true,result and result.errorCode
end
function POI:SetSetting(key,value)
 if key=="worldMapSize"then value=math.max(12,math.min(48,tonumber(value)or 22))
 elseif key=="minimapSize"then value=math.max(10,math.min(36,tonumber(value)or 18))
 elseif key=="maxSynced"then value=math.max(50,math.min(1000,math.floor(tonumber(value)or 500)))
 elseif key=="worldMapEnabled"or key=="minimapEnabled"then value=value==true else return false,"INVALID_SETTING"end
 local ok,reason=HolyStorm.Settings:Set("poi."..key,value)
 if ok then self:Refresh("SETTING")end;return ok,reason
end
function POI:SetCategoryVisible(id,visible)
 if not self.categories[id]then return false end
 local ok=HolyStorm.Settings:Set("poi.categoryVisible."..id,visible~=false)
 if ok then HolyStorm.Events:Emit("HS_POI_FILTER_CHANGED","category",id,visible~=false);self:Refresh("CATEGORY_FILTER")end;return ok
end
function POI:SetTargetVisible(id,visible)
 if not self.targets[id]then return false end
 local ok=HolyStorm.Settings:Set("poi.targetVisible."..id,visible~=false)
 if ok then HolyStorm.Events:Emit("HS_POI_FILTER_CHANGED","target",id,visible~=false);self:Refresh("TARGET_FILTER")end;return ok
end
function POI:RegisterLocalSettings()
 local legacy=self:GetSettings();local definitions={
  {id="poi.worldMapEnabled",key="worldMapEnabled",type="toggle",default=true,nameKey="WORLD_ENABLED",order=1,slash={path={"poi","world-map"}}},
  {id="poi.minimapEnabled",key="minimapEnabled",type="toggle",default=true,nameKey="MINIMAP_ENABLED",order=2,slash={path={"poi","minimap"}}},
  {id="poi.worldMapSize",key="worldMapSize",type="range",default=22,nameKey="WORLD_SIZE",order=3,min=12,max=48,step=1},
  {id="poi.minimapSize",key="minimapSize",type="range",default=18,nameKey="MINIMAP_SIZE",order=4,min=10,max=36,step=1},
  {id="poi.maxSynced",key="maxSynced",type="range",default=500,nameKey="MAX_SYNCED",order=5,min=50,max=1000,step=50},
 }
 for _,definition in ipairs(definitions)do local entry=definition;local expected=type(entry.default);HolyStorm.Options:RegisterSetting({id=entry.id,module="POI",type=entry.type,default=entry.default,scope="account",scopes={"character","account","guild","allGuilds"},nameKey=entry.nameKey,descriptionKey="DESCRIPTION",uiOrder=entry.order,name=L[entry.nameKey],description=L["DESCRIPTION"],group="POI",slash=entry.slash,setter=function(value)return POI:SetSetting(entry.key,value)end,validate=function(value)return type(value)==expected and(expected~="number"or value>=entry.min and value<=entry.max and value%1==0)end});HolyStorm.Settings:ImportLegacy(entry.id,legacy[entry.key],"account")end
 for id in pairs(self.categories)do local categoryId=id;local definitionId="poi.categoryVisible."..categoryId;local nameKey="CATEGORY_"..categoryId:gsub("%-","_"):upper();HolyStorm.Options:RegisterSetting({id=definitionId,module="POI",type="toggle",default=true,scope="account",scopes={"character","account","guild","allGuilds"},nameKey=nameKey,descriptionKey="DESCRIPTION",uiOrder=20,name=L[nameKey],description=L["DESCRIPTION"],group="POI",slash={path={"poi","category",categoryId}},setter=function(value)return POI:SetCategoryVisible(categoryId,value)end});HolyStorm.Settings:ImportLegacy(definitionId,legacy.categoryVisible[categoryId],"account")end
 for id in pairs(self.targets)do local targetId=id;local definitionId="poi.targetVisible."..targetId;local default=legacy.targetVisible[targetId]~=false;HolyStorm.Options:RegisterSetting({id=definitionId,module="POI",type="toggle",default=default,scope="account",scopes={"character","account","guild","allGuilds"},nameKey="TARGET_"..targetId,name=L["TARGET_"..targetId],descriptionKey="DESCRIPTION",description=L["DESCRIPTION"],uiOrder=30,group="POI",slash={path={"poi","target",targetId}},setter=function(value)return POI:SetTargetVisible(targetId,value)end});HolyStorm.Settings:ImportLegacy(definitionId,legacy.targetVisible[targetId],"account")end
end
function POI:IsModuleEnabled(target)return target=="PERSONAL"or not HolyStorm.Policy or HolyStorm.Policy:IsGuildModuleEnabled("poi")end
function POI:IsMapValid(mapID)
 mapID=tonumber(mapID);if not mapID or mapID<1 or mapID%1~=0 then return false end
 if C_Map and C_Map.GetMapInfo then local ok,info=pcall(C_Map.GetMapInfo,mapID);return ok and info~=nil end;return true
end
function POI:GetMapName(mapID)
 mapID=tonumber(mapID)
 if mapID and C_Map and type(C_Map.GetMapInfo)=="function"then local ok,info=pcall(C_Map.GetMapInfo,mapID);if ok and type(info)=="table"and type(info.name)=="string"and info.name~=""then return info.name end end
 return mapID and string.format(L["MAP_ID"],mapID)or L["MAP_UNKNOWN"]
end
function POI:GetCurrentContext()
 local inRaid=IsInRaid and IsInRaid();local inGroup=IsInGroup and IsInGroup();if not inRaid and not inGroup then return nil end
 local target=inRaid and"RAID"or"GROUP";local leader=UnitGUID("player")or"unknown";local count=inRaid and(GetNumGroupMembers and GetNumGroupMembers()or 0)or(GetNumSubgroupMembers and GetNumSubgroupMembers()or 0)
 for index=1,count do local unit=inRaid and("raid"..index)or("party"..index);if UnitExists and UnitExists(unit)and UnitIsGroupLeader and UnitIsGroupLeader(unit)then leader=UnitGUID(unit)or leader;break end end
 if UnitIsGroupLeader and UnitIsGroupLeader("player")then leader=UnitGUID("player")or leader end
 local instanceID=0;if GetInstanceInfo then local currentInstanceID=select(8,GetInstanceInfo());instanceID=tonumber(currentInstanceID)or 0 end
 return{target=target,leaderGuid=leader,instanceID=instanceID,sessionId=string.format("%s-%s-%d",string.lower(target),tostring(leader):gsub("[^%w%-_]",""),instanceID)}
end
function POI:NewId()
 self.sequence=self.sequence+1;local guid=tostring(UnitGUID("player")or"local"):gsub("[^%w]",""):sub(-20)
 return string.format("poi-%08x-%04x-%04x-%s",now()%0xffffffff,self.sequence%0xffff,math.random(0,0xffff),guid)
end
function POI:NewRevisionID(poiID,revision,actor)
 self.sequence=self.sequence+1
 return string.format("rev-%s-%d-%08x-%04x-%04x",tostring(actor or"local"):gsub("[^%w]",""):sub(-16),revision,now()%0xffffffff,self.sequence%0xffff,math.random(0,0xffff))
end
function POI:MakeProvenance(source,metadata)
 source=source or"MANUAL"
 if source~="MANUAL"and source~="CURRENT_PLAYER_POSITION"and source~="GUILD_PLAYER_POSITION"then return nil,"INVALID_PROVENANCE"end
 if metadata~=nil and type(metadata)~="table"then return nil,"INVALID_PROVENANCE_METADATA"end
 local safe={};if type(metadata)=="table"then
  for key in pairs(metadata)do if key~="characterUUID"and key~="characterName"then return nil,"INVALID_PROVENANCE_METADATA"end end
  for _,key in ipairs({"characterUUID","characterName"})do local value=metadata[key];if value~=nil then if type(value)~="string"or#value>128 then return nil,"INVALID_PROVENANCE_METADATA"end;safe[key]=value end end
 end
 return{kind=source,metadata=safe}
end
function POI:Normalize(input,current)
 local result=copy(input or{});result.poiID=result.poiID or self:NewId();result.target=string.upper(tostring(result.target or(current and current.target)or"PERSONAL"));result.scope=result.target
 result.schemaVersion=2;result.mapID=tonumber(result.mapID);result.x=tonumber(result.x);result.y=tonumber(result.y);result.name=HolyStorm.Utils.Trim(result.name or"");result.description=tostring(result.description or"");result.category=tostring(result.category or"note"):lower();result.customCategory=HolyStorm.Utils.Trim(result.customCategory or"")
 result.icon=self.icons[result.icon]and result.icon or"marker";result.color=type(result.color)=="table"and result.color or{r=1,g=.82,b=0,a=1};result.status=string.upper(tostring(result.status or"ACTIVE"));result.expiresAt=tonumber(result.expiresAt);result.lifetime=tonumber(result.lifetime)
 if result.lifetime and result.lifetime>0 and not result.expiresAt then result.expiresAt=now()+result.lifetime end
 if result.target=="GUILD"then result.guildId=result.guildId or HolyStorm.Data.POIStore:GetGuildId();result.sessionId=nil
 elseif result.target=="GROUP"or result.target=="RAID"then local context=self:GetCurrentContext();result.sessionId=result.sessionId or(context and context.target==result.target and context.sessionId);result.guildId=nil
 else result.guildId,result.sessionId=nil,nil end
 if current then
  result.creatorGuid=current.creatorGuid;result.creatorAccountUUID=current.creatorAccountUUID;result.creatorName=current.creatorName;result.createdAt=current.createdAt
  result.provenance=copy(current.provenance);result.previousRevisionID=current.revisionID
 else
  local existingProvenance=type(result.provenance)=="table"and result.provenance or nil
  local provenance,reason=self:MakeProvenance(result.source,existingProvenance and existingProvenance.metadata or result.sourceMetadata)
  if existingProvenance and existingProvenance.kind then provenance,reason=self:MakeProvenance(existingProvenance.kind,existingProvenance.metadata)end
  if provenance then result.provenance=provenance else result.provenanceError=reason end
 end
 result.source=nil;result.sourceMetadata=nil;result.receivedFrom=nil;result.syncedAt=nil;result.lifetime=nil;result.temporary=nil
 return result
end
function POI:Validate(entry)
 if type(entry)~="table"or entry.schemaVersion~=2 or not validId(entry.poiID)or not self.targets[entry.target]or entry.scope~=entry.target or not self.statuses[entry.status]then return false,"INVALID_POI"end
 local allowed={poiID=true,schemaVersion=true,target=true,scope=true,mapID=true,x=true,y=true,name=true,description=true,category=true,customCategory=true,icon=true,color=true,status=true,expiresAt=true,guildId=true,sessionId=true,creatorGuid=true,creatorAccountUUID=true,creatorName=true,createdAt=true,modifiedBy=true,updatedAt=true,revision=true,revisionID=true,previousRevisionID=true,provenance=true,deletedAt=true,deletedBy=true}
 for key in pairs(entry)do if not allowed[key]then return false,"INVALID_FIELD"end end
 if not self:IsMapValid(entry.mapID)or not finite(entry.x)or not finite(entry.y)or entry.x<0 or entry.x>1 or entry.y<0 or entry.y>1 then return false,"INVALID_POSITION"end
 if type(entry.name)~="string"or#entry.name==0 or#entry.name>self.maxName or type(entry.description)~="string"or#entry.description>self.maxDescription or type(entry.customCategory)~="string"or#entry.customCategory>self.maxCustomCategory then return false,"INVALID_TEXT"end
 if not self.categories[entry.category]or entry.category=="custom"and entry.customCategory==""then return false,"INVALID_CATEGORY"end
 if not self.icons[entry.icon]then return false,"INVALID_ICON"end
 if type(entry.provenance)~="table"or(entry.provenance.kind~="MANUAL"and entry.provenance.kind~="CURRENT_PLAYER_POSITION"and entry.provenance.kind~="GUILD_PLAYER_POSITION")or type(entry.provenance.metadata or{})~="table"then return false,"INVALID_PROVENANCE"end
 for key,value in pairs(entry.provenance.metadata or{})do if(key~="characterUUID"and key~="characterName")or type(value)~="string"or#value>128 then return false,"INVALID_PROVENANCE_METADATA"end end
 local c=entry.color;if type(c)~="table"or not finite(c.r)or not finite(c.g)or not finite(c.b)or not finite(c.a)or c.r<0 or c.r>1 or c.g<0 or c.g>1 or c.b<0 or c.b>1 or c.a<0 or c.a>1 then return false,"INVALID_COLOR"end
 if entry.expiresAt~=nil and(not finite(entry.expiresAt)or entry.expiresAt<0)then return false,"INVALID_EXPIRATION"end
 if not finite(entry.revision)or entry.revision<1 or entry.revision%1~=0 or not validId(entry.revisionID)or type(entry.creatorGuid)~="string"or#entry.creatorGuid==0 or#entry.creatorGuid>128 or type(entry.modifiedBy)~="string"or#entry.modifiedBy==0 or#entry.modifiedBy>128 or not finite(entry.createdAt)or entry.createdAt<0 or not finite(entry.updatedAt)or entry.updatedAt<entry.createdAt then return false,"INVALID_METADATA"end
 if entry.creatorName~=nil and(type(entry.creatorName)~="string"or#entry.creatorName>128)or entry.creatorAccountUUID~=nil and(type(entry.creatorAccountUUID)~="string"or#entry.creatorAccountUUID>160)then return false,"INVALID_CREATOR"end
 if entry.previousRevisionID~=nil and not validId(entry.previousRevisionID)then return false,"INVALID_REVISION_CHAIN"end
 if entry.status=="DELETED"and(not finite(entry.deletedAt)or type(entry.deletedBy)~="string"or entry.deletedBy=="")then return false,"INVALID_TOMBSTONE"end
 if entry.target=="GUILD"and(type(entry.guildId)~="string"or entry.guildId=="")then return false,"INVALID_GUILD"end
 if(entry.target=="GROUP"or entry.target=="RAID")and not validId(entry.sessionId)then return false,"INVALID_SESSION"end
 return true
end
function POI:NormalizeIncoming(entry)return entry end
function POI:IsExpired(entry)return entry and entry.expiresAt and entry.expiresAt<=now()end
function POI:CanView(entry,ignoreLocal,settings)
 if not entry or entry.status~="ACTIVE"or self:IsExpired(entry)or not self:IsModuleEnabled(entry.target)then return false end
 if entry.target=="GUILD"and entry.guildId~=HolyStorm.Data.POIStore:GetGuildId()then return false end
 if entry.target=="GROUP"or entry.target=="RAID"then local context=self:GetCurrentContext();if not context or context.target~=entry.target or context.sessionId~=entry.sessionId then return false end end
 if not ignoreLocal then settings=settings or self:GetSettings();if settings.hidden[entry.poiID]or settings.categoryVisible[entry.category]==false or settings.targetVisible[entry.target]==false then return false end end
 return true
end
function POI:Get(id)local entry=HolyStorm.Data.POIStore:Get(id);if not entry then return nil end;entry=copy(entry);entry.receivedFrom=nil;entry.syncedAt=nil;return entry end
function POI:GetVisible(options)
 options=options or{};local settings=self:GetSettings();local out={};local q=string.lower(HolyStorm.Utils.Trim(options.search or""));local player=UnitGUID("player")
 local includeHidden=options.includeHidden==true or options.mode=="HIDDEN"
 for _,stored in ipairs(HolyStorm.Data.POIStore:GetAll())do local entry=stored;local visible=self:CanView(entry,includeHidden,settings);local hidden=settings.hidden[entry.poiID]==true
  local mode=not options.mode or options.mode=="ALL"or options.mode=="OWN"and entry.creatorGuid==player or options.mode=="SYNCED"and entry.target~="PERSONAL"or options.mode=="HIDDEN"and hidden
  if visible and mode and(options.mode~="HIDDEN"or hidden)then local haystack=string.lower(table.concat({entry.name,entry.description,entry.creatorName or"",entry.customCategory or""}," "));if q==""or haystack:find(q,1,true)then out[#out+1]=copy(entry)end end
 end
 local field=options.sort or"name";table.sort(out,function(a,b)local av,bv=a[field],b[field];if av==bv then return a.poiID<b.poiID end;if av==nil then return false elseif bv==nil then return true end;return options.desc and av>bv or av<bv end);return out
end
function POI:CountSynced()
 local count=0;for _,entry in ipairs(HolyStorm.Data.POIStore:GetAll())do if entry.target~="PERSONAL"and entry.status=="ACTIVE"then count=count+1 end end;return count
end
function POI:CanMutate(entry,action,actorGuid)
 local target=entry and entry.target or"PERSONAL";if target=="PERSONAL"then return true end
 local permissionId=permission(target,action);if not permissionId then return false end;actorGuid=actorGuid or UnitGUID("player")
 local permissions=HolyStorm.PermissionEngine or HolyStorm.Policy
 return permissions and permissions:Can(permissionId,account(actorGuid),actorGuid,entry)==true
end
function POI:Save(input,expectedRevision)
 local current=input and input.poiID and self:Get(input.poiID)or nil
 if current and current.status=="DELETED"then return false,"DELETED"end
 local candidate=self:Normalize(input,current);if not self:IsModuleEnabled(candidate.target)then return false,"MODULE_DISABLED"end
 if current and tonumber(expectedRevision)~=tonumber(current.revision)then return false,"CONFLICT",current.revision elseif not current and expectedRevision~=nil and tonumber(expectedRevision)~=0 then return false,"CONFLICT",0 end
 if current and candidate.target~=current.target then return false,"SCOPE_IMMUTABLE"end
 if current and not self:CanMutate(current,"edit")then log("WARN","POI permission rejected",{poiID=candidate.poiID,action="edit"});return false,"PERMISSION_DENIED"end
 if not current and not self:CanMutate(candidate,"create")then return false,"PERMISSION_DENIED"end
 local actor=UnitGUID("player");candidate.creatorGuid=current and current.creatorGuid or candidate.creatorGuid or actor;candidate.creatorAccountUUID=current and current.creatorAccountUUID or candidate.creatorAccountUUID or account(actor);candidate.creatorName=current and current.creatorName or candidate.creatorName or GetUnitName("player",true);candidate.createdAt=current and current.createdAt or now();candidate.modifiedBy=actor;candidate.updatedAt=now();candidate.revision=(current and current.revision or 0)+1;candidate.previousRevisionID=current and current.revisionID or nil;candidate.revisionID=self:NewRevisionID(candidate.poiID,candidate.revision,actor);candidate.status="ACTIVE"
 if candidate.provenanceError then return false,candidate.provenanceError end
 local valid,reason=self:Validate(candidate);if not valid then return false,reason end
 if not current and#HolyStorm.Data.POIStore:GetAll()>=self.maxEntries then return false,"POI_LIMIT"end
 local saved,storeReason=HolyStorm.Data.POIStore:Put(candidate);if not saved then return false,storeReason end
 if candidate.target~="PERSONAL"then HolyStorm.Sync:Publish("poi",candidate.poiID,current and"POI_UPDATED"or"POI_CREATED");if candidate.target=="GUILD"then self:PruneTombstones(candidate.guildId)end end
 HolyStorm.Events:Emit(current and"HS_POI_UPDATED"or"HS_POI_CREATED",candidate.poiID,candidate.target);HolyStorm.Events:Emit("HS_POI_LIST_CHANGED",candidate.poiID,current and"UPDATED"or"CREATED");log("INFO",current and"POI updated"or"POI created",{poiID=candidate.poiID,target=candidate.target})
 self.expiredNotified[candidate.poiID]=nil;self:ScheduleExpiration();self:Refresh("SAVE");return true,copy(candidate)
end
function POI:Delete(id,expectedRevision)
 local entry=self:Get(id);if not entry then return false,"NOT_FOUND"end;if entry.status=="DELETED"then return false,"DELETED"end
 if tonumber(expectedRevision)~=tonumber(entry.revision)then return false,"CONFLICT",entry.revision end
 if not self:CanMutate(entry,"delete")then return false,"PERMISSION_DENIED"end
 if entry.target=="PERSONAL"then HolyStorm.Data.POIStore:Remove(entry);self:UpdateSettings(function(settings)settings.hidden[id]=nil;return true end)
 else
  entry.status="DELETED";entry.deletedAt=now();entry.deletedBy=UnitGUID("player");entry.updatedAt=now();entry.modifiedBy=entry.deletedBy;entry.previousRevisionID=entry.revisionID;entry.revision=entry.revision+1;entry.revisionID=self:NewRevisionID(id,entry.revision,entry.deletedBy)
  HolyStorm.Data.POIStore:Put(entry);HolyStorm.Sync:Publish("poi",id,"POI_DELETED");if entry.target=="GUILD"then self:PruneTombstones(entry.guildId)end
 end
 HolyStorm.Events:Emit("HS_POI_DELETED",id,entry.target);HolyStorm.Events:Emit("HS_POI_LIST_CHANGED",id,"DELETED");log("INFO","POI deleted",{poiID=id,target=entry.target});self:Refresh("DELETE");return true,entry
end
function POI:PruneTombstones(guildId)
 local bucket=HolyStorm.Data.POIStore:GetBucket("GUILD",nil,false,guildId);if not bucket then return 0 end
 local deleted={};local cutoff=now()-self.tombstoneRetention
 for id,entry in pairs(bucket)do if entry.status=="DELETED"then if (tonumber(entry.deletedAt)or 0)<cutoff then bucket[id]=nil else deleted[#deleted+1]={id=id,at=tonumber(entry.deletedAt)or 0}end end end
 table.sort(deleted,function(a,b)if a.at==b.at then return a.id<b.id end;return a.at<b.at end)
 local excess=#deleted-self.maxGuildTombstones;for index=1,math.max(0,excess)do bucket[deleted[index].id]=nil end
 return math.max(0,#deleted-math.max(0,excess))
end
function POI:SetHidden(id,hidden)
 local entry=self:Get(id);if not entry then return false end
 local ok=self:UpdateSettings(function(settings)settings.hidden[id]=hidden==true or nil;return true end)
 if ok then HolyStorm.Events:Emit("HS_POI_VISIBILITY_CHANGED",id,hidden==true);self:Refresh("LOCAL_HIDE")end;return ok
end
function POI:GetCategoryName(entry)local category=self.categories[entry.category];return entry.category=="custom"and entry.customCategory or category and(category.nameKey and L[category.nameKey]or category.name)or entry.category end
function POI:GetIcon(entry)return self.icons[entry and entry.icon]or self.icons.marker end
function POI:GetRemaining(entry)if not entry.expiresAt then return nil end;return math.max(0,entry.expiresAt-now())end
function POI:GetTooltip(entry)return entry.name,entry.description,{category=self:GetCategoryName(entry),creator=entry.creatorName,remaining=self:GetRemaining(entry),target=entry.target,map=self:GetMapName(entry.mapID),createdAt=entry.createdAt,updatedAt=entry.updatedAt,expiresAt=entry.expiresAt,provenance=entry.provenance and entry.provenance.kind}end
function POI:Open(id)
 local entry=self:Get(id);if not entry then HolyStorm.Sync:RequestObject("poi",id,{reason="POI_LINK_OPEN"});return false,"LOADING"end
 if not self:CanView(entry)then return false,"UNAVAILABLE"end;HolyStorm:CallCapability("poi.open",id);return HolyStorm.MapLinks:OpenCoordinate(entry.mapID,entry.x,entry.y,entry.name)
end
function POI:Share(id)local entry=self:Get(id);if not self:CanView(entry)or entry.target=="PERSONAL"then return false,"UNAVAILABLE"end;return HolyStorm.RichLinks:InsertChatLink("poi",id,string.format(L["POI_LINK_LABEL"],entry.name))end
function POI:RequestCreate(input)
 if type(input)~="table"then return nil,"INVALID_REQUEST"end
 if not self:IsMapValid(input.mapID)or not finite(input.x)or not finite(input.y)or input.x<0 or input.x>1 or input.y<0 or input.y>1 then return nil,"INVALID_POSITION"end
 local source=input.source or"MANUAL";local provenance,reason=self:MakeProvenance(source,input.metadata);if not provenance then return nil,reason end
 local name=HolyStorm.Utils.Trim(input.name or"");if#name>self.maxName then return nil,"INVALID_TEXT"end
 local description=tostring(input.description or"");if#description>self.maxDescription then return nil,"INVALID_TEXT"end
 return{target="PERSONAL",scope="PERSONAL",mapID=tonumber(input.mapID),x=tonumber(input.x),y=tonumber(input.y),name=name,description=description,category=self.categories[input.category]and input.category or"note",customCategory="",icon=self.icons[input.icon]and input.icon or"marker",color=type(input.color)=="table"and copy(input.color)or{r=1,g=.82,b=0,a=1},source=source,provenance=provenance}
end
function POI:SetTemporaryMarker(mapID,x,y,options)local ok,marker=HolyStorm.MapLinks:SetTemporaryMarker(mapID,x,y,options);if ok then self:Refresh("TEMPORARY_MARKER")end;return ok,marker end
function POI:ClearTemporaryMarker()local removed=HolyStorm.MapLinks:ClearTemporaryMarker();if removed then self:Refresh("TEMPORARY_MARKER_CLEAR")end;return removed end
function POI:Refresh(reason)local refreshReason=reason or"POI_CHANGED";if HolyStorm.POIMap and HolyStorm.POIMap.SetRefreshReason then HolyStorm.POIMap:SetRefreshReason(refreshReason)end;HolyStorm.Tasks:Queue("POI.MapRefresh",{mergeKey="all",debounce=.1,priority=88,triggerSource=refreshReason})end
function POI:ScheduleExpiration()
 local nextAt;for _,entry in ipairs(HolyStorm.Data.POIStore:GetAll())do if entry.status=="ACTIVE"and entry.expiresAt and entry.expiresAt>now()then nextAt=nextAt and math.min(nextAt,entry.expiresAt)or entry.expiresAt end end
 if nextAt then HolyStorm.Tasks:Queue("POI.Expire",{mergeKey="expiration",delay=math.max(0,nextAt-now()),priority=90,triggerSource="EXPIRATION_SCHEDULE"})end
end
function POI:CleanupExpired()
 local changed=0
 for _,stored in ipairs(HolyStorm.Data.POIStore:GetAll())do local entry=copy(stored);if entry.status=="ACTIVE"and self:IsExpired(entry)then
  if entry.target=="PERSONAL"or entry.target=="GROUP"or entry.target=="RAID"then HolyStorm.Data.POIStore:Remove(entry);changed=changed+1
  elseif self:CanMutate(entry,"delete",entry.creatorGuid)or self:CanMutate(entry,"delete")then local ok=self:Delete(entry.poiID,entry.revision);if ok then changed=changed+1 end end
  if self.expiredNotified[entry.poiID]~=entry.revisionID then self.expiredNotified[entry.poiID]=entry.revisionID;HolyStorm.Events:Emit("HS_POI_EXPIRED",entry.poiID,entry.target);log("INFO","POI expired",{poiID=entry.poiID,target=entry.target})end
 end end
 if changed>0 then HolyStorm.Events:Emit("HS_POI_LIST_CHANGED",nil,"EXPIRED");self:Refresh("EXPIRED")end;self:ScheduleExpiration();return true
end
function POI:HandleGroupContext()
 local previous=self.currentContext;local current=self:GetCurrentContext();local changed=not previous and current or previous and(not current or previous.sessionId~=current.sessionId or previous.target~=current.target)
 if previous and changed then local removed=HolyStorm.Data.POIStore:RemoveSession(previous.sessionId);if removed>0 then HolyStorm.Events:Emit("HS_POI_SESSION_CLEARED",previous.sessionId,removed);self:Refresh("SESSION_LEFT")end end
 self.currentContext=current
 if current then HolyStorm.Data.POIStore:RemoveOtherSessions(current.sessionId);if changed then self.lastResync=now();HolyStorm.Sync:Discover("poi",nil,{channel=current.target=="RAID"and"RAID"or"PARTY",scope=current.target,sessionId=current.sessionId,reason="POI_SESSION_RESYNC",priority=86,delay=.3+math.random()*1.5})end end
 if not current then local removed=HolyStorm.Data.POIStore:RemoveOtherSessions(nil);if removed>0 then HolyStorm.Events:Emit("HS_POI_LIST_CHANGED",nil,"SESSION_CLEANUP");self:Refresh("SESSION_CLEANUP")end end
end
function POI:GetDiagnostics()
 local pending,queued={},0;for _,request in pairs(HolyStorm.Sync.requests or{})do if request.domain=="poi"and request.objectId then pending[request.objectId]=true end end
 if HolyStorm.Tasks.GetLiveTasks then for _,task in ipairs(HolyStorm.Tasks:GetLiveTasks())do if task.module=="POI"or task.metadata and task.metadata.domain=="poi"then queued=queued+1 end end end
 local rows={};for _,entry in ipairs(HolyStorm.Data.POIStore:GetAll())do local map=HolyStorm.POIMap and HolyStorm.POIMap:GetRenderState(entry.poiID)or{};rows[#rows+1]={poiID=entry.poiID,target=entry.target,mapID=entry.mapID,x=entry.x,y=entry.y,creator=entry.creatorGuid,revision=entry.revision,revisionID=entry.revisionID,source=entry.provenance and entry.provenance.kind,receivedFrom=entry.receivedFrom,expiresAt=entry.expiresAt,sessionId=entry.sessionId,visible=self:CanView(entry),hidden=self:GetSettings().hidden[entry.poiID]==true,worldPin=map.worldPin==true,minimapPin=map.minimapPin==true,viewedMapID=map.viewedMapID,minimapViewedMapID=map.minimapViewedMapID,transform=map.transform,transformedX=map.transformedX,transformedY=map.transformedY,lastReceived=entry.syncedAt,pendingFetch=pending[entry.poiID]==true}end
 return{entries=rows,context=copy(self.currentContext),lastResync=self.lastResync,pendingCount=HolyStorm.Utils.TableCount(pending),queuedTasks=queued,suppressionRequests=HolyStorm.Utils.TableCount(HolyStorm.Sync.heard or{}),worldMap=HolyStorm.POIMap and HolyStorm.POIMap.GetWorldMapDiagnostics and HolyStorm.POIMap:GetWorldMapDiagnostics()or nil}
end
function POI:PruneIncomingMetadata(entry,metadata)
 return type(metadata)=="table"and metadata.objectId==entry.poiID and tonumber(metadata.version)==entry.revision and metadata.revisionID==entry.revisionID and tonumber(metadata.updatedAt)==entry.updatedAt and metadata.owner==entry.modifiedBy and metadata.target==entry.target and metadata.scope==entry.scope
end
function POI:IsRelayMember(senderGuid,target)
 if not senderGuid then return false end
 if target=="GUILD"then
  local guild=HolyStorm.Data.GuildStore.GetCurrentRosterSummary and HolyStorm.Data.GuildStore:GetCurrentRosterSummary()
  return type(guild)=="table"and type(guild.roster)=="table"and guild.roster[senderGuid]~=nil
 end
 local raid=target=="RAID";local count=raid and(GetNumGroupMembers and GetNumGroupMembers()or 0)or(GetNumSubgroupMembers and GetNumSubgroupMembers()or 0)
 for index=1,count do local unit=raid and("raid"..index)or("party"..index);if UnitExists and UnitExists(unit)and UnitGUID(unit)==senderGuid then return true end end
 return UnitGUID("player")==senderGuid
end
function POI:CanServe(metadata,recipientGuid,recipientName)
 if type(metadata)~="table"or not validId(metadata.objectId)then return false,"INVALID"end
 if metadata.target=="PERSONAL"then return false,"NOT_VISIBLE"end
 local entry=self:Get(metadata.objectId);if not entry then return false,"NOT_FOUND"end
 local valid=self:Validate(entry);if not valid then return false,"INVALID"end
 if entry.status=="ACTIVE"and self:IsExpired(entry)then return false,"NOT_FOUND"end
 if not self:PruneIncomingMetadata(entry,metadata)then return false,"STALE"end
 if not self:IsModuleEnabled(entry.target)then return false,"MODULE_DISABLED"end
 if entry.target=="GUILD"then
  if entry.guildId~=HolyStorm.Data.POIStore:GetGuildId()then return false,"NOT_VISIBLE"end
  if not self:IsRelayMember(recipientGuid,"GUILD")then return false,"NOT_VISIBLE"end
 elseif entry.target=="GROUP"or entry.target=="RAID"then
  local context=self:GetCurrentContext();if not context or context.target~=entry.target or context.sessionId~=entry.sessionId then return false,"STALE"end
  if not self:IsRelayMember(recipientGuid,entry.target)then return false,"NOT_VISIBLE"end
 else return false,"NOT_VISIBLE"end
 return true
end
function POI:CompareFork(current,incoming)
 if current.status=="DELETED"and incoming.status~="DELETED"then return false,"TOMBSTONE_WINS"end
 if incoming.status=="DELETED"and current.status~="DELETED"then return true,"TOMBSTONE_WINS"end
 if incoming.status=="DELETED"and current.status=="DELETED"then return incoming.revisionID>current.revisionID,"TOMBSTONE_FORK"end
 return incoming.revisionID>current.revisionID,"REVISION_FORK"
end
function POI:PayloadEqual(left,right)
 local a,b=copy(left),copy(right);a.receivedFrom=nil;a.syncedAt=nil;b.receivedFrom=nil;b.syncedAt=nil
 local leftText=HolyStorm.Serializer and HolyStorm.Serializer:Serialize(a);local rightText=HolyStorm.Serializer and HolyStorm.Serializer:Serialize(b)
 return leftText~=nil and leftText==rightText
end
function POI:IdentityEqual(current,incoming)
 return current.creatorGuid==incoming.creatorGuid and current.creatorAccountUUID==incoming.creatorAccountUUID and current.creatorName==incoming.creatorName and current.createdAt==incoming.createdAt and self:PayloadEqual(current.provenance,incoming.provenance)
end
function POI:Import(id,entry,metadata,senderGuid,sender)
 local valid,reason=self:Validate(entry);if not valid or id~=entry.poiID or entry.target=="PERSONAL"or not self:PruneIncomingMetadata(entry,metadata)then log("WARN","POI import validation failed",{poiID=id,reason=reason or"METADATA_MISMATCH"});return false,reason or"METADATA_MISMATCH"end
 if not self:IsModuleEnabled(entry.target)then return false,"MODULE_DISABLED"end
 if entry.target=="GUILD"and entry.guildId~=HolyStorm.Data.POIStore:GetGuildId()then return false,"WRONG_GUILD"end
 if entry.target=="GROUP"or entry.target=="RAID"then local context=self:GetCurrentContext();if not context or context.sessionId~=entry.sessionId or context.target~=entry.target then return false,"WRONG_SESSION"end end
 local current=self:Get(id)
 if current then
  if current.target~=entry.target or current.scope~=entry.scope then return false,"SCOPE_MISMATCH"end
  if not self:IdentityEqual(current,entry)then log("WARN","POI origin metadata changed",{poiID=id});return false,"ORIGIN_IMMUTABLE"end
  if current.status=="DELETED"and entry.status~="DELETED"then return false,"TOMBSTONE_WINS"end
  if entry.revision<current.revision then return false,"STALE"end
  if entry.revision==current.revision then
   if entry.revisionID==current.revisionID then if self:PayloadEqual(entry,current)then return true,"NOOP"end;log("WARN","POI revision ID collision",{poiID=id,revisionID=entry.revisionID});return false,"REVISION_ID_COLLISION"end
   local wins,conflict=self:CompareFork(current,entry);log("WARN","POI revision conflict resolved",{poiID=id,revision=entry.revision,localRevision=current.revisionID,remoteRevision=entry.revisionID,resolution=wins and"REMOTE"or"LOCAL",conflict=conflict});if not wins then return false,conflict end
  end
 elseif entry.status=="ACTIVE"and self:CountSynced()>=self:GetSettings().maxSynced then log("WARN","POI receive limit reached",{poiID=id});return false,"POI_LIMIT"end
 local imported=copy(entry);imported.receivedFrom=sender;imported.syncedAt=now()
 local saved,storeReason=HolyStorm.Data.POIStore:Put(imported);if not saved then return false,storeReason end
 if imported.target=="GUILD"then self:PruneTombstones(imported.guildId)end
 local event=imported.status=="DELETED"and"HS_POI_DELETED"or current and"HS_POI_UPDATED"or"HS_POI_SYNCED"
 HolyStorm.Events:Emit(event,id,imported.target);HolyStorm.Events:Emit("HS_POI_LIST_CHANGED",id,event);self:ScheduleExpiration();self:Refresh("SYNC");return true
end
function POI:RegisterSyncDomain()
 HolyStorm.Sync:RegisterDomain("poi",{freshness="revision-chain",catchUp=false,getChannel=function(meta)return meta and(meta.target=="RAID"and"RAID"or meta.target=="GROUP"and"PARTY"or"GUILD")or"GUILD"end,getRecipients=function()return nil end,
  getMetadata=function(id)local entry=POI:Get(id);if not entry or entry.target=="PERSONAL"or entry.status=="ACTIVE"and POI:IsExpired(entry)then return nil end;return{objectId=id,owner=entry.modifiedBy,version=entry.revision,revisionID=entry.revisionID,previousRevisionID=entry.previousRevisionID,updatedAt=entry.updatedAt,target=entry.target,scope=entry.scope,sessionId=entry.sessionId}end,
  canShare=function(meta,recipientGuid,recipientName)return POI:CanServe(meta,recipientGuid,recipientName)end,
  listMetadata=function(since,request)local out={};for _,entry in ipairs(HolyStorm.Data.POIStore:GetAll())do local inScope=entry.target=="GUILD"and(not request or not request.scope or request.scope=="GUILD")or(entry.target=="GROUP"or entry.target=="RAID")and request and request.scope==entry.target and request.sessionId==entry.sessionId;if entry.target~="PERSONAL"and inScope and(entry.status=="DELETED"or not POI:IsExpired(entry))and(entry.updatedAt or 0)>since then out[#out+1]={objectId=entry.poiID,owner=entry.modifiedBy,version=entry.revision,revisionID=entry.revisionID,previousRevisionID=entry.previousRevisionID,updatedAt=entry.updatedAt,target=entry.target,scope=entry.scope,sessionId=entry.sessionId}end end;return out end,
  export=function(id)local entry=POI:Get(id);if not entry or entry.target=="PERSONAL"then return nil end;entry.receivedFrom=nil;entry.syncedAt=nil;return entry end,
  validate=function(entry,meta,id)local valid,reason=POI:Validate(entry);if not valid then log("WARN","Rejected incoming POI",{poiID=id,reason=reason});return false,reason end;if not POI:PruneIncomingMetadata(entry,meta)or entry.target=="PERSONAL"then return false,"METADATA_MISMATCH"end;if entry.target=="GUILD"and entry.guildId~=HolyStorm.Data.POIStore:GetGuildId()then return false,"WRONG_GUILD"end;if entry.target=="GROUP"or entry.target=="RAID"then local context=POI:GetCurrentContext();if not context or context.target~=entry.target or context.sessionId~=entry.sessionId then return false,"WRONG_SESSION"end end;return true end,
  authorize=function(entry,meta,senderGuid)local id=permission(entry.target,entry.status=="DELETED"and"delete"or POI:Get(entry.poiID)and"edit"or"create");if not id or meta.owner~=entry.modifiedBy then return false end;if meta.direct and senderGuid~=meta.owner then return false end;if not meta.direct and not POI:IsRelayMember(senderGuid,entry.target)then return false end;local engine=HolyStorm.PermissionEngine or HolyStorm.Policy;return engine and engine:Can(id,account(meta.owner),meta.owner,entry)==true end,
  import=function(id,entry,meta,senderGuid,sender)return POI:Import(id,entry,meta,senderGuid,sender)end,updateEvent="HS_POI_SYNCED"})
end
function POI:RunStartup()
 self:CleanupExpired();for guildId in pairs(HolyStorm.Data.POIStore:GetRoot().guilds)do self:PruneTombstones(guildId)end;self:HandleGroupContext();if not self.guildDiscoveryStarted and self:IsModuleEnabled("GUILD")then local requestId=HolyStorm.Sync:Discover("poi",nil,{channel="GUILD",scope="GUILD",reason="POI_LOGIN",priority=94,startupPhase=4});self.guildDiscoveryStarted=requestId~=nil and requestId~=false end;return true
end
function POI:Initialize()
 local stored,storeError=HolyStorm.Data.POIStore:Initialize();if not stored then log("ERROR","POI store unavailable",{reason=storeError});return false,storeError end
 local settings,settingsError=self:InitializeSettings();if not settings then log("WARN","POI settings unavailable",{reason=settingsError})end
 self:RegisterCategory("quest",{nameKey="POI_CATEGORY_QUEST"});self:RegisterCategory("achievement",{nameKey="POI_CATEGORY_ACHIEVEMENT"});self:RegisterCategory("raid-entrance",{nameKey="POI_CATEGORY_RAID_ENTRANCE"});self:RegisterCategory("note",{nameKey="POI_CATEGORY_NOTE"});self:RegisterCategory("custom",{nameKey="POI_CATEGORY_CUSTOM"})
 self:RegisterLocalSettings()
 local icons={marker="Interface\\Icons\\INV_Misc_Map_01",circle="Interface\\TargetingFrame\\UI-RaidTargetingIcon_2",dot="Interface\\TargetingFrame\\UI-RaidTargetingIcon_2",star="Interface\\TargetingFrame\\UI-RaidTargetingIcon_1",skull="Interface\\TargetingFrame\\UI-RaidTargetingIcon_8",diamond="Interface\\TargetingFrame\\UI-RaidTargetingIcon_3",triangle="Interface\\TargetingFrame\\UI-RaidTargetingIcon_4",moon="Interface\\TargetingFrame\\UI-RaidTargetingIcon_5",square="Interface\\TargetingFrame\\UI-RaidTargetingIcon_6",cross="Interface\\TargetingFrame\\UI-RaidTargetingIcon_7",exclamation="Interface\\GossipFrame\\AvailableQuestIcon",quest="Interface\\GossipFrame\\AvailableQuestIcon",question="Interface\\GossipFrame\\ActiveQuestIcon",treasure="Interface\\Icons\\INV_Misc_Coin_01",portal="Interface\\Icons\\Spell_Arcane_TeleportStormWind",flag="Interface\\Icons\\INV_BannerPVP_02",note="Interface\\Icons\\INV_Misc_Note_01"}
 for id,texture in pairs(icons)do self:RegisterIcon(id,{texture=texture,nameKey="POI_ICON_"..string.upper(id)})end
 HolyStorm.Tasks:RegisterTaskType("POI.Expire",{name=L["TASK_POI_EXPIRE"],localizedNameKey="TASK_POI_EXPIRE",module="POI",priority=90,executionMode="MERGE_BY_KEY",execute=function()return POI:CleanupExpired()end})
 HolyStorm.Tasks:RegisterTaskType("POI.MapRefresh",{name=L["TASK_POI_MAP_REFRESH"],localizedNameKey="TASK_POI_MAP_REFRESH",module="POI",priority=88,executionMode="MERGE_BY_KEY",execute=function()if HolyStorm.POIMap then HolyStorm.POIMap:Refresh()end;return true end})
 HolyStorm.Tasks:RegisterTaskType("POI.Context",{name=L["TASK_POI_CONTEXT"],localizedNameKey="TASK_POI_CONTEXT",module="POI",priority=84,executionMode="UNIQUE",execute=function()POI:HandleGroupContext();return true end})
 HolyStorm.Tasks:RegisterTaskType("POI.Startup",{name=L["TASK_POI_STARTUP"],localizedNameKey="TASK_POI_STARTUP",module="POI",priority=90,executionMode="UNIQUE",conditions={"PLAYER_READY","NOT_LOADING","NOT_ZONING"},execute=function()return POI:RunStartup()end})
 self:RegisterSyncDomain()
 if HolyStorm.Rules then local RuleL=LibStub("AceLocale-3.0"):GetLocale("Holy_Storm_POI");local fields={target=function(p)return p.target end,category=function(p)return p.category end,creator=function(p)return p.creatorGuid end,mapID=function(p)return p.mapID end,temporary=function(p)return p.temporary==true end};for id,getter in pairs(fields)do local resolver=getter;local key="RULE_FIELD_"..string.upper(id);HolyStorm.Rules:RegisterField("poi","poi."..id,{type=id=="mapID"and"number"or id=="temporary"and"boolean"or"string",name=RuleL[key],nameKey=key,description=RuleL[key.."_DESC"],descriptionKey=key.."_DESC",category=RuleL["TITLE"],resolver=function(context)local poi=context.target and context.target.poi;return poi and resolver(poi)end})end end
 HolyStorm.MapLinks:RegisterPOIProvider("holy-storm-poi",{get=function(id)local entry=POI:Get(id);return POI:CanView(entry)and entry or nil end,list=function()return POI:GetVisible()end,open=function(id)return POI:Open(id)end})
 HolyStorm.Events:Register("GROUP_ROSTER_UPDATE","poi-context",function()HolyStorm.Tasks:Queue("POI.Context",{mergeKey="group-context",debounce=.5,priority=84,triggerSource="GROUP_ROSTER_UPDATE"})end)
 HolyStorm.Events:Register("PLAYER_ENTERING_WORLD","poi-startup",function()HolyStorm.Tasks:Queue("POI.Startup",{mergeKey="startup",delay=.2,startupPhase=4,priority=90,triggerSource="PLAYER_ENTERING_WORLD"})end)
 HolyStorm.Tasks:Queue("POI.Startup",{mergeKey="startup",delay=.1,startupPhase=4,priority=90,triggerSource="POI_INITIALIZE"})
 return true
end
HolyStorm.POI=POI
