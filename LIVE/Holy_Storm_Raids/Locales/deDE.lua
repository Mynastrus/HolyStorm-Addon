local addonVersion = "1.1.0"
local L = LibStub("AceLocale-3.0"):NewLocale("Holy_Storm_Raids", "deDE")

if not L then
    return
end
L["PERMISSION_DENIED"]="Du besitzt keine Berechtigung für diese Inhalte.";L["MODULE_DISABLED"]="Dieses Modul ist deaktiviert.";L["NO_RAID"]="Keine Raid-Daten verfügbar.";L["NO_DATA"]="Keine Daten"
L["COLUMN_RAID"]="Raid";L["DIFFICULTY_LFR"]="LFR";L["DIFFICULTY_NORMAL"]="Normal";L["DIFFICULTY_HEROIC"]="Heroisch";L["DIFFICULTY_MYTHIC"]="Mythisch";L["COLUMN_BEST"]="Bestwert";L["WEEKLY_TOOLTIP"]="Wöchentlich %s";L["BOSS_KILLED"]="✓ %s";L["BOSS_OPEN"]="○ %s";L["BEST_TOOLTIP"]="Bester Lebenszeitfortschritt";L["BEST_ROW"]="%s | %s | %d Siege";L["OPEN_JOURNAL"]="Klicken, um den Eintrag im Abenteuerführer zu öffnen."

L["RULE_FIELD_PROGRESS"] = "Raidfortschritt"
L["RULE_FIELD_PROGRESS_DESC"] = "Die Anzahl besiegter Bosse aus dem besten gespeicherten Raidfortschritt."

L["HEADING"] = "Schlachtzugssperren"
L["WINDOW_TITLE"] = "Holy Storm     |cffBFBFBFSchlachtzugssperren|r"
L["NAVIGATION_TITLE"] = "Schlachtzugssperren"
L["NO_LOCKOUTS"] = "Es wurden keine aktiven Schlachtzugssperren gefunden."
L["BOSS_LOCKED"] = "Gesperrt"
L["BOSS_AVAILABLE"] = "Verfügbar"
L["UNKNOWN"] = "Unbekannt"

L["DISPLAY_NAME"] = "Schlachtzüge"
L["DESCRIPTION"] = "Stellt schlachtzugbezogene Funktionen bereit."
