local HolyStorm=LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local L=LibStub("AceLocale-3.0"):GetLocale("Holy_Storm_Equipment")
local slots={
 {INVSLOT_HEAD,"SLOT_HEAD","Interface\\PaperDoll\\UI-PaperDoll-Slot-Head"},{INVSLOT_NECK,"SLOT_NECK","Interface\\PaperDoll\\UI-PaperDoll-Slot-Neck"},
 {INVSLOT_SHOULDER,"SLOT_SHOULDER","Interface\\PaperDoll\\UI-PaperDoll-Slot-Shoulder"},{INVSLOT_BACK,"SLOT_BACK","Interface\\PaperDoll\\UI-PaperDoll-Slot-Chest"},
 {INVSLOT_CHEST,"SLOT_CHEST","Interface\\PaperDoll\\UI-PaperDoll-Slot-Chest"},{INVSLOT_WRIST,"SLOT_WRIST","Interface\\PaperDoll\\UI-PaperDoll-Slot-Wrists"},
 {INVSLOT_HAND,"SLOT_HANDS","Interface\\PaperDoll\\UI-PaperDoll-Slot-Hands"},{INVSLOT_WAIST,"SLOT_WAIST","Interface\\PaperDoll\\UI-PaperDoll-Slot-Waist"},
 {INVSLOT_LEGS,"SLOT_LEGS","Interface\\PaperDoll\\UI-PaperDoll-Slot-Legs"},{INVSLOT_FEET,"SLOT_FEET","Interface\\PaperDoll\\UI-PaperDoll-Slot-Feet"},
 {INVSLOT_FINGER1,"SLOT_FINGER1","Interface\\PaperDoll\\UI-PaperDoll-Slot-Finger"},{INVSLOT_FINGER2,"SLOT_FINGER2","Interface\\PaperDoll\\UI-PaperDoll-Slot-Finger"},
 {INVSLOT_TRINKET1,"SLOT_TRINKET1","Interface\\PaperDoll\\UI-PaperDoll-Slot-Trinket"},{INVSLOT_TRINKET2,"SLOT_TRINKET2","Interface\\PaperDoll\\UI-PaperDoll-Slot-Trinket"},
 {INVSLOT_MAINHAND,"SLOT_MAINHAND","Interface\\PaperDoll\\UI-PaperDoll-Slot-MainHand"},{INVSLOT_OFFHAND,"SLOT_OFFHAND","Interface\\PaperDoll\\UI-PaperDoll-Slot-SecondaryHand"},
}
local function itemName(item)
 if not item then return nil end
 local label=type(item.link)=="string"and item.link:match("|h%[?(.-)%]?|h")
 return label or item.name or(item.itemId and tostring(item.itemId))
end
local function openItem(row)
 local link=row.item and row.item.link;if not link then return end
 if HandleModifiedItemClick then HandleModifiedItemClick(link)elseif SetItemRef then local payload=link:match("|H([^|]+)|h");if payload then SetItemRef(payload,link,"LeftButton")end end
end
local function itemTooltip(row,_,_,tooltip)
 local link=row.item and row.item.link;if not link then return end
 tooltip:SetHyperlink(link);return true
end
local function iconCell(cell,_,row)
 if not cell.icon then cell.icon=cell.frame:CreateTexture(nil,"ARTWORK");cell.icon:SetSize(20,20);cell.icon:SetPoint("LEFT",4,0);cell.text:ClearAllPoints();cell.text:SetPoint("LEFT",28,0);cell.text:SetPoint("RIGHT",-4,0)end
 cell.icon:SetTexture(row.item and row.item.icon or row.state=="EMPTY"and row.emptyTexture or"Interface\\Icons\\INV_Misc_QuestionMark");cell.icon:Show();cell:SetDisplay(row.slotLabel)
end
local function itemCell(cell,_,row)
 if row.state=="UNKNOWN"then cell:SetDisplay(HolyStorm.CharacterUI:FormatState(nil));return end
 if row.state=="EMPTY"then cell:SetDisplay(L["EMPTY_SLOT"]);return end
 local name=itemName(row.item);local link=row.item.link
 if link then cell:SetDisplay(link,name,function(short)return HolyStorm.UI.Components:ReplaceHyperlinkLabel(link,short)end)else cell:SetDisplay(name or HolyStorm.CharacterUI:FormatState(nil),name)end
