local addonVersion="1.1.0"
local HolyStorm=LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local L=LibStub("AceLocale-3.0"):GetLocale("Holy_Storm")
local Commands={version=addonVersion,handlers={},registry={},aliases={}}
local function printMessage(message) print(L["ADDON_PREFIX"]..message) end
function Commands:PrintUserMessage(message)if type(message)~="string"or message==""then return false end;printMessage(message);return true end
local scanTargets={
    raid={block="raid",started="COMMAND_SCAN_STARTED_RAID",unavailable="COMMAND_SCAN_UNAVAILABLE_RAID"},
    equipment={block="equipment",started="COMMAND_SCAN_STARTED_EQUIPMENT",unavailable="COMMAND_SCAN_UNAVAILABLE_EQUIPMENT"},
    mythicplus={block="mythicPlus",started="COMMAND_SCAN_STARTED_MYTHICPLUS",unavailable="COMMAND_SCAN_UNAVAILABLE_MYTHICPLUS"},
    delves={block="delves",started="COMMAND_SCAN_STARTED_DELVES",unavailable="COMMAND_SCAN_UNAVAILABLE_DELVES"},
    stats={block="stats",started="COMMAND_SCAN_STARTED_STATS",unavailable="COMMAND_SCAN_UNAVAILABLE_STATS"},
}
local scanCompleted={raid="COMMAND_SCAN_COMPLETED_RAID",equipment="COMMAND_SCAN_COMPLETED_EQUIPMENT",mythicPlus="COMMAND_SCAN_COMPLETED_MYTHICPLUS",delves="COMMAND_SCAN_COMPLETED_DELVES",stats="COMMAND_SCAN_COMPLETED_STATS"}
local function declarationsByBlock(manager)
    local result={}
    for _,definition in ipairs(manager:GetDeclarations())do result[definition.block]=definition end
    return result
end
local function resolveAndQueueScan(manager,definition)
    if not definition then return false end
    local request={block=definition.block,addonId=definition.addonId,capability=definition.capability,reason="MANUAL_COMMAND"}
    local provider=manager:ResolveProvider(request)
    if not provider then return false end
    return manager:Request(definition.block,"MANUAL_COMMAND",true,{order=definition.order,addonId=definition.addonId,capability=definition.capability})
end
local function registerScanCommand()
    Commands:RegisterSubcommand("scan",{
        help=function()return L["COMMAND_HELP_SCAN"]end,
        execute=function(arguments)
            local target=HolyStorm.Utils.Trim(arguments or ""):lower()
            if target==""then Commands:PrintUserMessage(L["COMMAND_SCAN_USAGE"]);return end
            local manager=HolyStorm.CharacterScans
            if not manager or not UnitGUID or not UnitGUID("player")then Commands:PrintUserMessage(L["COMMAND_SCAN_ALL_UNAVAILABLE"]);return end
            local declarations=declarationsByBlock(manager)
            if target=="raid status"then
                local definition=declarations.raid
                local provider=definition and manager:ResolveProvider({block="raid",addonId=definition.addonId,capability=definition.capability,reason="MANUAL_STATUS"})
                if not provider or type(provider.status)~="function"then Commands:PrintUserMessage(L["COMMAND_SCAN_UNAVAILABLE_RAID"]);return end
                local lines=provider.status()
                for _,line in ipairs(type(lines)=="table"and lines or{})do Commands:PrintUserMessage(line)end
                return
            end
            if target=="all"then
                local started=0
                for _,definition in ipairs(manager:GetDeclarations())do
                    if resolveAndQueueScan(manager,definition)then started=started+1 end
                end
                Commands:PrintUserMessage(started>0 and L["COMMAND_SCAN_ALL_STARTED"]or L["COMMAND_SCAN_ALL_UNAVAILABLE"])
                return
            end
            local targetDefinition=scanTargets[target]
            if not targetDefinition then Commands:PrintUserMessage(string.format(L["COMMAND_SCAN_UNKNOWN_TARGET"],target));Commands:PrintUserMessage(L["COMMAND_SCAN_USAGE"]);return end
            local definition=declarations[targetDefinition.block]
            if resolveAndQueueScan(manager,definition)then Commands:PrintUserMessage(L[targetDefinition.started])else Commands:PrintUserMessage(L[targetDefinition.unavailable])end
        end,
    })
