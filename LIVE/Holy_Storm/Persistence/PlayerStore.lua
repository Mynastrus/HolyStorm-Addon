local addonVersion="2.0.0"
local HolyStorm=LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local Store={version=addonVersion}
local function copy(value)return HolyStorm.Utils.DeepCopy(value)end
function Store:Initialize()
 local players,owners=HolyStorm.PlayerData:GetPlayers(),HolyStorm.PlayerData:GetOwners();for id,player in pairs(players)do if type(id)~="string"or#id>128 or type(player)~="table"then players[id]=nil else player.id=id;player.characters=type(player.characters)=="table"and player.characters or{};player.roles=type(player.roles)=="table"and player.roles or{};player.version=tonumber(player.version)or 0;player.updatedAt=tonumber(player.updatedAt)or 0 end end;for guid,id in pairs(owners)do if type(guid)~="string"or type(id)~="string"then owners[guid]=nil end end;self:Create(HolyStorm.db.global.localPlayerId,HolyStorm.db.global.installId)
end
function Store:GetAll()return HolyStorm.PlayerData:GetPlayers()end
function Store:GetLocalPlayerId()return HolyStorm.db.global.localPlayerId end
function Store:Get(id)return type(id)=="string"and self:GetAll()[id]or nil end
function Store:Create(id,installId)if type(id)~="string"then return nil end;local p=self:Get(id);if not p then p={id=id,installId=installId,characters={},roles={},version=0,createdAt=HolyStorm.Utils.Now(),updatedAt=0};self:GetAll()[id]=p end;p.characters=type(p.characters)=="table"and p.characters or{};p.roles=type(p.roles)=="table"and p.roles or{};return p end
function Store:GetCharacterOwner(guid)return type(guid)=="string"and HolyStorm.PlayerData:GetOwners()[guid]or nil end
function Store:LinkCharacter(playerId,guid,characterData,remote)
 if HolyStorm.TwinkCore and HolyStorm.TwinkCore.localAccountUUID then if remote then return false,"USE_TWINK_CORE"end;if playerId==HolyStorm.TwinkCore:GetLocalAccountUUID()then if characterData then HolyStorm.Data.CharacterStore:Upsert(guid,characterData,"local")end;return HolyStorm.TwinkCore:ConfirmLocalCharacter(guid)end;return false,"NOT_LOCAL_ACCOUNT"end
 if type(playerId)~="string"or type(guid)~="string"then return false end;if not remote and playerId~=self:GetLocalPlayerId()then return false end;local player=self:Create(playerId);local oldId=self:GetCharacterOwner(guid);local changed=oldId~=playerId or player.characters[guid]~=true;if characterData then HolyStorm.Data.CharacterStore:Upsert(guid,characterData,"local")end
 if oldId and oldId~=playerId then local old=self:Get(oldId);if old then old.characters[guid]=nil end end;HolyStorm.PlayerData:GetOwners()[guid]=playerId;player.characters[guid]=true;local character=HolyStorm.PlayerData:GetOrCreateCharacter(guid);character.playerId=playerId
 if not remote and changed then player.version=(player.version or 0)+1;player.updatedAt=HolyStorm.Utils.Now();player.ownerGuid=UnitGUID("player");HolyStorm.Events:Emit("HS_PLAYER_UPDATED",playerId,player);HolyStorm.Events:Emit("HS_PLAYERDATA_ACCOUNT_OWNED_UPDATED",playerId)end;return changed
end
function Store:LinkLocalCharacter(guid)if HolyStorm.TwinkCore and HolyStorm.TwinkCore.localAccountUUID then return HolyStorm.TwinkCore:ConfirmLocalCharacter(guid)end;return self:LinkCharacter(self:GetLocalPlayerId(),guid)end
function Store:SetMainCharacter(playerId,guid)if HolyStorm.TwinkCore and playerId==HolyStorm.TwinkCore:GetLocalAccountUUID()then return HolyStorm.TwinkCore:SetAccountMain(guid)end;return false end
function Store:UpdateLocalMetadata(changes)
 if type(changes)~="table"then return false end;local p=self:Get(self:GetLocalPlayerId());local metadata=copy(p and p.metadata or{});for key,value in pairs(changes)do metadata[key]=value end;return self:SetLocalMetadata(metadata)
end
function Store:SetLocalMetadata(metadata)
 if HolyStorm.TwinkCore and HolyStorm.TwinkCore.localAccountUUID then return HolyStorm.TwinkCore:SetAccountMetadata(metadata)end;return false
end
function Store:Export(id)return HolyStorm.TwinkCore and HolyStorm.TwinkCore:ExportOwnerSnapshot(id)or nil end
function Store:GetMetadata(id)return HolyStorm.TwinkCore and HolyStorm.TwinkCore:GetOwnerMetadata(id)or nil end
function Store:AcceptRemote()return false,"USE_TWINK_SYNC_DOMAIN"end
HolyStorm.Data.PlayerStore=Store;HolyStorm.PlayerManager=Store
Store.GetProfiles,Store.GetProfile,Store.CreateProfile=Store.GetAll,Store.Get,Store.Create
function Store:RegisterCurrentCharacter()local c=HolyStorm.Data.CharacterStore:CaptureCurrent();if c then self:LinkLocalCharacter(c.guid);return self:GetLocalPlayerId()end end
function Store:MigrateLegacyCharacters()return 0 end
