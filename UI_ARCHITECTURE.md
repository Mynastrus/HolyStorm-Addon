# Holy Storm – deklarative UI-Architektur

## Zweck und Grenze

`Holy_Storm_UI` ist der optionale, zentrale Renderer für Holy Storm. Fachmodule
liefern View-Beschreibungen, Spalten, Daten, Renderer und Aktionen. Das UI-Addon
besitzt Layout, WoW-Frames, Interaktionszustände und den View-Lifecycle. Es
enthält keine Character-, Equipment-, Raid-, Kalender- oder Permission-
Fachlogik.

Der bestehende `RegisterUIExtension`-Vertrag bleibt der ladeordnungsunabhängige
Einstieg eines Feature-Addons. Sobald die UI bereit ist, registriert die
Extension ihre Views über `HolyStorm.UI:RegisterView`. Fehlt `Holy_Storm_UI`,
bleiben Core und Feature-Addons funktionsfähig. `RegisterPage` ist weiterhin der
Low-Level-Kompatibilitätsvertrag für noch nicht migrierte Seiten.

## Schichten

```text
Feature / Domain
    -> View Model, View- und Tabellenbeschreibung
    -> HolyStorm.UI / UIComponents / UILayout
    -> WoW Frame API und AceGUI
```

`UILayout` berechnet Geometrie und besitzt keine Domainkenntnis.
`UIComponents` erzeugt Grundkomponenten. `UIManager` verwaltet Views und
Refresh. Die Domain bleibt für Datenbeschaffung, Berechtigungsentscheidungen
und Aktionen verantwortlich.

## Layout-System

`HolyStorm.UILayout` unterstützt horizontale (`row`) und vertikale (`column`)
Container, verschachtelte Container, Padding und Gaps. Tracks können wie folgt
beschrieben werden:

```lua
local row = HolyStorm.UI.Components:CreateRow(parent, {
    gap = 8,
    padding = { left = 12, right = 12, top = 8, bottom = 8 },
})

row:Add(icon,  { width = 32 })
row:Add(name,  { weight = 1, minWidth = 120 })
row:Add(state, { width = 100 })
```

Gültige Größen sind `width`/`height`/`size` für feste Pixel, `percent` oder
`"50%"` für relative Größen und `weight`/`flex`/`fr` für den Rest. Optional
begrenzen `minWidth`, `maxWidth`, `minHeight` und `maxHeight` einen Track.
`ResolveTracks`, `Calculate` und `Measure` sind reine Funktionen und damit
offline testbar. `autoSize`, `autoWidth` und `autoHeight` übernehmen gemessene
Kindgrößen für inhaltsbasierte Container. Container reagieren ausschließlich
auf `OnSizeChanged`; es gibt keine Layout-Polling-Schleife.

## Grundkomponenten

`HolyStorm.UI.Components` stellt bewusst nur die aktuelle Basis bereit:

- `CreateText`, `CreateIcon`, `CreateButton`
- `CreateContainer`, `CreateRow`, `CreateColumn`
- `CreateScrollContainer`
- `CreateTabGroup`, `CreateTreeGroup`
- `CreateTable`
- `Build(parent, description, context)` für rekursive Beschreibungen

Die Factory gibt Controller mit einem `frame` zurück. Container besitzen
`Add`, `Remove`, `Clear` und `Relayout`. Neue Widgets werden als weitere
Factory-Methode und optionaler `Build`-Typ ergänzt; Features erzeugen keine
zweite Layout-Engine.

## Table API

Eine Tabelle ist vollständig generisch:

```lua
local tableView = HolyStorm.UI.Components:CreateTable(parent, {
    columns = {
        { id = "icon", width = 32, renderCell = renderIcon },
        { id = "name", title = L["NAME"], weight = 1, minWidth = 140,
          sortable = true },
        { id = "status", title = L["STATUS"], width = 100, align = "RIGHT" },
    },
    rowHeight = 26,
    headerHeight = 26,
    columnGap = 1,
    emptyText = L["NO_RESULTS"],
    unknownText = L["UNKNOWN"],
    onRowClick = function(row, button) Module:Select(row.id, button) end,
    rowTooltip = function(row) return row.tooltip end,
})

tableView:SetData(rows)
```

Spalten unterstützen feste, prozentuale und gewichtete Breite,
Min-/Max-Breite, Header-Ausrichtung, `value(row)`, `renderCell`, Tooltip,
Cell-Click sowie explizites `sortable = true`. Die Tabelle unterstützt
`SetColumns`, `SetData`, `UpdateRow`, `SetSort`, `SetEmptyText`, `SetEnabled`,
`Refresh`, `Relayout` und `Destroy`.

Rows und Cells werden gepoolt und bei einem Refresh wiederverwendet. Resize
berechnet nur Anker und Breiten neu. `SetData({})` zeigt den lokalisierten Empty
State. `nil`-Werte werden über `unknownText` dargestellt. Sortierung und Custom
Renderer sind opt-in; die Tabelle kennt keine fachlichen Datentypen.

## Deklarative Views

