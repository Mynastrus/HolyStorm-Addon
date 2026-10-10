-- Offline behavior and context-header layout regressions for the guild roster search.
local root=(arg[0]:gsub("tools[/\\]test_guild_roster_search.lua$",""))
local function copy(value,seen)
    if type(value)~="table"then return value end
    seen=seen or{};if seen[value]then return seen[value]end
    local out={};seen[value]=out;for key,child in pairs(value)do out[copy(key,seen)]=copy(child,seen)end;return out
end
local listeners={}
local locale=setmetatable({},{__index=function(_,key)return key end})
locale.ROSTER_RESULT_COUNT="%d of %d members";locale.ROSTER_NO_MATCHES="No guild members match these filters.";locale.NO_MEMBERS="No guild members could be found."
locale.ROSTER_FILTER_COUNT="Filter (%d)";locale.ROSTER_FILTER_COUNT_SHORT="F (%d)";locale.ROSTER_SAVED_MENU="Saved";locale.ROSTER_SAVED_MENU_COUNT="Saved (%d)";locale.ROSTER_SAVED_MENU_SHORT="Saved";locale.ROSTER_SAVED_MENU_SHORT_COUNT="Saved (%d)";locale.ROSTER_FILTER_BUTTON="Filter";locale.ROSTER_FILTER_BUTTON_SHORT="Filter";locale.ROSTER_SEARCH_PLACEHOLDER="Search guild members...";locale.ROSTER_SEARCH_PLACEHOLDER_SHORT="Search..."
local filters={localFilters={},globalFilters={},active={}}
local characterReads=0
local HolyStorm={
    Utils={DeepCopy=copy,Trim=function(value)return tostring(value or""):match("^%s*(.-)%s*$")end,SafeCall=function(_,fn,...)return pcall(fn,...)end,Now=function()return 1 end},
    db={global={rules={global={}},filters={global={},demands={}},},profile={rules={localRules={}},filters={localFilters={},activeByContext={}}}},
    Events={Emit=function(_,event,...)for _,fn in pairs(listeners[event]or{})do fn(event,...)end end,Register=function(_,event,owner,fn)listeners[event]=listeners[event]or{};listeners[event][owner]=fn end,UnregisterOwner=function()end},
    Data={CharacterStore={Get=function(_,guid)characterReads=characterReads+1;return{guid=guid}end}},
}
function HolyStorm:IsModuleAvailable()return true end
function HolyStorm:RegisterModule(definition,initializer)self.guildDefinition=definition;initializer(self.GuildRoster)end
HolyStorm.GuildRoster={}
HolyStorm.PermissionEngine={HasPermission=function()return true end}
HolyStorm.Policy=HolyStorm.PermissionEngine
HolyStorm.PolicyUI={NewId=function()return"guild-roster-test-filter"end,ErrorText=function(_,reason)return tostring(reason)end}
HolyStorm.FilterManager={
    RegisterTemplate=function()return true end,
    GetFilters=function(_,scope)return copy(scope=="local"and filters.localFilters or filters.globalFilters)end,
    GetFilter=function(_,id,scope)return copy((scope=="local"and filters.localFilters or filters.globalFilters)[id])end,
    GetActiveFilters=function(_,context)return copy(filters.active[context]or{})end,
    SetActiveFilters=function(_,context,entries)filters.active[context]=copy(entries or{});return true end,
    BuildContext=function(_,accountUUID,characterUUID,_,projection)return{accountUUID=accountUUID or"local-account",playerId=accountUUID or"local-account",characterUUID=characterUUID,guid=characterUUID,character=projection and projection.character or{},guild=projection and projection.guild}end,
    ApplyFilter=function(_,filter,context)return HolyStorm.Rules:Evaluate(filter.root or filter.rules,context)end,
    SaveFilter=function(_,filter,scope)assert(scope=="local","saved roster filters stay local");filters.localFilters[filter.id]=copy(filter);return true,copy(filter)end,
}
function LibStub(name)
    if name=="AceAddon-3.0"then return{GetAddon=function()return HolyStorm end}end
    if name=="AceLocale-3.0"then return{GetLocale=function()return locale end}end
    error("Unexpected library "..tostring(name))
end

