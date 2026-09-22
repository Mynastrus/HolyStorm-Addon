local HolyStorm=LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local localeLibrary=LibStub("AceLocale-3.0",true)
local L=localeLibrary and localeLibrary.GetLocale and localeLibrary:GetLocale("Holy_Storm_UI",true)or setmetatable({},{__index=function(_,key)return key end})
local Components=HolyStorm.UIComponents
local Layout=HolyStorm.UILayout
local unpack=unpack or table.unpack

local function call(value,...)
    if type(value)=="function"then local ok,result=pcall(value,...);if ok then return result end;return nil end
    return value
end
local function rowValue(row,column,index)
    if column.value then return call(column.value,row,column,index)end
    if type(row)~="table"then return row end
    if row[column.id]~=nil then return row[column.id]end
    return row[column.index or index]
end

local TableMethods={}
function TableMethods:SetColumns(columns)
    self.columns=columns or{};self.sortColumn=nil
    for index,column in ipairs(self.columns)do column.index=index end
    self:EnsureHeaders();self:Relayout();self:Refresh()
end
function TableMethods:SetData(rows)
    self.rows=type(rows)=="table"and rows or{};self:ApplySort();self:Refresh()
end
function TableMethods:GetData()return self.rows end
function TableMethods:SetEmptyText(text)self.emptyText=text or L["TABLE_EMPTY"];self.empty:SetText(self.emptyText)end
function TableMethods:SetEnabled(enabled)self.enabled=enabled~=false;self:Refresh()end
function TableMethods:UpdateRow(index,row)
    if row~=nil then self.rows[index]=row end
    local widget=self.rowFrames[index];if widget then self:RenderRow(widget,self.rows[index],index)end
end
function TableMethods:SetSort(columnId,direction)
    local found;for _,column in ipairs(self.columns)do if column.id==columnId and column.sortable==true then found=column;break end end
    if not found then return false end
    self.sortColumn=columnId;self.sortDirection=direction=="desc"and"desc"or"asc";self:ApplySort();self:Refresh();return true
end
function TableMethods:ApplySort()
    if not self.sortColumn then return end
    local column;for _,item in ipairs(self.columns)do if item.id==self.sortColumn then column=item;break end end;if not column then return end
    local direction=self.sortDirection=="desc"and-1 or 1
    table.sort(self.rows,function(left,right)
        if column.compare then return column.compare(left,right,direction,self)end
        local a,b=rowValue(left,column,column.index),rowValue(right,column,column.index)
        if a==b then return false end;if a==nil then return direction>0 end;if b==nil then return direction<0 end
        if type(a)~=type(b)or(type(a)~="string"and type(a)~="number")then a,b=tostring(a),tostring(b)end
        if type(a)=="string"then a,b=a:lower(),b:lower()end
        return direction>0 and a<b or a>b
    end)
end
function TableMethods:ToggleSort(column)
    if column.sortable~=true then return end
    local direction=self.sortColumn==column.id and self.sortDirection=="asc"and"desc"or"asc";self:SetSort(column.id,direction)
    if self.options.onSort then self.options.onSort(column.id,direction,self)end
end
function TableMethods:EnsureHeaders()
    for index,column in ipairs(self.columns)do
        local header=self.headers[index]
        if not header then
            header=CreateFrame("Button",nil,self.header,"BackdropTemplate");header:RegisterForClicks("LeftButtonUp")
            header.text=header:CreateFontString(nil,"OVERLAY","GameFontNormalSmall");header.text:SetPoint("LEFT",self.options.cellPadding or 6,0);header.text:SetPoint("RIGHT",-(self.options.cellPadding or 6),0)
            header:SetScript("OnClick",function(button)self:ToggleSort(button.column)end);self.headers[index]=header
        end
        header.column=column;header.text:SetText(column.title or column.label or column.id or"");header.text:SetJustifyH(column.headerAlign or column.align or"LEFT");header:SetEnabled(column.sortable==true);header:Show()
    end
    for index=#self.columns+1,#self.headers do self.headers[index]:Hide()end
