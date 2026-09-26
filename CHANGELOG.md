# Changelog

## Unreleased

- Embedded LibQTip centrally in Holy Storm UI and migrated the Raid Best tooltip to the shared structured tooltip service.
- Added centrally loaded LibDataBroker, LibDBIcon, LibSharedMedia, AceCommQueue, and LibGuildRoster infrastructure, including the persisted minimap launcher option. Existing Sync and guild-roster models remain unchanged.
- Routed outgoing legacy HSC1 Sync frames through the central AceCommQueue transport adapter; retained GuildStore as the peer identity authority and left LibGuildRoster unused for peer resolution.

## 5.5.0 — 15.09.2026

- Feature-Permissions wurden aus der zentralen Definitionsliste in die besitzenden Modulmetadaten verlagert. Die zentrale PermissionRegistry bleibt die einzige Registry; modulare Defaults werden für Systemgruppen angewendet, optionale Rechte erscheinen erst beim Laden des Moduls und unbekannte persistierte Permission-IDs bleiben für spätere Re-Registrierung erhalten.
- Die Rule-Felder `equipment.itemLevel`, `mythicplus.rating`, `raid.progress` und `delves.status` werden nun von ihren Modulen über die zentrale RuleEngine registriert. Nicht geladene optionale Module lassen gespeicherte Regeln unverändert; fehlende Felder liefern weiterhin `UNKNOWN`.

Hier halten wir ausschließlich Änderungen an den auslieferbaren Addon-Dateien
im Ordner `LIVE` fest. Änderungen an Projektdokumentation, dem Release-Ordner
oder anderen Dateien außerhalb von `LIVE` gehören nicht in dieses Changelog.

## Noch nicht veröffentlicht

### 26. September 2026

- Die Hauptansicht zeigt statt News-Kacheln, Modul- und Befehlslisten nur noch den aktuellen Charakter mit Spezialisierung/Klasse sowie Gegenstandsstufe, Mythisch+-Wertung und dem besten verlässlichen Schlachtzugsfortschritt der aktuellen Erweiterung. Die Werte stammen aus den vorhandenen Character-, Equipment-, Mythic+- und Raid-Snapshots und werden über deren bestehende Ereignisse ohne zusätzliche Scans oder Polling aktualisiert.
- Guild Activity ist als drittes lazy Guild-Management-Child implementiert. Provider erfassen eventgetrieben Online-Sitzungen, inhaltsfreie Gildenchat-Zähler, Raidbegegnungen und abgeschlossene gildenrelevante Mythisch+-Läufe; Calendar-Attendance bleibt mangels verlässlicher Beobachtung als nicht verfügbarer Erweiterungspunkt bestehen.
- Das versionierte `guild-activity`-DataManager-Schema speichert accountorientierte Shards mit Character-Provenance, UTC-Tages-/Wochenaggregaten, begrenzten Details, deterministischer Deduplizierung, unsicher markierter Session-Recovery und langfristiger Verdichtung. Die zentrale `guildActivity`-Sync-Domain überträgt autoritative kompakte Shards gezielt unter `guild-activity-view`, nicht einzelne Chat-Nachrichten oder Hot Events.
- Activity besitzt factual Rule-Felder, Account-Übersicht/Detail/Filter im gemeinsamen UI-Framework und eine wiederverwendbare `View Activity`-CharacterAction. Es gibt keine Punkte, Wertung, Empfehlungen, automatische Rangänderungen oder Chat-Inhaltsspeicherung.
- `Holy_Storm_Guild` besitzt nun eine erweiterbare Guild-Management-Oberfläche mit lazy registrierten Notes- und Absence-Unterseiten. Strukturierte private Notes bleiben accountweit lokal; Shared Notes und accountorientierte Absences verwenden getrennte DataManager-Schemas, zentrale Sync-Domains, monotone Revisionen und Tombstones.
- Shared-Note-Sichtbarkeit wird über PermissionEngine-Gruppen abgebildet. Der generische SyncManager kann empfängerabhängige Metadatenangebote und Payload-Exporte vor dem Versand filtern und als gezielte Whispers zustellen; private Notes werden weder angekündigt noch synchronisiert. Diese Zugriffskontrolle ist keine kryptografische Vertraulichkeit gegenüber manipulierten autorisierten Clients.
- Neue Guild-Management-Permissions besitzen lokalisierte Namen/Beschreibungen und Defaults: Mitglieder sehen öffentliche Notes/Absences und verwalten eigene Absences; Offiziere erhalten zusätzlich Notes-Verwaltung, eingeschränkte Sichtbarkeiten und administrative Absence-Verwaltung; Leadership behält dynamischen Vollzugriff.
- Die Rule-Felder `guild.absence.current`, `guild.absence.start` und `guild.absence.end`, ein wiederverwendbarer Character-Action-Provider sowie fokussierte Offline-Tests für Privacy, Authority, Revisionen, Tombstones, Identität, UI-Verträge und Lokalisierung wurden ergänzt. Calendar bleibt mangels Provider-Vertrag bewusst entkoppelt.

- Die vollständige Administration verwendet nun denselben deklarativen `UILayout`-/`UIComponents`-Pfad wie Character Overview. Gruppen/Berechtigungen, Rules, Filter und Policy-Diagnose werden lazy gebaut und verwenden gemeinsame Tabs, Scroll-Container, Empty States, Controls und die generische Table mit Row-/Cell-Reuse und Selection-State.
- Gruppenlisten, Membership-Quellen, effektive Mitglieder, Permission-Zuweisungen, Registry-basierte Permission-Matrix, Rule-/Filter-Listen, Checklisten und der verschachtelte Condition-Tree besitzen keine Administration-eigenen Zeilen-, Scroll- oder Breitenrenderer mehr. Leadership-Vollzugriff, additive Grants, unbekannte Felder und getrennte Character-/Account-/Rang-/System-/Filter-/Rule-Quellen bleiben unverändert sichtbar.
- Factory Reset, Gruppen-, Permission-, Rule- und Filteränderungen sowie Diagnose bleiben an die vorhandenen Domain-APIs und Revision Chain gebunden. Der externe `page`-/`render`-Section-Vertrag bleibt als Compatibility erhalten; die eingebauten Sections verwenden ausschließlich den lazy `build`-Lifecycle.
- Neue Regressionstests decken die gemeinsame Administration-UI, lazy Section-Lifecycle, Table-basierte Auswahl und Checklisten, Domain-Delegation, Membership-Quellen, geschützte Systemgruppen, Bestätigungsweg, Lokalisierung und Character-Overview-Isolation ab.

### 23. September 2026

- Ein zentraler, feature-blinder `CharacterScanManager` entdeckt Character-Datenblöcke deklarativ aus den Addon-TOCs, erfasst beim Login ausschließlich fehlende Blöcke und serialisiert alle Snapshot-Workflows über die gemeinsame Ressource `CHARACTER_SCAN`. Fachliche Events markieren ihren Block gezielt als dirty; Zonenwechsel startet keinen pauschalen Neuscan.
- Mythic+-Bestzeiten zeigen nun Key-Stufe, Laufzeit und In-/Overtime-Farbe anhand der gespeicherten Blizzard-Laufdaten. Raid-Lockouts werden über alle Encounter-Journal-Tiers aufgelöst, unterstützen Timewalking als optionale zentrale Tabellenspalte und zeigen nicht verifizierbare Lebenszeit-Kills ausdrücklich als unbekannt, statt lokale Beobachtungen zu addieren.
- Login-Presence verteilt die Semantic Version einmal pro Sitzung, antwortet leichtgewichtig und weist genau einmal auf eine entdeckte neuere Version hin. Die Gildenliste zeigt bekannte Holy-Storm-Versionen; strukturierte Comms-/Sync-Diagnosen enthalten Richtung, Sender, Ziel, Domain, Objekt, Nachrichtentyp, Version, Grund, Anfrage- und Korrelations-ID sowie Relay-/Retry-Kontext.
- Technische Logger-Ausgaben schreiben nicht mehr in den Spielerchat. Sichtbare Meldungen laufen über die zentrale Command-Ausgabe und sind in Deutsch und Englisch lokalisiert.

### 22. September 2026

- `Holy_Storm_UI` besitzt jetzt eine zentrale deklarative View-, Layout- und Komponentenarchitektur mit festen, prozentualen und gewichteten Tracks, verschachtelten Row-/Column-Containern, Padding, Gaps, Auto-Messung und ereignisgetriebenem Resize.
- Die generische Table-Komponente unterstützt lokalisierte Header, feste/flexible Spalten, Min-/Max-Breiten, Row-/Header-Höhen, Scrollen, Hover/Disabled, Tooltips, Clicks, opt-in Sortierung, Custom Renderer, Empty/Unknown States sowie Frame-/Cell-Reuse.
- Character Overview und der Administration-Host registrieren sich über den neuen View-Lifecycle. Der Character-Stats-Tab verwendet die zentrale Table; bestehende gemischte Feature-Tabs behalten vorerst ihren Compatibility-Renderer, dessen Spaltenberechnung bereits auf `UILayout` delegiert.
- Neue Offline-Tests decken View-Registrierung und Duplikate, optionale Module, Localization-Fallback, Layout-/Spaltenberechnung, Auto-Messung, Resize, Sorting, Empty/Unknown States und Frame-Reuse ab.

### 18. September 2026

