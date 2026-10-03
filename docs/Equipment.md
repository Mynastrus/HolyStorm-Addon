# Equipment snapshot audit

This document describes the Equipment producer and its stored Character consumer. The source of truth is `LIVE/Holy_Storm_Equipment/Equipment.lua` plus `LIVE/Holy_Storm_Characters/UI/StoredFeatureTabs.lua`.

## Current contract

The producer registers the `equipment` PlayerData block at schema/snapshot version 4. Its synchronized fields are `equipment` and the compatibility field `itemLevel`. The Equipment module has no separate `equipment-read` permission: the Character storage tab is rendered from stored data, and writes still go through the owner-controlled PlayerData path. The producer depends on Core and Synchronization, exposes `character.scan.equipment`, and is loaded on demand.

The snapshot covers these 16 slots: head, neck, shoulder, chest, waist, legs, feet, wrist, hands, both fingers, both trinkets, back, main hand, and off hand. Shirt, tabard, and obsolete ranged slots are excluded.

Slot representation is intentionally compatible with schema 4:

| Stored value | Meaning |
| --- | --- |
| `false` | Blizzard's equipment-slot `ItemLocation` confirms the slot is empty. |
| `nil` / missing | `UNKNOWN`; a scan with any unknown slot is incomplete and cannot commit. |
| table with `state = "EQUIPPED"` | Equipped item with matching item ID and full original item link, effective item level, quality, and icon. |

Older schema-4 item tables without `state` remain readable as equipped when they have an item ID. Old `false` values retain their historical schema-4 meaning. A table is not accepted as an empty-slot marker.

New equipped item tables contain `state`, `slot`, `itemId`, the untouched `link`, per-item `itemLevel`, `quality`, and `icon`. Optional fields are `enchantId`, `sockets`, `gems[]`, and Blizzard's generic `setID`. The item name is read from the stored hyperlink. Tooltip-derived enchant/socket labels and a speculative `isTier` flag are not persisted by new scans.

Item-level fields are:

| Field | Meaning |
| --- | --- |
| `itemLevel` | Compatibility alias for `equippedItemLevel`; this has always been the second `GetAverageItemLevel()` return in the current producer. |
| `equippedItemLevel` | Blizzard's currently equipped character item level, from return 2. All summaries and the `equipment.itemLevel` rule use this value. |
| `overallItemLevel` | Blizzard's overall character item level, from return 1; it can reflect available better gear outside the worn set. Stored separately and not substituted for equipped level. |
| slot `itemLevel` | Per-item effective level from `C_Item.GetDetailedItemLevelInfo(originalLink)`, using its `actualItemLevel` return. Preview levels are not committed. |

No Holy Storm average formula is used. The `itemLevel` alias and the top-level PlayerData field are retained for existing schema-4 readers; new code should read `equippedItemLevel`.

## Retail API audit matrix

The API signatures below were checked against the current `live` branch of the generated Blizzard API documentation and Blizzard FrameXML mirrors on 2026-09-30. “Conditional” means the API is useful only when its required local item context or cached detail data is available. API documentation's `MayReturnNothing` and `SecretArguments = AllowedWhenUntainted` flags are treated as readiness/security constraints, not as evidence for an empty value.

