# Holy Storm Changelog

## 5.11.0 — 24.10.2026

### English

- Added Guild Roster search, saved filter profiles and a responsive context header with search, filters and refresh controls. Quick filters can be combined, and the search covers the roster information already shown in the table.
- Added account-level player profiles and centralized settings and commands. Character context actions now support managing alt-character relationships with the existing permission rules.
- Refined Character Overview and profile layouts for narrow and resized windows. Identity and profile content now fit together, and tooltips choose available screen space and close when their data becomes stale.
- Improved synchronization and data integrity: current owner data keeps authority over relayed character copies, stale or conflicting updates are rejected, and identical updates no longer create duplicate work. Online roster versions stay current without duplicate notices.
- Reduced Guild Activity and Activity Points work during captures and updates. The stores now update the affected account data without repeatedly copying or replaying the full guild history.
- Improved character data collection and display across Equipment, Stats, Raids, Mythic+, Delves and Achievements. Current Retail API results and reset periods are handled more reliably; unavailable or uncertain values remain unknown instead of being shown as empty or inferred.
- Fixed POI World Map pins and Retail Minimap key handling so map markers render and refresh consistently.
- Corrected Guild Roster Retail dropdown behavior and improved Dashboard, profile and character-table tooltips. Fixed the Delves summary localization key and updated English and German labels, compact-card text, weekdays and empty states.

### Deutsch

- Die Gildensuche, gespeicherte Filterprofile und ein responsiver Kontext-Header mit Suche, Filtern und Aktualisierung wurden ergänzt. Schnellfilter lassen sich kombinieren; die Suche umfasst die bereits in der Tabelle angezeigten Mitgliederdaten.
- Kontobezogene Spielerprofile sowie zentrale Einstellungen und Befehle wurden ergänzt. Charakter-Kontextaktionen können Twink-Beziehungen unter den bestehenden Berechtigungsregeln verwalten.
- Die Charakterübersicht und Profil-Layouts passen sich besser an schmale und geänderte Fenster an. Identität und Profilinhalte bleiben gemeinsam im verfügbaren Platz; Tooltips nutzen freie Bildschirmbereiche und schließen bei veralteten Daten.
- Synchronisierung und Datenintegrität wurden verbessert: Aktuelle Daten des Besitzers haben Vorrang vor weitergeleiteten Charakterkopien, veraltete oder widersprüchliche Updates werden verworfen und identische Updates erzeugen keine doppelte Arbeit. Versionsanzeigen im Online-Gildenroster bleiben aktuell, ohne doppelte Hinweise auszulösen.
- Guild Activity und Activity Points benötigen bei Erfassung und Aktualisierung weniger Arbeit. Es werden die betroffenen Accountdaten aktualisiert, statt wiederholt den gesamten Gildenverlauf zu kopieren oder erneut auszuwerten.
- Erfassung und Anzeige der Charakterdaten für Ausrüstung, Werte, Raids, Mythic+, Tiefen und Erfolge wurden verbessert. Aktuelle Retail-APIs und Reset-Zeiträume werden zuverlässiger berücksichtigt; nicht verfügbare oder unsichere Werte bleiben unbekannt, statt als leer oder abgeleitet angezeigt zu werden.
- POI-Pins auf der Weltkarte und die Retail-Minimap-Schlüssel wurden korrigiert, damit Kartenmarkierungen zuverlässig angezeigt und aktualisiert werden.
- Das Retail-Dropdown des Gildenrosters wurde korrigiert; Dashboard-, Profil- und Charaktertabellen-Tooltips wurden verbessert. Der Lokalisierungsschlüssel der Tiefen-Zusammenfassung ist behoben; englische und deutsche Beschriftungen, kompakte Kartentexte, Wochentage und Leerzustände wurden aktualisiert.

## 5.9.0 — 27.09.2026

### English

