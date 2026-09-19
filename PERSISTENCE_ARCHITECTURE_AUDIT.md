# Holy Storm Persistence- und Datenarchitektur-Audit

Stand: 2026-09-19
Repository-Revision: `94a02493f7eb89c8328401867bb05b275bfd1909` (`main`)
Gegenstand: Ist-Analyse sowie dokumentierter Phase-1-Implementierungsstand; keine Store- oder SavedVariable-Migration

## Kurzfazit

Holy Storm besitzt bereits drei Bausteine einer späteren zentralen Architektur, aber noch keinen zentralen DataManager im geforderten Sinn:

1. `Persistence/Database.lua` ist die zentrale AceDB-Initialisierung und bietet `Get`, `Set`, `RegisterArea` und `GetArea` an.
2. Unter dem Namen `HolyStorm.DataManager` existiert dort bereits ein kleiner Alias auf die Area-API. Im übrigen Repository wird dieser Alias derzeit nicht verwendet.
3. `PlayerDataStore` ist für Character-Blöcke bereits eine vergleichsweise starke Commit-/Freshness-Grenze: Validierung, Owner-Revision, Remote-Freshness und Events liegen dort.

Die Zielregel „nur DataManager greift direkt auf SavedVariables zu“ ist dennoch weit entfernt: Stores, Logging, Policy, Core-Manager, Feature-Module und UI greifen auf `HolyStorm.db`, persistente Live-Tabellen oder die drei SavedVariable-Globals zu. Besonders relevant sind vier Befunde:

- Die öffentlichen Getter vieler Stores geben persistente Tabellen als veränderbare Referenzen zurück. Dadurch können Revision, Validierung und Events vollständig umgangen werden.
- Remote beobachtete Character-Identity wird ohne neue Owner-Revision geändert. Das verletzt für den synchronisierbaren `identity`-Block die Origin-Autorität.
- `AchievementStore` speichert `direct=false` durch den Lua-Ausdruck `remoteMeta and remoteMeta.direct or true` als `true`. Ein Relay kann dadurch lokal fälschlich als direkter Owner erscheinen.
- Migrationen verändern mehrere Live-Tabellen schrittweise, ohne Copy-on-write, Backup oder Rollback. Ein Fehler wird zwar erkannt, kann aber einen teilweise veränderten Zustand hinterlassen.

## 1. SavedVariables-Inventar

Es gibt genau eine produktive TOC-Datei, `LIVE/Holy_Storm/Holy_Storm.toc`. Sie deklariert in Zeile 12 drei accountweite SavedVariables:

| SavedVariable | TOC-Scope | Logischer Scope | Primärer Eigentümer heute | Direkte Leser | Direkte Schreiber |
|---|---|---|---|---|---|
| `HolyStormDB` | `SavedVariables` (accountweit) | AceDB-Container mit `global`, `profile` und logisch charactergebundenem `char`; zusätzlich guild-keyed Bereiche | `Persistence/Database.lua` / AceDB | `Database.lua:6-7`; `UI/Pages/SavedVariables.lua:107,181`; AceDB-Bibliothek | `Database.lua:7,11-14`; danach alle direkten `HolyStorm.db`-Mutatoren; AceDB selbst |
| `HS_Player_DB` | `SavedVariables` (accountweit) | kanonische Character-, Account-/Player-, Relationship- und Sync-Watermark-Datenbank | `Persistence/PlayerDataStore.lua`, fachlich zusätzlich `CharacterStore`, `PlayerStore`, `TwinkCore` | `Database.lua:8`; `Migrations.lua:30-38,70-90`; `PlayerDataStore.lua:42-52`; Diagnose-UI | dieselben Initialisierer/Migrationen; transitiv alle Mutatoren der von `PlayerDataStore` herausgegebenen Tabellen |
| `HS_GuildLog_DB` | `SavedVariables` (accountweit) | ein nicht nach Guild-ID partitioniertes Guild-Log mit `entries` und `snapshot` | `Persistence/GuildStore.lua` / `Modules/GuildLog` | `Database.lua:9`; `GuildStore.lua:12-16`; Diagnose-UI | `Database.lua:9`; `GuildStore.lua:12-16` |

`SavedVariablesPerCharacter` wird in keiner TOC-Datei deklariert. `HolyStormDB.char` ist ein AceDB-Namespace innerhalb der accountweiten Variable, kein separates WoW-`SavedVariablesPerCharacter`-Global.

Guildbezogene Daten liegen accountweit und werden teilweise per Guild-ID getrennt:

- `HolyStormDB.global.data.guilds[guildId]`: Roster-/Guild-Cache.
- `HolyStormDB.global.permissionStates[guildId]`: Policy-Revision-State.
- `HolyStormDB.global.content.guilds[guildId]`: News/Guides.
- `HolyStormDB.global.poi.guilds[guildId]`: Guild-POIs.
- `HolyStormDB.global.achievements.guilds[guildId]`: Definitionen und Award-Events.
- `HS_GuildLog_DB` besitzt dagegen keine Guild-ID-Partitionierung.

Nach `PlayerDataStore:Initialize` sind `HolyStormDB.global.data.characters`, `.players` und `.characterOwners` In-Memory-Aliase auf die entsprechenden Tabellen in `HS_Player_DB` (`PlayerDataStore.lua:47-52`). Damit gibt es während der Sitzung für diese drei Tabellen eine gemeinsame Tabellenidentität, aber weiterhin zwei deklarierte SavedVariable-Wurzeln und Legacy-Pfade.

## 2. Direkte Persistenzzugriffe

### 2.1 Produktivcode, nach Kategorie

| Klasse | Datei/Funktion | Zugriff und Wirkung |
|---|---|---|
| A – zentrale Persistence-Komponente | `Persistence/Database.lua:4-16` | Liest alten `HolyStormDB`-Root, erzeugt AceDB, initialisiert alle drei Globals, startet Migrationen. |
| A/H – Migration/Compatibility | `Persistence/Migrations.lua:7-124` | Mutiert `HolyStormDB.global` und `HS_Player_DB` direkt; setzt alle zentralen Schema-Marker. |
| B – Store | `Persistence/PlayerDataStore.lua:41-76` | Rekonstruiert `HS_Player_DB`, setzt Schema 2, installiert Legacy-Aliase, repariert Block-Metadaten. |
| B – Store | `Persistence/PlayerDataStore.lua:79-145` | Mutiert Characters, Blockdaten, Metadaten und Sync-Watermarks direkt in der kanonischen Root-Tabelle. |
| B – Store | `Persistence/CharacterStore.lua` | Mutiert indirekt `HS_Player_DB` über `PlayerData`; `GetOrCreate` und kompatible APIs geben Live-Daten weiter. |
| B – Store | `Persistence/PlayerStore.lua:5-25` | Mutiert live herausgegebene Accounts/Owner-Mappings; liest `HolyStorm.db.global` direkt. |
| B – Store | `Persistence/GuildStore.lua:4-40` | Mutiert `HolyStormDB.global.data.guilds`; mutiert `HS_GuildLog_DB` direkt. |
| B – Store | `Persistence/ContentStore.lua:8-44` | Mutiert `HolyStormDB.global.content` direkt; führt zusätzlich eine fachliche Legacy-News-Migration aus. |
| B – Store | `Persistence/POIStore.lua:5-21` | Mutiert `HolyStormDB.global.poi` direkt. |
| B – Store | `Persistence/AchievementStore.lua:6-21` | Initialisiert und mutiert `HolyStormDB.global.achievements` direkt. |
| C – Snapshot | `Persistence/SnapshotManager.lua` | Kein direkter DB-Zugriff; hält nur flüchtige Fingerprints und koordiniert Workflows. |
| D – Feature/Core | `Modules/Characters/TwinkCore.lua:30-44,73-141` | Mutiert Accounts, Relationships, Tombstones und Character-Owner über Live-Referenzen; schreibt zusätzlich zwei `HolyStorm.db.global`-IDs direkt. |
| D – Feature | `Modules/Characters/Profiles.lua:8-10` | `GetAccount` erhält eine Live-Account-Tabelle und initialisiert `metadata` direkt; fachliche Änderungen laufen danach über Store-APIs. |
| D – Feature | `Modules/Characters/RuleDataProvider.lua:24-54` | Liest Rules, Filters und Demands direkt aus `HolyStorm.db`; schreibt abgeleitete Demands über `CharacterStore:Upsert`. |
| D – Feature | `Modules/POI/POIService.lua:17-20,55,57` | Mutiert Profileinstellungen direkt über eine Live-AceDB-Tabelle. |
| D – Feature | `Modules/Positions/GuildPositions.lua:11,18-19` | Initialisiert und mutiert Profileinstellungen direkt. Live-Positionsdaten selbst bleiben flüchtig. |
| D – Feature | `Modules/News/Content.lua:18` | Liest `HolyStorm.db.global.installId` direkt für IDs; Datenmutation läuft über `ContentStore`. |
| D – Feature | `Modules/Calendar/Calendar.lua:12-14,151-167` | Arbeitet über `HolyStorm.Database`, nicht über Raw-Globals; speichert Snapshot und Unread-State. |
| D – Feature | `Modules/Professions/Professions.lua:7-10` | Kein direkter DB-Zugriff, aber direkter Store-Commit ohne SnapshotManager/Validator. |
| D – Rule/Policy | `Core/Permissions/FilterManager.lua:93-103,162-203,282-306,323-330` | Liest und mutiert globale Templates sowie lokale Profile-Filter/-Rules direkt. |
| D – Rule/Policy | `Core/Permissions/PolicyState.lua:34-112,229-258` | Holt persistente Roots über `Database:GetRoot`, gibt/ändert darin gespeicherte Policy-State-Tabellen. |
| D – Rule/Policy | `Core/Permissions/PermissionSync.lua:27-63,83-90` | Mutiert den persistenten Policy-State bei Remote-Import und initialisiert Profile-Tabellen über einen Live-Root. |
| D/H – Rule | `Core/Permissions/RuleEngine.lua:389-393` | Liest persistente Demands direkt über `HolyStorm.db.global`. |
| D – Core | `Core/Tasks/TaskManager.lua:37`; `Core/Workflows/WorkflowManager.lua:18` | Lesen persistente UI-/History-Limits direkt aus dem AceDB-Profil. |
| E – UI | `UI/Pages/Logs.lua:34-40,60` | Initialisiert und mutiert `HolyStorm.db.profile.logs` direkt. |
| E – UI | `UI/Pages/TaskManager.lua:31-58,148` | Initialisiert, mutiert und löscht `HolyStorm.db.profile.taskManager.columns` direkt. |
| E – UI | `UI/Pages/Options.lua:102` | Übergibt die komplette AceDB-Instanz an `AceDBOptions`; andere Optionen nutzen `Database:Get/Set`. |
| E – UI/Diagnose | `UI/Pages/SavedVariables.lua:106-114,178-195` | Liest die drei Globals dynamisch über `_G[...]`; kein Schreibpfad. |
| E – UI | `UI/Framework/MainWindow.lua:331-347`, `UI/Pages/Options.lua:23-73` | Benutzt die öffentliche `Database`-Fassade; kein Raw-Zugriff, aber noch nicht die spätere DataManager-Grenze. |
| F – Sync | `Sync/SyncManager.lua` | Kein Raw-DB-Zugriff. Persistenz erfolgt über Domain-Imports/Stores; der Manager mutiert aber Sync-Watermarks über `PlayerData`. |
| G – Logging | `Core/Logging/Logger.lua:4-22` | Bindet `history` direkt an `HolyStorm.db.global.logs.entries`, begrenzt auf 2000 und ersetzt die Tabelle bei `Clear`. |
| H – Compatibility | `PolicyState:BindCompatibility`, `PlayerDataStore:Initialize`, `TwinkCore:Initialize` | Installieren Aliase bzw. schreiben alte Kompatibilitätspfade weiter. |

