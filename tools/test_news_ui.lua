local root=(arg[0]:gsub("tools[/\\]test_news_ui.lua$","")).."LIVE/Holy_Storm/"
local News={}
local HolyStorm={}
function HolyStorm:RegisterRequiredModule()return News end
function HolyStorm:ApplyModuleMetadata()end
function LibStub(name)if name=="AceAddon-3.0"then return{GetAddon=function()return HolyStorm end}elseif name=="AceLocale-3.0"then return{GetLocale=function()return setmetatable({},{__index=function(_,key)return key end})end}end end
assert(loadfile(root.."Modules/News/News.lua"))()
local renders=0
News.page={IsShown=function()return true end}
News.RenderList=function()renders=renders+1 end
News.mode="detail";assert(not News:RefreshListIfVisible()and renders==0,"content events do not close the active detail view")
News.mode="editor";assert(not News:RefreshListIfVisible()and renders==0,"content events do not close the active editor")
News.mode="list";assert(News:RefreshListIfVisible()and renders==1,"visible content lists still refresh on content events")
News.page={IsShown=function()return false end};assert(not News:RefreshListIfVisible()and renders==1,"hidden content pages are not rendered")
print("News list/detail event-mode tests passed")
