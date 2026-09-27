# Holy Storm Changelog

## Unreleased

### English

- Refined Character Overview spacing, compact profile sizing, and dynamic widget height; Mythic+ cards now use a neutral current-season label instead of exposing Blizzard's internal season ID.

### Deutsch

- Abstände, kompakte Profilgröße und Höhe dynamischer Widgets in der Charakterübersicht wurden verbessert. Mythic+-Karten zeigen nun eine neutrale Bezeichnung für die aktuelle Saison statt Blizzards interner Saison-ID.

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
