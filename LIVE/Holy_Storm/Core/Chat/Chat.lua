local addonVersion="1.0.0"
local HolyStorm=LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local L=LibStub("AceLocale-3.0"):GetLocale("Holy_Storm")

local Chat={version=addonVersion,index={full={},short={}},indexSize=0,processors={},filters={},lastMentionAt=0,recentMessages={},stats={processed=0,errors=0,mentions=0,players=0,urls=0,tokens=0}}
local events={CHAT_MSG_GUILD="GUILD",CHAT_MSG_OFFICER="OFFICER",CHAT_MSG_PARTY="PARTY",CHAT_MSG_PARTY_LEADER="PARTY_LEADER",CHAT_MSG_RAID="RAID",CHAT_MSG_RAID_LEADER="RAID_LEADER",CHAT_MSG_INSTANCE_CHAT="INSTANCE_CHAT",CHAT_MSG_INSTANCE_CHAT_LEADER="INSTANCE_CHAT_LEADER",CHAT_MSG_WHISPER="WHISPER",CHAT_MSG_WHISPER_INFORM="WHISPER_INFORM",CHAT_MSG_SAY="SAY",CHAT_MSG_YELL="YELL"}
local orderedEvents={"CHAT_MSG_GUILD","CHAT_MSG_OFFICER","CHAT_MSG_PARTY","CHAT_MSG_PARTY_LEADER","CHAT_MSG_RAID","CHAT_MSG_RAID_LEADER","CHAT_MSG_INSTANCE_CHAT","CHAT_MSG_INSTANCE_CHAT_LEADER","CHAT_MSG_WHISPER","CHAT_MSG_WHISPER_INFORM","CHAT_MSG_SAY","CHAT_MSG_YELL"}
local sounds={"TELL_MESSAGE","READY_CHECK","RAID_WARNING"}

