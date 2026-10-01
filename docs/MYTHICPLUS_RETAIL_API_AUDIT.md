# Mythic+ Retail API Audit

Last researched: 2026-10-01. The Retail UI source mirror's `live` branch and generated API documentation are the reference; the live branch can move as Blizzard patches the client. Holy Storm had no Retail client available for in-client verification during this audit.

## Purpose and authority

The Mythic+ feature persists the character's current season rating, Blizzard's current season dungeon pool, per-dungeon score, and Blizzard-selected season best records. Its optional weekly block contains only current-period Mythic+ Great Vault thresholds. Current affixes, the owned keystone, an active run, and an observed run history are not persistent progression facts in this model.

The feature remains a standard Character snapshot producer:

`EventManager → CharacterScanManager → Task/Workflow → Collect → Validate → semantic compare → PlayerData → Sync → CharacterStore → stored Character UI`

## Retail API audit matrix

| Feature | Retail API | Reliability / scope | Reset | Persist / sync / remote render | Decision |
|---|---|---|---|---|---|
| Current season identity | `C_MythicPlus.GetCurrentSeason()` → `seasonID:number`; `GetCurrentUIDisplaySeason()` → optional display ID | Reliable global season context; display ID is optional; guard errors and unavailable values | Season | Yes for season ID; display ID is descriptive. Standard character sync; remote UI checks the stored ID against known current season | Implemented |
| Character overall rating | `C_ChallengeMode.GetOverallDungeonScore()` → `number` | Reliable current player overall seasonal rating; no unit argument; 0 is valid | Season | Yes; used by dashboard, rule field and Character view | Implemented directly; never summed from dungeon scores |
| Rating color | `C_ChallengeMode.GetDungeonScoreRarityColor(score)` → optional `ColorMixin` | Reliable UI-only semantic for a supplied score; not character data | None | No data persisted; may render stored ratings | Used behind `pcall`; plain text fallback |
| Seasonal dungeon pool | `C_ChallengeMode.GetMapTable()` → challenge-map ID array | Reliable current client pool; docs do not promise order; empty/duplicate IDs are rejected | Season | Yes, one stored row per returned ID | Implemented, sorted by stable challenge-map ID |
| Dungeon metadata | `C_ChallengeMode.GetMapUIInfo(challengeMapID)` → name, instance ID, time limit, icon file ID, background file ID, map ID; may return nothing | Conditional on map info readiness; API marks arguments secret-capable, so calls are protected and returned fields are sanitized. Name is localized presentation, not identity | Season metadata | Name/icon/instance/map/time limit persist and sync; renderable remotely | Implemented; incomplete rows reject whole scan |
| Seasonal in-time / overtime bests | `C_MythicPlus.GetSeasonBestForMap(challengeMapID)` → nilable `MapSeasonBestInfo` records | Current source returns timed and overtime slots separately. Each record includes `dungeonScore`, duration, `completionDate: CalendarTime`, affix IDs and members. Calls/fields are guarded for secret values | Season | Selected record fields persist; party-member identity is excluded | Authoritative map score and best-run source |
| Per-dungeon tracked-affix details | `C_MythicPlus.GetSeasonBestAffixScoreInfoForMap(challengeMapID)` → tracked-affix rows and `bestOverAllScore`; marked `MayReturnNothing` | Optional current-season detail. A nil result is not evidence of a zero or empty affix list. The Challenges UI does not require it for its seasonal map rows | Season | Persist only when the API returns a usable table; absent detail stays nil | Optional tooltip detail; never blocks a complete score snapshot |
| Affix identity on a best run | `MapSeasonBestInfo.affixIDs` | Reliable IDs inside each returned run | Run/season | Persist IDs; resolve labels dynamically only if needed | Implemented |
| Current weekly affixes | `C_MythicPlus.GetCurrentAffixes()` and `C_ChallengeMode.GetAffixInfo(id)` | Current rotation, global and transient; returned names are localized | Weekly | No | Audited; intentionally not persisted or used as identity |
| Great Vault Mythic+ thresholds | `C_WeeklyRewards.GetActivities(Enum.WeeklyRewardChestThresholdType.MythicPlus)` → activity list | Character-scoped weekly activity thresholds; API arguments are secret-capable; conditional on reward data being current | Weekly reward period | Persist only with `AreRewardsForCurrentRewardPeriod()==true` and `C_DateAndTime.GetWeeklyResetStartTime()` identity; standard character sync | Implemented separately as `greatVaultMythicPlus` |
| Great Vault current period | `C_WeeklyRewards.AreRewardsForCurrentRewardPeriod()` → bool | Reliable period predicate for reward data, not proof of Mythic+ completion | Weekly reward period | A false or unavailable result omits weekly data; a prior period is never labeled current | Implemented |
| Great Vault reward availability | `C_WeeklyRewards.HasAvailableRewards()` → bool | Global Great Vault state, not Mythic+-specific | Weekly reward period | Not persisted in Mythic+ block to avoid implying the available reward came from Mythic+ | Audited; omitted |
| Weekly best run | `C_MythicPlus.GetWeeklyBestForMap(challengeMapID)` → optional duration, level, completion date, affix IDs, members, dungeon score | Current weekly best API; useful for map-by-map weekly runs, but distinct from vault threshold activity | Weekly | Not currently needed by a consumer; not persisted | Audited; omitted |
| Weekly chest reward level | `C_MythicPlus.GetWeeklyChestRewardLevel()` → current best level, reward level, next reward level and next best level | Conditional weekly reward summary; not equivalent to run count or Great Vault threshold list | Weekly | Not needed because typed vault threshold activities are used | Audited; omitted |
| Owned keystone | `C_MythicPlus.GetOwnedKeystoneLevel()`, `GetOwnedKeystoneChallengeMapID()`, `GetOwnedKeystoneMapID()`; may return nothing | Character-scoped and volatile; nil does not mean level/map zero | Changes during play | No | Audited; removed from persistent snapshot |
| Active challenge run | `C_ChallengeMode.IsChallengeModeActive()`, `GetActiveChallengeMapID()`, `GetActiveKeystoneInfo()` | Runtime/run scope | Run | No | Audited; transient |
| Run completion | `CHALLENGE_MODE_COMPLETED`; `C_ChallengeMode.GetChallengeCompletionInfo()` | Synchronous completion event; completion info is run scope and may describe a practice run | Run | No raw event result persisted; it triggers a fresh seasonal scan | Implemented trigger only |
| Weekly record change | `MYTHIC_PLUS_NEW_WEEKLY_RECORD(mapChallengeModeID, completionMilliseconds, level)` | Useful signal for a new weekly record that can affect season best data | Weekly/seasonal refresh signal | Event payload not stored; trigger only | Implemented trigger |
| Map/reward readiness | `CHALLENGE_MODE_MAPS_UPDATE`, `RequestMapInfo()`, `RequestRewards()` | Asynchronous readiness signals/requests; request functions have no data return | Global/current season | No direct persistence | Requests run once for bootstrap/manual refresh; later events rescan |
| Run history | `C_MythicPlus.GetRunHistory(includePreviousWeeks, includeIncompleteRuns, currentSeasonOnly)` → run array; secret arguments allowed only untainted | API exists, but documentation does not promise an exhaustive lifetime record or stable retention | Current season / previous weeks depending flags | No | Audited; no lifetime-history claim or history snapshot |
| Timed/untimed | Separate `GetSeasonBestForMap` return slots; completion info has `onTime` | Reliable as the in-time/overtime API slot; do not infer from duration versus timer | Run/season | Slot distinction persists | Implemented with separate slots |
| Keystone upgrade count | completion info includes `keystoneUpgradeLevels` | Run-result detail only | Run | No | Audited; omitted |

