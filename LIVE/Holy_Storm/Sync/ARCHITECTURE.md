# Holy Storm Sync v2

Sync v2 evolves the existing SyncManager, PlayerData, Comms and AceCommQueue
contracts. The envelope protocol remains v3 and HSC1 remains the transport
framing protocol. Snapshot ownership, origin revisions, receiver timestamps,
domain validation and persistence are still defined by their existing owners.

## Data path

```text
Login Presence + bounded revision manifest / on-demand DISCOVER
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
repeated roster, module and on-demand triggers while a request is active.
Login no longer starts discovery. TaskManager retains trigger-source history
for diagnostics.

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

## Login metadata and demand-driven payloads

The former path was `PLAYER_LOGIN -> Presence -> RunCatchUp -> Discover` for
every loaded domain whose `catchUp` flag was not false. The live opt-outs were
`poi` and `guild-position`. Redundant startup discoveries also existed in the
Achievements `PLAYER_ENTERING_WORLD` handler, POI startup, News and Guild
Management `OnEnable`, and the Achievement guild-update handler. The character
scan login hook only reset scan state; it did not queue producer scans.
The separately enabled, privacy-gated `guild-position` feature still captures
and discovers only live positions on its own login/roster lifecycle. Its domain
has `catchUp=false`; this is not persistent catch-up across feature domains.
POI retains only its current group-session resync, not an automatic Guild scan.

The current path is `PLAYER_LOGIN -> Sync.LoginPresence -> PRESENCE`. Presence
contains the resolved addon version, session ID, reply request and a schema-1
manifest with at most 64 metadata entries. It never contains character blocks,
equipment, raid, Mythic+, Delves, achievement records or other snapshots. The
current core manifest provider advertises only enabled, locally owned character
blocks. Optional domains can register a manifest provider without adding a
hard dependency to core. Unknown domains are held in a 256-entry bounded list
for up to the Presence TTL and considered if that module registers.

The receiver compares each entry against local domain metadata using that
domain's freshness rule. Character blocks use owner-aware freshness: an exact
direct owner match is current, but a direct owner can repair an indirect relay
copy even when its numeric version is lower. Missing or fresher eligible data
creates normal `QueueFetch` demand. Login does not call `RunCatchUp`; the legacy
entry point logs `LOGIN_CATCHUP_SUPPRESSED` and returns without discovery.
Passive healing remains available from newer offers, domain events and actual
feature use.

Outbound requests for the same domain, object, owner, version and revision are
collected for 0.75 seconds in the existing bounded Sync job queue (up to 64
recipients and four request IDs per recipient). One recipient gets a Whisper.
Multiple recipients may share one Guild payload only if every requester is
currently in the guild roster and the domain explicitly permits the audience,
every online member passes `canShare`, or the domain declares its data safe for
guild broadcast. If any privacy check fails, authorized requesters get targeted
Whispers. Export occurs only after at least one authorized request survives
revalidation. Owner/version/revision metadata is checked again before export,
and the payload preserves the original owner through relays.

Character Overview requests only the selected tab's declared blocks.
Achievements, content, POI and Guild Management discovery runs on the matching
page or feature being opened. No load-on-demand feature module must be present
for core Presence or Sync to operate.

The recurring 180-240 second Presence heartbeat was removed. Guild roster rows
provide online status; login Presence and reply-requested peer Presence provide
version detection, and the existing 300-second peer expiry remains. The
one-shot `RunPresenceHeartbeat` compatibility method does not schedule itself or
start discovery.

Structured logs record manifest receipt, same/current/newer decisions, merged
requests, recipient counts, Whisper/broadcast routing, privacy refusal, payload
suppression and the deliberate login catch-up suppression without logging
payload contents.

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

The OFFER sender is the current transport source; `metadata.owner` remains the
revision author and does not imply that the author holds the payload. POI
advertisements revalidate the exact stored revision and recipient scope before
they are sent. Personal POIs are never shared, and transient POIs require the
current matching group or raid session.

FETCH_RESULT is an additive protocol-v3 control envelope correlated by domain,
entity, request ID and source. NOT_FOUND, NOT_VISIBLE, STALE, INVALID and
UNAVAILABLE let a source decline a request without waiting for the fetch
timeout. The requester immediately exhausts that source and tries another
candidate. Outbound response jobs include the request ID in their dedup key so
a retry cannot inherit an earlier response's correlation ID. Timed-out sources
receive the configured bounded retries; exhausted source/revision pairs stay
suppressed in memory for ten minutes (up to 512 entries), unless a new source,
new revision or explicit user refresh appears.

The central planner does not create owner revisions. Character block payloads
must retain the original character GUID as owner. A relay can advance an
indirect cache while no direct copy from that owner is known. Once a block has
been received directly from its owner, a relay cannot replace it even with a
higher numeric version; a later direct owner copy can replace a relay cache
even if its version is lower. Locally owned blocks still reject non-identical
remote data. Identical same-revision payloads remain no-ops. Other domains use
their registered freshness rules; in particular, permission imports retain
their revision-chain validation.

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
over the HSC1 ceiling is declined with UNAVAILABLE before payload frames are
queued. Packet-level send/receive detail stays at DEBUG; Comms reports
aggregate completion and fragment progress to Sync.

The displayed queued Sync count is the number of catch-up/send jobs waiting in
the Sync queue. It excludes the active transfer and completed inbound payloads;
pending inbound payloads have their own diagnostic count. An active FETCH with
an armed timeout remains real active work.

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

For character blocks, source authority is evaluated before numeric freshness
when comparing the same owner. This lets the owner's direct copy repair an
indirect relay cache without changing the owner revision format. Login
discovery remains a metadata-only manifest followed by targeted requests; it
does not start a global catch-up or recurring Presence heartbeat.

## Retry and recovery

Each selected data job has at most three retries with bounded exponential
backoff. Fetch response timeout and transport/import failures release the
active slot, record a structured result and let the queue continue. A terminal
failure removes the active dedupe entry but retains the old cache. A later
event, manifest or on-demand discovery can offer the object again. The queue is
deliberately in-memory; metadata discovery reconstructs unfinished work after
reload.

## Presence and GuildLog

Presence is independent of the data transfer slot. Existing version semantics
remain in Sync: local version is authoritative, versionless Presence refreshes
peer liveness without erasing a known version, valid Presence refreshes peer
version freshness, and expired peers are removed after the existing timeout.
`DEV` and semantic release versions retain their existing validation. Login
Presence includes the bounded schema-1 revision manifest described above. The
Guild roster provides online status, so Sync registers no periodic Presence
heartbeat; version changes are learned from login Presence and direct replies.
Peer Presence data still expires after the existing 300-second TTL.

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
one-shot Presence refreshes, metadata request history, queued work, debounce
delays and maintenance tasks do not count. Fetch request IDs rotate on each attempt, and
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
