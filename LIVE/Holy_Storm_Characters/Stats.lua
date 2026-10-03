local addonVersion="1.2.0"
local HolyStorm=LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local L=LibStub("AceLocale-3.0"):GetLocale("Holy_Storm_Twinks")
local metadata={id="CharacterStats",name="CharacterStats",displayName=L["RULE_CATEGORY_STATS"],internalName="characterStats",version=addonVersion,moduleType="feature",category="feature",description=L["RULE_CATEGORY_STATS_DESC"],permissions={"player-read","sync-send"},dependencies={"core"},capabilities={"character.scan.stats","character.scan.additional"},data={block="stats"},enabledByDefault=true,ruleFields={
 {id="character.spec",aliases={"spec"},type="string",name=L["RULE_FIELD_SPECIALIZATION"],nameKey="RULE_FIELD_SPECIALIZATION",description=L["RULE_FIELD_SPECIALIZATION_DESC"],descriptionKey="RULE_FIELD_SPECIALIZATION_DESC",category=L["RULE_CATEGORY_STATS"],dependencies={"stats"},resolver=function(context)local spec=context.character and context.character.stats and context.character.stats.spec;return spec and(spec.id or spec.name)end},
 {id="character.role",aliases={"role"},type="string",name=L["RULE_FIELD_ROLE"],nameKey="RULE_FIELD_ROLE",description=L["RULE_FIELD_ROLE_DESC"],descriptionKey="RULE_FIELD_ROLE_DESC",category=L["RULE_CATEGORY_STATS"],dependencies={"stats"},resolver=function(context)return context.character and context.character.stats and context.character.stats.spec and context.character.stats.spec.role end},
}}

local primaryStats={{key="strength",index=1},{key="agility",index=2},{key="stamina",index=3},{key="intellect",index=4}}
local secondaryStats={
 {key="criticalStrike",rating="CR_CRIT_MELEE"},
 {key="haste",rating="CR_HASTE_MELEE",effective="GetHaste"},
 {key="mastery",rating="CR_MASTERY",effective="GetMasteryEffect"},
 {key="versatility",rating="CR_VERSATILITY_DAMAGE_DONE",effective="GetVersatility"},
 {key="leech",rating="CR_LIFESTEAL",effective="GetLifesteal"},
 {key="avoidance",rating="CR_AVOIDANCE",effective="GetAvoidance"},
 {key="speed",rating="CR_SPEED",effective="GetSpeed"},
}

local function safeNumber(value)
 if value==nil then return nil end
 if issecretvalue and issecretvalue(value)then return nil end
 if type(value)~="number"or value~=value or value==math.huge or value==-math.huge then return nil end
 return value
end
local function safeString(value)
 if value==nil or issecretvalue and issecretvalue(value)or type(value)~="string"then return nil end
 return value
end
local function callNumber(name,...)
 local callback=_G[name];if type(callback)~="function"then return nil end
 local ok,value=pcall(callback,...);if not ok then return nil end
 return safeNumber(value)
end
local function callValues(callback,...)
 if type(callback)~="function"then return false end
 return pcall(callback,...)
end
local function ratingId(key)local value=_G[key];return safeNumber(value)end
local function masteryValue()
 local ok,value,coefficient=callValues(_G.GetMasteryEffect)
 if not ok then return nil,nil end
 return safeNumber(value),safeNumber(coefficient)
end
local function critValue()
 if type(_G.GetCritChance)~="function"or type(_G.GetRangedCritChance)~="function"or type(_G.GetSpellCritChance)~="function"then return nil,nil end
 local schoolCount=safeNumber(_G.MAX_SPELL_SCHOOLS);if not schoolCount or schoolCount<3 then return nil,nil end
 local spellCrit
 for school=2,schoolCount do
  local value=callNumber("GetSpellCritChance",school);if value==nil then return nil,nil end
  spellCrit=spellCrit and math.min(spellCrit,value)or value
 end
 local ranged=callNumber("GetRangedCritChance");local melee=callNumber("GetCritChance")
 if ranged==nil or melee==nil then return nil,nil end
 if spellCrit>=ranged and spellCrit>=melee then return spellCrit,ratingId("CR_CRIT_SPELL")end
 if ranged>=melee then return ranged,ratingId("CR_CRIT_RANGED")end
 return melee,ratingId("CR_CRIT_MELEE")
