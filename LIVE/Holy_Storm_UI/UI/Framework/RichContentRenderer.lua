local HolyStorm=LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local Rich=HolyStorm.RichContent
local function fontFor(kind)return kind=="heading1"and"GameFontNormalHuge"or kind=="heading2"and"GameFontNormalLarge"or"GameFontHighlight"end
function Rich:CreateRenderer(parent)
 local frame=CreateFrame("Frame",nil,parent);frame:SetAllPoints();local scroll=CreateFrame("ScrollFrame",nil,frame,"UIPanelScrollFrameTemplate");scroll:SetPoint("TOPLEFT");scroll:SetPoint("BOTTOMRIGHT",-28,0);local content=CreateFrame("Frame",nil,scroll);content:SetSize(1,1);scroll:SetScrollChild(content);local view={frame=frame,scroll=scroll,content=content,rows={}};scroll:SetScript("OnSizeChanged",function()Rich:Layout(view)end);return view
end
function Rich:Layout(view)
 local width=math.max(1,(view.scroll:GetWidth()or 1)-12);view.content:SetWidth(width);local y=4
 for _,row in ipairs(view.rows)do if row:IsShown()then row:SetWidth(width);row.text:SetWidth(math.max(1,width-20));local height=row.kind=="rule"and 10 or math.max(18,math.ceil(row.text:GetStringHeight()or 18)+8);row:SetHeight(height);row:ClearAllPoints();row:SetPoint("TOPLEFT",view.content,"TOPLEFT",0,-y);y=y+height end end;view.content:SetHeight(math.max(1,y+4))
end
function Rich:Render(view,body,context)
 local blocks,diagnostics=self:Parse(body);for index,block in ipairs(blocks)do local row=view.rows[index];if not row then row=CreateFrame("Frame",nil,view.content);row.text=row:CreateFontString(nil,"OVERLAY","GameFontHighlight");row.text:SetPoint("TOPLEFT",10,-4);row.text:SetJustifyH("LEFT");row.text:SetJustifyV("TOP");row.text:SetWordWrap(true);if row.text.SetHyperlinksEnabled then row.text:SetHyperlinksEnabled(true);row.text:SetScript("OnHyperlinkClick",function(_,link,_,button)Rich:HandleHyperlink(link,button,row.text)end);row.text:SetScript("OnHyperlinkEnter",function(_,link)if link:match("^item:")then GameTooltip:SetOwner(row.text,"ANCHOR_CURSOR_RIGHT");GameTooltip:SetHyperlink(link);GameTooltip:Show()else Rich:ShowTooltip(row.text,link)end end);row.text:SetScript("OnHyperlinkLeave",function()GameTooltip:Hide()end)end;row.rule=row:CreateTexture(nil,"ARTWORK");row.rule:SetColorTexture(.35,.35,.35,1);row.rule:SetPoint("LEFT",10,0);row.rule:SetPoint("RIGHT",-10,0);row.rule:SetHeight(1);view.rows[index]=row end;row.kind=block.kind;row.text:SetFontObject(fontFor(block.kind));row.text:SetText(block.text);row.text:SetShown(block.kind~="rule");row.rule:SetShown(block.kind=="rule");row:Show()end
 for index=#blocks+1,#view.rows do view.rows[index]:Hide()end;view.context=context;self:Layout(view);if C_Timer and C_Timer.After then C_Timer.After(0,function()if view.frame:IsShown()then Rich:Layout(view)end end)end;return diagnostics
end
