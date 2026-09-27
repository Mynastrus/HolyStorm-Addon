# Raid lifetime Statistics

The Raid producer in `LIVE/Holy_Storm_Raids/Raids.lua` collects two independent
sources. The Encounter Journal supplies the current expansion's raid and boss
catalog (instance IDs, encounter IDs, order, names, and icons). Saved instances
supply weekly lockouts. Blizzard Statistics supplies lifetime boss kill counts;
weekly kills are never substituted for missing lifetime values.

## Statistic ID mapping

Blizzard's current Statistics UI enumerates `GetStatisticsCategoryList()`, calls
`GetCategoryNumAchievements(categoryID)`, and obtains a statistic ID from the
third return of `GetStatistic(categoryID, index)`. It displays the name from
`GetAchievementInfo(statisticID)` and the value from `GetStatistic(statisticID)`.
See Blizzard's Mainline [Statistics UI source](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_AchievementUI/Mainline/Blizzard_AchievementUI.lua#L2212-L2305),
particularly `AchievementFrameStats_UpdateDataProvider` and the statistic row
initializer.

Holy Storm traverses the returned Statistics categories during the existing
Raid scan workflow. It parses a row label of the current client's form
`Boss (Difficulty: Raid)`, normalizes punctuation and whitespace, and requires
exact agreement with one Encounter Journal raid, one encounter boss, and a
canonical difficulty name from `GetDifficultyInfo`. The resulting snapshot
record uses stable Encounter Journal raid/encounter identities and retains
Blizzard's statistic ID. Duplicate matches for a boss/difficulty are
rejected. A manual `/hs scan raid` refreshes the discovery index; an automatic
scan can reuse a nonempty index for the same catalog.

This is a controlled current-client label mapping. There is no verified
hardcoded StatisticID registry for the current raid shown in the Retail report,
Der Giftige Abgrund. GMS 2.0.3 demonstrates a static `{LFR, Normal, Heroic,
Mythic}` ID table for older raids, but its table does not include that raid.
Those IDs are not copied into Holy Storm. The old requirement for exactly one
achievement criterion with type 0 and an asset matching an Encounter Journal
creature ID has been removed: Blizzard's Statistics UI does not require that
relationship to name or read a row.

In [GMS 2.0.3](https://github.com/Mynastrus/GMS/tree/v2.0.3/GMS),
`Core/RaidIds.lua` maps selected journal IDs to map IDs and then to positional
four-ID boss rows. `Modules/Raids.lua` uses its static path to
call `GetStatistic(statisticID)` for each row, count positive bosses by
difficulty, and store aggregate raid Best. Although that module defines
category and label helpers, its active `BuildBestByRaidFromCharacterStatistics`
path returns the static result before using them. GMS treats zero and unknown
alike for its aggregate count and does not retain per-boss kill counts. Holy
Storm retains its own snapshot, persistence, Sync, and UI model instead.

The mapping still depends on Blizzard's current localized label shape and the
current client's names agreeing with Encounter Journal and `GetDifficultyInfo`.
There is no documented guarantee that all future raids retain that format.
`RAID_LIFETIME_CANDIDATE_REJECTED`, `RAID_LIFETIME_UNMAPPED`, and per-slot
`RAID_LIFETIME_STAT` records expose failures without guessing an ID or a boss.
Unrelated Statistics are excluded from detailed logs. Detailed records are
bounded; the scan summary reports category, candidate, read, mapping, and
truncation counts.

## Snapshot and Best

Each known value is stored in Raid snapshot v3 under
`lifetime.bosses[encounterID].difficulties[LFR|NORMAL|HEROIC|MYTHIC]` with the
numeric `kills`, Blizzard `statisticId`, and `source="blizzard-statistic"`.
Positive numeric values and confirmed zero are known. `nil`, `--`, malformed,
or inaccessible values are unknown and do not become zero. Multiple difficulty
records are retained. The snapshot flows through PlayerData, CharacterStore,
and generic character Sync without a Raid-specific projection.

Character UI and the LibQTip Best tooltip accept only positive counts with
that statistic provenance. Each boss displays its highest positive difficulty;
the compact raid Best counts bosses at the highest available difficulty. A
fresh validated snapshot with no lifetime values may still contain an empty
`lifetime.bosses`; `/hs scan raid status` exposes that state.

## Future raid maintenance

The current-client discovery normally needs no per-raid code or data change.
When Blizzard changes Statistics labels or exposes a verified stable mapping,
record the EJ instance ID, encounter IDs and order, all four StatisticIDs per
boss, and direct `GetStatistic(statisticID)` results in both supported locales.
Validate positive, unique IDs and the EJ boss count before introducing a static
mapping. Never bridge a positional row table to EJ bosses when counts differ.
Use synthetic IDs only in offline fixtures; actual IDs require authoritative
data or a Retail scan. Add the observed label form and zero/unknown cases to
the end-to-end fixture, then repeat the Retail acceptance scan. The release
gate remains open until that real scan confirms lifetime Best independently of
the weekly lockout.
