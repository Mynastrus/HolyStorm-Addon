# Holy Storm – Administration Host

## Zweck und Verantwortungsgrenze

`UI/Administration/AdministrationRegistry.lua` ist der zentrale Host für administrative Oberflächen. Er besitzt genau einen Eintrag im rechten Dock des bestehenden `MainWindow` und darin eine dynamische, kategorisierte `AceGUI TreeGroup`-Navigation. Der Host koordiniert Registrierung, Verfügbarkeit, Anzeige, Refresh und Lifecycle; fachliche Permission-, Gruppen-, Rule- oder Filteroperationen verbleiben in den jeweiligen Core-Komponenten beziehungsweise Modulen.

Der Core enthält keine Liste optionaler Feature-Module. Eine Seite erscheint nur, wenn ihr Owner sie registriert und ihre deklarierten Voraussetzungen zur Laufzeit erfüllt sind.

## Öffentliche API

- `HolyStorm.Administration:RegisterSection(definition)`
- `HolyStorm.Administration:UnregisterSection(id)`
- `HolyStorm.Administration:UnregisterOwner(owner)`
- `HolyStorm.Administration:GetSection(id)`
- `HolyStorm.Administration:GetSections(visibleOnly)`
- `HolyStorm.Administration:IsSectionAvailable(id)`
- `HolyStorm.Administration:Open(sectionId)`
- `HolyStorm.Administration:Refresh(sectionId)`
- `HolyStorm.Administration:RefreshNavigation()`
- `HolyStorm.Administration:RegisterCategory(id, definition)`
- `HolyStorm.Administration:GetNavigationModel()`

Die Convenience-Funktionen `HolyStorm:RegisterAdministrationSection`, `HolyStorm:UnregisterAdministrationSection` und `HolyStorm:GetAdministrationSections` delegieren auf denselben Host. `RefreshSections` bleibt als Alias für bestehende Verbraucher erhalten.

## Section Contract

Pflichtfelder sind `id` und entweder `page` oder `build`. Unterstützte Metadaten sind:

- `owner`, optional `moduleId`
- `category`, `order`
- `title`/`displayName` oder `titleKey`/`displayNameKey`
- `description` oder `descriptionKey`
- `icon`
- `permission` beziehungsweise kompatibel `requiredPermission`; eine Liste bedeutet standardmäßig „mindestens eine“, `permissionMode="all"` verlangt alle
- `requires.module`, `requires.capability`
- `isAvailable(section, context)`
- `events` für gezielten Content-Refresh und `availabilityEvents` für eine erneute Gating-/Navigationsprüfung
- `build(parent, context)`, `show(section, context)`, `hide(section, context)`, `refresh(section, context)`, `destroy(section, context)`

`build` darf einen WoW-Frame oder ein AceGUI-Widget zurückgeben. Der Host baut eine Section erst bei ihrer ersten Anzeige. Ein vom Host gebautes AceGUI-Widget wird beim Entfernen freigegeben, sofern die Section keinen eigenen `destroy`-Callback besitzt. `render` bleibt als Compatibility-Name für `refresh` gültig.

## Registration Lifecycle

Eine direkte Registrierung ist nach dem Laden von `AdministrationRegistry.lua` möglich. Zusätzlich wertet `ModuleRegistry` nichtleere `metadata.administration`-Definitionen aus. Definitionen, die vor dem Host eintreffen, werden zwischengespeichert und nach dessen Initialisierung registriert. Doppelte IDs werden abgelehnt; wiederholtes Refresh erzeugt keine zweiten Navigationszeilen oder Event-Handler.

Beim Entfernen werden sectionbezogene Event-Handler abgemeldet, die sichtbare Seite verborgen und ihr Destroy-Lifecycle ausgeführt. Wird die aktive Section ungültig, wählt der Host deterministisch die erste noch verfügbare Section. Bleibt keine Section übrig, verschwindet der Administration-Dockeintrag und ein geöffneter Host kehrt zur Startseite zurück.

## Permission-, Modul- und Capability-Gating

