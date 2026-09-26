# Holy Storm – Projektkontext

## Zweck und Laufzeit

Holy Storm ist ein Gildenverwaltungs-Addon für World of Warcraft Retail. Der auslieferbare Addon-Quellcode liegt unter `LIVE/Holy_Storm`; Werkzeuge und Offline-Tests liegen unter `tools`. Die TOC-Datei ist die verbindliche Quelle für die Ladefolge.

## Aktuelle Struktur

- `Core/`: gemeinsame Infrastruktur für Bootstrap, Events, Tasks, Workflows, Registry, Permissions, Logging, Aktionen, Hooks, Content-Helfer und Zustand.
- `Persistence/`: Schema, Migrationen, Datenbankadapter, Stores und SnapshotManager.
- `Sync/`: Addon-Kommunikation und generischer SyncManager.
- `UI/`: Framework, Character-UI, Administration und zentrale Utility-Seiten.
- `Modules/`: fachliche Module wie Characters, Achievements, News, POI, Positions, Equipment, MythicPlus, Raids, Delves, Calendar, Professions, Guild und GuildLog.
- `Locales/`: zentrale Core-Lokalisierung; domänenspezifische Locales liegen bei UI oder Modul.

## Architekturgrundsätze

- Persistente Daten werden über Database/DataManager/Stores geschrieben; Module manipulieren SavedVariables nicht direkt.
- Charakterdaten in `HS_Player_DB` sind owner-kontrollierte, versionierte Datenblöcke. Neue lokale Snapshots ersetzen den letzten gültigen Block nur nach erfolgreicher Validierung.
- Module kommunizieren über Core-APIs, Events, Capabilities, Tasks, Workflows und registrierte Sync-Domains.
- Die zentrale Task-Queue und der WorkflowManager orchestrieren Arbeit ohne parallele Modul-Queues.
- `ModuleRegistry` stellt den einheitlichen Metadatenvertrag und Required-/Optional-Compatibility-APIs bereit.
- Die Administration registriert Seiten über `HolyStorm.Administration`; Fachlogik verbleibt in ihren Core-Komponenten oder Modulen.
- Permission-Änderungen sind gildenbezogene Revisionen. Die höchste Versionsnummer allein entscheidet niemals einen Konflikt.

## Zentrale Datenmodelle

`HolyStormDB` enthält AceDB-Konfiguration, gildenweite Feature-Daten und Permission-State. `HS_Player_DB` ist der kanonische Player-/Account-/Character-Bestand mit Character-Blockmetadaten. `HS_GuildLog_DB` bleibt der bestehende GuildLog-Speicher.

PlayerStore verwaltet Account-/Player-Identität und Character-Zuordnungen. CharacterStore stellt Character-Daten bereit. GuildStore verwaltet den aktuellen Gildenbestand. PlayerDataStore besitzt die registrierten Character-Blöcke `identity`, `equipment`, `mythicPlus`, `raid`, `delves`, `stats`, `profile`, `professions`, `addon` und `demands`.

## Permission-System

Die Fachkomponenten sind `PermissionRegistry`, `PermissionEngine`, `GroupManager`, `RuleEngine` (`HolyStorm.Rules`), `FilterManager`, `PolicyState` und `PermissionSync`. `HolyStorm.Policy`, `HolyStorm.Permissions`, `HolyStorm.PermissionManager` und `HolyStorm:HasPermission` bleiben Compatibility-Oberflächen. Neue Administration-UI greift direkt auf die Fachkomponenten zu.

Die geschützten Systemgruppen heißen `guild-leadership`, `officers` und `guild-member`. Rechte sind additiv. Leadership erhält dynamisch alle registrierten Permissions. `managerGroupIds` vergibt ausschließlich Verwaltungsbefugnis und vererbt keine Rechte.

## Module und UI

