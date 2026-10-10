# Snapshot Refresh Policy

## Contract

Holy Storm uses three rules for persisted character snapshots:

- **CACHE-FIRST:** render the last accepted stored block immediately. A refresh never clears it.
- **IDLE BY DEFAULT:** login, addon readiness, module loading, missing data, and elapsed time alone never start a snapshot producer.
- **EVENT-DRIVEN BY DESIGN:** a relevant Blizzard change event or an explicit user action requests the normal serialized producer workflow.

The policy covers Equipment, Mythic+, Raid, Delves, and Stats. It does not change transient presence, live position sharing, calendar, achievement, relationship, or user-authored POI behavior.

## Login and startup

`PLAYER_LOGIN` marks the player logged in, starts the existing login presence session, and clears stale in-memory CharacterScanManager queue state. `PLAYER_ENTERING_WORLD` marks the player ready and clears loading/zoning state. Core, event, identity, addon, and stored-data initialization still happen as required. Neither event requests a character snapshot.

The five registered snapshot blocks are declared by their feature TOCs. Some producers are load-on-demand and others are registered with the core character feature; provider registration never inspects a stored block to decide to scan. A missing, old, unsupported, or incomplete snapshot is displayed as such and remains unchanged until a real producer event or explicit request.

| Startup phase | Work | Snapshot scan? |
| --- | --- | --- |
| Essential | Core bootstrap, persistence/store setup, identity and module/capability registration, event registration | No |
| Lightweight | Guild/presence prerequisites and small metadata updates | No |
| Background | Bounded Sync v2 discovery/catch-up and maintenance | No |
| On demand or event | Snapshot collection, large optional views, explicit user refresh | Only for a relevant event or explicit action |

## Producer event and freshness matrix

| Block | Snapshot version | Automatic refresh signals | Login/load protection | Freshness rule |
| --- | --- | --- | --- | --- |
| Equipment | v4 | `PLAYER_EQUIPMENT_CHANGED`; player `UNIT_INVENTORY_CHANGED`; `SOCKET_INFO_UPDATE` | Ignores these event callbacks before `playerReady`, including a load-on-event initialization burst. A late module load does not scan unless the triggering equipment event is already in the ready state. | Event-driven. There is no wall-clock expiry. The one-second Equipment workflow retains its two-scan stability check, validation, and atomic PlayerData commit. |
| Mythic+ | v5 | `CHALLENGE_MODE_COMPLETED`, `MYTHIC_PLUS_NEW_WEEKLY_RECORD`, `WEEKLY_REWARDS_UPDATE` | Completion and score events are ignored before `playerReady`. If enabled before ready, the first weekly reward event is suppressed even when Blizzard delivers it just after readiness; a module loaded after readiness accepts its first weekly event. `CHALLENGE_MODE_MAPS_UPDATE` is not a scan trigger. | Stored season ID and weekly reset identity are compared with current Retail context. Old rating remains visible as stale. No time-to-live scan. |
| Raid | v3 | `ENCOUNTER_END` with success while inside a Raid; `UPDATE_INSTANCE_INFO` while inside a Raid | No module-enable/bootstrap scan. Events outside a Raid and unsuccessful encounters are ignored. `UPDATE_INSTANCE_INFO` caused by `RequestRaidInfo` folds into an active scan rather than recursively requesting more raid info. | Weekly identity/reset applies only to lockouts. Lifetime/best records remain usable when only the weekly identity changes. No time-to-live scan. |
| Delves | v3 | `WEEKLY_REWARDS_UPDATE` | If enabled before ready, the first weekly reward event is suppressed even when delivered just after readiness; a module loaded after readiness accepts its first weekly event. Account curio and live party/run events do not trigger the persisted World Vault snapshot. | Stored Delves season number and weekly reset identity. Old weekly data stays stored and is labeled stale; no time-to-live scan. |
| Stats | v2 | `PLAYER_EQUIPMENT_CHANGED`, player `PLAYER_SPECIALIZATION_CHANGED`, `TRAIT_CONFIG_UPDATED`, `PLAYER_TALENT_UPDATE`, `PLAYER_LEVEL_UP` | No enable/login baseline read or entering-world scan. Non-level triggers before `playerReady` are ignored. Baseline collection is delayed/coalesced after the relevant durable-change event. | Persistent baseline is event-driven; no age expiry. Temporary aura/buff values are a local overlay only and update only while the local Stats tab is visible. |

