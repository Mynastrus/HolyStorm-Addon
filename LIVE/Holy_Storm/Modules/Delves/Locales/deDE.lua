local addonVersion = "1.1.0"
local L = LibStub("AceLocale-3.0"):NewLocale("Holy_Storm_Delves", "deDE")

if not L then
    return
end

L["RULE_FIELD_STATUS"] = "Wöchentlicher Tiefenfortschritt"
L["RULE_FIELD_STATUS_DESC"] = "Der im Tiefen-Snapshot gespeicherte wöchentliche Fortschrittswert."

L["DISPLAY_NAME"] = "Tiefen"
L["DESCRIPTION"] = "Stellt tiefenbezogene Funktionen bereit."
L["ACTIVITY_FORMAT"] = "%d / %d (Stufe %d)"
L["NO_DATA"] = "Kein Tiefenfortschritt verfügbar."
