# Holy Storm: POI World Map Rendering and Minimap Key Fix

**Completed:** 2026-10-04 23:03:30 +02:00 (Europe/Berlin)
**Branch:** `main`
**Implementation commit:** `082298c65ec751f5149e2a4d22b1c08df2ca0049` (pushed to `origin/main`)

## A. `Map.lua` Minimap signature failure

The failing expression in the reported `Map.lua:120` was the inner signature builder:

```lua
table.concat({entry.poiID, entry.revisionID or entry.revision, string.format("%.5f", x), string.format("%.5f", y)}, ":")
```

The nil was component 2: `entry.revisionID or entry.revision`. `MapLinks:SetTemporaryMarker` creates a legitimate temporary marker with the fixed `poiID` `temporary-coordinate`, coordinates, and `temporary=true`, but no revision fields. `Map:GetEntries` adds that marker to the same active entry list as saved POIs. Therefore both `Map:Refresh` and the shared `minimap:update:poi` updater could reach the signature builder with a revisionless marker.

The fix gives temporary markers an explicit `temporary` signature component. Saved POIs still require a valid revision component before a key is built; malformed identity/revision values are rejected and recorded in bounded diagnostics. Temporary entries also receive a namespaced render key and bypass the revision-based transform cache, so a moved marker cannot reuse stale transformed coordinates. The signature remains stable across repeated refreshes and changes when the projected position changes.

This does not remove any saved POI identity or merge revisions. A stored POI whose ID equals the temporary marker's fixed ID is distinct from the temporary marker in rendering and reconciliation.

## B. World Map rendering path

The Minimap exception was **not** the reason a World Map pin was missing. `Map:Refresh` refreshes the visible World Map provider before calling `RefreshMinimap`; the thrown Minimap error followed World Map acquisition, positioning, and reconciliation in that pass. The shared updater can throw independently without being part of the World Map provider callback.

The independent pin-template defect was in `Map.xml`: the World Map pin had a sized button and assigned icon/glow textures, but neither texture had anchors. The icon now fills the pin frame and the glow is centered. Pin initialization also selects the existing `PIN_FRAME_LEVEL_AREA_POI` frame-level range.

The exact-map runtime regression test confirms that a valid visible POI reaches `AcquirePin`, uses its original normalized coordinates without a related-map transform, has a 22×22 frame, configured icon, full default alpha, visible state, and the POI frame-level type, and remains one active pin after reconciliation. Unchanged refreshes reuse pins; removed or inapplicable entries are released. Existing parent-map transformation behavior, unrelated-map filtering, unsupported transforms, and no-navigation behavior remain covered.

The provider is installed behind the existing `installed` guard on World Map show, remains attached across close/reopen and navigation, and refreshes through the provider callbacks. This follows the current Retail MapCanvas contract: [`MapCanvasMixin:AcquirePin` / provider lifecycle](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_MapCanvas/Blizzard_MapCanvas.lua) and [`MapCanvasDataProviderMixin`](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_MapCanvas/MapCanvas_DataProviderBase.lua). The existing assertion fix remains intact: `Map.xml` still defines no `OnEnter`/`OnLeave` scripts; hover is handled by `OnMouseEnter`/`OnMouseLeave` mixin methods.

## C. Regression safety and verification

- Added runtime coverage for the real revisionless temporary marker, repeated Minimap refresh, marker movement, missing persistent revision handling, and the temporary/stored POI ID collision case.
- Added exact-map World Map assertions for acquisition, visual initialization, original coordinates, and stable active-pin reconciliation.
- Expanded bounded diagnostics with World Map-enabled counts, `AcquirePin` attempts/successes, removals, invalid identity, and Minimap signature component failures.
- Minimap projection, settings, pin reuse, visibility state, tooltip/click handlers, and refresh throttling remain on their existing paths; repeated refresh tests passed without signature errors or duplicate pins.
- Full Lua regression suite: **81/81 passed**.
- Lua syntax check: **6 changed Lua files passed**; `Map.xml` parsed successfully; `git diff --check` passed.
- Feature locale parity check passed.

The WoW Retail client is not available in this environment, so a live visual check of the newly anchored icon and a BugSack check after opening/reopening the World Map remain to be confirmed in-game. No synchronization or persistence code was changed. No release or tag was created. Root `images/` was not modified, and the pre-existing user-owned workspace-file change was left unstaged and untouched.

## Delivery

Implementation and tests were committed as `082298c65ec751f5149e2a4d22b1c08df2ca0049` (`Fix POI minimap keys and world map pin visuals`) and pushed to `origin/main`. The pushed remote head matched the local commit.
