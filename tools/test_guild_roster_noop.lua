local root=(arg[0]:gsub("tools[/\\]test_guild_roster_noop.lua$","")).."LIVE/Holy_Storm/"
local clock=1000
local function stable(value)
 if type(value)~="table"then return type(value)..":"..tostring(value)end
 local keys={};for key in pairs(value)do keys[#keys+1]=key end;table.sort(keys,function(a,b)return tostring(a)<tostring(b)end);local out={"{"};for _,key in ipairs(keys)do out[#out+1]=stable(key);out[#out+1]="=";out[#out+1]=stable(value[key]);out[#out+1]=";"end;out[#out+1]="}";return table.concat(out)
end
local events,identityVersion,identityValue={},0
local HolyStorm={db={global={data={guilds={}}}},Data={CharacterStore={}},DataManager={},State={values={}},Events={},Utils={Now=function()return clock end,TableCount=function(value)local count=0;for _ in pairs(value or{})do count=count+1 end;return count end},Serializer={Serialize=function(_,value)return stable(value)end}}
function LibStub()return{GetAddon=function()return HolyStorm end}end
function HolyStorm.DataManager:RegisterSchema()return true end
function HolyStorm.DataManager:SafeCopy(value)return value end
function HolyStorm.DataManager:Get(_,id)return HolyStorm.db.global.data.guilds[id]end
function HolyStorm.State:Set(key,value)self.values[key]=value end
function HolyStorm.Events:Emit(event,...)events[#events+1]={event=event,args={...}}end
function HolyStorm.Data.CharacterStore:Upsert(guid,changes)
 assert(changes.lastSeen==nil,"roster observation must not inject a volatile owner timestamp")
 local serialized=stable(changes);if serialized==identityValue then return false,"UNCHANGED"end;identityValue=serialized;identityVersion=identityVersion+1;HolyStorm.Events:Emit("HS_CHARACTER_UPDATED",guid);return true
end
function IsInGuild()return true end
function GetGuildInfo()return"Guild","Officer",1,"Realm"end
function GetNormalizedRealmName()return"Realm"end
function GetRealmName()return"Realm"end
function GuildControlGetNumRanks()return 1 end
function GuildControlGetRankName()return"Officer"end
function GetNumGuildMembers()return 1 end
function GetGuildRosterInfo()return"Alpha-Realm","Officer",1,80,"Paladin","City","","",true,0,"PALADIN",0,0,false,false,0,"Player-Local"end
function UnitGUID()return"Player-Local"end

assert(loadfile(root.."Persistence/GuildStore.lua"))();local Store=HolyStorm.Data.GuildStore;Store:Initialize();assert(Store:RefreshFromBlizzard());local record=Store:_GetLive("realm:guild");local firstUpdatedAt,firstEventCount=record.updatedAt,#events;assert(identityVersion==1 and record.version==1,"initial roster observation creates one identity and roster revision")
clock=1010;local changed,reason=Store:RefreshFromBlizzard();assert(not changed and reason=="UNCHANGED","identical roster reconciliation is a no-op");record=Store:_GetLive("realm:guild");assert(identityVersion==1 and record.version==1 and record.updatedAt==firstUpdatedAt and#events==firstEventCount,"no-op roster reconciliation changes no revision, timestamp, character event or roster event")
print("Guild roster no-op reconciliation tests passed")
