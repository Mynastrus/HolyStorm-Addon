local addonVersion = "2.0.0"
local L = LibStub("AceLocale-3.0"):NewLocale("Holy_Storm_Dungeons", "deDE")

if not L then
    return
end

L["RULE_FIELD_RATING"] = "Mythisch+-Wertung"
L["RULE_FIELD_RATING_DESC"] = "Die im Mythisch+-Snapshot gespeicherte Gesamtwertung."

L["DISPLAY_NAME"] = "Mythisch+"
L["UNKNOWN"]="Unbekannt";L["NO_MYTHICPLUS"]="Keine Mythisch+-Daten für die aktuelle Saison.";L["PERMISSION_DENIED"]="Du besitzt keine Berechtigung für diese Inhalte.";L["MODULE_DISABLED"]="Dieses Modul ist deaktiviert."
L["COLUMN_DUNGEON"]="Dungeon";L["DUNGEON_SCORE"]="Dungeonwertung";L["BEST_RUN"]="Bester Lauf";L["MYTHIC_IN_TIME"]="In Zeit";L["MYTHIC_OVERTIME"]="Über Zeit";L["DUNGEONS_TOTAL"]="Dungeons abgeschlossen";L["BEST_RATING"]="Beste Dungeonwertung";L["BEST_KEY"]="Bester Key";L["OVERALL_RATING"]="Gesamtwertung";L["SEASON"]="Saison %s";L["TELEPORT_UNAVAILABLE"]="Dungeon-Teleport noch nicht verfügbar.";L["OPEN_JOURNAL"]="Klicken, um den Eintrag im Abenteuerführer zu öffnen."
L["TYRANNICAL"]="Tyrannisch";L["FORTIFIED"]="Verstärkt";L["SEASON_SUMMARY"]="Saison %s  •  Gesamtwertung: %s";L["TELEPORT_READY"]="Klicken, um zum Dungeon zu teleportieren.";L["TELEPORT_COOLDOWN"]="Nächster Teleport verfügbar in: %s"
L["DESCRIPTION"] = "Erfasst Schlüsselsteine, Affixe und wöchentliche Mythisch+-Läufe aus Blizzard-Daten."
L["CURRENT_KEY"] = "Aktueller Schlüsselstein"
L["WEEKLY_RUNS"] = "Wöchentliche Läufe"
L["NO_MYTHIC_DATA"] = "Keine Mythisch+-Daten verfügbar."
L["KEY_FORMAT"] = "%s: %s +%d"
L["RUN_FORMAT"] = "%s: %d"