- Die zentrale Rule-/Filter-Administration wurde vervollständigt: derselbe verschachtelte AND-/OR-/NOT-Editor verwaltet typisierte Conditions, strukturierte Enum-/Boolean-/Character-/Account-Werte, Mehrfachwerte sowie Hoch/Runter und Ein-/Ausrücken. Listen, Metadaten, Empty States, Field-Provider-Diagnose und alle sichtbaren Texte liegen in deDE/enUS vor.
- RuleEngine besitzt nun eine zentrale Operator-Metadatenregistry und liefert Diagnose-Traces mit Expected/Actual Value, Provider, Modul, Typ und UNKNOWN-Grund. Optionale Modulfelder bleiben bei Deaktivierung in gespeicherten Bäumen erhalten, liefern `UNKNOWN` und werden nach Reaktivierung wieder auswertbar.
- FilterManager stellt sichere CRUD-/Duplikations-, Preview- und erweiterbare Referenz-APIs bereit. Gildenweite Änderungen bleiben revisionsbasiert und permission-geprüft; Löschungen mit bekannten Gruppen- oder Modulreferenzen werden verhindert, und Preview verändert weder State noch Mitgliedschaften.
- Neue Regressionstests decken Filter- und Rule-CRUD, Referenzschutz, verschachtelte Bäume, typabhängige Operatoren/Werte, optionale Fields, Preview-Traces, Core-Permission-Gating, Lokalisierung sowie das Verbot zweiter Engines, statischer Feature-Feldlisten und direkter UI-Persistenzzugriffe ab.
- Die vorhandene Administration ist nun ein generischer Host mit genau einem Hauptfenster-Einstieg, dynamischer kategorisierter Tree-Navigation, deterministischer Sortierung, Lifecycle-Callbacks sowie Permission-, Modul-, Capability- und Availability-Gating. Rechte/Gruppen, Rules, Filter und Policy-Diagnose verwenden den Host; nicht verfügbare Bereiche verschwinden vollständig und eine ungültige aktive Seite fällt kontrolliert zurück.
- Die Gruppenverwaltung trennt System-, Rang-, manuelle und Filter-/Regelquellen, schützt Systemgruppen und Leadership-Vollzugriff im Core und autorisiert Metadaten-, Mitgliedschafts- und Permission-Änderungen getrennt. Beim Löschen einer Custom-Gruppe werden Manager-Referenzen in derselben Revision bereinigt.
- Die Permission-Matrix liest ausschließlich die aktive PermissionRegistry und zeigt ID, Lokalisierung, Beschreibung, Modul, Kategorie, Defaults, direkte Zuweisungen, effektive Grants und den geschützten Leadership-Vollzugriff. Gruppen-, Permission- und Mitgliedersuchen sowie lokalisierte Leer-, Fehler-, Tooltip- und Bestätigungszustände wurden vervollständigt.
- „Standards wiederherstellen“ bleibt eine monotone autorisierte `RESET`-Revision und setzt nur Gruppen-/Permission-Anpassungen zurück. Wiederverwendbare globale und lokale Filter/Rules, Modulstatus und fachfremde Holy-Storm-Daten bleiben erhalten.
- `metadata.administration` und früh geladene Modul-Permissions werden durch die ModuleRegistry gepuffert und nach Verfügbarkeit ihrer zentralen Registry registriert. Der Core kennt weiterhin keine feste Liste optionaler Admin-Module.
- Modul-Permission-Defaults werden pro Gilden-State nur einmal initialisiert. Erneute Registrierung, Reload, Login und Upgrade stellen eine manuell entfernte Zuweisung nicht wieder her. Die Character Overview deklariert keine eigene Grundzugriffs-Permission mehr.
- Neue Vertragstests decken Section-Registrierung und -Entfernung, Duplikate, Sortierung, Permission-/Modul-/Capability-Gating, Deaktivierung, aktiven Fallback, Navigations-Deduplizierung, deutsche/englische Lokalisierung, deklarative Modulregistrierung, einmalige Permission-Defaults und den freien Character-Overview-Grundzugriff ab.

### 16. September 2026

- Die RuleEngine ist nun ein reiner Core-Vertrag ohne Character-, Guild-, Equipment-, Mythic+-, Raid-, Delve-, Quest-, Achievement-, POI-, Content- oder Calendar-Feldwissen. Fachmodule registrieren lokalisierte, typisierte Felder ownergebunden über `metadata.ruleFields` oder die öffentliche Registry; Lifecycle-Cleanup, Availability, erlaubte Operatoren, Value-Provider, Aliase und Resolverfehler werden zentral behandelt.
- Unbekannte Felder bleiben in Rules und Filtern strukturell gültig, speicher- und synchronisierbar und liefern bei der Auswertung `UNKNOWN`. Owner-Cleanup löscht keine persistierten Objekte. AND/OR/NOT sowie kombinierte Filter verwenden konsistente Tri-State-Semantik.
- Quest- und Blizzard-Erfolgsdaten werden nicht mehr aus der RuleEngine gescannt. `CharacterRuleData` sammelt registrierte Bedarfe, plant die Erfassung über den TaskManager und persistiert ausschließlich über den CharacterStore.
- Feature-Filtervorlagen und Condition-Builder-Defaults sind nicht länger im Core an konkrete Character-Felder gekoppelt. Rule-Feldnamen und -beschreibungen besitzen deutsche und englische Modul-Lokalisierungen.
- Die Sync-Autorisierung wurde abgegrenzt: normale ownergebundene Character-Daten bleiben ohne Share-Permission sichtbar; administrative, veränderbare oder sensible Domains verwenden direkt PermissionEngine mit Compatibility-Fallback. Neue Vertragstests decken Registry-Owner, Cleanup, unbekannte Felder, Resolverfehler, Portabilität und Tri-State-Logik ab.
- Frühe Permission-Registrierungen greifen nicht mehr vor der AceDB-Initialisierung auf PolicyState zu. PolicyState verwendet die zentrale Database-Fassade, bewahrt vorhandene Zustände bei erneutem Bootstrap und behandelt verfrühte Zugriffe kontrolliert. Der Policy-Locale-Vertrag enthält nun außerdem die fehlende Kategorie `CATEGORY_CHARACTERS` und wird vollständig für deDE/enUS geprüft.

### 15. September 2026

- Die Administration registriert Gruppen-/Berechtigungs-, Regel-, Filter- und Diagnosebereiche nun über einen zentralen, permission- und modulgebundenen Section-Host. Die Seiten verwenden direkt PermissionRegistry, PermissionEngine, GroupManager, FilterManager, Rules und PolicyState; die bestehenden Policy-/Permissions-Fassaden bleiben für Compatibility erhalten.
- „Standards wiederherstellen“ erzeugt weiterhin eine normale autorisierte Revision. Statusansichten zeigen zusätzlich Gilden-ID, Changed By/At, abgelehnte Revisionen, Lücken und Fork-Daten.
- Die lebende Architektur-, Modul-, Permission-, Sync- und Ingame-Testdokumentation wurde auf den aktuellen Stand gebracht; der historische Refactor-Handoff wurde entfernt. Der Standard für Retry-fähige Tasks und Snapshot-Workflows beträgt drei Retries, sofern eine Definition bewusst keinen anderen Wert setzt. Holy Storm wurde auf `5.3.3` erhöht.

### 14. September 2026

- Die zentrale Logansicht verwendet nun eine virtualisierte, zeilenbasierte Scrolltabelle mit Level- und Kategoriefarben, kombinierten und dauerhaft gespeicherten Filtern, Schnellfiltern, pausierbarer Darstellung, optionalem Auto-Scroll sowie einer scrollbareren strukturierten Detailansicht. Comms-, Sync-, Task-, Workflow- und Event-Diagnosen enthalten kompakte Richtungs-, Absender-, Ziel-, Paket-, Domain-, Objekt-, Versions-, Übertragungs- und Korrelationsdaten, ohne Payloads oder interne Objektstrukturen zu protokollieren; Text-, CSV-, JSON- und Discord-Export bleiben verfügbar. Logger wurde auf `2.1.0`, EventBus auf `1.1.0`, TaskManager auf `3.1.0`, Comms auf `2.1.0`, SyncManager auf `3.3.0`, Schema auf `2.4.0` und die Logseite auf `1.1.0` erhöht; die sichtbaren Texte der Logseite besitzen neue deutsche und englische Locale-Dateien.
- Der Mythic+-Charakterreiter verwendet nun dieselbe Anzahl Tabellenzellen und Spaltendefinitionen und verarbeitet fehlende, alte oder teilweise beschädigte Snapshot- und Dungeon-Daten defensiv. Rendererfehler werden mit Reiter, Charakter, Datenblock und Snapshot-Version protokolliert, während die UI weiterhin den freundlichen Fallback zeigt. Die zentrale PlayerData-Validierung weist neue leere oder strukturell ungültige Mythic+-Blöcke ab; fehlgeschlagene Snapshot-Retries erreichen unverändert keinen Commit und erhalten damit den letzten gültigen Stand. CharacterOverview wurde auf `1.4.1`, Mythic+ auf `2.1.2`, PlayerDataStore auf `1.0.1` und die Release-Version auf `5.3.2` erhöht.
- Mythic+-Snapshots lesen Blizzard-Daten nun ohne bei jedem Scan erneut Affix-, Karten- und Belohnungsanfragen auszulösen. Die Anfragen erfolgen einmalig beim initialen Welteintritt beziehungsweise bei einem expliziten Refresh; ihre Update-Events sowie kurz aufeinanderfolgende Abschluss-, Karten- und Wochenrekord-Events werden weiterhin durch den vorhandenen Snapshot-Workflow zusammengeführt. Dadurch kann `MYTHIC_PLUS_CURRENT_AFFIX_UPDATE` keinen selbstverstärkenden `SNAPSHOT_MYTHICPLUS`-Kreislauf mehr erzeugen. Das Mythic+-Modul wurde auf `2.1.1` und die Release-Version auf `5.3.1` erhöht.

### 13. September 2026

- Blizzards `MapCanvas` wird nun als erforderliche Ladeabhängigkeit vor Holy Storm initialisiert. Dadurch können die POI- und Gildenpositions-Pins ihr `MapCanvasPinTemplate` sicher erben; die XML-Warnungen und anschließenden nil-Aufrufe beim Karten-Refresh entfallen.
- Ein neues Gildenerfolgssystem verwaltet versionierte Entwürfe, aktive und archivierte automatische Erfolge, manuelle Erfolge und Heldentaten. Es verwendet die zentrale Regel-, Filter-, Rechte-, Task-, Identitäts-, Rich-Link- und Sync-Infrastruktur, wertet fehlende oder veraltete Daten als `UNKNOWN`, erstellt unveränderliche Kandidaten-Snapshots und synchronisiert größere Vergaben in 30-Empfänger-Batches. Auditierbare Korrekturereignisse verhindern, dass widerrufene Vergaben durch alte Sync-Pakete wieder erscheinen. Browser, Detailansicht, Editor mit zentralem Regel-Builder, exakte Vergabevorschau, Testmodus, Benachrichtigung und Charakter-Reiter sind auf Deutsch und Englisch integriert.

- Raid-Snapshots werden in der Charakteransicht nun entsprechend dem tatsächlichen Single-Field-Vertrag des PlayerData-Stores direkt gelesen. Die vorherige doppelte `raidLockouts`-Entpackung lieferte trotz erfolgreich gespeicherter Raid-ID stets `nil` und verursachte die irreführende Anzeige „Keine Daten im Cache“. Aktive Lockouts bleiben außerdem unabhängig vom Ladezustand des Abenteuerführers speicherbar und werden allen Raids des aktuellen Erweiterungs-Tiers zugeordnet.