Permissions werden ausschließlich mit `PermissionEngine:HasPermission` ausgewertet. Nicht autorisierte Sections fehlen vollständig in der Navigation. Die dynamische Vollzugriffsregel der geschützten Gildenleitung bleibt damit unverändert in der PermissionEngine.

`requires.module` prüft ein tatsächlich geladenes und aktiviertes Modul sowie den gildenweiten Modulstatus. Metadaten eines lediglich bekannten, aber nicht geladenen Optional-Moduls genügen nicht. `requires.capability` verwendet die zentrale ModuleRegistry und akzeptiert nur Handler aktivierter Module. Direkte Referenzen auf optionale Module sind nicht erforderlich.

## Navigation und Sortierung

Die eingebauten Kategorien definieren nur Bezeichnungen und Reihenfolge; sie erzeugen keine leeren Seiten: Allgemein, Berechtigungen, Gruppen/Rollen, Regeln, Filter, Module sowie System/Diagnose. Zusätzliche Kategorien sind registrierbar.

Sortiert wird nach Kategorie-Reihenfolge, Section-Reihenfolge, lokalisiertem Titel und abschließend technischer ID. Kategorien ohne verfügbare Section erscheinen nicht.

## Gemeinsame UI-Implementierung

Der Host selbst liegt in einem `UILayout`-Container; der Section-Kontext stellt
`components` und `layout` für interne und externe Erweiterungen bereit. Die
eingebauten Sections `permissions`, `rules`, `filters` und `policyInspector`
registrieren ausschließlich einen lazy `build`-Callback. Damit werden weder die
komplexen Editoren noch ihre Diagnoseansichten beim Login konstruiert.

Alle eingebauten Seiten verwenden `UIComponents`-Rows/-Columns, die gemeinsame
`HolyStormTabGroup`, `CreateScrollContainer` und die generische Table. Die Table
besitzt wiederverwendete Rows/Cells und einen allgemeinen Selection-State.
`PolicyUI` adaptiert darauf die wiederverwendbaren Listen, Checklisten und den
Rule-Tree. Nur native WoW-Dropdowns und EditBoxen bleiben als elementare Controls;
sie bilden keine parallele Layout-, Scroll- oder Tabellenimplementierung.

Die Gruppen-/Permission-Seite bewahrt Section, Gruppe, Unterreiter, Auswahl und
Table-Scrollposition im Controller, solange die Section gebaut bleibt. Rule- und
Filter-Seiten bewahren entsprechend Scope, ausgewähltes Objekt, Entwurf und
Scrollzustand. Frames oder andere transiente UI-Objekte werden nicht persistiert.

## Refresh und Events

Section-spezifische `events` markieren nicht eine zweite UI als zuständig, sondern rufen gezielt deren `refresh` auf. Der Host aktualisiert Gating und Navigation insbesondere bei Permission-/State-/Gruppenänderungen, Modul-Lifecycle, Capability-Registrierung, Roster- und Guild-Updates. Relevante Host-Events sind:

- `HS_ADMINISTRATION_SECTION_REGISTERED`
- `HS_ADMINISTRATION_SECTION_UNREGISTERED`
- `HS_ADMINISTRATION_NAVIGATION_UPDATED`
- konsumiert: `HS_MODULE_AVAILABILITY_CHANGED`, `HS_CAPABILITY_REGISTERED`, `HS_CAPABILITY_UNREGISTERED` und die zentralen Permission-/Guild-Events

## Gruppen- und Permission-Administration

Die registrierte Section `permissions` verwendet keine eigene Fachlogik und keine SavedVariables-Zugriffe. Sie liest Gruppen aus `GroupManager`, effektive Mitgliedschaften und Rechte aus `PermissionEngine`, Definitionen aus `PermissionRegistry` sowie Rules/Filter aus `FilterManager`. Entwürfe werden ausschließlich über die Manager-/State-APIs committed; Stale-Revisionen werden vor dem Speichern verworfen und der Core wiederholt jede Autorisierungs- und Invariantenprüfung.

