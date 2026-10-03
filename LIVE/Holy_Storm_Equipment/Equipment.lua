local addonVersion="6.3.0"
local HolyStorm=LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local L=LibStub("AceLocale-3.0"):GetLocale("Holy_Storm_Equipment")
local metadata={id="equipment",name="Equipment",displayName=L["DISPLAY_NAME"],description=L["DESCRIPTION"],version=addonVersion,moduleType="feature",category="feature",permissions={"sync-send","sync-receive"},dependencies={"core","synchronization"},capabilities={"character.scan.equipment"},ui={characterTab="equipment"},data={block="equipment",snapshotType="equipment",schemaVersion=4,capability="character.scan.equipment"},sync={domains={"character"}},enabledByDefault=true,ruleFields={{id="equipment.itemLevel",aliases={"itemLevel"},type="number",name=L["RULE_FIELD_ITEM_LEVEL"],nameKey="RULE_FIELD_ITEM_LEVEL",description=L["RULE_FIELD_ITEM_LEVEL_DESC"],descriptionKey="RULE_FIELD_ITEM_LEVEL_DESC",category=L["DISPLAY_NAME"],dependencies={"equipment"},unit="itemLevel",resolver=function(context)local block=context.character and context.character.equipment or HolyStorm.Data.CharacterStore:GetBlock(context.characterUUID,"equipment");return block and tonumber(block.equippedItemLevel or block.itemLevel)or nil end}}}
local SLOTS={INVSLOT_HEAD,INVSLOT_NECK,INVSLOT_SHOULDER,INVSLOT_CHEST,INVSLOT_WAIST,INVSLOT_LEGS,INVSLOT_FEET,INVSLOT_WRIST,INVSLOT_HAND,INVSLOT_FINGER1,INVSLOT_FINGER2,INVSLOT_TRINKET1,INVSLOT_TRINKET2,INVSLOT_BACK,INVSLOT_MAINHAND,INVSLOT_OFFHAND}
local WORKFLOW="EQUIPMENT_UPDATE"
local unpackValues=unpack or table.unpack
local itemLoadRequests={}
local function runtime(task)local w=HolyStorm.Workflows.workflows[task.workflowId];return w,w and w.context end
local function fingerprint(snapshot)return HolyStorm.PlayerData:FingerprintSnapshot(snapshot)end
local function safeCall(fn,...)
 if type(fn)~="function"then return nil end
 local function pack(...)return{n=select("#",...),...}end
 local result=pack(pcall(fn,...));if not result[1]then return nil end;return unpackValues(result,2,result.n)
end
local function requestItemData(itemId)
 if type(itemId)~="number"or not(C_Item and type(C_Item.RequestLoadItemDataByID)=="function")then return end
 local now=HolyStorm.Utils.Now();for id,requestedAt in pairs(itemLoadRequests)do if now-requestedAt>60 then itemLoadRequests[id]=nil end end
 if itemLoadRequests[itemId]and now-itemLoadRequests[itemId]<15 then return end
 itemLoadRequests[itemId]=now;safeCall(C_Item.RequestLoadItemDataByID,itemId)
end
local function equipmentSlotItem(slot)
 if not(Item and type(Item.CreateFromEquipmentSlot)=="function")then return nil end
 local object=safeCall(Item.CreateFromEquipmentSlot,Item,slot);if not object then return nil end
 local empty=safeCall(object.IsItemEmpty,object);if type(empty)=="boolean"then return object,not empty end
 return object,nil
end
local function captureGem(itemLink,index)
 local gemId=C_Item and safeCall(C_Item.GetItemGemID,itemLink,index)
 if type(gemId)~="number"then return{state="SOCKET_UNKNOWN"}end
 local gemName,gemLink;if C_Item then gemName,gemLink=safeCall(C_Item.GetItemGem,itemLink,index)end
 local itemName,itemInfoLink,quality,_,_,_,_,_,_,icon;if C_Item then itemName,itemInfoLink,quality,_,_,_,_,_,_,icon=safeCall(C_Item.GetItemInfo,gemLink or gemId)end
 return{state="SOCKET_FILLED",itemId=gemId,name=gemName or itemName,link=gemLink or itemInfoLink,quality=quality,icon=icon}
