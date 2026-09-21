local root=(arg[0]:gsub("tools[/\\]test_chat.lua$","")).."LIVE/Holy_Storm/"
unpack=unpack or table.unpack
local locale=setmetatable({RICH_LINK_LIMIT="link limit",RICH_ITEM_FALLBACK="Item %s",RICH_POI_UNAVAILABLE="POI unavailable",RICH_CONTENT_UNAVAILABLE="Content unavailable",CHAT_URL_COPY_HELP="Copy",CHAT_URL_TOOLTIP="URL",ACCOUNT_MAIN="Account main",GUILD_MAIN="Guild main",SHADOW_MAIN="Guild fallback"},{__index=function(_,key)return key end})
local profile={enabled=true,chat={enabled=true,playerEnrichment=true,classColors=true,playerTooltips=true,showMain=false,showRealName=false,links=true,urls=true,mentions={enabled=true,characterName=true,realName=false,sound=3081,cooldown=2.5,ownMessages=false},channels={GUILD=true,OFFICER=true,PARTY=true,PARTY_LEADER=true,RAID=true,RAID_LEADER=true,INSTANCE_CHAT=true,INSTANCE_CHAT_LEADER=true,WHISPER=true,WHISPER_INFORM=true,SAY=true,YELL=true}}}
local records={A={guid="A",name="Marithiel",realm="Norgannon",classFile="PALADIN",class="Paladin",level=80,itemLevel=620},T={guid="T",name="Tom",realm="Norgannon",classFile="MAGE"},B={guid="B",name="Twin",realm="RealmOne",classFile="DRUID"},C={guid="C",name="Twin",realm="RealmTwo",classFile="WARRIOR"}}
local guild={id="guild",roster={A={online=true,rank="Member"},T={online=true},B={online=true}}};local filters,removed,listeners={},{},{};local sounds=0;local clock=100;local opens={};local allCalls=0;local modifiedClick=false;local editBox={text="",cursor=0}
local HolyStorm={Data={CharacterStore={},GuildStore={}},Utils={},Database={},Policy={},Events={},RichLinks=nil,MapLinks={},Content={},CharacterActions={},CharacterUI={},Logger={Write=function()end},TwinkCore={},capabilities={}}
function LibStub(name)if name=="AceAddon-3.0"then return{GetAddon=function()return HolyStorm end}elseif name=="AceLocale-3.0"then return{GetLocale=function()return locale end}end end
function HolyStorm.Utils.DeepCopy(v,seen)if type(v)~="table"then return v end;seen=seen or{};if seen[v]then return seen[v]end;local out={};seen[v]=out;for k,x in pairs(v)do out[HolyStorm.Utils.DeepCopy(k,seen)]=HolyStorm.Utils.DeepCopy(x,seen)end;return out end
function HolyStorm.Utils.TableCount(v)local n=0;for _ in pairs(v or{})do n=n+1 end;return n end
function HolyStorm.Utils.Trim(v)return tostring(v or""):match("^%s*(.-)%s*$")end
function HolyStorm.Utils.SafeCall(_,fn,...)local result={pcall(fn,...)};local ok=table.remove(result,1);return ok,unpack(result)end
function HolyStorm.Utils.Now()return clock end
function HolyStorm.Database:Get(path)local value=profile;for key in path:gmatch("[^%.]+")do if type(value)~="table"then return nil end;value=value[key]end;return value end
function HolyStorm.Data.CharacterStore:GetAll()allCalls=allCalls+1;return records end;function HolyStorm.Data.CharacterStore:Get(id)return records[id]end
function HolyStorm.Data.GuildStore:GetCurrent()return guild end
function HolyStorm.Policy:IsGuildModuleEnabled()return true end
function HolyStorm.Events:Register(event,owner,callback)listeners[event]=listeners[event]or{};listeners[event][owner]=callback end
function HolyStorm.Events:UnregisterOwner(owner)for _,bucket in pairs(listeners)do bucket[owner]=nil end end
function HolyStorm.Events:Emit(event,...)for _,callback in pairs(listeners[event]or{})do callback(event,...)end end
function HolyStorm:RegisterModule(metadata,factory)local module={metadata=metadata};factory(module);self.chatModule=module;return module end
function HolyStorm:RegisterCapability(owner,id,handler)self.capabilities[id]={owner=owner,handler=handler};return true end
function HolyStorm:UnregisterCapability(owner,id)local entry=self.capabilities[id];if not entry or entry.owner~=owner then return false end;self.capabilities[id]=nil;return true end
function HolyStorm:IsCapabilityAvailable(id)return self.capabilities[id]~=nil end
function HolyStorm:CallCapability(id,...)local entry=self.capabilities[id];if not entry then return{}end;local result=entry.handler(nil,...);return result~=nil and{[entry.owner]=result}or{}end
function HolyStorm.TwinkCore:GetAccountUUIDForCharacter(id)return id=="A"and"account-A"or nil end
function HolyStorm.TwinkCore:GetVisibleCharactersForViewer(id)return id=="account-A"and{{characterUUID="A"}}or{}end
function HolyStorm.TwinkCore:GetAccount(id)return id=="account-A"and{metadata={realName="Daniel"}}or nil end
function HolyStorm.TwinkCore:GetRosterIdentity(id)return id=="T"and{accountMain="A"}or nil end
function HolyStorm.CharacterUI:ShowTooltip(_,id)opens.tooltip=id;return true end
function HolyStorm.CharacterActions:CreateContextMenu(_,id)opens.menu=id;return true end
HolyStorm:RegisterCapability("Characters","character.open",function(_,id)opens.character=id;return true end)
function HolyStorm.Content:GetVisibleById(id)return id=="guide-one"and{id=id,title="Guide One",type="GUIDE",category="TEST"}or nil end
function HolyStorm.Content:Open(id)opens.content=id;return id=="guide-one" end
function HolyStorm.MapLinks:ResolvePOI()end;function HolyStorm.MapLinks:OpenPOI(id)opens.poi=id end;function HolyStorm.MapLinks:OpenCoordinate(_,x,y)opens.coordinate={x=x,y=y}end
function UnitGUID()return"A"end;function GetUnitName(_,full)return full and"Marithiel-Norgannon"or"Marithiel"end;function GetTime()return clock end;function PlaySound()sounds=sounds+1 end
function IsModifiedClick(kind)return kind=="CHATLINK"and modifiedClick end
function editBox:GetText()return self.text end;function editBox:SetText(value)self.text=value end;function editBox:GetCursorPosition()return self.cursor end;function editBox:SetCursorPosition(value)self.cursor=value end
RAID_CLASS_COLORS={PALADIN={r=1,g=.5,b=.8,GenerateHexColor=function()return"ffff80cc"end},MAGE={r=.2,g=.8,b=1},DRUID={r=1,g=.5,b=0},WARRIOR={r=.7,g=.5,b=.3}}
ChatFrameUtil={AddMessageEventFilter=function(event,fn)filters[event]=fn end,RemoveMessageEventFilter=function(event)removed[event]=true end,GetActiveWindow=function()return editBox end,InsertLink=function(value)editBox.text=editBox.text..value;editBox.cursor=#editBox.text;return true end}
function StaticPopup_Show()end;StaticPopupDialogs={};OKAY="Okay"

assert(loadfile(root.."Core/Content/RichContent.lua"))();HolyStorm.RichContent:Initialize();assert(loadfile(root.."../Holy_Storm_Characters/CharacterDirectory.lua"))();HolyStorm.CharacterDirectory:Initialize("Characters");assert(loadfile(root.."../Holy_Storm_Chat/Chat.lua"))()
-- Standalone feature addons own these registrations in production. Register their
-- public contracts in this focused Chat test fixture so the core remains feature-free.
local function characterRender(target,label)local record=HolyStorm.Data.CharacterStore:Get(target);return label or(record and(record.fullName or record.name))or target end
local function characterClick(target,button,owner)if button=="RightButton"then return HolyStorm.CharacterActions:CreateContextMenu(owner,target)end;return HolyStorm:CallCapability("character.open",target,"summary")end
local function characterTooltip(target)local record=HolyStorm.Data.CharacterStore:Get(target);return record and(record.fullName or record.name)or target,record and record.class end
for _,kind in ipairs({"character","player"})do HolyStorm.RichLinks:RegisterType({type=kind,render=characterRender,chatText=function(target)local record=HolyStorm.Data.CharacterStore:Get(target);return(record and(record.name or record.fullName)or target):match("^([^%-]+)")end,onClick=characterClick,tooltip=characterTooltip,showTooltip=function(owner,target)return HolyStorm.CharacterUI:ShowTooltip(owner,target)end})end
HolyStorm.RichLinks:RegisterType({type="poi",render=function(target,label)return label or target end,onClick=function(target)return HolyStorm.MapLinks:OpenPOI(target)end})
local function contentRender(target,label)local entry=HolyStorm.Content:GetVisibleById(target);return label or(entry and entry.title)or target end
local function contentClick(target)return HolyStorm.Content:Open(target)end
HolyStorm.RichLinks:RegisterType({type="news",render=contentRender,onClick=contentClick});HolyStorm.RichLinks:RegisterType({type="guide",render=contentRender,onClick=contentClick})
HolyStorm.Chat:Initialize();local Chat=HolyStorm.Chat
local plain=Chat:ProcessMessage("CHAT_MSG_GUILD","Hallo zusammen","Other");assert(plain=="Hallo zusammen","normal text remains unchanged")
local substring=Chat:ProcessMessage("CHAT_MSG_GUILD","Ich esse Tomaten.","Other");assert(substring=="Ich esse Tomaten.","substring is not enriched")
local player=Chat:ProcessMessage("CHAT_MSG_GUILD","Marithiel komm bitte","Other");assert(player:find("|Hholystorm:player:A|h",1,true)and player:find("ffff80cc",1,true),"known player becomes stable UUID link with class color")
assert(not player:find("cffff80ccMarithiel",1,true)and not player:find("Marithiel r",1,true),"class color control codes never leak into the visible label")
local canonicalPlayer=Chat:ProcessMessage("CHAT_MSG_GUILD","marithiel und marithiel-norgannon","Other");assert(canonicalPlayer:find("|h[Marithiel]|h",1,true)and canonicalPlayer:find("|h[Marithiel-Norgannon]|h",1,true),"visible links use canonical capitalization and preserve an explicitly requested realm")
assert(Chat:ProcessMessage("CHAT_MSG_GUILD",player,"Other")==player,"player enrichment is idempotent")
profile.chat.classColors=false;player=Chat:ProcessMessage("CHAT_MSG_GUILD","Marithiel komm bitte","Other");assert(player:find("|Hholystorm:player:A|h",1,true)and not player:find("ffff80cc",1,true),"class color can be disabled independently");profile.chat.classColors=true
profile.chat.showMain=true;local withMain=Chat:ProcessMessage("CHAT_MSG_GUILD","Tom","Other");assert(withMain:find("Tom %(Marithiel%)"),"account main comes from TwinkCore");profile.chat.showMain=false
profile.chat.showRealName=true;local withRealName=Chat:ProcessMessage("CHAT_MSG_GUILD","Marithiel","Other");assert(withRealName:find("Daniel",1,true),"only visible shared account metadata supplies real-name labels");profile.chat.showRealName=false
local ambiguous=Chat:ProcessMessage("CHAT_MSG_GUILD","Twin kommt","Other");assert(ambiguous:find("holystorm:player:B",1,true),"unique current-guild candidate resolves an otherwise cross-realm short name")
guild.roster.C={online=true,rankIndex=0};guild.roster.B.rankIndex=5;Chat:RebuildPlayerIndex();local rankedTwin=Chat:ProcessMessage("CHAT_MSG_GUILD","Twin kommt","Other");assert(rankedTwin:find("holystorm:player:C",1,true),"highest-ranked current guild character wins when names are identical");guild.roster.C=nil;Chat:RebuildPlayerIndex()
guild.roster.B=nil;Chat:RebuildPlayerIndex();ambiguous=Chat:ProcessMessage("CHAT_MSG_GUILD","Twin kommt","Other");assert(not ambiguous:find("holystorm:player",1,true),"ambiguous cross-realm short name is not guessed")
local qualified=Chat:ProcessMessage("CHAT_MSG_GUILD","Twin-RealmTwo kommt","Other");assert(qualified:find("holystorm:player:C",1,true),"realm-qualified name resolves exactly")
local item="|cffa335ee|Hitem:111::::::::80:70::1:2:999:888::::::|h[Marithiel]|h|r";assert(Chat:ProcessMessage("CHAT_MSG_GUILD",item,"Other")==item,"native item link and color wrapper remain byte-for-byte intact")
local textureMarkup="|TInterface\\Icons\\INV_Misc_QuestionMark:16:16|t";local textureResult=Chat:ProcessMessage("CHAT_MSG_GUILD",textureMarkup.." Marithiel","Other");assert(textureResult:sub(1,#textureMarkup)==textureMarkup and textureResult:find("holystorm:player:A",1,true),"texture markup is protected while adjacent plain text is enriched")
local url=Chat:ProcessMessage("CHAT_MSG_GUILD","Siehe https://example.com/test.","Other");assert(url:find("holystorm:url:https%%3A%%2F%%2Fexample.com%%2Ftest",1,false)and url:sub(-1)==".","URL excludes sentence punctuation: "..url)
profile.chat.playerEnrichment=false;local guide=Chat:ProcessMessage("CHAT_MSG_GUILD","[[guide:guide-one|Guide One]] Marithiel","Other");assert(guide:find("holystorm:guide:guide%-one")and not guide:find("holystorm:player",1,true),"links remain active when player enrichment is disabled");profile.chat.playerEnrichment=true
local ok=HolyStorm.RichLinks:RegisterToken({id="TEST",validate=function(payload)return payload=="ok"end,render=function(payload)return HolyStorm.RichLinks:MakeHyperlink("guide","guide-one","Token "..payload)end,fallback="Test"});assert(ok);local token=Chat:ProcessMessage("CHAT_MSG_GUILD","{{TEST:ok}}","Other");assert(token:find("holystorm:guide:guide%-one"),"registered functional token renders through central registry");local unknown=Chat:ProcessMessage("CHAT_MSG_GUILD","{{FUTURE:value}}","Other");assert(unknown=="[FUTURE: value]","unknown token has readable fallback");local malformed=Chat:ProcessMessage("CHAT_MSG_GUILD","{{TEST:no}} tail","Other");assert(malformed=="[Test] tail","invalid token is isolated")
local tokenClick;assert(HolyStorm.RichLinks:RegisterToken({id="ACTION",parser=function(payload)return tonumber(payload)end,display=function(value)return"Action "..value end,onClick=function(value)tokenClick=value end,tooltip=function(value)return"Action",tostring(value)end,fallback="Action"}));local actionToken=Chat:ProcessMessage("CHAT_MSG_GUILD","{{ACTION:42}}","Other");local actionLink=actionToken:match("|H([^|]+)|h");assert(actionLink and actionLink:find("holystorm:token:",1,true),"tokens may expose safe registered click and tooltip handlers");HolyStorm.RichLinks:HandleHyperlink(actionLink,"LeftButton");assert(tokenClick==42,"token click dispatches only the registered handler")
sounds=0;clock=110;Chat:ProcessMessage("CHAT_MSG_GUILD","Marithiel Marithiel Marithiel","Other");assert(sounds==1,"multiple mentions produce one sound");Chat:ProcessMessage("CHAT_MSG_GUILD","Marithiel","Marithiel-Norgannon","A");assert(sounds==1,"own message does not alert");clock=111;Chat:ProcessMessage("CHAT_MSG_GUILD","Marithiel","Other2");assert(sounds==1,"mention cooldown prevents spam");clock=114;Chat:ProcessMessage("CHAT_MSG_GUILD","Marithiel","Other3");assert(sounds==2,"mention alert resumes after cooldown")
profile.chat.mentions.characterName=false;profile.chat.mentions.realName=true;clock=120;Chat:ProcessMessage("CHAT_MSG_GUILD","Daniel, bitte kommen","Other");assert(sounds==3,"voluntarily shared real-name mention is optional and boundary-aware");profile.chat.mentions.characterName=true;profile.chat.mentions.realName=false
profile.chat.channels.SAY=false;assert(Chat:ProcessMessage("CHAT_MSG_SAY","Marithiel https://example.com","Other")=="Marithiel https://example.com","disabled channel remains unchanged")
local beforeBurst=allCalls;HolyStorm.Events:Emit("HS_CHARACTER_UPDATED","A");HolyStorm.Events:Emit("HS_ROSTER_UPDATED","guild");HolyStorm.Events:Emit("HS_ACCOUNT_UPDATED","account-A");assert(Chat.indexDirty and allCalls==beforeBurst,"event bursts only mark the player index dirty");Chat:ProcessMessage("CHAT_MSG_GUILD","Hallo zusammen","Other");assert(allCalls==beforeBurst+1 and not Chat.indexDirty,"the dirty player index rebuilds once on demand")
local scans=allCalls;for _=1,20 do Chat:ProcessMessage("CHAT_MSG_GUILD","Hallo zusammen","Other")end;assert(allCalls==scans,"no full character database scan occurs per message")
assert(Chat:RegisterProcessor("broken-test",35,function()error("expected")end));local readable,brokenDiagnostics=Chat:ProcessMessage("CHAT_MSG_GUILD","Hallo zusammen","Other");assert(readable=="Hallo zusammen"and#brokenDiagnostics.errors==1,"processor errors are isolated and preserve readable text");assert(Chat:UnregisterProcessor("broken-test"))
HolyStorm.RichLinks:HandleHyperlink("holystorm:player:A","LeftButton");assert(opens.character=="A","left click opens character through capability");HolyStorm.RichLinks:HandleHyperlink("holystorm:player:A","RightButton",{});assert(opens.menu=="A","right click uses central character context menu");HolyStorm.RichLinks:HandleHyperlink("holystorm:guide:guide-one","LeftButton");assert(opens.content=="guide-one","guide click uses permission-aware content API")
modifiedClick=true;local shiftedLink=HolyStorm.RichLinks:MakeHyperlink("player","A","Marithiel (Main / Daniel)");editBox.text="vor "..shiftedLink.." nach";editBox.cursor=#editBox.text;opens.character=nil;assert(HolyStorm.RichLinks:HandleHyperlink("holystorm:player:A","LeftButton")and editBox.text=="vor Marithiel nach","shift click replaces a generated player hyperlink with the plain short name");assert(not opens.character,"shift click does not open the character overview");editBox.text="";editBox.cursor=0;HolyStorm.RichLinks:HandleHyperlink("holystorm:character:A","LeftButton");assert(editBox.text=="Marithiel","direct generated character links insert only the plain short name");modifiedClick=false
assert(Chat:ShowNativePlayerTooltip({},"player:Marithiel-Norgannon:42")and opens.tooltip=="A","native sender links show the central Holy Storm character tooltip")
profile.chat.playerTooltips=false;opens.tooltip=nil;assert(not HolyStorm.RichLinks:ShowTooltip({},"holystorm:player:A")and not opens.tooltip,"generated player-link tooltips honor the Chat setting");profile.chat.playerTooltips=true;assert(HolyStorm.RichLinks:ShowTooltip({},"holystorm:player:A")and opens.tooltip=="A","generated player-link tooltips delegate to Characters when enabled")
assert(Chat:HandleNativePlayerLink("player:Marithiel-Norgannon:42","LeftButton",{})and opens.character=="A","native sender links open the central character overview")
assert(Chat:HandleNativePlayerLink("player:Marithiel-Norgannon:42","RightButton",{})and opens.menu=="A","native sender links expose the central character context menu")
assert(not Chat:HandleNativePlayerLink("player:Unknown-Norgannon:42","LeftButton",{}),"unknown native sender links retain Blizzard's default behavior")
assert(not HolyStorm.RichLinks:HandleHyperlink("holystorm:open")and not HolyStorm.RichLinks:HandleHyperlink("holystorm:status")and not HolyStorm.RichLinks:HandleHyperlink("holystorm:help"),"legacy command links remain available to the command handler")
HolyStorm.Hooks={Secure=function(_,_,_,callback)HolyStorm.commandHook=callback end,Script=function()end};HolyStorm.UI={Open=function()opens.ui=true end};local optionsModule={Open=function()opens.options=true end};function HolyStorm:GetModule(name)return name=="Options"and optionsModule or nil end;SlashCmdList={};NUM_CHAT_WINDOWS=0
assert(loadfile(root.."Core/Commands/Commands.lua"))();HolyStorm.Commands:Initialize();local registeredCommand=HolyStorm.RichLinks:MakeHyperlink("command","open","/hs");assert(registeredCommand:find("holystorm:command:open",1,true),"command links are registered in the central rich-link registry");HolyStorm.RichLinks:HandleHyperlink("holystorm:command:open","LeftButton");assert(opens.ui,"registered /hs command link opens Holy Storm");HolyStorm.Commands:Execute("o");assert(opens.options,"/hs o opens options");opens.ui=false;HolyStorm.commandHook("holystorm:open",nil,"LeftButton");assert(opens.ui,"legacy command links are forwarded to Commands instead of reported as unsupported")
assert(filters.CHAT_MSG_GUILD and filters.CHAT_MSG_WHISPER and filters.CHAT_MSG_INSTANCE_CHAT_LEADER,"real supported chat filters are registered");local d=Chat:GetDiagnostics();assert(d.indexSize>0 and#d.linkTypes>=9 and#d.tokens>=2 and d.stats.processed>0,"developer diagnostics expose registry, cache, channel and parser state")
Chat:Shutdown();assert(removed.CHAT_MSG_GUILD,"filters are removed cleanly")

-- Core + Chat without Characters: remove every optional Characters contract and
-- prove that the independent pipeline still initializes and remains useful.
HolyStorm.CharacterDirectory:Shutdown();HolyStorm:UnregisterCapability("Characters","character.open");HolyStorm.RichLinks:GetTypes().player=nil;HolyStorm.RichLinks:GetTypes().character=nil
filters,removed={},{};sounds=0;clock=200;profile.chat.showMain=true;profile.chat.showRealName=true;profile.chat.channels.SAY=true
assert(Chat:Initialize(),"Chat initializes without Characters")
local standalonePlain=Chat:ProcessMessage("CHAT_MSG_GUILD","Marithiel kommt gleich","Other");assert(standalonePlain=="Marithiel kommt gleich","missing character directory leaves player names as readable text")
local standaloneURL=Chat:ProcessMessage("CHAT_MSG_GUILD","https://example.com/standalone","Other");assert(standaloneURL:find("holystorm:url:",1,true),"URL enrichment works without Characters")
local standaloneToken=Chat:ProcessMessage("CHAT_MSG_GUILD","{{TEST:ok}}","Other");assert(standaloneToken:find("holystorm:guide:guide%-one"),"generic registered tokens work without Characters")
Chat:ProcessMessage("CHAT_MSG_GUILD","Marithiel, standalone ping","Other");assert(sounds==1,"own character mention works without Characters")
assert(not Chat:ShowNativePlayerTooltip({},"player:Marithiel-Norgannon:42"),"native player tooltip is not claimed without Characters")
assert(not Chat:HandleNativePlayerLink("player:Marithiel-Norgannon:42","LeftButton",{}),"native player action is not claimed without Characters")
assert(filters.CHAT_MSG_GUILD,"standalone Chat registers normal chat filters")
Chat:Shutdown();assert(removed.CHAT_MSG_GUILD,"standalone shutdown removes chat filters")
print("Chat enrichment, mentions, rich links, URLs, boundaries, ambiguity and protection tests passed")
