# Guild Management architecture

`Holy_Storm_Guild` owns the Guild Management domain. The existing `GuildRoster` module remains responsible for Blizzard roster, public-note, officer-note, and rank interactions. The separate `GuildManagement` module owns structured Holy Storm notes and absences.

## Parent and feature registration

`HolyStorm.GuildManagement:RegisterFeature(definition)` registers ordered child features. A child supplies a stable ID and lazy `build` callback; optional refresh and presentation metadata stay feature-owned. The single `guildManagement` UI view hosts the registered children in a shared tab group. Only `notes` and `absences` exist today. Activity, points, and recommendations can register later without adding feature knowledge to Core. Future recommendations may prepare proposals, but consequential guild changes must always require explicit confirmation from an authorized user.

## Persistence and identity

All three schema-version-1 roots use `DataManager`:

- `guild-private-notes`: account-wide local notes, partitioned by the local Account UUID.
- `guild-shared-notes`: guild-partitioned synchronized notes.
- `guild-absences`: guild-partitioned synchronized absences.

Notes have a stable note ID, subject Character UUID and optional known Account UUID, immutable original author, last editor, category, content, scope/visibility, created/modified/expiration timestamps, revision, and status. Private notes never enter a Sync domain. Shared deletion writes a content-minimized tombstone.

Absences have a stable absence ID, immutable subject Account/Character ownership and origin Character UUID, creator/current editor, start/end, optional title/reason, timestamps, revision, and status. They are account-oriented when the Account-to-Characters relationship is known; no future cross-account `Player` layer is introduced. Ended entries remain history. Cancellation writes a tombstone.

## Synchronization and privacy

The domains are `guildNotes` and `guildAbsences`. Both use central metadata discovery, targeted fetch, `PlayerData:CompareMetadata`, validation/authorization, and tombstones. A relay preserves origin metadata and is recorded separately as `receivedFrom`.

`guildNotes` uses the SyncManager's generic outbound `canShare` and `getRecipients` hooks. Visibility-filtered announcements and discovery offers are whispered only to recipients authorized by PermissionEngine, and `FETCH` is denied before export for unauthorized requesters. Public, raid-leadership, officer, and guild-leadership scopes map to separate permissions; category is independent. Private-note IDs, metadata, and content are absent from Sync.

Shared-note visibility is immutable after creation. This prevents a client that was authorized for an older revision from retaining a readable stale copy after the note is narrowed to a different audience. Content, category, subject, expiration, and editor metadata remain editable under the normal revision/permission checks.

This is access control, not cryptographic confidentiality. WoW addon messages cannot defend against a modified authorized client that records or republishes received content, nor can a client prove historical rank membership cryptographically.

## Permissions and rules

Leadership retains dynamic full access through the protected PermissionEngine model; feature code contains no leadership bypass. Defaults are:

- Officers and guild members: `guild-notes-view`, `guild-absences-view`, `guild-absences-manage-own`.
- Officers only: `guild-notes-view-raid-leadership`, `guild-notes-view-officers`, `guild-notes-create`, `guild-notes-edit-own`, `guild-notes-edit-any`, `guild-notes-delete-own`, `guild-notes-delete-any`, `guild-notes-manage-categories`, `guild-absences-manage-any`.
- No static assignment: `guild-notes-view-leadership`; Leadership receives it through dynamic full access.

The module owns `guild.absence.current`, `guild.absence.start`, and `guild.absence.end`. Missing identity/provider/permission data remains `UNKNOWN`; private notes and note content/counts are deliberately not Rule fields.

## UI, tasks, and optional Calendar

The parent uses UIManager, `UILayout`, the shared tab group, shared Table/EditBox/buttons, empty states, resize, and table selection. Child views are materialized only on first selection. Note expiration schedules one TaskManager wake-up at the nearest expiry and only refreshes presentation; the persisted record remains, preventing stale resurrection. There is no recurring poll or keepalive broadcast.

Character actions are contributed through the reusable CharacterActions provider registry and consumed by the Guild Roster member surface. Private-note actions remain available without guild-note permissions; unavailable shared/absence actions are disabled. Cancelled absences remain tombstones and appear alongside naturally ended entries in History.

Calendar currently has no external event-provider API. Absences therefore remain independent; no duplicate Calendar records or Calendar coupling were added. A future integration should consume an explicit read-only provider contract rather than copy records into Calendar storage.
