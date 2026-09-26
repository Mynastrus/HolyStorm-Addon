# Holy Storm – Architektur

Diese Datei beschreibt den implementierten Stand des WoW-Retail-Addons. Geplante Erweiterungen sind ausdrücklich als „Target / Planned“ markiert.

## Projekt und Verzeichnisgrenzen

Der produktive Addon-Baum liegt in `LIVE/Holy_Storm`. `Core` enthält gemeinsam benötigte Infrastruktur, `Persistence` die dauerhafte Datenhaltung, `Sync` Transport und generische Synchronisation, `UI` das gemeinsame UI und `Modules` fachliche Funktionen. Bibliotheken unter `Libs` werden vor dem Addon geladen. Die Reihenfolge in `Holy_Storm.toc` ist Teil des Laufzeitvertrags.

## Start und Laufzeit

`Core/Bootstrap/Bootstrap.lua` erzeugt die AceAddon-Instanz. `OnInitialize` initialisiert Datenbank, Logger, Events, State, Tasks, Workflows, Stores, Kommunikation, Sync, Permission-System und die aktuell noch direkt angebundenen Kernservices. `OnEnable` bindet WoW-Events; die initiale Character-Erfassung wird nach `PLAYER_LOGIN` deklarativ durch den `CharacterScanManager` geplant.

`EventBus` ist der zentrale Ereignisverteiler. Besitzerbezogene Registrierung erlaubt das gemeinsame Abmelden. `TaskManager` stellt eine globale Queue mit stabilen Task-Type-IDs, Laufzeit-IDs, Prioritäten, Bedingungen, Abhängigkeiten, Merge-Modi und Diagnose bereit. `WorkflowManager` orchestriert mehrstufige Abläufe ausschließlich über registrierte Tasks und deren Events. Retry-Grenzen können pro Task, Workflow-Schritt oder kontrolliertem Workflow-Ergebnis gesetzt werden.

`Logger` ist die zentrale strukturierte Logging-Infrastruktur. Einträge enthalten Level, Modul, Kategorie, Nachricht und begrenzte Diagnosemetadaten. UI, Sync, Task- und Permission-Code erzeugen keine zweite Log-Datenbank. Technische Logeinträge werden nicht in den Spielerchat gespiegelt; absichtliche Benutzerhinweise verwenden die zentrale Command-Ausgabe.

## Persistence und Datenzugriff

`Persistence/Schema.lua`, `Migrations.lua` und `Database.lua` definieren und initialisieren AceDB-Daten. `Database` bleibt während der schrittweisen Migration das Low-Level-Backend für AceDB und die drei vorhandenen SavedVariables. Der in `Database.lua` vorhandene `HolyStorm.DataManager` ist seit Contract-Version 1 die technische Zielgrenze für neue Persistence-Integrationen; es gibt keine zweite DataManager-Datei oder parallele Datenbankinstanz. `ConfigManager` und noch nicht migrierte Stores verwenden weiterhin die bestehende Database-/SavedVariable-Infrastruktur.

Der DataManager-Vertrag besteht aus:

- `RegisterSchema`: stabile ID, Owner, aktuelle ganzzahlige Version, Validator, Storage-Binding sowie optional Default Factory, Metadaten, Event und initiale Migrationen. Registrierung liest oder verändert keine Live-Daten.
- `RegisterMigration` und `RunMigrations`: ausschließlich eindeutige Vorwärtsschritte `n → n+1`; der Runner arbeitet auf einer vollständig entkoppelten Kopie, validiert den Zielstand und ersetzt erst danach den Schema-Root in einem In-Memory-Swap. Fehler lassen den bisherigen Root unverändert.
- `Get`, `GetCopy`, `Exists` und `GetMetadata`: öffentliche Reads liefern defensive Kopien beziehungsweise kopierte Schema-Metadaten. Defaults werden beim Lesen nicht materialisiert.
- `Commit`, `Update` und `Transaction`: Copy-on-write, Mutator auf dem Draft, Schema-/Versionsvalidierung, atomarer Ersatz und optionales schemaeigenes Event erst nach Erfolg. Ergebnisse folgen `{ok, changed, operation, schema, version, errorCode, error, ...}`.
- `SafeCopy`: SavedVariable-kompatible primitive Werte, Arrays, Maps, gemischte und gemeinsam referenzierte azyklische Tabellen; Metatables werden nicht übernommen. Funktionen, Threads, Userdata, Tabellenschlüssel und Zyklen werden mit stabilen Fehlercodes abgelehnt.

