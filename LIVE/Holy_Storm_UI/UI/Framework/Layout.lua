local HolyStorm=LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")

local Layout={version="1.0.0"}

local function number(value,fallback)
    value=tonumber(value)
    return value or fallback or 0
end

local function clamp(value,minimum,maximum)
    if minimum~=nil then value=math.max(value,number(minimum))end
    if maximum~=nil then value=math.min(value,number(maximum,value))end
    return value
end

function Layout:NormalizePadding(value)
    if type(value)=="number"then return{left=value,right=value,top=value,bottom=value}end
    value=type(value)=="table"and value or{}
    local horizontal=number(value.horizontal or value.x)
    local vertical=number(value.vertical or value.y)
    return{
        left=number(value.left,horizontal),right=number(value.right,horizontal),
        top=number(value.top,vertical),bottom=number(value.bottom,vertical),
    }
end

function Layout:NormalizeTrack(track)
    if type(track)=="number"then return{kind="fixed",value=math.max(0,track)}end
    track=type(track)=="table"and track or{}
    local result={minimum=track.minWidth or track.minHeight or track.min,maximum=track.maxWidth or track.maxHeight or track.max}
    local fixed=track.width or track.height or track.size
    local percent=track.percent
    if type(fixed)=="string"then percent=tonumber(fixed:match("^([%d%.]+)%%$"));if percent then percent=percent/100 end end
    if fixed~=nil and type(fixed)~="string"then result.kind,result.value="fixed",math.max(0,number(fixed))
    elseif percent~=nil then result.kind,result.value="percent",math.max(0,number(percent));if result.value>1 then result.value=result.value/100 end
    else result.kind,result.value="weight",math.max(0,number(track.weight or track.flex or track.fr,1))end
    return result
end

-- Resolves fixed, percentage and weighted tracks without allocating frames.
-- Min/max constraints are applied before remaining space is shared.
function Layout:ResolveTracks(tracks,total,gap)
    tracks=tracks or{};total=math.max(0,number(total));gap=math.max(0,number(gap))
    local count=#tracks
    local usable=math.max(0,total-math.max(0,count-1)*gap)
    local widths,normalized={},{}
    local committed,weight=0,0
    for index,track in ipairs(tracks)do
        local item=self:NormalizeTrack(track);normalized[index]=item
        if item.kind=="fixed"then widths[index]=clamp(item.value,item.minimum,item.maximum);committed=committed+widths[index]
        elseif item.kind=="percent"then widths[index]=clamp(usable*item.value,item.minimum,item.maximum);committed=committed+widths[index]
        else widths[index]=0;weight=weight+item.value end
    end
    local remaining=math.max(0,usable-committed)
    if weight>0 and remaining>0 then
        local active={}
        for index,item in ipairs(normalized)do if item.kind=="weight"and item.value>0 then active[index]=true end end
        while remaining>.001 do
            local activeWeight=0
            for index in pairs(active)do activeWeight=activeWeight+normalized[index].value end
            if activeWeight<=0 then break end
            local constrained=false
            for index in pairs(active)do
                local item=normalized[index];local share=remaining*item.value/activeWeight;local resolved=clamp(share,item.minimum,item.maximum)
                if math.abs(resolved-share)>.001 then widths[index]=resolved;remaining=math.max(0,remaining-resolved);active[index]=nil;constrained=true end
            end
            if not constrained then for index in pairs(active)do widths[index]=remaining*normalized[index].value/activeWeight end;remaining=0 end
        end
    end
    return widths,usable
end

