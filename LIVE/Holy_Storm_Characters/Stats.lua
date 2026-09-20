local addonVersion="1.1.0"
local HolyStorm=LibStub("AceAddon-3.0"):GetAddon("Holy_Storm");local L=LibStub("AceLocale-3.0"):GetLocale("Holy_Storm_Twinks")
local metadata={id="CharacterStats",name="CharacterStats",displayName=L["RULE_CATEGORY_STATS"],internalName="characterStats",version=addonVersion,moduleType="feature",category="feature",description=L["RULE_CATEGORY_STATS_DESC"],permissions={"player-read","sync-send"},dependencies={"core","ui"},capabilities={"character.scan.stats","character.scan.additional"},data={block="stats"},enabledByDefault=true,ruleFields={
 {id="character.spec",aliases={"spec"},type="string",name=L["RULE_FIELD_SPECIALIZATION"],nameKey="RULE_FIELD_SPECIALIZATION",description=L["RULE_FIELD_SPECIALIZATION_DESC"],descriptionKey="RULE_FIELD_SPECIALIZATION_DESC",category=L["RULE_CATEGORY_STATS"],dependencies={"stats"},resolver=function(context)local spec=context.character and context.character.stats and context.character.stats.spec;return spec and(spec.id or spec.name)end},
 {id="character.role",aliases={"role"},type="string",name=L["RULE_FIELD_ROLE"],nameKey="RULE_FIELD_ROLE",description=L["RULE_FIELD_ROLE_DESC"],descriptionKey="RULE_FIELD_ROLE_DESC",category=L["RULE_CATEGORY_STATS"],dependencies={"stats"},resolver=function(context)return context.character and context.character.stats and context.character.stats.spec and context.character.stats.spec.role end},
}}
HolyStorm:RegisterModule(metadata,function(Module)
 function Module:GetCharacterSnapshot(guid)return HolyStorm.Data.CharacterStore:GetBlock(guid,"stats")end
 function Module:Collect()
  local s={primary={},secondary={},updatedAt=HolyStorm.Utils.Now(),snapshotVersion=1};for i,key in ipairs({"strength","agility","stamina","intellect"})do local base,effective=UnitStat("player",i);s.primary[key]={base=base,effective=effective}end
  local baseArmor,effectiveArmor=UnitArmor("player");s.armor={base=baseArmor,effective=effectiveArmor}
  local ratings={{"criticalStrike",CR_CRIT_MELEE},{"haste",CR_HASTE_MELEE},{"mastery",CR_MASTERY},{"versatility",CR_VERSATILITY_DAMAGE_DONE}};for _,x in ipairs(ratings)do if x[2]then s.secondary[x[1]]={rating=GetCombatRating(x[2])or 0,percent=GetCombatRatingBonus(x[2])or 0}end end
  local index=GetSpecialization and GetSpecialization();if index then local id,name,_,icon,role=GetSpecializationInfo(index);s.spec={index=index,id=id,name=name,icon=icon,role=role}end;return s
 end
 function Module:Validate(s)return type(s)=="table"and type(s.primary)=="table"and s.primary.stamina and s.primary.stamina.base~=nil,"stats unavailable"end
 function Module:Commit(s)local guid=UnitGUID("player");return HolyStorm.Data.CharacterStore:SetStats(guid,s,{updatedAt=s.updatedAt,updatedBy=guid},"blizzard")end
 function Module:Queue(sync)return HolyStorm.Snapshots:Queue("stats",function()return Module:Collect()end,function(s)return Module:Validate(s)end,function(s,f)return Module:Commit(s,f,sync)end,{source="CharacterStats",delay=1,retryDelay=2.5,priority=5})end
 function Module:OnInitialize()HolyStorm:RegisterCapability("CharacterStats","character.scan.stats",function(_,sync)return Module:Queue(sync)end);HolyStorm:RegisterCapability("CharacterStats","character.scan.additional",function(_,sync)return Module:Queue(sync)end)end
 function Module:OnEnable()for _,ev in ipairs({"PLAYER_EQUIPMENT_CHANGED","PLAYER_SPECIALIZATION_CHANGED","TRAIT_CONFIG_UPDATED","PLAYER_TALENT_UPDATE"})do local event=ev;HolyStorm.Events:Register(event,"character-stats",function(_,firstArgument)if event~="PLAYER_SPECIALIZATION_CHANGED"or not firstArgument or firstArgument=="player"then Module:Queue(true)end end)end end
 function Module:OnDisable()HolyStorm.Events:UnregisterOwner("character-stats");HolyStorm.Snapshots:Cancel("stats")end
end)
