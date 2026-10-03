# Holy Storm Positions

## Purpose

`Holy_Storm_Positions` shows the latest known position of online guild members
who use Holy Storm. It adds pins to the Blizzard World Map and, when enabled,
the Minimap. It is a live convenience feature, not a route recorder or general
tracking service.

The feature uses only the map and movement information exposed by the Retail
client. If an API cannot produce a position or exact map conversion, the marker
is omitted.

## Module contract and dependencies

- Internal module ID: `positions`; display name: **Guild positions**.
- Module type/category: feature.
- The module registers the `positions` page and Options tab through the existing
  UI extension and Options systems.
- Required add-ons: `Holy_Storm`, `Holy_Storm_UI`, and Blizzard's
  `Blizzard_MapCanvas`. Sync-v2 is a declared Holy Storm dependency.
- POI and Character Actions are optional integrations. There is no hard POI
  add-on dependency.
- Ordinary position viewing and sharing do not define guild permissions.
  Administrative module policy can disable the feature for the guild.

## Settings and privacy

Settings are registered as the version 1 `positions` profile area through the
DataManager. The settings are local configuration; received coordinates are
never written to SavedVariables or CharacterStore.

New profiles default to sharing enabled, guild display enabled, World Map
enabled, Minimap disabled, and current-map-only disabled. World Map and Minimap
sizes are separate settings. Marker style is either class icon/color or one
unified guild icon.

The sharing toggle is local to the player. Another guild member cannot change
it. Turning sharing off drops pending local coordinates and clears the local
diagnostic position. If a position had already been shared, the module queues
one coordinate-free withdrawal control through Sync-v2 so peers remove that
marker. The withdrawal contains no map or coordinate fields. It is not a new
position. Further position exports are suppressed while sharing is off. Old
profile values explicitly set to `share=false` remain false to preserve an
existing opt-out; profiles without that value receive the enabled default.

## Ephemeral data model

One in-memory value is retained per character GUID. A normal update contains
only:

```text
characterUUID, guildId, mapID, x, y, timestamp, sequence, moving
```

The schema does not include equipment, raid/Mythic+ snapshots, tooltip text,
AFK/DND duplication, or twink lists. Local and received state are replaced in
place as newer updates arrive. There is no coordinate history, route, or
position persistence.

## Sync-v2 behavior and queue bounds

The `guild-position` Sync-v2 domain is `live=true`, `catchUp=false`, and
priority `110`. It uses the existing Sync-v2 and Comms transport; the module
does not open an AceComm channel or transport of its own. Priority 110 maps to
the existing BULK transport class, below control and interactive data.

TaskManager merges pending publishes by domain and character ID. Sync-v2 looks
up the current metadata/export when the live task runs, so it sends the newest
state. Sync-v2 also replaces a queued incoming LIVE value for the same live
domain/object with the higher version. An already-running small transport is
allowed to finish; old positions do not form a following history queue.

Initial position discovery is explicitly requested after addon readiness. It
does not enable general login catch-up for the live domain. Position payloads
do not advance durable player-data catch-up watermarks.

## Movement, capture, and send cadence

The module listens for `PLAYER_STARTED_MOVING` and `PLAYER_STOPPED_MOVING`.
While moving, one central TaskManager recurring job samples no faster than
once per second. `GetUnitSpeed("player")` selects an automatic maximum send
interval: under 4 yards/second uses 8 seconds, under 10 uses 5 seconds, and
10 or more uses 3 seconds. A position must also move by a small normalized
coordinate threshold before an update is queued.

If speed is unavailable or errors, movement events remain the gate and the
fallback interval is 5 seconds. If no speed value is available during a sample,
the state is treated as stationary. Stationary players receive no recurring
coordinate updates. Start/stop state changes can emit an update, and a stop
captures the final position. Zone/map change events request an immediate sample
without waiting for the movement interval.

## Freshness and Presence

Roster presence is authoritative for marker eligibility. A member is removed as
soon as the guild roster says they are offline or they no longer belong to the
current guild.

