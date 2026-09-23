local addonVersion="6.3.0"
local HolyStorm=LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local L=LibStub("AceLocale-3.0"):GetLocale("Holy_Storm_Equipment")
if HolyStorm.PermissionRegistry then HolyStorm.PermissionRegistry:RegisterLegacyAlias("equipment.read","equipment-read")end
if HolyStorm.PlayerData then HolyStorm.PlayerData:RegisterBlock("equipment",{fields={"equipment","itemLevel"},event="HS_EQUIPMENT_UPDATED",staleAfter=21600})end
local metadata={id="equipment",name="Equipment",displayName=L["DISPLAY_NAME"],description=L["DESCRIPTION"],version=addonVersion,moduleType="feature",category="feature",permissions={{id="equipment-read",category="Equipment",defaults={member=true}},"sync-send","sync-receive"},dependencies={"core","synchronization"},capabilities={"character.scan.equipment"},ui={characterTab="equipment"},data={block="equipment",snapshotType="equipment",schemaVersion=4,capability="character.scan.equipment"},sync={domains={"character"}},enabledByDefault=true,ruleFields={{id="equipment.itemLevel",aliases={"itemLevel"},type="number",name=L["RULE_FIELD_ITEM_LEVEL"],nameKey="RULE_FIELD_ITEM_LEVEL",description=L["RULE_FIELD_ITEM_LEVEL_DESC"],descriptionKey="RULE_FIELD_ITEM_LEVEL_DESC",category=L["DISPLAY_NAME"],dependencies={"equipment"},unit="itemLevel",resolver=function(context)local block=context.character and context.character.equipment or HolyStorm.Data.CharacterStore:GetBlock(context.characterUUID,"equipment");return block and tonumber(block.itemLevel)or nil end}}}
local SLOTS={INVSLOT_HEAD,INVSLOT_NECK,INVSLOT_SHOULDER,INVSLOT_CHEST,INVSLOT_WAIST,INVSLOT_LEGS,INVSLOT_FEET,INVSLOT_WRIST,INVSLOT_HAND,INVSLOT_FINGER1,INVSLOT_FINGER2,INVSLOT_TRINKET1,INVSLOT_TRINKET2,INVSLOT_BACK,INVSLOT_MAINHAND,INVSLOT_OFFHAND}
local WORKFLOW="EQUIPMENT_UPDATE"
local function runtime(task)local w=HolyStorm.Workflows.workflows[task.workflowId];return w,w and w.context end
local function fingerprint(snapshot)local value=HolyStorm.Utils.DeepCopy(snapshot);if type(value)=="table"then value.updatedAt=nil;value.version=nil;value.snapshotVersion=nil end;return HolyStorm.Serializer:Serialize(value)end
local function tooltipDetails(slot)
 local enchantName,socketNames
 if not(C_TooltipInfo and C_TooltipInfo.GetInventoryItem)then return nil,{}end
 local data=C_TooltipInfo.GetInventoryItem("player",slot);socketNames={}
 local lineTypes=Enum and Enum.TooltipDataLineType
 for _,line in ipairs(data and data.lines or{})do
  if lineTypes and line.type==lineTypes.ItemEnchantmentPermanent then enchantName=line.leftText end
  if lineTypes and line.type==lineTypes.GemSocket then socketNames[#socketNames+1]=line.leftText end
 end
 return enchantName,socketNames
end
local function captureGem(itemLink,index,socketName)
 local gemName,gemLink;if C_Item.GetItemGem then gemName,gemLink=C_Item.GetItemGem(itemLink,index)end
 local gemId=C_Item.GetItemGemID and C_Item.GetItemGemID(itemLink,index)
 if not gemId then return{empty=true,name=socketName}end
 local cachedName,cachedLink,_,_,_,_,_,_,_,icon;if GetItemInfo then cachedName,cachedLink,_,_,_,_,_,_,_,icon=GetItemInfo(gemLink or gemId)end
 if not cachedName and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(gemId)end
 return{itemId=gemId,name=gemName or cachedName,link=gemLink or cachedLink,icon=icon,socketName=socketName}
end
local function isTierItem(itemId,setID)
 local getBonuses=C_Item and C_Item.GetSetBonusesForSpecializationByItemID;if not getBonuses then return setID~=nil end
 local index=C_SpecializationInfo and C_SpecializationInfo.GetSpecialization and C_SpecializationInfo.GetSpecialization()or(GetSpecialization and GetSpecialization())
 local specID;if index then if C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo then specID=C_SpecializationInfo.GetSpecializationInfo(index)elseif GetSpecializationInfo then specID=GetSpecializationInfo(index)end end
 if not specID then return setID~=nil end;local bonuses=getBonuses(specID,itemId);return type(bonuses)=="table"and next(bonuses)~=nil
end
local function captureItem(slot)
 local itemId=GetInventoryItemID("player",slot);local link=GetInventoryItemLink("player",slot);if not itemId then return false end;if not link then return nil,"ITEM_LINK_PENDING"end
 local itemString=link:match("|H(item:[^|]+)|h");local fields=itemString and{strsplit(":",itemString)}or{};local level=GetDetailedItemLevelInfo and GetDetailedItemLevelInfo(link)
 if not level then if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(itemId)end;return nil,"ITEM_DATA_PENDING"end
 local enchantName,socketNames=tooltipDetails(slot);local socketCount=C_Item and C_Item.GetItemNumSockets and C_Item.GetItemNumSockets(link)or#socketNames;socketCount=tonumber(socketCount)or#socketNames;local gems={}
 if C_Item then for index=1,socketCount do gems[index]=captureGem(link,index,socketNames[index])end end
 local quality=select(3,GetItemInfo(link));local setID=select(16,GetItemInfo(link))
 return{slot=slot,itemId=itemId,link=link,itemLevel=level,enchantId=tonumber(fields[3])or 0,enchantName=enchantName,gems=gems,sockets=socketCount,quality=quality,icon=GetInventoryItemTexture("player",slot),setID=setID,isTier=isTierItem(itemId,setID)}
end

HolyStorm:RegisterModule(metadata,function(Module)
 HolyStorm:ApplyModuleMetadata(Module,metadata)
 function Module:GetCharacterSnapshot(guid)local record=HolyStorm.Data.CharacterStore:Get(guid or UnitGUID("player"));return record and record.equipment,HolyStorm.Data.CharacterStore:GetBlockMetadata(guid,"equipment")end
 function Module:Collect()
  local snapshot={slots={},updatedAt=HolyStorm.Utils.Now(),snapshotVersion=4};local count=0
  for _,slot in ipairs(SLOTS)do local item,reason=captureItem(slot);if reason then snapshot.pending=reason end;snapshot.slots[slot]=item or false;if item then count=count+1 end end
  snapshot.equippedCount=count;snapshot.itemLevel=GetAverageItemLevel and select(2,GetAverageItemLevel())or 0;return snapshot
 end
 function Module:Validate(snapshot)
  if type(snapshot)~="table"or type(snapshot.slots)~="table"or snapshot.pending then return false,snapshot and snapshot.pending or"MISSING_SNAPSHOT"end
  for _,slot in ipairs(SLOTS)do if snapshot.slots[slot]==nil then return false,"MISSING_SLOT"end end
  local old=HolyStorm.Data.CharacterStore:Get(UnitGUID("player"));local oldCount=old and old.equipment and old.equipment.equippedCount or 0
  if snapshot.equippedCount==0 and oldCount>0 then local fp=fingerprint(snapshot.slots);if self.emptyCandidate~=fp then self.emptyCandidate=fp;return false,"SUDDEN_EMPTY_EQUIPMENT"end end
  self.emptyCandidate=nil;return true
 end
 function Module:Store(snapshot)
  local guid=UnitGUID("player")
  local changed=HolyStorm.PlayerData:WriteOwnedBlock(guid,"equipment",{equipment=snapshot,itemLevel=snapshot.itemLevel},"blizzard")
  return changed
 end
 function Module:RegisterWorkflow()
  HolyStorm.Tasks:RegisterTaskType("Equipment.Scan",{name=L["TASK_SCAN"],localizedNameKey="TASK_SCAN",module="Equipment",priority=25,executionMode="UNIQUE",conditions={"PLAYER_LOGGED_IN","PLAYER_READY","NOT_IN_COMBAT","NOT_LOADING","NOT_ZONING"},maxRetries=5,execute=function(task)local _,c=runtime(task);local snapshot=Module:Collect();c.data.snapshot=snapshot;return snapshot end})
  HolyStorm.Tasks:RegisterTaskType("Equipment.Validate",{name=L["TASK_VALIDATE"],localizedNameKey="TASK_VALIDATE",module="Equipment",priority=25,executionMode="UNIQUE",execute=function(task)local _,c=runtime(task);local valid,reason=Module:Validate(c.data.snapshot);if not valid then return{workflowAction="RETRY",gotoStep=1,delay=2.5,maxRetries=5,reason=reason}end;return{valid=true}end})
  HolyStorm.Tasks:RegisterTaskType("Equipment.Compare",{name=L["TASK_COMPARE"],localizedNameKey="TASK_COMPARE",module="Equipment",priority=25,executionMode="UNIQUE",execute=function(task)local _,c=runtime(task);local record=HolyStorm.Data.CharacterStore:Get(UnitGUID("player"));local old=record and record.equipment;local changed=fingerprint(c.data.snapshot)~=fingerprint(old);c.data.changed=changed;if not changed then return{workflowAction="COMPLETE",changed=false}end;return{changed=true}end})
  HolyStorm.Tasks:RegisterTaskType("Equipment.Store",{name=L["TASK_STORE"],localizedNameKey="TASK_STORE",module="Equipment",priority=25,executionMode="UNIQUE",execute=function(task)local _,c=runtime(task);c.data.stored=Module:Store(c.data.snapshot);return{stored=c.data.stored}end})
  HolyStorm.Workflows:Register(WORKFLOW,{name=L["WORKFLOW_EQUIPMENT_UPDATE"],localizedNameKey="WORKFLOW_EQUIPMENT_UPDATE",module="Equipment",priority=25,allowParallel=false,debounce=1,steps={{id="scan",taskType="Equipment.Scan"},{id="validate",taskType="Equipment.Validate"},{id="compare",taskType="Equipment.Compare"},{id="store",taskType="Equipment.Store"}}})
 end
 -- DE: Waerend RUNNING werden Trigger zu genau einem Pending-Restart verdichtet.
 -- EN: While RUNNING, triggers collapse into exactly one pending restart.
 function Module:Request(sync,triggerSource,debounce)
  local workflowId,state=HolyStorm.Workflows:Request(WORKFLOW,{triggerSource=triggerSource or"MANUAL",debounce=debounce or 1,context={sync=sync==true}})
  HolyStorm.Tasks:RecordEvent(triggerSource or"MANUAL","Equipment",{workflowId=workflowId,triggeredTask="Equipment.Scan"});return workflowId,state
 end
 function Module:RefreshPage()
  if not self.page or not self.page:IsShown()then return end;local r=HolyStorm.Data.CharacterStore:Get(UnitGUID("player"));local lines={};local _,active=HolyStorm.Workflows:IsRunning(WORKFLOW);local workflowStatus=active and active.status
  if not workflowStatus then for _,workflow in ipairs(HolyStorm.Workflows:GetHistory())do if workflow.workflowType==WORKFLOW then workflowStatus=workflow.status;break end end end
  if workflowStatus then lines[#lines+1]=string.format(L["WORKFLOW_STATUS"],L["STATUS_"..workflowStatus]or workflowStatus)end
  for _,slot in ipairs(SLOTS)do local item=r and r.equipment and r.equipment.slots[slot];lines[#lines+1]=string.format("%d: %s",slot,item and item.link or L["EMPTY_SLOT"])end;self.content:SetText(table.concat(lines,"\n"))
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
