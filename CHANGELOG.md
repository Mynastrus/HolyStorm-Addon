# Holy Storm Changelog

## Unreleased

### English

- Replaced the separate Guild Roster toolbar with a shared, page-owned context-header slot. Character Overview keeps its existing identity/status HeaderBar in that slot; Guild Roster places search and filters there while its member list uses the remaining content and scroll height. The UIManager, MainWindow, CharacterOverview, and GuildRoster modules were versioned for the new contract.
- Fixed the Dashboard profile rows' vertical anchors. The heading and all available name, birthday and role rows now form one clipped, resize-safe block inside the Character header. Dashboard GameTooltip and LibQTip card tooltips now choose among all four screen sides, avoid other Dashboard cards where space permits, and remain screen-clamped.
- Fixed the Dashboard profile overlay: profile and character identity now share the header-content parent, and measured responsive widths prevent the identity text from extending underneath the profile card. Icons compact or hide at narrow widths, while full profile details remain available on hover.
- Positioned Dashboard tooltips against available screen space, clamped native Character table tooltips, and close stale native/profile tooltips when the selected character or rendered profile data changes.
- Fixed the Delves summary's doubled `DELVES_DELVES_SUMMARY` lookup and expanded the localization contract to validate literal keys behind prefix proxies in both locales. Updated the preferred-role label for compact cards.
- Kept the local Holy Storm version authoritative in the Sync version store, preserved fresh peer versions across versionless Presence and repeated login reconciliation, and limited version DEBUG logs to actual changes and expiry. Guild Roster reads every version from the store.
- Fixed Retail Mythic+ scans for Blizzard's current `CalendarTime.monthDay` best-run dates, made `GetSeasonBestAffixScoreInfoForMap` optional, derived map scores from Blizzard-selected best runs, and added bounded readiness retries with compact stable-reason diagnostics. Mythic+ snapshots are now v5.
- Audited Character Overview consumers against stored snapshot contracts; corrected Equipment v4 unknown socket/tier rendering, stale Raid weekly display, strict legacy-version handling, data-driven Stats rows, header identity metadata, and read-only tab switching. Documented the consumer matrix and Retail acceptance sequence.
- Kept the seven base Character tabs in the requested order and moved the separately registered Achievements tab after them.
- Audited current Retail Mythic+ APIs and moved Character snapshots to v4 with complete dynamic map-pool validation, direct season/rating data, Blizzard-selected timed and overtime records, current-period Mythic+ Great Vault thresholds, and no persisted volatile keystone or inferred Fortified/Tyrannical categories.
- Updated stored Mythic+ views to use stable map IDs, separate timed/overtime records, current-season gating, Blizzard rating colors and correctly labeled Great Vault thresholds; documented the API contract and in-client acceptance checklist.
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

- Die separate Gildenroster-Toolbar wurde durch einen gemeinsamen, seitenabhängigen Kontext-Header ersetzt. Die Charakterübersicht behält ihren bestehenden HeaderBar für Identität und Status; das Gildenroster zeigt Suche und Filter dort an. Die Mitgliederliste nutzt die verbleibende Content- und Scrollhöhe. UIManager, MainWindow, CharacterOverview und GuildRoster erhalten Versionen für den neuen Vertrag.
- Die vertikalen Anker der Profilzeilen sind korrigiert. Überschrift sowie Name, Geburtstag und Rolle bleiben zusammenhängend und innerhalb des Charakter-Headers; beim Ändern der Fensterbreite wird das Layout neu berechnet. Dashboard-Tooltips für GameTooltip und LibQTip prüfen alle vier Bildschirmseiten, meiden nach Möglichkeit andere Karten und bleiben am sichtbaren Bildschirm begrenzt.
- Die Überlagerung der Profilkarte ist behoben: Profil und Charakteridentität verwenden jetzt denselben Header-Inhaltsbereich. Die gemessenen responsiven Breiten verhindern, dass Identitätstext unter die Profilkarte läuft. Bei geringer Breite werden Icons verkleinert oder das Spezialisierungsicon ausgeblendet; vollständige Profildetails bleiben im Tooltip zugänglich.
- Dashboard-Tooltips berücksichtigen den verfügbaren Bildschirmplatz. Native Tooltips der Charaktertabellen werden am Bildschirm gehalten; veraltete Profil- und native Tooltips schließen beim Charakter- oder Datenwechsel.
- Der doppelte Locale-Zugriff `DELVES_DELVES_SUMMARY` ist korrigiert. Der Localization Contract prüft nun auch literale Schlüssel über Präfix-Proxies in beiden Sprachen. Die Rollenbezeichnung wurde für kompakte Karten verkürzt.
- Die lokale Holy-Storm-Version bleibt im Sync-Versionsstore autoritativ. Versionslose Presence-Updates und wiederholte Login-Abgleiche erhalten noch gueltige Peer-Versionen. Das Gildenroster liest alle Versionen aus dem Store; DEBUG-Eintraege entstehen nur bei tatsaechlichen Aenderungen und beim Ablauf.
- Retail-Mythic+-Scans unterstützen nun Blizzards aktuelles Datumsfeld `CalendarTime.monthDay`. `GetSeasonBestAffixScoreInfoForMap` ist optionale Detailinformation; Dungeonwertungen stammen aus Blizzards Bestläufen. Begrenzte Readiness-Retries und kompakte Reason-IDs machen Scanfehler sichtbar. Mythic+-Snapshots verwenden Schema v5.
- Die Character-Overview-Consumer wurden mit den gespeicherten Snapshot-Verträgen abgeglichen. Unbekannte Sockel-/Tierdaten in Equipment v4, veraltete Raid-Wochenbindungen, Legacy-Versionen, dynamische Stats-Zeilen, Header-Identität und Tab-Wechsel ohne Scan sind korrigiert. Consumer-Matrix und Retail-Abnahmefolge sind dokumentiert.
- Die sieben Basis-Character-Tabs bleiben in der gewünschten Reihenfolge; der separat registrierte Erfolge-Tab folgt danach.
- Die aktuellen Retail-Mythic+-APIs wurden geprüft. Character-Snapshots verwenden nun Schema v4 mit vollständigem dynamischem Dungeonpool, direkter Saison und Gesamtwertung, getrennten Blizzard-Bestläufen (In Time/Over Time) und aktuellen Mythisch+-Schatzkammer-Schwellen. Veränderliche Schlüssel sowie abgeleitete Tyrannisch-/Verstärkt-Kategorien werden nicht mehr gespeichert.
- Gespeicherte Mythisch+-Ansichten verwenden stabile Karten-IDs, getrennte Laufrekorde, eine aktuelle Saisonprüfung, Blizzards Wertungsfarben und korrekt bezeichnete Schatzkammer-Schwellen. API-Vertrag und In-Game-Abnahmecheckliste sind dokumentiert.
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
