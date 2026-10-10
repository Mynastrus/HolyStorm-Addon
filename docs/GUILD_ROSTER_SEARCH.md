# Guild roster search and toolbar

The GuildRoster module owns search state, quick-filter options, rule fields, and the controls it contributes. The UI framework owns the optional page toolbar slot and the content viewport. The framework has no GuildRoster dependency.

This change versions GuildRoster at 2.3.0, UIManager at 2.1.0, MainWindow at 2.5.0, and RuleEngine at 4.1.0.

## Page toolbar contract

`HolyStorm.UI:RegisterPageToolbar(pageId, owner, definition)` registers a page-owned toolbar. The definition supplies:

- `build(parent, driver)`: create and retain the feature's controls under the supplied toolbar frame.
- `height(width)`: return the toolbar height in UI units for the current available width.
- `layout(frame, width, height)`: position feature controls after a resize.

The driver places the slot below the Holy Storm title and above page content. Page content moves down only while its page has a registered toolbar. Home, Options, and pages without a toolbar return to the original content inset. Toolbar frames are siblings of the scrollable content region and never enter its scroll child. Unregistering the page also releases its toolbar.

## Guild Roster behavior

The roster contributes its search field, saved-filter multi-selector, Save and Manage actions, status/rank/class/Holy Storm selectors, refresh and reset controls, and result count. The toolbar uses three width bands and the framework recalculates its height when the window changes size. The roster header and row scroll frame occupy the remaining page content.

Quick filters and the search rule combine with every selected saved filter using AND. Each saved filter keeps its existing RuleEngine tree logic. Saved selections use FilterManager's existing `guildRoster` context; a saved combined filter is written through `FilterManager:SaveFilter(..., "local")`, so it stays in the user's local profile and is not synchronized.

Search covers the fields already visible in the roster: character name, realm, rank, class, level, zone, and a currently known Holy Storm version. Case folding includes ASCII and common Latin-1 uppercase letters, `Ÿ`, and capital sharp S; it does not perform full Unicode normalization. Public notes, officer notes, private profile fields, and full character records are not searchable. Character records are read once while a roster snapshot is built and are attached to the local row context so existing advanced rules do not trigger per-keystroke reads. Typing uses a cancellable short debounce and does not request a roster refresh, network transfer, or global task.

Presence versions come from `Sync:GetKnownVersion`. A known version is `RECOGNIZED`; no current version is `UNKNOWN`. The Sync store does not distinguish an addon that is absent from one whose presence has not been received or has expired, so absence is never treated as proof of `NOT_RECOGNIZED`. The selector retains a separate not-recognized value for sources that can reliably provide that fact later.

The existing pooled rows, sort order, left-click character action, right-click member context menu, note permissions, and rank permissions remain in the roster module. After quick and saved filters run, the existing twink grouping is applied to the filtered rows.

## Regression coverage

Run `lua tools/test_guild_roster_search.lua`, `lua tools/test_ui_framework.lua`, and `lua tools/test_mainwindow_text.lua` for filter semantics, profile persistence contracts, cached-row performance, responsive layout, central toolbar lifecycle, and content-space release. `tools/test_localization_contract.lua` checks English/German key parity.