```lua
HolyStorm:RegisterUIExtension("example", {
    id = "example.ui",
    order = 30,
    initialize = function()
        assert(HolyStorm.UI:RegisterView({
            id = "example.overview",
            owner = "example",
            titleKey = "EXAMPLE_TITLE",
            localeName = "Holy_Storm_Example",
            requires = { module = "example", capability = "example.read" },
            availabilityEvents = { "HS_MODULE_AVAILABILITY_CHANGED" },
            events = { "HS_EXAMPLE_UPDATED" },
            build = function(parent, context)
                return context.components:Build(parent, {
                    type = "column", gap = 8, padding = 12,
                    children = {
                        { type = "text", text = L["EXAMPLE_TITLE"], height = 24 },
                        { type = "table", columns = columns, weight = 1 },
                    },
                }, context)
            end,
            refresh = function(view, context)
                -- Nur View Model aktualisieren; Fachlogik bleibt im Modul.
            end,
        }))
    end,
})
```

Pflichtfelder sind eine stabile, namensraumfähige `id`, `owner` und genau eine
Quelle aus `page`/`frame`, `build` oder `layout`. Doppelte IDs werden mit
`VIEW_ID_EXISTS` abgelehnt. Optionale Felder sind `order`, `title`, `titleKey`,
`locale`, `localeName`, `localize`, `icon`, `navigation`, `events`,
`availabilityEvents`, `requires`, `isAvailable`, `refresh`, `onCreate`,
`onShow`, `onHide` und `destroy`.

Öffentliche Lifecycle-Methoden:

- `RegisterView`, `GetView`, `GetViews`
- `ShowView`, `UnregisterView`, `UnregisterViewOwner`
- `IsViewAvailable`, `RefreshViewAvailability`
- `MarkDirty`, `RefreshPage` für ereignisgetriebene Updates

Registrierung speichert den Vertrag. Bei bereiter UI und erfüllten
Voraussetzungen wird die View genau einmal gebaut und an den bestehenden
`MainWindow`-Host gebunden. `events` markieren die View dirty. Eine sichtbare
View wird verzögert und zusammengefasst aktualisiert. Wird eine Voraussetzung
ungültig, werden Seite und Navigation abgehängt und der Frame verborgen. Bei
erneuter Verfügbarkeit wird derselbe Frame wiederverwendet. Deregistrierung
entfernt Events, Navigation und Frame über den Destroy-Lifecycle.

## Availability und optionale Module

`requires.module` und `requires.capability` verwenden ausschließlich die
vorhandene Modul-/Capability-Registry. Ein String oder eine Liste ist möglich.
Zusätzliche Laufzeitbedingungen gehören in `isAvailable`. Die UI hardcodiert
keine optionalen Feature-Namen. Fehlt ein Modul, bleibt die View registriert,
wird aber weder gebaut noch angezeigt.

Berechtigungen werden von der zuständigen Domain beziehungsweise dem
Administration-Host geprüft. Insbesondere besitzt Character Overview keine
eigene Zugriffs-Permission; nur seine restriktiven Daten-Tabs verwenden ihre
bereits vorhandenen Fach-Permissions.

## Lokalisierung

Sichtbare Texte kommen aus den bestehenden AceLocale-Namespaces. Eine View kann
bereits lokalisierte Texte, `locale`, `localeName` oder `localize(key)` liefern.
Fehlt ein View-Titel, fällt der Host sicher auf die View-ID zurück. Die
generischen Tabellen-Fallbacks `TABLE_EMPTY` und `TABLE_UNKNOWN` liegen in
`Holy_Storm_UI` für `enUS` und `deDE`. Feature-spezifische Labels bleiben im
Feature-Locale.

## Theme-Erweiterungspunkt

`UIComponents.tokens` bündelt grundlegende Abstände, Größen, Farben und
Texturen. `ApplyTheme(overrides)` ersetzt gezielt Tokens und emittiert
`HS_UI_THEME_CHANGED`. Das ist nur der Erweiterungspunkt, kein vollständiges
Theme-System. Ein späteres ElvUI-Theme bleibt ein optionales separates Addon;
die Basis-UI besitzt keine ElvUI-Abhängigkeit.

## Aktueller Migrationsstand und Regeln

Character Overview registriert seine Seite über `RegisterView`, verwendet die
zentrale TabGroup und rendert den Stats-Tab über die zentrale Table. Der
gemischte Rich-Text-/Tabellenrenderer bleibt vorerst als Compatibility-Pfad für
Equipment, Mythic+, Raid und Delves bestehen. Diese Feature-Tabs werden in
späteren, fachlich getrennten Schritten auf reine Table-/Section-Beschreibungen
migriert. Die Character-Grundstruktur und Permission-Semantik wurden nicht
verändert.

Der Administration-Host registriert sich als zentrale View und erzeugt seine
Navigation über `CreateTreeGroup`. Die komplexen vorhandenen Editoren wurden
bewusst nicht visuell redesignnt.

Für neue Module gelten folgende Regeln:

1. UI nur über `RegisterUIExtension` und `RegisterView` anbinden.
2. Stable IDs mit Modul-Namespace und explizitem Owner verwenden.
3. Layout über `UILayout`/`UIComponents`, Tabellen über `CreateTable` bauen.
4. Daten und Aktionen injizieren; keine Domainlogik in Renderer verschieben.
5. Refresh durch bestehende Events auslösen, kein Polling oder dauerhaftes
   `OnUpdate` verwenden.
6. Frames und Rows aktualisieren beziehungsweise wiederverwenden, nicht bei
   jedem Refresh neu erzeugen.
7. Alle sichtbaren Texte mindestens in `enUS` und `deDE` lokalisieren.
8. Feature-Availability deklarieren und fehlende optionale Addons tolerieren.
