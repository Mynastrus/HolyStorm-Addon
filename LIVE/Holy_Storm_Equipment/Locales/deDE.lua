local addonVersion = "1.1.0"
local L = LibStub("AceLocale-3.0"):NewLocale("Holy_Storm_Equipment", "deDE")

if not L then
    return
end

L["RULE_FIELD_ITEM_LEVEL"] = "Gegenstandsstufe der Ausrüstung"
L["UNKNOWN"]="Unbekannt";L["ITEM_LEVEL"]="Stufe der angelegten Ausrüstung";L["PERMISSION_DENIED"]="Du besitzt keine Berechtigung für diese Inhalte.";L["MODULE_DISABLED"]="Dieses Modul ist deaktiviert."
L["COLUMN_SLOT"]="Platz";L["COLUMN_ITEM"]="Ausgerüsteter Gegenstand";L["COLUMN_TIER"]="Set";L["COLUMN_ENCHANT"]="Verzauberung";L["COLUMN_GEMS"]="Sockel / Edelsteine";L["COLUMN_ILVL"]="Gegenstandsstufe";L["EMPTY_SOCKET"]="Leerer Sockel";L["GEM_ID"]="Edelstein %s"
L["TIER_ITEM"]="Gegenstand eines Klassensets";L["ENCHANTED"]="Verzaubert";L["NOT_ENCHANTED"]="Nicht verzaubert"
L["SLOT_HEAD"]="Kopf";L["SLOT_NECK"]="Hals";L["SLOT_SHOULDER"]="Schulter";L["SLOT_BACK"]="Rücken";L["SLOT_CHEST"]="Brust";L["SLOT_WRIST"]="Handgelenke";L["SLOT_HANDS"]="Hände";L["SLOT_WAIST"]="Taille";L["SLOT_LEGS"]="Beine";L["SLOT_FEET"]="Füße";L["SLOT_FINGER1"]="Ring 1";L["SLOT_FINGER2"]="Ring 2";L["SLOT_TRINKET1"]="Schmuckstück 1";L["SLOT_TRINKET2"]="Schmuckstück 2";L["SLOT_MAINHAND"]="Haupthand";L["SLOT_OFFHAND"]="Nebenhand"
L["RULE_FIELD_ITEM_LEVEL_DESC"] = "Blizzards durchschnittliche Gegenstandsstufe der angelegten Ausrüstung."

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
L["OPTIONS_TITLE"]="Ausrüstungsoptionen";L["SCAN_TRIGGERS"]="Scan-Auslöser";L["SCAN_ON_EQUIPMENT_CHANGE"]="Bei Ausrüstungsänderungen immer scannen";L["SCAN_TRIGGER_DESC"]="Fordert den zentralen entprellten Ausrüstungsworkflow an.";L["SCAN_ON_ENCHANT_CHANGE"]="Zusätzlich bei geänderten Waffenverzauberungen scannen";L["SCAN_ON_SOCKET_CHANGE"]="Zusätzlich bei geänderten Sockeln oder Edelsteinen scannen";L["OPTION_SCAN_ENCHANT"]="Ausrüstungsscan bei Verzauberungsänderung";L["OPTION_SCAN_SOCKET"]="Ausrüstungsscan bei Sockel- und Edelsteinänderung";L["SCAN_STATUS_TITLE"]="Status des Ausrüstungsscans";L["SCAN_STATUS_FORMAT"]="Letzter erfolgreicher Scan: %s\nSnapshot-Revision: %s · Schema: %s · Snapshot: %s\nStatus: %s · letzter Fehler: %s · Wiederholungen: %d";L["SCAN_TIME_FORMAT"]="%d.%m.%Y %H:%M:%S";L["SCAN_NEVER"]="Noch nie";L["SCAN_NOW"]="Jetzt scannen";L["COMMAND_SCAN_DESC"]="Den zentralen Ausrüstungsscan-Workflow anfordern.";L["SCAN_STATUS_CURRENT"]="Aktuell";L["SCAN_STATUS_DIRTY"]="Eingereiht";L["SCAN_STATUS_REFRESHING"]="Scan läuft";L["SCAN_STATUS_MISSING"]="Noch kein Scan";L["SCAN_STATUS_QUEUED"]="Eingereiht";L["SCAN_STATUS_RUNNING"]="Läuft";L["SCAN_STATUS_COMPLETED"]="Abgeschlossen";L["SCAN_STATUS_FAILED"]="Fehlgeschlagen"
L["SCOPE_LABEL"] = "Einstellung speichern für"
L["SCOPE_CHARACTER"] = "Diesen Charakter"
L["SCOPE_ACCOUNT"] = "Account / global"
L["SCOPE_GUILD"] = "Diese Gilde"
L["SCOPE_ALL_GUILDS"] = "Alle Gilden"
