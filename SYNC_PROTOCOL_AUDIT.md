# Sync Wire Protocol Audit

Audit baseline: `c7e7cee467f37fd6bfffeb77fec88bb8340306be`.

## Decision

Retain HSC1 framing and receive reassembly. There is no double fragmentation in the current path: each HSC1 frame is capped at 255 bytes, the limit AceComm uses to select between a single addon message and its multipart path. Replacing HSC1 with one large AceComm logical message could reduce queue calls, but would discard HSC1's bounded transfer size, fragment timeout and deployed-client wire compatibility. The embedded AceComm receiver does not provide equivalent limits or expiry. This is not a safe simplification without a separately designed capability rollout and a bounded AceComm receive layer.

HSC1 is treated as deployed protocol. The repository's historical release notes document chunked, limited Sync in shipped versions, and Holy Storm has an established add-on prefix and released upgrade path. There is no reliable all-peers capability negotiation today. Sync's `protocol=3` is the serialized semantic envelope version; it is distinct from the HSC1 transport frame marker. Presence currently advertises the add-on version, not a transport protocol capability. No HSC2 capability or dual-send was introduced.

## Current path and limits

```text
domain payload
  -> deterministic Holy Storm Serializer (depth 12, 10,000 entries,
     65,535-byte string limit, 262,144-byte serialized limit)
  -> Sync envelope (protocol=3, kind/domain/data/sentAt/sender)
  -> HSC1 frames (220 payload bytes each, max 300 queued frames)
  -> SyncTransport -> AceCommQueue -> AceComm -> ChatThrottleLib
  -> C_ChatInfo.SendAddonMessage (255-byte message ceiling)
```

The effective outbound serialized-payload ceiling is 66,000 bytes (`220 * 300`), even though Serializer permits 262,144 bytes. Each frame also contains the HSC1 marker, a timestamp/serial transmission ID, fragment index/count, and separators. Comms rejects any complete frame over 255 bytes before queueing it. Thus each HSC1 frame is one AceComm logical send and one WoW addon message. AceComm does not add its multipart marker bytes to these frames.

Receive runs from `CHAT_MSG_ADDON` into `Comms:OnMessage`, keyed by sender, channel and HSC1 transmission ID. Parts may arrive out of order; a duplicate index replaces the prior part, but there is no completed-transfer replay cache. A changed total discards that transfer. The hardened receiver accepts at most 300 parts of at most 220 bytes (66,000 assembled bytes), 64 incomplete transfers globally and 16 per sender. The limits mirror the existing sender's 300-frame/220-byte ceiling and serializer limit. Since current senders cannot produce a larger valid transfer, the lower bound does not reduce compatibility with the known HSC1 producer. Before accepting a new transfer, expired transfers are removed; if a cap remains full, the oldest incomplete transfer in the relevant scope is evicted, with a stable key tie-break. These operations only discard volatile transport state.

Structural checks (marker, decimal indexes, valid generated ID shape, sender, accepted Retail channel, 255-byte frame ceiling, fragment size, count and index bounds) run before state allocation. Each transfer tracks accepted part and byte counts. A replacement adjusts the byte total by `newLength - oldLength`; a would-be overflow discards that transfer. Completion requires the declared count of unique parts and an in-range byte total. State and sender/global accounting are removed before concatenation and event delivery, followed by a final size check. Partial state expires after 30 seconds of inactivity through the existing one-shot timer and TaskManager cleanup task. `SyncManager:Receive` then deserializes and validates the semantic envelope, resolves sender identity through GuildStore, and applies the existing domain authority, freshness, authorization, and import path.

The maximum fragment-held payload bytes are bounded by `64 * 66,000 = 4,224,000` bytes, plus Lua table overhead. This is a hard upper bound under the configured transfer and fragment limits, not a target memory footprint. Diagnostics expose active and peak incomplete transfers, received fragments, reject/oversize counts, cap evictions, expiry, duplicates, and completions. Invalid traffic is counted and warning logs are rate-limited per rejection category; payload contents are never logged.

