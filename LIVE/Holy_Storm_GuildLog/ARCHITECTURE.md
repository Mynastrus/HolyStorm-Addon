# Holy Storm Guild Log

GuildLog is the structured, persistent history for one guild. It is registered as the `guildLog` Holy Storm module and appears as a feature inside Guild Management. It does not add a roster column, main navigation page, private saved-variable database, or transport implementation.

## Event contract

Events contain data, not rendered sentences. Each stored event has `schemaVersion`, deterministic `eventId`, `identityKey`, `type`, `guildId`, numeric `timestamp`, `timestampSource`, `capturedAt`, `updatedAt`, `actor`, `subject`, structured `data`, `provenance`, `resolutionState`, `originGuid`, `recordedByGuid`, and `revisionId`. UI text is rendered from the current client's locale. The principal timestamp sources are `SERVER_EVENT`, `ROSTER_DELTA_CAPTURE`, and `PRODUCER`; states are `AUTHORITATIVE`, `RECONSTRUCTED`, and the internal `SUPERSEDED` reconciliation state.

Other modules submit events through the `guild.log.submit` capability. Register a type first with `guild.log.registerType`:

```lua
HolyStorm:CallCapability("guild.log.registerType", {
    id = "RAID_REWARD",
    category = "other",
    labelKey = "CATEGORY_RAID_REWARD",
    color = "69a8d8",
    identityKey = function(event)
        return "raid-reward:" .. event.data.rewardId .. ":" .. event.subject.guid
    end,
    render = function(event, characterName, locale)
        return string.format(MyAddonLocale["GUILD_REWARD"], characterName(event.subject), event.data.rewardName)
    end,
})

HolyStorm:CallCapability("guild.log.submit", {
    type = "RAID_REWARD",
    timestamp = HolyStorm.Utils.Now(),
    timestampSource = "PRODUCER",
    resolutionState = "AUTHORITATIVE",
    subject = { guid = characterGuid },
    data = { rewardId = rewardId, rewardName = rewardName },
    provenance = { kind = "MODULE_EVENT", source = "MyAddon" },
})
```

Use an event-specific stable `identityKey` when the generic `data.eventKey` key does not express the event's identity. Include only structured information needed for display, matching, and search. Renderers receive a character-name callback so actor and subject names can use the existing RichLinks infrastructure in GuildLog's row renderer. Do not put localized text into `data` or `provenance`.

For a custom category, the plugin should provide its category label key in the active `Holy_Storm_GuildLog` locale table before registering the type. Its enUS/deDE locale files should define the same key. For a type in the built-in `other` category, the category label remains `Other events`; the type label is used in search when available.

`guild.log.query` returns visible structured events. `guild.log.export` accepts `bbcode`, `html`, or `csv` and an options table with `scope = "ALL"` or `scope = "FILTERED"`; it returns the export text or `{ errorCode = "FILTER_INDEX_PENDING" }` while the visible page's large-log index is being built. Capability calls return a map keyed by the owning module, following the Core capability contract.

Built-in types cover joins, departures, rank changes, level-ups, public and officer-note changes, Guild Management achievements, absence lifecycle changes, birthdays, and guild anniversaries. Birthday and guild-anniversary types are available to reliable producers, but GuildLog does not invent dates: profile birthdates are account data and the guild store's creation time is only the local observation time.

## Roster observations and reconciliation

GuildLog consumes `HS_ROSTER_UPDATED` and queues immutable roster observations as `GuildLog.RosterDelta` tasks. It persists only the baseline fields needed to detect join, leave, rank, level, and note-hash changes. It hashes note values and never stores note text. A roster-derived event records its observation interval, local detection time, and `RECONSTRUCTED` state; it does not guess an actor or an exact event time.

When a direct rank event matches a reconstructed transition within the saved observation interval, the existing event is upgraded and its alias remains resolvable. If the observed transition is A-to-C and direct events later establish A-to-B followed by B-to-C, GuildLog marks the inferred A-to-C record `SUPERSEDED` and keeps the two direct events visible. Rank transitions without reliable rank ordering are displayed as rank changes without guessing promotion or demotion.

