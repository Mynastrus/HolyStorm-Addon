# Holy Storm 5.0.0 – Ingame-Testcheckliste

Alle Fälle mit aktivierten Lua-Fehlern testen; nach jedem fehlgeschlagenen Snapshot prüfen, dass der letzte gültige Stand erhalten bleibt und spätestens nach Versuch 5 kein weiterer automatischer Retry entsteht.

## Gildenerfolge

- Als Gildenleitung einen automatischen Erfolg mit verschachteltem AND/OR/NOT anlegen, als Entwurf speichern, aktivieren und anschließend archivieren. Nur der aktive Zustand darf automatisch vergeben.
- Eine Regel mit absichtlich fehlenden Charakterdaten testen: Vorschau und Diagnose müssen `Unbekannt` samt Grund zeigen und dürfen keine Vergabe erzeugen.
- Einen manuellen Erfolg für Gildenroster, aktuelle Gruppe, aktuellen Raid sowie einen zentralen Gildenfilter vorprüfen. Kandidatenzahl und PASS/FAIL/UNKNOWN vor und nach der Bestätigung vergleichen.
- Eine Vorschau erzeugen, danach Gruppenmitglieder wechseln lassen und erst dann bestätigen. Vergeben werden darf ausschließlich an den unveränderlichen Snapshot.
- Testmodus mit mehreren berechtigten Spielern ausführen: Ergebnis und Erklärungen müssen sichtbar sein, Store, Verlauf, Benachrichtigungen und Sync bleiben unverändert.
- Mehr als 30 Kandidaten vergeben und auf einem zweiten Client nachladen. Die Batches müssen zusammen vollständig und ohne Doppelvergabe erscheinen.
- Eine Vergabe mit Grund widerrufen, einen alten Client synchronisieren und neu laden. Der Widerruf muss durch das Korrekturereignis erhalten bleiben.
- Charakter- und Account-Scope mit zwei Twinks desselben Accounts prüfen. Account-Erfolge dürfen im Charakter-Reiter nicht doppelt vergeben werden.
- Einen Erfolgslink in Chat, News und Guide anklicken sowie per Shift-Klick einfügen. Sichtbarkeit, Tooltip und geöffnete Detailansicht müssen der zentralen Link-Infrastruktur entsprechen.
- Mit Mitglied-, Offiziers- und Leitungsrollen Create/Edit/Publish/Award/Revoke/Test getrennt prüfen; versteckte oder nicht erlaubte Aktionen dürfen auch über direkte Service- und Sync-Pfade nicht gelingen.

## Equipment

- Einzelnes Item, mehrere Items schnell und ein komplettes Set wechseln.
- Ringe und Schmuckplätze tauschen; Waffe, Verzauberung, Gem und Sockel ändern.
- Ein Item entfernen, vollständig ausziehen und wieder anlegen.
- Logout/Login sowie verzögerte Itemdaten prüfen: kontrollierte Validation-Retries sind erlaubt, `ITEM_DATA_LOAD_RESULT` darf aber keinen neuen Equipment-Workflow starten.

## Task-Manager und Workflows

- Entwicklerseite öffnen und Live Tasks, Queue, Workflows, Historie, Performance, Ereignismonitor und Abhängigkeiten prüfen.
- Schnell mehrere Equipment-Slots wechseln: genau ein Workflow darf laufen; vor dem Scan werden Trigger gemergt, während der Ausführung darf höchstens ein Pending-Restart entstehen.
- Triggeranzahl und Quellen für `PLAYER_EQUIPMENT_CHANGED`, `UNIT_INVENTORY_CHANGED` und `SOCKET_INFO_UPDATE` mit Event-Monitor und korrelierten Logs vergleichen.
- Queue im Leerlauf, während Debounce, mit blockiertem Task und während `WAITING_ASYNC` pausieren und fortsetzen.
- Im Kampf einen Equipment-Scan anfordern: der Task muss mit lokalisiertem Blockierungsgrund warten, andere ausführbare Tasks dürfen weiterlaufen.
- Workflow abbrechen, neu starten und Pending-Restart entfernen; Abbruch und Queue-Bereinigung jeweils im Bestätigungsdialog prüfen.
- Tabellen sortieren, Spaltenbreite ziehen, Spalten per Umschalt-/Strg-Klick verschieben, per Rechtsklick ausblenden und über Zurücksetzen wiederherstellen; UI neu laden und gespeichertes Layout kontrollieren.
- Deutsch und Englisch testen; Tasknamen, Status, Blockierungsgründe, Buttons, Tooltips und Tabellenüberschriften dürfen nicht auf die andere Sprache zurückfallen.

## Mythic+

