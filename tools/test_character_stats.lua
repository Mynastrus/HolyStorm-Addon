-- Character Stats API semantics, baseline protection and transient update contracts.
local root=(arg[0]:gsub("tools[/\\]test_character_stats.lua$","")).."LIVE/Holy_Storm_Characters/"
local now=1000;local runtime=10;local callbacks={};local emitted={};local listeners={};local writes={};local auraState={}
unpack=unpack or table.unpack
function GetTime()return runtime end;function UnitGUID()return"Player-Local"end
function issecretvalue(value)return value=="SECRET"end
local function statValue(index)
 local values={
  [1]={100,110,5,0},[2]={50,50,0,0},[3]={300,300,0,0},[4]={200,200,0,0}
 };return unpack(values[index])
end
function UnitStat(_,index)return statValue(index)end
function UnitArmor()return 0,2390,2390,0 end
CR_CRIT_MELEE=1;CR_CRIT_RANGED=2;CR_CRIT_SPELL=3;CR_HASTE_MELEE=4;CR_MASTERY=5;CR_VERSATILITY_DAMAGE_DONE=6;CR_LIFESTEAL=7;CR_AVOIDANCE=8;CR_SPEED=9
MAX_SPELL_SCHOOLS=7
function GetSpellCritChance()return 25 end
function GetRangedCritChance()return 23 end;function GetCritChance()return 22 end
function GetHaste()return 20 end;function GetMasteryEffect()return 22,1.15 end
function GetCombatRating(rating)if rating==CR_CRIT_SPELL then return 936 elseif rating==CR_HASTE_MELEE then return 813 elseif rating==CR_MASTERY then return 690 elseif rating==CR_VERSATILITY_DAMAGE_DONE then return 148 elseif rating==CR_LIFESTEAL then return 0 else return 0 end end
function GetCombatRatingBonus(rating)if rating==CR_CRIT_SPELL then return 20.3 elseif rating==CR_HASTE_MELEE then return 18.5 elseif rating==CR_MASTERY then return 15 elseif rating==CR_VERSATILITY_DAMAGE_DONE then return 2.7 else return 0 end end
function GetVersatilityBonus()return .3 end;function GetLifesteal()return 0 end;function GetAvoidance()return 5 end;function GetSpeed()return 0 end
function GetSpecialization()return 1 end;function GetSpecializationInfo()return 102, "Balance", nil, 55, "DAMAGER" end
C_UnitAuras={GetAuraDataByIndex=function(_,index,filter)return auraState[filter]and auraState[filter][index]or nil end}
C_Timer={After=function(delay,callback)callbacks[#callbacks+1]={delay=delay,callback=callback}end}
local HolyStorm={Events={},Utils={Now=function()return now end},PlayerData={},Data={CharacterStore={}},Snapshots={},CharacterScans={},Serializer={Serialize=function(_,value)
 local function encode(v)if type(v)~="table"then return tostring(v)end;local keys={};for k in pairs(v)do keys[#keys+1]=k end;table.sort(keys,function(a,b)return tostring(a)<tostring(b)end);local out={};for _,k in ipairs(keys)do out[#out+1]=tostring(k)..":"..encode(v[k])end;return"{"..table.concat(out,",").."}"end;return encode(value)
end}}
HolyStorm.UI={visible=false,GetVisiblePage=function(self)return self.visible and"character"or nil end};HolyStorm.CharacterUI={activeTab="stats",context={characterUUID="Player-Local"}}
function HolyStorm.Data.CharacterStore:GetBlock(guid,block)return HolyStorm.PlayerData:GetBlock(guid,block)end
function HolyStorm:GetAddon()return self end
function HolyStorm.Events:Register(event,owner,fn)listeners[event]=listeners[event]or{};listeners[event][owner]=fn end
function HolyStorm.Events:UnregisterOwner(owner)for _,byOwner in pairs(listeners)do byOwner[owner]=nil end end
function HolyStorm.Events:Emit(event,...)
 emitted[#emitted+1]={event=event,args={...}};for _,fn in pairs(listeners[event]or{})do fn(event,...)end
end
function HolyStorm.PlayerData:GetMetadata()return self.metadata end
function HolyStorm.PlayerData:GetBlock()return self.snapshot end
function HolyStorm.PlayerData:WriteOwnedBlock(guid,block,snapshot,source)writes[#writes+1]={guid=guid,block=block,snapshot=snapshot,source=source};self.snapshot=snapshot;self.metadata={snapshotVersion=snapshot.snapshotVersion};return true,self.metadata end
function HolyStorm.CharacterScans:RegisterProvider(_,definition)self.provider=definition;return true end
function HolyStorm.CharacterScans:Request(block,reason,sync,options)self.requests=self.requests or{};self.requests[#self.requests+1]={block=block,reason=reason,sync=sync,options=options};return true end
function HolyStorm.Snapshots:Queue(_,scanner,validator,commit,options)self.scanner=scanner;self.validator=validator;self.commit=commit;self.options=options;return true,"workflow-stats"end
function HolyStorm:RegisterModule(_,callback)callback({})end
function HolyStorm:RegisterCapability()return true end
local locale=setmetatable({},{__index=function(_,key)return key end})
function LibStub(name)if name=="AceLocale-3.0"then return{GetLocale=function()return locale end}end;return HolyStorm end
local Stats
HolyStorm.RegisterModule=function(_,_,callback)Stats={};callback(Stats)end
assert(loadfile(root.."Stats.lua"))()
Stats:OnInitialize();Stats:OnEnable();assert(#callbacks==0,"Stats enable and missing baseline do not schedule login work");callbacks={};Stats.baselineTimer=false;Stats.liveTimer=false

local clean=Stats:Collect();assert(clean.snapshotVersion==2 and clean.schemaVersion==2 and clean.capture.eligible)
assert(clean.primary.strength.baseline==95 and clean.primary.strength.baseline~=110,"UnitStat positive buffs are excluded from the stored primary baseline")
assert(clean.armor.baseline==2390,"effective equipped armor becomes the character baseline instead of UnitArmor's zero raw base")
assert(clean.secondary.criticalStrike.rating==936 and clean.secondary.criticalStrike.baseline==25,"Blizzard-selected spell crit percentage and its matching rating are both kept")
assert(clean.secondary.haste.baseline==20 and clean.secondary.mastery.baseline==22 and clean.secondary.mastery.coefficient==1.15,"effective haste and spec-scaled mastery are used instead of rating bonus")
assert(clean.secondary.versatility.baseline==3 and clean.secondary.leech.baseline==0 and clean.secondary.speed.baseline==0,"Versatility includes the separate bonus, while Leech and Speed preserve confirmed zero values")
assert(Stats:Validate(clean));assert(Stats:Commit(clean));assert(#writes==1 and writes[1].source=="blizzard")
local malformed={snapshotVersion=2,schemaVersion=2,primary={},armor=clean.armor,secondary=clean.secondary,capture=clean.capture};for key,value in pairs(clean.primary)do malformed.primary[key]=value end;malformed.primary.strength={baseline="95"};assert(not Stats:Validate(malformed),"snapshot validation rejects malformed numeric fields")

-- Timed auras retain safe primary baselines while excluding transient fields.
auraState.HELPFUL={{duration=30,expirationTime=runtime+30}}
now=1010
local buffed=Stats:Collect();assert(buffed.capture.eligible and buffed.capture.partial and buffed.capture.reason=="TIMED_AURA_ACTIVE")
assert(buffed.primary.strength.baseline==95 and buffed.armor.baseline==nil,"primary stats stay available while potentially transient armor is omitted")
for _,stat in pairs(buffed.secondary)do assert(stat.rating==nil and stat.baseline==nil and stat.coefficient==nil,"all potentially buff-modified secondary values are omitted")end
local valid,reason=Stats:Validate(buffed);assert(valid,reason)
assert(Stats:Commit(buffed)and#writes==2 and Stats.baselineDirty,"safe partial primary baseline commits during a temporary aura and remains dirty for a later clean capture")

-- Effective secondary values remain transient and unknown/unavailable stays nil.
function GetMasteryEffect()return"SECRET",1.15 end
function GetSpeed()return"SECRET"end
function GetSpecializationInfo()return 102,"SECRET",nil,55,"SECRET"end
local live=Stats:CollectLive();assert(live.secondary.mastery.effective==nil and live.secondary.speed.effective==nil and live.spec.name==nil and live.spec.role==nil,"secret and unavailable API values remain unknown")
auraState.HELPFUL={}
local optionalMissing=Stats:Collect();assert(optionalMissing.capture.partial==false and optionalMissing.secondary.mastery.baseline==nil and optionalMissing.secondary.speed.baseline==nil and Stats:Validate(optionalMissing),"missing optional effective values do not reject otherwise usable persistent stats")
function GetMasteryEffect()return 22,1.15 end;function GetSpeed()return 0 end
function GetSpecializationInfo()return 102,"Balance",nil,55,"DAMAGER"end
auraState.HELPFUL={{duration=30,expirationTime=runtime+30}}

-- Aura bursts coalesce only while the Stats view is visible.
Stats.baselineDirty=false;callbacks={};listeners.UNIT_AURA["character-stats-live"]("UNIT_AURA","player");assert(#callbacks==0,"hidden Stats view does not recompute the live overlay")
HolyStorm.UI.visible=true;listeners.UNIT_AURA["character-stats-live"]("UNIT_AURA","player");listeners.UNIT_AURA["character-stats-live"]("UNIT_AURA","player");assert(#callbacks==1,"visible UNIT_AURA bursts are debounced")
callbacks[1].callback();callbacks={};assert(#writes==2,"live aura refresh does not write PlayerData")
local last;for _,entry in ipairs(emitted)do if entry.event=="HS_STATS_LIVE_UPDATED"then last=entry end end
assert(last and last.args[1]=="Player-Local"and last.args[2].secondary.criticalStrike.effective==25,"the live layer publishes effective values through the internal event bus")

-- A config change during an aura dirties the baseline; aura removal schedules one later baseline request.
Stats.baselineDirty=false;auraState.HELPFUL={{duration=30,expirationTime=runtime+30}};listeners.PLAYER_EQUIPMENT_CHANGED["character-stats"]("PLAYER_EQUIPMENT_CHANGED",1)
assert(Stats.baselineDirty and #callbacks==2,"durable configuration changes debounce live and baseline requests")
callbacks[1].callback();callbacks[2].callback();assert(#writes==2,"an active timed aura never adds transient values to the baseline")
auraState.HELPFUL={};callbacks={};listeners.UNIT_AURA["character-stats-live"]("UNIT_AURA","player");assert(#callbacks==1);callbacks[1].callback();assert(#callbacks==2,"clean aura removal schedules a baseline refresh after the coalesced live read");callbacks[2].callback()
assert(HolyStorm.CharacterScans.requests and #HolyStorm.CharacterScans.requests>0,"baseline refresh resumes after the temporary aura ends through CharacterScanManager")
print("Character Stats Retail API, baseline, live overlay and debounce tests passed")
