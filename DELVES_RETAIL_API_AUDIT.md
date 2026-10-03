# Delves Retail API audit

Audit date: 2026-09-29. The target is current Retail FrameXML on the `live` branch. There was no Retail client available for in-game verification, so runtime readiness and reward semantics remain a later acceptance item.

## Purpose and current contract

The Delves feature records the current Delves season number and a separately named slice of Great Vault progress: `C_WeeklyRewards` activities for `Enum.WeeklyRewardChestThresholdType.World`. This is **Great Vault World activity progress**, not a Delves completion counter. A successful scan requires current-period Great Vault data and a Blizzard weekly reset identity.

Persistent snapshots are character-owner data in PlayerData. They use block `delves`, schema/snapshot version 3, validation in `Delves.lua`, normal CharacterScanManager provider `delves`, and SnapshotManager workflow `delves`. Freshness follows stored season and weekly identity; the descriptor's legacy generic freshness value does not trigger work. Only a changed, validated PlayerData commit follows the existing central revision and sync path. Timestamp metadata is ignored by the central semantic compare. There are no direct sync send calls in this module.

## Production implementation audited

| Area | Current implementation |
| --- | --- |
| Files | `LIVE/Holy_Storm_Delves/Delves.lua`; `Holy_Storm_Delves.toc`; module locales `Locales/enUS.lua`, `Locales/deDE.lua`. Stored rendering is in `LIVE/Holy_Storm_Characters/UI/StoredFeatureTabs.lua` and its UI locales. Dashboard summary is in `LIVE/Holy_Storm_UI/UI/Framework/Dashboard.lua`. |
| Module contract | Internal ID/block `delves`; feature module; version `2.2.0`; display name/description from module locale; core dependency; character scan capabilities; schema metadata registered with PlayerData. |
| Permissions | No Delves view/share permission. Character tabs are storage-owned and shareable by the normal character data contract. `sync-send` remains in module metadata for the standard module permission contract. |
| Dependencies | AceAddon/AceLocale and Holy Storm Core; runtime APIs `C_DelvesUI`, `C_WeeklyRewards`, `C_DateAndTime`, `Enum.WeeklyRewardChestThresholdType`. No remote-character Blizzard API reads. |
| Provider | `CharacterScans:RegisterProvider("Delves", ...)`, block `delves`, order 40. Missing, old, or stale stored data does not cause a bootstrap scan. Manual `/hs scan delves` goes through the same capability/provider/TaskManager/WorkflowManager/SnapshotManager path. |
| Events | `WEEKLY_REWARDS_UPDATE` queues a normal CharacterScanManager request. `DELVES_ACCOUNT_DATA_ELEMENT_CHANGED` concerns account curio ranks; `ACTIVE_DELVE_DATA_UPDATE` is live party/run data. Neither changes this persistent snapshot and both were removed as triggers. |
| Scan | `Module:Collect()` safely calls documented APIs, rejects missing/not-current data, copies the bounded World activity list, and builds a v3 snapshot. It does not enumerate a Delve catalog or inspect inventory/quests/achievements. |
| Validation | Requires v3 schema/snapshot versions, valid season and reset identity, explicitly current Great Vault period, finite nonnegative numeric activity values, unique activity IDs/indexes, valid completion list and consistent count, and boolean reward availability. A successful empty list is valid zero. |
| Commit and sync | `WriteOwnedBlock` only. SnapshotManager retries unavailable scans with a fresh scan under its bounded retry policy. Core publishes only after a successful changed PlayerData commit. |
| Stored UI | Character → Delves renders stored season, Great Vault World counts/reward state and activity thresholds/levels. It reads stored character data plus generic season/reset context. Previous-reset values remain visible and are labeled cached/stale. No Delves Blizzard API is called while rendering a remote character. |
| Dashboard | Shows the snapshot's stored season; it no longer labels a Great Vault World count as Delves progress. |
| Slash commands | Shared `/hs scan delves` command maps to the registered character scan capability. No Delves-specific commit or send path. |
| Logging | Module has no direct log writes. Provider/workflow/commit failures use shared CharacterScanManager, SnapshotManager and PlayerData diagnostics. |
| Localization/docs | Visible Character UI labels exist in enUS/deDE. This file is the data/API contract document. |

## API matrix

Reliability describes whether the current live API documents the data. Conditional means the value is accepted only when readiness checks prove the relevant current-period data is loaded.

