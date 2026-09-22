local HolyStorm=LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local L=LibStub("AceLocale-3.0"):GetLocale("Holy_Storm_Raids")
local difficultyKeys={"LFR","NORMAL","HEROIC","MYTHIC"}
local function raidKey(name)return type(name)=="string"and name:lower():gsub("[%s%p%c]+","")or nil end
local function openJournal(row)if row.instanceId and not(InCombatLockdown and InCombatLockdown())and EncounterJournal_OpenJournal then EncounterJournal_OpenJournal(nil,tonumber(row.instanceId))end end
local function raidCell(cell,_,row)
 if not cell.icon then cell.icon=cell.frame:CreateTexture(nil,"ARTWORK");cell.icon:SetSize(20,20);cell.icon:SetPoint("LEFT",4,0);cell.text:ClearAllPoints();cell.text:SetPoint("LEFT",28,0);cell.text:SetPoint("RIGHT",-4,0)end
 cell.icon:SetTexture(row.icon or"Interface\\Icons\\INV_Sword_27");cell:SetDisplay(row.name,row.name)
end
local function progress(row,key)
 local lockout=row.weekly[key];if lockout then return string.format("%d/%d",tonumber(lockout.killed)or 0,tonumber(lockout.total)or row.total or 0)end
 if row.catalogReady and row.total and row.total>0 then return"0/"..row.total end
 return HolyStorm.CharacterUI:FormatState(nil)
end
local function weeklyTooltip(row,key,tooltip)
 tooltip:SetText(string.format(L["WEEKLY_TOOLTIP"],L["DIFFICULTY_"..key]or key));local lockout=row.weekly[key];local bosses=lockout and lockout.bosses or row.catalogBosses
 if not row.catalogReady and not lockout then tooltip:AddLine(L["NO_DATA"],.7,.7,.7);return true end
 for _,boss in ipairs(bosses or{})do local killed=lockout and boss.killed==true;tooltip:AddLine(string.format(killed and L["BOSS_KILLED"]or L["BOSS_OPEN"],boss.name or L["UNKNOWN"]),killed and.2 or.7,killed and 1 or.7,killed and.2 or.7)end
 if not bosses or#bosses==0 then tooltip:AddLine(L["NO_DATA"],.7,.7,.7)end;return true
