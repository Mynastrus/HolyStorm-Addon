# Holy Storm – Addon- und Modulvertrag

Holy Storm wird als Addon-Familie ausgeliefert. `Holy_Storm` ist der eigenständig
ladefähige Core. Jedes Feature liegt in einem eigenen WoW-Addon und deklariert
`## RequiredDeps: Holy_Storm`:

- `Holy_Storm_Characters`
- `Holy_Storm_Equipment`
- `Holy_Storm_Raids`
- `Holy_Storm_MythicPlus`
- `Holy_Storm_Delves`
- `Holy_Storm_Calendar`
- `Holy_Storm_Professions`
- `Holy_Storm_Guild`
- `Holy_Storm_GuildLog`
- `Holy_Storm_News`
- `Holy_Storm_Achievements`
- `Holy_Storm_POI`
- `Holy_Storm_Positions`

Alle Addons verwenden die TOC-Kategorie `Holy Storm`. Die bestehenden
SavedVariables bleiben unverändert im Core-TOC; Feature-Addons erzeugen keine
zweiten Datenbanken.

## Core-Verantwortung

Der Core besitzt Infrastruktur, gemeinsame Stores und Hosts: Registry, Events,
Tasks, Workflows, Actions, Permissions, Sync, Logging, Rich Content sowie die
generische UI. Er lädt keine Feature-Runtime- oder Feature-UI-Dateien.

`ModuleRegistry:NormalizeModuleMetadata` normalisiert `id`, `internalName`,
`name`, `displayName`, `description`, `icon`, `version`, `moduleType`,
`category`, `dependencies`, `capabilities`, `ui`, `options`, `administration`,
`data`, `sync`, `permissions`, `ruleFields`, `schemaVersion` und
`snapshotVersion`.

## Feature-Registrierung

Feature-Addons registrieren sich mit `HolyStorm:RegisterModule(metadata,
factory)`. Die Kategorie `feature` erzeugt das AceAddon-Modul beim Laden des
Feature-Addons; die frühere interne Optional-Modul-Schaltung ist nur noch eine
Compatibility-API. Aktivierung und Deaktivierung erfolgen über den WoW-Addon-
Manager und die normalen AceAddon-Lifecycles.

Feature-spezifische Verantwortungen verbleiben beim jeweiligen Addon:

- Permissions und Rule-Felder über Modulmetadaten
- Datenblock-Schemas über `HolyStorm.PlayerData:RegisterBlock`
- Snapshot-, Task-, Workflow- und Sync-Registrierung
- UI-Seiten, Navigation und Administrationserweiterungen
- Feature-Locale-Namespaces in Englisch und Deutsch
- Rich-Link-Typen und Slash-Unterbefehle

Der Core entdeckt Character-Scan-Capabilities dynamisch. Es gibt keine
featurebezogenen Startup-Zweige im Bootstrap.

## Dynamische Erweiterungspunkte

- `RegisterCapability` / `CallCapability` für fachliche Aktionen
- `RegisterCharacterTab` für CharacterOverview-Tabs
- `RegisterCharacterSummarySection` für Summary-Blöcke
- `RegisterAdministrationSection` beziehungsweise `metadata.administration`
- `Commands:RegisterSubcommand` für `/hs`-Unterbefehle
- `RichLinks:RegisterType` und `RegisterToken` für Inhalte und Chatlinks
- `PlayerData:RegisterBlock` für featureeigene Character-Daten
- `Rules:RegisterField` sowie `metadata.ruleFields` für Filterregeln

Character-Erweiterungen sind load-order-sicher: Sie können vor oder nach
`Holy_Storm_Characters` geladen werden und werden über die Core-Registry
nachregistriert. Fehlt ein Feature-Addon, fehlen nur dessen Tabs, Seiten,
Capabilities und Datenregistrierungen; der Core bleibt funktionsfähig.

## Anforderungen an neue Feature-Addons

1. Eigenen Ordner und eigenes TOC mit `RequiredDeps: Holy_Storm` anlegen.
2. Stabile Modul-ID, SemVer, Icon, Abhängigkeiten und Datenversionen deklarieren.
3. Nur öffentliche Store-, Event-, Task-, Workflow-, Capability-, UI-,
   Permission- und Sync-APIs verwenden.
4. Keine SavedVariables direkt verändern und keine zweite Queue einführen.
5. Featuretexte mindestens in `enUS` und `deDE` im Feature-Addon pflegen.
6. Ohne andere Feature-Addons sicher laden; optionale Integration ausschließlich
   über Registries, Capabilities oder nil-sichere Abfragen herstellen.
7. TOC-, Syntax-, Locale-, Offline- und Ingame-Vertragstests ergänzen.