- Raid-IDs und der aktuelle Erweiterungs-Raidkatalog werden nun unabhängig voneinander erfasst. Eine aktive persönliche Instanzsperre gelangt dadurch auch dann in den Charakter-Cache, wenn der Abenteuerführer beim ersten Scan noch nicht bereit ist. Holy Storm lädt dessen Daten bei Bedarf nach, erkennt alle Raids des neuesten Erweiterungs-Tiers als aktuell und verknüpft Lockouts robust mit den passenden Katalogeinträgen.
- Der vollständige Charakterbereich besitzt nun einen gemeinsamen dunklen, gold eingefassten Rahmen mit Charakterportrait, klassenfarbigem Namen, Identitätszeile, Fraktionswasserzeichen, Datenstatus und Refresh-Aktion. Alle sieben responsiven Icon-Reiter verwenden einen klaren Hoverzustand und eine blau leuchtende aktive Auswahl; die Inhaltsansichten erhalten einen eigenen Abschnittskopf und einheitliche Tabellenkarten. Mythisch+ ergänzt darunter eine Zusammenfassung für abgeschlossene Dungeons, beste Dungeonwertung, besten Key und Gesamtwertung.
- Die Mythisch+-Erfassung wartet bei vorhandener Gesamtwertung nun auf die asynchron geladenen Dungeonwerte, reagiert auf `CHALLENGE_MODE_MAPS_UPDATE` und normalisiert den besten Lauf aus Zeit-, Überzeit- und saisonalen Score-Daten. Die Charakteransicht zeigt passend zur aktuellen Retail-Struktur je Dungeon den besten Key, dessen Wertung sowie Zeitstatus und Laufzeit statt leerer Tyrannisch-/Verstärkt-Spalten.
- Inhaltszeilen in „News & Guides“ öffnen ihre Detailansicht nun zuverlässig. Das beim Öffnen ausgelöste Gelesen-Ereignis aktualisiert nur noch eine tatsächlich sichtbare Liste und setzt Detailansicht oder Editor nicht mehr unmittelbar zurück; die Zeilen registrieren ihren Linksklick außerdem explizit.
- Shift-Klick auf von Holy Storm erzeugte Spieler- und Charakterlinks fügt nur noch den kanonischen Charakternamen ohne Realm, Zusatzinformationen oder Hyperlink-Markup in das aktive Chatfeld ein.
- Auch Blizzards vorangestellte Absenderlinks werden nun über dieselbe realm- und rangbewusste Charakterauflösung mit dem zentralen Holy-Storm-Tooltip, der Charakterübersicht und dem Charakter-Kontextmenü verbunden. Modifizierte und unbekannte Spielerlinks behalten ihr natives Chatverhalten.
- Ein neues zentrales Chat-Modul reichert echte eingehende Gilden-, Gruppen-, Schlachtzugs-, Instanz-, Flüster-, Sagen- und Schreien-Nachrichten lokal an. Ein event-invaliderter Spielerindex, UTF-8-erhaltende Wortgrenzen, Realm-Auflösung und ein linkbewusster Parser erzeugen UUID-basierte Charakterlinks, optionale Klassenfarben, Account-Main-/freigegebene Realnamen-Anzeigen, zentrale Tooltips und das bestehende Charakter-Kontextmenü, ohne native Links, Farbcodes, Texturen oder Atlas-Tags zu verändern.
- Persönliche Erwähnungsalarme unterstützen Charakter- und freiwillig freigegebene Realnamen, schließen eigene Nachrichten standardmäßig aus und begrenzen SoundKit-Wiedergaben durch Nachrichten-Deduplizierung und Cooldown. Die Optionen enthalten getrennte Schalter, Soundauswahl/Test, Kanalkonfiguration sowie Parser- und Registry-Diagnosen.
- Die vorhandene Rich-Link-Infrastruktur besitzt nun zusätzlich eine sichere registrierte Token-API und Diagnosemetadaten. Guide-, News-, POI-, Koordinaten-, Character-/Player- und URL-Aktionen bleiben an ihre zentralen Sichtbarkeits-, Store-, UI- und Map-APIs gebunden; unbekannte oder fehlerhafte Links/Tokens fallen lesbar zurück und können keinen beliebigen Lua-Code ausführen.

- Die Ausrüstung in der Charakterübersicht zeigt fehlende Verzauberungen und Nicht-Setteile nun als leere Felder. Setgegenstände erhalten ausschließlich einen Haken; Sockel und Edelsteine werden mit ihren API-Namen gespeichert und dargestellt. Item- und Edelsteinicons sowie ihre Namen reagieren auf Hover und normale Klicks mit den WoW-Tooltips beziehungsweise dem Itemlink-Fenster.
- Der News-/Guide-Editor verwendet für seinen mehrzeiligen Inhalt nun Blizzards `InputScrollFrameTemplate`. Damit wird nicht länger die ausschließlich für FontStrings verfügbare Methode `GetStringHeight` auf einem EditBox-Frame aufgerufen. Ein noch nicht initialisierter persönlicher Fensterstatus wird beim frühen Größenereignis ebenfalls sicher behandelt.
- Das rechte Seitenmenü verwendet seine Seitenreihenfolge nun ausschließlich zum Sortieren und ordnet alle Einträge lückenlos in einer einzelnen Spalte an. Doppelte oder gebrochene Sortierwerte führen nicht mehr zu überlagerten Buttons; bei kleinen Fensterhöhen stehen Mausrad sowie Auf-/Ab-Schaltflächen zum Scrollen bereit.
- Die POI-Gruppenkontexterkennung isoliert die Instanz-ID nun korrekt aus den Mehrfachrückgaben von `GetInstanceInfo`. Dadurch schlagen `poi.context` und davon abhängige `POI.MapRefresh`-Aufgaben in Gruppen oder Raids nicht mehr mit einer ungültigen `tonumber`-Basis fehl.
- Die neue Permission-Kategorie für Gildenpositionen besitzt nun vollständige deutsche und englische AceLocale-Einträge; dadurch erscheint beim Öffnen der Rechteverwaltung keine `CATEGORY_POSITIONS`-Warnung mehr.
- Holy Storm 5.3.0 ergänzt eine standardmäßig deaktivierte, freiwillige Gilden-Positionsfreigabe. Live-Pakete enthalten ausschließlich Charakter-UUID, Gilden-ID, Karte, normierte Koordinaten, Serverzeit und Sequenz; Positionen werden weder dauerhaft gespeichert noch über andere Spieler weitergereicht und bei Offline-, Gildenwechsel-, Richtlinien- oder Ablaufereignissen entfernt.
- Die bewegungsabhängige Erfassung nutzt echte Bewegungsereignisse und Geschwindigkeitsklassen, überspringt Stillstand und unbedeutende Änderungen und führt wartende Updates je Charakter auf den neuesten Zustand zusammen. Der Generic Sync Framework übernimmt Transport, Autorisierung, Validierung, Gildenabgleich, initiale Discovery und Ratenbegrenzung.
- Gildenmitglieder erhalten eine eigene, gepoolte Kartenebene auf Weltkarte und optional Minimap. Sie verwendet die gemeinsame POI-Kartentransformation, getrennte lokale Anzeigeoptionen, Klassensymbole oder Gildenmarker, lokale Tooltips sowie ein zentrales Charakter-Kontextmenü mit Öffnen, Main öffnen, Einladen, Flüstern, Namen kopieren und „Position als POI übernehmen“.
- Die neue Diagnoseansicht zeigt Freigabe-, Bewegungs-, Sync-, Ablauf- und Transformationsstatus in echten verankerten UI-Spalten statt in mit Leerzeichen simulierten Tabellen.

### 12. September 2026