Die wichtigsten indirekten Umgehungen sind nicht durch eine Suche nach Globalnamen sichtbar: `Database:GetRoot`, `Database:GetArea`, `PlayerData:GetCharacters/GetPlayers/GetOwners`, `CharacterStore:Get/GetAll/GetOrCreate`, `GuildStore:Get/GetAll/GetCurrent`, `ContentStore:GetEntries/GetGuild`, `POIStore:GetRoot/GetAll` und `AchievementStore:GetGuild/GetDefinitions/GetEvents` liefern Live-Tabellen oder darin enthaltene Live-Objekte. Nur einzelne Getter kopieren explizit, etwa `PlayerData:GetMetadata` oder Policy-Read-APIs.

### 2.2 Testcode

- `tools/test_playerdata_sync.lua:16-18` erstellt eine flache Legacy-`HS_Player_DB` und prüft die Rekonstruktion in Schema 2.
- `tools/test_twinks.lua:14` erstellt eine kanonische `HS_Player_DB`-Fixture.
- Weitere Tests verwenden überwiegend Mock-Objekte `HolyStorm.db`; das sind Test-Fixtures, keine produktiven SavedVariable-Zugriffe.

## 3. Bestehende Database-/Persistence-Komponenten

### `Database`

- Verantwortung: AceDB-Initialisierung, Legacy-Root-Erkennung, Start der globalen Migrationen, generisches Path-`Get/Set`, Area-Registrierung.
- Öffentliche API: `Initialize`, `IsInitialized`, `GetRoot`, `Get`, `Set`, `RegisterArea`, `GetArea`, `SetAreaValue`.
- Schema/Migration: delegiert an `Schema` und `Migrations`.
- Validierung: nur Scope-/Pfad-Grundprüfung; keine Schemas oder Datenvalidatoren.
- Revision: keine.
- Events: `HS_CONFIG_CHANGED`, `HS_DATA_CHANGED` nach In-Memory-Mutation.
- Sync: keine direkte Verbindung.
- Kritisch: `GetRoot` und `GetArea` geben veränderbare Live-Tabellen zurück.

### vorhandener `DataManager`

`Database.lua:49-53` legt bereits `HolyStorm.DataManager` an. Er besitzt nur `RegisterArea`, `GetArea` und `Set` als Weiterleitung an `Database`. Eine repositoryweite Suche findet keinen Nutzer. Er ist deshalb ein vorhandener Namens-/API-Keim, aber kein zentraler Persistence-Owner, kein Commit-Koordinator und kein Schema-/Migrationsmanager.

### `ConfigManager`

Ein dünner Alias für Defaults und `Database:Get/Set`. Auch er liefert über Defaults/`Get` Tabellen ohne Read-only-Garantie.

### Stores

- `PlayerDataStore`: kanonische Character-Blöcke, Metadaten, Freshness, Watermarks.
- `CharacterStore`: fachlicher Adapter auf `PlayerDataStore`, inklusive Legacy-Kompatibilität.
- `PlayerStore`: alter Player-/Account-Adapter; delegiert neue Account-Funktionen überwiegend an `TwinkCore`.
- `GuildStore`: Guild-Roster und separates GuildLog.
- `ContentStore`: Guild-Content, Index, Reads und begrenzte History.
- `POIStore`: persönliche, Guild- und Session-POIs.
- `AchievementStore`: Definitionen, Award-Events und Sync-Metadaten.

### sonstige State-/Storage-Komponenten

- `StateManager` ist ausschließlich flüchtiger Runtime-State und persistiert nicht.
- `SnapshotManager` persistiert nicht.
- Task-/Workflow-History ist flüchtig; nur Limits, Filter und Spaltenlayout sind im Profil persistent.
- Es gibt keine Repository-Klasse und keine atomare Transaction-Komponente.

## 4. CharacterStore

`CharacterStore` ist ein dünner fachlicher Adapter auf `PlayerDataStore`.

- Daten: Identity sowie Blöcke `equipment`, `raid`, `mythicPlus`, `professions`, `delves`, `stats`, `profile`; kompatible Record-Felder zusätzlich `addon` und `demands` über den PlayerData-Blockkatalog.
- Schlüssel: WoW-Character-GUID.
- Ownership: `PlayerData:IsLocallyOwned`; aktuell eigener `UnitGUID("player")` oder Relationship zum lokalen Account.
- Lesen: `GetAll`, `Get`, `GetOrCreate`, `GetBlock`, `GetBlockMetadata`, spezialisierte Getter.
- Schreiben: `Upsert`, `CaptureCurrent`, spezialisierte `Set*`-Methoden.
- Snapshot-Eingang: Feature-Module rufen spezialisierte Setter auf; Remote-Daten gehen über `PlayerData:AcceptRemoteBlock`.
- Validierung: allein durch registrierten PlayerData-Blockvalidator. Von den Character-Blöcken besitzt nur Mythic+ einen Store-Level-Validator.
- Version/Schema: Blockmetadaten enthalten `version`; Snapshot-Schema liegt im Payload (`snapshotVersion`) bzw. nur in Modulmetadaten. Der Store erzwingt diese Versionen außer Mythic+ nicht.
- Events: `HS_PLAYERDATA_UPDATED`, blockspezifisches Event und lokal `HS_PLAYERDATA_OWNED_UPDATED`.
- Persistenz: indirekt und sofort durch Mutation von `HS_Player_DB`.
- Sync: `SyncManager` hört `HS_PLAYERDATA_OWNED_UPDATED`; Remote-Import nutzt exklusiv `AcceptRemoteBlock`.
- Verhältnis zu `PlayerDataStore`: `CharacterStore` besitzt weder eigene Daten noch eigene Revisionen; die Wahrheit liegt in `PlayerDataStore`.

Wer darf schreiben: Technisch jeder Code mit Zugriff auf das globale `HolyStorm.Data.CharacterStore` bzw. `HolyStorm.PlayerData`. Feature-Module, GuildStore, RuleDataProvider, Bootstrap und TwinkCore tun dies. Der Store schützt nicht nach aufrufendem Modul, sondern nur nach GUID-Ownership und Modus. Sync schreibt über `PlayerData`, nicht über `CharacterStore`.

Besonderheit: Die `metadata`-Parameter der spezialisierten `CharacterStore:Set*`-Methoden werden ignoriert. `updatedAt`, `updatedBy` und Revision werden ausschließlich in `PlayerData:ApplyBlock` erzeugt. Das verhindert zwar, dass Module Revisionen frei setzen, macht die Signatur aber irreführend.

## 5. PlayerDataStore

### Datenmodell

`HS_Player_DB` Schema 2:

```text
schemaVersion
characters[characterGUID]
  guid, playerId, record.version, record.updatedAt, record.updatedBy
  <fachliche Felder>
  blockMeta[blockId] = { owner, version, updatedAt, source, receivedFrom, direct }
accounts / players                 (Alias-Paar)
characterAccounts / characterOwners (Alias-Paar)
localAccountUUID
adminTwinkTombstones
twinkSchemaVersion
sync.foreignWatermark
sync.foreignWatermarks[domain]
```

Character und Account sind N:M konzeptionell nicht erlaubt: `characterAccounts[guid]` zeigt auf genau einen Account; der Account hält dazu `characters[guid]`.

### Laden und Legacy-Rekonstruktion

`PlayerData:Initialize`:

1. erkennt eine flache alte `HS_Player_DB`, wenn `.characters` fehlt;
2. baut Root/Collections auf und setzt `schemaVersion=2`;
3. kopiert fehlende Datensätze aus `HolyStormDB.global.data`, wobei vorhandene kanonische Daten gewinnen;
4. bindet die drei Legacy-Tabellen in `HolyStormDB.global.data` als Aliase auf die kanonischen Tabellen;
5. rekonstruiert fehlende `blockMeta` aus Record-, Feld- und eingebetteten Versionen/Timestamps;
6. rekonstruiert Account-Metadaten und alte `knownTwinks`-Beziehungen, ohne die Character-Records für Rollback zu löschen.

Zusätzlich führen `Migrations` Schritt 6/7 und `TwinkCore:MigrateAccounts` ähnliche bzw. nachgelagerte Rekonstruktionen aus. Migration ist daher derzeit dezentral.

### Blöcke und Metadaten

Registrierte Blöcke: `identity`, `equipment`, `mythicPlus`, `raid`, `delves`, `stats`, `profile`, `professions`, `addon`, `demands`.

Metadaten:

- `owner`: Character-GUID.
- `version`: monoton pro Block bei lokalem Owner-Commit.
- `updatedAt`: lokaler Commit-Zeitpunkt bzw. erhaltenes Origin-`updatedAt`.
- `source`: Collector/Origin-Angabe oder `sync`.
- `receivedFrom`: Transport-Absender bei Remote-Import.
- `direct`: ob der unmittelbare Sender der Owner war.
- `objectId`, `block`, `guid` werden beim Lesen ergänzt, aber nicht so gespeichert.

Es gibt kein separates `originCreatedAt`, `originUpdatedAt` versus `receivedAt`, keine Content-Hash-Konfliktprüfung und keine schemaVersion in den Blockmetadaten.

### Commit und Konfliktbehandlung

