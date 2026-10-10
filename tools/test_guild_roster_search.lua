-- Offline behavior and toolbar-layout regressions for the guild roster search.
local root=(arg[0]:gsub("tools[/\\]test_guild_roster_search.lua$",""))
local function copy(value,seen)
    if type(value)~="table"then return value end
    seen=seen or{};if seen[value]then return seen[value]end
    local out={};seen[value]=out;for key,child in pairs(value)do out[copy(key,seen)]=copy(child,seen)end;return out
end
local listeners={}
local locale=setmetatable({},{__index=function(_,key)return key end})
locale.ROSTER_RESULT_COUNT="%d of %d members";locale.ROSTER_NO_MATCHES="No guild members match these filters.";locale.NO_MEMBERS="No guild members could be found."
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
GuildRoster.searchBox=savedSearchBox;GuildRoster.RefreshQuickFilterLabels=function()end;GuildRoster.RefreshSavedFilterMenuText=function()end
GuildRoster.filterState={search="member",status="ONLINE",rank="1",class="MAGE",addonStatus="UNKNOWN"};GuildRoster.activeFilters={{id="mages",scope="global"}};GuildRoster.activeFilterDefinitions={}
GuildRoster:ResetFilters()
assert(GuildRoster.filterState.search==""and GuildRoster.filterState.status=="ALL"and#GuildRoster.activeFilters==0 and#filters.active.guildRoster==0,"reset clears search, quick filters and saved selections")

local function layoutWidget(name)
    return{name=name,points={},ClearAllPoints=function(self)self.points={}end,SetPoint=function(self,_,_,_,x,y)self.points={x=x,y=y}end,SetSize=function(self,w,h)self.width,self.height=w,h end,SetWidth=function(self,w)self.width=w end,SetHeight=function(self,h)self.height=h end}
end
for _,width in ipairs({900,700,600})do
    local names={"searchBox","clearSearchButton","savedFilterMenu","saveFilterButton","manageFiltersButton","refreshButton","resetFiltersButton","statusMenu","rankMenu","classMenu","addonStatusMenu","resultLabel"}
    for _,name in ipairs(names)do GuildRoster[name]=layoutWidget(name)end
    local height=GuildRoster:GetToolbarHeight(width);GuildRoster:LayoutToolbar({},width,height)
    assert((width>=820 and height==62)or(width>=650 and width<820 and height==92)or(width<650 and height==150),"toolbar height adapts to the available window width")
    local dropdowns={savedFilterMenu=true,statusMenu=true,rankMenu=true,classMenu=true,addonStatusMenu=true};local rows={}
    for _,name in ipairs(names)do
        local widget=GuildRoster[name];assert(widget.points and widget.points.y<0,"every toolbar control is positioned for the active width: "..name)
        local x=widget.points.x+(dropdowns[name]and 16 or 0);local y=widget.points.y
        assert(x>=0 and x+widget.width<=width+0.01,"toolbar control stays inside the available width: "..name)
        rows[y]=rows[y]or{};rows[y][#rows[y]+1]={name=name,left=x,right=x+widget.width}
    end
    for _,row in pairs(rows)do table.sort(row,function(a,b)return a.left<b.left end);for index=2,#row do assert(row[index-1].right<=row[index].left+0.01,"toolbar controls do not overlap: "..row[index-1].name.." / "..row[index].name)end end
end

-- A search for one character cannot reuse a previous character's row object or filter result.
GuildRoster.activeFilterDefinitions={};GuildRoster.filterState={search="",status="ALL",rank="ALL",class="ALL",addonStatus="RECOGNIZED"};GuildRoster.quickFilter=GuildRoster:BuildQuickFilter(GuildRoster.filterState)
assert(GuildRoster:MatchesMember(recognized),"the first character matches the current filter")
assert(not GuildRoster:MatchesMember(unknown),"switching to a different character reevaluates its own addon status")
print("Guild roster search, saved-filter composition, privacy, unknown states, performance and responsive toolbar tests passed")