These are the events the current implementation consumes. Events are gated by payload/context where relevant; their names alone do not authorize unrelated scans. Existing API-specific retries remain bounded and recollect fresh data. No polling loop is used to wait for producer data.

### Other persistent feature data

The optional Professions module stores a separate `professions` block. Its TOC loads it on `TRADE_SKILL_SHOW`; it refreshes after the user opens the profession UI or after `SKILL_LINES_CHANGED`. It has no login producer trigger and is not a declared snapshot block in `/hs scan all`. Profile values are user-authored; identity and presence metadata use core observation/write paths and are outside the five producer contract.

## Shared status and stored values

`CharacterUI:GetDataStatus(characterUUID, block, scope)` is the shared status authority for the Dashboard and Character Overview. It reads the stored CharacterStore block and metadata, applies expected snapshot/schema versions, consults local transient CharacterScanManager state only for the local player, and evaluates domain-specific current context. It does not read producer APIs for a remote character. Dashboard summary passes its already-read block/meta pair into this function to avoid repeat store reads/deep copies.

| Status | Meaning | Display and action |
| --- | --- | --- |
| `MISSING` | No stored accepted block exists. | Show the existing unknown marker (`-`) and a localized scan prompt. A click requests only the matching producer. |
| `CURRENT` | Stored block is supported and no domain freshness mismatch is known. | Keep the existing value and presentation. |
| `STALE` | Stored block is valid, but season/weekly identity no longer matches current context. | Keep showing the stored value with a rescan prompt. No scan occurs until an event or user action. |
| `DIRTY` | A relevant event or manual request is queued, before its workflow begins. | Preserve stored values and show a pending/refresh indication. The serialized manager advances the request. |
| `REFRESHING` | The normal provider workflow is active. | Preserve stored values and show an updating indication. |
| `ERROR` | Provider could not start or the workflow failed/cancelled. | Preserve the last valid stored value; offer a targeted retry. With no prior value, keep the unknown marker. |
| `UNSUPPORTED` | Stored schema/version cannot be consumed by the current UI contract. | Show the no-current-data prompt and offer a targeted scan for the local character. |

Runtime state is memory-only. It records state, reason, changed time, last attempt, last successful snapshot time, and last error where applicable; it does not grow SavedVariables. Status changes emit `HS_CHARACTER_SNAPSHOT_STATUS_CHANGED` so visible views update without polling. No global age TTL is used for these blocks.

## Manual refresh and sync

`/hs scan <block>`, `/hs scan all`, and the dashboard/Character Overview actions request the registered provider through CharacterScanManager. The manager serializes work, merges same-block requests, and gives explicit manual requests interactive priority (15) over ordinary producer work (30). The dashboard has no collection/commit path of its own. A card action targets its own block; it never turns a missing/stale metric into scan-all.

For the local character, snapshot prompts start that block's provider. For a remote character, the Overview uses the existing CharacterStore/Sync request path instead of offering a producer this client cannot run. A remote import refreshes the view through its block update event; remote producer state is not conflated with local runtime state.

PlayerData validates and commits only accepted snapshots. A changed local owned-block commit emits the established owned-update event, and Sync publishes from it. Login Presence runs after a 1.5-second delay in startup phase 4 and carries only version/session metadata plus the bounded revision manifest. Login does not start a global catch-up, and Sync does not schedule a recurring global Presence heartbeat. Missing eligible objects are fetched through the existing targeted queue, which merges duplicate jobs and distinguishes interactive from maintenance priority. This policy does not redesign that protocol.

