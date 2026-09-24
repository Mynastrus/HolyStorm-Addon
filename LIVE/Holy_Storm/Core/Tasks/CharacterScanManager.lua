local addonVersion="1.0.0"
local HolyStorm=LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local L=LibStub("AceLocale-3.0"):GetLocale("Holy_Storm")

-- Generic, feature-blind exclusivity group for local character data scans.
-- Providers declare their block and request callback; the Core only serializes
-- those callbacks and never knows what the block contains.
local CharacterScans={version=addonVersion,providers={},pending={},queue={},active=nil,initialized=false,loginSession=0,initialDelay=3,releaseDelay=1.25}
local function copy(value)return HolyStorm.Utils.DeepCopy(value)end
local function valid(value)return type(value)=="string"and value~=""end
local function sortQueue(left,right)local lo=tonumber(left.order)or 100;local ro=tonumber(right.order)or 100;if lo==ro then return left.block<right.block end;return lo<ro end

function CharacterScans:RegisterProvider(owner,definition)
 if not valid(owner)or type(definition)~="table"or not valid(definition.block)or not valid(definition.capability)or type(definition.request)~="function"then return false,"INVALID_CHARACTER_SCAN_PROVIDER"end
 self.providers[definition.block]={owner=owner,block=definition.block,capability=definition.capability,addonId=definition.addonId,order=tonumber(definition.order)or 100,request=definition.request}
 if HolyStorm.Events then HolyStorm.Events:Emit("HS_CHARACTER_SCAN_PROVIDER_REGISTERED",definition.block,owner)end
 return true
end

