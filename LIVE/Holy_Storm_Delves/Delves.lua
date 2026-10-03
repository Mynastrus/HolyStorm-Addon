local addonVersion="2.2.0"
local HolyStorm=LibStub("AceAddon-3.0"):GetAddon("Holy_Storm");local L=LibStub("AceLocale-3.0"):GetLocale("Holy_Storm_Delves")

local function validNumber(value,minimum,integer)
 return type(value)=="number"and value==value and value~=math.huge and value~=-math.huge and value>=minimum and(not integer or value%1==0)
end
local function validSnapshot(snapshot)
 if type(snapshot)~="table"or snapshot.snapshotVersion~=3 or snapshot.schemaVersion~=3 then return false,"INVALID_DELVES_SNAPSHOT"end
 if not validNumber(snapshot.seasonNumber,1,true)or not validNumber(snapshot.weeklyIdentity,1,true)then return false,"INVALID_DELVES_CONTEXT"end
 local greatVault,world=snapshot.greatVault,snapshot.greatVaultWorld
 if type(greatVault)~="table"or greatVault.currentPeriod~=true or type(greatVault.rewardAvailable)~="boolean"then return false,"INVALID_DELVES_VAULT"end
 if world~=nil then
  if type(world)~="table"or not validNumber(world.progress,0,true)or type(world.completed)~="table"or type(world.activities)~="table"then return false,"INVALID_DELVES_WORLD_PROGRESS"end
  local ids,indexes,completed={}, {},{}
  for _,activity in ipairs(world.activities)do
   if type(activity)~="table"or not validNumber(activity.id,1,true)or not validNumber(activity.index,1,true)or not validNumber(activity.progress,0,false)or not validNumber(activity.threshold,0,false)then return false,"INVALID_DELVES_ACTIVITY"end
   if ids[activity.id]or indexes[activity.index]then return false,"DUPLICATE_DELVES_ACTIVITY"end
   ids[activity.id]=true;indexes[activity.index]=true
   if activity.progress>=activity.threshold then completed[activity.index]=true end
  end
  local seen,count={},0
  for _,index in ipairs(world.completed)do if not validNumber(index,1,true)or not completed[index]or seen[index]then return false,"INVALID_DELVES_COMPLETION"end;seen[index]=true;count=count+1 end
  if count~=world.progress then return false,"INVALID_DELVES_PROGRESS"end
  for index in pairs(completed)do if not seen[index]then return false,"INVALID_DELVES_COMPLETION"end end
 end
 return true
end

if HolyStorm.PlayerData then HolyStorm.PlayerData:RegisterBlock("delves",{fields={"delves"},event="HS_DELVES_UPDATED",staleAfter=21600,owner="delves",schemaVersion=3,snapshotVersion=3,capability="character.scan.delves",scanProvider="delves",validate=validSnapshot})end
local metadata={id="delves",name="Delves",displayName=L["DISPLAY_NAME"],description=L["DESCRIPTION"],version=addonVersion,moduleType="feature",category="feature",permissions={"sync-send"},dependencies={"core"},capabilities={"character.scan.delves","character.scan.additional"},ui={},options={},administration={},data={block="delves",snapshotType="delves",schemaVersion=3,capabilities={"character.scan.delves","character.scan.additional"}},sync={domains={"character"}},enabledByDefault=true,ruleFields={{id="delves.status",aliases={"delveStatus"},type="number",name=L["RULE_FIELD_STATUS"],nameKey="RULE_FIELD_STATUS",description=L["RULE_FIELD_STATUS_DESC"],descriptionKey="RULE_FIELD_STATUS_DESC",category=L["DISPLAY_NAME"],dependencies={"delves"},unit="progress",resolver=function(context)local block=context.character and context.character.delves or HolyStorm.Data.CharacterStore:GetBlock(context.characterUUID,"delves");local vault=block and block.greatVaultWorld;return vault and tonumber(vault.progress)or nil end}}}

