local HolyStorm=LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local Activity=HolyStorm.GuildManagement.Activity
local owner="guild-activity-provider:mythic-plus"
local active
local function activeKey()
 local mapId=C_ChallengeMode and C_ChallengeMode.GetActiveChallengeMapID and C_ChallengeMode.GetActiveChallengeMapID();local level
 if C_ChallengeMode and C_ChallengeMode.GetActiveKeystoneInfo then local ok,value=pcall(C_ChallengeMode.GetActiveKeystoneInfo);if ok then level=tonumber(value)end end
 return tonumber(mapId),level
end
local function completion()
 if not C_ChallengeMode then return{}end
 if C_ChallengeMode.GetChallengeCompletionInfo then local ok,info=pcall(C_ChallengeMode.GetChallengeCompletionInfo);if not ok or type(info)~="table"then return{}end;return{challengeMapId=tonumber(info.mapChallengeModeID),keystoneLevel=tonumber(info.level),durationMs=tonumber(info.time),timed=type(info.onTime)=="boolean"and info.onTime or nil,upgradeLevels=tonumber(info.keystoneUpgradeLevels),practiceRun=type(info.practiceRun)=="boolean"and info.practiceRun or nil}end
 if not C_ChallengeMode.GetCompletionInfo then return{}end;local result={pcall(C_ChallengeMode.GetCompletionInfo)};if not result[1]then return{}end;return{challengeMapId=tonumber(result[2]),keystoneLevel=tonumber(result[3]),durationMs=tonumber(result[4]),timed=type(result[5])=="boolean"and result[5]or nil,upgradeLevels=tonumber(result[6]),practiceRun=type(result[7])=="boolean"and result[7]or nil}
end
local function mapName(mapId)if not(C_ChallengeMode and C_ChallengeMode.GetMapUIInfo and mapId)then return nil end;local ok,name=pcall(C_ChallengeMode.GetMapUIInfo,mapId);return ok and name or nil end

Activity:RegisterProvider("mythic-plus",{
 types={"MYTHICPLUS_RUN"},
 enable=function(service)
  if not(C_ChallengeMode and C_ChallengeMode.GetActiveChallengeMapID and(C_ChallengeMode.GetChallengeCompletionInfo or C_ChallengeMode.GetCompletionInfo))then return false end
  local started=HolyStorm.Events:Register("CHALLENGE_MODE_START",owner,function()local mapId,level=activeKey();active={challengeMapId=mapId,keystoneLevel=level,startedAt=HolyStorm.Utils.Now(),group=service:SnapshotGuildGroup()}end)
  local completed=HolyStorm.Events:Register("CHALLENGE_MODE_COMPLETED",owner,function()local info=completion();local stamp=HolyStorm.Utils.Now();local context=active or{};active=nil;service:Submit("mythic-plus","MYTHICPLUS_RUN",{challengeMapId=info.challengeMapId or context.challengeMapId,keystoneLevel=info.keystoneLevel or context.keystoneLevel,durationMs=info.durationMs,timed=info.timed,upgradeLevels=info.upgradeLevels,practiceRun=info.practiceRun,startedAt=context.startedAt or stamp,occurredAt=stamp,dungeonName=mapName(info.challengeMapId or context.challengeMapId),group=context.group or service:SnapshotGuildGroup()})end)
  if not(started and completed)then HolyStorm.Events:UnregisterOwner(owner);return false end;return true
 end,
 disable=function()active=nil;HolyStorm.Events:UnregisterOwner(owner)end,
 normalize=function(service,_,payload)
  local actor={accountUUID=payload.capturedAccountUUID,characterUUID=payload.capturedCharacterUUID};if not actor.accountUUID or not actor.characterUUID then actor=HolyStorm.GuildManagement:Actor()end;if not actor.accountUUID or not actor.characterUUID then return nil,"MISSING_IDENTITY"end;if not service:IsGuildRelevant(payload.group)then return nil,"NOT_GUILD_RELEVANT"end;if not tonumber(payload.challengeMapId)or not tonumber(payload.keystoneLevel)then return nil,"COMPLETION_INFO_UNAVAILABLE"end;local startedAt=tonumber(payload.startedAt)or tonumber(payload.occurredAt);local occurrenceId=table.concat({"mythicplus",tostring(payload.challengeMapId),tostring(payload.keystoneLevel),tostring(startedAt)},":")
  return{type="MYTHICPLUS_RUN",eventId=service:DeterministicId("mythicplus",actor.accountUUID,occurrenceId),occurrenceId=occurrenceId,accountUUID=actor.accountUUID,characterUUID=actor.characterUUID,source="blizzard-challenge-mode",startedAt=startedAt,occurredAt=tonumber(payload.occurredAt),metadata={challengeMapId=tonumber(payload.challengeMapId),dungeonName=tostring(payload.dungeonName or""),keystoneLevel=tonumber(payload.keystoneLevel),durationMs=tonumber(payload.durationMs),timed=payload.timed,upgradeLevels=tonumber(payload.upgradeLevels),practiceRun=payload.practiceRun,groupSize=payload.group.groupSize,guildMembers=payload.group.guildMembers,guildClassification=payload.group.classification}}
 end,
})
