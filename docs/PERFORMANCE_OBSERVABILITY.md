# Core Performance & Runtime Observability

Holy Storm exposes low-overhead, volatile runtime metrics at existing lifecycle
boundaries. The implementation extends the Task Manager, Workflow Manager,
EventBus, CharacterScanManager, SyncManager, and UIManager; it does not add a
profiler, polling loop, metrics scheduler, or parallel debug interface.

## Low-overhead principles

- Counters update only when a task, workflow, scheduler pass, event dispatch,
  producer request, sync job, or central UI page refresh changes state.
- No stack sampling, per-function hooks, or permanent `OnUpdate` measurement is
  used.
- Event observability stores bounded aggregates, not event arguments or payloads.
- Metric keys are bounded and long trigger names are truncated. Existing task,
  workflow, and event history limits remain in force.
- Metric getters do not deep-copy metric trees. Developer views read aggregates
  only when rendered; the closed Task Manager does not schedule refresh work.
- Metrics do not emit events, queue tasks, or wake the scheduler.
- Runtime metrics are in-memory only. They are not written to SavedVariables,
  snapshots, logs, sync payloads, POIs, or settings.

## Task metrics

The Task Manager's **Performance** view reports task-type and module aggregates:
requested, started, completed, failed, cancelled, retries, merges, trigger
counts, average queue wait, and average/maximum execution time. Module and
trigger-category/name aggregates combine task and workflow activity.

Queue wait is measured from the task's monotonic queue timestamp to its first
start. Execution time measures the time spent inside the task callback. For an
asynchronous task, the interval waiting for `Complete()` is reported separately
as async wait and is not charged as callback execution. `GetTime()` is used for
monotonic timing; wall time is reserved for display timestamps.

Trigger attribution records a category (`BLIZZARD_EVENT`,
`HOLY_STORM_EVENT`, `USER`, `SYNC`, `MAINTENANCE`, or `SYSTEM`) and its trigger
name. The original bounded trigger history remains available on individual
tasks for detailed inspection.

## Workflow metrics

Workflow aggregates count requested, started, completed, failed, and cancelled
workflows, along with retries/merges/triggers and elapsed time. Live workflows
retain their module, trigger, current step/task, and status in the existing
**Workflows** view. Workflow elapsed time intentionally includes time spent
waiting between steps; task execution time does not.

## Scheduler metrics

The Performance view exposes scheduler wake requests, actual scheduler runs,
coalesced wakes, queue-budget exhaustions, queue scans, queue checks, selected
tasks, and transitions between idle and active. These counters are updated in
the existing `Schedule`, `Wake`, `Process`, and queue-selection paths.

## Event aggregation

The existing **Event Monitor** now reads EventBus aggregates: dispatch count
per event, last-seen timestamp, and follow-on task/workflow requests and starts.
Only fixed counter fields and timestamps are retained. Event arguments,
payloads, chat text, and snapshots are never stored by these metrics.

Follow-on counts are attributed when the central task/workflow request has the
same trigger name as an already observed event. Other custom trigger names
remain visible in task/workflow trigger aggregates but are not fabricated into
event-dispatch counts.

## Producer scans

CharacterScanManager keeps volatile per-block counters for the standard
`equipment`, `mythicPlus`, `raid`, `delves`, and `stats` providers. Each reports
requested, automatic, manual, trigger-name, completed, and failed counts.
`loginProducerScans` counts automatic providers actually launched during the
existing four-second startup window. It begins at zero on `PLAYER_LOGIN` and
does not request scans or create timers.

Snapshot presence, age, or absence do not create producer requests. Thus a
zero login-producer count after `/reload` directly reflects whether a producer
was launched during startup, rather than whether cached data happened to exist.

## Startup diagnostics

The existing TaskManager startup window (four seconds) aggregates task,
workflow, scheduler, sync-job, producer-scan, and central UI page-refresh
counts, plus peak task queue size and elapsed time. The window expires when
existing runtime code queries or processes tasks; it adds no scheduler or timer.
Its results remain available in memory after the window closes.

## Sync metrics

SyncManager reports requested, started, completed, failed, and retried
catch-up transfers, with bounded domain/reason aggregates and current queued
and active work. Existing transfer details remain available through Sync's
runtime diagnostics. Outbound task work is also attributed to the `Sync`
module by TaskManager.

## Idle definition

The combined status is **Idle** only when:

- the task queue, scheduler execution, and pending task wake work are empty;
- no non-terminal workflow exists;
- CharacterScanManager has no active or queued scan; and
- Sync has no active transfer, outstanding discovery request, queued catch-up
  job, or pending payload.

Scheduled expiry timers alone are not counted as currently executing work.
Waiting tasks and workflows count as active/pending work, even when blocked on
conditions or a future delay.

## Developer UI and reset

The existing Task Manager Developer page is reused:

- **Performance** shows current runtime state, active/waiting tasks,
  workflows, scheduler/startup metrics, sync activity, producer scans, module
  totals, trigger totals, and task/workflow-type aggregates.
- **Event Monitor** shows payload-free per-event aggregates.
- **Live Tasks**, **Queue**, **Workflows**, and **History** keep their existing
  detailed views.
- Text is localized in `enUS` and `deDE`.

**Reset runtime metrics** clears only in-memory metric counters and aggregates
in TaskManager, WorkflowManager, EventBus, CharacterScanManager, SyncManager,
and UIManager. It does not cancel work or clear task/workflow histories, logs,
snapshots, SavedVariables, sync data, POIs, or settings.

## Persistence and privacy

Runtime metrics are not persisted and naturally reset when the addon reloads.
Task Manager column layout remains an existing user setting and is independent
of the metric data. Aggregates contain only bounded event/trigger/module names,
counts, and timestamps; no event payload, chat content, character snapshot,
serialized sync payload, or user-provided event arguments are captured.

## Retail test procedure

1. Enable the Task Manager Developer page and select **Performance**.
2. Run `/reload`; after the startup window closes, inspect the five producer
   rows. `Automatic` and `loginProducerScans` should remain zero unless an
   actual event-driven automatic producer ran during startup. A manual scan
   should increment only the matching provider's manual/requested counters.
3. Request a manual producer scan and confirm it appears first as waiting,
   then started, and finally completed or failed with its trigger name.
4. Compare a delayed task's queue-wait value with its execution value. For an
   asynchronous task, verify async waiting is not added to callback execution.
5. Generate task/workflow activity and confirm module/trigger aggregates and
   Event Monitor follow-on counts update. Confirm no payload details appear in
   the aggregate rows.
6. Leave the Task Manager closed while normal events occur; no Task Manager
   refresh should be scheduled. Reopen it to read current aggregate values.
7. Use **Reset runtime metrics** and confirm counters return to zero while
   active work, histories, logs, snapshots, settings, and sync state remain
   unchanged.