- Holy Storm 5.2.0 ergänzt ein vollständiges POI-System mit stabilen IDs, persönlichen, Gilden-, Gruppen- und Raid-Zielen, Kategorien, frei wählbaren Symbolen und Farben sowie optionaler Lebensdauer. Persönlicher Anzeigezustand, Ziel-/Kategoriefilter und getrennte Größen und Schalter für Weltkarte und Minimap bleiben lokal.
- Weltkartenmarker verwenden einen MapCanvas-DataProvider mit gepoolten Pins; Minimapmarker werden über einen gemeinsamen, gedrosselten Aktualisierungspfad recycelt. Ein zentraler Koordinatenhelfer transformiert Positionen nur über verfügbare WoW-Weltkoordinaten und lässt Marker bei unsicheren Umrechnungen aus. Tooltips, Kontextmenüs, Detailansicht, Editor, Hidden-Verwaltung und Diagnoseansicht sind integriert.
- Die neue `poi`-Domain nutzt ausschließlich das Generic Sync Framework. Gilden-POIs sind persistent und tombstone-gesichert; Gruppen-/Raid-POIs sind an eine konkrete Session gebunden, werden beim Kontextwechsel entfernt und über Discovery, Jitter, Best-Source-Auswahl und Response Suppression nachsynchronisiert. Eingaben, Authority, Mengenlimits, Revisionen und abgelaufene Daten werden zentral validiert.
- POI- und Koordinatenlinks sind an die zentrale Rich-Link-/Map-Provider-Infrastruktur angebunden. Guide-Koordinaten setzen lokale temporäre Marker, während POI-Links stabile `poiID`s verwenden und weiterhin die POI-Sichtbarkeits- und Rechteprüfung durchlaufen.
- Holy Storm 5.1.0 vereinheitlicht Gilden-News, Ankündigungen und Guides in einer gildengetrennten Content-Infrastruktur. Stabile Content-IDs, Metadatenindex, Revisionen mit Optimistic Locking, auditierte Statuswechsel, Tombstones und die zentrale `content`-Sync-Domain verhindern Titelkopplung, stille Edit-Konflikte und das Wiederauftauchen gelöschter Inhalte.
- Die zentrale Permission Engine besitzt nun getrennte View-, Create-, Edit-, Delete- und Publish-Rechte für News und Guides. Entwürfe bleiben Autoren bzw. Bearbeitern vorbehalten; direkte Links, Suche, Dashboard und Sync-Import prüfen dieselbe gruppen-, charakter-, account- oder filterbasierte Sichtbarkeit. Persönlicher News-Lesestatus wird nicht mehr gildenweit synchronisiert.
- Eine gemeinsame, erweiterbare Rich-Content- und Link-Registry rendert Überschriften, Hervorhebungen, Listen, Absätze und Trennlinien sowie Item-, Player-, Character-, POI-, Coordinate-, News- und Guide-Links. Vollständige WoW-Itemlinks bleiben unverändert; Koordinaten öffnen ausschließlich ihre angegebene Map und setzen, sofern unterstützt, einen lokalen temporären Wegpunkt. POI-Module können stabile IDs über eine Provider-API anbinden.
- Die neue News-&-Guides-Oberfläche bietet Suche und zentrale Filter, Content-Liste und Detailansicht, Entwurf/Veröffentlichen/Archivieren/Löschen, Rich-Content-Vorschau, Link-Einfügeaktionen und Chat-Sharing. `/hs guide <ID/Name>` löst Guides eindeutig auf; `guide share` fügt den Link in den aktuellen Chat ein. Das Dashboard verwendet veröffentlichte News und Ankündigungen aus derselben Read-API.
- Die bisherige News-Persistenz wird über einen idempotenten Task einschließlich Titel, Inhalt, Autor, Datum, Zielrängen und persönlichem Lesestatus in den neuen Content-Store migriert. Diagnoseangaben zeigen im Debugmodus Revision, Quelle, Body-Status sowie erkannte, ungelöste und fehlerhafte Rich Links.
- Die Inhalte aller Reiter der Charakterübersicht werden nun in einzeln dimensionierten, umbrechenden Zeilen dargestellt. Ausrüstung, Mythisch+, Raid, Werte und Twinks verwenden echte, gemeinsam verankerte UI-Spalten statt Leerzeichen in proportionaler Schrift. Eine zuverlässige Breitenberechnung verhindert abgeschnittene Inhalte; dezente Zeilenhintergründe verbessern zusätzlich die Lesbarkeit umfangreicher Charakterdaten.
- Eine kanonische Charakteransicht ersetzt die bisherigen parallelen Charakter-Detailseiten. Sie besitzt einen stabilen UUID-Kontext, einen festen Header und die intern registrierten, lokalisierten Tabs Übersicht, Ausrüstung, Mythisch+, Raid, Tiefen, Werte und Twinks.
- Charakterdaten werden sofort aus validierten Store-Snapshots dargestellt und anschließend blockbezogen über den zentralen Task- und Sync-Pfad aktualisiert. Ereignisse invalidieren nur betroffene gecachte Tabs; Kontext-Tokens verhindern, dass verspätete Antworten eines zuvor geöffneten Charakters die aktuelle Ansicht überschreiben.
- Equipment, Mythisch+, Raid, Tiefen und Charakterwerte stellen öffentliche Snapshot-Read-APIs bereit. Ihre alten globalen Detailseiten wurden entfernt; das globale Twink-Management bleibt als fachlich eigenständige Verwaltungsansicht erhalten und öffnet Charaktere nun in der gemeinsamen Übersicht.
- Der Raid-Snapshot enthält den aktuellen Raid-Katalog sowie je Boss deduplizierte Lebenszeit-Kills. LFR, Normal, Heroisch und Mythisch verwenden zentrale Schwierigkeitsfarben; Weekly- und Best-Tooltips teilen eine wiederverwendbare Darstellung, die je Boss ausschließlich die höchste besiegte Schwierigkeit zeigt.
- Nicht zuverlässig von der Retail-API bereitgestellte Tier-, Teleport-, Delve-Ressourcen- und temporäre Buffdetails werden ausdrücklich als unbekannt bzw. nicht verfügbar angezeigt, statt geschätzt zu werden.

### 8. September 2026

- Holy Storm wurde auf Version 5.0.0 für Retail 12.1.0 erweitert. Eine zentrale Snapshot-Pipeline führt vollständige Scans, Validierung, Änderungsvergleich sowie höchstens fünf verzögerte Neuversuche aus und bewahrt bei Fehlern den letzten gültigen Stand.
- Equipment, aktuelles Mythic+-Season-Pool, aktueller Raid-Tier, Delves und dauerhafte Charakterstats verwenden die neue Pipeline, versionierte Stores, interne Aktualisierungsereignisse und Delta-Synchronisation.
- Datenbankschema 4 migriert bestehende Daten idempotent und ergänzt Profile, News, persistente technische Logs, Filteranforderungen und regelbasierte Berechtigungsgruppen.
- Die zentrale Rule Engine unterstützt verschachtelte UND-/ODER-/NICHT-Gruppen, Vergleichsoperatoren, lokale und globale Filter sowie bedarfsgesteuerte Quest- und Achievement-Abfragen.
- Die drei nicht löschbaren Standardgruppen Gildenleiter, Offiziere und Benutzer, dynamische Rang-/Regelmitgliedschaften und zentrale Permission-Keys ersetzen die bisherige einfache Rollenzuweisung; Altrollen bleiben erhalten.
- Freiwillige Account- und Charakterprofile, versionierte zielrangbezogene Gilden-News mit Lesebestätigungen, Addon-Presence und eine persistente technische Logansicht wurden ergänzt.

### 6. September 2026

- Die SavedVariables-Ansicht bietet nun standardmäßig eine anklickbare, aufklappbare Baumdarstellung und weiterhin optional eine Textansicht zum Kopieren. Normale Raid-Daten werden nicht mehr durch eine zu niedrige Verschachtelungsgrenze abgeschnitten. Tabellenschlüssel werden unabhängig vom Ausgabelimit formatiert, sodass bei großen Datenbeständen kein `nil`-Verkettungsfehler mehr entsteht; auch nichtskalare Lua-Schlüssel werden sicher angezeigt.

- Holy Storm wurde auf die zentrale 4.0.0-Architektur umgestellt: Bootstrap, EventBus, State-, Task-, Hook-, Action-, UI-, Kommunikations- und Synchronisationsmanager sind getrennte Core-Dienste. Die alte `CoreManagers.lua` und das bisherige Synchronisationsmodul wurden entfernt.

- Das Datenmodell trennt nun Gilden, Spieler und Charaktere in eigenen Stores. Eine idempotente, dreistufige Migration übernimmt bestehende Twinks, Spielerprofile, Charakterzuordnungen, Einstellungen und die bisherigen separaten SavedVariables, ohne Blizzard-Daten durch Synchronisationsdaten zu überschreiben.

- Equipment, Raid-Lockouts, Gildenroster, Charaktere, Gildenlog und Kalender verwenden die zentralen Events, Tasks, Stores und UI-Invalidierung. Mythisch+, Berufe und Tiefen erfassen ihre verfügbaren Retail-Daten defensiv über offizielle Blizzard-APIs.

- Kommunikation nutzt nun zentral registriertes Prefix, Chunking, Größenlimits, Ratenbegrenzung und Paketbereinigung. Synchronisation ist versioniert, validiert eingehende Strukturen und überträgt Equipment-, Raid-, Mythisch+- und Berechtigungsänderungen delta-basiert.

### 3. September 2026

- Der bestehende Ace3-Core wurde um zentrale Event-, Daten- und Konfigurationsmanager erweitert. Module können WoW- und Holy-Storm-Events abonnieren, fachliche Datenbereiche je Datenebene registrieren und Konfigurationsänderungen entkoppelt verarbeiten. Das neue CoreManagers-Teil, der Core und die Modulregistrierung wurden auf `1.0.1`, `2.3.4` und `1.5.0` versioniert.

- Die Synchronisierung unterstützt nun priorisierte Delta-Nachrichten mit registrierten Modulhandlern, Queue-Limit, fragmentierten Paketen, Sender-/Echo-Schutz und Bereinigung unvollständiger Übertragungen. Das Synchronisationsmodul wurde auf `1.3.0` angehoben.

- Equipment ist nun ein vollständiges Referenzmodul: Es erfasst nur geänderte Slots, speichert sie charakterbezogen, löst `HS_EQUIPMENT_UPDATED` aus, überträgt Deltas in die Gilde und stellt die erfassten Daten in einer eigenen UI-Seite dar. Das Modul ist für neue Profile standardmäßig aktiviert und wurde auf `3.0.0` angehoben.

- Das Raid-Modul erfasst nun echte gespeicherte Schlachtzugssperren samt Bossstatus über die Retail-API, speichert und zeigt sie charakterbezogen an und synchronisiert Änderungen innerhalb einer Gruppe bzw. eines Schlachtzugs als Delta. Es ist für neue Profile standardmäßig aktiviert und wurde auf `3.0.0` angehoben.

### 1. September 2026

- Die Charakterseite verwendet nun eine Panel-Registry: Das Gildenroster stellt
  Kontext und Layout bereit, während Profil-, Raid-, M+-/Tiefen- und
  Ausrüstungspanel eigene Renderer registrieren. Fachmodule können ihre Daten
  künftig unabhängig in diese Panels liefern. Das Gildenroster-Modul wurde auf
  `1.12.0` und die Release-Version auf `3.36.0` erhöht.

- Die Charakterseite ist nun als Dashboard aufgebaut: Kopfbereich mit
  Charakterdaten, getrennte Raid- und M+-/Tiefen-Panels links sowie ein großes
  Ausrüstungspanel rechts. Das Gildenroster-Modul wurde auf `1.11.2` und die
  Release-Version auf `3.35.2` erhöht.

- Neues optionales Modul „Gildenevents“: Es liest Gildenevents über die
  Kalender-API aus und zeigt sie auf einer eigenen Seite an. Aktivierung:
  Optionen → Optionale Module → Gildenevents, danach `/reload`. Das Modul und
  die Optionen wurden auf `1.0.0` und `1.4.1`, die Release-Version auf
  `3.35.1` erhöht.

- Linksklick auf einen Roster-Eintrag öffnet nun eine Charakterseite mit
  bekannten Gilden-, Charakter- und Twinkdaten. Bereiche für Realname,
  Geburtstag, Tiefen, M+, Raids, Ausrüstung und Raidteilnahmen sind vorbereitet.
  Das Gildenroster-Modul wurde auf `1.11.1` und die Release-Version auf
  `3.34.0` erhöht.

- Das optionale Gildenlog ist nun standardmäßig aktiviert und kann weiterhin
  über die Optionen abgeschaltet werden. Core und Gildenlog wurden auf `2.3.3`
  und `1.0.3`, die Release-Version auf `3.33.4` erhöht.

- Das aktivierte Gildenlog ist über seinen Navigationsreiter rechts sowie mit
  `/hs log` erreichbar. Core und Lokalisierung wurden auf `2.3.2` und `1.7.1`,
  die Release-Version auf `3.33.3` erhöht.

