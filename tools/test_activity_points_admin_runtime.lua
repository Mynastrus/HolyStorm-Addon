-- Build Activity Points against the production shared UI implementations.
local root=(arg[0]:gsub("tools[/\\]test_activity_points_admin_runtime.lua$","")).."LIVE/"
local selectors,labels,currentSelector={},{},nil
local function region(kind,parent)
    local object={kind=kind,parent=parent,width=720,height=720,shown=true,textValue="",points={}}
    function object:SetParent(value)self.parent=value end
    function object:SetSize(width,height)self.width,self.height=width,height end
    function object:SetWidth(value)self.width=value end
    function object:SetHeight(value)self.height=value end
    function object:GetWidth()return self.width end
    function object:GetHeight()return self.height end
    function object:SetPoint(...)self.points[#self.points+1]={...}end
    function object:ClearAllPoints()self.points={}end
    function object:SetAllPoints()end
    function object:SetScript(event,callback)self[event]=callback end
    function object:HookScript(event,callback)self[event]=callback end
    if kind~="font"and kind~="texture"then
        function object:CreateTexture()return region("texture",self)end
        function object:CreateFontString()return region("font",self)end
    end
    if kind=="texture"then
        function object:SetTexture(value)self.texture=value end
        function object:SetTexCoord(...)self.texCoord={...}end
        function object:SetColorTexture(...)self.color={...}end
    end
    if kind=="font"or kind=="Button"or kind=="EditBox"then
        function object:SetText(value)self.textValue=value or"";if self.kind=="font"then labels[self.textValue]=true end end
        function object:GetText()return self.textValue end
    end
    if kind=="font"then
        function object:GetStringHeight()return 18 end
        function object:SetTextColor()end
        function object:SetJustifyH()end
        function object:SetJustifyV()end
        function object:SetWordWrap()end
    end
    if kind=="EditBox"then function object:SetAutoFocus()end end
    if kind=="Button"then function object:RegisterForClicks()end end
    if kind=="Button"or kind=="EditBox"then function object:SetEnabled(value)self.enabled=value~=false end end
    function object:SetAlpha(value)self.alpha=value end
    function object:SetShown(value)self.shown=value==true end
    function object:IsShown()return self.shown end
    function object:Show()self.shown=true end
    function object:Hide()self.shown=false end
    if kind=="ScrollFrame"then
        function object:SetScrollChild(value)self.scrollChild=value end
        function object:SetVerticalScroll(value)self.verticalScroll=value end
    end
    return object
end
function CreateFrame(kind,_,parent,template)
    local frame=region(kind,parent)
    if template=="UIDropDownMenuTemplate"then selectors[#selectors+1]=frame end
    return frame
end
function UIDropDownMenu_SetWidth(menu,width)menu.width=width end
function UIDropDownMenu_Initialize(menu,callback)menu.initialize=function(_,level)currentSelector=menu;callback(menu,level);currentSelector=nil end end
function UIDropDownMenu_SetText(menu,value)menu.label=value end
function UIDropDownMenu_CreateInfo()return{}end
function UIDropDownMenu_AddButton(info)currentSelector.lastItem=info end

local locale=setmetatable({ACTIVITY_POINTS_RULES="Point Rules",ACTIVITY_POINTS_DECAY_SECTION="Decay",ACTIVITY_POINTS_MANUAL_ADJUSTMENT="Manual Adjustment",ACTIVITY_POINTS_RULE_NAME="Rule name",ACTIVITY_POINTS_DECAY_MODE="Decay mode",ACTIVITY_POINTS_TARGET="Target"},{__index=function(_,key)return key end})
local guild={rules={},decay={mode="FIXED",intervalDays=30,amount=4}}
local function copy(value)
    if type(value)~="table"then return value end
    local result={};for key,item in pairs(value)do result[copy(key)]=copy(item)end;return result
end
local modules={}
local HolyStorm={Utils={DeepCopy=copy,SafeCall=function(_,callback,...)return pcall(callback,...)end},Data={GuildActivityPointsStore={GetGuild=function()return guild end,GetRules=function()return guild.rules end},GuildStore={GetCurrent=function()return{roster={}}end}},GuildManagement={GetGuildId=function()return"guild"end},Events={},UI={}}
function HolyStorm:RegisterRequiredModule(id)local module={};modules[id]=module;return module end
function HolyStorm:ApplyModuleMetadata(module,metadata)module.metadata=metadata end
function HolyStorm.Events:Emit()end
HolyStorm.FilterManager={GetRules=function()return{}end,GetFilters=function()return{}end,GetFilterTemplates=function()return{}end}
HolyStorm.PolicyState={GetPermissionStateStatus=function()return{status="VALID",revisionID="rev"}end,status={VALID="VALID"}}
HolyStorm.PermissionRegistry={GetPermissions=function()return{}end}
HolyStorm.PermissionEngine={HasPermission=function()return true end}
HolyStorm.GroupManager={GetGroups=function()return{}end,systemIds={LEADERSHIP="leadership"}}
HolyStorm.Rules={GetFields=function()return{}end,GetField=function()return nil end,GetAllowedOperators=function()return{}end,GetOperator=function()return{requiresValue=false}end,Validate=function()return true end}
local aceGUI={Create=function(_,kind)
    assert(kind=="HolyStormTabGroup","unexpected AceGUI widget: "..tostring(kind))
    local content=region("tab-content")
    return{frame=region("tab-frame"),SetLayout=function()end,SetTabs=function()end,SetCallback=function()end,GetContentFrame=function()return content end}
end}
function LibStub(name)
    if name=="AceAddon-3.0"then return{GetAddon=function()return HolyStorm end}end
    if name=="AceLocale-3.0"then return{GetLocale=function()return locale end}end
    if name=="AceGUI-3.0"then return aceGUI end
end
assert(loadfile(root.."Holy_Storm_UI/UI/Framework/Layout.lua"))()
assert(loadfile(root.."Holy_Storm_UI/UI/Framework/Components.lua"))()
assert(loadfile(root.."Holy_Storm_UI/UI/Framework/Table.lua"))()
assert(loadfile(root.."Holy_Storm_UI/UI/Framework/Components/PolicyUI.lua"))()
HolyStorm.UI.Components=HolyStorm.UIComponents
HolyStorm.PolicyUI.CharacterItems=function()return{}end
assert(HolyStorm.UIComponents.CreateSelector==nil,"production UIComponents must not gain a test-only selector")
assert(loadfile(root.."Holy_Storm_Guild/Services/ActivityPoints.lua"))()
local parent=region("parent")
local points=HolyStorm.GuildManagement.ActivityPoints
local page=points:BuildAdmin(parent)
assert(page and page.parent==parent,"Activity Points must return a frame owned by the Administration viewport")
assert(page.kind=="Frame" and #selectors==3,"event, decay and target must use real PolicyUI dropdowns")
assert(points.adminEventSelector==selectors[1] and points.adminDecayMode==selectors[2],"builder must retain production selector frames")
assert(selectors[1]:GetValue()=="MYTHICPLUS_RUN" and selectors[2]:GetValue()=="FIXED","selector GetValue/SetValue contract must survive initial render")
assert(points.adminDecayInterval.edit:GetText()=="30" and points.adminDecayAmount.edit:GetText()=="4","decay fields must receive saved values")
assert(page:IsShown() and points.adminTable and points.adminTable.SetData,"shared scroll, table and form must build")
for _,label in ipairs({"Point Rules","Decay","Manual Adjustment","Rule name","Decay mode","Target"})do assert(labels[label],"missing visible label: "..label)end
selectors[1].initialize(selectors[1],1)
assert(selectors[1].lastItem and selectors[1].lastItem.func,"Retail dropdown must populate selectable items")
for _,entry in ipairs({{"Rules.lua","RulesUI"},{"Filters.lua","FiltersUI"},{"Permissions.lua","PermissionsUI"},{"PolicyInspector.lua","PolicyInspectorUI"}})do
    assert(loadfile(root.."Holy_Storm_UI/UI/Administration/"..entry[1]))()
    local module=assert(modules[entry[2]],entry[1].." module missing")
    local built=module:Build(region("admin-viewport"))
    assert(built and built.kind=="Frame",entry[1].." must build with production shared UI controls")
end
print("Activity Points, Rules, Filters, Permissions and Policy Inspector production UI builds passed")
