local HolyStorm=LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local Tooltips={active={}}
local unpack=unpack or table.unpack
local windowHooked=false
local lifecycleFrame=type(CreateFrame)=="function"and CreateFrame("Frame")or nil
if lifecycleFrame and lifecycleFrame.RegisterEvent and lifecycleFrame.SetScript then
 lifecycleFrame:RegisterEvent("PLAYER_LOGOUT")
 lifecycleFrame:SetScript("OnEvent",function(_,event)if event=="PLAYER_LOGOUT"then Tooltips:ReleaseAll()end end)
end

local function keyFor(id)
 if type(id)~="string"or id==""then return nil end
 return "HolyStorm:"..id
end

function Tooltips:Release(id)
 local key=keyFor(id);local active=key and self.active[key]
 if not active then return false end
 self.active[key]=nil
 pcall(function()active.tooltip:Hide()end)
 pcall(active.library.Release,active.library,active.tooltip)
 return true
end

function Tooltips:ReleaseAll()
 local keys={};for key in pairs(self.active)do keys[#keys+1]=key end
 for _,key in ipairs(keys)do self:Release(key:sub(#"HolyStorm:"+1))end
 return #keys
end

function Tooltips:ReleaseOwner(owner)
 local keys={};for key,active in pairs(self.active)do if active.owner==owner then keys[#keys+1]=key end end
 for _,key in ipairs(keys)do self:Release(key:sub(#"HolyStorm:"+1))end
 return #keys
end

function Tooltips:ShowTable(id,owner,options)
 options=type(options)=="table"and options or{}
 local key=keyFor(id);local columns=options.columns
 if not key or not owner or type(columns)~="table"or#columns==0 then return false end
 self:Release(id)
 local library=LibStub("LibQTip-1.0",true)
 if not library then return false end
 local justifications={};for index,column in ipairs(columns)do justifications[index]=column.align or"LEFT"end
 local acquired,tooltip=pcall(library.Acquire,library,key,#columns,unpack(justifications))
 if not acquired or not tooltip then return false end
 local ok=pcall(function()
  if tooltip.SetClampedToScreen then tooltip:SetClampedToScreen(true)end
  if type(options.anchor)=="table"then tooltip:ClearAllPoints();tooltip:SetPoint(options.anchor.point or"LEFT",owner,options.anchor.relativePoint or"RIGHT",options.anchor.x or 8,options.anchor.y or 0)
  elseif tooltip.SmartAnchorTo then tooltip:SmartAnchorTo(owner)
  else tooltip:ClearAllPoints();tooltip:SetPoint("LEFT",owner,"RIGHT",8,0)end
  for _,header in ipairs(options.headers or{})do tooltip:AddHeader(unpack(header))end
  if options.separator then tooltip:AddSeparator()end
  for _,row in ipairs(options.rows or{})do
   local line=tooltip:AddLine(unpack(row.cells or row))
   for column,color in pairs(row.colors or{})do
    if type(color)=="table"then tooltip:SetCellTextColor(line,column,color.r,color.g,color.b,color.a)end
   end
  end
  tooltip:Show()
 end)
 if not ok then pcall(library.Release,library,tooltip);return false end
 self.active[key]={library=library,tooltip=tooltip,owner=owner}
 local window=HolyStorm.UI and HolyStorm.UI.driver and HolyStorm.UI.driver.frame
 if not windowHooked and window and window.HookScript then window:HookScript("OnHide",function()Tooltips:ReleaseAll()end);windowHooked=true end
 return true,tooltip
end

HolyStorm.Tooltips=Tooltips