assert(loadfile(root.."LIVE/Holy_Storm/Core/Permissions/RuleEngine.lua"))()
local Rules=HolyStorm.Rules
local GuildRoster=HolyStorm.GuildRoster
assert(loadfile(root.."LIVE/Holy_Storm_Guild/Guild.lua"))()
for _,definition in ipairs(HolyStorm.guildDefinition.ruleFields)do assert(Rules:RegisterField("GuildRoster",definition.id,definition))end

local function member(overrides)
    local value={guid="Player-1",name="Ritschy-Silvermoon",realm="Silvermoon",rank="Raider",rankIndex=1,level=80,className="Mage",classFileName="MAGE",zone="Stormwind",online=true,status="ONLINE",addonVersion="1.2.3",addonStatus="RECOGNIZED",note="secret-note",characterRecord={mythicPlus={overallScore=2500}}}
    value.characterRecord.score=2500
    for key,entry in pairs(overrides or{})do value[key]=entry end
    return value
end
local recognized=member()
local unknown=member({guid="Player-2",name="Sera-Dalaran",realm="Dalaran",rank="Member",rankIndex=3,className="Priest",classFileName="PRIEST",zone=nil,online=false,status=3600,addonVersion=nil,addonStatus="UNKNOWN",characterRecord={}})
local afk=member({guid="Player-3",name="Ayla-Area52",realm="Area52",status="AFK"})
local dnd=member({guid="Player-4",name="Nox-Area52",realm="Area52",status="DND"})
local offlineStatus=member({guid="Player-5",name="Offline-Area52",realm="Area52",online=false,status=1,addonStatus="UNKNOWN",addonVersion=nil})
assert(Rules:RegisterField("search-test","character.score",{type="number",resolver=function(context)return context.character and context.character.score end}))
GuildRoster.sourceMembers={recognized,unknown};local snapshotGuild={roster={}}
GuildRoster:BuildFilterContexts(snapshotGuild)
local cachedContext=GuildRoster:GetFilterContext(recognized)
local scorePass=Rules:Evaluate({field="character.score",operator=">",value=2000},cachedContext)
local scoreUnknown,_,scoreUnknownStatus=Rules:Evaluate({field="character.score",operator=">",value=2000},GuildRoster:GetFilterContext(unknown))
assert(scorePass and not scoreUnknown and scoreUnknownStatus==Rules.Result.UNKNOWN,"saved character rules use the cached record while missing data remains UNKNOWN")
assert(cachedContext==GuildRoster:GetFilterContext(recognized)and cachedContext.guild==snapshotGuild and cachedContext.accountUUID=="local-account","filter contexts are prepared once per roster snapshot and reused")

local function quick(state,item)
    GuildRoster.filterState=state;GuildRoster.quickFilter=GuildRoster:BuildQuickFilter(state)
    GuildRoster.activeFilterDefinitions={}
    return GuildRoster:MatchesMember(item)
