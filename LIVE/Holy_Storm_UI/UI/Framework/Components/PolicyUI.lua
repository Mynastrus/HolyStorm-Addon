local addonVersion="1.2.0"
local HolyStorm=LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local L=LibStub("AceLocale-3.0"):GetLocale("Holy_Storm_Policy")
local UI={version=addonVersion}
local Components=HolyStorm.UIComponents

local function copy(value)return HolyStorm.Utils.DeepCopy(value)end
local function listText(value)
    if type(value)~="table"then return tostring(value==nil and""or value)end
    local values={};for _,item in ipairs(value)do values[#values+1]=tostring(item)end
    return table.concat(values,",")
end
local function parseList(text)
    local result={}
    for value in tostring(text or""):gmatch("[^,]+")do result[#result+1]=value:match("^%s*(.-)%s*$")end
    return result
end
local function operatorNeedsValue(operator)
    local definition=HolyStorm.Rules:GetOperator(operator)
    return not definition or definition.requiresValue~=false
end

function UI:Label(parent,text,template)
    return Components:CreateText(parent,{text=text,font=template or"GameFontHighlightSmall",align="LEFT"}).text
end

function UI:Button(parent,text,width,callback)
    return Components:CreateButton(parent,{text=text,width=width or 100,height=23,onClick=callback}).button
end

function UI:Edit(parent,width,onChanged)
    return Components:CreateEditBox(parent,{width=width or 180,height=22,onChanged=onChanged}).edit
end

function UI:NewId(prefix)return string.format("%s-%08x-%04x",prefix,HolyStorm.Utils.Now()%0xffffffff,math.random(0,0xffff))end
function UI:DisplayGroupName(group)return group and group.nameKey and L[group.nameKey]or group and group.name or"-"end
function UI:FormatTime(value)return value and date("%Y-%m-%d %H:%M",value)or L["NONE"]end
function UI:ErrorText(reason)
    local text=tostring(reason);local code,detail=text:match("^([^:]+):?(.*)$");local template=L["ERROR_"..code]or L["ERROR_"..text]
    if template and detail~=""then local ok,value=pcall(string.format,template,detail);if ok then return value end end
    return template or text
end

function UI:MembershipSourceKey(reason)
    local source=reason and(reason.source or reason.type)or"UNKNOWN"
    if source=="CHARACTER"or source=="ACCOUNT"then source="MANUAL"end
    return"MEMBERSHIP_"..source
end

function UI:DisplayMembershipReason(reason)
    local source=L[self:MembershipSourceKey(reason)]or tostring(reason and(reason.source or reason.type)or L["UNKNOWN"])
    local detail=reason and(reason.name or reason.id)
    return detail~=nil and string.format(L["MEMBERSHIP_SOURCE_FORMAT"],source,tostring(detail))or source
end

function UI:Value(text,fieldType)
    if fieldType=="number"then return tonumber(text)end
    if text=="true"then return true elseif text=="false"then return false end
    return text
end

function UI:FlattenTrace(trace)
    local function status(entry)return L["RESULT_"..tostring(entry.status)]or tostring(entry.status)end
    local lines={}
    for _,entry in ipairs(trace or{})do
        local indent=string.rep("  ",tonumber(entry.depth)or 0)
        if entry.kind=="condition"then
            local field=HolyStorm.Rules:GetField(entry.field)
            local fieldName=field and(field.name or(field.nameKey and L[field.nameKey]))or entry.field or"?"
            local reason=entry.reason and string.format(L["TRACE_REASON"],UI:ErrorText(entry.reason))or""
            lines[#lines+1]=indent..string.format(L["TRACE_CONDITION"],fieldName,tostring(entry.operator or"?"),listText(entry.expected),listText(entry.actual),status(entry),tostring(entry.provider or L["UNAVAILABLE"]),reason)
        elseif entry.kind=="group"then
            lines[#lines+1]=indent..string.format(L["TRACE_GROUP"],L["LOGIC_"..tostring(entry.logic)]or tostring(entry.logic),status(entry))
        else
            lines[#lines+1]=indent..string.format(L["TRACE_ERROR"],UI:ErrorText(entry.error),status(entry))
        end
    end
    return table.concat(lines,"\n")
end

function UI:CreateTextPanel(parent)
    local panel=Components:CreateScrollContainer(parent,{scrollbarInset=24});local scroll,content=panel.scroll,panel.content
    local text=self:Label(content,"","GameFontHighlightSmall");text:SetPoint("TOPLEFT",4,-4);text:SetPoint("RIGHT",-4,0);text:SetJustifyV("TOP");text:SetWordWrap(true)
    local output={fontString=text}
    local function resize()panel:Relayout();local width=math.max(1,content:GetWidth()or 1);text:SetWidth(math.max(1,width-8));content:SetHeight(math.max(scroll:GetHeight()or 1,text:GetStringHeight()+8))end
    function output:SetText(value)text:SetText(value or"");resize();scroll:SetVerticalScroll(0)end
    function output:GetText()return text:GetText()end
    function output:SetTextColor(...)return text:SetTextColor(...)end
    panel.frame:HookScript("OnSizeChanged",resize)
    return panel.frame,output,content
end

function UI:CreateList(parent,onSelect)
    local list
    list=Components:CreateTable(parent,{headerHeight=0,rowHeight=25,columns={{id="label",weight=1,truncate=true}},emptyText=L["NO_SELECTION"],onRowClick=function(item)list.selected=item;list:SetSelection(item and(item.id or item.value));onSelect(item)end,rowTooltip=function(item)return item and item.tooltip end})
    function list:SetItems(items,labeler)
        self.items=items or{};self.labeler=labeler
        for _,item in ipairs(self.items)do item.label=labeler and labeler(item)or tostring(item.name or item.id)end
        self.selection=self.selected and(self.selected.id or self.selected.value);self:SetData(self.items)
    end
    function list:SetPoint(...)return self.frame:SetPoint(...)end;function list:SetSize(...)return self.frame:SetSize(...)end;function list:SetWidth(...)return self.frame:SetWidth(...)end;function list:SetHeight(...)return self.frame:SetHeight(...)end
    function list:Show()return self.frame:Show()end;function list:Hide()return self.frame:Hide()end;function list:IsShown()return self.frame:IsShown()end
    return list
end

function UI:CreateSelector(parent,width,getItems,onSelect)
    local menu=CreateFrame("Frame",nil,parent,"UIDropDownMenuTemplate")
    UIDropDownMenu_SetWidth(menu,width or 180)
    UIDropDownMenu_Initialize(menu,function(_,level)
        if level~=1 then return end
        for _,item in ipairs(getItems()or{})do
            local selected=item;local info=UIDropDownMenu_CreateInfo();info.text=item.label or item.name or item.id;info.disabled=item.disabled;info.checked=item.value==menu.value
            info.func=function()menu.value=selected.value;UIDropDownMenu_SetText(menu,selected.label or selected.name or selected.id);if onSelect then onSelect(selected.value,selected)end end
            UIDropDownMenu_AddButton(info,level)
        end
    end)
    function menu:SetValue(value,label)self.value=value;UIDropDownMenu_SetText(self,label or tostring(value or""))end
    function menu:GetValue()return self.value end
    return menu
end

function UI:CreateMultiSelector(parent,width,getItems,onChanged)
    local menu=CreateFrame("Frame",nil,parent,"UIDropDownMenuTemplate");menu.values={}
    UIDropDownMenu_SetWidth(menu,width or 180)
    local function refreshText()local values={};for value in pairs(menu.values)do values[#values+1]=tostring(value)end;table.sort(values);UIDropDownMenu_SetText(menu,#values>0 and table.concat(values,", ")or L["SELECT_VALUES"])end
    UIDropDownMenu_Initialize(menu,function(_,level)
        if level~=1 then return end
        for _,item in ipairs(getItems()or{})do
            local selected=item;local info=UIDropDownMenu_CreateInfo();info.text=item.label or item.name or tostring(item.value);info.keepShownOnClick=true;info.checked=menu.values[item.value]==true
            info.func=function()if menu.values[selected.value]then menu.values[selected.value]=nil else menu.values[selected.value]=true end;refreshText();if onChanged then onChanged(menu:GetValues())end end
            UIDropDownMenu_AddButton(info,level)
        end
    end)
    function menu:SetValues(values)self.values={};for _,value in ipairs(values or{})do self.values[value]=true end;refreshText()end
    function menu:GetValues()local values={};for value in pairs(self.values)do values[#values+1]=value end;table.sort(values,function(a,b)return tostring(a)<tostring(b)end);return values end
    refreshText();return menu
end

function UI:CreateCheckList(parent,getItems,onToggle)
    local checklist
    checklist=Components:CreateTable(parent,{headerHeight=0,rowHeight=25,columns={{id="checked",width=30,align="CENTER",value=function(item)return item.checked and"|cff20ff20\226\156\147|r"or"\226\150\161"end},{id="label",weight=1,truncate=true,value=function(item)return item.label or item.name or item.id end}},emptyText=L["NO_SELECTION"],onRowClick=function(item)if not item.disabled then onToggle(item.value,item.checked~=true,item);checklist:Refresh()end end,isRowDisabled=function(item)return item.disabled==true end})
    local refreshTable=checklist.Refresh
    function checklist:Refresh()
        if self.refreshingItems then return refreshTable(self)end
        self.items=getItems()or{};self.refreshingItems=true;self:SetData(self.items);self.refreshingItems=false
    end
    function checklist:SetPoint(...)return self.frame:SetPoint(...)end;function checklist:SetSize(...)return self.frame:SetSize(...)end;function checklist:SetWidth(...)return self.frame:SetWidth(...)end;function checklist:SetHeight(...)return self.frame:SetHeight(...)end
    function checklist:Show()return self.frame:Show()end;function checklist:Hide()return self.frame:Hide()end
    return checklist
end

function UI:CharacterItems()
    local out={};local guild=HolyStorm.Data.GuildStore:GetCurrent()
    for guid,member in pairs(guild and guild.roster or{})do out[#out+1]={value=guid,label=member.name or guid,member=member}end
    table.sort(out,function(a,b)return a.label<b.label end);return out
end

function UI:AccountItems()
    local seen,out={},{}
    for _,character in ipairs(self:CharacterItems())do
        local id=HolyStorm.TwinkCore and HolyStorm.TwinkCore:GetAccountUUIDForCharacter(character.value)
        if id and not seen[id]then seen[id]=true;local characters=HolyStorm.TwinkCore:GetCharactersForAccount(id);local main=HolyStorm.TwinkCore:GetAccountMain(id);local record=main and HolyStorm.Data.CharacterStore:Get(main);local label=record and record.name or main or id;out[#out+1]={value=id,label=string.format(L["ACCOUNT_SELECTOR_FORMAT"],label,HolyStorm.Utils.TableCount(characters)),main=main}end
    end
    table.sort(out,function(a,b)return a.label<b.label end);return out
end

function UI:GroupItems(excludeId)
    local out={};for _,group in pairs(HolyStorm.GroupManager:GetGroups())do out[#out+1]={value=group.id,label=self:DisplayGroupName(group),disabled=group.id==excludeId}end
    table.sort(out,function(a,b)return a.label<b.label end);return out
end

function UI:FieldValueItems(definition,node)
    if definition.type=="boolean"then return{{value=true,label=L["YES"]},{value=false,label=L["NO"]}}end
    if definition.type=="character"then return self:CharacterItems()end
    if definition.type=="account"then return self:AccountItems()end
    if definition.type=="enum"or definition.valueProvider or definition.enumProvider then
        local values=definition.values or{};local provider=definition.valueProvider or definition.enumProvider
        if provider then local ok,result=HolyStorm.Utils.SafeCall("rule.values:"..tostring(node and node.field),provider,node,definition);if ok and type(result)=="table"then values=result end end
        local out={}
        for _,value in ipairs(values)do local item=type(value)=="table"and copy(value)or{value=value};item.value=item.value~=nil and item.value or item.id;item.label=item.label or(definition.valueLabels and L[definition.valueLabels[item.value]])or tostring(item.value);out[#out+1]=item end
        return out
    end
    return{}
end

function UI:DefaultCondition(fieldId)
    local fields=HolyStorm.Rules:GetFields();local ids={}
    for id,definition in pairs(fields)do if not definition.hidden then ids[#ids+1]=id end end;table.sort(ids)
    local id=fieldId or ids[1]or"unavailable";local definition=fields[id]or{};local operators=HolyStorm.Rules:GetAllowedOperators(definition);local operator=definition.defaultOperator or operators[1]or"exists";local node={field=id,operator=operator}
    if operatorNeedsValue(operator)then node.value=definition.defaultValue;if node.value==nil then node.value=definition.type=="number"and 0 or definition.type=="boolean"and true or""end end
    return node
end

function UI:CreateRuleBuilder(parent,onChanged)
    local builder=CreateFrame("Frame",nil,parent);builder.root={logic="AND",children={self:DefaultCondition()}};builder.selectedPath={1}
    local layout=Components:CreateColumn(builder,{frame=builder,gap=4})
    local selectorHost=CreateFrame("Frame",nil,builder);local condition=Components:CreateRow(selectorHost,{gap=4});condition.frame:SetAllPoints(selectorHost)
    local logic=self:CreateSelector(selectorHost,180,function()return{{value="AND",label=L["LOGIC_AND"]},{value="OR",label=L["LOGIC_OR"]},{value="NOT",label=L["LOGIC_NOT"]}}end,function(value)local node=builder:GetSelected();if node and node.logic then node.logic=value;if value=="NOT"then while#node.children>1 do table.remove(node.children)end end;builder:Changed()end end);logic:SetPoint("TOPLEFT",-15,0)
    local field=self:CreateSelector(condition.frame,190,function()local out={};for id,definition in pairs(HolyStorm.Rules:GetFields())do if not definition.hidden then out[#out+1]={value=id,label=definition.name or(definition.nameKey and L[definition.nameKey])or id}end end;table.sort(out,function(a,b)return a.label<b.label end);return out end,function(value)local node=builder:GetSelected();if node and not node.logic then local replacement=UI:DefaultCondition(value);node.field,node.operator,node.value=replacement.field,replacement.operator,replacement.value;builder:Changed()end end)
    local operator=self:CreateSelector(condition.frame,125,function()local node=builder:GetSelected();local out={};for _,id in ipairs(HolyStorm.Rules:GetAllowedOperators(node and node.field))do out[#out+1]={value=id,label=L["OP_"..id:upper()]or id}end;return out end,function(value)local node=builder:GetSelected();if node and not node.logic then node.operator=value;if not operatorNeedsValue(value)then node.value=nil elseif node.value==nil then node.value=(HolyStorm.Rules:GetField(node.field)or{}).type=="number"and 0 or""end;builder:Changed()end end)
    local value1=self:Edit(condition.frame,150);local value2=self:Edit(condition.frame,90)
    local typedValue=self:CreateSelector(condition.frame,170,function()local node=builder:GetSelected();return UI:FieldValueItems(HolyStorm.Rules:GetField(node and node.field)or{},node)end,function(value)local node=builder:GetSelected();if node and not node.logic then node.value=value;builder:Changed()end end)
    local multiValue=self:CreateMultiSelector(condition.frame,170,function()local node=builder:GetSelected();return UI:FieldValueItems(HolyStorm.Rules:GetField(node and node.field)or{},node)end,function(values)local node=builder:GetSelected();if node and not node.logic then node.value=values;builder:Changed()end end)
    local apply=self:Button(condition.frame,L["APPLY"],70,function()local node=builder:GetSelected();if not node or node.logic then return end;local definition=HolyStorm.Rules:GetField(node.field)or{};if node.operator=="between"or node.operator=="not_between"then node.value={tonumber(value1:GetText()),tonumber(value2:GetText())}elseif node.operator=="in"or node.operator=="not_in"then node.value=parseList(value1:GetText())else node.value=UI:Value(value1:GetText(),definition.type)end;builder:Changed()end)
    local actions=Components:CreateRow(builder,{gap=4})
    local function action(text,callback)return UI:Button(actions.frame,text,80,callback)end
    actions:Add(action(L["ADD_CONDITION"],function()builder:AddNode(UI:DefaultCondition())end),{weight=1,minWidth=80})
    actions:Add(action(L["ADD_AND_GROUP"],function()builder:AddNode({logic="AND",children={UI:DefaultCondition()}})end),{weight=1,minWidth=70})
    actions:Add(action(L["ADD_OR_GROUP"],function()builder:AddNode({logic="OR",children={UI:DefaultCondition()}})end),{weight=1,minWidth=70})
    actions:Add(action(L["REMOVE"],function()builder:RemoveSelected()end),{weight=1,minWidth=55})
    actions:Add(action(L["MOVE_UP"],function()builder:MoveSelected(-1)end),{weight=1,minWidth=45})
    actions:Add(action(L["MOVE_DOWN"],function()builder:MoveSelected(1)end),{weight=1,minWidth=45})
    actions:Add(action(L["INDENT"],function()builder:IndentSelected()end),{weight=1,minWidth=38})
    actions:Add(action(L["OUTDENT"],function()builder:OutdentSelected()end),{weight=1,minWidth=38})
    builder.validation=UI:Label(builder,"")
    local tree
    tree=Components:CreateTable(builder,{headerHeight=0,rowHeight=25,emptyText=L["NO_SELECTION"],columns={{id="label",weight=1,truncate=true,renderCell=function(_,value,row)return row.unavailable and("|cffff8040"..value.."|r")or value end}},onRowClick=function(row)builder.selectedPath=copy(row.path);builder:Render()end,isRowSelected=function(row)return row.key==builder.selectedKey end})
    builder.tree=tree
    layout:Add(selectorHost,{height=25});layout:Add(actions,{height=25});layout:Add(builder.validation,{height=20});layout:Add(tree,{weight=1,minHeight=120})

    function builder:GetNode(path)local node=self.root;for _,index in ipairs(path or self.selectedPath)do node=node and node.children and node.children[index]end;return node end
    function builder:GetSelected()return self:GetNode(self.selectedPath)end
    function builder:GetParent()if#self.selectedPath==0 then return nil end;local path=copy(self.selectedPath);local index=table.remove(path);return self:GetNode(path),index,path end
    function builder:GetContainer()local node=self:GetSelected();if node and node.logic then return node,copy(self.selectedPath)end;local parentNode,_,path=self:GetParent();return parentNode or self.root,path or{}end
    function builder:AddNode(node)local container,path=self:GetContainer();if container.logic=="NOT"and#container.children>=1 then return end;container.children[#container.children+1]=node;self.selectedPath=copy(path);self.selectedPath[#self.selectedPath+1]=#container.children;self:Changed()end
    function builder:RemoveSelected()local parentNode,index,path=self:GetParent();if parentNode and index and#parentNode.children>1 then table.remove(parentNode.children,index);self.selectedPath=path;if#path==0 then self.selectedPath={math.min(index,#parentNode.children)}end;self:Changed()end end
    function builder:MoveSelected(delta)local parentNode,index,path=self:GetParent();local target=index and index+delta;if parentNode and target and target>=1 and target<=#parentNode.children then parentNode.children[index],parentNode.children[target]=parentNode.children[target],parentNode.children[index];self.selectedPath=path;self.selectedPath[#self.selectedPath+1]=target;self:Changed()end end
    function builder:IndentSelected()local parentNode,index,path=self:GetParent();local previous=parentNode and index and parentNode.children[index-1];if previous and previous.logic and previous.logic~="NOT"then local node=table.remove(parentNode.children,index);previous.children[#previous.children+1]=node;self.selectedPath=path;self.selectedPath[#self.selectedPath+1]=index-1;self.selectedPath[#self.selectedPath+1]=#previous.children;self:Changed()end end
    function builder:OutdentSelected()local parentNode,index,parentPath=self:GetParent();if not parentNode or#parentPath==0 or#parentNode.children<=1 then return end;local grandPath=copy(parentPath);local parentIndex=table.remove(grandPath);local grand=self:GetNode(grandPath);if not grand or not grand.children then return end;local node=table.remove(parentNode.children,index);table.insert(grand.children,parentIndex+1,node);self.selectedPath=grandPath;self.selectedPath[#self.selectedPath+1]=parentIndex+1;self:Changed()end
    function builder:SetRule(root)self.root=copy(root or{logic="AND",children={UI:DefaultCondition()}});if not self.root.logic then self.root={logic="AND",children={self.root}}end;self.selectedPath={};self:Render()end
    function builder:GetRule()return copy(self.root)end
    function builder:Validate()return HolyStorm.Rules:Validate(self.root)end
    function builder:Changed()if onChanged then onChanged()end;self:Render()end
    function builder:Render()
        local flat={};local function walk(node,path,depth)local definition=node.field and HolyStorm.Rules:GetField(node.field);local name=definition and(definition.name or(definition.nameKey and L[definition.nameKey]))or node.field;local label=node.logic and("["..(L["LOGIC_"..node.logic]or node.logic).."]")or string.format("%s  %s  %s%s",name or"?",node.operator or"=",listText(node.value),definition and""or"  ["..L["UNAVAILABLE"].."]");flat[#flat+1]={key=table.concat(path,"."),path=copy(path),label=string.rep("    ",depth)..label,unavailable=node.field~=nil and definition==nil};for index,child in ipairs(node.children or{})do local childPath=copy(path);childPath[#childPath+1]=index;walk(child,childPath,depth+1)end end;walk(self.root,{},0);self.selectedKey=table.concat(self.selectedPath,".");tree:SetData(flat)
        local selected=self:GetSelected()or self.root;condition:Clear();logic:SetShown(selected.logic~=nil);condition.frame:SetShown(selected.logic==nil)
        if selected.logic then logic:SetValue(selected.logic,L["LOGIC_"..selected.logic]or selected.logic)else
            local definition=HolyStorm.Rules:GetField(selected.field)or{};field:SetValue(selected.field,definition.name or(definition.nameKey and L[definition.nameKey])or selected.field);operator:SetValue(selected.operator or"=",L["OP_"..tostring(selected.operator or"="):upper()]or selected.operator);condition:Add(field,{weight=2,minWidth=130});condition:Add(operator,{weight=1.2,minWidth=95})
            if operatorNeedsValue(selected.operator or"=")then local listOperator=selected.operator=="in"or selected.operator=="not_in";local structured=definition.type=="boolean"or definition.type=="enum"or definition.type=="character"or definition.type=="account"or definition.valueProvider~=nil or definition.enumProvider~=nil;if listOperator and structured then multiValue:SetValues(type(selected.value)=="table"and selected.value or{});condition:Add(multiValue,{weight=2,minWidth=120})elseif structured and not listOperator then typedValue:SetValue(selected.value,tostring(selected.value or""));condition:Add(typedValue,{weight=2,minWidth=120})else value1:SetText(listText(selected.value));condition:Add(value1,{weight=2,minWidth=90});if selected.operator=="between"or selected.operator=="not_between"then value1:SetText(tostring(type(selected.value)=="table"and selected.value[1]or""));value2:SetText(tostring(type(selected.value)=="table"and selected.value[2]or""));condition:Add(value2,{weight=1,minWidth=60})end;condition:Add(apply,{width=70})end end
        end
        local valid,reason=self:Validate();self.validation:SetText(valid and L["VALID_EXPRESSION"]or string.format(L["INVALID_EXPRESSION"],UI:ErrorText(reason)));layout:Relayout()
    end
    builder:Render();return builder
end

function UI:CreateFilterBar(parent,contextId,onChanged)
    local bar=CreateFrame("Frame",nil,parent);bar:SetHeight(52);bar.contextId=contextId;bar.active=HolyStorm.FilterManager:GetActiveFilters(contextId);bar.chips={}
    local menu=CreateFrame("Frame",nil,bar,"UIDropDownMenuTemplate");menu:SetPoint("TOPLEFT",-16,0);UIDropDownMenu_SetWidth(menu,125);UIDropDownMenu_SetText(menu,L["FILTER"])
    local function changed()HolyStorm.FilterManager:SetActiveFilters(contextId,bar.active);if onChanged then onChanged()end end
    local function refresh()for _,chip in ipairs(bar.chips)do chip:Hide()end;local x=145;for index,entry in ipairs(bar.active)do local itemIndex=index;local filter=HolyStorm.FilterManager:GetFilter(entry.id,entry.scope);local chip=bar.chips[itemIndex]or UI:Button(bar,"",115,function()table.remove(bar.active,itemIndex);refresh();changed()end);bar.chips[itemIndex]=chip;chip:SetText((filter and filter.name or entry.id).." ×");chip:ClearAllPoints();chip:SetPoint("TOPLEFT",x,2);chip:Show();x=x+120 end end
    UIDropDownMenu_Initialize(menu,function(_,level)if level~=1 then return end;for _,scope in ipairs({"local","global"})do local selectedScope=scope;local root=HolyStorm.FilterManager:GetFilters(selectedScope);for id,filter in pairs(root or{})do local selectedId=id;local info=UIDropDownMenu_CreateInfo();info.text=(selectedScope=="global"and L["GLOBAL_BADGE"]or L["LOCAL_BADGE"])..filter.name;info.keepShownOnClick=true;local found;for index,entry in ipairs(bar.active)do if entry.id==selectedId and entry.scope==selectedScope then found=index end end;local foundIndex=found;info.checked=foundIndex~=nil;info.func=function()if foundIndex then table.remove(bar.active,foundIndex)else bar.active[#bar.active+1]={id=selectedId,scope=selectedScope}end;refresh();changed()end;UIDropDownMenu_AddButton(info,level)end end end)
    local reset=self:Button(bar,L["RESET"],110,function()for index=#bar.active,1,-1 do table.remove(bar.active,index)end;refresh();changed()end);reset:SetPoint("TOPLEFT",0,-28)
    local manage=self:Button(bar,L["MANAGE_FILTERS"],135,function()HolyStorm.Administration:Open("filters")end);manage:SetPoint("LEFT",reset,"RIGHT",6,0)
    function bar:Matches(value)return HolyStorm.FilterManager:ApplyFilters(self.active,value,"AND")end
    function bar:Apply(items)local out={};for _,item in ipairs(items or{})do if self:Matches(item)then out[#out+1]=item end end;return out end
    refresh();return bar
end

HolyStorm.PolicyUI=UI
