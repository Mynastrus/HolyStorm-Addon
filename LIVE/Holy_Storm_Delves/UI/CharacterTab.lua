local HolyStorm=LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local L=LibStub("AceLocale-3.0"):GetLocale("Holy_Storm_Delves")
local function field(value)
 local C=HolyStorm.CharacterUI;if type(value)=="boolean"then return value and L["YES"]or L["NO"]end;if type(value)~="table"then return C:FormatState(value)end
 if value.status=="unknown"then return C:FormatState(nil)end
 for _,key in ipairs({"value","count","level","name"})do if value[key]~=nil then return C:FormatState(value[key])end end
 return L["PRESENT"]
end
local function refresh(view,context,definition)
 local C=HolyStorm.CharacterUI;local ok,reason=C:CanUseTab(definition);if not ok then C:SetTableView(view,{}, {emptyText=reason=="PERMISSION"and L["PERMISSION_DENIED"]or L["MODULE_DISABLED"]});return end
 local snapshot=C:GetSnapshot(context.characterUUID,"delves");if not snapshot then C:SetTableView(view,{}, {emptyText=L["NO_DELVES"]});return end
 local rows={
  {group=L["GROUP_OVERVIEW"],metric=L["GREAT_VAULT"],value=field(snapshot.weeklyProgress),details=""},
  {group=L["GROUP_OVERVIEW"],metric=L["BOUNTIFUL"],value=field(snapshot.bountiful),details=""},
  {group=L["GROUP_RESOURCES"],metric=L["KEY_FRAGMENTS"],value=field(snapshot.keyFragments),details=""},
  {group=L["GROUP_RESOURCES"],metric=L["COMPLETED_KEYS"],value=field(snapshot.completedKeys),details=""},
  {group=L["GROUP_RESOURCES"],metric=L["TREASURE_MAP"],value=field(snapshot.treasureMap),details=""},
  {group=L["GROUP_RESOURCES"],metric=L["MAP_USED"],value=field(snapshot.treasureMapUsed),details=""},
  {group=L["GROUP_COMPANION"],metric=L["COMPANION"],value=field(snapshot.companion),details=""},
  {group=L["GROUP_COMPANION"],metric=L["FLUTE"],value=field(snapshot.flute),details=""},
  {group=L["GROUP_COMPANION"],metric=L["MINI_ROGUE"],value=field(snapshot.miniRogue),details=""},
 }
 for index,activity in ipairs(type(snapshot.activities)=="table"and snapshot.activities or{})do rows[#rows+1]={group=L["GROUP_ACTIVITIES"],metric=string.format(L["ACTIVITY"],activity.index or index),value=field(activity.progress),details=string.format(L["ACTIVITY_DETAILS"],field(activity.threshold),field(activity.level))}end
 C:SetTableView(view,rows,{summary=string.format(L["SEASON"],field(snapshot.seasonNumber)),emptyText=L["NO_DELVES"]})
end
local function build(parent)return HolyStorm.CharacterUI:CreateTableView(parent,{columns={
 {id="group",title=L["COLUMN_GROUP"],width=135},{id="metric",title=L["COLUMN_METRIC"],weight=1,minWidth=190},{id="value",title=L["COLUMN_VALUE"],width=130,align="RIGHT"},{id="details",title=L["COLUMN_DETAILS"],weight=.8,minWidth=160},
},rowHeight=26,headerHeight=26,columnGap=1,emptyText=L["NO_DELVES"]})end
HolyStorm:RegisterCharacterTab("delves",{id="delves",order=50,label=L["DISPLAY_NAME"],labelKey="DISPLAY_NAME",icon="Interface\\Icons\\INV_Misc_Map_01",permission="delves-read",moduleId="delves",blocks={"delves"},events={"HS_DELVES_UPDATED"},build=build,refresh=refresh})
HolyStorm:RegisterCharacterSummarySection("delves",{id="delves",order=50,render=function(context)local C=HolyStorm.CharacterUI;local allowed,reason=C:CanUseTab(C:GetTab("delves"));if not allowed then return{label=L["DISPLAY_NAME"],tabId="delves",value=reason=="PERMISSION"and L["PERMISSION_DENIED"]or L["MODULE_DISABLED"]}end;local snapshot=C:GetSnapshot(context.characterUUID,"delves");return{label=L["DISPLAY_NAME"],tabId="delves",value=snapshot and(L["GREAT_VAULT"]..": "..field(snapshot.weeklyProgress))or L["NO_DELVES"]}end})
