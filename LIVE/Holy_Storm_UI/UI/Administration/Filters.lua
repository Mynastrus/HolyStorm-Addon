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
    local UI=HolyStorm:GetModule("UI",true);local page=CreateFrame("Frame",nil,UI.content);self.page=page
    local title=HolyStorm.PolicyUI:Label(page,L["FILTERS_TITLE"],"GameFontHighlightLarge");title:SetPoint("TOPLEFT",14,-12)
    self.scopeButtons={};for index,item in ipairs({{"local",L["LOCAL_FILTERS"]},{"global",L["GLOBAL_FILTERS"]},{"template",L["TEMPLATES"]}})do local scope=item[1];local button=HolyStorm.PolicyUI:Button(page,item[2],125,function()Page:SetScope(scope)end);button:SetPoint("TOPLEFT",14+(index-1)*129,-40);self.scopeButtons[scope]=button end
    self.search=HolyStorm.PolicyUI:Edit(page,190,function()Page:Render()end);self.search:SetPoint("TOPLEFT",14,-72)
    self.list=HolyStorm.PolicyUI:CreateList(page,function(filter)Page:Select(filter)end);self.list:SetPoint("TOPLEFT",14,-100);self.list:SetSize(200,420)
    self.emptyList=HolyStorm.PolicyUI:Label(page,"");self.emptyList:SetPoint("TOPLEFT",14,-108);self.emptyList:SetWidth(190)
    self.newButton=HolyStorm.PolicyUI:Button(page,L["NEW"],62,function()Page:Select({id=HolyStorm.PolicyUI:NewId("filter"),name=L["NEW"],description="",category="",root={logic="AND",children={HolyStorm.PolicyUI:DefaultCondition()}}})end);self.newButton:SetPoint("BOTTOMLEFT",14,18)
    self.duplicateButton=HolyStorm.PolicyUI:Button(page,L["DUPLICATE"],90,function()Page:Duplicate()end);self.duplicateButton:SetPoint("LEFT",self.newButton,"RIGHT",4,0)
    self.deleteButton=HolyStorm.PolicyUI:Button(page,L["DELETE"],70,function()Page:Delete()end);self.deleteButton:SetPoint("LEFT",self.duplicateButton,"RIGHT",4,0)
    local nameLabel=HolyStorm.PolicyUI:Label(page,L["NAME"]);nameLabel:SetPoint("TOPLEFT",225,-42);self.name=HolyStorm.PolicyUI:Edit(page,220);self.name:SetPoint("TOPLEFT",225,-60)
    local categoryLabel=HolyStorm.PolicyUI:Label(page,L["CATEGORY"]);categoryLabel:SetPoint("LEFT",self.name,"RIGHT",12,18);self.category=HolyStorm.PolicyUI:Edit(page,140);self.category:SetPoint("LEFT",self.name,"RIGHT",12,0)
    local descriptionLabel=HolyStorm.PolicyUI:Label(page,L["DESCRIPTION"]);descriptionLabel:SetPoint("LEFT",self.category,"RIGHT",12,18);self.description=HolyStorm.PolicyUI:Edit(page,250);self.description:SetPoint("LEFT",self.category,"RIGHT",12,0)
    self.builder=HolyStorm.PolicyUI:CreateRuleBuilder(page);self.builder:SetPoint("TOPLEFT",225,-92);self.builder:SetPoint("BOTTOMRIGHT",-14,300)
    self.emptyDetail=HolyStorm.PolicyUI:Label(page,L["NO_SELECTION"]);self.emptyDetail:SetPoint("TOPLEFT",225,-104)
    self.meta=HolyStorm.PolicyUI:Label(page,"");self.meta:SetPoint("BOTTOMLEFT",225,265);self.meta:SetPoint("RIGHT",-14,0)
    self.usageScroll,self.usage=HolyStorm.PolicyUI:CreateTextPanel(page);self.usageScroll:SetPoint("BOTTOMLEFT",225,205);self.usageScroll:SetPoint("RIGHT",-14,0);self.usageScroll:SetHeight(50)
    self.testCharacter=HolyStorm.PolicyUI:CreateSelector(page,220,function()return HolyStorm.PolicyUI:CharacterItems()end,function()Page:Test()end);self.testCharacter:SetPoint("BOTTOMLEFT",410,170)
    self.testScroll,self.testText=HolyStorm.PolicyUI:CreateTextPanel(page);self.testScroll:SetPoint("BOTTOMLEFT",225,48);self.testScroll:SetPoint("RIGHT",-14,0);self.testScroll:SetHeight(115)
    self.saveButton=HolyStorm.PolicyUI:Button(page,L["SAVE"],90,function()Page:Save()end);self.saveButton:SetPoint("BOTTOMLEFT",225,18)
    local discard=HolyStorm.PolicyUI:Button(page,L["DISCARD"],90,function()Page:Select(Page.selectedId and Page:Root()[Page.selectedId]);status(L["DISCARDED"])end);discard:SetPoint("LEFT",self.saveButton,"RIGHT",5,0)
    local test=HolyStorm.PolicyUI:Button(page,L["TEST"],90,function()Page:Test()end);test:SetPoint("LEFT",discard,"RIGHT",5,0)
    self.scope="local";self.scopeButtons["local"]:SetEnabled(false);self:Select(nil)
    HolyStorm.Administration:RegisterSection({id="filters",category="filters",displayName=L["FILTERS_TITLE"],displayNameKey="FILTERS_TITLE",description=L["FILTERS_DESC"],descriptionKey="FILTERS_DESC",order=10,requiredPermission={"filters-create","filters-edit","filters-delete"},owner="Core",page=page,refresh=function()Page:Render()end,events={"HS_FILTER_UPDATED","HS_FILTER_DELETED","HS_FILTER_REFERENCE_PROVIDER_CHANGED","HS_GROUP_UPDATED","HS_GROUP_DELETED","HS_RULE_FIELD_REGISTERED","HS_RULE_FIELD_UNREGISTERED","HS_MODULE_AVAILABILITY_CHANGED","HS_CHARACTER_UPDATED","HS_ROSTER_UPDATED","HS_PERMISSIONS_STATE_UPDATED"},icon="Interface\\Icons\\INV_Misc_Spyglass_02"})
end
