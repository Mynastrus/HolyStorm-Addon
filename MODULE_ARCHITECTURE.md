# Holy Storm – Modulvertrag

Diese Referenz trennt klar zwischen **A: implementiert**, **B: vorbereitet** und **C: zukünftiges Ziel**.

## Metadatenvertrag

`ModuleRegistry:NormalizeModuleMetadata` normalisiert folgende Felder:

- `id`, `internalName`
- `name`, `displayName`, `description`, `icon`, `version`
- `moduleType`, `category`
- `dependencies`, `capabilities`
- `ui`, `options`, `administration`, `data`, `sync`

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

Module können Seiten über `HolyStorm.UI:RegisterPage` und Navigation über `AddNavigation` registrieren. CharacterOverview stellt eine eigene Tab-Registry bereit. Administrative Erweiterungen verwenden `HolyStorm:RegisterAdministrationSection` beziehungsweise `HolyStorm.Administration:RegisterSection` mit ID, Anzeigeinformationen, Reihenfolge, Permission, Modul/Owner, Page oder Build, Render und Verfügbarkeit.

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

## B – vorbereitet, aber nicht flächendeckend genutzt

- Die Metadatenfelder `ui`, `options`, `administration`, `data` und `sync` existieren, treiben aber noch nicht automatisch alle Registrierungen und Lifecycle-Schritte.
- Die Administration-Registry akzeptiert externe Modul-Sections und blendet fehlende oder gildenweit deaktivierte Module sicher aus.
- PermissionRegistry akzeptiert Modul-Permissions; bestehende Feature-Permissions werden dennoch größtenteils zentral vorregistriert.
- RuleEngine besitzt eine Feld-/Provider-Registry, aber mehrere Feature-Provider befinden sich weiterhin in Core.
- Capabilities reduzieren Bootstrap-Kopplung, während einige Services noch direkt in Bootstrap initialisiert werden.
- Sync-Domains sind generisch registrierbar, einzelne Features verwenden bei Autorisierung aber noch Compatibility-Fassaden.

## C – Target / Planned

- Feature-Permissions und Rule-Feldprovider werden durch die besitzenden Module registriert.
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
