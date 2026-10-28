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

## 2026-10-28 – Datenbankarchitektur und Multi-Server-Discord (Konzept)

- **Vorgeschlagen, noch nicht implementiert:** getrennte logische MySQL-Datenbanken `hs_wow` (aus Blizzard importierte WoW-Daten), `hs_users` (Holy-Storm-Konten und Battle.net-/Discord-OAuth), `hs_discord` (Discord-Konfiguration, Server-, Gilden- und Rollenverknüpfungen).
- Datenbanken dürfen auf demselben MySQL-Server liegen; unabhängige Zugriffsrechte pro Dienst/Schema einrichten. Bei übergreifenden Beziehungen stabile IDs und Service-Schnittstellen verwenden, statt unkontrollierte direkte Schreibzugriffe.
- `hs_wow`: Charaktere, Gilden, Ränge, Realms, API-Abrufzeitpunkte und Importstatus; importierte Daten von nutzereigenen Einstellungen trennen.
- `hs_users`: User-IDs, OAuth-Identitäten und Charakterzuordnungen, Sitzungen; OAuth-Secrets/Tokens nicht unverschlüsselt speichern, minimal benötigte Scopes und Löschkonzept.
- `hs_discord`: Discord-Guild-IDs, WoW-Gilden↔Discord-Server-Zuordnung, Bot-Installationsstatus, Einstellungen, Rollenmapping, Sync-Status/Audit. Ein Bot soll auf mehreren Discord-Servern nutzbar sein (**mandantenfähig**), mit isolierten Rechten/Einstellungen je Server. Optional mehrere WoW-Gilden pro Discord-Server erlauben.
- **Geplanter Ablauf:** WoW-Gildenleiter meldet sich per Battle.net an, Holy Storm prüft seine Gildenverwaltungsberechtigung, danach verknüpft er einen Discord-Server, auf dem er die nötigen Discord-Managementrechte besitzt, installiert/autorisiert den Bot und konfiguriert ihn über die Website.
- **Offen / technisch zu prüfen:** Ob und wie der Gildenleiterstatus zuverlässig über verfügbare Blizzard-Daten nachweisbar ist; Verifikation der Discord-Serverberechtigung; Discord-OAuth-Scopes und Bot-Berechtigungen; Entzug von Berechtigungen, Installation/Deinstallation, Gildenwechsel, Mehrfachzuordnungen und Datentrennung.
- **Wichtig:** Das ist ein Architekturentwurf, keine Zusage bereits vorhandener Datenbanken oder Live-Bot-Funktionen.

## 2026-10-28 – Discord-Bot-Installation: konkretisierter Ablauf

- **Vom Nutzer festgelegter Zielablauf:** Battle.net-OAuth-Login → eigene Charaktere und ihre Gilden über Blizzard-API ermitteln → anhand des Roster-Rangs Gildenleitung prüfen → Discord-Konto per OAuth verknüpfen → Discord-Nutzer ist einer WoW-Gildenleitung zugeordnet → Bot auf einem ausgewählten Discord-Server installieren.
- Der Nutzer möchte bei der Installation **Administrator-Berechtigung für den Bot anfordern**, die der Installierende im Discord-Dialog bestätigt. Diese Produktanforderung ist als Wunsch notiert; Sicherheitsprüfung vor Umsetzung: Administrator ist sehr weitreichend, minimal benötigte Einzelberechtigungen bevorzugen, sofern der Funktionsumfang es erlaubt.
- Die Installation durch Discord-Nutzer setzt ausreichende Serverberechtigung voraus (Discord-Dokumentation: `MANAGE_GUILD` für Server-Installation, nicht zwingend selbst Administrator).
- **Sicherheitsanforderung:** Gildenleiter-Berechtigung nicht nur aus einer Gildenzugehörigkeit ableiten, sondern verlässlichen Roster-Rang/Gildenleiterstatus mit aktueller API prüfen; OAuth-Konto- und Charakterbesitz nachweisen; IDs serverseitig verifizieren. Auch Bot-Installation, Serverzuordnung und aktuelle Serververwaltungsrechte unabhängig prüfen.
- Mehrmandantenfähigkeit: Bot-Einstellungen und Rollenmapping strikt nach Discord-Server und verknüpfter WoW-Gilde isolieren.
- **Status:** fachlich konkretisierter Entwurf, nicht implementiert.

## 2026-10-28 – Registrierung direkt aus Discord (Machbarkeitsfrage)