end
local function versatilityValue()
 local rating=ratingId("CR_VERSATILITY_DAMAGE_DONE");local ratingPercent=rating and callNumber("GetCombatRatingBonus",rating)
 local otherPercent=rating and callNumber("GetVersatilityBonus",rating)
 if ratingPercent==nil or otherPercent==nil then return nil end
 return ratingPercent+otherPercent
end
local function readLive()
 local live={primary={},secondary={},available=true}
 for _,definition in ipairs(primaryStats)do
  local ok,current,effective,positive,negative=callValues(_G.UnitStat,"player",definition.index)
  current,effective,positive,negative=ok and safeNumber(current),ok and safeNumber(effective),ok and safeNumber(positive),ok and safeNumber(negative)
  local baseline=current and positive~=nil and negative~=nil and(current-positive-negative)or nil
  live.primary[definition.key]={baseline=baseline,effective=effective}
 end
 local armorCall,_,effectiveArmor=callValues(_G.UnitArmor,"player")
 live.armor={effective=armorCall and safeNumber(effectiveArmor)or nil}
 local crit,critRating=critValue()
 for _,definition in ipairs(secondaryStats)do
  local ratingType=definition.key=="criticalStrike"and critRating or ratingId(definition.rating)
  local rating=ratingType and callNumber("GetCombatRating",ratingType)or nil
  local effective
  if definition.key=="criticalStrike"then effective=crit
  elseif definition.key=="versatility"then effective=versatilityValue()
  elseif definition.key=="mastery"then effective=masteryValue()
  else effective=callNumber(definition.effective)end
  live.secondary[definition.key]={rating=rating,effective=effective}
 end
 local _,coefficient=masteryValue();live.secondary.mastery.coefficient=coefficient
 local index=type(GetSpecialization)=="function"and callNumber("GetSpecialization")or nil;if index then
  local ok,id,name,_,icon,role=callValues(GetSpecializationInfo,index)
  if ok then live.spec={index=index,id=safeNumber(id),name=safeString(name),icon=safeNumber(icon),role=safeString(role)}end
 end
 return live
end

local function baselineSafety()
 local auraApi=C_UnitAuras
 if type(auraApi)~="table"or type(auraApi.GetAuraDataByIndex)~="function"then return false,"AURA_API_UNAVAILABLE"end
 local currentTime
 if type(GetTime)=="function"then local clockOk,value=pcall(GetTime);if clockOk then currentTime=safeNumber(value)end end
 if currentTime==nil then return false,"AURA_CLOCK_UNAVAILABLE"end
 for _,filter in ipairs({"HELPFUL","HARMFUL"})do
  local terminated=false
  for index=1,255 do
   local ok,aura=pcall(auraApi.GetAuraDataByIndex,"player",index,filter)
   if not ok then return false,"AURA_STATE_UNREADABLE"end
   if issecretvalue and issecretvalue(aura)then return false,"AURA_STATE_UNREADABLE"end
   if aura==nil then terminated=true;break end
   if type(aura)~="table"then return false,"AURA_STATE_UNREADABLE"end
   local expiration=rawget(aura,"expirationTime");local duration=rawget(aura,"duration")
   if issecretvalue and(issecretvalue(expiration)or issecretvalue(duration))then return false,"AURA_STATE_UNREADABLE"end
   expiration=safeNumber(expiration);duration=safeNumber(duration)
   if expiration==nil or duration==nil then return false,"AURA_STATE_UNREADABLE"end
   if expiration and duration and duration>0 and expiration>currentTime then return false,"TIMED_AURA_ACTIVE"end
  end
  if not terminated then return false,"AURA_SCAN_LIMIT"end
 end
 return true,"NO_TIMED_AURAS"
end