- Local: Ownership prüfen, validieren, bei gleicher Nutzlast `UNCHANGED`, Version um eins erhöhen, Daten und Metadaten ersetzen, danach Events.
- Remote: `owner==guid`, gültige nichtnegative Version, Metadatenvergleich, lokaler Owner vor indirektem Relay geschützt, dann Daten und Origin-Version übernehmen.
- Vergleich: zuerst Version; bei gleicher Version gewinnt `direct=true` gegen `direct=false`; sonst `SAME_VERSION`.
- Timestamp ist kein Konfliktkriterium.
- Fehlende Remote-Version ist ungültig. Legacy-Daten erhalten bei Metadatenrekonstruktion mindestens Version 0 bzw. die höchste vorhandene Record-/Feldversion.

### Problematische Identity-Beobachtung

`ObserveIdentity` (`PlayerDataStore.lua:142-145`) verändert fremde Identity-Felder und setzt `updatedAt=now()`, ohne die Owner-Version zu erhöhen. Auslöser sind unter anderem Guild-Roster-Beobachtungen und Sync-Presence. Da `identity` selbst synchronisierbar ist, erzeugt ein Nicht-Owner damit eine veränderte Kopie unter unveränderter Owner-Revision. Das weicht vom ansonsten korrekten Owner-Revision-Modell ab.

## 6. SnapshotManager

Registrierte Typen entstehen dynamisch bei `Queue`: aktuell `mythicplus`, `raids`, `delves`, `stats`. Equipment benutzt einen eigenen Workflow.

Der generische Ablauf ist:

```text
Snapshot.<id>.Scan
→ Snapshot.<id>.Validate
→ Fingerprint-Vergleich gegen flüchtigen letzten erfolgreichen Fingerprint
→ Snapshot.<id>.Commit
```

- Erzeugung: vom Modul gelieferter Scanner.
- Validierung: vom Modul gelieferter Validator; Fehler führt zu erneutem Scan mit maximal drei Retries per Default.
- Vergleich: serialisierter Deep-Copy ohne top-level `updatedAt`, `version`, `snapshotVersion`.
- Revision: keine; entsteht erst im `PlayerDataStore`.
- Schema: keine Registrierung oder Prüfung.
- Commit: Callback des Moduls.
- Events/Sync: nicht im SnapshotManager; kommen aus Store und Sync-Listenern.
- Persistenz: keine eigene.
- Fingerprints: nur Runtime, global pro Snapshot-ID, nicht persistent und nicht nach Character getrennt.

Der Manager koordiniert also, persistiert aber nicht. Seine Validierung prüft einen einzelnen Scan; eine A/B-Stabilitätsprüfung existiert nicht.

## 7. Provenance- und Revisionssystem

| Domäne | Vorhandene Origin-Felder | Transport-/Relay-Felder | Erzeuger/Änderungsrecht | Bewertung |
|---|---|---|---|---|
| Character-Block | `owner`, `version`, `updatedAt`, `source` | `receivedFrom`, `direct` | lokaler Character über `WriteOwnedBlock`; Remote übernimmt Origin-Metadaten | Grundmodell gut; `ObserveIdentity` verletzt es; `receivedAt` fehlt. |
| Twink-Account | `accountUUID`, `ownerVersion`, `updatedAt`, `issuedBy` | nur Log-Kontext; kein persistentes `receivedFrom` | lokaler Account, ausgelöst von einem owner-bestätigten Character | Relay übernimmt Origin-Felder; Owner ist der letzte ausstellende Character, nicht die Account-ID. |
| Twink-Admin | `assignedBy`, `assignedAt`, `adminVersion`, `source` | kein persistentes `receivedFrom` | jeweils autorisierter Admin | Version pro Relationship/Tombstone; Autorität ist Policy-basiert. |
| Permission-State | `version`, `revisionID`, `previousRevisionID`, `changedBy`, `changedAt`, History | `lastSync`, Catchup-/Recovery-State | autorisierter Actor; vollständige Revision Chain | Stärkstes Modell; darf nicht durch generische DataManager-Revision ersetzt werden. |
| Content | `author*`, `modifiedBy`, `modifiedAt`, `revision` | `source="sync"`, `syncedAt` | jeder jeweils autorisierte Bearbeiter | Gemeinsame redaktionelle Ownership, nicht stabiler einzelner Owner. Origin-Felder bleiben erhalten. |
| POI | `creator*`, `modifiedBy`, `updatedAt`, `revision` | `source`, `receivedFrom`, `syncedAt` | Creator oder autorisierter Bearbeiter je Scope | Relay erzeugt keine neue Revision. |
| Achievement | Store-Meta `owner`, `version`, `updatedAt`; Payload besitzt fachliche Actor-Felder | `source="sync"`; kein `receivedFrom` | autorisierter Definition-/Award-Actor | Fehler: indirektes Remote-Meta wird als `direct=true` gespeichert. |
| Live Position | `characterUUID`, `sequence`, `timestamp` | inbound `source`, `receivedFrom`, `receivedAt` | nur Character selbst | Korrekt getrennt, aber absichtlich flüchtig. |

Das Relay-Verbot ist für Character, Content, POI, Twinks und Policy überwiegend umgesetzt: Version und Origin-Zeit werden beim Import übernommen. Abweichungen sind Identity-Beobachtung und der Achievement-`direct`-Fehler.

## 8. Freshness-Logik

Zentrale Standardfunktion ist `PlayerData:CompareMetadata`:

1. Remote-Metadaten und `version` müssen gültig sein.
2. Höhere Version gewinnt, niedrigere verliert.
3. Bei gleicher Version gewinnt eine direkte Owner-Kopie gegen eine indirekte Kopie.
4. Sonst ist die Version gleich und wird nicht importiert.

Konkretes Verhalten:

- älteres Relay: abgelehnt;
- neueres Relay: angenommen, auch wenn indirekt;
- gleiche Revision, beide indirekt oder beide direkt: erste gespeicherte Kopie gewinnt;
- gleiche Revision, lokales Relay und direkter Owner: direkter Owner gewinnt;
- fehlende Legacy-Revision in einem eingehenden Sync-Payload: ungültig;
- Legacy-Persistenz ohne Metadaten: beim Laden zu Version 0 oder vorhandener Record-Version rekonstruiert;
- Timestamp: kein Tie-Breaker; nur Catch-up-Watermark und Staleness.

Dezentrale Ausnahmen:

- Permission verwendet eine eigene Revision Chain und Fork-/Missing-Predecessor-Erkennung.
- Content und POI prüfen zusätzlich im Import `current.revision >= incoming.revision`.
- Achievements prüft im Store die Version nochmals.
- Live Positions vergleichen Sequence und Timestamp.

Risiko: Catch-up nutzt pro Domain einen maximalen fremden `updatedAt`-Watermark. Timestamps verschiedener Origin-Clients werden damit global verglichen. Clock-Skew kann dazu führen, dass ein späteres Objekt mit kleinerem Origin-Timestamp bei `listMetadata(since)` nicht angeboten wird, obwohl seine Revision neu ist.

## 9. Modulvergleich

| Modul/Bereich | Quelle | Snapshot | Validator | Vergleich | Commit/Store | direkte DB | Sync | Schema/Revision | Events |
|---|---|---|---|---|---|---|---|---|---|
| Equipment | WoW Inventory/Tooltip/Item APIs | Vollsnapshot | Modul + Store-Grundprüfung | Fingerprint gegen gespeicherten Block im eigenen Workflow; Store prüft erneut | `CharacterStore:SetEquipment` | nein | Character-Domain nach Store-Event | Snapshot 4; Block-Owner-Version | `HS_PLAYERDATA_UPDATED`, `HS_EQUIPMENT_UPDATED`, Owned-Event |
| Mythic+ | `C_MythicPlus`, `C_ChallengeMode` | Vollsnapshot | Modul und zusätzlicher PlayerData-Validator | SnapshotManager-Fingerprint + Store `same` | `SetMythicPlus` | nein | Character-Domain | Snapshot 3; Block-Owner-Version | entsprechende Character-Events |
| Raids | Encounter Journal + Saved Instances | Vollsnapshot plus kumulative Lifetime-Daten | Modul | SnapshotManager + Store | `SetRaidLockouts` | nein | Character-Domain | Snapshot 3; Block-Owner-Version | `HS_RAIDLOCKS_UPDATED` |
| Delves | Delves/Weekly Rewards APIs | Vollsnapshot | Modul | SnapshotManager + Store | `SetDelves` | nein | Character-Domain | Snapshot 2; Block-Owner-Version | `HS_DELVES_UPDATED` |
| Stats | Unit-/CombatRating-/Spec-APIs | Vollsnapshot | Modul | SnapshotManager + Store | `SetStats` | nein | Character-Domain | Payload Snapshot 1; Block-Owner-Version | `HS_STATS_UPDATED` |
| Professions | Profession APIs | Vollständige Liste | keiner außer API-Verfügbarkeit | nur Store-Gleichheit | `SetProfessions` | nein | Character-Domain, weil Block registriert | keine explizite Snapshot-Schema-Version; Block-Owner-Version | `HS_PROFESSIONS_UPDATED` |
| Identity | Unit/Guild/Presence | mutable Beobachtung bzw. Block | keine fachliche Validierung | Feldvergleich/Store | `CaptureCurrent`, `ObserveIdentity` | nein | Character-Domain | keine Snapshot-Version; Blockversion | `HS_CHARACTER_UPDATED` |
| Profile | UI-Eingabe | mutable Vollblock | keine | Store-Gleichheit | `SetProfile` | Account-Metadaten teils über Live-Ref | Character/Twink-Domänen | keine Schema-Version; Block-/Account-Version | `HS_PROFILE_UPDATED`, Account-Events |
| Calendar | Blizzard Calendar | nur persistierter Fingerprint-Index + unread; volle Events flüchtig | Secret-Value-Normalisierung, sonst kein Commit-Validator | eigener Fingerprint | `Database:Set` | via Database-Fassade | nein | keine Schema-/Revision | `HS_CALENDAR_UPDATED` |
| Guild roster | Blizzard Guild API | kompletter mutable Cache | strukturelle Init, keine Snapshotvalidierung | keine Gleichheitsprüfung; Version immer +1 | `GuildStore` | ja | nicht als Domain | keine Schema-ID; Record-Version | `HS_GUILD_UPDATED`, `HS_ROSTER_UPDATED` |
| Content | UI/fachlicher Service/Sync | mutable Objekte + History | ausführlicher Service-Validator | expectedRevision + Sync-Version | `ContentStore` | Store ja | `content` | Root Schema 1; Objekt-Revision | Content-/News-/Guide-Events |
| POI | UI/fachlicher Service/Sync | mutable Objekt/Tombstone | Service-Validator | expectedRevision + Sync-Version | `POIStore` | Store/Settings ja | `poi` | Root Schema 1; Objekt-Revision | POI-Events |
| Achievements | Definitionen, Evaluationen, manuelle Awards | Definitionen mutable; Award-Events append-only/correction | ausführlich | Store-Version | `AchievementStore` | Store ja | `achievements` | Root/Guild Schema 1; Store-Meta-Version | Definition/Award/Index/earned Events |
| Positions | Player position | flüchtiger Live-Snapshot | streng | Sequence+Timestamp | nur Runtime | Settings ja | live domain | keine persistente Datenversion | Position-Events |