API definitions are in Blizzard's generated `MythicPlusInfoDocumentation.lua`, `MythicPlusInfoSharedDocumentation.lua`, `ChallengeModeInfoDocumentation.lua`, and `WeeklyRewardsDocumentation.lua` in the [current UI source mirror](https://github.com/Gethe/wow-ui-source/tree/live/Interface/AddOns/Blizzard_APIDocumentationGenerated). The [Blizzard Challenges UI source](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_ChallengesUI/Mainline/Blizzard_ChallengesUI.lua) reads the two seasonal best records, uses their `dungeonScore` values to choose the displayed row when both exist, reads `GetWeeklyBestForMap` separately, and uses `GetDungeonScoreRarityColor` for overall rating display. The mirror identifies itself as a mirror of the latest UI source and its `live` branch tracks Retail; verify again after client patches.

## Season and dungeon identity

`seasonId` is the authoritative ID from `C_MythicPlus.GetCurrentSeason()`. `displaySeasonId` is retained separately if `GetCurrentUIDisplaySeason()` is available; it is not substituted for the actual season ID. No season is inferred from a date or hardcoded ID.

`C_ChallengeMode.GetMapTable()` defines the entire current pool. A scan sorts IDs for deterministic display, requires each ID to be unique, and requires metadata and successful best-run reads for every member. It does not assume a fixed pool size. `challengeMapId` is the row key; localized dungeon name is presentation only. `GetMapUIInfo` may return nothing before map info is ready.