Outbound retry has two layers with separate scopes. AceCommQueue retries client-refused sends (three retries under the embedded defaults), then reports a terminal callback. SyncManager retries a failed envelope enqueue through TaskManager (up to the task's existing retry limit). There is no end-to-end delivery acknowledgement. A successful queue callback indicates ChatThrottleLib finished submitting the message's physical chunk(s), not that a peer accepted or persisted its contents.

## Embedded AceComm-3.0 (minor 14)

Source: `LIVE/Holy_Storm/Libs/AceComm-3.0/AceComm-3.0.lua`.

- `SendCommMessage` uses a 255-byte logical-message threshold. Larger strings are split into 254-byte data pieces, with `\001` FIRST, `\002` NEXT and `\003` LAST markers. A leading control byte is escaped with `\004` when possible.
- On receive, AceComm spools by prefix, distribution and normalized sender; it appends pieces in arrival order and fires the registered callback only after LAST. Orphan NEXT/LAST are ignored. A new FIRST overwrites an existing same-key spool.
- AceComm does not attach a per-message ID, sequence number, checksum, size limit, or expiry to this spool. The source itself has a TODO about expiring old data. It relies on pieces arriving in order and does not distinguish overlapping messages on the same stream.
- It delegates physical transmission to ChatThrottleLib. The embedded CTL source enforces the 255-byte addon-message size ceiling and retries its documented throttle refusal path.
- Its “unlimited length” comment means the send API does not define an application maximum; it is not a suitable bound for SavedVariables-derived Sync data or hostile multipart input.

## Embedded AceCommQueue-1.0 (minor 7)

Source: `LIVE/Holy_Storm/Libs/AceCommQueue-1.0/AceCommQueue-1.0.lua`.

- It queues complete `SendCommMessage` calls per `(prefix, distribution, target)`, not individual AceComm chunks and not a new wire frame format.
- It lets only one AceComm logical send per queue key be in flight; it starts the next message after the prior call's terminal callback. This prevents AceComm multipart messages on one key from interleaving through ChatThrottleLib.
- Queued calls are selected by ALERT, NORMAL, then BULK priority. Refused sends are retried with exponential delays (embedded defaults: three retries, one-second base); a 300-second no-progress stall detector can release a stuck slot.
- Its terminal callback covers local send completion or a suppressed/rejected/refused outcome. It does not confirm receiver reassembly, deserialization, authority, or persistence.
- For current HSC1 traffic every queued call is already a single AceComm chunk. Queue operations therefore equal HSC1 fragments. ACQ's no-interleaving guarantee matters for any AceComm logical message over 255 bytes, but does not remove HSC1's own transfer IDs, fragment assembly, or timeout.

## Responsibility classification

| HSC1 responsibility | Classification | Reason |
| --- | --- | --- |
| `HSC1` marker | Backward compatibility | Existing clients expect it; AceComm does not replace the Holy Storm wire contract. |
| HSC1 transport version | Backward compatibility | Separates frame parsing from semantic Sync `protocol=3`; no safe peer capability negotiation exists. |
| Transmission ID | Required protocol feature | Associates fragments and diagnostics with one application transfer. |
| Fragment index and count | Required protocol feature | Supports out-of-order delivery and completion detection. |
| 220-byte payload piece | Required transport sizing | Keeps the full HSC1 frame below the WoW/AceComm 255-byte ceiling. |
| 300 outbound-frame limit | Required safety bound | Caps one outbound serialized Sync payload at 66,000 bytes and queue work. |
| Manual receive assembly | Required for HSC1 | AceComm sees each HSC1 frame as a complete single-part message; it cannot assemble HSC1's inner fragments. |
| 30-second fragment expiry | Required recovery | AceComm multipart spool has no expiry; HSC expiry bounds stale partial state. |
| Duplicate-fragment replacement | Required protocol behavior | Retransmitted indexes replace earlier copies while awaiting the other parts; completed-transfer replay is not deduplicated. |
| Completion detection | Required protocol behavior | Emits a logical Sync payload only once all declared pieces are present. |
| Malformed-fragment rejection | Required safety | Invalid counts/indexes/protocols must not reach Serializer or Sync. |
| Sender/channel validation | Required domain boundary | Transport filters self traffic; Sync resolves sender GUID and applies domain authority. There is no general ingress channel allowlist. |
| Payload-size checks | Required safety | Serializer and Comms caps limit outbound/inbound logical data; AceComm has no logical receive cap. |

## Synthetic framing comparison

Assumptions: decimal clock ID of ten digits, short serial, HSC1 chunk size 220, and a minimal new envelope of five bytes. Figures are byte/chunk arithmetic from the embedded sources, not latency measurements. Exact HSC header bytes vary with clock, serial, part and total digit counts.

| Logical payload | Current HSC1 frames / queue calls | Current AceComm physical chunks | Hypothetical one-message AceComm chunks | Approx. HSC framing overhead |
| ---: | ---: | ---: | ---: | ---: |
| 100 B | 1 | 1 | 1 | 27 B |
| 1 KB | 5 | 5 | 5 | ~135 B |
| 10 KB | 46 | 46 | 40 | ~1.3 KB |
| 50 KB | 228 | 228 | 197 | ~7.0 KB |

There is no duplicated AceComm fragmentation today: one HSC1 piece fits within a single 255-byte AceComm message. A hypothetical no-HSC design would reduce queue operations, but its physical chunk count is similar and would need to reintroduce bounded, expiring receive assembly to match current safety. No runtime latency or reliability claim is made from these counts.

## Retail constraints and open runtime check

The embedded Retail-targeted source uses `C_ChatInfo.RegisterAddonMessagePrefix`, the `CHAT_MSG_ADDON` event and a 255-byte message ceiling; the project TOC declares interface 120100. Current Retail API references likewise list a 255-character message maximum, a 16-character prefix maximum and per-prefix throttling. The current API also reports outgoing restriction errors such as `AddOnMessageLockdown` and `TargetOffline`; AceCommQueue retries a terminal client refusal three times but does not query a restriction-state API or guarantee eventual delivery. Channel routing and connected-realm name normalization remain in the existing Comms/GuildStore path. The library source establishes software behavior, but cannot establish live delivery/order under current Retail channel and instance restrictions. Verify those in the matrix below before changing the wire stack.

## Focused Retail matrix

Use two current Retail clients in one guild. For every row inspect Comms diagnostics (`pendingPackets`, `incomingTransmissions`, `incomingFragments`, `transport.queued`, `transport.sent`, `transport.failures`, `transport.lastFailure`, `transport.queuedAlert/Normal/Bulk`), and structured logs (`direction`, `from`, `to`, `channel`, `domain`, `objectId`, `messageKind`, `transmissionId`, `packetPart`, `packetTotal`, `bytes`, `requestId`, `selectedSource`, `originalOwner`, `relay`, `retry`, `reason`). After payload cases inspect the domain SavedVariables' owner/version/revision/provenance fields and Permission revision chain.

1. Small owner-to-peer payload over guild and whisper.
2. Logical payload just above 255 bytes to prove the existing HSC frames remain single AceComm sends; inspect wire frames and queue counts.
3. Realistic Equipment payload; compare expected block metadata and imported data.
4. Mythic+ and Raid payloads using targeted fetch; verify the selected source and one-peer whisper.
5. Several simultaneous Sync transfers at different Sync priorities; verify HSC fragment reassembly and ACQ ordering.
6. Owner and receiver logout, then reconnect; verify incomplete fragments expire and no invalid/empty block is committed.
7. `/reload` during partial transfer; verify in-memory fragments are discarded and a later discovery/fetch repairs state.
8. Legacy client peer; verify HSC1 send/receive compatibility.
9. Sequential Permission update and stale client recovery; verify revision ID/predecessor, changedBy/changedAt, and leader trust anchor remain valid.
10. Repeat guild/whisper cases across connected realms and in the Retail instance states relevant to the current patch; record API restriction errors and transport failure callbacks.

No live Retail result is claimed by this audit.
