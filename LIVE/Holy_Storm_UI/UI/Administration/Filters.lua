local HolyStorm=LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local L=LibStub("AceLocale-3.0"):GetLocale("Holy_Storm_Policy")
local Page=HolyStorm:RegisterRequiredModule("FiltersUI")
local Filters,State,Engine=HolyStorm.FilterManager,HolyStorm.PolicyState,HolyStorm.PermissionEngine

HolyStorm:ApplyModuleMetadata(Page,{displayName=L["FILTERS_TITLE"],internalName="filtersUI",version="1.3.0",category="required",description=L["FILTERS_DESC"],permissions={"filters-edit"},dependencies={"core","ui"},enabledByDefault=true})

local function status(message)HolyStorm.Events:Emit("HS_UI_STATUS_REQUESTED",message)end
local function referencesText(references)
    local lines={}
    for _,reference in ipairs(references or{})do lines[#lines+1]=string.format(L["REFERENCE_FORMAT"],L["REFERENCE_"..tostring(reference.kind):upper()]or reference.kind,reference.name or reference.id,reference.provider or L["UNKNOWN"])end
    return #lines>0 and table.concat(lines,"\n")or L["NO_REFERENCES"]
end

function Page:Root()return self.scope=="template"and Filters:GetFilterTemplates()or Filters:GetFilters(self.scope)end

function Page:Items()
    local out={};local query=string.lower(self.search and self.search:GetText()or"")
    for _,filter in pairs(self:Root())do
        local summary=Filters:GetObjectSummary("filters",filter.id,self.scope)or{}
        local haystack=string.lower(table.concat({filter.name or"",filter.id or"",filter.category or"",table.concat(summary.providers or{}," ")}," "))
        if query==""or haystack:find(query,1,true)then filter._summary=summary;filter.tooltip=string.format(L["FILTER_OVERVIEW_TOOLTIP"],filter.id,filter.category or L["NONE"],filter.creator or L["NONE"],HolyStorm.PolicyUI:FormatTime(filter.modifiedAt or filter.updatedAt),summary.references or 0,L[summary.status]or summary.status or L["AVAILABLE"]);out[#out+1]=filter end
    end
    table.sort(out,function(a,b)return tostring(a.name)<tostring(b.name)end)
    return out
end

function Page:Select(filter)
    self.selectedId=filter and filter.id
    self.isNew=filter and self:Root()[filter.id]==nil or false
    self.draft=filter and HolyStorm.Utils.DeepCopy(filter)or nil
    if self.list then self.list.selected=filter;self.list:SetSelection(filter and filter.id)end
    if self.draft then self.draft._summary,self.draft.tooltip=nil,nil end
    self.baseRevision=State:GetPermissionStateStatus().revisionID
    if not self.draft then self.emptyDetail:SetText(L["NO_SELECTION"]);self.name:SetText("");self.description:SetText("");self.category:SetText("");self.builder:Hide();self.meta:SetText("");self.usage:SetText("");self.testText:SetText("");return end
    self.emptyDetail:SetText("")
    self.builder:Show()
    self.name:SetText(self.draft.name or"");self.description:SetText(self.draft.description or"");self.category:SetText(self.draft.category or"")
    self.builder:SetRule(self.draft.root or self.draft.rules)
    self:ShowDetails();self:Test()
end

function Page:ShowDetails()
    if not self.draft then return end
    local summary=Filters:GetObjectSummary("filters",self.draft.id,self.scope)or{}
    self.meta:SetText(string.format(L["FILTER_METADATA_FORMAT"],self.draft.id,self.draft.creator or L["NONE"],HolyStorm.PolicyUI:FormatTime(self.draft.createdAt),HolyStorm.PolicyUI:FormatTime(self.draft.modifiedAt or self.draft.updatedAt),tostring(self.draft.version or 0),L[summary.status or"AVAILABLE"]or summary.status or L["AVAILABLE"]))
    self.usage:SetText(L["REFERENCES"]..":\n"..referencesText(Filters:GetReferences("filters",self.draft.id,self.scope)))
end

function Page:Render()
    if not self.page:IsShown()then return end
    local root=self:Root()
    if self.selectedId and not root[self.selectedId]and not self.isNew then self:Select(nil)end
    local items=self:Items();self.emptyList:SetText(#items==0 and L["EMPTY_FILTERS"]or"")
    self.list:SetItems(items,function(filter)local summary=filter._summary or{};return string.format(L["FILTER_LIST_FORMAT"],filter.name,filter.id,filter.category or L["NONE"],summary.references or 0,L[summary.status]or summary.status or L["AVAILABLE"])end)
    local writable=self.scope~="global"or State:GetPermissionStateStatus().status==State.status.VALID
    local canCreate=Engine:HasPermission(nil,nil,"filters-create")
    local canEdit=Engine:HasPermission(nil,nil,"filters-edit")
    local canDelete=Engine:HasPermission(nil,nil,"filters-delete")
    self.newButton:SetEnabled(writable and canCreate and self.scope~="template")
    self.duplicateButton:SetEnabled(writable and self.draft~=nil and canCreate)
    self.saveButton:SetEnabled(writable and self.draft~=nil and self.scope~="template"and(self.isNew and canCreate or not self.isNew and canEdit))
    self.deleteButton:SetEnabled(writable and self.draft~=nil and self.scope~="template"and not self.isNew and canDelete)
end

function Page:SetScope(scope)
    self.scope=scope;self.selectedId=nil;self.draft=nil
    for key,button in pairs(self.scopeButtons)do button:SetEnabled(key~=scope)end
    self:Select(nil);self:Render()
end

function Page:Save()
    if not self.draft then return end
    local valid,reason=self.builder:Validate();if not valid then status(string.format(L["INVALID_EXPRESSION"],HolyStorm.PolicyUI:ErrorText(reason)));return end
    if self.scope=="global"and self.baseRevision~=State:GetPermissionStateStatus().revisionID then status(L["STALE_EDITOR"]);return end
    self.draft.name=self.name:GetText();self.draft.description=self.description:GetText();self.draft.category=self.category:GetText();self.draft.root=self.builder:GetRule()
    local ok,result=Filters:SaveFilter(self.draft,self.scope)
    if ok then self:Select(result);self:Render();status(L["SAVED"])else status(string.format(L["INVALID"],HolyStorm.PolicyUI:ErrorText(result)))end
end

function Page:Duplicate()
    if not self.draft then return end
    if self.scope=="template"or self.isNew then
        local duplicate=HolyStorm.Utils.DeepCopy(self.draft);duplicate.id=HolyStorm.PolicyUI:NewId("filter");duplicate.name=(duplicate.name or L["NEW"]).." "..L["COPY_SUFFIX"];duplicate.creator,duplicate.createdAt,duplicate.modifiedBy,duplicate.modifiedAt,duplicate.version=nil,nil,nil,nil,nil
        self:SetScope("local");self:Select(duplicate);self:Render();return
    end
    local ok,result=Filters:DuplicateFilter(self.draft.id,self.scope,{name=(self.draft.name or L["NEW"]).." "..L["COPY_SUFFIX"]})
    if ok then self:Select(result);self:Render();status(L["SAVED"])else status(HolyStorm.PolicyUI:ErrorText(result))end
end

function Page:Delete()
    if not self.draft then return end
    local references=Filters:GetReferences("filters",self.draft.id,self.scope)
    if#references>0 then status(L["FILTER_IN_USE"].."\n"..referencesText(references));return end
    StaticPopupDialogs.HOLYSTORM_FILTER_DELETE={text=string.format(L["CONFIRM_FILTER_DELETE"],self.draft.name),button1=L["DELETE"],button2=L["CANCEL"],OnAccept=function()local ok,reason=Filters:DeleteFilter(Page.draft.id,Page.scope);if ok then Page:Select(nil);Page:Render()else status(HolyStorm.PolicyUI:ErrorText(reason))end end,timeout=0,whileDead=true,hideOnEscape=true}
    StaticPopup_Show("HOLYSTORM_FILTER_DELETE")
end

function Page:Test()
    if not self.draft then return end
    local filter=HolyStorm.Utils.DeepCopy(self.draft);filter.root=self.builder:GetRule()
    local guid=self.testCharacter and self.testCharacter:GetValue()
    if guid then
        local ok,preview=Filters:Preview("filters",filter,{guid=guid},self.scope)
        if not ok then self.testText:SetText(HolyStorm.PolicyUI:ErrorText(preview));return end
        self.testText:SetText((L["RESULT_"..preview.status]or preview.status).."\n"..HolyStorm.PolicyUI:FlattenTrace(preview.trace));return
    end
    local guild=HolyStorm.Data.GuildStore:GetCurrent();local count,total,unknown=0,0,0
    for characterId,member in pairs(guild and guild.roster or{})do total=total+1;local ok,preview=Filters:Preview("filters",filter,{guid=characterId,member=member},self.scope);if ok and preview.status==HolyStorm.Rules.Result.PASS then count=count+1 elseif ok and preview.status==HolyStorm.Rules.Result.UNKNOWN then unknown=unknown+1 end end
    self.testText:SetText(total==0 and L["EMPTY_PREVIEW_ENTITIES"]or string.format(L["MATCHES_WITH_UNKNOWN"],count,total,unknown))
end

function Page:OnInitialize()
    HolyStorm.Administration:RegisterSection({id="filters",category="filters",displayName=L["FILTERS_TITLE"],displayNameKey="FILTERS_TITLE",description=L["FILTERS_DESC"],descriptionKey="FILTERS_DESC",order=10,requiredPermission={"filters-create","filters-edit","filters-delete"},owner="Core",build=function(parent)return Page:Build(parent)end,refresh=function()Page:Render()end,events={"HS_FILTER_UPDATED","HS_FILTER_DELETED","HS_FILTER_REFERENCE_PROVIDER_CHANGED","HS_GROUP_UPDATED","HS_GROUP_DELETED","HS_RULE_FIELD_REGISTERED","HS_RULE_FIELD_UNREGISTERED","HS_MODULE_AVAILABILITY_CHANGED","HS_CHARACTER_UPDATED","HS_ROSTER_UPDATED","HS_PERMISSIONS_STATE_UPDATED"},icon="Interface\\Icons\\INV_Misc_Spyglass_02"})
end

function Page:Build(parent)
    local C=HolyStorm.UI.Components;local page=CreateFrame("Frame",nil,parent);self.page=page
    local root=C:CreateColumn(page,{frame=page,gap=8,padding={left=12,right=12,top=8,bottom=10}});root:Add(C:CreateText(page,{text=L["FILTERS_TITLE"],font="GameFontHighlightLarge"}),{height=26})
    local scopeRow=C:CreateRow(page,{gap=6});self.scopeButtons={};for _,item in ipairs({{"local",L["LOCAL_FILTERS"]},{"global",L["GLOBAL_FILTERS"]},{"template",L["TEMPLATES"]}})do local scope=item[1];local button=HolyStorm.PolicyUI:Button(scopeRow.frame,item[2],125,function()Page:SetScope(scope)end);self.scopeButtons[scope]=button;scopeRow:Add(button,{width=125})end;root:Add(scopeRow,{height=24})
    local body=C:CreateRow(page,{gap=12});root:Add(body,{weight=1,minHeight=440});local sidebar=C:CreateColumn(body.frame,{gap=6});body:Add(sidebar,{width=220,minWidth=190})
    self.search=HolyStorm.PolicyUI:Edit(sidebar.frame,190,function()Page:Render()end);sidebar:Add(self.search,{height=24});self.emptyList=HolyStorm.PolicyUI:Label(sidebar.frame,"");sidebar:Add(self.emptyList,{height=18});self.list=HolyStorm.PolicyUI:CreateList(sidebar.frame,function(filter)Page:Select(filter)end);sidebar:Add(self.list,{weight=1,minHeight=260})
    local listActions=C:CreateRow(sidebar.frame,{gap=4});self.newButton=HolyStorm.PolicyUI:Button(listActions.frame,L["NEW"],62,function()Page:Select({id=HolyStorm.PolicyUI:NewId("filter"),name=L["NEW"],description="",category="",root={logic="AND",children={HolyStorm.PolicyUI:DefaultCondition()}}})end);self.duplicateButton=HolyStorm.PolicyUI:Button(listActions.frame,L["DUPLICATE"],90,function()Page:Duplicate()end);self.deleteButton=HolyStorm.PolicyUI:Button(listActions.frame,L["DELETE"],70,function()Page:Delete()end);listActions:Add(self.newButton,{weight=1,minWidth=52});listActions:Add(self.duplicateButton,{weight=1,minWidth=70});listActions:Add(self.deleteButton,{weight=1,minWidth=58});sidebar:Add(listActions,{height=24})
    local detail=C:CreateColumn(body.frame,{gap=5});body:Add(detail,{weight=1,minWidth=420});local form=C:CreateRow(detail.frame,{gap=8});local function field(label,width,weight)local column=C:CreateColumn(form.frame,{gap=2});column:Add(C:CreateText(column.frame,{text=label,font="GameFontNormalSmall"}),{height=16});local edit=HolyStorm.PolicyUI:Edit(column.frame,width);column:Add(edit,{height=22});form:Add(column,{weight=weight or 1,minWidth=90});return edit end;self.name=field(L["NAME"],220,2);self.category=field(L["CATEGORY"],140,1);self.description=field(L["DESCRIPTION"],250,2);detail:Add(form,{height=42})
    self.emptyDetail=HolyStorm.PolicyUI:Label(detail.frame,L["NO_SELECTION"]);detail:Add(self.emptyDetail,{height=18});self.builder=HolyStorm.PolicyUI:CreateRuleBuilder(detail.frame);detail:Add(self.builder,{weight=1,minHeight=170});self.meta=HolyStorm.PolicyUI:Label(detail.frame,"");self.meta:SetWordWrap(true);detail:Add(self.meta,{height=34});self.usageScroll,self.usage=HolyStorm.PolicyUI:CreateTextPanel(detail.frame);detail:Add(self.usageScroll,{height=58})
    local preview=C:CreateRow(detail.frame,{gap=6});preview:Add(C:CreateText(preview.frame,{text=L["CHARACTER"],font="GameFontNormalSmall"}),{width=90});self.testCharacter=HolyStorm.PolicyUI:CreateSelector(preview.frame,220,function()return HolyStorm.PolicyUI:CharacterItems()end,function()Page:Test()end);preview:Add(self.testCharacter,{weight=1,minWidth=170});detail:Add(preview,{height=24});self.testScroll,self.testText=HolyStorm.PolicyUI:CreateTextPanel(detail.frame);detail:Add(self.testScroll,{height=100})
    local actions=C:CreateRow(detail.frame,{gap=6});self.saveButton=HolyStorm.PolicyUI:Button(actions.frame,L["SAVE"],90,function()Page:Save()end);local discard=HolyStorm.PolicyUI:Button(actions.frame,L["DISCARD"],90,function()Page:Select(Page.selectedId and Page:Root()[Page.selectedId]);status(L["DISCARDED"])end);local test=HolyStorm.PolicyUI:Button(actions.frame,L["TEST"],90,function()Page:Test()end);actions:Add(self.saveButton,{width=90});actions:Add(discard,{width=90});actions:Add(test,{width=90});detail:Add(actions,{height=24})
    self.scope="local";self.scopeButtons["local"]:SetEnabled(false);self:Select(nil);root:Relayout();return page
end
