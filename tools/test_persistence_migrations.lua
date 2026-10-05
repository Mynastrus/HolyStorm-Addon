local root=(arg[0]:gsub("tools[/\\]test_persistence_migrations.lua$","")).."LIVE/Holy_Storm/"
local logs={};local now=1000
local function copy(value,seen)if type(value)~="table"then return value end;seen=seen or{};if seen[value]then return seen[value]end;local out={};seen[value]=out;for key,child in pairs(value)do out[copy(key,seen)]=copy(child,seen)end;return out end
local HolyStorm;HolyStorm={Data={},Utils={DeepCopy=copy,Now=function()return now end,ApplyDefaults=function(value,defaults)value=type(value)=="table"and value or{};for key,child in pairs(defaults or{})do if value[key]==nil then value[key]=copy(child)elseif type(value[key])=="table"and type(child)=="table"then HolyStorm.Utils.ApplyDefaults(value[key],child)end end;return value end},Logger={Write=function(_,level,source,category,message,context)logs[#logs+1]={level=level,source=source,category=category,message=message,context=context}end},Events={Emit=function()end}}
function LibStub(name)if name=="AceLocale-3.0"then return{GetLocale=function()return setmetatable({},{__index=function(_,key)return key end})end}end;return{GetAddon=function()return HolyStorm end}end
assert(loadfile(root.."Persistence/Schema.lua"))();assert(loadfile(root.."Persistence/Migrations.lua"))()

HolyStormDB={global={schemaVersion=12,data={guilds={keep={name="Guild"}},characters={Legacy={raid={snapshotVersion=3,lifetime={bosses={one={kills=7}}}}}},players={account={characters={Legacy=true}}},characterOwners={Legacy="account"}},playerProfiles={profile={roles={officer=true}}},characterOwners={Other="profile"},twinks={Twink={identity={name="Alt"}}}}}
HS_Player_DB={schemaVersion=2,characters={Current={identity={name="Current"}}},players={canonical={characters={Current=true}}},characterOwners={Current="canonical"}}
local global=HolyStormDB.global
assert(HolyStorm.Data.Migrations:Run(global,12));assert(global.schemaVersion==14 and HS_Player_DB.schemaVersion==2,"database schema advances independently to v14")
assert(global.localSettings and global.localSettings.schemaVersion==1 and global.localSettings.character and global.localSettings.account and global.localSettings.guild and global.localSettings.allGuilds,"local scope buckets are created without replacing existing saved data")
assert(HS_Player_DB.characters.Legacy.raid.lifetime.bosses.one.kills==7 and HS_Player_DB.characters.Twink.identity.name=="Alt","character and raid history are preserved while aliases consolidate")
assert(HS_Player_DB.players.account.characters.Legacy and HS_Player_DB.players.profile.roles.officer and HS_Player_DB.characterOwners.Other=="profile","account and owner mappings are preserved")
assert(global.data.guilds.keep.name=="Guild"and global.data.characters==nil and global.data.players==nil and global.data.characterOwners==nil,"guild data remains while obsolete character aliases are removed")
assert(global.playerProfiles==nil and global.characterOwners==nil and global.twinks==nil,"one-time compatibility roots are cleaned after migration")
local migrationLog=logs[#logs];assert(migrationLog.context.migrationId=="database.12-to-13.player-alias-cleanup"and migrationLog.context.cleanup==true,"migration logs identify domain, transition and cleanup")
assert(HolyStorm.Data.Migrations:Run(global,14));assert(global.data.characters==nil and HS_Player_DB.characters.Legacy.raid.lifetime.bosses.one.kills==7,"repeat migration is idempotent and does not recreate aliases")

local future={schemaVersion=15,data={retained=true}};local before=copy(future);local ok,reason=HolyStorm.Data.Migrations:Run(future,15);assert(not ok and reason=="SCHEMA_VERSION_NEWER"and future.schemaVersion==before.schemaVersion and future.data.retained,"future schemas remain untouched")
local malformed={schemaVersion=12,data={characters={broken="not a record"}}};local malformedBefore=copy(malformed);local accepted=HolyStorm.Data.Migrations:Run(malformed,12);assert(not accepted and malformed.schemaVersion==malformedBefore.schemaVersion and malformed.data.characters.broken=="not a record","malformed legacy records are retained for recovery")

HolyStorm.db={global=global};HolyStorm.State={};HolyStorm.Utils.TableCount=function(value)local n=0;for _ in pairs(value or{})do n=n+1 end;return n end
assert(loadfile(root.."Persistence/PlayerDataStore.lua"))();HolyStorm.PlayerData:Initialize()
assert(global.data.characters==nil and global.data.players==nil and HS_Player_DB.characters.Legacy.raid.lifetime.bosses.one.kills==7,"current PlayerData startup does not restore legacy mirrors")
local futurePlayerDb={schemaVersion=99,opaque={preserve=true}};HS_Player_DB=futurePlayerDb;HolyStorm.PlayerData.futureSchema=false;assert(HolyStorm.PlayerData:Initialize());assert(HS_Player_DB==futurePlayerDb and futurePlayerDb.schemaVersion==99 and futurePlayerDb.opaque.preserve and HolyStorm.PlayerData.futureSchema,"newer player schemas are left untouched and opened read-only")
print("Central persistence migration cleanup, preservation, idempotency and future-schema tests passed")