## 10. Equipment-Pipeline

Ist-Ablauf:

```text
WoW Event
→ EventBus-Handler
→ debounced WorkflowManager Request
→ Scan
→ Validierung desselben Scans
→ Vergleich mit gespeichertem Equipment
→ Store
→ PlayerData validiert/prüft unchanged/erhöht Owner-Revision
→ Store-Events
→ SyncManager hört Owned-Event und queued Publish
```

Vorhanden: EventManager, Debounce, Task/Workflow, Scan A, Validierung, Vergleich mit letztem Store-Snapshot, Commit, Owner-Timestamp/Revision, Store, eventgetriebener Sync, Update-Events.

Fehlt gegenüber dem Zielbild: Scan B und Vergleich A==B. Der spezielle Schutz gegen plötzlich komplett leeres Equipment verlangt nur eine Wiederholung eines identischen leeren Kandidaten; für andere zwischenzeitlich instabile, aber formal vollständige Werte gibt es keine Doppel-Scan-Stabilitätsprüfung.

Equipment greift nicht direkt auf Persistenz zu. Die Revision entsteht in `PlayerData:ApplyBlock`, nicht im Modul. Ein formal valider, aber während der einzelnen slotweisen Erfassung inkonsistenter Snapshot kann gespeichert werden. Sync vor erfolgreichem Store-Commit ist nicht möglich: Publish wird erst durch `HS_PLAYERDATA_OWNED_UPDATED` nach Mutation ausgelöst. Der an `Request` übergebene `sync`-Wert steuert diesen Publish allerdings nicht; jede tatsächliche lokale Änderung publiziert.

## 11. MythicPlus, Raids, Delves und Stats

- Mythic+: Vollsnapshot. Keine History. Strenger Readiness-Validator; Store wiederholt einen Teil davon. `snapshotVersion=3`. Kein Delta. Keine A/B-Stabilität.
- Raids: Der aktuelle Zustand ist ein Vollsnapshot. `lifetime` ist ein kumulativer Unterbereich; `seen[raid:diff:boss]` dedupliziert Kills und verhindert doppeltes Hochzählen. Die gesamte kombinierte Struktur wird ersetzt. `snapshotVersion=3`.
- Delves: Vollsnapshot inklusive expliziter `unknown`-Objekte für nicht exponierte API-Felder. Keine History/Deltas. `snapshotVersion=2`.
- Stats: Vollsnapshot, keine History/Deltas. `snapshotVersion=1` im Payload, aber keine deklarierte Modul-`data.schemaVersion`.

Bei allen vier Modulen entsteht Freshness zentral als Character-Blockversion. Der Sync-Payload ist `{guid, block, data}` plus Blockmetadaten im Envelope. Die Modulvalidatoren werden nur lokal im Snapshot-Workflow ausgeführt; beim Remote-Import wird nur Mythic+ nochmals fachlich validiert. Raids, Delves und Stats akzeptieren remote grundsätzlich jede Tabelle.

## 12. Permission-/Policy-Persistenz

`PolicyState` speichert pro Guild einen State in `HolyStormDB.global.permissionStates[guildId]` und spiegelt den aktiven Zustand aus Kompatibilitätsgründen nach `global.permissions.groups/roles`, `global.filters.global` und `global.rules.global`.

Fachliches Modell:

- State: Groups, Filters, Rules, Module-Schalter, Permission-Default-Ledger.
- Revision Chain: `version`, `revisionID`, `previousRevisionID`, `changedBy`, `changedAt`, `change`, begrenzte History (100).
- Validierung: State-/Objekt-/Rule-Validierung, Systemgruppen-Invarianten, Manager-Zyklus, Berechtigungsprüfung.
- Konflikte: Duplicate, Fork, Missing Predecessor, Snapshot Mismatch, trusted Snapshot Recovery.
- Rejected-History: begrenzt auf 100.
- Sync: eigene Domain mit `freshness="revision-chain"`.

`PermissionRegistry` hält Definitionen zunächst flüchtig und schreibt Defaults bei verfügbarer Persistence in den aktiven State. `GroupManager` und `FilterManager` sind fachliche APIs. Globale Änderungen laufen über `PolicyState:CommitChange`; lokale Filter/Rules, Templates und UI-Aktivierung werden dagegen direkt im AceDB-Profil/globalen Filterbereich verändert.

Administration-UI schreibt Policy-State über Manager-/State-APIs. Es gibt in `UI/Administration` keinen direkten `HolyStorm.db`- oder `Database:GetRoot`-Zugriff. `Permissions.lua` ruft für Modulschalter und Reset öffentliche State-Methoden auf.

Der spätere DataManager kann den kompletten validierten Policy-State atomar speichern, darf aber weder Revision IDs erzeugen noch Fork-/Predecessor-/Authority-Logik ersetzen. Diese fachliche Revision Chain muss vollständig bei Policy bleiben.

## 13. Logging-Persistenz

Es existieren zwei getrennte persistente Logs:

1. Core Diagnostic Logger in `HolyStormDB.global.logs.entries`:
   - persistenter Ring Buffer, maximal 2000 Einträge;
   - Felder u. a. Level, Source, Category, Message, Context, Correlation, Timestamp;
   - kein Schema-Marker, keine Migration, keine Alters-Retention;
   - direkte DB-Bindung und direkter Clear;
   - UI-Filter/-Spalten liegen separat in `profile.logs`.
2. GuildLog in `HS_GuildLog_DB`:
   - `entries`, maximal 1000;
   - `snapshot` des letzten Rosters zum Erkennen von Join/Leave/Level/Rank/Note-Änderungen;
   - kein Schema-Marker, keine Guild-ID-Partitionierung, keine zeitbasierte Retention.

Eine zentrale Log Database im Sinn eines einheitlichen Schemas existiert nicht. Später sollten beide über DataManager-Backends laufen, aber als getrennte fachliche Schemas mit Append-/Ring-Operationen; große Logeinträge sollten nicht über generische Full-Root-Copies geschrieben werden.

## 14. UI-Persistenzverstöße

Vollständige direkte UI-Funde:

- `UI/Pages/Logs.lua:35,38,60`: direkte Initialisierung und Mutation von `HolyStorm.db.profile.logs`.
- `UI/Pages/TaskManager.lua:32,52-58,148`: direkte Initialisierung/Mutation/Löschung von Spaltenlayout.
- `UI/Pages/Options.lua:102`: vollständige AceDB-Instanz wird an AceDBOptions gegeben; die übrigen Optionspfade benutzen die Database-Fassade.
- `UI/Pages/SavedVariables.lua:107,181`: direkter, absichtlich read-only Diagnosezugriff auf Globals über `_G`.

Fassaden-, aber noch keine DataManager-Zugriffe:

- `UI/Framework/MainWindow.lua:331-347` liest/schreibt Window-State über `HolyStorm.Database`.
- `UI/Pages/Options.lua:23-73` liest/schreibt Chat-/Window-Settings über `HolyStorm.Database`.
- `UI/Character/CharacterOverview.lua:217` liest Debug-Konfiguration über `HolyStorm.Database`.

Die Administration-UI mutiert keine Store- oder DB-Tabellen direkt. Feature-nahe UI in `Profiles.lua` initialisiert jedoch eine live persistente Account-`metadata`-Tabelle direkt.

## 15. Sync-Datenfluss

Tatsächlicher generischer Eingangspfad:

```text
Comms: Chunk-Reassembly
→ HS_COMMS_MESSAGE
→ SyncManager: Deserialize + Envelope-/Sender-Prüfung
→ Domain.validate
→ Domain.authorize
→ generischer Metadata-Freshness-Vergleich
  (außer revision-chain)
→ Domain.import
→ Store-/State-Mutation und fachliche Events
→ Foreign Watermark
→ HS_SYNC_DOMAIN_UPDATED
→ optionales domain.updateEvent
```

Character-Import geht direkt zu `PlayerData:AcceptRemoteBlock`; Sync mutiert keine Character-Tabelle selbst. Andere Domains importieren in ihre Stores oder fachlichen Services. Remote-Module übernehmen Daten damit dezentral über registrierte Import-Callbacks, nicht über einen einheitlichen Persistence-Commit.

Validierung und Freshness sind zweistufig/dezentral:

- SyncManager prüft Envelope, Domain-Validator, Authority und Standard-Metadaten.
- Store/Service prüft teilweise erneut (PlayerData, Content, POI, Achievements).
- Permission überspringt Standard-Freshness und validiert die Revision Chain selbst.

Nach Remote-Import können doppelte Events entstehen: Store/Service emittiert ein fachliches Event, anschließend emittiert SyncManager `HS_SYNC_DOMAIN_UPDATED` und gegebenenfalls das `updateEvent`. Bei POI ist `HS_POI_SYNCED` sowohl im Import als auch als Domain-`updateEvent` vorhanden; bei Content wird `HS_CONTENT_UPDATED` im Import emittiert und zusätzlich `HS_CONTENT_SYNC_UPDATED` generisch. Diese Doppelung ist nicht immer derselbe Eventname, bei POI aber tatsächlich doppelt.

## 16. Schema-Inventar

