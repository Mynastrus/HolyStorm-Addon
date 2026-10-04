# Holy Storm Sync v2

Sync v2 evolves the existing SyncManager, PlayerData, Comms and AceCommQueue
contracts. The envelope protocol remains v3 and HSC1 remains the transport
framing protocol. Snapshot ownership, origin revisions, receiver timestamps,
domain validation and persistence are still defined by their existing owners.

## Data path

```text
Presence / DISCOVER
        |
        v
Metadata offers (at most 100 objects per page)
        |
        v
Catch-up job queue (coalesced, bounded, prioritized)
        |
        v
One active logical data transfer
        |
        v
AceCommQueue / ChatThrottleLib -> HSC1 fragments
        |
        v
Reassembly -> Sync validation -> domain import -> atomic persistence
```

Transport fragmentation != Sync scheduling. HSC1 protects messages that have
already been selected for transfer; it does not decide which character or
domain should be sent next.

## Discovery and metadata

Discovery remains scoped by domain and object/scope. `activeRequests` merges
repeated login, roster, module and on-demand triggers while a request is
active. TaskManager retains trigger-source history for diagnostics.

Responders take one sorted metadata snapshot per domain/request and share that
index across recipients. Recipient-specific sharing checks are applied while
forming each page, avoiding a full copied list for every responding peer.
Offers are sent in pages of at most `Sync.maxOffers` (100). The requester asks
that same sender for the next page after receiving `hasMore`. The snapshot
expires with the normal request timeout. No snapshot payload is exported to
answer a discovery request.

Metadata pages are sorted by entity key and revision. Character block IDs use
`GUID + separator + block`, which keeps a character's block jobs together in
the FIFO order when priorities match. GuildLog uses its event/entity IDs and
the same bounded paging mechanism.

## Job planning, identity and deduplication

`Sync.catchUpJobs` is an in-memory queue capped at 20,000 jobs. A job records
its object/entity, domain, owner/character, wanted version and revision, up to
five source candidates, priority class, state, queue/start time, retry count,
request ID and failure reason. The logical deduplication key is:

```text
domain + entity/object ID + required version + required revision
```

Equivalent offers from multiple peers merge into the same job and add source
candidates. Repeated requests for the same owner/block/revision therefore do
not create extra transfers. Over-capacity work is rejected with a structured
diagnostic instead of being converted into more TaskManager tasks.

One unique `Sync.QueuePump` TaskManager task dispatches queued work. Jobs remain
in memory; they do not become individual TaskManager tasks or transport sends
until selected. The active slot is global, which is stricter than one active
large transfer per recipient. This serializes character/domain catch-up across
the client while preserving parallel control, metadata and Presence messages.

The classes are `USER_INTERACTIVE`, `IMPORTANT_CONTROL`, `BACKGROUND_CATCHUP`
and `MAINTENANCE`. Lower numeric values are more important, matching
TaskManager and SyncTransport. A user opening a character promotes an existing
queued job. Background jobs wait briefly for competing source offers. A
running domain transfer is allowed to finish before the next job is selected.
Queue waiting time is not counted as an execution timeout.

## Source selection and authority

Source candidates are coalesced before dispatch. The original owner is
preferred over a relay; candidates of equal authority are compared with the
existing metadata freshness/revision comparison. At most five alternatives are
retained. A timed-out/failed source is removed when another candidate exists.
Outbound `canShare` authorization is checked on receipt of FETCH and again
immediately before export.

The central planner does not create owner revisions. PlayerData continues to
accept only owner-originated revisions, preserve origin timestamps and
identity through relays, reject older revisions and same-revision conflicts,
and protect locally owned snapshots from remote copies.

## Traffic, payload boundaries and fragmentation

Sync uses the existing `SyncTransport` wrapper and AceCommQueue/ChatThrottleLib
priority queues; it adds no competing throttle. Presence, discovery and FETCH
control use the higher-priority transport classes. Large background PAYLOADs
use the bulk class. At most one logical Sync payload is in flight globally.

Each PAYLOAD has one domain and one object/entity ID. Character payloads remain
one character block each. GuildLog event entries remain individually keyed;
metadata pages are bounded and never turn into an unbounded full-log payload.
Domain snapshots are not split after export because splitting an atomic domain
snapshot could invalidate its schema and commit semantics.

