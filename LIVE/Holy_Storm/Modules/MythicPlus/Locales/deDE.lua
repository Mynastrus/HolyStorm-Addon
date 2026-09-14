local addonVersion = "2.0.0"
local L = LibStub("AceLocale-3.0"):NewLocale("Holy_Storm_Dungeons", "deDE")

if not L then
    return
end

L["DISPLAY_NAME"] = "Mythisch+"
L["DESCRIPTION"] = "Erfasst Schlüsselsteine, Affixe und wöchentliche Mythisch+-Läufe aus Blizzard-Daten."
L["CURRENT_KEY"] = "Aktueller Schlüsselstein"
L["WEEKLY_RUNS"] = "Wöchentliche Läufe"
L["NO_MYTHIC_DATA"] = "Keine Mythisch+-Daten verfügbar."
L["KEY_FORMAT"] = "%s: %s +%d"
L["RUN_FORMAT"] = "%s: %d"
