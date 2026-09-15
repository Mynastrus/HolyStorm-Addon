# Holy Storm – Projektkontext

## Zweck

Dieses Repository entwickelt ein **World of Warcraft Retail Addon**. Dieser
Kontext dient als zentrale, dauerhaft gepflegte Referenz für technische
Entscheidungen, Konventionen und wichtige Projektinformationen.

## Zielplattform

- Spiel: World of Warcraft Retail
- Addon-Sprache: Lua
- Benutzeroberfläche: WoW UI API (XML und/oder Lua)
- Addon-Metadaten: `.toc`-Datei

## Grundstruktur eines WoW-Addons

Ein Addon benötigt normalerweise:

1. Einen Addon-Ordner unter `World of Warcraft/_retail_/Interface/AddOns/`.
2. Eine `.toc`-Datei mit Metadaten und der Reihenfolge der zu ladenden Dateien.
3. Lua-Dateien für Logik und Event-Verarbeitung.
4. Optional XML- oder Lua-Dateien für Frames und UI-Elemente.

## Auslieferungsstruktur

Alle auslieferbaren Addon-Dateien werden ausschließlich unter `LIVE/` erstellt.
`LIVE/` enthält einen Addon-Ordner (`Holy_Storm/`), der als Ganzes direkt nach
`World of Warcraft/_retail_/Interface/AddOns/` kopiert werden kann. Die
Dateien in der Projektwurzel – beispielsweise diese Kontextdatei – gehören
nicht zum installierbaren Addon.

## Wichtige technische Regeln

- Nur Funktionen der WoW UI API verwenden; keine externen Netzwerkzugriffe.
- Ereignisse über `Frame:RegisterEvent()` registrieren und in
  `OnEvent`-Handlern verarbeiten.
- Persistente Einstellungen über `SavedVariables` in der `.toc` definieren.
- Die Lade-Reihenfolge in der `.toc` ist relevant: gemeinsame Hilfsfunktionen
  müssen vor Dateien geladen werden, die sie nutzen.
- Beim Testen UI mit `/reload` neu laden und Lua-Fehler aktiv prüfen.

## Geplante Projektdaten

- Addon-Name: Holy Storm
- Ziel/Funktionen: _noch festzulegen_
- Gespeicherte Einstellungen: _noch festzulegen_
- Slash-Befehle: _noch festzulegen_

## Entwicklungsnotizen

Hier werden künftig Entscheidungen, API-Hinweise, unterstützte WoW-Versionen
und offene Aufgaben ergänzt.

## Changelog-Regel

Jede Änderung innerhalb von `LIVE/` wird in `CHANGELOG.md` festgehalten. Dazu
zählen auch Ordner- und Dateierstellungen, Löschungen, Umbenennungen sowie
Änderungen an Addon-Code und dessen Konfiguration. Änderungen außerhalb von
`LIVE/` werden nicht im Changelog erfasst. Der zugehörige Eintrag beschreibt
kurz, was geändert wurde und warum, falls dies nicht offensichtlich ist.

## Release-Regel

Veröffentlichungen werden im Ordner `RELEASES/` abgelegt. Für jede
Veröffentlichung wird der vollständige Inhalt von `LIVE/` als ZIP-Datei
komprimiert. Das Namensformat lautet:

`Holy Storm vX.X.X.zip`

Beispiel: `Holy Storm v1.0.0.zip`. Die ZIP-Datei enthält damit den Ordner
`Holy_Storm/`, der direkt nach `Interface/AddOns/` entpackt werden kann.

Vor jedem Release wird die aktuelle WoW-Retail-Interface-Version geprüft. Der
Wert in der Zeile `## Interface:` muss anschließend in der TOC-Datei des
Core-Addons und in jeder Modul-TOC auf diesen aktuellen Wert gesetzt werden.
Diese Anpassung ist auch dann erforderlich, wenn sich am Addon-Code nichts
geändert hat. Da die TOC-Dateien unter `LIVE/` liegen, wird die jeweilige
Anpassung zusätzlich im Changelog festgehalten, bevor das ZIP erstellt wird.

## Versionierung der Lua-Dateien

Jede eigene Lua-Datei des Addons verwaltet ihre eigene Versionsnummer über die
lokale Variable `addonVersion`. Beim Laden wird diese Nummer am zugehörigen
Addon-Teil als `version` gespeichert. Eine Änderung an einer Lua-Datei erhöht
deren eigene Versionsnummer; die Versionsnummern anderer Lua-Dateien bleiben
davon unberührt. Eingebundene Drittanbieter-Bibliotheken behalten ihre eigene
Versionsverwaltung. Die Versionsnummer in einer TOC-Datei beschreibt weiterhin
das gemeinsame Release.

Für jede Änderung an einer eigenen Lua-Datei wird die Version direkt erhöht:

- Fehlerkorrektur oder kleine interne Anpassung: Patch (`1.0.0` → `1.0.1`)
- Neue, rückwärtskompatible Funktion: Minor (`1.0.0` → `1.1.0`)
- Inkompatible Änderung an einer bestehenden Schnittstelle: Major
  (`1.0.0` → `2.0.0`)

Das Werkzeug `tools/Update-AddonVersion.ps1` führt diese Erhöhung für die
angegebenen Lua-Dateien aus. Die Änderung der Versionsnummer wird gemeinsam
mit der fachlichen Änderung im Changelog dokumentiert.

## Addon-Architektur

Der Core bindet Ace3 lokal ein, nutzt es jedoch nur für Addon-/Modul-Lifecycle,
Konfiguration und UI-Komponenten. `Core/Bootstrap/Bootstrap.lua` erstellt den Namespace und
steuert ausschließlich Initialisierung, Login-Zustände und die initiale
Datenerfassungsreihenfolge. WoW- und interne Ereignisse laufen über
`HolyStorm.Events`; teure Arbeiten über die priorisierte, deduplizierende
`HolyStorm.Tasks`-Queue.

Persistenz und Fachzugriffe sind getrennt: `Persistence/Database.lua` verwaltet AceDB,
Defaults und Schema-Versionen. `Persistence/GuildStore.lua`, `Persistence/PlayerStore.lua` und
`Persistence/CharacterStore.lua` kapseln Gilden-, Spieler- und Charakterdaten. Eine
accountweite Installationskennung verbindet eigene Charaktere automatisch mit
dem lokalen Spielerprofil. Blizzard-Daten besitzen Vorrang vor empfangenen
Synchronisationsdaten.

Kommunikation, Serialisierung, Synchronisation, Berechtigungen, Hooks, Aktionen
und UI-Verwaltung sind eigenständige Core-Dienste. Fachmodule liegen nach Domäne
unter `Modules/`; UI-Grundlagen und Einstellungsseiten unter `UI/`. Optionale
Module werden weiterhin über `HolyStorm:RegisterOptionalModule()` registriert
und über das AceDB-Profil aktiviert. Alle Module gehören zum selben Addon und
besitzen keine eigenen TOC-Dateien.

Verpflichtend sind UI, Optionen, SavedVariables-Anzeige, Gildenroster und
Charakterverwaltung. Optional sind Equipment, Raids, Mythisch+, Kalender,
Berufe, Gildenlog und Tiefen.

XML-Dateien werden nach Möglichkeit vermieden. Bibliotheken und Lua-Dateien
werden direkt und in der erforderlichen Reihenfolge über die Core-TOC geladen.

Die Core-TOC enthält die passenden Metadaten für diese Veröffentlichung:
`Interface`, `Title`, lokalisierte Titel und Hinweise, `Author`, `Category`,
`DefaultState`, `Version` und `SavedVariables`. Metadaten für nicht vorhandene
Funktionen – beispielsweise `IconTexture` oder `AddonCompartmentFunc` – werden
erst ergänzt, wenn die zugehörigen Assets oder Funktionen existieren.

## Modul-Metadaten

Jedes Modul erhält Metadaten über `HolyStorm:ApplyModuleMetadata()`. Diese
enthalten mindestens `displayName`, `internalName`, `version`, `category`,
`description`, `permissions`, `dependencies` und `enabledByDefault`.
`permissions` beschreibt die vom Modul benötigten fachlichen Zugriffsrechte;
die technische Durchsetzung dieser Rechte wird bei der jeweiligen Funktion
ergänzt.

## Lokalisierung

Alle nutzersichtbaren Texte werden über AceLocale-3.0 und die Sprachdateien in
`LIVE/Holy_Storm/Locales/` verwaltet. `enUS.lua` dient als vollständige
Standardsprache; `deDE.lua` enthält die deutsche Übersetzung. Jedes Modul
besitzt zusätzlich einen eigenen `Locales/`-Ordner mit eigenen `enUS.lua`- und
`deDE.lua`-Dateien. Neue sichtbare Modultexte werden ausschließlich in den
Sprachdateien des jeweiligen Moduls ergänzt. Der Zugriff erfolgt über
`L["KEY"]`. Auch sichtbare TOC-Metadaten erhalten sprachspezifische Einträge
wie `Title-deDE` und `Notes-deDE`.

Vor jedem Release muss die Prüfung mit
`powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\Test-Localization.ps1`
erfolgreich ausgeführt werden. Sie schlägt fehl, wenn Übersetzungen in einer
unterstützten Sprache fehlen, ein verwendeter Schlüssel nicht in `enUS.lua`
definiert ist oder eine typische direkte Textausgabe erkannt wird. Ein Release
darf erst erstellt werden, wenn die Prüfung ohne Fehler endet.