local function safeNumber(value)
 if value==nil or issecretvalue and issecretvalue(value)or type(value)~="number"or value~=value or value==math.huge or value==-math.huge then return nil end
 return value
end
local function safeCall(fn,...)
 if type(fn)~="function"then return false,nil,"API_UNAVAILABLE"end
 local ok,value=pcall(fn,...);if not ok then return false,nil,tostring(value)end
 return true,value
end
local function currentContext()
 local seasonOk,season=safeCall(C_DelvesUI and C_DelvesUI.GetCurrentDelvesSeasonNumber)
 local weekOk,week=safeCall(C_DateAndTime and C_DateAndTime.GetWeeklyResetStartTime)
 season=safeNumber(season);week=safeNumber(week)
 if not seasonOk or not weekOk or not season or not week then return nil end
 return season,week
end
local function unavailable(stage,reason)return nil,"DELVES_"..reason,{producer="delves",stage=stage}end

HolyStorm:RegisterModule(metadata,function(Module)
 HolyStorm:ApplyModuleMetadata(Module,metadata)
 function Module:GetCharacterSnapshot(guid)return HolyStorm.Data.CharacterStore:GetBlock(guid,"delves")end
 function Module:Collect()
  local delves,weekly,dateTime=C_DelvesUI,C_WeeklyRewards,C_DateAndTime
  if type(delves)~="table"or type(weekly)~="table"or type(dateTime)~="table"then return unavailable("APIS","API_UNAVAILABLE")end
  local seasonOk,season=safeCall(delves.GetCurrentDelvesSeasonNumber)
  season=safeNumber(season)
  if not seasonOk or not season or season<1 or season%1~=0 then return unavailable("SEASON","SEASON_UNAVAILABLE")end
  local resetOk,weeklyIdentity=safeCall(dateTime.GetWeeklyResetStartTime)
  weeklyIdentity=safeNumber(weeklyIdentity)
  if not resetOk or not weeklyIdentity or weeklyIdentity<1 or weeklyIdentity%1~=0 then return unavailable("WEEKLY_RESET","WEEKLY_RESET_UNAVAILABLE")end
  local enum=Enum and Enum.WeeklyRewardChestThresholdType;local world=enum and enum.World
  if type(weekly.AreRewardsForCurrentRewardPeriod)~="function"or type(weekly.HasAvailableRewards)~="function"then return unavailable("WEEKLY_REWARDS","WEEKLY_REWARDS_API_UNAVAILABLE")end
  local periodOk,isCurrentPeriod=safeCall(weekly.AreRewardsForCurrentRewardPeriod)
  if not periodOk or isCurrentPeriod~=true then return unavailable("WEEKLY_REWARDS","REWARD_PERIOD_UNAVAILABLE")end
  local rewardOk,rewardAvailable=safeCall(weekly.HasAvailableRewards)
  if not rewardOk or type(rewardAvailable)~="boolean"then return unavailable("WEEKLY_REWARDS","REWARD_AVAILABILITY_UNAVAILABLE")end
  local worldProgress,worldDiagnostics
  local activitiesOk,rawActivities,activitiesError=false,nil,nil
  if world~=nil and type(weekly.GetActivities)=="function"then activitiesOk,rawActivities,activitiesError=safeCall(weekly.GetActivities,world)end
  if not activitiesOk or type(rawActivities)~="table"then
   -- Weekly World activities enrich the snapshot; the core Delves context and
   -- Great Vault reward state remain valid while Blizzard's optional list is absent.
   worldDiagnostics={producer="delves",stage="WORLD_ACTIVITIES",optional=true,api="C_WeeklyRewards.GetActivities",apiAvailable=type(weekly.GetActivities)=="function",worldThresholdAvailable=world~=nil,callSucceeded=activitiesOk,resultType=type(rawActivities),error=activitiesError and activitiesError:sub(1,160)or nil}
  else
   worldProgress={activities={},completed={},progress=0}
   for _,activityInfo in ipairs(rawActivities)do
    if type(activityInfo)~="table"then return unavailable("WORLD_ACTIVITIES","INVALID_ACTIVITY")end
    local id,index,progress,threshold=safeNumber(activityInfo.id),safeNumber(activityInfo.index),safeNumber(activityInfo.progress),safeNumber(activityInfo.threshold)
    if not id or id<1 or id%1~=0 or not index or index<1 or index%1~=0 or not progress or progress<0 or not threshold or threshold<0 then return unavailable("WORLD_ACTIVITIES","INVALID_ACTIVITY")end
    local activity={id=id,index=index,type=safeNumber(activityInfo.type),activityTierID=safeNumber(activityInfo.activityTierID),progress=progress,threshold=threshold,level=safeNumber(activityInfo.level)}
    worldProgress.activities[#worldProgress.activities+1]=activity
    if progress>=threshold then worldProgress.completed[#worldProgress.completed+1]=index end
   end
   worldProgress.progress=#worldProgress.completed
  end
  local snapshot={snapshotVersion=3,schemaVersion=3,seasonNumber=season,weeklyIdentity=weeklyIdentity,greatVault={currentPeriod=true,rewardAvailable=rewardAvailable},greatVaultWorld=worldProgress,updatedAt=HolyStorm.Utils.Now()}
  local valid,reason=validSnapshot(snapshot);if not valid then return unavailable("VALIDATION",reason or"INVALID_SNAPSHOT")end
  return snapshot,worldDiagnostics and"DELVES_WORLD_ACTIVITIES_UNAVAILABLE"or nil,worldDiagnostics
 end
 function Module:Validate(snapshot,scanReason)
  if type(snapshot)~="table"then return false,scanReason or"DELVES_COLLECTION_UNAVAILABLE",false end
  local valid,reason=validSnapshot(snapshot);return valid,reason,false
 end
 function Module:Commit(snapshot)local guid=UnitGUID("player");return HolyStorm.PlayerData:WriteOwnedBlock(guid,"delves",snapshot,"blizzard")end
 function Module:Queue(sync)return HolyStorm.Snapshots:Queue("delves",function()return Module:Collect()end,function(snapshot,scanReason,diagnostics,attempt,maximum)return Module:Validate(snapshot,scanReason,diagnostics,attempt,maximum)end,function(snapshot,force)return Module:Commit(snapshot,force,sync)end,{source="Delves",delay=1,retryDelay=2.5,priority=6})end
 function Module:OnInitialize()
  HolyStorm.CharacterScans:RegisterProvider("Delves",{block="delves",capability="character.scan.delves",addonId="delves",order=40,request=function(sync)local queued,workflowId=Module:Queue(sync);if not queued then return nil end;return workflowId end})
  HolyStorm:RegisterCapability("Delves","character.scan.delves",function(_,sync,reason)return HolyStorm.CharacterScans:Request("delves",reason or"CAPABILITY",sync,{order=40})end)
  HolyStorm:RegisterCapability("Delves","character.scan.additional",function(_,sync,reason)return HolyStorm.CharacterScans:Request("delves",reason or"CAPABILITY",sync,{order=40})end)
 end
 function Module:OnEnable()
  if not C_DelvesUI or not C_WeeklyRewards or not C_DateAndTime then self:Disable();return end
  self.ignoreInitialWeeklyRewardsUpdate=HolyStorm.State and not HolyStorm.State:Is("playerReady") or false
  HolyStorm.Events:Register("WEEKLY_REWARDS_UPDATE","delves",function()
   if self.ignoreInitialWeeklyRewardsUpdate then self.ignoreInitialWeeklyRewardsUpdate=false;return end
   HolyStorm.CharacterScans:Request("delves","WEEKLY_REWARDS_UPDATE",true,{order=40})
  end)
 end
 function Module:OnDisable()HolyStorm.Events:UnregisterOwner("delves");HolyStorm.Snapshots:Cancel("delves");self.ignoreInitialWeeklyRewardsUpdate=nil end
end)
