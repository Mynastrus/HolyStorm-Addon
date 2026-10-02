local script=arg[0]:gsub("\\","/")
local root=script:match("^(.*)/tools/[^/]+$")or"."
local uiRoot=root.."/LIVE/Holy_Storm_UI/"

local frames={}
local function region(kind,parent,template)
 local object={kind=kind,parent=parent,template=template,width=900,height=560,shown=true,scripts={},children={}}
 function object:SetParent(value)self.parent=value end
 function object:SetSize(width,height)self.width,self.height=width,height end
 function object:SetWidth(width)self.width=width end
 function object:SetHeight(height)self.height=height end
 function object:GetWidth()return self.width end
 function object:GetHeight()return self.height end
 function object:SetPoint()end
 function object:SetAllPoints()end
 function object:ClearAllPoints()end
 function object:SetScript(event,callback)self.scripts[event]=callback end
 function object:HookScript(event,callback)self.scripts[event]=callback end
 function object:CreateFontString()local text=region("font",self);self.children[#self.children+1]=text;return text end
 function object:CreateTexture()return region("texture",self)end
 function object:SetText(text,...)assert(select("#",...)==0,"button SetText receives only its text");self.text=text end
 function object:SetImage(value,...)self.image=value;self.imageArgs={...}end
 function object:SetImageSize()end
 function object:SetFontObject()end
 function object:SetFullWidth()end
 function object:SetRelativeWidth()end
 function object:SetJustifyH()end
 function object:SetLayout()end
 function object:AddChild(child)self.children[#self.children+1]=child end
 function object:DoLayout()end
 function object:Show()self.shown=true end
 function object:Hide()self.shown=false end
 function object:SetShown(value)self.shown=value end
 function object:EnableMouse()end
 function object:RegisterForDrag()end
 function object:SetFrameStrata()end
 function object:SetFrameLevel()end
 function object:SetClampedToScreen()end
 function object:SetClampRectInsets()end
 function object:SetMovable()end
 function object:SetResizable()end
 function object:RegisterForClicks()end
 function object:SetNormalTexture()end
 function object:SetResizeBounds()end
 function object:SetMinResize()end
 function object:StartSizing()end
 function object:StartMoving()end
 function object:StopMovingOrSizing()end
 function object:GetLeft()return 0 end
 function object:GetTop()return 560 end
 return object
end

local locale={WINDOW_TITLE="Holy Storm",WINDOW_TITLE_OPTIONS="Holy Storm Options",STATUS_BAR_READY="Holy Storm v%s - Ready",DASHBOARD_UPDATE_UNKNOWN="Update time unknown",DASHBOARD_REFRESH="Refresh data",DASHBOARD_REFRESH_TOOLTIP="Refresh character data through the normal scan workflow.",SYNC_RUNNING="Sync running",SYNC_TOOLTIP_TITLE="Synchronization activity",SYNC_CHARACTER="Character",SYNC_DOMAIN="Domain",SYNC_DOMAIN_EQUIPMENT="Equipment",SYNC_DIRECTION="Direction",SYNC_RECEIVE="Receive",SYNC_PHASE="Phase",SYNC_PHASE_TRANSFER="Transfer",SYNC_SOURCE="Source",SYNC_TARGET="Target",SYNC_REQUEST="Request ID",SYNC_REVISION="Revision",SYNC_BYTES="Bytes",SYNC_FRAGMENTS="Fragments",SYNC_RETRY="Retry",SYNC_QUEUE="Queue",SYNC_SEND="Send"}
local module={dashboardProviders={}}
local addon={version="DEV",Libraries={},Events={listeners={}}}
function addon.Events:Register(event,owner,callback)self.listeners[event]=callback end
function addon:RegisterRequiredModule()return module end
function addon:ApplyModuleMetadata()end
function addon:GetModule(id)if id=="UI"then return module end end
local driver
driver={SetDriver=function(_,value)driver.value=value end}
addon.UI=driver

local tooltip={text=nil,callCount=0}
function tooltip:SetOwner(owner,anchor)self.owner,self.anchor=owner,anchor end
function tooltip:SetText(text,...)
 local count=select("#",...);assert(count<=3,"Retail GameTooltip:SetText accepts color, alpha and wrap after its text")
 local color,alpha,wrap=...
 if count>=1 then assert(type(color)=="table","Retail tooltip color must be a Color object")end
 if count>=2 then assert(type(alpha)=="number","Retail tooltip alpha must be numeric")end
 if count>=3 then assert(type(wrap)=="boolean","Retail tooltip wrap must be boolean")end
 self.text=text;self.callCount=self.callCount+1
end
function tooltip:Show()self.shown=true end
function tooltip:Hide()self.shown=false end
function tooltip:AddDoubleLine(left,right)self.lines=self.lines or{};self.lines[#self.lines+1]={left=left,right=right}end

function LibStub(name)
 if name=="AceAddon-3.0"then return{GetAddon=function()return addon end}end
 if name=="AceLocale-3.0"then return{GetLocale=function()return locale end}end
 if name=="AceGUI-3.0"then return{Create=function(_,kind)local frame=region("ace:"..kind);local widget=region("widget:"..kind);widget.frame=frame;if kind=="Icon"then widget.image=region("texture",frame)end;return widget end}end
 error("Unexpected library "..name)
end
function CreateFrame(kind,name,parent,template)local value=region(kind,parent,template);value.name=name;frames[#frames+1]=value;return value end

UIParent=region("parent")
UISpecialFrames={}
function tContains(values,wanted)for _,value in ipairs(values)do if value==wanted then return true end end;return false end
GameTooltip=tooltip
GameFontNormalSmallOutline={};GameFontHighlightSmall={};GameFontHighlightLarge={};GameFontHighlight={};GameFontNormal={}

assert(loadfile(uiRoot.."UI/Framework/MainWindow.lua"))()
local dashboardBuilt=false
module.BuildHomeDashboard=function(_,parent,widgets)dashboardBuilt=parent~=nil and widgets.classIcon~=nil and widgets.specIcon~=nil end
module.LoadWindowState=function()end
module.CreateRightDock=function()end
module.RegisterDashboardEvents=function()end
module.SetRightDockVisible=function()end
module.RefreshDashboard=function()module.dashboardRefreshed=true end
module.SaveWindowSize=function()end
module.SaveWindowPosition=function()end
module:OnInitialize()

assert(dashboardBuilt and module.dashboardRefreshed,"MainWindow creates the existing dashboard and proceeds through initialization")
assert(module.windowTitle and module.windowTitle.text==locale.WINDOW_TITLE,"the localized Holy Storm window title is assigned")
local refreshButton
for _,frame in ipairs(frames)do if frame.template=="UIPanelButtonTemplate"then refreshButton=frame;break end end
assert(refreshButton and refreshButton.text==locale.DASHBOARD_REFRESH,"refresh button receives its localized caption")
assert(not module.syncActivityButton.shown and module.syncActivityLabel.text==locale.SYNC_RUNNING,"sync activity is completely hidden at idle while retaining its active label")
addon.Sync={GetActivity=function()return{active=true,queuedJobs=4,activeOperations={{characterUUID="Character-1",domain="equipment",direction="RECEIVE",phase="TRANSFER",sender="Source-Realm",receiver="Local-Realm",requestId="request-1",revision=27,bytes=12000,fragments=58,fragmentsTotal=139,retryCount=1,maxRetries=3,queuePosition=1}}}end}
assert(module:RefreshSyncActivity()and module.syncActivityButton.shown,"the statusbar appears only when the central model reports an active transfer")
module.syncActivityButton.scripts.OnEnter(module.syncActivityButton);assert(tooltip.shown and tooltip.text==locale.SYNC_TOOLTIP_TITLE and tooltip.lines[1].right=="Character-1"and tooltip.lines[10].right=="58 / 139","the active tooltip exposes localized technical activity details");module.syncActivityButton.scripts.OnLeave();addon.Sync.GetActivity=function()return{active=false,queuedJobs=0,activeOperations={}}end;assert(not module:RefreshSyncActivity()and not module.syncActivityButton.shown,"the statusbar becomes empty again when the last transfer ends")
local onEnter=assert(refreshButton.scripts.OnEnter,"refresh tooltip handler is installed")
onEnter(refreshButton)
assert(tooltip.callCount==2 and tooltip.text==locale.DASHBOARD_REFRESH_TOOLTIP,"hover assigns the localized tooltip using only supported Retail arguments")

print("MainWindow Retail tooltip SetText contract and initialization regression passed")
