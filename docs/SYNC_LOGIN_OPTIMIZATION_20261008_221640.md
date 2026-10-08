# Abschlussbericht: Login-Sync-Optimierung

**Zeitstempel:** 08.10.2026, 22:16 Europe/Berlin

**Repository / Branch:** Holy Storm, `main`

**Ausgangsstand:** `e7660e1764a6bf17083f296e5478de6fbc6114ab`

## Ausgangsproblem und Audit

`RunLoginPresence()` sendete beim Login eine Presence mit Add-on-Version und Session-ID und rief danach `RunCatchUp()` auf. `RunCatchUp()` startete `Discover` für jede geladene Domain, deren `catchUp`-Option nicht `false` war. Die beim Audit registrierten persistenten Domains waren `character`, `permissions`, `twinks`, `twinkAdmin`, `content`, `achievements`, `guildLog`, `guildAbsences`, `guildActivityPoints`, `guildNotes` und `guildActivity`. `poi` und `guild-position` waren bereits von diesem globalen Catch-up ausgenommen.

Zusätzliche redundante Discovery-Pfade waren Achievements bei `PLAYER_ENTERING_WORLD` und `HS_GUILD_UPDATED`, POI-Startup, `News:OnEnable()` sowie `GuildManagement:OnEnable()` für Notes, Absences und Activity. `CharacterScanManager:BeginLogin()` setzte beim Login nur Scan-Zustände zurück und startete selbst keine Character-Producer-Scans.

Separat davon aktiviert das Positions-Feature bei aktivierter, erlaubter Freigabe seine Live-Positionserfassung und eine auf `guild-position` begrenzte Discovery. Diese optionale Live-Funktion bleibt bestehen; sie ist kein persistenter Catch-up über alle Domains. POI behält nur den Resync der aktuellen Gruppen-/Raid-Sitzung.

## Neuer Login- und Datenfluss

```text
PLAYER_LOGIN
  -> minimale Guild-PRESENCE mit Version und Session-ID
  -> kleines Manifest verfügbarer Owner-Revisionen
  -> lokaler Vergleich durch den Empfänger
  -> Fetch-Bedarf nur für fehlende oder neuere Remote-Revisionen
  -> 0,75 Sekunden Requests derselben Revision sammeln
  -> ein Empfänger: Whisper
  -> mehrere Empfänger: Guild-Transfer nur bei gemeinsamer Berechtigung
```

Die Presence enthält Version, Session-ID, die bestehende Reply-Anforderung und ein Manifest der Revisionen. Die verlässliche Sender- und Character-Identität bleibt im bestehenden Envelope. Es werden keine Character-Snapshots, Equipment-, Raid-, Mythic+-, Delves- oder Achievement-Payloads in die Presence gelegt. Pro Manifest sind höchstens 64 Einträge erlaubt.

Der Core erzeugt Manifest-Einträge aus verfügbaren, aktivierten, lokal owner-kontrollierten Character-Blöcken. Ein Eintrag enthält Domain, Objekt-ID, Owner, Version und optionale Revisions-/Schema-Kopfwerte. Er enthält weder Snapshot noch Nutzdaten oder Historie. Weitere Domains können denselben zentralen `listManifest`-Vertrag registrieren, ohne eine Abhängigkeit des Core auf optionale Add-ons zu erzeugen. Unbekannte Domains werden in höchstens 256 Einträgen bis zum bestehenden Presence-TTL vorgemerkt und nach Registrierung des Moduls geprüft.

Der Empfänger vergleicht die angekündigte Revision mit seinem lokalen Domain-Metadata-Stand und verwendet weiterhin `PlayerData:CompareMetadata` sowie die Freshness-Regeln der Domain. Gleicher Owner, gleiche Version und gleiche Revision lösen keinen Fetch aus. Ist der lokale Stand neuer, wird nichts angefordert. Ein fehlender Snapshot oder eine neuere Remote-Revision erzeugt eine normale `QueueFetch`-Aufgabe. Revision-Chain-Domains behalten ihre Ketten- und Konfliktregeln.

## Request-Coalescing und Übertragungsentscheidung

Requests für dieselbe Domain, Objekt-ID, Owner, Version und Revision werden 0,75 Sekunden in der bestehenden Sync-Job-Queue gesammelt. Es gibt keine zweite Netzwerkqueue. Pro Batch sind höchstens 64 Empfänger und pro Empfänger vier Request-IDs gespeichert; die gemeinsame Sync-Queue bleibt auf 20.000 Jobs begrenzt.

Ein Empfänger bekommt genau einen gezielten Whisper. Bei mehreren Empfängern kommt ein einmaliger Guild-Transfer nur infrage, wenn alle Anfragenden aktuell online im Guild-Roster stehen und die Domain die gesamte Online-Zielgruppe ausdrücklich freigibt, jedes Online-Mitglied die `canShare`-Prüfung besteht oder die Domain für Guild-Broadcasts freigegeben ist. Bei unbekanntem Online-Status, fehlender Roster-Identität oder unterschiedlicher Privacy-Berechtigung wird nicht gebroadcastet; autorisierte Empfänger bekommen gezielte Whispers. Rechte und aktuelle Owner-/Versions-/Revisionsmetadaten werden vor dem Export erneut geprüft. Ein Relay behält den originalen Owner bei.