| Schema-ID (heute faktisch) | Version | Owner | Speicherort | Migration | Validator | Revision | Form | Sync |
|---|---:|---|---|---|---|---|---|---|
| `holystorm-root` | 12 | Database/Migrations | `HolyStormDB.global` | Schritte 1-12 | nein | nein | mutable root | indirekt |
| `config-profile` | implizit | Config/je Feature | `HolyStormDB.profiles[*]` | AceDB defaults | feldweise kaum | nein | mutable config | nein |
| `config-char` | implizit | Database | `HolyStormDB.char` | AceDB defaults | nein | nein | mutable | nein |
| `playerdata-root` | 2 | PlayerDataStore | `HS_Player_DB` | Schritt 6/7 + Initialize | Root-Reparatur | blockweise | mixed | Character/Twinks |
| `character.identity` | keine | Character owner | `characters[guid]` | Meta-Rekonstruktion | nur table | Blockversion | mutable snapshot | ja |
| `character.equipment` | Snapshot 4 | Character owner | dito | keine | lokal ausführlich, remote nur table | Blockversion | snapshot | ja |
| `character.mythicPlus` | Snapshot 3 | Character owner | dito | Legacy tolerant | lokal + Store | Blockversion | snapshot | ja |
| `character.raid` | Snapshot 3 | Character owner | dito | keine | nur lokal | Blockversion | snapshot + lifetime | ja |
| `character.delves` | Snapshot 2 | Character owner | dito | keine | nur lokal | Blockversion | snapshot | ja |
| `character.stats` | Snapshot 1 | Character owner | dito | keine | nur lokal | Blockversion | snapshot | ja |
| `character.professions` | keine | Character owner | dito | keine | nein | Blockversion | snapshot | ja |
| `character.profile` | keine | Character owner | dito | Legacy-Feldübernahme | nein | Blockversion | mutable snapshot | ja |
| `accounts/twinks` | `twinkSchemaVersion=1` | Account owner | `HS_Player_DB.accounts` | Schritt 7 + TwinkCore | Owner/Admin-Payload | owner/admin versions | mutable snapshot + tombstones | ja |
| `guild-roster` | keine | Blizzard/local cache | `HolyStormDB.global.data.guilds` | Schritt 1 defaults | nein | Guild record version | mutable cache | nein |
| `permission-state` | State schema 6; root marker 1 | Policy | `permissionStates[guild]` | Schritt 8 + lazy UpgradeState | ausführlich | eigene Chain | state + history | ja |
| `local-rules/filters` | keine/Objektversion | FilterManager | profile rules/filters | defaults/runtime | ausführlich bei Save | Objektversion | mutable | nein |
| `templates/demands` | keine | Rules/FilterManager | global filters | Schritte 4/5/runtime | teilweise | nein | derived/config | nein |
| `content` | 1 | ContentStore/Service | global content | Schritt 9 + guild-lazy migration | ausführlich | Objekt-Revision | mutable + History(10) | ja |
| `poi` | 1 | POIStore/Service | global poi | Schritt 10 | ausführlich | Objekt-Revision | mutable/tombstone | ja, außer personal |
| `achievements` | 1 | AchievementStore/Service | global achievements | Schritt 12 | ausführlich | Store-Meta-Version | mutable definitions + append/correction events | ja |
| `calendar-state` | keine | Calendar | global guildEvents | Defaults | Fingerprint-Erzeugung | nein | snapshot-index/config | nein |
| `core-logs` | keine | Logger | global logs | Schritt 4/defaults | nein | nein | ring buffer | nein |
| `guild-log` | keine | GuildStore/GuildLog | `HS_GuildLog_DB` | nur Init | nein | nein | ring + snapshot | nein |
| `positions-live` | keine | Positions | Runtime | entfällt | ausführlich | Sequence | ephemeral | live |

## 17. Migrationen

Der zentrale Runner interpretiert `steps[n]` als Migration von `n-1` nach `n`:

| Von→Nach | Inhalt |
|---|---|
| 0→1 | Install-/Player-ID, `global.data`, alte Profiles/Owners, Kopie alter Root-Settings |
| 1→2 | Characters/Players/Owners aus `global.twinks` und flacher `HS_Player_DB`; Legacy-Profilfelder/Twinks |
| 2→3 | Permission-Role-Grundlage und Guild-Leader-Rolle |
| 3→4 | Filters, News, Logs, Permission-Gruppen |
| 4→5 | Rules, Filter-Templates/Demands, Policy/Tombstones, Systemgruppen-Aliase |
| 5→6 | `HS_Player_DB` Schema 2 wird kanonisch, Merge aus altem Global-Data |
| 6→7 | Accounts/Relationships-Aliase, lokaler Account, Admin-Tombstones, Twink-Schema 1 |
| 7→8 | Guild-scoped Permission-States und Permission-Schema-Marker |
| 8→9 | `news` nach `content.legacyNews/legacyReads`, alter `news`-Pfad wird gelöscht |
| 9→10 | POI-Root Schema 1 |
| 10→11 | keine Datenmigration; Positionen bleiben flüchtig |
| 11→12 | Achievement-Root und neue Default-Permissions in vorhandenen Policy-States |

Trigger: einmal in `Database:Initialize`, basierend auf `HolyStormDB.global.schemaVersion`.

Atomarität/Fehler:

- Jede Step-Funktion läuft in `pcall`; bei Fehler wird der Runner beendet und Bootstrap wirft einen Fehler.
- Innerhalb eines Steps gibt es keinen Rollback. Bereits erfolgte Mutationen bleiben im Live-Root.
- `global.schemaVersion` wird erst nach erfolgreichem Step gesetzt, sodass der Step beim nächsten Laden wiederholt wird.
- Es gibt kein Backup, Recovery-Journal oder Read-only-Fallback.
- Mehrere Steps mutieren gleichzeitig `HolyStormDB` und `HS_Player_DB`; ein partieller Cross-Root-Zustand ist möglich.

Dezentrale Migrationen/Reparaturen: `PlayerData:Initialize`, `TwinkCore:MigrateAccounts`, `PolicyState:UpgradeState`, `ContentStore:MigrateLegacy`, Store-Initialisierer und AceDB-Defaults. Damit liegen Migrationen aktuell nicht ausschließlich im zentralen Runner.

## 18. Schreibautorität

| Datenart | Aktuell autoritativ schreibend | Weitere tatsächliche Schreiber |
|---|---|---|
| lokale Character-Origin-Blöcke | aktueller Character über `WriteOwnedBlock` | alle Module mit Store-Zugriff können den Aufruf auslösen |
| fremde Character-Kopie | Sync/`AcceptRemoteBlock` | `ObserveIdentity` verändert zusätzlich fremde Identity ohne Owner-Revision |
| Account-Origin | `TwinkCore` für lokalen Account | `PlayerStore`-Legacyadapter, Profile-Modul über APIs/Live-Ref |
| administrative Relationships | jeder aktuell berechtigte Admin | Sync übernimmt autorisierte Kopien |
| Guild-Roster-Cache | lokaler Blizzard-Scan | keiner remote |
| globale Policy | autorisierte Actors via Policy Chain | Permission-Sync/Recovery |
| lokale Rules/Filters/Config | lokaler Benutzer/UI | FilterManager und direkte UI-/Feature-Zugriffe |
| Content/POI/Achievements | jeweils autorisierter fachlicher Actor | Sync-Importe |
| Logs | Logger bzw. GuildStore | UI darf Core-Logger leeren über Logger-API |

Verstöße gegen „nur Owner erzeugt Origin-Revisions“:

- Character-Versionen selbst werden nur bei lokalen Owner-Commits erhöht.
- `ObserveIdentity` ändert aber fremde Origin-Daten ohne neue Revision und schreibt einen lokalen Timestamp unter derselben Revision.
- Achievement-Remote-Metadaten markieren Relay-Kopien fälschlich als direkt.
- POI/Content/Achievement sind absichtlich gemeinsam editierbare Objekte; „Owner“ bedeutet dort letzter autorisierter Actor, nicht unveränderlicher Creator.

## 19. Event- und Commit-Reihenfolge

| Bereich | Reihenfolge |
|---|---|
| Character local | validate → compare → Daten/Meta mutieren → fachliche Events → Owned-Event → Sync-Publish wird durch Listener queued |
| Character remote | Sync validate/authorize/freshness → Store validate/freshness → Daten/Meta mutieren → Storeevents → Sync-Domain-Events |
| Policy local | clone/apply/validate → State-Felder ersetzen + History → Cache/Domain-Events → Sync publish |
| Policy remote | Chain anwenden oder Recovery-State ersetzen → Events; danach Sync-Domain-Events |
| Content local | validate → History append → Put → Index invalidieren → Sync publish → fachliche Events |
| POI local | validate → Put/Remove → Sync publish → fachliche Events |
| Achievement local | validate → Store Put + Storeevent → Index → Sync publish |
| Logs | Ring mutieren → Event |
| Calendar | Snapshot/Unread mutieren → Runtime-Events ersetzen → Event |

„Persistenz erfolgreich“ bedeutet heute lediglich, dass die SavedVariable-Tabelle im Speicher mutiert wurde. WoW bietet hier keinen synchronen Festplatten-Commit; geschrieben wird später durch den Client. Kein aktueller Pfad kann daher einen tatsächlichen IO-Erfolg bestätigen.

Events werden nach der jeweiligen Tabellenmutation ausgelöst, aber es gibt keine allgemeine atomare Commit-Grenze. UI kann den neuen In-Memory-Zustand in Events sehen. Bei mehrteiligen Mutationen (Policy, Twinks, Migrationen) existiert kein Rollback. POI-Sync emittiert `HS_POI_SYNCED` im Import und nochmals als Domain-Update-Event.

## 20. Data Ownership Matrix

| Bereich | Owner | Quelle | Validator | Store | Persistenz | Revision/Freshness | Sync | Schema | Events |
|---|---|---|---|---|---|---|---|---|---|
| Character Identity | Character | Unit/Guild/Presence | minimal | PlayerData/CharacterStore | HS_Player_DB | Blockversion, mit Observe-Ausnahme | character | unversioniert | Character/PlayerData |
| Equipment | Character | Inventory | Modul | CharacterStore | HS_Player_DB | Blockversion | character | 4 | Equipment |
| Mythic+ | Character | Mythic APIs | Modul + Store | CharacterStore | HS_Player_DB | Blockversion | character | 3 | Mythic+ |
| Raids | Character | EJ/instances | Modul | CharacterStore | HS_Player_DB | Blockversion | character | 3 | Raid |
| Delves | Character | Delve APIs | Modul | CharacterStore | HS_Player_DB | Blockversion | character | 2 | Delves |
| Stats | Character | Unit stats | Modul | CharacterStore | HS_Player_DB | Blockversion | character | 1 | Stats |
| Professions | Character | Profession APIs | keiner | CharacterStore | HS_Player_DB | Blockversion | character | — | Professions |
| Account/Twinks | Account/Issuer | owner proof/admin | Payloadvalidator | TwinkCore/PlayerStore | HS_Player_DB | ownerVersion/adminVersion | twinks/twinkAdmin | 1 | Account/Twinks |
| Guild cache | lokale Blizzard-Sicht | Guild roster | keiner | GuildStore | HolyStormDB | record.version | nein | — | Guild/Roster |
| Policy | fachlich autorisierter Actor | Admin/API/Sync | Policy | PolicyState | HolyStormDB | Revision Chain | permissions | State 6 | Policy/Permission |
| Local rules/filters | lokaler User | UI | Rule/Filter | FilterManager | HolyStormDB profile | object version | nein | — | Rule/Filter |
| Content | autorisierter Editor | UI/Sync | ContentService | ContentStore | HolyStormDB | revision | content | 1 | Content/News/Guide |
| POI | Creator/Editor | UI/Sync | POIService | POIStore | HolyStormDB | revision | poi | 1 | POI |
| Achievements | autorisierter Actor | UI/evaluation/Sync | AchievementService | AchievementStore | HolyStormDB | Store-meta version | achievements | 1 | Achievement |
| Calendar | lokaler Client | Calendar API | Statusnormalisierung | Database | HolyStormDB | Fingerprint only | nein | — | Calendar |
| Core logs | Logger | alle Systeme | keiner | Logger | HolyStormDB | ring order/time | nein | — | Log |
| Guild log | lokaler Client | Roster diff | keiner | GuildStore | HS_GuildLog_DB | ring order/time | nein | — | GuildLog |

