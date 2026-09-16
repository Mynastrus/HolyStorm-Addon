local addonVersion = "5.0.0"
local HolyStorm = LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local L = LibStub("AceLocale-3.0"):GetLocale("Holy_Storm")
local Core = HolyStorm.PermissionCore
local Sync = { version=addonVersion }

function Sync:ExportPermissionState(guildId)
    local state=self:GetState(guildId); if not state or state.version==0 then return nil end
    return {guildId=guildId,current={version=state.version,revisionID=state.revisionID,previousRevisionID=state.previousRevisionID,changedBy=Core.Copy(state.changedBy),changedAt=state.changedAt},history=Core.Copy(state.history),snapshot=self:Snapshot(state)}
end
function Sync:GetPermissionMetadata(guildId)
    local state=self:GetState(guildId); if not state or state.version==0 then return nil end
    return {objectId=guildId,owner=state.changedBy and state.changedBy.characterUUID,version=state.version,updatedAt=state.changedAt or 0,source="permission-revision-chain",revisionID=state.revisionID,oldestRevisionID=state.history[1] and state.history[1].revisionID}
end
function Sync:RequestPermissionCatchup(reason)
    local state=self:GetState(); if not state then return false end
    if state.status==self.status.VALID or state.status==self.status.UNINITIALIZED then state.status=self.status.CATCHING_UP end
    state.catchupReason=reason; state.catchup={requestedAfter=state.revisionID,startedAt=Core.Now(),receivedCount=0,validatedCount=0}
    HolyStorm.Events:Emit("HS_PERMISSIONS_CATCHUP_STARTED",state.guildId,reason)
    HolyStorm.Tasks:Queue("Policy.PermissionCatchup",{mergeKey=state.guildId,priority=10,triggerSource=reason or "CHAIN_GAP"})
    Core.Log("INFO","recovery","Permission catch-up requested",{guildId=state.guildId,reason=reason}); return true
end
function Sync:RunPermissionCatchup()
    local state=self:GetState(); if not state then return false end
    return HolyStorm.Sync:Discover("permissions",state.guildId,{reason="PERMISSION_CHAIN_CATCHUP",priority=10})~=nil
end
function Sync:RecoverFromSnapshot(state,payload,senderId)
    if not state or not self:IsActualGuildLeader(nil,senderId) then
        if state then state.status=self.status.RECOVERY_REQUIRED; state.recovery={reason="TRUSTED_SNAPSHOT_REQUIRED",requestedAt=Core.Now()}; HolyStorm.Events:Emit("HS_PERMISSIONS_RECOVERY_REQUIRED",state.guildId,"TRUSTED_SNAPSHOT_REQUIRED") end
        Core.Log("WARN","recovery","Permission recovery rejected",{guildId=state and state.guildId,sender=senderId,reason="TRUSTED_SNAPSHOT_REQUIRED"}); return false,"RECOVERY_TRUST_REQUIRED"
    end
    local valid,err=self:ValidateSnapshot(payload.snapshot); if not valid then Core.Log("WARN","recovery","Permission recovery snapshot rejected",{guildId=state.guildId,reason=err}); return false,err end
    state.groups=Core.Copy(payload.snapshot.groups); state.filters=Core.Copy(payload.snapshot.filters); state.rules=Core.Copy(payload.snapshot.rules); state.modules=Core.Copy(payload.snapshot.modules); state.version=payload.current.version; state.revisionID=payload.current.revisionID; state.previousRevisionID=payload.current.previousRevisionID; state.changedBy=Core.Copy(payload.current.changedBy); state.changedAt=payload.current.changedAt; state.history=Core.Copy(payload.history or {})
    while #state.history>self.maxHistory do table.remove(state.history,1) end
    state.status=self.status.VALID; state.recovery={completedAt=Core.Now(),source=senderId,trustAnchor="VISIBLE_BLIZZARD_RANK_0"}; state.lastSync=Core.Now(); self:EnsureSystemGroups(state); self:BindCompatibility(state); self:Invalidate("SNAPSHOT_RECOVERY")
    HolyStorm.Events:Emit("HS_PERMISSIONS_CATCHUP_COMPLETED",state.guildId,state.version); HolyStorm.Events:Emit("HS_PERMISSIONS_STATE_UPDATED",state.guildId,state.version,state.revisionID); Core.Log("INFO","recovery","Permission recovery completed",{guildId=state.guildId,version=state.version,source=senderId}); return true
