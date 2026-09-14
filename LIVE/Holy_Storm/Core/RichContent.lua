local addonVersion="1.0.0"
local HolyStorm=LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local L=LibStub("AceLocale-3.0"):GetLocale("Holy_Storm")
local Rich={version=addonVersion,types={},tokens={},cache={},cacheOrder={},maxBody=60000,maxTokens=250,maxTokenLength=320}

local function encode(value)return(tostring(value or""):gsub("([^%w%-%._,])",function(char)return string.format("%%%02X",string.byte(char))end))end
local function decode(value)return(tostring(value or""):gsub("%%(%x%x)",function(hex)return string.char(tonumber(hex,16))end))end
local function safeLabel(value)return tostring(value or""):gsub("[|\r\n]"," "):sub(1,180)end
local function patternEscape(value)return(tostring(value or""):gsub("([^%w])","%%%1"))end

function Rich:RegisterType(definition)
 if type(definition)~="table"or type(definition.type)~="string"or not definition.type:match("^[a-z][a-z0-9%-]*$")or type(definition.render)~="function"then return false,"INVALID_LINK_TYPE"end
 if self.types[definition.type]then if HolyStorm.Logger then HolyStorm.Logger:Write("WARN","RichContent","link","Duplicate link registration",{type=definition.type})end;return false,"DUPLICATE_LINK_TYPE"end
 self.types[definition.type]=definition;return true
end
function Rich:GetType(id)return self.types[id]end
function Rich:GetTypes()return self.types end
function Rich:RegisterToken(definition)
 if type(definition)~="table"or type(definition.id)~="string"or not definition.id:match("^[A-Z][A-Z0-9_%-]*$")or(type(definition.render)~="function"and type(definition.display)~="function")then return false,"INVALID_TOKEN"end
 definition.render=definition.render or definition.display
 if self.tokens[definition.id]then if HolyStorm.Logger then HolyStorm.Logger:Write("WARN","RichContent","token","Duplicate token registration",{token=definition.id})end;return false,"DUPLICATE_TOKEN"end
 self.tokens[definition.id]=definition;return true
end
function Rich:GetTokens()return self.tokens end
function Rich:MakeToken(linkType,target,label)local definition=self.types[linkType];if not definition then return nil,"UNKNOWN_LINK_TYPE"end;target=tostring(target or"");if#target==0 or#target>self.maxTokenLength or target:find("[\r\n%[%]|]")then return nil,"INVALID_TARGET"end;return"[["..linkType..":"..target..(label and("|"..safeLabel(label))or"").."]]"end
function Rich:MakeHyperlink(linkType,target,label,colorHex)
 local definition=self.types[linkType];if not definition then return safeLabel(label~=""and label or(linkType..": "..tostring(target)))end
 local ok,rendered=HolyStorm.Utils.SafeCall("richlink.render:"..linkType,definition.render,target,label);if not ok then rendered=nil end;if type(rendered)=="string"and rendered:find("|H",1,true)then return rendered end
 colorHex=type(colorHex)=="string"and colorHex:match("^%x%x%x%x%x%x$")and string.lower(colorHex)or"3fc7eb"
 return"|cff"..colorHex.."|Hholystorm:"..linkType..":"..encode(target).."|h["..safeLabel(rendered or label or target).."]|h|r"
