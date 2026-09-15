# Holy Storm – Architektur

Diese Datei beschreibt den implementierten Stand des WoW-Retail-Addons. Geplante Erweiterungen sind ausdrücklich als „Target / Planned“ markiert.

## Projekt und Verzeichnisgrenzen

Der produktive Addon-Baum liegt in `LIVE/Holy_Storm`. `Core` enthält gemeinsam benötigte Infrastruktur, `Persistence` die dauerhafte Datenhaltung, `Sync` Transport und generische Synchronisation, `UI` das gemeinsame UI und `Modules` fachliche Funktionen. Bibliotheken unter `Libs` werden vor dem Addon geladen. Die Reihenfolge in `Holy_Storm.toc` ist Teil des Laufzeitvertrags.

## Start und Laufzeit

`Core/Bootstrap/Bootstrap.lua` erzeugt die AceAddon-Instanz. `OnInitialize` initialisiert Datenbank, Logger, Events, State, Tasks, Workflows, Stores, Kommunikation, Sync, Permission-System und die aktuell noch direkt angebundenen Kernservices. `OnEnable` bindet WoW-Events und stößt die initiale Character- und Guild-Erfassung über Tasks und Capabilities an.

`EventBus` ist der zentrale Ereignisverteiler. Besitzerbezogene Registrierung erlaubt das gemeinsame Abmelden. `TaskManager` stellt eine globale Queue mit stabilen Task-Type-IDs, Laufzeit-IDs, Prioritäten, Bedingungen, Abhängigkeiten, Merge-Modi und Diagnose bereit. `WorkflowManager` orchestriert mehrstufige Abläufe ausschließlich über registrierte Tasks und deren Events. Retry-Grenzen können pro Task, Workflow-Schritt oder kontrolliertem Workflow-Ergebnis gesetzt werden.

`Logger` ist die zentrale strukturierte Logging-Infrastruktur. Einträge enthalten Level, Modul, Kategorie, Nachricht und begrenzte Diagnosemetadaten. UI, Sync, Task- und Permission-Code erzeugen keine zweite Log-Datenbank.

## Persistence und Datenzugriff

`Persistence/Schema.lua`, `Migrations.lua` und `Database.lua` definieren und initialisieren AceDB-Daten. `DataManager` und `ConfigManager` sind Compatibility-/Komfortzugriffe auf den Database-Adapter. Fachliche persistente Zugriffe erfolgen über Stores:

- `PlayerDataStore`, `PlayerStore`, `CharacterStore`, `GuildStore`
- `ContentStore`, `POIStore`, `AchievementStore`

`HS_Player_DB` ist der kanonische owner-kontrollierte Player-/Character-Bestand. Accounts/Player werden über `PlayerStore` und `characterOwners` mit Character-UUIDs verknüpft. Character-Blöcke besitzen eigene Metadaten: Owner, Version, Aktualisierungszeit, Quelle, Relay-Herkunft und Direct-Flag.

`SnapshotManager` adaptiert Snapshot-Abläufe an TaskManager und WorkflowManager. Scan, Validate und Commit sind getrennte Schritte. Ein ungültiger Scan erreicht den Commit nicht; der letzte gültige persistente Datenblock bleibt bestehen. Registrierte PlayerData-Blöcke sind derzeit `identity`, `equipment`, `mythicPlus`, `raid`, `delves`, `stats`, `profile`, `professions`, `addon` und `demands`.

## Synchronisation und Provenance

`Sync/Comms.lua` kapselt den AddonMessage-Transport. `SyncManager` registriert Domains mit Metadaten-, Export-, Validierungs-, Autorisierungs- und Importfunktionen. Discovery, Offer, Fetch, Payload und passive Heilung laufen über die zentrale Task-Queue.

Normale owner-kontrollierte Objekte werden anhand ihrer Domain-Metadaten verglichen. Owner-Provenance bleibt vom Relais getrennt: `owner` bezeichnet den Datenbesitzer, `receivedFrom` die übertragende Gegenstelle, `direct` eine direkte Owner-Übertragung. Permission-State verwendet dagegen eine Revision Chain und niemals „höchste Version gewinnt“. Details stehen in `SYNC_ARCHITECTURE.md`.

## ModuleRegistry und Capabilities

`ModuleRegistry` normalisiert Metadaten mit `id`, `internalName`, `name`, `displayName`, `description`, `icon`, `version`, `moduleType`, `category`, `dependencies`, `capabilities`, `ui`, `options`, `administration`, `data` und `sync`. `RegisterModule` ist der einheitliche Vertrag; `RegisterRequiredModule` und `RegisterOptionalModule` bleiben kompatibel.

Capabilities sind benannte, von Modulen registrierte Handler. Der Bootstrap verwendet sie derzeit für Equipment-, Raid-, Mythic+-, Delve- und weitere Character-Scans. Der detaillierte Implementierungsstand steht in `MODULE_ARCHITECTURE.md`.

## UI und Administration

