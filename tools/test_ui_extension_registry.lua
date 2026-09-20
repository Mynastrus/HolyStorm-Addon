local root=(arg[0]:gsub("tools[/\\]test_ui_extension_registry.lua$","")).."LIVE/"
local emitted={}
local HolyStorm={Modules={},Utils={DeepCopy=function(value)local out={};for key,item in pairs(value or{})do out[key]=item end;return out end,SafeCall=function(_,callback,...)local ok,result=pcall(callback,...);return ok,result end},Events={Emit=function(_,event,...)emitted[#emitted+1]={event,...}end}}
local locale=setmetatable({},{__index=function(_,key)return key end})
function HolyStorm:GetModule()return nil end
function HolyStorm:IterateModules()return function()end end
function LibStub(name)if name=="AceAddon-3.0"then return{GetAddon=function()return HolyStorm end}elseif name=="AceLocale-3.0"then return{GetLocale=function()return locale end}end end
assert(loadfile(root.."Holy_Storm/Core/Registry/ModuleRegistry.lua"))()
local built={}
assert(HolyStorm:RegisterUIExtension("feature-before",{id="before",order=20,initialize=function()built.before=true end}))
local before=HolyStorm:GetUIExtensions();assert(#before==1 and before[1].id=="before","feature can register before UI")
local observed
HolyStorm.Events.Emit=function(_,event,id,definition)if event=="HS_UI_EXTENSION_REGISTERED"then observed={id=id,definition=definition}end end
assert(HolyStorm:RegisterUIExtension("feature-after",{id="after",order=10,initialize=function()built.after=true end}))
assert(observed and observed.id=="after","loaded UI can observe later feature registration")
local ordered=HolyStorm:GetUIExtensions();assert(ordered[1].id=="after"and ordered[2].id=="before","extensions are deterministic")
local coreToc=assert(io.open(root.."Holy_Storm/Holy_Storm.toc","rb"));local core=coreToc:read("*a");coreToc:close()
local uiToc=assert(io.open(root.."Holy_Storm_UI/Holy_Storm_UI.toc","rb"));local ui=uiToc:read("*a");uiToc:close()
assert(not core:find("UI\\",1,true)and not core:find("AceGUI",1,true),"core loads without UI files or GUI libraries")
assert(ui:find("## RequiredDeps: Holy_Storm",1,true)and not ui:find("Holy_Storm_Equipment",1,true),"UI has no feature dependency")
print("UI extension before/after load-order and standalone Core/UI contracts passed")
