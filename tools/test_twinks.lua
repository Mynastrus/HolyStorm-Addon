-- Offline contracts for TwinkCore scenarios A-J.
local root=(arg[0]:gsub("tools[/\\]test_twinks.lua$","")).."LIVE/Holy_Storm/"
local clock,currentGuid=1000,"Maristi"
function time()return clock end;function GetTime()return clock end;function UnitGUID()return currentGuid end
function IsInGuild()return true end;function GetGuildInfo()return"Guild",nil,0 end
local HolyStorm={db={global={localPlayerId="account-local",localAccountUUID="account-local",installId="install",data={characters={},players={},characterOwners={}}}},Data={},State={Set=function()end}}
function HolyStorm:GetAddon()return self end
local locale=setmetatable({}, {__index=function(_,key)return key end})
function LibStub(name)if name=="AceLocale-3.0"then return{GetLocale=function()return locale end}end;return HolyStorm end
assert(loadfile(root.."Core/Utils/Utils.lua"))();assert(loadfile(root.."Core/Serialization/Serializer.lua"))()
HolyStorm.Logger={Write=function()end};HolyStorm.Events={listeners={},emitted={}}
function HolyStorm.Events:Register(event,owner,fn)self.listeners[event]=self.listeners[event]or{};self.listeners[event][owner]=fn end
function HolyStorm.Events:Emit(event,...)self.emitted[#self.emitted+1]=event;for _,fn in pairs(self.listeners[event]or{})do fn(event,...)end end
HS_Player_DB={characters={},players={},characterOwners={},sync={foreignWatermark=0,foreignWatermarks={}}}
assert(loadfile(root.."Persistence/PlayerDataStore.lua"))();HolyStorm.PlayerData:Initialize()
local characterData={
 Maristi={guid="Maristi",name="Maristi",realm="Realm",classFile="PALADIN",level=80},
 Marithiel={guid="Marithiel",name="Marithiel",realm="Realm",classFile="PRIEST",level=80},
 Daniel={guid="Daniel",name="Daniel",realm="Realm",classFile="WARRIOR",level=80},
 Klaus={guid="Klaus",name="Klaus",realm="Realm",classFile="MAGE",level=80},
}
HolyStorm.Data.CharacterStore={Get=function(_,guid)return characterData[guid]end}
local guild={id="guild-1",roster={}}
local guildSummaryReads=0
HolyStorm.Data.GuildStore={GetCurrent=function()return guild end,GetCurrentRosterSummary=function()guildSummaryReads=guildSummaryReads+1;local summary={id=guild.id,roster={}};for guid,member in pairs(guild.roster)do summary.roster[guid]={rankIndex=member.rankIndex,classFile=member.classFile,level=member.level}end;return summary end,ResolveSenderGuid=function(_,sender)return sender end}
HolyStorm.Tasks={types={},queued={}}
function HolyStorm.Tasks:RegisterTaskType(id,d)self.types[id]=d;return true end
function HolyStorm.Tasks:Queue(id,o)self.queued[#self.queued+1]={id=id,options=o};return"task"end
function HolyStorm.Tasks:ScheduleRecurring()return true end
HolyStorm.Comms={available=true,Send=function()return true end};HolyStorm.Policy={Can=function()return true end}
assert(loadfile(root.."Sync/SyncManager.lua"))();HolyStorm.Sync:Initialize()
assert(loadfile(root.."Modules/Characters/TwinkCore.lua"))();HolyStorm.TwinkCore:Initialize()
local core=HolyStorm.TwinkCore;local accountUUID=core:GetLocalAccountUUID()

-- A: a later login learns a second character without changing AccountUUID.
currentGuid="Marithiel";assert(core:ConfirmLocalCharacter("Marithiel"));local chars=core:GetCharactersForAccount(accountUUID);assert(chars.Maristi and chars.Marithiel);assert(core:GetAccountUUIDForCharacter("Marithiel")==accountUUID)
HolyStorm.PlayerData:Initialize();assert(type(core:GetCharactersForAccount(accountUUID).Maristi)=="table" and core:IsOwnerConfirmed("Maristi"))
-- Add the remaining owner-known characters used by B-E.
currentGuid="Daniel";assert(core:ConfirmLocalCharacter("Daniel"));currentGuid="Klaus";assert(core:ConfirmLocalCharacter("Klaus"));currentGuid="Maristi"
-- B: manual main changes while account identity remains stable.
assert(core:SetAccountMain("Maristi"));local stable=core:GetLocalAccountUUID();assert(core:SetAccountMain("Marithiel"));assert(core:GetLocalAccountUUID()==stable and core:GetAccount(stable).mainCharacterUUID=="Marithiel")
assert(core:SetAccountMain("Maristi"))
-- C: out-of-guild account main produces deterministic highest-rank shadow main.
guild.roster={Marithiel={rankIndex=4},Daniel={rankIndex=2}};local guildMain,shadow=core:GetGuildMain(accountUUID,guild);assert(guildMain=="Daniel" and shadow==true);assert(core:GetAccountMain(accountUUID)=="Maristi")
-- D: account main entering the guild immediately becomes guild main.
guild.roster.Maristi={rankIndex=9};guildMain,shadow=core:GetGuildMain(accountUUID,guild);assert(guildMain=="Maristi" and shadow==false)
-- E: guild-only keeps the main reference visible, hides other outsiders, but exports all.
guild.roster.Maristi=nil;assert(core:SetVisibility(core.visibility.GUILD_ONLY));local visible=core:GetVisibleCharactersForViewer(accountUUID,guild);local shown={};for _,entry in ipairs(visible)do shown[entry.characterUUID]=true end;assert(shown.Maristi and shown.Marithiel and shown.Daniel and not shown.Klaus);local exported=core:ExportOwnerSnapshot(accountUUID);assert(exported.characters.Maristi and exported.characters.Marithiel and exported.characters.Daniel and exported.characters.Klaus)

-- K: one compact guild read serves a large recalculation without a full GuildStore record.
for index=1,250 do local guid="Roster-"..index;guild.roster[guid]={rankIndex=index};core.accounts["account-roster-"..index]={accountUUID="account-roster-"..index,characters={[guid]={characterUUID=guid,fullName=guid,normalizedFullName=string.lower(guid),relationship={source=core.sources.ADMIN}}},visibility=core.visibility.ALL,ownerVersion=0,version=0} end
local rosterRankBefore=guild.roster["Roster-250"].rankIndex;guildSummaryReads=0;local originalGetCurrent=HolyStorm.Data.GuildStore.GetCurrent;HolyStorm.Data.GuildStore.GetCurrent=function()error("full GuildStore read is forbidden in TwinkCore recalculation")end;assert(core:RecalculateGuildMains());HolyStorm.Data.GuildStore.GetCurrent=originalGetCurrent;assert(guildSummaryReads==1,"recalculation performs exactly one compact guild read");assert(core:GetGuildMain("account-roster-250",guild)=="Roster-250","recalculation preserves correct guild main selection");assert(guild.roster["Roster-250"].rankIndex==rosterRankBefore,"recalculation does not mutate the persistent roster")

-- F: an owner snapshot that mentions only its owner does not delete unrelated admin facts.
local adminAccount,ma,mi,da="account-maristi-admin","Maristi-Admin","Marithiel-Admin","Daniel-Admin"
characterData[ma]={guid=ma,name="Maristi",realm="Other"};characterData[mi]={guid=mi,name="Marithiel",realm="Other"};characterData[da]={guid=da,name="Daniel",realm="Other"}
assert(core:AssignCharacterAdministrative(adminAccount,mi));assert(core:AssignCharacterAdministrative(adminAccount,da))
local function ownerEntry(guid)local e=core:CompactIdentity(guid,core.sources.OWNER);e.relationship.confirmedAt=clock;return e end
local payloadF={accountUUID=adminAccount,characters={[ma]=ownerEntry(ma)},visibility=core.visibility.ALL,ownerVersion=1,updatedAt=clock,issuedBy=ma}
assert(core:MergeOwnerSnapshot(adminAccount,payloadF,{owner=ma,version=1,updatedAt=clock}));assert(core:GetRelationshipSource(mi)==core.sources.ADMIN and core:GetRelationshipSource(da)==core.sources.ADMIN)
-- G: explicit owner evidence upgrades only Marithiel; Daniel remains administrative.
clock=1010;local payloadG={accountUUID=adminAccount,characters={[ma]=ownerEntry(ma),[mi]=ownerEntry(mi)},visibility=core.visibility.ALL,ownerVersion=2,updatedAt=clock,issuedBy=ma}
assert(core:MergeOwnerSnapshot(adminAccount,payloadG,{owner=ma,version=2,updatedAt=clock}));assert(core:IsOwnerConfirmed(mi) and core:GetRelationshipSource(da)==core.sources.ADMIN)
-- H: another owner's explicit Daniel evidence moves precisely Daniel.
local klausAccount,ka="account-klaus","Klaus-Admin";characterData[ka]={guid=ka,name="Klaus",realm="Other"};clock=1020
local payloadH={accountUUID=klausAccount,characters={[ka]=ownerEntry(ka),[da]=ownerEntry(da)},visibility=core.visibility.ALL,ownerVersion=2,updatedAt=clock,issuedBy=ka}
assert(core:MergeOwnerSnapshot(klausAccount,payloadH,{owner=ka,version=2,updatedAt=clock}));assert(core:GetAccountUUIDForCharacter(da)==klausAccount and core:IsOwnerConfirmed(da));assert(not core:GetCharactersForAccount(adminAccount)[da])
-- I: administrative removal cannot remove owner-confirmed evidence and returns localized text.
local removed,reason,message=core:RemoveAdministrativeAssignment(klausAccount,da);assert(not removed and reason=="OWNER_CONFIRMED" and message=="TWINK_ERROR_OWNER_CONFIRMED")
-- J: the central metadata comparator rejects an older owner version before import.
local stale={accountUUID=klausAccount,characters={[ka]=ownerEntry(ka),[da]=ownerEntry(da)},visibility=core.visibility.ALL,ownerVersion=1,updatedAt=900,issuedBy=ka}
assert(not HolyStorm.Sync:OnPayload("twinks",{objectId=klausAccount,metadata={objectId=klausAccount,owner=ka,version=1,updatedAt=900},payload=stale},ka));assert(core:GetAccount(klausAccount).ownerVersion==2)

-- K2: relationship confirmation is idempotent across roster availability, guild identity, rank and level changes.
local originalPublish=HolyStorm.Sync.Publish;local publishCount=0;HolyStorm.Sync.Publish=function(self,domain,id,reason)if domain=="twinks"then publishCount=publishCount+1 end;return originalPublish(self,domain,id,reason)end
local function countEvent(eventName)local count=0;for _,event in ipairs(HolyStorm.Events.emitted)do if event==eventName then count=count+1 end end;return count end
local repeatGuid="Repeat-Character";characterData[repeatGuid]={guid=repeatGuid,name="Repeat",realm="Realm",classFile="PALADIN",level=80,guild="Character Guild"};currentGuid=repeatGuid;guild.id="Internal Guild ID";guild.roster[repeatGuid]=nil
local repeatAccount=core:GetAccount(accountUUID);local repeatVersion=repeatAccount.ownerVersion;local repeatEvents=countEvent("HS_CHARACTER_RELATIONSHIP_UPDATED");local repeatPublishes=publishCount
assert(core:ConfirmLocalCharacter(repeatGuid));local firstVersion=core:GetAccount(accountUUID).ownerVersion;assert(firstVersion==repeatVersion+1,"new owner-confirmed character must create one relationship revision")
local _,sameChanged=core:ConfirmLocalCharacter(repeatGuid);assert(sameChanged==false and core:GetAccount(accountUUID).ownerVersion==firstVersion,"identical confirmation changed the owner relationship")
guild.roster[repeatGuid]={rankIndex=4,classFile="PALADIN"};assert(select(2,core:ConfirmLocalCharacter(repeatGuid))==false,"roster availability changed the relationship")
guild.roster[repeatGuid].rankIndex=1;assert(select(2,core:ConfirmLocalCharacter(repeatGuid))==false,"guild rank changed the relationship")
characterData[repeatGuid].level=81;assert(select(2,core:ConfirmLocalCharacter(repeatGuid))==false,"level metadata changed the relationship")
characterData[repeatGuid].guild="Another Character Guild";guild.id="Different Internal Guild ID";for _=1,100 do assert(select(2,core:ConfirmLocalCharacter(repeatGuid))==false)end
assert(countEvent("HS_CHARACTER_RELATIONSHIP_UPDATED")==repeatEvents+1 and publishCount==repeatPublishes+1,"100 identical confirmations caused relationship events or publishes")
local switchGuid="Switched-Character";characterData[switchGuid]={guid=switchGuid,name="Switched",realm="Realm",classFile="MAGE",level=80};local otherAccount="account-previous-owner";core.accounts[otherAccount]={accountUUID=otherAccount,characters={[switchGuid]=core:CompactIdentity(switchGuid,core.sources.OWNER,{id="old",roster={}})},visibility=core.visibility.ALL,ownerVersion=1,version=1};core.relationships[switchGuid]=otherAccount;currentGuid=switchGuid;local switchVersion=core:GetAccount(accountUUID).ownerVersion;local _,switchChanged=core:ConfirmLocalCharacter(switchGuid);assert(switchChanged and core.relationships[switchGuid]==accountUUID and not core.accounts[otherAccount].characters[switchGuid],"real character-to-account switch was not revised")
HolyStorm.Sync.Publish=originalPublish
print("TwinkCore scenarios A-J passed")