end
local function commandLink(command,action)return HolyStorm.RichLinks:GetType("command")and HolyStorm.RichLinks:MakeHyperlink("command",action,command)or string.format("|cffffff00|Hholystorm:%s|h%s|h|r",action,command)end
local function tooltipFor(link)
    if link=="holystorm:status" or link=="holystorm:open" then return L["COMMAND_TOOLTIP_OPEN_TITLE"],L["COMMAND_TOOLTIP_OPEN_DESCRIPTION"] end
    if link=="holystorm:help" then return L["COMMAND_TOOLTIP_HELP_TITLE"],L["COMMAND_TOOLTIP_HELP_DESCRIPTION"] end
end
function Commands:Initialize()
    SLASH_HOLYSTORM1,SLASH_HOLYSTORM2,SLASH_HOLYSTORM3="/holystorm","/hs","/holy_storm"
    SlashCmdList.HOLYSTORM=function(input) Commands:Execute(input) end
    if HolyStorm.Events and not self.scanCompletionRegistered then
        HolyStorm.Events:Register("HS_CHARACTER_SCAN_COMPLETED","command-scan-feedback",function(_,block,status,reasons)Commands:OnCharacterScanCompleted(block,status,reasons)end)
        self.scanCompletionRegistered=true
    end
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
    self:RegisterSlashCommand({id="core."..id,path={id},group="Core",description=type(definition.help)=="function"and definition.help()or definition.help,execute=function(arguments)return definition.execute(arguments)end})
    return true