Die eingebauten Bindings `database`, `player` und `guildLog` bilden die künftige Backend-Grenze für `HolyStormDB`, `HS_Player_DB` und `HS_GuildLog_DB`. In Phase 1 registriert noch kein produktiver Store ein Schema; dadurch startet Laden beziehungsweise Schema-Registrierung weder Migrationen noch Änderungen an SavedVariables. Bestehende `Database`, `ConfigManager`- und Store-APIs bleiben kompatibel. Die frühere `DataManager:GetArea`-Kompatibilitätsoberfläche liefert nun eine Kopie und erzeugt bei einem Read keine fehlenden Defaults; ihr Legacy-Write-Pendant bleibt bis zur späteren Area-Migration bestehen.

Fachliche Revisionen bleiben außerhalb dieses technischen Vertrags: Character-Owner-Versionen gehören weiterhin `PlayerDataStore`, die Policy Revision Chain weiterhin `PolicyState`. Der DataManager erzeugt oder ersetzt keine dieser Revisionen. Das vollständige Ist-Inventar, die verbleibenden Live-Getter und die Phasenfolge stehen in `PERSISTENCE_ARCHITECTURE_AUDIT.md`.

Fachliche persistente Zugriffe erfolgen derzeit weiterhin über Stores:

- `PlayerDataStore`, `PlayerStore`, `CharacterStore`, `GuildStore`
- `ContentStore`, `POIStore`, `AchievementStore`

`HS_Player_DB` ist der kanonische owner-kontrollierte Player-/Character-Bestand. Accounts/Player werden über `PlayerStore` und `characterOwners` mit Character-UUIDs verknüpft. Character-Blöcke besitzen eigene Metadaten: Owner, Version, Aktualisierungszeit, Quelle, Relay-Herkunft und Direct-Flag.

`SnapshotManager` adaptiert Snapshot-Abläufe an TaskManager und WorkflowManager. Scan, Validate und Commit sind getrennte Schritte. Ein ungültiger Scan erreicht den Commit nicht; der letzte gültige persistente Datenblock bleibt bestehen. Registrierte PlayerData-Blöcke sind derzeit `identity`, `equipment`, `mythicPlus`, `raid`, `delves`, `stats`, `profile`, `professions`, `addon` und `demands`.

`CharacterScanManager` ist die zentrale Exklusivitätsgrenze für lokale Character-Snapshots. Er entdeckt Block, Capability, Addon und Reihenfolge aus TOC-Metadaten, lädt den Provider bei Bedarf und startet immer nur einen Workflow der logischen Ressource `CHARACTER_SCAN`. Beim Login werden ausschließlich Blöcke ohne persistente Metadaten angefordert. Fachliche Events können denselben Block erneut als dirty markieren; solche Anforderungen werden zusammengeführt und fair hinter bereits wartende andere Blöcke gestellt.

## Synchronisation und Provenance

`Sync/Comms.lua` kapselt den AddonMessage-Transport. `SyncManager` registriert Domains mit Metadaten-, Export-, Validierungs-, Autorisierungs- und Importfunktionen. Discovery, Offer, Fetch, Payload und passive Heilung laufen über die zentrale Task-Queue.

Normale owner-kontrollierte Objekte werden anhand ihrer Domain-Metadaten verglichen. Owner-Provenance bleibt vom Relais getrennt: `owner` bezeichnet den Datenbesitzer, `receivedFrom` die übertragende Gegenstelle, `direct` eine direkte Owner-Übertragung. Permission-State verwendet dagegen eine Revision Chain und niemals „höchste Version gewinnt“. Details stehen in `SYNC_ARCHITECTURE.md`.

## ModuleRegistry und Capabilities

