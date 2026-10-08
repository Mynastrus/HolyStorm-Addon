local root=(arg[0]:gsub("tools[/\\]test_poi.lua$","")).."LIVE/Holy_Storm/"
local featureRoot=(arg[0]:gsub("tools[/\\]test_poi.lua$","")).."LIVE/Holy_Storm_POI/"
local function copy(value,seen)if type(value)~="table"then return value end;seen=seen or{};if seen[value]then return seen[value]end;local out={};seen[value]=out;for key,child in pairs(value)do out[copy(key,seen)]=copy(child,seen)end;return out end
local function serialize(value)
 if type(value)~="table"then return type(value)..":"..tostring(value)end
 local keys={};for key in pairs(value)do keys[#keys+1]=key end;table.sort(keys,function(a,b)return tostring(a)<tostring(b)end)
 local out={};for _,key in ipairs(keys)do out[#out+1]=serialize(key).."="..serialize(value[key])end;return"{"..table.concat(out,",").."}"
end
local function valueAt(value,path)for _,key in ipairs(path or{})do if type(value)~="table"then return nil end;value=value[key]end;return value end
local function setAt(value,path,child)for index=1,#path-1 do value[path[index]]=type(value[path[index]])=="table"and value[path[index]]or{};value=value[path[index]]end;value[path[#path]]=child end

local clock=1000;local currentGuid="Player-A";local currentGuild={id="realm:guild"};local currentRoster={};local moduleEnabled=true;local permissions={};local groupMode=nil
local locale=setmetatable({TASK_POI_EXPIRE="Expire POIs",TASK_POI_MAP_REFRESH="Refresh POIs",TASK_POI_CONTEXT="POI context",TASK_POI_STARTUP="POI startup",POI_LINK_LABEL="POI: %s"},{__index=function(_,key)return key end})
local HolyStorm={db={global={installId="poi-test",poi={schemaVersion=1,personal={},guilds={},sessions={}}},profile={poi={}}},Data={GuildStore={},PlayerStore={},POIStore=nil},DataManager={},MapLinks={},Utils={},Policy={},Tasks={registered={},queued={}},Sync={domains={},published={},requested={},discovered={}},Events={handlers={},emitted={}},TwinkCore={},Logger={rows={}},Rules={fields={}},RichLinks={},capabilities={},Serializer={}}
local localSettings,settingDefinitions,registeredTabs={},{},{}
HolyStorm.Settings={
 definitions=settingDefinitions,
 Register=function(_,definition)settingDefinitions[definition.id]=copy(definition);return true end,
 GetDefinition=function(_,id)return settingDefinitions[id]end,
 Get=function(_,id)local definition=settingDefinitions[id];if not definition then return nil end;local value=localSettings[id];return value==nil and copy(definition.default)or copy(value)end,
 Set=function(_,id,value)if not settingDefinitions[id]then return false,"UNKNOWN_SETTING"end;localSettings[id]=copy(value);return true end,
 ImportLegacy=function(self,id,value)if value==nil or localSettings[id]~=nil then return false end;return self:Set(id,value)end,
}
HolyStorm.Options={
 RegisterSetting=function(_,definition)local ok=HolyStorm.Settings:Register(definition);return ok end,
 SetSetting=function(_,id,value)local definition=settingDefinitions[id];if definition and definition.setter then return definition.setter(value)end;return HolyStorm.Settings:Set(id,value)end,
 RegisterOptionsTab=function(_,id,options)registeredTabs[id]=options;return true end,
 CreateScopeSelector=function()return{type="select"}end,
 Open=function()return true end,
}
HolyStorm.Commands={RegisterOption=function()return true end}
function LibStub(name)if name=="AceAddon-3.0"then return{GetAddon=function()return HolyStorm end}elseif name=="AceLocale-3.0"then return{GetLocale=function()return locale end}end end
function HolyStorm.Utils.DeepCopy(value)return copy(value)end;function HolyStorm.Utils.Now()return clock end;function HolyStorm.Utils.Trim(value)return tostring(value):match("^%s*(.-)%s*$")end;function HolyStorm.Utils.TableCount(value)local n=0;for _ in pairs(value or{})do n=n+1 end;return n end;function HolyStorm.Utils.ApplyDefaults(target,defaults)target=type(target)=="table"and target or{};for key,value in pairs(defaults)do if target[key]==nil then target[key]=copy(value)end end;return target end;function HolyStorm.Utils.SafeCall(_,fn,...)local results={pcall(fn,...)};local ok=table.remove(results,1);return ok,(table.unpack or unpack)(results)end
function HolyStorm.Serializer:Serialize(value)return serialize(value)end
function HolyStorm.DataManager:RegisterSchema(definition)self.schemas=self.schemas or{};self.schemas[definition.id]=definition;return{ok=true}end
function HolyStorm.DataManager:_root(schema)local d=self.schemas[schema];return valueAt(HolyStorm.db[d.storage.scope],d.storage.path),d end
function HolyStorm.DataManager:Get(schema,key)local value,d=self:_root(schema);if key then local path=type(key)=="table"and key or{key};value=valueAt(value,path)end;return value and copy(value)or nil,{ok=true}end
function HolyStorm.DataManager:Commit(schema,key,value)local _,d=self:_root(schema);local path={};for _,part in ipairs(d.storage.path)do path[#path+1]=part end;if key~=nil then for _,part in ipairs(type(key)=="table"and key or{key})do path[#path+1]=part end end;setAt(HolyStorm.db[d.storage.scope],path,copy(value));return{ok=true}end
function HolyStorm.DataManager:Update(schema,key,mutator)
 local old,d=self:_root(schema);local draft=old and copy(old)or d.default();local decision,code,detail=mutator(draft);if decision==false then return{ok=false,errorCode=code,detail=detail}end;if type(decision)=="table"then draft=decision end
 if not d.validate(draft)then return{ok=false,errorCode="VALIDATION_FAILED"}end
 local path={};for _,part in ipairs(d.storage.path)do path[#path+1]=part end;setAt(HolyStorm.db[d.storage.scope],path,copy(draft));return{ok=true}
end
function HolyStorm.DataManager:RunMigrations(schema)
 local root,d=self:_root(schema);if not root then return{ok=false,errorCode="DATA_NOT_FOUND"}end
 local version=tonumber(root.schemaVersion);for _,migration in ipairs(d.migrations or{})do if migration.fromVersion==version then local replacement=migration.migrate(root,{});root=replacement or root;root.schemaVersion=migration.toVersion;version=migration.toVersion end end
 if not d.validate(root)then return{ok=false,errorCode="VALIDATION_FAILED"}end;local path=d.storage.path;setAt(HolyStorm.db[d.storage.scope],path,root);return{ok=true}
end
function HolyStorm.DataManager:GetOwnedRoot(schema,owner)local value,d=self:_root(schema);if not value then value=d.default();setAt(HolyStorm.db[d.storage.scope],d.storage.path,value)end;return value,{ok=true}end
function HolyStorm.Data.GuildStore:GetCurrent()return currentGuild end;function HolyStorm.Data.GuildStore:GetCurrentRosterSummary()return{roster=currentRoster}end;function HolyStorm.Data.PlayerStore:GetCharacterOwner(guid)return"account-"..tostring(guid)end;function HolyStorm.TwinkCore:GetAccountUUIDForCharacter(guid)return"account-"..tostring(guid)end
function HolyStorm.Policy:IsGuildModuleEnabled()return moduleEnabled end;function HolyStorm.Policy:Can(id)return permissions[id]~=false end
function HolyStorm.Tasks:RegisterTaskType(id,definition)self.registered[id]=definition end;function HolyStorm.Tasks:Queue(id,options)self.queued[#self.queued+1]={id=id,options=options};return true end;function HolyStorm.Tasks:GetLiveTasks()return{}end
function HolyStorm.Sync:RegisterDomain(id,definition)self.domains[id]=definition end;function HolyStorm.Sync:Publish(domain,id,reason)self.published[#self.published+1]={domain=domain,id=id,reason=reason};return true end;function HolyStorm.Sync:RequestObject(domain,id,options)self.requested[#self.requested+1]={domain=domain,id=id,options=options};return true end;function HolyStorm.Sync:Discover(domain,since,options)self.discovered[#self.discovered+1]={domain=domain,since=since,options=options};return true end
function HolyStorm.Events:Register(event,owner,handler)self.handlers[event..":"..owner]=handler end;function HolyStorm.Events:UnregisterOwner(owner)for key in pairs(self.handlers)do if key:match(":"..owner.."$")then self.handlers[key]=nil end end end;function HolyStorm.Events:Emit(event,...)self.emitted[#self.emitted+1]={event=event,args={...}}end
function HolyStorm.Logger:Write(level,module,category,message,context)self.rows[#self.rows+1]={level=level,module=module,category=category,message=message,context=context}end
function HolyStorm.Rules:RegisterField(owner,id,definition)if definition==nil then definition=id;id=owner end;self.fields[id]=definition;return true end
function HolyStorm.RichLinks:InsertChatLink(kind,id,label)self.last={kind=kind,id=id,label=label};return true end
function HolyStorm.MapLinks:RegisterPOIProvider(id,provider)self.poiProviders=self.poiProviders or{};self.poiProviders[id]=provider;return true end
function HolyStorm.MapLinks:UnregisterPOIProvider(id)if not self.poiProviders then return false end;self.poiProviders[id]=nil;return true end
function HolyStorm.MapLinks:ListPOIs()local out={};for _,provider in pairs(self.poiProviders or{})do if provider.list then for _,entry in ipairs(provider.list())do out[#out+1]={id=entry.poiID,name=entry.name,mapID=entry.mapID}end end end;return out end
function HolyStorm.MapLinks:SetTemporaryMarker(mapID,x,y,options)self.temporaryMarker={poiID="temporary-coordinate",mapID=mapID,x=x,y=y,temporary=true,localOnly=true,expiresAt=clock+(options.timeout or 0)};return true,self.temporaryMarker end;function HolyStorm.MapLinks:ClearTemporaryMarker()self.temporaryMarker=nil;return true end
function HolyStorm.MapLinks:OpenCoordinate()return true end
function HolyStorm:RegisterCapability(id,fn)self.capabilities[id]=fn end;function HolyStorm:CallCapability(id,...)self.called={id=id,args={...}};return true end
function UnitGUID(unit)if unit=="party1"or unit=="raid1"then return"Leader-B"end;return currentGuid end;function GetUnitName()return"Alpha-Realm"end;function UnitExists(unit)return unit=="party1"or unit=="raid1"end;function UnitIsGroupLeader(unit)return unit=="party1"or unit=="raid1"end
function IsInRaid()return groupMode=="RAID"end;function IsInGroup()return groupMode=="GROUP"or groupMode=="RAID"end;function GetNumGroupMembers()return groupMode=="RAID"and 1 or 0 end;function GetNumSubgroupMembers()return groupMode=="GROUP"and 1 or 0 end;function GetInstanceInfo()return nil,nil,nil,nil,nil,nil,nil,777,"Normal",0,20 end
C_Map={GetMapInfo=function(id)return tonumber(id)and tonumber(id)>0 and{id=id,name="Zone "..tostring(id)}or nil end,GetBestMapForUnit=function()return 84 end,GetPlayerMapPosition=function()return{GetXY=function()return.5,.6 end}end};UiMapPoint={CreateFromCoordinates=function(map,x,y)return{mapID=map,x=x,y=y}end};function OpenWorldMap(map)HolyStorm.openedMap=map end

-- The v1 root mirrors the persisted shape left by earlier POI versions.
HolyStorm.db.global.poi.personal.legacy={poiID="legacy",target="PERSONAL",mapID=84,x=.2,y=.3,name="Legacy",description="",category="note",customCategory="",color={r=1,g=.8,b=0,a=1},status="ACTIVE",revision=2,creatorGuid="Player-A",creatorName="Alpha",createdAt=900,updatedAt=950,modifiedBy="Player-A",source="sync",receivedFrom="relay",syncedAt=950}
assert(loadfile(featureRoot.."Persistence/POIStore.lua"))();assert(loadfile(root.."Core/Content/MapLinks.lua"))();assert(loadfile(featureRoot.."POIService.lua"))();assert(HolyStorm.POI:Initialize());local POI=HolyStorm.POI;local domain=HolyStorm.Sync.domains.poi
for _,id in ipairs({"poi.worldMapEnabled","poi.minimapEnabled","poi.worldMapSize","poi.minimapSize","poi.maxSynced","poi.categoryVisible.note","poi.targetVisible.PERSONAL"})do assert(settingDefinitions[id],"POI local setting was not registered centrally: "..id)end
assert(domain.catchUp==false and type(domain.canShare)=="function"and type(domain.getRecipients)=="function","POI catch-up is scoped by POI lifecycle and offers use a source-serving contract")
assert(HolyStorm.db.global.poi.schemaVersion==2 and POI:Get("legacy").schemaVersion==2 and POI:Get("legacy").scope=="PERSONAL"and POI:Get("legacy").provenance.kind=="MANUAL"and POI:Get("legacy").source==nil,"v1 persisted POIs migrate in place to schema v2 and discard transport source")
assert(POI:GetIcon({icon="removed-old-icon"}).id=="marker"and POI:Normalize({icon="removed-old-icon"}).icon=="marker","unknown saved icon falls back to the stable default marker")
assert(POI:GetSettings().schemaVersion==1 and POI:GetSettings().worldMapEnabled and HolyStorm.DataManager.schemas["poi-settings"],"settings migrate through the DataManager schema")
local startupDiscoveries=#HolyStorm.Sync.discovered;assert(POI:RunStartup()and#HolyStorm.Sync.discovered==startupDiscoveries,"POI startup performs cleanup without an automatic guild discovery");assert(POI:RunStartup()and#HolyStorm.Sync.discovered==startupDiscoveries,"later world-entry startup remains idle without repeating discovery")

local function draft(target,name)return{target=target or"PERSONAL",mapID=84,x=.25,y=.75,name=name or"Test POI",description="Rich [[coordinate:84,0.2,0.3|route]]",category="note",customCategory="",icon="marker",color={r=.2,g=.4,b=.6,a=1},status="ACTIVE"}end
local function metadata(entry)return{objectId=entry.poiID,owner=entry.modifiedBy,version=entry.revision,revisionID=entry.revisionID,previousRevisionID=entry.previousRevisionID,updatedAt=entry.updatedAt,target=entry.target,scope=entry.scope,sessionId=entry.sessionId,direct=true}end
local function importedVersion(base,revision,revisionID,actor,name)
 local entry=copy(base);entry.revision=revision;entry.revisionID=revisionID;entry.previousRevisionID=base.revisionID;entry.updatedAt=clock+revision;entry.modifiedBy=actor;entry.name=name or entry.name;return entry
end

local ok,personal=POI:Save(draft("PERSONAL","Personal"),0);assert(ok and personal.revision==1 and#HolyStorm.Sync.published==0,"personal POI persists without synchronization");local stable=personal.poiID;local oldRevision=personal.revisionID;personal.name="Renamed";ok,personal=POI:Save(personal,1);assert(ok and personal.poiID==stable and personal.revision==2 and personal.previousRevisionID==oldRevision,"stable ID and revision chain survive edits");assert(not POI:Save(personal,1),"stale editor revision is rejected")
permissions["poi-create-guild"]=false;assert(not POI:Save(draft("GUILD","Denied"),0),"guild create permission is enforced");assert(POI:Save(draft("PERSONAL","No permission needed"),0),"local POI creation needs no permission");permissions["poi-create-guild"]=nil
local guild;ok,guild=POI:Save(draft("GUILD","Guild"),0);assert(ok and guild.guildId=="realm:guild"and HolyStorm.Sync.published[#HolyStorm.Sync.published].id==guild.poiID,"guild POI is isolated and published")
currentRoster["Player-B"]={name="Beta"};assert(domain.canShare(metadata(guild),"Player-B","Beta-Realm","offer"),"a guild member can receive metadata for an exact stored POI revision");assert(not domain.canShare(metadata(guild),"Player-Outsider","Outsider-Realm","offer"),"a nonmember cannot be offered a guild POI");local personalCopy=copy(guild);personalCopy.target="PERSONAL";assert(not domain.canShare(metadata(personalCopy),"Player-B","Beta-Realm","offer"),"personal POIs never become a shareable source");POI:SetHidden(guild.poiID,true);assert(domain.canShare(metadata(guild),"Player-B","Beta-Realm","offer"),"recipient-local hiding does not make shared data unavailable from a valid source");POI:SetHidden(guild.poiID,false);moduleEnabled=false;local moduleShare,moduleReason=domain.canShare(metadata(guild),"Player-B","Beta-Realm","fetch");moduleEnabled=true;assert(not moduleShare and moduleReason=="MODULE_DISABLED","disabled POI module is exposed as a deterministic source unavailability reason");local absentShare,absentReason=domain.canShare({objectId="missing-served-copy",owner="Player-A",version=1,revisionID="missing-r1",updatedAt=clock,target="GUILD",scope="GUILD"},"Player-B","Beta-Realm","fetch");assert(not absentShare and absentReason=="NOT_FOUND","metadata without a local stored payload cannot become a POI source")
local mismatchedMetadata=metadata(guild);mismatchedMetadata.revisionID="stale-revision";assert(not domain.canShare(mismatchedMetadata,"Player-B","Beta-Realm","offer"),"a stale POI index entry cannot advertise a revision the source does not hold")
local guildOnlyOffers=domain.listMetadata(0,{scope="GUILD"});for _,offer in ipairs(guildOnlyOffers)do assert(offer.target=="GUILD"and not offer.sessionId,"guild discovery never includes transient session entries")end
currentGuid="Player-B";permissions["poi-edit-guild"]=false;assert(not POI:Save(guild,guild.revision),"guild edit permission is enforced at the action layer");permissions["poi-edit-guild"]=nil;permissions["poi-delete-guild"]=false;assert(not POI:Delete(guild.poiID,guild.revision),"guild delete permission is enforced at the action layer");permissions["poi-delete-guild"]=nil;currentGuid="Player-A"
POI:SetHidden(guild.poiID,true);assert(not POI:CanView(guild)and POI:CanView(guild,true),"local hiding is separate from shared data");local hiddenList=POI:GetVisible({mode="HIDDEN"});local hiddenFound=false;for _,entry in ipairs(hiddenList)do if entry.poiID==guild.poiID then hiddenFound=true end end;assert(hiddenFound,"hidden view can list locally hidden POIs")
local progressing=guild;for _=2,5 do local saved;ok,saved=POI:Save(progressing,progressing.revision);assert(ok);progressing=saved end;local base=copy(progressing);local officerA;ok,officerA=POI:Save(progressing,5);assert(ok and officerA.revision==6,"Officer A advances POI revision 5 to 6")
local forkA=importedVersion(base,6,"a-fork","Player-A","Officer A edit");local forkB=importedVersion(base,6,"z-fork","Player-B","Officer B edit");assert(domain.validate(forkB,metadata(forkB),forkB.poiID),"valid guild POI payload and metadata validate");assert(domain.authorize(forkB,metadata(forkB),"Player-B","OfficerB",forkB.poiID),"direct owner is authorized");assert(domain.import(forkB.poiID,forkB,metadata(forkB),"Player-B","OfficerB"),"same-revision sibling is resolved deterministically");assert(POI:Get(guild.poiID).revisionID=="z-fork"and POI:Get(guild.poiID).name=="Officer B edit","deterministic revision ID ordering converges on the same sibling")
local forkWithOriginChange=copy(importedVersion(forkB,3,"origin-fork","Player-B","changed origin"));forkWithOriginChange.provenance={kind="GUILD_PLAYER_POSITION",metadata={characterUUID="Someone-Else"}};local originMeta=metadata(forkWithOriginChange);assert(not domain.import(forkWithOriginChange.poiID,forkWithOriginChange,originMeta,"Player-B","OfficerB"),"relay edits cannot change creator or provenance")
local newer=importedVersion(POI:Get(guild.poiID),7,"rev-newer","Player-B","Remote update");local newerOk,newerReason=domain.import(guild.poiID,newer,metadata(newer),"Player-B","Remote");assert(newerOk,"newer remote POI imports: "..tostring(newerReason));assert(POI:GetSettings().hidden[guild.poiID]and POI:Get(guild.poiID).name=="Remote update","sync update preserves local hide state");assert(not domain.import(guild.poiID,forkB,metadata(forkB),"Player-B","OldClient"),"older sync revision cannot overwrite");local exported=domain.export(guild.poiID);assert(exported.receivedFrom==nil and exported.syncedAt==nil and exported.source==nil and exported.provenance.kind=="MANUAL","Sync export strips local receipt and transport fields while preserving provenance")
assert(domain.getChannel({target="GUILD"})=="GUILD"and domain.getChannel({target="GROUP"})=="PARTY"and domain.getChannel({target="RAID"})=="RAID","sync channels follow target scope");assert(domain.freshness=="revision-chain","Sync-v2 uses revision-chain freshness")

local requestDraft=POI:RequestCreate({source="GUILD_PLAYER_POSITION",mapID=84,x=.4,y=.5,target="GUILD",metadata={characterUUID="Player-B",characterName="Beta"}});assert(requestDraft and requestDraft.target=="PERSONAL"and requestDraft.provenance.kind=="GUILD_PLAYER_POSITION"and requestDraft.provenance.metadata.characterUUID=="Player-B"and POI:Get(requestDraft.poiID)==nil,"position capability prepares a personal-scope creation draft without saving")
assert(not POI:RequestCreate({mapID=84,x=2,y=.5}),"capability rejects invalid coordinates")

groupMode="GROUP";POI:HandleGroupContext();local group;ok,group=POI:Save(draft("GROUP","Group"),0);assert(ok and group.sessionId:match("^group%-"),"group POI receives a session ID");local groupSession=group.sessionId;local scopedGroupOffers=domain.listMetadata(0,{scope="GROUP",sessionId=groupSession});assert(#scopedGroupOffers==1 and scopedGroupOffers[1].objectId==group.poiID,"group discovery returns only the active session POI");assert(domain.canShare(metadata(group),"Leader-B","Leader-Realm","offer")and not domain.canShare(metadata(group),"Player-Outsider","Outsider-Realm","offer"),"group POI serving follows current group membership");groupMode=nil;POI:HandleGroupContext();assert(not POI:Get(group.poiID)and HolyStorm.Data.POIStore:GetRoot().sessions[groupSession]==nil,"leaving a group clears ephemeral POIs")
groupMode="RAID";POI:HandleGroupContext();local raid;ok,raid=POI:Save(draft("RAID","Raid"),0);assert(ok and raid.sessionId and HolyStorm.Sync.discovered[#HolyStorm.Sync.discovered].options.channel=="RAID","raid session triggers scoped resync");groupMode=nil;POI:HandleGroupContext();assert(not POI:Get(raid.poiID),"leaving a raid clears ephemeral POIs")

local expiring;ok,expiring=POI:Save(draft("PERSONAL","Short"),0);expiring.expiresAt=clock+5;HolyStorm.Data.POIStore:Put(expiring);POI:ScheduleExpiration();assert(HolyStorm.Tasks.queued[#HolyStorm.Tasks.queued].options.delay==5,"earliest expiration is scheduled exactly");clock=clock+6;POI:CleanupExpired();assert(not POI:Get(expiring.poiID),"expired personal POI is removed")

local invalid=copy(guild);invalid.poiID="remote-invalid";invalid.revision=1;invalid.revisionID="remote-rev-1";invalid.previousRevisionID=nil;invalid.target="GUILD";invalid.scope="GUILD";invalid.guildId="realm:guild";invalid.creatorGuid="Remote";invalid.modifiedBy="Remote";invalid.creatorName="Remote";invalid.creatorAccountUUID="account-Remote";invalid.createdAt=clock;invalid.updatedAt=clock;invalid.status="ACTIVE";invalid.deletedAt=nil;invalid.deletedBy=nil;invalid.provenance={kind="MANUAL",metadata={}};invalid.x=2
assert(not domain.validate(invalid,metadata(invalid),invalid.poiID),"invalid remote coordinates are rejected");invalid.x=.2;invalid.icon="unknown";assert(not domain.validate(invalid,metadata(invalid),invalid.poiID),"invalid remote icons are rejected without fallback persistence");invalid.icon="marker";invalid.category="future-category";assert(not domain.validate(invalid,metadata(invalid),invalid.poiID),"invalid remote categories are rejected")
POI:SetCategoryVisible("note",false);assert(not POI:CanView(personal),"category filter applies locally");POI:SetCategoryVisible("note",true);POI:SetSetting("worldMapSize",34);POI:SetSetting("minimapSize",16);assert(POI:GetSettings().worldMapSize==34 and POI:GetSettings().minimapSize==16,"world-map and minimap sizes persist independently")
local priorPublished=#HolyStorm.Sync.published;assert(POI:SetTemporaryMarker(84,.1,.2,{timeout=10}));assert(HolyStorm.MapLinks.temporaryMarker.localOnly and#HolyStorm.Sync.published==priorPublished,"temporary coordinate marker stays local");POI:ClearTemporaryMarker()
assert(HolyStorm.Rules.fields["poi.target"]and HolyStorm.Rules.fields["poi.mapID"],"POI fields are available to the central rule engine");local listed=HolyStorm.MapLinks:ListPOIs();local found=false;for _,item in ipairs(listed)do if item.id==personal.poiID then found=true end end;assert(found,"MapLinks provider exposes canonical poiID")
local dx,dy,mode=HolyStorm.MapLinks:TransformCoordinate(84,.25,.75,84);assert(dx==.25 and dy==.75 and mode=="DIRECT","same-map coordinates remain exact");assert(not HolyStorm.MapLinks:TransformCoordinate(84,.25,.75,85),"cross-map positions are omitted when official transformation APIs are unavailable")
function CreateVector2D(x,y)return{x=x,y=y,GetXY=function(self)return self.x,self.y end}end;C_Map.GetWorldPosFromMapPos=function(source,point)assert(source==84);return 1,CreateVector2D(point.x*100,point.y*100)end;C_Map.GetMapPosFromWorldPos=function(continent,world,target)assert(continent==1 and target==85);return 85,CreateVector2D(world.x/200,world.y/200)end;dx,dy,mode=HolyStorm.MapLinks:TransformCoordinate(84,.25,.75,85);assert(dx==.125 and dy==.375 and mode=="TRANSFORMED","child-to-parent coordinates use Blizzard's world-position conversion")
local missing=POI:Open("missing-id");assert(not missing and HolyStorm.Sync.requested[#HolyStorm.Sync.requested].id=="missing-id","missing POI links request their object on demand")

local tombstone;ok,tombstone=POI:Delete(guild.poiID,POI:Get(guild.poiID).revision);assert(ok and tombstone.status=="DELETED"and tombstone.revision==8,"global delete creates a newer tombstone");local stale=copy(newer);assert(not domain.import(guild.poiID,stale,metadata(stale),"Player-B","OldClient"),"an older active client cannot resurrect a guild tombstone");local sameRevisionActive=importedVersion(newer,tombstone.revision,"zz-active","Player-B","stale branch");assert(not domain.import(guild.poiID,sameRevisionActive,metadata(sameRevisionActive),"Player-B","OldClient"),"a same-version active sibling cannot beat a delete tombstone")
local deleteCase;ok,deleteCase=POI:Save(draft("GUILD","Rev 5 delete test"),0);assert(ok);local revision5=copy(deleteCase);revision5.revision=5;revision5.revisionID="client-a-rev-5";revision5.updatedAt=clock;HolyStorm.Data.POIStore:Put(revision5);local clientC=copy(revision5);local tombstone6;ok,tombstone6=POI:Delete(deleteCase.poiID,5);assert(ok and tombstone6.revision==6 and tombstone6.status=="DELETED","required revision 5 delete produces tombstone revision 6");assert(not domain.import(clientC.poiID,clientC,metadata(clientC),"Player-A","Client C"),"Client C's old revision 5 cannot resurrect Client B's revision 6 tombstone")
local tombBucket=HolyStorm.Data.POIStore:GetBucket("GUILD",nil,false,"realm:guild");tombBucket[guild.poiID].deletedAt=clock-POI.tombstoneRetention-1;POI:PruneTombstones("realm:guild");assert(tombBucket[guild.poiID]==nil,"tombstones older than the documented retention are pruned")

local maxBefore=POI:GetSettings().maxSynced;POI:SetSetting("maxSynced",50);local function makeRemote(id)
 local entry=copy(invalid);entry.poiID=id;entry.revision=1;entry.revisionID="remote-"..id;entry.previousRevisionID=nil;entry.name=id;entry.x=.25;entry.category="note";entry.customCategory="";entry.icon="marker";entry.status="ACTIVE";entry.deletedAt=nil;entry.deletedBy=nil;entry.modifiedBy="Remote";entry.creatorGuid="Remote";entry.updatedAt=clock
 return entry
end
for index=1,50 do local entry=makeRemote("bulk-"..index);local accepted,reason=domain.import(entry.poiID,entry,metadata(entry),"Remote","Remote");assert(accepted,"object-level sync accepts a valid POI within the configured limit: "..tostring(reason).." / "..tostring(POI:CountSynced()))end
local overflow=makeRemote("bulk-overflow");assert(not domain.import(overflow.poiID,overflow,metadata(overflow),"Remote","Remote"),"received POI limit rejects overflow without partial persistence")
local offers=domain.listMetadata(0,{scope="GUILD"});assert(#offers>=50 and offers[1].mapID==nil and offers[1].x==nil,"large guild discovery exports compact metadata without coordinates")
POI:SetSetting("maxSynced",maxBefore)
currentGuild={id="realm:other"};assert(POI:Get(guild.poiID)==nil,"guild data is isolated by guild identity");currentGuild={id="realm:guild"}

local poiModule
function HolyStorm:ApplyModuleMetadata()end
function HolyStorm:RegisterModule(metadata,factory)poiModule={};factory(poiModule);self.poiModule=poiModule;return poiModule end
function HolyStorm:RegisterUIExtension()return true end
local ui={content={}}
function ui:RegisterPage()return true end;function ui:AddNavigation()return true end;function ui:ShowPage()return true end
HolyStorm.UI=ui
function HolyStorm:GetModule(id)if id=="Options"then return self.Options elseif id=="UI"then return ui end end
local function widget()
 local frame={}
 return setmetatable(frame,{__index=function(target,key)if key=="CreateFontString"then return function()return widget()end end;return function()return target end end})
end
function CreateFrame()return widget()end
assert(loadfile(featureRoot.."POI.lua"))();poiModule.BuildList=function()return{}end;poiModule.BuildDetail=function()return{}end;poiModule.BuildEditor=function()return{}end;poiModule.BuildDiagnostics=function()return{}end
poiModule:InitializeUI();assert(registeredTabs.poi,"POI configuration is registered in the central options page")
assert(registeredTabs.poi.args.worldMapEnabled and registeredTabs.poi.args.categoryFilters and registeredTabs.poi.args.targetFilters and registeredTabs.poi.args.scopes,"central POI options retain map, category, target, and scope controls")
registeredTabs.poi.args.worldMapEnabled.set(nil,false);assert(registeredTabs.poi.args.worldMapEnabled.get()==false,"central POI option writes through the shared local settings registry")

local moduleFile=assert(io.open(featureRoot.."POI.lua","r"));local moduleSource=moduleFile:read("*a");moduleFile:close()
assert(moduleSource:find('InputScrollFrameTemplate',1,true)and not moduleSource:find('description:GetStringHeight()',1,true),"POI editor uses Blizzard's scrolling EditBox contract")
assert(not moduleSource:find('poi-view',1,true)and not moduleSource:find('Holy_Storm_Positions',1,true),"POI has no view permission or hard Positions dependency")
for _,permission in ipairs({"poi-create-guild","poi-edit-guild","poi-delete-guild"})do assert(moduleSource:find(permission,1,true),"module metadata declares "..permission)end
assert(moduleSource:find('leadership=true,officers=true,member=false',1,true),"guild administration defaults are explicit for each system group")
print("POI migration, permissions, CRUD, revision conflicts, tombstones, scopes, sync, capability and map-coordinate tests passed")
