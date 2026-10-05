local script=arg[0]:gsub("\\","/")
local root=script:match("^(.*)/tools/[^/]+$")or"."
local source=root.."/LIVE/Holy_Storm_Characters/Profiles.lua"

local function widget(kind)
 local value={kind=kind}
 if kind=="CheckButton"then value.text={SetText=function()end}end
 return setmetatable(value,{__index=function(self,key)
  if key=="CreateFontString"then return function()return widget("FontString")end end
  return function()end
 end})
end

local locale=setmetatable({COUNTRIES={}}, {__index=function(_,key)return key end})
local localPageRegistrations,pageRegistrations,navigationRegistrations,shownPages,unregisteredPages={}, {},{}, {},{}
local moduleUI={content=widget("Frame")}
function moduleUI:RegisterPage(id,page,title,onShow,events)
 localPageRegistrations[#localPageRegistrations+1]={id=id,page=page,title=title,onShow=onShow,events=events}
 return true
end
local managerUI={}
function managerUI:RegisterPage(id,page,title,onShow,events)
 pageRegistrations[#pageRegistrations+1]={id=id,page=page,title=title,onShow=onShow,events=events}
 return true
end
function managerUI:AddNavigation(id,order,icon,title,description,callback)
 navigationRegistrations[#navigationRegistrations+1]={id=id,order=order,icon=icon,title=title,description=description,callback=callback}
 return true
end
function managerUI:ShowPage(id)shownPages[#shownPages+1]=id;return true end
function managerUI:UnregisterPage(id)unregisteredPages[#unregisteredPages+1]=id;return true end

local HolyStorm={
 UI=managerUI,
 Utils={DeepCopy=function(value)return value end,Trim=function(value)return tostring(value or""):match("^%s*(.-)%s*$")end},
}
function HolyStorm:GetAddon()return self end
function HolyStorm:RegisterRequiredModule()return{}end
function HolyStorm:ApplyModuleMetadata()end
function HolyStorm:GetModule(id)
 if id=="UI"then return moduleUI end
end
function LibStub(name)
 if name=="AceAddon-3.0"then return{GetAddon=function()return HolyStorm end}end
 if name=="AceLocale-3.0"then return{GetLocale=function()return locale end}end
 error("Unexpected library: "..tostring(name))
end
function CreateFrame(kind)return widget(kind)end
function UIDropDownMenu_SetWidth()end
function UIDropDownMenu_Initialize()end
function UIDropDownMenu_CreateInfo()return{}end
function UIDropDownMenu_AddButton()end
function UIDropDownMenu_SetSelectedValue()end
function UIDropDownMenu_SetText()end
function UnitGUID()return"local-character"end

assert(loadfile(source))()
local profiles=assert(HolyStorm.Profiles)
assert(type(moduleUI.RegisterPage)=="function","the UI module fixture exposes the legacy page method")
assert(moduleUI.AddNavigation==nil,"the UI module fixture must not provide navigation")
assert(type(managerUI.AddNavigation)=="function","the UI manager owns navigation")
profiles:BuildUI()
assert(#localPageRegistrations==0,"Profiles does not bypass UIManager with the UI module's legacy page method")
assert(#pageRegistrations==1 and pageRegistrations[1].id=="profiles","Profiles registers its feature page through UIManager")
assert(#navigationRegistrations==1 and navigationRegistrations[1].id=="profiles","Profiles registers navigation through HolyStorm.UI")
navigationRegistrations[1].callback()
assert(#shownPages==1 and shownPages[1]=="profiles","profile navigation opens the registered page through UIManager")
profiles:OnDisable()
assert(#unregisteredPages==1 and unregisteredPages[1]=="profiles","Profiles unregisters its page through UIManager")

print("Player Profile UI page and central navigation API separation passed")