## 21. Priorisierte Architekturprobleme

### P0 – Datenverlust-/Korruptionsrisiko

1. Nicht-atomare Migrationen über mehrere Live-Roots ohne Backup/Rollback (`Migrations.lua`). Ein Step-Fehler kann Teilmutationen hinterlassen.
2. Fremde synchronisierbare Identity wird durch `ObserveIdentity` unter unveränderter Owner-Version und lokalem Timestamp verändert. Relay/Beobachter können damit Origin-Daten verfälschen.
3. `AchievementStore.lua:18` speichert indirekte Remote-Metadaten wegen `... or true` immer als `direct=true`. Dadurch kann eine spätere echte Owner-Kopie derselben Version als `SAME_VERSION` abgewiesen werden.
4. Breite Live-Referenzen aus öffentlichen Gettern erlauben unvalidierte, ereignislose und unrevidierte Mutationen. Konkrete produktive Nutzer existieren bereits.

### P1 – Architektur-/Ownership-Verstoß

1. `HolyStorm.DataManager` existiert nur als ungenutzte Area-Fassade; fast alle Stores besitzen direkten Persistence-Zugriff.
2. UI (`Logs`, `TaskManager`, AceDBOptions) mutiert oder erhält direkte DB-Objekte.
3. Logger, FilterManager, TwinkCore, Positions, POI-Settings und Core-Manager greifen direkt auf `HolyStorm.db` zu.
4. Remote-Validierung ist für Character-Blöcke uneinheitlich; Raids/Delves/Stats/Equipment/Professions haben beim Import keine fachlichen Store-Validatoren.
5. Globaler timestampbasierter Domain-Watermark vergleicht Uhren verschiedener Origin-Clients.
6. Store-/Domain-Events sind dezentral und teilweise doppelt; es existiert kein einheitliches Event-after-commit-Vertrag.
7. `HS_GuildLog_DB` ist nicht nach Guild-ID partitioniert.

### P2 – Legacy-/Migration-Schuld

1. Character/Player/Owner-Daten leben kanonisch in `HS_Player_DB`, werden aber in `HolyStormDB.global.data` weiter aliasiert.
2. Migration/Reparatur ist über Runner, PlayerData, TwinkCore, Policy und Content verteilt.
3. `PlayerData:Initialize` setzt Schema 2 unconditionally; ein zukünftiger unbekannter höherer Marker würde nicht fail-closed behandelt.
4. Mehrere Schemas besitzen gar keinen Marker: Logs, GuildLog, Guild cache, Calendar, Config, Professions/Profile/Identity.
5. Policy hält zusätzlich aktive Compatibility-Spiegel in alten globalen Tables.

### P3 – Cleanup/Verbesserung

1. Ignorierte `metadata`-Parameter der CharacterStore-Setter entfernen oder korrekt typisieren.
2. Snapshot-Fingerprints nach Objekt/Owner statt nur Typ schlüsseln, falls später mehrere lokale Characters verarbeitet werden.
3. Modulmetadaten und Payload-`snapshotVersion` vereinheitlichen (Stats, Professions).
4. Zeitbasierte Log-Retention und explizite Log-Schemata ergänzen.
5. Read-APIs konsequent als Kopie/read-only View definieren.

## 22. Vorgeschlagene DataManager-Zielarchitektur

Kein zweites paralleles System aufbauen: `Persistence/Database.lua` und der vorhandene Name `HolyStorm.DataManager` sollten schrittweise zur einzigen öffentlichen Persistence-Grenze entwickelt werden.

Interne, kleine Komponenten:

- `PersistenceBackend`: alleiniger Besitzer von `HolyStormDB`, `HS_Player_DB`, `HS_GuildLog_DB` und AceDB. Liefert interne Root-Zugriffe, niemals an beliebige Module.
- `SchemaRegistry`: Schema-ID, aktuelle Version, Scope/Backend, Defaults, Validator, Copy-/Retention-Policy, Authority-/Metadata-Policy.
- `MigrationRunner`: versionierte, idempotente Copy-on-write-Migrationen mit Validierung und Recovery-Datensatz.
- `CommitCoordinator`: erwartet aktuelle Revision, validiert, erzeugt einen Draft/Copy, ersetzt den Zielblock als eine In-Memory-Operation, zeichnet Commit-Ergebnis auf und publiziert erst danach Events.
- `MetadataPolicy`: generische Blockmetadaten/Freshness für Owner-Snapshot-Domänen. Policy-Revision-Chain bleibt explizit fachlich und wird als bereits validierter State gespeichert.
- `Repositories/Stores`: fachlich benannte APIs auf dem DataManager; sie kennen Datenmodelle, aber keine Globals.
- `LogStorage`: optimierte Append-/Trim-Operationen statt generischer Root-Copies.

Wichtige Semantik:

- Reads geben standardmäßig Kopien oder explizite read-only Views zurück.
- `Commit` ist eine atomare In-Memory-Swap-Grenze. Ein echter Festplatten-Commit ist unter WoW nicht synchron bestätigbar und darf nicht behauptet werden.
- Validierung erfolgt vor dem Swap; Events und Sync-Hinweise erst danach.
- Origin-Versionen werden nur erzeugt, wenn die registrierte Authority-Policy den lokalen Client als Owner bestätigt.
- Remote-Commits übernehmen Origin-Metadaten unverändert und ergänzen getrennte Transportmetadaten (`receivedFrom`, `receivedAt`, `transportChannel`).
- Schema-Version und fachliche Revision sind getrennte Konzepte.
- History/Retention ist schemaabhängig, nicht global in einer God-Class.

## 23. Vorgeschlagene öffentliche API

Kleine stabile Kern-API:

```lua
DataManager:RegisterSchema(definition)
DataManager:Get(schemaId, key, options)                 -- defensive copy
DataManager:GetMetadata(schemaId, key)
DataManager:Commit(schemaId, key, value, context)       -- validated atomic swap
DataManager:Update(schemaId, key, mutator, context)     -- copy-on-write transaction
DataManager:Append(schemaId, key, value, context)       -- nur für registrierte append/ring schemas
DataManager:RegisterMigration(schemaId, from, to, fn)
DataManager:RunMigrations(schemaId)
```

`context` sollte mindestens Modus (`owned`, `remote`, `derived`, `config`), erwartete Revision, Actor/Owner, Origin-Metadaten und Transport-Metadaten enthalten. Rückgabe ist ein strukturiertes Ergebnis `{changed, value, metadata, commitId}` oder ein stabiler Fehlercode.

Snapshot-API:

```lua
SnapshotManager:RegisterType(id, definition)
SnapshotManager:Request(id, objectId, options)
SnapshotManager:Submit(id, objectId, snapshot, acquisitionContext)
```

Der SnapshotManager koordiniert Scan, A/B-Stabilität, fachliche Validierung und Vergleich. Erst danach ruft er intern `DataManager:Commit`. `DataManager:SubmitSnapshot` sollte nicht parallel als zweite Lifecycle-API eingeführt werden; falls der Name aus Kompatibilitätsgründen nötig ist, sollte er nur ein interner, schmaler Alias für den finalen validierten Commit sein.

## 24. Verantwortungsgrenzen

- DataManager: alleiniger Raw-SavedVariable-Zugriff, Schema-/Storage-Version, Migration, Copy-on-write-Commit, generische Metadaten, Retention, Commit-Ergebnis und post-commit Event.
- SnapshotManager: Acquisition-Lifecycle, Debounce-Workflow-Integration, Scan A/B, fachliche Snapshotvalidierung, Gleichheit/Stabilität; keine direkte Persistence.
- Stores: fachlich strukturierter Zugriff auf committed Daten, domainbezogene Queries und Kommandos; keine Globals und keine frei veränderbaren Roots.
- SyncManager: Envelope, Transport, Discovery, Source-Auswahl; keine fachliche Revisionserzeugung und keine direkte Persistence.
- TaskManager/WorkflowManager: Ausführungskoordination, Retry/Debounce/Conditions; keine fachliche Datenentscheidung.
- EventManager: Ereignisverteilung; Commit-Events nur aus dem Commit-Ergebnis heraus.
- Module: Datenerfassung, fachliche Interpretation und Validatoren; keine SavedVariables.
- Policy: Authority und eigene Revision Chain; DataManager speichert das validierte Ergebnis, ersetzt die Chain nicht.

## 25. Konkreter Migrationsplan

### Phase 1 – Contract und Schutznetz

- vorhandenen `HolyStorm.DataManager`-Namen übernehmen;
- Schema-/Commit-Ergebnis-Typen und Backend-Grenze definieren;
- keine Pfade verschieben;
- statischen Test einführen, der neue Raw-Global-/`HolyStorm.db`-Zugriffe außerhalb einer Allowlist verhindert;
- Failure-/Rollback-Tests mit In-Memory-Backend ergänzen.

### Phase 2 – bestehende Database-Fassade integrieren

- `Database` intern zum einzigen Besitzer von AceDB/Globals machen;
- `ConfigManager`, MainWindow und Options auf defensive DataManager-Config-APIs legen;
- `GetRoot`/`GetArea` als intern/deprecated markieren, noch nicht entfernen.

### Phase 3 – risikoarme Persistenzbereiche

- UI-Settings von Logs/TaskManager/POI/Positions migrieren;
- Core Logger und GuildLog als Ring-Schemas integrieren;
- Calendar-State über ein kleines Schema führen;
- Pfade und Datenformate unverändert lassen.

### Phase 4 – Character/PlayerData gemeinsam

- `HS_Player_DB` als Backend registrieren, ohne Keys zu verschieben;
- `PlayerDataStore` auf CommitCoordinator umstellen;
- defensive Reads einführen und konkrete Live-Ref-Nutzer vorher migrieren;
- Identity-Beobachtung in `observedIdentity` oder derived cache trennen;
- Character-Blockvalidatoren und schemaVersion-Metadaten registrieren;
- Achievement-`direct`-Fehler unabhängig vor bzw. spätestens hier korrigieren.

### Phase 5 – Accounts/Twinks/PlayerStore

- Account-/Relationship-Operationen atomar über Store/DataManager;
- Owner- und Admin-Versionen unverändert beibehalten;
- Legacy-Aliase nur noch im Backend erzeugen;
- Remote-Provenance um getrennte Transportmetadaten ergänzen.

