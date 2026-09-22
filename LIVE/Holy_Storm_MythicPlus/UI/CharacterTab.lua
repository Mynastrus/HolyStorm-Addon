local HolyStorm=LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local L=LibStub("AceLocale-3.0"):GetLocale("Holy_Storm_Dungeons")
local TYRANNICAL,FORTIFIED=9,10
local function affixEntry(dungeon,affixId)
 for _,entry in pairs(type(dungeon.affixScores)=="table"and dungeon.affixScores or{})do
  if type(entry)=="table"then
   local id=tonumber(entry.affixID or entry.affixId or entry.id);local found=id==affixId
   for _,candidate in ipairs(type(entry.affixIDs)=="table"and entry.affixIDs or{})do if tonumber(candidate)==affixId then found=true end end
   if found then return entry end
  end
 end
end
local function keyResult(entry,ready,timeLimit)
 if type(entry)~="table"then return ready and""or HolyStorm.CharacterUI:FormatState(nil)end
 local level=tonumber(entry.level or entry.bestLevel);if not level or level<=0 then return""end
 local overTime=entry.overTime;if overTime==nil and tonumber(entry.durationSec)and tonumber(timeLimit)then overTime=tonumber(entry.durationSec)>tonumber(timeLimit)end;if overTime==nil then return HolyStorm.CharacterUI:FormatState(nil)end
 local text="+"..level;if overTime==true then return"|cffff4040"..text.."|r"end;return"|cff20ff20"..text.."|r"
end
local function scoreText(value)
 local score=tonumber(value);if score==nil then return HolyStorm.CharacterUI:FormatState(nil)end
 local text=score%1==0 and tostring(score)or string.format("%.1f",score);local color=C_ChallengeMode and C_ChallengeMode.GetDungeonScoreRarityColor and C_ChallengeMode.GetDungeonScoreRarityColor(score)
 if color then if color.WrapTextInColorCode then return color:WrapTextInColorCode(text)end;if color.r then return string.format("|cff%02x%02x%02x%s|r",math.floor(color.r*255+.5),math.floor(color.g*255+.5),math.floor(color.b*255+.5),text)end end
 return text
end
local function teleportState(dungeon)
 local spellId=tonumber(dungeon.teleportSpellId or dungeon.teleportSpellID);if not spellId then return{state="UNAVAILABLE"}end
 local known=(C_SpellBook and C_SpellBook.IsSpellKnown and C_SpellBook.IsSpellKnown(spellId))or(C_Spell and C_Spell.IsSpellKnown and C_Spell.IsSpellKnown(spellId))or(IsSpellKnownOrOverridesKnown and IsSpellKnownOrOverridesKnown(spellId))or(IsSpellKnown and IsSpellKnown(spellId));if not known then return{state="UNAVAILABLE",spellId=spellId}end
 local hasCooldownAPI=C_Spell and C_Spell.GetSpellCooldown or GetSpellCooldown;if not hasCooldownAPI then return{state="UNAVAILABLE",spellId=spellId}end
 local cooldown=C_Spell and C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldown(spellId);local start,duration
 if type(cooldown)=="table"then start,duration=cooldown.startTime,cooldown.duration elseif GetSpellCooldown then start,duration=GetSpellCooldown(spellId)end;if start==nil or duration==nil then return{state="UNAVAILABLE",spellId=spellId}end
 local remaining=tonumber(start)and tonumber(duration)and math.max(0,start+duration-((GetTime and GetTime())or 0))or 0
 return{state=remaining>0 and"COOLDOWN"or"READY",spellId=spellId,remaining=remaining}
end
local function teleportTooltip(row,tooltip)
 local state=row.teleport;if state.spellId and tooltip.SetSpellByID then tooltip:SetSpellByID(state.spellId)else tooltip:SetText(row.name)end;if state.state=="READY"then tooltip:AddLine(L["TELEPORT_READY"],.2,1,.2,true)elseif state.state=="COOLDOWN"then local value=SecondsToClock and SecondsToClock(state.remaining)or tostring(math.ceil(state.remaining));tooltip:AddLine(string.format(L["TELEPORT_COOLDOWN"],value),1,.3,.3,true)else tooltip:AddLine(L["TELEPORT_UNAVAILABLE"],.7,.7,.7,true)end
end
local function castTeleport(row)
 local state=row.teleport;if not state or state.state~="READY"or not state.spellId then return end
 if CastSpellByID then CastSpellByID(state.spellId)elseif C_Spell and C_Spell.CastSpell then C_Spell.CastSpell(state.spellId)end
