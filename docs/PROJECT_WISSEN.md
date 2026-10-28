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

## 2026-10-28 – Priorität Discord-Bot und kanalübergreifende Raid-Anmeldungen

- **Priorität 1 (entschieden):** Zuverlässig funktionierender Holy-Storm-Discord-Bot für den internen Pilotbetrieb; Slash-Kommandogruppe bevorzugt `/hs`. Erweiterte Pakete zur automatischen Erstellung kompletter Kategorien/Kanäle/Raidstrukturen bleiben zunächst optional bzw. nachrangig.
- **Entschieden:** Eine zentrale Raid-/Event-API mit einer gemeinsamen persistierten Datenquelle; Discord, Website und später Mobil-/Desktop-App nutzen dieselben Events und Anmeldungen. Anmelden, abmelden und Status ändern müssen von allen Oberflächen aus denselben Datensatz aktualisieren.
- **Entschieden:** Discord soll die Raid-Anmeldeliste automatisch aktualisieren; Website/App zeigen denselben aktuellen Stand. Technisch Discord-Nachrichten gezielt editieren; Aktualisierungen ereignisbasiert (API-Events/WebSocket wo passend), mit idempotenten Schreiboperationen und periodischer Abstimmung bei verpassten Events.
- **Entschieden:** Beim Anmelden Hauptcharakter als Voreinstellung vorschlagen; Spieler dürfen einen anderen verknüpften, zulässigen Charakter auswählen.
- **Entschieden:** Pro Anmeldung Charakter und Spezialisierung festhalten und zugehörige Raid-Rolle (Tank, Heiler, Nahkampf-DD, Fernkampf-DD) ableiten/anzeigen, insbesondere bei Multi-Rollen-Klassen (z. B. Druide Balance = Fernkampf-DD, Wiederherstellung = Heiler).
- **Später geplant:** Companion-Addon zeigt Events ingame und bietet Anmeldungen an. WoW-Addon kann nicht selbst beliebig direkt externe HTTP-APIs aufrufen oder zuverlässig beim Logout einen externen Server kontaktieren; tatsächlicher Transfer benötigt einen unterstützten Companion-/Import-/Export-/Client-Weg und belastbare Konfliktauflösung. Logout/Relog-Synchronisierung als Ziel, nicht als bereits technisch gesichert.
- **Offen für spätere Ausarbeitung:** Event-Typen/Termine/Zeitzonen, Zusage-/Absage-/Vielleicht-/Wartelistenstatus, Raid-Leiter-Rechte, Main-Charakter-Regel, Spezialisierungsvalidierung, Teilnehmerlimits, Datenschutz und Verbindungs-/Offline-Strategien. Event-/Teilnehmer-Daten sinnvollerweise als eigenes fachliches Modul/Schema; Datenbankzuschnitt noch entscheiden.
- **Status:** Anforderungen und Umsetzungsreihenfolge festgehalten, nicht implementiert.

## 2026-10-28 – Raid-Anmeldestatus und Wartelistenregeln

- **Entschieden:** Raid-Anmeldung unterscheidet **Zugesagt**, **Vorläufig** (Teilnahme unsicher), **Abgemeldet** (nimmt nicht teil) sowie **Warteliste** (vorerst kein Platz). Status soll über Discord, Website und später Apps zentral synchronisiert werden.
- **Entschieden:** Bei Überbelegung ist der Zeitpunkt der Anmeldung die grundsätzliche Reihenfolge/Fairnessregel (wer zuerst angemeldet ist, wird vorrangig berücksichtigt), zugleich müssen Rollenbedarf und Gruppenaufstellung berücksichtigt werden können.
- **Entschieden:** Raidleitung darf Teilnehmer manuell priorisieren, bestätigen oder umsetzen und damit die automatische Reihenfolge bei Bedarf übersteuern. Solche Eingriffe sollten mit Zeit, Bearbeiter und Grund nachvollziehbar protokolliert werden.
- **Empfohlene konkrete Logik zur späteren Detailentscheidung:** Zugesagte Plätze besetzen primär bestätigte Teilnehmer. Frei werdende Plätze werden aus der Warteliste bevorzugt nach benötigter Rolle (Tank/Heiler/Nahkampf-DD/Fernkampf-DD), innerhalb geeigneter Kandidaten nach frühem Anmeldezeitpunkt besetzt. Vorläufig angemeldete Personen zählen gesondert, damit sie Plätze nicht unbemerkt dauerhaft blockieren. Raidleitung kann umsortieren. Charakter und Spezialisierung sind Bestandteil der Anmeldung.
- **Offen:** Ob Wartelisten-Nachrücken automatisch verbindlich wird oder zuerst eine Bestätigung erfordert; wie Anmeldefristen, vorläufige Teilnehmer, Rollenquoten und Nachrückbenachrichtigungen gehandhabt werden.
- **Status:** vier Status und Grundprinzipien bestätigt, Detailalgorithmus noch zu beschließen und zu implementieren.

## 2026-10-28 – Nachrücken mit verpflichtender Bestätigung