### Phase 6 – SnapshotManager und Feature-Module

- finalen Commit an DataManager koppeln;
- Equipment A/B-Scan ergänzen;
- Mythic/Raid/Delves/Stats/Professions auf registrierte Snapshot-Typen vereinheitlichen;
- Publish ausschließlich nach erfolgreichem Commit-Ergebnis.

### Phase 7 – Policy und Rules/Filters

- Policy-State als fachlich versioniertes opaque Schema atomar speichern;
- Revision Chain unverändert lassen;
- lokale Rules/Filters/Templates und Compatibility-Spiegel hinter Store/DataManager ziehen;
- UI bleibt auf Policy-/Manager-APIs.

### Phase 8 – Content, POI, Achievements und Guild-Cache

- bestehende fachliche Validatoren/Revisionen als Schema-Hooks registrieren;
- Histories/Tombstones/Retention explizit machen;
- doppelte Sync-Events bereinigen;
- Guild-ID-Partitionierung für GuildLog migrationssicher planen.

### Phase 9 – Enforcement und Legacy-Abbau

- Raw-Zugriffe außerhalb Backend entfernen;
- öffentliche Live-Root-Getter entfernen;
- Aliase erst nach mindestens einer stabilen, rückwärtskompatiblen Release-Phase abbauen;
- unbekannte höhere Schemas fail-closed/read-only behandeln.

## 26. Backward Compatibility und Teststrategie

### Kompatibilität

- Zunächst dieselben drei Globals und dieselben Pfade weiterverwenden.
- Bestehende Daten in place lesen; keine Big-Bang-Verschiebung.
- Vor jeder strukturellen Migration Deep-Copy in einen Recovery-Block mit alter Version und Prüfsumme; erst validierten neuen Root tauschen.
- Migrationen idempotent und pro Schema/Block journalisiert machen.
- Unbekannte Felder erhalten, solange der Validator sie nicht explizit verwirft.
- Bei ungültigem Block nur den Block isolieren; übrige DB lesbar halten.
- Bei unbekannter höherer Schema-Version nicht downgraden, sondern read-only/fail-closed mit Diagnose.

### Erforderliche Tests

1. Clean install aller drei Globals.
2. Bestehende aktuelle DB ohne Datenänderung.
3. Jede relevante Legacy-Form: alter HolyStormDB-Root, flache `HS_Player_DB`, v1/v2 PlayerData, alte Twinks, Roles/Groups, News.
4. Malformed block bei intaktem Rest-Root.
5. Jede Schema-Migration einzeln und als Kette.
6. Fehler mitten in Migration: alter Root bleibt vollständig aktiv.
7. Valider, invalider und unveränderter Snapshot.
8. Equipment A/B gleich und A/B ungleich.
9. Neue lokale Owner-Revision genau +1.
10. Stale Remote-Revision.
11. Neuere Relay-Revision mit unveränderten Origin-Metadaten.
12. Gleiche Revision: Relay gegen Relay, Owner gegen Relay, abweichender Payload-Hash.
13. Fehlende Legacy-Revision und unbekannte höhere Schema-Version.
14. Policy Missing Predecessor, Fork, vollständige Chain und trusted Recovery.
15. Transaction-Validator-, Mutator- und Event-Fehler mit Rollback.
16. simulierte Backend-/Persistence-Fehler vor Swap.
17. Event exakt einmal und nur nach Commit; Sync nie vor Commit.
18. Reload-Recovery nach vorbereiteter, aber nicht abgeschlossener Migration.
19. statische Architekturprüfung: Raw-Globals und `HolyStorm.db` nur im Backend.
20. Defensive-Read-Test: Mutation einer Rückgabe ändert Persistenz nicht.

Aktueller Teststatus: Alle 27 vorhandenen `tools/test_*.lua`-Programme laufen erfolgreich. Vorhanden sind gute Happy-Path-Tests für PlayerData/Sync, Twinks, Policy, Equipment, Mythic+, Raids, POI, Content, Achievements, Logs und Workflows. Die oben genannten Failure-, Rollback-, Reload- und statischen Enforcement-Fälle fehlen.

## Empfehlung für den ersten anschließenden Implementierungsprompt

Der nächste Schritt sollte ausschließlich Phase 1 umsetzen und noch keinen Store migrieren:

> Implementiere im bestehenden Holy-Storm-Repository den DataManager-Core-Contract als evolutionäre Erweiterung des bereits vorhandenen `HolyStorm.DataManager` in `Persistence/Database.lua`. Keine SavedVariable umbenennen oder verschieben, keine bestehende Migration ausführen/verändern und noch keinen Feature-Store migrieren. Führe eine interne Backend-Grenze für die drei vorhandenen Globals, eine Schema-Registry, strukturierte Commit-Ergebnisse und einen testbaren Copy-on-write-Transaktionskern mit Validate-before-swap und Event-after-commit ein. Bestehende `Database`-/`ConfigManager`-APIs müssen kompatibel bleiben. Ergänze In-Memory-Tests für erfolgreichen Commit, unchanged, Validierungsfehler, erwartete Revision, Mutatorfehler/Rollback, Eventreihenfolge und eine statische Allowlist-Prüfung für neue direkte `HolyStormDB`/`HS_Player_DB`/`HS_GuildLog_DB`/`HolyStorm.db`-Zugriffe. Produktive Stores bleiben in diesem Schritt unverändert.

Damit entsteht zuerst ein belastbarer Zielvertrag und ein Schutznetz, ohne bestehende SavedVariables oder fachliche Revisionen anzutasten.

## 27. Phase 1 – implementierter Core-Contract

### Ausgangszustand des DataManager-Stubs

Vor Phase 1 lag `HolyStorm.DataManager` ausschließlich in `Persistence/Database.lua` und delegierte `RegisterArea`, `GetArea` und `Set` direkt an `Database`. Repositoryinterne Aufrufer gab es nicht. Der Stub war kein registriertes Modul und besaß daher keinen `ModuleRegistry`-Metadatenvertrag, keine Lifecycle-Methode und keine eigenen Initialisierungsabhängigkeiten. In der TOC-Reihenfolge lud `Database.lua` nach `Schema.lua` und `Migrations.lua` sowie nach Logger und EventBus, aber vor allen Stores. Sein Verhältnis zu Stores war nur die indirekte Character-Area-Abhängigkeit von `Database:GetArea` auf `CharacterStore`, die erst bei einem späteren Methodenaufruf aufgelöst wurde. Direkte Verantwortlichkeit für Schema, Validation, Migration oder Commit bestand nicht.

Phase 1 entwickelt genau diese vorhandene Instanz in derselben Datei weiter. `Database` bleibt zunächst Low-Level-AceDB-Backend; es wurde weder eine zweite Database-Schicht noch eine zweite DataManager-Instanz angelegt. `DataManager.version` und `contractVersion=1` bilden den Core-Vertrag, ohne daraus ein Feature-Modul zu machen. Die bestehende TOC-Reihenfolge ist ausreichend: alle Methoden werden erst nach vollständigem Addon-Load aufgerufen, Logger/EventBus sind dann verfügbar, und kein Feature muss vor DataManager laden.

### Öffentlicher Vertrag

```lua
DataManager:RegisterSchema(definition)
DataManager:RegisterMigration(schemaId, fromVersion, toVersion, migrate)
DataManager:RunMigrations(schemaId, context)
DataManager:Get(schemaId, key)
DataManager:GetCopy(schemaId, key)
DataManager:Exists(schemaId, key)
DataManager:GetMetadata(schemaId)
DataManager:SafeCopy(value)
DataManager:Commit(schemaId, key, value, context)
DataManager:Update(schemaId, key, mutator, context)
DataManager:Transaction(schemaId, key, mutator, context)
```

`key` ist `nil` für den gesamten Schema-Root, ein String/eine Zahl für einen direkten Key oder eine Segmentliste für einen verschachtelten Key. Mutationsergebnisse verwenden einheitlich `ok`, `changed`, `operation`, `schema` und `version`; Fehler ergänzen `errorCode` und `error`, Migrationen zusätzlich `fromVersion`/`toVersion`. Der Core erzeugt keine UI-Texte.

Die Schema-Definition verlangt `id`, `owner`, positive ganzzahlige `version`, `validate` und `storage`. Optional sind `default`, `metadata`, `event`, `versionField` und eine Liste initialer Migrationen. Storage bindet an `database` mit AceDB-Scope/Pfad oder an die vorbereiteten Root-Backends `player` und `guildLog`. Schemata sind nicht im Core hardcodiert. Registrierung kopiert Metadaten, liest keine Live-Daten, materialisiert keine Defaults und startet keine Migration.

Migrationen sind eindeutig je Schema und Ausgangsversion, nur vorwärts und nur als zusammenhängende Schritte `n → n+1` registrierbar. `RunMigrations` liest explizit, kopiert vollständig, führt alle Schritte ausschließlich auf dem Draft aus, schreibt die technischen Versionsmarker dort fort, validiert den endgültigen Stand und ersetzt erst dann den Schema-Root. Callback-, Pfad-, Copy- oder Validation-Fehler lassen Tabellenidentität und Inhalt des Live-Roots unverändert. Die vorhandene globale Migration in `Migrations.lua` wurde mangels eines im Audit belegten risikoarmen Pilotkandidaten nicht umgestellt und läuft weiterhin ausschließlich im bestehenden `Database:Initialize`-Pfad.

`SafeCopy` unterstützt primitive SavedVariable-Werte, verschachtelte Arrays, Maps, gemischte Tabellen und azyklisch gemeinsam referenzierte Tabellen. Metatables werden absichtlich nicht kopiert. Funktionen, Threads, Userdata, Tabellenschlüssel, Zyklen und eine Tiefe über 128 werden strukturiert abgelehnt. Öffentliche DataManager-Reads liefern immer solche Kopien; nur `Update`/`Transaction` erhalten einen internen Draft. Defaults werden erst für eine Mutation erzeugt, niemals durch `Get`.

`Commit`, `Update` und `Transaction` kopieren den gesamten Schema-Root, validieren Schema-Version und Owner-Validator vor dem Austausch und geben auch Ergebniswerte nur als Kopie zurück. Ein optionales schemaeigenes Event wird genau nach einem erfolgreichen geänderten Swap emittiert; Phase 1 führt kein globales neues Event ein. Validation-, Migration-, Transaction-, Schema-Konflikt- und Pfadfehler werden über `Logger:Write` mit Schema, Version, Operation, Error Code und Detail protokolliert. Die technische Schema-Version ist ausdrücklich keine Character-Owner-Revision und keine Policy-Revision.

