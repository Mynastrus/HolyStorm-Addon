# Holy Storm – Addon- und Modulvertrag

Holy Storm wird als Addon-Familie ausgeliefert. `Holy_Storm` ist der
eigenständig ladefähige, feature-blinde Kernel. Die fachlichen Addons sind
`Holy_Storm_Chat`, `Holy_Storm_Characters`, `Holy_Storm_Equipment`, `Holy_Storm_Raids`,
`Holy_Storm_MythicPlus`, `Holy_Storm_Delves`, `Holy_Storm_Calendar`,
`Holy_Storm_Professions`, `Holy_Storm_Guild`, `Holy_Storm_GuildLog`,
`Holy_Storm_News`, `Holy_Storm_Achievements`, `Holy_Storm_POI` und
`Holy_Storm_Positions`. Die grafische Oberfläche liegt in `Holy_Storm_UI`.

Alle Addons verwenden `## RequiredDeps: Holy_Storm` (POI und Positions
zusätzlich `Blizzard_MapCanvas`) und die TOC-Kategorie `Holy Storm`.
`HolyStormDB` und `HS_Player_DB` gehören dem Core. `HS_GuildLog_DB` gehört
`Holy_Storm_GuildLog`; der globale Name bleibt zur verlustfreien Nutzung
bestehender Daten unverändert.

## Core-Verantwortung

Der Core besitzt Bootstrap, Logging, Events, Tasks, Workflows, Registry und
Addon-Loader sowie gemeinsam benötigte Persistence-, Permission-, Sync-,
Command-, Action-, Hook-, Karten-/Orts- und Rich-Content-Dienste. Renderer,
Fenster, Administration und Optionsseiten liegen in `Holy_Storm_UI`.
Character- und Guild-Collections werden von ihren Features angefordert, nicht
vom Core-Bootstrap.

## TOC-Discovery und Load-on-Demand

Jedes Addon deklariert `X-HolyStorm-ID`. Optional sind
`X-HolyStorm-Requires` und eine kommaseparierte Liste in
`X-HolyStorm-LoadOnEvent`. Der Core liest diese Werte über
`C_AddOns.GetNumAddOns`, `C_AddOns.GetAddOnInfo` und
`C_AddOns.GetAddOnMetadata`. Er kennt weder Feature-Namen noch die fachliche
Bedeutung eines Events.

Bei einem passenden Event versucht der Loader das Addon genau einmal über
`C_AddOns.LoadAddOn` zu laden und hinterlegt den Load Context
`{ reason = "event", trigger = event }`. Das Feature fordert anschließend die
fachliche Arbeit selbst über TaskManager oder WorkflowManager an.

Aktuell sind folgende Addons Load-on-Demand:

- Equipment: `PLAYER_EQUIPMENT_CHANGED`
- Mythic+: `CHALLENGE_MODE_COMPLETED`
- Raids: `ENCOUNTER_END`
- Professions: `TRADE_SKILL_SHOW`

Die übrigen Features bleiben wegen Login-, Sync- oder dauerhaftem Dienstbedarf
normal geladen. Insbesondere wird `PLAYER_ENTERING_WORLD` nicht als generischer
Loader-Trigger verwendet.

## Feature- und UI-Registrierung

Features registrieren sich mit `HolyStorm:RegisterModule(metadata, factory)`.
Sie besitzen ihre Permissions, Rule-Felder, Datenblock-Schemas, Tasks,
Workflows, Sync-Domänen, Commands und fachlichen Events selbst. Größere Arbeit
läuft über Tasks oder Workflows.

Optionale Präsentation wird mit `RegisterUIExtension` registriert. Die Registry
ist reihenfolgeunabhängig: Ein Feature kann vor der UI registrieren und später
integriert werden; eine bereits geladene UI beobachtet nachträgliche
Registrierungen. Ohne `Holy_Storm_UI` bleiben Core und Features funktionsfähig.

Weitere Erweiterungspunkte sind `RegisterCapability` / `CallCapability`,
`RegisterCharacterTab`, `RegisterCharacterSummarySection`,
`metadata.administration`, `Commands:RegisterSubcommand`,
`RichLinks:RegisterType`, `PlayerData:RegisterBlock` und
`Rules:RegisterField`.

## Anforderungen an neue Feature-Addons

1. Eigenes TOC mit `RequiredDeps: Holy_Storm` und stabiler `X-HolyStorm-ID`.
2. `LoadOnDemand: 1` nur mit einem sinnvollen, spezifischen
   `X-HolyStorm-LoadOnEvent`; keine eigene Trigger-Sprache.
3. Nur öffentliche Store-, Event-, Task-, Workflow-, Registry-, Permission-
   und Sync-APIs verwenden.
4. UI-Integration ausschließlich optional und über `RegisterUIExtension`.
5. SavedVariables nicht direkt aus UI-Code ändern.
6. Featuretexte mindestens in `enUS` und `deDE` pflegen.
7. TOC-, Syntax-, Locale-, Offline- und Ingame-Vertragstests ergänzen.
