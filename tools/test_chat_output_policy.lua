local root=(arg[0]:gsub("tools[/\\]test_chat_output_policy.lua$",""))
local function read(path)local file=assert(io.open(root..path,"rb"));local source=file:read("*a");file:close();return source end
local logger=read("LIVE/Holy_Storm/Core/Logging/Logger.lua")
assert(not logger:find("print%s*%(")and not logger:find("DEFAULT_CHAT_FRAME%s*:%s*AddMessage"),"structured logger never mirrors technical entries into chat")
for _,path in ipairs({"LIVE/Holy_Storm/Sync/SyncManager.lua","LIVE/Holy_Storm/Sync/Comms.lua","LIVE/Holy_Storm/Core/Tasks/TaskManager.lua","LIVE/Holy_Storm/Core/Workflows/WorkflowManager.lua","LIVE/Holy_Storm/Persistence/PlayerDataStore.lua"})do local source=read(path);assert(not source:find("print%s*%(")and not source:find("ChatFrame%d*%s*:%s*AddMessage"),"technical core path has no direct chat output: "..path)end
for _,path in ipairs({"LIVE/Holy_Storm_News/News.lua","LIVE/Holy_Storm_GuildLog/GuildLog.lua"})do local source=read(path);assert(not source:find("print%s*%(")and source:find("PrintUserMessage",1,true),"intentional feature chat uses the central user-message API: "..path)end
print("Technical WARN/ERROR logging remains separate from intentional user chat messages")
