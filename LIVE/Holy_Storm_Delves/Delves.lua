local addonVersion="2.2.0"
local HolyStorm=LibStub("AceAddon-3.0"):GetAddon("Holy_Storm");local L=LibStub("AceLocale-3.0"):GetLocale("Holy_Storm_Delves")
if HolyStorm.PermissionRegistry then HolyStorm.PermissionRegistry:RegisterLegacyAlias("delves.read","delves-read")end
local function validDelves(s)
 if type(s)~="table"or s.snapshotVersion~=2 or not tonumber(s.seasonNumber)or tonumber(s.seasonNumber)<=0 or type(s.activities)~="table"or type(s.completed)~="table"then return false,"INVALID_DELVES_SNAPSHOT"end
 if type(s.weeklyProgress)~="number"or s.weeklyProgress<0 or s.weeklyProgress%1~=0 then return false,"INVALID_DELVES_PROGRESS"end
 if type(s.weeklyRewardAvailable)~="boolean"and not(type(s.weeklyRewardAvailable)=="table"and s.weeklyRewardAvailable.status=="unknown")then return false,"INVALID_DELVES_REWARD_STATE"end
 local completed={};for _,activity in ipairs(s.activities)do if type(activity)~="table"or not tonumber(activity.id)or tonumber(activity.id)<=0 or not tonumber(activity.index)or tonumber(activity.index)<1 or tonumber(activity.index)%1~=0 or not tonumber(activity.progress)or tonumber(activity.progress)<0 or not tonumber(activity.threshold)or tonumber(activity.threshold)<0 then return false,"INVALID_DELVES_ACTIVITY"end;if activity.progress>=activity.threshold then completed[activity.index]=true end end
 local completionCount,seen=0,{};for _,index in ipairs(s.completed)do if not completed[index]or seen[index]then return false,"INVALID_DELVES_COMPLETION_MISMATCH"end;seen[index]=true;completionCount=completionCount+1 end
 if completionCount~=s.weeklyProgress then return false,"INVALID_DELVES_PROGRESS_MISMATCH"end
 return true
