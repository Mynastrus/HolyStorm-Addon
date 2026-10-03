local addonVersion="1.0.0"
local HolyStorm=LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local L=LibStub("AceLocale-3.0"):GetLocale("Holy_Storm")

-- Serializes explicit and event-driven scans. Snapshot presence and age never
-- enqueue producer work; cached freshness is read by the shared CharacterUI API.
local function emptyMetrics()
 local byBlock={}
 for _,block in ipairs({"equipment","mythicPlus","raid","delves","stats"})do byBlock[block]={requested=0,automatic=0,manual=0,completed=0,failed=0,triggers={}}end
 return{byBlock=byBlock,loginProducerScans=0}
end
local CharacterScans={version=addonVersion,providers={},pending={},queue={},active=nil,runtimeStates={},initialized=false,loginSession=0,releaseDelay=1.25,loginWindowSeconds=4,metrics=emptyMetrics()}
local function copy(value)return HolyStorm.Utils.DeepCopy(value)end
local function valid(value)return type(value)=="string"and value~=""end
local function sortQueue(left,right)local lo=tonumber(left.order)or 100;local ro=tonumber(right.order)or 100;if lo==ro then return left.block<right.block end;return lo<ro end
local function manualRequest(request)return request and(request.manual==true or request.reason=="MANUAL"or request.reason=="MANUAL_COMMAND"or request.reason=="DASHBOARD_MANUAL"or request.reasons and(request.reasons.MANUAL or request.reasons.MANUAL_COMMAND or request.reasons.DASHBOARD_MANUAL))end
local function scanMetric(block)
 block=tostring(block or"UNKNOWN");if#block>96 then block=block:sub(1,96)end
 local metrics=CharacterScans.metrics.byBlock;local item=metrics[block]
 if not item then local count=0;for _ in pairs(metrics)do count=count+1 end;if count>=64 then block="OTHER";item=metrics[block]end end
 if not item then item={requested=0,automatic=0,manual=0,completed=0,failed=0,triggers={}};metrics[block]=item end
 return item
end
local function recordRequest(request)
 local item=scanMetric(request.block);item.requested=item.requested+1
 if manualRequest(request)then item.manual=item.manual+1 else item.automatic=item.automatic+1 end
 local trigger=tostring(request.reason or"UNKNOWN");if#trigger>96 then trigger=trigger:sub(1,96)end;if not item.triggers[trigger]then local count=0;for _ in pairs(item.triggers)do count=count+1 end;if count>=64 then trigger="OTHER"end end;item.triggers[trigger]=(item.triggers[trigger]or 0)+1
 if HolyStorm.Tasks and HolyStorm.Tasks.RecordStartupMetric then HolyStorm.Tasks:RecordStartupMetric("producerScansRequested")end
end

function CharacterScans:RegisterProvider(owner,definition)
 if not valid(owner)or type(definition)~="table"or not valid(definition.block)or not valid(definition.capability)or type(definition.request)~="function"or definition.status~=nil and type(definition.status)~="function"then return false,"INVALID_CHARACTER_SCAN_PROVIDER"end
 self.providers[definition.block]={owner=owner,block=definition.block,capability=definition.capability,addonId=definition.addonId,order=tonumber(definition.order)or 100,request=definition.request,status=definition.status}
 if HolyStorm.Events then HolyStorm.Events:Emit("HS_CHARACTER_SCAN_PROVIDER_REGISTERED",definition.block,owner)end
 return true
end

