# Holy Storm POI

## Purpose and current implementation

`Holy_Storm_POI` manages deliberate, persistent map markers. A POI has a stable
identity, title, optional description, icon, canonical map coordinates, scope,
creator, provenance, revision history metadata, and optional expiration. The
module reuses the existing manager, map, and synchronization contracts. It does
not depend on `Holy_Storm_Positions`.

The module provides local and guild/group/raid CRUD, a POI editor and management
list, icon selection, Sync-v2 object transfer, map links, World Map pins, exact
coordinate conversion, and optional Minimap markers. Persistent POIs are loaded
at login without a World Map coordinate transform. The World Map provider is
installed on map show, and the shared Minimap driver runs only while enabled
markers exist.

## Scopes and visibility

The serialized target `PERSONAL` is the local scope. It is visible only on the
current client, has no guild permission requirement, and is never listed,
exported, or published by Sync-v2. `GUILD` is shared with the current guild and
is visible to guild members by default. Visibility is not permission-gated.

`GROUP` and `RAID` remain supported as temporary session scopes for the
existing group workflow. Their records are removed when the client leaves the
matching group or raid session. Local hide, category filters, target filters,
World Map display, and Minimap display are client-local settings.

## Data model

Each record has schema version 2 and stores canonical coordinates only:

| Field | Meaning |
| --- | --- |
| `poiID` | Stable generated identity; never derived from title or coordinates |
| `schemaVersion` | Record schema, currently `2` |
| `name`, `description` | User-authored text |
| `mapID`, `x`, `y` | Original map and normalized coordinates in the 0–1 range |
| `icon`, `category`, `color` | Stable icon/category keys and marker color |
| `target`, `scope` | Matching scope identifiers; `PERSONAL` means local |
| `creatorGuid`, `creatorAccountUUID`, `creatorName`, `createdAt` | Immutable origin identity |
| `modifiedBy`, `updatedAt` | Actor and time for the current revision |
| `revision`, `revisionID`, `previousRevisionID` | Monotonic object version and branch identity |
| `provenance` | Creation source (`MANUAL`, `CURRENT_PLAYER_POSITION`, or `GUILD_PLAYER_POSITION`) and bounded optional character metadata |
| `expiresAt` | Optional absolute expiration time |
| `status`, `deletedAt`, `deletedBy` | Active state or retained delete tombstone |
| `guildId` or `sessionId` | Scope ownership for guild or temporary group records |

An edit keeps the POI ID, creator, creation time, and provenance. It increments
the revision, points to the previous revision ID, and creates a fresh revision
ID. Scope is immutable for an existing record, so changing sharing scope cannot
leave an old shared copy behind. A future explicit conversion flow would need
to create a new scoped object through the normal permission checks.

## Persistence and migration

`POIStore` registers the version 2 global `poi-store` schema at `global.poi`.
Its version 1 to 2 DataManager migration adds per-record schema/scope fields,
revision IDs, provenance defaults, and safe defaults for legacy records. The
store owns its root only through `DataManager:GetOwnedRoot`; settings use the
version 1 profile schema `poi-settings` and DataManager transactions. Neither
feature file accesses SavedVariables directly.

## Permissions and actions

The module metadata is the source of truth for POI permissions. Guild leadership
and officers default to all guild create, edit, and delete permissions; guild
members default to none. Each permission explicitly declares all three default
groups. There is no `poi-view` permission. Local POI actions do not check a
permission. The service checks permissions again inside save, delete, and
remote-authority paths, in addition to hiding unavailable UI actions.

The guild IDs are `poi-create-guild`, `poi-edit-guild`, and
`poi-delete-guild`. Separate group and raid action permissions preserve the
temporary-scope workflow. enUS and deDE administration locales provide labels
for every registered POI permission.

## Sync-v2 authority and conflicts

Guild/group/raid records use the central `poi` Sync-v2 domain with
`freshness="revision-chain"`. Discovery sends compact per-object metadata;
payloads are fetched one POI at a time through the standard Sync-v2/HSC1 path.
Personal records are never published. The feature defines no transport,
fragmenter, or scheduler of its own.

