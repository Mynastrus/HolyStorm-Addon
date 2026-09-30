local addonVersion = "1.1.0"
local HolyStorm = LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")

-- HS_Player_DB is the canonical persistent owner-controlled data store.
local PlayerData = {
    version = addonVersion,
    schemaVersion = 2,
    blocks = {},
    fieldToBlock = {},
    identityFields = {},
}

local function copy(value) return HolyStorm.Utils.DeepCopy(value) end
local function now() return HolyStorm.Utils.Now() end
local function validId(value) return type(value)=="string" and #value>0 and #value<=128 end
local ignoredSnapshotMetadata={version=true,updatedAt=true,committedAt=true,receivedAt=true,originCreatedAt=true,receivedFrom=true,transport=true,transportMetadata=true,syncMetadata=true,schemaVersion=true,snapshotVersion=true}
local function comparable(value,root)
    if type(value)~="table"then return value end
    local result={}
    for key,child in pairs(value)do if not(root and ignoredSnapshotMetadata[key])then result[key]=comparable(child,false)end end
    return result
end
local function semanticDigest(value)return HolyStorm.Serializer and HolyStorm.Serializer:Serialize(comparable(value,true))end
local function same(left,right,definition)
    if type(definition)~="table"or#definition.fields==1 then local a,b=semanticDigest(left),semanticDigest(right);return a~=nil and a==b end
    local function blockDigest(data)
        local values={}
        for _,field in ipairs(definition.fields)do values[field]=semanticDigest(type(data)=="table"and data[field]or nil)end
        return HolyStorm.Serializer and HolyStorm.Serializer:Serialize(values)
    end
    local a,b=blockDigest(left),blockDigest(right);return a~=nil and a==b
end

local function ensureBlockMetadata(record,guid,blockId,definition)
    record.blockMeta=type(record.blockMeta)=="table"and record.blockMeta or{}
    if type(record.blockMeta[blockId])=="table"then return end
    local hasData=false;local blockUpdatedAt=0;local blockSource;local version=0
    for _,field in ipairs(definition.fields)do
        local value=record[field];if value~=nil then hasData=true end
        if type(value)=="table"then blockUpdatedAt=math.max(blockUpdatedAt,tonumber(value.updatedAt)or 0);version=math.max(version,tonumber(value.version)or 0);blockSource=blockSource or value.source end
    end
    if hasData then version=math.max(version,tonumber(record.version)or 0);record.blockMeta[blockId]={owner=guid,version=version,updatedAt=math.max(blockUpdatedAt,tonumber(record.updatedAt)or 0),source=blockSource or(record.fieldSources and record.fieldSources[definition.fields[1]])or"migration",receivedFrom=nil,direct=false}end
end

