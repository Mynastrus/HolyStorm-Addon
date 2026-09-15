# Holy Storm – Permission-Architektur

## Komponenten

- `PermissionRegistry.lua`: Registry aller bekannten Permission-Definitionen mit ID, Kategorie, Modul/Owner, Label- und Description-Key. Module können weitere Permissions registrieren.
- `PermissionEngine.lua`: baut Account-/Character-/Guild-Kontext, ermittelt Membership-Gründe, effektive Gruppen und additive Rechte und liefert Erklärungen, Matrizen und Zusammenfassungen.
- `GroupManager.lua`: normalisiert und verwaltet System- und Custom-Gruppen, Mitgliedschaften, Permissions und `managerGroupIds`.
- `RuleEngine.lua` (`HolyStorm.Rules`): validiert und evaluiert Condition Trees über registrierte Felder und Operatoren mit `PASS`, `FAIL` und `UNKNOWN`.
- `FilterManager.lua`: verwaltet lokale sowie gildenweite Rules/Filter und deren Verknüpfung mit Gruppen.
- `PolicyState.lua`: hält den gildenbezogenen Permission-State, autorisiert und validiert Mutationen und erzeugt Revisionen.
- `PermissionSync.lua`: exportiert/importiert den State, führt Catch-up aus und steuert vertrauensgebundene Recovery.
- `Policy.lua`: Compatibility-Fassade, die bestehende Methoden auf die Komponenten delegiert. Sie ist nicht die neue Fachlogikschicht.

Zusätzliche Compatibility-Oberflächen bleiben `HolyStorm.Permissions`, `HolyStorm.PermissionManager` und `HolyStorm:HasPermission`. Legacy-Role-Methoden delegieren auf Gruppenoperationen.

## State und Systemgruppen

Jede Gilde besitzt einen State mit `groups`, `filters`, `rules`, `modules`, `version`, `revisionID`, `previousRevisionID`, History, Rejected-Revisions, Status und Recovery-/Catch-up-Metadaten.

Die drei geschützten Systemgruppen sind:

- `guild-leadership`: aktuelle Blizzard-Gildenleitung plus zulässige zusätzliche Memberships; effektiver Vollzugriff auf alle registrierten Permissions.
- `officers`: dynamische Systemmitgliedschaft über Blizzard-Gildenrang 1 sowie weitere konfigurierte Quellen.
- `guild-member`: dynamische Mitgliedschaft aller sichtbaren Gildenmitglieder.

Systemgruppen können nicht gelöscht werden. Geschützte Identität, Name-Key, Systemregel und Ersteller werden im Core validiert. Änderungen an zusätzlichen Leadership-Mitgliedschaften darf nur der tatsächlich aktuelle Blizzard-Gildenleiter vornehmen; die UI ist nicht die Sicherheitsgrenze.

## Membership Sources

Gruppenmitgliedschaft kann gleichzeitig aus mehreren Quellen entstehen:

- `SYSTEM`: Blizzard-Gildenleitung, Offiziersrang oder allgemeine Gildenmitgliedschaft.
- `CHARACTER`: explizite Character-UUID.
- `ACCOUNT`: Account-/Player-UUID und damit auch zugeordnete Twinks.
- `GUILD_RANK`: konfigurierter Blizzard-Gildenrang.
- `FILTER`: passender gildenweiter Filter.
- `RULE`: passende wiederverwendbare Rule.

PermissionEngine liefert strukturierte Gründe; die Administration zeigt die Quellen getrennt an. `UNKNOWN` aus nicht verfügbaren Rule-Feldern ist kein `PASS`.

## Effektive Rechte

Rechte sind additiv: Die Vereinigungsmenge der Permissions aller effektiven Gruppen gilt. Es gibt keine Deny-Vererbung. Ein tatsächlicher Blizzard-Gildenleiter oder ein Mitglied von `guild-leadership` erhält dynamisch jede aktuell in PermissionRegistry registrierte Permission; dafür existiert keine statische Vollzugriffsliste in der UI.

`managerGroupIds` bedeutet ausschließlich, dass Mitglieder der referenzierten Manager-Gruppen die Zielgruppe im Rahmen weiterer Core-Invarianten verwalten dürfen. Die Manager-Gruppe erhält weder Mitgliedschaft noch Permissions der Zielgruppe. Manager-Zyklen werden bei State-Validierung abgelehnt.

## Rules und Filter

Rules bestehen aus Bedingungen oder verschachtelten `AND`-/`OR`-/`NOT`-Bäumen. RuleEngine ist die einzige Auswertungsengine. Das Ergebnis enthält Boolean-Kompatibilität, Tri-State und Trace. FilterManager speichert gildenweite Objekte revisionsbasiert im Permission-State und persönliche lokale Objekte im Profil. Die Admin-Seiten verwenden denselben zentralen Condition Builder, aber keine eigene Auswertung.