- Das Gildenlog wird nun separat in `HS_GuildLog_DB` gespeichert. Vorhandene
  Einträge werden bei der ersten Nutzung übernommen; die Datenbank ist in der
  Anzeige gespeicherter Variablen auswählbar. Gildenlog, Saved-Variables-Modul
  und dessen Lokalisierungen wurden auf `1.0.2`, `1.5.2` und `1.0.1`, die
  Release-Version auf `3.33.2` erhöht.

- Das Gildenlog verwendet nun ein nicht editierbares, scrollbareres Rich-Text-
  Feld. Beitritte, Austritte, Level-, Rang- und Notizänderungen erhalten jeweils
  eigene Farben. Das Gildenlog-Modul wurde auf `1.0.1` und die Release-Version
  auf `3.33.1` erhöht.

- Neues optionales Modul „Gildenlog“: Es vergleicht den gespeicherten
  Gildenroster-Schnappschuss beim Sitzungsbeginn und bei Live-Updates. Ein-
  und Austritte sowie Level-, Rang- und Notizänderungen werden mit Zeitstempel
  dauerhaft protokolliert. Aktivierung: Optionen → Optionale Module →
  Gildenlog, danach `/reload`. Das Modul und die Optionen wurden auf `1.0.0`
  und `1.4.0`, die Release-Version auf `3.33.0` erhöht.

- Die Rang-Auswahl im Mitgliedsfenster ist zurück. Sie erzeugt ausschließlich
  die benötigten sicheren Makro-Schritte; „Rang anwenden“ wird anschließend
  durch einen bewussten Mausklick ausgeführt. Direkte, geschützte Rang-APIs
  werden dabei nicht mehr verwendet. Das Gildenroster-Modul und seine
  Lokalisierungen wurden auf `1.11.0` und `1.0.3`, die Release-Version auf
  `3.32.0` erhöht.

- Rangaktionen verwenden nun sichere Makro-Buttons mit `/guildpromote` und
  `/guilddemote`, die durch den bewussten Mausklick des Spielers ausgeführt
  werden. Der geschützte direkte Aufruf von `SetGuildRankOrder` wurde entfernt.
  Das Gildenroster-Modul wurde auf `1.10.1` und die Release-Version auf
  `3.31.1` erhöht.

- Berechtigte Spieler können im Mitglieds-Detailfenster wieder den Rang
  ändern. Die Auswahl verwendet die aktuelle `C_GuildInfo.SetGuildRankOrder`-
  API und zeigt nur zulässige Zielränge an, statt die geschützten alten
  Beförderungsfunktionen aufzurufen. Das Gildenroster-Modul und seine
  Lokalisierungen wurden auf `1.10.0` und `1.0.2`, die Release-Version auf
  `3.31.0` erhöht.

- Die Rang-Aktionen wurden aus dem eigenen Mitgliedsfenster entfernt, da
  Blizzard `GuildPromote` und `GuildDemote` für Addons schützt. Dadurch tritt
  kein Addon-Action-Forbidden-Fehler mehr auf. Das Gildenroster-Modul wurde
  auf `1.9.2` und die Release-Version auf `3.30.2` erhöht.

- Das Aktualisieren-Piktogramm im Gildenroster wurde auf eine kompakte Größe
  von 18 × 18 Pixel reduziert. Das Gildenroster-Modul wurde auf `1.9.1` und
  die Release-Version auf `3.30.1` erhöht.

- Die Optionen enthalten nun eine Seite „Gildenroster“. Dort lässt sich
  steuern, ob Offline-Mitglieder angezeigt und bekannte Twinks gruppiert
  werden; beide Einstellungen sind standardmäßig aktiv und wirken sofort auf
  die Rosteransicht. Core, Gildenroster und dessen Lokalisierungen wurden auf
  `2.3.1`, `1.9.0` und `1.0.1`, die Release-Version auf `3.30.0` erhöht.

- Der kleine Twink-Pfeil zeigt nun in die entgegengesetzte Richtung und wurde
  auf 10 Pixel verkleinert. Das Gildenroster-Modul wurde auf `1.8.1` und die
  Release-Version auf `3.29.1` erhöht.

- Das Mitglieds-Detailfenster ist nun bewegbar und per Escape schließbar. Sein
  Titel zeigt Name und Realm in Klassenfarbe. Berechtigte Mitglieder können
  Gilden- und Offiziersnotiz bearbeiten und speichern sowie Mitglieder
  befördern oder degradieren. Das Gildenroster-Modul wurde auf `1.8.0` und die
  Release-Version auf `3.29.0` erhöht.

- Der Twink-Abzweig im Gildenroster verwendet nun `Arrow-Up-Up`, um 90 Grad
  nach rechts gedreht. Das Gildenroster-Modul wurde auf `1.7.3` und die
  Release-Version auf `3.28.3` erhöht.

- Der Aktualisieren-Button des Gildenrosters ist nun ein kompaktes
  `UI-RefreshButton`-Piktogramm; seine Funktion bleibt über den Tooltip
  erkennbar. Das Gildenroster-Modul wurde auf `1.7.2` und die Release-Version
  auf `3.28.2` erhöht.

- Der Aktualisieren-Button des Gildenrosters ist nun rechtsbündig im grauen
  Zwischenbereich unter der Titelleiste und über dem Inhaltsrahmen ausgerichtet.
  Das Gildenroster-Modul wurde auf `1.7.1` und die Release-Version auf
  `3.28.1` erhöht.

- Rechtsklick auf ein Mitglied öffnet nun ein eigenes, vom Blizzard-
  Gildenfenster unabhängiges Detailmenü. Es zeigt Name, Stufe, Klasse, Zone,
  Rang, letzten Online-Status sowie Gilden- und Offiziersnotiz an und dient als
  Grundlage für spätere Aktionen. Das Gildenroster-Modul wurde auf `1.7.0` und
  die Release-Version auf `3.28.0` erhöht.

- Eingerückte Twinks erhalten nun auch einen sichtbar nach rechts versetzten
  Namen. Der Rechtsklick versucht nach dem initialen Laden der Blizzard-
  Gildenoberfläche erneut, den Standard-Mitgliedsdialog zu öffnen. Das
  Gildenroster-Modul wurde auf `1.6.2` und die Release-Version auf `3.27.2`
  erhöht.

- Twinks im Gildenroster erhalten nun eine Blizzard-Pfeilgrafik statt einer
  nicht vorhandenen Schrift-Glyphe. Ein Rechtsklick lädt bei Bedarf nur die
  Blizzard-Gildenoberfläche und toggelt das Gildenfenster nicht mehr. Das
  Gildenroster-Modul wurde auf `1.6.1` und die Release-Version auf `3.27.1`
  erhöht.

- Die Statusanzeige im Gildenroster verwendet nun Blizzard-Texturen statt
  nicht unterstützter Schriftzeichen. Rechtsklick selektiert das Mitglied im
  Blizzard-Gildenroster und öffnet dessen Standard-Detailfenster. Das
  Gildenroster-Modul wurde auf `1.6.0` und die Release-Version auf `3.27.0`
  erhöht.

- Der Aktualisieren-Button des Gildenrosters ist nun mittig im Bereich direkt
  unter der Titelleiste positioniert. Das Gildenroster-Modul wurde auf `1.5.1`
  und die Release-Version auf `3.26.1` erhöht.

- Eingerückte Twinks erhalten nun den Abzweigpfeil `↳`. Rosterzeilen besitzen
  eine vollständige Blizzard-artige Hervorhebung beim Überfahren; ein
  Rechtsklick nutzt den geladenen Blizzard-Handler für das normale
  Gildenmitglied-Menü. Das Gildenroster-Modul wurde auf `1.5.0` und die
  Release-Version auf `3.26.0` erhöht.

- Der Gildenroster nutzt keinen separaten Überschriftsbereich mehr; Tabelle
  und Aktualisieren-Button verwenden den verfügbaren Fensterraum besser. Der
  Button sitzt nun im oberen Zwischenbereich. Bekannte Twinks werden direkt
  unter ihrem zugehörigen Charakter gruppiert und leicht eingerückt angezeigt.
  Das Gildenroster-Modul wurde auf `1.4.1` und die Release-Version auf
  `3.25.1` erhöht.

- Die internen Event-Frames von Synchronisation, Twinks und Gildenroster
  erhalten nun explizit `UIParent` als Parent. Das beseitigt den Fehler bei
  ihrer Erzeugung während der Modulinitialisierung. Die Module wurden auf
  `1.2.1`, `1.4.1` und `1.3.1` sowie die Release-Version auf `3.24.1`
  erhöht.

- Synchronisation, Twinks und Gildenroster registrieren ihre WoW-Ereignisse
  nun über eigene Frames. Das beseitigt die Aktivierungsfehler durch fehlende
  Event-Methoden auf den Modulobjekten. Synchronisation wurde auf `1.2.0`,
  Twinks auf `1.4.0`, Gildenroster auf `1.3.0` und die Release-Version auf
  `3.24.0` erhöht.

- Pflichtmodule binden nun zentral AceEvent ein. Dadurch können Twinks,
  Synchronisation und Gildenroster ihre WoW-Ereignisse zuverlässig
  registrieren. Die Modulregistrierung wurde auf `1.4.0` und die
  Release-Version auf `3.23.2` erhöht.

- Ein Aktivierungsfehler des Synchronisationsmoduls wurde behoben: Sein
  Nachrichten-Queue-Timer wird nun vom Core verwaltet, der AceTimer einbindet.
  Das Synchronisationsmodul wurde auf `1.1.1` und die Release-Version auf
  `3.23.1` erhöht.

- Twinks werden beim Betreten der Welt nun über die Synchronisation innerhalb
  der Gilde geteilt. Übertragen werden ausschließlich die Twink-GUIDs. Beim
  Empfänger landen sie als `knownTwinks` am Spieler-Datensatz des sendenden
  Charakters in `HS_Player_DB`. Das Twinks-Modul wurde auf `1.3.0` und die
  Release-Version auf `3.23.0` erhöht.

- Die Datenbankauswahl unter „Gespeicherte Variablen“ nutzt nun die doppelte
  Standardbreite, damit ihre vollständigen Bezeichnungen sichtbar sind. Das
  SavedVariables-Modul wurde auf `1.5.1` und die Release-Version auf `3.22.1`
  erhöht.