A moving position older than 90 seconds is stale and removed. A stationary
position remains eligible while its guild roster entry remains online; lack of
movement updates alone does not make it disappear. This balances the deliberate
no-heartbeat stationary policy with movement freshness. The tooltip can still
show that the stationary coordinate is old.

## Map hierarchy and coordinate conversion

Map relation checks walk `C_Map.GetMapInfo(mapID).parentMapID` in both
directions, with a visited set and a 100-level safety limit. The optional
current-map-only setting accepts the viewed map and related ancestor/descendant
maps. It does not compare IDs as a substitute for hierarchy.

For a different map, conversion is:

1. `C_Map.GetWorldPosFromMapPos(sourceMapID, CreateVector2D(x, y))`.
2. `C_Map.GetMapPosFromWorldPos(continentID, worldPosition, targetMapID)`.
3. Verify the returned map ID exactly equals the requested target and validate
   its normalized coordinates.

No zone-name lookup, guessed offset, hand-built continent table, or nearest-map
fallback is used. If either API returns nothing, errors, produces invalid
coordinates, or returns another map ID, no pin is placed.

## World Map

The module attaches one `MapCanvasDataProviderMixin` provider to
`WorldMapFrame`. Pins are acquired through `MapCanvasMixin:AcquirePin` and
released through Blizzard's provider/pin-pool lifecycle. A changed character
updates only that pin; an opened/viewed map change is handled by the Blizzard
MapCanvas refresh contract. Disabling World Map markers removes the provider's
pins. Module disable removes the provider and unregisters its events.

## Minimap

Minimap display is independent from World Map display. The current player's
map and position come from `C_Map.GetBestMapForUnit("player")` and
`C_Map.GetPlayerMapPosition(mapID, "player")`. The remote position is first
converted to that exact map. Its relative position is projected using
`C_Map.GetMapWorldSize` and `C_Minimap.GetViewRadius`; a point outside the view
radius is hidden rather than clamped to the edge.

For a rotating Minimap, the projection uses `GetPlayerFacing()`. If rotation is
enabled but orientation cannot be read, markers are hidden. If Blizzard reports
that Minimap rotation is ignored, the projection uses north-up orientation.
Pins share one indexed frame pool. Transformed remote coordinates are cached by
character version and target map; the shared MapLinks updater is polled by its
existing central driver, while this feature limits a full refresh to once per
second and skips unchanged signatures.

## Marker style and tooltip

Class style uses Blizzard's class atlas and `RAID_CLASS_COLORS`. Guild style
uses one consistent Holy Storm guild icon. Separate settings control the two
pin sizes.

Hover text reads the existing CharacterUI, CharacterStore, guild roster, and
TwinkCore identity systems. Available values include name, class, race, role,
rank, AFK/DND status, main-character relation, item level, current raid
progress, current-season Mythic+ rating, and coordinate age. Missing values are
omitted. Mythic+ rating is displayed only for schema/snapshot version 5 when its
season ID matches `C_MythicPlus.GetCurrentSeason()`.

## Right-click and POI capability

Right-click delegates invite, whisper, copy-name, character, and main-character
actions to the existing `CharacterActions` context menu. If
`poi.create` is available from the POI module, the menu adds “Use position as
POI” and passes the original map ID and normalized coordinates through the
capability. If POI is unavailable, that menu item is disabled; other map and
character actions remain available. The callback checks the capability again
before use.

## Events and tasks

Feature events:

- `PLAYER_ENTERING_WORLD`, `PLAYER_STARTED_MOVING`, `PLAYER_STOPPED_MOVING`.
- `ZONE_CHANGED_NEW_AREA`, `ZONE_CHANGED`, `ZONE_CHANGED_INDOORS`.
- `HS_ROSTER_UPDATED`, `PLAYER_GUILD_UPDATE`, and
  `HS_PERMISSIONS_STATE_UPDATED`.
- The map provider also waits for `ADDON_LOADED` for `Blizzard_WorldMap`.

TaskManager jobs:

- `Position.Capture`: waits for player-ready, loading/zoning completion, and
  guild availability.
