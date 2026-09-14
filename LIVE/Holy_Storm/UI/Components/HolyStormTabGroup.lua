local Type,Version="HolyStormTabGroup",1
local AceGUI=LibStub and LibStub("AceGUI-3.0",true)
if not AceGUI or(AceGUI:GetWidgetVersion(Type)or 0)>=Version then return end

local panelBackdrop={bgFile="Interface\\Buttons\\WHITE8x8",edgeFile="Interface\\Buttons\\WHITE8x8",edgeSize=1}
local fallbackIcon="Interface\\Icons\\INV_Misc_QuestionMark"
local tabHeight,contentGap=30,6

local function style(frame,selected)
 if frame.SetBackdrop then frame:SetBackdrop(panelBackdrop);frame:SetBackdropColor(selected and.035 or.018,selected and.16 or.025,selected and.31 or.04,.98);frame:SetBackdropBorderColor(selected and.15 or.32,selected and.65 or.24,selected and 1 or.08,selected and 1 or.9)end
 if frame.label then frame.label:SetTextColor(selected and.75 or.92,selected and.9 or.92,selected and 1 or.92)end
 if frame.glow then frame.glow:SetShown(selected)end
end

local methods={}
function methods:OnAcquire()
 self.tabs={};self.tabButtons={};self.selected=nil;self:SetWidth(300);self:SetHeight(100)
end
function methods:OnRelease()
 self.selected=nil;self.tabs={};for _,button in pairs(self.tabButtons or{})do button:Hide()end
end
function methods:OnWidthSet(width)
 self.frame.width=width;self:LayoutTabs()
end
function methods:OnHeightSet(height)
 self.frame.height=height;self:LayoutTabs()
end
function methods:LayoutFinished(width,height)
 if width then self:OnWidthSet(width)end;if height then self:OnHeightSet(height)end
end
function methods:GetContentFrame()
 return self.content
end
function methods:UpdateSelection()
 for _,button in pairs(self.tabButtons or{})do style(button,button.value==self.selected)end
end
function methods:LayoutTabs()
 local count=#(self.tabs or{});if count==0 then return end
 local width=math.max(560,(self.frame.GetWidth and self.frame:GetWidth()or self.frame.width or 850));local height=math.max(1,(self.frame.GetHeight and self.frame:GetHeight()or self.frame.height or 100));local gap=4;local buttonWidth=math.floor((width-gap*(count-1))/count)
 self.tabBar:SetHeight(tabHeight);self.content:SetWidth(width);self.content:SetHeight(math.max(1,height-tabHeight-contentGap));self.content:Show()
 for index,tab in ipairs(self.tabs)do local button=self.tabButtons[tab.value];if button then button:ClearAllPoints();button:SetPoint("TOPLEFT",self.tabBar,"TOPLEFT",(index-1)*(buttonWidth+gap),0);button:SetSize(buttonWidth,tabHeight)end end
end
function methods:SetTabs(tabs)
 local seen={};self.tabs=tabs or{}
 for _,tab in ipairs(self.tabs)do
  seen[tab.value]=true;local button=self.tabButtons[tab.value]
  if not button then
   button=CreateFrame("Button",nil,self.tabBar,"BackdropTemplate");button:RegisterForClicks("LeftButtonUp")
   button.icon=button:CreateTexture(nil,"ARTWORK");button.icon:SetSize(18,18);button.icon:SetPoint("LEFT",8,0)
   button.label=button:CreateFontString(nil,"OVERLAY","GameFontNormalSmall");button.label:SetPoint("LEFT",button.icon,"RIGHT",5,0);button.label:SetPoint("RIGHT",-6,0);button.label:SetJustifyH("CENTER")
   button.glow=button:CreateTexture(nil,"BACKGROUND");button.glow:SetPoint("TOPLEFT",1,-1);button.glow:SetPoint("BOTTOMRIGHT",-1,1);button.glow:SetColorTexture(.05,.45,1,.32);button.glow:Hide()
   button:SetScript("OnEnter",function(b)if b.value~=self.selected and b.SetBackdropBorderColor then b:SetBackdropBorderColor(.75,.52,.12,1)end end)
   button:SetScript("OnLeave",function()self:UpdateSelection()end)
   button:SetScript("OnClick",function(b)if b.value then self:SelectTab(b.value)end end)
   self.tabButtons[tab.value]=button
  end
  button.value=tab.value;button.label:SetText(tab.text or tab.value or"");button.icon:SetTexture(tab.icon or fallbackIcon);button:Show()
 end
 for value,button in pairs(self.tabButtons)do if not seen[value]then button:Hide()end end
 self:LayoutTabs();self:UpdateSelection()
end
function methods:SelectTab(value,silent)
 if not value then return end
 self.selected=value;self:UpdateSelection();if not silent then self:Fire("OnGroupSelected",value)end
end

local function Constructor()
 local frame=CreateFrame("Frame",nil,UIParent);frame:SetFrameStrata("FULLSCREEN_DIALOG")
 local tabBar=CreateFrame("Frame",nil,frame);tabBar:SetPoint("TOPLEFT");tabBar:SetPoint("TOPRIGHT");tabBar:SetHeight(tabHeight);tabBar:Show()
 local content=CreateFrame("Frame",nil,frame);content:SetPoint("TOPLEFT",tabBar,"BOTTOMLEFT",0,-contentGap);content:SetPoint("BOTTOMRIGHT");content:SetSize(1,1);content:Show()
 local widget={frame=frame,tabBar=tabBar,content=content,type=Type,tabs={},tabButtons={}}
 frame.obj=widget;tabBar.obj=widget;content.obj=widget
 frame:SetScript("OnSizeChanged",function()widget:LayoutTabs()end);frame:Show()
 for method,func in pairs(methods)do widget[method]=func end
 return AceGUI:RegisterAsContainer(widget)
end

AceGUI:RegisterWidgetType(Type,Constructor,Version)
