local addonVersion="1.0.0"
local HolyStorm=LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local L=LibStub("AceLocale-3.0"):GetLocale("Holy_Storm_TaskManager")
local Page=HolyStorm:RegisterRequiredModule("TaskManagerUI")
HolyStorm:ApplyModuleMetadata(Page,{displayName=L["DISPLAY_NAME"],internalName="taskManagerUI",version=addonVersion,category="required",description=L["DESCRIPTION"],permissions={"tasks-view"},dependencies={"core","ui"},enabledByDefault=true})
local views={"LIVE_TASKS","QUEUE","WORKFLOWS","HISTORY","PERFORMANCE","EVENT_MONITOR","DEPENDENCIES"}
local ROW_HEIGHT=20
local MAX_VISIBLE_ROWS=32
local REFRESH_DELAY=.1
local refreshEvents={"HS_TASK_QUEUED","HS_TASK_MERGED","HS_TASK_STARTED","HS_TASK_WAITING","HS_TASK_BLOCKED","HS_TASK_COMPLETED","HS_TASK_FAILED","HS_TASK_CANCELLED","HS_TASK_QUEUE_PAUSED","HS_TASK_QUEUE_RESUMED","HS_WORKFLOW_QUEUED","HS_WORKFLOW_STARTED","HS_WORKFLOW_STEP_CHANGED","HS_WORKFLOW_WAITING","HS_WORKFLOW_PAUSED","HS_WORKFLOW_COMPLETED","HS_WORKFLOW_FAILED","HS_WORKFLOW_CANCELLED","HS_WORKFLOW_RESTART_PENDING"}
local columns={
 LIVE_TASKS={{"status","COL_STATUS",86},{"name","COL_TASK",150},{"module","COL_MODULE",90},{"workflow","COL_WORKFLOW",135},{"priority","COL_PRIORITY",58},{"triggers","COL_TRIGGERS",58},{"created","COL_CREATED",72},{"waiting","COL_WAITING",62},{"runtime","COL_RUNTIME",62},{"block","COL_BLOCK",150}},
 QUEUE={{"position","QUEUE",45},{"status","COL_STATUS",78},{"name","COL_TASK",170},{"module","COL_MODULE",90},{"workflow","COL_WORKFLOW",140},{"priority","COL_PRIORITY",58},{"triggers","COL_TRIGGERS",58},{"waiting","COL_WAITING",70},{"block","COL_BLOCK",165}},
 WORKFLOWS={{"status","COL_STATUS",86},{"name","COL_WORKFLOW",170},{"module","COL_MODULE",90},{"step","COL_STEP",155},{"progress","COL_PROGRESS",76},{"restart","COL_RESTART",85},{"runtime","COL_RUNTIME",70},{"triggers","COL_TRIGGERS",60}},
 HISTORY={{"status","COL_STATUS",86},{"kind","DETAILS",82},{"name","COL_TASK",190},{"module","COL_MODULE",100},{"workflow","COL_WORKFLOW",150},{"runtime","COL_RUNTIME",75},{"triggers","COL_TRIGGERS",65},{"block","COL_BLOCK",170}},
 PERFORMANCE={{"name","COL_TASK",180},{"module","COL_MODULE",90},{"workflow","COL_WORKFLOW",120},{"runs","COL_RUNS",55},{"average","COL_AVERAGE",70},{"maximum","COL_MAXIMUM",70},{"errors","COL_ERRORS",55},{"merges","COL_MERGES",80},{"triggers","COL_TRIGGERS",65}},
 EVENT_MONITOR={{"created","COL_CREATED",80},{"event","COL_EVENT",220},{"module","COL_MODULE",120},{"workflow","COL_WORKFLOW",170},{"name","COL_TASK",180}},
 DEPENDENCIES={{"status","COL_STATUS",90},{"name","COL_TASK",220},{"dependency","COL_DEPENDENCY",260},{"workflow","COL_WORKFLOW",180}},
}
local function elapsed(started,finished)if not started then return"-"end;return string.format("%.2fs",math.max(0,(finished or HolyStorm.Utils.Now())-started))end
local function stamp(value)return value and date("%H:%M:%S",value)or"-"end
local function yes(value)return value and L["TRUE"]or L["FALSE"]end
local function status(value)return L["STATUS_"..tostring(value)]or tostring(value or"-")end
local function reason(value)if not value then return"-"end;local kind,id=tostring(value):match("^([A-Z_]+):(.*)$");if kind and L["REASON_"..kind]then return string.format(L["REASON_"..kind],id)end;return L["REASON_"..tostring(value)]or tostring(value)end
local function flatten(value,depth,seen)
 if type(value)~="table"then return tostring(value==nil and"-"or value)end;depth=depth or 0;seen=seen or{};if seen[value]then return"<"..L["CYCLE"]..">"end;if depth>=4 then return"<"..L["NESTED_TRUNCATED"]..">"end;seen[value]=true;local out={};for k,v in pairs(value)do out[#out+1]=tostring(k).."="..flatten(v,depth+1,seen)end;seen[value]=nil;table.sort(out);return"{"..table.concat(out,", ").."}"
end
local fieldLabels={uniqueId="FIELD_UNIQUE_ID",registryId="FIELD_REGISTRY_ID",workflowId="FIELD_WORKFLOW_ID",workflowType="FIELD_WORKFLOW_TYPE",status="FIELD_STATUS",module="FIELD_MODULE",priority="FIELD_PRIORITY",currentTask="FIELD_CURRENT_TASK",currentStep="FIELD_CURRENT_STEP",blockReason="FIELD_BLOCK_REASON",lastError="FIELD_LAST_ERROR",createdAt="FIELD_CREATED_AT",startedAt="FIELD_STARTED_AT",finishedAt="FIELD_FINISHED_AT",triggerCount="FIELD_TRIGGER_COUNT",pendingRestart="FIELD_PENDING_RESTART"}
local function matches(row,search,module,workflow)local hay=string.lower(table.concat({row.name or"",row.module or"",row.status or"",row.workflow or"",row.event or"",row.block or""}," "));return(search==""or hay:find(search,1,true))and(module==""or string.lower(row.module or""):find(module,1,true))and(workflow==""or string.lower(row.workflow or""):find(workflow,1,true))end

function Page:GetLayout(view)
 local root=HolyStorm.db.profile.taskManager;root.columns=root.columns or{};root.columns[view]=root.columns[view]or{widths={},hidden={},order={}};return root.columns[view]
end
function Page:GetColumns()
 local defs=columns[self.view];local layout=self:GetLayout(self.view);local byKey={};for _,d in ipairs(defs)do byKey[d[1]]=d end;local result={}
 for _,key in ipairs(layout.order)do if byKey[key]then result[#result+1]=byKey[key];byKey[key]=nil end end;for _,d in ipairs(defs)do if byKey[d[1]]then result[#result+1]=d end end;return result
end
function Page:BuildData()
 local rows={};local taskMap={}
 if self.view=="LIVE_TASKS"or self.view=="DEPENDENCIES"then
  for _,t in ipairs(HolyStorm.Tasks:GetLiveTasks())do taskMap[t.uniqueId]=t;if self.view=="DEPENDENCIES"then for _,dep in ipairs(t.dependencies or{})do rows[#rows+1]={status=status(t.status),name=t.name,dependency=type(dep)=="table"and(dep.taskId or dep.registryId)or dep,workflow=t.workflowId or"-",object=t,kind="task"}end end;if self.view=="LIVE_TASKS"then rows[#rows+1]={status=status(t.status),name=t.name,module=t.module,workflow=t.workflowId or"-",priority=t.priority,triggers=t.triggerCount,created=stamp(t.createdAt),waiting=elapsed(t.queuedAt,t.startedAt),runtime=elapsed(t.startedAt,t.finishedAt),block=reason(t.blockReason),object=t,kind="task"}end end
 elseif self.view=="QUEUE"then for i,t in ipairs(HolyStorm.Tasks:GetQueue())do rows[#rows+1]={position=i,status=status(t.status),name=t.name,module=t.module,workflow=t.workflowId or"-",priority=t.priority,triggers=t.triggerCount,waiting=elapsed(t.queuedAt),block=reason(t.blockReason),object=t,kind="task"}end
 elseif self.view=="WORKFLOWS"then for _,w in ipairs(HolyStorm.Workflows:GetLive())do rows[#rows+1]={status=status(w.status),name=w.name,module=w.module,step=w.currentTask or"-",progress=string.format("%d/%d",#w.completedTasks,w.totalTasks or 0),restart=yes(w.pendingRestart),runtime=elapsed(w.startedAt,w.finishedAt),triggers=w.triggerCount,workflow=w.workflowId,object=w,kind="workflow"}end
 elseif self.view=="HISTORY"then
  for _,t in ipairs(HolyStorm.Tasks:GetHistory())do rows[#rows+1]={status=status(t.status),kind=L["KIND_TASK"],name=t.name,module=t.module,workflow=t.workflowId or"-",runtime=elapsed(t.startedAt,t.finishedAt),triggers=t.triggerCount,block=reason(t.lastError),object=t,objectKind="task"}end
  for _,w in ipairs(HolyStorm.Workflows:GetHistory())do rows[#rows+1]={status=status(w.status),kind=L["KIND_WORKFLOW"],name=w.name,module=w.module,workflow=w.workflowId,runtime=elapsed(w.startedAt,w.finishedAt),triggers=w.triggerCount,block=reason(w.lastError),object=w,objectKind="workflow"}end
 elseif self.view=="PERFORMANCE"then for id,p in pairs(HolyStorm.Tasks:GetPerformance())do rows[#rows+1]={name=id,module=p.module,workflow="-",runs=p.runs,average=string.format("%.3fs",p.averageDuration),maximum=string.format("%.3fs",p.maxDuration),errors=p.errors,merges=p.merges,triggers=p.triggers,kind="performance",object=p}end;for id,p in pairs(HolyStorm.Workflows:GetPerformance())do rows[#rows+1]={name=id,module=p.module,workflow=id,runs=p.runs,average=string.format("%.3fs",p.averageDuration),maximum=string.format("%.3fs",p.maxDuration),errors=p.errors,merges=p.merges,triggers=p.triggers,kind="performance",object=p}end
 elseif self.view=="EVENT_MONITOR"then local events=HolyStorm.Tasks:GetEventHistory();for i=#events,1,-1 do local e=events[i];rows[#rows+1]={created=stamp(e.timestamp),event=e.event,module=e.module,workflow=e.workflowId or"-",name=e.triggeredTask or e.taskId or"-",kind="event",object=e}end end
 local search=string.lower(self.search:GetText()or"");local module=string.lower(self.moduleFilter:GetText()or"");local workflow=string.lower(self.workflowFilter:GetText()or"");local filtered={};for _,row in ipairs(rows)do if matches(row,search,module,workflow)then filtered[#filtered+1]=row end end
 local key=self.sortKey;if key then table.sort(filtered,function(a,b)local av,bv=a[key],b[key];if av==bv then return tostring(a.name or"")<tostring(b.name or"")end;if self.sortAscending then return tostring(av or"")<tostring(bv or"")else return tostring(av or"")>tostring(bv or"")end end)end;return filtered
end
function Page:MoveColumn(key,direction)local layout=self:GetLayout(self.view);local defs=self:GetColumns();layout.order={};local index;for i,d in ipairs(defs)do layout.order[i]=d[1];if d[1]==key then index=i end end;if index then local target=math.max(1,math.min(#layout.order,index+direction));layout.order[index],layout.order[target]=layout.order[target],layout.order[index]end;self:Render()end
function Page:HeaderClick(key,button)if button=="RightButton"then self:GetLayout(self.view).hidden[key]=true;self:Render();return end;if IsShiftKeyDown()then self:MoveColumn(key,-1);return elseif IsControlKeyDown()then self:MoveColumn(key,1);return end;if self.sortKey==key then self.sortAscending=not self.sortAscending else self.sortKey,self.sortAscending=key,true end;self:RenderRows()end
function Page:BuildHeaders()
 for _,h in ipairs(self.headers)do h:Hide()end;local x=0;local layout=self:GetLayout(self.view)
 for _,d in ipairs(self:GetColumns())do if not layout.hidden[d[1]]then local h=self.headers[#self.visibleHeaders+1]or CreateFrame("Button",nil,self.header,"BackdropTemplate");self.headers[#self.visibleHeaders+1]=h;self.visibleHeaders[#self.visibleHeaders+1]=h;h:Show();h:ClearAllPoints();h:SetPoint("TOPLEFT",x,0);local width=layout.widths[d[1]]or d[3];h:SetSize(width,22);h:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8x8"});h:SetBackdropColor(.12,.12,.12,.95);h:RegisterForClicks("LeftButtonUp","RightButtonUp");h:SetScript("OnClick",function(_,button)Page:HeaderClick(d[1],button)end);h.text=h.text or h:CreateFontString(nil,"OVERLAY","GameFontNormalSmall");h.text:ClearAllPoints();h.text:SetPoint("LEFT",4,0);h.text:SetPoint("RIGHT",-7,0);h.text:SetText(L[d[2]]or d[2]);h.text:SetJustifyH("LEFT")
   h:SetScript("OnEnter",function(self)GameTooltip:SetOwner(self,"ANCHOR_TOP");GameTooltip:SetText(L["HEADER_HINT"]);GameTooltip:Show()end);h:SetScript("OnLeave",function()GameTooltip:Hide()end)
   local grip=h.grip or CreateFrame("Button",nil,h);h.grip=grip;grip:SetPoint("TOPRIGHT");grip:SetPoint("BOTTOMRIGHT");grip:SetWidth(6);grip:SetScript("OnMouseDown",function()grip.startX=GetCursorPosition()/UIParent:GetEffectiveScale();grip.startWidth=h:GetWidth();grip:SetScript("OnUpdate",function()local current=GetCursorPosition()/UIParent:GetEffectiveScale();layout.widths[d[1]]=math.max(40,grip.startWidth+current-grip.startX);h:SetWidth(layout.widths[d[1]])end)end);grip:SetScript("OnMouseUp",function()grip:SetScript("OnUpdate",nil);Page:Render()end);x=x+width+1 end end
 GameTooltip:Hide()
end
function Page:ShowDetails(row)
 self.selected=row;local o=row and row.object;if not o then self.detail:SetText(L["NO_SELECTION"]);return end;local lines={L["DETAILS"]..": "..tostring(row.name or row.event or"-")}
 for _,key in ipairs({"uniqueId","registryId","workflowId","workflowType","status","module","priority","currentTask","currentStep","blockReason","lastError","createdAt","startedAt","finishedAt","triggerCount","pendingRestart"})do if o[key]~=nil then local value=o[key];if key=="status"then value=status(value)elseif key=="blockReason"or key=="lastError"then value=reason(value)end;lines[#lines+1]=(L[fieldLabels[key]]or key)..": "..tostring(value)end end
 if o.triggerSources then lines[#lines+1]=L["TRIGGER_SOURCES"]..": "..flatten(o.triggerSources)end;if o.triggerHistory then lines[#lines+1]=L["TRIGGER_HISTORY"]..": "..flatten(o.triggerHistory)end;if o.conditions then lines[#lines+1]=L["CONDITIONS"]..": "..flatten(o.conditions)end;if o.dependencies then lines[#lines+1]=L["TASK_DEPENDENCIES"]..": "..flatten(o.dependencies)end;if o.executionMode then lines[#lines+1]=L["MERGE_MODE"]..": "..o.executionMode end;if o.retryCount then lines[#lines+1]=L["RETRIES"]..": "..o.retryCount.."/"..(o.maxRetries or 0)end;if o.taskOrder then lines[#lines+1]=L["TASK_ORDER"]..": "..flatten(o.taskOrder)end;if o.completedTasks then lines[#lines+1]=L["COMPLETED_TASKS"]..": "..flatten(o.completedTasks)end;if o.pendingTasks then lines[#lines+1]=L["PENDING_TASKS"]..": "..flatten(o.pendingTasks)end;if o.tasks then lines[#lines+1]=L["WORKFLOW_TASKS"]..": "..flatten(o.tasks)end;if o.metadata then lines[#lines+1]=L["METADATA"]..": "..flatten(o.metadata)end
 local correlation=o.workflowId or o.uniqueId;if correlation then local logs={};for _,e in ipairs(HolyStorm.Logger:GetHistory())do if e.correlationId==correlation or e.context and(e.context.taskId==o.uniqueId or e.context.workflowId==correlation)then logs[#logs+1]=string.format("[%s/%s] %s",e.level,e.source,e.message)end end;if#logs>0 then lines[#lines+1]=L["LOGS"]..":";for i=math.max(1,#logs-5),#logs do lines[#lines+1]=logs[i]end end end;self.detail:SetText(table.concat(lines,"\n"))
end
function Page:RenderRows(rebuildData)
 if self.paintingRows then return end
 self.paintingRows=true
 if rebuildData~=false then self.data=self:BuildData()end
 local data=self.data or{}
 for _,r in ipairs(self.rows)do r:Hide()end
 local defs=self:GetColumns()
 local layout=self:GetLayout(self.view)
 local totalHeight=math.max(1,#data*ROW_HEIGHT)
 self.rowContent:SetHeight(totalHeight)
 if#data==0 then self.empty:Show()else self.empty:Hide()end
 local scrollOffset=self.scroll and self.scroll:GetVerticalScroll()or 0
 local viewportHeight=self.scroll and self.scroll:GetHeight()or 300
 local maxScroll=math.max(0,totalHeight-viewportHeight)
 scrollOffset=math.max(0,math.min(scrollOffset,maxScroll))
 local firstIndex=math.floor(scrollOffset/ROW_HEIGHT)+1
 local visibleCount=math.min(MAX_VISIBLE_ROWS,math.ceil(viewportHeight/ROW_HEIGHT)+2)
 for slot=1,visibleCount do
  local dataIndex=firstIndex+slot-1
  local row=data[dataIndex]
  if not row then break end
  local r=self.rows[slot]
  if not r then
   r=CreateFrame("Button",nil,self.rowContent)
   r:SetHeight(ROW_HEIGHT)
   r.cells={}
   r.highlight=r:CreateTexture(nil,"BACKGROUND")
   r.highlight:SetAllPoints()
   r.highlight:SetColorTexture(.15,.35,.5,.22)
   r:SetHighlightTexture(r.highlight)
   self.rows[slot]=r
  end
  r:Show()
  r:ClearAllPoints()
  r:SetPoint("TOPLEFT",0,-((dataIndex-1)*ROW_HEIGHT))
  r:SetPoint("RIGHT",self.rowContent,"RIGHT")
  r:SetScript("OnClick",function()Page:ShowDetails(row)end)
  local x,cellIndex=0,0
  for _,d in ipairs(defs)do
   if not layout.hidden[d[1]]then
    cellIndex=cellIndex+1
    local cell=r.cells[cellIndex]or r:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    r.cells[cellIndex]=cell
    cell:Show()
    cell:ClearAllPoints()
    local width=layout.widths[d[1]]or d[3]
    cell:SetPoint("TOPLEFT",x+4,-3)
    cell:SetWidth(width-8)
    cell:SetJustifyH("LEFT")
    cell:SetWordWrap(false)
    cell:SetText(tostring(row[d[1]]or"-"))
    x=x+width+1
   end
  end
  for n=cellIndex+1,#r.cells do r.cells[n]:Hide()end
 end
 if rebuildData~=false then self:ShowDetails(self.selected)end
 self.paintingRows=false
end
function Page:RequestRefresh()
 if not self.page or not self.page:IsShown()then HolyStorm.UI:MarkDirty("taskManager",true);return end
 if self.refreshPending then return end
 self.refreshPending=true
 self.refreshElapsed=0
 self.page:SetScript("OnUpdate",function(frame,delta)
  Page.refreshElapsed=Page.refreshElapsed+delta
  if Page.refreshElapsed<REFRESH_DELAY then return end
  frame:SetScript("OnUpdate",nil)
  Page.refreshPending=false
  HolyStorm.UI:MarkDirty("taskManager")
 end)
end
function Page:Render()if not self.page:IsShown()or not HolyStorm.Policy:Can("taskmanager-view")and not HolyStorm.Policy:Can("tasks-view")then return end;self.visibleHeaders={};self:BuildHeaders();self:RenderRows();self.pause:SetText(HolyStorm.Tasks:IsPaused()and L["RESUME"]or L["PAUSE"])
end
function Page:SelectView(view)self.view=view;self.selected=nil;if self.scroll then self.scroll:SetVerticalScroll(0)end;for key,b in pairs(self.tabs)do b:SetEnabled(key~=view)end;self:Render()end
local function button(parent,text,width,point,callback)local b=CreateFrame("Button",nil,parent,"UIPanelButtonTemplate");b:SetSize(width,23);b:SetPoint(unpack(point));b:SetText(text);b:SetScript("OnClick",callback);return b end
function Page:OnInitialize()
 local UI=HolyStorm:GetModule("UI",true);local p=CreateFrame("Frame",nil,UI.content);self.page=p;self.view="LIVE_TASKS";self.headers,self.rows,self.tabs={}, {}, {}
 local searchLabel=p:CreateFontString(nil,"OVERLAY","GameFontNormalSmall");searchLabel:SetPoint("TOPLEFT",14,-10);searchLabel:SetText(L["SEARCH"]);local search=CreateFrame("EditBox",nil,p,"InputBoxTemplate");search:SetSize(155,22);search:SetPoint("TOPLEFT",14,-28);search:SetAutoFocus(false);search:SetScript("OnTextChanged",function()Page:RenderRows()end);self.search=search
 local moduleLabel=p:CreateFontString(nil,"OVERLAY","GameFontNormalSmall");moduleLabel:SetPoint("TOPLEFT",180,-10);moduleLabel:SetText(L["MODULE_FILTER"]);local module=CreateFrame("EditBox",nil,p,"InputBoxTemplate");module:SetSize(110,22);module:SetPoint("TOPLEFT",180,-28);module:SetAutoFocus(false);module:SetScript("OnTextChanged",function()Page:RenderRows()end);self.moduleFilter=module
 local workflowLabel=p:CreateFontString(nil,"OVERLAY","GameFontNormalSmall");workflowLabel:SetPoint("TOPLEFT",305,-10);workflowLabel:SetText(L["WORKFLOW_FILTER"]);local workflow=CreateFrame("EditBox",nil,p,"InputBoxTemplate");workflow:SetSize(110,22);workflow:SetPoint("TOPLEFT",305,-28);workflow:SetAutoFocus(false);workflow:SetScript("OnTextChanged",function()Page:RenderRows()end);self.workflowFilter=workflow
 button(p,L["RESET_COLUMNS"],130,{"TOPLEFT",430,-27},function()HolyStorm.db.profile.taskManager.columns[Page.view]=nil;Page:Render()end)
 for index,view in ipairs(views)do local x=14+((index-1)%4)*150;local y=-58-math.floor((index-1)/4)*26;local b=button(p,L[view],145,{"TOPLEFT",x,y},function()Page:SelectView(view)end);self.tabs[view]=b end
 local header=CreateFrame("Frame",nil,p);header:SetPoint("TOPLEFT",14,-114);header:SetPoint("TOPRIGHT",-28,-114);header:SetHeight(22);self.header=header
 local scroll=CreateFrame("ScrollFrame",nil,p,"UIPanelScrollFrameTemplate");scroll:SetPoint("TOPLEFT",header,"BOTTOMLEFT",0,-2);scroll:SetPoint("BOTTOMRIGHT",p,"BOTTOMRIGHT",-30,204);local content=CreateFrame("Frame",nil,scroll);content:SetSize(1,1);scroll:SetScrollChild(content);scroll:HookScript("OnSizeChanged",function(s)content:SetWidth(s:GetWidth());Page:RenderRows(false)end);scroll:HookScript("OnVerticalScroll",function()Page:RenderRows(false)end);self.scroll,self.rowContent=scroll,content
 local empty=p:CreateFontString(nil,"OVERLAY","GameFontHighlight");empty:SetPoint("TOPLEFT",scroll,12,-12);empty:SetText(L["EMPTY"]);self.empty=empty
 local detail=p:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");detail:SetPoint("TOPLEFT",14,-398);detail:SetPoint("BOTTOMRIGHT",-22,73);detail:SetJustifyH("LEFT");detail:SetJustifyV("TOP");detail:SetText(L["NO_SELECTION"]);self.detail=detail
 self.pause=button(p,L["PAUSE"],120,{"BOTTOMLEFT",14,18},function()if not HolyStorm.Policy:Can("taskmanager-control")then return end;if HolyStorm.Tasks:IsPaused()then HolyStorm.Tasks:Resume()else HolyStorm.Tasks:Pause()end;Page:Render()end)
 button(p,L["CANCEL_WORKFLOW"],160,{"BOTTOMLEFT",140,18},function()local o=Page.selected and Page.selected.object;if o and(o.workflowId or o.workflowType)then Page.pendingWorkflow=o.workflowType and o.workflowId or o.workflowId;StaticPopup_Show("HOLYSTORM_CANCEL_WORKFLOW")end end)
 button(p,L["RESTART_WORKFLOW"],160,{"BOTTOMLEFT",306,18},function()if not HolyStorm.Policy:Can("taskmanager-control")then return end;local o=Page.selected and Page.selected.object;local id=o and(o.workflowType and o.workflowId or o.workflowId);if id then HolyStorm.Workflows:Restart(id)end end)
 button(p,L["CLEAR_RESTART"],190,{"BOTTOMLEFT",14,45},function()if not HolyStorm.Policy:Can("taskmanager-control")then return end;local o=Page.selected and Page.selected.object;local id=o and(o.workflowType and o.workflowId or o.workflowId);if id then HolyStorm.Workflows:ClearPendingRestart(id)end end)
 button(p,L["CLEAR_QUEUE"],140,{"BOTTOMLEFT",210,45},function()StaticPopup_Show("HOLYSTORM_CLEAR_TASK_QUEUE")end)
 StaticPopupDialogs["HOLYSTORM_CLEAR_TASK_QUEUE"]={text=L["CONFIRM_CLEAR_QUEUE"],button1=L["YES"],button2=L["NO"],OnAccept=function()if HolyStorm.Policy:Can("taskmanager-control")then HolyStorm.Tasks:ClearQueue()end end,timeout=0,whileDead=true,hideOnEscape=true,preferredIndex=3}
 StaticPopupDialogs["HOLYSTORM_CANCEL_WORKFLOW"]={text=L["CONFIRM_CANCEL_WORKFLOW"],button1=L["YES"],button2=L["NO"],OnAccept=function()if Page.pendingWorkflow and HolyStorm.Policy:Can("taskmanager-control")then HolyStorm.Workflows:Cancel(Page.pendingWorkflow,"MANUAL_CANCEL")end;Page.pendingWorkflow=nil end,timeout=0,whileDead=true,hideOnEscape=true,preferredIndex=3}
 HolyStorm.UI:RegisterPage("taskManager",p,L["WINDOW_TITLE"],function()Page:Render()end)
 for _,event in ipairs(refreshEvents)do HolyStorm.Events:Register(event,"ui:taskManager:coalesced",function()Page:RequestRefresh()end)end
 HolyStorm.UI:AddNavigation("taskManager",13,"Interface\\Icons\\INV_Engineering_90_Circuitry",L["DISPLAY_NAME"],L["DESCRIPTION"],function()HolyStorm.UI:ShowPage("taskManager")end);p:HookScript("OnSizeChanged",function(_,_,height)detail:ClearAllPoints();detail:SetPoint("TOPLEFT",14,-(height-162));detail:SetPoint("BOTTOMRIGHT",-22,73)end);p:HookScript("OnHide",function(frame)frame:SetScript("OnUpdate",nil);Page.refreshPending=false end)
end