- **Entschieden:** Wer von der Raid-Warteliste nachrückt, wird nicht sofort als fest zugesagt behandelt. Stattdessen erhält die Person ein **Nachrückangebot**, das sie aktiv bestätigen oder ablehnen kann.
- **Geplant für die Handy-App:** Push-Benachrichtigung („Du bist für den Raid nachgerückt – bitte bestätige deine Teilnahme“) mit Bestätigungs- bzw. Ablehnmöglichkeit; Push benötigt später App-Einwilligung und funktionsfähige Geräte-/Push-Infrastruktur.
- **MVP-Vorschlag:** Derselbe Bestätigungsprozess zunächst über Discord-Bot-Interaktionen/private Nachrichten oder einen persönlichen Hinweis mit Link, falls DM-Zustellung nicht möglich ist; später Website und App ebenfalls über die zentrale Raid-API.
- **Technische Empfehlung:** eigener Zwischenstatus „Bestätigung ausstehend“ für angebotenen Platz; optional konfigurierbare Antwortfrist. Bei Ablehnung oder Fristablauf Platz an den nächsten nach Rollenbedarf geeigneten Wartelistenplatz anbieten. Doppelte Zusagen und parallele Angebote durch atomare Reservierungen verhindern.
- **Offen:** Konkrete Frist, Benachrichtigungskanäle und Eskalation bei Nichtzustellung.
- **Status:** Bestätigungspflicht und spätere App-Push-Benachrichtigung beschlossen; konkrete Ablaufparameter noch offen.

## 2026-10-28 – Automatische rollenbasierte Warteliste und Raid-Voraussetzungen

- **Entschieden:** Teilnehmer können sich nicht selbst auf die Warteliste setzen. Sie werden automatisch dort eingeordnet, wenn die maximale Teilnehmerzahl insgesamt oder das Kontingent für ihre ausgewählte Rolle erreicht ist. Beispiel: Bei 20 Gesamtplätzen werden nach Vollbelegung weitere Anmeldungen wartend geführt; bei nur zwei Heilerplätzen kommt der dritte Heiler auch dann auf die Warteliste, wenn andere Rollen noch freie Plätze haben.
- **Entschieden:** Die Raidleitung definiert bei Erstellung Gesamtplätze und gewünschte Rollenverteilung (Tanks, Heiler, DDs; optional feinere Unterteilung). Die konkrete Rollenverteilung muss konsistent zur Gesamtzahl sein; Beispiel „2 Tanks, 2 Heiler, 9 DDs“ umfasst 13 Plätze, nicht 20.
- **Entschieden:** Bei Anmeldung kann der Spieler neben dem bevorzugten Charakter und dessen Spezialisierung alternative geeignete Charaktere, Spezialisierungen und Rollen angeben („könnte auch …“). Diese Alternativen gelten zunächst als Angebote, nicht als mehrere belegte Raidplätze. Die Raidleitung darf unter geeigneten Optionen auswählen und umstellen.
- **Entschieden:** Die Raidleitung legt für einen Raid Mindest-Charakterlevel und Mindest-Itemlevel fest. Die Plattform prüft ausgewählte Haupt-/Alternativcharaktere gegen verfügbare, möglichst aktuelle WoW-Daten; fehlende oder veraltete Daten werden ausdrücklich gekennzeichnet statt als nachgewiesen behandelt. Itemlevelprüfung passend zum gewünschten Regelwerk (z. B. equipped vs. average) später festlegen.
- **Entschieden aus vorherigem Gespräch:** Beim Nachrücken gilt Rollenbedarf vor Anmeldezeit innerhalb gleicher Eignung; angebotene Plätze müssen aktiv bestätigt werden.
- **Offen:** Umgang mit vorläufigen Teilnehmern und Reservierungen bei Rollenquoten, Alternativeinsatz nach Rückfrage, Raidleitung-Override bei Mindestwerten, Zusammenstellung und Reihenfolge, Verfügbarkeit/Aktualität der Itemlevel-Daten.
- **Status:** Fachregeln entschieden; Detailalgorithmus und Implementierung offen.

## 2026-10-28 – Erweiterte Raid-Zugangsvoraussetzungen

- **Entschieden:** Die Raidleitung kann pro Event zusätzlich zu Mindestlevel und Mindest-Itemlevel erforderliche Vorquests/Quest-Abschlüsse und konkrete WoW-Erfolge als Teilnahmevoraussetzungen festlegen.
- **Entschieden:** Alle Voraussetzungen werden im Raid-Event klar sichtbar als **Anforderungen / Requirements** in der Beschreibung angezeigt, auch auf Discord und später in Website, App und Companion.
- **Geplante Prüfung:** Wo die Blizzard-API den Quest-/Erfolgsstatus des betreffenden verknüpften Charakters belastbar bereitstellt, automatisch prüfen. Kontoweite Erfolge, Charakterbindung und API-Zugriffs-/Datenlücken ausdrücklich berücksichtigen.
- **Sicherheit/UX:** Nicht verifizierbare Bedingungen als „nicht automatisch prüfbar“ markieren, nicht ungeprüft als erfüllt behaupten. Raidleitung kann solche Bedingungen nach eigenen Regeln manuell bestätigen oder Ausnahmen erteilen. Charakter- und Spezialisierungswechsel müssen die Zulassungsprüfung erneut auslösen.
- **Offen:** Umgang mit unerfüllten Anforderungen (Anmeldung sperren oder vorbehaltlich zulassen), Quest-IDs/Erfolgs-IDs, kontoweit vs. charakterbezogen, Mindest-Itemlevel-Definition.
- **Status:** Produktanforderung bestätigt, noch nicht implementiert.