end
local function captureItem(slot)
 local itemId=GetInventoryItemID and GetInventoryItemID("player",slot)
 local link=GetInventoryItemLink and GetInventoryItemLink("player",slot)
 local slotItem,slotHasItem=equipmentSlotItem(slot)
 if slotHasItem==false then if itemId~=nil or link~=nil then return nil,"SLOT_STATE_CONFLICT"end;return false end
 if slotHasItem==true and slotItem then
  local locationId=safeCall(slotItem.GetItemID,slotItem);if type(locationId)=="number"and locationId>0 then itemId=locationId end
  local locationLink=safeCall(slotItem.GetItemLink,slotItem);if type(locationLink)=="string"and locationLink~=""then link=locationLink end
 end
 if itemId==nil and link==nil then
  if slotHasItem==true and slotItem then itemId=safeCall(slotItem.GetItemID,slotItem);link=safeCall(slotItem.GetItemLink,slotItem)end
  if itemId==nil and (type(link)~="string"or link=="")then return nil,"SLOT_STATE_UNKNOWN"end
 end
 if type(itemId)~="number"or itemId<=0 then
  local itemString=type(link)=="string"and link:match("|H(item:[^|]+)|h")
  itemId=itemString and tonumber(itemString:match("^item:(%d+)"))
 end
 if type(itemId)~="number"or itemId<=0 then return nil,"ITEM_ID_PENDING"end
 if type(link)~="string"or link==""then return nil,"ITEM_LINK_PENDING"end
 local itemString=link:match("|H(item:[^|]+)|h");if not itemString then return nil,"ITEM_LINK_INVALID"end
 local fields={strsplit(":",itemString)};local linkedItemId=tonumber(fields[2]);if linkedItemId~=itemId then return nil,"ITEM_ID_LINK_MISMATCH"end
 local level,previewLevel;if C_Item then level,previewLevel=safeCall(C_Item.GetDetailedItemLevelInfo,link)end
 if type(level)~="number"or level<=0 or type(previewLevel)~="boolean"or previewLevel then requestItemData(itemId);return nil,"ITEM_DATA_PENDING"end
 if not C_Item then return nil,"ITEM_DATA_PENDING"end
 local itemName,itemInfoLink,quality=safeCall(C_Item.GetItemInfo,link)
 if type(quality)~="number"then requestItemData(itemId);return nil,"ITEM_DATA_PENDING"end
 local socketCount=C_Item and safeCall(C_Item.GetItemNumSockets,link);local gems={}
 if type(socketCount)=="number"and socketCount>=0 then for index=1,socketCount do gems[index]=captureGem(link,index)end else socketCount=nil end
 local enchantId;if fields[3]==""then enchantId=0 elseif fields[3]~=nil then enchantId=tonumber(fields[3])end
 local icon=GetInventoryItemTexture and GetInventoryItemTexture("player",slot)
 if not icon and slotItem then icon=safeCall(slotItem.GetItemIcon,slotItem)end
 if not icon then if C_Item and type(C_Item.GetItemIconByID)=="function"then icon=safeCall(C_Item.GetItemIconByID,itemId)end end
 if not icon then requestItemData(itemId);return nil,"ITEM_DATA_PENDING"end
 local setID;if C_Item and type(C_Item.GetItemInfo)=="function"then local packed={pcall(C_Item.GetItemInfo,link)};if packed[1]then setID=packed[17]end end
 return{state="EQUIPPED",slot=slot,itemId=itemId,link=link,itemLevel=level,enchantId=enchantId,gems=gems,sockets=socketCount,quality=quality,icon=icon,setID=type(setID)=="number"and setID or nil}
