local addonVersion = "2.4.0"
local HolyStorm = LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local L = LibStub("AceLocale-3.0"):GetLocale("Holy_Storm_GuildRoster")
if HolyStorm.PermissionRegistry then HolyStorm.PermissionRegistry:RegisterLegacyAlias("guild.roster.read","guild-roster-read");HolyStorm.PermissionRegistry:RegisterLegacyAlias("roster.manage","roster-manage")end

HolyStorm:RegisterModule({
    id = "GuildRoster", name = "GuildRoster", displayName = L["DISPLAY_NAME"], internalName = "guildRoster", version = addonVersion,
    moduleType = "feature", category="feature", description = L["DESCRIPTION"], permissions = {{id="guild-roster-read",category="Roster",defaults={member=true}}, {id="roster-manage",category="Roster",defaults={officers=true}}},
    dependencies = { "core" }, ui = { page = "guildRoster", navigation = true },
    data = { stores = { "GuildStore", "CharacterStore" } }, enabledByDefault = true,
    ruleFields = {
        {id="guild.rank",aliases={"guildRank"},type="string",name=L["RULE_FIELD_GUILD_RANK"],nameKey="RULE_FIELD_GUILD_RANK",description=L["RULE_FIELD_GUILD_RANK_DESC"],descriptionKey="RULE_FIELD_GUILD_RANK_DESC",category=L["DISPLAY_NAME"],dependencies={"roster"},resolver=function(context)return(context.member and context.member.rank)or(context.character and context.character.guildRank)end},
        {id="guild.rankIndex",type="number",name=L["RULE_FIELD_GUILD_RANK_INDEX"],nameKey="RULE_FIELD_GUILD_RANK_INDEX",description=L["RULE_FIELD_GUILD_RANK_INDEX_DESC"],descriptionKey="RULE_FIELD_GUILD_RANK_INDEX_DESC",category=L["DISPLAY_NAME"],dependencies={"roster"},resolver=function(context)return(context.member and context.member.rankIndex)or(context.character and context.character.guildRankIndex)end},
        {id="player.online",aliases={"online"},type="boolean",name=L["RULE_FIELD_ONLINE"],nameKey="RULE_FIELD_ONLINE",description=L["RULE_FIELD_ONLINE_DESC"],descriptionKey="RULE_FIELD_ONLINE_DESC",category=L["DISPLAY_NAME"],dependencies={"roster"},resolver=function(context)return context.member and context.member.online end},
        {id="player.afk",type="boolean",name=L["RULE_FIELD_AFK"],nameKey="RULE_FIELD_AFK",description=L["RULE_FIELD_AFK_DESC"],descriptionKey="RULE_FIELD_AFK_DESC",category=L["DISPLAY_NAME"],dependencies={"roster"},resolver=function(context)if not context.member then return nil,"MISSING_ROSTER"end;if context.member.online==false then return false elseif context.member.online~=true then return nil,"MISSING_ONLINE"end;if context.member.status==nil then return nil,"MISSING_STATUS"end;return context.member.status=="AFK"or context.member.status==1 end},
        {id="player.dnd",type="boolean",name=L["RULE_FIELD_DND"],nameKey="RULE_FIELD_DND",description=L["RULE_FIELD_DND_DESC"],descriptionKey="RULE_FIELD_DND_DESC",category=L["DISPLAY_NAME"],dependencies={"roster"},resolver=function(context)if not context.member then return nil,"MISSING_ROSTER"end;if context.member.online==false then return false elseif context.member.online~=true then return nil,"MISSING_ONLINE"end;if context.member.status==nil then return nil,"MISSING_STATUS"end;return context.member.status=="DND"or context.member.status==2 end},
        {id="guild.classFile",type="string",name=L["RULE_FIELD_CLASS"],nameKey="RULE_FIELD_CLASS",description=L["RULE_FIELD_CLASS_DESC"],descriptionKey="RULE_FIELD_CLASS_DESC",category=L["DISPLAY_NAME"],dependencies={"roster"},resolver=function(context)return context.member and context.member.classFileName end},
        {id="guild.addonStatus",type="enum",values={"RECOGNIZED","NOT_RECOGNIZED","UNKNOWN"},name=L["RULE_FIELD_ADDON_STATUS"],nameKey="RULE_FIELD_ADDON_STATUS",description=L["RULE_FIELD_ADDON_STATUS_DESC"],descriptionKey="RULE_FIELD_ADDON_STATUS_DESC",category=L["DISPLAY_NAME"],dependencies={"roster"},resolver=function(context)return context.member and(context.member.addonStatus or"UNKNOWN")end},
        {id="guild.rosterSearch",type="string",name=L["RULE_FIELD_ROSTER_SEARCH"],nameKey="RULE_FIELD_ROSTER_SEARCH",description=L["RULE_FIELD_ROSTER_SEARCH_DESC"],descriptionKey="RULE_FIELD_ROSTER_SEARCH_DESC",category=L["DISPLAY_NAME"],dependencies={"roster"},resolver=function(context)
            local member=context.member;if not member then return nil,"MISSING_ROSTER"end
            local values={member.name,member.realm,member.rank,member.className,member.classFileName,member.level and tostring(member.level),member.zone,member.addonVersion}
            local visible={};for _,value in ipairs(values)do if type(value)=="string"or type(value)=="number"then visible[#visible+1]=tostring(value)end end
            return table.concat(visible," ")
        end},
    },
}, function(GuildRoster)

HolyStorm.FilterManager:RegisterTemplate("GuildRoster",{id="template-online",name=L["FILTER_TEMPLATE_ONLINE"],description=L["FILTER_TEMPLATE_ONLINE_DESC"],rules={field="player.online",operator="true"}})

local function setColumnText(fontString, text, color)
    fontString:SetText(text or L["UNKNOWN_VALUE"])
    fontString:SetTextColor(color[1], color[2], color[3])
end

local statusTextures = {
    offline = "Interface\\COMMON\\Indicator-Gray",
    online = "Interface\\COMMON\\Indicator-Green",
    afk = "Interface\\COMMON\\Indicator-Yellow",
    dnd = "Interface\\COMMON\\Indicator-Red",
}

function GuildRoster:FormatOfflineDuration(seconds)
    if not seconds or seconds <= 0 then return L["OFFLINE"] end
    if seconds >= 86400 then return string.format(L["OFFLINE_FOR"], string.format(L["DAYS"], math.floor(seconds / 86400))) end
    if seconds >= 3600 then return string.format(L["OFFLINE_FOR"], string.format(L["HOURS"], math.floor(seconds / 3600))) end
    return string.format(L["OFFLINE_FOR"], string.format(L["MINUTES"], math.max(1, math.floor(seconds / 60))))
end

function GuildRoster:GetSettings()
    local settings = HolyStorm.Database:Get("guildRoster", "profile")
    if type(settings)~="table"then HolyStorm.Database:Set("guildRoster",{},"profile");settings=HolyStorm.Database:Get("guildRoster","profile")end
    if settings.showOffline == nil then HolyStorm.Database:Set("guildRoster.showOffline", true, "profile") end
    if settings.groupTwinks == nil then HolyStorm.Database:Set("guildRoster.groupTwinks", true, "profile") end
    return settings
end

local function newFilterState()
    return {search="",status="ALL",rank="ALL",class="ALL",addonStatus="ALL"}
end

local function combineRules(children)
    if #children==0 then return nil end
    if #children==1 then return children[1] end
    return {logic="AND",children=children}
end

function GuildRoster:BuildQuickFilter(state)
    state=state or self.filterState or newFilterState()
    local children={}
    local query=HolyStorm.Utils.Trim and HolyStorm.Utils.Trim(state.search)or tostring(state.search or""):match("^%s*(.-)%s*$")
    if query and query~=""then children[#children+1]={field="guild.rosterSearch",operator="contains",value=query}end
    if state.status=="ONLINE"then children[#children+1]={field="player.online",operator="=",value=true}
    elseif state.status=="OFFLINE"then children[#children+1]={field="player.online",operator="=",value=false}
    elseif state.status=="AFK"then children[#children+1]={field="player.afk",operator="true"}
    elseif state.status=="DND"then children[#children+1]={field="player.dnd",operator="true"}end
    if state.rank and state.rank~="ALL"and tonumber(state.rank)then children[#children+1]={field="guild.rankIndex",operator="=",value=tonumber(state.rank)}end
    if state.class and state.class~="ALL"then children[#children+1]={field="guild.classFile",operator="=",value=state.class}end
    if state.addonStatus and state.addonStatus~="ALL"then children[#children+1]={field="guild.addonStatus",operator="=",value=state.addonStatus}end
    return combineRules(children)
end

function GuildRoster:GetFilterContext(member)
    if member.filterContext then return member.filterContext end
    return {guid=member.guid,characterUUID=member.guid,accountUUID=member.accountUUID,character=member.characterRecord or{},member=member,target=member}
end

function GuildRoster:BuildFilterContexts(guild)
    local base={}
    if HolyStorm.FilterManager.BuildContext then
        local ok,value=HolyStorm.Utils.SafeCall("guild-roster.filter-context",HolyStorm.FilterManager.BuildContext,HolyStorm.FilterManager,nil,nil,nil,{guild=guild,character={}})
        if ok and type(value)=="table"then base=value end
    end
    for _,member in ipairs(self.sourceMembers or{})do
        local context={};for key,value in pairs(base)do context[key]=value end
        context.accountUUID=member.accountUUID or base.accountUUID;context.playerId=context.accountUUID
        context.characterUUID=member.guid;context.guid=member.guid;context.character=member.characterRecord or{}
        context.guild=guild;context.member=member;context.target=member
        member.filterContext=context
    end
end

function GuildRoster:MatchesMember(member)
    local context=self:GetFilterContext(member)
    if self.quickFilter then
        local _,_,status=HolyStorm.Rules:Evaluate(self.quickFilter,context)
        if status~=HolyStorm.Rules.Result.PASS then return false end
    end
    for _,entry in ipairs(self.activeFilterDefinitions or{})do
        local matched,_,status=HolyStorm.FilterManager:ApplyFilter(entry.filter,context,entry.scope)
        if not matched or status~=HolyStorm.Rules.Result.PASS then return false end
    end
    return true
end

function GuildRoster:ApplyRosterFilters()
    local filtered={}
    for _,member in ipairs(self.sourceMembers or{})do if self:MatchesMember(member)then filtered[#filtered+1]=member end end
    self.visibleMembers=filtered
    self:RenderRows(self:BuildDisplayMembers(filtered))
    self:UpdateResultCount(#filtered,#(self.sourceMembers or{}))
    return filtered
end

function GuildRoster:ReloadActiveFilters()
    local active=HolyStorm.FilterManager:GetActiveFilters("guildRoster")or{}
    self.activeFilters=active;self.activeFilterDefinitions={};local validActive={};local changed=false
    for _,entry in ipairs(active)do
        local id,scope=type(entry)=="table"and entry.id or entry,type(entry)=="table"and entry.scope or"global"
        local filter=id and HolyStorm.FilterManager:GetFilter(id,scope)
        if filter then self.activeFilterDefinitions[#self.activeFilterDefinitions+1]={id=id,scope=scope,filter=filter};validActive[#validActive+1]=type(entry)=="table"and{id=id,scope=scope}or id else changed=true end
    end
    if changed then self.activeFilters=validActive;HolyStorm.FilterManager:SetActiveFilters("guildRoster",validActive)end
    return self.activeFilterDefinitions
end

function GuildRoster:SetActiveFilter(id,scope)
    local found
    for index,entry in ipairs(self.activeFilters or{})do
        local entryId=type(entry)=="table"and entry.id or entry
        local entryScope=type(entry)=="table"and(entry.scope or"global")or"global"
        if entryId==id and entryScope==scope then found=index;break end
    end
    if found then table.remove(self.activeFilters,found)else self.activeFilters[#self.activeFilters+1]={id=id,scope=scope}end
    HolyStorm.FilterManager:SetActiveFilters("guildRoster",self.activeFilters)
    self:ReloadActiveFilters();self:RefreshSavedFilterMenuText()
    self:ApplyRosterFilters()
end

function GuildRoster:ResetFilters()
    self.filterState=newFilterState();self.quickFilter=nil
    self.searchGeneration=(self.searchGeneration or 0)+1
    if self.searchTimer and self.searchTimer.Cancel then self.searchTimer:Cancel();self.searchTimer=nil end
    self.activeFilters={};self.activeFilterDefinitions={}
    if self.searchBox then self.isUpdatingControls=true;self.searchBox.isPlaceholder=false;self.searchBox:SetText("");self.searchBox.isPlaceholder=true;self.searchBox:SetText(L["ROSTER_SEARCH_PLACEHOLDER"]);self.isUpdatingControls=false end
    HolyStorm.FilterManager:SetActiveFilters("guildRoster",{})
    self:RefreshQuickFilterLabels();self:RefreshSavedFilterMenuText();self:ApplyRosterFilters()
end

function GuildRoster:BuildCombinedFilterRoot()
    local children={};local quick=self:BuildQuickFilter(self.filterState)
    if quick then children[#children+1]=quick end
    for _,entry in ipairs(self.activeFilterDefinitions or{})do
        local root=entry.filter and(entry.filter.root or entry.filter.rules)
        if type(root)~="table"then return nil,"FILTER_NOT_FOUND"end
        children[#children+1]=HolyStorm.Utils.DeepCopy(root)
    end
    local root=combineRules(children)
    if not root then return nil,"NO_ACTIVE_FILTERS"end
    local valid,reason=HolyStorm.Rules:Validate(root)
    if not valid then return nil,reason end
    return root
end

function GuildRoster:SaveCurrentFilterProfile(name)
    local engine=HolyStorm.PermissionEngine or HolyStorm.Policy
    if not engine or not engine:HasPermission(nil,nil,"filters-create")then return false,"PERMISSION_DENIED"end
    name=HolyStorm.Utils.Trim and HolyStorm.Utils.Trim(name)or tostring(name or""):match("^%s*(.-)%s*$")
    if type(name)~="string"or name==""or#name>128 then return false,"INVALID_OBJECT_NAME"end
    local root,reason=self:BuildCombinedFilterRoot();if not root then return false,reason end
    local filter={id=HolyStorm.PolicyUI:NewId("guild-roster"),name=name,description=L["ROSTER_SAVED_FILTER_DESC"],category=L["ROSTER_FILTER_CATEGORY"],root=root}
    local ok,result=HolyStorm.FilterManager:SaveFilter(filter,"local")
    if ok then
        self:RefreshSavedFilterMenuText()
        HolyStorm.Events:Emit("HS_UI_STATUS_REQUESTED",L["ROSTER_FILTER_SAVED"])
    end
    return ok,result
end

function GuildRoster:GetRankOptions()
    if self.rankOptions then return self.rankOptions end
    local ranks,ordered={},{}
    for _,member in ipairs(self.sourceMembers or{})do
        local key=member.rankIndex and member.rankIndex<math.huge and tostring(member.rankIndex)
        if key and not ranks[key]and member.rank then ranks[key]={value=key,label=member.rank,order=member.rankIndex};ordered[#ordered+1]=ranks[key]end
    end
    table.sort(ordered,function(a,b)return a.order<b.order or a.order==b.order and a.label<b.label end)
    self.rankOptions=ordered;return ordered
end

function GuildRoster:GetClassOptions()
    if self.classOptions then return self.classOptions end
    local classes,ordered={},{}
    for _,member in ipairs(self.sourceMembers or{})do
        local key=member.classFileName
        if key and not classes[key]then classes[key]={value=key,label=member.className or key};ordered[#ordered+1]=classes[key]end
    end
    table.sort(ordered,function(a,b)return a.label<b.label or a.label==b.label and a.value<b.value end)
    self.classOptions=ordered;return ordered
end

function GuildRoster:OnQuickFiltersChanged(debounce)
    self.quickFilter=self:BuildQuickFilter(self.filterState)
    self:RefreshQuickFilterLabels()
    if debounce then
        self.searchGeneration=(self.searchGeneration or 0)+1;local generation=self.searchGeneration
        local function apply()if generation==GuildRoster.searchGeneration and GuildRoster.page and GuildRoster.page:IsShown()then GuildRoster:ApplyRosterFilters()end end
        if self.searchTimer and self.searchTimer.Cancel then self.searchTimer:Cancel();self.searchTimer=nil end
        if C_Timer and C_Timer.NewTimer then self.searchTimer=C_Timer.NewTimer(.16,function()self.searchTimer=nil;apply()end)
        elseif C_Timer and C_Timer.After then C_Timer.After(.16,apply)else apply()end
    else
        self.searchGeneration=(self.searchGeneration or 0)+1
        if self.searchTimer and self.searchTimer.Cancel then self.searchTimer:Cancel();self.searchTimer=nil end
        self:ApplyRosterFilters()
    end
end

function GuildRoster:GetSavedFilterItems()
    local items={}
    for _,scope in ipairs({"local","global"})do
        for id,filter in pairs(HolyStorm.FilterManager:GetFilters(scope)or{})do
            local key=scope..":"..id
            items[#items+1]={value=key,id=id,scope=scope,label=(scope=="local"and L["ROSTER_LOCAL_BADGE"]or L["ROSTER_GLOBAL_BADGE"]).." "..(filter.name or id)}
        end
    end
    table.sort(items,function(a,b)return a.label<b.label end)
    return items
end

function GuildRoster:RefreshSavedFilterMenuText()
    local menu=self.savedFilterMenu
    if not menu then return end
    local selected={};local count=0
    for _,entry in ipairs(self.activeFilters or{})do
        local id,scope=type(entry)=="table"and entry.id or entry,type(entry)=="table"and entry.scope or"global"
        if id then selected[#selected+1]=(scope or"global")..":"..id;count=count+1 end
    end
    menu:SetValues(selected)
    UIDropDownMenu_SetText(menu,string.format(L["ROSTER_SAVED_FILTERS_SELECTED"],count))
end

function GuildRoster:RefreshQuickFilterLabels()
    local state=self.filterState or newFilterState()
    local function set(menu,value,label)
        if menu then menu:SetValue(value,label)end
    end
    set(self.statusMenu,state.status,string.format(L["ROSTER_FILTER_STATUS_FORMAT"],L["ROSTER_FILTER_STATUS"],L["ROSTER_STATUS_"..state.status]or L["ROSTER_STATUS_ALL"]))
    local rankLabel=L["ROSTER_RANK_ALL"]
    if state.rank~="ALL"then for _,item in ipairs(self:GetRankOptions())do if item.value==state.rank then rankLabel=item.label;break end end end
    set(self.rankMenu,state.rank,string.format(L["ROSTER_FILTER_RANK_FORMAT"],L["ROSTER_FILTER_RANK"],rankLabel))
    local classLabel=L["ROSTER_CLASS_ALL"]
    if state.class~="ALL"then for _,item in ipairs(self:GetClassOptions())do if item.value==state.class then classLabel=item.label;break end end end
    set(self.classMenu,state.class,string.format(L["ROSTER_FILTER_CLASS_FORMAT"],L["ROSTER_FILTER_CLASS"],classLabel))
    local addonLabel=L["ROSTER_ADDON_ALL"]
    if state.addonStatus~="ALL"then addonLabel=L["ROSTER_ADDON_"..state.addonStatus]or addonLabel end
    set(self.addonStatusMenu,state.addonStatus,string.format(L["ROSTER_FILTER_ADDON_FORMAT"],L["ROSTER_FILTER_ADDON"],addonLabel))
    if self.clearSearchButton then self.clearSearchButton:SetShown((state.search or"")~="")end
end

function GuildRoster:UpdateResultCount(visible,total)
    if self.resultLabel then self.resultLabel:SetText(string.format(L["ROSTER_RESULT_COUNT"],visible,total))end
    if self.emptyState then self.emptyState.frame:SetShown(visible==0);self.emptyState:SetText(self.emptyMessage or(total==0 and L["NO_MEMBERS"]or L["ROSTER_NO_MATCHES"]))end
end

function GuildRoster:OpenSaveFilterDialog()
    local permission=HolyStorm.PermissionEngine or HolyStorm.Policy
    if not permission or not permission:HasPermission(nil,nil,"filters-create")then
        HolyStorm.Events:Emit("HS_UI_STATUS_REQUESTED",L["ROSTER_FILTER_PERMISSION_DENIED"]);return
    end
    local root,reason=self:BuildCombinedFilterRoot()
    if not root then
        HolyStorm.Events:Emit("HS_UI_STATUS_REQUESTED",reason=="NO_ACTIVE_FILTERS"and L["ROSTER_NO_FILTER_TO_SAVE"]or HolyStorm.PolicyUI:ErrorText(reason));return
    end
    StaticPopup_Show("HOLYSTORM_SAVE_ROSTER_FILTER")
end

function GuildRoster:CreateContextHeader(parent)
    local policyUI=HolyStorm.PolicyUI
    local search=policyUI:Edit(parent,220,function(edit)
        if GuildRoster.isUpdatingControls or edit.isPlaceholder then return end
        GuildRoster.filterState.search=edit:GetText()or""
        GuildRoster:OnQuickFiltersChanged(true)
    end)
    search:SetMaxLetters(128)
    search:SetScript("OnEditFocusGained",function(edit)
        if edit.isPlaceholder then edit.isPlaceholder=nil;edit:SetText("")end
    end)
    search:SetScript("OnEditFocusLost",function(edit)
        if edit:GetText()==""then edit.isPlaceholder=true;edit:SetText(L["ROSTER_SEARCH_PLACEHOLDER"])end
    end)
    search:SetScript("OnEnterPressed",function(edit)edit:ClearFocus()end)
    search.isPlaceholder=true;search:SetText(L["ROSTER_SEARCH_PLACEHOLDER"])
    self.searchBox=search
    self.clearSearchButton=policyUI:Button(parent,"x",26,function()
        GuildRoster.filterState.search="";GuildRoster.isUpdatingControls=true;search.isPlaceholder=true;search:SetText(L["ROSTER_SEARCH_PLACEHOLDER"]);GuildRoster.isUpdatingControls=false
        GuildRoster:OnQuickFiltersChanged(false)
    end)
    self.clearSearchButton:SetScript("OnEnter",function(button)GameTooltip:SetOwner(button,"ANCHOR_TOP");GameTooltip:SetText(L["ROSTER_CLEAR_SEARCH"]);GameTooltip:Show()end)
    self.clearSearchButton:SetScript("OnLeave",function()GameTooltip:Hide()end)
    self.clearSearchButton:Hide()

    local saved=policyUI:CreateMultiSelector(parent,180,function()return GuildRoster:GetSavedFilterItems()end,function(values)
        local itemsByKey={};for _,item in ipairs(GuildRoster:GetSavedFilterItems())do itemsByKey[item.value]=item end
        local active={};for _,key in ipairs(values or{})do local item=itemsByKey[key];if item then active[#active+1]={id=item.id,scope=item.scope}end end
        GuildRoster.activeFilters=active;HolyStorm.FilterManager:SetActiveFilters("guildRoster",active)
        GuildRoster:ReloadActiveFilters();GuildRoster:RefreshSavedFilterMenuText();GuildRoster:ApplyRosterFilters()
    end)
    self.savedFilterMenu=saved
    self.saveFilterButton=policyUI:Button(parent,L["ROSTER_SAVE_FILTER"],100,function()GuildRoster:OpenSaveFilterDialog()end)
    self.manageFiltersButton=policyUI:Button(parent,L["ROSTER_MANAGE_FILTERS"],104,function()HolyStorm.Administration:Open("filters")end)
    self.refreshButton=policyUI:Button(parent,L["REFRESH"],86,function()GuildRoster:RequestAndRefresh()end)
    self.refreshButton:SetScript("OnEnter",function(button)GameTooltip:SetOwner(button,"ANCHOR_TOP");GameTooltip:SetText(L["REFRESH_TOOLTIP"]);GameTooltip:Show()end)
    self.refreshButton:SetScript("OnLeave",function()GameTooltip:Hide()end)
    self.resetFiltersButton=policyUI:Button(parent,L["ROSTER_RESET_FILTERS"],88,function()GuildRoster:ResetFilters()end)
    self.statusMenu=policyUI:CreateSelector(parent,110,function()return{
        {value="ALL",label=L["ROSTER_STATUS_ALL"]},{value="ONLINE",label=L["ROSTER_STATUS_ONLINE"]},{value="OFFLINE",label=L["ROSTER_STATUS_OFFLINE"]},
        {value="AFK",label=L["ROSTER_STATUS_AFK"]},{value="DND",label=L["ROSTER_STATUS_DND"]},
    }end,function(value)GuildRoster.filterState.status=value;GuildRoster:OnQuickFiltersChanged(false)end)
    self.rankMenu=policyUI:CreateSelector(parent,110,function()
        local items={{value="ALL",label=L["ROSTER_RANK_ALL"]}};for _,item in ipairs(GuildRoster:GetRankOptions())do items[#items+1]=item end;return items
    end,function(value)GuildRoster.filterState.rank=value;GuildRoster:OnQuickFiltersChanged(false)end)
    self.classMenu=policyUI:CreateSelector(parent,110,function()
        local items={{value="ALL",label=L["ROSTER_CLASS_ALL"]}};for _,item in ipairs(GuildRoster:GetClassOptions())do items[#items+1]=item end;return items
    end,function(value)GuildRoster.filterState.class=value;GuildRoster:OnQuickFiltersChanged(false)end)
    self.addonStatusMenu=policyUI:CreateSelector(parent,168,function()return{
        {value="ALL",label=L["ROSTER_ADDON_ALL"]},{value="RECOGNIZED",label=L["ROSTER_ADDON_RECOGNIZED"]},
        {value="NOT_RECOGNIZED",label=L["ROSTER_ADDON_NOT_RECOGNIZED"]},{value="UNKNOWN",label=L["ROSTER_ADDON_UNKNOWN"]},
    }end,function(value)GuildRoster.filterState.addonStatus=value;GuildRoster:OnQuickFiltersChanged(false)end)
    self.resultLabel=policyUI:Label(parent,"","GameFontHighlightSmall")
    self.resultLabel:SetJustifyH("RIGHT")
    local function tooltip(widget,text)
        widget:SetScript("OnEnter",function(owner)GameTooltip:SetOwner(owner,"ANCHOR_TOP");GameTooltip:SetText(text);GameTooltip:Show()end)
        widget:SetScript("OnLeave",function()GameTooltip:Hide()end)
    end
    tooltip(search,L["ROSTER_SEARCH_TOOLTIP"]);tooltip(saved,L["ROSTER_SAVED_FILTERS_TOOLTIP"])
    tooltip(self.statusMenu,L["ROSTER_STATUS_TOOLTIP"]);tooltip(self.rankMenu,L["ROSTER_RANK_TOOLTIP"])
    tooltip(self.classMenu,L["ROSTER_CLASS_TOOLTIP"]);tooltip(self.addonStatusMenu,L["ROSTER_ADDON_TOOLTIP"])
    if not StaticPopupDialogs["HOLYSTORM_SAVE_ROSTER_FILTER"]then
        StaticPopupDialogs["HOLYSTORM_SAVE_ROSTER_FILTER"]={
            text=L["ROSTER_SAVE_FILTER_PROMPT"],button1=ACCEPT,button2=CANCEL,hasEditBox=true,maxLetters=128,timeout=0,whileDead=true,hideOnEscape=true,preferredIndex=3,
            OnAccept=function(dialog)
                local edit=dialog.EditBox or dialog.editBox
                local ok,reason=GuildRoster:SaveCurrentFilterProfile(edit and edit:GetText()or"")
                if not ok then HolyStorm.Events:Emit("HS_UI_STATUS_REQUESTED",HolyStorm.PolicyUI:ErrorText(reason))end
            end,
            EditBoxOnEnterPressed=function(edit)local dialog=edit:GetParent();if dialog.button1 then dialog.button1:Click()end end,
            OnShow=function(dialog)if dialog.EditBox then dialog.EditBox:SetText("");dialog.EditBox:SetFocus()end end,
        }
    end
    self:RefreshSavedFilterMenuText();self:RefreshQuickFilterLabels()
end

function GuildRoster:LayoutContextHeader(parent,width,height)
    local narrow=width<820
    local compact=width<650
    local function place(widget,x,y,w,h,dropdown)
        widget:ClearAllPoints()
        if dropdown then widget:SetPoint("TOPLEFT",parent,"TOPLEFT",x-16,-y)
        else widget:SetPoint("TOPLEFT",parent,"TOPLEFT",x,-y)end
        if widget.SetSize then widget:SetSize(w,h)elseif widget.SetWidth then widget:SetWidth(w);if widget.SetHeight then widget:SetHeight(h)end end
    end
    local gap=5
    if not narrow then
        local x=0;local y=2;local searchW=math.min(230,width*.28)
        place(self.searchBox,x,y,searchW-31,24);place(self.clearSearchButton,searchW-26,y,26,23);x=x+searchW+gap
        local savedW=math.min(190,width*.23);place(self.savedFilterMenu,x,y,savedW,24,true);x=x+savedW+gap
        place(self.saveFilterButton,x,y,96,23);x=x+101
        place(self.manageFiltersButton,x,y,104,23);x=x+109
        place(self.refreshButton,x,y,84,23)
        y=34;x=0
        local statusW=112;local rankW=112;local classW=112;local addonW=170
        place(self.statusMenu,x,y,statusW,24,true);x=x+statusW+gap
        place(self.rankMenu,x,y,rankW,24,true);x=x+rankW+gap
        place(self.classMenu,x,y,classW,24,true);x=x+classW+gap
        place(self.addonStatusMenu,x,y,addonW,24,true);x=x+addonW+gap
        place(self.resetFiltersButton,x,y,88,23);x=x+93
        place(self.resultLabel,x,y,math.max(80,width-x),22)
    elseif not compact then
        local y1,y2,y3=2,32,62
        local searchWidth=width*.35;local savedWidth=width*.25;local actionX=searchWidth+31+savedWidth+gap*3
        place(self.searchBox,0,y1,searchWidth,24);place(self.clearSearchButton,searchWidth+5,y1,26,23)
        place(self.savedFilterMenu,searchWidth+31,y1,savedWidth,24,true)
        place(self.saveFilterButton,actionX,y1,90,23);place(self.manageFiltersButton,actionX+95,y1,96,23)
        place(self.statusMenu,0,y2,112,24,true);place(self.rankMenu,116,y2,112,24,true);place(self.classMenu,232,y2,112,24,true)
        place(self.addonStatusMenu,348,y2,164,24,true);place(self.refreshButton,518,y2,84,23)
        place(self.resetFiltersButton,0,y3,88,23);place(self.resultLabel,94,y3,width-94,22)
    else
        local y1,y2,y3,y4=2,32,62,92
        place(self.searchBox,0,y1,width-34,24);place(self.clearSearchButton,width-28,y1,26,23)
        local half=math.floor((width-gap)/2)
        place(self.statusMenu,0,y2,half,24,true);place(self.rankMenu,half+gap,y2,half,24,true)
        place(self.classMenu,0,y3,half,24,true);place(self.addonStatusMenu,half+gap,y3,half,24,true)
        place(self.savedFilterMenu,0,y4,width-188,24,true);place(self.refreshButton,width-182,y4,84,23);place(self.resetFiltersButton,width-93,y4,88,23)
        local y5=122;place(self.saveFilterButton,0,y5,96,23);place(self.manageFiltersButton,101,y5,104,23);place(self.resultLabel,210,y5,width-210,22)
    end
end

function GuildRoster:GetContextHeaderHeight(width)
    if width<650 then return 150 elseif width<820 then return 92 else return 62 end
end

function GuildRoster:RegisterContextHeader()
    local ok,reason=HolyStorm.UI:RegisterPageContextHeader("guildRoster","GuildRoster",{
        height=function(width)return GuildRoster:GetContextHeaderHeight(width)end,
        build=function(parent)GuildRoster:CreateContextHeader(parent)end,
        layout=function(parent,width,height)GuildRoster:LayoutContextHeader(parent,width,height)end,
    })
    if not ok then HolyStorm.Utils.SafeCall("guild.context-header.register",function()error(tostring(reason))end)end
end

function GuildRoster:CreateColumn(parent, left, right)
    local text = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("LEFT", parent, left < 0 and "RIGHT" or "LEFT", left, 0)
    text:SetPoint("RIGHT", parent, "RIGHT", right, 0)
    text:SetJustifyH("LEFT")
    return text
end

function GuildRoster:CreateRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(22)
    row:EnableMouse(true)
    row.highlight = row:CreateTexture(nil, "BACKGROUND")
    row.highlight:SetAllPoints()
    row.highlight:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    row.highlight:SetBlendMode("ADD")
    row.highlight:SetAlpha(0.8)
    row.highlight:Hide()
    row:SetScript("OnEnter", function(self) self.highlight:Show() end)
    row:SetScript("OnLeave", function(self) self.highlight:Hide() end)
    row.indicator = row:CreateTexture(nil, "ARTWORK")
    row.indicator:SetSize(14, 14); row.indicator:SetPoint("LEFT", row, "LEFT", 8, 0)
    row.classIcon=row:CreateTexture(nil,"ARTWORK");row.classIcon:SetSize(16,16);row.classIcon:SetPoint("LEFT",row,"LEFT",27,0);row.classIcon:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
    row.twinkArrow = row:CreateTexture(nil, "ARTWORK")
    row.twinkArrow:SetSize(10, 10); row.twinkArrow:SetPoint("LEFT", row, "LEFT", 50, 0)
    row.twinkArrow:SetTexture("Interface\\Buttons\\Arrow-Up-Up")
    row.twinkArrow:SetRotation(-math.pi / 2)
    row.twinkArrow:Hide()
    row.name = self:CreateColumn(row, 46, -560); row.rank = self:CreateColumn(row, -550, -445)
    row.level = self:CreateColumn(row, -435, -390); row.realm = self:CreateColumn(row, -380, -280); row.realm:SetWordWrap(false)
    row.zone = self:CreateColumn(row, -270, -170); row.status = self:CreateColumn(row, -160, -90); row.version = self:CreateColumn(row, -80, -10)
    return row
end

function GuildRoster:CreateMemberMenu()
    local menu = CreateFrame("Frame", "HolyStormGuildMemberMenu", UIParent, "BasicFrameTemplateWithInset")
    menu:SetSize(360, 424); menu:SetFrameStrata("DIALOG"); menu:SetToplevel(true); menu:SetClampedToScreen(true); menu:SetMovable(true); menu:EnableMouse(true); menu:RegisterForDrag("LeftButton"); menu:Hide()
    menu:SetScript("OnDragStart", function(self) self:StartMoving() end)
    menu:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    if not tContains(UISpecialFrames, "HolyStormGuildMemberMenu") then table.insert(UISpecialFrames, "HolyStormGuildMemberMenu") end
    menu.title = menu:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    menu.title:SetPoint("TOPLEFT", menu, "TOPLEFT", 20, -28); menu.title:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -42, -28); menu.title:SetJustifyH("LEFT")
    menu.detail = menu:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    menu.detail:SetPoint("TOPLEFT", menu.title, "BOTTOMLEFT", 0, -6); menu.detail:SetJustifyH("LEFT")
    menu.zone = menu:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    menu.zone:SetPoint("TOPLEFT", menu.detail, "BOTTOMLEFT", 0, -16); menu.zone:SetJustifyH("LEFT")
    menu.rank = menu:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    menu.rank:SetPoint("TOPLEFT", menu.zone, "BOTTOMLEFT", 0, -12); menu.rank:SetJustifyH("LEFT")
    menu.lastSeen = menu:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    menu.lastSeen:SetPoint("TOPLEFT", menu.rank, "BOTTOMLEFT", 0, -12); menu.lastSeen:SetJustifyH("LEFT")

    local function createNoteBox(label, top)
        local labelText = menu:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        labelText:SetPoint("TOPLEFT", menu, "TOPLEFT", 20, top); labelText:SetText(label); labelText:SetTextColor(1, 0.82, 0)
        local box = CreateFrame("Frame", nil, menu, "BackdropTemplate")
        box:SetPoint("TOPLEFT", labelText, "BOTTOMLEFT", 0, -4); box:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -20, 0); box:SetHeight(58)
        box:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        box.text = box:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        box.text:SetPoint("TOPLEFT", box, "TOPLEFT", 8, -7); box.text:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -8, 7); box.text:SetJustifyH("LEFT"); box.text:SetJustifyV("TOP"); box.text:SetWordWrap(true)
        box.edit = CreateFrame("EditBox", nil, box)
        box.edit:SetPoint("TOPLEFT", box, "TOPLEFT", 8, -7); box.edit:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -8, 7)
        box.edit:SetFontObject(GameFontHighlight); box.edit:SetMultiLine(true); box.edit:SetAutoFocus(false); box.edit:SetMaxLetters(0); box.edit:SetJustifyH("LEFT"); box.edit:SetJustifyV("TOP")
        box.edit:SetScript("OnEscapePressed", function() menu:Hide() end); box.edit:Hide()
        return box
    end
    menu.note = createNoteBox(L["MEMBER_NOTE"], -154)
    menu.officerNote = createNoteBox(L["MEMBER_OFFICER_NOTE"], -244)
    menu.rankButton = CreateFrame("Button", nil, menu, "UIPanelButtonTemplate")
    menu.rankButton:SetSize(120, 21); menu.rankButton:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -20, -96); menu.rankButton:SetText(L["MEMBER_CHANGE_RANK"]); menu.rankButton:Hide()
    menu.rankButton:SetScript("OnClick", function() GuildRoster:ShowRankMenu(menu) end)
    menu.rankApply = CreateFrame("Button", nil, menu, "SecureActionButtonTemplate,UIPanelButtonTemplate")
    menu.rankApply:SetSize(120, 21); menu.rankApply:SetPoint("RIGHT", menu.rankButton, "LEFT", -4, 0); menu.rankApply:SetText(L["MEMBER_APPLY_RANK"]); menu.rankApply:Hide()
    menu.save = CreateFrame("Button", nil, menu, "UIPanelButtonTemplate")
    menu.save:SetSize(112, 24); menu.save:SetPoint("BOTTOMRIGHT", menu, "BOTTOMRIGHT", -20, 16); menu.save:SetText(L["MEMBER_SAVE"]); menu.save:Hide()
    menu.save:SetScript("OnClick", function()
        local member = menu.member
        if not member then return end
        HolyStorm.Actions:Execute("guild.save-notes", member.index, menu.note.edit:GetText(), menu.officerNote.edit:GetText(), menu.canEditNote, menu.canEditOfficerNote)
    end)
    menu.contextActions = {}
    for index = 1, 4 do
        local action = CreateFrame("Button", nil, menu, "UIPanelButtonTemplate")
        action:SetSize(150, 22); action:SetPoint("BOTTOMLEFT", menu, "BOTTOMLEFT", 20 + (((index - 1) % 2) * 156), 48 + (math.floor((index - 1) / 2) * 26)); action:Hide()
        action:SetScript("OnClick", function(button) if button.callback and menu.member then button.callback(menu.member.guid, button.context) end end)
        menu.contextActions[index] = action
    end
    menu.close = CreateFrame("Button", nil, menu, "UIPanelCloseButton")
    menu.close:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -4, -4)
    self.memberMenu = menu
end

function GuildRoster:ShowRankMenu(menu)
    local member = menu.member
    if InCombatLockdown() or not (member and member.guid and _G.C_GuildInfo and _G.C_GuildInfo.IsGuildRankAssignmentAllowed) then return end
    if not self.rankDropdown then self.rankDropdown = CreateFrame("Frame", "HolyStormGuildRosterRankDropdown", UIParent, "UIDropDownMenuTemplate") end
    UIDropDownMenu_Initialize(self.rankDropdown, function(_, level)
        if level ~= 1 then return end
        local currentOrder = _G.C_GuildInfo.GetGuildRankOrder and _G.C_GuildInfo.GetGuildRankOrder(member.guid) or (member.rankIndex + 1)
        for rankOrder = 1, GuildControlGetNumRanks() do
            if _G.C_GuildInfo.IsGuildRankAssignmentAllowed(member.guid, rankOrder) then
                local selectedOrder = rankOrder
                local info = UIDropDownMenu_CreateInfo()
                info.text = GuildControlGetRankName(selectedOrder)
                info.checked = selectedOrder == currentOrder
                info.func = function() GuildRoster:PrepareRankChange(menu, selectedOrder) end
                UIDropDownMenu_AddButton(info, level)
            end
        end
    end, "MENU")
    ToggleDropDownMenu(1, nil, self.rankDropdown, "cursor", 0, 0)
end

function GuildRoster:PrepareRankChange(menu, targetOrder)
    local member = menu.member
    if InCombatLockdown() or not member then return end
    local currentOrder = _G.C_GuildInfo.GetGuildRankOrder and _G.C_GuildInfo.GetGuildRankOrder(member.guid) or (member.rankIndex + 1)
    if targetOrder == currentOrder then menu.rankApply:Hide(); return end
    local command = targetOrder < currentOrder and "/guildpromote " or "/guilddemote "
    local macroLines = {}
    for _ = 1, math.abs(targetOrder - currentOrder) do table.insert(macroLines, command .. (member.name or "")) end
    menu.rankApply:SetAttribute("type", "macro")
    menu.rankApply:SetAttribute("macrotext", table.concat(macroLines, "\n"))
    menu.rankApply:SetText(L["MEMBER_APPLY_RANK"] .. ": " .. (GuildControlGetRankName(targetOrder) or ""))
    menu.rankApply:Show()
end

function GuildRoster:ShowGuildMemberMenu(row, member)
    if not self.memberMenu then self:CreateMemberMenu() end
    local menu = self.memberMenu
    local classColor = RAID_CLASS_COLORS[member.classFileName] or NORMAL_FONT_COLOR
    menu.title:SetText(member.name or L["UNKNOWN_VALUE"]); menu.title:SetTextColor(classColor.r, classColor.g, classColor.b)
    menu.detail:SetText(string.format(L["MEMBER_LEVEL_CLASS"], member.level or 0, member.className or L["UNKNOWN_VALUE"]))
    menu.zone:SetText(L["MEMBER_ZONE"] .. " " .. (member.zone or L["UNKNOWN_VALUE"]))
    menu.rank:SetText(L["MEMBER_RANK"] .. " " .. (member.rank or L["UNKNOWN_VALUE"]))
    menu.lastSeen:SetText(L["MEMBER_LAST_SEEN"] .. " " .. (member.online and L["ONLINE"] or self:FormatOfflineDuration(member.status)))
    local note = member.note and member.note ~= "" and member.note or L["NO_NOTE"]
    local officerNote = member.officerNote and member.officerNote ~= "" and member.officerNote or L["NO_NOTE"]
    local policyCanManage=(HolyStorm.PermissionEngine or HolyStorm.Policy):Can("roster-manage")
    menu.canEditNote = policyCanManage and (((_G.CanEditPublicNote and _G.CanEditPublicNote()) or (_G.CanEditOfficerNote and _G.CanEditOfficerNote()))==true)
    menu.canEditOfficerNote = policyCanManage and ((_G.CanEditOfficerNote and _G.CanEditOfficerNote())==true)
    menu.member = member
    menu.note.text:SetText(note); menu.note.edit:SetText(member.note or ""); menu.note.text:SetShown(not menu.canEditNote); menu.note.edit:SetShown(menu.canEditNote)
    menu.officerNote.text:SetText(officerNote); menu.officerNote.edit:SetText(member.officerNote or ""); menu.officerNote.text:SetShown(not menu.canEditOfficerNote); menu.officerNote.edit:SetShown(menu.canEditOfficerNote)
    menu.save:SetShown(menu.canEditNote or menu.canEditOfficerNote)
    local canChangeRank = false
    if member.guid and _G.C_GuildInfo and _G.C_GuildInfo.IsGuildRankAssignmentAllowed and _G.GuildControlGetNumRanks then
        for rankOrder = 1, GuildControlGetNumRanks() do
            if _G.C_GuildInfo.IsGuildRankAssignmentAllowed(member.guid, rankOrder) then canChangeRank = true; break end
        end
    end
    menu.rankButton:SetShown(policyCanManage and canChangeRank and not InCombatLockdown())
    menu.rankApply:Hide()
    local context=HolyStorm.CharacterActions and HolyStorm.CharacterActions:Resolve(member.guid)
    local actions=context and HolyStorm.CharacterActions:GetProviderActions(member.guid,context)or{}
    for index,button in ipairs(menu.contextActions or{})do local action=actions[index];button.callback=action and action.callback or nil;button.context=context;button:SetText(action and action.text or"");button:SetEnabled(action and action.enabled~=false or false);button:SetShown(action~=nil)end
    menu:ClearAllPoints(); menu:SetPoint("TOPLEFT", row, "BOTTOMLEFT", 18, 2); menu:Show(); menu:Raise()
end

function GuildRoster:CreateHeader(parent)
    local header = CreateFrame("Frame", nil, parent)
    header:SetHeight(24); header:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -1); header:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -1)
    header.indicator = self:CreateColumn(header, 10, -560); header.name = self:CreateColumn(header, 46, -560); header.rank = self:CreateColumn(header, -550, -445)
    header.level = self:CreateColumn(header, -435, -390); header.realm = self:CreateColumn(header, -380, -280); header.realm:SetWordWrap(false)
    header.zone = self:CreateColumn(header, -270, -170); header.status = self:CreateColumn(header, -160, -90); header.version = self:CreateColumn(header, -80, -10)
    for _, column in ipairs({ "name", "rank", "level", "realm", "zone", "status", "version" }) do
        header[column]:SetFontObject(GameFontNormalSmall); header[column]:SetText(L["COLUMN_" .. string.upper(column)]); header[column]:SetTextColor(1, 0.82, 0)
    end
end

function GuildRoster:ShowCharacter(member)
    return member and member.guid and next(HolyStorm:CallCapability("character.open",member.guid,"summary"))~=nil or false
end

function GuildRoster:InitializeUI()
    local UI = HolyStorm:GetModule("UI", true)
    local page = CreateFrame("Frame", nil, UI.content)
    self.filterState=self.filterState or newFilterState()
    self:CreateHeader(page)
    local scroll = CreateFrame("ScrollFrame", nil, page, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -28); scroll:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -28, 4)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1); scroll:SetScrollChild(content)
    scroll:SetScript("OnSizeChanged", function(self) content:SetWidth(self:GetWidth()) end)
    content:SetWidth(scroll:GetWidth())
    local empty=HolyStorm.UIComponents:CreateEmptyState(page,{text=L["ROSTER_NO_MATCHES"],width=440})
    empty.frame:SetPoint("TOPLEFT",scroll,"TOPLEFT");empty.frame:SetPoint("BOTTOMRIGHT",scroll,"BOTTOMRIGHT");empty.frame:Hide()
    self.page, self.ui, self.scroll, self.scrollContent, self.rows,self.emptyState = page, UI, scroll, content, {},empty
    self.sourceMembers,self.visibleMembers={},{}
    HolyStorm.UI:RegisterPage("guildRoster", page, L["WINDOW_TITLE"], function() GuildRoster:Refresh() end, { "HS_ROSTER_UPDATED", "HS_SYNC_VERSION_UPDATED", "HS_FILTER_UPDATED", "HS_FILTER_DELETED", "HS_ACTIVE_FILTERS_UPDATED" })
    self:RegisterContextHeader()
    HolyStorm.UI:AddNavigation("guildRoster", 3, "Interface\\Icons\\INV_Misc_GroupLooking", L["NAVIGATION_TITLE"], L["NAVIGATION_DESCRIPTION"], function() GuildRoster:RequestAndRefresh(); HolyStorm.UI:ShowPage("guildRoster") end)
end

function GuildRoster:OnInitialize()
    HolyStorm.Actions:Register("guild.save-notes", "GuildRoster", function(index, publicNote, officerNote, canEditPublic, canEditOfficer)
        if not (HolyStorm.PermissionEngine or HolyStorm.Policy):Can("roster-manage") then return false end
        if canEditPublic and _G.GuildRosterSetPublicNote then _G.GuildRosterSetPublicNote(index, publicNote) end
        if canEditOfficer and _G.GuildRosterSetOfficerNote then _G.GuildRosterSetOfficerNote(index, officerNote) end
        GuildRoster:RequestAndRefresh()
    end, { combatSafe=false, priority=0 })
    HolyStorm:RegisterUIExtension("GuildRoster",{id="guild.roster",order=3,initialize=function()GuildRoster:InitializeUI()end})
end

function GuildRoster:OnEnable()
    local Options = HolyStorm:GetModule("Options", true)
    if Options then Options:RegisterOptionsTab("guildRoster", {
        type = "group", name = L["OPTIONS_TAB_TITLE"], order = 4,
        args = {
            showOffline = {
                type = "toggle", name = L["OPTION_SHOW_OFFLINE"], desc = L["OPTION_SHOW_OFFLINE_DESC"], order = 1,
                get = function() return GuildRoster:GetSettings().showOffline end,
                set = function(_, value) HolyStorm.Database:Set("guildRoster.showOffline", value, "profile"); GuildRoster:Refresh() end,
            },
            groupTwinks = {
                type = "toggle", name = L["OPTION_GROUP_TWINKS"], desc = L["OPTION_GROUP_TWINKS_DESC"], order = 2,
                get = function() return GuildRoster:GetSettings().groupTwinks end,
                set = function(_, value) HolyStorm.Database:Set("guildRoster.groupTwinks", value, "profile"); GuildRoster:Refresh() end,
            },
        },
    }) end
    local function queueRoster(request)
        if request then HolyStorm.Data.GuildStore:RequestRoster() end
        HolyStorm.Tasks:Enqueue("guild.roster",function()HolyStorm.Data.GuildStore:RefreshFromBlizzard()end,{priority=6,debounce=.5,cooldown=5})
    end
    HolyStorm.Events:Register("GUILD_ROSTER_UPDATE", "guild-roster", function()queueRoster(false);if HolyStorm.UI then HolyStorm.UI:MarkDirty("guildRoster")end end)
    HolyStorm.Events:Register("PLAYER_GUILD_UPDATE", "guild-roster", function()queueRoster(true);if HolyStorm.UI then HolyStorm.UI:MarkDirty("guildRoster")end end)
    if IsLoggedIn() then queueRoster(true) end
end

function GuildRoster:OnDisable() if self.searchTimer and self.searchTimer.Cancel then self.searchTimer:Cancel();self.searchTimer=nil end;HolyStorm.Events:UnregisterOwner("guild-roster");HolyStorm.Tasks:Cancel("guild.roster") end

function GuildRoster:RequestAndRefresh()
    if _G.GuildRoster then _G.GuildRoster() end
    HolyStorm.Tasks:Enqueue("guild.ui-refresh", function() HolyStorm.Data.GuildStore:RefreshFromBlizzard(); GuildRoster:Refresh() end, { priority=1, debounce=0.3, cooldown=1 })
end

function GuildRoster:Refresh()
    if not self.page or not self.page:IsShown() then return end
    if not IsInGuild() then self.sourceMembers={};self.emptyMessage=L["NO_GUILD"];self.twinkOwnerByGuid={};HolyStorm.Events:Emit("HS_UI_STATUS_REQUESTED",L["NO_GUILD"]);self:ReloadActiveFilters();self:ApplyRosterFilters();return end
    self.emptyMessage=nil
    local settings, guild = self:GetSettings(), HolyStorm.Data.GuildStore:GetCurrent()
    self.settings=settings
    local members, memberCount = {}, 0
    for _, stored in pairs(guild and guild.roster or {}) do
        memberCount = memberCount + 1
        if settings.showOffline or stored.online then
            local c=HolyStorm.Data.CharacterStore:Get(stored.guid)
            local version=HolyStorm.Sync and HolyStorm.Sync:GetKnownVersion(stored.guid)
            local realm=stored.name and stored.name:match("%-([^%-]+)$")
            table.insert(members, { index=stored.index,guid=stored.guid,name=stored.name,realm=realm,rank=stored.rank,rankIndex=stored.rankIndex or math.huge,level=stored.level,className=stored.class,zone=stored.zone,note=stored.note,officerNote=stored.officerNote,online=stored.online,status=stored.status,isMobile=stored.isMobile,classFileName=stored.classFile,characterRecord=c or{},itemLevel=c and c.itemLevel,mythicScore=c and c.mythicPlus and c.mythicPlus.overallScore,addonVersion=version,addonStatus=version and"RECOGNIZED"or"UNKNOWN" })
        end
    end
    table.sort(members, function(left, right)
        if left.online ~= right.online then return left.online end
        if left.rankIndex ~= right.rankIndex then return left.rankIndex < right.rankIndex end
        return (left.name or "") < (right.name or "")
    end)
    self.sourceMembers=members
    self:BuildFilterContexts(guild)
    self.rankOptions,self.classOptions=nil,nil
    self:GetRankOptions();self:GetClassOptions()
    self.twinkOwnerByGuid={}
    if settings.groupTwinks and HolyStorm.TwinkCore then
        for _,member in ipairs(members)do
            if member.guid then
                local identity=HolyStorm.TwinkCore:GetRosterIdentity(member.guid,guild)
                if identity and identity.guildMain and identity.guildMain~=member.guid then self.twinkOwnerByGuid[member.guid]=identity.guildMain end
            end
        end
    end
    self:ReloadActiveFilters();self:RefreshSavedFilterMenuText();self:RefreshQuickFilterLabels();self:ApplyRosterFilters()
    HolyStorm.Events:Emit("HS_UI_STATUS_REQUESTED",memberCount > 0 and string.format(L["STATUS_MEMBER_COUNT"], memberCount) or L["NO_MEMBERS"])
end

function GuildRoster:BuildDisplayMembers(members)
    local settings=self.settings or self:GetSettings()
    if not settings.groupTwinks then self.lastMembersByGuid={};for _,member in ipairs(members)do if member.guid then self.lastMembersByGuid[member.guid]=member end end;return members end
    local membersByGuid,twinksByOwner,twinkOwners={},{},{}
    for _,member in ipairs(members)do member.isTwink=nil;if member.guid then membersByGuid[member.guid]=member end end
    self.lastMembersByGuid=membersByGuid
    for guid,ownerGuid in pairs(self.twinkOwnerByGuid or{})do
        if ownerGuid~=guid and membersByGuid[guid]and membersByGuid[ownerGuid]then
            twinkOwners[guid]=ownerGuid;twinksByOwner[ownerGuid]=twinksByOwner[ownerGuid]or{};table.insert(twinksByOwner[ownerGuid],membersByGuid[guid])
        end
    end
    local grouped={}
    for _,member in ipairs(members)do
        if not twinkOwners[member.guid]then
            table.insert(grouped,member);local twinks=twinksByOwner[member.guid]
            if twinks then table.sort(twinks,function(left,right)return(left.name or"")<(right.name or"")end);for _,twink in ipairs(twinks)do twink.isTwink=true;table.insert(grouped,twink)end end
        end
    end
    return grouped
end

function GuildRoster:RenderRows(members)
    for _, row in ipairs(self.rows) do row:Hide() end
    for index, member in ipairs(members) do
        local row = self.rows[index]
        if not row then row = self:CreateRow(self.scrollContent); self.rows[index] = row end
        row:ClearAllPoints(); row:SetPoint("TOPLEFT", self.scrollContent, "TOPLEFT", 0, -((index - 1) * 22)); row:SetPoint("TOPRIGHT", self.scrollContent, "TOPRIGHT", 0, -((index - 1) * 22))
        local classColor = RAID_CLASS_COLORS[member.classFileName] or NORMAL_FONT_COLOR
        local state, stateColor = "offline", { 0.55, 0.55, 0.55 }
        if member.online then
            state, stateColor = "online", { 0.25, 0.9, 0.25 }
            if member.status == "AFK" or member.status == 1 then state, stateColor = "afk", { 1, 0.82, 0.2 } end
            if member.status == "DND" or member.status == 2 then state, stateColor = "dnd", { 0.95, 0.2, 0.2 } end
        end
        local characterName = member.name and member.name:match("^([^-]+)") or L["UNKNOWN_VALUE"]
        local realm = member.name and member.name:match("%-([^%-]+)$") or L["UNKNOWN_VALUE"]
        row.indicator:SetTexture(statusTextures[state])
        local coords=CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[member.classFileName];if coords then row.classIcon:SetTexCoord(unpack(coords));row.classIcon:Show()else row.classIcon:Hide()end
        row.indicator:Show()
        row.twinkArrow:SetShown(member.isTwink)
        row.name:ClearAllPoints()
        row.name:SetPoint("LEFT", row, "LEFT", member.isTwink and 64 or 46, 0)
        row.name:SetPoint("RIGHT", row, "RIGHT", -560, 0)
        setColumnText(row.name, characterName, { classColor.r, classColor.g, classColor.b })
        setColumnText(row.rank, member.rank, { 1, 1, 1 }); setColumnText(row.level, member.level and tostring(member.level), { 1, 1, 1 })
        setColumnText(row.realm, realm, { 1, 1, 1 }); setColumnText(row.zone, member.zone, { 1, 1, 1 })
        setColumnText(row.status, member.online and L[string.upper(state)] or self:FormatOfflineDuration(member.status), stateColor)
        setColumnText(row.version, member.addonVersion or "|cff888888–|r", member.addonVersion and { 1, 1, 1 } or { .55, .55, .55 })
        row:SetScript("OnMouseUp", function(_, button)
            if button == "RightButton" then GuildRoster:ShowGuildMemberMenu(row, member) elseif button == "LeftButton" then GuildRoster:ShowCharacter(member) end
        end)
        row:SetScript("OnEnter",function(frame)frame.highlight:Show();GameTooltip:SetOwner(frame,"ANCHOR_RIGHT");GameTooltip:AddLine(member.name or"-");GameTooltip:AddDoubleLine("Item level",string.format("%.1f",member.itemLevel or 0));GameTooltip:AddDoubleLine("Mythic+",string.format("%.1f",member.mythicScore or 0));GameTooltip:AddDoubleLine("Holy Storm",member.addonVersion or"not installed / unknown");GameTooltip:AddDoubleLine("Zone",member.online and(member.zone or"-")or GuildRoster:FormatOfflineDuration(member.status));GameTooltip:Show()end);row:SetScript("OnLeave",function(frame)frame.highlight:Hide();GameTooltip:Hide()end)
        row:Show()
    end
    self.scrollContent:SetHeight(math.max(1, #members * 22))
end
end)
