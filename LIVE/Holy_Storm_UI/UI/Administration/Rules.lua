local HolyStorm=LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local L=LibStub("AceLocale-3.0"):GetLocale("Holy_Storm_Policy")
local Page=HolyStorm:RegisterRequiredModule("RulesUI")
local Filters,State,Engine=HolyStorm.FilterManager,HolyStorm.PolicyState,HolyStorm.PermissionEngine

HolyStorm:ApplyModuleMetadata(Page,{displayName=L["RULES_TITLE"],internalName="rulesUI",version="1.3.0",category="required",description=L["RULES_DESC"],permissions={"rules-manage"},dependencies={"core","ui"},enabledByDefault=true})
local function status(message)HolyStorm.Events:Emit("HS_UI_STATUS_REQUESTED",message)end

function Page:Items()
    local out={};local query=string.lower(self.search and self.search:GetText()or"")
    for _,rule in pairs(Filters:GetRules(self.scope))do local summary=Filters:GetObjectSummary("rules",rule.id,self.scope)or{};local haystack=string.lower(table.concat({rule.name or"",rule.id or"",rule.category or"",table.concat(summary.providers or{}," ")}," "));if query==""or haystack:find(query,1,true)then rule._summary=summary;rule.tooltip=string.format(L["RULE_OVERVIEW_TOOLTIP"],rule.id,rule.category or L["NONE"],rule.creator or L["NONE"],HolyStorm.PolicyUI:FormatTime(rule.modifiedAt),rule.version or 0,L[summary.status]or summary.status or L["AVAILABLE"]);out[#out+1]=rule end end
    table.sort(out,function(a,b)return tostring(a.name)<tostring(b.name)end);return out
end

function Page:Select(rule)
    self.selectedId=rule and rule.id;self.isNew=rule and Filters:GetRules(self.scope)[rule.id]==nil or false;self.draft=rule and HolyStorm.Utils.DeepCopy(rule)or nil;if self.draft then self.draft._summary,self.draft.tooltip=nil,nil end;self.baseRevision=State:GetPermissionStateStatus().revisionID
    if self.list then self.list.selected=rule;self.list:SetSelection(rule and rule.id)end
    if not self.draft then self.emptyDetail:SetText(L["NO_SELECTION"]);self.name:SetText("");self.description:SetText("");self.category:SetText("");self.builder:Hide();self.meta:SetText("");self.usage:SetText("");self.testText:SetText("");return end
    self.emptyDetail:SetText("");self.builder:Show();self.name:SetText(self.draft.name or"");self.description:SetText(self.draft.description or"");self.category:SetText(self.draft.category or"");self.builder:SetRule(self.draft.root or self.draft.rules);self:ShowDetails();self:Test()
end

function Page:ShowDetails()
    if not self.draft then return end
    local summary=Filters:GetObjectSummary("rules",self.draft.id,self.scope)or{};self.meta:SetText(string.format(L["RULE_METADATA_FORMAT"],self.draft.id,self.draft.creator or L["NONE"],HolyStorm.PolicyUI:FormatTime(self.draft.createdAt),HolyStorm.PolicyUI:FormatTime(self.draft.modifiedAt),tostring(self.draft.version or 0),L[summary.status or"AVAILABLE"]or summary.status or L["AVAILABLE"]))
    local references=Filters:GetReferences("rules",self.draft.id,self.scope);local lines={L["REFERENCES"]..":"};for _,reference in ipairs(references)do lines[#lines+1]=string.format(L["REFERENCE_FORMAT"],L["REFERENCE_"..tostring(reference.kind):upper()]or reference.kind,reference.name or reference.id,reference.provider or L["UNKNOWN"])end;if#references==0 then lines[#lines+1]=L["NO_REFERENCES"]end;self.usage:SetText(table.concat(lines,"\n"))
end

function Page:ShowFieldDiagnostics()
    local lines={L["FIELD_PROVIDERS"]..":"};local count=0
    for _,field in ipairs(HolyStorm.Rules:GetFieldDiagnostics(Engine:BuildContext(nil,UnitGUID("player"))))do count=count+1;lines[#lines+1]=string.format(L["FIELD_DIAGNOSTIC_FORMAT"],field.name or(field.nameKey and L[field.nameKey])or field.id,field.id,field.provider or field.owner,field.module,field.type,table.concat(field.operators or{},", "),field.available and L["AVAILABLE"]or L["UNAVAILABLE"] )end
    if count==0 then lines[#lines+1]=L["EMPTY_FIELDS"]end
    self.fields:SetText(table.concat(lines,"\n"))
end

function Page:Render()
    if not self.page:IsShown()then return end
    local root=Filters:GetRules(self.scope);if self.selectedId and not root[self.selectedId]and not self.isNew then self:Select(nil)end
    local items=self:Items();self.emptyList:SetText(#items==0 and L["EMPTY_RULES"]or"");self.list:SetItems(items,function(rule)local summary=rule._summary or{};return string.format(L["RULE_LIST_FORMAT"],rule.name,rule.id,rule.category or L["NONE"],rule.version or 0,L[summary.status]or summary.status or L["AVAILABLE"])end)
    local writable=self.scope~="global"or State:GetPermissionStateStatus().status==State.status.VALID;local allowed=Engine:HasPermission(nil,nil,"rules-manage")
    self.newButton:SetEnabled(writable and allowed);self.duplicateButton:SetEnabled(writable and allowed and self.draft~=nil);self.saveButton:SetEnabled(writable and allowed and self.draft~=nil);self.deleteButton:SetEnabled(writable and allowed and self.draft~=nil and not self.isNew);self:ShowFieldDiagnostics()
end

function Page:Save()
    if not self.draft then return end
    local valid,reason=self.builder:Validate();if not valid then status(string.format(L["INVALID_EXPRESSION"],HolyStorm.PolicyUI:ErrorText(reason)));return end
    if self.scope=="global"and self.baseRevision~=State:GetPermissionStateStatus().revisionID then status(L["STALE_EDITOR"]);return end
    self.draft.name=self.name:GetText();self.draft.description=self.description:GetText();self.draft.category=self.category:GetText();self.draft.root=self.builder:GetRule()
    local ok,result=Filters:SaveRule(self.draft,self.scope);if ok then self:Select(result);self:Render();status(L["SAVED"])else status(string.format(L["INVALID"],HolyStorm.PolicyUI:ErrorText(result)))end
end

function Page:Duplicate()
    if not self.draft then return end
    if self.isNew then local duplicate=HolyStorm.Utils.DeepCopy(self.draft);duplicate.id=HolyStorm.PolicyUI:NewId("rule");duplicate.name=(duplicate.name or L["NEW"]).." "..L["COPY_SUFFIX"];self:Select(duplicate);self:Render();return end
    local ok,result=Filters:DuplicateRule(self.draft.id,self.scope,{name=(self.draft.name or L["NEW"]).." "..L["COPY_SUFFIX"]});if ok then self:Select(result);self:Render();status(L["SAVED"])else status(HolyStorm.PolicyUI:ErrorText(result))end
end

function Page:Delete()
    if not self.draft then return end
    local references=Filters:GetReferences("rules",self.draft.id,self.scope);if#references>0 then status(L["RULE_IN_USE"]);return end
    StaticPopupDialogs.HOLYSTORM_RULE_DELETE={text=string.format(L["CONFIRM_RULE_DELETE"],self.draft.name),button1=L["DELETE"],button2=L["CANCEL"],OnAccept=function()local ok,reason=Filters:DeleteRule(Page.draft.id,Page.scope);if ok then Page:Select(nil);Page:Render()else status(HolyStorm.PolicyUI:ErrorText(reason))end end,timeout=0,whileDead=true,hideOnEscape=true};StaticPopup_Show("HOLYSTORM_RULE_DELETE")
end

function Page:Test()
    if not self.draft then return end
    local rule=HolyStorm.Utils.DeepCopy(self.draft);rule.root=self.builder:GetRule();local guid=self.testCharacter and self.testCharacter:GetValue()
    if not guid then self.testText:SetText(#HolyStorm.PolicyUI:CharacterItems()==0 and L["EMPTY_PREVIEW_ENTITIES"]or L["SELECT_PREVIEW_ENTITY"]);return end
    local ok,preview=Filters:Preview("rules",rule,{guid=guid},self.scope);if not ok then self.testText:SetText(HolyStorm.PolicyUI:ErrorText(preview));return end
    self.testText:SetText((L["RESULT_"..preview.status]or preview.status).."\n"..HolyStorm.PolicyUI:FlattenTrace(preview.trace))
end

function Page:SetScope(scope)self.scope=scope;self.selectedId=nil;self.draft=nil;self.localButton:SetEnabled(scope~="local");self.globalButton:SetEnabled(scope~="global");self:Select(nil);self:Render()end

function Page:OnInitialize()
    HolyStorm.Administration:RegisterSection({id="rules",category="rules",displayName=L["RULES_TITLE"],displayNameKey="RULES_TITLE",description=L["RULES_DESC"],descriptionKey="RULES_DESC",order=10,requiredPermission="rules-manage",owner="Core",build=function(parent)return Page:Build(parent)end,refresh=function()Page:Render()end,events={"HS_RULE_UPDATED","HS_RULE_DELETED","HS_FILTER_REFERENCE_PROVIDER_CHANGED","HS_GROUP_UPDATED","HS_GROUP_DELETED","HS_RULE_FIELD_REGISTERED","HS_RULE_FIELD_UNREGISTERED","HS_RULE_OPERATOR_REGISTERED","HS_MODULE_AVAILABILITY_CHANGED","HS_CHARACTER_UPDATED","HS_ROSTER_UPDATED","HS_PERMISSIONS_STATE_UPDATED"},icon="Interface\\Icons\\INV_Inscription_Tradeskill01"})
end

function Page:Build(parent)
    local C=HolyStorm.UI.Components;local page=CreateFrame("Frame",nil,parent);self.page=page
    local root=C:CreateColumn(page,{frame=page,gap=8,padding={left=12,right=12,top=8,bottom=10}})
    root:Add(C:CreateText(page,{text=L["RULES_TITLE"],font="GameFontHighlightLarge"}),{height=26})
    local scopeRow=C:CreateRow(page,{gap=6});self.localButton=HolyStorm.PolicyUI:Button(scopeRow.frame,L["LOCAL_RULES"],120,function()Page:SetScope("local")end);self.globalButton=HolyStorm.PolicyUI:Button(scopeRow.frame,L["GLOBAL_RULES"],120,function()Page:SetScope("global")end);scopeRow:Add(self.localButton,{width=120});scopeRow:Add(self.globalButton,{width=120});root:Add(scopeRow,{height=24})
    local body=C:CreateRow(page,{gap=12});root:Add(body,{weight=1,minHeight=460})
    local sidebar=C:CreateColumn(body.frame,{gap=6});body:Add(sidebar,{width=220,minWidth=190})
    self.search=HolyStorm.PolicyUI:Edit(sidebar.frame,190,function()Page:Render()end);sidebar:Add(self.search,{height=24})
    self.emptyList=HolyStorm.PolicyUI:Label(sidebar.frame,"");sidebar:Add(self.emptyList,{height=18})
    self.list=HolyStorm.PolicyUI:CreateList(sidebar.frame,function(rule)Page:Select(rule)end);sidebar:Add(self.list,{weight=1,minHeight=260})
    local listActions=C:CreateRow(sidebar.frame,{gap=4});self.newButton=HolyStorm.PolicyUI:Button(listActions.frame,L["NEW"],62,function()Page:Select({id=HolyStorm.PolicyUI:NewId("rule"),name=L["NEW"],description="",category="",root={logic="AND",children={HolyStorm.PolicyUI:DefaultCondition()}}})end);self.duplicateButton=HolyStorm.PolicyUI:Button(listActions.frame,L["DUPLICATE"],90,function()Page:Duplicate()end);self.deleteButton=HolyStorm.PolicyUI:Button(listActions.frame,L["DELETE"],70,function()Page:Delete()end);listActions:Add(self.newButton,{weight=1,minWidth=52});listActions:Add(self.duplicateButton,{weight=1,minWidth=70});listActions:Add(self.deleteButton,{weight=1,minWidth=58});sidebar:Add(listActions,{height=24})
    local detail=C:CreateColumn(body.frame,{gap=5});body:Add(detail,{weight=1,minWidth=420})
    local form=C:CreateRow(detail.frame,{gap=8});local function field(label,width,weight)local column=C:CreateColumn(form.frame,{gap=2});column:Add(C:CreateText(column.frame,{text=label,font="GameFontNormalSmall"}),{height=16});local edit=HolyStorm.PolicyUI:Edit(column.frame,width);column:Add(edit,{height=22});form:Add(column,{weight=weight or 1,minWidth=90});return edit end;self.name=field(L["NAME"],220,2);self.category=field(L["CATEGORY"],140,1);self.description=field(L["DESCRIPTION"],250,2);detail:Add(form,{height=42})
    self.emptyDetail=HolyStorm.PolicyUI:Label(detail.frame,L["NO_SELECTION"]);detail:Add(self.emptyDetail,{height=18})
    self.builder=HolyStorm.PolicyUI:CreateRuleBuilder(detail.frame);detail:Add(self.builder,{weight=1,minHeight=150})
    self.meta=HolyStorm.PolicyUI:Label(detail.frame,"");self.meta:SetWordWrap(true);detail:Add(self.meta,{height=34})
    self.usageScroll,self.usage=HolyStorm.PolicyUI:CreateTextPanel(detail.frame);detail:Add(self.usageScroll,{height=50})
    self.fieldsScroll,self.fields=HolyStorm.PolicyUI:CreateTextPanel(detail.frame);detail:Add(self.fieldsScroll,{height=76})
    local preview=C:CreateRow(detail.frame,{gap=6});preview:Add(C:CreateText(preview.frame,{text=L["CHARACTER"],font="GameFontNormalSmall"}),{width=90});self.testCharacter=HolyStorm.PolicyUI:CreateSelector(preview.frame,200,function()return HolyStorm.PolicyUI:CharacterItems()end,function()Page:Test()end);preview:Add(self.testCharacter,{weight=1,minWidth=160});detail:Add(preview,{height=24})
    self.testScroll,self.testText=HolyStorm.PolicyUI:CreateTextPanel(detail.frame);detail:Add(self.testScroll,{height=58})
    local actions=C:CreateRow(detail.frame,{gap=6});self.saveButton=HolyStorm.PolicyUI:Button(actions.frame,L["SAVE"],90,function()Page:Save()end);local discard=HolyStorm.PolicyUI:Button(actions.frame,L["DISCARD"],90,function()Page:Select(Page.selectedId and Filters:GetRules(Page.scope)[Page.selectedId]);status(L["DISCARDED"])end);local test=HolyStorm.PolicyUI:Button(actions.frame,L["TEST"],90,function()Page:Test()end);actions:Add(self.saveButton,{width=90});actions:Add(discard,{width=90});actions:Add(test,{width=90});detail:Add(actions,{height=24})
    self.scope="local";self.localButton:SetEnabled(false);self:Select(nil);root:Relayout();return page
end
