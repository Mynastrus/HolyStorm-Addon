-- Offline smoke test for the row-pooled log UI. Run with: lua tools/test_logs_ui.lua
local root=(arg[0]:gsub("tools[/\\]test_logs_ui.lua$","")).."LIVE/Holy_Storm/"
local locale=setmetatable({}, {__index=function(_,key)return key end})
local Frame={}
Frame.__index=Frame
function Frame:SetSize(width,height)self.width,self.height=width,height end
function Frame:SetWidth(width)self.width=width end
function Frame:SetHeight(height)self.height=height end
function Frame:GetWidth()return self.width or 1000 end
function Frame:GetHeight()return self.height or 600 end
function Frame:SetPoint()end
function Frame:ClearAllPoints()end
function Frame:SetFrameStrata()end
function Frame:SetBackdrop()end
function Frame:SetBackdropColor()end
function Frame:SetBackdropBorderColor()end
function Frame:SetScript(name,callback)self.scripts=self.scripts or{};self.scripts[name]=callback end
function Frame:RegisterForClicks()end
function Frame:CreateFontString()return setmetatable({shown=true},Frame)end
function Frame:CreateTexture()return setmetatable({shown=true},Frame)end
function Frame:SetAllPoints()end
function Frame:SetColorTexture()end
function Frame:SetJustifyH()end
function Frame:SetJustifyV()end
function Frame:SetWordWrap()end
function Frame:SetTextColor()end
function Frame:SetText(text)self.text=tostring(text or"")end
function Frame:GetText()return self.text or""end
function Frame:GetStringHeight()local _,lines=(self.text or""):gsub("\n","");return(lines+1)*14 end
function Frame:SetChecked(value)self.checked=value end
function Frame:GetChecked()return self.checked end
function Frame:SetShown(value)self.shown=value end
function Frame:IsShown()return self.shown~=false end
function Frame:Show()self.shown=true end
function Frame:Hide()self.shown=false end
function Frame:SetScrollChild(child)self.child=child end
function Frame:SetVerticalScroll(value)self.vertical=value end
function Frame:GetVerticalScroll()return self.vertical or 0 end
function Frame:SetMultiLine()end
function Frame:SetAutoFocus()end
function Frame:SetFontObject()end
function Frame:HighlightText()end
function Frame:SetFocus()end
UIParent=setmetatable({shown=true},Frame)
function CreateFrame()return setmetatable({shown=true,width=1000,height=600},Frame)end
function UIDropDownMenu_SetWidth(frame,width)frame.dropdownWidth=width end
function UIDropDownMenu_SetText(frame,value)frame.dropdownText=value end
function UIDropDownMenu_Initialize(frame,callback)frame.initialize=callback end
function UIDropDownMenu_CreateInfo()return{}end
function UIDropDownMenu_AddButton()end
function date(_,timestamp)return tostring(timestamp or 0)end

local Logs
local HolyStorm={version="5.3.2",db={profile={logs={autoScroll=true}},global={logs={entries={}}}},Logger={history={}},Permissions={Has=function()return true end},UI={}}
function HolyStorm.Logger:GetHistory()local out={};for index,entry in ipairs(self.history)do out[index]=entry end;return out end
function HolyStorm.Logger:Clear()self.history={}end
function HolyStorm:RegisterRequiredModule()Logs={};return Logs end
function HolyStorm:ApplyModuleMetadata()end
function HolyStorm:GetModule()return self.UI end
function HolyStorm.UI:RegisterPage(_,page)self.page=page end
function HolyStorm.UI:AddNavigation()end
function HolyStorm.UI:ShowPage()end
HolyStorm.UI.content=CreateFrame()
function LibStub(name)if name=="AceAddon-3.0"then return{GetAddon=function()return HolyStorm end}elseif name=="AceLocale-3.0"then return{GetLocale=function()return locale end}end end

assert(loadfile(root.."UI/Pages/Logs.lua"))();Logs:OnInitialize()
for index=1,2000 do HolyStorm.Logger.history[index]={timestamp=index,level=index%20==0 and"ERROR"or"DEBUG",source="Module"..(index%7),category=index%3==0 and"event"or"task",message="Entry "..index,context=index%3==0 and{eventName="EVENT_"..(index%5)}or{}}end
Logs:Render();assert(#Logs.filtered==2000 and#Logs.rows<=60,"2000 entries must use a bounded reusable row pool")
Logs:SelectEntry({timestamp=1,level="INFO",source="Legacy",category="general",message="partial",context=nil});assert(Logs.detailsText.text:find("partial",1,true),"detail view must tolerate missing context")
Logs:SetPaused(true);HolyStorm.Logger.history[2001]={timestamp=2001,level="INFO",source="Core",category="ui",message="paused"};Logs:Render();assert(#Logs.filtered==2000,"pause must freeze rendering only");Logs:SetPaused(false);assert(#Logs.filtered==2001,"resume must refresh stored entries")
Logs.exportFormat="json";Logs:ShowExport(false);assert(Logs.exportDialog:IsShown()and Logs.exportDialog.edit.text:sub(1,1)=="[","export dialog must show the selected format")
print("Log UI row pooling, pause/resume, detail and export smoke tests passed")
