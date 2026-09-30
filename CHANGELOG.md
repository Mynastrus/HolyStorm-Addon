# Holy Storm Changelog

## Unreleased

### English

- Audited Retail Equipment item APIs, preserved complete item links, separated equipped and overall character item level, rejected unknown slots and unloaded item data instead of storing them as empty, and kept uncertain gems/tier facts unknown in stored Character views.
- Refined Character Overview spacing, compact profile sizing, and dynamic widget height; Mythic+ cards now use a neutral current-season label instead of exposing Blizzard's internal season ID.
- Dynamic providers now form a two-column content-sized grid. Event weekdays and compact card descriptions use localized labels, and an empty achievement catalog has a clear zero state.
- Corrected profile card anchoring and applied the shared dashboard text styles to keep profile content readable.
- Kept online Guild Roster versions current with jittered Sync Presence refreshes and removed them through the existing five-minute freshness policy.
- Kept Mythic+ encounter-end events out of Raid scans, cached only complete lifetime statistic mappings, and split Statistics discovery into bounded central workflow chunks.
- Corrected lifetime Raid Best to count against the full Encounter Journal boss catalog; Best tooltips now show every boss in encounter order, including those without confirmed kills.
- Preserved the stable Raid and boss catalog beside lifetime statistics in the v3 snapshot, rejected empty Encounter Journal container entries by metadata, and added a reload regression fixture for lifetime Best.
- Made character block imports idempotent at equal origin revisions, reject stale revisions and conflicting same-revision content, preserve origin timestamps separately from receiver timestamps, and log bounded block-specific freshness decisions.
- Corrected Character Stats to use Retail's effective paper-doll values, version the persisted baseline, keep live aura changes transient, and show rating separately from effective percentages.
- Unified the five character snapshot block descriptors and semantic comparison, made Equipment commit failures visible to the workflow, and preserved unavailable Delves API state instead of converting it to empty/false values.
- Reframed Delves snapshots around the documented current season and Great Vault World reward data, added weekly reset identity and readiness validation, and removed unsupported placeholders and unrelated scan triggers.
- Consolidated Twink relationships around owner-confirmed AUTO and administrative MANUAL authority, prevented manual relays from replacing AUTO, tombstoned manual moves, and moved TwinkCore onto PlayerData's relationship API.
- Added reusable character context actions for manual assignment, reassignment and removal, with officer and guild-leadership defaults and localized source explanations.

### Deutsch

- Die Retail-Equipment-APIs wurden geprüft. Vollständige ItemLinks bleiben erhalten; angelegte und allgemeine Gegenstandsstufe sind getrennt. Unbekannte Plätze und ungeladene Itemdaten werden nicht als leer gespeichert; unsichere Sockel- und Setdaten bleiben in gespeicherten Charakteransichten unbekannt.
- Twink-Beziehungen unterscheiden nun klar zwischen owner-bestätigter AUTO- und administrativer MANUAL-Autorität. Veraltete manuelle Relays können AUTO nicht überschreiben; manuelle Wechsel werden tombstoniert und TwinkCore verwendet die PlayerData-Beziehungs-API.
- Wiederverwendbare Charakter-Kontextaktionen ermöglichen manuelles Zuordnen, Wechseln und Entfernen. Gildenleitung und Offiziere erhalten die Verwaltungsberechtigung standardmäßig; Quellhinweise sind lokalisiert.

- Delves-Snapshots bilden nun die dokumentierte aktuelle Saison und Weltfortschritte der Großen Schatzkammer ab, nutzen eine Wochenreset-Identität mit Readiness-Prüfung und entfernen unbelegte Platzhalter sowie irrelevante Scan-Trigger.

- Abstände, kompakte Profilgröße und Höhe dynamischer Widgets in der Charakterübersicht wurden verbessert. Mythic+-Karten zeigen nun eine neutrale Bezeichnung für die aktuelle Saison statt Blizzards interner Saison-ID.
- Dynamische Anbieter verwenden nun ein zweispaltiges, inhaltsabhängiges Raster. Wochentage und kompakte Kartenbeschreibungen sind lokalisiert; ein leerer Erfolgskatalog zeigt einen eindeutigen Nullwert.
- Die Profilkarte wurde korrekt verankert und verwendet nun die gemeinsamen Dashboard-Textstile für besser lesbare Profilinhalte.
- Versionsanzeigen für Online-Mitglieder bleiben durch zeitversetzte Sync-Presence-Aktualisierungen aktuell und folgen weiterhin der bestehenden Frischefrist von fünf Minuten.
- Mythic+-Kampfende lösen keine Raid-Scans mehr aus. Vollständige Lebenszeit-Statistikzuordnungen werden zwischengespeichert und die Ermittlung läuft in begrenzten Workflow-Abschnitten.
- Der Raid-Lebenszeitbestwert verwendet nun alle Bosse des Abenteuerführer-Katalogs als Gesamtzahl. Bestwert-Tooltips zeigen jeden Boss in Begegnungsreihenfolge, auch ohne bestätigte Siege.
- Der stabile Raid- und Bosskatalog bleibt zusammen mit den Lebenszeitstatistiken im v3-Snapshot gespeichert. Leere Abenteuerführer-Container werden anhand ihrer Metadaten ausgeschlossen; ein Reload-Regressionstest sichert den Bestwert.
- Charakterblock-Importe behandeln identische Herkunftsrevisionen nun idempotent, verwerfen ältere Revisionen und widersprüchliche Inhalte deterministisch, trennen Ursprungs- und Empfangszeitstempel und protokollieren begrenzte blockbezogene Frischeentscheidungen.
- Charakterwerte folgen nun Blizzards effektiven Retail-Werten. Gespeicherte Baselines sind versioniert, Live-Auraänderungen bleiben transient und Rating wird getrennt vom effektiven Prozentwert angezeigt.
- Die Blockverträge und semantischen Vergleiche der fünf Character Snapshot Pipelines wurden vereinheitlicht. Equipment-Commitfehler werden im Workflow sichtbar; nicht verfügbare Delves-APIs bleiben unbekannt statt als leer oder false gespeichert zu werden.

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