end
local function gemsFor(item)
 if not item then return nil,nil,nil end
 local sockets=tonumber(item.sockets);local gems=type(item.gems)=="table"and item.gems or nil
 if sockets==nil and gems then sockets=#gems end;if sockets==0 then return "",{},{}end;if sockets==nil then return nil,nil,nil end
 local labels,details,installed={},{},{}
 for index=1,sockets do
  local gem=gems and gems[index]
  if type(gem)=="table"and gem.empty then labels[#labels+1]="○";details[#details+1]=gem.name or L["EMPTY_SOCKET"]
  elseif gem~=nil then local id=type(gem)=="table"and gem.itemId or gem;local name=type(gem)=="table"and gem.name or nil;local icon=type(gem)=="table"and gem.icon or nil;labels[#labels+1]=(icon and("|T"..icon..":16:16|t")or"◆");details[#details+1]=name or string.format(L["GEM_ID"],tostring(id or index));installed[#installed+1]=gem
  else labels[#labels+1]=HolyStorm.CharacterUI:FormatState(nil);details[#details+1]=HolyStorm.CharacterUI:FormatState(nil)end
 end
 return table.concat(labels," "),details,installed
end
local function refresh(view,context,definition)
 local C=HolyStorm.CharacterUI;local ok,reason=C:CanUseTab(definition);if not ok then C:SetTableView(view,{}, {emptyText=reason=="PERMISSION"and L["PERMISSION_DENIED"]or L["MODULE_DISABLED"]});return end
 local snapshot=C:GetSnapshot(context.characterUUID,"equipment");if not snapshot then C:SetTableView(view,{}, {emptyText=L["NO_EQUIPMENT"]});return end
 local rows={};for _,slot in ipairs(slots)do
  local raw=snapshot.slots and snapshot.slots[slot[1]];local state=raw==nil and"UNKNOWN"or raw==false and"EMPTY"or"VALUE";local item=state=="VALUE"and raw or nil;local gems,gemDetails,installedGems=gemsFor(item)
  local enchant;if item then local enchantId=tonumber(item.enchantId);if enchantId==nil then enchant=C:FormatState(nil)elseif enchantId>0 then enchant="✓"else enchant="○"end end
  rows[#rows+1]={slotId=slot[1],slotLabel=L[slot[2]],emptyTexture=slot[3],state=state,item=item,itemText=itemName(item),tier=item and(item.isTier==nil and C:FormatState(nil)or item.isTier and"✓"or"")or(state=="UNKNOWN"and C:FormatState(nil)or""),enchant=enchant or(state=="UNKNOWN"and C:FormatState(nil)or""),gems=gems or(state=="UNKNOWN"and C:FormatState(nil)or""),gemDetails=gemDetails,installedGems=installedGems,itemLevel=item and C:FormatState(item.itemLevel)or(state=="UNKNOWN"and C:FormatState(nil)or"")}
 end
 C:SetTableView(view,rows,{summary=L["ITEM_LEVEL"]..": "..C:FormatState(snapshot.itemLevel),emptyText=L["NO_EQUIPMENT"]})
end
local function build(parent)
 local C=HolyStorm.CharacterUI
 return C:CreateTableView(parent,{columns={
  {id="slotLabel",title=L["COLUMN_SLOT"],width=150,renderCell=iconCell,onClick=openItem,tooltip=itemTooltip},
  {id="itemText",title=L["COLUMN_ITEM"],weight=1,minWidth=180,truncate=true,renderCell=itemCell,onClick=openItem,tooltip=itemTooltip},
  {id="tier",title=L["COLUMN_TIER"],width=55,align="CENTER",tooltip=function(row)return row.item and row.item.isTier and L["TIER_ITEM"]or nil end},
  {id="enchant",title=L["COLUMN_ENCHANT"],width=100,align="CENTER",tooltip=function(row)if not row.item or row.item.enchantId==nil then return end;return tonumber(row.item.enchantId)>0 and(row.item.enchantName or L["ENCHANTED"])or L["NOT_ENCHANTED"]end},
  {id="gems",title=L["COLUMN_GEMS"],width=130,align="CENTER",tooltip=function(row,_,_,tooltip)if row.installedGems and#row.installedGems==1 and type(row.installedGems[1])=="table"and row.installedGems[1].link then tooltip:SetHyperlink(row.installedGems[1].link);return true end;if not row.gemDetails or#row.gemDetails==0 then return end;tooltip:SetText(L["COLUMN_GEMS"]);for _,line in ipairs(row.gemDetails)do tooltip:AddLine(line,1,1,1)end;return true end},
  {id="itemLevel",title=L["COLUMN_ILVL"],width=80,align="RIGHT"},
 },rowHeight=26,headerHeight=26,columnGap=1,emptyText=L["NO_EQUIPMENT"]})
end
HolyStorm:RegisterCharacterTab("equipment",{id="equipment",order=20,label=L["DISPLAY_NAME"],labelKey="DISPLAY_NAME",icon="Interface\\Icons\\INV_Helmet_08",permission="equipment-read",moduleId="equipment",blocks={"equipment"},events={"HS_EQUIPMENT_UPDATED"},build=build,refresh=refresh})
HolyStorm:RegisterCharacterSummarySection("equipment",{id="equipment",order=20,render=function(context)local C=HolyStorm.CharacterUI;local allowed,reason=C:CanUseTab(C:GetTab("equipment"));if not allowed then return{label=L["DISPLAY_NAME"],tabId="equipment",value=reason=="PERMISSION"and L["PERMISSION_DENIED"]or L["MODULE_DISABLED"]}end;local snapshot=C:GetSnapshot(context.characterUUID,"equipment");return{label=L["DISPLAY_NAME"],tabId="equipment",value=snapshot and(L["ITEM_LEVEL"]..": "..C:FormatState(snapshot.itemLevel))or L["NO_EQUIPMENT"]}end})