end
assert(quick({search="RITSCHY",status="ALL",rank="ALL",class="ALL",addonStatus="ALL"},recognized),"search matches visible names without case sensitivity")
assert(quick({search="silvermoon",status="ALL",rank="ALL",class="ALL",addonStatus="ALL"},recognized),"search includes realm")
assert(not quick({search="secret-note",status="ALL",rank="ALL",class="ALL",addonStatus="ALL"},recognized),"search excludes public and officer notes")
assert(quick({search="",status="ONLINE",rank="1",class="MAGE",addonStatus="RECOGNIZED"},recognized),"status, rank, class and addon recognition combine with AND")
assert(not quick({search="",status="ONLINE",rank="1",class="MAGE",addonStatus="RECOGNIZED"},unknown),"combined quick filters reject a partial match")
assert(quick({search="",status="OFFLINE",rank="ALL",class="ALL",addonStatus="UNKNOWN"},unknown),"offline and unknown are explicit filter values")
assert(quick({search="",status="AFK",rank="ALL",class="ALL",addonStatus="ALL"},afk),"online AFK state matches")
assert(quick({search="",status="DND",rank="ALL",class="ALL",addonStatus="ALL"},dnd),"online DND state matches")
assert(not quick({search="",status="AFK",rank="ALL",class="ALL",addonStatus="ALL"},offlineStatus),"offline status codes do not imply AFK")
local unknownPresence=member();unknownPresence.online,unknownPresence.status=nil,nil
assert(not quick({search="",status="AFK",rank="ALL",class="ALL",addonStatus="ALL"},unknownPresence),"missing online or status data remains UNKNOWN for AFK")
local multiStatus={search="",status={ONLINE=true,OFFLINE=true},rank={['1']=true,['3']=true},class={MAGE=true,PRIEST=true},addonStatus={RECOGNIZED=true,UNKNOWN=true}}
assert(quick(multiStatus,recognized)and quick(multiStatus,unknown),"multiple values use OR within every selected category")
multiStatus.class={MAGE=true}
assert(quick(multiStatus,recognized)and not quick(multiStatus,unknown),"separate categories combine with AND")
multiStatus.search="silvermoon"
assert(quick(multiStatus,recognized)and not quick(multiStatus,unknown),"search is ANDed with multi-select quick filters")
local multiRoot=GuildRoster:BuildQuickFilter(multiStatus)
assert(multiRoot.logic=="AND"and multiRoot.children[2].logic=="OR"and multiRoot.children[3].logic=="OR","quick-filter groups preserve category OR and cross-category AND logic")
assert(not quick({search="",status="",rank="ALL",class="ALL",addonStatus="NOT_RECOGNIZED"},unknown),"missing version stays UNKNOWN and never implies not recognized")
assert(quick({search="",status="",rank="ALL",class="ALL",addonStatus="ALL"},member({name="ÜBER-Silvermoon"})),"empty status is not treated as a quick filter")
assert(Rules:RegisterField("search-test","search.text",{type="string",resolver=function(context)return context.text end}))
local unicodePass,_,unicodeStatus=Rules:Evaluate({field="search.text",operator="contains",value="\195\156BER"},{text="\195\156ber den gro\195\159en Sturm"})
assert(unicodePass and unicodeStatus==Rules.Result.PASS,"contains folds German uppercase umlauts")
local sharpSPass=Rules:Evaluate({field="search.text",operator="contains",value="STRA\225\186\158E"},{text="Stra\195\159e"})
assert(sharpSPass,"contains folds the uppercase German sharp S")

