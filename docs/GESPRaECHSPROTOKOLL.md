# Holy Storm – Gesprächs- und Entscheidungsprotokoll

Chronologische Zusammenfassung unserer fachlichen Gespräche. Nicht als wortgetreues Transkript gedacht.

## 2026-10-28 – Dokumentation im GitHub-Repository
- **Entschieden:** Besprochene Anforderungen, Ideen und technische Beschlüsse sollen in einer oder mehreren Dateien im GitHub-Repository dokumentiert werden.
- **Umsetzung:** Diese Protokolldatei und `PROJECT_WISSEN.md` bilden den Anfang.
- **Hinweis:** Künftige Gespräche werden nicht automatisch synchronisiert; Aktualisierungen müssen jeweils vorgenommen werden.

## 2026-10-26 – Website: Meine Gilden und Communities
- **Entschieden:** Navigationspunkt `Meine Gilden` mit Übersicht aller zugeordneten Gilden.
- **Entschieden:** Gildenbezogene Angaben wie Discord-Invite-Link speichern; standardmäßig privat für den jeweiligen Nutzer, vom Gildenleiter optional öffentlich einstellbar.
- **Zurückgestellt:** WoW-Communities. Blizzard-API-Abdeckung untersuchen; spätere Companion-App oder Companion-Addon denkbar.
- **Offen:** Rollen- und Ownership-Nachweis, Datenmodell, UI und Datenschutz.

## 2026-10-25 – Website/Discord/Workspace
- **Entschieden:** Battle.net-OAuth-Login auf der Website und Verknüpfung mit Discord-OAuth.
- **Entschieden:** Discord-Nutzer bekommen **alle verschiedenen** Gildenrangrollen ihrer aktuell zugehörigen verknüpften Charaktere, nicht ausschließlich den höchsten Rang.
- **Entschieden:** Statusrollen `Gildenmitglied`, `Ehemaliges Gildenmitglied`, `Verifiziert` nach den Regeln in `PROJECT_WISSEN.md`.
- **Geplant:** zentraler VS-Code-Workspace mit Addon, Website, API, WebSockets, Discord, Apps, Infrastruktur und zentralem Deployment.

## Oktober 2026 – Addon, UI und Release
- **Umgesetzt laut früheren Arbeitsberichten, nicht in dieser Dokumentationsänderung neu geprüft:** modulares Addon, Gilden-Roster/UI-Optimierungen, differenzierte Sync-Protokolle und Regressionstests.
- **Anforderung:** GitHub-Actions-/CurseForge-Workflow für Releases verwenden und vor Ausführung auf Aktualität überprüfen.
- **UI-Wunsch:** Suche/Filter ohne Überlagerung unter der Titelleiste des Gildenfensters.

## Vorlage für neue Einträge

### JJJJ-MM-TT – Thema
- **Idee / Entschieden / Implementiert / Verworfen / Offen:**
- **Details:**
- **Betroffene Bereiche:**
- **Nächster Schritt / Prüfung:**

## 2026-10-28 – Datenbanktrennung und Discord-Bot für mehrere Server
- **Anforderung:** Eine reine Import-/Cache-Datenbank für WoW-/Blizzard-API-Daten, eine separate Nutzer-/OAuth-Datenbank und eine eigene Discord-Konfigurationsdatenbank.
- **Anforderung:** Holy-Storm-Discord-Bot soll von berechtigten Gildenleitern auf unterschiedlichen Discord-Servern installiert und pro Server eingerichtet werden können.
- **Konzeptvorschlag:** Drei getrennte MySQL-Schemas `hs_wow`, `hs_users`, `hs_discord`; mandantenfähige Discord-Bot-Verwaltung einschließlich Zuordnung zu WoW-Gilden.
- **Zu prüfen:** Blizzard-API-Nachweis Gildenleitung, Discord-Serververwaltungsrechte, Bot-OAuth-Installation, Multi-Gilden-Server, Rechteisolierung und Sicherheitskonzept.
- **Status:** Diskussion/Konzept, nicht implementiert.