end
function Sync:ImportPermissionState(guildId,payload,meta,senderId)
    local state=self:GetState(guildId)
    if not state or type(payload)~="table" or payload.guildId~=guildId or type(payload.current)~="table" or type(payload.history)~="table" or type(payload.snapshot)~="table" then return false,"INVALID_PAYLOAD" end
    if payload.current.version==state.version and payload.current.revisionID==state.revisionID then return true,"DUPLICATE" end
    if payload.current.version==state.version and payload.current.previousRevisionID==state.previousRevisionID and payload.current.revisionID~=state.revisionID then
        state.status=self.status.CONFLICT; state.fork={localRevision=state.revisionID,remoteRevision=payload.current.revisionID,version=state.version}; self:RecordRejected(payload.current,senderId,"FORK"); HolyStorm.Events:Emit("HS_PERMISSIONS_CONFLICT_DETECTED",Core.Copy(state.fork)); Core.Log("ERROR","recovery","Permission revision conflict detected",state.fork); return false,"FORK"
    end
    local revisions=Core.Copy(payload.history); table.sort(revisions,function(left,right) return (left.version or 0)<(right.version or 0) end)
    local progressed=false; if state.catchup then state.catchup.receivedCount=#revisions; state.catchup.respondingPeer=senderId end
    for _,revision in ipairs(revisions) do
        if revision.version>state.version then
            local ok,reason=self:ApplyRevision(state,revision)
            if not ok then if reason=="MISSING_PREDECESSOR" then break else return false,reason end end
            progressed=true; if state.catchup then state.catchup.validatedCount=state.catchup.validatedCount+1 end
        end
    end
    if state.version==payload.current.version and state.revisionID==payload.current.revisionID then
        if not Core.Same(self:Snapshot(state),payload.snapshot) then state.status=self.status.CONFLICT; state.fork={localRevision=state.revisionID,remoteRevision=payload.current.revisionID,reason="SNAPSHOT_MISMATCH"}; HolyStorm.Events:Emit("HS_PERMISSIONS_CONFLICT_DETECTED",Core.Copy(state.fork)); Core.Log("ERROR","recovery","Permission snapshot conflict detected",state.fork); return false,"SNAPSHOT_MISMATCH" end
        state.status=self.status.VALID; state.lastSync=Core.Now(); HolyStorm.Events:Emit("HS_PERMISSIONS_CATCHUP_COMPLETED",guildId,state.version); Core.Log("INFO","recovery","Permission catch-up successful",{guildId=guildId,version=state.version}); return true
    end
    if not progressed then
        state.status=self.status.RECOVERY_REQUIRED; state.missingRevisions={after=state.revisionID,target=payload.current.revisionID}; HolyStorm.Events:Emit("HS_PERMISSIONS_RECOVERY_REQUIRED",guildId,"MISSING_PREDECESSOR"); Core.Log("WARN","recovery","Permission recovery required",{guildId=guildId,after=state.revisionID,target=payload.current.revisionID})
        if senderId and self:IsActualGuildLeader(nil,senderId) then return self:RecoverFromSnapshot(state,payload,senderId) end
        self:RequestPermissionCatchup("MISSING_PREDECESSOR"); return false,"MISSING_PREDECESSOR"
    end
    self:RequestPermissionCatchup("INCOMPLETE_CHAIN"); return false,"INCOMPLETE_CHAIN"
end
function Sync:ValidatePermissionPayload(payload,meta,guildId)
    return type(payload)=="table" and payload.guildId==guildId and type(payload.current)=="table" and type(meta)=="table" and tonumber(payload.current.version)==tonumber(meta.version) and payload.current.revisionID==meta.revisionID and type(payload.history)=="table" and type(payload.snapshot)=="table"
