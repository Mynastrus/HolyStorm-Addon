local HolyStorm=LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local Activity=HolyStorm.GuildManagement.Activity
local owner="guild-activity-provider:raid"
local active
local function instanceInfo()if not GetInstanceInfo then return{}end;local name,instanceType,difficultyId,difficultyName,maxPlayers,_,_,instanceId=GetInstanceInfo();return{name=name,instanceType=instanceType,difficultyId=difficultyId,difficultyName=difficultyName,maxPlayers=maxPlayers,instanceId=instanceId}end

Activity:RegisterProvider("raid",{
 types={"RAID_ENCOUNTER"},
 enable=function(service)
  if not GetInstanceInfo then return false end
  local started=HolyStorm.Events:Register("ENCOUNTER_START",owner,function(_,encounterId,encounterName,difficultyId,groupSize)active={encounterId=encounterId,encounterName=encounterName,difficultyId=difficultyId,groupSize=groupSize,startedAt=HolyStorm.Utils.Now(),instance=instanceInfo()}end)
  local finished=HolyStorm.Events:Register("ENCOUNTER_END",owner,function(_,encounterId,encounterName,difficultyId,groupSize,success)local stamp=HolyStorm.Utils.Now();local context=active and tonumber(active.encounterId)==tonumber(encounterId)and active or{};active=nil;service:Submit("raid","RAID_ENCOUNTER",{encounterId=encounterId,encounterName=encounterName,difficultyId=difficultyId,groupSize=groupSize,success=success==1,startedAt=context.startedAt or stamp,occurredAt=stamp,instance=context.instance or instanceInfo(),group=service:SnapshotGuildGroup()})end)
  if not(started and finished)then HolyStorm.Events:UnregisterOwner(owner);return false end;return true
 end,
 disable=function()active=nil;HolyStorm.Events:UnregisterOwner(owner)end,
 normalize=function(service,_,payload)
  local actor={accountUUID=payload.capturedAccountUUID,characterUUID=payload.capturedCharacterUUID};if not actor.accountUUID or not actor.characterUUID then actor=HolyStorm.GuildManagement:Actor()end;if not actor.accountUUID or not actor.characterUUID then return nil,"MISSING_IDENTITY"end;if not service:IsGuildRelevant(payload.group)then return nil,"NOT_GUILD_RELEVANT"end;local instance=payload.instance or{};local startedAt=tonumber(payload.startedAt)or tonumber(payload.occurredAt);local occurredAt=tonumber(payload.occurredAt);local occurrenceId=table.concat({"raid",tostring(instance.instanceId or 0),tostring(payload.encounterId),tostring(payload.difficultyId),tostring(startedAt)},":")
  return{type="RAID_ENCOUNTER",eventId=service:DeterministicId("raid",actor.accountUUID,occurrenceId),occurrenceId=occurrenceId,accountUUID=actor.accountUUID,characterUUID=actor.characterUUID,source="blizzard-encounter",startedAt=startedAt,occurredAt=occurredAt,metadata={encounterId=tonumber(payload.encounterId),encounterName=tostring(payload.encounterName or""),difficultyId=tonumber(payload.difficultyId),instanceId=tonumber(instance.instanceId)or 0,instanceName=tostring(instance.name or""),success=payload.success==true,groupSize=payload.group.groupSize,guildMembers=payload.group.guildMembers,guildClassification=payload.group.classification}}
 end,
})