- Das Kopierfeld im Optionen-Reiter „Gespeicherte Variablen“ passt seine Höhe
  nun an die aktuelle Fenstergröße an und wird auch nach dem Skalieren des
  Hauptfensters neu berechnet. Der Erklärungstext über der Auswahl wurde
  entfernt. Das SavedVariables-Modul wurde auf `1.5.0` und die
  Release-Version auf `3.22.0` erhöht.

- Im Optionen-Reiter „Gespeicherte Variablen“ lassen sich nun `HolyStormDB`
  und `HS_Player_DB` auswählen. Ein Aktualisieren-Button rendert den Inhalt der
  gewählten Datenbank erneut. Die Auswahl aktualisiert die Anzeige sofort. Das
  SavedVariables-Modul wurde auf `1.4.1` und die Release-Version auf `3.21.1`
  erhöht.

- Die neue accountweite SavedVariable `HS_Player_DB` speichert
  Spielerinformationen direkt nach Spieler-GUID, getrennt von `HolyStormDB`.
  Der eigene Charakter aus Twinks und alle über den Gildenroster gelesenen
  Charaktere werden automatisch übernommen. Die Synchronisation stellt die
  Datenbank zudem über die Datenquelle `players` zur Verteilung bereit. Der
  Core wurde auf `2.3.0`, Twinks auf `1.2.0`, Gildenroster auf `1.2.1`,
  Synchronisation auf `1.1.0` und die Release-Version auf `3.20.1` erhöht.

- Das neue Pflichtmodul `Synchronisation` stellt eine sichere Basis für die
  Datenverteilung zwischen Holy-Storm-Nutzern bereit. Es unterstützt Gilde,
  Gruppe, Raid und Whisper, serialisiert Tabellen ohne Codeausführung, teilt
  große Nachrichten auf und bietet registrierbare Datenquellen zum Anfordern,
  Verteilen und Übernehmen von Daten. Die Release-Version lautet `3.19.0`.

- Die Realm-Spalte im Gildenroster bricht ihre Werte nicht mehr um und liest
  ausschließlich den Teil nach dem letzten Bindestrich des Charakternamens.
  Das Gildenroster-Modul wurde auf `1.1.2` und die Release-Version auf
  `3.18.7` erhöht.

- Die Namensspalte im Gildenroster zeigt nun nur noch den Charakternamen. Der
  Realm erscheint weiterhin ausschließlich in der separaten Realm-Spalte. Das
  Gildenroster-Modul wurde auf `1.1.1` und die Release-Version auf `3.18.6`
  erhöht.

- Der Core speichert den aktuellen Charakter beim vollständig abgeschlossenen
  Betreten der Welt nun zentral über das Twinks-Modul. Dadurch wird jeder
  Charakter definitiv in die accountweite Twinkliste aufgenommen. Der Core
  wurde auf `2.2.1` und die Release-Version auf `3.18.5` erhöht.

- Die Twinks-Speicherung initialisiert ihren accountweiten Datenspeicher nun
  sicher und wird zusätzlich beim Betreten der Welt sowie beim Öffnen der
  Übersicht ausgeführt. Dadurch wird der aktuelle Charakter zuverlässig
  gespeichert und angezeigt. Das Twinks-Modul wurde auf `1.1.2` und die
  Release-Version auf `3.18.4` erhöht.

- Nachträglich registrierte Seitennavigationssymbole übernehmen nun den
  Sichtbarkeitszustand des Hauptfensters. Dadurch erscheinen Gildenroster- und
  Twinks-Symbol nicht mehr beim Login, solange das Fenster geschlossen ist.
  Das UI-Modul wurde auf `1.20.1` und die Release-Version auf `3.18.2` erhöht.

- Das neue Pflichtmodul `Twinks` speichert beim Login jeden Charakter dieses
  WoW-Accounts accountweit über seine GUID mit Name, Klasse und Stufe. Seine
  Übersicht gleicht die gespeicherten GUIDs mit dem Gildenroster ab und
  kennzeichnet dadurch eigene Charaktere innerhalb der Gilde. Der Core wurde
  auf `2.2.0` und die Release-Version auf `3.18.0` erhöht.
- Beim Öffnen der Twinks-Übersicht wird der Gildenroster nun aktiv aktualisiert
  und nach dessen Antwort erneut abgeglichen. Das Twinks-Modul wurde auf
  `1.1.0` und die Release-Version auf `3.18.1` erhöht.

- Im Gildenroster liegt „Aktualisieren“ nun im oberen Fensterbereich, während
  die Mitgliederzahl in der Statusleiste erscheint. Die Klassenspalte wurde
  durch den Realm ersetzt; Namen nutzen jetzt die Klassenfarbe. Ein farbiger
  Punkt vor jedem Namen kennzeichnet Offline (grau), Online (grün), AFK (gelb)
  und DND (rot). Das UI-Modul wurde auf `1.20.0`, das Gildenroster-Modul auf
  `1.1.0` und die Release-Version auf `3.17.0` erhöht.

- Die Anzeige von `HolyStormDB` ist nun ein eigener Reiter in den Optionen und
  keine eigenständige Seite mehr. Das Options-Modul wurde auf `1.3.0`, das
  SavedVariables-Modul auf `1.3.0` und die Release-Version auf `3.16.0`
  erhöht.

- Der Inhalt von `HolyStormDB` wird jetzt in einem mehrzeiligen, nicht
  bearbeitbaren Textfeld angezeigt. Der Text kann darin markiert und kopiert
  werden. Das Modul wurde auf `1.2.0` und die Release-Version auf `3.15.0`
  erhöht.

- Der Scrollbereich der Anzeige gespeicherter Variablen übernimmt nun korrekt
  die verfügbare Breite. Dadurch wird der Inhalt von `HolyStormDB` sichtbar
  gerendert. Das Modul wurde auf `1.1.1` und die Release-Version auf `3.14.2`
  erhöht.

- Die Ansicht „Gespeicherte Variablen“ zeigt nun ausschließlich die
  SavedVariable `HolyStormDB` dieses Addons. Damit funktioniert sie unabhängig
  von der in der Spielversion unzuverlässigen Metadatenabfrage anderer Addons.
  Das Modul wurde auf `1.1.0` und die Release-Version auf `3.14.1` erhöht.

- Das neue Pflichtmodul `Gespeicherte Variablen` ist über die rechte
  Seitennavigation erreichbar. Es listet die accountweiten und
  charakterbezogenen SavedVariables aller geladenen Addons auf und stellt den
  Inhalt der gewählten Variable verschachtelt dar. Die Ausgabe ist gegen
  Zyklen, zu tiefe Tabellen und zu große Datenmengen abgesichert. Das UI-Modul
  wurde auf `1.19.0` und die Release-Version auf `3.14.0` erhöht.

- Das neue Pflichtmodul `Gildenroster` ist über die rechte Seitennavigation
  erreichbar. Es zeigt Namen, Rang, Stufe, Klasse, Zone und Online-Status aller
  Gildenmitglieder, aktualisiert sich bei Gildenänderungen und kann manuell neu
  geladen werden. Das UI-Modul wurde auf `1.18.0` und die Release-Version auf
  `3.13.0` erhöht.

- Zwischen Überschrift und Beschreibung der News-Kacheln liegt nun eine feste
  Leerzeile. Das UI-Modul wurde auf `1.17.6` und die Release-Version auf
  `3.12.6` erhöht.
- Die nicht sichtbare Panel-Textur der Kachel-Hervorhebung wurde durch einen
  goldenen Tooltip-Rahmen mit abgerundeten Ecken ersetzt. Das UI-Modul wurde
  auf `1.17.5` und die Release-Version auf `3.12.5` erhöht.
- Die Hover-Hervorhebung verwendet nun eine Blizzard-Panel-Textur mit
  abgerundeten, transparenten Ecken. Das UI-Modul wurde auf `1.17.4` und die
  Release-Version auf `3.12.4` erhöht.
- Die Hover-Hervorhebung der News-Kacheln ist auf den sichtbaren Kachelrahmen
  begrenzt. Das UI-Modul wurde auf `1.17.3` und die Release-Version auf
  `3.12.3` erhöht.
- Anklickbare News-Kacheln erhalten beim Überfahren eine dezente goldene
  Hervorhebung. Das UI-Modul wurde auf `1.17.2` und die Release-Version auf
  `3.12.2` erhöht.
- Die News-Kacheln sind nun vollständig per Linksklick anklickbar; die
  separaten Öffnen-Buttons wurden entfernt. Das UI-Modul wurde auf `1.17.1`
  und die Release-Version auf `3.12.1` erhöht.

### 31. August 2026

- Die Inhalte der Hauptansicht verwenden nun AceGUI-Gruppen, -Labels,
  -Symbole und -Buttons. Die drei News-Kacheln teilen sich die verfügbare
  Breite flexibel; Text und Icon liegen nebeneinander, der Öffnen-Button
  sitzt unten rechts. Das UI-Modul wurde auf `1.17.0`, seine Sprachdateien
  auf `1.10.0` und die Release-Version auf `3.12.0` erhöht.

### 27. August 2026

- Die Hauptansicht besitzt nun ein Newsportal mit drei großen, lokalisierten
  Beitragskacheln. Jede Kachel enthält Symbol, Überschrift, Kurztext und einen
  kleinen Pfeil unten links, der eine eigene Beitragsansicht öffnet. Ein
  Zurück-Pfeil führt wieder zur Übersicht. Das UI-Modul wurde auf `1.16.0`,
  seine Sprachdateien auf `1.9.1` und die Release-Version auf `3.11.0` erhöht.
- Das Zahnrad der rechten Optionsnavigation wird nun goldfarben dargestellt.
  Das UI-Modul wurde auf `1.15.2` und die Release-Version auf `3.10.2` erhöht.
- Rahmen und Hintergrund der Navigations-Slots wurden wiederhergestellt. Die
  Symbolgrafiken selbst verwenden nun eine additive Darstellung, damit ihre
  schwarzen Bildbereiche nicht mehr als Hintergrund sichtbar sind. Das
  UI-Modul wurde auf `1.15.1` und die Release-Version auf `3.10.1` erhöht.
- Die dunklen Hintergrundflächen der rechten Navigationssymbole wurden entfernt.
  Sichtbar bleiben Symbol, Rahmen, Auswahlhervorhebung und Tooltip. Das
  UI-Modul wurde auf `1.15.0` und die Release-Version auf `3.10.0` erhöht.
- Die rechte Iconleiste wurde um zwei Pixel weiter nach rechts verschoben. Das
  UI-Modul wurde auf `1.14.2` und die Release-Version auf `3.9.2` erhöht.
