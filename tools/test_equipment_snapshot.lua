local root=(arg[0]:gsub("tools[/\\]test_equipment_snapshot.lua$",""))
local featureRoot=root.."LIVE/Holy_Storm_Equipment/"
local oldCharacter=nil
local equipmentIds,equipmentLinks={},{}
local equipmentBlock
local HolyStorm={Utils={Now=function()return 100 end,DeepCopy=function(value)return value end},Data={CharacterStore={Get=function()return oldCharacter end,GetBlock=function()return nil end}},PlayerData={RegisterBlock=function(_,id,definition)if id=="equipment"then equipmentBlock=definition end;return true end,FingerprintSnapshot=function(_,value)return tostring(value[INVSLOT_HEAD])end},Workflows={workflows={}},Serializer={Serialize=function()return"snapshot"end}}
function LibStub(name)if name=="AceAddon-3.0"then return{GetAddon=function()return HolyStorm end}end;return{GetLocale=function()return setmetatable({},{__index=function(_,key)return key end})end}end
function HolyStorm:RegisterModule(_,factory)local module={};factory(module);self.Equipment=module end
function HolyStorm:ApplyModuleMetadata()end
for index,name in ipairs({"HEAD","NECK","SHOULDER","CHEST","WAIST","LEGS","FEET","WRIST","HAND","FINGER1","FINGER2","TRINKET1","TRINKET2","BACK","MAINHAND","OFFHAND"})do _G["INVSLOT_"..name]=index end
local itemLink="|cffa335ee|Hitem:111:42::::::::80:70::1:2:999:888|h[Tier Helm]|h|r"
equipmentIds[INVSLOT_HEAD]=111;equipmentLinks[INVSLOT_HEAD]=itemLink
function GetInventoryItemID(_,slot)return equipmentIds[slot]end
function GetInventoryItemLink(_,slot)return equipmentLinks[slot]end
function GetInventoryItemTexture()return 900 end
function GetAverageItemLevel()return 700,705 end
function UnitGUID()return"Player-1"end
function strsplit(separator,text)local result={};for field in(text..separator):gmatch("(.-)"..separator)do result[#result+1]=field end;return table.unpack(result)end
Item={CreateFromEquipmentSlot=function(_,slot)return{IsItemEmpty=function()return equipmentIds[slot]==nil end,GetItemID=function()return equipmentIds[slot]end,GetItemLink=function()return equipmentLinks[slot]end}end}
C_Item={
 GetDetailedItemLevelInfo=function()return 710,false,710 end,
 GetItemInfo=function(value)if value==1001 or tostring(value):find("item:1001",1,true)then return"Quick Ruby","|cffa335ee|Hitem:1001|h[Quick Ruby]|h|r",4,nil,nil,nil,nil,nil,nil,901 end;return"Tier Helm",itemLink,4,nil,nil,nil,nil,nil,nil,900,nil,nil,nil,nil,nil,77 end,
 GetItemNumSockets=function()return 1 end,
 GetItemGem=function()return"Quick Ruby","|cffa335ee|Hitem:1001|h[Quick Ruby]|h|r"end,
 GetItemGemID=function()return 1001 end,
 RequestLoadItemDataByID=function()end,
}
Enum={TooltipDataLineType={GemSocket=3,ItemEnchantmentPermanent=15}}
C_TooltipInfo={GetInventoryItem=function()return{lines={{type=15,leftText="Sophic Devotion"},{type=3,leftText="Prismatic Socket"}}}end}
assert(loadfile(featureRoot.."Equipment.lua"))()
local module=HolyStorm.Equipment
local snapshot=module:Collect();local item=snapshot.slots[INVSLOT_HEAD]
assert(snapshot.snapshotVersion==4 and item.state=="EQUIPPED"and item.itemId==111,"equipped slot has an explicit state and item identity")
assert(item.link==itemLink,"original full item link is preserved verbatim")
assert(snapshot.equippedItemLevel==705 and snapshot.itemLevel==705 and snapshot.overallItemLevel==700,"Blizzard equipped and overall item levels have distinct fields")
assert(item.itemLevel==710 and item.quality==4 and item.icon==900,"effective item level, quality and icon are captured")
assert(item.setID==77 and item.isTier==nil,"ordinary item-set metadata is not promoted to tier membership")
assert(item.enchantId==42 and item.enchantName==nil,"enchant presence comes from the original item link, not localized tooltip text")
assert(item.sockets==1 and item.gems[1].state=="SOCKET_FILLED"and item.gems[1].name=="Quick Ruby"and item.gems[1].link:find("item:1001",1,true),"structured gem identity is retained")
assert(snapshot.slots[INVSLOT_NECK]==false,"an empty slot is recorded only after ItemLocation confirms it")
assert(module:Validate(snapshot)and equipmentBlock.validate({equipment=snapshot,itemLevel=snapshot.itemLevel}),"complete schema-4 snapshots pass module and PlayerData validation")
assert(module:GetEnchantState(snapshot,INVSLOT_HEAD)=="ENCHANTED"and module:GetSocketState(snapshot,INVSLOT_HEAD,1)=="SOCKET_FILLED","query helpers expose stable enchant and socket states")
local tierCount,reason=module:GetTierPieceCount(snapshot);assert(tierCount==nil and reason=="TIER_MEMBERSHIP_UNAVAILABLE","tier count remains unavailable without authoritative membership data")

C_Item.GetItemGemID=function()return nil end
snapshot=module:Collect();assert(snapshot.slots[INVSLOT_HEAD].gems[1].state=="SOCKET_UNKNOWN"and module:GetSocketState(snapshot,INVSLOT_HEAD,1)=="SOCKET_UNKNOWN","missing gem data is not interpreted as an empty socket")
C_Item.GetItemGemID=function()return 1001 end
C_Item.GetItemNumSockets=function()return 0 end
snapshot=module:Collect();assert(snapshot.slots[INVSLOT_HEAD].sockets==0 and module:GetSocketState(snapshot,INVSLOT_HEAD,1)=="NO_SOCKET","a structured zero socket count differs from a missing gem result")
C_Item.GetItemNumSockets=function()return 1 end

local averageItemLevel=GetAverageItemLevel
GetAverageItemLevel=function()return nil,705 end
snapshot=module:Collect();assert(snapshot.pending=="CHARACTER_ITEM_LEVEL_PENDING"and not equipmentBlock.validate({equipment=snapshot,itemLevel=snapshot.itemLevel}),"unready Blizzard character item level cannot reach PlayerData")
GetAverageItemLevel=averageItemLevel

oldCharacter={equipment={equippedCount=1}}
local originalEmpty=Item.CreateFromEquipmentSlot
Item.CreateFromEquipmentSlot=function()return{IsItemEmpty=function()return nil end}end
equipmentIds[INVSLOT_NECK]=nil;equipmentLinks[INVSLOT_NECK]=nil
snapshot=module:Collect();assert(snapshot.pending=="SLOT_STATE_UNKNOWN"and snapshot.slots[INVSLOT_NECK]==nil,"unavailable slot status remains unknown rather than empty")
local firstValid,firstReason=module:Validate(snapshot);assert(not firstValid and firstReason=="SLOT_STATE_UNKNOWN","incomplete slot scan cannot commit")
Item.CreateFromEquipmentSlot=originalEmpty

equipmentIds[INVSLOT_NECK]=222;equipmentLinks[INVSLOT_NECK]=nil
snapshot=module:Collect();assert(snapshot.pending=="ITEM_LINK_PENDING"and snapshot.slots[INVSLOT_NECK]==nil,"present item without its link is incomplete, not empty")
equipmentIds[INVSLOT_NECK]=nil

equipmentIds[INVSLOT_HEAD]=112
snapshot=module:Collect();assert(snapshot.pending=="ITEM_ID_LINK_MISMATCH","inconsistent ID and full item link invalidate the whole scan")
equipmentIds[INVSLOT_HEAD]=111

equipmentIds[INVSLOT_HEAD]=nil;equipmentLinks[INVSLOT_HEAD]=nil
snapshot=module:Collect();local firstEmpty,emptyReason=module:Validate(snapshot);assert(not firstEmpty and emptyReason=="SUDDEN_EMPTY_EQUIPMENT","first sudden-empty scan is rejected")
assert(module:Validate(snapshot),"second matching full scan confirms genuine empty equipment")
assert(module:Validate(snapshot),"separate stability scan confirms the same empty candidate")
print("Equipment rich snapshot tests passed")
