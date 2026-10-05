# Abschlussbericht: Options, Spielerprofil und Equipment

## Abschlussdaten

- Zeit: 2026-10-05 22:15:20 Europe/Berlin
- Repository/Branch: Holy Storm, `main`
- Ausgangscommit: `d9f0ae489ae4652c1b41ef7a3d2d0302fd5fbb44`
- Implementierungscommits, beide auf `origin/main`:
  - `80264c8c3a1297cf1e4b1a2de90a03e2a8e79c78` — zentrale Settings, Commands und Spielerprofil
  - `b72191cdb6fb449923d4793d19c12d4e5fb2b0c0` — Socket-Scan nur nach erfolgreichem Einsetzen
- Es wurde kein Tag und kein Release erstellt.

## Ausgangslage

Die zentrale Holy-Storm-Optionsseite und AceDB-Profile waren vorhanden. POI-Einstellungen und Teile der Positionskonfiguration verwendeten jedoch noch eigene oder modulnahe Speicherpfade. Es gab keinen gemeinsamen Vertrag für lokale Settings und keine zentrale Command-Registry für die UI-Einstiege. Der bisherige Characters-Bereich zeigte Account- und Profilfunktionen, hieß nach außen aber weiterhin „Characters“.

## Implementierte Architektur

- Die Optionsseite bleibt die einzige Heimat für Nutzeroptionen. Feature-Module registrieren Optionsgruppen zentral; das bestehende AceDB/AceDBOptions-Profil bleibt bestehen.
- `Settings` speichert persönliche, nicht synchronisierte Werte in `HolyStormDB.global.localSettings`. Unterstützte Scopes: Charakter, Account/Global, konkrete Gilde und alle Gilden. Auflösung: Gilde → alle Gilden → Charakter → Account → Modul-Default. Der Optionsvertrag enthält stabile ID, Modul, Lokalisierung, Typ, Default, Scopes, Speicherbeschreibung, UI-Reihenfolge und optionalen Slash-Pfad.
- Synchronisierte administrative Gildeneinstellungen bleiben bei Permission- und Sync-Systemen und werden von `Settings` abgewiesen.
- Die zentrale Command-Registry speist Registrierung und Hilfeseite. Hilfe, Info und Status sind Seiten der bestehenden UI; es wurde kein weiteres Fenster-System angelegt.

## Slash-Einstiege

- `/hs` und `/hs open`: Hauptfenster
- `/hs help` und `/hs ?`: registrierte Command-Hilfe
- `/hs info`: kompakte Addon-, Modul-, Profil- und Gildeninformationen
- `/hs status`: Addon-, Modul-, Sync-, Task-, Workflow- und Log-Status in der UI
- `/hs reload`: `ReloadUI()`
- `/hs options` und `/hs o`: zentrale Optionen
- `/hs addons`: geladene Addons
- `/hs scan <target>`: vorhandene Charakter-Scan-Ziele
- `/hs equipment scan`: offizieller manueller Equipment-Scan
- Einfache POI-, Positions- und Equipment-Triggeroptionen erhalten Slash-Pfade aus demselben Optionsvertrag und schreiben über denselben Scope-/Settings-Pfad wie die UI.

## Spielerprofil

Der sichtbare Addonname ist jetzt **Player Profile / Spielerprofil**. Interne Addon-ID, Verzeichnis, SavedVariables, Sync-Domains und TwinkCore-API bleiben aus Kompatibilitätsgründen unverändert. Die vorhandene Charakterübersicht bleibt als „Characters / Charaktere“ erreichbar.

Alle Profilangaben sind freiwillig. Accountfelder sind Realname, strukturiertes Geburtsdatum (Tag/Monat/Jahr), Land mit stabilem Ländercode, Stadt, Spielertyp, typische Wochentage und typische Spielzeiten. Geburtsdaten werden auf Kalendergültigkeit geprüft; ein nicht lesbarer alter Wert bleibt erhalten und wird als Migration-unresolved markiert. Alter wird nicht separat gespeichert.

Jedes Feld speichert Wert und Sichtbarkeit getrennt. `PRIVATE`, `GUILD` und `PUBLIC` sind verfügbar; fehlende Sichtbarkeit ist `GUILD`. Leere Angaben und vorhandene, für den Betrachter nicht sichtbare Angaben bleiben unterscheidbar. PRIVATE-Werte bleiben lokal erhalten und werden vor dem Export aus den geteilten Daten entfernt.

