# Retail Raid scan runtime audit

Baseline: `be17eaa3c26fe4b70cfd153865171e5512df5bfb` on `main`.
This audit establishes code and offline contract behavior. Retail FPS, Blizzard
API cost, GC pauses and total client scan duration still require an ingame test.

## Proven source of sustained orchestration load

Every partial collection returned `GOTO scan`. SnapshotManager passed that result
to TaskManager.Complete. WorkflowManager archived the completed task ID and queued
a **new** Snapshot.raids.Scan task. This produced three lifecycle logs and
queued/started/completed events for every small slice, plus workflow step/wait
events. The slice timer measured collection, excluding this surrounding work.

TaskManager.archive walks retained completed tasks and searches the history for
each task. Workflow.completedTasks grew throughout collection. Developer workflow
projections copied that growing list. Task/workflow events dirtied the Developer
UI; selected details also copied/searched Logger history. Logger writes copy their
context and emit HS_LOG_ADDED. This explains a sustained load amplifier even when
each collection slice contains little API work. Its exact share of the observed
Retail FPS drop cannot be quantified offline.

The scheduler already executed one task per Process call; there was no inner
multi-task catch-up loop. However, no continuation frame guard existed. The fix
guards a continuing task with WoW's frame-stable GetTime, including repeated
Process calls and overdue wakes, and schedules relative to current completion.

## Measured fixture

One tier, one raid, eight bosses, 96 Statistics categories, 1,025 labeled rows
(one exact current statistic, 1,024 unrelated rows), two weekly lockouts.
Both measurements load the real TaskManager, WorkflowManager, SnapshotManager
and Raid collector; Blizzard APIs, Logger/Event delivery and persistence are
deterministic fixtures. Counts are structural measurements, not Retail timings.

| Quantity | Baseline | After |
| --- | ---: | ---: |
| Scan task instances / lifecycles | 594 | 1 |
| Total snapshot task instances, including Validate and Commit | 596 | 3 |
| queued / started / completed snapshot task events | 596 / 596 / 596 | 3 / 3 / 3 |
| completed task IDs retained by the workflow | 596 | 3 |
| Logger entries | 1,830 | 14 |
| Actual collection slices | 594 | 2,332 |
| Actual API calls in collection | 2,285 | 2,284 |
| Current-ID cache retained candidates | 1,025 | 1 |

The larger cold slice count is intentional: ID enumeration and label lookup are
now separate potentially expensive calls, with at most one API per slice. There
is no added fixed Raid delay. Initial Statistics discovery still enumerates every
category once; a generic category label cannot safely exclude current Raid data.
Cold discovery duration is an explicit Retail acceptance item, not an assumed
success. It must not become an unacceptable prolonged sequence of frame spikes.

The next same-catalog fixture refresh takes **34 collection slices and 21 API
calls**: one EJ tier check, one mapped statistic value, 19 saved-instance queries.
It performs no catalog build, Statistics category traversal or label discovery.

## Authoritative pipeline and work frequency

`/hs scan raid` -> CharacterScanManager.Request -> CharacterScan.Advance -> Raid
provider -> SNAPSHOT_RAIDS -> Scan (same task resumes) -> catalog / difficulty
metadata / Statistics ID discovery / lifetime / RaidInfo readiness / weekly
lockouts -> Validate -> atomic PlayerData.WriteOwnedBlock -> owner update event
-> Sync.Publish(character, block). CharacterScanManager releases the producer
on the terminal workflow event and advances one coalesced pending request.

Completed collection phases were already retained during an undisturbed baseline
run; the audit did **not** establish a complete recollection on every GOTO. The
repeated hot work was task creation, archival, lifecycle events/logging, workflow
projection and UI invalidation. Additional unnecessary collection work occurred
between logical scans: CollectRaidCatalogChunk ignored the available static
catalog cache, and every scan traversed unrelated retained candidate rows.