function Layout:Calculate(axis,width,height,tracks,gap,padding)
    padding=self:NormalizePadding(padding)
    local horizontal=axis=="row"or axis=="horizontal"
    local primary=horizontal and math.max(0,number(width)-padding.left-padding.right)or math.max(0,number(height)-padding.top-padding.bottom)
    local sizes=self:ResolveTracks(tracks,primary,gap)
    local result,offset={},0
    for index,size in ipairs(sizes)do
        if horizontal then result[index]={x=padding.left+offset,y=padding.top,width=size,height=math.max(0,number(height)-padding.top-padding.bottom)}
        else result[index]={x=padding.left,y=padding.top+offset,width=math.max(0,number(width)-padding.left-padding.right),height=size}end
        offset=offset+size+(index<#sizes and number(gap)or 0)
    end
    return result
end

function Layout:Measure(axis,tracks,measurements,gap,padding)
    padding=self:NormalizePadding(padding);measurements=measurements or{}
    local horizontal=axis=="row"or axis=="horizontal";local primary,cross=0,0
    for index,track in ipairs(tracks or{})do
        local normalized=self:NormalizeTrack(track);local measured=measurements[index]or{}
        local measuredPrimary=horizontal and number(measured.width)or number(measured.height)
        local measuredCross=horizontal and number(measured.height)or number(measured.width)
        local size=normalized.kind=="fixed"and normalized.value or measuredPrimary
        primary=primary+clamp(size,normalized.minimum,normalized.maximum);cross=math.max(cross,measuredCross)
    end
    primary=primary+math.max(0,#(tracks or{})-1)*number(gap)
    if horizontal then return primary+padding.left+padding.right,cross+padding.top+padding.bottom end
    return cross+padding.left+padding.right,primary+padding.top+padding.bottom
end

function Layout:CreateContainer(parent,definition)
    definition=definition or{}
    local frame=definition.frame or CreateFrame("Frame",definition.name,parent,definition.template)
    local container={frame=frame,definition=definition,children={},layout=self}
    function container:Add(child,track)
        local childFrame=type(child)=="table"and child.frame or child
        if not childFrame then return false end
        if childFrame.SetParent then childFrame:SetParent(self.frame)end
        self.children[#self.children+1]={object=child,frame=childFrame,track=track or{weight=1}}
        self:Relayout();return child
    end
    function container:Remove(child)
        for index,item in ipairs(self.children)do if item.object==child or item.frame==child then table.remove(self.children,index);if item.frame.Hide then item.frame:Hide()end;self:Relayout();return true end end
        return false
    end
    function container:Measure()
        local tracks,measurements={},{}
        for index,item in ipairs(self.children)do tracks[index]=item.track;measurements[index]={width=item.frame.GetWidth and item.frame:GetWidth()or 0,height=item.frame.GetHeight and item.frame:GetHeight()or 0}end
        return self.layout:Measure(self.definition.axis or"column",tracks,measurements,self.definition.gap or 0,self.definition.padding)
    end
    function container:Relayout()
        if self.relayouting then return end;self.relayouting=true
        local width=self.frame.GetWidth and self.frame:GetWidth()or 0;local height=self.frame.GetHeight and self.frame:GetHeight()or 0
        local tracks={};for index,item in ipairs(self.children)do tracks[index]=item.track end
        if self.definition.autoSize or self.definition.autoWidth or self.definition.autoHeight then
            local measuredWidth,measuredHeight=self:Measure();width=(self.definition.autoSize or self.definition.autoWidth)and measuredWidth or width;height=(self.definition.autoSize or self.definition.autoHeight)and measuredHeight or height
            if self.frame.SetSize then self.frame:SetSize(math.max(1,width),math.max(1,height))end
        end
        local rects=self.layout:Calculate(self.definition.axis or"column",width,height,tracks,self.definition.gap or 0,self.definition.padding)
        for index,item in ipairs(self.children)do
            local rect=rects[index];local childFrame=item.frame
            if rect and childFrame then
                if childFrame.ClearAllPoints then childFrame:ClearAllPoints()end
                if childFrame.SetPoint then childFrame:SetPoint("TOPLEFT",self.frame,"TOPLEFT",rect.x,-rect.y)end
                if childFrame.SetSize then childFrame:SetSize(math.max(1,rect.width),math.max(1,rect.height))end
                if childFrame.Show then childFrame:Show()end
                if type(item.object)=="table"and item.object.Relayout then item.object:Relayout()end
            end
        end
        self.relayouting=false
    end
    function container:Clear()
        for _,item in ipairs(self.children)do if item.frame.Hide then item.frame:Hide()end end
        self.children={}
    end
    if frame.HookScript then frame:HookScript("OnSizeChanged",function()container:Relayout()end)end
    return container
end

HolyStorm.UILayout=Layout