Die Charaktertabelle zeigt Hauptcharakter-Krone, Klassenicon, klassengefärbten Namen, Realm, bekannte Gilde und bevorzugte Spezialisierungen. Main-Auswahl verwendet den vorhandenen exklusiven TwinkCore-Account-Main-Pointer. Specs werden aus den Klassen-/Spec-Daten gefiltert; bevorzugte Rollen werden aus ihnen abgeleitet. Bestehende Rollenfelder bleiben kompatibel, wenn noch keine Specs gewählt wurden.

## Migrationen und Datenkompatibilität

- Database-Schema 14 initialisiert die lokalen Settings-Buckets idempotent, ohne AceDB-Profile oder synchronisierte Gildendaten zu ersetzen.
- POI- und Positionswerte werden nur importiert, wenn im zentralen Speicher noch kein Wert existiert.
- Fehlende Positions-Share-Werte erhalten `true`; bereits gespeichertes `false` bleibt deaktiviert.
- Legacy-Geburtsdatum wird soweit sicher möglich strukturiert migriert. Nicht eindeutig parsebare Originalwerte bleiben erhalten und werden mit `UNRESOLVED` protokolliert.
- Account-UUID, Account-Main und bestehende TwinkCore-Daten behalten ihre bestehenden IDs und Speicherorte.
- Vor Export/Sync werden Profilfelder am PlayerData-/TwinkCore-Rand gemäß Sichtbarkeit bereinigt.

## Positions-, POI- und Equipment-Optionen

### Positions

Guild Position Sharing ist für neue und fehlende Werte aktiviert. Explizites `false` wird nicht überschrieben. Für Share kann der Benutzer zwischen dieser Gilde und allen Gilden wählen. Administrative Daten und Positions-Snapshots verbleiben im vorhandenen Permission-/Snapshot-/Sync-Pfad.

### POI

Map- und Minimap-Sichtbarkeit, Markergrößen, `maxSynced`, Kategorien- und Target-Filter sind in der zentralen Optionsseite registriert. Die bestehende POI-Funktionsseite bleibt erhalten; ihr Settings-Button öffnet die zentrale POI-Gruppe. Pro-POI-Ausblendung bleibt lokaler Elementzustand im DataManager.

### Equipment

Der Pflichttrigger bei Equipment-Wechsel wird angehakt und deaktiviert angezeigt. Optionale Trigger für Waffenverzauberungen und Sockeländerungen sind standardmäßig an. Scan-Status zeigt vorhandene Snapshot-Metadaten statt einer parallelen Persistenz. Button und Slash-Command rufen beide `RequestManualScan` und damit den CharacterScans-/Workflow-Pfad auf. Es gibt keinen Sync-Abschalter.

Die aktuelle 12.1-Live-UI/API-Quelle führt `SOCKET_INFO_SUCCESS` und `SOCKET_INFO_UPDATE`. Die Blizzard-Socketing-UI verwendet `SOCKET_INFO_UPDATE` zum Aktualisieren des Fensters/Tooltips; `SOCKET_INFO_SUCCESS` folgt dem erfolgreichen Socket-Vorgang. Deshalb fordert ausschließlich `SOCKET_INFO_SUCCESS` einen Scan an. Alle Requests laufen durch denselben einsekündigen Equipment-Workflow-Debounce. Der Ingame-Zeitpunkt und die tatsächliche Snapshot-Aktualisierung benötigen weiterhin einen Retail-Client-Test.

Quellenprüfung:

- [ItemSocketInfo API-Dokumentation der aktuellen Live-UI-Quelle](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/ItemSocketInfoDocumentation.lua)
- [Socketing-UI Eventbehandlung der aktuellen Live-UI-Quelle](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_ItemSocketingUI/Blizzard_ItemSocketingUI.lua)

## Geänderte Dateien

