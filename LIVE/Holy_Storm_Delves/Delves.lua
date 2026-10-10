local addonVersion="2.2.1"
local HolyStorm=LibStub("AceAddon-3.0"):GetAddon("Holy_Storm");local L=LibStub("AceLocale-3.0"):GetLocale("Holy_Storm_Delves")

local function validNumber(value,minimum,integer)
 return type(value)=="number"and value==value and value~=math.huge and value~=-math.huge and value>=minimum and(not integer or value%1==0)
end
local function validSnapshot(snapshot)
 if type(snapshot)~="table"or snapshot.snapshotVersion~=3 or snapshot.schemaVersion~=3 then return false,"INVALID_DELVES_SNAPSHOT"end
 if not validNumber(snapshot.seasonNumber,1,true)or not validNumber(snapshot.weeklyIdentity,1,true)then return false,"INVALID_DELVES_CONTEXT"end
 local greatVault,world=snapshot.greatVault,snapshot.greatVaultWorld
 if type(greatVault)~="table"or greatVault.currentPeriod~=nil and type(greatVault.currentPeriod)~="boolean"or greatVault.rewardAvailable~=nil and type(greatVault.rewardAvailable)~="boolean"then return false,"INVALID_DELVES_VAULT"end
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

local function secretValue(value)
 if not issecretvalue then return false end;local ok,result=pcall(issecretvalue,value);return not ok or result==true
end
local function safeNumber(value)
 if value==nil or secretValue(value)or type(value)~="number"or value~=value or value==math.huge or value==-math.huge then return nil end
 return value
end
local function safeCall(fn,...)
 if type(fn)~="function"then return false,nil,"API_UNAVAILABLE"end
 local ok,value=pcall(fn,...);if not ok then return false,nil,tostring(value)end
 return true,value
end
local function unavailable(stage,api,reason,errorText,retryable)
 return nil,retryable and"DELVES_API_NOT_READY"or"DELVES_REQUIRED_DATA_INVALID",{producer="delves",stage=stage,api=api,cause=reason,error=errorText and tostring(errorText):sub(1,160)or nil,retryable=retryable==true}
end
local function optionalUnavailable(stage,api,reason,errorText)
 return{producer="delves",stage=stage,api=api,optional=true,cause=reason,error=errorText and tostring(errorText):sub(1,160)or nil}
end
local function readOptionalBoolean(api,method,stage)
 local fn=type(api)=="table"and api[method]or nil
 local ok,value,errorText=safeCall(fn)
 if ok and type(value)=="boolean"then return value end
 return nil,optionalUnavailable(stage,"C_WeeklyRewards."..method,ok and"INVALID_RESULT"or"API_UNAVAILABLE",errorText)
end

