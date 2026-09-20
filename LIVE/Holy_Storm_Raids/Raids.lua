local addonVersion="5.2.0"
local HolyStorm=LibStub("AceAddon-3.0"):GetAddon("Holy_Storm");local L=LibStub("AceLocale-3.0"):GetLocale("Holy_Storm_Raids")
if HolyStorm.PlayerData then HolyStorm.PlayerData:RegisterBlock("raid",{fields={"raidLockouts"},event="HS_RAIDLOCKS_UPDATED",staleAfter=21600})end
local metadata={id="raids",name="Raids",displayName=L["DISPLAY_NAME"],description=L["DESCRIPTION"],version=addonVersion,moduleType="feature",category="feature",permissions={{id="raids-read",category="Raid",defaults={member=true}},"sync-send"},dependencies={"core","synchronization","ui"},capabilities={"character.scan.raids"},ui={characterTab="raid"},data={block="raid",snapshotType="raids",schemaVersion=3,capability="character.scan.raids"},sync={domains={"character"}},enabledByDefault=true,ruleFields={{id="raid.progress",aliases={"raidProgress"},type="number",name=L["RULE_FIELD_PROGRESS"],nameKey="RULE_FIELD_PROGRESS",description=L["RULE_FIELD_PROGRESS_DESC"],descriptionKey="RULE_FIELD_PROGRESS_DESC",category=L["DISPLAY_NAME"],dependencies={"raid"},unit="bosses",resolver=function(context)local block=context.character and context.character.raid or HolyStorm.Data.CharacterStore:GetBlock(context.characterUUID,"raid");local progress=block and block.bestProgress;return progress and tonumber(progress.killed)or nil end}}}
HolyStorm:RegisterModule(metadata,function(Module)
 HolyStorm:ApplyModuleMetadata(Module,metadata)
 local difficultyKeys={[7]="LFR",[17]="LFR",[14]="NORMAL",[15]="HEROIC",[16]="MYTHIC"};local difficultyOrder={LFR=1,NORMAL=2,HEROIC=3,MYTHIC=4}
 local function raidKey(name)return type(name)=="string"and name:lower():gsub("[%s%p%c]+","")or nil end
 local function ensureEncounterJournal()
  if EJ_GetNumTiers and EJ_SelectTier and EJ_GetInstanceByIndex then return true end
  local loader=C_AddOns and C_AddOns.LoadAddOn or LoadAddOn;if loader then pcall(loader,"Blizzard_EncounterJournal")end
  return EJ_GetNumTiers and EJ_SelectTier and EJ_GetInstanceByIndex and true or false
 end
 function Module:GetCharacterSnapshot(guid)return HolyStorm.Data.CharacterStore:GetRaidLockouts(guid),HolyStorm.Data.CharacterStore:GetBlockMetadata(guid,"raid")end
 function Module:GetLatestRaid()
  local raids,tier=self:GetCurrentRaidCatalog();local raid=raids[1];return raid and{id=raid.id,name=raid.name,tier=tier}or nil
 end
 function Module:GetCurrentRaidCatalog()
  if not ensureEncounterJournal()then return{},nil,false end;local tier=EJ_GetNumTiers();if not tier or tier<1 then return{},nil,false end
  local previousTier=EJ_GetCurrentTier and EJ_GetCurrentTier();EJ_SelectTier(tier);local raids={};local index=1
  while true do local id,name,_,_,buttonImage=EJ_GetInstanceByIndex(index,true);if not id then break end;local raid={id=id,name=name,icon=buttonImage,tier=tier,order=index,bosses={}};if EJ_SelectInstance and EJ_GetEncounterInfoByIndex then EJ_SelectInstance(id);local encounterIndex=1;while true do local bossName,_,bossId=EJ_GetEncounterInfoByIndex(encounterIndex,id);if not bossName then break end;raid.bosses[#raid.bosses+1]={id=bossId or encounterIndex,name=bossName,order=encounterIndex};encounterIndex=encounterIndex+1 end end;raids[#raids+1]=raid;index=index+1 end
  if previousTier and previousTier~=tier then EJ_SelectTier(previousTier)end;return raids,tier,#raids>0
 end
 function Module:Collect()
  local raids,tier,catalogReady=self:GetCurrentRaidCatalog();local latest=raids[1]and{id=raids[1].id,name=raids[1].name,tier=tier}or nil;local currentByName={};for _,raid in ipairs(raids)do currentByName[raidKey(raid.name)]=raid end
  local old=self:GetCharacterSnapshot(UnitGUID("player"));local lifetime=HolyStorm.Utils.DeepCopy(type(old)=="table"and old.lifetime or{bosses={},seen={}});lifetime.bosses=type(lifetime.bosses)=="table"and lifetime.bosses or{};lifetime.seen=type(lifetime.seen)=="table"and lifetime.seen or{}
  local s={currentRaid=latest,currentTier=tier,catalogReady=catalogReady,raids=raids,lockouts={},lifetime=lifetime,updatedAt=HolyStorm.Utils.Now(),snapshotVersion=3,bestProgress={killed=0,total=0,difficultyId=0}}
  for i=1,(GetNumSavedInstances and GetNumSavedInstances()or 0)do
   local name,id,reset,diff,locked,extended,_,isRaid,maxPlayers,diffName,encounters,encounterProgress=GetSavedInstanceInfo(i)
   if isRaid and locked then
    local bosses,killed={},0
    for x=1,encounters or 0 do
     local bossName,bossId,done=GetSavedInstanceEncounterInfo(i,x);bossName=bossName or((name or L["UNKNOWN"]).." #"..x);bossId=bossId or(name..":"..x);bosses[x]={name=bossName,id=bossId,killed=done==true}
     if done then
      killed=killed+1;local seenKey=table.concat({tostring(id),tostring(diff),tostring(bossId)},":")
      if not lifetime.seen[seenKey]then lifetime.seen[seenKey]=true;local boss=lifetime.bosses[bossId]or{id=bossId,name=bossName,raidName=name,difficulties={}};boss.name=bossName or boss.name;boss.raidName=name or boss.raidName;boss.difficulties=type(boss.difficulties)=="table"and boss.difficulties or{};local difficulty=difficultyKeys[tonumber(diff)];if difficulty then local entry=boss.difficulties[difficulty]or{kills=0};entry.kills=(tonumber(entry.kills)or 0)+1;boss.difficulties[difficulty]=entry end;lifetime.bosses[bossId]=boss end
     end
    end
    killed=math.max(killed,tonumber(encounterProgress)or 0);local catalog=currentByName[raidKey(name)];local item={name=name,lockoutId=id,journalInstanceId=catalog and catalog.id,reset=reset,difficultyId=diff,difficultyName=diffName,extended=extended,maxPlayers=maxPlayers,bosses=bosses,killed=killed,total=encounters or 0,isCurrent=catalog~=nil};s.lockouts[#s.lockouts+1]=item
    local currentKey=difficultyKeys[tonumber(diff)];local bestKey=difficultyKeys[tonumber(s.bestProgress.difficultyId)];local currentOrder,bestOrder=difficultyOrder[currentKey]or 0,difficultyOrder[bestKey]or 0;if item.isCurrent and killed>0 and(currentOrder>bestOrder or(currentOrder==bestOrder and killed>s.bestProgress.killed))then s.bestProgress={killed=killed,total=encounters or 0,difficultyId=diff,difficultyName=diffName}end
   end
  end
  return s
 end
 function Module:Validate(s)if type(s)~="table"or type(s.lockouts)~="table"or type(s.raids)~="table"or type(s.lifetime)~="table"or type(s.lifetime.bosses)~="table"then return false,"instance data unavailable"end;for _,r in ipairs(s.lockouts)do if not r.name or not r.difficultyId or type(r.bosses)~="table"then return false,"lockout incomplete"end end;if not s.catalogReady and#s.lockouts==0 then return false,"raid catalog pending"end;return true end
 function Module:Commit(s)local guid=UnitGUID("player");return HolyStorm.Data.CharacterStore:SetRaidLockouts(guid,s,{updatedAt=s.updatedAt,updatedBy=guid},"blizzard")end
 function Module:Queue(sync,delay,requestRaidInfo)
  -- UPDATE_INSTANCE_INFO is the response to RequestRaidInfo(). Requesting the
  -- data again from that event creates a loop and keeps extending the debounce.
  if requestRaidInfo~=false and RequestRaidInfo then RequestRaidInfo()end
  return HolyStorm.Snapshots:Queue("raids",function()return Module:Collect()end,function(s)return Module:Validate(s)end,function(s,f)return Module:Commit(s,f,sync)end,{source="Raids",delay=delay or 1,retryDelay=2.5,priority=3})
 end
 function Module:RefreshPage()if not self.page or not self.page:IsShown()then return end;local r=HolyStorm.Data.CharacterStore:Get(UnitGUID("player"));local d=r and r.raidLockouts;local lines={};for _,raid in ipairs(d and d.lockouts or{})do lines[#lines+1]=string.format("%s — %s (%d/%d)",raid.name or L["UNKNOWN"],raid.difficultyName or"",raid.killed or 0,raid.total or 0)end;self.content:SetText(#lines>0 and table.concat(lines,"\n")or L["NO_LOCKOUTS"])end
 function Module:OnInitialize()HolyStorm:RegisterCapability("Raids","character.scan.raids",function(_,sync)return Module:Queue(sync,1)end)end
 function Module:OnEnable()for _,ev in ipairs({"UPDATE_INSTANCE_INFO","BOSS_KILL","ENCOUNTER_END","PLAYER_ENTERING_WORLD"})do local event=ev;HolyStorm.Events:Register(event,"raids",function()Module:Queue(true,event=="BOSS_KILL"and .5 or 1,event~="UPDATE_INSTANCE_INFO")end)end end
 function Module:OnDisable()HolyStorm.Events:UnregisterOwner("raids");HolyStorm.Snapshots:Cancel("raids")end
end)
