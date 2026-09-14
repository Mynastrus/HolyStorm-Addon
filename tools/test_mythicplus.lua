local root=(arg[0]:gsub("tools[/\\]test_mythicplus.lua$","")).."LIVE/Holy_Storm/"
local Module={};local registeredEvents={};local requested={affixes=0,maps=0,rewards=0}
local HolyStorm={Utils={Now=function()return 100 end},Data={CharacterStore={}},Snapshots={},Events={}}
function HolyStorm:RegisterOptionalModule(_,_,callback)callback(Module)end
function HolyStorm:ApplyModuleMetadata()end
function HolyStorm:RegisterCapability()end
function HolyStorm.Data.CharacterStore:GetBlock()end
function HolyStorm.Data.CharacterStore:SetMythicPlus()return true end
function HolyStorm.Snapshots:Queue()return true end
function HolyStorm.Snapshots:Cancel()end
function HolyStorm.Events:Register(event)registeredEvents[event]=true end
function HolyStorm.Events:UnregisterOwner()end
function LibStub(name)if name=="AceAddon-3.0"then return{GetAddon=function()return HolyStorm end}elseif name=="AceLocale-3.0"then return{GetLocale=function()return setmetatable({},{__index=function(_,key)return key end})end}end end
function UnitGUID()return"A"end
C_ChallengeMode={GetOverallDungeonScore=function()return 1128 end,GetMapTable=function()return{1,2}end,GetMapUIInfo=function(id)return"Dungeon "..id,100+id,1800,200+id,300+id,400+id end,GetAffixInfo=function(id)return"Affix "..id,"Description",500+id end}
C_MythicPlus={GetCurrentSeason=function()return 18 end,GetCurrentUIDisplaySeason=function()return 2 end,RequestCurrentAffixes=function()requested.affixes=requested.affixes+1 end,RequestMapInfo=function()requested.maps=requested.maps+1 end,RequestRewards=function()requested.rewards=requested.rewards+1 end,GetCurrentAffixes=function()return{{id=9}}end,GetOwnedKeystoneLevel=function()return 4 end,GetOwnedKeystoneChallengeMapID=function()return 1 end,GetOwnedKeystoneMapID=function()return 401 end,GetSeasonBestForMap=function()end,GetSeasonBestAffixScoreInfoForMap=function()end}
assert(loadfile(root.."Modules/MythicPlus/MythicPlus.lua"))()
local pending=Module:Collect();local valid,reason=Module:Validate(pending);assert(not valid and reason=="dungeon scores pending","overall rating without loaded map scores is retried instead of committed")
C_MythicPlus.GetSeasonBestForMap=function(id)if id==1 then return{level=6,dungeonScore=145,durationSec=1200}end;return nil,{level=5,dungeonScore=90,durationSec=1900}end
C_MythicPlus.GetSeasonBestAffixScoreInfoForMap=function(id)if id==1 then return{{name="Seasonal",score=145,level=6,durationSec=1200,overTime=false}},155 end end
local snapshot=Module:Collect();assert(Module:Validate(snapshot));assert(snapshot.snapshotVersion==3 and snapshot.scoreDataReady,"loaded per-dungeon scores produce a complete v3 snapshot");assert(snapshot.dungeons[1].bestRun.level==6 and snapshot.dungeons[1].bestRun.score==145 and not snapshot.dungeons[1].bestRun.overTime,"in-time best run is normalized");assert(snapshot.dungeons[1].score==155,"the API's second overall-score return value is retained");assert(snapshot.dungeons[2].bestRun.level==5 and snapshot.dungeons[2].bestRun.overTime and snapshot.dungeons[2].score==90,"the API's second overtime return value is retained and normalized");assert(requested.affixes>0 and requested.maps>0 and requested.rewards>0,"all asynchronous Mythic+ data requests are issued")
Module:OnEnable();assert(registeredEvents.CHALLENGE_MODE_MAPS_UPDATE,"map-data completion event triggers a fresh snapshot")
print("Mythic+ asynchronous loading and best-run parsing tests passed")
