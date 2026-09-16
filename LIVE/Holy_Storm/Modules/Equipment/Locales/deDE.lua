local addonVersion = "1.1.0"
local L = LibStub("AceLocale-3.0"):NewLocale("Holy_Storm_Equipment", "deDE")

if not L then
    return
end

L["RULE_FIELD_ITEM_LEVEL"] = "Gegenstandsstufe"
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