Snapshot validation normally computes a content fingerprint only when its
commit consumer uses that value. Mythic+, Delves, and Stats commit through
PlayerData's own semantic equality check, so their workflows skip the
otherwise redundant full fingerprint serialization. Unchanged blocks still do
not get a new owner revision or trigger Sync.

## UI visibility and idle work

Dashboard and Character Overview read stored blocks first. Opening either view, selecting a tab, hovering a card, and rebuilding visible layout do not request a producer scan. Hidden dashboards and tabs are marked dirty by relevant events and rebuilt when shown/selected. Visible Character Overview refreshes are coalesced by a one-shot 50 ms timer. The header spinner rotates only while a sync activity is shown.

The audited timer/update work is scoped as follows:

| Work | Classification | Idle behavior |
| --- | --- | --- |
| TaskManager wake timer | Event/task-driven | `Wake` returns immediately when no task is queued or running; one-shot timer exists only for queued work. Coalesced wake diagnostics summarize the active burst. |
| Snapshot workflows and Stats debounce | Event-driven | One-shot workflow/debounce tasks only after a relevant event or user request; no repeating producer timer. |
| Sync login Presence and discovery | Metadata-only / demand-driven | One login Presence carries a bounded revision manifest. There is no global login catch-up or recurring Presence heartbeat; missing objects are fetched on demand. |
| Positions movement sample | Live event-driven exception | One-second sampler runs only while sharing and movement are active; it stops on `PLAYER_STOPPED_MOVING`. Login capture/reconciliation is necessary live sharing behavior. |
| Positions roster cleanup | Background maintenance exception | Ten-second recurring roster reconciliation exists while the Positions service is active and is cancelled on disable; it is not a character snapshot scan. |
| POI startup | Background maintenance | Loads/reconciles persistent POIs, expires/prunes entries, and may discover synchronized POIs; it does not full-refresh snapshots or transform maps at login. The World Map provider installs on map show. The shared Minimap updater runs only while enabled markers exist. |
| MapLinks Minimap driver | UI-visible-only | Its shared OnUpdate is installed only while a POI or Positions provider has enabled, visible marker work; it is removed when the last provider goes inactive. With no markers or Minimap display disabled, no periodic map projection runs. |
| World Map providers | UI-visible-only | POI and Positions providers install on World Map show. Data changes update an installed provider only while the map is visible; hidden map events update stored/render model state without coordinate transforms. |
| Dashboard / Character Overview | UI-visible-only | No periodic full rebuild. Event changes mark hidden views dirty. Spinner `OnUpdate` work is conditional on a visible spinner. |
| LibGuildRoster and communications libraries | Background / transport-specific | Roster retry/maintenance and queued communication work are scoped to their existing contracts; they are not snapshot polling. |

This policy does not claim a specific CPU percentage. Retail CPU measurement and event ordering still require an in-client run.

## Retail acceptance plan

1. `/reload`, then wait 30 seconds without interacting. Confirm there are no Equipment, Mythic+, Raid, Delves, or Stats producer workflows, no scan-all, no script errors, and no repeated producer tasks. Observe CPU in the client without treating a target percentage as an offline assertion.
2. Open the Dashboard and Character Overview. Confirm cached values appear immediately and opening/selecting tabs queues no producer scan.
3. With a missing block, confirm the unknown marker and localized prompt; click it and confirm only that block's workflow starts.
4. With stale season/weekly data, confirm its prior value remains visible; click the prompt and confirm only the matching producer starts.
5. Change equipment, complete a keystone, make a relevant raid/lockout change, update weekly rewards, and change specialization/talents. Confirm relevant automatic refresh still completes and commits once.
6. Leave the UI closed while playing. Confirm no UI render loop, producer poller, script timeout, or BugSack error appears; separately verify expected Presence, bounded Sync, and active Positions behavior.
