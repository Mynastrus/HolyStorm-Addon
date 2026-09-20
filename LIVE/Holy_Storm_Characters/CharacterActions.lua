local addonVersion="1.0.0"
local HolyStorm=LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local L=LibStub("AceLocale-3.0"):GetLocale("Holy_Storm_Twinks")
local Actions={version=addonVersion}
local function enabled(item,value)if item and item.SetEnabled then item:SetEnabled(not not value)end;return item end

function Actions:Resolve(characterUUID)
 local context=HolyStorm.CharacterUI and HolyStorm.CharacterUI:ResolveContext(characterUUID);if not context then return nil end;local member=context.member;local account=context.accountUUID;local main=HolyStorm.TwinkCore and HolyStorm.TwinkCore:GetRosterIdentity(characterUUID,context.guild);return{characterUUID=characterUUID,name=context.fullName or context.name or characterUUID,online=member and member.online==true,context=context,main=main,accountUUID=account}
end
function Actions:Open(characterUUID)return HolyStorm:CallCapability("character.open",characterUUID,"summary")end
function Actions:OpenMain(characterUUID)local data=self:Resolve(characterUUID);local target=data and data.main and(data.main.accountMain or data.main.guildMain);return target and self:Open(target)or false end
function Actions:Invite(characterUUID)local data=self:Resolve(characterUUID);if not data or not data.online then return false end;return HolyStorm.Actions:Execute("character.invite",data.name)end
function Actions:Whisper(characterUUID)local data=self:Resolve(characterUUID);if not data or not data.online then return false end;if ChatFrame_SendTell then ChatFrame_SendTell(data.name);return true end;return false end
function Actions:CopyName(characterUUID)
 local data=self:Resolve(characterUUID);if not data then return false end;if ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow()and ChatEdit_InsertLink then ChatEdit_InsertLink(data.name);return true end;if not StaticPopupDialogs or not StaticPopup_Show then return false end;StaticPopupDialogs.HOLYSTORM_COPY_NAME={text=L["CHARACTER_COPY_HELP"],button1=OKAY,hasEditBox=true,editBoxWidth=280,OnShow=function(dialog,value)local box=dialog.EditBox or dialog.editBox;if box then box:SetText(value or"");box:HighlightText();box:SetFocus()end end,EditBoxOnEscapePressed=function(box)box:GetParent():Hide()end,timeout=0,whileDead=true,hideOnEscape=true};StaticPopup_Show("HOLYSTORM_COPY_NAME",nil,nil,data.name);return true
end
function Actions:CreateContextMenu(owner,characterUUID,extraActions)
 local data=self:Resolve(characterUUID);if not data then return false end;if not MenuUtil or not MenuUtil.CreateContextMenu then return self:Open(characterUUID)end;MenuUtil.CreateContextMenu(owner,function(_,root)
  root:CreateTitle(data.name);enabled(root:CreateButton(L["CHARACTER_ACTION_INVITE"],function()Actions:Invite(characterUUID)end),data.online);enabled(root:CreateButton(L["CHARACTER_ACTION_WHISPER"],function()Actions:Whisper(characterUUID)end),data.online);root:CreateButton(L["CHARACTER_ACTION_COPY_NAME"],function()Actions:CopyName(characterUUID)end);root:CreateButton(L["CHARACTER_ACTION_OPEN"],function()Actions:Open(characterUUID)end);enabled(root:CreateButton(L["CHARACTER_ACTION_OPEN_MAIN"],function()Actions:OpenMain(characterUUID)end),data.main and(data.main.accountMain or data.main.guildMain));for _,action in ipairs(extraActions or{})do enabled(root:CreateButton(action.text,function()action.callback(characterUUID,data)end),action.enabled~=false)end
 end);return true
end
function Actions:Initialize()
 HolyStorm.Actions:Register("character.invite","CharacterActions",function(name)if C_PartyInfo and C_PartyInfo.InviteUnit then C_PartyInfo.InviteUnit(name)elseif InviteUnit then InviteUnit(name)end end,{combatSafe=false,priority=20})
end
HolyStorm.CharacterActions=Actions
