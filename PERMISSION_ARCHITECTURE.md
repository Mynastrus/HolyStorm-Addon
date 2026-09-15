# Holy Storm permission architecture

## Authority and scope

`Core/Permissions/Policy.lua` is the only authority for groups, effective memberships,
permissions, permission-context filter references, guild module flags, revisions,
catch-up, and recovery. State is keyed by stable guild ID. UI code reads copies
and invokes public mutation APIs; it neither edits SavedVariables nor sends sync
messages.

The protected system groups are exactly `guild-leadership`, `officers`, and
`guild-member`. Their Blizzard rank membership is evaluated dynamically. Custom
character, account, rank, and filter sources are additive. There is no deny rule.
The actual Blizzard rank-0 member is the local trust anchor and is the only actor
that may alter additional leadership membership.

## Revision chain

Every guild-wide mutation creates one revision containing `revisionID`,
`previousRevisionID`, actor identity, timestamp, and a declarative change. A
received revision is accepted only when it directly follows the current revision,
passes structural validation, and its actor was authorized by that exact
predecessor state. History is bounded to 100 entries.

The `permissions` sync domain therefore uses `freshness="revision-chain"`.
Generic metadata comparison may select a source, but cannot authorize or import
permission state. Equal-version sibling revision IDs are fetched so the Policy
engine can detect forks. Missing predecessors start catch-up; a snapshot recovery
is accepted only from a currently visible Blizzard rank-0 character. No
"highest version wins" recovery exists.

This is integrity and consistency enforcement inside the World of Warcraft addon
trust model. It is not cryptographic authentication and makes no security claim
against a malicious client that can forge addon messages or local game state.

## Public UI contracts

Read APIs include `GetGroups`, `GetGroupSummaries`, `GetEffectiveMembers`,
`GetFilters`, `GetRules`, `GetUsage`, `Explain`, `GetPermissionStateStatus`,
`GetRevisionHistory`, and `GetRejectedRevisions`. Mutations use `CreateGroup`,
`SaveGroup`, membership APIs, filter/rule APIs, `SetGuildModuleEnabled`, and
`RestoreDefaults`.

The reusable UI infrastructure in `UI/Framework/Components/PolicyUI.lua` supplies dynamic
selectors, checked lists, virtualized/scrolled lists, trace formatting, and the
nested condition builder. Conditions come from the Rule Engine registry;
permissions come from the Permission registry. Core events mark pages dirty, and
the UI manager coalesces visible-page refreshes.
