# Character Overview Consumer Contract

## Purpose

The Character Overview is a read-only consumer of persisted character identity and feature snapshots. It displays data owned by CharacterStore/PlayerData, and never derives a remote character's values from the local player's inventory, run history, raid statistics, auras, or weekly activities. The UI does not own a second snapshot or relationship model.

## Architecture

Feature updates follow the existing producer path:

`Producer -> CharacterScanManager -> Task/Workflow -> validation -> PlayerData -> Sync -> CharacterStore -> Character Overview`

The seven base tabs register from the required `Holy_Storm_Characters` addon. Their visibility does not depend on Equipment, Mythic+, Raid, or Delves producer modules being loaded. The Overview reads only the requested CharacterStore blocks. CharacterStore is the UI's query boundary; PlayerData owns block revisions, freshness, persistence, and sync.

## Character identity and context

The selected Character UUID/GUID is the stable key. `CharacterUI:ResolveContext` combines the stored CharacterStore record, current guild roster metadata, PlayerStore ownership, and TwinkCore's account/roster identity APIs. Name and realm are presentation fields and are not used as identity keys. Account-Main and Guild-/Shadow-Main remain separate central TwinkCore results.

`SetContext` increments a context token. Opening another character replaces the selected context; delayed refresh callbacks compare their captured token before they render. Every tab adapter receives the selected context and queries its own block by `context.characterUUID`. Relationship tabs re-query TwinkCore rather than caching a PlayerUUID group. CharacterStore update events mark only the affected tab and summary dirty; refresh is deferred and token-guarded.

## Stored data and local versus remote

| View | Source | Schema | Local | Remote | Reload | Stale handling | Unknown handling | Live API in the view | Status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Overview | identity plus equipment, Mythic+, raid and other summary sections from CharacterStore | Identity record; Equipment v4, Mythic+ v5, Raid v3, Delves v3 | Same stored fields as every other character | Stored identity and blocks only | Stored data renders without opening a producer | M+ season mismatch is suppressed; each feature section applies its own weekly/version rules | Missing feature data uses localized no-data/gray unknown | Global M+ season and weekly reset are context only; no player values are sampled | Correct after fixes |
| Equipment | CharacterStore `equipment` block | v4 (`snapshotVersion`) | Stored equipped level and slot records | Stored slot records and complete saved item links | Does not need Equipment producer loaded | Unsupported versions render no current rows; normal block freshness is shown in header | `false` slot is confirmed empty; absent slot/item/socket/enchant data stays unknown | None | Correct after fixes |
| Mythic+ | CharacterStore `mythicPlus` block | v5 (`schemaVersion` and `snapshotVersion`) | Stored rating, pool, API-selected timed/overtime records | Stored values; local current season is only a global comparison context | No Mythic+ producer required | Old season is hidden; Great Vault is shown only for matching weekly reset identity/current period | Zero score remains `0`; no completion is distinct from unknown; unavailable affix detail stays nil | `GetCurrentSeason`, `GetWeeklyResetStartTime`, rating color and Encounter Journal navigation are presentation context only | Correct |
| Raids | CharacterStore `raid` block | v3 (`snapshotVersion`) | Stored catalog, weekly lockouts and lifetime statistics | Same stored catalog and lifetime data | Catalog and Best tooltip use stored boss order/data | Shared status marks weekly identity stale while lifetime Best remains available | Missing lockout/boss statistics are gray unknown, never fabricated as zero kills | Encounter Journal opens only on explicit click | Cache-first |
| Delves | CharacterStore `delves` block | v3 (`schemaVersion` and `snapshotVersion`) | Stored season and World Great Vault activities | Stored values | Does not need Delves producer loaded | Weekly values require matching stored reset identity and `currentPeriod`; old schemas are not read as v3 | Missing/old weekly data remains gray unknown | `GetWeeklyResetStartTime` is global reset context only | Correct |
| Stats | CharacterStore `stats` block | v2; explicitly supported legacy v1 display path | Persisted baseline plus local transient live overlay for the own character only | Persisted baseline; no local temporary values | Persisted rows render before any live overlay arrives | Unsupported versions are not reinterpreted; data freshness remains in shared header | Missing fields remain unknown; numeric zero is retained | No APIs are called by the tab; own-character live overlay is supplied by the Stats producer event | Correct after fixes |
| Twinks | TwinkCore, CharacterStore, GuildStore and PlayerStore | Current central relationship contract | Same central queries | Visibility follows TwinkCore (`all`/`guild-only`) and relationship authority | Re-queries central relationship data on open/update | No cached account grouping; AUTO supersedes MANUAL according to TwinkCore | Unassigned/missing account has a localized empty state | No player-only values are used to supplement the selected character | Correct |

## Tab registration and order

The base order is stable and registered independently of feature producers:

1. Overview
2. Equipment
3. Mythic+
4. Raids
5. Delves
6. Stats
7. Twinks

