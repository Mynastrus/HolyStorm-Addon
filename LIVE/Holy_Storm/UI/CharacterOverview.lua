local addonVersion="1.4.0"
local HolyStorm=LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local L=LibStub("AceLocale-3.0"):GetLocale("Holy_Storm_CharacterUI")
local Page=HolyStorm:RegisterRequiredModule("CharacterOverview")
HolyStorm:ApplyModuleMetadata(Page,{displayName=L["WINDOW_TITLE"],internalName="characterOverview",version=addonVersion,category="required",description=L["WINDOW_TITLE"],permissions={"player-read"},dependencies={"core","ui"},enabledByDefault=true})
local C=HolyStorm.CharacterUI

local blocksByTab={summary={"identity","equipment","mythicPlus","raid","delves","stats"},equipment={"equipment"},mythicPlus={"mythicPlus"},raid={"raid"},delves={"delves"},stats={"stats"},twinks={"identity"},achievements={}}
local tabByEvent={HS_CHARACTER_UPDATED="summary",HS_EQUIPMENT_UPDATED="equipment",HS_MYTHICPLUS_UPDATED="mythicPlus",HS_RAIDLOCKS_UPDATED="raid",HS_DELVES_UPDATED="delves",HS_STATS_UPDATED="stats",HS_TWINKS_UPDATED="twinks",HS_ACCOUNT_MAIN_CHANGED="twinks",HS_GUILD_MAIN_CHANGED="twinks",HS_TWINK_VISIBILITY_CHANGED="twinks",HS_ROSTER_UPDATED="summary"}
local characterScopedEvents={HS_CHARACTER_UPDATED=true,HS_EQUIPMENT_UPDATED=true,HS_MYTHICPLUS_UPDATED=true,HS_RAIDLOCKS_UPDATED=true,HS_DELVES_UPDATED=true,HS_STATS_UPDATED=true}
local slotDefinitions

local function value(v)return v==nil and L["UNKNOWN"]or tostring(v)end
local function number(v,format)return tonumber(v)and string.format(format or"%.1f",tonumber(v))or L["UNKNOWN"]end
local function dateValue(timestamp)return timestamp and date("%d.%m.%Y %H:%M",timestamp)or nil end
local function classColor(classFile)return RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]or NORMAL_FONT_COLOR or{r=1,g=1,b=1}end
local function hyperlink(kind,id,label,difficulty)local text=difficulty and C:ColorDifficulty(difficulty,label)or("|cff3fc7eb"..tostring(label).."|r");return id and("|Hhscharacter:"..kind..":"..tostring(id).."|h"..text.."|h")or text end
local function linkedIcon(link,texture)
 local payload=link and link:match("|H([^|]+)|h");return payload and texture and("|H"..payload.."|h|T"..texture..":18:18|t|h")or(texture and("|T"..texture..":18:18|t")or"")
end
local function linkedText(link,label)
 local payload=link and link:match("|H([^|]+)|h");return payload and("|H"..payload.."|h"..tostring(label).."|h")or tostring(label or"")
end
local function gemDisplay(gem,itemLink)
 if type(gem)=="table"and gem.empty then return linkedText(itemLink,gem.name or L["EMPTY_SOCKET"])end
 local itemId=type(gem)=="table"and gem.itemId or gem;local storedName=type(gem)=="table"and gem.name;local storedLink=type(gem)=="table"and gem.link;local storedIcon=type(gem)=="table"and gem.icon
 local name,link,_,_,_,_,_,_,_,icon;if GetItemInfo then name,link,_,_,_,_,_,_,_,icon=GetItemInfo(storedLink or itemId)end;name=name or storedName;link=link or storedLink;icon=icon or storedIcon or(C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(itemId))
 if not name and itemId and C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(itemId)end
 if not link and itemId then link="|Hitem:"..tostring(itemId).."|h|cff3fc7eb["..tostring(name or string.format(L["GEM_ID"],itemId)).."]|r|h"end
 local iconText=linkedIcon(link,icon);return(iconText~=""and(iconText.." ")or"")..(link or name or"")
end
local function tableRow(cells,columns,style,maxWidth)return{cells=cells,columns=columns,style=style,maxWidth=maxWidth}end
local equipmentColumns={{width=.18},{width=.35},{width=.08},{width=.12},{width=.18},{width=.09,align="RIGHT"}}
local mythicColumns={{width=.36},{width=.11,align="RIGHT"},{width=.13,align="RIGHT"},{width=.11,align="RIGHT"},{width=.13,align="RIGHT"},{width=.16,align="RIGHT"}}
local mythicSummaryColumns={{width=.25},{width=.25},{width=.25},{width=.25}}
local raidColumns={{width=.38},{width=.10,align="RIGHT"},{width=.12,align="RIGHT"},{width=.12,align="RIGHT"},{width=.12,align="RIGHT"},{width=.16,align="RIGHT"}}
local statsColumns={{width=.42},{width=.24,align="RIGHT"},{width=.34,align="RIGHT"}}
local twinkColumns={{width=.42},{width=.14},{width=.08,align="RIGHT"},{width=.15},{width=.21}}
local tabVisuals={summary={icon="Interface\\Icons\\Achievement_Character_Human_Male"},equipment={icon="Interface\\Icons\\INV_Helmet_08"},mythicPlus={icon="Interface\\Icons\\Achievement_ChallengeMode_Gold"},raid={icon="Interface\\Icons\\INV_Sword_27"},delves={icon="Interface\\Icons\\INV_Misc_Map_01"},stats={icon="Interface\\Icons\\INV_Misc_Note_03"},twinks={icon="Interface\\Icons\\Achievement_GuildPerk_EverybodysFriend"}}
local panelBackdrop={bgFile="Interface\\Buttons\\WHITE8x8",edgeFile="Interface\\Buttons\\WHITE8x8",edgeSize=1}
local function stylePanel(frame,r,g,b,a,br,bg,bb,ba)if frame.SetBackdrop then frame:SetBackdrop(panelBackdrop);frame:SetBackdropColor(r or.025,g or.035,b or.05,a or.94);frame:SetBackdropBorderColor(br or.32,bg or.24,bb or.08,ba or.9)end end