- **Idee / zur Entscheidung:** Nutzer sollen die Holy-Storm-Registrierung auch direkt in Discord über den Bot beginnen können, ohne manuell zuerst die Website aufzurufen.
- **Technisch möglich:** Discord-Slash-Command `/registrieren`, Buttons, Auswahlfelder und Modals starten den Ablauf; der Bot kennt die Discord-User-ID aus einer validierten Interaction und kann einen kurzlebigen, einmaligen Verknüpfungsvorgang in der zentralen API anlegen.
- **Notwendiger externer Schritt:** Die Autorisierung des Battle.net-Kontos und die Freigabe des `wow.profile`-Scopes erfolgen über Blizzards OAuth-Anmeldeseite im Browser. Discord-Bot darf nicht nach Battle.net-Passwort fragen. Der Callback verbindet die verifizierte Battle.net-Identität sicher mit der gestarteten Discord-Interaction (state/nonce, TTL, Einmalnutzung).
- **Nach erfolgreichem Callback:** API legt/verknüpft Holy-Storm-Konto; importiert WoW-Charaktere nach Berechtigung; prüft ggf. Gildenleiterstatus; Discord-Bot bestätigt den Erfolg per privater Antwort/DM, sofern zulässig. Derselbe Account wird später über die Website nutzbar.
- **Noch offen:** Registrierung als optionaler Discord-Einstieg oder bevorzugter Standard; Bestätigungs-UX, Ablauf bei bereits vorhandenem Konto und notwendige Sicherheits-/Datenschutzmaßnahmen.
- **Status:** Machbarkeitskonzept, noch nicht implementiert.

## 2026-10-28 – Discord-Rollen über mehrere Gilden und Server (Anforderungen)

- **Entschieden:** Registrierung wahlweise auf holystorm.de oder per Discord-Slash-Befehl; beide Wege nutzen dasselbe zentrale Benutzerkonto und OAuth-Verknüpfungen.
- **Entschieden:** Ein Discord-Server kann mehrere WoW-Gilden abbilden; eine gemeinsame Plattform unterstützt viele Discord-Server und WoW-Gilden.
- **Entschieden:** Der jeweils berechtigte Gildenleiter konfiguriert pro WoW-Gilde ihre Gildenränge mit Namen und Reihenfolge/Rangnummer (nicht allein Freitextnamen als ID). Die Rangnummern und aktuelle Rangzuordnung sind gegen Blizzard-Roster-Daten zu validieren.
- **Entschieden:** Der Bot kann die zugeordneten Discord-Gildenrangrollen automatisch anlegen, speichern und anhand der aktuell verknüpften Charaktere vergeben/entziehen. Ein Benutzer bekommt alle unterschiedlichen zutreffenden Rangrollen.
- **Entschieden:** WoW-Klassenrollen (z. B. Krieger und Magier) werden ebenfalls automatisch erstellt und je nach Charakterbestand vergeben; Spieler mit mehreren Klassen erhalten alle zutreffenden Klassenrollen.
- **Sicherheit/Logik:** Eine Rollenabbildung benötigt mindestens Discord-Server-ID, WoW-Gilden-ID, Rangindex sowie Discord-Rollen-ID; so kollidieren gleichnamige Ränge verschiedener Gilden nicht. Klassenrollenumfang pro Gilde/Server konfigurieren, um Mehrgilden-Mehrdeutigkeiten zu vermeiden. Discord-Rollenrechte und Hierarchie des Bots müssen vor automatischer Erstellung/Zuweisung geprüft werden.
- **Noch offen:** Ob Klassenrollen aus allen verknüpften Charakteren oder nur aus Charakteren der auf dem Discord-Server zugeordneten Gilden entstehen; Benennung von Rollen bei mehreren Gilden und Reconciliation gelöschter/umbenannter Rollen.
- **Status:** beschlossene Fachanforderungen, technische Details noch nicht implementiert.

## 2026-10-28 – Klassenrollen je Gilde optional (bestätigt)

