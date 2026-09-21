local HolyStorm=LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local L=LibStub("AceLocale-3.0"):GetLocale("Holy_Storm_Chat")
local ChatOptions={parserResult=nil,registered=false}

local function get(path)return HolyStorm.Database:Get("chat."..path,"profile")end
local function set(path,value)HolyStorm.Database:Set("chat."..path,value,"profile")end

function ChatOptions:Build()
 local channelArgs={};local channelOrder={"GUILD","OFFICER","PARTY","PARTY_LEADER","RAID","RAID_LEADER","INSTANCE_CHAT","INSTANCE_CHAT_LEADER","WHISPER","WHISPER_INFORM","SAY","YELL"}
 for index,id in ipairs(channelOrder)do local channelId=id;channelArgs[channelId]={type="toggle",name=L["CHAT_CHANNEL_"..channelId],order=index,get=function()return get("channels."..channelId)end,set=function(_,value)set("channels."..channelId,value)end}end
 return{type="group",name=L["CHAT_SETTINGS"],order=2,args={
  enabled={type="toggle",name=L["CHAT_ENABLED"],order=1,get=function()return get("enabled")end,set=function(_,value)set("enabled",value)end},
  enrichment={type="toggle",name=L["CHAT_PLAYER_ENRICHMENT"],order=2,get=function()return get("playerEnrichment")end,set=function(_,value)set("playerEnrichment",value)end},
  classColors={type="toggle",name=L["CHAT_CLASS_COLORS"],order=3,get=function()return get("classColors")end,set=function(_,value)set("classColors",value)end},
  tooltips={type="toggle",name=L["CHAT_PLAYER_TOOLTIPS"],order=4,get=function()return get("playerTooltips")end,set=function(_,value)set("playerTooltips",value)end},
  showMain={type="toggle",name=L["CHAT_SHOW_MAIN"],order=5,get=function()return get("showMain")end,set=function(_,value)set("showMain",value)end},
  showRealName={type="toggle",name=L["CHAT_SHOW_REAL_NAME"],desc=L["CHAT_REAL_NAME_PRIVACY"],order=6,get=function()return get("showRealName")end,set=function(_,value)set("showRealName",value)end},
  links={type="toggle",name=L["CHAT_LINKS"],order=7,get=function()return get("links")end,set=function(_,value)set("links",value)end},
  urls={type="toggle",name=L["CHAT_URLS"],order=8,get=function()return get("urls")end,set=function(_,value)set("urls",value)end},
  mentions={type="group",inline=true,name=L["CHAT_MENTIONS"],order=20,args={
   enabled={type="toggle",name=L["CHAT_MENTION_ENABLED"],order=1,get=function()return get("mentions.enabled")end,set=function(_,value)set("mentions.enabled",value)end},
   character={type="toggle",name=L["CHAT_MENTION_CHARACTER"],order=2,get=function()return get("mentions.characterName")end,set=function(_,value)set("mentions.characterName",value)end},
   realName={type="toggle",name=L["CHAT_MENTION_REAL_NAME"],order=3,get=function()return get("mentions.realName")end,set=function(_,value)set("mentions.realName",value)end},
   own={type="toggle",name=L["CHAT_MENTION_OWN"],order=4,get=function()return get("mentions.ownMessages")end,set=function(_,value)set("mentions.ownMessages",value)end},
   sound={type="select",name=L["CHAT_MENTION_SOUND"],order=5,values={TELL_MESSAGE=L["CHAT_SOUND_TELL"],READY_CHECK=L["CHAT_SOUND_READY_CHECK"],RAID_WARNING=L["CHAT_SOUND_RAID_WARNING"]},get=function()return get("mentions.sound")end,set=function(_,value)set("mentions.sound",value)end},
   test={type="execute",name=L["CHAT_SOUND_TEST"],order=6,func=function()local value=get("mentions.sound");local sound=tonumber(value)or(SOUNDKIT and SOUNDKIT[tostring(value)])or(SOUNDKIT and SOUNDKIT.TELL_MESSAGE)or 3081;if PlaySound then PlaySound(sound,"Master")end end},
  }},
  channels={type="group",inline=true,name=L["CHAT_CHANNELS"],order=30,args=channelArgs},
  diagnostics={type="group",inline=true,name=L["CHAT_DIAGNOSTICS"],order=40,args={
   status={type="description",order=1,name=function()local diagnostics=HolyStorm.Chat:GetDiagnostics();return string.format(L["CHAT_DIAGNOSTICS_FORMAT"],tostring(diagnostics.enabled),diagnostics.indexSize,#diagnostics.linkTypes,#diagnostics.tokens,table.concat(diagnostics.activeChannels,", "),diagnostics.stats.processed,diagnostics.stats.errors)end},
   parser={type="input",name=L["CHAT_PARSER_TEST"],order=2,width="full",set=function(_,value)ChatOptions.parserResult=HolyStorm.Chat:ParseForDiagnostics(value)end,get=function()return""end},
   result={type="description",order=3,name=function()return ChatOptions.parserResult or L["CHAT_PARSER_EMPTY"]end},
  }},
 }}
end

function ChatOptions:RegisterExtension()
 if self.registered then return true end;self.registered=true
 return HolyStorm:RegisterUIExtension("Chat",{id="chat.options",order=2,initialize=function()
  local options=HolyStorm:GetModule("Options",true);return options and options:RegisterOptionsTab("chat",ChatOptions:Build())
 end})
end

HolyStorm.ChatOptions=ChatOptions
