local root=(arg[0]:gsub("tools[/\\]test_addon_loader.lua$","")).."LIVE/Holy_Storm/"
local definitions={
 {name="Unrelated_Addon",metadata={}},
 {name="Vendor_Module_One",metadata={["X-HolyStorm-ID"]="alpha",["X-HolyStorm-Requires"]="core, synchronization",["X-HolyStorm-LoadOnEvent"]="EVENT_ALPHA, EVENT_BETA"}},
 {name="Vendor_Module_Two",metadata={["X-HolyStorm-ID"]="beta"}},
 {name="Missing_Id",metadata={["X-HolyStorm-LoadOnEvent"]="EVENT_ALPHA"}},
}
local loaded,attempts={},{}
C_AddOns={
 GetNumAddOns=function()return#definitions end,
 GetAddOnInfo=function(index)return definitions[index].name end,
 GetAddOnMetadata=function(name,key)for _,definition in ipairs(definitions)do if definition.name==name then return definition.metadata[key]end end end,
 IsAddOnLoaded=function(name)return loaded[name]==true end,
 LoadAddOn=function(name)attempts[name]=(attempts[name]or 0)+1;loaded[name]=true;return true end,
}
local listeners={}
local HolyStorm={
 Utils={DeepCopy=function(value)local out={};for key,item in pairs(value or{})do out[key]=item end;return out end},
 Events={Register=function(_,event,owner,callback)listeners[event]={owner=owner,callback=callback}end,UnregisterOwner=function(_,owner)for event,entry in pairs(listeners)do if entry.owner==owner then listeners[event]=nil end end end},
 Logger={WARN=function()end},
}
function LibStub(name)assert(name=="AceAddon-3.0");return{GetAddon=function()return HolyStorm end}end
assert(loadfile(root.."Core/Registry/AddonLoader.lua"))()
local Loader=HolyStorm.AddonLoader
assert(Loader:Initialize()==nil)
assert(Loader.addonsById.alpha and Loader.addonsById.beta,"Holy Storm metadata discovery")
assert(not Loader.addonsById.Unrelated_Addon and not Loader.addonsById.Missing_Id,"addons without an ID are ignored")
assert(#Loader.addonsById.alpha.requires==2 and Loader.addonsById.alpha.requires[2]=="synchronization","requires metadata parsing")
assert(listeners.EVENT_ALPHA and listeners.EVENT_BETA,"event registry")
assert(not listeners.PLAYER_ENTERING_WORLD,"normal addons do not gain synthetic login triggers")
listeners.EVENT_ALPHA.callback("EVENT_ALPHA")
assert(attempts.Vendor_Module_One==1,"event must cause one load attempt")
local context=HolyStorm:GetAddonLoadContext("alpha")
assert(context and context.reason=="event"and context.trigger=="EVENT_ALPHA","original load context")
listeners.EVENT_ALPHA.callback("EVENT_ALPHA")
listeners.EVENT_BETA.callback("EVENT_BETA")
assert(attempts.Vendor_Module_One==1,"repeated events must not cause repeated load attempts")
assert(not attempts.Vendor_Module_Two,"addon without LoadOnEvent remains normally managed")
Loader:Shutdown();assert(not listeners.EVENT_ALPHA and not listeners.EVENT_BETA,"loader shutdown unregisters events")
local source=assert(io.open(root.."Core/Registry/AddonLoader.lua","rb"));local text=source:read("*a");source:close()
for _,name in ipairs({"Holy_Storm_Equipment","Holy_Storm_Raids","Holy_Storm_MythicPlus","Holy_Storm_Professions"})do assert(not text:find(name,1,true),"loader hardcodes "..name)end
print("Generic addon discovery, event loading, single-attempt and load-context contracts passed")
