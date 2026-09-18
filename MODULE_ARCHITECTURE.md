# Holy Storm – Modulvertrag

Diese Referenz trennt klar zwischen **A: implementiert**, **B: vorbereitet** und **C: zukünftiges Ziel**.

## Metadatenvertrag

`ModuleRegistry:NormalizeModuleMetadata` normalisiert folgende Felder:

- `id`, `internalName`
- `name`, `displayName`, `description`, `icon`, `version`
- `moduleType`, `category`
- `dependencies`, `capabilities`
- `ui`, `options`, `administration`, `data`, `sync`
- `permissions`, `ruleFields`

`id` und `internalName` sind stabile technische Identitäten. Sichtbare Namen und Beschreibungen sollen lokalisiert werden. `version` ist SemVer. `category` unterscheidet derzeit insbesondere `required` und `optional`; `moduleType` beschreibt etwa `core` oder `feature`.

## A – aktuell implementiert

### Registrierung und Lifecycle

- `HolyStorm:RegisterModule(metadata, factory)` ist der einheitliche Einstieg. Required-Module werden sofort als AceAddon-Modul erzeugt; Optional-Module hinterlegen zunächst ihre Factory.
- `HolyStorm:RegisterRequiredModule(name)` bleibt für vorhandene feste Komponenten verfügbar.
- `HolyStorm:RegisterOptionalModule(name, metadata, factory)` bleibt als Compatibility-API verfügbar.
- `HolyStorm:ApplyModuleMetadata(module, metadata)` versieht vorhandene Module mit normalisierten Metadaten.
- Persönliche Optional-Modul-Aktivierung läuft über `IsOptionalModuleEnabled`/`SetOptionalModuleEnabled`; das Permission-System ergänzt den gildenweiten Modulstatus.

### Capabilities

`RegisterCapability(moduleName, capability, handler)` registriert einen benannten Handler. `CallCapability` ruft ausschließlich geladene und aktivierte Module auf. Character-Scans verwenden aktuell unter anderem `character.scan.equipment`, `character.scan.raids`, `character.scan.mythicplus`, `character.scan.delves`, `character.scan.stats` und `character.scan.additional`.

### UI und Administration

Module können Seiten über `HolyStorm.UI:RegisterPage` und Navigation über `AddNavigation` registrieren. CharacterOverview stellt eine eigene Tab-Registry bereit. Administrative Erweiterungen deklarieren `metadata.administration` oder verwenden `HolyStorm:RegisterAdministrationSection`. Die ModuleRegistry übergibt deklarierte Sections an den zentralen Host; dieser prüft Permission, geladenes/aktiviertes Modul, Capability und optionale Verfügbarkeit. Der vollständige Vertrag steht in `ADMINISTRATION_ARCHITECTURE.md`.

### Daten, Snapshots und Sync

- Character-Datenblöcke werden über `HolyStorm.PlayerData:RegisterBlock` beschrieben.
- Snapshot-Abläufe verwenden `HolyStorm.Snapshots:Queue` und damit TaskManager/WorkflowManager.
- Sync-Domains registrieren sich über `HolyStorm.Sync:RegisterDomain` mit Metadaten, Export, Validierung, Autorisierung und Import.
- Tasks und Workflows besitzen stabile registrierte IDs; Module erzeugen keine eigene parallele Scheduler-Infrastruktur.

### Permissions, Locales und Commands

- Permissions können mit `HolyStorm.PermissionRegistry:RegisterPermission` registriert werden.
- Effektive Rechte werden über `PermissionEngine` geprüft; alte Verbraucher dürfen Compatibility-APIs verwenden.
- Modulspezifische Locales liegen unter `Modules/<Modul>/Locales` und werden vor dem Modul geladen.
- Slash Commands werden zentral über die Commands-Infrastruktur angebunden; Module sollen keine konkurrierenden Root-Kommandos erzeugen.

### Rule-Felder

