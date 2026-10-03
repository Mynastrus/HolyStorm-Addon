# Character Snapshot Pipeline

The current refresh policy is documented in [`docs/SNAPSHOT_REFRESH_POLICY.md`](docs/SNAPSHOT_REFRESH_POLICY.md). That document defines the cache-first behavior, shared status contract, producer event matrix, manual entry points, login behavior, sync interaction, and idle-work audit.

## Write and sync boundary

Feature producers collect and validate their own Blizzard data, then call `PlayerData:WriteOwnedBlock`. PlayerData owns schema validation, semantic equality, revisions, timestamps, persistence, and the accepted remote-import boundary. `HS_PLAYERDATA_OWNED_UPDATED` is emitted only after a changed authoritative write; SyncManager publishes from that event. A rejected, incomplete, unavailable, or failed refresh leaves the last valid stored block intact.

`CharacterScanManager` serializes explicit and event-triggered requests through registered providers. Snapshot presence and age do not enqueue work. `/hs scan <block>`, `/hs scan all`, dashboard prompts, and the Character Overview refresh action all request the existing provider workflow. Dashboard and Character Overview use `CharacterUI:GetDataStatus` for a common view of stored validity, domain freshness, and local transient scan state.

## Audited blocks

The character snapshot declaration registry currently contains Equipment, Mythic+, Raid, Delves, and Stats. Professions is a separate optional, event-loaded local block updated when its profession view is requested or skill lines change; it is not part of `/hs scan all`. Profile and character identity writes are user/core data paths rather than Blizzard snapshot producers.

See the policy document for current versions, retained events, freshness rules, startup protections, and the Retail acceptance plan. Historical API investigation remains in [`docs/MYTHICPLUS_RETAIL_API_AUDIT.md`](docs/MYTHICPLUS_RETAIL_API_AUDIT.md), [`DELVES_RETAIL_API_AUDIT.md`](DELVES_RETAIL_API_AUDIT.md), and [`docs/Equipment.md`](docs/Equipment.md).