Identity keys are event-specific: level-ups use guild, character, and new level; achievements use character, achievement, and award instance; absences use character, absence ID, and revision; rank changes include the character and old/new ranks with timestamp tolerance. Merging identical observations uses stable ordering for conflicting fields so peers converge.

## Persistence, retention, and sync

`GuildLogStore` owns the `guild-log` DataManager schema at the central `global.guildLog` path. It stores each guild's entries, roster baseline, aliases, and retention settings. The defaults retain up to 5,000 events or 730 days, whichever limit is reached first. The optional shared Options module adds local controls from 100 to 20,000 events and 30 to 3,650 days. Pruning is queued in the background and orders equal timestamps by deterministic event ID.

The former `HS_GuildLog_DB` contained localized message strings and raw note values in its roster snapshot. Those records are not copied into the structured schema. On upgrade, the first complete roster observation establishes a clean baseline without inventing events; new deltas are recorded from that point onward.

The `guildLog` Sync domain transfers one structured event per object through SyncManager. Metadata and revision IDs support duplicate suppression, catch-up, and reconciliation without sending the whole log. Normal events follow the existing guild broadcast route. Events gated by a Guild Management permission use the SyncManager's targeted-recipient path and recheck each recipient's permission. Officer-note changes are filtered locally using WoW's officer-note permission and are never synchronized; only hashes are stored.

An event's `originGuid` is its sync owner. `actor` means the character who performed the action; `recordedByGuid` identifies the client that first observed or recorded it. This distinction matters for reconstructed events where the actor is unknown. Direct achievement and absence events use the producing actor as their origin when available.

## Permissions, tasks, and diagnostics

Normal GuildLog reading uses the default-visible policy. Officer-note events are locally visible only when `C_GuildInfo.CanViewOfficerNote()` grants access; the event contains hashes rather than note text, and these events are excluded from sync. Guild Management events with an administrative permission are checked when listed, exported, published, and served to a requesting peer. GuildLog defines no read permission for ordinary entries.

`GuildLog.RosterDelta`, `GuildLog.Filter`, and `GuildLog.Prune` run through TaskManager. Roster snapshots are submitted asynchronously, filter-index work is chunked and debounced, and retention runs once per day plus after writes that reach a configured limit. Query and export preparation operate on the store's visible result set; a pending large-log index is reported to the caller instead of blocking the UI.

GuildLog diagnostics use Holy Storm's central Logger under the `GuildLog` / `events` context. They record accepted and invalid events, duplicate merges, reconstructed-event reconciliation, sync acceptance or rejection, pruning, and permission-sensitive events hidden or rejected. Routine accepted/duplicate/hidden messages use debug level to avoid noisy normal logs; exceptional validation failures use warning level.

## UI behavior

GuildLog registers a Guild Management feature and lets the existing tab registry refresh when the feature is added or removed. It uses a one-column, virtualized list with a centrally defined category marker. Player names use Holy Storm RichLinks. The filter popup combines categories, actor, subject, reconstruction state, and inclusive date bounds. The repository has no shared WoW date-picker component, so date bounds accept localized `YYYY-MM-DD` input and explain the format in their tooltips. Search indexes are built in TaskManager chunks. Exports use the same visible store query as the UI and escape CSV, HTML, and BBCode output, including custom-rendered text.

`/hs guild log` and `/hs glog` emit the same Guild Management navigation request as the UI feature. GuildLog has no standalone page.

## Offline regression checks

Run `lua tools/test_guild_log.lua` for structured events, permissions, producer integrations, roster snapshots, reconciliation, sync deduplication, commands, locale rendering, filters, exports, retention, reload, and a 5,000-event work-budget check. `tools/test_localization_contract.lua`, `tools/test_addon_split.lua`, and `tools/test_persistence_boundary.lua` cover locale parity, addon ownership, and the no-direct-SavedVariables contract.
