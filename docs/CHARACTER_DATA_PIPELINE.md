# Character Data Pipeline

This document describes the persisted character snapshots for Equipment, Mythic+, Raids, Delves, and Stats. The shared policy remains cache-first on login, idle by default, and event-driven. A snapshot's absence, age, or stale domain identity never starts a producer by itself.

## Common lifecycle

```text
Blizzard change event or explicit user request
  -> CharacterScanManager (one serialized producer at a time)
  -> provider workflow through TaskManager / WorkflowManager
  -> candidate collection
  -> validation and, when needed, comparison
  -> PlayerData / SnapshotManager atomic owned-block write
  -> owned-block and block update events
  -> SyncManager publication for a changed authoritative revision
  -> passive Character Overview and Dashboard reads
```

The UI reads the last accepted CharacterStore block immediately. `DIRTY`, `REFRESHING`, and `ERROR` preserve that value. `CURRENT` and `STALE` describe the stored block; freshness is domain-specific. Missing or unsupported data stays missing or unsupported until an explicit action or relevant event starts a producer.

`CharacterScanManager` is the only entry point for manual and event-driven feature scans. `/hs scan <block>`, `/hs scan all`, Dashboard's global `Daten aktualisieren`, and individual block actions use the same provider queue. `RequestAll` targets every declared snapshot provider, regardless of current status; the manager serializes them. `SyncManager` follows a changed `PlayerData:WriteOwnedBlock` event. Producers do not publish transport directly. Unchanged writes do not create an authoritative revision or a Sync publication.

Before a provider's first TaskManager task starts, the provider explicitly declares whether its underlying workflow can merge another request safely. Equipment, Mythic+, Delves, and Stats opt into this path because their workflow manager resets/merges the queued first step. Raid does not: its active run object exists as soon as it is queued, before the workflow task starts, so a real Raid change is held as one pending CharacterScanManager follow-up. This keeps a correlated Raid event from being swallowed by a provider that simply returns its current run ID.

All five owners read through CharacterStore and commit through PlayerData. None access central SavedVariables directly. The stable origin owner, revision, and creation time are set by the owned-block persistence path; receive and relay timestamps do not replace the origin timestamp.

## Producer matrix