- Die rechte Navigation verwendet nun zusätzlich eine niedrigere Frame-Strata.
  Ihr überlappender Bereich wird dadurch zuverlässig hinter dem gesamten
  Hauptfenster dargestellt. Das UI-Modul wurde auf `1.14.1` und die
  Release-Version auf `3.9.1` erhöht.
- Die Slots der rechten Navigation sind nun eigenständige Rahmen auf einer
  niedrigeren Ebene als das Hauptfenster. Ihre linke Kante wird dadurch korrekt
  hinter dem Fensterrand dargestellt. Die Navigation wird beim Öffnen und
  Schließen des Hauptfensters passend ein- beziehungsweise ausgeblendet. Das
  UI-Modul wurde auf `1.14.0` und die Release-Version auf `3.9.0` erhöht.
- Der Abstand der rechten Iconleiste zum Hauptfenster wurde reduziert. Der
  Auswahlrahmen bleibt frei vom Fensterrand, ohne einen zu großen Zwischenraum
  zu erzeugen. Das UI-Modul wurde auf `1.13.4` und die Release-Version auf
  `3.8.4` erhöht.
- Die rechte Iconleiste wurde weiter nach außen versetzt. Auch der goldene
  Auswahlrahmen hält nun Abstand zum Hauptfenster und berührt dessen Rand nicht
  mehr. Die Bildschirmbegrenzung berücksichtigt den neuen Abstand ebenfalls.
  Das UI-Modul wurde auf `1.13.3` und die Release-Version auf `3.8.3`
  erhöht.
- Beim Wechsel von den Optionen zur Hauptansicht wird die Titelleiste nun
  zuverlässig wieder auf „Holy Storm“ zurückgesetzt. Das UI-Modul wurde auf
  `1.13.1` und die Release-Version auf `3.8.1` erhöht.
- Die Hauptansicht enthält jetzt einen anklickbaren `ReloadUI`-Button mit
  Tooltip, der die Benutzeroberfläche von World of Warcraft neu lädt. Das
  UI-Modul wurde auf `1.13.0`, seine Sprachdateien auf `1.8.0` und die
  Release-Version auf `3.8.0` erhöht.
- Die Titelleiste zeigt in der Hauptansicht „Holy Storm“. Beim Wechsel zu den
  Optionen wird „Optionen“ als hellgrauer Zusatz angezeigt und beim Zurückkehren
  wieder entfernt. Das UI-Modul wurde auf `1.12.0`, seine Sprachdateien auf
  `1.7.0` und die Release-Version auf `3.7.0` erhöht.
- Gespeicherte Fenstergröße und -position werden nur noch beim tatsächlichen
  Öffnen eines geschlossenen Hauptfensters angewendet, nicht beim Wechsel der
  internen Seiten. Die Fenstergröße wird während des Skalierens unmittelbar
  gesichert, sofern die entsprechende Option aktiv ist. Dadurch springt das
  Fenster beim Verlassen der Optionen nicht mehr. Das UI-Modul wurde auf
  `1.11.3` und die Release-Version auf `3.6.3` erhöht.
- Die Optionsseite bleibt nun als dauerhafter AceConfigDialog-Inhalt erhalten.
  Beim Wechsel zur Modulübersicht wird sie lediglich ausgeblendet und beim
  Zurückkehren wieder eingeblendet; ein erneuter fehleranfälliger Aufbau findet
  nicht statt. Das UI-Modul wurde auf `1.11.2` und die Release-Version auf
  `3.6.2` erhöht.
- Beim Verlassen der Optionsseite wird ihr AceGUI-Container nun vollständig
  freigegeben und beim erneuten Öffnen frisch erstellt. Die Profil- und
  Fenstereinstellungen erscheinen dadurch bei jedem Seitenwechsel zuverlässig.
  Das UI-Modul wurde auf `1.11.1` und die Release-Version auf `3.6.1` erhöht.
- Die Modulübersicht ist jetzt als vollständige AceGUI-Containerhierarchie im
  AceGUI-ScrollFrame eingebunden. Dadurch funktioniert der Wechsel zwischen
  Hauptfenster und Optionen dauerhaft. Die rechte Navigation wurde weiter in
  den Fensterrand versetzt und auf eine niedrigere Darstellungsebene gelegt,
  sodass ihre linke Kante hinter dem Fenster liegt. Das UI-Modul wurde auf
  `1.11.0` und die Release-Version auf `3.6.0` erhöht.
- Der Wechsel zwischen Modulübersicht und Optionen stellt die jeweilige Seite
  nun zuverlässig wieder her. Die Modulansicht wird erst nach dem Anzeigen des
  Hauptfensters aktiviert; der AceGUI-Scrollbereich wird dabei vollständig
  aktualisiert. Die linke Kante der rechten Navigation liegt jetzt hinter dem
  Fensterrand wie bei GMS. Das UI-Modul wurde auf `1.10.3` und die
  Release-Version auf `3.5.3` erhöht.
- Das Hauptfenster wird nun einschließlich des links überstehenden Portrait-
  Symbols und der rechten Iconleiste innerhalb des Spielfensters gehalten. Das
  UI-Modul wurde auf `1.10.2` und die Release-Version auf `3.5.2` erhöht.
- Das Hauptfenster besitzt nun wie GMS eine rechte Iconleiste. Die Symbole für
  Hauptfenster und Optionen schalten zwischen Modulübersicht und Einstellungen
  um, markieren die aktive Ansicht und zeigen lokalisierte Tooltips. Das
  UI-Modul wurde auf `1.10.0`, seine Sprachdateien auf `1.6.0` und die
  Release-Version auf `3.5.0` erhöht.
- Der Optionsreiter „Allgemeine Einstellungen“ heißt jetzt
  „Fenstereinstellungen“. Die Sprachdateien des Optionsmoduls wurden auf
  `1.2.1` und die Release-Version auf `3.4.1` erhöht.
- Die Modul- und Befehlsübersicht im Hauptfenster befindet sich jetzt in einem
  AceGUI-Scrollbereich. Lange Inhalte bleiben damit innerhalb des Fensters und
  können über die AceWidget-Scrollleiste erreicht werden. Das UI-Modul wurde
  auf `1.10.1` und die Release-Version auf `3.5.1` erhöht.
- Die Profiloptionen enthalten nun den Reiter „Allgemeine Einstellungen“.
  Dort lassen sich das Speichern von Fensterposition und Fenstergröße getrennt
  aktivieren sowie beide Werte zurücksetzen. Aktivierte Werte werden beim
  nächsten Öffnen des Hauptfensters wiederhergestellt. Der Core wurde auf
  `2.1.0`, das UI-Modul auf `1.8.1`, das Optionsmodul samt Sprachdateien auf
  `1.2.0` und die Release-Version auf `3.3.1` erhöht.
- Die Modulübersicht im Hauptfenster enthält jetzt einen Befehlsbereich. Die
  Einträge für Hauptfenster, Profiloptionen und Hilfe sind anklickbare Buttons
  mit lokalisierten Tooltips. Das UI-Modul wurde auf `1.7.0`, seine
  Sprachdateien auf `1.5.1` und die Release-Version auf `3.2.0` erhöht.
- Die gespeicherten Einstellungen verwenden nun AceDB-3.0 mit Profilen;
  vorhandene Einstellungen aus der bisherigen Speicherstruktur werden in das
  aktive Profil übernommen. Über `/hs options` oder `/hs o` öffnet sich das
  Hauptfenster direkt mit den AceConfig-Profiloptionen. `/hs ?` listet nun
  Hauptfenster, Optionen und Hilfe vollständig auf. Dafür wurden AceDB,
  AceDBOptions, AceConfigRegistry, AceConfigDialog und AceGUI ohne XML-Dateien
  eingebunden. Der Core
  wurde auf `2.0.0`, die Modulregistrierung auf `1.3.0`, das UI-Modul auf
  `1.6.0`, das Optionsmodul samt Sprachdateien auf `1.1.0` und die
  Core-Sprachdateien auf `1.7.0` erhöht. Die Release-Version lautet `3.1.0`.
- Der Status wurde um zwei Pixel weiter nach links und zwei Pixel nach oben
  verschoben. Das UI-Modul wurde auf `1.5.5` und die Release-Version auf
  `3.0.5` erhöht.
- Der Status wurde im unteren Statusbereich weiter nach links und etwas tiefer
  ausgerichtet. Das UI-Modul wurde auf `1.5.4` und die Release-Version auf
  `3.0.4` erhöht.
- Der blaue Hintergrund der Statusleiste wurde entfernt. Der Status steht nun
  linksbündig und mit den passenden Innenabständen im unteren Statusbereich.
  Das UI-Modul wurde auf `1.5.3` und die Release-Version auf `3.0.3` erhöht.
- Die Statusleiste wurde aus dem Inhaltsbereich in den vorgesehenen unteren
  Statusbereich des Fenster-Templates verschoben. Das UI-Modul wurde auf
  `1.5.2` und die Release-Version auf `3.0.2` erhöht.
- Titel und Symbol werden jetzt in den dafür vorgesehenen Bereichen des
  `ButtonFrameTemplate` dargestellt: der Titel in der Fenster-Titelleiste und
  das Symbol im Portrait-Slot oben links. Der Text der Statusleiste verbleibt
  zentriert innerhalb der Statusleiste. Das UI-Modul wurde auf `1.5.1` und die
  Release-Version auf `3.0.1` erhöht.
- Das Hauptfenster besitzt nun eine klar erkennbare Kopfzeile mit Holy-Storm-
  Titel und Symbol sowie eine hellblaue, lokalisierte Statusleiste am unteren
  Rand. Das UI-Modul wurde auf `1.5.0`, seine Sprachdateien auf `1.4.0` und
  die Release-Version auf `3.0.0` erhöht.
- Die erste Größenänderung des bislang nicht verschobenen Hauptfensters bleibt
  nun stabil. Vor dem Skalieren wird die zentrierte Ausgangsposition in eine
  feste Bildschirmposition überführt, sodass das Fenster nicht mehr plötzlich
  unverhältnismäßig groß wird. Das UI-Modul wurde auf `1.4.1` und die
  Release-Version auf `2.9.1` erhöht.
