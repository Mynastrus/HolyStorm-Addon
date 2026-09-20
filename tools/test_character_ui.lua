local root=(arg[0]:gsub("tools[/\\]test_character_ui.lua$","")).."LIVE/Holy_Storm/"
local featureRoot=(arg[0]:gsub("tools[/\\]test_character_ui.lua$","")).."LIVE/Holy_Storm_Characters/"
local function deepCopy(value,seen)if type(value)~="table"then return value end;seen=seen or{};if seen[value]then return seen[value]end;local out={};seen[value]=out;for key,child in pairs(value)do out[deepCopy(key,seen)]=deepCopy(child,seen)end;return out end
local records={A={guid="A",name="Alpha",realm="Realm",classFile="PALADIN",level=80,equipment={itemLevel=710,slots={}},itemLevel=710,stats={spec={id=70,name="Retribution",icon=98765,index=3,role="DAMAGER"}}},B={guid="B",name="Beta-OtherRealm",classFile="MAGE",class="Mage",level=75,faction="Horde"},C={guid="C",name="Gamma",stats={primary={}}},D={guid="D",name="Delta",realm="Realm",classFile="DRUID",level=70}}
local metas={A={equipment={version=2,updatedAt=100}}}
local refreshes={}
local HolyStorm={Utils={DeepCopy=deepCopy},Data={CharacterStore={},GuildStore={},PlayerStore={}},PlayerData={},Tasks={registry={},queued={}},Policy={}}
function HolyStorm:GetAddon()return self end
function LibStub()return HolyStorm end
function UnitGUID()return"LOCAL"end
LOCALIZED_CLASS_NAMES_MALE={PALADIN="Paladin",MAGE="Mage",DRUID="Druid"}
function HolyStorm.Data.CharacterStore:Get(guid)return records[guid]end
function HolyStorm.Data.CharacterStore:GetBlock(guid,block)local record=records[guid];if not record then return nil end;if block=="equipment"then return{equipment=record.equipment,itemLevel=record.itemLevel},deepCopy(metas[guid]and metas[guid][block])end;return record[block],deepCopy(metas[guid]and metas[guid][block])end
function HolyStorm.Data.CharacterStore:RequestRefresh(guid,blocks)refreshes[#refreshes+1]={guid=guid,blocks=blocks};return true end
function HolyStorm.Data.CharacterStore:CaptureCurrent()return records.LOCAL end
function HolyStorm.Data.GuildStore:GetCurrent()return{id="guild",roster={A={name="Alpha",rank="Officer",rankIndex=1,classFile="PALADIN",level=80},D={name="Delta",rank="Member",class="Druid",classFile="DRUID",level=70}}}end
function HolyStorm.Data.PlayerStore:GetCharacterOwner(guid)return"account-"..guid end
function HolyStorm.PlayerData:IsStale(guid,block)return guid=="A"and block=="equipment"end
HolyStorm.TwinkCore={GetAccountUUIDForCharacter=function(_,guid)return"account-"..guid end,GetRosterIdentity=function(_,guid)return guid=="B"and{accountMain="A",guildMain="A"}or nil end}
function HolyStorm.Tasks:GetTaskType(id)return self.registry[id]end
function HolyStorm.Tasks:Queue(id,options)self.queued[#self.queued+1]={id=id,options=deepCopy(options)};return"task-"..#self.queued end
function HolyStorm.Policy:Can()return true end
function HolyStorm.Policy:IsGuildModuleEnabled()return true end
RAID_CLASS_COLORS={PALADIN={r=1,g=.5,b=.8,WrapTextInColorCode=function(_,text)return"|cffff80cc"..text.."|r"end},MAGE={r=.2,g=.8,b=1}};LEVEL="Level";GameTooltip={lines={},wraps={}};function GameTooltip:SetOwner()end;function GameTooltip:SetText(text,r,g,b)self.title,self.titleColor=text,{r=r,g=g,b=b}end;function GameTooltip:AddLine(text,r,g,b,wrap)self.lines[#self.lines+1]=text;self.wraps[#self.lines]=wrap end;function GameTooltip:Show()self.shown=true end

assert(loadfile(featureRoot.."UI/CharacterUI.lua"))()
local C=HolyStorm.CharacterUI

local dummy=function()end
assert(C:RegisterTab({id="raid",order=40,labelKey="RAID",build=dummy,refresh=dummy}))
assert(C:RegisterTab({id="summary",order=10,labelKey="SUMMARY",build=dummy,refresh=dummy}))
assert(C:RegisterTab({id="equipment",order=20,labelKey="EQUIPMENT",build=dummy,refresh=dummy}))
local tabs=C:GetTabs();assert(tabs[1].id=="summary"and tabs[2].id=="equipment"and tabs[3].id=="raid","tab registry order")

local a=C:SetContext("A");assert(a.characterUUID=="A"and a.accountUUID=="account-A"and a.className=="Paladin"and a.member.rankIndex==1 and a.spec.name=="Retribution"and a.spec.icon==98765)
local d=C:ResolveContext("D");assert(d.className=="Druid","ResolveContext falls back to GuildStore member.class")
local token=a.token;local equipment,meta=C:GetSnapshot("A","equipment");assert(equipment.itemLevel==710 and meta.version==2);assert(C:GetDataStatus("A","equipment")=="STALE")
local b=C:SetContext("B");assert(b.characterUUID=="B"and not C:IsCurrent("A",token)and C:IsCurrent("B",b.token),"stale context guard")
assert(b.name=="Beta"and b.realm=="OtherRealm"and b.fullName=="Beta-OtherRealm","ResolveContext splits Name-Realm into name, realm and retained fullName")
assert(C:ShowTooltip({},"B")and GameTooltip.title=="Beta"and GameTooltip.titleColor.g==.8,"tooltip title omits the realm and uses the character class color");assert(GameTooltip.lines[1]:find("OtherRealm | Mage | Level 75",1,true)and GameTooltip.lines[1]:find("PlusManz%-Horde")and GameTooltip.wraps[1]==false,"tooltip identity line contains a faction indicator and disables wrapping: "..tostring(GameTooltip.lines[1]).." / "..tostring(GameTooltip.wraps[1]));local coloredMain=false;for _,line in ipairs(GameTooltip.lines)do if line:find("ACCOUNT_MAIN: |cffff80ccAlpha|r",1,true)then coloredMain=true end end;assert(coloredMain,"tooltip colors the main character with the main character's own class")

local raid={raids={{name="Raid One",bosses={{},{}}}},lifetime={bosses={
 bossA={name="Boss A",raidName="Raid One",difficulties={LFR={kills=5},NORMAL={kills=2},HEROIC={kills=7},MYTHIC={kills=1}}},
 bossB={name="Boss B",raidName="Raid One",difficulties={LFR={kills=5},NORMAL={kills=2}}},
}}}
local rows=C:BuildRaidBestRows(raid);assert(#rows==2);assert(rows[1].bossName=="Boss A"and rows[1].difficulty=="MYTHIC"and rows[1].kills==1);assert(rows[2].difficulty=="NORMAL"and rows[2].kills==2)
local best=C:GetBestProgress(raid,"Raid One");assert(best.difficulty=="MYTHIC"and best.killed==1 and best.total==2)
assert(C:GetDifficultyById(7).id=="LFR"and C:GetDifficultyById(14).id=="NORMAL"and C:GetDifficultyById(15).id=="HEROIC"and C:GetDifficultyById(16).id=="MYTHIC")
assert(C:GetDifficultyColor("LFR").r==1 and C:GetDifficultyColor("NORMAL").g==1 and C:GetDifficultyColor("HEROIC").b==1 and C:GetDifficultyColor("MYTHIC").r==.70)

HolyStorm.Tasks.registry["Character.Refresh"]={};assert(C:RequestRefresh("A",{"equipment"},"TEST"));assert(C:RequestRefresh("A",{"raid"},"TEST_MERGE"));local queued=HolyStorm.Tasks.queued[1];assert(queued.options.mergeKey=="A"and queued.options.metadata.characterUUID=="A");assert(C:ConsumeRefresh("A"));assert(refreshes[#refreshes].guid=="A"and refreshes[#refreshes].blocks[1]=="equipment"and refreshes[#refreshes].blocks[2]=="raid","refresh block coalescing")
local queueCount=#HolyStorm.Tasks.queued;assert(C:RequestRefresh("C",{"stats"},"CHARACTER_OPEN"));assert(#HolyStorm.Tasks.queued==queueCount,"current blocks are not refreshed on open")
HolyStorm.Tasks.registry["Character.Refresh"]=nil;assert(C:RequestRefresh("B",{"raid"},"TEST"));assert(refreshes[#refreshes].guid=="B"and refreshes[#refreshes].blocks[1]=="raid")

print("Character UI registry, context, refresh and raid presentation tests passed")