function CharacterScans:GetDeclarations()
 local declarations,seen={},{}
 if HolyStorm.AddonLoader and HolyStorm.AddonLoader.GetCharacterDataDefinitions then
  for _,definition in ipairs(HolyStorm.AddonLoader:GetCharacterDataDefinitions())do declarations[#declarations+1]=definition;seen[definition.block]=true end
 end
 for block,provider in pairs(self.providers)do if not seen[block]then declarations[#declarations+1]={block=block,capability=provider.capability,addonId=provider.addonId,order=provider.order}end end
 table.sort(declarations,sortQueue);return declarations
end

function CharacterScans:Request(block,reason,sync,options)
 if not valid(block)then return false,"INVALID_CHARACTER_BLOCK"end;options=options or{};local queued=self.pending[block]
 if queued then queued.sync=queued.sync or sync==true;queued.reasons[reason or"UNKNOWN"]=true;return true,"MERGED"end
 local order=tonumber(options.order)or(self.providers[block]and self.providers[block].order)or 100;if self.active and self.active.block==block then order=math.huge end
 local request={block=block,reason=reason or"UNKNOWN",reasons={[reason or"UNKNOWN"]=true},sync=sync==true,order=order,initial=options.initial==true,addonId=options.addonId,capability=options.capability}
 self.pending[block]=request;self.queue[#self.queue+1]=request;table.sort(self.queue,sortQueue)
 if self.initialized then HolyStorm.Tasks:Queue("CharacterScan.Advance",{delay=tonumber(options.delay)or 0,priority=30,triggerSource=reason or"CHARACTER_SCAN_REQUEST"})end
 return true,"QUEUED"
end

function CharacterScans:QueueBootstrapBlocks()
 local guid=UnitGUID("player");if not guid then return false end
 for _,definition in ipairs(self:GetDeclarations())do
  local freshness=HolyStorm.PlayerData:GetBlockFreshness(guid,definition.block);local reason
  if not freshness.metadataExists then reason="INITIAL_MISSING_BLOCK"elseif freshness.stale then reason="INITIAL_STALE_BLOCK"end
  local queued=reason~=nil;if queued then self:Request(definition.block,reason,true,{initial=true,order=definition.order,addonId=definition.addonId,capability=definition.capability})end
  HolyStorm.Logger:Write("DEBUG","CharacterScan","bootstrap","Character scan bootstrap decision",{block=definition.block,metadataExists=freshness.metadataExists,stale=freshness.stale,queued=queued,reason=reason or"FRESH",updatedAt=freshness.updatedAt or 0,staleAfter=freshness.staleAfter,age=freshness.age or 0})
 end
 return true
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
  HolyStorm.Logger:Write("WARN","CharacterScan","provider","Character scan provider unavailable",{block=request.block,capability=request.capability,addonId=request.addonId,reason=request.reason})
  HolyStorm.Tasks:Queue("CharacterScan.Advance",{delay=self.releaseDelay,priority=30,triggerSource="CHARACTER_SCAN_PROVIDER_UNAVAILABLE"});return false
 end
 local ok,workflowId,state=HolyStorm.Utils.SafeCall("character-scan:"..request.block,provider.request,request.sync,request.reason,copy(request.reasons))
 if not ok or not valid(workflowId)then
  HolyStorm.Logger:Write("WARN","CharacterScan","workflow","Character scan did not start",{block=request.block,capability=provider.capability,reason=request.reason,error=not ok and tostring(workflowId)or tostring(state)})
  HolyStorm.Tasks:Queue("CharacterScan.Advance",{delay=self.releaseDelay,priority=30,triggerSource="CHARACTER_SCAN_START_FAILED"});return false
 end
 self.active={block=request.block,workflowId=workflowId,reason=request.reason,reasons=request.reasons,sync=request.sync,startedAt=HolyStorm.Utils.Now()}
 HolyStorm.Logger:Write("DEBUG","CharacterScan","workflow","Character scan started",{block=request.block,workflowId=workflowId,reason=request.reason,resource="CHARACTER_SCAN"},workflowId)
 return true
end

function CharacterScans:Finish(workflow,status)
 local active=self.active;if not active or not workflow or workflow.workflowId~=active.workflowId then return false end
 self.active=nil
 HolyStorm.Logger:Write(status=="FAILED"and"WARN"or"DEBUG","CharacterScan","workflow","Character scan released",{block=active.block,workflowId=active.workflowId,status=status,reason=active.reason,resource="CHARACTER_SCAN"},active.workflowId)
 HolyStorm.Tasks:Queue("CharacterScan.Advance",{delay=self.releaseDelay,priority=30,triggerSource="CHARACTER_SCAN_"..status});return true
end

function CharacterScans:BeginLogin()
 self.loginSession=self.loginSession+1;self.active=nil;self.pending={};self.queue={}
 return HolyStorm.Tasks:Queue("CharacterScan.InitialBootstrap",{delay=self.initialDelay,startupPhase=4,priority=30,triggerSource="PLAYER_LOGIN",metadata={session=self.loginSession}})
end

function CharacterScans:Initialize()
 if self.initialized then return true end;self.initialized=true
 HolyStorm.Tasks:RegisterTaskType("CharacterScan.InitialBootstrap",{name=L["TASK_CHARACTER_SCAN_DISCOVER"],localizedNameKey="TASK_CHARACTER_SCAN_DISCOVER",module="CharacterScan",priority=30,executionMode="UNIQUE",conditions={"PLAYER_LOGGED_IN","PLAYER_READY","NOT_LOADING","NOT_ZONING",function()local guid=UnitGUID("player");return guid and HolyStorm.PlayerData:GetMetadata(guid,"identity")~=nil end},execute=function()return CharacterScans:QueueBootstrapBlocks()end})
 HolyStorm.Tasks:RegisterTaskType("CharacterScan.Advance",{name=L["TASK_CHARACTER_SCAN_ADVANCE"],localizedNameKey="TASK_CHARACTER_SCAN_ADVANCE",module="CharacterScan",priority=30,executionMode="UNIQUE",conditions={"PLAYER_LOGGED_IN","PLAYER_READY","NOT_LOADING","NOT_ZONING"},execute=function()return CharacterScans:Advance()end})
 HolyStorm.Events:Register("PLAYER_LOGIN","character-scan",function()CharacterScans:BeginLogin()end)
 HolyStorm.Events:Register("HS_WORKFLOW_COMPLETED","character-scan",function(_,workflow)CharacterScans:Finish(workflow,"COMPLETED")end)
 HolyStorm.Events:Register("HS_WORKFLOW_FAILED","character-scan",function(_,workflow)CharacterScans:Finish(workflow,"FAILED")end)
 HolyStorm.Events:Register("HS_WORKFLOW_CANCELLED","character-scan",function(_,workflow)CharacterScans:Finish(workflow,"CANCELLED")end)
 return true
end

function CharacterScans:GetDiagnostics()return{active=copy(self.active),queued=#self.queue,pending=copy(self.pending),providers=HolyStorm.Utils.TableCount(self.providers),loginSession=self.loginSession}end
HolyStorm.CharacterScans=CharacterScans