function C:CreateTextView(parent)
 local frame=CreateFrame("Frame",nil,parent,"BackdropTemplate");frame:SetAllPoints();stylePanel(frame,.018,.027,.04,.96,.25,.19,.07,.9)
 local heading=frame:CreateFontString(nil,"OVERLAY","GameFontHighlightLarge");heading:Hide()
 local status=frame:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");status:SetPoint("TOPRIGHT",-12,-8);status:SetJustifyH("RIGHT");status:SetTextColor(.65,.65,.65);status:Hide()
 local scroll=CreateFrame("ScrollFrame",nil,frame,"UIPanelScrollFrameTemplate");scroll:SetPoint("TOPLEFT",8,-8);scroll:SetPoint("BOTTOMRIGHT",-30,8)
 local content=CreateFrame("Frame",nil,scroll);content:SetSize(1,1);scroll:SetScrollChild(content)
 local view={frame=frame,heading=heading,status=status,scroll=scroll,content=content,rows={}}
 scroll:SetScript("OnSizeChanged",function()C:LayoutTextView(view)end)
 return view
end
function C:LayoutTextView(view)
 if not view or not view.scroll then return end
 local width=math.max(1,(view.scroll:GetWidth()or 1)-14);view.content:SetWidth(width)
 local y=4
 for _,row in ipairs(view.rows or{})do
  if row:IsShown()then
   row:SetWidth(width);local textHeight=16
   if row.cellsData then
    local tableWidth=math.min(width,row.maxWidth or width);local x=0
    for index,column in ipairs(row.columns)do local cell=row.cells[index];local cellWidth=index==#row.columns and(tableWidth-x)or math.floor(tableWidth*column.width);cell:ClearAllPoints();cell:SetPoint("TOPLEFT",row,"TOPLEFT",x+8,-4);cell:SetWidth(math.max(1,cellWidth-16));cell:SetJustifyH(column.align or"LEFT");cell:SetJustifyV(row.verticalCenter and"MIDDLE"or"TOP");textHeight=math.max(textHeight,math.ceil(cell:GetStringHeight()or 16));x=x+cellWidth end
   else row.text:SetWidth(math.max(1,width-16));textHeight=math.max(16,math.ceil(row.text:GetStringHeight()or 16))end
   local height=row.blank and 10 or math.max(row.minHeight or 0,textHeight+8)
   row:SetHeight(height);row:ClearAllPoints();row:SetPoint("TOPLEFT",view.content,"TOPLEFT",0,-y);y=y+height
  end
 end
 view.content:SetHeight(math.max(1,y+4))
end
function C:AcquireTextRow(view,index)
 local row=view.rows[index];if row then return row end
 row=CreateFrame("Frame",nil,view.content);local background=row:CreateTexture(nil,"BACKGROUND");background:SetAllPoints();background:SetColorTexture(1,1,1,.035);row.background=background
 local line=row:CreateFontString(nil,"OVERLAY","GameFontHighlight");line:SetPoint("TOPLEFT",8,-4);line:SetJustifyH("LEFT");line:SetJustifyV("TOP");line:SetWordWrap(true);if line.SetNonSpaceWrap then line:SetNonSpaceWrap(false)end;row.text=line
 if line.SetHyperlinksEnabled then line:SetHyperlinksEnabled(true);line:SetScript("OnHyperlinkClick",function(_,link,_,button)C:HandleLink(link,button)end);line:SetScript("OnHyperlinkEnter",function(_,link)C:ShowLinkTooltip(line,link)end);line:SetScript("OnHyperlinkLeave",function()GameTooltip:Hide()end)end
 view.rows[index]=row;return row
end
function C:AcquireTableCell(row,index)
 local cell=row.cells[index];if cell then return cell end
 cell=row:CreateFontString(nil,"OVERLAY","GameFontHighlight");cell:SetJustifyV("TOP");cell:SetWordWrap(true);if cell.SetNonSpaceWrap then cell:SetNonSpaceWrap(false)end
 if cell.SetHyperlinksEnabled then cell:SetHyperlinksEnabled(true);cell:SetScript("OnHyperlinkClick",function(_,link,_,button)C:HandleLink(link,button)end);cell:SetScript("OnHyperlinkEnter",function(_,link)C:ShowLinkTooltip(cell,link)end);cell:SetScript("OnHyperlinkLeave",function()GameTooltip:Hide()end)end
 row.cells[index]=cell;return cell
