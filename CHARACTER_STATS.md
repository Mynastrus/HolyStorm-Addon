# Character Stats data contract

## Audit findings

The old `stats` v1 producer stored the first two `UnitStat` returns as `base` and `effective`, stored the first two `UnitArmor` returns as `base` and `effective`, and stored `GetCombatRatingBonus` as the secondary percentage. The Character -> Values view rendered primary `effective - base`; for armor that made the API's first return of `0` the base and its second return of `2390` the additional amount. Secondary totals displayed rating bonus percentages, which omit class/spec/passive and other effective contributions used by Blizzard's Character Panel.

The current Blizzard FrameXML reads effective primary/armor and secondary values for the paper doll. Critical strike uses the highest applicable melee, ranged, or minimum spell-school chance and its corresponding rating type. Haste and mastery use their effective APIs; versatility combines rating bonus with `GetVersatilityBonus`. Holy Storm now follows those displayed-value semantics. Sources: [Blizzard PaperDollFrame](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_UIPanels_Game/Mainline/PaperDollFrame.lua), [Unit API documentation](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua), [Player API documentation](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/PlayerScriptDocumentation.lua).

## Per-stat contract

| Stat | Rating source | Effective/live source | Stored baseline | Additional support | Stored and synced |
| --- | --- | --- | --- | --- | --- |
| Strength | — | `UnitStat("player", 1)` effective return | Current stat less positive and negative buff returns | Observed delta only after a clean snapshot | Baseline |
| Agility | — | `UnitStat("player", 2)` effective return | Current stat less positive and negative buff returns | Observed delta only after a clean snapshot | Baseline |
| Stamina | — | `UnitStat("player", 3)` effective return | Current stat less positive and negative buff returns | Observed delta only after a clean snapshot | Baseline |
| Intellect | — | `UnitStat("player", 4)` effective return | Current stat less positive and negative buff returns | Observed delta only after a clean snapshot | Baseline |
| Armor | — | `UnitArmor` effective return (second return) | Effective armor captured without an observable timed aura | Observed delta only after a clean snapshot | Baseline |
| Critical Strike | `GetCombatRating` for the rating family chosen by Blizzard's effective crit comparison | Highest of `GetCritChance`, `GetRangedCritChance`, and the minimum spell-school `GetSpellCritChance` | Effective selected crit chance captured without an observable timed aura | Observed percentage-point delta only after a clean snapshot | Rating and baseline |
| Haste | `GetCombatRating(CR_HASTE_MELEE)` | `GetHaste` | Effective haste captured without an observable timed aura | Observed percentage-point delta only after a clean snapshot | Rating and baseline |
| Mastery | `GetCombatRating(CR_MASTERY)` | First return from `GetMasteryEffect`; coefficient retained separately | Effective, specialization-scaled mastery captured without an observable timed aura | Observed percentage-point delta only after a clean snapshot | Rating, baseline, coefficient |
| Versatility | `GetCombatRating(CR_VERSATILITY_DAMAGE_DONE)` | `GetCombatRatingBonus` plus `GetVersatilityBonus` for damage done | Effective damage versatility captured without an observable timed aura | Observed percentage-point delta only after a clean snapshot | Rating and baseline |
| Leech | `GetCombatRating(CR_LIFESTEAL)` | `GetLifesteal` | Effective leech captured without an observable timed aura | Observed percentage-point delta only after a clean snapshot | Rating and baseline |
| Avoidance | `GetCombatRating(CR_AVOIDANCE)` | `GetAvoidance` | Effective avoidance captured without an observable timed aura | Observed percentage-point delta only after a clean snapshot | Rating and baseline |
| Speed | `GetCombatRating(CR_SPEED)` | `GetSpeed` | Effective speed captured without an observable timed aura | Observed percentage-point delta only after a clean snapshot | Rating and baseline |

`UnitStat` returns the current stat, effective stat, positive buff contribution, and negative buff contribution. The stored primary baseline is the first return minus the two buff returns; the live total is the effective return. `UnitArmor` returns base, effective, real, and bonus armor. The first armor return is not the character-panel armor baseline; the second is the displayed effective armor.

Rating and effective percentage remain separate. Zero is preserved; missing, non-finite, protected, or unavailable API values remain unknown. Mastery includes specialization scaling in the effective value. Versatility's main percentage is the displayed damage/healing benefit; the damage reduction component is not currently stored or rendered.

## Snapshot, persistence, and compatibility

Stats v2 stores only the normal-state baselines, useful rating values, specialization metadata, and capture eligibility/reason in the existing `stats` PlayerData block. It does not persist live effective values as authoritative totals. PlayerData validates v1 blocks for backward compatibility and validates v2 schema/capture and finite numeric fields. V1 blocks are not rewritten or misread as v2 baselines; the UI can continue to show stored primary legacy values but does not invent secondary effective percentages or additional values. A successful v2 refresh naturally replaces v1 through the existing owned-block write and synchronization path.

PlayerData block sync carries the validated v2 baseline and ratings. The transient live layer stays in `CharacterUI` memory and is only accepted for the local player's GUID. Remote characters render their stored snapshot and never inherit the local player's live buffs.

## Temporary-state limits and event flow

Blizzard exposes effective values, but does not provide a universal per-stat split between permanent character configuration and temporary modifiers. Holy Storm therefore does not label rating contribution as baseline or derive a universal temporary formula. It records a persistent baseline only when the aura API and clock are readable and a complete helpful/harmful aura scan finds no active timed aura. Unknown aura fields, secret values, API failures, or an incomplete scan make the capture ineligible. The commit checks this condition again to close the scan-to-write race.

When a v2 baseline is available, the UI's Additional field is the observed difference between current effective value and that baseline. It is not an attribution to a particular aura or proof that every source is temporary. If baseline freshness is uncertain, Additional is unknown. Permanent configuration changes mark the baseline dirty; until a clean replacement baseline commits, the UI withholds Additional. Indefinite effects with no timer cannot be distinguished from permanent effects by this aura check; this is an API limitation and remains a known boundary.

Equipment, specialization, trait/talent, level, and entering-world events schedule debounced live refreshes and baseline scans through CharacterScanManager, SnapshotManager validation, and PlayerData commit/sync. `UNIT_AURA` only schedules a coalesced live refresh. If a durable change is waiting while timed auras are active, the baseline stays dirty and the next aura update after they expire retries the scan. The live layer is held in memory only and is never independently synchronized.

The Character -> Values table displays the persistent baseline, observed additional difference, and current effective total. Secondary totals show `rating (effective %)`. Gray `-` means unknown/unavailable; confirmed zero displays `0` or `0.0%`; positive and negative additional differences are green and red. Remote rows show stored baselines/ratings and leave additional unknown.
