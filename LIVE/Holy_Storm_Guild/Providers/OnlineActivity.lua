local HolyStorm=LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local Activity=HolyStorm.GuildManagement.Activity
local owner="guild-activity-provider:online"

Activity:RegisterProvider("online",{
 types={"ONLINE_SESSION"},
 enable=function(service)
  local entering=HolyStorm.Events:Register("PLAYER_ENTERING_WORLD",owner,function()HolyStorm.Tasks:Queue("GuildActivity.OpenSession",{delay=1,priority=60,triggerSource="PLAYER_ENTERING_WORLD",metadata={reason="PLAYER_ENTERING_WORLD"}})end)
  local logout=HolyStorm.Events:Register("PLAYER_LOGOUT",owner,function()service:Shutdown("PLAYER_LOGOUT")end)
  if not(entering and logout)then HolyStorm.Events:UnregisterOwner(owner);return false end
  if IsLoggedIn and IsLoggedIn()then HolyStorm.Tasks:Queue("GuildActivity.OpenSession",{delay=1,startupPhase=4,priority=60,triggerSource="ACTIVITY_ENABLE",metadata={reason="ACTIVITY_ENABLE"}})end
  return true
 end,
 disable=function()HolyStorm.Events:UnregisterOwner(owner)end,
})