end
local function bestText(snapshot,raidName)
 local C=HolyStorm.CharacterUI;local counts,total={},0
 for _,boss in ipairs(C:BuildRaidBestRows(snapshot))do if not raidName or not boss.raidName or boss.raidName==raidName then counts[boss.difficulty]=(counts[boss.difficulty]or 0)+1 end end
 for _,raid in ipairs(type(snapshot.raids)=="table"and snapshot.raids or{})do if not raidName or raid.name==raidName then total=total+#(raid.bosses or{})end end
 local parts={};for _,key in ipairs({"MYTHIC","HEROIC","NORMAL","LFR"})do if counts[key]and counts[key]>0 then local short=key=="MYTHIC"and"M"or key=="HEROIC"and"H"or key=="NORMAL"and"N"or"LFR";parts[#parts+1]=C:ColorDifficulty(key,string.format("%s %d/%d",short,counts[key],total>0 and total or counts[key]))end end
 if#parts>0 then return table.concat(parts," · ")end
 local fallback=C:GetBestProgress(snapshot,raidName);if fallback and(tonumber(fallback.killed)or 0)>0 then local short=fallback.difficulty=="MYTHIC"and"M"or fallback.difficulty=="HEROIC"and"H"or fallback.difficulty=="NORMAL"and"N"or fallback.difficulty=="LFR"and"LFR"or"?";return C:ColorDifficulty(fallback.difficulty,string.format("%s %d/%d",short,fallback.killed,fallback.total))end
 return snapshot.catalogReady==true and""or C:FormatState(nil)
end
local function bestTooltip(row,tooltip)
 local C=HolyStorm.CharacterUI;tooltip:SetText(L["BEST_TOOLTIP"]);local shown=0
 for _,boss in ipairs(C:BuildRaidBestRows(row.snapshot))do if not boss.raidName or boss.raidName==row.name then local short=boss.difficulty=="MYTHIC"and"M"or boss.difficulty=="HEROIC"and"H"or boss.difficulty=="NORMAL"and"N"or"LFR";tooltip:AddLine(string.format(L["BEST_ROW"],C:ColorDifficulty(boss.difficulty,short),boss.bossName,boss.kills),1,1,1);shown=shown+1 end end
 if shown==0 then tooltip:AddLine(L["NO_DATA"],.7,.7,.7)end;return true
end
local function refresh(view,context,definition)
 local C=HolyStorm.CharacterUI;local ok,reason=C:CanUseTab(definition);if not ok then C:SetTableView(view,{}, {emptyText=reason=="PERMISSION"and L["PERMISSION_DENIED"]or L["MODULE_DISABLED"]});return end
 local snapshot=C:GetSnapshot(context.characterUUID,"raid");if not snapshot then C:SetTableView(view,{}, {emptyText=L["NO_RAID"]});return end
 local rows,byName,byId={},{},{};for _,catalog in ipairs(type(snapshot.raids)=="table"and snapshot.raids or{})do local row={name=catalog.name or C:FormatState(nil),instanceId=catalog.id,icon=catalog.icon,order=catalog.order or#rows+1,weekly={},catalogBosses=catalog.bosses or{},total=#(catalog.bosses or{}),catalogReady=snapshot.catalogReady==true,snapshot=snapshot};rows[#rows+1]=row;byName[raidKey(row.name)]=row;byId[tostring(row.instanceId)]=row end
 for _,lockout in ipairs(type(snapshot.lockouts)=="table"and snapshot.lockouts or{})do local row=lockout.journalInstanceId and byId[tostring(lockout.journalInstanceId)]or byName[raidKey(lockout.name)];if not row then row={name=lockout.name or C:FormatState(nil),instanceId=lockout.journalInstanceId,order=1000+#rows,weekly={},catalogBosses={},total=tonumber(lockout.total),catalogReady=false,snapshot=snapshot};rows[#rows+1]=row;byName[raidKey(row.name)]=row end;local difficulty=C:GetDifficultyById(lockout.difficultyId);if difficulty then row.weekly[difficulty.id]=lockout end end
 table.sort(rows,function(a,b)if a.order==b.order then return tostring(a.name)<tostring(b.name)end;return a.order<b.order end)
 for _,row in ipairs(rows)do for _,key in ipairs(difficultyKeys)do row[key:lower()]=C:ColorDifficulty(key,progress(row,key))end;row.best=bestText(snapshot,row.name)end
 C:SetTableView(view,rows,{emptyText=L["NO_RAID"]})
end
local function build(parent)
 local columns={{id="name",title=L["COLUMN_RAID"],weight=1,minWidth=200,truncate=true,renderCell=raidCell,onClick=openJournal,tooltip=function(row,_,_,tooltip)tooltip:SetText(row.name);tooltip:AddLine(L["OPEN_JOURNAL"],1,1,1,true);return true end}}
 for _,key in ipairs(difficultyKeys)do local difficultyKey=key;columns[#columns+1]={id=difficultyKey:lower(),title=L["DIFFICULTY_"..difficultyKey],width=90,align="RIGHT",tooltip=function(row,_,_,tooltip)return weeklyTooltip(row,difficultyKey,tooltip)end}end
 columns[#columns+1]={id="best",title=L["COLUMN_BEST"],width=180,align="RIGHT",tooltip=function(row,_,_,tooltip)return bestTooltip(row,tooltip)end}
 return HolyStorm.CharacterUI:CreateTableView(parent,{columns=columns,rowHeight=27,headerHeight=26,columnGap=1,emptyText=L["NO_RAID"]})
end
HolyStorm:RegisterCharacterTab("raids",{id="raid",order=40,label=L["DISPLAY_NAME"],labelKey="DISPLAY_NAME",icon="Interface\\Icons\\INV_Sword_27",permission="raids-read",moduleId="raids",blocks={"raid"},events={"HS_RAIDLOCKS_UPDATED"},build=build,refresh=refresh})
HolyStorm:RegisterCharacterSummarySection("raids",{id="raid",order=40,render=function(context)local C=HolyStorm.CharacterUI;local allowed,reason=C:CanUseTab(C:GetTab("raid"));if not allowed then return{label=L["DISPLAY_NAME"],tabId="raid",value=reason=="PERMISSION"and L["PERMISSION_DENIED"]or L["MODULE_DISABLED"]}end;local snapshot=C:GetSnapshot(context.characterUUID,"raid");return{label=L["DISPLAY_NAME"],tabId="raid",formatted=snapshot and bestText(snapshot)or L["NO_RAID"]}end})