- Login mit vorhandenen Season-Runs und dynamischem Dungeon-Pool.
- Dungeon intime und overtime beenden; Score, Key-Level und Affixwerte prüfen.
- Direkt nach Abschluss teleportieren beziehungsweise Ladebildschirm auslösen und Retry beobachten.

## Raids

- Login ohne und mit Lockout.
- Bosskill und `UPDATE_INSTANCE_INFO` prüfen.
- Lockout verlängern oder zurücksetzen; neuesten Raid-Tier und Difficulty vergleichen.

## Delves

- Delve abschließen und Weekly-Rewards-Fortschritt ändern.
- Bountiful-/Wochenzustände prüfen; nicht verfügbare Werte müssen `unknown` bleiben.
- Companion wechseln beziehungsweise Rolle/Curios ändern und erneut scannen.

## Stats und Profile

- Equipment, Spec und Talente ändern.
- Food, Flask, Rune, Proc und Encounter-Buff anwenden; es dürfen keine Aura-/Buffdatensätze synchronisiert werden.
- Jeden bekannten eigenen Charakter auswählen und getrennt speichern.
- Leere Profilfelder dürfen nicht geteilt werden; ausgefüllte Felder auf zweitem Gildenclient prüfen.

## Roster und Charakteransicht

- Online, AFK, DND, offline/zuletzt online, Klassenicon und Klassenfarbe prüfen.
- Holy-Storm-Version, Itemlevel, Mythic+- und Raidwerte prüfen.
- Sortierung, Spaltenbreite/-reihenfolge/-sichtbarkeit sowie gespeichertes Layout prüfen.
- Twink-Gruppierung an/aus und alternative Gruppierungen prüfen.
- Charakter anklicken und den gleichbleibenden Header sowie die internen Tabs Übersicht, Ausrüstung, Mythisch+, Raid, Tiefen, Werte und Twinks kontrollieren.
- Zwischen zwei Charakteren wechseln, während der erste aktualisiert wird; verspätete Daten des ersten Charakters dürfen die zweite Ansicht nicht überschreiben. Anschließend die Zurück-Navigation prüfen.
- Cache-Daten müssen sofort erscheinen. Der Refresh-Status darf danach nur echte Zustände anzeigen und bei mehreren schnellen Modulereignissen nicht den kompletten Frame mehrfach neu aufbauen.
- Equipment-Links und Gem-Tooltips, Raid-/Dungeon-Journal-Links sowie deaktivierte Teleport-Hinweise mit und ohne Kampfzustand prüfen.
- Raid-Weekly-Tooltips für LFR, Normal, Heroisch und Mythisch sowie den Best-Tooltip prüfen: je Boss darf nur die höchste jemals besiegte Schwierigkeit erscheinen.
- Twink-Tab mit Sichtbarkeit „Alle“ und „Nur Gilde“, Account-Main, Gilden-/Shadow-Main sowie administrativer Beziehung prüfen; ein Twink-Link muss im selben Character-Framework öffnen.
- Deutsch und Englisch bei schmaler und breiter Fenstergröße prüfen; lange Listen müssen innerhalb des Tabs scrollbar bleiben.

## News

- Entwurf, veröffentlichte und archivierte News erstellen.
- Genau einen sowie mehrere konkrete Gildenränge auswählen; höhere Ränge dürfen nicht automatisch sehen.
- News lesen, Receipt und Zusammenfassung kontrollieren.
- Gelesene News bearbeiten; neue Version muss wieder ungelesen sein.
- Neues Mitglied synchronisieren; ältere unveränderte News dürfen nicht neu zählen.

## Permissions und Filter

- Eigene Gruppe erstellen, umbenennen, duplizieren und löschen.
- Standardgruppen umbenennen; Löschen muss abgelehnt werden.
- Gildenmeister-Automatik, Offiziersrang, manuelles Mitglied und mehrere Mitgliedschaftsgründe prüfen.
- Änderungen verwerfen und anschließend bewusst speichern.
- Lokale und globale Filter mit UND/ODER/NICHT, Zahlen-, Text-, Bereichs- und Listenoperatoren testen.
- Max-Level, Klasse, Rolle, Main/Twink, Itemlevel, Quest-ID und Achievement-ID testen.
- Regelanalyse mit erfüllten und nicht erfüllten Einzelbedingungen prüfen.

## Logs

- DEBUG/INFO/WARN/ERROR, Modul-, Level- und Textfilter prüfen.
- Pause, Refresh, Clear und Auto-Scroll an/aus testen.
- Spalten verschieben, ausblenden und skalieren; Fenstergröße und gespeichertes Layout prüfen.
- Gefilterten und vollständigen Export als Text, CSV und JSON prüfen.
- Discord-Export in ein Discord-Eingabefeld kopieren und Format/Längenlimit prüfen.
