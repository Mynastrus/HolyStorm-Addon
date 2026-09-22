local addonVersion = "1.1.0"
local L = LibStub("AceLocale-3.0"):NewLocale("Holy_Storm_Delves", "deDE")

if not L then
    return
end
L["UNKNOWN"]="Unbekannt";L["PRESENT"]="Vorhanden";L["NO_DELVES"]="Tiefendaten sind noch nicht verfügbar.";L["PERMISSION_DENIED"]="Du besitzt keine Berechtigung für diese Inhalte.";L["MODULE_DISABLED"]="Dieses Modul ist deaktiviert.";L["SEASON"]="Saison %s"
L["GREAT_VAULT"]="Große Schatzkammer";L["BOUNTIFUL"]="Opulent / ermächtigt";L["KEY_FRAGMENTS"]="Schlüsselfragmente";L["COMPLETED_KEYS"]="Abgeschlossene Schlüssel";L["TREASURE_MAP"]="Schatzkarte";L["MAP_USED"]="Karte diese Woche benutzt";L["FLUTE"]="Flöte";L["MINI_ROGUE"]="Mini-Räuber";L["COMPANION"]="Begleiter";L["ACTIVITY"]="Aktivität %s";L["PROGRESS_FORMAT"]="%s / %s (Stufe %s)"
L["GROUP_OVERVIEW"]="Wöchentlich";L["GROUP_RESOURCES"]="Ressourcen";L["GROUP_COMPANION"]="Begleiter";L["GROUP_ACTIVITIES"]="Schatzkammer-Aktivitäten";L["COLUMN_GROUP"]="Bereich";L["COLUMN_METRIC"]="Fortschritt";L["COLUMN_VALUE"]="Wert";L["COLUMN_DETAILS"]="Details";L["ACTIVITY_DETAILS"]="Schwelle %s  •  Stufe %s"
L["YES"]="Ja";L["NO"]="Nein"

L["RULE_FIELD_STATUS"] = "Wöchentlicher Tiefenfortschritt"
L["RULE_FIELD_STATUS_DESC"] = "Der im Tiefen-Snapshot gespeicherte wöchentliche Fortschrittswert."

L["DISPLAY_NAME"] = "Tiefen"
L["DESCRIPTION"] = "Stellt tiefenbezogene Funktionen bereit."
L["ACTIVITY_FORMAT"] = "%d / %d (Stufe %d)"
L["NO_DATA"] = "Kein Tiefenfortschritt verfügbar."
