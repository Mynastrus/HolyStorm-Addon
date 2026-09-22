local addonVersion = "1.1.0"
local L = LibStub("AceLocale-3.0"):NewLocale("Holy_Storm_Equipment", "deDE")

if not L then
    return
end

L["RULE_FIELD_ITEM_LEVEL"] = "Gegenstandsstufe"
L["UNKNOWN"]="Unbekannt";L["ITEM_LEVEL"]="Gegenstandsstufe";L["PERMISSION_DENIED"]="Du besitzt keine Berechtigung für diese Inhalte.";L["MODULE_DISABLED"]="Dieses Modul ist deaktiviert."
L["COLUMN_SLOT"]="Platz";L["COLUMN_ITEM"]="Ausgerüsteter Gegenstand";L["COLUMN_TIER"]="Set";L["COLUMN_ENCHANT"]="Verzauberung";L["COLUMN_GEMS"]="Sockel / Edelsteine";L["COLUMN_ILVL"]="Gegenstandsstufe";L["EMPTY_SOCKET"]="Leerer Sockel";L["GEM_ID"]="Edelstein %s"
L["TIER_ITEM"]="Gegenstand eines Klassensets";L["ENCHANTED"]="Verzaubert";L["NOT_ENCHANTED"]="Nicht verzaubert"
L["SLOT_HEAD"]="Kopf";L["SLOT_NECK"]="Hals";L["SLOT_SHOULDER"]="Schulter";L["SLOT_BACK"]="Rücken";L["SLOT_CHEST"]="Brust";L["SLOT_WRIST"]="Handgelenke";L["SLOT_HANDS"]="Hände";L["SLOT_WAIST"]="Taille";L["SLOT_LEGS"]="Beine";L["SLOT_FEET"]="Füße";L["SLOT_FINGER1"]="Ring 1";L["SLOT_FINGER2"]="Ring 2";L["SLOT_TRINKET1"]="Schmuckstück 1";L["SLOT_TRINKET2"]="Schmuckstück 2";L["SLOT_MAINHAND"]="Haupthand";L["SLOT_OFFHAND"]="Nebenhand"
L["RULE_FIELD_ITEM_LEVEL_DESC"] = "Die im Ausrüstungs-Snapshot gespeicherte durchschnittliche Gegenstandsstufe."

L["HEADING"] = "Aktuelle Ausrüstung"
L["WINDOW_TITLE"] = "Holy Storm     |cffBFBFBFAusrüstung|r"
L["NAVIGATION_TITLE"] = "Ausrüstung"
L["EMPTY_SLOT"] = "Leer"
L["TASK_SCAN"] = "Ausrüstung erfassen"
L["TASK_VALIDATE"] = "Ausrüstung prüfen"
L["TASK_COMPARE"] = "Ausrüstung vergleichen"
L["TASK_STORE"] = "Ausrüstung speichern"
L["TASK_SYNC"] = "Ausrüstung synchronisieren"
L["WORKFLOW_EQUIPMENT_UPDATE"] = "Ausrüstungsaktualisierung"
L["WORKFLOW_STATUS"] = "Status: %s"
L["STATUS_QUEUED"] = "Eingereiht"
L["STATUS_WAITING"] = "Wartet"
L["STATUS_READY"] = "Bereit"
L["STATUS_RUNNING"] = "Läuft"
L["STATUS_WAITING_ASYNC"] = "Wartet auf Daten"
L["STATUS_PAUSED"] = "Pausiert"
L["STATUS_COMPLETED"] = "Abgeschlossen"
L["STATUS_FAILED"] = "Fehlgeschlagen"
L["STATUS_CANCELLED"] = "Abgebrochen"
L["NO_EQUIPMENT"] = "Ausrüstungsinformationen sind noch nicht verfügbar."

L["DISPLAY_NAME"] = "Ausrüstung"
L["DESCRIPTION"] = "Stellt ausrüstungsbezogene Funktionen bereit."