end
local function dungeonCell(cell,_,row)
 if not cell.teleportButton then
  local button=CreateFrame("Button",nil,cell.frame);button:SetSize(20,20);button:SetPoint("LEFT",4,0);local texture=button:CreateTexture(nil,"ARTWORK");texture:SetAllPoints();button.texture=texture
  button:SetScript("OnClick",function()castTeleport(cell.teleportRow)end);button:SetScript("OnEnter",function(owner)if not GameTooltip then return end;GameTooltip:SetOwner(owner,"ANCHOR_RIGHT");teleportTooltip(cell.teleportRow,GameTooltip);GameTooltip:Show()end);button:SetScript("OnLeave",function()if GameTooltip then GameTooltip:Hide()end end)
  cell.teleportButton=button;cell.text:ClearAllPoints();cell.text:SetPoint("LEFT",30,0);cell.text:SetPoint("RIGHT",-4,0)
 end
 cell.teleportRow=row;cell.teleportButton.texture:SetTexture(row.texture or"Interface\\Icons\\Spell_Arcane_TeleportStormWind");cell.teleportButton:SetEnabled(row.teleport.state=="READY");cell.teleportButton:SetAlpha(row.teleport.state=="READY"and 1 or row.teleport.state=="COOLDOWN"and.65 or.3);cell:SetDisplay(row.name)
end
local function openJournal(row)if row.instanceId and not(InCombatLockdown and InCombatLockdown())and EncounterJournal_OpenJournal then EncounterJournal_OpenJournal(nil,tonumber(row.instanceId))end end
local function refresh(view,context,definition)
 local C=HolyStorm.CharacterUI;local ok,reason=C:CanUseTab(definition);if not ok then C:SetTableView(view,{}, {emptyText=reason=="PERMISSION"and L["PERMISSION_DENIED"]or L["MODULE_DISABLED"]});return end
 local snapshot=C:GetSnapshot(context.characterUUID,"mythicPlus");if not snapshot or next(snapshot)==nil then C:SetTableView(view,{}, {emptyText=L["NO_MYTHICPLUS"]});return end
 local rows={};for _,dungeon in pairs(type(snapshot.dungeons)=="table"and snapshot.dungeons or{})do if type(dungeon)=="table"then
  rows[#rows+1]={name=dungeon.name or C:FormatState(nil),instanceId=dungeon.instanceId,challengeMapId=dungeon.challengeMapId,texture=dungeon.texture,teleport=teleportState(dungeon),tyrannical=keyResult(affixEntry(dungeon,TYRANNICAL),snapshot.scoreDataReady==true,dungeon.timeLimit),fortified=keyResult(affixEntry(dungeon,FORTIFIED),snapshot.scoreDataReady==true,dungeon.timeLimit),rating=snapshot.scoreDataReady==false and C:FormatState(nil)or scoreText(dungeon.score)}
 end end
 table.sort(rows,function(a,b)return tostring(a.name)<tostring(b.name)end)
 local season=C:FormatState(snapshot.seasonId or snapshot.seasonNumber);local overall=scoreText(snapshot.overallScore);C:SetTableView(view,rows,{summary=string.format(L["SEASON_SUMMARY"],season,overall),emptyText=L["NO_MYTHICPLUS"]})
end
local function build(parent)
 return HolyStorm.CharacterUI:CreateTableView(parent,{columns={
  {id="name",title=L["COLUMN_DUNGEON"],weight=1,minWidth=220,truncate=true,renderCell=dungeonCell,onClick=openJournal,tooltip=function(row,_,_,tooltip)tooltip:SetText(row.name);tooltip:AddLine(L["OPEN_JOURNAL"],1,1,1,true);return true end},
  {id="tyrannical",title=L["TYRANNICAL"],width=120,align="RIGHT"},{id="fortified",title=L["FORTIFIED"],width=120,align="RIGHT"},{id="rating",title=L["DUNGEON_SCORE"],width=110,align="RIGHT"},
 },rowHeight=28,headerHeight=26,columnGap=1,emptyText=L["NO_MYTHICPLUS"]})
end
HolyStorm:RegisterCharacterTab("mythicPlus",{id="mythicPlus",order=30,label=L["DISPLAY_NAME"],labelKey="DISPLAY_NAME",icon="Interface\\Icons\\Achievement_ChallengeMode_Gold",permission="mythicplus-read",moduleId="mythicPlus",blocks={"mythicPlus"},events={"HS_MYTHICPLUS_UPDATED"},build=build,refresh=refresh})
HolyStorm:RegisterCharacterSummarySection("mythicPlus",{id="mythicPlus",order=30,render=function(context)local C=HolyStorm.CharacterUI;local allowed,reason=C:CanUseTab(C:GetTab("mythicPlus"));if not allowed then return{label=L["DISPLAY_NAME"],tabId="mythicPlus",value=reason=="PERMISSION"and L["PERMISSION_DENIED"]or L["MODULE_DISABLED"]}end;local snapshot=C:GetSnapshot(context.characterUUID,"mythicPlus");return{label=L["DISPLAY_NAME"],tabId="mythicPlus",value=snapshot and(L["OVERALL_RATING"]..": "..scoreText(snapshot.overallScore))or L["NO_MYTHICPLUS"]}end})
