local root=(arg[0]:gsub("tools[/\\]test_manual_scan_commands.lua$",""))
local sourceFile=assert(io.open(root.."LIVE/Holy_Storm/Core/Commands/Commands.lua","rb"));local source=sourceFile:read("*a");sourceFile:close()
local definitions={
 {block="equipment",capability="character.scan.equipment",addonId="equipment",order=10},
 {block="mythicPlus",capability="character.scan.mythicplus",addonId="mythicPlus",order=20},
 {block="raid",capability="character.scan.raids",addonId="raids",order=30},
 {block="delves",capability="character.scan.delves",addonId="delves",order=40},
 {block="stats",capability="character.scan.stats",addonId="characters",order=50},
}
local requests,unavailable,output={},{},{}
local manager={}
function manager:GetDeclarations()return definitions end
function manager:ResolveProvider(request)if unavailable[request.block]then return nil end;return{capability=request.capability,status=request.block=="raid"and function()return{"Stored raid snapshot","Lifetime bosses: 3"}end or nil}end
function manager:Request(block,reason,sync,options)requests[#requests+1]={block=block,reason=reason,sync=sync,options=options};return true,"QUEUED"end
local locale=setmetatable({ADDON_PREFIX="[Holy Storm] "},{__index=function(_,key)return key end})
local HolyStorm={CharacterScans=manager,Utils={Trim=function(value)return tostring(value):match("^%s*(.-)%s*$")end}}
function HolyStorm:GetAddon()return self end
function LibStub(name)if name=="AceAddon-3.0"then return HolyStorm end;if name=="AceLocale-3.0"then return{GetLocale=function()return locale end}end;error("unexpected library "..tostring(name))end
local originalPrint=print
print=function(message)output[#output+1]=message end
assert(loadfile(root.."LIVE/Holy_Storm/Core/Commands/Commands.lua"))()
print=originalPrint
local Commands=HolyStorm.Commands
assert(Commands and Commands.handlers.scan,"scan is registered in the central /hs subcommand tree")
function UnitGUID(unit)assert(unit=="player");return"Player-Current"end
local function run(argument)
 output={};local oldPrint=print;print=function(message)output[#output+1]=message end;Commands.handlers.scan.execute(argument);print=oldPrint;return table.concat(output,"\n")
end
local expected={raid="raid",equipment="equipment",mythicplus="mythicPlus",delves="delves",stats="stats"}
for target,block in pairs(expected)do
 local before=#requests;local message=run(target);assert(#requests==before+1,target.." queues exactly one scan")
 local request=requests[#requests];assert(request.block==block and request.reason=="MANUAL_COMMAND"and request.sync==true,target.." uses the forced canonical scan request")
 assert(request.options.capability and request.options.addonId and request.options.order,target.." resolves provider metadata rather than hardcoding capabilities")
 assert(message:find("COMMAND_SCAN_STARTED_"..target:upper(),1,true),target.." reports localized started feedback")
end

local beforeAll=#requests;local allMessage=run("all");assert(#requests==beforeAll+#definitions,"scan all requests every declared scan provider")
for index,definition in ipairs(definitions)do local request=requests[beforeAll+index];assert(request.block==definition.block and request.reason=="MANUAL_COMMAND"and request.options.order==definition.order,"scan all preserves CharacterScanManager declaration order")end
assert(allMessage:find("COMMAND_SCAN_ALL_STARTED",1,true),"scan all reports localized aggregate feedback")
output={};local oldPrint=print;print=function(message)output[#output+1]=message end
assert(Commands:OnCharacterScanCompleted("raid","COMPLETED",{MANUAL_COMMAND=true}),"manual workflow completion has a clean localized command hook")
print=oldPrint;assert(table.concat(output,"\n"):find("COMMAND_SCAN_COMPLETED_RAID",1,true),"manual scan completion feedback is localized")
assert(not Commands:OnCharacterScanCompleted("raid","COMPLETED",{BOSS_KILL=true}),"automatic scans do not produce manual-command feedback")

local beforeUsage=#requests;assert(run(""):find("COMMAND_SCAN_USAGE",1,true),"empty scan prints usage");assert(#requests==beforeUsage,"empty scan does not scan everything")
local beforeStatus=#requests;local status=run("raid status");assert(status:find("Stored raid snapshot",1,true)and status:find("Lifetime bosses: 3",1,true),"raid status prints the provider's stored-snapshot report");assert(#requests==beforeStatus,"raid status must not enqueue another scan")
local unknown=run("foo");assert(unknown:find("COMMAND_SCAN_UNKNOWN_TARGET",1,true)and unknown:find("COMMAND_SCAN_USAGE",1,true),"unknown target prints localized error and usage")
local beforeUnavailable=#requests;unavailable.raid=true;assert(run("raid"):find("COMMAND_SCAN_UNAVAILABLE_RAID",1,true),"unavailable provider produces localized feedback");assert(#requests==beforeUnavailable,"unavailable provider does not enqueue a dead workflow")
assert(run("raid status"):find("COMMAND_SCAN_UNAVAILABLE_RAID",1,true),"raid status handles an unloaded provider")

assert(not source:find("CharacterStore",1,true)and not source:find("HS_Player_DB",1,true)and not source:find("SnapshotManager",1,true),"commands do not mutate snapshots, CharacterStore, or SavedVariables directly")
assert(source:find("HS_CHARACTER_SCAN_COMPLETED",1,true),"command completion feedback subscribes to the scan manager lifecycle signal")
print=originalPrint
print("Manual scan slash command routing, forced queue semantics, all ordering, localization and unavailable-provider tests passed")
