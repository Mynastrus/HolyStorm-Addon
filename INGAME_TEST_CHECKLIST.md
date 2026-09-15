# Holy Storm – Ingame-Testcheckliste

Mit aktivierten Lua-Fehlern testen. Nach Reload/Login prüfen, dass gespeicherte Daten ohne erzwungenen Neuscan sichtbar sind. Der Standard für Retry-fähige Tasks/Workflow-Ergebnisse ist drei Retries; ein Task darf bewusst eine andere Grenze deklarieren. Nach fehlgeschlagenen Snapshot-Scans muss der letzte gültige Stand erhalten bleiben.

## Start, UI und Daten

- Frische Installation, Update einer bestehenden Datenbank, Login, `/reload` und Charakterwechsel ohne Lua-Fehler prüfen.
- Hauptfenster, Navigation, CharacterOverview und Utility-Seiten öffnen, schließen, skalieren und aktualisieren.
- Equipment-, Mythic+-, Raid-, Delve-, Stats-, Profile- und Profession-Daten nach Reload aus dem zentralen Store anzeigen.
- Einen absichtlich ungültigen Snapshot provozieren: kein Commit, begrenzte Retries, letzter gültiger Snapshot weiterhin sichtbar.

## Administration Host

- Admin-Seiten erscheinen nur mit mindestens einer passenden effektiven Berechtigung.
- Gruppen/Berechtigungen, Regeln, Filter und Diagnose werden über die zentrale Administration registriert.
- Eine dynamisch registrierte Section erscheint in definierter Reihenfolge und wird beim Entzug der Berechtigung entfernt.
- Section eines fehlenden oder gildenweit deaktivierten Moduls erzeugt weder Navigation noch kaputte Seite.
- Reaktivierung eines Moduls beziehungsweise einer Permission aktiviert die vorhandene Section ohne Reload.
- Alle Admin-Texte, Tooltips, Status- und Bestätigungsdialoge in `deDE` und `enUS` prüfen.

## Gruppen und Membership

- Custom-Gruppe anlegen, umbenennen, beschreiben, speichern und löschen.
- `guild-leadership`, `officers` und `guild-member` sind gesperrt und nicht löschbar; geschützte Felder bleiben unveränderbar.
- Nur der tatsächliche aktuelle Blizzard-Gildenleiter kann zusätzliche Leadership-Memberships ändern.
- Character-, Account- und Guild-Rank-Membership einzeln testen.
- Filter- und Rule-Membership testen; Datenänderung invalidiert die effektiven Memberships.
- Charakter mit mehreren gleichzeitigen Membership-Gründen zeigt alle Quellen getrennt.
- Account-Membership gilt nach Erkennung auch für einen neuen Twink desselben Accounts.
- Permissions aus mehreren Gruppen werden additiv vereinigt.
- Leadership zeigt Vollzugriff und erhält auch eine nachträglich registrierte Permission.
- Manager-Gruppe kann die Zielgruppe verwalten, erbt aber weder deren Mitgliedschaft noch deren Permissions.
- Direkten und indirekten Manager-Zyklus versuchen; der Core muss speichern ablehnen.

## Permissions, Rules und Filter

- Permission-Liste entspricht der PermissionRegistry und zeigt Kategorie, Owner/Modul und lokalisierte Beschreibung.
- Rechtezuweisung speichern und mit einem zweiten Charakter positiv und negativ prüfen.
- Rules und Filter mit `AND`, `OR` und verschachtelten Gruppen erstellen, duplizieren, testen, speichern und löschen.
- Vorschau und Diagnose zeigen `PASS`, `FAIL` und bei fehlenden/veralteten Daten ausdrücklich `UNKNOWN`.
- `UNKNOWN` darf weder als Membership noch als erlaubtes Filterergebnis behandelt werden.
- Verwendete Rules/Filter können nicht unbemerkt gelöscht werden.
- Lokale Rules/Filter bleiben persönlich; gildenweite Änderungen erzeugen Permission-Revisionen und Sync.

## Revision Chain, Catch-up und Recovery

- Normale Mutation: Version steigt um eins, neue Revision-ID, korrekter Vorgänger, Changed By/At und History-Eintrag.
- Fehlender Vorgänger: lokale Anwendung ablehnen und Catch-up starten.
- Vollständige angebotene Kette: in Reihenfolge validieren und Status wieder `VALID`.
- Nicht reparierbare Lücke: `RECOVERY_REQUIRED` anzeigen.
- Vertrauenswürdige Snapshot-Recovery nur vom sichtbaren aktuellen Blizzard-Gildenleiter akzeptieren.
- Zwei Geschwisterrevisionen mit gleichem Vorgänger als Fork erkennen und `CONFLICT` anzeigen.
- Alte Revision ablehnen; identische Revision als Duplikat behandeln.
- Konflikt niemals durch „höchste Version gewinnt“ auflösen.
- Diagnose zeigt Guild ID, Status, Version, Revision, Previous, Last Sync, Changed By/At, History, Rejected Count, Missing und Fork.

## Factory Reset

- Sicherheitsdialog nennt ausschließlich Gruppen, Permissions, gildenweite Rules/Filter und Policy-/Modulkonfiguration; andere Daten bleiben erhalten.
- Reset mit berechtigtem Account ausführen: Version steigt, Revision-ID ändert sich, Previous verweist auf den alten Kopf.
- Custom-Gruppen, manuelle Memberships, Manager- und Permission-Zuweisungen sowie gildenweite Custom-Rules/-Filter sind entfernt.
- Genau drei Systemgruppen entsprechen wieder den Defaults.
- Persönliche lokale Rules/Filter bleiben erhalten.
- Player-/Character-Daten, Snapshots, Equipment, Mythic+, Raid, Delves, Achievements, Content, POIs, Logs und Twink-Identität bleiben unverändert.
- Reset ohne `permissions-reset` ablehnen und keine Revision erzeugen.
- Reset wird über die Permission-Sync-Domain an andere Clients verteilt.

## Sync und Identität

- Character-Blöcke zwischen zwei Clients entdecken, gezielt anfordern, validieren und in CharacterOverview aktualisieren.
- Direkten Owner-Payload und Relay-Payload prüfen: Owner bleibt stabil, `receivedFrom` und `direct` sind korrekt.
- Stale Version, Owner-Mismatch, ungültige Payload und nicht autorisierte Änderung ablehnen.
- Twink- und TwinkAdmin-Sync mit Account-Main und Zuordnungen prüfen.
- Permission-Catch-up, Recovery und Fork mit zwei Testclients gemäß obigem Abschnitt prüfen.

## Feature-Smoke-Tests

- Achievements: Entwurf, Aktivierung, Vergabe, Widerruf, Archiv und Sync.
- News/Guides: CRUD, Publish, RichContent, Read Receipt und Sync.
- POI: persönliche/Gilden-/Gruppen-/Raid-Ziele, Kartenpins, Ablauf und Berechtigungen.
- Positions: freiwillige Freigabe, Ablauf, Weltkarte/Minimap und keine Persistenz/Relays.
- Chat: Spielerlinks, Tooltips, Kontextmenü, URL/MapLinks, Erwähnungen und native Links.
- Equipment, Mythic+, Raids und Delves: Scan, Validierung, last-known-good und Character-Tabs.
- TaskManager-Seite: Queue, Merge, Blocked/Waiting, Pause/Resume, Retry-Zähler und Workflow-Verlauf.
- Logs: Filter, Pause, Auto-Scroll, Details und Export ohne Payload-Leaks.
