# Holy Storm PlayerData and synchronization architecture

`HS_Player_DB` schema 2 is the canonical persistent store for characters,
accounts, ownership links, per-domain watermarks, and owner-issued block
metadata. `HolyStormDB.global.data` is assigned compatibility aliases at
runtime; it is not a second write path.

Modules read and write characters through `HolyStorm.Data.CharacterStore` (or
the lower-level `HolyStorm.PlayerData` block API) and accounts through
`HolyStorm.Data.PlayerStore`. Only `WriteOwnedBlock` increments a character
block version. Network imports must use `AcceptRemoteBlock`, which preserves
the owner's version and timestamp and rejects stale data.

## Character block metadata

Each character record has `blockMeta[blockId]` containing:

- `owner`: character GUID that issued the version
- `version`: monotonically increasing owner-issued version
- `updatedAt`: owner-issued timestamp
- `source`: original collection source
- `receivedFrom`: most recent transport peer, for diagnostics
- `direct`: whether the most recent accepted copy came directly from its owner

At equal versions, a direct-owner copy outranks a relayed copy. A newer
owner-issued version outranks an older version even when relayed. A relay never
calls the owned-write path.

## Domain API

Synchronized domains register once through `HolyStorm.Sync:RegisterDomain` and
provide `getMetadata`, `listMetadata`, `export`, `import`, plus optional
`validate`, `authorize`, and `updateEvent` callbacks. Transport, serialization,
discovery, response jitter/suppression, best-source selection, payload fetch,
retry, passive healing, and login catch-up remain Core responsibilities.

The built-in domain is `character`. `TwinkCore` registers `twinks` for complete
owner-issued AccountUUID-to-character snapshots and `twinkAdmin` for separately
authorized administrative assignments/tombstones. News registers `news` and
`newsRead`; policy registers the permissions/rules/filters `policy` domain.
Equipment, Mythic+, raid lockouts, delves, stats, profiles, professions, and
on-demand rule data are character blocks and need no module transport handler.

The Calendar module currently reads Blizzard's server-owned calendar API and
has no addon-owned synchronized dataset. It therefore does not register a
domain; any future Holy Storm-owned event objects must register through this
API rather than adding transport code to the module.

## Wire flow

1. `DISCOVER` broadcasts metadata criteria only.
2. Peers jitter `OFFER` metadata responses and suppress equivalent offers they
   overhear.
3. The requester selects one best source and whispers `FETCH`.
4. Only that source whispers `PAYLOAD`.
5. Other clients may schedule deduplicated, low-priority passive refreshes from
   overheard metadata.

Login catch-up is delayed and low priority. Per-domain foreign watermarks only
optimize discovery; versions decide final freshness. Locally owned characters
and the local account never advance foreign watermarks.

The stable `AccountUUID` is independent of character names and the selected
main. `twinks` always exports the complete known relationship, including entries
hidden by the account-wide UI visibility setting. Owner versions are advanced
only by the local account; relays preserve them. Administrative changes retain
their actor/version provenance and cannot remove an owner-confirmed relation.

The protocol authenticates claimed senders against guild-roster identity and
applies domain authority rules, but WoW addon messages have no cryptographic
signature. Consequently, owner-version provenance is enforceable as a client
invariant, not cryptographic proof against a malicious modified client.

## Account and twink identity

`HolyStorm.TwinkCore` owns the current `AccountUUID -> Characters` layer. A
future person/player layer can reference one or more AccountUUIDs without
changing character-facing module contracts. Public read/write entry points are
`GetAccountUUIDForCharacter`, `GetAccount`, `GetCharactersForAccount`,
`GetAccountMain`, `SetAccountMain`, `GetGuildMain`, `GetRosterIdentity`,
`GetRelationshipSource`, `IsOwnerConfirmed`, `GetVisibility`, `SetVisibility`,
`GetVisibleCharactersForViewer`, `AssignCharacterAdministrative`, and
`RemoveAdministrativeAssignment`.

Relationships carry either `owner-confirmed` or `administrative` provenance.
Owner evidence applies per character: it upgrades or moves characters explicitly
present in the owner snapshot but does not delete administrative entries absent
from that snapshot. Administrative tombstones have their own actor-issued
versions and permission checks (`twinks.assign`, `twinks.remove`). Guild-main and
shadow-main selection is deterministic and remains a derived, non-persistent
view over the current guild roster.

Consumers refresh from `HS_ACCOUNT_UPDATED`, `HS_TWINKS_UPDATED`,
`HS_CHARACTER_RELATIONSHIP_UPDATED`, `HS_ACCOUNT_MAIN_CHANGED`,
`HS_GUILD_MAIN_CHANGED`, and `HS_TWINK_VISIBILITY_CHANGED`. Deferred guild-main
recalculation is deduplicated through `TwinkCore.RecalculateGuildMains` in the
central Task Manager.