function PlayerData:RegisterBlock(id,definition)
    if not validId(id) or type(definition)~="table" or type(definition.fields)~="table" then return false,"INVALID_BLOCK" end
    if self.blocks[id]then return false,"BLOCK_EXISTS"end
    local fields,seenFields={},{};for _,field in ipairs(definition.fields)do if type(field)~="string"or self.fieldToBlock[field]or seenFields[field]then return false,"INVALID_BLOCK_FIELD"end;fields[#fields+1]=field;seenFields[field]=true end
    local schemaVersion=tonumber(definition.schemaVersion);local snapshotVersion=tonumber(definition.snapshotVersion)
    if definition.schemaVersion~=nil and not schemaVersion or definition.snapshotVersion~=nil and not snapshotVersion or schemaVersion and(schemaVersion<1 or schemaVersion%1~=0)or snapshotVersion and(snapshotVersion<1 or snapshotVersion%1~=0)then return false,"INVALID_BLOCK_VERSION"end
    for _,field in ipairs(fields)do self.fieldToBlock[field]=id end
    self.blocks[id]={id=id,fields=fields,owner=definition.owner or id,schemaVersion=schemaVersion,snapshotVersion=snapshotVersion,validate=definition.validate,event=definition.event or("HS_"..id:upper().."_UPDATED"),staleAfter=tonumber(definition.staleAfter)or 21600,syncEnabled=definition.syncEnabled~=false,persistenceEnabled=definition.persistenceEnabled~=false,authority=definition.authority or"character-owner",compatibility=type(definition.compatibility)=="table"and copy(definition.compatibility)or{},addonId=definition.addonId or id,capability=definition.capability,scanProvider=definition.scanProvider or id}
    if self.root and type(self.root.characters)=="table"then
        self.root.normalizedBlocks=type(self.root.normalizedBlocks)=="table"and self.root.normalizedBlocks or{}
        if self.root.normalizedBlocks[id]~=true then
            for guid,record in pairs(self.root.characters)do if validId(guid)and type(record)=="table"then ensureBlockMetadata(record,guid,id,self.blocks[id])end end
            self.root.normalizedBlocks[id]=true
        end
    end
    return true
end
function PlayerData:HasBlock(id)return self.blocks[id]~=nil end
function PlayerData:IsBlockSyncEnabled(id)local definition=self.blocks[id];return definition~=nil and definition.syncEnabled~=false end
function PlayerData:FingerprintSnapshot(value)return semanticDigest(value)end
function PlayerData:FingerprintBlock(blockId,value)local definition=self.blocks[blockId];if not definition then return nil end;if#definition.fields==1 then return semanticDigest(value)end;local values={};for _,field in ipairs(definition.fields)do values[field]=semanticDigest(type(value)=="table"and value[field]or nil)end;return HolyStorm.Serializer:Serialize(values)end
function PlayerData:SnapshotsEqual(left,right,blockId)return same(left,right,blockId and self.blocks[blockId])end
function PlayerData:GetBlockDefinition(id)local definition=self.blocks[id];return definition and copy(definition)or nil end
function PlayerData:GetBlockDefinitions()local result={};for id in pairs(self.blocks)do result[#result+1]=copy(self.blocks[id])end;table.sort(result,function(a,b)return a.id<b.id end);return result end

function PlayerData:Initialize()
    HS_Player_DB=type(HS_Player_DB)=="table"and HS_Player_DB or{}
    if tonumber(HS_Player_DB.schemaVersion)and tonumber(HS_Player_DB.schemaVersion)>self.schemaVersion then
        self.futureSchema=true;self.root={schemaVersion=self.schemaVersion,characters={},players={},characterOwners={},sync={foreignWatermark=0,foreignWatermarks={}},normalizedBlocks={}}
        if HolyStorm.Logger and HolyStorm.Logger.Write then HolyStorm.Logger:Write("ERROR","PlayerData","migration","Character database is newer than this addon; persistent data is read-only",{domain="player-data",oldSchema=HS_Player_DB.schemaVersion,newSchema=self.schemaVersion,migrationId="player-data.future-schema",success=false,reason="SCHEMA_VERSION_NEWER"})end
        return true
    end
    local legacyFlat=HS_Player_DB.characters==nil and HS_Player_DB or nil
    local root=legacyFlat and{}or HS_Player_DB
    root.schemaVersion=self.schemaVersion;root.characters=type(root.characters)=="table"and root.characters or{};root.players=type(root.players)=="table"and root.players or{};root.characterOwners=type(root.characterOwners)=="table"and root.characterOwners or{};root.sync=type(root.sync)=="table"and root.sync or{};root.sync.foreignWatermark=tonumber(root.sync.foreignWatermark)or 0;root.sync.foreignWatermarks=type(root.sync.foreignWatermarks)=="table"and root.sync.foreignWatermarks or{};root.normalizedBlocks=type(root.normalizedBlocks)=="table"and root.normalizedBlocks or{}
    if legacyFlat then for guid,record in pairs(legacyFlat)do if validId(guid)and type(record)=="table"then root.characters[guid]=copy(record)end end;HS_Player_DB=root end
    local old=type(HolyStorm.db.global.data)=="table"and HolyStorm.db.global.data or{}
    if HolyStorm.Database and HolyStorm.Database.migrationBlocked then
        for guid,record in pairs(type(old.characters)=="table"and old.characters or{})do if validId(guid)and type(record)=="table"and root.characters[guid]==nil then root.characters[guid]=copy(record)end end
        for id,record in pairs(type(old.players)=="table"and old.players or{})do if validId(id)and type(record)=="table"and root.players[id]==nil then root.players[id]=copy(record)end end
        for guid,id in pairs(type(old.characterOwners)=="table"and old.characterOwners or{})do if validId(guid)and validId(id)and root.characterOwners[guid]==nil then root.characterOwners[guid]=id end end
    end
    HolyStorm.db.global.data=old
    self.root=root
    if tonumber(root.normalizationVersion)~=1 then
        -- One migration pass replaces the former independent character/profile
        -- traversals. Subsequent logins trust the persisted normalization marker.
        for guid,record in pairs(root.characters)do
            if not validId(guid)or type(record)~="table"then root.characters[guid]=nil else
                record.guid=guid;record.blockMeta=type(record.blockMeta)=="table"and record.blockMeta or{}
                for blockId,definition in pairs(self.blocks)do ensureBlockMetadata(record,guid,blockId,definition)end
                local ownerId=root.characterOwners[guid];local player=ownerId and root.players[ownerId]
                if player then
                    player.characters=type(player.characters)=="table"and player.characters or{};if player.characters[guid]==nil then player.characters[guid]=true end
                    player.metadata=type(player.metadata)=="table"and player.metadata or{}
                    if not player.metadata.realName and type(record.realName)=="string"then player.metadata.realName=record.realName end
                    if not player.metadata.birthday and type(record.birthday)=="string"then player.metadata.birthday=record.birthday end
                    for twinkGuid,known in pairs(type(record.knownTwinks)=="table"and record.knownTwinks or{})do if known==true and validId(twinkGuid)then if player.characters[twinkGuid]==nil then player.characters[twinkGuid]=true end;root.characterOwners[twinkGuid]=ownerId end end
                end
            end
        end
        for id,player in pairs(root.players)do
            if not validId(id)or type(player)~="table"then root.players[id]=nil else player.id=id;player.characters=type(player.characters)=="table"and player.characters or{};player.roles=type(player.roles)=="table"and player.roles or{};player.version=tonumber(player.version)or 0;player.updatedAt=tonumber(player.updatedAt)or 0;if not player.ownerGuid then player.ownerGuid=player.mainCharacter or next(player.characters)end end
        end
        for guid,id in pairs(root.characterOwners)do if not validId(guid)or not validId(id)then root.characterOwners[guid]=nil end end
        for blockId in pairs(self.blocks)do root.normalizedBlocks[blockId]=true end
        root.normalizationVersion=1
    end
    return true
end

function PlayerData:GetRoot() return self.root end
-- TwinkCore owns the relationship rules; PlayerData owns their persistence.
-- Keep the legacy fields in this store so existing SavedVariables migrate in
-- place, while callers no longer need to inspect the PlayerData root.
function PlayerData:GetTwinkState()
    local root=self.root
    root.accounts=type(root.accounts)=="table"and root.accounts or root.players or{}
    root.players=root.accounts
    root.characterAccounts=type(root.characterAccounts)=="table"and root.characterAccounts or root.characterOwners or{}
    root.characterOwners=root.characterAccounts
    root.adminTwinkTombstones=type(root.adminTwinkTombstones)=="table"and root.adminTwinkTombstones or{}
    return{accounts=root.accounts,relationships=root.characterAccounts,tombstones=root.adminTwinkTombstones,localAccountUUID=root.localAccountUUID}
end
function PlayerData:SetLocalAccountUUID(accountUUID)
    if not validId(accountUUID)then return false,"INVALID_ACCOUNT_UUID"end
    self.root.localAccountUUID=accountUUID
    return true
end
function PlayerData:SetCharacterOwner(guid,accountUUID)
    if not validId(guid)or accountUUID~=nil and not validId(accountUUID)then return false,"INVALID_IDENTITY"end
    self.root.characterOwners[guid]=accountUUID
    local character=self.root.characters[guid]
    if character then character.playerId=accountUUID end
    return true
end
function PlayerData:GetCharacters() return self.root.characters end
function PlayerData:GetCharacter(guid) return validId(guid)and self.root.characters[guid]or nil end
function PlayerData:GetOrCreateCharacter(guid)
    if not validId(guid)then return nil end;local record=self.root.characters[guid]
    if not record then record={guid=guid,blockMeta={}};self.root.characters[guid]=record end
    record.blockMeta=type(record.blockMeta)=="table"and record.blockMeta or{};return record
end
function PlayerData:GetPlayers() return self.root.players end
function PlayerData:GetOwners() return self.root.characterOwners end
function PlayerData:GetDiagnostics()
    local blocks=0;for _,record in pairs(self.root.characters)do for _ in pairs(type(record)=="table"and record.blockMeta or{})do blocks=blocks+1 end end
    return{characters=HolyStorm.Utils.TableCount(self.root.characters),players=HolyStorm.Utils.TableCount(self.root.players),owners=HolyStorm.Utils.TableCount(self.root.characterOwners),blocks=blocks,normalizationVersion=self.root.normalizationVersion}
end
function PlayerData:GetForeignWatermark(domain)if domain then return tonumber(self.root.sync.foreignWatermarks[domain])or 0 end;local value=tonumber(self.root.sync.foreignWatermark)or 0;for _,watermark in pairs(self.root.sync.foreignWatermarks)do value=math.max(value,tonumber(watermark)or 0)end;return value end
function PlayerData:AdvanceForeignWatermark(owner,timestamp,domain)if type(owner)=="string"and not self:IsLocallyOwned(owner)then local value=tonumber(timestamp)or 0;domain=domain or"global";self.root.sync.foreignWatermarks[domain]=math.max(self:GetForeignWatermark(domain),value);self.root.sync.foreignWatermark=math.max(tonumber(self.root.sync.foreignWatermark)or 0,value)end;return self:GetForeignWatermark(domain)end
function PlayerData:IsLocallyOwned(guid)
    if guid==UnitGUID("player")then return true end;local localId=HolyStorm.db.global.localPlayerId;return localId and self.root.characterOwners[guid]==localId or false
end
function PlayerData:GetBlock(guid,blockId)
    local record=self:GetCharacter(guid);local definition=self.blocks[blockId];if not record or not definition then return nil end
    if #definition.fields==1 then return record[definition.fields[1]],record.blockMeta and copy(record.blockMeta[blockId])end
    local data={};for _,field in ipairs(definition.fields)do data[field]=copy(record[field])end;return data,record.blockMeta and copy(record.blockMeta[blockId])
end
function PlayerData:GetMetadata(guid,blockId)
    local record=self:GetCharacter(guid);local meta=record and record.blockMeta and record.blockMeta[blockId];if not meta then return nil end
    local result=copy(meta);local definition=self.blocks[blockId];local header=self:GetBlockHeader(guid,blockId)
    result.objectId=guid.."\031"..blockId;result.owner=result.owner or guid;result.block=blockId;result.guid=guid
    result.schemaVersion=header and header.schemaVersion or definition and definition.schemaVersion
    result.snapshotVersion=header and header.snapshotVersion or definition and definition.snapshotVersion
    return result
end
function PlayerData:CompareMetadata(localMeta,remoteMeta)
    if type(remoteMeta)~="table"then return -1,"INVALID_METADATA"end;local rv=tonumber(remoteMeta.version);if not rv or rv<0 then return -1,"INVALID_VERSION"end
    local lv=tonumber(localMeta and localMeta.version)or-1;if rv~=lv then return rv>lv and 1 or-1,rv>lv and"NEWER_VERSION"or"STALE_VERSION"end
    local remoteDirect=remoteMeta.direct==true;local localDirect=localMeta and localMeta.direct==true;if remoteDirect~=localDirect then return remoteDirect and 1 or-1,remoteDirect and"DIRECT_OWNER"or"INDIRECT_COPY"end
    return 0,"SAME_VERSION"
end
function PlayerData:ValidateBlock(blockId,data)
    local definition=self.blocks[blockId];if not definition or type(data)~="table"then return false,"INVALID_BLOCK_DATA"end
    if definition.validate then local ok,result,reason=HolyStorm.Utils.SafeCall("playerdata.validate:"..blockId,definition.validate,data);if not ok then return false,tostring(result)end;if result==false then return false,reason or"VALIDATION_FAILED"end end
    return true
end
function PlayerData:ApplyBlock(guid,blockId,data,meta,mode)
    if self.futureSchema then return false,"FUTURE_SCHEMA_READ_ONLY",false end
    if not validId(guid)or type(meta)~="table"then return false,"INVALID_IDENTITY",false end
    local definition=self.blocks[blockId];if not definition then return false,"INVALID_BLOCK_DATA",false end
    if definition.persistenceEnabled==false then return false,"PERSISTENCE_DISABLED",true end
    if mode=="remote"and definition.syncEnabled==false then return false,"SYNC_DISABLED",true end
    local valid,reason=self:ValidateBlock(blockId,data);if not valid then return false,reason or"INVALID_BLOCK_DATA",false end
    local record=self:GetOrCreateCharacter(guid);local current=record.blockMeta[blockId]
    if mode=="remote"then
        if meta.owner~=guid then return false,"INVALID_OWNER",true end
        local incomingVersion=tonumber(meta.version);if not incomingVersion or incomingVersion<1 or incomingVersion%1~=0 then return false,"MISSING_REQUIRED_METADATA",true end
        local originCreatedAt=tonumber(meta.originCreatedAt or meta.updatedAt);if not originCreatedAt or originCreatedAt<=0 or originCreatedAt~=originCreatedAt or originCreatedAt==math.huge then return false,"MISSING_REQUIRED_METADATA",true end
        local storedVersion=tonumber(current and current.version)or 0;local identical=false
        if current and storedVersion==incomingVersion then
            local existing;if#definition.fields==1 then existing=record[definition.fields[1]]else existing={};for _,field in ipairs(definition.fields)do existing[field]=record[field]end end
            identical=same(existing,data,definition)
        end
        local locallyOwned=self:IsLocallyOwned(guid)
        if incomingVersion<storedVersion then return false,"STALE_REVISION",true end
        if incomingVersion==storedVersion then
            if identical then
                if not locallyOwned and meta.direct==true and current.direct~=true then current.direct=true;current.receivedFrom=meta.receivedFrom;current.receivedAt=now();current.originCreatedAt=current.originCreatedAt or current.updatedAt end
                return true,"NOOP",true
            end
            return false,locallyOwned and"SELF_OWNED_REMOTE_REJECT"or"SAME_REVISION_CONFLICT",true
        end
        if locallyOwned then return false,"SELF_OWNED_REMOTE_REJECT",true end
    elseif not self:IsLocallyOwned(guid)then return false,"NOT_LOCAL_OWNER",true end
    local clean=copy(data)
    if mode~="remote"and#definition.fields>1 then for _,field in ipairs(definition.fields)do if clean[field]==nil then clean[field]=copy(record[field])end end end
    local version=mode=="remote"and tonumber(meta.version)or((tonumber(current and current.version)or 0)+1)
    local updatedAt=mode=="remote"and tonumber(meta.originCreatedAt or meta.updatedAt)or now()
    if mode~="remote"and current then local existing;if#definition.fields==1 then existing=record[definition.fields[1]]else existing={};for _,field in ipairs(definition.fields)do existing[field]=record[field]end end;if same(existing,clean,definition)then return false,"UNCHANGED",true end end
    if #definition.fields==1 then record[definition.fields[1]]=clean else for _,field in ipairs(definition.fields)do record[field]=clean[field]end end
    -- Keep block-local metadata visible to compatible readers without making it authoritative.
    for _,field in ipairs(definition.fields)do if type(record[field])=="table"then record[field].version=version;record[field].updatedAt=updatedAt end end
    record.blockMeta[blockId]={owner=guid,version=version,updatedAt=updatedAt,originCreatedAt=mode=="remote"and tonumber(meta.originCreatedAt or meta.updatedAt)or updatedAt,committedAt=mode=="remote"and tonumber(meta.committedAt or meta.originCreatedAt or meta.updatedAt)or updatedAt,receivedAt=mode=="remote"and now()or nil,source=meta.source or(mode=="remote"and"sync"or"local"),receivedFrom=mode=="remote"and meta.receivedFrom or nil,direct=mode~="remote"or meta.direct==true}
    record.version=math.max(tonumber(record.version)or 0,version);record.updatedAt=math.max(tonumber(record.updatedAt)or 0,updatedAt);record.updatedBy=guid
    if mode=="remote"then self:AdvanceForeignWatermark(guid,updatedAt,"character")end
    HolyStorm.Events:Emit("HS_PLAYERDATA_UPDATED",guid,blockId,copy(record.blockMeta[blockId]),mode)
    HolyStorm.Events:Emit(definition.event,guid,self:GetBlock(guid,blockId),mode~="remote")
    if mode~="remote"then HolyStorm.Events:Emit("HS_PLAYERDATA_OWNED_UPDATED",guid,blockId,copy(record.blockMeta[blockId]))end
    return true,copy(record.blockMeta[blockId])
end
function PlayerData:WriteOwnedBlock(guid,blockId,data,source) return self:ApplyBlock(guid,blockId,data,{source=source or"local"},"owned")end
local function snapshotVersion(data)
    if type(data)~="table"then return nil end
    return tonumber(data.snapshotVersion or data.schemaVersion)
end
function PlayerData:GetBlockHeader(guid,blockId)
    local record=self:GetCharacter(guid);local definition=self.blocks[blockId];if not record or not definition then return nil end
    local result={};for _,field in ipairs(definition.fields)do local value=record[field];if type(value)=="table"then if value.snapshotVersion~=nil then result.snapshotVersion=value.snapshotVersion end;if value.schemaVersion~=nil then result.schemaVersion=value.schemaVersion end end end;return result
end
function PlayerData:LogRemoteBlockDecision(decision,reason,guid,blockId,incoming,stored,incomingData,storedData,validationStatus)
    local incomingVersion=tonumber(incoming and incoming.version);local storedVersion=tonumber(stored and stored.version)
    HolyStorm.Logger:Write(decision=="REJECT"and"WARN"or"DEBUG","PlayerData","freshness","Character block sync decision",{
        decision=decision,reason=reason,character=guid,block=blockId,origin=incoming and incoming.owner,storedOrigin=stored and stored.owner,
        incomingRevision=incomingVersion,storedRevision=storedVersion,
        incomingOriginCreatedAt=tonumber(incoming and(incoming.originCreatedAt or incoming.updatedAt)),storedOriginCreatedAt=tonumber(stored and(stored.originCreatedAt or stored.updatedAt)),
        incomingCommittedAt=tonumber(incoming and incoming.committedAt),storedCommittedAt=tonumber(stored and stored.committedAt),
        incomingReceivedAt=tonumber(incoming and incoming.receivedAt),storedReceivedAt=tonumber(stored and stored.receivedAt),
        incomingSource=incoming and incoming.source,storedSource=stored and stored.source,
        incomingReceivedFrom=incoming and incoming.receivedFrom,storedReceivedFrom=stored and stored.receivedFrom,
        authority=incoming and(incoming.direct==true and"DIRECT_ORIGIN"or"RELAY"),
        incomingSchemaVersion=type(incomingData)=="table"and tonumber(incomingData.schemaVersion),storedSchemaVersion=type(storedData)=="table"and tonumber(storedData.schemaVersion),
        incomingSnapshotVersion=snapshotVersion(incomingData),storedSnapshotVersion=snapshotVersion(storedData),
        validationStatus=validationStatus or"PASSED"
    })
end
function PlayerData:AcceptRemoteBlock(guid,blockId,data,meta,senderGuid,sender)
    meta=copy(meta or{});meta.receivedFrom=sender or senderGuid;meta.direct=senderGuid~=nil and senderGuid==guid;meta.receivedAt=now()
    local stored=self:GetMetadata(guid,blockId);local storedData=self:GetBlockHeader(guid,blockId)
    local ok,reason,validated=self:ApplyBlock(guid,blockId,data,meta,"remote")
    local localOwner=self:IsLocallyOwned(guid);local returnValue
    if ok and type(reason)=="table"then
        returnValue=reason
        local incomingRevision=tonumber(meta.version);local previousRevision=tonumber(stored and stored.version)or 0
        reason=incomingRevision and incomingRevision>previousRevision+1 and"REVISION_GAP_ACCEPTED"or"ACCEPTED"
    end
    local decision=ok and(reason=="NOOP"and"NOOP"or"ACCEPT")or"REJECT"
    self:LogRemoteBlockDecision(decision,reason,guid,blockId,meta,stored,data,storedData,validated and"PASSED"or"FAILED")
    if ok and reason=="NOOP"then return true,"NOOP"end
    if ok then return true,returnValue or"ACCEPTED"end
    return ok,reason
end
function PlayerData:ObserveIdentity(guid,data,source)
    if not validId(guid)or type(data)~="table"or not self:IsLocallyOwned(guid)then return false end
    return self:WriteOwnedBlock(guid,"identity",data,source or"observation")
end
function PlayerData:GetBlockFreshness(guid,blockId)
    local definition=self.blocks[blockId];local meta=self:GetMetadata(guid,blockId);local staleAfter=definition and definition.staleAfter or 21600
    local localOwner=meta and self:IsLocallyOwned(guid);local updatedAt=meta and(tonumber(localOwner and(meta.committedAt or meta.updatedAt)or(meta.receivedAt))or nil)or nil;local age=updatedAt and now()-updatedAt or nil
    local state=not meta and"MISSING"or age==nil and"UNKNOWN"or age>staleAfter and"STALE"or"CURRENT"
    return{metadata=meta,metadataExists=meta~=nil,stale=state~="CURRENT",state=state,clockDomain=localOwner and"LOCAL_COMMIT"or"LOCAL_RECEIVE",updatedAt=tonumber(meta and(meta.originCreatedAt or meta.updatedAt)),freshnessAt=updatedAt,staleAfter=staleAfter,age=age}
end
function PlayerData:IsStale(guid,blockId)return self:GetBlockFreshness(guid,blockId).stale end
function PlayerData:RequestRefresh(guid,blocks)
    if not HolyStorm.Sync then return false end
    if not blocks then blocks={};for blockId in pairs(self.blocks)do if blockId~="addon"then blocks[#blocks+1]=blockId end end;table.sort(blocks)end
    for _,blockId in ipairs(blocks)do if self:IsStale(guid,blockId)then HolyStorm.Sync:RequestObject("character",guid.."\031"..blockId,{owner=guid,reason="ON_DEMAND"})end end;return true
end

local identity={"name","realm","class","classFile","race","raceFile","sex","level","faction","guild","guildRank","guildRankIndex","lastSeen"}
PlayerData:RegisterBlock("identity",{fields=identity,event="HS_CHARACTER_UPDATED",staleAfter=3600})
PlayerData:RegisterBlock("addon",{fields={"addon"},event="HS_PRESENCE_UPDATED",staleAfter=3600})
HolyStorm.PlayerData=PlayerData