HolyStorm:RegisterModule(metadata,function(Module)
 Module.live=nil;Module.liveTimer=false;Module.baselineTimer=false;Module.baselineDirty=true
 function Module:GetCharacterSnapshot(guid)return HolyStorm.Data.CharacterStore:GetBlock(guid,"stats")end
 function Module:CollectLive()
  local live=readLive();live.baselineReady=self.baselineDirty~=true;self.live=live
  local guid=UnitGUID and UnitGUID("player");if guid then HolyStorm.Events:Emit("HS_STATS_LIVE_UPDATED",guid,live)end
  return live
 end
 function Module:Collect()
  local live=self:CollectLive();local allowed,reason=baselineSafety()
  if not allowed then self.baselineDirty=true end
  local partial=not allowed
  local snapshot={snapshotVersion=2,schemaVersion=2,updatedAt=HolyStorm.Utils.Now(),spec=live.spec,primary={},secondary={},capture={eligible=true,partial=partial,reason=reason}}
  for _,definition in ipairs(primaryStats)do local value=live.primary[definition.key];snapshot.primary[definition.key]={baseline=value.baseline}end
  snapshot.armor={};if not partial then snapshot.armor.baseline=live.armor.effective end
  for _,definition in ipairs(secondaryStats)do local value=live.secondary[definition.key];snapshot.secondary[definition.key]=partial and{}or{rating=value.rating,baseline=value.effective,coefficient=value.coefficient}end
  return snapshot
 end
 function Module:Validate(snapshot)
  if type(snapshot)~="table"or snapshot.snapshotVersion~=2 or snapshot.schemaVersion~=2 or type(snapshot.primary)~="table"or type(snapshot.secondary)~="table"or type(snapshot.armor)~="table"or type(snapshot.capture)~="table"or type(snapshot.capture.reason)~="string"or type(snapshot.capture.partial)~="boolean"then return false,"INVALID_STATS_SNAPSHOT",false end
  if snapshot.capture.eligible~=true then return false,snapshot.capture.reason or"BASELINE_UNSAFE",false end
  local function optionalNumber(value)return value==nil or safeNumber(value)~=nil end
  local count=0
  for _,definition in ipairs(primaryStats)do local stat=snapshot.primary[definition.key];if type(stat)~="table"or not optionalNumber(stat.baseline)then return false,"INVALID_PRIMARY_STAT",false end;if stat.baseline~=nil then count=count+1 end end
  if not optionalNumber(snapshot.armor.baseline)then return false,"INVALID_ARMOR_BASELINE",false end;if snapshot.armor.baseline~=nil then count=count+1 end
  for _,definition in ipairs(secondaryStats)do local stat=snapshot.secondary[definition.key];if type(stat)~="table"or not optionalNumber(stat.rating)or not optionalNumber(stat.baseline)or not optionalNumber(stat.coefficient)then return false,"INVALID_SECONDARY_STAT",false end;if stat.rating~=nil or stat.baseline~=nil then count=count+1 end end
  local stored=HolyStorm.Data.CharacterStore:GetBlock(UnitGUID("player"),"stats")
  if type(stored)=="table"and stored.snapshotVersion==2 then
   local candidate={primary=snapshot.primary,secondary=snapshot.secondary,armor=snapshot.armor,spec=snapshot.spec}
   local previous={primary=stored.primary,secondary=stored.secondary,armor=stored.armor,spec=stored.spec}
   if HolyStorm.Serializer:Serialize(candidate)==HolyStorm.Serializer:Serialize(previous)then self.baselineDirty=false end
  end
  if snapshot.capture.partial then
   if snapshot.armor.baseline~=nil then return false,"PARTIAL_STATS_CONTAINS_ARMOR",false end
   for _,definition in ipairs(secondaryStats)do local stat=snapshot.secondary[definition.key];if stat.rating~=nil or stat.baseline~=nil or stat.coefficient~=nil then return false,"PARTIAL_STATS_CONTAINS_TRANSIENT_FIELDS",false end end
  end
  return count>0,"STATS_UNAVAILABLE",false
 end
 function Module:Commit(snapshot)
  local partial=type(snapshot)=="table"and type(snapshot.capture)=="table"and snapshot.capture.partial==true
  local allowed,reason=baselineSafety();if not allowed and not partial then self.baselineDirty=true;return false,reason end
  local guid=UnitGUID("player");local ok,writeReason=HolyStorm.PlayerData:WriteOwnedBlock(guid,"stats",snapshot,"blizzard")
  if partial then self.baselineDirty=true elseif ok or writeReason=="UNCHANGED"then self.baselineDirty=false end
  if not partial and(ok or writeReason=="UNCHANGED")then HolyStorm.Events:Emit("HS_STATS_BASELINE_UPDATED",guid,snapshot)end
  if ok or writeReason=="UNCHANGED"then self:CollectLive()end
  return ok,writeReason
 end
 function Module:Queue(sync)return HolyStorm.Snapshots:Queue("stats",function()return Module:Collect()end,function(snapshot,scanReason,diagnostics,attempt,maximum)return Module:Validate(snapshot,scanReason,diagnostics,attempt,maximum)end,function(snapshot)return Module:Commit(snapshot)end,{source="CharacterStats",delay=1,retryDelay=2.5,priority=5})end
 function Module:RequestBaseline(reason)
  local allowed=baselineSafety();if not allowed then self.baselineDirty=true;return false,"BASELINE_UNSAFE"end
  self.baselineDirty=true
  if HolyStorm.CharacterScans then return HolyStorm.CharacterScans:Request("stats",reason or"CHARACTER_STATS_BASELINE",true,{order=50,manual=reason=="MANUAL"or reason=="MANUAL_COMMAND"or reason=="DASHBOARD_MANUAL"})end
  return self:Queue(true)
 end
 function Module:ScheduleBaseline(delay,reason)
  self.baselineReason=reason or self.baselineReason or"CHARACTER_STATS_CHANGED"
  if self.baselineTimer then return end;self.baselineTimer=true
  C_Timer.After(delay or .35,function()local trigger=Module.baselineReason;Module.baselineTimer=false;Module.baselineReason=nil;Module:RequestBaseline(trigger)end)
 end
 function Module:ScheduleLive(delay)
  if self.liveTimer then return end;self.liveTimer=true
  C_Timer.After(delay or .2,function()Module.liveTimer=false;Module:CollectLive();if Module.baselineDirty then local allowed=baselineSafety();if allowed then Module:ScheduleBaseline(.1)end end end)
 end
 function Module:OnInitialize()
  HolyStorm.CharacterScans:RegisterProvider("CharacterStats",{block="stats",capability="character.scan.stats",addonId="characters",order=50,request=function(sync,reason)local _,workflowId=Module:Queue(sync);return workflowId end})
  HolyStorm:RegisterCapability("CharacterStats","character.scan.stats",function(_,sync,reason)return HolyStorm.CharacterScans:Request("stats",reason or"CAPABILITY",sync,{order=50})end)
  HolyStorm:RegisterCapability("CharacterStats","character.scan.additional",function(_,sync,reason)return HolyStorm.CharacterScans:Request("stats",reason or"CAPABILITY",sync,{order=50})end)
 end
 function Module:OnEnable()
  local function statsViewVisible()
   local ui=HolyStorm.UI;local character=HolyStorm.CharacterUI
   return ui and ui.GetVisiblePage and ui:GetVisiblePage()=="character"and character and character.activeTab=="stats"and character.context and character.context.characterUUID==UnitGUID("player")
  end
  local events={"PLAYER_EQUIPMENT_CHANGED","PLAYER_SPECIALIZATION_CHANGED","TRAIT_CONFIG_UPDATED","PLAYER_TALENT_UPDATE","PLAYER_LEVEL_UP"}
  for _,eventName in ipairs(events)do local event=eventName;HolyStorm.Events:Register(event,"character-stats",function(_,unit)
   if event=="PLAYER_SPECIALIZATION_CHANGED"and unit and unit~="player"then return end
   if event~="PLAYER_LEVEL_UP"and HolyStorm.State and not HolyStorm.State:Is("playerReady")then return end
   Module.baselineDirty=true;if statsViewVisible()then Module:ScheduleLive(.25)end;Module:ScheduleBaseline(.5,event)
  end)end
  HolyStorm.Events:Register("UNIT_AURA","character-stats-live",function(_,unit)
   if unit=="player"and statsViewVisible()then Module:ScheduleLive(.25)end
  end)
  HolyStorm.Events:Register("HS_STATS_LIVE_REQUESTED","character-stats-live-request",function(_,guid)
   if guid==UnitGUID("player")then Module:ScheduleLive(0)end
  end)
 end
 function Module:OnDisable()HolyStorm.Events:UnregisterOwner("character-stats");HolyStorm.Events:UnregisterOwner("character-stats-live");HolyStorm.Events:UnregisterOwner("character-stats-live-request");HolyStorm.Snapshots:Cancel("stats");self.live=nil end
end)
