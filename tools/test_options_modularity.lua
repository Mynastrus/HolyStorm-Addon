local script=arg[0]:gsub("\\","/")
local workspace=script:match("^(.*)/tools/[^/]+$")or"."
local optionsPath=workspace.."/LIVE/Holy_Storm_UI/UI/Pages/Options.lua"
local chatOptionsPath=workspace.."/LIVE/Holy_Storm_Chat/UI/ChatOptions.lua"

local function createEnvironment()
 local modules,extensions,notified={},{},0
 local locale=setmetatable({CHAT_DIAGNOSTICS_FORMAT="%s|%d|%d|%d|%s|%d|%d",CHAT_PARSER_EMPTY="empty"},{__index=function(_,key)return key end})
 local registry={}
 function registry:RegisterOptionsTable(id,options)self[id]=options end
 function registry:NotifyChange()notified=notified+1 end
 local database={values={}}
 function database:Get(path)return self.values[path]end
 function database:Set(path,value)self.values[path]=value end
 function database:GetHandle()return{}end
 local HolyStorm={Database=database,uiReady=false}
 function HolyStorm:GetAddon()return self end
 function HolyStorm:RegisterRequiredModule(name)local module={name=name};modules[name]=module;return module end
 function HolyStorm:ApplyModuleMetadata()end
 function HolyStorm:GetModule(name)return modules[name]end
 function HolyStorm:RegisterUIExtension(_,definition)extensions[definition.id]=definition;if self.uiReady then definition.initialize(definition)end;return true end
 function HolyStorm:FlushExtensions()for _,definition in pairs(extensions)do definition.initialize(definition)end end
 _G.LibStub=function(name)
  if name=="AceAddon-3.0"then return{GetAddon=function()return HolyStorm end}
  elseif name=="AceLocale-3.0"then return{GetLocale=function()return locale end}
  elseif name=="AceDBOptions-3.0"then return{GetOptionsTable=function()return{type="group",name="Profiles",args={}}end}
  elseif name=="AceConfigRegistry-3.0"then return registry end
  error("unexpected library "..tostring(name))
 end
 return HolyStorm,modules,extensions,function()return notified end
end

-- Core + UI without Chat owns no chat service or chat option group.
do
 local HolyStorm,modules=createEnvironment();assert(loadfile(optionsPath))();modules.Options:OnInitialize()
 assert(HolyStorm.Chat==nil,"Core + UI test must not provide a Chat service")
 assert(modules.Options.optionsTable.args.chat==nil,"generic UI must not embed Characters chat options")
end

-- UI first: Chat registers its options immediately through the extension.
do
 local HolyStorm,modules,_,notifications=createEnvironment();assert(loadfile(optionsPath))();modules.Options:OnInitialize();HolyStorm.uiReady=true
 HolyStorm.Chat={GetDiagnostics=function()return{enabled=true,indexSize=1,linkTypes={},tokens={},activeChannels={"GUILD"},stats={processed=2,errors=0}}end,ParseForDiagnostics=function(_,value)return"rendered:"..value end}
 assert(loadfile(chatOptionsPath))();assert(HolyStorm.ChatOptions:RegisterExtension())
 local chat=modules.Options.optionsTable.args.chat;assert(chat and chat.args.diagnostics,"Chat loaded after UI must register chat options")
 assert(chat.args.diagnostics.args.status.name():find("GUILD",1,true),"chat diagnostics remain functional")
 assert(notifications()==1,"live option registration must notify AceConfig once")
end

-- Chat first: registration survives until the Options module initializes.
do
 local HolyStorm,modules=createEnvironment();HolyStorm.Chat={GetDiagnostics=function()return{enabled=true,indexSize=0,linkTypes={},tokens={},activeChannels={},stats={processed=0,errors=0}}end,ParseForDiagnostics=function(_,value)return value end}
 assert(loadfile(chatOptionsPath))();assert(HolyStorm.ChatOptions:RegisterExtension());assert(loadfile(optionsPath))()
 HolyStorm.uiReady=true;HolyStorm:FlushExtensions()
 assert(modules.Options.optionsTable==nil and modules.Options.pendingTabs.chat,"pre-UI chat registration must remain pending")
 modules.Options:OnInitialize();assert(modules.Options.optionsTable.args.chat,"Options initialization must consume pending Chat options")
end

print("Options chat modularity and both addon load orders passed")
