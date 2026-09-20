local addonVersion = "2.0.0"
local HolyStorm = LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local L = LibStub("AceLocale-3.0"):GetLocale("Holy_Storm_Options")

local Options = HolyStorm:RegisterRequiredModule("Options")
HolyStorm:ApplyModuleMetadata(Options, {
    displayName = L["DISPLAY_NAME"],
    internalName = "options",
    version = addonVersion,
    category = "required",
    description = L["DESCRIPTION"],
    permissions = {
        "settings-read",
        "settings-write",
    },
    dependencies = {
        "core",
    },
    enabledByDefault = true,
})

function Options:OnInitialize()
    local function chatGet(path) return HolyStorm.Database:Get("chat."..path,"profile") end
    local function chatSet(path,value) HolyStorm.Database:Set("chat."..path,value,"profile") end
    local channelArgs={};local channelOrder={"GUILD","OFFICER","PARTY","PARTY_LEADER","RAID","RAID_LEADER","INSTANCE_CHAT","INSTANCE_CHAT_LEADER","WHISPER","WHISPER_INFORM","SAY","YELL"};for index,id in ipairs(channelOrder)do local channelId=id;channelArgs[channelId]={type="toggle",name=L["CHAT_CHANNEL_"..channelId],order=index,get=function()return chatGet("channels."..channelId)end,set=function(_,value)chatSet("channels."..channelId,value)end}end
    self.optionsTable = {
        type = "group",
        name = L["OPTIONS_TITLE"],
        args = {
            general = {
                type = "group",
                name = L["GENERAL_SETTINGS"],
                order = 1,
                args = {
                    savePosition = {
                        type = "toggle",
                        name = L["SAVE_WINDOW_POSITION"],
                        order = 1,
                        get = function()
                            return HolyStorm.Database:Get("window.savePosition", "profile")
                        end,
                        set = function(_, value)
                            HolyStorm.Database:Set("window.savePosition", value, "profile")
                            local uiModule = HolyStorm:GetModule("UI", true)

                            if uiModule then
                                if value then
                                    uiModule:SaveWindowPosition()
                                else
                                    HolyStorm.Database:Set("window.position", nil, "profile")
                                end
                            end
                        end,
                    },
                    saveSize = {
                        type = "toggle",
                        name = L["SAVE_WINDOW_SIZE"],
                        order = 2,
                        get = function()
                            return HolyStorm.Database:Get("window.saveSize", "profile")
                        end,
                        set = function(_, value)
                            HolyStorm.Database:Set("window.saveSize", value, "profile")
                            local uiModule = HolyStorm:GetModule("UI", true)

                            if uiModule then
                                if value then
                                    uiModule:SaveWindowSize()
                                else
                                    HolyStorm.Database:Set("window.size", nil, "profile")
                                end
                            end
                        end,
                    },
                    resetPosition = {
                        type = "execute",
                        name = L["RESET_WINDOW_POSITION"],
                        order = 3,
                        func = function()
                            local uiModule = HolyStorm:GetModule("UI", true)
                            if uiModule then
                                uiModule:ResetWindowPosition()
                            end
                        end,
                    },
                    resetSize = {
                        type = "execute",
                        name = L["RESET_WINDOW_SIZE"],
                        order = 4,
                        func = function()
                            local uiModule = HolyStorm:GetModule("UI", true)
                            if uiModule then
                                uiModule:ResetWindowSize()
                            end
                        end,
                    },
                },
            },
            profiles = LibStub("AceDBOptions-3.0"):GetOptionsTable(HolyStorm.Database:GetHandle()),
            chat = {
                type="group",name=L["CHAT_SETTINGS"],order=2,args={
                    enabled={type="toggle",name=L["CHAT_ENABLED"],order=1,get=function()return chatGet("enabled")end,set=function(_,v)chatSet("enabled",v)end},
                    enrichment={type="toggle",name=L["CHAT_PLAYER_ENRICHMENT"],order=2,get=function()return chatGet("playerEnrichment")end,set=function(_,v)chatSet("playerEnrichment",v)end},
                    classColors={type="toggle",name=L["CHAT_CLASS_COLORS"],order=3,get=function()return chatGet("classColors")end,set=function(_,v)chatSet("classColors",v)end},
                    tooltips={type="toggle",name=L["CHAT_PLAYER_TOOLTIPS"],order=4,get=function()return chatGet("playerTooltips")end,set=function(_,v)chatSet("playerTooltips",v)end},
                    showMain={type="toggle",name=L["CHAT_SHOW_MAIN"],order=5,get=function()return chatGet("showMain")end,set=function(_,v)chatSet("showMain",v)end},
                    showRealName={type="toggle",name=L["CHAT_SHOW_REAL_NAME"],desc=L["CHAT_REAL_NAME_PRIVACY"],order=6,get=function()return chatGet("showRealName")end,set=function(_,v)chatSet("showRealName",v)end},
                    links={type="toggle",name=L["CHAT_LINKS"],order=7,get=function()return chatGet("links")end,set=function(_,v)chatSet("links",v)end},
                    urls={type="toggle",name=L["CHAT_URLS"],order=8,get=function()return chatGet("urls")end,set=function(_,v)chatSet("urls",v)end},
                    mentions={type="group",inline=true,name=L["CHAT_MENTIONS"],order=20,args={
                        enabled={type="toggle",name=L["CHAT_MENTION_ENABLED"],order=1,get=function()return chatGet("mentions.enabled")end,set=function(_,v)chatSet("mentions.enabled",v)end},
                        character={type="toggle",name=L["CHAT_MENTION_CHARACTER"],order=2,get=function()return chatGet("mentions.characterName")end,set=function(_,v)chatSet("mentions.characterName",v)end},
                        realName={type="toggle",name=L["CHAT_MENTION_REAL_NAME"],order=3,get=function()return chatGet("mentions.realName")end,set=function(_,v)chatSet("mentions.realName",v)end},
                        own={type="toggle",name=L["CHAT_MENTION_OWN"],order=4,get=function()return chatGet("mentions.ownMessages")end,set=function(_,v)chatSet("mentions.ownMessages",v)end},
                        sound={type="select",name=L["CHAT_MENTION_SOUND"],order=5,values={TELL_MESSAGE=L["CHAT_SOUND_TELL"],READY_CHECK=L["CHAT_SOUND_READY_CHECK"],RAID_WARNING=L["CHAT_SOUND_RAID_WARNING"]},get=function()return chatGet("mentions.sound")end,set=function(_,v)chatSet("mentions.sound",v)end},
                        test={type="execute",name=L["CHAT_SOUND_TEST"],order=6,func=function()local value=chatGet("mentions.sound");local sound=tonumber(value)or(SOUNDKIT and SOUNDKIT[tostring(value)])or(SOUNDKIT and SOUNDKIT.TELL_MESSAGE)or 3081;if PlaySound then PlaySound(sound,"Master")end end},
                    }},
                    channels={type="group",inline=true,name=L["CHAT_CHANNELS"],order=30,args=channelArgs},
                    diagnostics={type="group",inline=true,name=L["CHAT_DIAGNOSTICS"],order=40,args={
                        status={type="description",order=1,name=function()local d=HolyStorm.Chat:GetDiagnostics();return string.format(L["CHAT_DIAGNOSTICS_FORMAT"],tostring(d.enabled),d.indexSize,#d.linkTypes,#d.tokens,table.concat(d.activeChannels,", "),d.stats.processed,d.stats.errors)end},
                        parser={type="input",name=L["CHAT_PARSER_TEST"],order=2,width="full",set=function(_,value)local rendered=HolyStorm.Chat:ParseForDiagnostics(value);Options.chatParserResult=rendered end,get=function()return""end},
                        result={type="description",order=3,name=function()return Options.chatParserResult or L["CHAT_PARSER_EMPTY"]end},
                    }},
                },
            },
        },
    }

    LibStub("AceConfigRegistry-3.0"):RegisterOptionsTable("HolyStormOptions", self.optionsTable)
end

function Options:Open()
    local uiModule = HolyStorm:GetModule("UI", true)

    if uiModule and uiModule.ShowOptions then
        uiModule:ShowOptions("HolyStormOptions")
    end
end

function Options:RegisterOptionsTab(id, options)
    self.optionsTable.args[id] = options
    LibStub("AceConfigRegistry-3.0"):NotifyChange("HolyStormOptions")
end