The separate Achievements addon intentionally contributes an additional tab. It is ordered after these seven base tabs and retains its own achievement visibility rules. Missing optional producer data does not unregister any base tab.

## Tab lifecycle and refresh

Tabs build lazily and reuse their view/table frames. Character switches mark all tab views dirty; only the selected view renders immediately. Opening the Overview and selecting any tab read stored data but do not enqueue producer scans. Missing or stale blocks are labeled through the shared `CharacterUI:GetDataStatus` contract. Data events schedule a bounded refresh for the affected visible tab and summary; hidden tabs remain dirty until selected. Failed tab adapters are caught and logged so another tab remains usable.

The header Refresh button uses the central Character.Refresh task. For the local character it dispatches capability requests through existing scan providers; for a remote character it calls CharacterStore/PlayerData's existing on-demand request path. The status prompt for the active producer block is clickable and targets that block. Opening a character, rendering, and tab switching never request scans.

## Overview and header

The header uses stored name, realm, class, race, faction, level, guild rank, and stored spec when available. Class atlas icon and spec icon use that character's stored class/spec, with an unknown class icon or hidden spec icon as fallback. The header compacts only present fields so a missing spec does not truncate later identity fields. The faction watermark is based on stored faction; guild membership does not imply faction.

Summary sections are adapters over the same stored blocks as their tabs. Equipment uses `equippedItemLevel` (the v4 `itemLevel` alias is also equipped level); it does not use overall item level or calculate an average. Mythic+ uses stored `overallScore` only when the stored v4 season matches the known current global season. Raid Best uses lifetime-confirmed per-boss statistics from the v3 stored catalog, not weekly lockouts.

## Equipment v4

One row is rendered per supported slot. The complete stored item hyperlink is used for the native tooltip and item click; the UI does not reconstruct `item:<id>`. Confirmed empty slots use the WoW slot placeholder. Missing slots render gray unknown. Item names are truncated to the available table width while preserving the link payload and tooltip.

Enchant state is inferred only from the v4 stored enchant ID: positive/zero is known and absent is unknown. Socket count zero means no sockets; a missing socket count remains unknown even if the gem list is empty. Only a stored `SOCKET_FILLED` or positive legacy gem ID renders as filled. Missing gem IDs and legacy `empty=true` flags are unknown because the current producer cannot reliably establish an empty socket. The current producer does not establish current-season tier membership; legacy `isTier` flags and generic item-set IDs are not enough, so tier stays unknown. Saved item links are checked against the saved item ID before tooltip or click handling. A malformed link keeps the stored item label visible but cannot be passed to WoW.

## Mythic+ v5

The stored dynamic seasonal pool is rendered by stable challenge-map ID. The UI requires v5 schema/snapshot versions and a matching verified current season. A previous-season snapshot is hidden in the tab, overview summary and dashboard; if the current-season API is unavailable, seasonal values remain unknown until the season can be verified. It uses Blizzard's per-dungeon score and selected in-time/overtime records, retains both in the tooltip, and uses Blizzard rating colors when available. Zero rating remains visible as zero; a loaded dungeon with no completion is labeled separately. Great Vault thresholds are separate from seasonal score and are visible only for the current reward period/reset identity.

The current saved schema does not provide a stable mapping from optional localized affix names to the Tyrannical and Fortified labels, and does not store dungeon teleport spell IDs or a recent-run history. The UI therefore does not infer those rows or actions from localized names, run affixes, or a static spell list. The optional tracked-affix details and actual best runs remain available in the tooltip.

## Raid v3

The UI uses the stored current Encounter Journal catalog, boss order, lockouts, and lifetime statistics. Weekly difficulty columns remain separate from lifetime Best. Best is calculated per catalog boss from the highest confirmed lifetime difficulty in the stored v3 data; the tooltip emits one row per catalog boss in stored order and does not treat partial or unknown statistics as zero. It displays zero kills only when all four authoritative difficulty counters are present and zero. Weekly boss tooltip state is green for killed, red for not killed and gray when unknown. Colors for progress columns are centralized: LFR yellow, Normal green, Heroic blue, Mythic purple. Weekly lockouts remain visible when their stored identity is stale, with a cached-week label; stored catalog and lifetime Best remain usable.

## Delves v3

The tab requires v3 schema and snapshot versions. It labels the activity list as Great Vault World activities; it does not call them completed Delves. Snapshot freshness follows the stored season and weekly reset identity. World progress and reward availability are optional and render as unknown when Blizzard's current-period data is unavailable or belongs to an unclaimed previous period. Legacy v2 fields and unsupported Delves history, companion, treasure map, flute, or crest facts are not displayed.

## Stats v2