end
if HolyStorm.PlayerData then HolyStorm.PlayerData:RegisterBlock("delves",{fields={"delves"},event="HS_DELVES_UPDATED",staleAfter=21600,owner="delves",schemaVersion=2,snapshotVersion=2,capability="character.scan.delves",scanProvider="delves",validate=validDelves})end
local metadata={id="delves",name="Delves",displayName=L["DISPLAY_NAME"],description=L["DESCRIPTION"],version=addonVersion,moduleType="feature",category="feature",permissions={{id="delves-read",category="Delves",defaults={member=true}},"sync-send"},dependencies={"core"},capabilities={"character.scan.delves","character.scan.additional"},ui={},options={},administration={},data={block="delves",snapshotType="delves",schemaVersion=2,capabilities={"character.scan.delves","character.scan.additional"}},sync={domains={"character"}},enabledByDefault=true,ruleFields={{id="delves.status",aliases={"delveStatus"},type="number",name=L["RULE_FIELD_STATUS"],nameKey="RULE_FIELD_STATUS",description=L["RULE_FIELD_STATUS_DESC"],descriptionKey="RULE_FIELD_STATUS_DESC",category=L["DISPLAY_NAME"],dependencies={"delves"},unit="progress",resolver=function(context)local block=context.character and context.character.delves or HolyStorm.Data.CharacterStore:GetBlock(context.characterUUID,"delves");return block and tonumber(block.weeklyProgress)or nil end}}}
local function unknown(reason)return{status="unknown",reason=reason or"not_exposed_by_blizzard_api"}end
local function safeNumber(value)if value==nil or issecretvalue and issecretvalue(value)or type(value)~="number"or value~=value or value==math.huge or value==-math.huge then return nil end;return value end
local function safeCall(fn,...)if type(fn)~="function"then return nil end;local ok,value=pcall(fn,...);if not ok then return nil end;return value end
HolyStorm:RegisterModule(metadata,function(Module)
 HolyStorm:ApplyModuleMetadata(Module,metadata)
 function Module:GetCharacterSnapshot(guid)return HolyStorm.Data.CharacterStore:GetBlock(guid,"delves")end
 function Module:Collect()
  local d,w=C_DelvesUI,C_WeeklyRewards;if type(d)~="table"or type(w)~="table"or type(w.GetActivities)~="function"or type(d.GetCurrentDelvesSeasonNumber)~="function"then return nil end
  local season=safeNumber(safeCall(d.GetCurrentDelvesSeasonNumber));if not season or season<=0 then return nil end
  local enum=Enum and Enum.WeeklyRewardChestThresholdType;local world=enum and enum.World;if world==nil then return nil end
  local activitiesOk,rawActivities=pcall(w.GetActivities,world);if not activitiesOk or type(rawActivities)~="table"then return nil end
  local s={seasonNumber=season,week=date("%G-W%V"),activities={},completed={},bountiful=unknown(),nemesis=unknown(),treasureMap=unknown(),flute=unknown(),crestProgress=unknown(),limitedRewards=unknown(),updatedAt=HolyStorm.Utils.Now(),snapshotVersion=2}
  for _,a in ipairs(rawActivities)do
   if type(a)~="table"then return nil end
   local id,index,progress,threshold=safeNumber(a.id),safeNumber(a.index),safeNumber(a.progress),safeNumber(a.threshold)
   if not id or id<=0 or not index or index<1 or index%1~=0 or not progress or progress<0 or not threshold or threshold<0 then return nil end
   local activity={id=id,index=index,type=safeNumber(a.type)or(type(a.type)=="string"and a.type or nil),progress=progress,threshold=threshold,level=safeNumber(a.level),rewardLevel=safeNumber(a.rewardLevel)};s.activities[#s.activities+1]=activity
   if progress>=threshold then s.completed[#s.completed+1]=index end
  end
  s.weeklyProgress=#s.completed
  if type(w.HasAvailableRewards)=="function"then local available=safeCall(w.HasAvailableRewards);if type(available)=="boolean"then s.weeklyRewardAvailable=available else s.weeklyRewardAvailable=unknown("weekly_reward_state_unavailable")end else s.weeklyRewardAvailable=unknown("weekly_reward_api_unavailable")end
  local companion
  if type(d.GetCompanionInfoForActivePlayer)=="function"then companion=safeNumber(safeCall(d.GetCompanionInfoForActivePlayer))end
  if companion and companion>0 then s.companion={id=companion,pdeId=safeNumber(safeCall(d.GetPlayerCompanionPDEID,companion)),factionId=safeNumber(safeCall(d.GetFactionForCompanion,companion)),roleNodeId=safeNumber(safeCall(d.GetRoleNodeForCompanion,companion)),traitTreeId=safeNumber(safeCall(d.GetTraitTreeForCompanion,companion)),level=unknown(),role=unknown(),abilities=unknown()}else s.companion=unknown("no_active_companion_data")end;return s
 end
 function Module:Validate(s)return validDelves(s)end
 function Module:Commit(s)local guid=UnitGUID("player");return HolyStorm.PlayerData:WriteOwnedBlock(guid,"delves",s,"blizzard")end
 function Module:Queue(sync)return HolyStorm.Snapshots:Queue("delves",function()return Module:Collect()end,function(s)return Module:Validate(s)end,function(s,f)return Module:Commit(s,f,sync)end,{source="Delves",delay=1,retryDelay=2.5,priority=6})end
 function Module:OnInitialize()
  HolyStorm.CharacterScans:RegisterProvider("Delves",{block="delves",capability="character.scan.delves",addonId="delves",order=40,request=function(sync)local queued,workflowId=Module:Queue(sync);if not queued then return nil end;return workflowId end})
  HolyStorm:RegisterCapability("Delves","character.scan.delves",function(_,sync,reason)return HolyStorm.CharacterScans:Request("delves",reason or"CAPABILITY",sync,{order=40})end);HolyStorm:RegisterCapability("Delves","character.scan.additional",function(_,sync,reason)return HolyStorm.CharacterScans:Request("delves",reason or"CAPABILITY",sync,{order=40})end)
 end
 function Module:OnEnable()if not C_DelvesUI or not C_WeeklyRewards then self:Disable();return end;for _,ev in ipairs({"WEEKLY_REWARDS_UPDATE","DELVES_ACCOUNT_DATA_ELEMENT_CHANGED","ACTIVE_DELVE_DATA_UPDATE"})do local event=ev;HolyStorm.Events:Register(event,"delves",function()HolyStorm.CharacterScans:Request("delves",event,true,{order=40})end)end end
 function Module:OnDisable()HolyStorm.Events:UnregisterOwner("delves");HolyStorm.Snapshots:Cancel("delves")end
end)