end
function C:SetView(view,heading,lines,status,meta,styles)
 if view.heading then view.heading:SetText("");view.heading:Hide()end;lines=lines or{};styles=styles or{}
 for index,entry in ipairs(lines)do
  local row=self:AcquireTextRow(view,index);local tableEntry=type(entry)=="table"and entry.cells;local style=type(entry)=="table"and entry.style or styles[index];row.blank=entry=="";row.cellsData=tableEntry and entry.cells or nil;row.columns=tableEntry and entry.columns or nil;row.maxWidth=tableEntry and entry.maxWidth or nil;row.minHeight=type(entry)=="table"and entry.minHeight or nil;row.verticalCenter=type(entry)=="table"and entry.verticalCenter or nil;row.cells=row.cells or{}
  row.text:SetShown(not tableEntry);row.text:SetText(tableEntry and""or entry)
  for cellIndex,cellText in ipairs(row.cellsData or{})do local cell=self:AcquireTableCell(row,cellIndex);cell:SetText(cellText or"");cell:SetFontObject(style=="header"and"GameFontNormal"or style=="summary"and"GameFontNormalLarge"or"GameFontHighlight");cell:SetTextColor((style=="header"or style=="summary")and 1 or 1,(style=="header"or style=="summary")and .82 or 1,(style=="header"or style=="summary")and 0 or 1);cell:Show()end
  for cellIndex=#(row.cellsData or{})+1,#row.cells do row.cells[cellIndex]:Hide()end
  row.text:SetFontObject(style=="section"and"GameFontNormalLarge"or style=="header"and"GameFontNormal"or style=="muted"and"GameFontDisable"or"GameFontHighlight")
  if style=="accent"or style=="header"then row.text:SetTextColor(1,.82,0)elseif style=="muted"then row.text:SetTextColor(.65,.65,.65)else row.text:SetTextColor(1,1,1)end
  row.background:SetShown(not row.blank);row.background:SetAlpha(style=="header"and .32 or style=="summary"and .22 or(index%2==0 and .8 or .35));row:Show()
 end
 for index=#lines+1,#view.rows do view.rows[index]:Hide()end
 self:LayoutTextView(view);if C_Timer and C_Timer.After then C_Timer.After(0,function()if view.frame:IsShown()then C:LayoutTextView(view)end end)end
 local statusText=status and L["STATUS_"..status]or"";if meta and meta.updatedAt then statusText=statusText..(statusText~=""and"  •  "or"")..string.format(L["LAST_UPDATED"],dateValue(meta.updatedAt))end;view.status:SetText(statusText)
end
function C:HandleLink(link,button)
 local kind,id=link:match("^hscharacter:([^:]+):(.+)$");if kind=="tab"then self:SelectTab(id)elseif kind=="character"then self:OpenCharacter(id,"summary")elseif kind=="journal"then self:OpenJournal(tonumber(id))end
 if link:match("^item:")then if SetItemRef then SetItemRef(link,link,button or"LeftButton")elseif HandleModifiedItemClick then HandleModifiedItemClick(link)end end
end
function C:ShowLinkTooltip(owner,link)
 GameTooltip:SetOwner(owner,"ANCHOR_CURSOR")
 if link:match("^item:")then GameTooltip:SetHyperlink(link)
 else local kind,id=link:match("^hscharacter:([^:]+):(.+)$");if kind=="weekly"then self:ShowWeeklyRaidTooltip(tonumber(id:match("^(%d+)")),id:match(":(.+)$"))elseif kind=="best"then self:ShowRaidBestTooltip(tonumber(id))elseif kind=="summarybest"then self:PopulateRaidBestTooltip(self.summaryRaidSnapshot)elseif kind=="enchant"then GameTooltip:SetText(L["COLUMN_ENCHANT"]);GameTooltip:AddLine(string.format(L["ENCHANTMENT_ID"],id),1,1,1,true)elseif kind=="journal"then GameTooltip:SetText(L["COLUMN_RAID"]);GameTooltip:AddLine(EncounterJournal_OpenJournal and L["OPEN_JOURNAL"]or L["JOURNAL_UNAVAILABLE"],1,1,1,true)elseif kind=="teleport"then GameTooltip:SetText(L["COLUMN_DUNGEON"]);GameTooltip:AddLine(L["TELEPORT_UNAVAILABLE"],1,1,1,true)elseif kind=="character"then GameTooltip:SetText(L["WINDOW_TITLE"])end end
 GameTooltip:Show()
end
function C:OpenJournal(instanceId,difficultyId)
 if InCombatLockdown and InCombatLockdown()then return false end
 if EncounterJournal_OpenJournal and instanceId then EncounterJournal_OpenJournal(difficultyId,instanceId);return true end;return false
end
function C:ShowWeeklyRaidTooltip(index,difficulty)
 local row=self.raidRows and self.raidRows[index];local lockout=row and row.weekly and row.weekly[difficulty];GameTooltip:SetText(string.format(L["WEEKLY_TOOLTIP"],L["DIFFICULTY_"..difficulty]or difficulty))
 if not lockout then GameTooltip:AddLine(L["NO_DATA"],.7,.7,.7);return end
 for _,boss in ipairs(lockout.bosses or{})do GameTooltip:AddLine(string.format(boss.killed and L["BOSS_KILLED"]or L["BOSS_OPEN"],boss.name or L["UNKNOWN"]),boss.killed and .2 or .7,boss.killed and 1 or .7,boss.killed and .2 or .7)end
end
function C:PopulateRaidBestTooltip(snapshot,raidName)
 GameTooltip:SetText(L["BEST_TOOLTIP"]);local shown=0
 for _,boss in ipairs(self:BuildRaidBestRows(snapshot))do if not raidName or not boss.raidName or boss.raidName==raidName then local short=boss.difficulty=="MYTHIC"and"M"or boss.difficulty=="HEROIC"and"H"or boss.difficulty=="NORMAL"and"N"or"LFR";GameTooltip:AddLine(string.format(L["BEST_ROW"],self:ColorDifficulty(boss.difficulty,short),boss.bossName,boss.kills));shown=shown+1 end end
 if shown==0 then GameTooltip:AddLine(L["NO_DATA"],.7,.7,.7)end
end
function C:ShowRaidBestTooltip(index)local row=self.raidRows and self.raidRows[index];return self:PopulateRaidBestTooltip(self.currentRaidSnapshot,row and row.name)end

local function statusFor(guid,block)local status,meta=C:GetDataStatus(guid,block);return status,meta end
local function blocked(view,definition)
 local ok,reason=C:CanUseTab(definition);if ok then return false end;C:SetView(view,L[definition.labelKey],{reason=="PERMISSION"and L["PERMISSION_DENIED"]or L["MODULE_DISABLED"]});return true