HSC1 retains its current 220-byte chunks, 300-fragment ceiling and serializer
byte ceiling. Transfers at 48 fragments or more produce a semantic warning
with request, entity, domain, revision, bytes and fragment count. A transfer
over the HSC1 ceiling is failed/deferred before frames are queued. Packet-level
send/receive detail stays at DEBUG; Comms reports aggregate completion and
fragment progress to Sync.

## Receive and atomic commit

Comms emits `HS_COMMS_MESSAGE` only after every HSC1 fragment has been
assembled and the complete serialized message is within the transport limit.
Sync places the complete payload in a bounded in-memory receive queue and uses
one `Sync.ReceivePayload` TaskManager worker. The worker applies envelope
identity checks, domain schema validation, authority checks and freshness
checks, then calls the domain importer. PlayerData commits each character
block as one write and emits its update event only after persistence succeeds.
GuildLog retains its own validated event merge semantics. Invalid, stale or
failed imports leave the last valid snapshot intact.

## Retry and recovery

Each selected data job has at most three retries with bounded exponential
backoff. Fetch response timeout and transport/import failures release the
active slot, record a structured result and let the queue continue. A terminal
failure removes the active dedupe entry but retains the old cache. The next
login/discovery can offer the object again. The queue is deliberately
in-memory; metadata discovery reconstructs unfinished work after reload.

## Presence and GuildLog

Presence is independent of the data transfer slot. Existing version semantics
remain in Sync: local version is authoritative, versionless Presence refreshes
peer liveness without erasing a known version, valid Presence refreshes peer
version freshness, and expired peers are removed after the existing timeout.
`DEV` and semantic release versions retain their existing validation.

GuildLog synchronization is by event ID, revision and metadata. Events are
individual bounded entities, not a transfer of the full persisted log. The
module's existing privacy filters remain responsible for suppressing
officer-note-sensitive content before export; the generic queue does not
bypass them.

## Activity and UI

`Sync:GetActivity()` returns a read-only copy of active operation details and
the queued job count. `HS_SYNC_ACTIVITY_UPDATED` announces active phase and
fragment-progress changes. MainWindow and Character Overview use only this
model; they do not infer Sync state from transport internals.

The activity model registers each qualifying operation with an activity ID and
ends it by that ID, so a late completion cannot end a newer operation. A fetch
counts while its response timeout is live or its matching payload is being
committed; a send counts while its own Comms transmission is outstanding.
Presence heartbeats, metadata request history, queued work, debounce delays and
maintenance tasks do not count. Fetch request IDs rotate on each attempt, and
recent terminal IDs are ignored so a late reply cannot start receive work again.
Activity reads and normal terminal events reconcile registrations against those
runtime owners and release stale entries without polling. Transient activity,
catch-up and receive state is cleared on initialization and shutdown.

Sync diagnostics expose active activity IDs/count, transfer/request/job details,
queue length, domain, phase, age and an event-driven mismatch flag. A stale
published active state is released and logged once when reconciliation finds no
authoritative runtime operation.

The MainWindow footer's center stays hidden while no logical transfer is
active. During an active transfer it shows only localized “Sync running” / “Sync
läuft” with a rotating indicator. Its tooltip contains localized labels for
character/entity, domain, direction, phase, source, target, request, revision,
bytes, fragments, retry and queue position. Character Overview shows the same
indicator only when the active operation's character GUID matches its current
context exactly.

Character views continue reading their existing cached snapshots immediately.
Refreshing does not clear a view; the receive worker swaps a validated
snapshot through the existing domain importer. The manual character refresh
button retains the local scan workflow, and opening a remote Character Overview
queues its requested blocks as interactive Sync work.

## Large guild behavior

The regression test `tools/test_sync_v2.lua` creates 1,000 characters with
three stale domains (3,000 jobs), duplicates metadata across two relay sources,
opens one character interactively, and checks bounded metadata pages, one
active transfer, constant TaskManager pump count, owner preference, Presence
availability, retry continuation, one-object payload boundaries and atomic
receive. The test models scheduling and payload boundaries; in-game bandwidth,
guild roster timing and Retail UI behavior still require a Retail client.
