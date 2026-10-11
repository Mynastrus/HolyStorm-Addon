# Guild Roster context-header runtime hotfix

## Runtime failure

The Guild Roster builder created its two dropdowns with `CreateFrame("DropdownButton", ..., "WowStyle1FilterDropdownTemplate")`, then called `SetDefaultText` on each. That method is not in the filter template's mixin chain. Retail's `WowStyle1FilterDropdownMixin` combines `DropdownTextMixin` and `WowFilterButtonMixin`; the former provides `SetText`, while `SetDefaultText` belongs to `DropdownSelectionTextMixin`, which is used by the selectable `WowStyle1DropdownTemplate`. The same filter-template mismatch affected dynamic labels: `OverrideText` is also absent from this template.

As a result, `filterMenu:SetDefaultText(...)` raised `attempt to call a nil value`. `MainWindow:EnsurePageContextHeader` caught the build exception, and `MainWindow:RegisterPageContextHeader` returned `PAGE_CONTEXT_HEADER_BUILD_FAILED`; GuildRoster then logged the registration failure. The latter was a consequence of the failed build, not a second failing API call.

The code now initializes and refreshes both filter dropdown labels with the template's `SetText`. The Blizzard `DropdownButtonMixin:SetupMenu`, menu-description `CreateButton`/`CreateCheckbox` methods, and `MenuResponse` values remain the Retail menu implementation.

Retail source references:

- [Blizzard Menu templates](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_Menu/MenuTemplates.lua): `DropdownSelectionTextMixin:SetDefaultText` and `WowStyle1FilterDropdownMixin` composition.
- [Blizzard Menu implementation guide](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_Menu/11_0_0_MenuImplementationGuide.lua): supported `DropdownButton` creation, templates, and menu-description API.

## Failure reporting and optional UI

`MainWindow` now preserves the builder's caught error as the registration reason. GuildRoster records registration failures through the structured Logger context with `code`, `pageId`, `owner`, and `reason`. The saved-menu action reports a localized status if the optional Administration service is unavailable; the header and profile list remain usable.

## Regression coverage

`tools/test_guild_roster_search.lua` loads the UIManager facade and MainWindow driver, binds the driver, then calls GuildRoster's actual header registration method. It verifies construction of the search, Filter, Saved, and refresh controls; nested category and saved-profile menu generation; multi-selection; menu refresh/open/close behavior; missing Administration behavior; page hide/show; unregister/rebuild; and structured diagnostics for a failed build without retrying on page switches.

The dropdown mock models the Retail filter template contract: it exposes `SetText` and `SetupMenu`, and deliberately does not expose `SetDefaultText` or `OverrideText`. Blizzard's menu implementation itself is not run by the offline test, so final click-through and visual alignment still need an in-game Retail check.

GuildRoster version: 2.5.1. MainWindow version: 2.6.1.