| Feature | Blizzard API | Reliability / scope | Persist | Sync | Remote render | Implemented |
| --- | --- | --- | --- | --- | --- | --- |
| Slot occupied / empty | `Item:CreateFromEquipmentSlot(slot):IsItemEmpty()` → boolean; internally uses an equipment `ItemLocation` and `C_Item.DoesItemExist(location)` | Conditional; local player's slot only. Guarded calls; missing API, errors, or non-boolean results mean UNKNOWN. | Slot state | Yes | Yes | Yes |
| Item ID | `Item:CreateFromEquipmentSlot(slot):GetItemID()` when the slot object is available; `GetInventoryItemID("player", slot)` and parsed hyperlink ID are fallbacks | Conditional; nil alone is ambiguous, so it never establishes EMPTY. Must match the ID embedded in the link. The `ItemLocation`-backed ID avoids mixing a transmog/appearance ID with the item identity. | `itemId` | Yes | Yes | Yes |
| Full item link | `Item:CreateFromEquipmentSlot(slot):GetItemLink()` when available; `GetInventoryItemLink("player", slot)` is fallback | Conditional; missing link for a positively occupied slot makes the whole scan incomplete. The returned link is stored unchanged. | `link` | Yes | Yes | Yes |
| Item name | `C_Item.GetItemInfo(itemInfo)` / `Item:GetItemName()` | Conditional on loaded item details. The stored original link already contains its display label; the UI reads it without rebuilding the hyperlink. | No extra name field | — | Yes, from stored link | Yes |
| Icon | `GetInventoryItemTexture("player", slot)`; `Item:GetItemIcon()` / `C_Item.GetItemIconByID` fallback | Conditional on local slot/item data. An unavailable icon keeps the scan incomplete; no fabricated question-mark item icon is stored. | `icon` | Yes | Yes | Yes |
| Quality | Third return of `C_Item.GetItemInfo(originalLink)` | Conditional; nil until item detail data is ready. Quality is not inferred from color, name, or level. | `quality` | Yes | Yes | Yes |
| Per-item effective item level | `C_Item.GetDetailedItemLevelInfo(itemInfo)` → actual level, preview flag, sparse level | Conditional; documented `MayReturnNothing`. Preview level is rejected; a missing/nonpositive actual level schedules the central retry. | `itemLevel` | Yes | Yes | Yes |
| Equipped character item level | `GetAverageItemLevel()` return 2 | Conditional; player-only and may be unavailable before character data is ready. No per-slot recalculation. | `equippedItemLevel` plus compatibility aliases | Yes | Yes | Yes |
| Overall character item level | `GetAverageItemLevel()` return 1 | Conditional; player-only and may include higher available gear outside the worn set. | `overallItemLevel` | Yes | Yes | Yes |
| Enchant ID / state | Enchant ID field in the original `item:` hyperlink | Conditional on a parseable complete item link. Empty field gives known ID 0; absent/unparseable field remains UNKNOWN. This reports presence only; it does not say whether a slot needs an enchant. | `enchantId` | Yes | Yes | Yes |
| Enchant localized name | Tooltip text from `C_TooltipInfo` | Unreliable as a cross-client authority: localized and presentation-oriented. | No | — | Native item tooltip | No |
| Socket count | `C_Item.GetItemNumSockets(itemInfo)` → non-nil number | Conditional on usable item info; no slot-specific socket assumption. Zero means NO_SOCKET. | `sockets` | Yes | Yes | Yes |
| Empty socket | `C_Item.GetItemGemID(itemInfo, index)` / `C_Item.GetItemGem(itemInfo, index)` | Unavailable as an authoritative empty-vs-not-ready distinction from the reviewed contract: both calls may return nothing. A nil gem result is SOCKET_UNKNOWN. | Per-socket state | Yes | Yes | Unknown retained |
| Gem ID / link | `C_Item.GetItemGemID` / `C_Item.GetItemGem` | Conditional; positive ID means SOCKET_FILLED. A missing ID is not taken to mean empty. | `gems[]` | Yes | Yes | Yes |
| Tier membership / equipped tier count | `C_Item.GetSetBonusesForSpecializationByItemID(specID, itemID)` → set-bonus spell ID table; `C_Item.GetItemInfo` may also provide `setID` | Not sufficient to establish tier membership: ordinary item sets also have set bonus data. No general tier-membership proof is available in the reviewed contract. | No authoritative tier flag/count | — | Unknown shown as unknown | No; query returns unavailable |
| Generic item set ID | Sixteenth `C_Item.GetItemInfo(itemInfo)` return (`setID`) | Conditional metadata for a generic item set. It does not mean the item is a tier piece. | Optional `setID` | Yes | Not currently rendered | Yes |
| Upgrade track / rank | `C_Item.GetItemUpgradeInfo(itemInfo)` → nullable `ItemUpgradeInfo`; original hyperlink also retains bonus/context fields | Conditional, but the reviewed public return contract does not establish a stable track/rank field contract suitable for this snapshot. | No | — | Full native item tooltip | No |
| Durability | `GetInventoryItemDurability(slot)` | Transient local-player condition; excluded from persistent guild snapshots. | No | No | No | No |
| Transmog / appearance | `C_Item.GetCurrentItemTransmogInfo(itemLocation)` → nullable transmog info | Separate appearance state; no Equipment consumer requires it. | No | No | No | No |

Primary API references:

- [Generated Retail Item API documentation](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/ItemDocumentation.lua) documents item-info readiness, `GetDetailedItemLevelInfo`, gem APIs, socket count, set bonuses, `DoesItemExist`, and nullable upgrade info.
- [Retail `Item.lua` FrameXML](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_ObjectAPI/Mainline/Item.lua) shows `CreateFromEquipmentSlot`, `IsItemEmpty`, `IsItemInPlayersControl`, item link/detail getters, cache checks, and `ContinueOnItemLoad`. The producer uses no item-load callback chain.
- [`GetAverageItemLevel` return semantics](https://warcraft.wiki.gg/wiki/API%3AGetAverageItemLevel) documents overall, equipped, and PvP returns and the local-player scope. This global is not in the generated Item API file.

## Collection, validation, and commit path

Equipment events (`PLAYER_EQUIPMENT_CHANGED`, player `UNIT_INVENTORY_CHANGED`, and `SOCKET_INFO_UPDATE`) enter EventManager and CharacterScanManager only after `playerReady`. Pre-ready callbacks, including load-on-event initialization noise, are ignored. Module activation, login, a missing block, or an old timestamp do not scan. The producer uses its single `EQUIPMENT_UPDATE` workflow with a one-second debounce and no parallel runs:

1. Scan every supported slot and capture the equipped/empty/unknown decision.
2. Validate all slots plus character and item-level readiness.
3. Compare the semantic snapshot with CharacterStore. PlayerData's fingerprint drops capture/receive/commit timestamps and schema metadata.
4. If changed, wait one second, take a full new scan, validate it, and compare scan 1 with scan 2.
5. Only a stable full snapshot reaches `PlayerData:WriteOwnedBlock`; that owner-controlled commit advances the revision and uses the existing character sync and CharacterStore paths.

Incomplete item or character data retries through the workflow (up to five retries, 2.5 seconds between retries). Each retry takes a new full scan. There are no `ContinueOnItemLoad` callbacks. A failed/incomplete scan never reaches commit, so the previous valid snapshot and revision remain available. A sudden transition from previously equipped gear to a completely empty snapshot requires a second matching candidate before validation accepts it; the stability scan then confirms it again.

The captured `false` empty state is emitted only when the equipment `ItemLocation` check returns the boolean empty result. Missing ID/link APIs without that check produce UNKNOWN and invalidate the whole candidate. Full item links are compared and synced as data, so same-ID bonus, gem, enchant, or upgrade variants differ.

## Stored Character UI and queries

Character → Equipment, the Equipment summary, and Dashboard read CharacterStore/PlayerData snapshots only. Remote rendering does not call inventory or ItemLocation APIs. The stored hyperlink is passed to native tooltip and modified-click handling unchanged. Item labels come from the link; quality and icon come from stored Blizzard data. Long links are visually shortened while the original link remains on the row.

- Equipped item: item icon, linked label, per-item level, and only facts known from stored fields.
- Confirmed empty: slot-specific paper-doll placeholder and localized “Empty”.
- Unknown: gray dash, no empty-slot placeholder, and no invented item icon.
- Enchant: known ID 0 is “not enchanted”; positive ID is “enchanted”; missing ID remains unknown. The UI does not judge whether an enchant is required.
- Gems: count 0 is “no socket”; a gem ID is “filled”; a missing gem result is a gray unknown marker. It is never relabeled as an empty socket.
- Tier: the old stored boolean remains renderable for compatibility. New scans do not claim tier membership from generic item-set bonuses; new membership queries return `nil, "TIER_MEMBERSHIP_UNAVAILABLE"`.

The module exposes `GetSlot(character, slotID)`, `GetEquippedItemLevel(character)`, `GetEnchantState(character, slotID)`, `GetSocketState(character, slotID, index)`, and `GetTierPieceCount(character)`. Queries return explicit UNKNOWN/unavailable states where the saved facts cannot support a conclusion. Future rule modules should consume these queries rather than copy slot parsing or claim their own tier truth.

The manual scan continues to use `/hs scan equipment`; dashboard and Character Overview refresh actions request the same CharacterScanManager provider and do not write around PlayerData. Equipment freshness is event-driven; there is no wall-clock stale threshold. See [`SNAPSHOT_REFRESH_POLICY.md`](SNAPSHOT_REFRESH_POLICY.md) for the shared UI status contract.

## Offline checks and Retail sign-off

The snapshot fixture covers full-link preservation, item ID/link mismatch, explicit EMPTY versus UNKNOWN, bounded incomplete-state rejection, equipped versus overall level, effective per-item level, quality, enchant link semantics, filled versus unknown sockets, generic item sets not being labeled tier, and the confirmed-empty candidate guard. The Character tab fixture covers all 16 rows, stored native link/tooltips, empty placeholders, unknown dashes, and summary item level.

There is no Retail client in this environment. Before relying on server-verified behavior, inspect in current Retail:

1. An actually empty equipment slot; ensure `Item:CreateFromEquipmentSlot(slot):IsItemEmpty()` yields true and the other slot APIs do not override it.
2. An equipped item whose link/detail data is not initially cached; confirm the event and five bounded retries eventually capture it, or preserve the prior snapshot.
3. A 2H weapon, dual wield, ring/trinket slots, an empty offhand, and a shield; compare both `GetAverageItemLevel()` values with Blizzard's character sheet.
4. An item with an enchant, an item with zero/multiple sockets, an empty socket, a filled socket, and a bonus socket; confirm exactly which nil gem results remain unresolved.
5. A tier item and a non-tier item that grants item-set bonuses; keep tier UI/query unknown unless Retail exposes a general membership API.
6. Upgrade track/rank data and the stored item tooltip after `/reload` and on a remote Character view.

This is a source-based audit and offline correctness pass. It does not claim that the live client behavior checklist has been run.
