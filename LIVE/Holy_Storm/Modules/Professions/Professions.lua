local addonVersion="1.0.0"
local HolyStorm=LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local L=LibStub("AceLocale-3.0"):GetLocale("Holy_Storm_Professions")
local metadata={displayName=L["DISPLAY_NAME"],internalName="professions",version=addonVersion,category="optional",description=L["DESCRIPTION"],permissions={"professions-read"},dependencies={"core","ui"},enabledByDefault=false}
HolyStorm:RegisterOptionalModule("Professions",metadata,function(Module)
    HolyStorm:ApplyModuleMetadata(Module,metadata)
    function Module:Snapshot()
        if not GetProfessions or not GetProfessionInfo then return false end; local guid=UnitGUID("player"); if not guid then return false end
        local result,professionSlots={}, {GetProfessions()}; for index=1,6 do local professionIndex=professionSlots[index]; if professionIndex then local name,icon,skillLevel,maxSkillLevel,numAbilities,spelloffset,skillLine,skillModifier,specializationIndex,specializationOffset=GetProfessionInfo(professionIndex); result[#result+1]={name=name,icon=icon,skillLevel=skillLevel,maxSkillLevel=maxSkillLevel,numAbilities=numAbilities,skillLine=skillLine,skillModifier=skillModifier,specializationIndex=specializationIndex,specializationOffset=specializationOffset} end end
        return HolyStorm.Data.CharacterStore:SetProfessions(guid,result,{updatedAt=HolyStorm.Utils.Now(),updatedBy=guid})
    end
    function Module:RefreshPage() if not self.page or not self.page:IsShown() then return end; local record=HolyStorm.Data.CharacterStore:Get(UnitGUID("player")); local lines={}; for _,profession in ipairs(record and record.professions or {}) do lines[#lines+1]=string.format(L["SKILL_FORMAT"],profession.name or "-",profession.skillLevel or 0,profession.maxSkillLevel or 0) end; self.text:SetText(#lines>0 and table.concat(lines,"\n") or L["NO_DATA"]) end
    function Module:OnInitialize()
        local driver=HolyStorm:GetModule("UI",true); local page=CreateFrame("Frame",nil,driver.content); local heading=page:CreateFontString(nil,"OVERLAY","GameFontHighlightLarge"); heading:SetPoint("TOPLEFT",18,-18); heading:SetText(metadata.displayName); local text=page:CreateFontString(nil,"OVERLAY","GameFontHighlight"); text:SetPoint("TOPLEFT",heading,"BOTTOMLEFT",0,-18); self.page,self.text=page,text
        HolyStorm.UI:RegisterPage("professions",page,metadata.displayName,function()Module:RefreshPage()end,{"HS_PROFESSIONS_UPDATED"}); HolyStorm.UI:AddNavigation("professions",11,"Interface\\Icons\\Trade_BlackSmithing",metadata.displayName,metadata.description,function()HolyStorm.UI:ShowPage("professions")end); HolyStorm:RegisterCapability("Professions","character.scan.additional",function(module)return module:Snapshot()end)
    end
    function Module:OnEnable() HolyStorm.Events:Register("SKILL_LINES_CHANGED","professions",function()HolyStorm.Tasks:Enqueue("professions.scan",function()Module:Snapshot()end,{priority=7,debounce=1})end) end
    function Module:OnDisable() HolyStorm.Events:UnregisterOwner("professions") end
end)
