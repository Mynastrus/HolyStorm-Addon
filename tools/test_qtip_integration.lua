local repository=(arg[0]:gsub("tools[/\\]test_qtip_integration.lua$",""))
local uiRoot=repository.."LIVE/Holy_Storm_UI/"
local active={};local acquired,released=0,0
local function newTooltip(key)
 local tip={key=key,headers={},lines={}}
 function tip:SetColumnLayout(count,...)self.columnCount=count;self.justification={...}end
 function tip:ClearAllPoints()end
 function tip:SetPoint(point,owner,relativePoint,x,y)self.owner,self.anchor,self.relativePoint,self.x,self.y=owner,point,relativePoint,x,y end
 function tip:SmartAnchorTo(owner)self.owner,self.anchor=owner,"SMART"end
 function tip:AddHeader(...)self.headers[#self.headers+1]={...};return #self.headers end
 function tip:AddSeparator()self.separated=true end
 function tip:AddLine(...)self.lines[#self.lines+1]={...};return #self.lines end
 function tip:SetCellTextColor(line,column,...)self.colors=self.colors or{};self.colors[line..":"..column]={...}end
 function tip:Show()self.shown=true end
 function tip:Hide()self.shown=false end
 return tip
end
local library={}
function library:Acquire(key,...)
 local tip=active[key]or newTooltip(key);active[key]=tip;tip:SetColumnLayout(...);acquired=acquired+1;return tip
end
function library:Release(tip)if active[tip.key]==tip then active[tip.key]=nil;tip.released=true;released=released+1 end end
local window={}
function window:HookScript(event,callback)self[event]=callback end
local logoutFrame={}
function logoutFrame:RegisterEvent(event)self.event=event end
function logoutFrame:SetScript(event,callback)self[event]=callback end
function CreateFrame()return logoutFrame end
local HolyStorm={UI={driver={frame=window}}}
function LibStub(name,silent)
 if name=="AceAddon-3.0"then return{GetAddon=function()return HolyStorm end}end
 if name=="LibQTip-1.0"then return library end
 if silent then return nil end
 error("unexpected library "..tostring(name))
end
assert(loadfile(uiRoot.."UI/Framework/Tooltips.lua"))()
local source=assert(io.open(uiRoot.."Libs/LibQTip-1.0/LibQTip-1.0.lua","rb")):read("*a")
assert(source:find('local MAJOR = "LibQTip-1.0"',1,true)and source:find("local MINOR = 49",1,true),"embedded upstream source version")
local toc=assert(io.open(uiRoot.."Holy_Storm_UI.toc","rb")):read("*a")
assert(toc:find("Libs\\LibQTip-1.0\\LibQTip-1.0.lua",1,true),"central UI loading")
local raidToc=assert(io.open(repository.."LIVE/Holy_Storm_Raids/Holy_Storm_Raids.toc","rb")):read("*a")
assert(not raidToc:find("LibQTip",1,true),"Raid does not embed a second library copy")
local tooltipAdapter=assert(io.open(repository.."LIVE/Holy_Storm_Characters/UI/StoredFeatureTabs.lua","rb")):read("*a")
assert(not tooltipAdapter:find("HS_Player_DB",1,true)and not tooltipAdapter:find("HolyStormDB",1,true),"Raid tooltip does not access raw SavedVariables")
local owner={};local rows={{cells={"Boss A","M",12},colors={[2]={r=.7,g=.3,b=1}}}}
assert(HolyStorm.Tooltips:ShowTable("raid-best",owner,{anchor={point="LEFT",relativePoint="RIGHT",x=8,y=0},columns={{align="LEFT"},{align="CENTER"},{align="RIGHT"},},headers={{"Boss","Best","Kills"}},separator=true,rows=rows}))
local tip=active["HolyStorm:raid-best"]
assert(tip.owner==owner and tip.anchor=="LEFT"and tip.relativePoint=="RIGHT"and tip.x==8 and tip.columnCount==3 and tip.justification[2]=="CENTER","owner, anchor and column layout")
assert(tip.headers[1][1]=="Boss"and tip.lines[1][1]=="Boss A"and tip.lines[1][3]==12 and tip.colors["1:2"][1]==.7,"headers, cells and colors")
assert(window.OnHide,"main window hide is hooked")
assert(HolyStorm.Tooltips:ShowTable("raid-best",owner,{columns={{align="LEFT"}},rows={{"again"}}})and released==1,"reacquisition releases the previous tooltip")
assert(HolyStorm.Tooltips:ReleaseOwner(owner)and released==2 and not active["HolyStorm:raid-best"],"owner leave releases pooled tooltip")
assert(HolyStorm.Tooltips:ShowTable("raid-best",owner,{columns={{align="LEFT"}},rows={{"again"}}}));window.OnHide();assert(released==3 and not active["HolyStorm:raid-best"],"window close releases active tooltip")
assert(HolyStorm.Tooltips:ShowTable("raid-best",owner,{columns={{align="LEFT"}},rows={{"again"}}}));logoutFrame.OnEvent(logoutFrame,"PLAYER_LOGOUT");assert(released==4 and not active["HolyStorm:raid-best"],"reload/logout releases active tooltip")
assert(HolyStorm.Tooltips:Release("raid-best")==false,"repeated release is safe")
print("Central LibQTip loading, table helper, owner lifecycle and Raid embedding contracts passed")