end
local function validEquipmentSnapshot(snapshot)
 local equippedLevel=type(snapshot)=="table"and(snapshot.equippedItemLevel or snapshot.itemLevel)
 if type(snapshot)~="table"or snapshot.snapshotVersion~=4 or snapshot.pending~=nil or type(snapshot.slots)~="table"or type(equippedLevel)~="number"or equippedLevel~=equippedLevel or equippedLevel<0 or (snapshot.equippedItemLevel~=nil and snapshot.itemLevel~=equippedLevel)or (snapshot.overallItemLevel~=nil and(type(snapshot.overallItemLevel)~="number"or snapshot.overallItemLevel~=snapshot.overallItemLevel or snapshot.overallItemLevel<0))or type(snapshot.equippedCount)~="number"or snapshot.equippedCount<0 or snapshot.equippedCount%1~=0 then return false,"INVALID_EQUIPMENT_SNAPSHOT"end
 local allowed={};for _,slot in ipairs(SLOTS)do if allowed[slot]then return false,"DUPLICATE_EQUIPMENT_SLOT"end;allowed[slot]=true end
 for slot in pairs(snapshot.slots)do if not allowed[slot]then return false,"UNEXPECTED_EQUIPMENT_SLOT"end end
 local count=0
 for _,slot in ipairs(SLOTS)do local item=snapshot.slots[slot];if item==nil then return false,"INCOMPLETE_EQUIPMENT_SLOTS"end;if item~=false then if type(item)~="table"or(item.state~=nil and item.state~="EQUIPPED")or(item.slot~=nil and item.slot~=slot)or type(item.itemId)~="number"or item.itemId<=0 or item.itemId%1~=0 or type(item.itemLevel)~="number"or item.itemLevel~=item.itemLevel or item.itemLevel<=0 or type(item.link)~="string"or item.link==""or(item.quality~=nil and(type(item.quality)~="number"or item.quality%1~=0))then return false,"INVALID_EQUIPMENT_ITEM"end;local itemString=item.link:match("|H(item:[^|]+)|h");local linkedId=itemString and tonumber(itemString:match("^item:(%d+)"));if linkedId~=item.itemId then return false,"EQUIPMENT_ITEM_ID_LINK_MISMATCH"end;if item.enchantId~=nil and(type(item.enchantId)~="number"or item.enchantId<0 or item.enchantId%1~=0)then return false,"INVALID_EQUIPMENT_ENCHANT"end;if item.sockets~=nil and(type(item.sockets)~="number"or item.sockets<0 or item.sockets%1~=0)then return false,"INVALID_EQUIPMENT_SOCKETS"end;count=count+1 end end
 if count~=snapshot.equippedCount then return false,"EQUIPMENT_COUNT_MISMATCH"end
 return true