| Work | Baseline frequency | New frequency |
| --- | --- | --- |
| Static catalog construction | Every logical scan, all tiers and bosses | Once when missing, explicitly invalidated or EJ tier count changes |
| EJ_SelectInstance | Every enumerated raid, including history | Zero; metadata/encounters use explicit journal instance IDs |
| EJ_GetInstanceInfo | Every enumerated raid | Current-tier raids only on catalog build |
| EJ_GetEncounterInfoByIndex | All tiers on each scan | Current-tier encounters only on catalog build |
| Historical raid identity index | Full encounter catalogs | ID/name/tier only; preserves older/Timewalking lockout identity |
| GetNumSavedInstances | Once per completed collection | Once, after the requested RaidInfo response |
| GetSavedInstanceInfo / EncounterInfo | Once per returned instance / boss | Once per returned instance / boss |
| Statistics category/row/label enumeration | Once without a valid ID cache | Once without a valid ID cache; IDs and labels in separate slices |
| Lifetime GetStatistic(id) | Once per unambiguous mapped current slot | Once per unambiguous mapped current slot |
| Candidate mapping / unmapped traversal | Includes all historical candidates | Only current raid/boss candidates; foreign matches remain rejected |
| Old detached snapshot load | Once per collection attempt | Once per collection attempt |
| Provider validation | After complete candidate | After complete candidate, once per successful attempt |
| Owner schema validation | Inside atomic write | Inside atomic write; retained |
| Unused Snapshot fingerprint | Once after provider validation | Zero for Raid; default unchanged for other producers |
| Semantic snapshot comparison | Once at owner write if old data exists | Same, once after complete collection |
| Comparable trees / semantic digests | Two for owner comparison plus unused fingerprint | Two for owner comparison; none on slices |
| Persistence preparation / revision update | Once at successful write | Once at successful write; unchanged candidate keeps revision |
| Partial persistence / partial Sync publication | None | None |

Searches across LIVE found no active definitions/callers for `_ScheduleScan`,
`ScanNow`, `OnUpdateInstanceInfo`, `_ScheduleDeferredStatsScan`,
`_RunStandaloneStatisticsEnrichment`, `ApplyRaidBestFromCharacterStatistics`.
There was no parallel legacy ingest or statistics enrichment pipeline. The
duplicated synchronous collector/discovery/lifetime implementations were
consolidated into adapters over the same collection algorithms. Stored Raid UI
reads committed snapshots and does not discover Statistics during rendering.

