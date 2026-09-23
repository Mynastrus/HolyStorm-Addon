local addonVersion="1.1.0"
local HolyStorm=LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local L=LibStub("AceLocale-3.0"):GetLocale("Holy_Storm")
local Commands={version=addonVersion,handlers={}}
local function printMessage(message) print(L["ADDON_PREFIX"]..message) end
function Commands:PrintUserMessage(message)if type(message)~="string"or message==""then return false end;printMessage(message);return true end
local function commandLink(command,action)return HolyStorm.RichLinks:GetType("command")and HolyStorm.RichLinks:MakeHyperlink("command",action,command)or string.format("|cffffff00|Hholystorm:%s|h%s|h|r",action,command)end
local function tooltipFor(link)
    if link=="holystorm:status" or link=="holystorm:open" then return L["COMMAND_TOOLTIP_OPEN_TITLE"],L["COMMAND_TOOLTIP_OPEN_DESCRIPTION"] end
    if link=="holystorm:help" then return L["COMMAND_TOOLTIP_HELP_TITLE"],L["COMMAND_TOOLTIP_HELP_DESCRIPTION"] end
end
function Commands:Initialize()
    SLASH_HOLYSTORM1,SLASH_HOLYSTORM2,SLASH_HOLYSTORM3="/holystorm","/hs","/holy_storm"
    SlashCmdList.HOLYSTORM=function(input) Commands:Execute(input) end
    local commandActions={open="",status="",help="?",options="options"}
    HolyStorm.RichLinks:RegisterType({type="command",owner="Commands",validate=function(action)return commandActions[action]~=nil end,render=function(action,label)return label or("/hs "..action)end,onClick=function(action)Commands:Execute(commandActions[action])end,tooltip=function(action)local legacy=action=="open"and"holystorm:open"or action=="status"and"holystorm:status"or action=="help"and"holystorm:help";local title,description=tooltipFor(legacy);return title or L["COMMAND_TOOLTIP_OPEN_TITLE"],description or L["COMMAND_TOOLTIP_OPEN_DESCRIPTION"]end})
    HolyStorm.Hooks:Secure("commands:set-item-ref","SetItemRef",function(link,_,button,owner)if HolyStorm.RichLinks:HandleHyperlink(link,button,owner)then return elseif HolyStorm.Chat and HolyStorm.Chat:HandleNativePlayerLink(link,button,owner)then return elseif link=="holystorm:status" or link=="holystorm:open" then Commands:Execute("") elseif link=="holystorm:help" then Commands:Execute("?") end end)
    for index=1,NUM_CHAT_WINDOWS do local frame=_G["ChatFrame"..index]; if frame then
        HolyStorm.Hooks:Script("commands:enter:"..index,"commands",frame,"OnHyperlinkEnter",function(owner,link)if HolyStorm.RichLinks:ShowTooltip(owner,link)or(HolyStorm.Chat and HolyStorm.Chat:ShowNativePlayerTooltip(owner,link))then return end;local title,description=tooltipFor(link);if title then GameTooltip:SetOwner(owner,"ANCHOR_CURSOR_RIGHT");GameTooltip:SetText(title);GameTooltip:AddLine(description,1,1,1,true);GameTooltip:Show()end end)
        HolyStorm.Hooks:Script("commands:leave:"..index,"commands",frame,"OnHyperlinkLeave",function(_,link)if HolyStorm.RichLinks:GetType(tostring(link):match("^holystorm:([a-z][a-z0-9%-]*):"))or(HolyStorm.Chat and HolyStorm.Chat:IsNativePlayerLink(link))or tooltipFor(link)then GameTooltip:Hide()end end)
    end end
end
function Commands:RegisterSubcommand(id,definition)
    if type(id)~="string"or not id:match("^[a-z][a-z0-9%-]*$")or type(definition)~="table"or type(definition.execute)~="function"then return false,"INVALID_SUBCOMMAND"end
    self.handlers[id]=definition
    return true
end
function Commands:UnregisterSubcommand(id)if not self.handlers[id]then return false end;self.handlers[id]=nil;return true end
function Commands:Execute(input)
    local value=HolyStorm.Utils.Trim(input or "")
    if value=="?" then printMessage(L["COMMAND_HELP_TITLE"]);printMessage(L["COMMAND_HELP_OPEN"]);printMessage(L["COMMAND_HELP_OPTIONS"]);printMessage(L["COMMAND_HELP_ADDONS"]);local ids={};for id in pairs(self.handlers)do ids[#ids+1]=id end;table.sort(ids);for _,id in ipairs(ids)do local help=self.handlers[id].help;if type(help)=="function"then help=help()end;if help then printMessage(help)end end;printMessage(L["COMMAND_HELP_HELP"])
    elseif value=="" then if HolyStorm.UI then HolyStorm.UI:Open()else printMessage(L["COMMAND_UI_UNAVAILABLE"]or"UI addon is not loaded.")end
    elseif value=="options" or value=="o" then local module=HolyStorm:GetModule("Options",true);if module then module:Open()end
    elseif value=="addons" then local addons=HolyStorm:GetLoadedAddonNames();printMessage(string.format(L["COMMAND_LOADED_ADDONS"],#addons,table.concat(addons,", ")))
    else local id,args=value:match("^([^%s]+)%s*(.*)$");local handler=id and self.handlers[id];if handler then local ok,err=HolyStorm.Utils.SafeCall("command:"..id,handler.execute,args);if not ok and HolyStorm.Logger then HolyStorm.Logger:ERROR("Commands","Subcommand %s failed: %s",id,tostring(err))end else printMessage(string.format(L["CORE_STATUS"],L[HolyStorm.Database:Get("enabled","profile")and"STATUS_ENABLED"or"STATUS_DISABLED"]))end end
end
function Commands:AnnounceLoaded()printMessage(string.format(L["CORE_LOADED"],HolyStorm.metadata.displayName,HolyStorm.version));printMessage(string.format(L["CORE_LOADED_HELP"],commandLink("/hs","open"),commandLink("/hs ?","help")))end
HolyStorm.Commands=Commands