| Producer / owner | Stored schema | Triggers and coalescing | Workflow and retry behavior | Required and optional collection data | Validation, no-op, and freshness |
| --- | --- | --- | --- | --- | --- |
| **Equipment** / Equipment addon | v4 (`equipment`, `itemLevel`) | `PLAYER_EQUIPMENT_CHANGED`, player `UNIT_INVENTORY_CHANGED`, `SOCKET_INFO_UPDATE`; ignores callbacks before `playerReady`. `EQUIPMENT_UPDATE` has a one-second debounce that resets when a related event merges into its queued first step. During an active scan, repeated events create at most one serialized follow-up. | Custom `EQUIPMENT_UPDATE`: `Equipment.Scan`, `Equipment.Validate`, `Equipment.Compare`, `Equipment.ConfirmScan`, `Equipment.ConfirmValidate`, `Equipment.StabilityCompare`, `Equipment.Store`. Scan A equal to stored content ends after three task lifecycles. A changed A requires B and stable equality before Store. Up to five workflow retries, with 2.5-second retry waits. Task definitions have a 30-second timeout for an actual ASYNC wait; queue/debounce time does not consume it. Item-data-not-ready results request Blizzard item loading and retry through the bounded workflow. | Equipped slot state, item identity/link, item level, required item metadata, and aggregate item level must form a complete candidate. Links are preserved. Gem, socket, icon, and set metadata are retained when available; unknown socket/gem detail is represented as unknown where the schema allows it. | Validates all expected slots and item/link consistency. Fingerprint comparison skips Scan B and PlayerData entirely when A is unchanged. Changed data commits once, only after A/B match. Event-driven; age alone does not make it stale. |
| **Mythic+** / MythicPlus addon | v5 (`mythicPlus`) | `CHALLENGE_MODE_COMPLETED`, `MYTHIC_PLUS_NEW_WEEKLY_RECORD`, `WEEKLY_REWARDS_UPDATE`; progression events before `playerReady` are ignored. If loaded before ready, the first weekly reward event is suppressed to absorb initial availability; a late-loaded module accepts its first real weekly event. Repeated requests merge into the queued workflow's debounce; an event during active work can queue at most one same-block follow-up. | `SNAPSHOT_MYTHICPLUS`: `Snapshot.mythicplus.Scan`, `.Validate`, `.Commit`. Completion/new-record initial delay is 0.5 seconds; other requests use 1.5 seconds. Bounded at three retries, 2.5 seconds apart. | Current season, overall score, current map pool and required per-map UI/best-run data are required. Display season, weekly reward identity/content, textures/backgrounds, and affix score details are optional where the API can return nothing. Missing optional dungeon detail does not invalidate the current-season score block. | Schema/version and current season/map pool are validated. The centralized PlayerData write provides semantic no-op detection. Stored season and weekly reset identity determine stale status; no TTL scan. |
| **Raids** / Raids addon | v3 (`raid`) | Successful `ENCOUNTER_END` while inside a Raid; `UPDATE_INSTANCE_INFO` while inside a Raid. No enable/login scan. A `RequestRaidInfo` response is correlated to the waiting scan and resumes that task; it does not request another scan. Unexpected real Raid changes during a run can request at most one follow-up. | `SNAPSHOT_RAIDS`: `Snapshot.raids.Scan`, `.Validate`, `.Commit`. The persistent scan context yields internally through `Tasks:Yield`; slices do not create additional task lifecycles. The correlated instance-info wait uses `WaitForResume` with a 10-second timeout. Five bounded retries, 2.5 seconds apart. | Current catalog, instance/lockout context, and validated lifetime data follow the existing Raid contract. Catalog collection caches static Encounter Journal data; lifetime/best fields are retained independently from weekly lockout state. | Atomic PlayerData write after validation; generic fingerprinting is disabled because PlayerData owns the comparison contract. Weekly reset can stale lockouts; lifetime scope remains current. Raid behavior is a regression boundary and was not redesigned. |
| **Delves** / Delves addon | v3 (`delves`) | `WEEKLY_REWARDS_UPDATE` only. If loaded before ready, the first weekly reward event is suppressed even if delivered just after readiness; a module loaded after readiness accepts its first weekly event. Curio/account and live run/party events do not trigger the persisted snapshot. | `SNAPSHOT_DELVES`: `Snapshot.delves.Scan`, `.Validate`, `.Commit`. One-second initial delay; up to three retries, 2.5 seconds apart. | **Required:** current Delves season number and current weekly reset identity. **Optional:** Great Vault reward booleans and World activity progress when current-period attribution is established. Previous-period rewards never label World progress as current. **Unavailable:** companion, Bountiful, Nemesis, treasure-map, and other metadata without a supported reliable API are omitted. | Version, required identities, and optional World consistency are validated. Missing optional APIs degrade to unknown; missing required identity uses bounded retry and cannot commit. PlayerData detects no-ops. Stored season and reset determine stale status. |
| **Stats** / CharacterStats module in Characters addon | v2 (`stats`) | Equipment, specialization, traits, talents, and level events after `playerReady`; a one-shot 0.5-second baseline timer coalesces the burst. `UNIT_AURA` only schedules the local live overlay while the local Stats tab is visible; aura changes do not trigger a persisted baseline scan. | `SNAPSHOT_STATS`: `Snapshot.stats.Scan`, `.Validate`, `.Commit`. One-second initial delay; up to three retries, 2.5 seconds apart. | Primary stat baselines are captured when safely available. Armor and secondary values are omitted from a partial capture when timed auras make them transient. Specialization is optional. Live effective values remain a local UI overlay. | Validates safe optional numbers and requires at least one reliable value. Partial capture cannot include transient armor or secondary fields. PlayerData detects no-ops; Dashboard reads persisted `baseline`/`rating` fields. Event-driven; age alone does not stale it. |

For the generic SnapshotManager workflows, the three task types have a 30-second timeout configured. TaskManager arms a timeout only after a task yields as ASYNC; a queued task's wait and debounce are not execution timeout. Current non-Raid producers complete their collection synchronously or return bounded retry results. A synchronous Lua/API call cannot be interrupted by a timer on the same game thread. Raid's only expected external wait has its explicit 10-second resume timeout.

## State, failures, cancellation, and authority

- `MISSING`: no accepted snapshot. The UI offers a targeted scan action.
- `CURRENT`: supported snapshot with no known domain mismatch.
- `STALE`: valid cached snapshot from an earlier season/week where the domain uses those identities. The old value remains visible.
- `DIRTY`: an event or explicit request is queued, including a workflow waiting for its debounce.
- `REFRESHING`: the first TaskManager lifecycle actually started.
- `ERROR`: admission or a started workflow failed. The previous accepted snapshot remains available; a targeted retry remains possible.