`UIManager` verwaltet Seiten, Refresh-Ereignisse und Navigation. `MainWindow` ist der zentrale Host. CharacterUI/CharacterOverview bilden die Character-Oberfläche; Feature-Tabs lesen über zentrale Stores.

`HolyStorm.Administration` ist der Erweiterungspunkt für Admin-Seiten. Eine Section beschreibt ID, Namen/Locale-Key, Beschreibung/Locale-Key, Reihenfolge, erforderliche Permission, optionales Modul/Owner, Seite oder Build-Callback, Render-Callback, Ereignisse und optionale Verfügbarkeit. Nicht verfügbare, deaktivierte oder nicht autorisierte Sections werden nicht in Seite und Navigation aktiviert. Die Administration enthält Gruppen, Berechtigungen, Regeln, Filter, Module und Status/Diagnose; ihre Fachoperationen verwenden direkt die Permission-Komponenten.

## Permissions, Gruppen, Rules und Filter

- `PermissionRegistry`: bekannte Permission-Definitionen und Metadaten.
- `PermissionEngine`: Kontext, Membership-Gründe, effektive Gruppen/Rechte, Matrix und Erklärungen.
- `GroupManager`: System- und benutzerdefinierte Gruppen sowie Mitgliedschaften und Manager-Gruppen.
- `RuleEngine` / `HolyStorm.Rules`: registrierbare Felder, Operatoren, Validierung und PASS/FAIL/UNKNOWN-Auswertung.
- `FilterManager`: lokale und gildenweite Rules/Filter sowie Verknüpfungen.
- `PolicyState`: gildenweiter State, Validierung, Autorisierung und revisionsbasierte Mutationen.
- `PermissionSync`: Revision-Catch-up, vertrauensgebundene Recovery und Sync-Domain.

Die Systemgruppen sind `guild-leadership`, `officers` und `guild-member`. Rechte mehrerer Gruppen werden addiert. Leadership besitzt dynamisch alle registrierten Permissions. Manager-Gruppen dürfen eine Zielgruppe verwalten, erben aber weder Mitgliedschaft noch Rechte dieser Gruppe. Die tatsächliche Blizzard-Gildenleitung ist der Trust Anchor für geschützte Leadership-Mitgliedschaft und Snapshot-Recovery.

Jede gildenweite Mutation erzeugt eine monotone Version mit neuer `revisionID`, korrekter `previousRevisionID`, `changedBy` und `changedAt`. Lücken lösen Catch-up/Recovery aus. Geschwisterrevisionen erzeugen `CONFLICT`; es gibt keinen automatischen Versionssieger. Factory Reset ist eine normale Revision und betrifft nur Gruppen, gildenweite Rules/Filter und Policy-/Modulkonfiguration.

## Lokalisierung

Zentrale Texte liegen unter `Locales`. UI- und Modultexte liegen in ihren Domänen, darunter `UI/Character/Locales`, `UI/Administration/Locales` und `Modules/*/Locales`. Neue sichtbare Texte müssen mindestens `enUS` und `deDE` besitzen. Locale-Namespace und Fallback bleiben bei AceLocale.

## SavedVariables und Compatibility

Die TOC deklariert `HolyStormDB`, `HS_Player_DB` und `HS_GuildLog_DB`. Schema und Migrationen bleiben die einzigen Stellen für strukturelle Datenmigration. Öffentliche Compatibility-Oberflächen wie `HolyStorm.Policy`, `HolyStorm.Permissions`, `HolyStorm.PermissionManager`, `HolyStorm:HasPermission`, DataManager und Required-/Optional-Modulregistrierung bleiben bestehen und delegieren auf die aktuelle Implementierung.

## Optionale und externe Module

Optionale In-Addon-Module werden aus Registry-Metadaten erzeugt und über persönliche sowie gildenweite Aktivierung gesteuert. Der Metadaten-, Capability-, UI-, Administration-, Data- und Sync-Vertrag bereitet externe Holy-Storm-Module vor.

Target / Planned: Feature-Pakete wie Equipment, MythicPlus, Raid, Delves oder POI können später separate WoW-Addons werden. Das ist noch nicht vollständig umgesetzt; TOC, Bootstrap-Aufrufe, zentrale Permission-Definitionen und einzelne Compatibility-Aufrufe koppeln sie derzeit noch an das Hauptaddon.

## Bekannte technische Restschulden

- Feature-Permissions sind noch zentral in `PermissionRegistry.lua` vordefiniert, obwohl die Registry Modulregistrierung unterstützt.
- `RuleEngine.lua` besitzt noch Feature-Felder für Equipment, Mythic+, Raid, Delves und Demand-Provider für Quests/Achievements.
- Einzelne Feature-Sync-Domains autorisieren noch über `HolyStorm.Policy`.
- Der Bootstrap initialisiert einige konkrete Services statt ausschließlich deklarative Lifecycle-Hooks zu nutzen.
- Modulmetadaten sind vorhanden, werden aber nicht in allen Modulen gleich vollständig für UI, Administration, Data und Sync genutzt.