end
function Commands:UnregisterSubcommand(id)if not self.handlers[id]then return false end;self.handlers[id]=nil;return true end
function Commands:RegisterSlashCommand(definition)
    if type(definition)~="table"or type(definition.id)~="string"or type(definition.execute)~="function"then return false,"INVALID_COMMAND"end
    local path=definition.path
    if type(path)=="string"then local parts={};for token in path:gmatch("[^%s]+")do parts[#parts+1]=token end;path=parts end
    if type(path)~="table"or #path==0 then return false,"INVALID_COMMAND_PATH"end
    local tokens={};for _,token in ipairs(path)do if type(token)~="string"or not token:match("^[a-z][a-z0-9%-]*$")then return false,"INVALID_COMMAND_PATH"end;tokens[#tokens+1]=token end
    local key=table.concat(tokens," ")
    for commandId,registered in pairs(self.registry)do
        if commandId~=definition.id and registered.key==key then return false,"COMMAND_PATH_EXISTS"end
    end
    local aliasPaths={}
    for _,alias in ipairs(definition.aliases or{})do
        local aliasPath=type(alias)=="table"and table.concat(alias," ")or tostring(alias)
        aliasPath=HolyStorm.Utils.Trim(aliasPath):lower()
        if aliasPath==""or self.aliases[aliasPath]and self.aliases[aliasPath]~=definition.id then return false,"COMMAND_ALIAS_EXISTS"end
        for commandId,registered in pairs(self.registry)do
            if commandId~=definition.id and registered.key==aliasPath then return false,"COMMAND_ALIAS_EXISTS"end
        end
        aliasPaths[#aliasPaths+1]=aliasPath
    end
    self:UnregisterSlashCommand(definition.id)
    self.registry[definition.id]={id=definition.id,path=tokens,key=key,group=definition.group or"Other",description=definition.description,execute=definition.execute,owner=definition.owner or"Core",syntax=definition.syntax or("/hs "..key),aliases=aliasPaths}
    for _,aliasPath in ipairs(aliasPaths)do self.aliases[aliasPath]=definition.id end
    return true
end
function Commands:UnregisterSlashCommand(id)
    local definition=self.registry[id];if not definition then return false end;self.registry[id]=nil
    for alias,target in pairs(self.aliases)do if target==id then self.aliases[alias]=nil end end
    return true
end
function Commands:GetRegisteredCommands()
    local result={};for _,definition in pairs(self.registry)do local item={id=definition.id,path=HolyStorm.Utils.DeepCopy(definition.path),key=definition.key,group=definition.group,description=definition.description,owner=definition.owner,syntax=definition.syntax,aliases=HolyStorm.Utils.DeepCopy(definition.aliases or{})};result[#result+1]=item end
    table.sort(result,function(a,b)if a.group~=b.group then return a.group<b.group end;if a.key~=b.key then return a.key<b.key end;return a.id<b.id end);return result
end
function Commands:RegisterOption(definition)
    local slash=definition and definition.slash;if type(slash)~="table"or slash.enabled==false then return false,"SLASH_UNAVAILABLE"end
    local path=slash.path;local argsType=definition.type
    local commandId="option."..definition.id
    return self:RegisterSlashCommand({id=commandId,path=path,aliases=slash.aliases,group=definition.group or definition.module,owner=definition.module,syntax=slash.syntax,description=definition.description,execute=function(arguments)
        local setting=HolyStorm.Settings;local valueText=HolyStorm.Utils.Trim(arguments or"")
        if valueText==""then local current=setting:Get(definition.id);local rendered=type(current)=="boolean"and(current and L["COMMAND_VALUE_ON"]or L["COMMAND_VALUE_OFF"])or tostring(current);return Commands:PrintUserMessage(string.format(L["COMMAND_OPTION_VALUE"],definition.name or definition.id,rendered))end
        local value
        if argsType=="toggle"then value=({["on"]=true,["true"]=true,["off"]=false,["false"]=false,["1"]=true,["0"]=false})[valueText:lower()]
        elseif argsType=="range"or argsType=="number"then value=tonumber(valueText)
        elseif argsType=="select"then for key,label in pairs(definition.values or{})do if valueText:lower()==tostring(key):lower()or valueText:lower()==tostring(label):lower()then value=key;break end end
        else return Commands:PrintUserMessage(L["COMMAND_OPTION_READ_ONLY"])end
        if value==nil then return Commands:PrintUserMessage(L["COMMAND_OPTION_INVALID"])end
        local options=HolyStorm.Options
        local ok,reason
        if options and options.SetSetting then ok,reason=options:SetSetting(definition.id,value)
        else ok,reason=setting:Set(definition.id,value)end
        if not ok then return Commands:PrintUserMessage(L["COMMAND_OPTION_INVALID"])end
        local rendered=type(value)=="boolean"and(value and L["COMMAND_VALUE_ON"]or L["COMMAND_VALUE_OFF"])or tostring(value)
        Commands:PrintUserMessage(string.format(L["COMMAND_OPTION_SET"],definition.name or definition.id,rendered));return true
    end})
end
local function openPage(page)
    local ui=HolyStorm.UI;if not ui then return false end
    ui:Open();if ui.ShowPage then return ui:ShowPage(page)end;return false
end
local function openMain()
    if HolyStorm.UI then HolyStorm.UI:Open();return true end
    printMessage(L["COMMAND_UI_UNAVAILABLE"]);return false
end
local function addonInformation()
    local names={}
    if HolyStorm.GetModuleEntries and HolyStorm.GetLoadedModuleById then
        for _,entry in ipairs(HolyStorm:GetModuleEntries())do
            if HolyStorm:GetLoadedModuleById(entry.id)then names[#names+1]=entry.displayName or entry.id end
        end
        table.sort(names)
    else
        names=HolyStorm.GetLoadedAddonNames and HolyStorm:GetLoadedAddonNames()or{}
    end
    local profile=HolyStorm.Database and HolyStorm.Database:GetHandle();profile=profile and profile:GetCurrentProfile()or"-"
    local guild=HolyStorm.Data and HolyStorm.Data.GuildStore and HolyStorm.Data.GuildStore:GetCurrent()
    local channel=HolyStorm.metadata and HolyStorm.metadata.channel
    return{version=HolyStorm.version or"-",channel=channel,modules=names,profile=profile,guild=guild and(guild.name or guild.id)or nil}
end
function Commands:GetInfo()return addonInformation()end
local function registerCoreCommands()
    Commands:RegisterSlashCommand({id="core.open",path={"open"},group="Core",syntax="/hs",description=L["COMMAND_OPEN_DESC"],execute=openMain})
    Commands:RegisterSlashCommand({id="core.help",path={"help"},aliases={{"?"}},group="Core",description=L["COMMAND_HELP_DESC"],execute=function()return openPage("system-help")end})
    Commands:RegisterSlashCommand({id="core.info",path={"info"},group="Core",description=L["COMMAND_INFO_DESC"],execute=function()return openPage("system-info")end})
    Commands:RegisterSlashCommand({id="core.status",path={"status"},group="Core",description=L["COMMAND_STATUS_DESC"],execute=function()return openPage("system-status")end})
    Commands:RegisterSlashCommand({id="core.reload",path={"reload"},group="Core",description=L["COMMAND_RELOAD_DESC"],execute=function()if type(ReloadUI)=="function"then ReloadUI();return true end;return false end})
    Commands:RegisterSlashCommand({id="core.options",path={"options"},aliases={{"o"}},group="Core",description=L["COMMAND_OPTIONS_DESC"],execute=function()local options=HolyStorm:GetModule("Options",true);if options then options:Open();return true end;return false end})
    Commands:RegisterSlashCommand({id="core.addons",path={"addons"},group="Core",description=L["COMMAND_ADDONS_DESC"],execute=function()local addons=HolyStorm:GetLoadedAddonNames();Commands:PrintUserMessage(string.format(L["COMMAND_LOADED_ADDONS"],#addons,table.concat(addons,", ")));return true end})
end
function Commands:OnCharacterScanCompleted(block,status,reasons)
    local key=scanCompleted[block]
    if key and status=="COMPLETED"and type(reasons)=="table"and reasons.MANUAL_COMMAND then Commands:PrintUserMessage(L[key]);return true end
    return false
end
function Commands:Execute(input)
    local value=HolyStorm.Utils.Trim(input or "")
    if value=="" then local definition=self.registry["core.open"];if definition then local ok,result=HolyStorm.Utils.SafeCall("command:core.open",definition.execute,"");return ok,result end;return openMain() end
    local id=self.aliases[value:lower()]
    local tokens={};for token in value:lower():gmatch("[^%s]+")do tokens[#tokens+1]=token end
    if not id then
        for length=#tokens,1,-1 do local key=table.concat(tokens," ",1,length);local candidate=self.aliases[key]
            if not candidate then for commandId,definition in pairs(self.registry)do if definition.key==key then candidate=commandId;break end end end
            if candidate then id=candidate;local definition=self.registry[id];local consumed=length;local args=table.concat(tokens," ",consumed+1);local ok,result=HolyStorm.Utils.SafeCall("command:"..id,definition.execute,args);if not ok and HolyStorm.Logger then HolyStorm.Logger:ERROR("Commands","Command %s failed: %s",id,tostring(result))end;return ok,result
            end
        end
    else local definition=self.registry[id];if definition then local ok,result=HolyStorm.Utils.SafeCall("command:"..id,definition.execute,"");return ok,result end end
    local idToken,args=value:match("^([^%s]+)%s*(.*)$");local handler=idToken and self.handlers[idToken]
    if handler then local ok,err=HolyStorm.Utils.SafeCall("command:"..idToken,handler.execute,args);if not ok and HolyStorm.Logger then HolyStorm.Logger:ERROR("Commands","Subcommand %s failed: %s",idToken,tostring(err))end;return ok,err end
    printMessage(string.format(L["CORE_STATUS"],L[HolyStorm.Database:Get("enabled","profile")and"STATUS_ENABLED"or"STATUS_DISABLED"]));return false
end
function Commands:AnnounceLoaded()printMessage(string.format(L["CORE_LOADED"],HolyStorm.metadata.displayName,HolyStorm.version));printMessage(string.format(L["CORE_LOADED_HELP"],commandLink("/hs","open"),commandLink("/hs ?","help")))end
registerScanCommand()
registerCoreCommands()
HolyStorm.Commands=Commands