local function lower(value)return string.lower(tostring(value or""))end
local function normalizeRealm(value)return lower(value):gsub("[%s%-']","")end
local function splitName(value)local name,realm=tostring(value or""):match("^([^%-]+)%-(.+)$");return name or value,realm end
local function normalizedFull(name,realm)local base,embedded=splitName(name);realm=embedded or realm;return lower(base)..(realm and realm~=""and("-"..normalizeRealm(realm))or"")end
local function setting(path)return HolyStorm.Database:Get("chat."..path,"profile")end
local function safeText(value)return tostring(value or""):gsub("[|\r\n]"," ")end
local function markupSegments(text)
 local out,i,start={},1,1;local length=#text
 local function plain(to)if to>=start then out[#out+1]={plain=true,text=text:sub(start,to)}end end
 while i<=length do
  local finish
  if text:sub(i,i+1)=="|H"then local a=text:find("|h",i+2,true);local b=a and text:find("|h",a+2,true);finish=b and b+1
  elseif text:sub(i,i+1)=="|c"then local b=text:find("|r",i+10,true);finish=b and b+1
  elseif text:sub(i,i+1)=="|T"then local b=text:find("|t",i+2,true);finish=b and b+1
  elseif text:sub(i,i+1)=="|A"then local b=text:find("|a",i+2,true);finish=b and b+1
  elseif text:sub(i,i+1)=="||"then finish=i+1 end
  if finish then plain(i-1);out[#out+1]={plain=false,text=text:sub(i,finish)};i=finish+1;start=i else i=i+1 end
 end;plain(length);return out
end
local function words(text)
 local result={};local i=1
 while true do local s,e=text:find("[%a\128-\255][%a\128-\255'%-]*",i);if not s then break end;result[#result+1]={s=s,e=e,value=text:sub(s,e)};i=e+1 end
 return result
end
local function classHex(classFile)
 local color=(C_ClassColor and C_ClassColor.GetClassColor and C_ClassColor.GetClassColor(classFile))or(RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]);if not color then return nil end
 if color.GenerateHexColor then local hex=color:GenerateHexColor();if type(hex)=="string"then if#hex==8 then return hex:sub(3)elseif#hex==6 then return hex end end end;return string.format("%02x%02x%02x",math.floor((color.r or 1)*255+.5),math.floor((color.g or 1)*255+.5),math.floor((color.b or 1)*255+.5))
end

function Chat:RegisterProcessor(id,order,callback)if type(id)~="string"or type(callback)~="function"or self.processors[id]then return false end;self.processors[id]={id=id,order=tonumber(order)or 100,callback=callback};return true end
function Chat:UnregisterProcessor(id)if not self.processors[id]then return false end;self.processors[id]=nil;return true end
function Chat:GetProcessors()local out={};for _,definition in pairs(self.processors)do out[#out+1]=definition end;table.sort(out,function(a,b)if a.order==b.order then return a.id<b.id end;return a.order<b.order end);return out end
function Chat:GetSettings()return HolyStorm.Database:Get("chat","profile")end
function Chat:IsEnabled(event)local channel=events[event];return setting("enabled")==true and HolyStorm.Database:Get("enabled","profile")~=false and(not HolyStorm.Policy or HolyStorm.Policy:IsGuildModuleEnabled("chat"))and channel and setting("channels."..channel)==true end
function Chat:RebuildPlayerIndex()
 local full,short,guild={}, {},HolyStorm.Data.GuildStore:GetCurrent();local guildMatches={}
 for guid,record in pairs(HolyStorm.Data.CharacterStore:GetAll())do
  local name=record and(record.fullName or record.name);if type(name)=="string"and name~=""then local base,embedded=splitName(name);local realm=embedded or record.realm;local fullKey=normalizedFull(base,realm);if realm and realm~=""then full[fullKey]=full[fullKey]and full[fullKey]~=guid and false or guid end;local key=lower(base);local bucket=short[key]or{};bucket[guid]=true;short[key]=bucket;if guild and guild.roster and guild.roster[guid]then local gb=guildMatches[key]or{};gb[guid]=true;guildMatches[key]=gb end end
 end
 local resolved={};for key,bucket in pairs(short)do local only,count=nil,0;for guid in pairs(bucket)do only,count=guid,count+1 end;if count==1 then resolved[key]=only else local best,bestRank,bestName;for guid in pairs(guildMatches[key]or{})do local member=guild.roster[guid]or{};local rank=tonumber(member.rankIndex)or math.huge;local record=HolyStorm.Data.CharacterStore:Get(guid)or{};local name=normalizedFull(record.fullName or record.name or guid,record.realm);if not best or rank<bestRank or(rank==bestRank and(name<bestName or(name==bestName and guid<best)))then best,bestRank,bestName=guid,rank,name end end;resolved[key]=best or false end end
 self.index={full=full,short=resolved};self.indexSize=HolyStorm.Utils.TableCount(full)+HolyStorm.Utils.TableCount(resolved);self.indexDirty=false;return self.indexSize
end
function Chat:InvalidatePlayerIndex()self.indexDirty=true end
function Chat:EnsurePlayerIndex()if self.indexDirty then self:RebuildPlayerIndex()end end
function Chat:ResolveCharacter(token)
 self:EnsurePlayerIndex()
 local name,realm=splitName(token);if realm then local guid=self.index.full[normalizedFull(name,realm)];return guid or nil,guid==false and"AMBIGUOUS"or guid and nil or"NOT_FOUND"end;local guid=self.index.short[lower(name)];return guid or nil,guid==false and"AMBIGUOUS"or guid and nil or"NOT_FOUND"
end
function Chat:IsNativePlayerLink(link)return type(link)=="string"and link:match("^player:[^:]+")~=nil end
function Chat:ResolveNativePlayerLink(link)
 local name=type(link)=="string"and link:match("^player:([^:]+)");if not name then return nil,"INVALID_LINK"end
 return self:ResolveCharacter(name)
end
function Chat:ShowNativePlayerTooltip(owner,link)
 if setting("playerEnrichment")~=true or setting("playerTooltips")==false then return false end
 local characterUUID=self:ResolveNativePlayerLink(link);if not characterUUID or not HolyStorm.CharacterUI then return false end
 return HolyStorm.CharacterUI:ShowTooltip(owner,characterUUID)==true
end
function Chat:HandleNativePlayerLink(link,button,owner)
 if setting("playerEnrichment")~=true then return false end
 local characterUUID=self:ResolveNativePlayerLink(link);if not characterUUID then return false end
 if IsModifiedClick and IsModifiedClick("CHATLINK")then return false end
 if button=="RightButton"and HolyStorm.CharacterActions then return HolyStorm.CharacterActions:CreateContextMenu(owner or DEFAULT_CHAT_FRAME or UIParent,characterUUID)==true end
 if button=="LeftButton"then HolyStorm:CallCapability("character.open",characterUUID,"summary");return true end
 return false
end
function Chat:GetRealName(characterUUID)
 if not HolyStorm.TwinkCore then return nil end;local accountUUID=HolyStorm.TwinkCore:GetAccountUUIDForCharacter(characterUUID);if not accountUUID then return nil end
 local visible=false;for _,entry in ipairs(HolyStorm.TwinkCore:GetVisibleCharactersForViewer(accountUUID,HolyStorm.Data.GuildStore:GetCurrent()))do if entry.characterUUID==characterUUID then visible=true;break end end;if not visible then return nil end
 local account=HolyStorm.TwinkCore:GetAccount(accountUUID);local value=account and account.metadata and account.metadata.realName;return type(value)=="string"and HolyStorm.Utils.Trim(value)~=""and HolyStorm.Utils.Trim(value)or nil
end
function Chat:PlayerLabel(characterUUID,original)
 local record=HolyStorm.Data.CharacterStore:Get(characterUUID)or{};local suffix={}
 if setting("showMain")then local identity=HolyStorm.TwinkCore:GetRosterIdentity(characterUUID,HolyStorm.Data.GuildStore:GetCurrent());local main=identity and identity.accountMain;if main and main~=characterUUID then local mainRecord=HolyStorm.Data.CharacterStore:Get(main);if mainRecord then suffix[#suffix+1]=splitName(mainRecord.name or mainRecord.fullName)end end end
 if setting("showRealName")then local realName=self:GetRealName(characterUUID);if realName then suffix[#suffix+1]=realName end end
 local canonical=record.fullName or record.name or original;local canonicalName,embeddedRealm=splitName(canonical);local _,requestedRealm=splitName(original);local canonicalRealm=embeddedRealm or record.realm;local label=requestedRealm and canonicalRealm and(canonicalName.."-"..canonicalRealm)or canonicalName;if#suffix>0 then label=label.." ("..table.concat(suffix," / ")..")"end
 return safeText(label)
end
function Chat:EnrichPlayers(text,diagnostics)
 if not setting("playerEnrichment")then return text end;local matches=words(text);if#matches==0 then return text end;local out,last={},1
 for _,token in ipairs(matches)do local guid=self:ResolveCharacter(token.value);if guid then local record=HolyStorm.Data.CharacterStore:Get(guid)or{};local color=setting("classColors")and classHex(record.classFile)or nil;out[#out+1]=text:sub(last,token.s-1);out[#out+1]=HolyStorm.RichLinks:MakeHyperlink("player",guid,self:PlayerLabel(guid,token.value),color);last=token.e+1;diagnostics.players[#diagnostics.players+1]={token=token.value,characterUUID=guid};self.stats.players=self.stats.players+1 end end
 out[#out+1]=text:sub(last);return table.concat(out)
end
function Chat:EnrichURLs(text,diagnostics)
 if not setting("urls")then return text end
 local httpPattern="https?://[%w%._~:/%?#%[%]@!$&'()*+,;=%%%-]+";local wwwPattern="www%.[%w%._~:/%?#%[%]@!$&'()*+,;=%%%-]+"
 local out,last,search={},1,1;while search<=#text do local hs,he=text:find(httpPattern,search);local ws,we=text:find(wwwPattern,search);local s,e;if hs and(not ws or hs<=ws)then s,e=hs,he elseif ws then s,e=ws,we else break end;local url=text:sub(s,e);local trailing=url:match("([%.,!?:;%)%]]+)$")or"";local clean=trailing~=""and url:sub(1,#url-#trailing)or url;if clean~=""then out[#out+1]=text:sub(last,s-1);out[#out+1]=HolyStorm.RichLinks:MakeHyperlink("url",clean,clean);out[#out+1]=trailing;last=e+1;diagnostics.urls[#diagnostics.urls+1]=clean;self.stats.urls=self.stats.urls+1 end;search=e+1 end;if last==1 then return text end;out[#out+1]=text:sub(last);return table.concat(out)
end
function Chat:ProcessPlain(text,diagnostics)
 local function transform(value,callback)local out={};for _,segment in ipairs(markupSegments(value))do out[#out+1]=segment.plain and callback(segment.text)or segment.text end;return table.concat(out)end
 local value=text;for _,processor in ipairs(self:GetProcessors())do local ok,result=HolyStorm.Utils.SafeCall("chat.processor:"..processor.id,function()return transform(value,function(part)return processor.callback(part,diagnostics)end)end);if ok and type(result)=="string"then value=result else diagnostics.errors[#diagnostics.errors+1]="PROCESSOR_"..processor.id;self.stats.errors=self.stats.errors+1;if HolyStorm.Logger then HolyStorm.Logger:Write("ERROR","Chat","handler","Chat processor failed",{processor=processor.id,error=tostring(result)})end end end;return value
end
function Chat:DetectMention(text)
 local mention=setting("mentions");if not mention or mention.enabled~=true then return false end;local wanted={};if mention.characterName then local name=GetUnitName and GetUnitName("player",false);if name then wanted[#wanted+1]=name end end;if mention.realName then local real=self:GetRealName(UnitGUID("player"));if real then wanted[#wanted+1]=real end end
 local function wordByte(byte)return byte and((byte>=48 and byte<=57)or(byte>=65 and byte<=90)or(byte>=97 and byte<=122)or byte>=128)end
 for _,segment in ipairs(markupSegments(text))do if segment.plain then local haystack=lower(segment.text);for _,needleValue in ipairs(wanted)do local needle=lower(needleValue);local offset=1;while needle~=""do local s,e=haystack:find(needle,offset,true);if not s then break end;if not wordByte(s>1 and haystack:byte(s-1))and not wordByte(e<#haystack and haystack:byte(e+1))then return true,segment.text:sub(s,e)end;offset=s+1 end end end end;return false
end
function Chat:IsOwnMessage(event,author,args)
 if event=="CHAT_MSG_WHISPER_INFORM"then return true end;local playerGuid=UnitGUID("player");for _,value in ipairs(args or{})do if value==playerGuid then return true end end;local mine=GetUnitName and GetUnitName("player",true);return mine and normalizedFull(author)==normalizedFull(mine)
end
function Chat:AlertMention(messageKey)
 if self.diagnosticMode then return false end
 local now=GetTime and GetTime()or HolyStorm.Utils.Now();for key,timestamp in pairs(self.recentMessages)do if now-timestamp>10 then self.recentMessages[key]=nil end end;if self.recentMessages[messageKey]and now-self.recentMessages[messageKey]<5 then return false end;self.recentMessages[messageKey]=now
 local cooldown=tonumber(setting("mentions.cooldown"))or 2.5;if now-self.lastMentionAt<cooldown then return false end;self.lastMentionAt=now;local configured=setting("mentions.sound");local sound=tonumber(configured)or(SOUNDKIT and SOUNDKIT[tostring(configured)])or(SOUNDKIT and SOUNDKIT.TELL_MESSAGE)or 3081;if PlaySound then PlaySound(sound,"Master")end;self.stats.mentions=self.stats.mentions+1;return true
end
function Chat:ParseForDiagnostics(text,event)
 self.diagnosticMode=true;local ok,rendered,diagnostics=HolyStorm.Utils.SafeCall("chat.diagnostics",function()return self:ProcessMessage(event or"CHAT_MSG_GUILD",text,"Parser-Test")end);self.diagnosticMode=false;if not ok then return tostring(text),{errors={tostring(rendered)}}end;return rendered,diagnostics
end
function Chat:ProcessMessage(event,message,author,...)
 local diagnostics={event=event,protected=0,players={},mentions={},urls={},links={},tokens={},unresolved={},errors={}};if not self:IsEnabled(event)or type(message)~="string"then return message,diagnostics end
 local args={...};local mentioned,mentionText=self:DetectMention(message);if mentioned then diagnostics.mentions[1]=mentionText;if setting("mentions.ownMessages")or not self:IsOwnMessage(event,author,args)then self:AlertMention(tostring(event).."\031"..tostring(author).."\031"..message)end end
 local output={};for _,segment in ipairs(markupSegments(message))do if segment.plain then local ok,value=HolyStorm.Utils.SafeCall("chat.pipeline",function()return self:ProcessPlain(segment.text,diagnostics)end);if ok then output[#output+1]=value else output[#output+1]=segment.text;diagnostics.errors[#diagnostics.errors+1]=tostring(value);self.stats.errors=self.stats.errors+1 end else diagnostics.protected=diagnostics.protected+1;output[#output+1]=segment.text end end
 self.stats.processed=self.stats.processed+1;self.stats.tokens=self.stats.tokens+#diagnostics.tokens;self.lastDiagnostics=diagnostics;return table.concat(output),diagnostics
end
function Chat:Filter(_,event,message,author,...)
 local args={...};local ok,rendered=HolyStorm.Utils.SafeCall("chat.filter:"..tostring(event),function()return Chat:ProcessMessage(event,message,author,unpack(args))end);if not ok then Chat.stats.errors=Chat.stats.errors+1;if HolyStorm.Logger then HolyStorm.Logger:Write("ERROR","Chat","parser","Chat message processing failed",{event=event,error=tostring(rendered)})end;rendered=message end;return false,rendered,author,unpack(args)
end
function Chat:ShowURL(url)
 if not StaticPopupDialogs or not StaticPopup_Show then return false end;StaticPopupDialogs.HOLYSTORM_CHAT_URL={text=L["CHAT_URL_COPY_HELP"],button1=OKAY,hasEditBox=true,editBoxWidth=360,OnShow=function(dialog,value)local box=dialog.EditBox or dialog.editBox;if box then box:SetText(value or"");box:HighlightText();box:SetFocus()end end,EditBoxOnEscapePressed=function(box)box:GetParent():Hide()end,timeout=0,whileDead=true,hideOnEscape=true};StaticPopup_Show("HOLYSTORM_CHAT_URL",nil,nil,url);return true
end
function Chat:GetDiagnostics()
 local channels={};for _,event in ipairs(orderedEvents)do if self:IsEnabled(event)then channels[#channels+1]=events[event]end end;local types={};for id,definition in pairs(HolyStorm.RichLinks:GetTypes())do types[#types+1]={id=id,owner=definition.owner or"core",click=definition.onClick~=nil,tooltip=definition.tooltip~=nil or definition.showTooltip~=nil,fallback=definition.render~=nil}end;table.sort(types,function(a,b)return a.id<b.id end);local tokens={};for id in pairs(HolyStorm.RichLinks:GetTokens())do tokens[#tokens+1]=id end;table.sort(tokens);local processors={"protected-markup","mentions"};for _,definition in ipairs(self:GetProcessors())do processors[#processors+1]=definition.id end;return{enabled=setting("enabled")==true,processors=processors,linkTypes=types,tokens=tokens,indexSize=self.indexSize,indexDirty=self.indexDirty==true,supportedChannels=events,activeChannels=channels,mention=HolyStorm.Utils.DeepCopy(setting("mentions")),stats=HolyStorm.Utils.DeepCopy(self.stats),last=self.lastDiagnostics}
end
function Chat:Initialize()
 self:RegisterProcessor("registered-tokens",10,function(text,diagnostics)if setting("links")then return HolyStorm.RichLinks:RenderRegisteredTokens(text,diagnostics)end;return text end)
 self:RegisterProcessor("rich-links",20,function(text,diagnostics)if setting("links")then return HolyStorm.RichLinks:RenderInline(text,diagnostics)end;return text end)
 self:RegisterProcessor("players",30,function(text,diagnostics)return Chat:EnrichPlayers(text,diagnostics)end)
 self:RegisterProcessor("urls",40,function(text,diagnostics)return Chat:EnrichURLs(text,diagnostics)end)
 self:RebuildPlayerIndex();local function invalidate()Chat:InvalidatePlayerIndex()end;for _,event in ipairs({"HS_CHARACTER_UPDATED","HS_ROSTER_UPDATED","HS_GUILD_UPDATED","HS_TWINKS_UPDATED","HS_ACCOUNT_UPDATED"})do HolyStorm.Events:Register(event,"chat-index",invalidate)end
 HolyStorm.RichLinks:RegisterType({type="url",owner="Chat",validate=function(url)return type(url)=="string"and#url<=320 and(url:match("^https?://")or url:match("^www%."))end,render=function(url,label)return label or url end,onClick=function(url)return Chat:ShowURL(url)end,tooltip=function(url)return L["CHAT_URL_TOOLTIP"],url end})
 self.filterFunction=function(...)return Chat:Filter(...)end;local add=ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter or ChatFrame_AddMessageEventFilter;for _,event in ipairs(orderedEvents)do local ok=add and pcall(add,event,self.filterFunction);if ok then self.filters[event]=true elseif HolyStorm.Logger then HolyStorm.Logger:Write("WARN","Chat","event","Unsupported chat event",{event=event})end end
end
function Chat:Shutdown()
 local remove=ChatFrameUtil and ChatFrameUtil.RemoveMessageEventFilter or ChatFrame_RemoveMessageEventFilter;if remove and self.filterFunction then for event in pairs(self.filters)do pcall(remove,event,self.filterFunction)end end;self.filters={};HolyStorm.Events:UnregisterOwner("chat-index")
end
function Chat:GetSounds()return sounds end
HolyStorm.Chat=Chat