end
if HolyStorm.PlayerData then HolyStorm.PlayerData:RegisterBlock("equipment",{fields={"equipment","itemLevel"},event="HS_EQUIPMENT_UPDATED",staleAfter=21600,owner="equipment",schemaVersion=4,snapshotVersion=4,capability="character.scan.equipment",validate=function(data)if type(data)~="table"then return false,"INVALID_EQUIPMENT_BLOCK"end;local valid,reason=validEquipmentSnapshot(data.equipment);if not valid then return false,reason end;if tonumber(data.itemLevel)~=tonumber(data.equipment.equippedItemLevel or data.equipment.itemLevel)then return false,"EQUIPMENT_ITEM_LEVEL_MISMATCH"end;return true end})end

 HolyStorm:RegisterModule(metadata,function(Module)
 HolyStorm:ApplyModuleMetadata(Module,metadata)
 function Module:GetCharacterSnapshot(guid)local record=HolyStorm.Data.CharacterStore:Get(guid or UnitGUID("player"));return record and record.equipment,HolyStorm.Data.CharacterStore:GetBlockMetadata(guid,"equipment")end
 local function storedSnapshot(character)
  if type(character)=="table"then return character.equipment or character end
  character=character or UnitGUID("player");local data=HolyStorm.Data.CharacterStore:GetBlock(character,"equipment");return type(data)=="table"and(data.equipment or data)or nil
 end
 function Module:GetSlot(character,slotID)
  local snapshot=storedSnapshot(character)
  local slot=snapshot and snapshot.slots and snapshot.slots[slotID]
  if slot==false then return{state="EMPTY",slotID=slotID}end
  if type(slot)=="table"and(slot.state=="EQUIPPED"or slot.state==nil and type(slot.itemId)=="number")then if slot.state=="EQUIPPED"then return slot end;local legacy={};for key,value in pairs(slot)do legacy[key]=value end;legacy.state="EQUIPPED";return legacy end
  return{state="UNKNOWN",slotID=slotID}
 end
 function Module:GetEquippedItemLevel(character)
  local snapshot=storedSnapshot(character)
  return snapshot and tonumber(snapshot.equippedItemLevel or snapshot.itemLevel)or nil
 end
 function Module:GetEnchantState(character,slotID)
  local slot=self:GetSlot(character,slotID);if slot.state~="EQUIPPED"then return slot.state=="EMPTY"and"NOT_APPLICABLE"or"UNKNOWN"end
  if type(slot.enchantId)~="number"then return"UNKNOWN"end;return slot.enchantId>0 and"ENCHANTED"or"NOT_ENCHANTED"
 end
 function Module:GetSocketState(character,slotID,index)
  local slot=self:GetSlot(character,slotID);if slot.state~="EQUIPPED"then return slot.state=="EMPTY"and"NOT_APPLICABLE"or"SOCKET_UNKNOWN"end
  if type(slot.sockets)~="number"then return"SOCKET_UNKNOWN"end;if slot.sockets==0 then return"NO_SOCKET"end
  local gem=slot.gems and slot.gems[index];if type(gem)~="table"then return"SOCKET_UNKNOWN"end;if gem.state then return gem.state end;if gem.empty then return"SOCKET_EMPTY"end;if type(gem.itemId)=="number"then return"SOCKET_FILLED"end;return"SOCKET_UNKNOWN"
 end
 function Module:GetTierPieceCount(character)
  -- Blizzard exposes set bonus spell IDs, but no general authoritative tier-membership query.
  return nil,"TIER_MEMBERSHIP_UNAVAILABLE"
 end
 function Module:Collect()
  local snapshot={slots={},updatedAt=HolyStorm.Utils.Now(),snapshotVersion=4};local count=0
  for _,slot in ipairs(SLOTS)do local item,reason=captureItem(slot);if reason then snapshot.pending=snapshot.pending or reason end;snapshot.slots[slot]=item;if item and item~=false then count=count+1 end end
  local overall,equipped;if type(GetAverageItemLevel)=="function"then overall,equipped=safeCall(GetAverageItemLevel)end
  if type(overall)~="number"or type(equipped)~="number"then snapshot.pending=snapshot.pending or"CHARACTER_ITEM_LEVEL_PENDING"end
  snapshot.equippedCount=count;snapshot.overallItemLevel=type(overall)=="number"and overall or nil;snapshot.equippedItemLevel=type(equipped)=="number"and equipped or nil;snapshot.itemLevel=snapshot.equippedItemLevel;return snapshot
 end
 function Module:Validate(snapshot)
  if type(snapshot)~="table"or snapshot.pending then return false,snapshot and snapshot.pending or"MISSING_SNAPSHOT"end
  local valid,reason=validEquipmentSnapshot(snapshot);if not valid then return false,reason end
  local old=HolyStorm.Data.CharacterStore:Get(UnitGUID("player"));local oldCount=old and old.equipment and old.equipment.equippedCount or 0
  if snapshot.equippedCount==0 and oldCount>0 then local fp=fingerprint(snapshot.slots);if self.emptyCandidate~=fp then self.emptyCandidate=fp;return false,"SUDDEN_EMPTY_EQUIPMENT"end;return true end
  self.emptyCandidate=nil;return true
 end
 function Module:Store(snapshot)
  local guid=UnitGUID("player")
  local changed,reason=HolyStorm.PlayerData:WriteOwnedBlock(guid,"equipment",{equipment=snapshot,itemLevel=snapshot.itemLevel},"blizzard")
  if changed or reason=="UNCHANGED"then self.emptyCandidate=nil end
  return changed,reason
 end
 function Module:RegisterWorkflow()
   HolyStorm.Tasks:RegisterTaskType("Equipment.Scan",{name=L["TASK_SCAN"],localizedNameKey="TASK_SCAN",module="Equipment",priority=25,executionMode="UNIQUE",conditions={"PLAYER_LOGGED_IN","PLAYER_READY","NOT_IN_COMBAT","NOT_LOADING","NOT_ZONING"},maxRetries=5,execute=function(task)local _,c=runtime(task);local snapshot=Module:Collect();c.data.snapshot=snapshot;c.data.candidateState="SCAN_A_CAPTURED";c.data.candidateReason=snapshot and snapshot.pending or nil;return snapshot end})
   HolyStorm.Tasks:RegisterTaskType("Equipment.Validate",{name=L["TASK_VALIDATE"],localizedNameKey="TASK_VALIDATE",module="Equipment",priority=25,executionMode="UNIQUE",execute=function(task)local _,c=runtime(task);local valid,reason=Module:Validate(c.data.snapshot);if not valid then c.data.candidateState="SCAN_A_INVALID";c.data.candidateReason=reason;return{workflowAction="RETRY",gotoStep=1,delay=2.5,maxRetries=5,reason=reason}end;c.data.candidateState="SCAN_A_VALIDATED";c.data.candidateReason=nil;c.data.lastSuccessfulStage="validate";return{valid=true}end})
   HolyStorm.Tasks:RegisterTaskType("Equipment.Compare",{name=L["TASK_COMPARE"],localizedNameKey="TASK_COMPARE",module="Equipment",priority=25,executionMode="UNIQUE",execute=function(task)local _,c=runtime(task);local record=HolyStorm.Data.CharacterStore:Get(UnitGUID("player"));local old=record and record.equipment;local changed=fingerprint(c.data.snapshot)~=fingerprint(old);c.data.changed=changed;if not changed then c.data.candidateState="UNCHANGED";return{workflowAction="COMPLETE",changed=false,status="UNCHANGED"}end;c.data.candidateState="SCAN_A_CHANGED";c.data.lastSuccessfulStage="compare";return{workflowAction="GOTO",gotoStep=4,delay=1,changed=true}end})
   HolyStorm.Tasks:RegisterTaskType("Equipment.ConfirmScan",{name=L["TASK_SCAN"],localizedNameKey="TASK_SCAN",module="Equipment",priority=25,executionMode="UNIQUE",conditions={"PLAYER_LOGGED_IN","PLAYER_READY","NOT_IN_COMBAT","NOT_LOADING","NOT_ZONING"},execute=function(task)local _,c=runtime(task);local snapshot=Module:Collect();c.data.confirmSnapshot=snapshot;c.data.candidateState="SCAN_B_CAPTURED";c.data.candidateReason=snapshot and snapshot.pending or nil;return{snapshot=snapshot}end})
   HolyStorm.Tasks:RegisterTaskType("Equipment.ConfirmValidate",{name=L["TASK_VALIDATE"],localizedNameKey="TASK_VALIDATE",module="Equipment",priority=25,executionMode="UNIQUE",execute=function(task)local _,c=runtime(task);local valid,reason=Module:Validate(c.data.confirmSnapshot);if not valid then c.data.candidateState="SCAN_B_INVALID";c.data.candidateReason=reason;return{workflowAction="RETRY",gotoStep=4,delay=2.5,maxRetries=5,reason=reason}end;c.data.candidateState="SCAN_B_VALIDATED";c.data.candidateReason=nil;c.data.lastSuccessfulStage="confirm-validate";return{valid=true}end})
   HolyStorm.Tasks:RegisterTaskType("Equipment.StabilityCompare",{name=L["TASK_COMPARE"],localizedNameKey="TASK_COMPARE",module="Equipment",priority=25,executionMode="UNIQUE",execute=function(task)local _,c=runtime(task);if fingerprint(c.data.snapshot)~=fingerprint(c.data.confirmSnapshot)then c.data.candidateState="SCAN_UNSTABLE";c.data.candidateReason="EQUIPMENT_CHANGED_DURING_CONFIRMATION";return{workflowAction="RETRY",gotoStep=1,delay=2.5,maxRetries=5,reason="EQUIPMENT_CHANGED_DURING_CONFIRMATION"}end;c.data.snapshot=c.data.confirmSnapshot;c.data.candidateState="STABLE";c.data.candidateReason=nil;c.data.lastSuccessfulStage="stability-compare";return{stable=true}end})
   HolyStorm.Tasks:RegisterTaskType("Equipment.Store",{name=L["TASK_STORE"],localizedNameKey="TASK_STORE",module="Equipment",priority=25,executionMode="UNIQUE",execute=function(task)local _,c=runtime(task);local stored,reason=Module:Store(c.data.snapshot);if stored==false and reason~="UNCHANGED"then c.data.candidateState="COMMIT_FAILED";c.data.candidateReason=reason;error("equipment commit failed: "..tostring(reason or"UNKNOWN"))end;c.data.stored=stored;c.data.candidateState=stored and"COMMITTED"or"UNCHANGED";c.data.candidateReason=reason;return{stored=stored,status=stored and"COMMITTED"or"UNCHANGED"}end})
   HolyStorm.Workflows:Register(WORKFLOW,{name=L["WORKFLOW_EQUIPMENT_UPDATE"],localizedNameKey="WORKFLOW_EQUIPMENT_UPDATE",module="Equipment",priority=25,allowParallel=false,debounce=1,metadata={resource="CHARACTER_SCAN",taskTimeout="NOT_CONFIGURED",workflowTimeout="NOT_CONFIGURED"},steps={{id="scan",taskType="Equipment.Scan"},{id="validate",taskType="Equipment.Validate"},{id="compare",taskType="Equipment.Compare"},{id="confirm-scan",taskType="Equipment.ConfirmScan"},{id="confirm-validate",taskType="Equipment.ConfirmValidate"},{id="stability-compare",taskType="Equipment.StabilityCompare"},{id="store",taskType="Equipment.Store"}}})
 end
 -- DE: Waerend RUNNING werden Trigger zu genau einem Pending-Restart verdichtet.
 -- EN: While RUNNING, triggers collapse into exactly one pending restart.
 function Module:Request(sync,triggerSource,debounce)
  local workflowId,state=HolyStorm.Workflows:Request(WORKFLOW,{triggerSource=triggerSource or"MANUAL",debounce=debounce or 1,context={sync=sync==true}})
  HolyStorm.Tasks:RecordEvent(triggerSource or"MANUAL","Equipment",{workflowId=workflowId,triggeredTask="Equipment.Scan"});return workflowId,state
 end
 function Module:OnInitialize()
  self:RegisterWorkflow()
  HolyStorm.CharacterScans:RegisterProvider("Equipment",{block="equipment",capability="character.scan.equipment",addonId="equipment",order=10,request=function(sync,reason)return Module:Request(sync,reason or"CHARACTER_SCAN",1)end})
  HolyStorm:RegisterCapability("Equipment","character.scan.equipment",function(_,sync,reason)return HolyStorm.CharacterScans:Request("equipment",reason or"CAPABILITY",sync,{order=10})end)
 end
 function Module:OnEnable()
  for _,event in ipairs({"PLAYER_EQUIPMENT_CHANGED","UNIT_INVENTORY_CHANGED","SOCKET_INFO_UPDATE"})do local eventName=event;HolyStorm.Events:Register(eventName,"equipment",function(_,firstArgument)if eventName~="UNIT_INVENTORY_CHANGED"or firstArgument=="player"then HolyStorm.CharacterScans:Request("equipment",eventName,true,{order=10})end end)end
  local context=self.loadContext;if context and context.reason=="event"then HolyStorm.CharacterScans:Request("equipment",context.trigger,true,{order=10})end
 end
 function Module:OnDisable()HolyStorm.Events:UnregisterOwner("equipment");local id=HolyStorm.Workflows.activeByType[WORKFLOW];if id then HolyStorm.Workflows:Cancel(id,"MODULE_DISABLED")end end
end)