end
function TableMethods:AcquireRow(index)
    local row=self.rowFrames[index];if row then return row end
    local frame=CreateFrame("Button",nil,self.content);frame:RegisterForClicks("LeftButtonUp","RightButtonUp")
    local background=frame:CreateTexture(nil,"BACKGROUND");background:SetAllPoints();background:SetColorTexture(1,1,1,.035)
    local hover=frame:CreateTexture(nil,"HIGHLIGHT");hover:SetAllPoints();local color=Components:GetToken("colors","hover",{1,.82,0,.10});hover:SetColorTexture(unpack(color))
    row={frame=frame,background=background,hover=hover,cells={}}
    frame:SetScript("OnClick",function(_,button)
        local columnId=frame.mouseColumn
        local column;for _,candidate in ipairs(self.columns)do if candidate.id==columnId then column=candidate;break end end
        if column and column.onClick then column.onClick(frame.rowData,button,column,self)elseif self.options.onRowClick then self.options.onRowClick(frame.rowData,button,self)end
    end)
    frame:SetScript("OnEnter",function(owner)self:ShowTooltip(owner,frame.rowData,nil)end);frame:SetScript("OnLeave",function()if GameTooltip then GameTooltip:Hide()end end)
    self.rowFrames[index]=row;return row
end
function TableMethods:AcquireCell(row,index)
    local cell=row.cells[index];if cell then return cell end
    local frame=CreateFrame("Button",nil,row.frame);frame:RegisterForClicks("LeftButtonUp","RightButtonUp")
    local text=frame:CreateFontString(nil,"OVERLAY","GameFontHighlight");text:SetPoint("LEFT",self.options.cellPadding or 6,0);text:SetPoint("RIGHT",-(self.options.cellPadding or 6),0);text:SetJustifyV("MIDDLE");text:SetWordWrap(false)
    cell={frame=frame,text=text}
    frame:SetScript("OnClick",function(_,button)local column=self.columns[index];if column and column.onClick then column.onClick(row.frame.rowData,button,column,self)elseif self.options.onRowClick then self.options.onRowClick(row.frame.rowData,button,self)end end)
    frame:SetScript("OnEnter",function(owner)self:ShowTooltip(owner,row.frame.rowData,self.columns[index])end);frame:SetScript("OnLeave",function()if GameTooltip then GameTooltip:Hide()end end)
    row.cells[index]=cell;return cell
end
function TableMethods:ShowTooltip(owner,row,column)
    if not GameTooltip then return end
    local source=column and column.tooltip or self.options.rowTooltip;local text=call(source,row,column,self)
    if not text or text==""then return end;GameTooltip:SetOwner(owner,"ANCHOR_RIGHT");GameTooltip:SetText(text);GameTooltip:Show()
end
function TableMethods:RenderRow(row,data,rowIndex)
    row.frame.rowData=data;row.background:SetAlpha(rowIndex%2==0 and .8 or .35)
    local disabled=not self.enabled or data and data.disabled==true or call(self.options.isRowDisabled,data,rowIndex,self)==true
    row.frame:SetEnabled(not disabled);row.frame:SetAlpha(disabled and .55 or 1)
    for index,column in ipairs(self.columns)do
        local cell=self:AcquireCell(row,index);local value=rowValue(data,column,index)
        cell.text:SetJustifyH(column.align or"LEFT");cell.text:SetText("");cell.frame:Show()
        if column.renderCell then
            local result=call(column.renderCell,cell,value,data,column,rowIndex,self);if result~=nil then cell.text:SetText(tostring(result))end
        else cell.text:SetText(value==nil and(column.unknownText or self.options.unknownText or L["TABLE_UNKNOWN"])or tostring(value))end
        cell.frame:SetEnabled(not disabled and(column.onClick~=nil or self.options.onRowClick~=nil))
    end
    for index=#self.columns+1,#row.cells do row.cells[index].frame:Hide()end
    row.frame:Show()
