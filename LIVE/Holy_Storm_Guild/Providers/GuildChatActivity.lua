local HolyStorm=LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local Activity=HolyStorm.GuildManagement.Activity
local owner="guild-activity-provider:guild-chat"
local function normalizeName(value)return type(value)=="string"and string.lower(value)or nil end

Activity:RegisterProvider("guild-chat",{
 types={"GUILD_CHAT"},
 enable=function(service)
  return HolyStorm.Events:Register("CHAT_MSG_GUILD",owner,function(_,_,sender,...)
   local lineId,guid=select(9,...),select(10,...);local localGuid=UnitGUID("player");local localName=GetUnitName and GetUnitName("player",true);if guid==localGuid or guid==nil and normalizeName(sender)==normalizeName(localName)then service:RecordGuildChat(localGuid,HolyStorm.Utils.Now(),lineId)end
  end)
 end,
 disable=function()HolyStorm.Events:UnregisterOwner(owner)end,
})