The explicit instance-ID metadata query also avoids depending on another UI's
selected EJ instance between slices. Blizzard's own UI uses this query form:
[Blizzard EncounterJournal source](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_EncounterJournal/Mainline/Blizzard_EncounterJournal.lua#L2265).
Statistics ID/skip enumeration follows the Blizzard Statistics UI contract:
[Blizzard AchievementUI source](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_AchievementUI/Mainline/Blizzard_AchievementUI.lua#L2106).

## Minimal generic continuation contract

TaskManager.Yield(task) requeues the **same** runtime task and callback. It does
not call Queue/Complete, log a lifecycle, emit slice events or sort the queue
again solely because of yielding. Callback execution durations accumulate using
GetTimePreciseSec where available. One API operation is followed by yielding,
even when that operation alone exceeds the time budget. CPU-only collection
loops keep the existing work/time bounds.

WaitForResume(task, timeout) uses TaskManager's existing bounded async timeout
and releases dispatch for unrelated work. ResumeTask cancels the timeout and
requeues the same task exactly once. HS_TASK_RESUMED is emitted only for a real
async signal; frame slices remain quiet. Cancellation, pause/resume, idle state,
timeouts, generic ASYNC completion and workflow coalescing remain observable.
No new scheduler, ticker, permanent OnUpdate or persistence was introduced.

RequestRaidInfo is requested once. Its expected UPDATE_INSTANCE_INFO response
unlocks the active context before Raid-instance trigger filtering, including
cities/world zones. Missing responses fail with TASK_TIMEOUT before any lockout
read/write; late responses are consumed. Genuine relevant events set one
dirtyAfterScan flag and submit at most one pending CharacterScan request.

## Diagnostics and counter definitions

One RAID_SCAN_PERFORMANCE record is emitted at terminal workflow completion
(also one on failure/cancellation, distinguished by status). Retained mapping
decisions are bounded volatile diagnostics, rather than per-boss Logger events.
The existing Developer TaskManager Performance view has a Raid last-scan row,
localized in deDE/enUS and refreshed through existing lifecycle notifications.

- totalWallMs: producer workflow request to terminal event, including waits.
- totalLuaMs: summed Raid callbacks, including collection/validation/commit;
  frame/async waits and unrelated tasks are excluded.
- slices: actual collector callback invocations, including readiness/retry work.
- maxSliceMs: longest actual collector callback, including a slow single API.
- taskLifecycleCount: distinct started Raid workflow tasks, normally three;
  validation retry attempts increase the count, slice continuations do not.
- catalogBuilds: actual new catalog builds, zero on a valid catalog cache hit.
- ejCalls: actual EJ tier selection/enumeration/metadata/encounter calls.
- statisticCalls: actual Statistics/category/label/value/difficulty queries.
- savedInstanceCalls: count, instance and encounter queries, including attempts.
- restarts: full collection retries or explicit generation invalidations.
- followUpQueued: genuine events that actually mark a coalesced next request.
- expectedInstanceInfoEvents: consumed response events belonging to the run.
- unexpectedRaidEvents: other relevant Raid events received while active.

## Files and focused checks

Runtime: Core/Tasks/TaskManager.lua, Core/Workflows/WorkflowManager.lua,
Persistence/SnapshotManager.lua, Holy_Storm_Raids/Raids.lua,
Holy_Storm_UI/UI/Pages/TaskManager.lua and its enUS/deDE locale files.

Targeted tests (no full suite):

- test_raid_workflow_continuation: real orchestration/context, one lifecycle,
  one API/frame, same-frame/backlog guard, no slice logs, one summary, actual
  counters, cold/warm cache, one old snapshot read, no unused fingerprint,
  slow API, async response outside Raid, independent tasks, timeout/late response,
  real CharacterScanManager login/freshness routing, one event follow-up,
  failed value reads/retries, expensive saved-instance exceptions and module
  disable preserving the previous snapshot.
- test_raid_scan_work_budget: exhaustive discovery, exact IDs, unrelated candidate
  pruning, one API/slice, cache recovery, failed discovery/value preservation.
- test_raid_catalog_work_budget: 24 tiers, current encounters, historical
  identities, no unnecessary instance selection, cache reuse/invalidation.
- test_raid_snapshot, test_raid_lifetime_pipeline: schema/identity/difficulties,
  ambiguous/foreign statistics rejection, deDE/enUS, lifetime/Best/weekly data,
  real PlayerData/CharacterStore/StoredFeatureTabs, persistence and reload.
- test_raid_trigger_routing: M+ lazy-load, relevant Raid-only triggers, expected
  response outside Raid and repeated genuine events coalescing.
- test_task_workflow: generic Yield, same task ID, lifecycle counts, frame guard,
  signal/resume, independent tasks, pause, duplicate resume, timeout/cancellation,
  GOTO/retry policies, pending workflow restart after a yielded first step.
- test_equipment_workflow, test_character_scan_manager, test_startup_storm:
  generic Snapshot, async, scheduler, producer and startup contracts.
- test_event_observability, test_task_reason_rendering,
  test_task_manager_diagnostics: existing metrics/reasons and all Raid summary
  counters in the Developer UI.
- luac -p for all changed Lua files; paired TaskManager locale key check;
  git diff --check.

## Exact Retail acceptance procedure

1. Install the updated LIVE addons, then /reload. Enable the FPS display. Note
   idle FPS and confirm no Raid collection starts solely from login/freshness.
2. Outside a Raid, run `/hs scan raid` once. Keep moving/turning during collection.
   Record minimum FPS, sustained drops and total duration; the old Raid snapshot
   must remain visible until completion.
3. Open Developer -> TaskManager -> Performance/Leistung, filter `Raid`, select
   Raid last scan/letzter Scan. Copy all 13 counters and status. Inspect the one
   RAID_SCAN_PERFORMANCE log for that workflow. Normally taskLifecycleCount=3,
   restarts=0 and expectedInstanceInfoEvents=1. Scan requested/started/completed
   must each occur once for that workflow, followed once by Validate and Commit.
4. Run `/hs scan raid` again in the same session. Compare responsiveness and
   duration. catalogBuilds must be zero; statisticCalls should now reflect only
   mapped values, rather than category/label discovery. Compare lifetime/Best
   and LFR/Normal/Heroic/Mythic weekly lockouts with `/hs scan raid status` and
   the stored Raid tab/Best tooltip.
5. Repeat with TaskManager closed and with Performance/Event Monitor visible,
   to check whether observability still causes sustained load.
6. After a successful Raid boss encounter, check one relevant refresh. Further
   relevant events during collection may produce one follow-up, preserving the
   current scan (no generation restart). M+ encounters must not scan Raid data.

Acceptance requires actual responsive Retail behavior and reliable complete
snapshots. A warm fast test does not substitute for the first cold scan test.