GuildRoster.sourceMembers={recognized,unknown,afk,dnd,offlineStatus}
GuildRoster.rankOptions,GuildRoster.classOptions=nil,nil
local ranks=GuildRoster:GetRankOptions();local classes=GuildRoster:GetClassOptions()
assert(#ranks==2 and ranks[1].value=="1"and ranks[2].value=="3","rank options are drawn from the current roster snapshot")
assert(#classes==2 and classes[1].value=="MAGE"and classes[2].value=="PRIEST","class options use class tokens and are sorted")
assert(not quick({search="",status="ALL",rank="2",class="ALL",addonStatus="ALL"},unknown),"missing rank values do not satisfy a negative or absent-data match")

filters.globalFilters.mages={id="mages",name="Mages",root={field="guild.classFile",operator="=",value="MAGE"}}
filters.localFilters.raiders={id="raiders",name="Raiders",root={field="guild.rankIndex",operator="=",value=1}}
filters.active.guildRoster={{id="mages",scope="global"},{id="raiders",scope="local"}}
GuildRoster:ReloadActiveFilters()
GuildRoster.filterState={search="silvermoon",status="ONLINE",rank="ALL",class="ALL",addonStatus="ALL"}
GuildRoster.quickFilter=GuildRoster:BuildQuickFilter(GuildRoster.filterState)
assert(GuildRoster:MatchesMember(recognized)and not GuildRoster:MatchesMember(unknown),"active saved profiles combine with search and quick filters using AND")
local combined=assert(GuildRoster:BuildCombinedFilterRoot())
assert(combined.logic=="AND"and#combined.children==3,"saved filter composition retains the quick filter and both saved rule trees")
local savedOk=GuildRoster:SaveCurrentFilterProfile("Raid Night")
assert(savedOk and filters.localFilters["guild-roster-test-filter"].name=="Raid Night"and not filters.globalFilters["guild-roster-test-filter"],"saving uses FilterManager local persistence")
filters.globalFilters.mages.root={field="guild.classFile",operator="=",value="PRIEST"};GuildRoster:ReloadActiveFilters()
GuildRoster.filterState={search="",status="ALL",rank="ALL",class="ALL",addonStatus="ALL"};GuildRoster.quickFilter=nil
assert(not GuildRoster:MatchesMember(recognized),"reloading uses the latest saved profile definition")
filters.globalFilters.mages.root={field="guild.classFile",operator="=",value="MAGE"};filters.localFilters.raiders=nil;GuildRoster:ReloadActiveFilters()
assert(#GuildRoster.activeFilters==1 and filters.active.guildRoster[1].id=="mages","a deleted saved profile is removed from active selections")
GuildRoster.activeFilters={};GuildRoster.activeFilterDefinitions={};filters.active.guildRoster={}

local omitted=member({guid="Player-6",name="OnlyName",online=true,characterRecord={}})
omitted.realm,omitted.rank,omitted.rankIndex,omitted.className,omitted.classFileName,omitted.zone,omitted.addonVersion,omitted.addonStatus,omitted.status=nil,nil,nil,nil,nil,nil,nil,nil,nil
GuildRoster.filterState={search="onlyname",status="ALL",rank="ALL",class="ALL",addonStatus="ALL"};GuildRoster.quickFilter=GuildRoster:BuildQuickFilter(GuildRoster.filterState);GuildRoster.activeFilterDefinitions={}
assert(GuildRoster:MatchesMember(omitted),"name search handles profiles with missing optional roster fields")
GuildRoster.filterState={search="",status="ALL",rank="ALL",class="ALL",addonStatus="UNKNOWN"};GuildRoster.quickFilter=GuildRoster:BuildQuickFilter(GuildRoster.filterState)
assert(GuildRoster:MatchesMember(omitted),"missing version is normalized to UNKNOWN")

local rendered,emptyShown,emptyText,resultText
GuildRoster.settings={groupTwinks=false};GuildRoster.RenderRows=function(_,rows)rendered=rows end
GuildRoster.resultLabel={SetText=function(_,value)resultText=value end}
GuildRoster.emptyState={frame={SetShown=function(_,value)emptyShown=value end},SetText=function(_,value)emptyText=value end}
GuildRoster.sourceMembers={}
for index=1,500 do GuildRoster.sourceMembers[index]=member({guid="synthetic-"..index,name="Member "..index,characterRecord={guid="synthetic-"..index}})end
GuildRoster.filterState={search="member 4",status="ALL",rank="ALL",class="ALL",addonStatus="ALL"};GuildRoster.quickFilter=GuildRoster:BuildQuickFilter(GuildRoster.filterState)
characterReads=0;local filtered=GuildRoster:ApplyRosterFilters()
assert(#filtered==111 and #rendered==111 and characterReads==0,"hundreds of local rows filter without CharacterStore reads on each search")
local timers={};C_Timer={NewTimer=function(delay,callback)local timer={delay=delay,callback=callback,cancelled=false};function timer:Cancel()self.cancelled=true end;timers[#timers+1]=timer;return timer end}
GuildRoster.statusMenu,GuildRoster.rankMenu,GuildRoster.classMenu,GuildRoster.addonStatusMenu,GuildRoster.clearSearchButton=nil,nil,nil,nil,nil
GuildRoster.page={IsShown=function()return true end};GuildRoster.filterState.search="member 1"
local applyCount=0;local originalApply=GuildRoster.ApplyRosterFilters
GuildRoster.ApplyRosterFilters=function(self)applyCount=applyCount+1;return originalApply(self)end
GuildRoster:OnQuickFiltersChanged(true);GuildRoster.filterState.search="member 2";GuildRoster:OnQuickFiltersChanged(true)
assert(timers[1].delay==.16 and timers[1].cancelled and not timers[2].cancelled,"typing debounces through one cancellable timer")
local requests=0;GuildRoster.RequestAndRefresh=function()requests=requests+1 end
characterReads=0;timers[2].callback()
assert(applyCount==1 and requests==0 and characterReads==0,"debounced typing filters locally without roster requests or store reads")
GuildRoster.ApplyRosterFilters=originalApply;C_Timer=nil
GuildRoster.filterState={search="no-such-member",status="ALL",rank="ALL",class="ALL",addonStatus="ALL"};GuildRoster.quickFilter=GuildRoster:BuildQuickFilter(GuildRoster.filterState)
local noMatches=GuildRoster:ApplyRosterFilters()
assert(#noMatches==0 and#rendered==0 and emptyShown and emptyText==locale.ROSTER_NO_MATCHES and resultText=="0 of 500 members","an empty result set shows the localized no-match state and count")

local savedSearchBox;savedSearchBox={SetText=function(_,value)savedSearchBox.text=value end}
local refreshQuickLabels,refreshSavedLabel=GuildRoster.RefreshQuickFilterLabels,GuildRoster.RefreshSavedFilterMenuText
GuildRoster.searchBox=savedSearchBox;GuildRoster.RefreshQuickFilterLabels=function()end;GuildRoster.RefreshSavedFilterMenuText=function()end
GuildRoster.filterState={search="member",status="ONLINE",rank="1",class="MAGE",addonStatus="UNKNOWN"};GuildRoster.activeFilters={{id="mages",scope="global"}};GuildRoster.activeFilterDefinitions={}
GuildRoster:ResetFilters()
assert(GuildRoster.filterState.search==""and next(GuildRoster.filterState.status)==nil and next(GuildRoster.filterState.rank)==nil and#GuildRoster.activeFilters==0 and#filters.active.guildRoster==0,"reset clears search, quick filters and saved selections")
GuildRoster.RefreshQuickFilterLabels=refreshQuickLabels;GuildRoster.RefreshSavedFilterMenuText=refreshSavedLabel

local function layoutWidget(name)
    return{name=name,points={},ClearAllPoints=function(self)self.points={}end,SetPoint=function(self,_,_,_,x,y)self.points={x=x,y=y}end,SetSize=function(self,w,h)self.width,self.height=w,h end,SetWidth=function(self,w)self.width=w end,SetHeight=function(self,h)self.height=h end}
end
-- Physical window widths can differ at the same UI scale; these values also
-- model the effective UI-unit widths seen under Retail's supported scales.
for _,width in ipairs({1100,900,820,740,700,650,600,520,400,360,320,300,280})do
    local names={"searchBox","filterMenu","savedFilterMenu","refreshButton"}
    for _,name in ipairs(names)do GuildRoster[name]=layoutWidget(name)end
    local height=GuildRoster:GetContextHeaderHeight(width);GuildRoster:LayoutContextHeader({},width,height)
    assert(height==30,"context header keeps one compact row at every width")
    local rows={};local visible=0
    for _,name in ipairs(names)do
        local widget=GuildRoster[name];assert(widget.points and widget.points.y<0,"every context header control is positioned for the active width: "..name)
        visible=visible+1
        local x=widget.points.x;local y=widget.points.y
        assert(x>=0 and x+widget.width<=width+0.01,"context header control stays inside the available width: "..name)
        assert(-y+widget.height<=height+0.01,"context header control stays inside its responsive height: "..name)
        rows[y]=rows[y]or{};rows[y][#rows[y]+1]={name=name,left=x,right=x+widget.width}
    end
    assert(visible==4 and GuildRoster.searchBox.points.y==GuildRoster.filterMenu.points.y and GuildRoster.searchBox.points.y==GuildRoster.savedFilterMenu.points.y and GuildRoster.searchBox.points.y==GuildRoster.refreshButton.points.y,"exactly four visible controls share one row")
    for _,row in pairs(rows)do table.sort(row,function(a,b)return a.left<b.left end);for index=2,#row do assert(row[index-1].right<=row[index].left+0.01,"context header controls do not overlap: "..row[index-1].name.." / "..row[index].name)end end
end
for _,scale in ipairs({.70,.85,1,1.15})do
    local width=math.floor(650/scale)
    GuildRoster:LayoutContextHeader({},width,GuildRoster:GetContextHeaderHeight(width))
    for _,name in ipairs({"searchBox","filterMenu","savedFilterMenu","refreshButton"})do
        local widget=GuildRoster[name]
        assert(widget.points.x>=0 and widget.points.x+widget.width<=width and widget.points.y==-3,"same physical minimum window remains one row at UI scale "..scale)
    end
end

-- Build the actual header controls with native dropdown callbacks, then inspect
-- the root/submenu entries and exercise checkbox toggles without a game client.
local function fakeWidget(name)
    local widget={name=name,scripts={},shown=true,text="",points={}}
    function widget:SetScript(event,callback)self.scripts[event]=callback end
    function widget:SetText(value)self.text=value or"";if self.scripts.OnTextChanged then self.scripts.OnTextChanged(self,false)end end
    function widget:GetText()return self.text end
    function widget:SetMaxLetters(value)self.maxLetters=value end
    function widget:SetShown(value)self.shown=value==true end
    function widget:Show()self.shown=true end
    function widget:Hide()self.shown=false end
    function widget:HasFocus()return self.focused==true end
    function widget:SetFocus()self.focused=true;if self.scripts.OnEditFocusGained then self.scripts.OnEditFocusGained(self)end end
    function widget:ClearFocus()self.focused=false;if self.scripts.OnEditFocusLost then self.scripts.OnEditFocusLost(self)end end
    function widget:CreateFontString()return fakeWidget(name.."-font")end
    function widget:SetPoint(...)self.pointArgs={...};local args={...};self.points={x=args[4],y=args[5]}end
    function widget:ClearAllPoints()self.points={}end
    function widget:SetSize(w,h)self.width,self.height=w,h end
    function widget:SetWidth(w)self.width=w end
    function widget:SetHeight(h)self.height=h end
    function widget:SetNormalTexture(value)self.normalTexture=value end
    function widget:SetPushedTexture(value)self.pushedTexture=value end
    function widget:SetHighlightTexture(value,blend)self.highlightTexture,self.highlightBlend=value,blend end
    function widget:SetTextColor(r,g,b)self.color={r,g,b}end
    function widget:SetJustifyH(value)self.justifyH=value end
    function widget:SetWordWrap(value)self.wordWrap=value end
    function widget:SetDefaultText(value)self.defaultText=value end
    function widget:OverrideText(value)self.displayText=value end
    function widget:SetupMenu(generator)self.menuGenerator=generator end
    function widget:GenerateMenu()
        local root=menuNode("root",nil);self.menuGenerator(self,root);self.generatedMenu=root;return root
    end
    return widget
end
function menuNode(kind,text,data)
    local node={kind=kind,text=text,data=data,children={}}
    function node:CreateButton(label,callback,value)
        local child=menuNode("button",label,value);child.callback=callback;self.children[#self.children+1]=child;return child
    end
    function node:CreateCheckbox(label,isSelected,setSelected,value)
        local child=menuNode("checkbox",label,value);child.isSelected=isSelected;child.setSelected=setSelected;self.children[#self.children+1]=child;return child
    end
    function node:CreateTitle(label)local child=menuNode("title",label);self.children[#self.children+1]=child;return child end
    function node:CreateDivider()local child=menuNode("divider");self.children[#self.children+1]=child;return child end
    function node:SetSelectionIgnored()self.selectionIgnored=true end
    function node:SetEnabled(value)self.enabled=value end
    return node
end
local activeDropdown
CreateFrame=function(frameType,name,parent,template)return fakeWidget(template or name or frameType or"frame")end
HolyStorm.PolicyUI.Edit=function(_,parent,width)return fakeWidget("search-edit")end
HolyStorm.Administration={Open=function(_,section)assert(section=="filters")end}
GameTooltip={SetOwner=function()end,SetText=function()end,Show=function()end,Hide=function()end}
StaticPopupDialogs={};ACCEPT="Accept";CANCEL="Cancel"
MenuResponse={Refresh="refresh",CloseAll="close-all"}
GuildRoster.resultLabel=nil
local contextHeader=fakeWidget("context-header")
GuildRoster:CreateContextHeader(contextHeader)
assert(GuildRoster.searchBox and GuildRoster.filterMenu and GuildRoster.savedFilterMenu and GuildRoster.refreshButton,"header builds the four required controls")
for _,name in ipairs({"clearSearchButton","saveFilterButton","manageFiltersButton","resetFiltersButton","statusMenu","rankMenu","classMenu","addonStatusMenu","resultLabel"})do
    assert(GuildRoster[name]==nil,"legacy permanent header control is not created: "..name)
end
assert(GuildRoster.searchPlaceholder.text==locale.ROSTER_SEARCH_PLACEHOLDER and GuildRoster.searchPlaceholder.shown,"localized placeholder is visibly shown while search is empty")
GuildRoster:LayoutContextHeader(contextHeader,320,30)
assert(GuildRoster.searchPlaceholder.text==locale.ROSTER_SEARCH_PLACEHOLDER_SHORT and GuildRoster.searchPlaceholder.width==GuildRoster.searchBox.width-16,"compact placeholder is localized and clipped to the narrow search field")
GuildRoster:LayoutContextHeader(contextHeader,650,30)
assert(GuildRoster.searchPlaceholder.text==locale.ROSTER_SEARCH_PLACEHOLDER,"wide layout restores the full localized search hint")
GuildRoster.searchBox:SetFocus();assert(not GuildRoster.searchPlaceholder.shown,"search placeholder hides while the edit box is focused")
GuildRoster.searchBox:ClearFocus();assert(GuildRoster.searchPlaceholder.shown,"search placeholder returns on an empty unfocused edit box")
local filterRoot=GuildRoster.filterMenu:GenerateMenu()
local categoryRows={};for _,entry in ipairs(filterRoot.children)do if entry.kind=="button"then categoryRows[entry.text]=entry end end
assert(categoryRows[locale.ROSTER_FILTER_STATUS]and categoryRows[locale.ROSTER_FILTER_RANK]and categoryRows[locale.ROSTER_FILTER_CLASS]and categoryRows[locale.ROSTER_FILTER_ADDON],"filter dropdown exposes four hierarchical categories")
local statusRows=categoryRows[locale.ROSTER_FILTER_STATUS].children;local statusOptions={}
for _,entry in ipairs(statusRows)do statusOptions[entry.text]=entry end
assert(statusOptions[locale.ROSTER_STATUS_ONLINE]and statusOptions[locale.ROSTER_STATUS_OFFLINE]and statusOptions[locale.ROSTER_STATUS_AFK],"status submenu contains Online, Offline and AFK")
assert(statusOptions[locale.ROSTER_STATUS_ONLINE].kind=="checkbox"and statusOptions[locale.ROSTER_STATUS_OFFLINE].kind=="checkbox","status submenu uses native checkbox controls")
local quickChanged=GuildRoster.OnQuickFiltersChanged
GuildRoster.OnQuickFiltersChanged=function(self)self.quickFilter=self:BuildQuickFilter(self.filterState);self:RefreshQuickFilterLabels()end
local onlineResponse=statusOptions[locale.ROSTER_STATUS_ONLINE].setSelected(statusOptions[locale.ROSTER_STATUS_ONLINE].data)
local offlineResponse=statusOptions[locale.ROSTER_STATUS_OFFLINE].setSelected(statusOptions[locale.ROSTER_STATUS_OFFLINE].data)
assert(onlineResponse==MenuResponse.Refresh and offlineResponse==MenuResponse.Refresh,"checkbox selection refreshes in place so the submenu stays open")
assert(GuildRoster.filterState.status.ONLINE and GuildRoster.filterState.status.OFFLINE and GuildRoster.filterMenu.displayText=="Filter (2)","filter submenu supports checked multi-selection and updates its active count")
GuildRoster.OnQuickFiltersChanged=quickChanged
local savedRoot=GuildRoster.savedFilterMenu:GenerateMenu();local savedLabels={};for _,entry in ipairs(savedRoot.children)do if entry.text then savedLabels[entry.text]=entry end end
assert(savedLabels[locale.ROSTER_SAVE_CURRENT_FILTER]and savedLabels[locale.ROSTER_MANAGE_FILTERS]and savedLabels[locale.ROSTER_CLEAR_SAVED_SELECTION],"saved dropdown contains save, manage and clear-selection actions")
local mageProfile;for _,entry in ipairs(savedRoot.children)do if entry.kind=="checkbox"and entry.data and entry.data.id=="mages"then mageProfile=entry;break end end
assert(mageProfile and mageProfile.isSelected(mageProfile.data)==false,"saved profiles remain native multi-select checkbox entries")
assert(mageProfile.setSelected(mageProfile.data)==MenuResponse.Refresh and GuildRoster:IsSavedFilterActive("mages","global"),"saved profile selection still flows through FilterManager")
GuildRoster:ClearSavedFilterSelection()
assert(GuildRoster.refreshButton.normalTexture and GuildRoster.refreshButton.scripts.OnClick,"refresh control uses the icon button and roster refresh action")

-- A search for one character cannot reuse a previous character's row object or filter result.
GuildRoster.activeFilterDefinitions={};GuildRoster.filterState={search="",status="ALL",rank="ALL",class="ALL",addonStatus="RECOGNIZED"};GuildRoster.quickFilter=GuildRoster:BuildQuickFilter(GuildRoster.filterState)
assert(GuildRoster:MatchesMember(recognized),"the first character matches the current filter")
assert(not GuildRoster:MatchesMember(unknown),"switching to a different character reevaluates its own addon status")
print("Guild roster search, saved-filter composition, privacy, unknown states, performance and responsive context header tests passed")
