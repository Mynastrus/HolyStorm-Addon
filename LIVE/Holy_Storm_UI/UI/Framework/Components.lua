local HolyStorm=LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local Components=HolyStorm.UIComponents or{}
local unpack=unpack or table.unpack
HolyStorm.UIComponents=Components

Components.tokens=Components.tokens or{
    spacing={xs=4,small=8,medium=12,large=18},
    sizes={row=24,header=26,button=24},
    colors={panel={.025,.035,.05,.94},border={.25,.19,.07,.9},hover={1,.82,0,.10},disabled={.45,.45,.45,1},unknown="|cff888888",positive="|cff20ff20",negative="|cffff4040"},
    textures={white="Interface\\Buttons\\WHITE8x8",fallbackIcon="Interface\\Icons\\INV_Misc_QuestionMark"},
}
Components.State=Components.State or{UNKNOWN="UNKNOWN",EMPTY="EMPTY",VALUE="VALUE"}

function Components:GetToken(group,key,fallback)
    local values=self.tokens[group]
    return type(values)=="table"and values[key]~=nil and values[key]or fallback
end

-- Deliberately small theme extension point. Optional themes may replace tokens;
-- widgets keep their contracts and do not depend on the theme addon.
function Components:ApplyTheme(overrides)
    for group,values in pairs(type(overrides)=="table"and overrides or{})do
        if type(values)=="table"then self.tokens[group]=self.tokens[group]or{};for key,value in pairs(values)do self.tokens[group][key]=value end end
    end
    if HolyStorm.Events then HolyStorm.Events:Emit("HS_UI_THEME_CHANGED",self.tokens)end
end

function Components:FormatState(value,state,options)
    options=options or{}
    if type(value)=="table"and value.status=="unknown"then state=self.State.UNKNOWN end
    if state==self.State.UNKNOWN or value==nil then return(self:GetToken("colors","unknown","|cff888888")..(options.unknownText or"–").."|r")end
    if state==self.State.EMPTY then return options.emptyText or""end
    if options.format then return options.format(value)end
    return tostring(value)
end

function Components:FormatDelta(value)
    value=tonumber(value);if value==nil then return self:FormatState(nil,self.State.UNKNOWN)end
    if value>0 then return self:GetToken("colors","positive","|cff20ff20").."+"..tostring(value).."|r"end
    if value<0 then return self:GetToken("colors","negative","|cffff4040")..tostring(value).."|r"end
    return"0"
end

function Components:ReplaceHyperlinkLabel(link,label)
    if type(link)~="string"then return tostring(label or"")end
    local prefix,payload,oldLabel,suffix=link:match("^(.-)|H([^|]+)|h(.-)|h(.*)$")
    if not payload then return tostring(label or link)end
    local value=tostring(label or oldLabel or"");if oldLabel and oldLabel:match("^%[.*%]$")and not value:match("^%[.*%]$")then value="["..value.."]"end
    return prefix.."|H"..payload.."|h"..value.."|h"..suffix
end

function Components:CreateSection(parent,options)
    options=options or{};local frame=CreateFrame("Frame",nil,parent);local title=frame:CreateFontString(nil,"OVERLAY",options.titleFont or"GameFontNormal")
    title:SetPoint("TOPLEFT",0,0);title:SetPoint("TOPRIGHT",0,0);title:SetHeight(options.titleHeight or 22);title:SetJustifyH(options.titleAlign or"LEFT");title:SetText(options.title or"")
    local content=CreateFrame("Frame",nil,frame);content:SetPoint("TOPLEFT",title,"BOTTOMLEFT",0,-(options.titleGap or 4));content:SetPoint("BOTTOMRIGHT")
    local layout=HolyStorm.UILayout:CreateContainer(content,{frame=content,axis=options.axis or"column",gap=options.gap or 0,padding=options.padding})
    local section={frame=frame,title=title,content=content,layout=layout}
    function section:SetTitle(value)title:SetText(value or"")end;function section:Add(child,track)return layout:Add(child,track)end;function section:Remove(child)return layout:Remove(child)end;function section:Clear()return layout:Clear()end;function section:Relayout()return layout:Relayout()end
    return section
end

function Components:CreateContainer(parent,options)
    return HolyStorm.UILayout:CreateContainer(parent,options)
end
function Components:CreateRow(parent,options)options=options or{};options.axis="row";return self:CreateContainer(parent,options)end
function Components:CreateColumn(parent,options)options=options or{};options.axis="column";return self:CreateContainer(parent,options)end

function Components:CreateText(parent,options)
    options=options or{}
    local text=parent:CreateFontString(options.name,options.layer or"OVERLAY",options.font or"GameFontHighlight")
    text:SetText(options.text or"");text:SetJustifyH(options.align or"LEFT");text:SetJustifyV(options.verticalAlign or"MIDDLE")
    if options.wrap~=nil then text:SetWordWrap(options.wrap==true)end
    return{frame=text,text=text,SetText=function(_,value)text:SetText(value or"")end}
end

function Components:CreateIcon(parent,options)
    options=options or{};local frame=CreateFrame("Frame",nil,parent);local size=options.size or 18;frame:SetSize(options.width or size,options.height or size)
    local texture=frame:CreateTexture(nil,options.layer or"ARTWORK");texture:SetAllPoints();texture:SetTexture(options.texture or self:GetToken("textures","fallbackIcon"))
    if options.texCoord then texture:SetTexCoord(unpack(options.texCoord))end
    return{frame=frame,texture=texture,SetTexture=function(_,value)texture:SetTexture(value or Components:GetToken("textures","fallbackIcon"))end}