Module deklarieren Rule-Felder bevorzugt in `metadata.ruleFields` oder registrieren sie explizit über `HolyStorm.Rules:RegisterField(owner, fieldID, definition)`. Eine Definition unterstützt `type`, lokalisierten Namen und Beschreibung, Kategorie, `resolver`, optionale `availability`, `dependencies`, `allowedOperators`, `valueProvider`/`enumProvider`, Einheit-/Anzeige-Metadaten und einen optionalen Demand-Collector. `RegisterAlias` hält alte Feld-IDs kompatibel.

Öffentliche Lifecycle- und Lese-APIs sind `RegisterField`, `RegisterAlias`, `UnregisterField`, `UnregisterOwner`, `GetField`, `GetFields`, `GetFieldsByOwner` und `GetAllowedOperators`. Module verändern keine internen Registry-Tabellen. Die ModuleRegistry registriert deklarierte Felder erneut beim Aktivieren und entfernt beim Deaktivieren nur die Felder des betreffenden Owners.

## B – vorbereitet, aber nicht flächendeckend genutzt

- Die Metadatenfelder `ui`, `options`, `data` und `sync` existieren, treiben aber noch nicht automatisch alle Registrierungen und Lifecycle-Schritte. `administration` wird bereits automatisch vom zentralen Host registriert.
- Die Administration-Registry akzeptiert externe Modul-Sections und blendet fehlende oder gildenweit deaktivierte Module sicher aus.
- Feature-Module deklarieren ihre Permissions als Metadaten. Die ModuleRegistry registriert sie über die zentrale PermissionRegistry und übernimmt dabei Owner, Kategorie und Systemgruppen-Defaults.
- RuleEngine besitzt ausschließlich die generische Feld-/Provider-Registry; alle fachlichen Felder einschließlich Character, Guild, Profile, Quest-/Achievement-Demand, Equipment, MythicPlus, Raids, Delves, Calendar, Content und POI werden durch ihre Owner registriert.
- Capabilities reduzieren Bootstrap-Kopplung, während einige Services noch direkt in Bootstrap initialisiert werden.
- Sync-Domains sind generisch registrierbar; geschützte Feature-Domains autorisieren über PermissionEngine, während normale ownergebundene Character-Daten ohne separates Share-Recht auskommen.

## C – Target / Planned

- Metadaten können Lifecycle, UI, Administration, Datenblöcke und Sync-Domains vollständiger deklarativ verbinden.
- Externe Drittanbieter-Module verwenden nur öffentliche Core-Verträge und keine internen Tabellen.
- Feature-Pakete können als separate WoW-Addons ausgeliefert werden, beispielsweise `Holy_Storm_Equipment`, `Holy_Storm_MythicPlus`, `Holy_Storm_Raid` oder `Holy_Storm_POI`.

Für separate Addons bleiben `Holy_Storm` als Required Dependency, eine TOC-seitige Load-Order, eigene Locale-Dateien und eine saubere Deaktivierung bei fehlendem Core erforderlich. Diese Pakettrennung ist noch nicht erfolgt.

## Anforderungen an neue Module

1. Stabile Metadaten mit eindeutiger ID und SemVer bereitstellen.
2. Nur öffentliche Store-, Event-, Task-, Workflow-, Capability-, UI-, Administration-, Permission- und Sync-APIs verwenden.
3. Keine SavedVariables direkt verändern und keine zweite Datenbank oder Queue einführen.
4. Sichtbare Texte in der Modul-Lokalisierung mindestens auf Deutsch und Englisch bereitstellen.
5. Tasks, Workflows, Capabilities, Permissions, Sync-Domains und UI-Seiten mit stabilen IDs registrieren.
6. Fachlogik im Modul halten; Core-Hosts erhalten nur Verträge und Callbacks.
7. Modulverhalten und Ingame-Prüfschritte dokumentieren und Offline-Vertragstests ergänzen.
