local root=(arg[0]:gsub("tools[/\\]test_options_profile_architecture.lua$",""))
local function copy(value,seen)
 if type(value)~="table"then return value end;seen=seen or{};if seen[value]then return seen[value]end
 local out={};seen[value]=out;for key,child in pairs(value)do out[copy(key,seen)]=copy(child,seen)end;return out
end
local function serialize(value)
 if type(value)~="table"then return type(value)..":"..tostring(value)end
 local keys={};for key in pairs(value)do keys[#keys+1]=key end;table.sort(keys,function(a,b)return tostring(a)<tostring(b)end)
 local out={};for _,key in ipairs(keys)do out[#out+1]=serialize(key).."="..serialize(value[key])end;return"{"..table.concat(out,",").."}"
end
local database={global={localSettings={}},profile={enabled=true}}
function database:GetCurrentProfile()return"Default"end
local currentGuild={id="Guild-A",name="Test Guild",roster={}}
local records={}
local accounts={}
local modules={}
local emitted={}
local pages={}
local profileWrites={}
local locale=setmetatable({COUNTRIES={US="United States",DE="Germany"}}, {__index=function(_,key)return key end})
local HolyStorm={Database={},Data={GuildStore={},CharacterStore={},PlayerStore={}},PlayerData={},Utils={},Events={},Serializer={},Logger={},State={},version="test-version",metadata={channel="dev"},moduleEntries={{id="Profiles",displayName="Player Profile"}},loaded={Profiles=true}}
function HolyStorm.Database:GetHandle()return database end
function HolyStorm.Database:Get()return true end
function HolyStorm.Utils.DeepCopy(value)return copy(value)end
function HolyStorm.Utils.Trim(value)return tostring(value or""):match("^%s*(.-)%s*$")end
function HolyStorm.Utils.SafeCall(_,fn,...)local result={pcall(fn,...)};local ok=table.remove(result,1);return ok,table.unpack(result)end
function HolyStorm.Serializer:Serialize(value)return serialize(value)end
function HolyStorm.Events:Emit(...)emitted[#emitted+1]={...}end
function HolyStorm.Logger:Write()end
function HolyStorm.Data.GuildStore:GetCurrent()return currentGuild end
function HolyStorm.Data.GuildStore:Get(id)return id==currentGuild.id and currentGuild or nil end
function HolyStorm.Data.CharacterStore:Get(guid)return records[guid]end
function HolyStorm.Data.CharacterStore:GetAll()return records end
function HolyStorm.Data.PlayerStore:SetLocalMetadata(value)accounts["local-account"].metadata=copy(value);return true end
function HolyStorm.PlayerData:RegisterBlock()return true end
function HolyStorm.PlayerData:WriteOwnedBlock(guid,blockId,data)profileWrites[guid]={blockId=blockId,data=copy(data)};records[guid].profile=copy(data);return true end
HolyStorm.TwinkCore={sources={OWNER="owner-confirmed",ADMIN="administrative"},localAccountUUID="local-account",accounts=accounts}
function HolyStorm.TwinkCore:GetLocalAccountUUID()return self.localAccountUUID end
function HolyStorm.TwinkCore:GetAccount(id)return copy(accounts[id])end
function HolyStorm.TwinkCore:GetAccountUUIDForCharacter(guid)return records[guid]and"local-account"or nil end
function HolyStorm.TwinkCore:IsOwnerConfirmed(guid)return records[guid]~=nil end
function HolyStorm.TwinkCore:GetAccountMain()return accounts["local-account"]and accounts["local-account"].mainCharacterUUID end
function HolyStorm:GetAddon()return self end
function HolyStorm:RegisterRequiredModule(name)local module={name=name};modules[name]=module;return module end
function HolyStorm:ApplyModuleMetadata()end
function HolyStorm:GetModule(name)return modules[name]end
function HolyStorm:GetModuleEntries()return self.moduleEntries end
function HolyStorm:GetLoadedModuleById(id)return self.loaded[id]and modules.Profiles or nil end
function HolyStorm:RegisterUIExtension()return true end
local optionsRegistry={}
local aceDialog={SelectGroup=function()end}
function LibStub(name)
 if name=="AceAddon-3.0"then return{GetAddon=function()return HolyStorm end}end
 if name=="AceLocale-3.0"then return{GetLocale=function()return locale end}end
 if name=="AceDBOptions-3.0"then return{GetOptionsTable=function()return{type="group",args={}}end}end
 if name=="AceConfigRegistry-3.0"then return{RegisterOptionsTable=function(_,id,value)optionsRegistry[id]=value end,NotifyChange=function()end}end
 if name=="AceConfigDialog-3.0"then return aceDialog end
 error("unexpected library "..tostring(name))
end
function UnitGUID()return"Warrior-A"end
function date(format,value)return os.date(format,value)end
local reloaded=0
function ReloadUI()reloaded=reloaded+1 end

assert(loadfile(root.."LIVE/Holy_Storm/Core/Settings/Settings.lua"))()
assert(loadfile(root.."LIVE/Holy_Storm_UI/UI/Pages/Options.lua"))()
modules.Options:OnInitialize()
modules.Profiles={}
local opened={}
HolyStorm.UI={Open=function()opened.main=(opened.main or 0)+1 end,ShowPage=function(_,page)opened.page=page;return true end}
assert(loadfile(root.."LIVE/Holy_Storm/Core/Commands/Commands.lua"))()
local Options,Settings,Commands=HolyStorm.Options,HolyStorm.Settings,HolyStorm.Commands

assert(Options:RegisterSetting({id="test.flag",module="Test",type="toggle",default=true,scope="account",scopes={"account"},nameKey="TEST_FLAG",descriptionKey="TEST_FLAG_DESC",uiOrder=1,name="Test flag",description="Test flag",slash={path={"test","flag"}}}))
local registered=Options:GetRegisteredSettings();assert(#registered==1 and registered[1].id=="test.flag"and registered[1].storage.locality=="local","option contract registry records stable identity and local storage")
local settingDefinition=Settings:GetDefinition("test.flag");assert(settingDefinition.default==true and settingDefinition.module=="Test","setting definitions are shared by UI and command registrations")
local setResult,setReason=Options:SetSetting("test.flag",false);local storedValue,storedReason=Settings:Get("test.flag");assert(setResult and storedValue==false,"central Options setter writes through the shared Settings store ("..tostring(setResult)..","..tostring(setReason)..","..tostring(storedValue)..","..tostring(storedReason)..","..serialize(database.global.localSettings)..")")
assert(Commands:Execute("test flag on")and Settings:Get("test.flag")==true,"slash command updates the same stored option as the UI API")

local scoped={id="test.scoped",module="Test",type="toggle",default=false,scope="account",scopes={"character","account","guild","allGuilds"},nameKey="TEST_SCOPED",descriptionKey="TEST_SCOPED_DESC",uiOrder=2}
assert(Settings:Register(scoped))
assert(Settings:Get("test.scoped")==false,"unset local settings use the module default")
assert(Settings:Set("test.scoped",true,"allGuilds")and Settings:Get("test.scoped")==true,"All Guilds value overrides the default")
assert(Settings:Set("test.scoped",false,"guild","Guild-A")and Settings:Get("test.scoped")==false,"current Guild override takes precedence")
assert(Settings:Set("test.scoped",true,"character","Warrior-A")and Settings:Get("test.scoped")==false,"Guild override remains above character value")
currentGuild=nil;assert(Settings:Get("test.scoped")==true,"without a current guild, All Guilds value is used")
assert(Settings:Set("test.scoped",false,"account")and Settings:Get("test.scoped")==true,"All Guilds value precedes the account fallback")
assert(Settings:SetSelectedScope("test.scoped","character")and Settings:Set("test.scoped",false)and Settings:GetStored("test.scoped","character","Warrior-A")==false,"selected scope controls the write bucket")
assert(not Settings:Set("test.scoped",true,"unknown")and not Settings:SetSelectedScope("test.scoped","unknown"),"invalid scopes are rejected")
currentGuild={id="Guild-A",name="Test Guild",roster={}}
assert(Settings:ImportLegacy("test.scoped",false,"allGuilds") == false,"existing value is never replaced by legacy import")
assert(Settings:Register({id="test.falseLegacy",module="Test",type="toggle",default=true,scopes={"account"}}))
assert(Settings:ImportLegacy("test.falseLegacy",false,"account")and Settings:Get("test.falseLegacy")==false,"an explicit false legacy value migrates without becoming the default")
assert(not Settings:ImportLegacy("test.falseLegacy",true,"account")and Settings:Get("test.falseLegacy")==false,"legacy imports never overwrite an explicit false value")
assert(not Settings:Register({id="test.synced",module="Test",type="toggle",default=true,scopes={"guild"},synchronized=true}),"local Settings API rejects synchronized administrative settings")

assert(Commands:Execute("?")and opened.page=="system-help","/hs ? opens the registered help page")
assert(Commands:Execute("help")and opened.page=="system-help","/hs help aliases the same help page")
local commandKeys={};for _,entry in ipairs(Commands:GetRegisteredCommands())do commandKeys[entry.key]=entry end
assert(commandKeys.help and commandKeys.help.aliases[1]=="?"and commandKeys["test flag"],"help source is the central command registry, including option commands and aliases")
assert(commandKeys.open and commandKeys.addons and commandKeys.scan,"all built-in commands appear in the central command registry")
assert(Commands:Execute("info")and opened.page=="system-info","/hs info opens the info page")
local info=Commands:GetInfo();assert(info.version=="test-version"and info.channel=="dev"and info.profile=="Default"and info.guild=="Test Guild"and info.modules[1]=="Player Profile","info includes available version, build, loaded modules, local profile, and guild")
assert(Commands:Execute("status")and opened.page=="system-status","/hs status opens the status page")
assert(Commands:Execute("reload")and reloaded==1,"/hs reload invokes ReloadUI")
local opensBefore=opened.main or 0;assert(Commands:Execute("")and opened.main==opensBefore+1,"bare /hs opens the main UI through its registry entry")
assert(commandKeys.open and commandKeys.open.syntax=="/hs","the bare main-window entry appears in registry-generated help")

local actualCountries=locale.COUNTRIES
local playerProfile={metadata={displayName="Legacy Name",birthdate="2000-02-29",country="us",location="Berlin"},characters={
 ["Warrior-A"]={characterUUID="Warrior-A",name="Arcturus",realm="Realm A",classFile="WARRIOR",guildId="Guild-A",relationship={source="owner-confirmed"}},
 ["Mage-A"]={characterUUID="Mage-A",name="Mira",realm="Realm A",classFile="MAGE",guildId="Guild-A",relationship={source="owner-confirmed"}},
 ["Remote"]={characterUUID="Remote",name="Not Mine",relationship={source="administrative"}},
}}
accounts["local-account"]=playerProfile
records["Warrior-A"]={guid="Warrior-A",name="Arcturus",classFile="WARRIOR",profile={preferredRole="HEALER",alternateRoles="tank",profileFields={alternateRoles={value="tank",visibility="GUILD"}}}}
records["Mage-A"]={guid="Mage-A",name="Mira",classFile="MAGE",profile={profileFields={preferredSpecs={value={62,70},visibility="GUILD"},realName={value="Hidden Name",visibility="PRIVATE"},country={value="US",visibility="PUBLIC"},raidInterest={value="Progress",visibility="GUILD"}}}}
function HolyStorm.Data.CharacterStore:Get(guid)return records[guid]end
function GetNumSpecializationsForClassID(classId)return classId==1 and 3 or classId==8 and 3 or 0 end
local specsByClass={[1]={{71,"Arms","DAMAGER"},{72,"Fury","DAMAGER"},{73,"Protection","TANK"}},[8]={{62,"Arcane","DAMAGER"},{63,"Fire","DAMAGER"},{64,"Frost","DAMAGER"}}}
function GetSpecializationInfoForClassID(classId,index)local entry=specsByClass[classId]and specsByClass[classId][index];if not entry then return nil end;return entry[1],entry[2],nil,nil,entry[3]end
assert(loadfile(root.."LIVE/Holy_Storm_Characters/Profiles.lua"))()
local Profiles=HolyStorm.Profiles
Profiles.pendingSpecs={}
local migrated=Profiles:MigrateAccountMetadata(playerProfile.metadata)
assert(migrated.profileFields.realName.value=="Legacy Name"and migrated.profileFields.realName.visibility=="GUILD","legacy displayName migrates as a guild-visible voluntary field")
assert(migrated.profileFields.birthDate.value.day==29 and migrated.profileFields.birthDate.value.month==2 and migrated.profileFields.birthDate.value.year==2000,"leap-day birth date migrates as structured day, month, and year")
assert(migrated.profileFields.country.value=="US"and migrated.profileFields.city.value=="Berlin","legacy country and location migrate without losing their values")
assert(Profiles:ParseLegacyBirthdate("2001-02-29")==nil and Profiles:ParseLegacyBirthdate("31.04.2001")==nil and Profiles:ParseLegacyBirthdate("2004-02-29").day==29,"birth dates reject invalid calendar days and accept leap years")
local invalid=migrated;invalid.birthdate="31/02/2000";invalid.profileMigration=nil;invalid.profileFields.birthDate=nil
local unresolved=Profiles:MigrateAccountMetadata(invalid);assert(unresolved.birthdate=="31/02/2000"and unresolved.profileMigration.birthDate=="UNRESOLVED","unparseable legacy birth date is retained and marked unresolved")
assert(Profiles:NormalizeCountryCode("de")=="DE"and Profiles:GetCountryName("US")=="United States","country input normalizes to a stable code and displays a localized label")
local rows=Profiles:GetAccountCharacters();assert(#rows==2 and rows[1].guid=="Warrior-A"and rows[2].guid=="Mage-A","profile character table lists local owner-confirmed characters only")
local chosen=Profiles:GetSelectedSpecs("Mage-A");assert(#chosen==1 and chosen[1]==62,"preferred spec IDs are constrained to the character class")
local roles=Profiles:GetPreferredRoles("MAGE",{62});assert(#roles==1 and roles[1]=="DAMAGER","preferred role is derived from the selected class specialization")
local private=Profiles:GetVisibleCharacterField("Mage-A","realName","Guild-A");assert(private.state=="HIDDEN"and private.value==nil,"private profile values remain stored but hidden from viewers")
local public=Profiles:GetVisibleCharacterField("Mage-A","country","Other-Guild");assert(public.state=="VISIBLE"and public.value=="US","public profile values are visible outside the guild")
local guildValue=Profiles:GetVisibleCharacterField("Mage-A","raidInterest","Guild-A");local hiddenGuild=Profiles:GetVisibleCharacterField("Mage-A","raidInterest","Other-Guild");assert(guildValue.state=="VISIBLE"and hiddenGuild.state=="HIDDEN","guild profile values require guild membership")
local empty=Profiles:GetVisibleCharacterField("Mage-A","mythicInterest","Guild-A");assert(empty.state=="NOT_ENTERED","empty profile fields remain distinct from hidden entered fields")
local sanitized=Profiles:SanitizeCharacterProfile(records["Mage-A"].profile);assert(sanitized.realName==nil and sanitized.country=="US"and sanitized.raidInterest=="Progress","profile sync sanitizer withholds private values and preserves visible values")

local legacyProfile=records["Warrior-A"].profile
Profiles.selected="Warrior-A";Profiles.pendingSpecs={};Profiles.visibilityEdits={preferredRole="GUILD",preferredSpecs="GUILD",alternateRoles="GUILD",raidInterest="GUILD",mythicInterest="GUILD",delveInterest="GUILD",realName="GUILD",birthDate="GUILD",country="GUILD",city="GUILD",playerType="GUILD",playDays="GUILD",playTimes="GUILD"}
Profiles.realNameEdit={GetText=function()return""end};Profiles.birthDayChecks={};Profiles.dayChecks={};Profiles.timeChecks={};Profiles.characterFieldEdits={alternateRoles={GetText=function()return""end},raidInterest={GetText=function()return""end},mythicInterest={GetText=function()return""end},delveInterest={GetText=function()return""end}}
Profiles.cityEdit={GetText=function()return""end};Profiles.birthDayValue=nil;Profiles.birthMonthValue=nil;Profiles.birthYearEdit={GetText=function()return""end};Profiles.playerTypeValue="";Profiles.countryCode=nil
Profiles.ReadBirthdate=function()return nil end;Profiles.RefreshCharacters=function()end
local saved,saveReason=Profiles:Save();assert(saved,saveReason)
assert(profileWrites["Warrior-A"].data.profileFields.preferredRole.value=="HEALER"and records["Warrior-A"].profile.preferredRole=="HEALER","legacy preferredRole is preserved until the user edits preferred specializations")
assert(Profiles.visibilityEdits.realName=="GUILD"and Profiles.visibilityEdits.birthDate=="GUILD","new and migrated profile fields default to GUILD visibility")

print("Options registry, local scope resolution, slash aliases, profile migration, privacy, country codes, character list, specialization validation, role derivation, and legacy preservation passed")