end
function Rich:RenderInline(text,diagnostics)
 local count=0
 text=tostring(text or""):gsub("%[%[([a-z][a-z0-9%-]*):([^]|]+)|?([^]]*)%]%]",function(linkType,target,label)
  count=count+1;if count>self.maxTokens then diagnostics.errors[#diagnostics.errors+1]="TOKEN_LIMIT";return"["..L["RICH_LINK_LIMIT"].."]"end
  local definition=self.types[linkType];diagnostics.links[#diagnostics.links+1]={type=linkType,target=target,resolved=definition~=nil}
  if#target>self.maxTokenLength then diagnostics.errors[#diagnostics.errors+1]="TOKEN_TOO_LONG";return"["..safeLabel(label~=""and label or linkType).."]"end
  if not definition then diagnostics.unresolved[#diagnostics.unresolved+1]={type=linkType,target=target};return"["..safeLabel(label~=""and label or(linkType..": "..target)).."]"end
  if definition.validate and not definition.validate(target)then diagnostics.errors[#diagnostics.errors+1]="INVALID_"..linkType:upper();return"["..safeLabel(label~=""and label or target).."]"end
  return self:MakeHyperlink(linkType,target,label~=""and label or nil)
 end)
 text=text:gsub("%*%*(.-)%*%*","|cffffd100%1|r");text=text:gsub("%*([^*\r\n]-)%*","|cffb8b8b8%1|r");return text
end
function Rich:RenderRegisteredTokens(text,diagnostics)
 diagnostics=diagnostics or{links={},tokens={},unresolved={},errors={}};diagnostics.tokens=diagnostics.tokens or{};diagnostics.unresolved=diagnostics.unresolved or{};diagnostics.errors=diagnostics.errors or{}
 return(tostring(text or""):gsub("{{([A-Z][A-Z0-9_%-]*):?([^}]*)}}",function(id,payload)
  local definition=self.tokens[id];diagnostics.tokens[#diagnostics.tokens+1]={id=id,payload=payload,resolved=definition~=nil}
  if not definition then diagnostics.unresolved[#diagnostics.unresolved+1]={token=id,payload=payload};return"["..safeLabel(id..(payload~=""and(": "..payload)or"")).."]"end
  if#payload>self.maxTokenLength or(definition.validate and not definition.validate(payload))then diagnostics.errors[#diagnostics.errors+1]="INVALID_TOKEN_"..id;return"["..safeLabel(definition.fallback or id).."]"end
  local parsed=payload;if definition.parser then local parsedOK,value=HolyStorm.Utils.SafeCall("token.parse:"..id,definition.parser,payload);if not parsedOK or value==nil then diagnostics.errors[#diagnostics.errors+1]="TOKEN_PARSER_"..id;return"["..safeLabel(definition.fallback or id).."]"end;parsed=value end
  local ok,result=HolyStorm.Utils.SafeCall("token.render:"..id,definition.render,parsed,diagnostics);if not ok or type(result)~="string"then diagnostics.errors[#diagnostics.errors+1]="TOKEN_HANDLER_"..id;return"["..safeLabel(definition.fallback or id).."]"end;if definition.onClick or definition.tooltip then return self:MakeHyperlink("token",id.."\031"..payload,result)end;return result
 end))
end
function Rich:Parse(body)
 body=tostring(body or"");if#body>self.maxBody then body=body:sub(1,self.maxBody)end
 local cached=self.cache[body];if cached then return HolyStorm.Utils.DeepCopy(cached.blocks),HolyStorm.Utils.DeepCopy(cached.diagnostics)end
 local blocks,diagnostics={}, {links={},unresolved={},errors={}};body=body:gsub("\r\n","\n"):gsub("\r","\n")
 local paragraph={};local function flush()if#paragraph>0 then blocks[#blocks+1]={kind="paragraph",text=self:RenderInline(table.concat(paragraph,"\n"),diagnostics)};paragraph={}end end
 for line in(body.."\n"):gmatch("(.-)\n")do
  if line==""then flush()
  elseif line:match("^%s*%-%-%-%s*$")then flush();blocks[#blocks+1]={kind="rule",text=""}
  else local marks,title=line:match("^(#+)%s+(.+)$");local bullet=line:match("^%s*[-*]%s+(.+)$");if marks then flush();blocks[#blocks+1]={kind=#marks==1 and"heading1"or"heading2",text=self:RenderInline(title,diagnostics)}elseif bullet then flush();blocks[#blocks+1]={kind="bullet",text="•  "..self:RenderInline(bullet,diagnostics)}else paragraph[#paragraph+1]=line end end
 end;flush()
 self.cache[body]={blocks=HolyStorm.Utils.DeepCopy(blocks),diagnostics=HolyStorm.Utils.DeepCopy(diagnostics)};self.cacheOrder[#self.cacheOrder+1]=body;if#self.cacheOrder>50 then self.cache[table.remove(self.cacheOrder,1)]=nil end
 return blocks,diagnostics
end
function Rich:Invalidate()self.cache={};self.cacheOrder={}end
function Rich:ReplaceModifiedChatLink(link,target,definition)
 if not(IsModifiedClick and IsModifiedClick("CHATLINK"))or type(definition.chatText)~="function"then return false end
 local ok,plain=HolyStorm.Utils.SafeCall("richlink.chat:"..tostring(definition.type or"unknown"),definition.chatText,target);if not ok or type(plain)~="string"then return true end;plain=safeLabel(plain);if plain==""then return true end
 local editBox=(ChatFrameUtil and ChatFrameUtil.GetActiveWindow and ChatFrameUtil.GetActiveWindow())or(ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow())or(GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus());local current=editBox and editBox.GetText and editBox:GetText()
 if type(current)=="string"then local escaped=patternEscape(link);local function replace(value)value=value:gsub("|c%x%x%x%x%x%x%x%x|H"..escaped.."|h.-|h|r",plain);return(value:gsub("|H"..escaped.."|h.-|h",plain))end;local updated=replace(current);if updated~=current then local cursor=editBox.GetCursorPosition and editBox:GetCursorPosition()or#current;local prefix=replace(current:sub(1,cursor));editBox:SetText(updated);if editBox.SetCursorPosition then editBox:SetCursorPosition(#prefix)end;return true end end
 local insert=(ChatFrameUtil and ChatFrameUtil.InsertLink)or ChatEdit_InsertLink;if insert then insert(plain)end;return true
end
function Rich:HandleHyperlink(link,button,owner)
 local value=tostring(link or"");if value=="holystorm:status"or value=="holystorm:open"or value=="holystorm:help"then return false end;local linkType,payload=value:match("^holystorm:([a-z][a-z0-9%-]*):(.+)$");local definition=linkType and self.types[linkType];if not definition then if value:match("^holystorm:")then if HolyStorm.Logger then HolyStorm.Logger:Write("WARN","RichContent","link","Unsupported Holy Storm link",{link=value})end;return true end;return false end;local target=decode(payload);if#target>self.maxTokenLength or(definition.validate and not definition.validate(target))then if HolyStorm.Logger then HolyStorm.Logger:Write("WARN","RichContent","link","Invalid Holy Storm link",{type=linkType})end;return true end;if self:ReplaceModifiedChatLink(value,target,definition)then return true end;if definition.onClick then local ok,err=HolyStorm.Utils.SafeCall("richlink.click:"..linkType,definition.onClick,target,button,owner);if not ok and HolyStorm.Logger then HolyStorm.Logger:Write("ERROR","RichContent","handler","Rich-link click handler failed",{type=linkType,error=tostring(err)})end end;return true
end
function Rich:ShowTooltip(owner,link)
 local linkType,payload=tostring(link or""):match("^holystorm:([a-z][a-z0-9%-]*):(.+)$");local definition=linkType and self.types[linkType];if not definition then return false end;local target=decode(payload);if definition.showTooltip then local ok,shown=HolyStorm.Utils.SafeCall("richlink.tooltip:"..linkType,definition.showTooltip,owner,target);return ok and shown==true end;if not definition.tooltip then return false end;local ok,title,description,tooltipLink=HolyStorm.Utils.SafeCall("richlink.tooltip:"..linkType,definition.tooltip,target);if not ok then return false end;GameTooltip:SetOwner(owner,"ANCHOR_CURSOR_RIGHT");if tooltipLink then GameTooltip:SetHyperlink(tooltipLink)else GameTooltip:SetText(title or linkType);if description then GameTooltip:AddLine(description,1,1,1,true)end end;GameTooltip:Show();return true
end
function Rich:InsertChatLink(linkType,target,label)local link=self:MakeHyperlink(linkType,target,label);if ChatEdit_InsertLink and ChatEdit_InsertLink(link)then return true,link end;return false,link end

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

function Rich:Initialize()
 self:RegisterType({type="item",validate=function(target)return tonumber(target)~=nil end,render=function(target,label)local _,link=GetItemInfo and GetItemInfo(tonumber(target));return link or(label or string.format(L["RICH_ITEM_FALLBACK"],target))end,onClick=function(target)if HandleModifiedItemClick then local _,link=GetItemInfo(tonumber(target));if link then HandleModifiedItemClick(link)end end end,tooltip=function(target)local _,link=GetItemInfo and GetItemInfo(tonumber(target));return nil,nil,link end})
 local function characterRender(target,label)local record=HolyStorm.Data.CharacterStore:Get(target);return label or(record and(record.fullName or record.name))or target end
 local function characterChatText(target)local record=HolyStorm.Data.CharacterStore:Get(target);local name=record and(record.name or record.fullName)or target;return tostring(name):match("^([^%-]+)")or tostring(name)end
 local function characterClick(target,button,owner)if button=="RightButton"and HolyStorm.CharacterActions then return HolyStorm.CharacterActions:CreateContextMenu(owner or DEFAULT_CHAT_FRAME or UIParent,target)end;HolyStorm:CallCapability("character.open",target,"summary")end
 local function characterTooltip(target)local record=HolyStorm.Data.CharacterStore:Get(target);return record and(record.fullName or record.name)or target,record and record.class end
 local function showCharacterTooltip(owner,target)return HolyStorm.CharacterUI and HolyStorm.CharacterUI:ShowTooltip(owner,target)end
 local function showPlayerTooltip(owner,target)if HolyStorm.Database:Get("chat.playerTooltips","profile")==false then return false end;return showCharacterTooltip(owner,target)end
 self:RegisterType({type="character",render=characterRender,chatText=characterChatText,onClick=characterClick,tooltip=characterTooltip,showTooltip=showCharacterTooltip,owner="CharacterUI"});self:RegisterType({type="player",render=characterRender,chatText=characterChatText,onClick=characterClick,tooltip=characterTooltip,showTooltip=showPlayerTooltip,owner="Chat"})
 local function tokenParts(target)local id,payload=tostring(target):match("^([^\031]+)\031(.*)$");return id,payload end
 local function tokenDefinition(target)local id,payload=tokenParts(target);return id and self.tokens[id],id,payload end
 local function tokenParsed(definition,id,payload)if not definition then return nil end;if definition.validate and not definition.validate(payload)then return nil end;if definition.parser then local ok,value=HolyStorm.Utils.SafeCall("token.parse:"..id,definition.parser,payload);return ok and value or nil end;return payload end
 self:RegisterType({type="token",owner="RichContent",validate=function(target)return tokenDefinition(target)~=nil end,render=function(target,label)local definition,id,payload=tokenDefinition(target);local parsed=tokenParsed(definition,id,payload);if not parsed then return label or id or target end;local ok,value=HolyStorm.Utils.SafeCall("token.render:"..id,definition.render,parsed);return label or(ok and value)or definition.fallback or id end,onClick=function(target,button,owner)local definition,id,payload=tokenDefinition(target);local parsed=tokenParsed(definition,id,payload);if parsed and definition.onClick then definition.onClick(parsed,button,owner)end end,tooltip=function(target)local definition,id,payload=tokenDefinition(target);local parsed=tokenParsed(definition,id,payload);if parsed and definition.tooltip then return definition.tooltip(parsed)end;return id end})
 self:RegisterType({type="coordinate",validate=function(target)local map,x,y=target:match("^(%d+),([%d%.]+),([%d%.]+)$");return tonumber(map)and tonumber(x)and tonumber(x)<=1 and tonumber(y)and tonumber(y)<=1 end,render=function(target,label)local map,x,y=target:match("^(%d+),([%d%.]+),([%d%.]+)$");return label or string.format("%.1f, %.1f",tonumber(x)*100,tonumber(y)*100)end,onClick=function(target)local map,x,y=target:match("^(%d+),([%d%.]+),([%d%.]+)$");HolyStorm.MapLinks:OpenCoordinate(map,x,y)end,tooltip=function(target)return target end})
 self:RegisterType({type="poi",render=function(target,label)local poi=HolyStorm.MapLinks:ResolvePOI(target);return label or(poi and poi.name)or target end,onClick=function(target)HolyStorm.MapLinks:OpenPOI(target)end,tooltip=function(target)local poi=HolyStorm.MapLinks:ResolvePOI(target);return poi and poi.name or target,poi and poi.description or L["RICH_POI_UNAVAILABLE"]end})
 local function contentRender(target,label)local entry=HolyStorm.Content and HolyStorm.Content:GetVisibleById(target);return label or(entry and entry.title)or target end
 local function contentClick(target)if HolyStorm.Content then HolyStorm.Content:Open(target)end end
 local function contentTooltip(target)local entry=HolyStorm.Content and HolyStorm.Content:GetVisibleById(target);return entry and entry.title or target,entry and(entry.type.." · "..entry.category)or L["RICH_CONTENT_UNAVAILABLE"]end
 self:RegisterType({type="news",render=contentRender,onClick=contentClick,tooltip=contentTooltip});self:RegisterType({type="guide",render=contentRender,onClick=contentClick,tooltip=contentTooltip})
end
HolyStorm.RichContent,HolyStorm.RichLinks=Rich,Rich