HolyStorm:RegisterModule(metadata,function(Module)
 HolyStorm:ApplyModuleMetadata(Module,metadata)
 function Module:GetCharacterSnapshot(guid)return HolyStorm.Data.CharacterStore:GetBlock(guid,"delves")end
 function Module:Collect()
  local delves,dateTime=C_DelvesUI,C_DateAndTime
  if type(delves)~="table"then return unavailable("SEASON","C_DelvesUI.GetCurrentDelvesSeasonNumber","API_UNAVAILABLE",nil,true)end
  if type(dateTime)~="table"then return unavailable("WEEKLY_RESET","C_DateAndTime.GetWeeklyResetStartTime","API_UNAVAILABLE",nil,true)end
  local seasonOk,seasonValue,seasonError=safeCall(delves.GetCurrentDelvesSeasonNumber)
  if not seasonOk or seasonValue==nil or secretValue(seasonValue)then return unavailable("SEASON","C_DelvesUI.GetCurrentDelvesSeasonNumber",seasonOk and"NOT_READY"or"API_ERROR",seasonError,true)end
  if type(seasonValue)~="number"then return unavailable("SEASON","C_DelvesUI.GetCurrentDelvesSeasonNumber","INVALID_TYPE",nil,false)end
  local season=safeNumber(seasonValue);if not season then return unavailable("SEASON","C_DelvesUI.GetCurrentDelvesSeasonNumber","INVALID_VALUE",nil,false)end
  if season<1 or season%1~=0 then return unavailable("SEASON","C_DelvesUI.GetCurrentDelvesSeasonNumber","INVALID_VALUE",nil,false)end
  local resetOk,resetValue,resetError=safeCall(dateTime.GetWeeklyResetStartTime)
  if not resetOk or resetValue==nil or secretValue(resetValue)then return unavailable("WEEKLY_RESET","C_DateAndTime.GetWeeklyResetStartTime",resetOk and"NOT_READY"or"API_ERROR",resetError,true)end
  if type(resetValue)~="number"then return unavailable("WEEKLY_RESET","C_DateAndTime.GetWeeklyResetStartTime","INVALID_TYPE",nil,false)end
  local weeklyIdentity=safeNumber(resetValue);if not weeklyIdentity then return unavailable("WEEKLY_RESET","C_DateAndTime.GetWeeklyResetStartTime","INVALID_VALUE",nil,false)end
  if weeklyIdentity<1 or weeklyIdentity%1~=0 then return unavailable("WEEKLY_RESET","C_DateAndTime.GetWeeklyResetStartTime","INVALID_VALUE",nil,false)end

  -- Great Vault values enrich the snapshot; season and reset identity are its
  -- required current-context fields. Blizzard's reward-period flag can be false
  -- while an older claim is available, so it is not a snapshot readiness gate.
  local weekly=type(C_WeeklyRewards)=="table"and C_WeeklyRewards or nil
  local isCurrentPeriod,periodDiagnostic=readOptionalBoolean(weekly,"AreRewardsForCurrentRewardPeriod","REWARD_PERIOD")
  local rewardAvailable,rewardDiagnostic=readOptionalBoolean(weekly,"HasAvailableRewards","REWARD_AVAILABILITY")
  local optionalDiagnostics={}
  if periodDiagnostic then optionalDiagnostics[#optionalDiagnostics+1]=periodDiagnostic end
  if rewardDiagnostic then optionalDiagnostics[#optionalDiagnostics+1]=rewardDiagnostic end

  local worldProgress,worldDiagnostic
  local canReadCurrentWorld=rewardAvailable==false or isCurrentPeriod==true
  local enum=Enum and Enum.WeeklyRewardChestThresholdType;local world=enum and enum.World
  if not canReadCurrentWorld then
   worldDiagnostic=optionalUnavailable("WORLD_ACTIVITIES","C_WeeklyRewards.AreRewardsForCurrentRewardPeriod",rewardAvailable==true and isCurrentPeriod==false and"PREVIOUS_PERIOD_REWARDS"or"CURRENT_PERIOD_UNCONFIRMED")
  elseif not weekly then
   worldDiagnostic=optionalUnavailable("WORLD_ACTIVITIES","C_WeeklyRewards.GetActivities","API_UNAVAILABLE")
  elseif world==nil then
   worldDiagnostic=optionalUnavailable("WORLD_ACTIVITIES","Enum.WeeklyRewardChestThresholdType.World","WORLD_THRESHOLD_UNAVAILABLE")
  elseif type(weekly.GetActivities)~="function"then
   worldDiagnostic=optionalUnavailable("WORLD_ACTIVITIES","C_WeeklyRewards.GetActivities","API_UNAVAILABLE")
  else
   local activitiesOk,rawActivities,activitiesError=safeCall(weekly.GetActivities,world)
   if not activitiesOk or type(rawActivities)~="table"then
    worldDiagnostic=optionalUnavailable("WORLD_ACTIVITIES","C_WeeklyRewards.GetActivities",activitiesOk and"INVALID_RESULT"or"API_UNAVAILABLE",activitiesError)
   else
    local candidate={activities={},completed={},progress=0};local activityDataValid=true;local invalidReason;local activityIDs,activityIndexes={},{}
    for _,activityInfo in ipairs(rawActivities)do
     if type(activityInfo)~="table"then activityDataValid=false;invalidReason="INVALID_ACTIVITY";break end
     local id,index,progress,threshold=safeNumber(activityInfo.id),safeNumber(activityInfo.index),safeNumber(activityInfo.progress),safeNumber(activityInfo.threshold)
     if not id or id<1 or id%1~=0 or not index or index<1 or index%1~=0 or not progress or progress<0 or not threshold or threshold<0 then activityDataValid=false;invalidReason="INVALID_ACTIVITY";break end
     if activityIDs[id]or activityIndexes[index]then activityDataValid=false;invalidReason="DUPLICATE_ACTIVITY";break end
     activityIDs[id]=true;activityIndexes[index]=true
     local activityType=safeNumber(activityInfo.type)
     if activityType~=nil and activityType~=world then activityDataValid=false;invalidReason="UNEXPECTED_ACTIVITY_TYPE";break end
     local activity={id=id,index=index,type=activityType,activityTierID=safeNumber(activityInfo.activityTierID),progress=progress,threshold=threshold,level=safeNumber(activityInfo.level)}
     candidate.activities[#candidate.activities+1]=activity
     if progress>=threshold then candidate.completed[#candidate.completed+1]=index end
    end
    if activityDataValid then candidate.progress=#candidate.completed;worldProgress=candidate
    else worldDiagnostic=optionalUnavailable("WORLD_ACTIVITIES","C_WeeklyRewards.GetActivities",invalidReason)end
   end
  end
  if worldDiagnostic then optionalDiagnostics[#optionalDiagnostics+1]=worldDiagnostic end
  local snapshot={snapshotVersion=3,schemaVersion=3,seasonNumber=season,weeklyIdentity=weeklyIdentity,greatVault={currentPeriod=isCurrentPeriod,rewardAvailable=rewardAvailable},greatVaultWorld=worldProgress,updatedAt=HolyStorm.Utils.Now()}
  local valid,reason=validSnapshot(snapshot);if not valid then return nil,reason or"DELVES_VALIDATION_FAILED",{producer="delves",stage="VALIDATION",validationReason=reason,retryable=false}end
  local optionalReason=worldDiagnostic and"DELVES_WORLD_ACTIVITIES_UNAVAILABLE"or(#optionalDiagnostics>0 and"DELVES_GREAT_VAULT_STATUS_UNAVAILABLE"or nil)
  return snapshot,optionalReason,#optionalDiagnostics>0 and{producer="delves",optional=true,details=optionalDiagnostics}or nil
 end
 function Module:Validate(snapshot,scanReason,diagnostics)
  if type(snapshot)~="table"then return false,scanReason or"DELVES_REQUIRED_DATA_MISSING",type(diagnostics)=="table"and diagnostics.retryable==true end
  local valid,reason=validSnapshot(snapshot);return valid,reason,false
 end
 function Module:Commit(snapshot)local guid=UnitGUID("player");local committed,reason=HolyStorm.PlayerData:WriteOwnedBlock(guid,"delves",snapshot,"blizzard");if HolyStorm.CharacterScans and HolyStorm.CharacterScans.RecordSnapshotResult then HolyStorm.CharacterScans:RecordSnapshotResult("delves",committed and"COMMITTED"or reason=="UNCHANGED"and"UNCHANGED"or"FAILED")end;return committed,reason end
 function Module:Queue(sync)return HolyStorm.Snapshots:Queue("delves",function()return Module:Collect()end,function(snapshot,scanReason,diagnostics,attempt,maximum)return Module:Validate(snapshot,scanReason,diagnostics,attempt,maximum)end,function(snapshot,force)return Module:Commit(snapshot,force,sync)end,{source="Delves",delay=1,retryDelay=2.5,priority=6,fingerprint=false,onValidationFailure=function(reason,disposition,retryCount,_,diagnostics)
  local details=type(diagnostics)=="table"and diagnostics or{};local stage=details.stage
  if not stage then stage=reason and(tostring(reason):find("INVALID_DELVES",1,true)or tostring(reason):find("DUPLICATE_DELVES",1,true))and"VALIDATION"or"COLLECT"end
  if HolyStorm.CharacterScans then
   if disposition=="FAIL"and HolyStorm.CharacterScans.RecordFailure then HolyStorm.CharacterScans:RecordFailure("delves",reason,stage,retryCount,details)end
  end
 end})end
 function Module:OnInitialize()
  HolyStorm.CharacterScans:RegisterProvider("Delves",{block="delves",capability="character.scan.delves",addonId="delves",order=40,mergeBeforeStart=true,request=function(sync)local queued,workflowId=Module:Queue(sync);if not queued then return nil end;return workflowId end})
  HolyStorm:RegisterCapability("Delves","character.scan.delves",function(_,sync,reason)return HolyStorm.CharacterScans:Request("delves",reason or"CAPABILITY",sync,{order=40})end)
  HolyStorm:RegisterCapability("Delves","character.scan.additional",function(_,sync,reason)return HolyStorm.CharacterScans:Request("delves",reason or"CAPABILITY",sync,{order=40})end)
 end
 function Module:OnEnable()
  self.ignoreInitialWeeklyRewardsUpdate=HolyStorm.State and not HolyStorm.State:Is("playerReady") or false
  HolyStorm.Events:Register("WEEKLY_REWARDS_UPDATE","delves",function()
   if self.ignoreInitialWeeklyRewardsUpdate then self.ignoreInitialWeeklyRewardsUpdate=false;return end
   HolyStorm.CharacterScans:Request("delves","WEEKLY_REWARDS_UPDATE",true,{order=40})
  end)
 end
 function Module:OnDisable()HolyStorm.Events:UnregisterOwner("delves");HolyStorm.Snapshots:Cancel("delves");self.ignoreInitialWeeklyRewardsUpdate=nil end
end)