end

function Components:CreateButton(parent,options)
    options=options or{};local button=CreateFrame("Button",nil,parent,options.template or"UIPanelButtonTemplate")
    button:SetSize(options.width or 120,options.height or self:GetToken("sizes","button",24));button:SetText(options.text or"")
    if options.onClick then button:SetScript("OnClick",options.onClick)end
    if options.tooltip then
        button:SetScript("OnEnter",function(owner)GameTooltip:SetOwner(owner,options.tooltipAnchor or"ANCHOR_RIGHT");GameTooltip:SetText(type(options.tooltip)=="function"and options.tooltip(owner)or options.tooltip);GameTooltip:Show()end)
        button:SetScript("OnLeave",function()GameTooltip:Hide()end)
    end
    return{frame=button,button=button,SetText=function(_,value)button:SetText(value or"")end,SetEnabled=function(_,value)button:SetEnabled(value~=false)end}
end

function Components:CreateEditBox(parent,options)
    options=options or{};local edit=CreateFrame("EditBox",nil,parent,options.template or"InputBoxTemplate")
    edit:SetSize(options.width or 180,options.height or 22);edit:SetAutoFocus(options.autoFocus==true)
    if options.text~=nil then edit:SetText(tostring(options.text))end
    if options.onChanged then edit:SetScript("OnTextChanged",options.onChanged)end
    if options.onEnterPressed then edit:SetScript("OnEnterPressed",options.onEnterPressed)end
    return{frame=edit,edit=edit,SetText=function(_,value)edit:SetText(value or"")end,GetText=function()return edit:GetText()end,SetEnabled=function(_,value)edit:SetEnabled(value~=false)end}
end

function Components:CreateEmptyState(parent,options)
    options=options or{};local frame=CreateFrame("Frame",nil,parent)
    local text=frame:CreateFontString(nil,"OVERLAY",options.font or"GameFontDisableLarge")
    text:SetPoint("CENTER");text:SetWidth(options.width or 420);text:SetJustifyH("CENTER");text:SetJustifyV("MIDDLE");text:SetWordWrap(true);text:SetText(options.text or"")
    return{frame=frame,text=text,SetText=function(_,value)text:SetText(value or"")end}
end

function Components:CreateScrollContainer(parent,options)
    options=options or{};local frame=CreateFrame("Frame",nil,parent);local scroll=CreateFrame("ScrollFrame",nil,frame,options.template or"UIPanelScrollFrameTemplate");scroll:SetAllPoints(frame)
    local content=CreateFrame("Frame",nil,scroll);content:SetSize(1,1);scroll:SetScrollChild(content)
    local controller={frame=frame,scroll=scroll,content=content}
    function controller:Relayout()local width=math.max(1,(self.scroll:GetWidth()or 1)-(options.scrollbarInset or 24));self.content:SetWidth(width)end
    function controller:SetContentHeight(height)self.content:SetHeight(math.max(1,height or 1))end
    if scroll.HookScript then scroll:HookScript("OnSizeChanged",function()controller:Relayout()end)end
    return controller
end

function Components:CreateAceContainer(kind,parent,options)
    options=options or{};local aceGUI=LibStub("AceGUI-3.0",true);if not aceGUI then return nil,"ACEGUI_UNAVAILABLE"end
    local widget=aceGUI:Create(kind);widget.frame:SetParent(parent)
    if options.layout and widget.SetLayout then widget:SetLayout(options.layout)end
    if options.width and widget.SetWidth then widget:SetWidth(options.width)end;if options.height and widget.SetHeight then widget:SetHeight(options.height)end
    return widget
end
function Components:CreateTabGroup(parent,options)
    local widget,reason=self:CreateAceContainer((options and options.widgetType)or"HolyStormTabGroup",parent,options)
    if widget and options then widget.wrapTabs=options.wrapTabs==true;widget.minTabWidth=options.minTabWidth;if widget.LayoutTabs then widget:LayoutTabs()end end
    return widget,reason
end
function Components:CreateTreeGroup(parent,options)return self:CreateAceContainer("TreeGroup",parent,options)end

function Components:Build(parent,description,context)
    if type(description)~="table"then return nil,"INVALID_COMPONENT"end
    local kind=description.type or"container";local component
    if kind=="text"then component=self:CreateText(parent,description)
    elseif kind=="icon"then component=self:CreateIcon(parent,description)
    elseif kind=="button"then component=self:CreateButton(parent,description)
    elseif kind=="edit"or kind=="input"then component=self:CreateEditBox(parent,description)
    elseif kind=="empty"then component=self:CreateEmptyState(parent,description)
    elseif kind=="row"then component=self:CreateRow(parent,description)
    elseif kind=="column"or kind=="container"or kind=="group"then component=self:CreateColumn(parent,description)
    elseif kind=="scroll"then component=self:CreateScrollContainer(parent,description)
    elseif kind=="section"then component=self:CreateSection(parent,description)
    elseif kind=="table"then component=self:CreateTable(parent,description)
    elseif kind=="tabGroup"then component=self:CreateTabGroup(parent,description)
    elseif kind=="treeGroup"then component=self:CreateTreeGroup(parent,description)
    else return nil,"UNKNOWN_COMPONENT"end
    local childParent=component.content or component.frame
    if component.Add and type(description.children)=="table"then
        for _,childDescription in ipairs(description.children)do local child=self:Build(childParent,childDescription,context);if child then component:Add(child,childDescription.track or childDescription)end end
    end
    if description.bind and context then description.bind(component,context)end
    return component
end