If a stored season differs from the known current season, bootstrap requests a new scan and the Character UI suppresses old-season rows. The original stored block may remain until a valid replacement commits. A missing current-season API does not make old data current; the UI reports no current-season data.

## Best runs, score and affixes

The schema keeps `bestInTime` and `bestOverTime` as distinct API-selected records. Each record stores the documented level, run score, duration, completion calendar fields, and affix IDs; it does not store party members. For the map's single displayed score, Holy Storm follows the Blizzard Challenges UI rule: use the higher `dungeonScore`; if tied, use the overtime record. Both API-selected records remain stored separately.

The map score is taken from the selected run record's documented `dungeonScore`. If a successful `GetSeasonBestForMap` call returns neither slot, the map has no season best and its score is zero, matching the Blizzard Challenges UI. If either best-run slot exists, the higher run score is used. This does not substitute a missing API read with zero: a failed call or malformed record rejects the scan. `GetOverallDungeonScore` remains the character total. Affix detail comes from the separate `GetSeasonBestAffixScoreInfoForMap`; if Blizzard returns nothing, `affixScores` stays nil. A returned empty table stays an empty table. Localized affix names are labels, not stable keys, and are never mapped to `FORTIFIED` or `TYRANNICAL`.

Current `GetSeasonBestForMap` documentation declares `completionDate` as `CalendarTime`. The current Calendar API field is `monthDay`; the previous MythicPlusDate shape used `day`. Collection accepts the current `monthDay` value and normalizes it to the existing stored `completionDate.day` key. This keeps timestamps comparable and avoids persisting a transient API type name.

Dungeon rating color comes from `C_ChallengeMode.GetDungeonScoreRarityColor`; the numeric score remains authoritative and the UI falls back to uncolored text if the color API fails.

## Weekly data and Great Vault

Mythic+ season bests do not reset weekly. Great Vault activities are a separate weekly concept. The optional `greatVaultMythicPlus` record contains activity `id`, display `index`, `progress`, `threshold`, `level`, and optional API tier/type values. `progress` is the number of completed Great Vault thresholds; it is never labeled as a number of runs.

Weekly data is included only when `AreRewardsForCurrentRewardPeriod()` is true, the Mythic+ activity type exists, `GetActivities()` returns a complete usable list, and the shared reset identity from `C_DateAndTime.GetWeeklyResetStartTime()` is available. The existing Delves producer uses that same reset identity. The UI always labels the Great Vault Mythic+ field and shows a neutral unknown marker unless the stored reset identity matches the current one. API-unavailable or previous-period data remains unknown/omitted. `HasAvailableRewards()` is intentionally omitted because it describes vault-wide reward availability, not an M+ reward specifically.

## Snapshot schema and validation

The block and snapshot schema are v5. V5 makes per-map `affixScores` optional because Blizzard documents that API as `MayReturnNothing`; the required map score and best records come from `GetSeasonBestForMap`. It also normalizes the current `CalendarTime.monthDay` field into the stable stored `day` key. V3 and v4 snapshots remain stored but fail current validation; bootstrap requests a replacement, and PlayerData retains the prior stored block unless a complete v5 snapshot commits.

```lua
{
  schemaVersion = 5,
  snapshotVersion = 5,
  seasonId = number,
  displaySeasonId = number?,
  overallScore = number, -- 0 is valid
  dungeonCount = number,
  poolComplete = true,
  scoreDataReady = true,
  dungeons = {
    {
      challengeMapId = number,
      name = string,
      instanceId = number,
      mapId = number,
      timeLimit = number,
      score = number, -- 0 is valid
      bestInTime = run?,
      bestOverTime = run?,
      affixScores = {}?, -- nil means API detail unavailable; {} means confirmed empty
    },
  },
  weeklyIdentity = number?,
  greatVaultMythicPlus = { currentPeriod = true, progress = number, activities = {} }?,
}
```

Validation checks exact schema versions, finite numeric season/rating/map/score/run values, unique map IDs, a complete dynamic pool, metadata for every dungeon, best-run shapes, and weekly identity/vault invariants. Season, overall rating, pool, or map metadata that is not ready remains UNKNOWN. Numeric rating zero is valid. A successful best-run API call with both nil slots is a confirmed no-completion state and yields map score zero. Nil affix detail remains UNKNOWN; it is never converted to zero or `[]`.