Die alten Kompatibilitätsmethoden `RegisterArea`, `GetArea` und `Set` bleiben erreichbar. `DataManager:GetArea` liefert jetzt defensiv und materialisiert beim Lesen keine Defaults; `Database:GetArea` und der Legacy-Write bleiben bis zu ihrer späteren Migration unverändert.

## 28. Verbleibende öffentliche mutable Persistenz-Getter

Phase 1 ändert diese Oberflächen bewusst noch nicht. „Aufrufer“ nennt repräsentative produktive Konsumenten; dynamische/externe Nutzer sind zusätzlich möglich.

| Datei / Funktion | Live-Datentyp | Aktuelle Aufrufer | Risiko | Empfohlene spätere Migration |
|---|---|---|---|---|
| `Persistence/Database.lua` – `Database:GetRoot` | vollständiger AceDB-`global`/`profile`/`char`-Root | `PolicyState:GetPersistenceRoot`, `PermissionSync:Initialize`, intern ConfigManager | beliebige Mutation ohne Validator/Commit/Event | Phase 2: intern/deprecated machen; registrierte Config-/Policy-Schemas verwenden |
| `Persistence/Database.lua` – `Database:Get`, `Database:GetArea`; `ConfigManager:Get` | beliebiger persistenter Teilbaum/Area | Chat, MainWindow, Options, Calendar und externe Compatibility-Nutzer | Tabellenwerte bleiben live; `Database:GetArea` materialisiert zudem Defaults | Phase 2/3: defensive Config-Reads und `Update` für Window/Chat/Calendar/Area |
| `Persistence/PlayerDataStore.lua` – `GetRoot`, `GetCharacters` | kompletter `HS_Player_DB`-Root beziehungsweise Character-Map | CharacterStore, SyncManager, TwinkCore, `HolyStorm:GetPlayerDatabase` | breiteste Umgehung von Blockvalidator, Owner-Version und Events | Phase 4: `playerdata-root` registrieren; Queries kopieren; interne Repository-Kommandos |
| `Persistence/PlayerDataStore.lua` – `GetCharacter`, `GetOrCreateCharacter` | Character-Record | CharacterStore; TwinkCore schreibt `playerId` direkt | unversionierte Feldmutation und implizite Erzeugung durch Getter | Phase 4: reiner Copy-Read plus explizite atomare Character-Kommandos |
| `Persistence/PlayerDataStore.lua` – `GetPlayers`, `GetOwners` | Account-Map und Character→Account-Map | PlayerStore, TwinkCore | Relationship-/Accountänderung ohne fachlichen Commit | Phase 4/5: gemeinsame Root-Transaction; danach defensive Reads |
| `Persistence/PlayerDataStore.lua` – `GetBlock` | bei Einfeld-Blöcken direkter Blockwert; bei Mehrfeld-Blöcken Kopie | CharacterStore, SyncManager, Feature-Regelprovider | uneinheitliche Copy-Semantik; Einfeld-Block kann live mutiert werden | Phase 4: immer defensive Kopie, Export intern aus validiertem Read |
| `Persistence/CharacterStore.lua` – `GetAll`, `Get`, `GetOrCreate`, `GetEquipment`, `GetRaidLockouts`; globale Compatibility `GetPlayerDatabase` | Character-Maps, Records und Blocktabellen | Chat, RichContent, Permissions, Achievement/UI, Feature-Seiten, Bootstrap | sehr viele Konsumenten können Blockrevision und Sync umgehen | Phase 4: Konsumenten auf Copy-Queries umstellen, Erzeugung nur über Commands |
| `Persistence/PlayerStore.lua` – `GetAll`, `Get`, `Create` sowie Aliase `GetProfiles`, `GetProfile`, `CreateProfile` | Account-Map/Account-Record | Profiles, Twink-/Permission-Kontext, Legacy-Nutzer | Profile initialisiert `metadata` direkt; Create gibt Schreibzeiger aus | Phase 5: Account-Queries defensiv, Metadata/Relationship als Commands |
| `Persistence/GuildStore.lua` – `GetAll`, `Get`, `GetCurrent` | Guild-Map/Guild-Record/Roster | Permissions, Policy, Chat, Content, Positions, Achievements | Roster/Guild-Version kann ohne Refresh-Commit verändert werden | Phase 3 oder 8: Guild-Cache-Schema und reine Query-Daten |
| `Persistence/GuildStore.lua` – `GetLogDatabase` | kompletter `HS_GuildLog_DB`-Root | GuildStore/GuildLog-Pfade | Entries/Snapshot ohne Ring-/Retention-Grenze mutierbar | Phase 3: eigenes Append-/Snapshot-Schema, kein Full-Root-Getter |
| `Persistence/ContentStore.lua` – `GetRoot`, `GetGuild`, `Get`, `GetIndex`, `GetEntries` | Content-Root, Guild-State, Entry-/Index-Maps | News/Content-Service und UI | Revision, History und Index können getrennt manipuliert werden | Phase 8: Content-Schema atomar; Query-Kopien, Commands behalten Fachvalidator |
| `Persistence/POIStore.lua` – `GetRoot`, `GetBucket`, `Get`, `GetAll` | POI-Root/Buckets/Entries | POIService, POIMap | `GetAll` ist neue Liste, enthält aber live Entry-Tabellen | Phase 3/8: defensive Entry-Queries; Put/Remove über Schema-Transaction |
| `Persistence/AchievementStore.lua` – `GetRoot`, `GetGuild`, `GetObject`, `GetDefinition`, `GetDefinitions`, `GetEvents`, `GetAwardsFor`, `IsEarned` | Achievement-State, Definitionen, Events und Awards | AchievementService, Index, UI, Sync | Definition/Events/Meta können außerhalb `Put` auseinanderlaufen; Awards in Ergebnislisten bleiben live | Phase 8: defensive Queries und atomarer Definition-/Event-Commit |
| `Core/Permissions/PolicyState.lua` – `GetStates`, `GetState`, `GetStateStore`, `GetStore` | Policy-State und Groups/Rules/Filters | Permission-/Group-/Filter-Komponenten, Compatibility-Fassaden | direkte Mutationen können Revision Chain umgehen | Phase 7: intern trennen; DataManager speichert nur den durch Policy validierten Gesamtstate atomar |

Der neue `tools/test_persistence_boundary.lua` hält die heutige Raw-Zugriffsmenge pro Produktdatei als explizite Übergangs-Allowlist fest. Neue Dateien oder zusätzliche Vorkommen von `HolyStormDB`, `HS_Player_DB`, `HS_GuildLog_DB` oder `HolyStorm.db` schlagen fehl. Die Allowlist ist keine Freigabe der Altzugriffe, sondern eine monoton abzubauende Baseline.

## 29. P0-Nachprüfung nach Phase 1

### Fremde Identity ohne Owner-Revision

Der Befund bleibt bewusst ungelöst und ist erneut verifiziert:

1. `PlayerDataStore.lua:ObserveIdentity` schreibt fremde Identity-Felder direkt in den Character-Record, übernimmt die vorhandene `blockMeta.identity.version` unverändert, setzt aber `updatedAt` neu und emittiert Update-Events.
2. `CharacterStore:Upsert` ruft diesen Pfad für nicht lokal besessene GUIDs auf; `GuildStore:RefreshFromBlizzard` liefert dafür Guild-Roster-Beobachtungen.
3. `SyncManager:Receive` ruft ihn für Presence/`lastSeen` auf.
4. `TwinkCore:MergeOwnerSnapshot` schreibt zunächst Owner-Mapping und `playerId` live und ruft danach `ObserveIdentity` mit synchronisierter kompakter Identity auf.

Der Phase-1-Contract kann den späteren Root über das vorbereitete `player`-Backend atomar ersetzen und auf einem Draft validieren. Der nächste Character-Schritt muss jedoch zuerst fachlich entscheiden, ob beobachtete Werte in einen getrennten `observedIdentity`-/Presence-Cache gehören oder ausschließlich als echte Owner-Version über `AcceptRemoteBlock` übernommen werden. Ohne diese Entscheidung darf DataManager keine neue Identity-Revision erzeugen.

### Achievement-`direct`-Provenance

Der vollständige Datenfluss wurde erneut geprüft: `SyncManager:OnPayload` berechnet `meta.direct` als `senderGuid == meta.owner`; `AchievementService:Import` reicht dieses Meta unverändert an `AchievementStore:Put`; dort wandelte `remoteMeta and remoteMeta.direct or true` den gültigen Wert `false` wegen Lua-Wahrheitslogik in `true` um. Der Fix ist klein und isoliert und wurde deshalb in Phase 1 vorgenommen: `remoteMeta == nil or remoteMeta.direct == true`. Lokale Writes bleiben direkt, Remote-Owner-Writes übernehmen `true`, Relay-Writes behalten `false`. Ein Regressionstest deckt Relay und lokalen Write ab. Es wurde kein Achievement-Schema und kein Store-Umbau vorgenommen.

## 30. Phase-1-Abgrenzung und verbleibende Risiken

Bereits gelöst sind der neue Core-Vertrag, Schema-/Migration-Registry, Copy-on-write-Rollback für alle über den neuen Runner ausgeführten Migrationen, defensive DataManager-Reads, validate-before-swap, strukturierte Resultate/Logs, schemaoptierte Events nach Commit sowie die Raw-Access-Baseline. Keine SavedVariable wurde umbenannt oder verschoben; Registrierung allein verändert keine Daten.

Bewusst nicht migriert sind bestehende `Migrations.lua`-Schritte, PlayerData-/Character-/Snapshot-/Equipment-/MythicPlus-/Raid-/Delve-/Stats-/Calendar-/Policy-/Logging-/Sync-Systeme und ihre oben inventarisierten Live-Getter. Daher bleiben nicht atomare Legacy-Migrationen und direkte Mutationen außerhalb des neuen Vertrags Risiken. Ein In-Memory-Swap ist außerdem kein synchron bestätigter Festplatten-Commit; WoW serialisiert SavedVariables erst später. Root-Swaps des vorbereiteten `player`-Backends dürfen erst verwendet werden, nachdem die heutigen Cross-Root-Aliase und gehaltenen Store-Referenzen gemeinsam migriert wurden.

Der nächste kleine Migrationsschritt sollte Phase 2 auf einen eng begrenzten AceDB-Configbereich anwenden, beispielsweise `profile.window` oder `profile.chat`: Schema registrieren, aktuelle Pfade unverändert lassen, konkrete UI-Leser auf defensive Reads und einen einzigen Writer auf `Update` umstellen. Parallel dazu sollte das Identity-Problem als separater fachlicher Hotfix spezifiziert werden; es ist kein geeigneter erster generischer DataManager-Pilot.
