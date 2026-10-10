local HolyStorm=LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local CharacterL=LibStub("AceLocale-3.0"):GetLocale("Holy_Storm_CharacterUI")
local function locale(prefix)return setmetatable({},{__index=function(_,key)return CharacterL[prefix..key]end})end
local function itemLink(item)
 if type(item)~="table"or type(item.link)~="string"then return nil end
 local itemString=item.link:match("|H(item:[^|]+)|h.-|h")
 local linkedId=itemString and tonumber(itemString:match("^item:(%d+)"))
 if not linkedId or tonumber(item.itemId)~=linkedId then return nil end
 return item.link
end

-- These adapters belong to the Character Storage consumer. The optional
-- feature addons only produce and update the snapshots consumed here.
do
 local L=locale("EQUIPMENT_")
 local slots={
  {INVSLOT_HEAD,"SLOT_HEAD","Interface\\PaperDoll\\UI-PaperDoll-Slot-Head"},{INVSLOT_NECK,"SLOT_NECK","Interface\\PaperDoll\\UI-PaperDoll-Slot-Neck"},{INVSLOT_SHOULDER,"SLOT_SHOULDER","Interface\\PaperDoll\\UI-PaperDoll-Slot-Shoulder"},{INVSLOT_BACK,"SLOT_BACK","Interface\\PaperDoll\\UI-PaperDoll-Slot-Chest"},
  {INVSLOT_CHEST,"SLOT_CHEST","Interface\\PaperDoll\\UI-PaperDoll-Slot-Chest"},{INVSLOT_WRIST,"SLOT_WRIST","Interface\\PaperDoll\\UI-PaperDoll-Slot-Wrists"},{INVSLOT_HAND,"SLOT_HANDS","Interface\\PaperDoll\\UI-PaperDoll-Slot-Hands"},{INVSLOT_WAIST,"SLOT_WAIST","Interface\\PaperDoll\\UI-PaperDoll-Slot-Waist"},
  {INVSLOT_LEGS,"SLOT_LEGS","Interface\\PaperDoll\\UI-PaperDoll-Slot-Legs"},{INVSLOT_FEET,"SLOT_FEET","Interface\\PaperDoll\\UI-PaperDoll-Slot-Feet"},{INVSLOT_FINGER1,"SLOT_FINGER1","Interface\\PaperDoll\\UI-PaperDoll-Slot-Finger"},{INVSLOT_FINGER2,"SLOT_FINGER2","Interface\\PaperDoll\\UI-PaperDoll-Slot-Finger"},
  {INVSLOT_TRINKET1,"SLOT_TRINKET1","Interface\\PaperDoll\\UI-PaperDoll-Slot-Trinket"},{INVSLOT_TRINKET2,"SLOT_TRINKET2","Interface\\PaperDoll\\UI-PaperDoll-Slot-Trinket"},{INVSLOT_MAINHAND,"SLOT_MAINHAND","Interface\\PaperDoll\\UI-PaperDoll-Slot-MainHand"},{INVSLOT_OFFHAND,"SLOT_OFFHAND","Interface\\PaperDoll\\UI-PaperDoll-Slot-SecondaryHand"},
 }
 local function itemName(item)if not item then return nil end;local link=itemLink(item);local label=link and link:match("|h%[?(.-)%]?|h");return label or item.name end
 local function openItem(row)local link=itemLink(row and row.item);if not link then return end;if HandleModifiedItemClick then pcall(HandleModifiedItemClick,link)elseif SetItemRef then local payload=link:match("|H([^|]+)|h");if payload then pcall(SetItemRef,payload,link,"LeftButton")end end end
 local function itemTooltip(row,_,_,tooltip)local item=row and row.item;local link=itemLink(item);if link and tooltip and type(tooltip.SetHyperlink)=="function"then local ok=pcall(tooltip.SetHyperlink,tooltip,link);if ok then return true end end;local name=itemName(item);if name and tooltip and type(tooltip.SetText)=="function"then tooltip:SetText(name);return true end end
 local function iconCell(cell,_,row)if not cell.icon then cell.icon=cell.frame:CreateTexture(nil,"ARTWORK");cell.icon:SetSize(20,20);cell.icon:SetPoint("LEFT",4,0);cell.text:ClearAllPoints();cell.text:SetPoint("LEFT",28,0);cell.text:SetPoint("RIGHT",-4,0)end;if row.state=="UNKNOWN"then cell.icon:SetTexture(nil);cell.icon:Hide()else cell.icon:SetTexture(row.item and row.item.icon or row.state=="EMPTY"and row.emptyTexture);cell.icon:Show()end;cell:SetDisplay(row.slotLabel)end
 local function itemCell(cell,_,row)if row.state=="UNKNOWN"then cell:SetDisplay(HolyStorm.CharacterUI:FormatState(nil));return end;if row.state=="EMPTY"then cell:SetDisplay(L["EMPTY_SLOT"]);return end;local name=itemName(row.item);local link=itemLink(row.item);if link then cell:SetDisplay(link,name,function(short)return HolyStorm.UI.Components:ReplaceHyperlinkLabel(link,short)end)else cell:SetDisplay(name or HolyStorm.CharacterUI:FormatState(nil),name)end end
 local function statusCell(cell,_,row,column)if not cell.statusIcon then cell.statusIcon=cell.frame:CreateTexture(nil,"ARTWORK");cell.statusIcon:SetSize(18,18);cell.statusIcon:SetPoint("CENTER");cell.statusIcon:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")end;local state=row[column.id.."State"];if state==true then cell.statusIcon:SetVertexColor(.2,1,.2,1);cell.statusIcon:Show();cell:SetDisplay("")else cell.statusIcon:Hide();cell:SetDisplay(state==nil and HolyStorm.CharacterUI:FormatState(nil)or"")end end
 local function formatItemLevel(value)local number=tonumber(value);return number and string.format("%.1f",number)or HolyStorm.CharacterUI:FormatState(nil)end
 local function itemLevelSummary(value)return"|cffffd100"..L["ITEM_LEVEL"]..":|r |cff80dfff"..formatItemLevel(value).."|r"end
 local function gemsFor(item)
  if not item then return nil,nil,nil end;local sockets=tonumber(item.sockets);local gems=type(item.gems)=="table"and item.gems or nil;if sockets==0 then return"",{},{}end;if sockets==nil then local unknown=HolyStorm.CharacterUI:FormatState(nil);return unknown,{unknown},{}end
 local labels,details,installed={},{},{};for index=1,sockets do local gem=gems and gems[index];local id=type(gem)=="table"and gem.itemId or gem;local knownFilled=type(gem)=="table"and(gem.state=="SOCKET_FILLED"or gem.state==nil)and tonumber(id)~=nil and tonumber(id)>0 or type(gem)=="number"and gem>0;if knownFilled then local name=type(gem)=="table"and gem.name or nil;local icon=type(gem)=="table"and gem.icon or nil;labels[#labels+1]=icon and("|T"..icon..":16:16|t")or tostring(id);details[#details+1]=name or string.format(L["GEM_ID"],tostring(id));installed[#installed+1]=gem else local unknown=HolyStorm.CharacterUI:FormatState(nil);labels[#labels+1]=unknown;details[#details+1]=unknown end end;return table.concat(labels," "),details,installed
 end
 local function refresh(view,context)
  local C=HolyStorm.CharacterUI;local snapshot=C:GetSnapshot(context.characterUUID,"equipment");if type(snapshot)~="table"or snapshot.snapshotVersion~=4 then C:SetTableView(view,{}, {emptyText=L["NO_EQUIPMENT"]});return end
  local rows={};for _,slot in ipairs(slots)do local raw=snapshot.slots and snapshot.slots[slot[1]];local state=raw==nil and"UNKNOWN"or raw==false and"EMPTY"or"EQUIPPED";local item=state=="EQUIPPED"and raw or nil;local gems,gemDetails,installedGems=gemsFor(item);local tierState,enchantState;if item then local enchantId=tonumber(item.enchantId);if enchantId~=nil then enchantState=enchantId>0 end elseif state=="EMPTY"then tierState,enchantState=false,false end;rows[#rows+1]={slotId=slot[1],slotLabel=L[slot[2]],emptyTexture=slot[3],state=state,item=item,itemText=itemName(item),tier="",tierState=tierState,enchant="",enchantState=enchantState,gems=gems or(state=="UNKNOWN"and C:FormatState(nil)or""),gemDetails=gemDetails,installedGems=installedGems,itemLevel=item and C:FormatState(item.itemLevel)or(state=="UNKNOWN"and C:FormatState(nil)or"")}end
  C:SetTableView(view,rows,{summary=itemLevelSummary(snapshot.equippedItemLevel or snapshot.itemLevel),emptyText=L["NO_EQUIPMENT"]})
 end
 local function build(parent)return HolyStorm.CharacterUI:CreateTableView(parent,{columns={{id="slotLabel",title=L["COLUMN_SLOT"],width=150,compactWidth=105,renderCell=iconCell,onClick=openItem,tooltip=itemTooltip},{id="itemText",title=L["COLUMN_ITEM"],weight=1,minWidth=180,compactWidth=120,truncate=true,renderCell=itemCell,onClick=openItem,tooltip=itemTooltip},{id="tier",title=L["COLUMN_TIER"],width=55,compactWidth=42,align="CENTER",renderCell=statusCell,tooltip=function(row)return row.tierState==true and L["TIER_ITEM"]or nil end},{id="enchant",title=L["COLUMN_ENCHANT"],width=100,compactWidth=72,align="CENTER",renderCell=statusCell,tooltip=function(row)if row.enchantState==nil then return end;if row.enchantState==false then return L["NOT_ENCHANTED"]end;return row.item and(row.item.enchantName or L["ENCHANTED"])or L["ENCHANTED"]end},{id="gems",title=L["COLUMN_GEMS"],width=130,compactWidth=90,align="CENTER",tooltip=function(row,_,_,tooltip)local installed=row.installedGems and#row.installedGems==1 and row.installedGems[1];local link=itemLink(installed);if link and type(tooltip.SetHyperlink)=="function"then local ok=pcall(tooltip.SetHyperlink,tooltip,link);if ok then return true end end;if not row.gemDetails or#row.gemDetails==0 then return end;tooltip:SetText(L["COLUMN_GEMS"]);for _,line in ipairs(row.gemDetails)do tooltip:AddLine(line,1,1,1)end;return true end},{id="itemLevel",title=L["COLUMN_ILVL"],width=80,compactWidth=55,align="RIGHT"}},rowHeight=26,headerHeight=26,columnGap=1,emptyText=L["NO_EQUIPMENT"]})end
 HolyStorm:RegisterCharacterTab("characters",{id="equipment",order=20,label=L["DISPLAY_NAME"],labelKey="EQUIPMENT_DISPLAY_NAME",icon="Interface\\Icons\\INV_Helmet_08",blocks={"equipment"},events={"HS_EQUIPMENT_UPDATED"},build=build,refresh=refresh})
 HolyStorm:RegisterCharacterSummarySection("characters",{id="equipment",order=20,render=function(context)local C=HolyStorm.CharacterUI;local snapshot=C:GetSnapshot(context.characterUUID,"equipment");return{label=L["DISPLAY_NAME"],tabId="equipment",value=type(snapshot)=="table"and snapshot.snapshotVersion==4 and itemLevelSummary(snapshot.equippedItemLevel or snapshot.itemLevel)or L["NO_EQUIPMENT"]}end})
end

do
 local L=locale("MYTHICPLUS_")
 local function safeNumber(value)if issecretvalue then local safe,secret=pcall(issecretvalue,value);if not safe or secret then return nil end end;local ok,number=pcall(tonumber,value);return ok and number or nil end
 local function scoreText(value)local score=safeNumber(value);if score==nil then return HolyStorm.CharacterUI:FormatState(nil)end;local text=score%1==0 and tostring(score)or string.format("%.1f",score);local api=C_ChallengeMode;local color;if api and type(api.GetDungeonScoreRarityColor)=="function"then local ok,result=pcall(api.GetDungeonScoreRarityColor,score);if ok then color=result end end;if color then if color.WrapTextInColorCode then return color:WrapTextInColorCode(text)end;if color.r then return string.format("|cff%02x%02x%02x%s|r",math.floor(color.r*255+.5),math.floor(color.g*255+.5),math.floor(color.b*255+.5),text)end end;return text end
 local function durationText(value)local seconds=safeNumber(value);if not seconds or seconds<0 then return nil end;seconds=math.floor(seconds+.5);local hours=math.floor(seconds/3600);local minutes=math.floor((seconds%3600)/60);local remainder=seconds%60;if hours>0 then return string.format("%d:%02d:%02d",hours,minutes,remainder)end;return string.format("%d:%02d",minutes,remainder)end
 local function levelText(value)local level=safeNumber(value);return level and level>0 and("+"..tostring(level))or nil end
 local function timedText(overTime)if type(overTime)~="boolean"then return HolyStorm.CharacterUI:FormatState(nil)end;return overTime and L["NOT_TIMED"]or L["TIMED"]end
 local function timedCell(cell,_,row)
  if not cell.statusIcon then cell.statusIcon=cell.frame:CreateTexture(nil,"ARTWORK");cell.statusIcon:SetSize(18,18);cell.statusIcon:SetPoint("CENTER")end
  if row.displayBestTimed==true then cell.statusIcon:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready");cell.statusIcon:SetVertexColor(.2,1,.2,1);cell.statusIcon:Show();cell:SetDisplay("")
  elseif row.displayBestTimed==false then cell.statusIcon:SetTexture("Interface\\RaidFrame\\ReadyCheck-NotReady");cell.statusIcon:SetVertexColor(1,.25,.25,1);cell.statusIcon:Show();cell:SetDisplay("")
  else cell.statusIcon:Hide();cell:SetDisplay(HolyStorm.CharacterUI:FormatState(nil))end
 end
 local function dungeonCell(cell,_,row)
  if not cell.icon then cell.icon=cell.frame:CreateTexture(nil,"ARTWORK");cell.icon:SetSize(20,20);cell.icon:SetPoint("LEFT",4,0)end
  cell.text:ClearAllPoints();cell.text:SetPoint("LEFT",row.texture and 28 or 6,0);cell.text:SetPoint("RIGHT",-4,0)
  if row.texture then cell.icon:SetTexture(row.texture);cell.icon:SetTexCoord(0,1,0,1);cell.icon:Show()else cell.icon:Hide()end
  cell:SetDisplay(row.name)
 end
 local function openJournal(row)if row and row.instanceId and not(InCombatLockdown and InCombatLockdown())and EncounterJournal_OpenJournal then pcall(EncounterJournal_OpenJournal,nil,tonumber(row.instanceId))end end
 local function runHasData(run)return type(run)=="table"and(levelText(run.level)~=nil or tonumber(run.score)~=nil or durationText(run.durationSec)~=nil or type(run.overTime)=="boolean")end
 local function appendRun(rows,label,run)
  if not runHasData(run)then return end
  local C=HolyStorm.CharacterUI;local unknown=C:FormatState(nil);local status=timedText(run.overTime);local colors
  if run.overTime==false then colors={[5]={r=.2,g=1,b=.2}}elseif run.overTime==true then colors={[5]={r=1,g=.25,b=.25}}else colors={[5]={r=.55,g=.55,b=.55}}end
  rows[#rows+1]={cells={label,levelText(run.level)or unknown,run.score~=nil and scoreText(run.score)or unknown,durationText(run.durationSec)or unknown,status},colors=colors}
 end
 local function bestRunTooltip(row,_,_,_,owner)
  if type(row)~="table"then return false end
  local C=HolyStorm.CharacterUI;local unknown=C:FormatState(nil);local rows={}
  appendRun(rows,L["TIMED"],row.bestInTime)
  appendRun(rows,L["NOT_TIMED"],row.bestOverTime)
  local affixes={};for _,entry in pairs(type(row.affixScores)=="table"and row.affixScores or{})do if type(entry)=="table"and runHasData(entry)then affixes[#affixes+1]=entry end end
  table.sort(affixes,function(a,b)return tostring(a.name or"")<tostring(b.name or"")end)
  for _,entry in ipairs(affixes)do if type(entry.name)=="string"and entry.name~=""then appendRun(rows,entry.name,entry)end end
  local timer=durationText(row.timeLimit);if timer then rows[#rows+1]={cells={L["DUNGEON_TIMER"],unknown,unknown,timer,unknown},colors={[5]={r=.55,g=.55,b=.55}}}end
  if #rows==0 then return false end
  local tooltips=HolyStorm.Tooltips
  return tooltips and tooltips:ShowTable("mythicplus-best-run",owner,{anchor={point="LEFT",relativePoint="RIGHT",x=8,y=0},columns={{align="LEFT"},{align="CENTER"},{align="RIGHT"},{align="RIGHT"},{align="CENTER"}},headers={{L["RUN"],L["COLUMN_BEST_LEVEL"],L["RUN_RATING"],L["COLUMN_TIME"],L["COLUMN_IN_TIME"]}},separator=true,rows=rows})or false
 end
 local function refresh(view,context)
  local C=HolyStorm.CharacterUI;local snapshot=C:GetSnapshot(context.characterUUID,"mythicPlus")
  if type(snapshot)~="table"or next(snapshot)==nil or snapshot.schemaVersion~=5 or snapshot.snapshotVersion~=5 then C:SetTableView(view,{}, {summary="",emptyText=L["NO_MYTHICPLUS"]});return end
  local rows={}
  for _,dungeon in pairs(type(snapshot.dungeons)=="table"and snapshot.dungeons or{})do if type(dungeon)=="table"then
   local timed=type(dungeon.bestInTime)=="table"and dungeon.bestInTime or nil
   local overtime=type(dungeon.bestOverTime)=="table"and dungeon.bestOverTime or nil
   local shown,shownTimed
   if timed and overtime then shownTimed=timed.score>overtime.score;shown=shownTimed and timed or overtime
   elseif timed then shown,shownTimed=timed,true
   elseif overtime then shown,shownTimed=overtime,false end
   rows[#rows+1]={name=dungeon.name or C:FormatState(nil),instanceId=dungeon.instanceId,challengeMapId=dungeon.challengeMapId,texture=dungeon.texture,bestInTime=timed,bestOverTime=overtime,displayBestTimed=shownTimed,affixScores=dungeon.affixScores,timeLimit=dungeon.timeLimit,bestLevel=shown and levelText(shown.level)or L["NO_COMPLETION"],rating=scoreText(dungeon.score),time=shown and durationText(shown.durationSec)or L["NO_COMPLETION"]}
  end end
  table.sort(rows,function(a,b)return(tonumber(a.challengeMapId)or 0)<(tonumber(b.challengeMapId)or 0)end)
  local dataStatus,_,_,staleReason=C:GetDataStatus(context.characterUUID,"mythicPlus",nil,{data=snapshot})
  if staleReason=="SEASON"then C:SetTableView(view,{}, {summary=L["SEASON_STALE"],emptyText=L["NO_MYTHICPLUS"]});return end
  if staleReason=="SEASON_UNKNOWN"then C:SetTableView(view,{}, {summary=L["SEASON_UNKNOWN"],emptyText=L["NO_MYTHICPLUS"]});return end
  local summary=string.format(L["SEASON_SUMMARY"],C:FormatState(snapshot.seasonId),scoreText(snapshot.overallScore))
  local vault=snapshot.greatVaultMythicPlus;local vaultProgress=C:FormatState(nil)
  if type(vault)=="table"and vault.currentPeriod==true and type(vault.activities)=="table"then vaultProgress=string.format(L["GREAT_VAULT_PROGRESS"],vault.progress,#vault.activities)end
  if dataStatus=="STALE"then vaultProgress=vaultProgress.." ("..L["WEEKLY_STALE"]..")"end
  summary=summary.."  •  "..string.format(L["GREAT_VAULT_SUMMARY"],vaultProgress)
  C:SetTableView(view,rows,{summary=summary,emptyText=L["NO_MYTHICPLUS"]})
 end
 local function build(parent)return HolyStorm.CharacterUI:CreateTableView(parent,{columns={{id="name",title=L["COLUMN_DUNGEON"],weight=1,minWidth=180,compactWidth=140,truncate=true,renderCell=dungeonCell,onClick=openJournal,tooltip=function(row,_,_,tooltip)tooltip:SetText(row.name);if row.instanceId and EncounterJournal_OpenJournal and not(InCombatLockdown and InCombatLockdown())then tooltip:AddLine(L["OPEN_JOURNAL"],1,1,1,true)end;return true end},{id="bestLevel",title=L["COLUMN_BEST_LEVEL"],width=95,compactWidth=74,align="CENTER",tooltip=bestRunTooltip},{id="rating",title=L["COLUMN_DUNGEON_RATING"],width=112,compactWidth=85,align="RIGHT",tooltip=bestRunTooltip},{id="time",title=L["COLUMN_TIME"],width=86,compactWidth=70,align="RIGHT",tooltip=bestRunTooltip},{id="timed",title=L["COLUMN_IN_TIME"],width=72,compactWidth=56,align="CENTER",renderCell=timedCell,tooltip=bestRunTooltip}},rowHeight=28,headerHeight=26,columnGap=1,emptyText=L["NO_MYTHICPLUS"]})end
 HolyStorm:RegisterCharacterTab("characters",{id="mythicPlus",order=30,label=L["DISPLAY_NAME"],labelKey="MYTHICPLUS_DISPLAY_NAME",icon="Interface\\Icons\\Achievement_ChallengeMode_Gold",blocks={"mythicPlus"},events={"HS_MYTHICPLUS_UPDATED"},build=build,refresh=refresh})
 HolyStorm:RegisterCharacterSummarySection("characters",{id="mythicPlus",order=30,render=function(context)local C=HolyStorm.CharacterUI;local snapshot=C:GetSnapshot(context.characterUUID,"mythicPlus");local valid=type(snapshot)=="table"and snapshot.schemaVersion==5 and snapshot.snapshotVersion==5;local _,_,_,staleReason=C:GetDataStatus(context.characterUUID,"mythicPlus",nil,{data=snapshot});return{label=L["DISPLAY_NAME"],tabId="mythicPlus",value=valid and staleReason~="SEASON"and staleReason~="SEASON_UNKNOWN"and(L["OVERALL_RATING"]..": "..scoreText(snapshot.overallScore))or L["NO_MYTHICPLUS"]}end})
end

do
 local L=locale("RAID_");local baseDifficultyKeys={"LFR","NORMAL","HEROIC","MYTHIC"}
 local function raidKey(name)return type(name)=="string"and name:lower():gsub("[%s%p%c]+","")or nil end
 local function openJournal(row)if row and row.instanceId and not(InCombatLockdown and InCombatLockdown())and EncounterJournal_OpenJournal then pcall(EncounterJournal_OpenJournal,nil,tonumber(row.instanceId))end end
 local function raidCell(cell,_,row)if not cell.icon then cell.icon=cell.frame:CreateTexture(nil,"ARTWORK");cell.icon:SetSize(20,20);cell.icon:SetPoint("LEFT",4,0);cell.text:ClearAllPoints();cell.text:SetPoint("LEFT",28,0);cell.text:SetPoint("RIGHT",-4,0)end;cell.icon:SetTexture(row.icon or"Interface\\Icons\\INV_Sword_27");cell:SetDisplay(row.nameDisplay or row.name,row.name)end
 local function progress(row,key)local lockout=row.weekly[key];if lockout then local killed=tonumber(lockout.killed);local total=tonumber(lockout.total)or tonumber(row.total);if killed~=nil and total~=nil then return string.format("%d/%d",killed,total)end end;return HolyStorm.CharacterUI:FormatState(nil)end
 local function weeklyTooltip(row,key,owner)
  local lockout=row.weekly[key];local rows={};local unknown=HolyStorm.CharacterUI:FormatState(nil)
  if not lockout then rows[1]={cells={row.weeklyCurrent and L["NO_CURRENT_LOCKOUT"]or L["NO_DATA"],unknown},colors={[1]={r=.55,g=.55,b=.55},[2]={r=.55,g=.55,b=.55}}}
  else for _,boss in ipairs(lockout.bosses or{})do local name=boss.name or L["UNKNOWN"];if boss.killed==true then rows[#rows+1]={cells={name,L["BOSS_STATE_KILLED"]},colors={[2]={r=.2,g=1,b=.2}}}elseif boss.killed==false then rows[#rows+1]={cells={name,L["BOSS_STATE_OPEN"]},colors={[2]={r=1,g=.25,b=.25}}}else rows[#rows+1]={cells={name,unknown},colors={[2]={r=.55,g=.55,b=.55}}}end end;if#rows==0 then rows[1]={cells={L["NO_DATA"],unknown},colors={[1]={r=.55,g=.55,b=.55},[2]={r=.55,g=.55,b=.55}}}end end
  local tooltips=HolyStorm.Tooltips;local label=row.weeklyStale and L["WEEKLY_STALE_TOOLTIP"]or L["WEEKLY_TOOLTIP"];return tooltips and tooltips:ShowTable("raid-weekly",owner,{anchor={point="LEFT",relativePoint="RIGHT",x=8,y=0},columns={{align="LEFT"},{align="RIGHT"}},headers={{string.format(label,L["DIFFICULTY_"..key]or key),L["COLUMN_STATE"]}},separator=true,rows=rows})or false
 end
 local function shortDifficulty(key)return key=="MYTHIC"and"M"or key=="HEROIC"and"H"or key=="NORMAL"and"N"or key=="TIMEWALKING"and"TW"or key=="LFR"and"LFR"or"?"end
 local function bestText(snapshot,row)local C=HolyStorm.CharacterUI;local best=C:GetBestProgress(snapshot,row);if best and(tonumber(best.killed)or 0)>0 then return C:ColorDifficulty(best.difficulty,string.format("%s %d/%d",shortDifficulty(best.difficulty),best.killed,best.total))end;return snapshot.catalogReady==true and""or C:FormatState(nil)end
 local function bestSummary(snapshot)local C=HolyStorm.CharacterUI;local best=C:GetBestCurrentRaidProgress(snapshot);if best and(tonumber(best.killed)or 0)>0 then local progress=C:ColorDifficulty(best.difficulty,string.format("%s %d/%d",shortDifficulty(best.difficulty),best.killed,best.total));return string.format(L["BEST_PROGRESS_FORMAT"],best.raidName or C:FormatState(nil),progress)end;return snapshot.catalogReady==true and""or C:FormatState(nil)end
 local function bestTooltip(row,_,_,_,owner)
  local C=HolyStorm.CharacterUI;local rows={};local bestRows=C:BuildRaidBestRows(type(row)=="table"and row.snapshot or nil,row)
  local unknown=C:FormatState(nil)
  for _,boss in ipairs(bestRows)do rows[#rows+1]={cells={boss.bossName or L["UNKNOWN"],boss.difficulty and shortDifficulty(boss.difficulty)or unknown,boss.kills or unknown},colors={[2]=C:GetDifficultyColor(boss.difficulty)}}end
  if#rows==0 then rows[1]={cells={L["NO_DATA"],unknown,unknown}}end
  local tooltips=HolyStorm.Tooltips
   return tooltips and tooltips:ShowTable("raid-best",owner,{anchor={point="LEFT",relativePoint="RIGHT",x=8,y=0},columns={{align="LEFT"},{align="CENTER"},{align="RIGHT"},},headers={{L["COLUMN_BOSS"],L["COLUMN_BEST"],L["COLUMN_KILLS"]}},separator=true,rows=rows})or false
 end
 local function raidTooltip(row,_,_,tooltip,owner)if row.weekly.TIMEWALKING then return weeklyTooltip(row,"TIMEWALKING",owner)end;tooltip:SetText(row.name);if row.instanceId and EncounterJournal_OpenJournal and not(InCombatLockdown and InCombatLockdown())then tooltip:AddLine(L["OPEN_JOURNAL"],1,1,1,true)end;return true end
 local function columns()local result={{id="name",title=L["COLUMN_RAID"],weight=1,minWidth=200,truncate=true,renderCell=raidCell,onClick=openJournal,tooltip=function(row,_,_,tooltip,owner)return raidTooltip(row,nil,nil,tooltip,owner)end}};for _,key in ipairs(baseDifficultyKeys)do local difficultyKey=key;result[#result+1]={id=difficultyKey:lower(),title=L["DIFFICULTY_"..difficultyKey],width=90,compactWidth=68,align="RIGHT",tooltip=function(row,_,_,tooltip,owner)return weeklyTooltip(row,difficultyKey,owner)end}end;result[#result+1]={id="best",title=L["COLUMN_BEST"],width=180,compactWidth=100,align="RIGHT",tooltip=function(row,_,_,tooltip,owner)return bestTooltip(row,nil,nil,nil,owner)end};return result end
 local function refresh(view,context)local C=HolyStorm.CharacterUI;local snapshot,snapshotMeta=C:GetSnapshot(context.characterUUID,"raid");if type(snapshot)~="table"or snapshot.snapshotVersion~=3 or snapshot.catalogReady~=true then C:SetTableView(view,{}, {emptyText=L["NO_RAID"]});return end;local weeklyCurrent=C:GetDataStatus(context.characterUUID,"raid",nil,{data=snapshot,meta=snapshotMeta})=="CURRENT";local rows,byName,byId={},{},{};for _,catalog in ipairs(type(snapshot.raids)=="table"and snapshot.raids or{})do local row={name=catalog.name or C:FormatState(nil),instanceId=catalog.id,icon=catalog.icon,order=catalog.order or#rows+1,weekly={},weeklyCurrent=weeklyCurrent,weeklyStale=not weeklyCurrent,catalogBosses=catalog.bosses or{},total=#(catalog.bosses or{}),catalogReady=snapshot.catalogReady==true,snapshot=snapshot};rows[#rows+1]=row;byName[raidKey(row.name)]=row;byId[tostring(row.instanceId)]=row end;for _,lockout in ipairs(type(snapshot.lockouts)=="table"and snapshot.lockouts or{})do local row=lockout.journalInstanceId and byId[tostring(lockout.journalInstanceId)]or byName[raidKey(lockout.name)];if not row then row={name=lockout.name or C:FormatState(nil),instanceId=lockout.journalInstanceId,order=1000+#rows,weekly={},weeklyCurrent=weeklyCurrent,weeklyStale=not weeklyCurrent,catalogBosses=lockout.bosses or{},total=tonumber(lockout.total),catalogReady=false,snapshot=snapshot};rows[#rows+1]=row;byName[raidKey(row.name)]=row;if row.instanceId then byId[tostring(row.instanceId)]=row end end;local difficulty=C:GetDifficultyById(lockout.difficultyId);if difficulty then row.weekly[difficulty.id]=lockout end end;table.sort(rows,function(a,b)if a.order==b.order then return tostring(a.name)<tostring(b.name)end;return a.order<b.order end);for _,row in ipairs(rows)do for _,key in ipairs(baseDifficultyKeys)do row[key:lower()]=C:ColorDifficulty(key,progress(row,key))end;local timewalking=row.weekly.TIMEWALKING;if timewalking then row.timewalkingText=C:ColorDifficulty("TIMEWALKING","TW "..progress(row,"TIMEWALKING"));row.nameDisplay=row.name.."  "..row.timewalkingText end;row.best=bestText(snapshot,row)end;C:SetTableView(view,rows,{emptyText=L["NO_RAID"]})end
 local function build(parent)return HolyStorm.CharacterUI:CreateTableView(parent,{columns=columns(),rowHeight=27,headerHeight=26,columnGap=1,emptyText=L["NO_RAID"]})end
 HolyStorm:RegisterCharacterTab("characters",{id="raid",order=40,label=L["DISPLAY_NAME"],labelKey="RAID_DISPLAY_NAME",icon="Interface\\Icons\\INV_Sword_27",blocks={"raid"},events={"HS_RAIDLOCKS_UPDATED"},build=build,refresh=refresh})
 HolyStorm:RegisterCharacterSummarySection("characters",{id="raid",order=40,render=function(context)local C=HolyStorm.CharacterUI;local snapshot=C:GetSnapshot(context.characterUUID,"raid");return{label=L["DISPLAY_NAME"],tabId="raid",formatted=type(snapshot)=="table"and snapshot.snapshotVersion==3 and snapshot.catalogReady==true and bestSummary(snapshot)or L["NO_RAID"]}end})
end

do
 local L=locale("DELVES_")
 local function field(value,seen)local C=HolyStorm.CharacterUI;if type(value)=="boolean"then return value and L["YES"]or L["NO"]end;if type(value)~="table"then return C:FormatState(value)end;if value.status=="unknown"then return C:FormatState(nil)end;seen=seen or{};if seen[value]then return C:FormatState(nil)end;seen[value]=true;for _,key in ipairs({"value","count","level","name","progress","threshold","rewardLevel","role","abilities"})do if value[key]~=nil then return field(value[key],seen)end end;if value.id~=nil then return L["PRESENT"]end;return C:FormatState(nil)end
 local function refresh(view,context)
  local C=HolyStorm.CharacterUI;local snapshot=C:GetSnapshot(context.characterUUID,"delves")
  if type(snapshot)~="table"or snapshot.snapshotVersion~=3 or snapshot.schemaVersion~=3 then C:SetTableView(view,{}, {emptyText=L["NO_DELVES"]});return end
  local vault=type(snapshot.greatVaultWorld)=="table"and snapshot.greatVaultWorld or{}
  local rewardState=type(snapshot.greatVault)=="table"and snapshot.greatVault or{}
  local weekCurrent=C:GetDataStatus(context.characterUUID,"delves",nil,{data=snapshot})=="CURRENT"
  local weeklyValue=field(vault.progress)
  if #(vault.activities or{})>0 then weeklyValue=string.format(L["GREAT_VAULT_PROGRESS"],weeklyValue,field(#vault.activities))end
  local weeklyReward=field(rewardState.rewardAvailable)
  local activities=type(vault.activities)=="table"and vault.activities or{}
  local summary=string.format(L["SEASON_STORED"],field(snapshot.seasonNumber))
  if not weekCurrent then summary=summary.." ("..L["WEEKLY_STALE"]..")"end
  local rows={{group=L["GROUP_OVERVIEW"],metric=L["GREAT_VAULT"],value=weeklyValue,details=""},{group=L["GROUP_OVERVIEW"],metric=L["WEEKLY_REWARD"],value=weeklyReward,details=""}}
  for index,activity in ipairs(activities)do rows[#rows+1]={group=L["GROUP_ACTIVITIES"],metric=string.format(L["ACTIVITY"],activity.index or index),value=field(activity.progress),details=string.format(L["ACTIVITY_DETAILS"],field(activity.threshold),field(activity.level),field(activity.rewardLevel))}end
  C:SetTableView(view,rows,{summary=summary,emptyText=L["NO_DELVES"]})
 end
 local function build(parent)return HolyStorm.CharacterUI:CreateTableView(parent,{columns={{id="group",title=L["COLUMN_GROUP"],width=135},{id="metric",title=L["COLUMN_METRIC"],weight=1,minWidth=190},{id="value",title=L["COLUMN_VALUE"],width=130,align="RIGHT"},{id="details",title=L["COLUMN_DETAILS"],weight=.8,minWidth=160}},rowHeight=26,headerHeight=26,columnGap=1,emptyText=L["NO_DELVES"]})end
 HolyStorm:RegisterCharacterTab("characters",{id="delves",order=50,label=L["DISPLAY_NAME"],labelKey="DELVES_DISPLAY_NAME",icon="Interface\\Icons\\INV_Misc_Map_01",blocks={"delves"},events={"HS_DELVES_UPDATED"},build=build,refresh=refresh})
 HolyStorm:RegisterCharacterSummarySection("characters",{id="delves",order=50,render=function(context)local C=HolyStorm.CharacterUI;local snapshot=C:GetSnapshot(context.characterUUID,"delves");if type(snapshot)~="table"or snapshot.snapshotVersion~=3 or snapshot.schemaVersion~=3 then return{label=L["DISPLAY_NAME"],tabId="delves",value=L["NO_DELVES"]}end;local vault=snapshot.greatVaultWorld;local value=type(vault)=="table"and field(vault.progress)or C:FormatState(nil);return{label=L["DISPLAY_NAME"],tabId="delves",value=string.format(L["DELVES_SUMMARY"],field(snapshot.seasonNumber),value)}end})
end