function CharacterScans:GetDeclarations()
 local declarations={}
 if HolyStorm.AddonLoader and HolyStorm.AddonLoader.GetCharacterDataDefinitions then
  for _,definition in ipairs(HolyStorm.AddonLoader:GetCharacterDataDefinitions())do
   if valid(definition.block)and valid(definition.capability)then declarations[#declarations+1]=copy(definition)end
  end
 end
 if #declarations==0 then
  for _,provider in pairs(self.providers)do declarations[#declarations+1]={block=provider.block,capability=provider.capability,addonId=provider.addonId,order=provider.order}end
 end
 table.sort(declarations,sortQueue)
 return declarations
end

function CharacterScans:SetRuntimeState(block,state,reason,errorText)
 local previous=self.runtimeStates[block]or{};local timestamp=HolyStorm.Utils.Now()
 local nextState={state=state,reason=reason or previous.reason,changedAt=timestamp,lastAttempt=previous.lastAttempt,lastSuccessfulSnapshot=previous.lastSuccessfulSnapshot,lastError=errorText}
 if state=="REFRESHING"then nextState.lastAttempt=timestamp end
 if state=="CURRENT"then nextState.lastSuccessfulSnapshot=timestamp;nextState.lastError=nil end
 self.runtimeStates[block]=nextState
 if HolyStorm.Events then HolyStorm.Events:Emit("HS_CHARACTER_SNAPSHOT_STATUS_CHANGED",block,state,copy(nextState),UnitGUID and UnitGUID("player"))end
 return nextState
end

function CharacterScans:GetRuntimeState(guid,block)
 if not valid(block)or not UnitGUID or guid~=UnitGUID("player")then return nil end
 local state=self.runtimeStates[block]
 return state and copy(state)or nil
end

function CharacterScans:Request(block,reason,sync,options)
 if not valid(block)then return false,"INVALID_CHARACTER_BLOCK"end;options=options or{};local queued=self.pending[block]
 if queued then queued.sync=queued.sync or sync==true;queued.reasons[reason or"UNKNOWN"]=true;queued.manual=queued.manual or manualRequest({manual=options.manual,reason=reason});recordRequest({block=block,reason=reason,manual=options.manual,reasons={[reason or"UNKNOWN"]=true}});if self.initialized then local manual=manualRequest({manual=options.manual,reason=reason});HolyStorm.Tasks:Queue("CharacterScan.Advance",{delay=tonumber(options.delay)or 0,priority=manual and 15 or 30,triggerSource=reason or"CHARACTER_SCAN_REQUEST"})end;return true,"MERGED"end
 local order=tonumber(options.order)or(self.providers[block]and self.providers[block].order)or 100;if self.active and self.active.block==block then order=math.huge end
 local request={block=block,reason=reason or"UNKNOWN",reasons={[reason or"UNKNOWN"]=true},sync=sync==true,order=order,addonId=options.addonId,capability=options.capability,manual=options.manual==true};request.manual=manualRequest(request);recordRequest(request)
 self.pending[block]=request;self.queue[#self.queue+1]=request;table.sort(self.queue,sortQueue)
 if not(self.active and self.active.block==block)then self:SetRuntimeState(block,"DIRTY",reason or"UNKNOWN")end
 if self.initialized then HolyStorm.Tasks:Queue("CharacterScan.Advance",{delay=tonumber(options.delay)or 0,priority=manualRequest(request)and 15 or 30,triggerSource=reason or"CHARACTER_SCAN_REQUEST"})end
 return true,"QUEUED"
end

function CharacterScans:ResolveProvider(request)
 local provider=self.providers[request.block];if provider and(not HolyStorm.IsModuleAvailable or HolyStorm:IsModuleAvailable(provider.owner,true))then return provider end
 local addonId=request.addonId
 if not addonId and HolyStorm.AddonLoader and HolyStorm.AddonLoader.GetCharacterDataDefinition then local declaration=HolyStorm.AddonLoader:GetCharacterDataDefinition(request.block);addonId=declaration and declaration.addonId end
 if addonId and HolyStorm.AddonLoader and HolyStorm.AddonLoader.LoadById then HolyStorm.AddonLoader:LoadById(addonId,{reason="character-scan",trigger=request.reason,block=request.block})end
 provider=self.providers[request.block];if provider and(not HolyStorm.IsModuleAvailable or HolyStorm:IsModuleAvailable(provider.owner,true))then return provider end
end

function CharacterScans:Advance()
 if self.active then return true end
 local request=table.remove(self.queue,1);if not request then return true end;self.pending[request.block]=nil
 local provider=self:ResolveProvider(request);if not provider then
  local item=scanMetric(request.block);item.failed=item.failed+1;if HolyStorm.Tasks and HolyStorm.Tasks.RecordStartupMetric then HolyStorm.Tasks:RecordStartupMetric("producerScansFailed")end
  HolyStorm.Logger:Write("WARN","CharacterScan","provider","Character scan provider unavailable",{block=request.block,capability=request.capability,addonId=request.addonId,reason=request.reason})
  self:SetRuntimeState(request.block,"ERROR",request.reason,"PROVIDER_UNAVAILABLE");HolyStorm.Tasks:Queue("CharacterScan.Advance",{delay=self.releaseDelay,priority=30,triggerSource="CHARACTER_SCAN_PROVIDER_UNAVAILABLE"});return false
 end
 local ok,workflowId,state=HolyStorm.Utils.SafeCall("character-scan:"..request.block,provider.request,request.sync,request.reason,copy(request.reasons))
 if not ok or not valid(workflowId)then
  local item=scanMetric(request.block);item.failed=item.failed+1;if HolyStorm.Tasks and HolyStorm.Tasks.RecordStartupMetric then HolyStorm.Tasks:RecordStartupMetric("producerScansFailed")end
  HolyStorm.Logger:Write("WARN","CharacterScan","workflow","Character scan did not start",{block=request.block,capability=provider.capability,reason=request.reason,error=not ok and tostring(workflowId)or tostring(state)})
  self:SetRuntimeState(request.block,"ERROR",request.reason,not ok and tostring(workflowId)or tostring(state));HolyStorm.Tasks:Queue("CharacterScan.Advance",{delay=self.releaseDelay,priority=30,triggerSource="CHARACTER_SCAN_START_FAILED"});return false
 end
 if HolyStorm.Tasks and HolyStorm.Tasks.IsStartupActive and HolyStorm.Tasks:IsStartupActive()and not manualRequest(request)then self.metrics.loginProducerScans=self.metrics.loginProducerScans+1 end
 self.active={block=request.block,workflowId=workflowId,reason=request.reason,reasons=request.reasons,sync=request.sync,startedAt=HolyStorm.Utils.Now()}
 self:SetRuntimeState(request.block,"REFRESHING",request.reason)
 HolyStorm.Logger:Write("DEBUG","CharacterScan","workflow","Character scan started",{block=request.block,workflowId=workflowId,reason=request.reason,resource="CHARACTER_SCAN"},workflowId)
 return true
end

function CharacterScans:Finish(workflow,status)
 local active=self.active;if not active or not workflow or workflow.workflowId~=active.workflowId then return false end
 self.active=nil;local queuedAgain=self.pending[active.block]~=nil
 if status=="COMPLETED"then local item=scanMetric(active.block);item.completed=item.completed+1;if HolyStorm.Tasks and HolyStorm.Tasks.RecordStartupMetric then HolyStorm.Tasks:RecordStartupMetric("producerScansCompleted")end;self:SetRuntimeState(active.block,queuedAgain and"DIRTY"or"CURRENT",queuedAgain and"EVENT_QUEUED"or active.reason)
 elseif status=="FAILED"then local item=scanMetric(active.block);item.failed=item.failed+1;if HolyStorm.Tasks and HolyStorm.Tasks.RecordStartupMetric then HolyStorm.Tasks:RecordStartupMetric("producerScansFailed")end;self:SetRuntimeState(active.block,"ERROR",active.reason,"WORKFLOW_FAILED")
 elseif not queuedAgain then self:SetRuntimeState(active.block,"STALE",active.reason,"WORKFLOW_CANCELLED")end
 HolyStorm.Logger:Write(status=="FAILED"and"WARN"or"DEBUG","CharacterScan","workflow","Character scan released",{block=active.block,workflowId=active.workflowId,status=status,reason=active.reason,resource="CHARACTER_SCAN"},active.workflowId)
 HolyStorm.Events:Emit("HS_CHARACTER_SCAN_COMPLETED",active.block,status,copy(active.reasons),active.workflowId)
 HolyStorm.Tasks:Queue("CharacterScan.Advance",{delay=self.releaseDelay,priority=manualRequest(self.queue[1])and 15 or 30,triggerSource="CHARACTER_SCAN_"..status});return true
end

function CharacterScans:BeginLogin()
 self.loginSession=self.loginSession+1;self.metrics.loginProducerScans=0;self.active=nil;self.pending={};self.queue={};self.runtimeStates={}
 return true
end

function CharacterScans:Initialize()
 if self.initialized then return true end;self.initialized=true
 HolyStorm.Tasks:RegisterTaskType("CharacterScan.Advance",{name=L["TASK_CHARACTER_SCAN_ADVANCE"],localizedNameKey="TASK_CHARACTER_SCAN_ADVANCE",module="CharacterScan",priority=30,executionMode="UNIQUE",conditions={"PLAYER_LOGGED_IN","PLAYER_READY","NOT_LOADING","NOT_ZONING"},execute=function()return CharacterScans:Advance()end})
 HolyStorm.Events:Register("PLAYER_LOGIN","character-scan",function()CharacterScans:BeginLogin()end)
 HolyStorm.Events:Register("HS_WORKFLOW_COMPLETED","character-scan",function(_,workflow)CharacterScans:Finish(workflow,"COMPLETED")end)
 HolyStorm.Events:Register("HS_WORKFLOW_FAILED","character-scan",function(_,workflow)CharacterScans:Finish(workflow,"FAILED")end)
 HolyStorm.Events:Register("HS_WORKFLOW_CANCELLED","character-scan",function(_,workflow)CharacterScans:Finish(workflow,"CANCELLED")end)
 return true
end

function CharacterScans:IsIdle()return not self.active and #self.queue==0 and next(self.pending)==nil end
function CharacterScans:GetRuntimeMetrics()return self.metrics end
function CharacterScans:ResetRuntimeMetrics()self.metrics=emptyMetrics();return true end
function CharacterScans:GetDiagnostics()return{active=copy(self.active),queued=#self.queue,pending=copy(self.pending),runtimeStates=copy(self.runtimeStates),providers=HolyStorm.Utils.TableCount(self.providers),loginSession=self.loginSession,loginProducerScans=self.metrics.loginProducerScans,idle=self:IsIdle(),metrics=self.metrics}end
HolyStorm.CharacterScans=CharacterScans