Baseline comes from the persisted v2 snapshot. Primary and secondary rows are data-driven: known stats retain their preferred order and additional producer fields are sorted and shown with a localized generic label. The explicit legacy v1 path reads only its legacy `base`/`effective` representation; other versions are unsupported. For the own character only, the separate Stats producer may provide transient live values for Total and Additional. Remote characters never use that cache. Additional is unknown until both baseline and live values are reliable; zero stays zero.

## TwinkCore

The Twinks tab queries visible characters, Account-Main, Guild-Main/Shadow-Main, and relationship authority through central TwinkCore APIs. It does not create a second rank sort or cache account membership. AUTO relationships are read-only and outrank MANUAL. MANUAL actions reuse CharacterActions and `twinks-manage-manual-assignments`; the permission controls administrative changes, not visibility of normal Twink rows. An Account-Main remains the owner-selected Account-Main even when outside the guild; Shadow-Main is presented separately.

## Known value, zero, empty, unknown, stale and unsupported

- Known values render from stored values; numeric zero remains `0`.
- Confirmed empty Equipment slots use placeholders. Empty and unknown are not interchangeable.
- Unknown values use the shared gray dash or localized no-data state; missing fields do not become `0`, `false`, or blank success values.
- Time-bound Mythic+ season/weekly data, Delves season/weekly data, and Raid weekly lockouts apply the shared stored-identity freshness checks. Stale stored values remain available for display; lifetime Raid data is not discarded merely because weekly data is stale.
- Feature consumers reject unsupported snapshot versions instead of silently reading old fields under new semantics. The header reports unsupported stored versions separately from current/stale/missing data.

## Tooltips and navigation

Structured raid and Mythic+ tables use the shared LibQTip/Tooltip service and release owners on context/tab changes. Native item tooltips use the exact stored hyperlink. Raid and dungeon journal navigation runs only on explicit click and keeps the existing combat guard. Tooltip renderer failures are contained by the tab refresh boundary.

## Permissions

The Character Overview module has no view permission. Equipment, Mythic+, Raid, Delves, Stats, and ordinary Twink data have no tab-level view gate. The remaining Twink permission is limited to manual relationship administration. Achievement visibility is owned by the separate Achievements service and is not a Character Overview permission.

## Data updates, performance and error isolation

PlayerData and snapshot runtime-status events identify the changed character and block. The page refreshes the active affected tab and summary after a short scheduled coalesce; inactive tabs are refreshed when selected. There is no per-frame polling. Tables reuse row frames, feature queries avoid full database scans, and the tab host uses the shared responsive table/layout components. SafeCall isolates each adapter and logs renderer failures without closing the Overview.

## Known limitations

- No Retail client was available for this audit. Tests validate stored consumer behavior, not Blizzard client rendering or API timing. In-game verification is still required for native item tooltips/clicks, truncation, narrow-window layout, Encounter Journal navigation, combat behavior, and localized header widths.
- Raid weekly freshness follows the shared domain status contract. Stale weekly lockouts remain in the stored snapshot and are labeled by status; lifetime best data remains current independently.
- An unsupported remote snapshot can remain unavailable until an authoritative newer block arrives through normal sync; the Character UI adds no private sync protocol.
- Long subtitle content is constrained by the shared HeaderBar's one-line width; verify it in both locales at the narrowest supported window.
- Lua 5.1/LuaJIT was not available locally. Changed Runtime Lua is statically audited for 5.2+-only syntax/APIs; Lua 5.4 syntax is checked separately.

## Retail acceptance

After a Retail client is available:

1. `/reload`, open the own character without manual scans, and verify identity, spec/class, race, faction, equipped item level, current Mythic+ rating, and lifetime Raid Best.
2. Open Equipment: all slots, empty versus unknown, original item links, tooltip/click, truncation, item level, known/unknown enchant, filled/unknown gems, and unsupported tier state.
3. Open Mythic+: current season/rating, complete dynamic dungeon pool, per-dungeon score/color, both in-time/overtime bests, no-completion, and current/old Great Vault period.
4. Open Raids: each weekly difficulty, stale weekly behavior, stored lifetime Best, catalog-order tooltip with unknown boss rows, and difficulty colors.
5. Open Delves: stored season, Great Vault World activity labels, and weekly reset transition.
6. Open Stats: stored baseline, own live Additional/Total before/after a buff, zero values, and no live addition on a remote character.
7. Open Twinks: AUTO, MANUAL and unassigned relationships, Account-Main versus Guild-/Shadow-Main, guild-only visibility, and officer/admin actions.
8. Switch tabs and characters repeatedly; verify each shows the selected GUID and that tab selection alone starts no scan. Receive newer block sync while open and confirm only the affected view refreshes.
9. Reload again and verify all stored tabs render with optional producers disabled. Open a remote character and confirm every value comes from stored data.
10. Verify `deDE` and `enUS`, narrow-window layout, BugSack/log output, no script timeouts, and no revisions/syncs caused only by viewing the UI.
