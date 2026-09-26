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
 bossA={name="Boss A",raidName="Raid One",difficulties={LFR={kills=5,source="blizzard-statistic",statisticId=1},NORMAL={kills=2,source="blizzard-statistic",statisticId=2},HEROIC={kills=7,source="blizzard-statistic",statisticId=3},MYTHIC={kills=1,source="blizzard-statistic",statisticId=4}}},
 bossB={name="Boss B",raidName="Raid One",difficulties={LFR={kills=5,source="blizzard-statistic",statisticId=5},NORMAL={kills=2,source="blizzard-statistic",statisticId=6}}},
}}}
local rows=C:BuildRaidBestRows(raid);assert(#rows==2);assert(rows[1].bossName=="Boss A"and rows[1].difficulty=="MYTHIC"and rows[1].kills==1);assert(rows[2].difficulty=="NORMAL"and rows[2].kills==2)
local best=C:GetBestProgress(raid,"Raid One");assert(best.difficulty=="MYTHIC"and best.killed==1 and best.total==2)
local function progressSnapshot(difficulties)
 local snapshot={raids={{id=800,name="Progress Raid",bosses={}}},lifetime={bosses={}}}
 for index=1,8 do snapshot.raids[1].bosses[index]={id=8000+index,name="Progress Boss "..index};local entries=difficulties[index];if entries then local stored={id=8000+index,name="Progress Boss "..index,raidInstanceId=800,raidName="Progress Raid",difficulties={}};for difficulty,value in pairs(entries)do local details=type(value)=="table"and value or{};local statisticId=details.statisticId;if statisticId==nil then statisticId=9000+index elseif statisticId==false then statisticId=nil end;stored.difficulties[difficulty]={kills=details.kills or value,source=details.source or"blizzard-statistic",statisticId=statisticId}end;snapshot.lifetime.bosses[8000+index]=stored end end
 return snapshot
end
local normalHeroic=progressSnapshot({{NORMAL=3,HEROIC=1},{NORMAL=2},{NORMAL=4},{NORMAL=5},{NORMAL=6},{NORMAL=7}});local normalHeroicBest=C:GetBestProgress(normalHeroic,{instanceId=800,name="Progress Raid"});assert(normalHeroicBest.difficulty=="HEROIC"and normalHeroicBest.killed==1 and normalHeroicBest.total==8,"Normal 6/8 plus Heroic 1/8 displays Heroic 1/8")
local heroicMythic=progressSnapshot({{HEROIC=9,MYTHIC=27},{HEROIC=4,MYTHIC=1},{HEROIC=2},{HEROIC=3},{HEROIC=5},{HEROIC=6},{HEROIC=7},{HEROIC=8}});local heroicMythicBest=C:GetBestProgress(heroicMythic,"Progress Raid");assert(heroicMythicBest.difficulty=="MYTHIC"and heroicMythicBest.killed==2 and heroicMythicBest.total==8,"Heroic 8/8 plus Mythic 2/8 displays Mythic 2/8")
local normalOnly=C:GetBestProgress(progressSnapshot({{NORMAL=1},{NORMAL=1},{NORMAL=1},{NORMAL=1},{NORMAL=1},{NORMAL=1}}),"Progress Raid");assert(normalOnly.difficulty=="NORMAL"and normalOnly.killed==6 and normalOnly.total==8,"Normal-only lifetime progress remains Normal 6/8")
local lfrOnly=C:GetBestProgress(progressSnapshot({{LFR=1},{LFR=1},{LFR=1},{LFR=1}}),"Progress Raid");assert(lfrOnly.difficulty=="LFR"and lfrOnly.killed==4 and lfrOnly.total==8,"LFR-only lifetime progress remains LFR 4/8")
local repeatedKills=progressSnapshot({{NORMAL=27}});repeatedKills.lifetime.bosses.duplicate=deepCopy(repeatedKills.lifetime.bosses[8001]);local repeatedRows=C:BuildRaidBestRows(repeatedKills);local repeatedBest=C:GetBestProgress(repeatedKills,"Progress Raid");assert(repeatedBest.killed==1 and repeatedRows[1].kills==27,"27 kills and duplicate records of one boss count as one progress boss while retaining the real kill count")
local legacyOnly=progressSnapshot({{NORMAL={kills=8,source="legacy-local-observation"}},{HEROIC={kills=3,source="observed"}},{MYTHIC={kills=1,statisticId=false}}});assert(C:GetBestProgress(legacyOnly,"Progress Raid")==nil and#C:BuildRaidBestRows(legacyOnly)==0,"legacy, observed and missing-statistic values never become lifetime Best")
local unknown=progressSnapshot({});assert(C:GetBestProgress(unknown,"Progress Raid")==nil,"unknown lifetime progress stays unknown")
local identityRaid={raids={{id=100,name="Raid One",bosses={{},{}}},{id=200,name="Raid Two",bosses={{},{},{}}}},bestProgress={difficultyId=14,killed=3,total=3,raidInstanceId=200,raidName="Raid Two"},lifetime={bosses={
 one={id=1,name="Boss One",raidInstanceId=100,raidName="Raid One",difficulties={HEROIC={kills=4,source="blizzard-statistic",statisticId=10}}},
 two={id=2,name="Boss Two",raidInstanceId=200,raidName="Raid One",difficulties={MYTHIC={kills=7,source="blizzard-statistic",statisticId=11}}},
}}}
local raidOneBest=C:GetBestProgress(identityRaid,{instanceId=100,name="Raid One"});assert(raidOneBest.difficulty=="HEROIC"and raidOneBest.killed==1 and raidOneBest.total==2,"stable raid IDs take precedence over a stale matching name")
local raidTwoBest=C:GetBestProgress(identityRaid,{instanceId=200,name="Raid Two"});assert(raidTwoBest.difficulty=="MYTHIC"and raidTwoBest.killed==1 and raidTwoBest.total==3,"matching stable raid IDs remain authoritative even when a stored name is stale")
assert(C:GetBestProgress(identityRaid,{instanceId=300,name="Raid Three"})==nil,"a scoped raid never inherits global bestProgress")
assert(C:GetDifficultyById(7).id=="LFR"and C:GetDifficultyById(14).id=="NORMAL"and C:GetDifficultyById(15).id=="HEROIC"and C:GetDifficultyById(16).id=="MYTHIC"and C:GetDifficultyById(33).id=="TIMEWALKING")
assert(C:GetDifficultyColor("LFR").r==1 and C:GetDifficultyColor("NORMAL").g==1 and C:GetDifficultyColor("HEROIC").b==1 and C:GetDifficultyColor("MYTHIC").r==.70)

records.A.mythicPlus={seasonId=18,overallScore=2500,scoreDataReady=true}
records.A.raid={catalogReady=true,raids={{id=100,name="Current One",order=1,bosses={{},{}}},{id=200,name="Current Two",order=2,bosses={{},{},{}}}},lifetime={bosses={
 currentOne={id=1,name="Current Boss One",raidInstanceId=100,raidName="Current One",difficulties={NORMAL={kills=2,source="blizzard-statistic",statisticId=21}}},
 currentTwo={id=2,name="Current Boss Two",raidInstanceId=200,raidName="Current Two",difficulties={HEROIC={kills=1,source="blizzard-statistic",statisticId=22}}},
 oldRaid={id=3,name="Old Boss",raidInstanceId=999,raidName="Old Expansion",difficulties={MYTHIC={kills=10,source="blizzard-statistic",statisticId=23}}},
}}}
local dashboard=C:GetDashboardSummary("A")
assert(dashboard.name=="Alpha"and dashboard.coloredName=="|cffff80ccAlpha|r"and dashboard.specName=="Retribution"and dashboard.specIcon==98765,"dashboard identity uses resolved short name, safe class color and stored specialization")
assert(dashboard.itemLevel==710 and dashboard.mythicPlusRating==2500,"dashboard query reuses Equipment and Mythic+ snapshots")
assert(dashboard.bestRaid.difficulty=="HEROIC"and dashboard.bestRaid.killed==1 and dashboard.bestRaid.total==3 and dashboard.bestRaid.raidName=="Current Two","dashboard best raid uses established priority across only current-expansion catalog raids")
records.C.equipment={itemLevel=0,slots={}};local missingDashboard=C:GetDashboardSummary("C");assert(missingDashboard.itemLevel==nil and missingDashboard.mythicPlusRating==nil and missingDashboard.bestRaid==nil,"dashboard query leaves unavailable producer data unknown")
records.A.raid=nil

HolyStorm.Tasks.registry["Character.Refresh"]={};assert(C:RequestRefresh("A",{"equipment"},"TEST"));assert(C:RequestRefresh("A",{"raid"},"TEST_MERGE"));local queued=HolyStorm.Tasks.queued[1];assert(queued.options.mergeKey=="A"and queued.options.metadata.characterUUID=="A");assert(C:ConsumeRefresh("A"));assert(refreshes[#refreshes].guid=="A"and refreshes[#refreshes].blocks[1]=="equipment"and refreshes[#refreshes].blocks[2]=="raid","refresh block coalescing")
local queueCount=#HolyStorm.Tasks.queued;assert(C:RequestRefresh("C",{"stats"},"CHARACTER_OPEN"));assert(#HolyStorm.Tasks.queued==queueCount,"current blocks are not refreshed on open")
HolyStorm.Tasks.registry["Character.Refresh"]=nil;assert(C:RequestRefresh("B",{"raid"},"TEST"));assert(refreshes[#refreshes].guid=="B"and refreshes[#refreshes].blocks[1]=="raid")

print("Character UI registry, context, refresh and raid presentation tests passed")
