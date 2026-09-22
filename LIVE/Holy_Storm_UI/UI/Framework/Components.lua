local HolyStorm=LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local Components=HolyStorm.UIComponents or{}
local unpack=unpack or table.unpack
HolyStorm.UIComponents=Components

Components.tokens=Components.tokens or{
    spacing={xs=4,small=8,medium=12,large=18},
    sizes={row=24,header=26,button=24},
    colors={panel={.025,.035,.05,.94},border={.25,.19,.07,.9},hover={1,.82,0,.10},disabled={.45,.45,.45,1}},
    textures={white="Interface\\Buttons\\WHITE8x8",fallbackIcon="Interface\\Icons\\INV_Misc_QuestionMark"},
}

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
function Components:CreateTabGroup(parent,options)return self:CreateAceContainer((options and options.widgetType)or"HolyStormTabGroup",parent,options)end
function Components:CreateTreeGroup(parent,options)return self:CreateAceContainer("TreeGroup",parent,options)end

function Components:Build(parent,description,context)
    if type(description)~="table"then return nil,"INVALID_COMPONENT"end
    local kind=description.type or"container";local component
    if kind=="text"then component=self:CreateText(parent,description)
    elseif kind=="icon"then component=self:CreateIcon(parent,description)
    elseif kind=="button"then component=self:CreateButton(parent,description)
    elseif kind=="row"then component=self:CreateRow(parent,description)
    elseif kind=="column"or kind=="container"or kind=="group"then component=self:CreateColumn(parent,description)
    elseif kind=="scroll"then component=self:CreateScrollContainer(parent,description)
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