`ModuleRegistry` normalisiert Metadaten mit `id`, `internalName`, `name`, `displayName`, `description`, `icon`, `version`, `moduleType`, `category`, `dependencies`, `capabilities`, `ui`, `options`, `administration`, `data`, `sync`, `permissions` und `ruleFields`. `RegisterModule` ist der einheitliche Vertrag; `RegisterRequiredModule` und `RegisterOptionalModule` bleiben kompatibel. Deklarierte Rule-Felder werden beim Laden beziehungsweise Aktivieren ownergebunden registriert und beim Deaktivieren geschlossen entfernt.

Capabilities sind benannte, von Modulen registrierte Handler. Equipment-, Raid-, Mythic+-, Delve- und Stats-Module registrieren ihre fachlichen Scan-Provider beim `CharacterScanManager`; direkte Capability-Aufrufe und Event-Refreshes münden damit in dieselbe serialisierte Queue. Der detaillierte Implementierungsstand steht in `MODULE_ARCHITECTURE.md`.

## UI und Administration

`UIManager` verwaltet deklarative Views, Availability, Lifecycle, Refresh-Ereignisse und Navigation. `MainWindow` ist der zentrale Host. `UILayout`, `UIComponents` und die generische Table-Komponente bilden die gemeinsame Layout-/Widget-Grenze. CharacterUI/CharacterOverview bilden die Character-Oberfläche; Feature-Tabs lesen über zentrale Stores. Der vollständige UI-Vertrag steht in `UI_ARCHITECTURE.md`.

`HolyStorm.Administration` ist der generische Erweiterungspunkt für Admin-Seiten. Ein einzelner Host im bestehenden Hauptfenster stellt eine kategorisierte Tree-Navigation, Lifecycle, gezielten Refresh sowie Permission-, Modul- und Capability-Gating bereit. Nicht verfügbare, deaktivierte oder nicht autorisierte Sections fehlen vollständig in der Navigation. Gruppen/Berechtigungen, Regeln, Filter und Policy-Diagnose werden lazy gebaut und verwenden `UILayout`, `UIComponents`, TabGroup, gemeinsame Scroll-Container und die generische Table; ihre Fachoperationen verwenden direkt die Permission-Komponenten. Der externe `page`-Compatibility-Vertrag bleibt erhalten, erzeugt aber keinen zweiten Host. Der vollständige Vertrag steht in `ADMINISTRATION_ARCHITECTURE.md`.

## Permissions, Gruppen, Rules und Filter

Holy Storm besitzt eigenständige, wiederverwendbare Rule-Objekte neben Filter-Objekten. Beide enthalten denselben Expression Tree und werden ausschließlich von `RuleEngine` ausgewertet; es existiert keine zweite Rule- oder Filterauswertung in der Administration. Die ownergebundene Field Registry, die zentrale Operator-Registry, typabhängige Validierung und `PASS`/`FAIL`/`UNKNOWN` bleiben die fachliche Source of Truth.

`FilterManager` verwaltet lokale und gildenweite Objekte, sichere Duplikation, nicht persistierende Preview sowie erweiterbare Referenz-Provider. Der eingebaute Gruppen-Provider ist nur ein Consumer dieses Vertrags; weitere Module können Referenzquellen registrieren. Die Administration koordiniert diese APIs und greift nicht direkt auf SavedVariables zu.

- `PermissionRegistry`: bekannte Permission-Definitionen und Metadaten.
- `PermissionEngine`: Kontext, Membership-Gründe, effektive Gruppen/Rechte, Matrix und Erklärungen.
- `GroupManager`: System- und benutzerdefinierte Gruppen sowie Mitgliedschaften und Manager-Gruppen.
- `RuleEngine` / `HolyStorm.Rules`: registrierbare Felder, Operatoren, Validierung und PASS/FAIL/UNKNOWN-Auswertung.
- `FilterManager`: lokale und gildenweite Rules/Filter sowie Verknüpfungen.
- `PolicyState`: gildenweiter State, Validierung, Autorisierung und revisionsbasierte Mutationen.
- `PermissionSync`: Revision-Catch-up, vertrauensgebundene Recovery und Sync-Domain.