- **Entschieden:** Klassenrollen-Synchronisierung ist pro zugeordneter WoW-Gilde auf einem Discord-Server ein-/ausschaltbar. Gildenrangrollen bleiben davon unabhängig aktiv.
- Wenn die Klassenrollenfunktion für eine Gilde aktiviert ist, legt der Bot benötigte Rollen an und vergibt sie anhand der verknüpften Charaktere dieser Gilde. Bei deaktivierter Funktion keine automatische Klassenrollenvergabe für diese Gilde.
- **Offen:** Gemeinsame oder gildengetrennte Klassenrollen bei mehreren Gilden auf demselben Discord-Server; insbesondere Rollenentzug nur, wenn keine andere aktivierte Gilde die jeweilige Klasse benötigt.
- **Berechtigungen geprüft:** Discord verlangt `MANAGE_ROLES` für das Erstellen und Verwalten von Rollen; Botrolle muss oberhalb verwalteter Rollen stehen. `ADMINISTRATOR` ist dafür nicht notwendig und hebt Rollenhierarchie nicht auf. Quelle: https://discord.com/developers/docs/topics/permissions und https://discord.com/developers/docs/resources/guild
- **Status:** Fachanforderung dokumentiert; noch nicht implementiert.

## 2026-10-28 – Konfiguration im Webportal und optional über Discord

- **Entschieden:** Die Einstellungen für Discord-Gildenrollen und optionale WoW-Klassenrollen werden bevorzugt im Holy-Storm-Webportal vorgenommen; optional sollen dieselben Einstellungen auch über Discord möglich sein. Das Webportal wird als einfacherer Weg empfohlen.
- Webportal zeigt nach OAuth-Anmeldung die verwaltbaren Gilden und verbundenen Discord-Server; pro Gilde können Klassenrollen aktiviert/deaktiviert sowie Gildenrang-Zuordnungen verwaltet werden.
- Discord-Bot übernimmt die Ausführung (Rollen anlegen und synchronisieren), kann Registrierung bzw. Verknüpfung anstoßen und soll optional Einstellungen per Slash-Befehl/Interaktionen ändern können. Beide Oberflächen nutzen die zentrale API und dieselbe Datenbank als gemeinsame Quelle; Berechtigungsprüfung und Validierung erfolgen serverseitig.
- **Status:** fachlich entschieden, technische Umsetzung offen.

## 2026-10-28 – Holy-Storm-Pilot und modulare Discord-Pakete

- **Entschieden:** Zunächst ausschließlich eigene Gilde Holy Storm und ihren Discord-Server testen; Architektur für andere Gilden/Server vorbereiten, aber noch nicht öffentlich anbieten.
- **Entschieden:** Bot soll je nach Auswahl Kategorien und Channels automatisch erstellen und konfigurieren können, um den Server dynamisch aufzubauen.
- **Entschieden:** Funktionspakete sind einzeln durch berechtigte Gildenleiter aktivierbar und deaktivierbar. Beispiel: Klassen-Paket erstellt WoW-Klassenrollen und synchronisiert sie mit verknüpften Charakteren. Weitere Pakete für Kategorien und Channels sind zu planen.
- Einstellungen primär im Webportal, optional in Discord, über dieselbe zentrale API.
- **Empfehlung:** Vorschau vor Strukturänderungen; verwaltete Discord-Rollen, Kanäle und Kategorien anhand ihrer IDs speichern, um Duplikate zu vermeiden. Beim Abschalten keine automatischen Löschungen von Kanälen oder Inhalten ohne Bestätigung.
- **Technik:** Rollenverwaltung benötigt Manage Roles und passende Rollenhierarchie; Channels/Kategorien benötigen Manage Channels. Administrator ist nicht pauschal erforderlich.
- **Offen:** Paketliste, Abhängigkeiten, Kanalnamen, Berechtigungen, Verhalten beim Abschalten und Umgang mit bereits vorhandenen Discord-Ressourcen.
- **Status:** Konzeptanforderungen, noch nicht implementiert.

## 2026-10-28 – Vollständige Discord-Serverstrukturen als Pakete

- **Entschieden:** Pakete dürfen komplette vorkonfigurierte Discord-Strukturen erstellen, nicht nur einzelne Rollen oder Kanäle.
- **Beispiel Raid-Paket (Konzept):** eigene Raid-Kategorie mit passenden Textkanälen (z. B. Anmeldung und Organisation), Sprachkanälen, zugehörigen Rollen und vorkonfigurierten Kanalberechtigungen.
- **Entschieden:** Gildenleiter aktivieren/deaktivieren Pakete einzeln; das Webportal ist die empfohlene Konfigurationsoberfläche, Discord die optionale Alternative.
- **Umsetzungshinweise:** Paketdefinitionen versionieren, Ressourcen über Discord-IDs verfolgen, vor Änderungen Vorschau anzeigen, bestehende Serverstruktur berücksichtigen; bei Deaktivierung keine Kanäle oder Inhalte kommentarlos löschen.
- **Status:** bestätigte Anforderung, noch nicht implementiert. Detailumfang einzelner Pakete wird später ausgearbeitet.
