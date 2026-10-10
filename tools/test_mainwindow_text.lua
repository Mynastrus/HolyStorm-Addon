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
 function object:SetPoint(...)self.points=self.points or{};self.points[#self.points+1]={...}end
 function object:SetAllPoints(target)self.allPoints=target or self.parent end
 function object:ClearAllPoints()self.points={}end
 function object:SetScript(event,callback)self.scripts[event]=callback end
 function object:HookScript(event,callback)self.scripts[event]=callback end
 function object:CreateFontString()local text=region("font",self);self.children[#self.children+1]=text;return text end
 function object:CreateTexture()return region("texture",self)end
 function object:SetText(text,...)assert(select("#",...)==0,"button SetText receives only its text");self.text=text end
 function object:SetOwner(owner,anchor)self.owner,self.anchor=owner,anchor end
 function object:ClearLines()self.text=nil;self.lines={}end
 function object:AddLine(text,r,g,b,wrap)self.lines=self.lines or{};self.lines[#self.lines+1]={text=text,r=r,g=g,b=b,wrap=wrap}end
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
 function object:IsShown()return self.shown end
 function object:EnableMouse()end
 function object:RegisterForDrag()end
 function object:SetFrameStrata()end
 function object:SetFrameLevel()end
 function object:SetClampedToScreen(value)self.clampedToScreen=value end
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

local locale={WINDOW_TITLE="Holy Storm",WINDOW_TITLE_OPTIONS="Holy Storm Options",STATUS_BAR_READY="Holy Storm v%s - Ready",DASHBOARD_UPDATE_UNKNOWN="Update time unknown",DASHBOARD_REFRESH="Refresh data",DASHBOARD_REFRESH_TOOLTIP="Refresh character data through the normal scan workflow.",SYNC_RUNNING="Sync running",SYNC_TOOLTIP_TITLE="Synchronization activity",SYNC_ACTIVITY_CHARACTER="Character data is being synchronized",SYNC_ACTIVITY_POI="POIs are being synchronized",SYNC_ACTIVITY_POSITIONS="Position data is being synchronized",SYNC_ACTIVITY_TRANSFER="Synchronization data is being transferred"}
local module={dashboardProviders={}}
local addon={version="DEV",Libraries={},Events={listeners={}},Utils={SafeCall=function(_,callback,...)return pcall(callback,...)end}}
function addon.Events:Register(event,owner,callback)self.listeners[event]=callback end
function addon:RegisterRequiredModule()return module end
function addon:ApplyModuleMetadata()end
function addon:GetModule(id)if id=="UI"then return module end end
local driver
driver={SetDriver=function(_,value)driver.value=value end}
addon.UI=driver

local tooltip={text=nil,callCount=0}
function tooltip:SetOwner(owner,anchor)self.owner,self.anchor=owner,anchor end
function tooltip:ClearLines()self.lines={}end
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
function tooltip:AddLine(text,r,g,b,wrap)self.lines=self.lines or{};self.lines[#self.lines+1]={text=text,wrap=wrap}end
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
local headerBuilds,headerLayouts=0,0
assert(module.contextHeaderSlot and module.contextHeaderSlot.parent==module.contentInset and module.content.parent==module.contextHeaderSlot.parent,"the page context header slot is a framework sibling above the page content")
local function headerDefinition(baseHeight)
 return{
  height=function(width)return width<800 and baseHeight+30 or baseHeight end,
  build=function(parent)headerBuilds=headerBuilds+1;assert(parent.parent==module.contextHeaderSlot,"header contents are parented to the central context slot")end,
  layout=function(_,width,height)headerLayouts=headerLayouts+1;assert(height==(width<800 and baseHeight+30 or baseHeight),"context header relayout receives current dimensions")end,
 }
end
assert(module:RegisterPageContextHeader("character","characters",headerDefinition(40)))
assert(module:RegisterPageContextHeader("guildRoster","GuildRoster",headerDefinition(50)))
local characterPage=CreateFrame("Frame",nil,module.content);local rosterPage=CreateFrame("Frame",nil,module.content);local plainPage=CreateFrame("Frame",nil,module.content)
module:RegisterPage("character",characterPage,"Character");module:RegisterPage("guildRoster",rosterPage,"Roster");module:RegisterPage("plain",plainPage,"Plain")
module.SetRightDockSelected=function()end
module:ShowPage("character")
local characterHeader=module.pageContextHeaders.character.frame;local rosterHeader=module.pageContextHeaders.guildRoster.frame
assert(headerBuilds==2 and headerLayouts==1 and module.contextHeaderSlot:IsShown()and module.contextHeaderSlot:GetHeight()==40 and characterHeader:IsShown()and not rosterHeader:IsShown(),"Character Overview activates its own non-scrolling context header")
assert(module.content.points[1][5]==-51 and module.content.points[2][1]=="BOTTOMRIGHT"and module.content.points[2][4]==-5 and module.content.points[2][5]==30 and module.scroll.frame.allPoints==module.content,"Character content begins below its context header and keeps the complete remaining window height")
module:ShowPage("guildRoster")
assert(headerLayouts==2 and module.contextHeaderSlot:GetHeight()==50 and not characterHeader:IsShown()and rosterHeader:IsShown()and module.content.points[1][5]==-61,"switching to the roster replaces the Character header and moves content below the roster header")
module.contextHeaderSlot:SetWidth(700);module.contextHeaderSlot.scripts.OnSizeChanged(module.contextHeaderSlot,700)
assert(headerLayouts==3 and module.contextHeaderSlot:GetHeight()==80 and module.content.points[1][5]==-91,"resizing recalculates roster header height and page content position")
module:ShowPage("plain")
assert(not module.contextHeaderSlot:IsShown()and not characterHeader:IsShown()and not rosterHeader:IsShown()and module.content.points[1][5]==-5 and module.content.points[2][5]==30,"switching to a page without a context header releases its space")
module:ShowModules()
assert(module.windowTitle and module.windowTitle.text==locale.WINDOW_TITLE,"the localized Holy Storm window title is assigned")
local refreshButton
for _,frame in ipairs(frames)do if frame.template=="UIPanelButtonTemplate"then refreshButton=frame;break end end
assert(refreshButton and refreshButton.text==locale.DASHBOARD_REFRESH,"refresh button receives its localized caption")
assert(not module.syncActivityButton.shown and module.syncActivityLabel.text==locale.SYNC_RUNNING,"sync activity is completely hidden at idle while retaining its active label")
local longIdentifier=string.rep("character/object/UUID-",1000)
addon.Sync={GetActivity=function()return{active=true,queuedJobs=4,activeOperations={{characterUUID=longIdentifier,entity=longIdentifier,domain="equipment",direction="RECEIVE",phase="TRANSFER",sender=longIdentifier,receiver=longIdentifier,requestId=longIdentifier,revision=longIdentifier,bytes=12000,fragments=58,fragmentsTotal=139,retryCount=1,maxRetries=3,queuePosition=1}}}end}
assert(module:RefreshSyncActivity()and module.syncActivityButton.shown,"the statusbar appears only when the central model reports an active transfer")
local syncTooltip=module.syncActivityTooltip
local tooltipCallsBeforeSync=tooltip.callCount
module.syncActivityButton.scripts.OnEnter(module.syncActivityButton)
assert(syncTooltip==GameTooltip and syncTooltip.shown and syncTooltip.text==locale.SYNC_TOOLTIP_TITLE and #syncTooltip.lines==1 and syncTooltip.lines[1].text==locale.SYNC_ACTIVITY_CHARACTER and syncTooltip.lines[1].wrap==true,"character activity uses the shared Blizzard tooltip with separate, wrappable localized lines")
assert(syncTooltip.owner==module.syncActivityButton and syncTooltip.anchor=="ANCHOR_TOP" and not syncTooltip.lines[1].text:find(longIdentifier,1,true),"the statusbar button is the external owner and long IDs never enter tooltip content")
module.syncActivityButton.scripts.OnLeave()
assert(not syncTooltip.shown,"leaving the statusbar hides the shared tooltip")
addon.Sync.GetActivity=function()return{active=true,queuedJobs=0,activeOperations={{domain="poi",entity="poi@"..longIdentifier,requestId=longIdentifier}}}end
module.syncActivityButton.scripts.OnEnter(module.syncActivityButton)
assert(#syncTooltip.lines==1 and syncTooltip.lines[1].text==locale.SYNC_ACTIVITY_POI and not syncTooltip.lines[1].text:find(longIdentifier,1,true),"POI identifiers are summarized without appearing in the tooltip")
addon.Sync.GetActivity=function()return{active=true,queuedJobs=0,activeOperations={{domain="guild-position",entity=longIdentifier}}}end
module.syncActivityButton.scripts.OnEnter(module.syncActivityButton)
assert(syncTooltip.lines[1].text==locale.SYNC_ACTIVITY_POSITIONS,"position activity gets a localized summary")
addon.Sync.GetActivity=function()return{active=true,queuedJobs=0,activeOperations={{domain="snapshot",entity=longIdentifier,requestId=longIdentifier}}}end
module.syncActivityButton.scripts.OnEnter(module.syncActivityButton)
assert(syncTooltip.lines[1].text==locale.SYNC_ACTIVITY_TRANSFER and #syncTooltip.lines==1,"other sync-v2 activity uses one generic localized line")
module.syncActivityButton.scripts.OnLeave()
addon.Sync.GetActivity=function()return{active=false,queuedJobs=0,activeOperations={}}end
assert(not module:RefreshSyncActivity()and not module.syncActivityButton.shown,"the statusbar becomes empty again when the last transfer ends")
local onEnter=assert(refreshButton.scripts.OnEnter,"refresh tooltip handler is installed")
onEnter(refreshButton)
assert(tooltip.callCount==tooltipCallsBeforeSync+5 and tooltip.text==locale.DASHBOARD_REFRESH_TOOLTIP,"status and refresh hovers use supported Retail tooltip calls")

print("MainWindow Retail tooltip SetText contract and initialization regression passed")
