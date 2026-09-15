# Holy Storm – Refactoring-Übergabe

Stand: 6. September 2026  
Projekt: `D:\WoW Addon - Holy Storm`  
Addon: `LIVE\Holy_Storm`

Diese Datei bewahrt den Arbeitsauftrag, den erreichten Zustand und die wichtigsten Prüfergebnisse unabhängig vom Codex-Chat auf. Sie ist der Einstiegspunkt, wenn die Arbeit später fortgesetzt oder überprüft wird.

## Ursprünglicher Auftrag

Das bestehende World-of-Warcraft-Retail-Addon **Holy Storm** sollte vollständig auf eine klar getrennte Architektur aus Core-Infrastruktur, Datenhaltung, UI und Fachmodulen umgebaut werden. Bestehende Funktionen und SavedVariables mussten erhalten beziehungsweise migrationssicher übernommen werden. Gefordert waren insbesondere ein zentraler EventBus, StateManager, TaskManager, Comms-/Sync-Layer, Berechtigungssystem, Serializer, Daten-Stores, UIManager und defensive Nutzung versionsabhängiger Blizzard-APIs. Es durften keine Platzhalter, TODO-Implementierungen oder parallelen Altarchitekturen verbleiben.

Die vollständige ursprüngliche Aufgabenbeschreibung kam aus:

`C:\Users\richa\.codex\attachments\872e08ef-16e7-4c52-826f-3281857f80f0\pasted-text.txt`

Die fachlich verbindlichen Details sind außerdem durch die implementierte Struktur, `PROJECT_CONTEXT.md` und `CHANGELOG.md` dokumentiert.

## Erreichter Zustand

- Addon-Version auf `4.0.0` aktualisiert; Retail-Interface `120100` beibehalten.
- SavedVariables beibehalten: `HolyStormDB`, `HS_Player_DB`, `HS_GuildLog_DB`.
- Neue Schichten unter `Core/`, `Data/`, `UI/` und domänenbezogenen `Modules/` eingeführt.
- Alte Parallelstruktur `Modules/Required` und `Modules/Optional` entfernt.
- Zentraler Bootstrap, EventBus, StateManager, priorisierter TaskManager, Datenbankdienst, Logger, Serializer, HookManager, ActionManager, UIManager, Comms und SyncManager sind implementiert und verbunden.
- Datenmodell trennt Guild, Player und Character; GUIDs dienen soweit möglich als Charakter-ID.
- Installationslokale Spielerkennung fasst eigene Charaktere automatisch zusammen.
- Schema-Version 3 und idempotente Migrationen übernehmen Altbestände einschließlich Twinks sowie Spieler-Metadaten.
- Blizzard-Daten haben Feldpriorität und werden nicht blind von synchronisierten Daten überschrieben.
- Das zentrale, datengetriebene Berechtigungssystem enthält eine unveränderliche Gildenleiterrolle mit vollständigen Rechten.
- Kommunikation verwendet ein versioniertes Protokoll, Chunking, Queue, Prioritäten, Throttling, Reassembly und defensive Eingangsvalidierung.
- UI-Seiten werden zentral registriert; unsichtbare Seiten werden nur als `dirty` markiert und erst beim Anzeigen aktualisiert.
- Fachmodule Guild, Characters, Equipment, Raids, MythicPlus, Calendar, Professions, Delves und GuildLog wurden migriert beziehungsweise funktional umgesetzt.
- Slash-Commands und Chat-Link-Hooks liegen zentral in `Core/Commands/Commands.lua`.
- Lokalisierungen liegen bei den jeweiligen Domänen; jede eigene Lua-Datei deklariert lokal ihre Addon-Version.

## Wichtige Einstiegspunkte

- `LIVE/Holy_Storm/Holy_Storm.toc` – vollständige Ladefolge
- `LIVE/Holy_Storm/Core/Bootstrap/Bootstrap.lua` – kontrollierter Start
- `LIVE/Holy_Storm/Core/Events/EventBus.lua` – WoW- und interne Events
- `LIVE/Holy_Storm/Core/Tasks/TaskManager.lua` – priorisierte Aufgabensteuerung
- `LIVE/Holy_Storm/Sync/Comms.lua` – technische Übertragung
- `LIVE/Holy_Storm/Sync/SyncManager.lua` – fachliche Synchronisation
- `LIVE/Holy_Storm/Core/Permissions/Permissions.lua` – Rollen und Rechte
- `LIVE/Holy_Storm/Persistence/Schema.lua` – aktuelles Datenmodell
- `LIVE/Holy_Storm/Persistence/Migrations.lua` – Datenmigrationen
- `PROJECT_CONTEXT.md` – Projekt- und Architekturkontext
- `CHANGELOG.md` – nachvollziehbare Änderungshistorie

## Öffentliche Kern-Namespaces

`HolyStorm.Events`, `HolyStorm.State`, `HolyStorm.Tasks`, `HolyStorm.Database`, `HolyStorm.Comms`, `HolyStorm.Sync`, `HolyStorm.Permissions`, `HolyStorm.Hooks`, `HolyStorm.Actions`, `HolyStorm.UI`, `HolyStorm.Data` und `HolyStorm.Modules`.

Kompatibilitätsaliasse für alten Code wurden gezielt erhalten, darunter `EventManager`, `DataManager`, `ConfigManager`, `PlayerManager`, `PermissionManager` und `HasPermission`.

## Durchgeführte Prüfungen

Alle folgenden Prüfungen waren beim Abschluss erfolgreich:

- Alle TOC-Pfade existieren und alle eigenen Lua-Dateien sind erfasst.
- Alle nicht eingebetteten Bibliotheksdateien lassen sich syntaktisch mit Lua laden.
- Lokalisierungsprüfung über `tools\Test-Localization.ps1`.
- TOC-Ladereihenfolge und Registrierungen mit simulierten WoW-/Ace-APIs.
- Vollständiger Core-Initialisierungs-Smoke-Test inklusive Schema 3, Status, Sync, lokaler Spielerkennung, Leiterrolle und Slash-Command.
- Serializer-Roundtrip und Ablehnung fehlerhafter Daten.
- Idempotente Alt-Datenmigration einschließlich `knownTwinks` und `realName`.
- EventBus-Routing sowie Task-Priorität und Deduplizierung.
- Vorrang lokaler Blizzard-Daten und Erhalt alter SavedVariable-Felder.

## Verbleibende Grenze

Der Code wurde statisch und mit simulierten APIs geprüft. Ein abschließender Lauf im echten aktuellen WoW-Retail-Client bleibt notwendig, weil dessen geschützte Laufzeit, Event-Reihenfolge, Serverkommunikation und konkrete API-Rückgaben außerhalb der lokalen Testumgebung nicht vollständig reproduzierbar sind.

## Hinweise für spätere Arbeit

- Vor weiteren Änderungen zuerst `PROJECT_CONTEXT.md`, `CHANGELOG.md` und diese Datei lesen.
- Keine zweite Addon-Kopie neben `LIVE/Holy_Storm` anlegen.
- Bestehende SavedVariables und Migrationspfade nicht entfernen.
- Blizzard-Datenpriorität in `CharacterStore` und den Sync-Handlern erhalten.
- Neue teure oder wiederkehrende Arbeit über `HolyStorm.Tasks` ausführen.
- Neue Events über `HolyStorm.Events` und neue UI-Seiten über `HolyStorm.UI` anbinden.
- Versionsabhängige Retail-APIs stets defensiv prüfen.
- Vor einer Veröffentlichung einen echten In-Game-Test durchführen; ein Release-ZIP wurde in diesem Arbeitsgang nicht erstellt.
