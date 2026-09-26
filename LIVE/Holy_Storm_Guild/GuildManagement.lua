local addonVersion="1.0.0"
local HolyStorm=LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local L=LibStub("AceLocale-3.0"):GetLocale("Holy_Storm_GuildRoster")
local GM=HolyStorm.GuildManagement

local function permission(id,category,defaults)local key=id:gsub("%-","_"):upper();return{id=id,category=category,defaults=defaults,label=L["PERMISSION_"..key],description=L["PERMISSION_DESC_"..key]}end
local permissions={
 permission("guild-notes-view",L["GUILD_NOTES"],{officers=true,member=true}),permission("guild-notes-view-raid-leadership",L["GUILD_NOTES"],{officers=true}),permission("guild-notes-view-officers",L["GUILD_NOTES"],{officers=true}),permission("guild-notes-view-leadership",L["GUILD_NOTES"],{}),
 permission("guild-notes-create",L["GUILD_NOTES"],{officers=true}),permission("guild-notes-edit-own",L["GUILD_NOTES"],{officers=true}),permission("guild-notes-edit-any",L["GUILD_NOTES"],{officers=true}),permission("guild-notes-delete-own",L["GUILD_NOTES"],{officers=true}),permission("guild-notes-delete-any",L["GUILD_NOTES"],{officers=true}),permission("guild-notes-manage-categories",L["GUILD_NOTES"],{officers=true}),
 permission("guild-absences-view",L["GUILD_ABSENCES"],{officers=true,member=true}),permission("guild-absences-manage-own",L["GUILD_ABSENCES"],{officers=true,member=true}),permission("guild-absences-manage-any",L["GUILD_ABSENCES"],{officers=true}),
}

HolyStorm:RegisterModule({
 id="GuildManagement",name="GuildManagement",displayName=L["GUILD_MANAGEMENT_TITLE"],internalName="guildManagement",version=addonVersion,moduleType="feature",category="feature",description=L["GUILD_MANAGEMENT_DESCRIPTION"],permissions=permissions,dependencies={"core","synchronization"},ui={page="guildManagement",navigation=true},data={stores={"GuildManagementStore"},schemaVersion=1},sync={domains={"guildNotes","guildAbsences"}},enabledByDefault=true,
 ruleFields={
  {id="guild.absence.current",type="boolean",name=L["GUILD_RULE_ABSENCE_CURRENT"],nameKey="GUILD_RULE_ABSENCE_CURRENT",description=L["GUILD_RULE_ABSENCE_CURRENT_DESC"],descriptionKey="GUILD_RULE_ABSENCE_CURRENT_DESC",category=L["GUILD_ABSENCES"],dependencies={"guild-absences"},availability=function()return GM.Absences~=nil end,resolver=function(context)if not GM.Absences:CanView()then return nil,"PERMISSION_DENIED"end;local accountUUID=context.accountUUID or GM:GetAccountUUID(context.characterUUID);if not accountUUID then return nil,"MISSING_IDENTITY"end;local active=GM.Absences:GetForAccount(accountUUID);return active~=nil end},
  {id="guild.absence.start",type="number",allowedOperators={"=","!=","<","<=",">",">=","exists","not_exists"},name=L["GUILD_RULE_ABSENCE_START"],nameKey="GUILD_RULE_ABSENCE_START",description=L["GUILD_RULE_ABSENCE_START_DESC"],descriptionKey="GUILD_RULE_ABSENCE_START_DESC",category=L["GUILD_ABSENCES"],dependencies={"guild-absences"},availability=function()return GM.Absences~=nil end,resolver=function(context)if not GM.Absences:CanView()then return nil,"PERMISSION_DENIED"end;local accountUUID=context.accountUUID or GM:GetAccountUUID(context.characterUUID);if not accountUUID then return nil,"MISSING_IDENTITY"end;local active,upcoming=GM.Absences:GetForAccount(accountUUID);local entry=active or upcoming;if not entry then return nil,"NO_ABSENCE"end;return entry.startAt end},
  {id="guild.absence.end",type="number",allowedOperators={"=","!=","<","<=",">",">=","exists","not_exists"},name=L["GUILD_RULE_ABSENCE_END"],nameKey="GUILD_RULE_ABSENCE_END",description=L["GUILD_RULE_ABSENCE_END_DESC"],descriptionKey="GUILD_RULE_ABSENCE_END_DESC",category=L["GUILD_ABSENCES"],dependencies={"guild-absences"},availability=function()return GM.Absences~=nil end,resolver=function(context)if not GM.Absences:CanView()then return nil,"PERMISSION_DENIED"end;local accountUUID=context.accountUUID or GM:GetAccountUUID(context.characterUUID);if not accountUUID then return nil,"MISSING_IDENTITY"end;local active,upcoming=GM.Absences:GetForAccount(accountUUID);local entry=active or upcoming;if not entry then return nil,"NO_ABSENCE"end;return entry.endAt end},
 },
},function(Module)
 function Module:RegisterCharacterActions()
  if not HolyStorm.CharacterActions or self.actionsRegistered then return false end
  self.actionsRegistered=HolyStorm.CharacterActions:RegisterProvider("guild-management",function(characterUUID,data)
   local accountUUID=data and data.accountUUID or GM:GetAccountUUID(characterUUID);local canUsePrivateNotes=characterUUID~=nil;local canViewAbsences=GM:Can("guild-absences-view",nil,nil)
   return{{text=L["GUILD_ACTION_VIEW_NOTES"],enabled=canUsePrivateNotes,callback=function()GM:Open("notes",characterUUID,"view")end},{text=L["GUILD_ACTION_ADD_NOTE"],enabled=canUsePrivateNotes,callback=function()GM:Open("notes",characterUUID,"create")end},{text=L["GUILD_ACTION_VIEW_ABSENCES"],enabled=canViewAbsences and accountUUID~=nil,callback=function()GM:Open("absences",characterUUID,"view")end}}
  end)==true;return self.actionsRegistered
 end
 function Module:OnInitialize()
  GM.Notes:Initialize();GM.Absences:Initialize();GM:RegisterFeature({id="notes",order=10,title=L["GUILD_NOTES"],icon="Interface\\Icons\\INV_Misc_Note_01",build=function(...)return GM.UI:BuildNotes(...)end,refresh=function()return GM.UI:RefreshNotes()end});GM:RegisterFeature({id="absences",order=20,title=L["GUILD_ABSENCES"],icon="Interface\\Icons\\INV_Misc_PocketWatch_01",build=function(...)return GM.UI:BuildAbsences(...)end,refresh=function()return GM.UI:RefreshAbsences()end})
  HolyStorm:RegisterUIExtension("GuildManagement",{id="guild.management",order=4,initialize=function()GM.UI:Initialize()end});self:RegisterCharacterActions()
 end
 function Module:OnEnable()
  self:RegisterCharacterActions();HolyStorm.Events:Register("HS_MODULE_AVAILABILITY_CHANGED","guild-management-actions",function()Module:RegisterCharacterActions()end)
  if IsInGuild()then HolyStorm.Sync:Discover("guildNotes",nil,{reason="GUILD_MANAGEMENT_ENABLE",priority=96});HolyStorm.Sync:Discover("guildAbsences",nil,{reason="GUILD_MANAGEMENT_ENABLE",priority=96})end
 end
 function Module:OnDisable()HolyStorm.Events:UnregisterOwner("guild-management-actions");if HolyStorm.CharacterActions then HolyStorm.CharacterActions:UnregisterProvider("guild-management")end;self.actionsRegistered=false end
end)
