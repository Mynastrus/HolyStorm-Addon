local HolyStorm=LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local CharacterL=LibStub("AceLocale-3.0"):GetLocale("Holy_Storm_CharacterUI")
local function locale(prefix)return setmetatable({},{__index=function(_,key)return CharacterL[prefix..key]end})end

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
 local function itemName(item)if not item then return nil end;local label=type(item.link)=="string"and item.link:match("|h%[?(.-)%]?|h");return label or item.name or(item.itemId and tostring(item.itemId))end
 local function openItem(row)local link=row.item and row.item.link;if not link then return end;if HandleModifiedItemClick then HandleModifiedItemClick(link)elseif SetItemRef then local payload=link:match("|H([^|]+)|h");if payload then SetItemRef(payload,link,"LeftButton")end end end
 local function itemTooltip(row,_,_,tooltip)local link=row.item and row.item.link;if not link then return end;tooltip:SetHyperlink(link);return true end
 local function iconCell(cell,_,row)if not cell.icon then cell.icon=cell.frame:CreateTexture(nil,"ARTWORK");cell.icon:SetSize(20,20);cell.icon:SetPoint("LEFT",4,0);cell.text:ClearAllPoints();cell.text:SetPoint("LEFT",28,0);cell.text:SetPoint("RIGHT",-4,0)end;cell.icon:SetTexture(row.item and row.item.icon or row.state=="EMPTY"and row.emptyTexture or"Interface\\Icons\\INV_Misc_QuestionMark");cell.icon:Show();cell:SetDisplay(row.slotLabel)end
 local function itemCell(cell,_,row)if row.state=="UNKNOWN"then cell:SetDisplay(HolyStorm.CharacterUI:FormatState(nil));return end;if row.state=="EMPTY"then cell:SetDisplay(L["EMPTY_SLOT"]);return end;local name=itemName(row.item);local link=row.item.link;if link then cell:SetDisplay(link,name,function(short)return HolyStorm.UI.Components:ReplaceHyperlinkLabel(link,short)end)else cell:SetDisplay(name or HolyStorm.CharacterUI:FormatState(nil),name)end end
 local function statusCell(cell,_,row,column)if not cell.statusIcon then cell.statusIcon=cell.frame:CreateTexture(nil,"ARTWORK");cell.statusIcon:SetSize(18,18);cell.statusIcon:SetPoint("CENTER");cell.statusIcon:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")end;local state=row[column.id.."State"];if state==true then cell.statusIcon:SetVertexColor(.2,1,.2,1);cell.statusIcon:Show();cell:SetDisplay("")else cell.statusIcon:Hide();cell:SetDisplay(state==nil and HolyStorm.CharacterUI:FormatState(nil)or"")end end
 local function formatItemLevel(value)local number=tonumber(value);return number and string.format("%.1f",number)or HolyStorm.CharacterUI:FormatState(nil)end
 local function itemLevelSummary(value)return"|cffffd100"..L["ITEM_LEVEL"]..":|r |cff80dfff"..formatItemLevel(value).."|r"end
 local function gemsFor(item)
  if not item then return nil,nil,nil end;local sockets=tonumber(item.sockets);local gems=type(item.gems)=="table"and item.gems or nil;if sockets==nil and gems then sockets=#gems end;if sockets==0 then return"",{},{}end;if sockets==nil then return nil,nil,nil end
  local labels,details,installed={},{},{};for index=1,sockets do local gem=gems and gems[index];if type(gem)=="table"and gem.empty then labels[#labels+1]=L["EMPTY_SOCKET"];details[#details+1]=gem.name or L["EMPTY_SOCKET"]elseif gem~=nil then local id=type(gem)=="table"and gem.itemId or gem;local name=type(gem)=="table"and gem.name or nil;local icon=type(gem)=="table"and gem.icon or nil;labels[#labels+1]=icon and("|T"..icon..":16:16|t")or tostring(id or index);details[#details+1]=name or string.format(L["GEM_ID"],tostring(id or index));installed[#installed+1]=gem else labels[#labels+1]=HolyStorm.CharacterUI:FormatState(nil);details[#details+1]=HolyStorm.CharacterUI:FormatState(nil)end end;return table.concat(labels," "),details,installed
 end
 local function refresh(view,context)
  local C=HolyStorm.CharacterUI;local snapshot=C:GetSnapshot(context.characterUUID,"equipment");if not snapshot then C:SetTableView(view,{}, {emptyText=L["NO_EQUIPMENT"]});return end
  local rows={};for _,slot in ipairs(slots)do local raw=snapshot.slots and snapshot.slots[slot[1]];local state=raw==nil and"UNKNOWN"or raw==false and"EMPTY"or"VALUE";local item=state=="VALUE"and raw or nil;local gems,gemDetails,installedGems=gemsFor(item);local tierState,enchantState;if item then tierState=item.isTier;local enchantId=tonumber(item.enchantId);if enchantId~=nil then enchantState=enchantId>0 end elseif state=="EMPTY"then tierState,enchantState=false,false end;rows[#rows+1]={slotId=slot[1],slotLabel=L[slot[2]],emptyTexture=slot[3],state=state,item=item,itemText=itemName(item),tier="",tierState=tierState,enchant="",enchantState=enchantState,gems=gems or(state=="UNKNOWN"and C:FormatState(nil)or""),gemDetails=gemDetails,installedGems=installedGems,itemLevel=item and C:FormatState(item.itemLevel)or(state=="UNKNOWN"and C:FormatState(nil)or"")}end
  C:SetTableView(view,rows,{summary=itemLevelSummary(snapshot.itemLevel),emptyText=L["NO_EQUIPMENT"]})
 end
 local function build(parent)return HolyStorm.CharacterUI:CreateTableView(parent,{columns={{id="slotLabel",title=L["COLUMN_SLOT"],width=150,compactWidth=105,renderCell=iconCell,onClick=openItem,tooltip=itemTooltip},{id="itemText",title=L["COLUMN_ITEM"],weight=1,minWidth=180,compactWidth=120,truncate=true,renderCell=itemCell,onClick=openItem,tooltip=itemTooltip},{id="tier",title=L["COLUMN_TIER"],width=55,compactWidth=42,align="CENTER",renderCell=statusCell,tooltip=function(row)return row.tierState==true and L["TIER_ITEM"]or nil end},{id="enchant",title=L["COLUMN_ENCHANT"],width=100,compactWidth=72,align="CENTER",renderCell=statusCell,tooltip=function(row)if row.enchantState==nil then return end;if row.enchantState==false then return L["NOT_ENCHANTED"]end;return row.item and(row.item.enchantName or L["ENCHANTED"])or L["ENCHANTED"]end},{id="gems",title=L["COLUMN_GEMS"],width=130,compactWidth=90,align="CENTER",tooltip=function(row,_,_,tooltip)if row.installedGems and#row.installedGems==1 and type(row.installedGems[1])=="table"and row.installedGems[1].link then tooltip:SetHyperlink(row.installedGems[1].link);return true end;if not row.gemDetails or#row.gemDetails==0 then return end;tooltip:SetText(L["COLUMN_GEMS"]);for _,line in ipairs(row.gemDetails)do tooltip:AddLine(line,1,1,1)end;return true end},{id="itemLevel",title=L["COLUMN_ILVL"],width=80,compactWidth=55,align="RIGHT"}},rowHeight=26,headerHeight=26,columnGap=1,emptyText=L["NO_EQUIPMENT"]})end
 HolyStorm:RegisterCharacterTab("characters",{id="equipment",order=20,label=L["DISPLAY_NAME"],labelKey="EQUIPMENT_DISPLAY_NAME",icon="Interface\\Icons\\INV_Helmet_08",blocks={"equipment"},events={"HS_EQUIPMENT_UPDATED"},build=build,refresh=refresh})
 HolyStorm:RegisterCharacterSummarySection("characters",{id="equipment",order=20,render=function(context)local C=HolyStorm.CharacterUI;local snapshot=C:GetSnapshot(context.characterUUID,"equipment");return{label=L["DISPLAY_NAME"],tabId="equipment",value=snapshot and itemLevelSummary(snapshot.itemLevel)or L["NO_EQUIPMENT"]}end})
end

do
 local L=locale("MYTHICPLUS_")
 local function scoreText(value)local score=tonumber(value);if score==nil then return HolyStorm.CharacterUI:FormatState(nil)end;local text=score%1==0 and tostring(score)or string.format("%.1f",score);local color=C_ChallengeMode and C_ChallengeMode.GetDungeonScoreRarityColor and C_ChallengeMode.GetDungeonScoreRarityColor(score);if color then if color.WrapTextInColorCode then return color:WrapTextInColorCode(text)end;if color.r then return string.format("|cff%02x%02x%02x%s|r",math.floor(color.r*255+.5),math.floor(color.g*255+.5),math.floor(color.b*255+.5),text)end end;return text end
 local function durationText(value)local seconds=tonumber(value);if not seconds or seconds<0 then return nil end;seconds=math.floor(seconds+.5);local hours=math.floor(seconds/3600);local minutes=math.floor((seconds%3600)/60);local remainder=seconds%60;if hours>0 then return string.format("%d:%02d:%02d",hours,minutes,remainder)end;return string.format("%d:%02d",minutes,remainder)end
 local function levelText(value)local level=tonumber(value);return level and level>0 and("+"..tostring(level))or nil end
 local function timedText(overTime)if type(overTime)~="boolean"then return HolyStorm.CharacterUI:FormatState(nil)end;return overTime and L["NOT_TIMED"]or L["TIMED"]end
 local function timedCell(cell,_,row)
  if not cell.statusIcon then cell.statusIcon=cell.frame:CreateTexture(nil,"ARTWORK");cell.statusIcon:SetSize(18,18);cell.statusIcon:SetPoint("CENTER")end
  local overtime=row.bestRun and row.bestRun.overTime
  if overtime==false then cell.statusIcon:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready");cell.statusIcon:SetVertexColor(.2,1,.2,1);cell.statusIcon:Show();cell:SetDisplay("")
  elseif overtime==true then cell.statusIcon:SetTexture("Interface\\RaidFrame\\ReadyCheck-NotReady");cell.statusIcon:SetVertexColor(1,.25,.25,1);cell.statusIcon:Show();cell:SetDisplay("")
  else cell.statusIcon:Hide();cell:SetDisplay(HolyStorm.CharacterUI:FormatState(nil))end
 end
 local function dungeonCell(cell,_,row)
  if not cell.icon then cell.icon=cell.frame:CreateTexture(nil,"ARTWORK");cell.icon:SetSize(20,20);cell.icon:SetPoint("LEFT",4,0)end
  cell.text:ClearAllPoints();cell.text:SetPoint("LEFT",row.texture and 28 or 6,0);cell.text:SetPoint("RIGHT",-4,0)
  if row.texture then cell.icon:SetTexture(row.texture);cell.icon:SetTexCoord(0,1,0,1);cell.icon:Show()else cell.icon:Hide()end
  cell:SetDisplay(row.name)
 end
 local function openJournal(row)if row.instanceId and not(InCombatLockdown and InCombatLockdown())and EncounterJournal_OpenJournal then EncounterJournal_OpenJournal(nil,tonumber(row.instanceId))end end
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
  appendRun(rows,L["BEST_RUN"],row.bestRun)
  local affixes={};for _,entry in pairs(type(row.affixScores)=="table"and row.affixScores or{})do if type(entry)=="table"and runHasData(entry)then affixes[#affixes+1]=entry end end
  local rank={TYRANNICAL=1,FORTIFIED=2};table.sort(affixes,function(a,b)local ar,br=rank[a.category]or 3,rank[b.category]or 3;if ar~=br then return ar<br end;return tostring(a.name or a.category or"")<tostring(b.name or b.category or"")end)
  for _,entry in ipairs(affixes)do local label=entry.category and L[entry.category]or entry.name;if type(label)=="string"and label~=""then appendRun(rows,label,entry)end end
  local timer=durationText(row.timeLimit);if timer then rows[#rows+1]={cells={L["DUNGEON_TIMER"],unknown,unknown,timer,unknown},colors={[5]={r=.55,g=.55,b=.55}}}end
  if #rows==0 then return false end
  local tooltips=HolyStorm.Tooltips
  return tooltips and tooltips:ShowTable("mythicplus-best-run",owner,{anchor={point="LEFT",relativePoint="RIGHT",x=8,y=0},columns={{align="LEFT"},{align="CENTER"},{align="RIGHT"},{align="RIGHT"},{align="CENTER"}},headers={{L["RUN"],L["COLUMN_BEST_LEVEL"],L["RUN_RATING"],L["COLUMN_TIME"],L["COLUMN_IN_TIME"]}},separator=true,rows=rows})or false
 end
 local function currentSeasonId()
  local api=C_MythicPlus;if not api or type(api.GetCurrentSeason)~="function"then return nil end
  local ok,value=pcall(api.GetCurrentSeason);return ok and tonumber(value)or nil
 end
 local function isCurrentSeason(snapshot)
  local stored=type(snapshot)=="table"and tonumber(snapshot.seasonId);local current=currentSeasonId()
  return stored~=nil and stored>0 and current~=nil and stored==current
 end
 local function refresh(view,context)
  local C=HolyStorm.CharacterUI;local snapshot=C:GetSnapshot(context.characterUUID,"mythicPlus")
  if not snapshot or next(snapshot)==nil or not isCurrentSeason(snapshot)then C:SetTableView(view,{}, {summary="",emptyText=L["NO_MYTHICPLUS"]});return end
  local rows={}
  for _,dungeon in pairs(type(snapshot.dungeons)=="table"and snapshot.dungeons or{})do if type(dungeon)=="table"then
   local best=type(dungeon.bestRun)=="table"and dungeon.bestRun or nil
   rows[#rows+1]={name=dungeon.name or C:FormatState(nil),instanceId=dungeon.instanceId,challengeMapId=dungeon.challengeMapId,texture=dungeon.texture,bestRun=best,affixScores=dungeon.affixScores,timeLimit=dungeon.timeLimit,bestLevel=best and levelText(best.level)or C:FormatState(nil),rating=snapshot.scoreDataReady==false and C:FormatState(nil)or scoreText(dungeon.score),time=best and durationText(best.durationSec)or C:FormatState(nil)}
  end end
  table.sort(rows,function(a,b)if a.name==b.name then return(tonumber(a.challengeMapId)or 0)<(tonumber(b.challengeMapId)or 0)end;return tostring(a.name)<tostring(b.name)end)
  C:SetTableView(view,rows,{summary=string.format(L["SEASON_SUMMARY"],C:FormatState(snapshot.seasonId),scoreText(snapshot.overallScore)),emptyText=L["NO_MYTHICPLUS"]})
 end
 local function build(parent)return HolyStorm.CharacterUI:CreateTableView(parent,{columns={{id="name",title=L["COLUMN_DUNGEON"],weight=1,minWidth=180,compactWidth=140,truncate=true,renderCell=dungeonCell,onClick=openJournal,tooltip=function(row,_,_,tooltip)tooltip:SetText(row.name);tooltip:AddLine(L["OPEN_JOURNAL"],1,1,1,true);return true end},{id="bestLevel",title=L["COLUMN_BEST_LEVEL"],width=95,compactWidth=74,align="CENTER",tooltip=bestRunTooltip},{id="rating",title=L["COLUMN_DUNGEON_RATING"],width=112,compactWidth=85,align="RIGHT",tooltip=bestRunTooltip},{id="time",title=L["COLUMN_TIME"],width=86,compactWidth=70,align="RIGHT",tooltip=bestRunTooltip},{id="timed",title=L["COLUMN_IN_TIME"],width=72,compactWidth=56,align="CENTER",renderCell=timedCell,tooltip=bestRunTooltip}},rowHeight=28,headerHeight=26,columnGap=1,emptyText=L["NO_MYTHICPLUS"]})end
 HolyStorm:RegisterCharacterTab("characters",{id="mythicPlus",order=30,label=L["DISPLAY_NAME"],labelKey="MYTHICPLUS_DISPLAY_NAME",icon="Interface\\Icons\\Achievement_ChallengeMode_Gold",blocks={"mythicPlus"},events={"HS_MYTHICPLUS_UPDATED"},build=build,refresh=refresh})
 HolyStorm:RegisterCharacterSummarySection("characters",{id="mythicPlus",order=30,render=function(context)local snapshot=HolyStorm.CharacterUI:GetSnapshot(context.characterUUID,"mythicPlus");local current=snapshot and isCurrentSeason(snapshot);return{label=L["DISPLAY_NAME"],tabId="mythicPlus",value=current and(L["OVERALL_RATING"]..": "..scoreText(snapshot.overallScore))or L["NO_MYTHICPLUS"]}end})
end

do
 local L=locale("RAID_");local baseDifficultyKeys={"LFR","NORMAL","HEROIC","MYTHIC"}
 local function raidKey(name)return type(name)=="string"and name:lower():gsub("[%s%p%c]+","")or nil end
 local function openJournal(row)if row.instanceId and not(InCombatLockdown and InCombatLockdown())and EncounterJournal_OpenJournal then EncounterJournal_OpenJournal(nil,tonumber(row.instanceId))end end
 local function raidCell(cell,_,row)if not cell.icon then cell.icon=cell.frame:CreateTexture(nil,"ARTWORK");cell.icon:SetSize(20,20);cell.icon:SetPoint("LEFT",4,0);cell.text:ClearAllPoints();cell.text:SetPoint("LEFT",28,0);cell.text:SetPoint("RIGHT",-4,0)end;cell.icon:SetTexture(row.icon or"Interface\\Icons\\INV_Sword_27");cell:SetDisplay(row.nameDisplay or row.name,row.name)end
 local function progress(row,key)local lockout=row.weekly[key];if lockout then return string.format("%d/%d",tonumber(lockout.killed)or 0,tonumber(lockout.total)or row.total or 0)end;return HolyStorm.CharacterUI:FormatState(nil)end
 local function weeklyTooltip(row,key,owner)
  local lockout=row.weekly[key];local rows={};local unknown=HolyStorm.CharacterUI:FormatState(nil)
  if not lockout then rows[1]={cells={L["NO_CURRENT_LOCKOUT"],unknown},colors={[1]={r=.55,g=.55,b=.55},[2]={r=.55,g=.55,b=.55}}}
  else for _,boss in ipairs(lockout.bosses or{})do local name=boss.name or L["UNKNOWN"];if boss.killed==true then rows[#rows+1]={cells={name,L["BOSS_STATE_KILLED"]},colors={[2]={r=1,g=.2,b=.2}}}elseif boss.killed==false then rows[#rows+1]={cells={name,L["BOSS_STATE_OPEN"]},colors={[2]={r=.2,g=1,b=.2}}}else rows[#rows+1]={cells={name,unknown},colors={[2]={r=.55,g=.55,b=.55}}}end end;if#rows==0 then rows[1]={cells={L["NO_DATA"],unknown},colors={[1]={r=.55,g=.55,b=.55},[2]={r=.55,g=.55,b=.55}}}end end
  local tooltips=HolyStorm.Tooltips;return tooltips and tooltips:ShowTable("raid-weekly",owner,{anchor={point="LEFT",relativePoint="RIGHT",x=8,y=0},columns={{align="LEFT"},{align="RIGHT"}},headers={{string.format(L["WEEKLY_TOOLTIP"],L["DIFFICULTY_"..key]or key),L["COLUMN_STATE"]}},separator=true,rows=rows})or false
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
 local function raidTooltip(row,_,_,tooltip,owner)if row.weekly.TIMEWALKING then return weeklyTooltip(row,"TIMEWALKING",owner)end;tooltip:SetText(row.name);tooltip:AddLine(L["OPEN_JOURNAL"],1,1,1,true);return true end
 local function columns()local result={{id="name",title=L["COLUMN_RAID"],weight=1,minWidth=200,truncate=true,renderCell=raidCell,onClick=openJournal,tooltip=function(row,_,_,tooltip,owner)return raidTooltip(row,nil,nil,tooltip,owner)end}};for _,key in ipairs(baseDifficultyKeys)do local difficultyKey=key;result[#result+1]={id=difficultyKey:lower(),title=L["DIFFICULTY_"..difficultyKey],width=90,compactWidth=68,align="RIGHT",tooltip=function(row,_,_,tooltip,owner)return weeklyTooltip(row,difficultyKey,owner)end}end;result[#result+1]={id="best",title=L["COLUMN_BEST"],width=180,compactWidth=100,align="RIGHT",tooltip=function(row,_,_,tooltip,owner)return bestTooltip(row,nil,nil,nil,owner)end};return result end
 local function refresh(view,context)local C=HolyStorm.CharacterUI;local snapshot=C:GetSnapshot(context.characterUUID,"raid");if not snapshot then C:SetTableView(view,{}, {emptyText=L["NO_RAID"]});return end;local rows,byName,byId={},{},{};for _,catalog in ipairs(type(snapshot.raids)=="table"and snapshot.raids or{})do local row={name=catalog.name or C:FormatState(nil),instanceId=catalog.id,icon=catalog.icon,order=catalog.order or#rows+1,weekly={},catalogBosses=catalog.bosses or{},total=#(catalog.bosses or{}),catalogReady=snapshot.catalogReady==true,snapshot=snapshot};rows[#rows+1]=row;byName[raidKey(row.name)]=row;byId[tostring(row.instanceId)]=row end;for _,lockout in ipairs(type(snapshot.lockouts)=="table"and snapshot.lockouts or{})do local row=lockout.journalInstanceId and byId[tostring(lockout.journalInstanceId)]or byName[raidKey(lockout.name)];if not row then row={name=lockout.name or C:FormatState(nil),instanceId=lockout.journalInstanceId,order=1000+#rows,weekly={},catalogBosses=lockout.bosses or{},total=tonumber(lockout.total),catalogReady=false,snapshot=snapshot};rows[#rows+1]=row;byName[raidKey(row.name)]=row;if row.instanceId then byId[tostring(row.instanceId)]=row end end;local difficulty=C:GetDifficultyById(lockout.difficultyId);if difficulty then row.weekly[difficulty.id]=lockout end end;table.sort(rows,function(a,b)if a.order==b.order then return tostring(a.name)<tostring(b.name)end;return a.order<b.order end);for _,row in ipairs(rows)do for _,key in ipairs(baseDifficultyKeys)do row[key:lower()]=C:ColorDifficulty(key,progress(row,key))end;local timewalking=row.weekly.TIMEWALKING;if timewalking then row.timewalkingText=C:ColorDifficulty("TIMEWALKING","TW "..progress(row,"TIMEWALKING"));row.nameDisplay=row.name.."  "..row.timewalkingText end;row.best=bestText(snapshot,row)end;C:SetTableView(view,rows,{emptyText=L["NO_RAID"]})end
 local function build(parent)return HolyStorm.CharacterUI:CreateTableView(parent,{columns=columns(),rowHeight=27,headerHeight=26,columnGap=1,emptyText=L["NO_RAID"]})end
 HolyStorm:RegisterCharacterTab("characters",{id="raid",order=40,label=L["DISPLAY_NAME"],labelKey="RAID_DISPLAY_NAME",icon="Interface\\Icons\\INV_Sword_27",blocks={"raid"},events={"HS_RAIDLOCKS_UPDATED"},build=build,refresh=refresh})
 HolyStorm:RegisterCharacterSummarySection("characters",{id="raid",order=40,render=function(context)local C=HolyStorm.CharacterUI;local snapshot=C:GetSnapshot(context.characterUUID,"raid");return{label=L["DISPLAY_NAME"],tabId="raid",formatted=snapshot and bestSummary(snapshot)or L["NO_RAID"]}end})
end

do
 local L=locale("DELVES_")
 local function field(value,seen)local C=HolyStorm.CharacterUI;if type(value)=="boolean"then return value and L["YES"]or L["NO"]end;if type(value)~="table"then return C:FormatState(value)end;if value.status=="unknown"then return C:FormatState(nil)end;seen=seen or{};if seen[value]then return C:FormatState(nil)end;seen[value]=true;for _,key in ipairs({"value","count","level","name","progress","threshold","rewardLevel","role","abilities"})do if value[key]~=nil then return field(value[key],seen)end end;if value.id~=nil then return L["PRESENT"]end;return C:FormatState(nil)end
 local function refresh(view,context)local C=HolyStorm.CharacterUI;local snapshot=C:GetSnapshot(context.characterUUID,"delves");if not snapshot then C:SetTableView(view,{}, {emptyText=L["NO_DELVES"]});return end;local activities=type(snapshot.activities)=="table"and snapshot.activities or{};local weeklyProgress=field(snapshot.weeklyProgress);if snapshot.weeklyProgress~=nil and#activities>0 then weeklyProgress=string.format(L["GREAT_VAULT_PROGRESS"],weeklyProgress,field(#activities))end;local companion=type(snapshot.companion)=="table"and snapshot.companion or{};local rows={{group=L["GROUP_OVERVIEW"],metric=L["GREAT_VAULT"],value=weeklyProgress,details=""},{group=L["GROUP_OVERVIEW"],metric=L["WEEKLY_REWARD"],value=field(snapshot.weeklyRewardAvailable),details=""},{group=L["GROUP_OVERVIEW"],metric=L["BOUNTIFUL"],value=field(snapshot.bountiful),details=""},{group=L["GROUP_OVERVIEW"],metric=L["NEMESIS"],value=field(snapshot.nemesis),details=""},{group=L["GROUP_RESOURCES"],metric=L["TREASURE_MAP"],value=field(snapshot.treasureMap),details=""},{group=L["GROUP_RESOURCES"],metric=L["CREST_PROGRESS"],value=field(snapshot.crestProgress),details=""},{group=L["GROUP_RESOURCES"],metric=L["LIMITED_REWARDS"],value=field(snapshot.limitedRewards),details=""},{group=L["GROUP_COMPANION"],metric=L["COMPANION_LEVEL"],value=field(companion.level),details=""},{group=L["GROUP_COMPANION"],metric=L["COMPANION_ROLE"],value=field(companion.role),details=""},{group=L["GROUP_COMPANION"],metric=L["COMPANION_ABILITIES"],value=field(companion.abilities),details=""},{group=L["GROUP_COMPANION"],metric=L["FLUTE"],value=field(snapshot.flute),details=""}};for index,activity in ipairs(activities)do rows[#rows+1]={group=L["GROUP_ACTIVITIES"],metric=string.format(L["ACTIVITY"],activity.index or index),value=field(activity.progress),details=string.format(L["ACTIVITY_DETAILS"],field(activity.threshold),field(activity.level),field(activity.rewardLevel))}end;C:SetTableView(view,rows,{summary=string.format(L["SEASON"],field(snapshot.seasonNumber)),emptyText=L["NO_DELVES"]})end
 local function build(parent)return HolyStorm.CharacterUI:CreateTableView(parent,{columns={{id="group",title=L["COLUMN_GROUP"],width=135},{id="metric",title=L["COLUMN_METRIC"],weight=1,minWidth=190},{id="value",title=L["COLUMN_VALUE"],width=130,align="RIGHT"},{id="details",title=L["COLUMN_DETAILS"],weight=.8,minWidth=160}},rowHeight=26,headerHeight=26,columnGap=1,emptyText=L["NO_DELVES"]})end
 HolyStorm:RegisterCharacterTab("characters",{id="delves",order=50,label=L["DISPLAY_NAME"],labelKey="DELVES_DISPLAY_NAME",icon="Interface\\Icons\\INV_Misc_Map_01",blocks={"delves"},events={"HS_DELVES_UPDATED"},build=build,refresh=refresh})
 HolyStorm:RegisterCharacterSummarySection("characters",{id="delves",order=50,render=function(context)local snapshot=HolyStorm.CharacterUI:GetSnapshot(context.characterUUID,"delves");return{label=L["DISPLAY_NAME"],tabId="delves",value=snapshot and(L["GREAT_VAULT"]..": "..field(snapshot.weeklyProgress))or L["NO_DELVES"]}end})
end
