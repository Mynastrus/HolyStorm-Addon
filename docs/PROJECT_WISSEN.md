# Holy Storm – Projektwissen und Entscheidungen

Stand: 2026-10-28. Diese Datei dokumentiert gemeinsame Planungen und Entscheidungen. Sie ist keine Bestätigung, dass jede geplante Funktion implementiert ist.

## Zweck und Pflege

Zentrale, versionierte Wissensbasis zu Holy Storm. Neue fachliche Entscheidungen, Änderungen und offene Fragen mit Datum ergänzen. Laufende Gesprächsnotizen stehen in [GESPRaECHSPROTOKOLL.md](GESPRaECHSPROTOKOLL.md). Bestehende Fakten bei Änderung aktualisieren; Geheimnisse, API-Schlüssel, Passwörter und personenbezogene OAuth-Tokens niemals eintragen.

**Wichtig:** Chat-Unterhaltungen werden nicht automatisch in GitHub synchronisiert. Aktualisierungen benötigen einen GitHub-Schreibvorgang im jeweiligen Gespräch/Arbeitsablauf.

## Projekte und Infrastruktur

- WoW-Retail-Addon: Repository `Mynastrus/HolyStorm-Addon`, Standardbranch `main`. Modulbasiertes Addon mit Core, UI, Gildenfunktionen, Charakterübersichten, Sync, Rechteverwaltung und optionalen Featuremodulen.
- Website: Repository `Holy_Storm_Website` (Name aus bisheriger Planung), öffentliche Website `holystorm.de`.
- Geplante/verwaltete Subdomains: `dev.holystorm.de` (Entwicklerportal), `addon.holystorm.de`, `api.holystorm.de`, `app.holystorm.de`, `discord.holystorm.de`, `ws.holystorm.de` (WebSockets).
- Hosting: Plesk; SSH, Node.js, Cronjobs, MySQL verfügbar. Zentrales Deployment für die Webbereiche angestrebt.
- Entwicklungsumgebung: zentraler VS-Code-Workspace mit Bereichen ADDON, WEBSITE, API, WEBSOCKETS, DISCORD, APPS, INFRASTRUCTURE, SHARED, SERVER, DATABASE, DOCS. Quellcode unter Git, Geheimnisse außerhalb des Repositories in privaten Umgebungsdateien.

## Addon – etablierte Architektur (Stand aus bisherigen Gesprächen)

- WoW Retail, Ace3, deutsche und englische Lokalisierung.
- Core: SavedVariables, Tasks, Snapshot/Revision, Sync-Kommunikation und Berechtigungsregeln.
- UI: Hauptfenster mit Navigation, Charakterübersicht sowie Admin-/Gildenfunktionen.
- Module unter anderem Characters, Equipment, Raids, MythicPlus, Delves, Achievements, Guild, Chat, Stats.
- Performanceziele: bedarfsgesteuerte Synchronisierung, keine pauschalen umfangreichen Login-Snapshots; modulare Load-on-Demand-Struktur.
- Releaseprozess über GitHub-Workflow/CurseForge; tatsächlichen Workflow vor jedem Release im Repository prüfen.
- UI-Wunsch: Suche und Filter im Gilden-Roster ordentlich im Bereich unter der Titelleiste platzieren; keine Überlagerungen.

## Website / Kontoverknüpfung – entschieden bzw. geplant

- Anmeldung auf der Website mittels Battle.net OAuth.
- Discord-Konto kann zusätzlich über Discord OAuth verknüpft werden.
- Website soll Charakter-/Gildenbezüge und Discord-Rollen automatisch zuordnen, vorbehaltlich verfügbarer API-Daten, Berechtigungen und Implementierung.
- Menüpunkt **Meine Gilden**: zeigt die Gilden, denen der angemeldete Nutzer zugeordnet ist.
- Pro Gilde können Zusatzinformationen wie Discord-Einladungslinks hinterlegt werden.
- Ein normaler Nutzer kann einen Discord-Link privat für sich speichern. Ein Gildenleiter kann den Link zusätzlich öffentlich sichtbar machen. Berechtigung serverseitig prüfen.
- **WoW-Communities vorerst nicht implementieren.** API-Unterstützung und ein späteres Companion-Addon/eine App als mögliche Integrationswege gesondert untersuchen.

## Discord-Rollensynchronisation – beschlossene Regeln

Voraussetzung für automatische Zuordnung: Battle.net-Login auf der Website und zusätzlich verknüpftes Discord-Konto.

1. Für **jeden unterschiedlichen WoW-Gildenrang**, den mindestens einer der verknüpften aktuell zugehörigen Charaktere hat, wird die passende Discord-Rolle vergeben. Nicht nur der höchste Rang!
2. Bei Rangwechseln und Gildenaustritten werden Rollen aktualisiert; Rollen, die über andere Charaktere weiterhin zutreffen, bleiben erhalten.
3. **Gildenmitglied:** mindestens ein verknüpfter Charakter ist aktuell Mitglied.
4. **Ehemaliges Gildenmitglied:** früher zugehörig, aktuell kein verknüpfter Charakter mehr Mitglied.
5. **Verifiziert:** Battle.net-Anmeldung und Discord-Verknüpfung erfolgreich, unabhängig von aktueller Gildenmitgliedschaft.

Offen für technische Ausarbeitung: Quellen der Charakterzuordnung, Polling/Webhooks, Fehlerbehandlung, Historie ehemaliger Mitglieder, Zuordnung von mehreren Gilden zu Discord-Servern und Lösch-/Datenschutzregeln.

## Entwicklerportal (MVP-Konzept)

- `dev.holystorm.de`: Übersicht zu Projekten, Status-/GitHub-Checks, optionalen Adaptern und Deployments.
- GitHub-Daten: Branches, Commits, Releases, Workflows; Addon: Module und WoW-Interface-Version.
- Sicherheitsziele: abgesicherte Administrationsanmeldung, CSRF-Schutz, Session-Timeout, Rate-Limiting und sichere Cookies.
- Noch nicht konfigurierte Integrationen dürfen nicht als aktiv dargestellt werden.

## Arbeitsregeln

- Neue Featureideen als **Idee**, bestätigte Anforderungen als **Entschieden**, umgesetzte Features erst nach Code-/Testprüfung als **Implementiert** markieren.
- Änderungsdatum und betroffene Komponenten notieren.
- Vor Codeänderungen aktuelle Repository-Struktur und vorhandene Tests prüfen.
- Nie Zugangsdaten oder persönliche Kontodaten in die Dokumentation committen.
- Entscheidungen, die mehrere Repositories betreffen, sollten später in eine zentrale übergreifende Dokumentationsquelle gespiegelt werden.
