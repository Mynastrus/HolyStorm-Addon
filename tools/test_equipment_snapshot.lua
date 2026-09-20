local root=(arg[0]:gsub("tools[/\\]test_equipment_snapshot.lua$","")).."LIVE/Holy_Storm/"
local featureRoot=(arg[0]:gsub("tools[/\\]test_equipment_snapshot.lua$","")).."LIVE/Holy_Storm_Equipment/"
local HolyStorm={Utils={Now=function()return 100 end,DeepCopy=function(value)return value end},Workflows={workflows={}},Serializer={Serialize=function()return"snapshot"end}}
function LibStub(name)if name=="AceAddon-3.0"then return{GetAddon=function()return HolyStorm end}end;return{GetLocale=function()return setmetatable({},{__index=function(_,key)return key end})end}end
function HolyStorm:RegisterModule(_,factory)local module={};factory(module);self.Equipment=module end
function HolyStorm:ApplyModuleMetadata()end
for index,name in ipairs({"HEAD","NECK","SHOULDER","CHEST","WAIST","LEGS","FEET","WRIST","HAND","FINGER1","FINGER2","TRINKET1","TRINKET2","BACK","MAINHAND","OFFHAND"})do _G["INVSLOT_"..name]=index end
local itemLink="|cffa335ee|Hitem:111:42::::::::80:70:::::::|h[Tier Helm]|h|r"
function GetInventoryItemID(_,slot)return slot==INVSLOT_HEAD and 111 or nil end
function GetInventoryItemLink(_,slot)return slot==INVSLOT_HEAD and itemLink or nil end
function GetInventoryItemTexture()return 900 end
function GetDetailedItemLevelInfo()return 710 end
function GetAverageItemLevel()return 700,705 end
function GetItemInfo(value)if value==1001 or tostring(value):find("item:1001",1,true)then return"Quick Ruby","|cffa335ee|Hitem:1001|h[Quick Ruby]|h|r",4,nil,nil,nil,nil,nil,nil,901 end;return"Tier Helm",itemLink,4,nil,nil,nil,nil,nil,nil,900,nil,nil,nil,nil,nil,77 end
function UnitGUID()return"Player-1"end
function strsplit(separator,text)local result={};for field in(text..separator):gmatch("(.-)"..separator)do result[#result+1]=field end;return table.unpack(result)end
C_Item={GetItemNumSockets=function()return 1 end,GetItemGem=function()return"Quick Ruby","|cffa335ee|Hitem:1001|h[Quick Ruby]|h|r"end,GetItemGemID=function()return 1001 end,GetSetBonusesForSpecializationByItemID=function(specID,itemID)assert(specID==70 and itemID==111);return{12345}end,RequestLoadItemDataByID=function()end}
C_SpecializationInfo={GetSpecialization=function()return 1 end,GetSpecializationInfo=function()return 70 end}
Enum={TooltipDataLineType={GemSocket=3,ItemEnchantmentPermanent=15}}
C_TooltipInfo={GetInventoryItem=function()return{lines={{type=15,leftText="Sophic Devotion"},{type=3,leftText="Prismatic Socket"}}}end}
assert(loadfile(featureRoot.."Equipment.lua"))()
local snapshot=HolyStorm.Equipment:Collect();local item=snapshot.slots[INVSLOT_HEAD]
assert(snapshot.snapshotVersion==4 and item.isTier==true and item.setID==77,"item-set metadata is captured")
assert(item.enchantId==42 and item.enchantName=="Sophic Devotion","enchantment ID and tooltip name are captured")
assert(item.sockets==1 and item.gems[1].name=="Quick Ruby"and item.gems[1].link:find("item:1001",1,true)and item.gems[1].icon==901,"gem name, link and icon are captured")
print("Equipment rich snapshot tests passed")