Stable validation reason IDs are:

- Retryable readiness: `UNKNOWN_MYTHICPLUS_SEASON`, `UNKNOWN_MYTHICPLUS_RATING`, `DUNGEON_POOL_NOT_READY`, `DUNGEON_MAP_INFO_NOT_READY`, `INCOMPLETE_MYTHICPLUS_POOL`, `INCOMPLETE_MYTHICPLUS_MAP`, and `INCOMPLETE_MYTHICPLUS_SCORES`.
- Immediate failure: `RETAIL_API_UNAVAILABLE`, `INVALID_DUNGEON_POOL`, `DUPLICATE_DUNGEON_MAP`, `BEST_RUN_API_UNAVAILABLE`, `BEST_RUN_API_ERROR`, `INVALID_BEST_RUN`, `INVALID_BEST_RUN_FIELDS`, `INVALID_BEST_RUN_COMPLETION_DATE`, `INVALID_BEST_RUN_AFFIXES`, and schema/record invariant failures returned by validation.

`updatedAt` is diagnostic only; semantic comparison remains owned by PlayerData and ignores it under the existing timestamp normalization. Identical meaningful content does not create a new revision or publish.

## Collection, readiness, retry and triggers

Bootstrap, a current-season mismatch, a weekly reset mismatch, and manual `/hs scan mythicplus` use the same `CharacterScanManager` provider. A manual/bootstrap request calls `RequestMapInfo()` and `RequestRewards()` before the workflow scans. Blizzard signals map readiness with `CHALLENGE_MODE_MAPS_UPDATE`; that event queues another ordinary CharacterScan request. The same non-parallel Snapshot workflow performs every retry as a fresh collection. Only season/rating/pool/map-metadata readiness failures retry. Invalid pool IDs, API errors, malformed best records, and invalid schemas fail without repeating an unchanged read. There are at most three retries after the initial attempt, 2.5 seconds apart; total attempts are four. No timer loop is used, and response events enter the same serialized scan path.

`CHALLENGE_MODE_COMPLETED`, `MYTHIC_PLUS_NEW_WEEKLY_RECORD`, `CHALLENGE_MODE_MAPS_UPDATE`, and `WEEKLY_REWARDS_UPDATE` request a scan through `CharacterScanManager`. The completion provider uses the existing delayed workflow start because the completion event is synchronous. No raid boss kill or generic login event is registered by this feature. `MYTHIC_PLUS_CURRENT_AFFIX_UPDATE` is not a trigger because the rotation is not stored.

The current Blizzard Challenges UI requests map info on show, listens for `CHALLENGE_MODE_MAPS_UPDATE`, and builds seasonal map rows from `GetSeasonBestForMap`'s two slots and their `dungeonScore`. It defaults a row to zero only when neither best record exists. Its optional tooltip reads affix detail separately. This is why Holy Storm treats `GetSeasonBestAffixScoreInfoForMap` as optional and uses the same best-run records for required per-map scores.

## Persistence, sync, query consumers and UI

The producer commits only through `PlayerData:WriteOwnedBlock`. Standard character-domain sync carries only the validated persistent block after an authoritative changed commit. There is no Mythic+ view permission; default Character visibility follows the shared Character UI policy. Remote tabs render their selected CharacterStore snapshot. The current season API is used only as global context to reject stale-season rows, never to fill remote rating or dungeon data.

The dashboard uses the same stored `overallScore` and season ID as the Character tab. The `mythicplus.rating` rule field also reads the stored block. There is no second query abstraction because these current consumers need only a direct rating lookup and map-ID keyed rows. Manual scans use the same provider/workflow/validation/commit route as automatic scans.

## Known limitations and Retail acceptance

- No WoW Retail client was available for live validation. Confirm whether the live branch APIs and activity enum still match the installed Retail build.
- Verify loaded map score readiness after login and after completion, including a zero-rating character and a season transition.
- Compare all dynamic pool IDs, per-dungeon score, each in-time/overtime best, affix IDs, timer state, and Blizzard rating color with the in-game UI.
- Confirm Mythic+ Great Vault thresholds against the current reward period, after reset, and with old reward data. Verify displayed progress describes thresholds, not runs.
- Exercise no keystone, a new keystone, an active run, a practice completion, untimed completion, `/hs scan mythicplus`, reload, remote storage and two-client sync.
- Check BugSack and logs; confirm unchanged content does not increase block revision.
- Run all offline tests and addon validators listed in the task before committing.
