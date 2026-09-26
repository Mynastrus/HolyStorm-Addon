local root=(arg[0]:gsub("tools[/\\]test_ui_framework.lua$","")).."LIVE/Holy_Storm_UI/"
local unpack=unpack or table.unpack
local modules={characters=true}
local listeners={}
local HolyStorm={Utils={},Events={},State={}}
function HolyStorm.Utils.SafeCall(_,callback,...)local values={pcall(callback,...)};local ok=table.remove(values,1);return ok,unpack(values)end
function HolyStorm.Events:Register(event,owner,callback)listeners[event]=listeners[event]or{};listeners[event][owner]=callback end
function HolyStorm.Events:UnregisterOwner(owner)for _,entries in pairs(listeners)do entries[owner]=nil end end
function HolyStorm.Events:Emit(event,...)for _,callback in pairs(listeners[event]or{})do callback(event,...)end end
function HolyStorm.State:Set(key,value)self[key]=value end
function HolyStorm:GetUIExtensions()return{}end
function HolyStorm:IsModuleAvailable(id)return modules[id]==true end
function HolyStorm:IsCapabilityAvailable()return false end

local uiLocale=setmetatable({TABLE_EMPTY="Nothing here",TABLE_UNKNOWN="Unknown"},{__index=function(_,key)return key end})
function LibStub(name,silent)
    if name=="AceAddon-3.0"then return{GetAddon=function()return HolyStorm end}end
    if name=="AceLocale-3.0"then return{GetLocale=function(_,localeName)return localeName=="Example"and{TITLE="Localized title"}or uiLocale end}end
    if silent then return nil end
end