## Revision Chain

Jede autorisierte gildenweite Änderung erzeugt:

- monoton steigende `version`
- neue `revisionID`
- exakte `previousRevisionID`
- `changedBy` mit Account- und Character-UUID
- `changedAt`
- eine typisierte Change-Payload

Die Revision wird erst nach Autorisierung, Apply und vollständiger Snapshot-Validierung committed. Danach werden Events emittiert, Caches invalidiert, die History begrenzt fortgeschrieben und die Permission-Sync-Domain veröffentlicht.

## Catch-up, Recovery und Konflikte

Statuswerte sind `UNINITIALIZED`, `VALID`, `CATCHING_UP`, `RECOVERY_REQUIRED` und `CONFLICT`.

- Eine fehlende direkte Vorgängerrevision startet Catch-up über die vorhandene Permission-Task-/Sync-Kette.
- Kann die Kette nicht lückenlos validiert werden, bleibt der State `RECOVERY_REQUIRED`.
- Snapshot-Recovery akzeptiert nur den implementierten Trust Anchor: einen direkt sichtbaren aktuellen Blizzard-Rang-0-Gildenleiter.
- Zwei verschiedene Revisionen mit gleicher Version und gleichem Vorgänger sind ein Fork und führen zu `CONFLICT`.
- Eine höhere Version gewinnt niemals allein aufgrund ihrer Nummer.
- Alte oder doppelte Revisionen werden erkannt; abgelehnte Revisionen bleiben begrenzt diagnostizierbar.

Die Administration zeigt Gilden-ID, Status, Version, Revision, Vorgänger, Last Sync, Changed By/At, History, Rejected Count, fehlende Revisionen, Catch-up und Fork-Daten. Sie bietet keine unsichere „höchste Version übernehmen“-Aktion.

## Factory Reset

`RestoreDefaults` erzeugt eine normale autorisierte `RESET`-Revision. Version und Revision Chain werden nicht zurückgesetzt. Der Reset:

- ersetzt die drei Systemgruppen durch Defaults und entfernt Custom-Gruppen,
- entfernt manuelle Memberships, Manager-, Permission-, Filter- und Rule-Zuweisungen,
- entfernt gildenweite Custom-Rules und Custom-Filter,
- setzt den gildenweiten Modul-/Policy-Status zurück.

Persönliche lokale Rules/Filter bleiben erhalten. Player-/Character-Daten, Snapshots, Equipment, Mythic+, Raid, Delves, Achievements, Content, POIs, Logs und Twink-Identität werden nicht verändert.

## Trust-Grenzen

WoW-Addons besitzen keine kryptografische Identität, keine geheimen Schlüssel und keinen vertrauenswürdigen Server. Autorisierung basiert daher auf sichtbaren Blizzard-Gildeninformationen, ownergebundener Provenance, direkter Senderzuordnung soweit verfügbar und einer lückenlosen Revision Chain. Ein manipuliertes Client-Addon kann Pakete erzeugen; das System reduziert Schaden durch Validierung, Trust Anchor, explizite Autorisierung, Fork-Erkennung und Ablehnung unsicherer Recovery.

## Administration und Logging

Die Administration greift direkt auf Registry, Engine, GroupManager, FilterManager, Rules und PolicyState zu. Mutationen erfolgen ausschließlich über Manager-/State-APIs. Group-, Membership-, Permission-, Rule-/Filter-, Reset-, Revisions-, Catch-up-, Recovery- und Konfliktaktionen verwenden den zentralen Logger und die bestehenden Events.

## Verbleibende Restschuld

Feature-Permissions sind noch überwiegend zentral in PermissionRegistry registriert:

- Roster/Professions: `guild-roster-read`, `roster-manage`, `professions-read`
- News/Guides: `news-view/create/edit/delete/publish/read-receipts` und `guide-view/create/edit/delete/publish`
- Calendar/Raid/Mythic+/Delves/Equipment: `calendar-read/manage`, `raids-read`, `mythicplus-read`, `delves-read`, `equipment-read`
- Logs/Tasks/Twinks: `logs-view/clear`, `taskmanager-view/control`, `tasks-view`, `twinks-assign/remove`
- POI/Positions: sämtliche `poi-*`-Definitionen sowie `position-view/share`
- Achievements: `achievement-view/create/edit/delete/publish/award/revoke/admin/test`

Die Achievement-Definitionen tragen bereits `Achievements` als Modulmetadatum; viele andere Feature-Definitionen werden im zentralen Definitionsblock noch mit `Core` als Owner registriert. RuleEngine besitzt weiterhin Core-seitig Feature-Felder für Equipment, Mythic+, Raid und Delves sowie Quest-/Achievement-Demand-Provider. Beide Registries sind erweiterbar; die Verlagerung zu den Feature-Modulen ist ein separater Folgeschritt.