| Feature / field | Current Blizzard API and observed contract | Reliability | Scope / lifetime / reset | Persist | Sync | Unknown possible | Implemented |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Delves season number | `C_DelvesUI.GetCurrentDelvesSeasonNumber()` → `seasonNumber:number`, documented non-nil | RELIABLE, guarded for absent API/runtime failure | Current global Delves season; changes on season transition | Yes | Yes | Yes, until API is available | Yes, `seasonNumber` |
| Season metadata | `C_DelvesUI.GetDelvesFactionForSeason()` gives faction ID; `GetDelvesAffixSpellsForSeason()` gives spell IDs. Neither creates a complete display-ready season descriptor | CONDITIONAL | Season | No | No | Yes | No |
| Delve catalog | Entrance APIs such as `GetDelveEntranceMapID()` and `GetDelveEntranceTiers()` describe an active UI entrance/context; inspected API has no complete seasonal catalog enumeration contract | UNAVAILABLE as a complete catalog | Run/UI context, not a complete season history | No | No | Yes | No |
| Weekly Delves progression | `C_WeeklyRewards.GetActivities(type)` → `WeeklyRewardActivityInfo` table (`type`, `index`, `threshold`, `progress`, `id`, `activityTierID`, `level`, optional claim/reward fields). `World` identifies the Great Vault World bucket, not Delves alone. | RELIABLE for the World Great Vault bucket after `AreRewardsForCurrentRewardPeriod()==true`; UNAVAILABLE as a Delves-only count | Character's current Great Vault reward period | Yes, explicitly as `greatVaultWorld` | Yes | Yes; nil/error/old period blocks commit | Yes, labeled Great Vault World |
| Weekly reset identity | `C_DateAndTime.GetWeeklyResetStartTime()` → `time_t` seconds | RELIABLE when API present and positive | Reset epoch for the client's server/region schedule; this function does not return a region ID | Yes | Yes | Yes; no fallback to local ISO week | Yes, `weeklyIdentity` |
| Bountiful Delves | No inspected stable API returns a character's current/completed Bountiful Delve set. A World Great Vault activity does not establish Bountiful state. | UNAVAILABLE | Potentially current week/run; exact reset/history contract not established | No | No | Yes | No |
| Delve completion / highest tier / successful runs / lifetime | `C_DelvesUI.GetActiveDelveTier()` is active party entrance/run context, not lifetime completion history. No stable completion-history API found in current Delves UI API docs | UNAVAILABLE for durable character history | Active run vs lifetime; durable history not exposed by inspected API | No | No | Yes | No |
| Great Vault reward state | `C_WeeklyRewards.AreRewardsForCurrentRewardPeriod()` → bool; `HasAvailableRewards()` → bool. `HasAvailableRewards()` is Great Vault-wide and has no category argument. | CONDITIONAL until current-period gate succeeds | Character / weekly reward period; reward claim availability can change | Yes, nested under `greatVault` | Yes | Yes; API unavailable/old-period blocks commit | Yes |
| Companion identity | `C_DelvesUI.GetCompanionInfoForActivePlayer()` → numeric `playerCompanionInfoID`; related helpers yield faction/node/tree IDs, not a complete named progression record | CONDITIONAL; API exposes IDs but not enough semantics for a user-facing progression snapshot | Active player's companion configuration; account/character persistence semantics are not fully stated in API contract | No | No | Yes | No |
| Companion name, level, XP, rank, role, abilities/progression | No inspected Delves UI API provides a complete stable companion progression payload. Trait/node identifiers alone are not a level/XP/role value | UNAVAILABLE | Season/configuration semantics unclear | No | No | Yes | No |
| Nemesis / rival / boss progress | No stable Delves API found. Achievement/quest heuristics are not authoritative for this field | UNAVAILABLE | Unknown | No | No | Yes | No |
| Treasure Map | No stable Delves API found for owned/active/used/reward state. Item possession would not establish active status | UNAVAILABLE | Item/run/weekly meaning not established | No | No | Yes | No |
| Flute | No current Delves API or precise supported feature definition found | UNAVAILABLE | Unknown | No | No | Yes | No |
| Crests, caps, keys, limits | Generic currencies and Great Vault rewards do not prove Delves-specific ownership/caps. No stable Delves-specific limit API found | UNAVAILABLE as Delves-owned data | Currency/reward reset varies | No | No | Yes | No |

## Snapshot, readiness, and UI semantics

The v3 snapshot is intentionally small:

```lua
{
  schemaVersion = 3,
  snapshotVersion = 3,
  seasonNumber = number,
  weeklyIdentity = number, -- C_DateAndTime.GetWeeklyResetStartTime()
  greatVault = {
    currentPeriod = true,
    rewardAvailable = boolean, -- Great Vault-wide, not World-only
  },
  greatVaultWorld = {
    progress = number, -- completed World reward thresholds
    completed = { number }, -- activity indexes
    activities = { ... },
  },
  updatedAt = number,
}
```