- `Position.Publish`: coalesces by local character and uses the Sync-v2 live
  domain.
- `Position.InitialDiscovery`: one explicit, delayed live-state discovery.
- `Position.Reconcile`: guild/presence cleanup.
- `Position.MapRefresh`: merges map changes and updates affected pins together.
- `Position.MovementSample` and `Position.Cleanup`: central recurring jobs;
  movement sampling is 1 second only while moving, cleanup is 10 seconds.

## Retail API audit and assumptions

The API signatures were checked against the Blizzard-generated API
documentation files in the current `Gethe/wow-ui-source` live source mirror,
which identified itself as Retail 12.1.0 (69933) at audit time:

- [`MapDocumentation.lua`](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/MapDocumentation.lua)
  documents `GetBestMapForUnit(unitToken)` (nullable map; only player and party
  members), `GetPlayerMapPosition(uiMapID, unitToken)` (nullable Vector2; only
  player and party members), `GetMapInfo(uiMapID)` (may return nothing),
  `GetMapChildrenInfo(uiMapID, mapType?, allDescendants?)`, the
  `UiMapDetails.parentMapID` field, both world/map conversion functions, and
  `GetMapWorldSize(uiMapID)` (width/height in yards).
- [`MinimapDocumentation.lua`](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/MinimapDocumentation.lua)
  documents `C_Minimap.GetViewRadius()` (yards) and
  `C_Minimap.IsRotateMinimapIgnored()`.
- [`PlayerScriptDocumentation.lua`](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/PlayerScriptDocumentation.lua)
  documents `GetPlayerFacing()` as nullable and the
  `PLAYER_STARTED_MOVING` / `PLAYER_STOPPED_MOVING` events.
- [`UnitDocumentation.lua`](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua)
  documents `GetUnitSpeed(unit)` and its four returns. It can be restricted, so
  calls are protected and event fallback is retained.
- [`Blizzard_MapCanvas.lua`](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_MapCanvas/Blizzard_MapCanvas.lua)
  documents the relevant implementation contract: providers are added with
  `AddDataProvider`, World Map pins are pooled by `AcquirePin`, and removing a
  provider calls its `RemoveAllData` and `OnRemoved` methods.

The local capture API returns nil when the map or position is unknown. The map
conversion APIs can return nothing on unsupported map/continent pairs. These
are expected runtime cases, not reasons to infer coordinates.

## Limitations and Retail verification

- WoW does not expose the remote guild member's current position directly to
  this add-on; members must have Holy Storm loaded and sharing enabled.
- Blizzard can omit positions on unsupported maps, transports, instances, or
  while map data is loading. In those cases the marker is omitted until a later
  valid capture/conversion.
- Map-to-world conversion establishes the exact target-map coordinate where
  Blizzard supports it. Minimap yard projection and minimap rotation still need
  the in-client checks below across outdoor, indoor, transport, and mount
  scenarios.
- Guild-roster presence refresh timing determines when offline removal is
  observed.
- Automated Lua tests use API fakes; they cannot verify real Blizzard map art,
  map transforms, or two-client transport behavior.

Retail test plan:

1. Run two Holy Storm clients. Confirm initial discovery and a moving update.
2. Stand still on one client for several minutes; the marker remains while the
   roster says online, with no recurring stationary position traffic.
3. Walk slowly, run, use a mount, teleport, Hearthstone, and take a portal. Check
   intervals, final stop capture, and immediate map-change capture.
4. Open exact zone, parent zone, continent, and world overview maps. Unsupported
   transforms must omit the pin.
5. Toggle World Map and Minimap independently; test marker sizes, class/guild
   style, rotating/north-up Minimap, map edges, and out-of-range hiding.
6. Toggle privacy off while the marker is visible. Confirm a coordinate-free
   withdrawal removes it, and that no later coordinates are sent until the
   local user opts in again.
7. Test online/offline, AFK/DND, tooltip data, character/main navigation,
   right-click actions, and POI both present and absent.
8. Observe Sync-v2 status while position updates run and while important
   character sync is active. Position transfers should stay low priority and
   not create a historical queue.