Metadata must match the payload object ID, modifier/owner, revision, revision
ID, update time, target, and scope before import. Direct authors must match the
metadata owner. Guild relays must be current guild roster members. A relay
preserves the original creator, revision IDs, provenance, modifier, and payload
values; the local receipt fields are removed from exports. Sync-v2 does not
cryptographically sign domain payloads, so this validates consistency and
current roster/permission authority, but cannot prove a malicious guild client
did not forge another actor's identity.

Edits require the caller's expected revision. A stale editor is rejected. If
two officers independently edit revision 5 into different revision 6 records,
both have the same parent and are sibling revisions. The receiver logs the
conflict and chooses the lexically greater revision ID, which converges when
each sibling is offered. A tombstone always wins against an active record at
the same revision. Lower revisions are rejected. Once a local tombstone exists,
an active payload cannot restore that object, even if it claims a larger
revision.

Guild delete records are retained for 180 days, with a hard cap of 2,000
tombstones per guild; oldest records are pruned first if the cap is exceeded.
An offline peer returning after retention has elapsed may require manual
reconciliation because the delete record may no longer be available. This
bounded policy prevents an unlimited tombstone history.

## Creation, editing, and deletion

The POI management page offers manual creation and editing, an icon picker, a
current-player-position helper, details, local hiding, sharing, coordinate
copying, and permission-gated deletion. Saves use one service path regardless
of UI or external capability. Guild and personal scope are selected in the
normal editor; an external caller cannot silently request a guild save.

The stable `poi.create` capability accepts a source, map ID, normalized
coordinates, optional title/description/category/icon, and bounded character
metadata. It validates the request, forces the initial scope to `PERSONAL`, and
opens the ordinary editor without saving. The Positions action passes the
original map coordinate and `GUILD_PLAYER_POSITION` provenance with character
identity metadata. Positions remains fully usable if POI is unavailable; POI
does not depend on Positions.

## Icons and UI

The icon registry is a bounded list of stable IDs backed by Blizzard textures.
The picker displays the current selection and localized hover names. Invalid
new remote icon/category IDs are rejected before storage. Rendering falls back
to the default marker if an old saved icon is no longer registered.

The management list supports text search, active/own/synchronized/hidden views,
stable sorting, scope, creator, map name, creation time, and lifetime. Details
and map tooltips show title, description, category, scope, map, creator, created
and updated times, and expiration where present. The map context menu includes
details, map navigation, hide, edit, sharing, and authorized delete actions.
Confirmation callbacks go through the service again.

There is no POI slash command. Manual creation is available through the normal
POI management page.

## World Map and map hierarchy

The World Map uses Blizzard's `MapCanvasDataProviderMixin` and pooled
`AcquirePin` contract. Exact map conversion goes through the shared MapLinks
wrapper: direct coordinates for the same map, otherwise
`C_Map.GetWorldPosFromMapPos` followed by `C_Map.GetMapPosFromWorldPos`. POI
rendering additionally requires the viewed and source maps to share an
ancestor/descendant relationship. A missing transform, unrelated map,
unexpected returned map ID, invalid map ID, or invalid coordinate hides the
pin; no coordinates are guessed. Parent-map positions are computed at render
time and are not stored redundantly. Transform results are cached by POI
revision and source/target map IDs. The provider reacts to the current map and
never calls `SetMapID`; only an explicit POI "Show on Map" action navigates.

Pin hover handlers are supplied as `OnMouseEnter` and `OnMouseLeave` mixin
methods. The XML pin template must not install `OnEnter` or `OnLeave` frame
scripts: Retail `MapCanvasMixin:AcquirePin` asserts those scripts are nil
before connecting the mixin handlers. A violation can throw during the
provider's map-change refresh and stop pin acquisition. The provider
reconciles pins by POI ID, updates positions in place, and releases only
obsolete pins. Repeated refreshes and map changes do not accumulate providers
or active pins.

The existing POI diagnostics view reports the currently viewed map, visible
local and scoped POI counts, exact and transformed matches, unsupported map
transforms, invalid map IDs/coordinates, acquired and active pin counts,
provider registrations, last refresh reason, and last rendering failure.
These are bounded aggregate values; per-POI rows continue to show visibility
and pin state. The World Map and Minimap settings remain independent.

## Minimap and settings