`greatVaultWorld` is not named Delves progress. The unscoped reward-availability flag lives separately under `greatVault`. The weekly reset epoch is required; a local calendar week string is not a reset identity. `AreRewardsForCurrentRewardPeriod()` must return true before the activity list is used. Missing APIs, thrown calls, wrong types, secret values, non-current reward data, invalid IDs, or inconsistent activities return no snapshot. SnapshotManager performs its bounded retry as a complete new `Collect()` call. This leaves the last valid committed revision in place and produces no sync.

The live API documentation marks `C_WeeklyRewards.GetActivities` and several `C_DelvesUI` companion helper calls with `SecretArguments = "AllowedWhenUntainted"`. The collector rejects secret activity numbers through `issecretvalue` checks. Season/reset/reward readiness calls are protected with `pcall`; missing methods or call failures are treated as unknown. No helper result is converted to a default zero.

An API-confirmed empty activity list is valid `progress = 0`. A nil/not-ready list is unknown and is not converted to empty. Shared status compares the stored weekly identity against the generic client weekly reset start time and labels old weekly data stale while retaining the cached values. It does not query a Delves API for a remote character; the season is expressly labeled as the stored season because the stored character record alone cannot certify that a remote record matches the client's current season. Season/reset mismatches never trigger an automatic scan.

Version 3 is a breaking data shape change from v2's ambiguous top-level `weeklyProgress` and placeholder unknown fields. There is no speculative conversion of v2 into v3: v2 remains stored/readable, renders weekly metrics unknown, and is replaced after the next successful scan. The validator accepts only v3 for local commits and remote imports. Stored CharacterStore remains the sole UI source for both local and remote records.

## Events, permissions, and runtime checks

`WEEKLY_REWARDS_UPDATE` is the only retained trigger: Blizzard documents it as the weekly reward update event. The initial availability event is ignored when the module enables before `playerReady`; a later module load does not suppress its first real event. `DELVES_ACCOUNT_DATA_ELEMENT_CHANGED` is documented as account data/curio-rank UI refresh, and `ACTIVE_DELVE_DATA_UPDATE` is documented around SpellScript/party Delve state or shutdown; neither is evidence that the persisted World Vault metrics changed. No completion event is used to claim Delve completion history. Weekly reward updates request a scan; SnapshotManager's one-second delay and bounded retries allow readiness to settle without polling or repeated API reads.

The Blizzard Weekly Rewards FrameXML creates a separate `World` activity row when the activity list contains that threshold type, reads the same activity list for refresh, and uses `AreRewardsForCurrentRewardPeriod()` to distinguish a previous claim from the current period. This supports the Great Vault World label and the period readiness gate; it does not establish that every World activity is a Delve.

No custom Delves view permission is declared. The regular Character Overview permission model governs stored character data. The only module permission retained is the existing `sync-send` capability metadata used by the standard module contract.

## Retail acceptance still required

With a current Retail client:

1. `/reload`, open Character → Delves and the Blizzard Great Vault UI.
2. Run `/hs scan delves`; compare season number and the `World` Great Vault activity thresholds/count. Do not compare it to a Delves-only completion counter.
3. Confirm `AreRewardsForCurrentRewardPeriod()` state corresponds to displayed current Vault values; test a newly reset character with zero activities.
4. Complete a Delve and observe whether Blizzard emits `WEEKLY_REWARDS_UPDATE` when the relevant Vault World data changes. The add-on intentionally cannot report successful Delve runs from the inspected public API.
5. Verify a no-change scan produces no new revision or publish; then verify a changed World Vault threshold commits and syncs once.
6. Reload and open a remote character. Confirm the tab uses only Stored Character data and old `weeklyIdentity` values remain visible with a stale label.
7. Test shortly before/after the regional weekly reset; confirm `GetWeeklyResetStartTime()` changes to the identity matching new current data.
8. Check BugSack, Holy Storm workflow logs, and for script timeouts.

## Primary source references

- [Current Blizzard Delves UI API documentation in wow-ui-source](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/DelvesUIDocumentation.lua)
- [Current Blizzard Weekly Rewards API documentation in wow-ui-source](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/WeeklyRewardsDocumentation.lua)
- [Current Blizzard Weekly Rewards UI implementation in wow-ui-source](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_WeeklyRewards/Blizzard_WeeklyRewards.lua)
- [Current Blizzard Date and Time API documentation in wow-ui-source](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/DateAndTimeDocumentation.lua)
- [Current Blizzard UI source mirror](https://github.com/Gethe/wow-ui-source)