Systemgruppen sind gesperrt und lokalisiert. Automatische System-/Gildenrangquellen, manuelle Character-/Accountquellen und Filter-/Rule-Quellen werden getrennt angezeigt. Die Permission-Matrix entsteht vollständig aus der aktiven Registry und enthält keine statische Feature-Permission-Liste. Factory Reset und Custom-Group-Löschung verwenden bestätigte, lokalisierte Dialoge und erzeugen normale Revisionen.

## Rule- und Filter-Administration

Holy Storm besitzt eigenständige wiederverwendbare Rule-Objekte und Filter-Objekte. Beide Seiten verwenden denselben `PolicyUI`-Rule-Tree-Editor und dieselbe `RuleEngine`; die UI implementiert weder Evaluator noch Operatorsemantik. Der Editor unterstützt Conditions, verschachtelte AND-/OR-/NOT-Gruppen, Hinzufügen, Entfernen, Hoch/Runter sowie Ein-/Ausrücken. Field-, Operator- und Value-Auswahl entstehen aus den aktiven Registries. Boolean-, Enum-, Character-, Account- und Mehrfachwerte verwenden strukturierte Auswahl, Number-/String- und Range-Werte typbezogene Eingaben.

Die Table-basierten Listen zeigen Name, ID, Objektversion beziehungsweise Referenzanzahl und Availability. Suche umfasst Name, ID, Kategorie und beteiligte Provider. Details zeigen Auditmetadaten, Baum, Referenzen, Preview und CRUD-Aktionen. Leere Listen, fehlende Fields, fehlende Preview-Entities, unbekannte Felder und referenzgeschützte Löschungen besitzen lokalisierte Zustände. Globale Create/Edit/Delete-Aktionen werden mit den vorhandenen granularen Filter-Permissions beziehungsweise `rules-manage` gegated und im Core erneut autorisiert.

Preview verwendet `FilterManager:Preview` und zeigt den von `RuleEngine` erzeugten Diagnose-Trace mit Actual/Expected Value, Provider und UNKNOWN-Grund. Sie persistiert nichts und ändert insbesondere keine Gruppenmitgliedschaft. Field-Provider-Diagnose liest `RuleEngine:GetFieldDiagnostics`. Registry-, Modul-, Character-, Roster-, Gruppen-, Referenz- und State-Events aktualisieren die Seiten ohne Polling.

## Abhängigkeiten und Lokalisierung

Der Host verwendet `UIManager`, `MainWindow`, `UILayout`, `UIComponents`, die generische Table, `AceGUI-3.0`, `EventBus`, `PermissionEngine`, `PolicyState` und die ModuleRegistry. Die Host-Texte und Core-Kategorien liegen in `Holy_Storm_Policy` für `enUS` und `deDE`. Externe Sections können bereits lokalisierte Texte, eine `locale`-Tabelle, `localeName` oder eine `localize`-Funktion liefern.

Der Compatibility-Vertrag `page` bleibt absichtlich bestehen, weil externe
Sections bereits aufgebaute Frames liefern dürfen. Er ist kein zweiter aktiver
Administration-Host. Ebenso bleiben `render` als Alias für `refresh` und
AceGUI-Widget-Rückgaben erhalten. Die ausgelieferten Core-Sections verwenden
diese Compatibility-Pfade nicht mehr.

## Beispiel einer Modul-Section

```lua
metadata.administration = {
    {
        id = "example-settings",
        category = "modules",
        order = 100,
        titleKey = "ADMIN_TITLE",
        descriptionKey = "ADMIN_DESCRIPTION",
        localeName = "Holy_Storm_Example",
        permission = "example-manage",
        requires = { capability = "example.configure" },
        build = function(parent, context)
            local page = context.components:CreateColumn(parent, {
                gap = 8,
                padding = 12,
            })
            -- Gemeinsame Components/Table verwenden.
            return page
        end,
        refresh = function(section, context)
            -- Daten der bereits gebauten UI aktualisieren.
        end,
    },
}
```

Das Beispiel ist ausschließlich Dokumentation und registriert keine Produktiv-Section.
