# Core Sync and DataManager Audit

Date: 2026-10-10
Baseline: `677f5e2` on `main`

## Scope and result

Reviewed the live persistence/DataManager APIs, PlayerData and CharacterStore,
GuildStore, SnapshotManager, SyncManager and Comms/SyncTransport, TaskManager,
WorkflowManager, EventBus, and the registered Sync domains. The audit followed
the current source rather than treating older audit notes as current behavior.

Four confirmed issues were fixed:

1. A higher numbered relay copy could replace a character block previously
   received directly from its owner. Character-block freshness now gives the
   direct owner precedence over relay version numbers. A direct owner can
   refresh an indirect cache even when its version number is lower. An offline
   relay may still advance a cache when no direct owner copy has been received.
2. Mythic+, Delves, and Stats computed a full serialized fingerprint during
   snapshot validation, but their commit callbacks ignored it. Those workflows
   now skip that redundant pass; PlayerData's semantic equality check and
   unchanged-write suppression remain in place.
3. Repeated Presence messages with the same valid peer version emitted a
   duplicate version event and queued a duplicate version notice. Presence
   still refreshes peer liveness, but version work now occurs only when that
   peer's version changes.
4. Core RuleEngine read persisted rule demands directly from `HolyStorm.db`.
   RuleEngine now registers the existing demand path with DataManager and reads
   through that schema; the feature provider uses the same schema to commit.

Several nearby systems were already behaving as required and were left intact:
the login manifest is metadata-only and bounded; payloads are fetched on
demand; equivalent jobs and requests coalesce; the receive queue and active
transfer slot are bounded; and privacy checks are repeated before export.

## Actual data paths

### Local character snapshots

```text
Relevant game event or explicit refresh
  -> existing CharacterScanManager / TaskManager request
  -> producer task and validation task
  -> SnapshotManager workflow
  -> PlayerData/CharacterStore owner commit
  -> owned-update event
  -> Sync metadata offer and demand-driven transfer
```

An unchanged local block is rejected as `UNCHANGED` before a new owner
revision or owned-update event is produced. The accepted stored block remains
available while a scan is pending or fails.

### Incoming synchronization

```text
AceComm/ChatThrottleLib frames
  -> HSC1 reassembly and complete-message size checks
  -> Sync envelope/correlation checks
  -> bounded pending payload list (64)
  -> one unique Sync.ReceivePayload TaskManager worker
  -> domain validation, authorization and freshness checks
  -> domain importer and its atomic/validated persistence boundary
```

The importer is not called for an invalid or stale payload. Character blocks
are committed through `PlayerData:AcceptRemoteBlock`; domain stores retain
their existing import rules. Successful imports publish the established
update events and preserve owner and origin-revision metadata through relays.

### Login and discovery

`Sync.LoginPresence` sends the addon version, a session ID, reply information,
and a schema-1 manifest capped at 64 metadata entries. Presence contains no
snapshots. The receiver requests only missing or newer eligible objects. The
legacy global catch-up entry point is suppressed at login, and Sync does not
schedule a recurring global Presence heartbeat. Targeted discovery, feature
use, roster changes, and relevant domain events can still create demand.

Metadata pages are capped at 100 offers. Pending unknown-domain manifest
entries are capped at 256. Sync uses one central catch-up queue and one global
logical payload transfer slot; duplicate object/revision jobs merge. Outbound
request coalescing uses the existing 0.75-second window. Transport
fragmentation, throttle priority, retries, timeout handling, and failure
suppression remain in the existing communication and Sync components.

## Persistence boundary and direct access review

`HolyStorm.DataManager` is a real schema-backed API in `Persistence/Database.lua`.
It supports schema registration, validated reads, owner-managed roots,
copy-on-write `Commit`/`Update`, and change events. The touched feature data
paths now use it:

| Data | Persistence contract | Existing data location |
| --- | --- | --- |
| Character rule demands | `character-rule-demands`; read with `Get`, write with `Commit` | `HolyStormDB.global.filters.demands` |
| News/content store | `content-store`; owner-managed root | `HolyStormDB.global.content` |
| Achievement store | `achievement-store`; owner-managed root | `HolyStormDB.global.achievements` |
| Content install ID | `Database:Get("installId", "global")` | Existing global setting |

These registrations retain the existing SavedVariables paths and shapes.
Rule-demand notifications are emitted only when the committed demands change.
Core RuleEngine registers the same demand schema and reads through DataManager,
so the core reader does not bypass the feature's persistence contract.
Content and Achievement stores use `GetOwnedRoot` so their existing store
owners can keep their indexed operations without returning a full deep copy for
every operation.