end
function TableMethods:Refresh()
    local count=#self.rows
    for index,data in ipairs(self.rows)do self:RenderRow(self:AcquireRow(index),data,index)end
    for index=count+1,#self.rowFrames do self.rowFrames[index].frame:Hide()end
    self.empty:SetShown(count==0);self.scroll:SetShown(count>0);self:Relayout()
end
function TableMethods:Relayout()
    if self.relayouting then return end;self.relayouting=true
    local width=math.max(1,(self.frame.GetWidth and self.frame:GetWidth()or 1));local height=math.max(1,(self.frame.GetHeight and self.frame:GetHeight()or 1))
    local headerHeight=self.options.headerHeight or Components:GetToken("sizes","header",26);local rowHeight=self.options.rowHeight or Components:GetToken("sizes","row",24);local gap=self.options.columnGap or 1
    self.header:SetHeight(headerHeight);self.scroll:SetPoint("TOPLEFT",self.frame,"TOPLEFT",0,-headerHeight);self.scroll:SetPoint("BOTTOMRIGHT",self.frame,"BOTTOMRIGHT",0,0)
    local bodyWidth=math.max(1,(self.scroll.GetWidth and self.scroll:GetWidth()or width)-(self.options.scrollbarWidth or 24));self.content:SetWidth(bodyWidth)
    local tracks={};for index,column in ipairs(self.columns)do tracks[index]={width=column.width,percent=column.percent,weight=column.weight or column.flex,min=column.minWidth,max=column.maxWidth}end
    self.columnWidths=Layout:ResolveTracks(tracks,bodyWidth,gap);local x=0
    for index,columnWidth in ipairs(self.columnWidths)do
        local header=self.headers[index];if header then header:ClearAllPoints();header:SetPoint("TOPLEFT",self.header,"TOPLEFT",x,0);header:SetSize(math.max(1,columnWidth),headerHeight)end
        for rowIndex,row in ipairs(self.rowFrames)do if rowIndex<=#self.rows then local cell=row.cells[index];if cell then cell.frame:ClearAllPoints();cell.frame:SetPoint("TOPLEFT",row.frame,"TOPLEFT",x,0);cell.frame:SetSize(math.max(1,columnWidth),rowHeight)end end end
        x=x+columnWidth+(index<#self.columnWidths and gap or 0)
    end
    for index,row in ipairs(self.rowFrames)do if index<=#self.rows then row.frame:ClearAllPoints();row.frame:SetPoint("TOPLEFT",self.content,"TOPLEFT",0,-((index-1)*rowHeight));row.frame:SetSize(bodyWidth,rowHeight)end end
    self.content:SetHeight(math.max(1,#self.rows*rowHeight));self.empty:SetWidth(math.max(1,width-24));self.relayouting=false
end
function TableMethods:Destroy()
    self.frame:Hide();self.rows={};self.columns={};self.rowFrames={};self.headers={}
end

function Components:CreateTable(parent,options)
    options=options or{};local frame=CreateFrame("Frame",nil,parent,"BackdropTemplate")
    local header=CreateFrame("Frame",nil,frame);header:SetPoint("TOPLEFT");header:SetPoint("TOPRIGHT")
    local scroll=CreateFrame("ScrollFrame",nil,frame,"UIPanelScrollFrameTemplate")
    local content=CreateFrame("Frame",nil,scroll);content:SetSize(1,1);scroll:SetScrollChild(content)
    local empty=frame:CreateFontString(nil,"OVERLAY","GameFontDisable");empty:SetPoint("TOPLEFT",12,-((options.headerHeight or 26)+12));empty:SetJustifyH("LEFT");empty:SetText(options.emptyText or L["TABLE_EMPTY"])
    local object={frame=frame,header=header,scroll=scroll,content=content,empty=empty,options=options,columns={},rows={},headers={},rowFrames={},enabled=true,emptyText=options.emptyText or L["TABLE_EMPTY"]}
    for key,method in pairs(TableMethods)do object[key]=method end
    if frame.HookScript then frame:HookScript("OnSizeChanged",function()object:Relayout()end)end
    object:SetColumns(options.columns or{});object:SetData(options.data or{});return object
end
