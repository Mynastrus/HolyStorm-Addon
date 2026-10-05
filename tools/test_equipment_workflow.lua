local repository=(arg[0]:gsub("tools[/\\]test_equipment_workflow.lua$",""))
local root=repository.."LIVE/Holy_Storm/"
local featureRoot=repository.."LIVE/Holy_Storm_Equipment/"
local monotonic,epoch=0,100000
function GetTime()return monotonic end
function time()return epoch+math.floor(monotonic)end
function InCombatLockdown()return false end
function UnitGUID(unit)if not unit or unit=="player"then return"Player-Test"end end
local timers={}
C_Timer={NewTimer=function(delay,callback)local timer={cancelled=false,due=monotonic+delay,callback=callback};function timer:Cancel()self.cancelled=true end;timers[#timers+1]=timer;return timer end,NewTicker=function(_,callback)local timer={callback=callback};function timer:Cancel()self.cancelled=true end;return timer end}
local function deepCopy(value,seen)if type(value)~="table"then return value end;seen=seen or{};if seen[value]then return seen[value]end;local out={};seen[value]=out;for key,child in pairs(value)do out[deepCopy(key,seen)]=deepCopy(child,seen)end;return out end
local listeners={}
local record={guid="Player-Test"}
local writes,syncs,workflowQueued,releases={},0,nil,{}
local HolyStorm={db={profile={taskManager={}}},Data={CharacterStore={}},Logger={history={}},Events={},State={values={playerLoggedIn=true,playerReady=true,guildAvailable=true}},Utils={}}
local settingDefinitions,settingValues,optionsTabs,slashCommands={},{},{},{}
HolyStorm.Settings={Register=function(_,definition)settingDefinitions[definition.id]=definition;return true end,Get=function(_,id)local value=settingValues[id];if value~=nil then return value end;local definition=settingDefinitions[id];return definition and definition.default end,GetDefinition=function(_,id)return settingDefinitions[id]end,Set=function(_,id,value)if not settingDefinitions[id]then return false end;settingValues[id]=value;return true end}
HolyStorm.Options={RegisterSetting=function(_,definition)return HolyStorm.Settings:Register(definition)end,RegisterOptionsTab=function(_,id,value)optionsTabs[id]=value;return true end,CreateScopeSelector=function()return{type="select"}end,SetSetting=function(_,id,value)return HolyStorm.Settings:Set(id,value)end}
HolyStorm.Commands={RegisterSlashCommand=function(_,definition)slashCommands[definition.id]=definition;return true end}
function HolyStorm:GetAddon()return self end
function HolyStorm:GetLocale()return setmetatable({},{__index=function(_,key)return key end})end
function HolyStorm.Utils.DeepCopy(value)return deepCopy(value)end
function HolyStorm.Utils.Now()return time()end
function HolyStorm.Utils.TableCount(value)local count=0;for _ in pairs(value or{})do count=count+1 end;return count end
function HolyStorm.Utils.SafeCall(_,fn,...)local arguments={...};return xpcall(function()return fn(table.unpack(arguments))end,function(err)return err end)end
function HolyStorm.State:Is(key)return self.values[key]==true end
function HolyStorm.State:Get(key)return self.values[key]end
function HolyStorm.Logger:Write(level,source,category,message,context,correlationId)self.history[#self.history+1]={level=level,source=source,category=category,message=message,context=context,correlationId=correlationId}end
function HolyStorm.Events:Register(event,owner,callback)listeners[event]=listeners[event]or{};listeners[event][owner]=callback end
function HolyStorm.Events:UnregisterOwner(owner)for _,bucket in pairs(listeners)do bucket[owner]=nil end end
function HolyStorm.Events:Emit(event,...)for _,callback in pairs(listeners[event]or{})do callback(event,...)end end
function HolyStorm.Data.CharacterStore:Get()return record end
function HolyStorm.Data.CharacterStore:GetBlock()return nil end
function HolyStorm:RegisterModule(_,factory)local module={};factory(module);self.Equipment=module;return module end
function HolyStorm:ApplyModuleMetadata()end
function HolyStorm:RegisterCapability()return true end
function HolyStorm.PlayerDataRegisterBlock()end
HolyStorm.PlayerData={RegisterBlock=function()return true end,WriteOwnedBlock=function(_,guid,blockId,data,source)
 assert(guid=="Player-Test"and blockId=="equipment"and source=="blizzard");record.equipment=deepCopy(data.equipment);record.itemLevel=data.itemLevel;writes[#writes+1]=deepCopy(data);HolyStorm.Events:Emit("HS_PLAYERDATA_OWNED_UPDATED",guid,blockId,{version=#writes});return true,{version=#writes}
end}
HolyStorm.PlayerData.FingerprintSnapshot=function(_,value)return HolyStorm.Serializer:Serialize(value)end
HolyStorm.Events:Register("HS_PLAYERDATA_OWNED_UPDATED","test-sync-after-commit",function(_,guid,block)assert(record.equipment~=nil and guid==record.guid and block=="equipment");syncs=syncs+1 end)
HolyStorm.Events:Register("HS_WORKFLOW_QUEUED","test-workflow-id",function(_,workflow)workflowQueued=workflow.workflowId end)
HolyStorm.Events:Register("HS_CHARACTER_SCAN_COMPLETED","test-scan-releases",function(_,block,status,_,workflowId)releases[#releases+1]={block=block,status=status,workflowId=workflowId}end)
function LibStub(name)if name=="AceAddon-3.0"then return{GetAddon=function()return HolyStorm end}end;return{GetLocale=function()return setmetatable({},{__index=function(_,key)return key end})end}end
for index,name in ipairs({"HEAD","NECK","SHOULDER","CHEST","WAIST","LEGS","FEET","WRIST","HAND","FINGER1","FINGER2","TRINKET1","TRINKET2","BACK","MAINHAND","OFFHAND"})do _G["INVSLOT_"..name]=index end
assert(loadfile(root.."Core/Serialization/Serializer.lua"))()
assert(loadfile(root.."Core/Tasks/TaskManager.lua"))()
assert(loadfile(root.."Core/Workflows/WorkflowManager.lua"))()
assert(loadfile(root.."Core/Tasks/CharacterScanManager.lua"))()
assert(loadfile(featureRoot.."Equipment.lua"))()
HolyStorm.Tasks:Initialize();HolyStorm.Workflows:Initialize();HolyStorm.CharacterScans:Initialize();HolyStorm.Equipment:OnInitialize()
local optionArgs=optionsTabs.equipment.args
assert(optionArgs.required.args.equipmentChanged.get()==true and optionArgs.required.args.equipmentChanged.disabled==true,"the required equipment-change trigger is always on and disabled")
assert(optionArgs.required.args.enchantChanges.get()==true and optionArgs.required.args.socketChanges.get()==true,"optional enchant and socket triggers default on")
for _,taskType in ipairs({"Equipment.Scan","Equipment.Validate","Equipment.Compare","Equipment.ConfirmScan","Equipment.ConfirmValidate","Equipment.StabilityCompare","Equipment.Store"})do assert(HolyStorm.Tasks:GetTaskType(taskType).timeoutSeconds==30,taskType.." declares a bounded ASYNC timeout")end
local slots={};for slot=1,16 do slots[slot]=false end
local function snapshot(itemId)
 local value={slots=deepCopy(slots),updatedAt=100,snapshotVersion=4,equippedCount=1,overallItemLevel=700,equippedItemLevel=700,itemLevel=700}
 value.slots[INVSLOT_HEAD]={state="EQUIPPED",slot=INVSLOT_HEAD,itemId=itemId,itemLevel=700,link="|Hitem:"..itemId..":0|h[Item]|h",quality=4}
 return value
end
local A,B,C=snapshot(111),snapshot(222),snapshot(333)
local scanSource,scanCalls
HolyStorm.Equipment.Collect=function()scanCalls=scanCalls+1;return deepCopy(scanSource(scanCalls))end
local function processAll(limit)
 for _=1,limit or 300 do
  if #HolyStorm.Tasks.queue==0 and not HolyStorm.Tasks.runningTaskId then return end
  local nextDue
  for _,task in ipairs(HolyStorm.Tasks.queue)do if task.notBefore>monotonic then nextDue=nextDue and math.min(nextDue,task.notBefore)or task.notBefore end end
  if nextDue and nextDue>monotonic then monotonic=nextDue end
  HolyStorm.Tasks.timer,HolyStorm.Tasks.timerDue=nil,nil;HolyStorm.Tasks:Process()
  if HolyStorm.Tasks.runningTaskId then return end
 end
 error("equipment workflow did not drain")
end
local function startEquipment(source,old)
 record={guid="Player-Test",equipment=deepCopy(old),itemLevel=old and old.itemLevel};scanSource=source;scanCalls=0;workflowQueued=nil
 local ok,reason=HolyStorm.CharacterScans:Request("equipment","TEST_EQUIPMENT",true,{order=10});assert(ok,reason);processAll();assert(workflowQueued,"CharacterScan starts an equipment workflow");return HolyStorm.Workflows.workflows[workflowQueued]
end
local function constant(value)return function()return value end end

local unchanged=startEquipment(constant(A),A)
assert(unchanged.status=="COMPLETED"and unchanged.currentStep==3 and#writes==0,"unchanged Scan A stops after comparison without a commit")
assert(#releases==1 and releases[1].status=="COMPLETED"and HolyStorm.CharacterScans.active==nil,"successful unchanged scan releases CharacterScan once")

local stableChanged=startEquipment(function(index)return index==1 and B or B end,A)
assert(stableChanged.status=="COMPLETED"and stableChanged.currentStep==7,"Scan A, Scan B, validation, stable comparison, and commit complete the workflow")
assert(scanCalls==2 and record.equipment.slots[INVSLOT_HEAD].itemId==222 and#writes==1,"stable candidate atomically replaces the last valid snapshot")
assert(syncs==1 and writes[1].equipment.slots[INVSLOT_HEAD].itemId==222,"sync notification follows the committed snapshot")
assert(releases[2].status=="COMPLETED"and HolyStorm.CharacterScans.active==nil,"changed equipment releases CharacterScan after success")
assert(stableChanged.duration<20,"normal equipment success does not enter the observed 20 second failure window")
local confirmScan,confirmValidate,storeCompleted=false,false,false
for _,taskId in ipairs(stableChanged.completedTasks)do local task=HolyStorm.Tasks.tasks[taskId];if task then confirmScan=confirmScan or task.registryId=="Equipment.ConfirmScan";confirmValidate=confirmValidate or task.registryId=="Equipment.ConfirmValidate";storeCompleted=storeCompleted or task.registryId=="Equipment.Store"and task.status=="COMPLETED"end end
assert(confirmScan and confirmValidate and storeCompleted,"ConfirmScan, ConfirmValidate, and Store task completions finalize the workflow")

local unstable=startEquipment(function(index)if index%2==1 then return B end;return C end,A)
assert(unstable.status=="FAILED"and# writes==1 and record.equipment.slots[INVSLOT_HEAD].itemId==111,"unstable Scan A and Scan B never commit or replace the last good snapshot")
assert(scanCalls==12,"unstable candidate retries are bounded at five retries after the initial attempt")
local unstableFailure=unstable.failureContext;assert(unstableFailure and unstableFailure.reason=="EQUIPMENT_CHANGED_DURING_CONFIRMATION"and unstableFailure.workflowType=="EQUIPMENT_UPDATE","unstable workflow failure has a concrete reason")
assert(unstableFailure.currentStepId=="stability-compare"and unstableFailure.failedTask=="Equipment.StabilityCompare"and unstableFailure.candidateState=="SCAN_UNSTABLE"and unstableFailure.candidateReason=="EQUIPMENT_CHANGED_DURING_CONFIRMATION","failure diagnostics identify the final stage and candidate")
assert(unstableFailure.workflowId==unstable.workflowId and unstableFailure.attempt==6 and unstableFailure.elapsed>=0 and unstableFailure.timeout==30 and unstableFailure.errorType=="WORKFLOW_RETRY_EXHAUSTED","failure diagnostics include workflow ID, attempt, elapsed, configured ASYNC timeout, and error type")
assert(unstableFailure.characterScanOwned and unstableFailure.characterScanBlock=="equipment"and unstableFailure.lastSuccessfulStage=="confirm-validate"and unstableFailure.dependency=="NONE","failure diagnostics include scan ownership, dependency, and last successful stage")
assert(releases[3].status=="FAILED"and HolyStorm.CharacterScans.active==nil,"failed workflow releases CharacterScan once")

local invalid={};for key,value in pairs(A)do invalid[key]=deepCopy(value)end;invalid.pending="ITEM_INFO_PENDING"
local invalidScan=startEquipment(constant(invalid),A)
assert(invalidScan.status=="FAILED"and scanCalls==6 and# writes==1 and record.equipment.slots[INVSLOT_HEAD].itemId==111,"invalid candidates exhaust a bounded retry without committing or deleting the last valid snapshot")
assert(invalidScan.failureContext.candidateState=="SCAN_A_INVALID"and invalidScan.failureContext.candidateReason=="ITEM_INFO_PENDING","invalid candidate reason is retained in failure diagnostics")
assert(releases[4].status=="FAILED"and HolyStorm.CharacterScans.active==nil,"invalid candidate failure releases CharacterScan exactly once")

local definition=HolyStorm.Workflows.registry.EQUIPMENT_UPDATE;definition.steps[1].timeoutSeconds=.5
scanSource=constant(A);scanCalls=0;record={guid="Player-Test",equipment=deepCopy(A),itemLevel=A.itemLevel};workflowQueued=nil
local originalScanExecute=HolyStorm.Tasks.registry["Equipment.Scan"].execute
HolyStorm.Tasks.registry["Equipment.Scan"].execute=function()return HolyStorm.Tasks.ASYNC end
assert(HolyStorm.CharacterScans:Request("equipment","TEST_ASYNC_TIMEOUT",true,{order=10}));processAll();local timedOut=HolyStorm.Workflows.workflows[workflowQueued]
assert(timedOut and timedOut.status=="WAITING_ASYNC"and HolyStorm.Tasks.tasks[HolyStorm.Tasks.runningTaskId].status=="WAITING_ASYNC","the test producer remains asynchronously active until its execution timeout")
local running=HolyStorm.Tasks.tasks[HolyStorm.Tasks.runningTaskId];assert(running.timeoutSeconds==.5 and running.timeoutTimer,"workflow step timeout is applied only after the task starts")
monotonic=running.timeoutTimer.due;running.timeoutTimer.callback();processAll()
timedOut=HolyStorm.Workflows.workflows[workflowQueued]
assert(timedOut.status=="FAILED"and timedOut.failureContext.errorType=="TASK_TIMEOUT"and timedOut.failureContext.failedTask=="Equipment.Scan"and timedOut.failureContext.timeout==.5,"task timeout becomes an explicit workflow failure")
assert(releases[5].status=="FAILED"and HolyStorm.CharacterScans.active==nil,"timeout releases CharacterScan instead of blocking later producers")
HolyStorm.Tasks.registry["Equipment.Scan"].execute=originalScanExecute
local releaseCount=#releases;assert(not HolyStorm.CharacterScans:Finish({workflowId=workflowQueued},"FAILED")and#releases==releaseCount,"duplicate terminal notification cannot release CharacterScan twice")

local otherStarts=0;HolyStorm.CharacterScans:RegisterProvider("OtherProducer",{block="other",capability="character.scan.other",order=20,request=function()otherStarts=otherStarts+1;return"other-scan-1"end})
assert(HolyStorm.CharacterScans:Request("other","AFTER_EQUIPMENT_FAILURE",true,{order=20}));processAll();assert(otherStarts==1 and HolyStorm.CharacterScans.active and HolyStorm.CharacterScans.active.workflowId=="other-scan-1","a different producer acquires CharacterScan after equipment failure")
HolyStorm.Events:Emit("HS_WORKFLOW_COMPLETED",{workflowId="other-scan-1"});processAll();assert(HolyStorm.CharacterScans.active==nil,"the next producer also releases normally")

record={guid="Player-Test",equipment=deepCopy(A),itemLevel=A.itemLevel};scanSource=constant(A);scanCalls=0;workflowQueued=nil
local originalRequest=HolyStorm.CharacterScans.Request;local manualRequests={}
HolyStorm.CharacterScans.Request=function(self,block,reason,sync,options)if reason=="MANUAL_OPTIONS"then manualRequests[#manualRequests+1]={block=block,reason=reason,sync=sync,options=deepCopy(options)}end;return originalRequest(self,block,reason,sync,options)end
assert(optionArgs.status.args.scan.func()==true,"manual scan button accepts the official request")
processAll();local equipmentCommand=assert(slashCommands["equipment.scan"]);assert(equipmentCommand.execute()==true,"equipment slash command accepts the official request")
processAll();HolyStorm.CharacterScans.Request=originalRequest
assert(#manualRequests==2 and manualRequests[1].block=="equipment"and manualRequests[2].block=="equipment"and manualRequests[1].reason==manualRequests[2].reason and manualRequests[1].reason=="MANUAL_OPTIONS","button and slash use the same CharacterScan request path")
assert(scanCalls==2,"manual button and slash each run the existing debounced equipment workflow")

HolyStorm.Equipment:OnEnable();local extraCalls={};local requestExtra=HolyStorm.CharacterScans.Request;HolyStorm.CharacterScans.Request=function(self,block,reason,sync,options)extraCalls[#extraCalls+1]=reason;return requestExtra(self,block,reason,sync,options)end;HolyStorm.Settings:Set("equipment.scanOnEnchantChange",false)
workflowQueued=nil;scanCalls=0;record={guid="Player-Test",equipment=deepCopy(A),itemLevel=A.itemLevel};scanSource=constant(A)
HolyStorm.Events:Emit("WEAPON_ENCHANT_CHANGED");assert(HolyStorm.CharacterScans.active==nil,"disabled optional enchant trigger does not request a workflow")
HolyStorm.Settings:Set("equipment.scanOnEnchantChange",true)
HolyStorm.Events:Emit("SOCKET_INFO_UPDATE");assert(#extraCalls==0,"socket UI refreshes do not trigger a scan")
HolyStorm.Events:Emit("WEAPON_ENCHANT_CHANGED");HolyStorm.Events:Emit("SOCKET_INFO_SUCCESS")
assert(HolyStorm.CharacterScans:Advance(),"queued optional triggers can advance through the official scan manager")
local mergedExtras=HolyStorm.CharacterScans.active and HolyStorm.CharacterScans.active.workflowId;assert(mergedExtras,"enabled extra triggers request the official CharacterScan workflow ("..table.concat(extraCalls,",")..","..tostring(HolyStorm.Settings:Get("equipment.scanOnSocketChange"))..")")
processAll();assert(scanCalls==1 and workflowQueued==mergedExtras and HolyStorm.CharacterScans.active==nil,"enchant and socket triggers merge into one debounced equipment workflow")
HolyStorm.CharacterScans.Request=requestExtra

record={guid="Player-Test",equipment=deepCopy(A),itemLevel=A.itemLevel};scanSource=constant(A);scanCalls=0;workflowQueued=nil
assert(HolyStorm.CharacterScans:Request("equipment","PLAYER_EQUIPMENT_CHANGED",true,{order=10})and HolyStorm.CharacterScans:Advance(),"the first equipment event queues one debounced workflow")
local debouncedWorkflow=HolyStorm.CharacterScans.active.workflowId;local scanTask
for _,task in pairs(HolyStorm.Tasks.tasks)do if task.workflowId==debouncedWorkflow and task.registryId=="Equipment.Scan"then scanTask=task;break end end
local firstNotBefore=scanTask and scanTask.notBefore;monotonic=monotonic+.4
assert(HolyStorm.CharacterScans:Request("equipment","UNIT_INVENTORY_CHANGED",true,{order=10})and HolyStorm.CharacterScans.active.workflowId==debouncedWorkflow,"a second equipment event before first task start merges into the queued workflow")
local mergedTask;for _,task in pairs(HolyStorm.Tasks.tasks)do if task.workflowId==debouncedWorkflow and task.registryId=="Equipment.Scan"then mergedTask=task;break end end
assert(mergedTask and firstNotBefore and mergedTask.notBefore>firstNotBefore and mergedTask.triggerCount>=2,"the merged equipment event resets the pending debounce window")
processAll();assert(scanCalls==1 and workflowQueued==debouncedWorkflow and HolyStorm.CharacterScans.active==nil,"an equipment burst during debounce produces one actual scan and one workflow (scans="..tostring(scanCalls)..",queued="..tostring(workflowQueued)..",expected="..tostring(debouncedWorkflow)..",active="..tostring(HolyStorm.CharacterScans.active and HolyStorm.CharacterScans.active.workflowId)..",task="..tostring(mergedTask and mergedTask.status)..",notBefore="..tostring(mergedTask and mergedTask.notBefore)..",clock="..tostring(monotonic)..",queue="..tostring(#HolyStorm.Tasks.queue)..",workflowStatus="..tostring(HolyStorm.Workflows.workflows[debouncedWorkflow]and HolyStorm.Workflows.workflows[debouncedWorkflow].status)..")")
print("Equipment workflow, snapshot atomicity, diagnostics, timeout, and CharacterScan tests passed")
