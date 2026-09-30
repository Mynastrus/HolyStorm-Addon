# TwinkCore identity model

## Purpose and identity

TwinkCore groups Character identities for roster and character views. A Character is keyed by Holy Storm's stable character GUID. A PlayerUUID (also called AccountUUID in the current API and saved schema) identifies one Holy Storm player group. “Twink” describes a Character in that group; it is not a separate identity.

The PlayerUUID is generated independently of character names and main selection. Changing the Account Main never changes the PlayerUUID or character membership.

## Relationships and authority

`owner-confirmed` is the persisted AUTO source. It is created when the current Character reports its local Holy Storm identity and may be relayed through an authorized owner snapshot. `administrative` is the persisted MANUAL fallback source. It is created through a guild-authorized manual assignment.

For each character GUID, `characterAccounts` indexes at most one effective PlayerUUID. AUTO outranks MANUAL. When an owner snapshot proves an AUTO relationship, TwinkCore removes the Character from its previous MANUAL group and installs the AUTO relationship. Between conflicting AUTO proofs, the newer `confirmedAt` wins; equal timestamps use the lexically smaller PlayerUUID, while a locally owner-confirmed AUTO relationship is protected from remote reassignment. Unrelated Characters stay in their existing groups; a single-character conflict does not merge or split whole groups. A later MANUAL payload is ignored while AUTO is effective. Character snapshots and their Equipment, Mythic+, Raid, Delves, Stats, profile and history blocks are separate and are never deleted by relationship changes.

Owner snapshots export only AUTO entries. MANUAL assignments use the existing `twinkAdmin` Sync domain, which carries per-assignment revisions and removal tombstones. Reassignment removes the old membership and records its tombstone before publishing the new assignment. Permission and authority are checked independently of transport revision, so a newer MANUAL relay cannot replace AUTO.

## Account Main, Guild Main and Shadow Main

The Account Main is explicitly selected by the owner from their AUTO-confirmed characters. Until then, TwinkCore selects a deterministic fallback, ordered by known guild rank, normalized character name, then character GUID. The fallback is computed and does not become a persisted owner choice.

`GetGuildMain(PlayerUUID)` returns the Account Main when it is in the current guild. Otherwise it returns a dynamically computed Shadow Main: the known guild Character with the highest rank, then normalized name, then GUID. Shadow Main is not persisted and never changes the Account Main.

## Visibility

The persisted default is `all`. `all` exposes every known Character. `guild-only` exposes guild Characters plus the Account Main as a reference even when that Main is outside the guild. Visibility filters views only; it does not remove relationships or alter their sync payload. AUTO and MANUAL use the same visibility rules.

## Persistence, migration and APIs

PlayerDataStore owns the persisted Twink relationship state and retains the legacy `accounts`, `players`, `characterAccounts`, `characterOwners`, and tombstone fields in place. TwinkCore obtains relationship state through `PlayerData:GetTwinkState`, assigns local account identity through `SetLocalAccountUUID`, and maintains the owner index through `SetCharacterOwner`. It does not access `PlayerData:GetRoot()` or manipulate snapshot blocks for relationship changes.

Startup normalization resolves duplicate legacy memberships per Character: AUTO wins over MANUAL; equal-authority collisions choose the lexically smaller PlayerUUID. It preserves unrelated group members and existing Character snapshot data. Legacy `owner-confirmed` and `administrative` source values remain supported as the serialized AUTO and MANUAL labels.

## Unknown and unassigned

A Character with no effective relationship remains unassigned. A guild roster record or stored character snapshot alone does not prove an account relationship. A MANUAL relationship is allowed only while no AUTO relationship is known. Context actions show the source, prevent editing AUTO, and expose assignment, change and remove for MANUAL when authorized.

## Events and permissions

Relationship and account changes emit the existing `HS_CHARACTER_RELATIONSHIP_UPDATED`, `HS_ACCOUNT_UPDATED`, `HS_TWINKS_UPDATED`, `HS_ACCOUNT_MAIN_CHANGED`, `HS_TWINK_VISIBILITY_CHANGED`, and `HS_GUILD_MAIN_CHANGED` events after local state is updated. Guild Main recalculation uses the existing unique TaskManager task and compact roster summary.

`twinks-manage-manual-assignments` is the Module Contract permission for manual guild relationship operations. Guild leadership and officers receive it by default; guild members do not. Viewing relationships has no separate Twink permission. Account Main selection remains owner-only and does not use the guild-management permission.

## UI

Guild roster grouping consumes `GetRosterIdentity`; selection of Account Main, Guild Main and Shadow Main remains in TwinkCore. Character Overview's Twinks tab renders the effective group from stored identity and roster data, including main labels, class, level, guild membership and relationship source. Reusable Character Actions provide manual assignment, reassignment and removal through the existing context menu.

## Retail acceptance

Offline checks cover storage migration, authority ordering, reassignment tombstones, owner snapshot filtering and UI locale contracts. A live Retail client is still needed to verify two-client guild sync, actual guild-rank ordering, context-menu presentation, reload stability, visibility in the roster and Character Overview, BugSack output, Holy Storm logs, and absence of script timeouts.
