local root=(arg[0]:gsub("tools[/\\]test_character_actions.lua$","")).."LIVE/Holy_Storm/"
local opened,invited,whispered,inserted,buttons
local locale=setmetatable({CHARACTER_ACTION_INVITE="Invite",CHARACTER_ACTION_WHISPER="Whisper",CHARACTER_ACTION_COPY_NAME="Copy",CHARACTER_ACTION_OPEN="Open",CHARACTER_ACTION_OPEN_MAIN="Main"},{__index=function(_,key)return key end})
local HolyStorm={CharacterUI={},TwinkCore={},Actions={},capabilities={}}
function LibStub(name)if name=="AceAddon-3.0"then return{GetAddon=function()return HolyStorm end}elseif name=="AceLocale-3.0"then return{GetLocale=function()return locale end}end end
function HolyStorm.CharacterUI:ResolveContext(guid)return{fullName=guid=="Player-A"and"Alpha-Realm"or"Main-Realm",member={online=guid=="Player-A"},guild={}}end
function HolyStorm.TwinkCore:GetRosterIdentity()return{accountMain="Player-Main"}end
function HolyStorm:CallCapability(id,guid)opened={id=id,guid=guid};return true end
function HolyStorm.Actions:Register(id,_,callback)self[id]=callback end
function HolyStorm.Actions:Execute(id,name)invited=name;return true end
function ChatFrame_SendTell(name)whispered=name end
function ChatEdit_GetActiveWindow()return true end
function ChatEdit_InsertLink(name)inserted=name end
MenuUtil={CreateContextMenu=function(_,builder)buttons={};local rootMenu={CreateTitle=function()end,CreateButton=function(_,text,callback)local item={text=text,callback=callback};function item:SetEnabled(value)self.enabled=value end;buttons[#buttons+1]=item;return item end};builder(nil,rootMenu)end}
assert(loadfile(root.."Modules/Characters/CharacterActions.lua"))();local Actions=HolyStorm.CharacterActions;Actions:Initialize()
assert(Actions:Open("Player-A")and opened.guid=="Player-A");assert(Actions:OpenMain("Player-A")and opened.guid=="Player-Main");assert(Actions:Invite("Player-A")and invited=="Alpha-Realm");assert(Actions:Whisper("Player-A")and whispered=="Alpha-Realm");assert(Actions:CopyName("Player-A")and inserted=="Alpha-Realm")
assert(Actions:CreateContextMenu({},"Player-A",{{text="POI",enabled=true,callback=function()end}}));assert(#buttons==6 and buttons[1].enabled and buttons[2].enabled and buttons[5].enabled and buttons[6].enabled,"central context actions and main action are enabled for an online known character")
print("Central character context action tests passed")
