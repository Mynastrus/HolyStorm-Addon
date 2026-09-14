local HolyStorm=LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
HolyStorm.UIComponents=HolyStorm.UIComponents or{}

local Components=HolyStorm.UIComponents

local function noWrap(fontString)
 if not fontString then return end
 fontString:SetWordWrap(false)
 if fontString.SetMaxLines then fontString:SetMaxLines(1)end
 if fontString.SetNonSpaceWrap then fontString:SetNonSpaceWrap(false)end
end

function Components:CreateHeaderBar(parent,anchor,options)
 options=options or{};anchor=anchor or parent
 local frame=CreateFrame("Frame",nil,parent)
 frame:SetPoint("BOTTOMLEFT",anchor,"TOPLEFT",options.left or 52,options.y or 4)
 frame:SetPoint("BOTTOMRIGHT",anchor,"TOPRIGHT",options.right or-12,options.y or 4)
 frame:SetHeight(options.height or 34)
 frame:Hide()

 local primary=frame:CreateTexture(nil,"ARTWORK");primary:SetSize(options.iconSize or 28,options.iconSize or 28);primary:SetPoint("LEFT",0,0)
 local secondary=frame:CreateTexture(nil,"ARTWORK");secondary:SetSize(options.iconSize or 28,options.iconSize or 28);secondary:SetPoint("LEFT",primary,"RIGHT",options.iconGap or 5,0);secondary:Hide()
 local title=frame:CreateFontString(nil,"OVERLAY",options.titleFont or"GameFontNormal");title:SetPoint("TOPLEFT",secondary,"TOPRIGHT",options.textGap or 12,options.titleY or-2);title:SetPoint("RIGHT",frame,"RIGHT",options.textRight or-250,0);title:SetJustifyH("LEFT");noWrap(title)
 local subtitle=frame:CreateFontString(nil,"OVERLAY",options.subtitleFont or"GameFontHighlightSmall");subtitle:SetPoint("TOPLEFT",title,"BOTTOMLEFT",0,options.subtitleGap or-3);subtitle:SetPoint("RIGHT",frame,"RIGHT",options.textRight or-250,0);subtitle:SetJustifyH("LEFT");noWrap(subtitle)
 local watermark=frame:CreateTexture(nil,"BACKGROUND");watermark:SetSize(options.watermarkSize or 48,options.watermarkSize or 48);watermark:SetPoint("RIGHT",options.watermarkRight or-205,0);watermark:SetAlpha(options.watermarkAlpha or.08)
 local status=frame:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");status:SetPoint("TOPRIGHT",options.statusRight or-32,options.statusTop or-2);status:SetSize(options.statusWidth or 260,14);status:SetJustifyH("RIGHT");status:SetJustifyV("TOP");noWrap(status)
 local updated=frame:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");updated:SetPoint("TOPRIGHT",status,"BOTTOMRIGHT",0,options.updatedGap or-3);updated:SetSize(options.statusWidth or 260,14);updated:SetJustifyH("RIGHT");updated:SetJustifyV("TOP");noWrap(updated)
 local developer=frame:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");developer:SetPoint("BOTTOMRIGHT",options.statusRight or-32,0);developer:SetTextColor(.5,.5,.5)
 local refresh=CreateFrame("Button",nil,frame);refresh:SetSize(options.refreshSize or 22,options.refreshSize or 22);refresh:SetPoint("RIGHT",0,0);refresh:SetNormalTexture("Interface\\Buttons\\UI-RefreshButton");refresh:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight","ADD")

 return{frame=frame,primaryIcon=primary,secondaryIcon=secondary,title=title,subtitle=subtitle,watermark=watermark,status=status,updated=updated,developer=developer,refreshButton=refresh}
end
