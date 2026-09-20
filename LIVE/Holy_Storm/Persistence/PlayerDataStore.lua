local addonVersion = "1.0.1"
local HolyStorm = LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")

-- HS_Player_DB is the canonical persistent owner-controlled data store.  The
-- legacy HolyStormDB.global.data tables are aliases installed during startup so
-- older readers remain compatible without creating a second source of truth.
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
local function same(left,right)
    local function comparable(value)local result=copy(value);if type(result)=="table"then result.version=nil;result.updatedAt=nil;for _,child in pairs(result)do if type(child)=="table"then child.version=nil;child.updatedAt=nil end end end;return result end
    local a=HolyStorm.Serializer and HolyStorm.Serializer:Serialize(comparable(left))
    local b=HolyStorm.Serializer and HolyStorm.Serializer:Serialize(comparable(right))
    return a~=nil and a==b
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
    local fields={};for _,field in ipairs(definition.fields)do if type(field)~="string"or self.fieldToBlock[field]then return false,"INVALID_BLOCK_FIELD"end;fields[#fields+1]=field;self.fieldToBlock[field]=id end
    self.blocks[id]={id=id,fields=fields,validate=definition.validate,event=definition.event or("HS_"..id:upper().."_UPDATED"),staleAfter=tonumber(definition.staleAfter)or 21600}
    if self.root and type(self.root.characters)=="table"then for guid,record in pairs(self.root.characters)do if validId(guid)and type(record)=="table"then ensureBlockMetadata(record,guid,id,self.blocks[id])end end end
    return true
end
function PlayerData:HasBlock(id)return self.blocks[id]~=nil end

function PlayerData:Initialize()
    HS_Player_DB=type(HS_Player_DB)=="table"and HS_Player_DB or{}
    local legacyFlat=HS_Player_DB.characters==nil and HS_Player_DB or nil
    local root=legacyFlat and{}or HS_Player_DB
    root.schemaVersion=self.schemaVersion;root.characters=type(root.characters)=="table"and root.characters or{};root.players=type(root.players)=="table"and root.players or{};root.characterOwners=type(root.characterOwners)=="table"and root.characterOwners or{};root.sync=type(root.sync)=="table"and root.sync or{};root.sync.foreignWatermark=tonumber(root.sync.foreignWatermark)or 0;root.sync.foreignWatermarks=type(root.sync.foreignWatermarks)=="table"and root.sync.foreignWatermarks or{}
    if legacyFlat then for guid,record in pairs(legacyFlat)do if validId(guid)and type(record)=="table"then root.characters[guid]=copy(record)end end;HS_Player_DB=root end
    local old=HolyStorm.db.global.data or{}
    for guid,record in pairs(type(old.characters)=="table"and old.characters or{})do if validId(guid)and type(record)=="table"and not root.characters[guid]then root.characters[guid]=copy(record)end end
    for id,record in pairs(type(old.players)=="table"and old.players or{})do if validId(id)and type(record)=="table"and not root.players[id]then root.players[id]=copy(record)end end
    for guid,id in pairs(type(old.characterOwners)=="table"and old.characterOwners or{})do if validId(guid)and validId(id)and not root.characterOwners[guid]then root.characterOwners[guid]=id end end
    HolyStorm.db.global.data=old;old.characters=root.characters;old.players=root.players;old.characterOwners=root.characterOwners
    self.root=root
    for guid,record in pairs(root.characters)do
        if not validId(guid)or type(record)~="table"then root.characters[guid]=nil else
            record.guid=guid;record.blockMeta=type(record.blockMeta)=="table"and record.blockMeta or{}
            for blockId,definition in pairs(self.blocks)do ensureBlockMetadata(record,guid,blockId,definition)end
        end
    end
    -- Preserve legacy voluntary profile fields and twink relationships inside
    -- the account store. The character records remain untouched for rollback.
    for guid,record in pairs(root.characters)do if type(record)=="table"then local ownerId=root.characterOwners[guid];local player=ownerId and root.players[ownerId];if player then player.characters=type(player.characters)=="table"and player.characters or{};if player.characters[guid]==nil then player.characters[guid]=true end;player.metadata=type(player.metadata)=="table"and player.metadata or{};if not player.metadata.realName and type(record.realName)=="string"then player.metadata.realName=record.realName end;if not player.metadata.birthday and type(record.birthday)=="string"then player.metadata.birthday=record.birthday end;for twinkGuid,known in pairs(type(record.knownTwinks)=="table"and record.knownTwinks or{})do if known==true and validId(twinkGuid)then if player.characters[twinkGuid]==nil then player.characters[twinkGuid]=true end;root.characterOwners[twinkGuid]=ownerId end end end end end
    for _,player in pairs(root.players)do if type(player)=="table"then player.characters=type(player.characters)=="table"and player.characters or{};if not player.ownerGuid then player.ownerGuid=player.mainCharacter or next(player.characters)end end end
    return true
end

function PlayerData:GetRoot() return self.root end
function PlayerData:GetCharacters() return self.root.characters end
function PlayerData:GetCharacter(guid) return validId(guid)and self.root.characters[guid]or nil end
function PlayerData:GetOrCreateCharacter(guid)
    if not validId(guid)then return nil end;local record=self.root.characters[guid]
    if not record then record={guid=guid,blockMeta={}};self.root.characters[guid]=record end
    record.blockMeta=type(record.blockMeta)=="table"and record.blockMeta or{};return record
end
function PlayerData:GetPlayers() return self.root.players end
function PlayerData:GetOwners() return self.root.characterOwners end
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
    local result=copy(meta);result.objectId=guid.."\031"..blockId;result.owner=result.owner or guid;result.block=blockId;result.guid=guid;return result
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
    if not validId(guid)or type(meta)~="table"then return false,"INVALID_IDENTITY"end;local valid,reason=self:ValidateBlock(blockId,data);if not valid then return false,reason end
    local record=self:GetOrCreateCharacter(guid);local definition=self.blocks[blockId];local current=record.blockMeta[blockId]
    if mode=="remote"then
        if meta.owner~=guid then return false,"OWNER_MISMATCH"end
        local decision,why=self:CompareMetadata(current,meta);if decision<=0 then return false,why end
        if self:IsLocallyOwned(guid)and meta.direct~=true then return false,"LOCAL_OWNER_PROTECTED"end
    elseif not self:IsLocallyOwned(guid)then return false,"NOT_LOCAL_OWNER" end
    local clean=copy(data);if mode~="remote"and#definition.fields>1 then for _,field in ipairs(definition.fields)do if clean[field]==nil then clean[field]=copy(record[field])end end end;local version=mode=="remote"and tonumber(meta.version)or((tonumber(current and current.version)or 0)+1);local updatedAt=mode=="remote"and(tonumber(meta.updatedAt)or 0)or now()
    if mode~="remote"and current then local existing=self:GetBlock(guid,blockId);if same(existing,clean)then return false,"UNCHANGED"end end
    if #definition.fields==1 then record[definition.fields[1]]=clean else for _,field in ipairs(definition.fields)do record[field]=copy(clean[field])end end
    -- Keep block-local metadata visible to compatible readers without making it authoritative.
    for _,field in ipairs(definition.fields)do if type(record[field])=="table"then record[field].version=version;record[field].updatedAt=updatedAt end end
    record.blockMeta[blockId]={owner=guid,version=version,updatedAt=updatedAt,source=meta.source or(mode=="remote"and"sync"or"local"),receivedFrom=meta.receivedFrom,direct=mode~="remote"or meta.direct==true}
    record.version=math.max(tonumber(record.version)or 0,version);record.updatedAt=math.max(tonumber(record.updatedAt)or 0,updatedAt);record.updatedBy=guid
    if mode=="remote"then self:AdvanceForeignWatermark(guid,updatedAt,"character")end
    HolyStorm.Events:Emit("HS_PLAYERDATA_UPDATED",guid,blockId,copy(record.blockMeta[blockId]),mode)
    HolyStorm.Events:Emit(definition.event,guid,self:GetBlock(guid,blockId),mode~="remote")
    if mode~="remote"then HolyStorm.Events:Emit("HS_PLAYERDATA_OWNED_UPDATED",guid,blockId,copy(record.blockMeta[blockId]))end
    return true,copy(record.blockMeta[blockId])
end
function PlayerData:WriteOwnedBlock(guid,blockId,data,source) return self:ApplyBlock(guid,blockId,data,{source=source or"local"},"owned")end
function PlayerData:AcceptRemoteBlock(guid,blockId,data,meta,senderGuid,sender)
    meta=copy(meta or{});meta.receivedFrom=sender or senderGuid;meta.direct=senderGuid~=nil and senderGuid==guid
    local ok,reason=self:ApplyBlock(guid,blockId,data,meta,"remote")
    HolyStorm.Logger:Write(ok and"DEBUG"or(reason=="STALE_VERSION"or reason=="SAME_VERSION")and"DEBUG"or"WARN","PlayerData","freshness",ok and"Character block accepted"or"Character block rejected",{guid=guid,block=blockId,owner=meta.owner,version=meta.version,receivedFrom=meta.receivedFrom,direct=meta.direct,reason=reason})
    return ok,reason
end
function PlayerData:ObserveIdentity(guid,data,source)
    if not validId(guid)or type(data)~="table"or not self:IsLocallyOwned(guid)then return false end
    return self:WriteOwnedBlock(guid,"identity",data,source or"observation")
end
function PlayerData:IsStale(guid,blockId)
    local definition=self.blocks[blockId];local meta=self:GetMetadata(guid,blockId);return not meta or now()-(tonumber(meta.updatedAt)or 0)>(definition and definition.staleAfter or 21600)
end
function PlayerData:RequestRefresh(guid,blocks)
    if not HolyStorm.Sync then return false end
    if not blocks then blocks={};for blockId in pairs(self.blocks)do if blockId~="addon"then blocks[#blocks+1]=blockId end end;table.sort(blocks)end
    for _,blockId in ipairs(blocks)do if self:IsStale(guid,blockId)then HolyStorm.Sync:RequestObject("character",guid.."\031"..blockId,{owner=guid,reason="ON_DEMAND"})end end;return true
end

local identity={"name","realm","class","classFile","race","raceFile","sex","level","faction","guild","guildRank","guildRankIndex","lastSeen"}
PlayerData:RegisterBlock("identity",{fields=identity,event="HS_CHARACTER_UPDATED",staleAfter=3600})
PlayerData:RegisterBlock("addon",{fields={"addon"},event="HS_PRESENCE_UPDATED",staleAfter=3600})
HolyStorm.PlayerData=PlayerData
