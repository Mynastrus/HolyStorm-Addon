local root=(arg[0]:gsub("tools[/\\]test_character_tabs.lua$","")).."LIVE/Holy_Storm/"
local unpack=unpack or table.unpack
local function copy(value,seen)if type(value)~="table"then return value end;seen=seen or{};if seen[value]then return seen[value]end;local out={};seen[value]=out;for key,child in pairs(value)do out[copy(key,seen)]=copy(child,seen)end;return out end
local locale=setmetatable({LEVEL="Level",SEASON="Season %s",PROGRESS_FORMAT="%s / %s (level %s)",ACTIVITY="Activity %s",CHARACTER_COUNT="%d known characters",LAST_UPDATED="Last updated: %s",WEEKLY_TOOLTIP="Weekly %s",BOSS_KILLED="Killed %s",BOSS_OPEN="Open %s",BEST_ROW="%s | %s | %d kills"},{__index=function(_,key)return key end})
local aceGUI;local eventListeners={};local errorLogs={}
local records={A={guid="A",name="Alpha-Realm",realm="Realm",classFile="PALADIN",level=80,guildRank="Stored Officer",stats={spec={id=70,name="Retribution",icon=98765,index=3,role="DAMAGER"}}}}
local blocks={}
local HolyStorm={Utils={DeepCopy=copy,TableCount=function(t)local n=0;for _ in pairs(t or{})do n=n+1 end;return n end,SafeCall=function(_,fn,...)local result={pcall(fn,...)};local ok=table.remove(result,1);return ok,unpack(result)end},Data={CharacterStore={},GuildStore={},PlayerStore={}},PlayerData={},Policy={},Tasks={},Events={},Logger={}}
function LibStub(name)if name=="AceAddon-3.0"then return{GetAddon=function()return HolyStorm end}elseif name=="AceLocale-3.0"then return{GetLocale=function()return locale end}elseif name=="AceGUI-3.0"then return aceGUI end end
function HolyStorm:RegisterRequiredModule()local module={};self.characterOverview=module;return module end
function HolyStorm:RegisterCapability(_,capability,handler)self.capabilities=self.capabilities or{};self.capabilities[capability]=handler;return true end
function HolyStorm:CallCapability()return true end
function HolyStorm:ApplyModuleMetadata()end
function HolyStorm:IsOptionalModuleEnabled()return true end
function HolyStorm:GetModule()return{frame=self.testUIFrame,content=self.testUIContent,RegisterPage=function()end}end
HolyStorm.UI={RegisterPage=function()end,GetVisiblePage=function()return HolyStorm.shownPage end,ShowPage=function(_,id)HolyStorm.shownPage=id;if HolyStorm.characterOverview and HolyStorm.characterOverview.page and HolyStorm.characterOverview.page.OnShow then HolyStorm.characterOverview.page.OnShow()end end};HolyStorm.Database={Get=function()return false end}
function HolyStorm.Tasks:RegisterTaskType()end;function HolyStorm.Tasks:GetTaskType()return nil end;function HolyStorm.Events:Register(event,_,callback)eventListeners[event]=callback end;function HolyStorm.Events:Emit()end
function HolyStorm.Logger:Write(level,source,category,message,context)errorLogs[#errorLogs+1]={level=level,source=source,category=category,message=message,context=context}end
function HolyStorm.Policy:Can()return true end
function HolyStorm.Policy:IsGuildModuleEnabled()return true end
function HolyStorm.Data.CharacterStore:Get(guid)return records[guid]end
function HolyStorm.Data.CharacterStore:CaptureCurrent()return records.A end
function HolyStorm.Data.CharacterStore:GetBlock(_,block)local data=blocks[block];if block=="equipment"then return data and{equipment=data,itemLevel=data.itemLevel},{version=3,updatedAt=100}end;return data,{version=block=="raid"and 3 or 2,updatedAt=100}end
function HolyStorm.Data.GuildStore:GetCurrent()return{roster={A={name="Alpha",classFile="PALADIN",level=80}}}end
function HolyStorm.Data.PlayerStore:GetCharacterOwner()return"account-A"end
function HolyStorm.PlayerData:IsStale()return false end
HolyStorm.TwinkCore={sources={OWNER="OWNER"},GetAccountUUIDForCharacter=function()return"account-A"end,GetAccount=function()return{characters={A=true,B=true}}end,GetAccountMain=function()return"A"end,GetGuildMain=function()return"B",true end,GetVisibleCharactersForViewer=function()return{{characterUUID="A",fullName="Alpha-Realm",classFile="PALADIN",level=80,relationship={source="OWNER"}},{characterUUID="B",fullName="Beta-Realm",classFile="MAGE",level=70,relationship={source="ADMIN"}}}end}
LOCALIZED_CLASS_NAMES_MALE={PALADIN="Paladin"};RAID_CLASS_COLORS={PALADIN={r=1,g=.96,b=.41}};NORMAL_FONT_COLOR={r=1,g=1,b=1};CLASS_ICON_TCOORDS={PALADIN={0,0.25,0,0.25}}
for index,name in ipairs({"HEAD","NECK","SHOULDER","BACK","CHEST","WRIST","HAND","WAIST","LEGS","FEET","FINGER1","FINGER2","TRINKET1","TRINKET2","MAINHAND","OFFHAND"})do _G["INVSLOT_"..name]=index end

assert(loadfile(root.."UI/Character/CharacterUI.lua"))();assert(loadfile(root.."UI/Framework/Components/HolyStormHeaderBar.lua"))();assert(loadfile(root.."UI/Character/CharacterOverview.lua"))()
local C=HolyStorm.CharacterUI;local context=C:ResolveContext("A")

local function widget(kind,parent)
 local object={kind=kind,parent=parent,width=640,height=360,shown=true,textValue="",points={}}
 function object:SetAllPoints(parent)self.allPoints=parent or self.parent;self.width=self.parent and self.parent.width or self.width;self.height=self.parent and self.parent.height or self.height end;function object:SetParent(parent)self.parent=parent end;function object:SetPoint(...)self.pointArgs={...};self.points[#self.points+1]=self.pointArgs end;function object:ClearAllPoints()self.pointArgs=nil;self.points={}end
 function object:SetSize(width,height)self.width=width;self.height=height end;function object:SetWidth(width)self.width=width end;function object:GetWidth()return self.width end;function object:SetHeight(height)self.height=height end;function object:GetHeight()return self.height end
 function object:SetScrollChild(child)self.scrollChild=child end;function object:SetScript(event,handler)self[event]=handler end;function object:HookScript(event,handler)self[event]=handler end
 function object:CreateFontString()return widget("font",self)end;function object:CreateTexture()return widget("texture",self)end
 function object:SetText(text)self.textValue=text or""end;function object:GetStringHeight()return math.max(16,math.ceil(#self.textValue/math.max(1,math.floor(self.width/8)))*16)end
 function object:SetFontObject()end;function object:SetTextColor()end;function object:SetJustifyH()end;function object:SetJustifyV()end;function object:SetWordWrap()end;function object:SetNonSpaceWrap()end;function object:SetHyperlinksEnabled()end
 function object:SetColorTexture()end;function object:SetTexture(value)self.texture=value end;function object:SetTexCoord(...)self.texCoord={...}end;function object:SetAlpha()end;function object:SetNormalTexture()end;function object:SetHighlightTexture()end;function object:RegisterForClicks(...)self.clicks={...}end;function object:EnableMouse()end;function object:SetEnabled(value)self.enabled=value end;function object:SetShown(shown)self.shown=shown end;function object:IsShown()return self.shown end;function object:Show()self.shown=true end;function object:Hide()self.shown=false end
 return object
end
local function createTabGroup()
 local group={frame=widget("tabgroup-frame"),content=widget("tabgroup-content"),tabButtons={},tabs={},callbacks={}}
 function group:SetCallback(event,handler)self.callbacks[event]=handler end
 function group:GetContentFrame()return self.content end
 function group:LayoutTabs()self.content:SetSize(math.max(1,self.frame.width),math.max(1,self.frame.height-36));self.content:Show()end
 function group:SetTabs(tabs)
  self.tabs=tabs or{};local seen={}
  for _,tab in ipairs(self.tabs)do seen[tab.value]=true;local button=self.tabButtons[tab.value]or widget("tab-button");button.value=tab.value;button.text=tab.text;button.icon=button.icon or widget("texture",button);button.icon:SetTexture(tab.icon);button:SetSize(100,30);button:RegisterForClicks("LeftButtonUp");self.tabButtons[tab.value]=button end
  for value,button in pairs(self.tabButtons)do if not seen[value]then button:Hide()end end
  self:LayoutTabs()
 end
 function group:SelectTab(value,silent)self.selected=value;if not silent and self.callbacks.OnGroupSelected then self.callbacks.OnGroupSelected(self,"OnGroupSelected",value)end end
 return group
end
aceGUI={Create=function(_,kind)assert(kind=="HolyStormTabGroup","unexpected AceGUI widget "..tostring(kind));return createTabGroup()end}
HolyStorm.testUIFrame=widget("main-frame");HolyStorm.testUIContent=widget("ui-content",HolyStorm.testUIFrame);CreateFrame=function(_,_,parent)return widget("frame",parent)end;C_Timer={After=function(_,callback)callback()end}
date=function(format,timestamp)return format.."|"..tostring(timestamp)end
UnitGUID=function()return"A"end;local portraitCalls=0;SetPortraitTexture=function()portraitCalls=portraitCalls+1 end
local textView=C:CreateTextView(widget("parent"));local completeLine=string.rep("Complete character data ",40);local columns={{width=.4},{width=.35},{width=.25,align="RIGHT"}};C:SetView(textView,"Heading",{{cells={"Name","Class","Level"},columns=columns,style="header",maxWidth=500},{cells={"Alpha","Paladin","80"},columns=columns,maxWidth=500},"",completeLine},"CURRENT")
assert(not textView.body and#textView.rows==4,"one reusable row per content line")
assert(textView.rows[4].text.textValue==completeLine and textView.rows[4].height>24,"long content remains complete and wraps")
assert(#textView.rows[1].cells==3 and textView.rows[1].cells[2].pointArgs[4]==textView.rows[2].cells[2].pointArgs[4],"table columns share exact anchors")
assert(textView.content.width>600 and textView.content.height>textView.rows[4].height,"scroll content receives usable dimensions")

local nativeSetView=C.SetView;local rendered={};function C:SetView(_,heading,lines,status,meta)local flattened={};for _,line in ipairs(lines or{})do flattened[#flattened+1]=type(line)=="table"and table.concat(line.cells or{},"\t")or line end;rendered={heading=heading,lines=lines,status=status,meta=meta,text=table.concat(flattened,"\n")}end
local function render(tab)local definition=assert(C:GetTab(tab));definition.refresh({},context,definition);return rendered end

local slots={};for index=1,16 do slots[index]=false end
slots[1]={itemId=111,link="|cffa335ee|Hitem:111::::::::80:70::1:2:999:888::::::|h[Test Helm]|h|r",itemLevel=710,enchantId=42,gems={1001,1002},icon=123,isTier=true}
slots[2]={itemId=222,link="|cff0070dd|Hitem:222::::::::80:70:::::::|h[Test Neck]|h|r",itemLevel=700,enchantId=0,gems={{empty=true,name="Prismatic Socket"}},sockets=1,icon=124,isTier=false}
blocks.equipment={itemLevel=705.5,slots=slots};local equipment=render("equipment")
assert(equipment.text:find("Hitem:111::::::::80:70::1:2:999:888",1,true),"full item link retained")
assert(equipment.text:find("EMPTY_SLOT",1,true)and equipment.text:find("710",1,true),"empty slot and item level")
assert(equipment.lines[3].cells[3]=="✓"and equipment.lines[4].cells[3]=="","only tier items receive a check mark")
assert(equipment.lines[4].cells[4]==""and not equipment.lines[4].cells[4]:find("UNKNOWN",1,true),"missing enchants render as an empty cell")
assert(equipment.lines[4].cells[5]:find("Prismatic Socket",1,true)and equipment.lines[4].cells[5]:find("Hitem:222",1,true),"empty sockets are named and linked to their item tooltip")
local opened;SetItemRef=function(link,text,button)opened={link=link,text=text,button=button}end;C:HandleLink("item:111","LeftButton");assert(opened and opened.link=="item:111"and opened.button=="LeftButton","normal item clicks open the WoW item reference")

blocks.mythicPlus={seasonId=16,overallScore=2500,dungeons={{name="Dungeon A",instanceId=200,challengeMapId=300,texture=400,score=250,affixScores={{affixID=9,score=130,level=12}}}}};local mythic=render("mythicPlus")
assert(mythic.text:find("2500",1,true)and mythic.text:find("250",1,true)and mythic.text:find("12",1,true)and mythic.text:find("MYTHIC_IN_TIME",1,true),"legacy affix snapshots render with dungeon score and best-run data")
assert(mythic.text:find("hscharacter:journal:200",1,true)and mythic.text:find("hscharacter:teleport:300",1,true),"journal and disabled teleport affordance")
local mythicLayout=C:CreateTextView(widget("mythic-layout"));nativeSetView(C,mythicLayout,"Mythic+",mythic.lines);assert(#mythicLayout.rows[2].columns==4 and#mythicLayout.rows[2].cells==4,"Mythic+ table rows and column definitions have matching cardinality")
blocks.mythicPlus=nil;assert(render("mythicPlus").text:find("NO_MYTHICPLUS",1,true),"nil Mythic+ snapshot uses the localized empty state")
blocks.mythicPlus={};assert(render("mythicPlus").text:find("NO_MYTHICPLUS",1,true),"empty Mythic+ snapshot uses the localized empty state")
blocks.mythicPlus={seasonId=16,overallScore=2400,dungeons=nil,snapshotVersion=2};local noDungeons=render("mythicPlus");assert(noDungeons.text:find("2400",1,true),"snapshot without a dungeon table still renders available summary data")
blocks.mythicPlus={snapshotVersion=1,seasonId=nil,overallScore=2300,dungeons={[1]="broken",[3]={name="Legacy Dungeon",instanceId=201,challengeMapId=301,texture=401,score=nil,bestRun=nil,bestInTime="broken",affixScores=nil}}};local damagedMythic=render("mythicPlus");assert(damagedMythic.text:find("Legacy Dungeon",1,true)and damagedMythic.text:find("UNKNOWN",1,true)and damagedMythic.text:find("2300",1,true),"legacy snapshots skip broken dungeon entries and show missing run and score values safely")
blocks.mythicPlus={seasonId=16,overallScore=2500,dungeons={{name="Dungeon A",instanceId=200,challengeMapId=300,texture=400,score=250,affixScores={{affixID=9,score=130,level=12}}}},snapshotVersion=3}

blocks.raid={raids={{id=100,name="Raid One",icon=500,order=1,bosses={{id=501},{id=502}}}},lockouts={{name="Raid One",difficultyId=17,killed=1,total=2,bosses={{name="Boss A",killed=true},{name="Boss B",killed=false}}},{name="Raid One",difficultyId=16,killed=1,total=2,bosses={{name="Boss A",killed=true},{name="Boss B",killed=false}}}},lifetime={bosses={[501]={id=501,name="Boss A",raidName="Raid One",difficulties={LFR={kills=5},NORMAL={kills=2},HEROIC={kills=7},MYTHIC={kills=1}}},[502]={id=502,name="Boss B",raidName="Raid One",difficulties={LFR={kills=5},NORMAL={kills=2}}}}}}
local storedRaid,storedRaidMeta=C:GetSnapshot("A","raid");assert(storedRaid==blocks.raid and storedRaidMeta.version==3,"single-field raid blocks are returned directly by PlayerData")
local raid=render("raid");assert(raid.text:find("|cffffd100",1,true),"LFR yellow");assert(raid.text:find("|cffb34dff",1,true),"Mythic purple");assert(C:BuildRaidBestRows(blocks.raid)[1].difficulty=="MYTHIC","one highest difficulty per boss")

blocks.delves={seasonNumber=3,weeklyProgress=2,bountiful={status="unknown"},keyFragments={count=4},companion={level=12},activities={{index=1,progress=2,threshold=4,level=8}}};local delves=render("delves")
assert(delves.text:find("UNKNOWN",1,true)and delves.text:find("4",1,true)and delves.text:find("12",1,true),"delve unknown and structured values")

blocks.stats={primary={strength={base=100,effective=120},agility={base=20,effective=20},stamina={base=200,effective=220},intellect={base=10,effective=10}},armor={base=500,effective=600},secondary={criticalStrike={rating=1000,percent=20},haste={rating=800,percent=15},mastery={rating=700,percent=12},versatility={rating=600,percent=10}}};local stats=render("stats")
assert(stats.text:find("100",1,true)and stats.text:find("120",1,true)and stats.text:find("LIVE_BUFFS_UNAVAILABLE",1,true),"persistent stats and explicit live limitation")

local twinks=render("twinks");assert(twinks.text:find("Alpha%-Realm")and twinks.text:find("Beta%-Realm")and twinks.text:find("SHADOW_MAIN",1,true)and twinks.text:find("ADMINISTRATIVE",1,true),"TwinkCore visibility, shadow main and relationship")
local Page=HolyStorm.characterOverview;Page:OnInitialize();assert(Page.header and Page.classIcon and Page.specIcon and Page.headerStatus and Page.headerUpdated and Page.tabHost,"character page builds the shared compact header and tab content shell");assert(Page.back==nil,"visible character back button is removed");assert(Page.refreshButton.width==22 and Page.refreshButton.height==22,"header refresh button stays compact")
assert(Page.header.parent==HolyStorm.testUIFrame and Page.tabGroup.frame.parent==Page.page and Page.tabHost==Page.tabGroup.content,"header is in the main window chrome while tabs and content stay on the character page");assert(Page.header.points[1][1]=="BOTTOMLEFT"and Page.header.points[1][2]==HolyStorm.testUIContent and Page.header.points[1][3]=="TOPLEFT"and Page.header.points[1][4]==52 and Page.header.points[1][5]==4 and Page.tabGroup.frame.points[1][3]==-8,"header is aligned near the title text start and the window content starts at the top")
C:SetContext("A",false);C:RefreshHeader();assert(C.context.name=="Alpha"and C.context.realm=="Realm","context keeps name and realm separated");assert(Page.headerName.textValue=="Alpha","header uses the character name without the realm");assert(Page.headerInfo.textValue:find("Realm",1,true)and Page.headerInfo.textValue:find("Paladin",1,true)and Page.headerInfo.textValue:find("Retribution",1,true)and Page.headerInfo.textValue:find("Level 80",1,true)and Page.headerInfo.textValue:find("Stored Officer",1,true),"header info contains realm, class, optional spec, level and guildRank fallback");assert(Page.classIcon.texture=="Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"and Page.classIcon.texCoord[1]==0,"own character uses the class icon texture");assert(portraitCalls==0,"own character no longer calls SetPortraitTexture");assert(Page.classIcon.width==28 and Page.classIcon.height==28 and Page.specIcon.width==28 and Page.specIcon.height==28,"class and spec icons have identical compact visible size");assert(Page.specIcon.texture==98765 and Page.specIcon.shown~=false,"known spec icon is shown")
assert(not Page.headerStatus.textValue:find("\n",1,true)and not Page.headerUpdated.textValue:find("\n",1,true),"header status uses separate single-line fields")
records.A.stats.spec=nil;C:RefreshHeader();assert(Page.specIcon.shown==false and not Page.headerInfo.textValue:find("Retribution",1,true),"missing spec hides the spec icon and omits the spec name");assert(Page.headerName.points[1][2]==Page.classIcon,"missing spec anchors the name to the class icon without a reserved icon slot")
records.A.stats.spec={id=70,name="Retribution",icon=98765,index=3,role="DAMAGER"};C:RefreshHeader();assert(Page.headerName.points[1][2]==Page.specIcon,"known spec anchors the name after the visible spec icon");assert(#C:GetTabs()==7 and Page.tabButtons.mythicPlus.height==30 and Page.tabButtons.mythicPlus.icon.texture,"seven compact icon+text tabs are built through the HolyStorm TabGroup");assert(Page.tabButtons.mythicPlus.clicks[1]=="LeftButtonUp","HolyStorm TabGroup tabs explicitly register their click")
assert(C:RegisterTab({id="achievements",order=6.5,labelKey="TAB_ACHIEVEMENTS",label="Achievements",icon="achievement-icon",build=function(parent)return C:CreateTextView(parent)end,refresh=function(view)C:SetView(view,"Achievements",{"ok"})end}));Page:BuildTabs();assert(Page.tabButtons.achievements and Page.tabButtons.achievements.icon.texture=="achievement-icon","dynamic achievement tab is retained")
C:SelectTab("summary");local summaryView=Page.views.summary;assert(summaryView and summaryView.frame.shown and summaryView.frame.parent==Page.tabHost and Page.tabHost.width>0 and Page.tabHost.height>0,"active tab view has a visible sized content parent");Page.header:Hide();C:OpenCharacter("A","summary",false);assert(Page.header.shown~=false,"character changes show the external header again");HolyStorm.shownPage="guild";if Page.page.OnHide then Page.page.OnHide()end;C:RefreshHeader();assert(Page.header.shown==false,"external character header stays hidden on non-character pages");HolyStorm.shownPage="character";if Page.page.OnShow then Page.page.OnShow()end;C:SelectTab("mythicPlus");assert(Page.headerUpdated.textValue:find("%%d%.%%m%.%%Y %%H:%%M|100"),"known tab metadata is rendered in dd.mm.yyyy format in the second status line");assert(C.activeTab=="mythicPlus"and Page.tabGroup.selected=="mythicPlus","tab selection stays synchronized with CharacterUI.activeTab");assert(summaryView.frame.shown==false and Page.views.mythicPlus.frame.shown==true,"SelectTab hides the previous view and shows the active view");assert(Page.views.mythicPlus.frame.parent==Page.tabHost and Page.views.mythicPlus.frame.points[1][2]==Page.tabHost and Page.views.mythicPlus.frame.points[2][2]==Page.tabHost,"active view is anchored to the tab content host");assert(Page.views.mythicPlus.frame.width>0 and Page.views.mythicPlus.frame.height>0,"active view receives usable width and height");assert(rendered.text and rendered.text:find("2500",1,true),"tab content is actually rendered during selection");Page.tabGroup.frame:SetSize(900,500);Page:LayoutTabs();assert(Page.tabHost.width==900 and Page.tabHost.height>400 and Page.views.mythicPlus.frame.points[1][2]==Page.tabHost,"resize updates the tab host and keeps the active view anchored")
local mythicDefinition=C:GetTab("mythicPlus");local originalMythicRefresh=mythicDefinition.refresh;mythicDefinition.refresh=function()error("forced Mythic+ renderer failure")end;assert(not C:RefreshTab("mythicPlus"),"renderer failure is isolated by the tab fallback");local diagnostic=errorLogs[#errorLogs];assert(diagnostic and diagnostic.level=="ERROR"and diagnostic.context.tabId=="mythicPlus"and diagnostic.context.characterGUID=="A"and diagnostic.context.dataBlock=="mythicPlus"and diagnostic.context.snapshotVersion==3 and diagnostic.context.error:find("forced Mythic+ renderer failure",1,true),"tab fallback logs actionable renderer diagnostics");assert(rendered.text:find("TAB_ERROR",1,true),"renderer failure keeps the friendly UI fallback");mythicDefinition.refresh=originalMythicRefresh;assert(C:RefreshTab("mythicPlus")and rendered.text:find("2500",1,true),"the last valid Mythic+ snapshot remains renderable after a failed refresh")
blocks.mythicPlus={seasonId=16,overallScore=2700,dungeons={{name="Recovered Dungeon",score=270,bestRun={level=14,score=270}}},snapshotVersion=3};assert(type(eventListeners.HS_MYTHICPLUS_UPDATED)=="function","character page listens for stored Mythic+ updates");eventListeners.HS_MYTHICPLUS_UPDATED("HS_MYTHICPLUS_UPDATED","A");assert(rendered.text:find("2700",1,true)and rendered.text:find("Recovered Dungeon",1,true),"a later valid Mythic+ update refreshes the active tab through the existing event")
local view=C:CreateTextView(widget("parent"));nativeSetView(C,view,"Heading",{"Identity"});assert(view.heading.textValue==""and view.heading.shown==false,"content views no longer render a redundant tab heading")
print("Character tab snapshot rendering tests passed")
