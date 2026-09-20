local addonVersion = "2.0.0"
local HolyStorm = LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local Store = { version=addonVersion }
local identityFields={name=true,realm=true,class=true,classFile=true,race=true,raceFile=true,sex=true,level=true,faction=true,guild=true,guildRank=true,guildRankIndex=true,lastSeen=true}

function Store:Initialize() return HolyStorm.PlayerData:GetRoot()~=nil end
function Store:GetAll() return HolyStorm.PlayerData:GetCharacters() end
function Store:Get(guid) return HolyStorm.PlayerData:GetCharacter(guid) end
function Store:GetOrCreate(guid) return HolyStorm.PlayerData:GetOrCreateCharacter(guid) end
function Store:GetBlock(guid,blockId) return HolyStorm.PlayerData:GetBlock(guid,blockId) end
function Store:GetProjection(guid,blocks)
    local projection={guid=guid}
    for _,blockId in ipairs(blocks or{}) do
        local block=self:GetBlock(guid,blockId)
        if block~=nil then
            if blockId=="identity" then for key,value in pairs(block) do projection[key]=value end else projection[blockId]=block end
        end
    end
    return projection
end
function Store:GetBlockMetadata(guid,blockId) return HolyStorm.PlayerData:GetMetadata(guid,blockId) end
function Store:RequestRefresh(guid,blocks) return HolyStorm.PlayerData:RequestRefresh(guid,blocks) end

-- Compatibility adapter for Core collectors. Remote synchronization uses
-- AcceptRemoteBlock exclusively so relays can never increment owner versions.
function Store:Upsert(guid,changes,source,metadata)
    if type(guid)~="string"or type(changes)~="table"then return false end
    if source=="sync"then
        local changed=false;local processed={}
        for field,value in pairs(changes)do
            local blockId=HolyStorm.PlayerData.fieldToBlock[field]
            if blockId and not processed[blockId]then
                processed[blockId]=true
                local data
                if #HolyStorm.PlayerData.blocks[blockId].fields==1 then data=value else data={};for _,name in ipairs(HolyStorm.PlayerData.blocks[blockId].fields)do data[name]=changes[name]end end
                local ok=HolyStorm.PlayerData:AcceptRemoteBlock(guid,blockId,data,{owner=guid,version=metadata and metadata.version,updatedAt=metadata and metadata.updatedAt,source="legacy-sync"},nil,metadata and metadata.updatedBy);changed=ok or changed
            end
        end
        return changed
    end
    local identity={};local hasIdentity=false;for field in pairs(identityFields)do if changes[field]~=nil then identity[field]=changes[field];hasIdentity=true end end
    local changed=false
    if hasIdentity and HolyStorm.PlayerData:IsLocallyOwned(guid)then changed=HolyStorm.PlayerData:WriteOwnedBlock(guid,"identity",identity,source or"local")or changed end
    local processed={};for field,value in pairs(changes)do
        local blockId=HolyStorm.PlayerData.fieldToBlock[field]
        if blockId and blockId~="identity"and not processed[blockId]then processed[blockId]=true;local data;if #HolyStorm.PlayerData.blocks[blockId].fields==1 then data=value else data={};for _,name in ipairs(HolyStorm.PlayerData.blocks[blockId].fields)do data[name]=changes[name]end end;changed=HolyStorm.PlayerData:WriteOwnedBlock(guid,blockId,data,source or"local")or changed end
    end
    return changed
end
function Store:CaptureCurrent()
    local guid=UnitGUID("player");if not guid then return nil end;local localizedClass,classFile=UnitClass("player");local race,raceFile=UnitRace("player");local guildName=GetGuildInfo("player")
    HolyStorm.PlayerData:WriteOwnedBlock(guid,"identity",{name=GetUnitName("player",true),realm=GetNormalizedRealmName and GetNormalizedRealmName()or GetRealmName(),class=localizedClass,classFile=classFile,race=race,raceFile=raceFile,sex=UnitSex("player"),level=UnitLevel("player"),faction=UnitFactionGroup("player"),guild=guildName,lastSeen=HolyStorm.Utils.Now()},"blizzard")
    local identity=self:GetBlock(guid,"identity")
    return {guid=guid,identity=identity}
end
HolyStorm.Data.CharacterStore=Store

-- Deprecated read-only compatibility entry points. Modules use CharacterStore.
function HolyStorm:GetPlayerDatabase()return HolyStorm.PlayerData:GetCharacters()end
function HolyStorm:UpdatePlayerRecord(guid,data)return Store:Upsert(guid,data,"local")end
function HolyStorm:MergePlayerDatabase()return false,"USE_SYNC_FRAMEWORK"end
