# Guild roster search and page context header

The GuildRoster module owns search state, quick-filter options, rule fields, and the controls it contributes. `UIManager` owns page registrations and forwards the optional context-header contract. `MainWindow` owns the shared context-header slot and content viewport; neither framework layer depends on GuildRoster.

GuildRoster is now version 2.4.0, CharacterOverview 2.1.0, UIManager 2.2.0, and MainWindow 2.6.0. RuleEngine remains at 4.1.0.

## Window and page header structure

The title is rendered by `MainWindow`. Directly below it, the window has a page context-header slot. The slot and page content are sibling frames under the window inset, so the slot does not scroll with a page's scroll child. `HolyStorm.UI:RegisterPageContextHeader(pageId, owner, definition)` lets a page provide its own header without adding feature dependencies to the framework. The definition supplies:

- `build(parent, driver)`: create or mount the page-owned header controls.
- `height(width)`: return the required height for the available window width.
- `layout(frame, width, height)`: reflow controls after the window is resized.

The driver activates one header with its page, hides the previous one, and moves the content viewport below the active header. Pages without a context header use the full original content area. Unregistering a page also removes its header registration and frame.

CharacterOverview now mounts its existing `HolyStormHeaderBar` (portrait, character name, short details, data status, and refresh action) in this slot at 40 UI units. Its established data and refresh behavior is unchanged. GuildRoster mounts its search and filter controls in the same slot. Other pages do not reserve header space unless they register a header.

## Guild roster controls and layout

The roster contributes its search field and clear action, saved-filter multi-selector, Save and Manage actions, status/rank/class/Holy Storm selectors, refresh and reset controls, and result count. The header uses three width bands and the framework recalculates its height on window resize. The roster column labels and member list occupy the entire remaining page content, including the vertical scroll viewport.

Quick filters and the search rule combine with every selected saved filter using AND. Each quick-filter category keeps its established selection semantics; every saved filter keeps its RuleEngine tree logic. Saved selections use FilterManager's existing `guildRoster` context. A combined filter is written through `FilterManager:SaveFilter(..., "local")`, so it stays in the user's local profile and is not synchronized.

Search covers fields already visible in the roster: character name, realm, rank, class, level, zone, and a currently known Holy Storm version. Case folding includes ASCII and common Latin-1 uppercase letters, `Å¸`, and capital sharp S; it does not perform full Unicode normalization. Public notes, officer notes, private profile fields, and full character records are not searchable. Character records are read once while a roster snapshot is built and attached to the local row context, so advanced rules do not trigger per-keystroke store reads. Typing uses a cancellable short debounce and does not request a roster refresh, network transfer, or global task.

Presence versions come from `Sync:GetKnownVersion`. A known version is `RECOGNIZED`; no current version is `UNKNOWN`. The Sync store does not distinguish an addon that is absent from one whose presence has not been received or has expired, so absence is never treated as proof of `NOT_RECOGNIZED`. The selector retains a separate not-recognized value for sources that can reliably provide that fact later.

The existing pooled rows, sort order, left-click character action, right-click member context menu, note permissions, and rank permissions remain in the roster module. After quick and saved filters run, the existing twink grouping is applied to the filtered rows.

## Regression coverage

Run `lua tools/test_guild_roster_search.lua`, `lua tools/test_ui_framework.lua`, `lua tools/test_mainwindow_text.lua`, and `lua tools/test_character_tabs.lua` for filter semantics, profile persistence, cached-row performance, responsive control placement, context-header ownership and lifecycle, CharacterOverview header retention, and content-space release. `tools/test_localization_contract.lua` checks English/German key parity.