Ohne Fetch-Anfrage wird kein Payload-Export gestartet. Wenn bei der erneuten Autorisierungsprüfung kein Empfänger übrig bleibt, wird der Payload unterdrückt und strukturiert protokolliert.

## Entfernte und bedarfsabhängige Discovery-Pfade

- `RunLoginPresence()` ruft `RunCatchUp()` nicht mehr auf. Der Legacy-Einstieg `RunCatchUp()` protokolliert `LOGIN_CATCHUP_SUPPRESSED` und erzeugt keine Discovery-Aufgaben.
- Achievement-Discovery bei `PLAYER_ENTERING_WORLD` und `HS_GUILD_UPDATED` wurde entfernt. Die Achievement-Seite synchronisiert beim Öffnen; eine manuelle Refresh-Aktion ist verfügbar.
- News/Content, POI und Guild Management synchronisieren beim Öffnen der zugehörigen Seite beziehungsweise beim Auswählen des Funktionsbereichs.
- Character Overview prüft beim Wechsel auf einen Remote-Tab nur die in diesem Tab deklarierten Character-Blöcke beziehungsweise dessen optionalen Sync-Bereich.
- Die permission-gesteuerte Live-Positionserfassung und der aktuelle Gruppen-/Raid-POI-Resync bleiben auf ihre jeweilige Domain begrenzt.

## Presence-Heartbeat

Der periodische Heartbeat mit etwa 180–240 Sekunden Abstand wurde entfernt. Der Blizzard-Guild-Roster liefert den Online-Status. Versionserkennung läuft über die Login-Presence und angeforderte Presence-Antworten; die bisherige Ablaufzeit für Peer-Versionen bleibt bei 300 Sekunden. `RunPresenceHeartbeat()` bleibt als expliziter Einmal-Aufruf verfügbar, startet aber weder einen Catch-up noch einen weiteren Heartbeat.

## Geänderte Dateien

- `LIVE/Holy_Storm/Sync/SyncManager.lua` und `LIVE/Holy_Storm/Sync/ARCHITECTURE.md`
- `LIVE/Holy_Storm/Locales/enUS.lua`, `LIVE/Holy_Storm/Locales/deDE.lua`
- `LIVE/Holy_Storm_Achievements/AchievementService.lua`, `LIVE/Holy_Storm_Achievements/Achievements.lua` sowie deren `enUS`-/`deDE`-Locales
- `LIVE/Holy_Storm_Characters/UI/CharacterOverview.lua`, `LIVE/Holy_Storm_Characters/UI/CharacterUI.lua`
- `LIVE/Holy_Storm_Guild/GuildManagement.lua`, `LIVE/Holy_Storm_Guild/UI/GuildManagementUI.lua`
- `LIVE/Holy_Storm_News/News.lua`, `LIVE/Holy_Storm_POI/POI.lua`, `LIVE/Holy_Storm_POI/POIService.lua`
- `SYNC_ARCHITECTURE.md`
- Regressionen: `tools/test_sync_login_manifest.lua`, `tools/test_sync_idle.lua`, `tools/test_sync_activity.lua`, `tools/test_sync_v2.lua`, `tools/test_guild_roster_presence.lua`, `tools/test_achievements.lua`, `tools/test_character_ui.lua`, `tools/test_poi.lua`

## Tests und Ergebnisse

- Vollständige Lua-Regression: **84 Testdateien bestanden**.
- Lua-Syntaxprüfung: **22 geänderte Lua-Dateien bestanden**.
- Locale-Parität und statische Locale-Referenzen: bestanden.
- `git diff --check`: bestanden.
- Die Regressionen prüfen Presence ohne globalen Catch-up, Manifest-Frische, optionale/unbekannte Domains, bounded Queues und Request-Coalescing, Whisper-/Broadcast-Routing, Privacy-Verweigerung, Achievement-Loginpfade, Character-Tab-Bedarf, unveränderte Owner-Provenance sowie die bestehenden PlayerData- und HSC1/AceCommQueue-Verträge.

## Commits und Push

- `e0cef6d` — `Optimize login sync and coalesce payload demand` — auf `origin/main` gepusht.
- Dieser Bericht wird als separater Dokumentations-Commit nach dem bereits erfolgreichen Source-Push gepusht.
- Kein Tag und kein Release erstellt.
- Die vorhandene Änderung an `WoW Addon - Holy Storm.code-workspace` wurde nicht gestaged oder in den Commit aufgenommen.

## Noch offene Retail-Ingame-Prüfungen

Es gab in dieser Umgebung keinen laufenden WoW-Retail-Client. Ingame zu prüfen sind zwei oder mehr Clients im selben Guild-Roster, tatsächliches HSC1-/ChatThrottleLib-Verhalten beim Login, ein einzelner Whisper gegenüber einem erlaubten gemeinsamen Guild-Transfer, zielgerichtete Whispers bei abweichenden Privacy-Rechten, das Laden einer optionalen Domain nach Empfang ihres Manifests sowie die freigegebene Live-Positionsfunktion.