- Core: `LIVE/Holy_Storm/Core/Commands/Commands.lua`, `LIVE/Holy_Storm/Core/Settings/Settings.lua`, `LIVE/Holy_Storm/Holy_Storm.toc`, `LIVE/Holy_Storm/Locales/deDE.lua`, `LIVE/Holy_Storm/Locales/enUS.lua`, `LIVE/Holy_Storm/Persistence/Migrations.lua`, `LIVE/Holy_Storm/Persistence/PlayerDataStore.lua`, `LIVE/Holy_Storm/Persistence/Schema.lua`, `LIVE/Holy_Storm/Sync/SyncManager.lua`
- Player Profile: `LIVE/Holy_Storm_Characters/CharacterDirectory.lua`, `LIVE/Holy_Storm_Characters/Holy_Storm_Characters.toc`, `LIVE/Holy_Storm_Characters/Locales/deDE.lua`, `LIVE/Holy_Storm_Characters/Locales/enUS.lua`, `LIVE/Holy_Storm_Characters/Profiles.lua`, `LIVE/Holy_Storm_Characters/TwinkCore.lua`
- Equipment: `LIVE/Holy_Storm_Equipment/Equipment.lua`, `LIVE/Holy_Storm_Equipment/Locales/deDE.lua`, `LIVE/Holy_Storm_Equipment/Locales/enUS.lua`
- POI: `LIVE/Holy_Storm_POI/Locales/deDE.lua`, `LIVE/Holy_Storm_POI/Locales/enUS.lua`, `LIVE/Holy_Storm_POI/POI.lua`, `LIVE/Holy_Storm_POI/POIService.lua`
- Positions: `LIVE/Holy_Storm_Positions/GuildPositions.lua`, `LIVE/Holy_Storm_Positions/Locales/deDE.lua`, `LIVE/Holy_Storm_Positions/Locales/enUS.lua`, `LIVE/Holy_Storm_Positions/Positions.lua`
- UI: `LIVE/Holy_Storm_UI/Holy_Storm_UI.toc`, `LIVE/Holy_Storm_UI/UI/Pages/Options.lua`, `LIVE/Holy_Storm_UI/UI/Pages/OptionsLocales/deDE.lua`, `LIVE/Holy_Storm_UI/UI/Pages/OptionsLocales/enUS.lua`, `LIVE/Holy_Storm_UI/UI/Pages/SystemPages.lua`
- Dokumentation: `OPTIONS_ARCHITECTURE.md`
- Tests: `tools/test_addon_split.lua`, `tools/test_chat.lua`, `tools/test_character_scan_manager.lua`, `tools/test_equipment_workflow.lua`, `tools/test_options_profile_architecture.lua`, `tools/test_persistence_migrations.lua`, `tools/test_playerdata_sync.lua`, `tools/test_poi.lua`, `tools/test_positions.lua`, `tools/test_twinks.lua`

## Audit der übrigen Module

Die ausführliche Matrix steht in `OPTIONS_ARCHITECTURE.md`. Es wurden für Achievements, Calendar, Delves, Mythic+, News, Professions oder Raids keine neuen Optionen erfunden.

- Achievements besitzt einen AceDB-Profilwert `achievements.sound`, aber keine sichtbare Optionsgruppe.
- Calendar hält Gildenereignis-/Unread-Zustand, keine Nutzerpräferenz.
- Chat hat eine zentrale Optionsgruppe mit AceDB-Profilwerten, aber noch keinen neuen Settings-Vertrag.
- Guild hat zentrale AceDB-Profiloptionen für Offline-Mitglieder und Twink-Gruppierung.
- GuildLog zeigt zentrale Retention-Regler; die Werte liegen im globalen DataManager-Retentionzustand.
- Delves, Mythic+ und Raids haben keine eigenen Nutzeroptionen. Bestehende generische `/hs scan`-Ziele bleiben dokumentiert.
- News und UI SavedVariables-Werkzeuge verwalten Inhalt bzw. Daten, keine neu erfundenen Modulpräferenzen.
- POI und Positions besitzen zentrale Gruppen; Equipment erhielt die zentrale Gruppe in dieser Änderung.

## Prüfungen und offene Ingame-Punkte

- Regression: **82/82 Lua-Tests bestanden**
- Locale-Parität: `tools/Test-Localization.ps1` bestanden
- Lua-Syntax: **356 Lua-Dateien geprüft, 0 Fehler**
- `git diff --check`: bestanden
- Lokaler Retail-Spielclient war für diese Änderung nicht verfügbar.

Im Spielclient bleiben zu prüfen: Eventzeitpunkt von `WEAPON_ENCHANT_CHANGED`, Zeitpunkt der Socket-Snapshot-Aktualisierung nach `SOCKET_INFO_SUCCESS`, tatsächliches Debounce-Verhalten mit Itemdaten sowie Darstellung/Bedienung der Options-, Status-, Such- und Profilseiten auf Retail.

## Delivery

Die beiden Implementierungscommits oben wurden auf `origin/main` gepusht. Dieser Bericht wird separat als Dokumentationscommit ergänzt. Die bestehende benutzereigene Änderung an `WoW Addon - Holy Storm.code-workspace` wurde nicht gestaged oder committed.