- Redesigned Character Overview as a responsive home dashboard with character and profile details, interactive Equipment, current-season Mythic+, lifetime Raid Best, Delves, Achievements, Stats and Twinks cards, plus optional News, Calendar and guild-achievement widgets.
- Improved stored Character views for Equipment, Mythic+, Raids, Delves, Achievements and Stats. Raid lifetime progress uses validated Blizzard Statistics; localized `/hs scan` commands and Raid scan status make manual refreshes and diagnostics available in game.
- Added Guild Activity tracking and account-based Activity Points and Activity Score, including rules, adjustments and decay. Activity Score does not change guild ranks. Added Guild Management Notes and Absences.
- Reworked Administration around the shared UI framework, with reusable layouts, clearer selectors, improved section lifecycle and diagnostics, and protected permission behavior.
- Improved synchronization with bounded HSC1 receive state, a central AceCommQueue transport, and stronger handling of identity, provenance and stale data.
- Added and centralized shared addon infrastructure, including LibQTip, LibDataBroker, LibDBIcon, LibSharedMedia, AceCommQueue and LibGuildRoster. Standardized the Holy Storm launcher, minimap and window icon.
- Added the schema 13 migration to consolidate legacy character and account data while preserving character history and guild data. Malformed and future schemas remain protected.
- Improved Retail compatibility, stability and localization. Development builds now show `DEV` when package metadata is unresolved; packaged builds continue to use the release version. Fixed tooltip title calls for the current Retail `GameTooltip:SetText` signature and hardened Calendar handling of protected values.

### Deutsch

- Die Charakterübersicht wurde als responsives Dashboard mit Charakter- und Profildaten neu gestaltet. Interaktive Karten zeigen Ausrüstung, aktuelle Mythic+-Wertung, Raid-Lebenszeitbestwert, Tiefen, Erfolge, Werte und weitere Charaktere; optionale Widgets zeigen News, Kalenderereignisse und Gildenerfolge.
- Gespeicherte Charakteransichten für Ausrüstung, Mythic+, Raids, Tiefen, Erfolge und Werte wurden verbessert. Der Raid-Lebenszeitfortschritt basiert auf validierten Blizzard-Statistiken. Lokalisierte `/hs scan`-Befehle und der Raid-Scanstatus unterstützen manuelle Scans und deren Diagnose.
- Guild Activity sowie accountbasierte Aktivitätspunkte und ein Aktivitätswert wurden ergänzt, einschließlich Regeln, Korrekturen und Verfall. Der Aktivitätswert verändert keine Gildenränge. Die Gildenverwaltung bietet nun Notizen und Abwesenheiten.
- Die Administration verwendet jetzt das gemeinsame UI-Framework mit wiederverwendbaren Layouts, verständlicheren Auswahlfeldern, verbessertem Seiten-Lifecycle und Diagnosen sowie geschütztem Berechtigungsverhalten.
- Die Synchronisierung wurde durch begrenzte HSC1-Empfangszustände, einen zentralen AceCommQueue-Transport und eine robustere Behandlung von Identität, Herkunft und veralteten Daten verbessert.
- Gemeinsame Addon-Infrastruktur wurde ergänzt und zentral eingebunden, darunter LibQTip, LibDataBroker, LibDBIcon, LibSharedMedia, AceCommQueue und LibGuildRoster. Das Holy-Storm-Symbol für Launcher, Minikarte und Fenster ist vereinheitlicht.
- Die Migration auf Datenbankschema 13 führt alte Charakter- und Account-Daten zusammen und erhält Charakterhistorie und Gildendaten. Fehlerhafte und neuere, unbekannte Schemas bleiben geschützt.
- Retail-Kompatibilität, Stabilität und Lokalisierung wurden verbessert. Entwicklungs-Builds zeigen bei nicht aufgelösten Paketmetadaten `DEV`; Paket-Builds verwenden weiterhin die Release-Version. Tooltip-Titel verwenden nun die aktuelle Retail-Signatur von `GameTooltip:SetText`; der Kalender behandelt geschützte Werte sicher.
