# Guild Activity Tracking architecture

Guild Activity is the third registered child of `HolyStorm.GuildManagement` in `Holy_Storm_Guild`. It records observable participation facts; it does not assign points, classify members, recommend rank/removal changes, or execute guild actions. Core, RuleEngine, FilterManager, Raid, MythicPlus, and Calendar remain feature-blind consumers or sources.

## Provider and event contract

`GuildManagement.Activity:RegisterProvider(id, definition)` accepts stable activity types, lifecycle callbacks, normalization, and optional validation. `Submit` stamps the current Account/Character before queued normalization so delayed work cannot be reassigned after a character switch; normalized output must retain that captured identity. Providers can be enabled, disabled, and unregistered independently. History remains readable when a provider is absent; provider-specific Rule values are `UNKNOWN`. Duplicate IDs and malformed providers are rejected.

The initial providers are `online`, `guild-chat`, `raid`, and `mythic-plus`. Stable event types are `ONLINE_SESSION`, `GUILD_CHAT`, `RAID_ENCOUNTER`, `MYTHICPLUS_RUN`, and the reserved extension type `EVENT_ATTENDANCE`. Each detailed event contains schema version, deterministic event ID, type, Account UUID, contributing Character UUID, provider/source, factual timestamps, and bounded type-specific metadata. An occurrence ID identifies a raid encounter/run/session; the participant relationship lives in the account-owned event. Thus each member retains its own participation fact without one shared occurrence becoming duplicates in one account shard.

Calendar invitation responses do not prove attendance. No Calendar provider is registered until an existing Holy Storm or Blizzard state can establish actual attendance reliably. `EVENT_ATTENDANCE` remains a narrow provider extension point and its Rule field returns `UNKNOWN` while unavailable. Calendar storage is unchanged.

## Identity and collection semantics

Storage is partitioned by current Guild ID and Account UUID. Character UUIDs remain on events and per-character aggregates; known twinks therefore contribute once to the account while remaining explainable. There is no future Player-to-Accounts identity layer.

Online presence opens one persisted session on login. Normal logout closes it exactly at the observed boundary. Zone transitions only checkpoint `lastObservedAt`; they do not create new sessions. After reload/crash, an orphaned session closes at its last checkpoint as `RECOVERED` with `uncertain=true`, then a new session opens. This deliberately does not invent a disconnect timestamp.

Guild chat captures only the local account's `CHAT_MSG_GUILD` participation. It buffers daily counts, deduplicates line IDs in memory, and persists no message, sender text, whisper, party/raid/Battle.net channel, or arbitrary chat payload. Hot handlers queue TaskManager work instead of rewriting storage per message.

Raid uses encounter start/end and stores instance, encounter, difficulty, success, time, and compact group context. Mythic+ uses challenge start/completion and stores map, level, duration/timed facts only when Blizzard completion data is present. These are participation facts and do not copy Raid/MythicPlus character-progression snapshots.

## Guild relevance

One central policy classifies a snapshot as `FULL_GUILD`, `MAJORITY_GUILD`, `PARTIAL_GUILD`, `NOT_GUILD_RELEVANT`, or `UNKNOWN`. The isolated foundation policy is `minimumGuildMembers=1` and `majorityRatio=0.5`; full, majority, and partial groups meeting the minimum are included, while zero-guild-member and unknown groups are rejected. Stored metadata contains group size, guild-member count, and classification. The threshold is intentionally isolated for later policy configuration and is not a quality score.

## Persistence, aggregation, and time

DataManager schema `guild-activity` stores `guildManagement.activity.guilds[guildId]` with bounded authoritative account shards and small summary indexes. A shard contains immutable origin Character UUID, current owner/writer, revision/timestamp, characters, detailed events, daily/weekly buckets, lifetime facts, and an optional open session. UI reads summaries and range aggregates rather than copying/scanning the entire database.

Daily boundaries use Unix/UTC day buckets, avoiding local DST-length days. `GetAggregate(account, startAt, endAt, options)` supports arbitrary factual ranges and optional Character UUID; `GetHistory` adds type/provider/character filters and a bounded result; `GetOverview` uses summary indexes plus cached aggregates. Cache keys include shard revision and are invalidated after commits/imports. Partial weekly overlap is explicitly marked approximate.

Recent online detail is retained for 90 days. Raid, Mythic+, and event occurrences remain detailed for 730 days. Daily aggregates remain for 180 days, then merge deterministically into Monday-aligned UTC weekly buckets retained for 520 weeks. Lifetime aggregates remain. Detail is additionally capped at 2,500 events per account. Moving a day to a week never re-adds lifetime facts, so repeated compaction cannot double count.

## Synchronization, authorization, and diagnostics

The central `guildActivity` Sync domain advertises metadata and transfers one bounded authoritative account shard, not individual chat messages/events. Capture is owner-controlled; origin stays immutable, revisions are monotonic, stale imports are rejected, and `receivedFrom` records relay provenance. Discovery, offers, fetch, validation, recipient enumeration, batching/throttling, and transport remain SyncManager/TaskManager responsibilities. Payloads are targeted only to recipients authorized for `guild-activity-view`.

The sole permission is `guild-activity-view`, because the foundation exposes no separate repair/manage action or more-sensitive diagnostics. Defaults grant it to `officers` and `guild-member`; protected Leadership receives it dynamically with all registered permissions.

Validation bounds IDs, timestamps, ranges, provider/source, required type fields, metadata depth/key/count/string/number sizes, detail count, bucket metrics, and open-session state. Logger entries identify validation, deduplication, recovery, compaction/sync rejection context but never chat content. Capture is event-driven; there is no polling, recurring timer, combat-log collection, movement/coordinate capture, or per-second persistence.

## Rules, UI, and future boundary

Module-owned factual Rule fields are `activity.lastSeen`, `activity.daysSinceLastActivity`, `activity.onlineDuration7d`, `activity.guildChatCount7d`, `activity.raidParticipation30d`, `activity.mythicPlusParticipation30d`, and `activity.eventAttendance30d`. The generic Rule contract cannot currently parameterize time windows, so stable localized windows are explicit; arbitrary ranges remain available through the Activity API. Missing identity/history/permission/provider yields `UNKNOWN`; an available provider plus known shard with no events yields zero. FilterManager consumes the fields generically.

The lazy Activity child uses shared UILayout, buttons, Table scrolling/selection, empty states, and responsive weighted columns. It supplies account overview, absence context, factual 7/30/90-day ranges, selected-account detail, and type/provider/character filters. `CharacterActions` contributes `View activity`, resolving Character to Account. No score, good/bad color, recommendation, or guild action is present.

Future Points/Recommendations may read the public factual query surface. They must remain separate policy domains and must never mutate Activity facts or automatically promote, demote, remove, punish, or reward a member.

## Known runtime limits

Capture is owner-observed: an account without Holy Storm Activity enabled produces no authoritative shard, so absence of data is `UNKNOWN`, not inactivity. Blizzard exposes no exact disconnect/crash timestamp, hence recovered sessions stop at the last event-driven checkpoint. Calendar responses are not attendance proof. Raid and Mythic+ facts depend on encounter/challenge completion events and the group roster visible to the participating client; unavailable completion data is rejected rather than inferred. The Retail provider prefers the table-returning `C_ChallengeMode.GetChallengeCompletionInfo` API and retains the older function only as a compatibility fallback.