Provider admission failures are counted separately from started scan failures. Cancellation releases CharacterScanManager ownership and workflow context; cancelled tasks cannot be resumed by a late callback. Raid releases its persistent scan run on terminal workflow events. A failed or cancelled candidate is never committed and therefore cannot publish Sync. Local owned data remains authoritative over imported/remote data.

The TaskManager **Leistung** view shows request source counts, automatic/manual requests, logical scans, actual TaskManager lifecycles, retries, completion/failure/admission/cancellation counts, commits, no-op results, last/total/max scan wall time, aggregate task Lua time, maximum task Lua time, queue wait, and trigger totals. Each producer's runtime details include last error, stage, API when the producer supplies one, concise detail, and retry state. Raid retains its finer scan metrics: wall time, measured Lua time, slice count and maximum slice, task lifecycle count, catalog builds, API call counts, restarts, and expected/unexpected instance-info events. Metrics are bounded in-memory aggregates; closing Developer UI leaves rendering idle and does not enable a profiler.

## Audit findings and regression boundaries

- Equipment already had the required stable A/B contract. Repeated events before the first task starts are merged into the queued workflow, resetting its one-second debounce. The audit removed one duplicate `C_Item.GetItemInfo` call; item links remain unchanged.
- Mythic+ progression events and Stats level-up were able to bypass readiness checks. Their callbacks now require `playerReady`; initial weekly availability remains protected until its first event so readiness itself cannot authorize a scan.
- Dashboard counted `effective`/`percent` fields even though persisted Stats stores primary `baseline` and secondary `rating`/`baseline`. It now counts the stored schema, including valid partial snapshots.
- Stats called mastery twice per capture; it now reuses the one API result.
- All five producers use PlayerData-owned writes and central Sync follow-up. A changed write produces one authoritative block update; no-op writes produce no new revision or publication.
- Raid's persistent scan context, yielding, catalog cache, work budget, correlated `UPDATE_INSTANCE_INFO`, lifetime/weekly split, and one-follow-up behavior are protected by the Raid regression suite. This pass adds only shared result metrics and does not alter Raid scan logic.
- Event Monitor keeps aggregate counters and bounded event history; it does not retain producer payload histories. Dashboard, Character Overview, and feature views remain read-only while rendering.

## Offline checks and Retail acceptance

Offline tests can verify event routing, queue coalescing, bounded retries, schema validation, no-op commits, task/workflow cleanup, and stored-value rendering. They cannot establish actual Retail API availability, Blizzard event order, CPU/FPS impact, or cross-client Sync behavior.

In Retail, verify:

1. `/reload`, then idle for 30 seconds. Confirm no five-producer scans start and no producer errors repeat.
2. Open and close Overview, Equipment, Mythic+, Raids, Delves, Stats, Dashboard, TaskManager, and Event Monitor. Confirm cached values render and closing a view stops its render work.
3. Click global `Daten aktualisieren`. Confirm all five providers run serially even when current. Click each individual refresh and confirm only its block runs. Repeat with `/hs scan all` and `/hs scan <block>`.
4. Change equipment. In TaskManager, verify burst requests merge, unchanged Scan A uses no Scan B/commit, and a real stable change commits once.
5. Complete a keystone or make another real Mythic+ progression change. Confirm one current-season scan for the event burst, and no scan from map-pool availability or opening the UI.
6. Manually scan Raids, then observe a successful encounter/lockout update. Confirm one Scan task lifecycle across yielded slices, a correlated instance-info response, no catalog rebuild storm, and no duplicate partial Sync.
7. Manually scan Delves with current, unavailable optional, and previous-period reward states where practical. Confirm required season/reset identity, unknown optional data, and no old-period attribution.
8. Change equipment/spec/talents/level for Stats. Confirm the baseline event burst coalesces; timed auras omit transient fields; the visible live overlay updates only in the local Stats tab.
9. In TaskManager **Leistung**, inspect requests/reasons, logical scans, task lifecycles, retries, wall time, commits/no-ops, and last failure stage/API. Compare Developer UI open and closed.
10. Inspect local authoritative revision and peer Sync after a real changed commit; repeat an unchanged scan and confirm it creates no new revision or Sync publication.

Retail CPU/FPS, API timing, event ordering, and actual peer publication still require an in-client run. No offline test is represented as Retail verification.