end
local function summary(view,context,definition)
 local lines={L["SUMMARY_IDENTITY"],string.format("  %s — %s %s",context.fullName or context.name or context.characterUUID,L["LEVEL"],value(context.level))}
 local equipment=C:GetSnapshot(context.characterUUID,"equipment");lines[#lines+1]="";lines[#lines+1]=hyperlink("tab","equipment",L["SUMMARY_EQUIPMENT"]);lines[#lines+1]="  "..(equipment and(L["ITEM_LEVEL"]..": "..number(equipment.itemLevel))or L["NO_EQUIPMENT"])
 local mythic=C:GetSnapshot(context.characterUUID,"mythicPlus");lines[#lines+1]="";lines[#lines+1]=hyperlink("tab","mythicPlus",L["SUMMARY_MYTHICPLUS"]);lines[#lines+1]="  "..(mythic and(L["RATING"]..": "..number(mythic.overallScore))or L["NO_MYTHICPLUS"])
 local raid=C:GetSnapshot(context.characterUUID,"raid");local best=raid and C:GetBestProgress(raid);C.summaryRaidSnapshot=raid;lines[#lines+1]="";lines[#lines+1]=hyperlink("tab","raid",L["SUMMARY_RAID"]);lines[#lines+1]="  "..(best and hyperlink("summarybest","all",string.format("%s %d/%d",best.difficulty,best.killed,best.total),best.difficulty)or L["NO_RAID"])
 local delves=C:GetSnapshot(context.characterUUID,"delves");lines[#lines+1]="";lines[#lines+1]=hyperlink("tab","delves",L["SUMMARY_DELVES"]);lines[#lines+1]="  "..(delves and(L["WEEKLY_PROGRESS"]..": "..value(delves.weeklyProgress))or L["NO_DELVES"])
 local account=context.accountUUID and HolyStorm.TwinkCore:GetAccount(context.accountUUID);local count=account and HolyStorm.Utils.TableCount(account.characters)or 0;lines[#lines+1]="";lines[#lines+1]=hyperlink("tab","twinks",L["SUMMARY_TWINKS"]);lines[#lines+1]="  "..(count>0 and string.format(L["CHARACTER_COUNT"],count)or L["NO_TWINKS"])
 C:SetView(view,L[definition.labelKey],lines,nil,nil,{[1]="section",[4]="section",[7]="section",[10]="section",[13]="section",[16]="section"})
end
local function equipment(view,context,definition)
 if blocked(view,definition)then return end;local snapshot,meta=C:GetSnapshot(context.characterUUID,"equipment");local status=statusFor(context.characterUUID,"equipment");if not snapshot then C:SetView(view,L[definition.labelKey],{L["NO_EQUIPMENT"]},status);return end
 slotDefinitions=slotDefinitions or{{INVSLOT_HEAD,"SLOT_HEAD"},{INVSLOT_NECK,"SLOT_NECK"},{INVSLOT_SHOULDER,"SLOT_SHOULDER"},{INVSLOT_BACK,"SLOT_BACK"},{INVSLOT_CHEST,"SLOT_CHEST"},{INVSLOT_WRIST,"SLOT_WRIST"},{INVSLOT_HAND,"SLOT_HANDS"},{INVSLOT_WAIST,"SLOT_WAIST"},{INVSLOT_LEGS,"SLOT_LEGS"},{INVSLOT_FEET,"SLOT_FEET"},{INVSLOT_FINGER1,"SLOT_FINGER1"},{INVSLOT_FINGER2,"SLOT_FINGER2"},{INVSLOT_TRINKET1,"SLOT_TRINKET1"},{INVSLOT_TRINKET2,"SLOT_TRINKET2"},{INVSLOT_MAINHAND,"SLOT_MAINHAND"},{INVSLOT_OFFHAND,"SLOT_OFFHAND"}}
 local lines={string.format("%s: %s",L["ITEM_LEVEL"],number(snapshot.itemLevel)),tableRow({L["COLUMN_SLOT"],L["COLUMN_ITEM"],L["COLUMN_TIER"],L["COLUMN_ENCHANT"],L["COLUMN_GEMS"],L["COLUMN_ILVL"]},equipmentColumns,"header",1650)}
 for _,slot in ipairs(slotDefinitions)do local item=snapshot.slots and snapshot.slots[slot[1]];if item then local gems={};for index=1,tonumber(item.sockets or(type(item.gems)=="table"and#item.gems)or 0)do local gem=item.gems and item.gems[index];if gem then gems[#gems+1]=gemDisplay(gem,item.link)end end;local tier=item.isTier==true and"✓"or"";local enchant="";if(tonumber(item.enchantId)or 0)>0 then enchant=linkedText(item.link,item.enchantName or"✓")end;local slotLabel=linkedIcon(item.link,item.icon).." "..L[slot[2]];lines[#lines+1]=tableRow({slotLabel,item.link or tostring(item.itemId or L["UNKNOWN"]),tier,enchant,table.concat(gems,"  "),value(item.itemLevel)},equipmentColumns,nil,1650)else lines[#lines+1]=tableRow({L[slot[2]],L["EMPTY_SLOT"],"","","",""},equipmentColumns,nil,1650)end end
 C:SetView(view,L[definition.labelKey],lines,status,meta,{[1]="accent"})
end
local function bestMythicRun(dungeon)
 if type(dungeon.bestRun)=="table"then return dungeon.bestRun end;local best;local function consider(entry,overTime)local score=entry and tonumber(entry.dungeonScore or entry.score or entry.seasonScore);local level=entry and tonumber(entry.level or entry.bestLevel);if level and level>0 and(not best or(score or 0)>(best.score or 0)or((score or 0)==(best.score or 0)and level>(best.level or 0)))then best={level=level,score=score or 0,durationSec=entry.durationSec,overTime=overTime==true or entry.overTime==true}end end;consider(dungeon.bestInTime,false);consider(dungeon.bestOverTime,true);for _,entry in pairs(type(dungeon.affixScores)=="table"and dungeon.affixScores or{})do consider(entry,entry.overTime)end;return best
end
local function runResult(run)if not run then return L["UNKNOWN"]end;local result=L[run.overTime and"MYTHIC_OVERTIME"or"MYTHIC_IN_TIME"];if tonumber(run.durationSec)and SecondsToClock then result=result.."  ·  "..SecondsToClock(run.durationSec,run.durationSec>=3600)end;return result end
local function mythic(view,context,definition)
 if blocked(view,definition)then return end;local snapshot,meta=C:GetSnapshot(context.characterUUID,"mythicPlus");local status=statusFor(context.characterUUID,"mythicPlus");if not snapshot then C:SetView(view,L[definition.labelKey],{L["NO_MYTHICPLUS"]},status);return end
 local lines={string.format(L["SEASON"],value(snapshot.seasonId)).."  |  "..L["RATING"]..": "..number(snapshot.overallScore),tableRow({L["COLUMN_DUNGEON"],L["COLUMN_BEST_KEY"],L["COLUMN_DUNGEON_SCORE"],L["COLUMN_RUN"]},mythicColumns,"header",1320)}
 local dungeons={};for _,d in ipairs(snapshot.dungeons or{})do dungeons[#dungeons+1]=d end;table.sort(dungeons,function(a,b)return tostring(a.name)<tostring(b.name)end)
 local completed,bestLevel,bestScore=0,nil,nil;for _,d in ipairs(dungeons)do local best=bestMythicRun(d);if best then completed=completed+1;if not bestLevel or(best.level or 0)>bestLevel then bestLevel=best.level end end;if tonumber(d.score)and(not bestScore or tonumber(d.score)>bestScore)then bestScore=tonumber(d.score)end;local icon=d.texture and hyperlink("teleport",d.challengeMapId or 0,"|T"..d.texture..":18:18|t")or"";local name=d.instanceId and hyperlink("journal",d.instanceId,d.name or L["UNKNOWN"])or(d.name or L["UNKNOWN"]);lines[#lines+1]=tableRow({icon.." "..name,value(best and best.level),number(d.score),runResult(best)},mythicColumns,nil,1320)end
 lines[#lines+1]="";lines[#lines+1]=tableRow({L["DUNGEONS_TOTAL"].."\n|cffffffff"..completed.." / "..#dungeons.."|r",L["BEST_RATING"].."\n|cffffffff"..number(bestScore).."|r",L["BEST_KEY"].."\n|cffffffff"..value(bestLevel).."|r",L["OVERALL_RATING"].."\n|cffffd100"..number(snapshot.overallScore).."|r"},mythicSummaryColumns,"summary",1320)
 C:SetView(view,L[definition.labelKey],lines,status,meta,{[1]="accent"})
end
local function raid(view,context,definition)
 if blocked(view,definition)then return end;local snapshot,meta=C:GetSnapshot(context.characterUUID,"raid");local status=statusFor(context.characterUUID,"raid");if not snapshot then C:SetView(view,L[definition.labelKey],{L["NO_RAID"]},status);return end
 local rows,byName,byId={},{},{};local function key(name)return type(name)=="string"and name:lower():gsub("[%s%p%c]+","")or nil end;for _,catalog in ipairs(snapshot.raids or{})do local row={name=catalog.name,instanceId=catalog.id,icon=catalog.icon,order=catalog.order or#rows+1,weekly={}};rows[#rows+1]=row;byName[key(row.name)]=row;byId[tostring(row.instanceId)]=row end
 for _,lockout in ipairs(snapshot.lockouts or{})do local row=lockout.journalInstanceId and byId[tostring(lockout.journalInstanceId)]or byName[key(lockout.name)];if not row then row={name=lockout.name,instanceId=lockout.journalInstanceId,order=1000+#rows,weekly={}};rows[#rows+1]=row;byName[key(row.name)]=row end;local difficulty=C:GetDifficultyById(lockout.difficultyId);if difficulty then row.weekly[difficulty.id]=lockout end end
 table.sort(rows,function(a,b)if a.order==b.order then return tostring(a.name)<tostring(b.name)end;return a.order<b.order end);C.raidRows=rows;C.currentRaidSnapshot=snapshot
 local lines={tableRow({L["COLUMN_RAID"],L["DIFFICULTY_LFR"],L["DIFFICULTY_NORMAL"],L["DIFFICULTY_HEROIC"],L["DIFFICULTY_MYTHIC"],L["COLUMN_BEST"]},raidColumns,"header",1350)}
 for index,row in ipairs(rows)do local values={};for _,key in ipairs({"LFR","NORMAL","HEROIC","MYTHIC"})do local x=row.weekly[key];values[#values+1]=x and hyperlink("weekly",index..":"..key,string.format("%d/%d",x.killed or 0,x.total or 0),key)or"—"end;local best=C:GetBestProgress(snapshot,row.name);local bestText=best and hyperlink("best",index,string.format("%s %d/%d",best.difficulty,best.killed,best.total),best.difficulty)or"—";local label=(row.icon and("|T"..row.icon..":18:18|t ")or"")..row.name;local name=row.instanceId and hyperlink("journal",row.instanceId,label)or label;lines[#lines+1]=tableRow({name,values[1],values[2],values[3],values[4],bestText},raidColumns,nil,1350)end
 C:SetView(view,L[definition.labelKey],#rows>0 and lines or{L["NO_RAID"]},status,meta)
end
local function unknownField(field)
 if type(field)~="table"then return value(field)end
 if field.status=="unknown"then return L["UNKNOWN"]end
 if field.value~=nil then return value(field.value)end
 if field.count~=nil then return value(field.count)end
 if field.level~=nil then return value(field.level)end
 if field.name~=nil then return value(field.name)end
 return L["PRESENT"]
end
local function delves(view,context,definition)
 if blocked(view,definition)then return end;local snapshot,meta=C:GetSnapshot(context.characterUUID,"delves");local status=statusFor(context.characterUUID,"delves");if not snapshot then C:SetView(view,L[definition.labelKey],{L["NO_DELVES"]},status);return end
 local lines={string.format(L["SEASON"],value(snapshot.seasonNumber)),L["GREAT_VAULT"]..": "..value(snapshot.weeklyProgress),L["BOUNTIFUL"]..": "..unknownField(snapshot.bountiful),L["KEY_FRAGMENTS"]..": "..unknownField(snapshot.keyFragments),L["COMPLETED_KEYS"]..": "..unknownField(snapshot.completedKeys),L["TREASURE_MAP"]..": "..unknownField(snapshot.treasureMap),L["MAP_USED"]..": "..unknownField(snapshot.treasureMapUsed),L["FLUTE"]..": "..unknownField(snapshot.flute),L["MINI_ROGUE"]..": "..unknownField(snapshot.miniRogue),L["COMPANION"]..": "..unknownField(snapshot.companion)}
 for index,a in ipairs(snapshot.activities or{})do lines[#lines+1]=string.format("%s  %s",string.format(L["ACTIVITY"],a.index or index),string.format(L["PROGRESS_FORMAT"],value(a.progress),value(a.threshold),value(a.level)))end;C:SetView(view,L[definition.labelKey],lines,status,meta,{[1]="accent"})
end
local function stats(view,context,definition)
 if blocked(view,definition)then return end;local snapshot,meta=C:GetSnapshot(context.characterUUID,"stats");local status=statusFor(context.characterUUID,"stats");if not snapshot then C:SetView(view,L[definition.labelKey],{L["NO_STATS"]},status);return end
 local lines={tableRow({L["COLUMN_STAT"],L["COLUMN_BASE"],L["COLUMN_EFFECTIVE"]},statsColumns,"header",760)};for _,key in ipairs({"strength","agility","stamina","intellect"})do local x=snapshot.primary and snapshot.primary[key];lines[#lines+1]=tableRow({L["STAT_"..key:upper()],value(x and x.base),value(x and x.effective)},statsColumns,nil,760)end
 if snapshot.armor then lines[#lines+1]=tableRow({L["STAT_ARMOR"],value(snapshot.armor.base),value(snapshot.armor.effective)},statsColumns,nil,760)end;for _,key in ipairs({"criticalStrike","haste","mastery","versatility"})do local x=snapshot.secondary and snapshot.secondary[key];local percent=x and tonumber(x.percent);lines[#lines+1]=tableRow({L["STAT_"..key:upper()],value(x and x.rating),percent and string.format("%.1f%%",percent)or L["UNKNOWN"]},statsColumns,nil,760)end;lines[#lines+1]="";lines[#lines+1]=L["COLUMN_LIVE_BUFFS"]..": "..L["LIVE_BUFFS_UNAVAILABLE"];C:SetView(view,L[definition.labelKey],lines,status,meta,{[#lines]="muted"})
end
local function twinks(view,context,definition)
 local core,accountUUID=HolyStorm.TwinkCore,context.accountUUID;if not accountUUID then C:SetView(view,L[definition.labelKey],{L["NO_TWINKS"]});return end;local guild=context.guild;local accountMain=core:GetAccountMain(accountUUID,guild);local guildMain,isShadow=core:GetGuildMain(accountUUID,guild);local characters=core:GetVisibleCharactersForViewer(accountUUID,guild);local lines={string.format(L["CHARACTER_COUNT"],#characters),L["ACCOUNT_MAIN"]..": "..value(accountMain),L[isShadow and"SHADOW_MAIN"or"GUILD_MAIN"]..": "..value(guildMain),"",tableRow({L["COLUMN_CHARACTER"],L["COLUMN_CLASS"],L["COLUMN_LEVEL"],L["COLUMN_GUILD"],L["COLUMN_RELATIONSHIP"]},twinkColumns,"header",1450)}
 for _,character in ipairs(characters)do local labels={};if character.characterUUID==accountMain then labels[#labels+1]=L["ACCOUNT_MAIN"]end;if character.characterUUID==guildMain then labels[#labels+1]=L[isShadow and"SHADOW_MAIN"or"GUILD_MAIN"]end;local label=(#labels>0 and("["..table.concat(labels,"/").."] ")or"")..(character.fullName or character.name or character.characterUUID);local inGuild=guild and guild.roster and guild.roster[character.characterUUID];local source=character.relationship and character.relationship.source==core.sources.OWNER and L["OWNER_CONFIRMED"]or L["ADMINISTRATIVE"];lines[#lines+1]=tableRow({hyperlink("character",character.characterUUID,label),value(character.classFile),value(character.level),inGuild and L["IN_GUILD"]or L["NOT_IN_GUILD"],source},twinkColumns,nil,1450)end;C:SetView(view,L[definition.labelKey],#characters>0 and lines or{L["NO_TWINKS"]},nil,nil,#characters>0 and{[1]="accent"}or nil)
end

local standardTabs={{id="summary",order=1,labelKey="TAB_SUMMARY",refresh=summary},{id="equipment",order=2,labelKey="TAB_EQUIPMENT",permission="equipment-read",moduleName="Equipment",moduleId="equipment",refresh=equipment},{id="mythicPlus",order=3,labelKey="TAB_MYTHICPLUS",permission="mythicplus-read",moduleName="MythicPlus",moduleId="mythicPlus",refresh=mythic},{id="raid",order=4,labelKey="TAB_RAID",permission="raids-read",moduleName="Raids",moduleId="raids",refresh=raid},{id="delves",order=5,labelKey="TAB_DELVES",permission="delves-read",moduleName="Delves",moduleId="delves",refresh=delves},{id="stats",order=6,labelKey="TAB_STATS",permission="player-read",moduleName="CharacterStats",moduleId="characterStats",refresh=stats},{id="twinks",order=7,labelKey="TAB_TWINKS",permission="player-read",refresh=twinks}}
for _,definition in ipairs(standardTabs)do definition.build=function(parent)return C:CreateTextView(parent)end;assert(C:RegisterTab(definition))end
HolyStorm:RegisterCapability("CharacterOverview","character.open",function(_,characterUUID,tabId)return C:OpenCharacter(characterUUID,tabId or"summary")end)

function Page:UpdateTabVisuals()
 if self.tabGroup and self.tabGroup.SelectTab and C.activeTab then self.tabGroup:SelectTab(C.activeTab,true)end
end
function Page:LayoutTabs()
 if self.tabGroup and self.tabGroup.LayoutTabs then self.tabGroup:LayoutTabs()end;if C.activeTab and self.views and self.views[C.activeTab]then C:LayoutTabView(self.views[C.activeTab])end
end
function Page:SetHeaderVisible(visible)
 if self.header then self.header:SetShown(visible==true)end
end
function Page:IsCharacterPageVisible()
 return HolyStorm.UI and HolyStorm.UI.GetVisiblePage and HolyStorm.UI:GetVisiblePage()=="character"
end
function C:LayoutTabView(view)
 if not view or not view.frame or not Page.tabHost then return end
 if view.frame.SetParent then view.frame:SetParent(Page.tabHost)end;view.frame:ClearAllPoints();view.frame:SetPoint("TOPLEFT",Page.tabHost,"TOPLEFT",0,0);view.frame:SetPoint("BOTTOMRIGHT",Page.tabHost,"BOTTOMRIGHT",0,0);if view.frame.SetSize and Page.tabHost.GetWidth and Page.tabHost.GetHeight then view.frame:SetSize(math.max(1,Page.tabHost:GetWidth()or 1),math.max(1,Page.tabHost:GetHeight()or 1))end;if view.scroll then self:LayoutTextView(view)end
end
function C:RefreshHeader()
 local context=self.context;if not context or not Page.headerName then return end;context=self:ResolveContext(context.characterUUID);context.token=self.contextToken;self.context=context;local color=classColor(context.classFile);Page.headerName:SetText(context.name or context.characterUUID);Page.headerName:SetTextColor(color.r,color.g,color.b);local rank=context.member and context.member.rank or context.record and context.record.guildRank;local parts={context.realm,context.className,context.spec and context.spec.name,context.level and(L["LEVEL"].." "..context.level),rank};local clean={};for _,part in ipairs(parts)do if part and part~=""then clean[#clean+1]=part end end;Page.headerInfo:SetText(table.concat(clean,"  •  "))
 if Page:IsCharacterPageVisible()then Page:SetHeaderVisible(true)end
 if Page.classIcon then self:ApplyClassIconTexture(Page.classIcon,context.classFile)end
 if Page.specIcon then local icon=context.spec and context.spec.icon;if icon then Page.specIcon:SetTexture(icon);Page.specIcon:SetTexCoord(0,1,0,1);Page.specIcon:Show()else Page.specIcon:Hide()end end
 if Page.headerName then Page.headerName:ClearAllPoints();if Page.specIcon and Page.specIcon:IsShown()then Page.headerName:SetPoint("TOPLEFT",Page.specIcon,"TOPRIGHT",12,-2)else Page.headerName:SetPoint("TOPLEFT",Page.classIcon,"TOPRIGHT",12,-2)end;Page.headerName:SetPoint("RIGHT",Page.header,"RIGHT",-250,0)end
 if Page.factionMark then local faction=context.record and context.record.faction;Page.factionMark:SetTexture(faction=="Horde"and"Interface\\FriendsFrame\\PlusManz-Horde"or faction=="Alliance"and"Interface\\FriendsFrame\\PlusManz-Alliance"or nil);Page.factionMark:SetShown(faction=="Horde"or faction=="Alliance")end
 local activeBlocks=blocksByTab[self.activeTab or"summary"]or{};local block=activeBlocks[1];local dataStatus,meta;if block then dataStatus,meta=self:GetDataStatus(context.characterUUID,block)end;Page.headerStatus:SetText(dataStatus and L["STATUS_"..dataStatus]or L["STATUS_CURRENT"]);if Page.headerUpdated then Page.headerUpdated:SetText(meta and meta.updatedAt and string.format(L["LAST_UPDATED"],dateValue(meta.updatedAt))or"")end
 local developerText=HolyStorm.Database:Get("debug","profile")and(context.characterUUID.."  |  "..tostring(context.accountUUID or"-"))or"";Page.developer:SetText(developerText);Page:UpdateTabVisuals()
end
function C:RefreshTab(id)
 local definition=self.tabs[id];if not definition or not self.context then return false end;local view=Page.views[id];if not view then local built,result=HolyStorm.Utils.SafeCall("character.tab.build:"..id,definition.build,Page.tabHost,self.context);local valid=built and type(result)=="table"and result.frame;if valid then view=result else view=self:CreateTextView(Page.tabHost)end;view.buildFailed=not valid;Page.views[id]=view;self:LayoutTabView(view);local visual=tabVisuals[id];if view.sectionIcon and view.sectionIcon.SetTexture then view.sectionIcon:SetTexture(definition.icon or(visual and visual.icon)or"Interface\\Icons\\INV_Misc_QuestionMark")end;if not valid then self:SetView(view,L[definition.labelKey],{L["TAB_ERROR"]})end end;if view.buildFailed then return false end
 local ok=HolyStorm.Utils.SafeCall("character.tab.refresh:"..id,definition.refresh,view,self.context,definition);if not ok then self:SetView(view,L[definition.labelKey],{L["TAB_ERROR"]})end;Page.dirty[id]=nil;return ok
end
function C:SelectTab(id)
 local definition=self.tabs[id]or self.tabs.summary;if not definition then return false end;id=definition.id;self.activeTab=id
 for tabId,view in pairs(Page.views)do view.frame:SetShown(tabId==id)end;Page:UpdateTabVisuals()
 if not Page.views[id]then self:RefreshTab(id)end;self:LayoutTabView(Page.views[id]);Page.views[id].frame:Show();if Page.dirty[id]then self:RefreshTab(id)end;self:RefreshHeader();return true
end
function C:OpenCharacter(characterUUID,optionalTab,addHistory)
 local context=self:SetContext(characterUUID,addHistory);if not context then return false end;for _,definition in ipairs(self:GetTabs())do Page.dirty[definition.id]=true end;HolyStorm.UI:ShowPage("character");self:RefreshHeader();self:SelectTab(optionalTab or self.activeTab or"summary");self:RequestRefresh(characterUUID,blocksByTab[optionalTab or self.activeTab or"summary"],"CHARACTER_OPEN");return true
end
function Page:ScheduleRefresh(tabId,guid)
 if guid and C.context and guid~=C.context.characterUUID then return end;self.dirty[tabId]=true;self.dirty.summary=true;if self.refreshScheduled then return end;local token=C.contextToken;self.refreshScheduled=true;C_Timer.After(.05,function()Page.refreshScheduled=nil;if token~=C.contextToken then return end;C:RefreshHeader();if C.activeTab and Page.dirty[C.activeTab]then C:RefreshTab(C.activeTab)end end)
end
function Page:BuildTabs()
 local tabs={};for _,definition in ipairs(C:GetTabs())do local visual=tabVisuals[definition.id];tabs[#tabs+1]={value=definition.id,text=definition.label or L[definition.labelKey],icon=definition.icon or(visual and visual.icon)}end
 if self.tabGroup and self.tabGroup.SetTabs then self.tabGroup:SetTabs(tabs);self.tabButtons=self.tabGroup.tabButtons or{};self.tabGroup:SelectTab(C.activeTab or(tabs[1]and tabs[1].value),true)end
end
function Page:OnInitialize()
 HolyStorm.Tasks:RegisterTaskType("Character.Refresh",{name=L["TASK_CHARACTER_REFRESH"],localizedNameKey="TASK_CHARACTER_REFRESH",module="CharacterOverview",priority=30,executionMode="MERGE_BY_KEY",execute=function(task)local m=task.metadata or{};return C:ConsumeRefresh(m.characterUUID)end})
 local UI=HolyStorm:GetModule("UI",true);local page=CreateFrame("Frame",nil,UI.content);self.page=page;self.views,self.tabButtons,self.dirty={},{},{}
 local headerBar=HolyStorm.UIComponents:CreateHeaderBar(UI.frame or page,UI.content or page);self.headerBar=headerBar;self.header=headerBar.frame;self.classIcon=headerBar.primaryIcon;self.portrait=headerBar.primaryIcon;self.specIcon=headerBar.secondaryIcon;self.headerName=headerBar.title;self.headerInfo=headerBar.subtitle;self.factionMark=headerBar.watermark;self.headerStatus=headerBar.status;self.headerUpdated=headerBar.updated;self.developer=headerBar.developer;self.refreshButton=headerBar.refreshButton
 self.refreshButton:SetScript("OnEnter",function(b)GameTooltip:SetOwner(b,"ANCHOR_LEFT");GameTooltip:SetText(L["REFRESH"]);GameTooltip:Show()end);self.refreshButton:SetScript("OnLeave",function()GameTooltip:Hide()end);self.refreshButton:SetScript("OnClick",function()if C.context then C:RequestRefresh(C.context.characterUUID,blocksByTab[C.activeTab],"MANUAL")end end)
 local aceGUI=LibStub("AceGUI-3.0");local tabGroup=aceGUI:Create("HolyStormTabGroup");tabGroup.frame:SetParent(page);tabGroup.frame:SetPoint("TOPLEFT",12,-8);tabGroup.frame:SetPoint("BOTTOMRIGHT",-12,10);tabGroup.frame:Show();tabGroup:SetCallback("OnGroupSelected",function(_,_,tabId)if C.context then C:SelectTab(tabId);C:RequestRefresh(C.context.characterUUID,blocksByTab[tabId],"TAB_SELECTED")end end);self.tabGroup=tabGroup;self.tabHost=tabGroup:GetContentFrame();self.tabHost:Show();self:BuildTabs();page:HookScript("OnSizeChanged",function()Page:LayoutTabs()end);page:HookScript("OnShow",function()Page:SetHeaderVisible(true)end);page:HookScript("OnHide",function()Page:SetHeaderVisible(false)end);HolyStorm.UI:RegisterPage("character",page,L["WINDOW_TITLE"],function()Page:SetHeaderVisible(true);if C.context then C:RefreshHeader();C:SelectTab(C.activeTab or"summary")end end)
 for event,tabId in pairs(tabByEvent)do local capturedEvent,capturedTab=event,tabId;HolyStorm.Events:Register(capturedEvent,"character-overview",function(_,guid)Page:ScheduleRefresh(capturedTab,characterScopedEvents[capturedEvent]and guid or nil)end)end
 HolyStorm.Events:Register("HS_CHARACTER_TAB_REGISTERED","character-overview-tabs",function()Page:BuildTabs()end)
 HolyStorm.Events:Register("HS_TASK_STARTED","character-overview-task",function(_,task)if task.registryId=="Character.Refresh"and C:IsCurrent(task.metadata.characterUUID)then Page.headerStatus:SetText(L["STATUS_REFRESHING"])end end)
 HolyStorm.Events:Register("HS_TASK_COMPLETED","character-overview-task-complete",function(_,task)if task.registryId=="Character.Refresh"and C:IsCurrent(task.metadata.characterUUID)then Page:ScheduleRefresh(C.activeTab,task.metadata.characterUUID)end end)
 HolyStorm.Events:Register("HS_TASK_FAILED","character-overview-task-failed",function(_,task)if task.registryId=="Character.Refresh"and C:IsCurrent(task.metadata.characterUUID)then Page:ScheduleRefresh(C.activeTab,task.metadata.characterUUID)end end)
end
function Page:OnDisable()HolyStorm.Events:UnregisterOwner("character-overview");HolyStorm.Events:UnregisterOwner("character-overview-tabs");HolyStorm.Events:UnregisterOwner("character-overview-task");HolyStorm.Events:UnregisterOwner("character-overview-task-complete");HolyStorm.Events:UnregisterOwner("character-overview-task-failed")end