The audit did not find a reason to claim that every persistent read or write
in the addon has been moved behind DataManager. AceDB initialization,
migrations, PlayerData/GuildStore internals, compatibility aliases, policy
state, filter settings, and some core/UI profile settings still have
intentional legacy or owner-managed access paths. The persistence-boundary test
protects the specific feature files changed here; it is not a repository-wide
proof of zero direct SavedVariables access.

## Registered synchronization data

Character snapshot blocks are objects within the `character` domain, not
separate domains. Current registered blocks are `identity`, `equipment`,
`mythicPlus`, `raid`, `delves`, `stats`, `profile`, `professions`, `addon`, and
`demands`. Their owner is the character GUID. Feature providers validate and
commit local data through PlayerData; enabled-block and permission checks gate
export. See `docs/SNAPSHOT_REFRESH_POLICY.md` for producer triggers and
freshness rules.

| Domain | Data and authority | Freshness / storage / access boundary |
| --- | --- | --- |
| `character` | Per-character blocks; owner is the character GUID | Owner-aware direct-versus-relay freshness; PlayerData block validation and commit; block/capability sharing checks |
| `permissions` | Guild permission state | `revision-chain`; Policy validates chain recovery and state before import. A high version alone never authorizes a permission change |
| `twinks` | Account-owned character relationship snapshot | Owner snapshot validation and merge in TwinkCore/PlayerData |
| `twinkAdmin` | Administrative assignment/removal and tombstone | Validated assigning authority plus `twinks-manage-manual-assignments`; owner-sourced relationships are protected |
| `content` | Guild news, guides, and announcements | ContentStore; entry author/modifier identity, revision, visibility, and action-specific permissions are checked |
| `achievements` | Achievement definitions and related guild achievement data | AchievementStore; service validation, authorization, and import rules remain in force |
| `guildLog` | Individual guild log events | `revision-chain`; GuildLogStore event validation; current-guild scope and sensitive-event/view checks |
| `guildNotes` | Shared guild notes | Notes service validation, recipient selection, `CanShare`, and import authorization |
| `guildActivity` | Guild activity shards | Activity service validation, recipient selection, and `CanShare` |
| `guildActivityPoints` | Guild activity-point state | `revision-chain`; ActivityPoints validation, authorization, recipients, and sharing rules |
| `guildAbsences` | Guild absence records | Absences service validation and authorization |
| `poi` | Personal, guild, or live group/raid POIs | `revision-chain`, exact revision and target-session checks; personal POIs are never shared; no automatic catch-up |
| `guild-position` | Live member positions | Ephemeral; separately gated live sharing, no persistent catch-up |

Calendar/event records have no registered Sync domain in the current source;
their local calendar behavior was not expanded or given a new sync contract by
this audit.

## Scheduler and event findings

TaskManager remains the sole logical task queue. It dispatches at most one task
per scheduler run, examines at most 64 queued candidates or 2 ms per scan, and
uses unique/merge modes, priority aging, and continuation/async timeout support.
WorkflowManager owns step progression over that queue; Sync jobs remain in the
central Sync job planner rather than becoming one TaskManager task each.

Timeouts can terminate asynchronous waits, but Lua cannot preempt a synchronous
task callback once it has started. No measured in-client timeout was available
to attribute to a particular callback. EventBus dispatch work is proportional
to listeners for that event and copies the listener list before callbacks; the
audit found no separate event-loop or recursion defect. The duplicate Presence
version notification described above was the confirmed redundant event path.

## Reproducible performance measurement

`tools/test_snapshot_fingerprint_budget.lua` compares the optional extra
SnapshotManager fingerprint traversal using a synthetic 500-character fixture
with 3,002 table nodes. With the previous fingerprint-enabled option, the extra
pass serialized 119,406 bytes and traversed all 3,002 nodes once. With the
fingerprint disabled for these three consumers, that extra pass traversed 0
nodes and serialized 0 bytes. The fixture measures structural work, not elapsed
milliseconds or WoW frame time. Required validation, PlayerData semantic
comparison, and actual persistence work remain.

## Regression coverage and remaining runtime check

New tests cover the DataManager-backed core demand reader, direct-owner
precedence over a higher relay version, an
offline-owner relay cache, direct-owner repair from a lower version, quiet
repeated Presence versions, the three skipped fingerprint passes, and
DataManager-backed rule-demand changes. Existing Sync, permissions, persistence,
privacy, transport, retry, and startup tests remain part of the full suite.

Retail verification is still needed for large live guilds, simultaneous
logins, real transport bandwidth, game-event ordering, and CPU/frame-time
measurements. No in-game script-time improvement is claimed by the offline
tests.