- Die Benutzeroberfläche zeigt nun alle Holy-Storm-Module mit ihrer jeweiligen
  Versionsnummer. Auch nicht aktivierte optionale Module sind sichtbar, ohne
  dass sie dafür geladen werden müssen. Das UI-Modul wurde auf `1.4.0`, die
  zugehörigen Sprachdateien auf `1.3.0`, die Modulregistrierung auf `1.2.0`,
  die optionalen Module auf `2.1.0` und die Core-Sprachdateien auf `1.6.2`
  erhöht. Die Release-Version lautet `2.9.0`.
- Die anklickbaren Befehle in der Ladeausgabe sind nun gelb. Ihre Tooltips
  heißen einheitlich „Holy Storm“; in den Beschreibungen wird der Addonname
  hellblau hervorgehoben. Core und Core-Sprachdateien stehen damit auf
  `1.9.1` beziehungsweise `1.6.1`, die Release-Version auf `2.8.1`.
- Nach dem Laden erscheinen jetzt zwei klar formulierte Chatzeilen: eine mit
  Addonname und Version, eine weitere mit den Befehlen zum Öffnen und zur
  Hilfe. `/hs` und `/hs ?` sind hellblau hervorgehoben, anklickbar und zeigen
  beim Überfahren einen passenden Tooltip. Der Core wurde auf `1.9.0`, die
  Core-Sprachdateien auf `1.6.0` und die Release-Version auf `2.8.0` erhöht.
- Das Hauptfenster kann nun über den Griff unten rechts in der Größe verändert
  werden. Die Mindestgröße beträgt 650 × 420 Pixel. Das UI-Modul wurde auf
  `1.3.0` und die Release-Version auf `2.7.0` erhöht.
- Die Holy-Storm-Oberfläche verwendet nun ein großes, verschiebbares
  `ButtonFrameTemplate`-Fenster mit Titel, Inhaltsbereich und Fußzeile. Sie
  kann über `ESC` geschlossen werden. Das UI-Modul und seine Sprachdateien
  wurden auf `1.2.0`, die Release-Version auf `2.6.0` erhöht.
- Die neuen UI-Module öffnen jetzt eine verschiebbare, lokalisierte Oberfläche,
  wenn `/hs`, `/holystorm` oder `/holy_storm` ohne Argument eingegeben wird.
  Der Core wurde auf `1.8.0`, das UI-Modul auf `1.1.0`, die Core-Sprachdateien
  auf `1.5.0` und die Release-Version auf `2.5.0` erhöht.
- Die Eingabe eines Fragezeichens nach einem Holy-Storm-Befehl zeigt jetzt die
  lokalisierte Liste aller Befehle an. Der Core wurde auf `1.7.0`, die
  Core-Sprachdateien auf `1.4.0` und die Release-Version auf `2.4.0` erhöht.
- AceEvent-3.0 und AceTimer-3.0 wurden eingebunden. Der Core verarbeitet den
  Welteintritt nun über AceEvent und schließt seine Initialisierung über einen
  AceTimer ab. Der Core wurde auf `1.6.0` und die Release-Version auf `2.3.0`
  erhöht.
- Beim Überfahren des anklickbaren Chat-Präfixes `[Holy Storm]` wird nun ein
  lokalisierter Tooltip angezeigt. Der Core wurde auf `1.5.0`, die
  Core-Sprachdateien auf `1.3.0` und die Release-Version auf `2.2.0` erhöht.
- Die Kurzbefehle `/hs` und `/holy_storm` stehen zusätzlich zu `/holystorm`
  bereit. Der Core wurde auf `1.4.1`, die Core-Sprachdateien auf `1.2.1` und
  die Release-Version auf `2.1.1` erhöht.
- Das hellblaue Chat-Präfix `[Holy Storm]` ist jetzt anklickbar und führt den
  Statusbefehl `/holystorm` aus. Der Core wurde auf `1.4.0`, die
  Core-Sprachdateien auf `1.2.0` und die Release-Version auf `2.1.0` erhöht.
- Chatausgaben verwenden jetzt das hellblaue Präfix `[Holy Storm]  ` mit zwei
  Leerzeichen vor der Nachricht. Der Core wurde auf `1.3.3`, die
  Core-Sprachdateien auf `1.1.6` und die Release-Version auf `2.0.2` erhöht.
- Ein Syntaxfehler in den optionalen Modulregistrierungen wurde behoben. Die
  Module `Equipment`, `Raids`, `Delves` und `Dungeons` stehen jetzt auf
  `2.0.1`; die Release-Version wurde ebenfalls auf `2.0.1` erhöht.
- `Equipment`, `Raids`, `Delves` und `Dungeons` sind nun optionale Module und
  werden nur bei Aktivierung in den gespeicherten Einstellungen erstellt. Die
  verpflichtenden Module `UI` und `Options` wurden ergänzt. Wegen dieser
  grundlegenden Strukturänderung lautet die Release-Version `2.0.0`.
- Der Gildenname in der Beschreibung wird jetzt im hellen Magier-Blau
  dargestellt. Die Core-Sprachdateien wurden auf `1.1.5` und die
  Release-Version auf `1.4.5` erhöht.
- Der Autor des Addons ist nun `Mynastrus - Norgannon - EU`. Die Core-Version
  wurde auf `1.3.2` und die Release-Version auf `1.4.4` erhöht.
- Die Addon-Beschreibung nennt nun das Gildenverwaltungssystem für
  `|cffF7D358<Holy Storm>|r` auf Norgannon-EU. Sie ist in Englisch und Deutsch
  hinterlegt; die Release-Version wurde auf `1.4.3` erhöht.
- Die TOC enthält nun zusätzlich Autor, Kategorie und den aktivierten
  Standardstatus. Die Release-Version wurde auf `1.4.2` erhöht.
- Der sichtbare Addon-Name lautet jetzt in allen Sprachen nur noch `Holy Storm`.
  Die Core-Sprachdateien wurden auf `1.1.3` und die Release-Version auf `1.4.1`
  erhöht.
- Jedes Pflichtmodul besitzt jetzt eigene AceLocale-Sprachdateien für Englisch
  und Deutsch. Die Modul-Lua-Dateien wurden auf `1.2.2` erhöht; die
  Core-Sprachdateien stehen auf `1.1.2`. Die Release-Version ist `1.4.0`.
- Die XML-Ladeanweisungen wurden entfernt. LibStub, AceAddon und AceLocale
  werden jetzt direkt über die TOC-Datei geladen.
- Auch die Chat-Präfix-Ausgabe wird nun lokalisiert. Die daraus entstandene
  Fehlerkorrektur erhöht den Core auf `1.3.1` und die Sprachdateien auf `1.1.1`.
- AceLocale-3.0 wurde eingebunden und ersetzt die eigene Lokalisierungslogik.
  Vor jedem Release prüft `tools/Test-Localization.ps1` fehlende Übersetzungen,
  nicht definierte Schlüssel und typische direkte, nicht lokalisierte Ausgaben.
  Der Core wurde auf `1.3.0`, die Pflichtmodule auf `1.2.1` und die
  Modulregistrierung auf `1.1.1` aktualisiert.
- Der Core stellt seine Lokalisierungsinstanz jetzt für alle Module bereit.
  Diese Fehlerkorrektur erhöht die Core-Version auf `1.2.1`.
- Alle sichtbaren Texte und Ausgaben verwenden jetzt die zentrale
  Lokalisierung. Englische und deutsche Übersetzungen sind enthalten; weitere
  Sprachen können über eigene Sprachdateien ergänzt werden. Die betroffenen
  Lua-Dateien wurden als Minor-Änderung auf `1.2.0` erhöht.
- Core und Pflichtmodule enthalten nun einheitliche Metadaten mit Anzeigename,
  internem Namen, Version, Kategorie, Beschreibung, Berechtigungen,
  Abhängigkeiten und Standardstatus. Die betroffenen Lua-Dateien wurden als
  neue rückwärtskompatible Funktion auf `1.1.0` erhöht.
- Die Versionsnummern verwenden jetzt keine führenden Nullen mehr. Die
  Startversion des Addons und seiner Lua-Dateien lautet `1.0.0`.
- Jedes verpflichtende Modul besitzt jetzt einen eigenen Ordner. Dadurch können
  künftig modulbezogene Lua-Dateien, UI-Dateien und Daten klar getrennt ergänzt
  werden.
- Die Module wurden in `Required` und `Optional` unterteilt. `Equipment`,
  `Raids`, `Delves` und `Dungeons` sind verpflichtend und werden immer durch
  die Core-TOC geladen. Optionale Module können künftig in den gespeicherten
  Einstellungen aktiviert und beim nächsten Laden gezielt erstellt werden.
- Die Bereiche `Equipment`, `Raids`, `Delves` und `Dungeons` sind jetzt
  interne Module des Core-Addons unter `Holy_Storm/Modules`. Ihre eigenen
  TOC-Dateien wurden entfernt; nur `Holy_Storm` wird von WoW als Addon geladen.
- AceAddon-3.0 und die benötigte Bibliothek LibStub wurden in den Core
  eingebunden. Der Core und alle Module verwenden nun AceAddons Addon- und
  Modulregistrierung statt einer eigenen Registrierung.
- Jede Lua-Datei verwaltet jetzt ihre eigene Versionsnummer. Die Version wird
  beim jeweiligen Addon-Teil gespeichert und startet bei `1.0.0`.
- Holy Storm wurde um die vier eigenständigen Module `Equipment`, `Raids`,
  `Delves` und `Dungeons` erweitert. Jedes Modul besitzt ein eigenes Addon-
  Verzeichnis mit TOC- und Lua-Datei und kann nur zusammen mit dem Core-Addon
  geladen werden.
- Der Core stellt nun eine gemeinsame Modulregistrierung bereit, über die sich
  die Erweiterungen bei Holy Storm anmelden können.
- Der Addon-Ordner und die Addon-Dateien wurden in `Holy_Storm` umbenannt.
  Die TOC-Datei lädt entsprechend `Holy_Storm.lua`.
- Das Grundgerüst des Addons wurde angelegt. Die Datei `HolyStorm.toc` enthält
  die Retail-Metadaten, die Startversion `1.0.0` und die Lade-Reihenfolge.
- `HolyStorm.lua` wurde ergänzt. Sie richtet gespeicherte Einstellungen ein,
  verarbeitet die grundlegenden Lade-Ereignisse und stellt den Befehl
  `/holystorm` bereit.
- Der Addon-Ordner `HolyStorm` wurde in `LIVE` vorbereitet. Er bildet die
  Grundlage für die Dateien, die später nach `Interface/AddOns` kopiert werden.