local function region(kind,parent)
    local object={kind=kind,parent=parent,width=100,height=100,shown=true,enabled=true,textValue="",points={}}
    function object:SetParent(value)self.parent=value end
    function object:SetSize(width,height)self.width,self.height=width,height;if self.OnSizeChanged then self.OnSizeChanged(self,width,height)end end
    function object:SetWidth(width)self.width=width end;function object:SetHeight(height)self.height=height end
    function object:GetWidth()return self.width end;function object:GetHeight()return self.height end
    function object:SetPoint(...)self.points[#self.points+1]={...}end;function object:ClearAllPoints()self.points={}end;function object:SetAllPoints()end
    function object:SetScript(event,callback)self[event]=callback end;function object:HookScript(event,callback)self[event]=callback end
    function object:CreateTexture()return region("texture",self)end;function object:CreateFontString()return region("font",self)end
    function object:SetTexture(value)self.texture=value end;function object:SetTexCoord(...)self.texCoord={...}end;function object:SetColorTexture(...)self.color={...}end
    function object:SetText(value)self.textValue=value or""end;function object:SetJustifyH()end;function object:SetJustifyV()end;function object:SetWordWrap()end
    function object:RegisterForClicks()end;function object:SetEnabled(value)self.enabled=value~=false end;function object:SetAlpha(value)self.alpha=value end
    function object:SetShown(value)self.shown=value==true end;function object:IsShown()return self.shown end;function object:Show()self.shown=true end;function object:Hide()self.shown=false end
    function object:SetScrollChild(value)self.scrollChild=value end
    return object
end
function CreateFrame(_,_,parent)return region("frame",parent)end

assert(loadfile(root.."UI/Framework/Layout.lua"))()
assert(loadfile(root.."UI/Framework/Components.lua"))()
assert(loadfile(root.."UI/Framework/Table.lua"))()

local section=HolyStorm.UIComponents:Build(region("section-parent"),{type="section",title="Details",children={{type="text",text="Content",track={height=20}}}});assert(section.title.textValue=="Details"and#section.layout.children==1,"declarative sections compose central layout children")

local Layout=HolyStorm.UILayout
local widths=Layout:ResolveTracks({{width=80},{weight=1,minWidth=50},{weight=2}},500,10)
assert(widths[1]==80,"fixed track")
assert(math.abs(widths[2]-133.333)<.01 and math.abs(widths[3]-266.666)<.01,"weighted remainder")
local halves=Layout:ResolveTracks({{percent=.5},{percent=.5}},400,8)
assert(halves[1]==196 and halves[2]==196,"percentage tracks use post-gap width")
local rects=Layout:Calculate("row",640,300,{{width=40},{weight=1},{width=100}},10,{left=20,right=20,top=5,bottom=5})
assert(rects[1].x==20 and rects[1].width==40 and rects[2].width==440 and rects[3].width==100,"row layout and padding")
local measuredWidth,measuredHeight=Layout:Measure("row",{{width=32},{weight=1},{width=100}},{{width=32,height=20},{width=180,height=28},{width=100,height=24}},8,{horizontal=10,vertical=5})
assert(measuredWidth==348 and measuredHeight==38,"automatic content measurement")

local parent=region("parent");parent:SetSize(600,300)
local dataTable=HolyStorm.UIComponents:CreateTable(parent,{columns={{id="icon",width=32},{id="name",title="Name",weight=1,sortable=true},{id="status",title="Status",width=100}},emptyText="Empty"})
dataTable.frame.width=600;dataTable.frame.height=300;dataTable.scroll.width=600;dataTable:Relayout()
assert(dataTable.columnWidths[1]==32 and dataTable.columnWidths[3]==100 and dataTable.columnWidths[2]>400,"table fixed/flexible columns")
dataTable:SetData({})
assert(dataTable.empty.shown and not dataTable.scroll.shown,"empty state")
dataTable:SetData({{name="Alpha",status=nil},{name=nil,status=false}})
assert(not dataTable.empty.shown and dataTable.rowFrames[1].cells[3].text.textValue=="Unknown"and dataTable.rowFrames[2].cells[2].text.textValue=="Unknown"and dataTable.rowFrames[2].cells[3].text.textValue=="false","missing and false table values")
local reused=dataTable.rowFrames[1]
dataTable:SetData({{name="Beta",status="Ready"}});assert(dataTable.rowFrames[1]==reused,"rows are reused")
dataTable:SetData({{name="Zulu"},{name="alpha"}});assert(dataTable:SetSort("name","asc")and dataTable.rows[1].name=="alpha","optional sorting")
dataTable:SetSelection("alpha");assert(dataTable.selection=="alpha","table selection state")
local oldFlexible=dataTable.columnWidths[2];dataTable.frame.width=800;dataTable.scroll.width=800;dataTable:Relayout();assert(dataTable.columnWidths[2]>oldFlexible,"table relayout on resize")
dataTable.frame.width=150;dataTable.scroll.width=150;dataTable:Relayout();local compactTotal=2;for _,width in ipairs(dataTable.columnWidths)do compactTotal=compactTotal+width end;assert(compactTotal<=126.01,"over-constrained tables compact centrally without overlapping the viewport")
local truncationTable=HolyStorm.UIComponents:CreateTable(parent,{columns={{id="name",weight=1,truncate=true}},cellPadding=2});truncationTable.frame.width=90;truncationTable.frame.height=100;truncationTable.scroll.width=90;truncationTable:SetData({{name="Übermäßig langer Name"}});truncationTable:Relayout();assert(truncationTable.rowFrames[1].cells[1].text.textValue:find("...",1,true),"UTF-8 labels truncate through the central table")

assert(loadfile(root.."UI/Framework/Components/PolicyUI.lua"))()
local selectedItem
local policyList=HolyStorm.PolicyUI:CreateList(parent,function(item)selectedItem=item end)
policyList:SetItems({{id="one",name="One"},{id="two",name="Two"}},function(item)return item.name end)
policyList.rowFrames[1].frame:OnClick("LeftButton");assert(selectedItem.id=="one"and policyList.selection=="one","policy lists delegate selection to the shared table")
local checked=false
local policyChecklist=HolyStorm.PolicyUI:CreateCheckList(parent,function()return{{value="one",label="One",checked=checked}}end,function(_,value)checked=value end)
policyChecklist:Refresh();policyChecklist.rowFrames[1].frame:OnClick("LeftButton");assert(checked==true,"policy checklists delegate toggles through the shared table")

assert(loadfile(root.."UI/Framework/UIManager.lua"))()
local UI=HolyStorm.UI
local driver={content=region("content"),pages={}}
function driver:RegisterPage(id,frame,title,onShow)self.pages[id]={frame=frame,title=title,onShow=onShow}end
function driver:UnregisterPage(id)self.pages[id]=nil end
function driver:ShowPage(id)for _,page in pairs(self.pages)do page.frame:Hide()end;self.pages[id].frame:Show();if self.pages[id].onShow then self.pages[id].onShow()end end
function driver:AddRightDockIcon()return true end;function driver:RemoveRightDockIcon()return true end;function driver:ShowModules()self.home=true end;function driver:SetStatusText()end
assert(UI:SetDriver(driver))

local builds,refreshes=0,0
assert(UI:RegisterView({id="example.view",owner="example",localeName="Example",titleKey="TITLE",build=function(parentFrame)builds=builds+1;return region("view",parentFrame)end,refresh=function()refreshes=refreshes+1 end}))
assert(builds==1 and UI:GetView("example.view").owner=="example"and driver.pages["example.view"].title=="Localized title","view registration and localization")
local duplicate,duplicateReason=UI:RegisterView({id="example.view",owner="other",frame=region("duplicate")});assert(not duplicate and duplicateReason=="VIEW_ID_EXISTS","duplicate view IDs")
assert(UI:ShowView("example.view")and refreshes==1,"view show and refresh lifecycle")
assert(UI:RegisterView({id="fallback.view",owner="example",titleKey="MISSING_TITLE",frame=region("fallback")}));assert(driver.pages["fallback.view"].title=="fallback.view","localization fallback")
local optionalBuilds=0
assert(UI:RegisterView({id="optional.view",owner="optional",requires={module="missing"},build=function(parentFrame)optionalBuilds=optionalBuilds+1;return region("optional",parentFrame)end}))
assert(optionalBuilds==0 and not UI.pages["optional.view"]and not UI:ShowView("optional.view"),"missing optional module is harmless")
modules.missing=true;UI:RefreshViewAvailability("optional.view");assert(optionalBuilds==1 and UI.pages["optional.view"],"late optional module availability")
modules.missing=false;UI:RefreshViewAvailability("optional.view");assert(not UI.pages["optional.view"],"unavailable view detaches")
modules.missing=true;UI:RefreshViewAvailability("optional.view");assert(optionalBuilds==1 and UI.pages["optional.view"],"availability reuses the built frame")
assert(UI:UnregisterViewOwner("example")==2 and not UI:GetView("example.view"),"owner cleanup")

print("UI layout, table, resize, empty state, localization and declarative view tests passed")