Minimap display is independent of World Map display. The shared MapLinks updater
is active only when Minimap markers are enabled and POIs need display. Its
per-frame driver is detached while all map providers are inactive. It provides
a single validated player-map context per projection pass. Exact map
transforms are cached and projection is limited to once per second, with
unchanged signatures skipped. Pins use a reusable linear pool. MapLinks applies
map-world size, view radius, range rejection, Minimap rotation, and player
facing; POIs outside range are hidden instead of clamped to the edge. Missing
Retail API results degrade to no markers.

The `poi-settings` profile contains `worldMapEnabled`, `minimapEnabled`,
`worldMapSize`, `minimapSize`, `maxSynced`, local hidden IDs, and category/target
visibility maps. World Map and Minimap marker sizes are independent of one
another and of the Positions module.

## Expiration, events, tasks, and options

No expiration is forced. Personal and group/raid records are locally removed
when they expire. Expired guild records are hidden locally. A client with
current delete authority may publish a tombstone; other clients leave the
shared record intact for an authorized cleanup actor. Expired guild POIs are
excluded from discovery as active records.

Semantic events include `HS_POI_CREATED`, `HS_POI_UPDATED`, `HS_POI_DELETED`,
`HS_POI_SYNCED`, and compact `HS_POI_LIST_CHANGED` notifications. UI listeners
react to events instead of polling persistence. TaskManager owns startup
discovery, group-context reconciliation, expiration cleanup, map refresh, and
message hiding. Stored records are read at initialization, but coordinate
transforms are deferred until the World Map is shown or enabled Minimap markers
need projection. Normal visibility and marker options stay in the regular POI
Options view; no separate administration UI is required.

## Retail APIs and known limits

The implementation uses the same audited Retail APIs and helper as Positions:
`C_Map.GetMapInfo`, `GetBestMapForUnit`, `GetPlayerMapPosition`,
`GetWorldPosFromMapPos`, `GetMapPosFromWorldPos`, `GetMapWorldSize`,
`C_Minimap.GetViewRadius`, `C_Minimap.IsRotateMinimapIgnored`, and the
MapCanvas provider/pin pool. The current-player-position button uses the
MapLinks validated player-position helper. Blizzard may return no map,
coordinate, conversion, or Minimap context while loading or on unsupported
maps; the POI is not drawn in those cases. Automated fakes cannot verify the
actual Retail maps, Minimap art/rotation, or two-client guild authority.

## Offline test strategy

`tools/test_poi.lua` covers root and settings migration, valid/invalid data,
local permission-free CRUD, guild permissions at the action layer, stable IDs,
revision increments, same-revision forks, immutable provenance, scope
isolation, no local publication, metadata-first discovery, object limits,
relay authority, stale rejection, tombstones, retention pruning, expiration,
capability validation/default scope, icon/category rejection, map conversion,
and MapLinks integration. `tools/test_poi_map.lua` checks MapCanvas ownership,
the pin script assertion contract, map hierarchy and no-navigation rule.
`tools/test_poi_map_runtime.lua` checks exact/parent/unrelated/unsupported map
rendering, invalid map/coordinate rejection, map-change callbacks, idempotent
pin/provider lifecycle, Minimap throttling and independence, diagnostics, and
provider teardown.
The complete offline suite also runs Positions, Sync-v2, TaskManager/workflow,
permission, locale-parity, persistence-boundary, and Lua syntax checks.

## Retail test plan

1. **Client A:** create a local POI, confirm Client B never receives it; create a
   guild POI, choose icons/scopes, edit, and delete it with an authorized role.
2. **Client B:** receive the guild POI, verify visibility as a member, verify
   edit/delete controls follow permissions, reload, and confirm persistence.
3. **Client C:** join with an older active revision and confirm a retained delete
   tombstone prevents resurrection.
4. Check exact zone, parent map, continent, unsupported map, World Map on/off,
   Minimap on/off, separate marker sizes, range hiding, and Minimap rotation.
5. Right-click a guild player position, choose “Position as POI”, and confirm
   the normal editor opens with the source character and personal scope; save
   only after explicitly choosing the final values.
6. Test permanent, expired local, expired guild with/without delete authority,
   simultaneous revision 5 edits, and the tombstone retention reconciliation
   behavior.
7. Observe Sync activity with normal character synchronization and a large
   guild POI set; discovery should remain metadata-first and payloads should be
   individual POI objects without broadcast bursts.