Der Core besitzt ausschließlich den Rule-Vertrag: Registry, Operatoren, Typ- und Strukturvalidierung, Abhängigkeitsermittlung sowie die drei Ergebnisse `PASS`, `FAIL` und `UNKNOWN`. Fachmodule besitzen Resolver, Feldmetadaten und optionale Demand-Collector. Unbekannte Feld-IDs bleiben in gespeicherten Rules und Filtern unverändert, gelten strukturell als portabel und ergeben bei der Auswertung `UNKNOWN`. Resolver- oder Availability-Fehler werden protokolliert und ebenfalls in `UNKNOWN` überführt.

Quest- und Blizzard-Erfolgsbedarfe werden deklarativ durch `CharacterRuleData` gesammelt. Sowohl der Neuaufbau des Bedarfs als auch dessen Erfassung laufen als Tasks; die Erfassung verwendet WoW-APIs und schreibt ausschließlich über `CharacterStore`. Die RuleEngine startet keine Scans und persistiert weder Bedarfslisten noch Character-Snapshots.

Die Systemgruppen sind `guild-leadership`, `officers` und `guild-member`. Rechte mehrerer Gruppen werden addiert. Leadership besitzt dynamisch alle registrierten Permissions; ihre Permission-Menge und die Systemgruppen-Metadaten sind im Core unveränderlich. Manager-Gruppen dürfen eine Zielgruppe verwalten, erben aber weder Mitgliedschaft noch Rechte dieser Gruppe. Beim Löschen einer Custom-Gruppe werden eingehende Manager-Referenzen atomar bereinigt. Die tatsächliche Blizzard-Gildenleitung ist der Trust Anchor für geschützte Leadership-Mitgliedschaft und Snapshot-Recovery.

Jede gildenweite Mutation erzeugt eine monotone Version mit neuer `revisionID`, korrekter `previousRevisionID`, `changedBy` und `changedAt`. Lücken lösen Catch-up/Recovery aus. Geschwisterrevisionen erzeugen `CONFLICT`; es gibt keinen automatischen Versionssieger. Factory Reset ist eine normale Revision und ersetzt ausschließlich die Gruppen durch die drei Defaults; wiederverwendbare Rules/Filter, Modulkonfiguration und fachfremde Daten bleiben erhalten.

## Lokalisierung

Zentrale Texte liegen unter `Locales`. UI- und Modultexte liegen in ihren Domänen, darunter `UI/Character/Locales`, `UI/Administration/Locales` und `Modules/*/Locales`. Neue sichtbare Texte müssen mindestens `enUS` und `deDE` besitzen. Locale-Namespace und Fallback bleiben bei AceLocale.

## SavedVariables und Compatibility

Die TOC deklariert `HolyStormDB`, `HS_Player_DB` und `HS_GuildLog_DB`. Schema und Migrationen bleiben die einzigen Stellen für strukturelle Datenmigration. Öffentliche Compatibility-Oberflächen wie `HolyStorm.Policy`, `HolyStorm.Permissions`, `HolyStorm.PermissionManager`, `HolyStorm:HasPermission`, DataManager und Required-/Optional-Modulregistrierung bleiben bestehen und delegieren auf die aktuelle Implementierung.

## Optionale und externe Module

Optionale In-Addon-Module werden aus Registry-Metadaten erzeugt und über persönliche sowie gildenweite Aktivierung gesteuert. Der Metadaten-, Capability-, UI-, Administration-, Data- und Sync-Vertrag bereitet externe Holy-Storm-Module vor.

Feature-Pakete wie Equipment, MythicPlus, Raids, Delves und POI werden als separate WoW-Addons ausgeliefert. Der Core entdeckt ihre Metadaten und optionalen Load-on-Demand-Trigger ohne fachliche Feature-Liste.

## Bekannte technische Restschulden

- Der Bootstrap initialisiert einige konkrete Services statt ausschließlich deklarative Lifecycle-Hooks zu nutzen.
- Modulmetadaten sind vorhanden, werden aber noch nicht in allen Modulen vollständig für UI, Administration, Data und Sync genutzt.
- `HolyStorm.Policy` bleibt als öffentliche Compatibility-Fassade bestehen. Neue fachliche Autorisierungen verwenden `PermissionEngine`; Test- und Altverbraucher können während der Übergangszeit auf die Fassade zurückfallen.