end
function Sync:BootstrapState()
    if not self:IsPersistenceReady() then Core.Log("ERROR","lifecycle","Permission state bootstrap requires initialized persistence");return false,"PERSISTENCE_NOT_READY" end
    local guildId=self:GetGuildId(); if not guildId then return false end
    local state=self:GetState(guildId)
    if not state then local reason;state,reason=self:CreateState(guildId);if not state then return false,reason end end
    self:UpgradeState(state); self:BindCompatibility(state)
    if state.version==0 then
        if self:IsActualGuildLeader(nil,UnitGUID("player")) then
            local actor=self:Actor(); local snapshot={groups=self:GetDefaultGroups(),filters=Core.Copy(state.filters),rules=Core.Copy(state.rules),modules={}}
            local revision={version=1,revisionID=self:NewRevisionId(guildId,1),previousRevisionID=nil,changedBy=actor,changedAt=Core.Now(),action="BASELINE",change={action="BASELINE",snapshot=Core.Copy(snapshot)}}
            self:CommitSnapshot(state,snapshot,revision); HolyStorm.Sync:Publish("permissions",guildId,"PERMISSION_BASELINE")
        else state.status=self.status.UNINITIALIZED; self:RequestPermissionCatchup("UNINITIALIZED") end
    end
    return true
end
function Sync:Initialize()
    if not self:IsPersistenceReady() then Core.Log("ERROR","lifecycle","Permission sync initialization requires initialized persistence");return false,"PERSISTENCE_NOT_READY" end
    local profile=HolyStorm.Database:GetRoot("profile")
    profile.rules=profile.rules or {localRules={}}; profile.rules.localRules=profile.rules.localRules or {}; profile.filters.localFilters=profile.filters.localFilters or {}; profile.filters.activeByContext=profile.filters.activeByContext or {}; self:RestoreTemplates()
    HolyStorm.Tasks:RegisterTaskType("Policy.RecalculateEffectiveMemberships",{name=L["TASK_POLICY_RECALCULATE"],localizedNameKey="TASK_POLICY_RECALCULATE",module="Policy",priority=20,executionMode="UNIQUE",execute=function() return HolyStorm.Policy:Recalculate() end})
    HolyStorm.Tasks:RegisterTaskType("Policy.PermissionCatchup",{name=L["TASK_PERMISSION_CATCHUP"],localizedNameKey="TASK_PERMISSION_CATCHUP",module="Policy",priority=10,executionMode="MERGE_BY_KEY",execute=function() return HolyStorm.Policy:RunPermissionCatchup() end})
    HolyStorm.Tasks:RegisterTaskType("Policy.PermissionRecovery",{name=L["TASK_PERMISSION_RECOVERY"],localizedNameKey="TASK_PERMISSION_RECOVERY",module="Policy",priority=5,executionMode="MERGE_BY_KEY",execute=function(task) local metadata=task.metadata; return HolyStorm.Policy:RecoverFromSnapshot(HolyStorm.Policy:GetState(metadata.guildId),metadata.payload,metadata.senderId) end})
    HolyStorm.Sync:RegisterDomain("permissions",{freshness="revision-chain",getMetadata=function(id) return HolyStorm.Policy:GetPermissionMetadata(id) end,listMetadata=function(since) local out={}; for id in pairs(HolyStorm.Policy:GetStates() or {}) do local metadata=HolyStorm.Policy:GetPermissionMetadata(id); if metadata and (metadata.updatedAt or 0)>since then out[#out+1]=metadata end end; return out end,export=function(id) return HolyStorm.Policy:ExportPermissionState(id) end,validate=function(payload,meta,id) return HolyStorm.Policy:ValidatePermissionPayload(payload,meta,id) end,authorize=function() return true end,import=function(id,payload,meta,senderId) return HolyStorm.Policy:ImportPermissionState(id,payload,meta,senderId) end,updateEvent="HS_PERMISSIONS_SYNC_UPDATED"})
    for _,event in ipairs({"HS_CHARACTER_UPDATED","HS_PLAYER_UPDATED","HS_ROSTER_UPDATED","HS_CHARACTER_RELATIONSHIP_UPDATED","HS_TWINKS_UPDATED","HS_FILTER_UPDATED"}) do local eventName=event; HolyStorm.Events:Register(eventName,"policy-cache",function() HolyStorm.Policy:Invalidate(eventName); if eventName=="HS_ROSTER_UPDATED" then HolyStorm.Policy:BootstrapState() end end) end
    local bootstrapped,bootstrapError=self:BootstrapState()
    if bootstrapped==false and bootstrapError then return false,bootstrapError end
    self:Invalidate("INITIALIZE"); return true
end

HolyStorm.PermissionComponents = HolyStorm.PermissionComponents or {}
HolyStorm.PermissionComponents.Sync = Sync