Module registrieren Metadaten über `RegisterModule`, `RegisterRequiredModule` oder die Compatibility-API `RegisterOptionalModule`. Character-Datenprovider deklarieren Block, Capability und Reihenfolge im TOC und registrieren sich beim feature-blinden `CharacterScanManager`; dieser erfasst beim Login nur fehlende Blöcke und serialisiert alle Scan-Workflows. Das UI-Framework verwaltet Seiten und Navigation. Die Administration-Registry ergänzt Permission- und Modul-Gating sowie verzögertes Bauen einer Seite. Die eingebauten Gruppen-/Permission-, Rule-, Filter- und Diagnose-Sections verwenden denselben `UILayout`-, `UIComponents`-, TabGroup-, Scroll- und Table-Pfad wie die übrige moderne UI; der `page`-Section-Vertrag bleibt nur für externe Compatibility erhalten.

## Entwicklung und Prüfung

- Offline-Tests: `lua tools/test_*.lua` beziehungsweise der im System installierte Lua-Interpreter.
- Lokalisierung: `tools/Test-Localization.ps1` sowie die Locale-Vertragstests.
- Struktur: alle TOC-Pfade prüfen, doppelte Einträge ausschließen und `git diff --check` ausführen.
- Änderungen an ausgeliefertem Code werden unter `## Noch nicht veröffentlicht` in `CHANGELOG.md` ergänzt.

## Aktuelle Restschulden

Die Guild-Management-Grundlage liegt in `Holy_Storm_Guild`: Ein registrierbarer Parent hostet lazy Notes, Absences und Activity. Private Notes sind accountweit lokal; Shared Notes, accountorientierte Absences und accountorientierte Activity-Shards verwenden getrennte DataManager-Schemas und zentrale Sync-Domains. Activity erfasst ausschließlich factual online/chat/raid/Mythic+-Teilnahme, verdichtet langfristig und enthält weder Chat-Inhalte noch Punkte oder Empfehlungen. Details: `GUILD_MANAGEMENT_ARCHITECTURE.md` und `GUILD_ACTIVITY_ARCHITECTURE.md`.

Calendar besitzt noch keinen verlässlichen Attendance-Provider; Einladungsantworten beweisen keine tatsächliche Teilnahme. Der Activity-Provider-Erweiterungspunkt bleibt deshalb ohne Calendar-Implementierung und das Feld liefert `UNKNOWN`. Points und Recommendations sind nicht implementiert; spätere Empfehlungen dürfen niemals automatisch Gildenrang- oder Entfernungsaktionen ausführen.

- Feature-Permissions gehören den Modulen: Sie werden über die `permissions`-Metadaten und die zentrale `PermissionRegistry` registriert. Systemgruppen-Defaults kommen aus den registrierten Definitionen; unbekannte persistierte IDs bleiben defensiv erhalten.
- Feature-Rule-Felder gehören ebenfalls den Modulen und werden über die zentrale `HolyStorm.Rules:RegisterField`-API registriert. Nicht geladene optionale Module stellen ihre Felder nicht bereit; gespeicherte Regeln bleiben erhalten und werden bei späterer Registrierung wieder auswertbar.
- `RuleEngine.lua` enthält noch Feature-Felder und Provider für Equipment, Mythic+, Raid, Delves sowie Quest-/Achievement-Demands. Die Feldregistry ist erweiterbar, die Eigentümerschaft ist aber noch nicht vollständig in die Module verschoben.
- Einige Feature-Sync-Autorisierungen verwenden weiterhin die `HolyStorm.Policy`-Compatibility-Fassade.
- Der Bootstrap initialisiert mehrere konkrete Services direkt. Weitere Entkopplung ist ein geplantes Ziel und kein bereits abgeschlossener Zustand.

Weitere Details stehen in `ARCHITECTURE.md`, `MODULE_ARCHITECTURE.md`, `PERMISSION_ARCHITECTURE.md` und `SYNC_ARCHITECTURE.md`.
