# Options, Local Settings, Commands, and Player Profile

## Central options page

`LIVE/Holy_Storm_UI/UI/Pages/Options.lua` is the single user-options home. Modules add groups with `Options:RegisterOptionsTab(id, definition)`. Existing profile controls from AceDBOptions remain available there. Feature pages can keep their functional UI, and a settings button may open the matching central group.

For settings that use the shared local store, modules register an option contract with `Options:RegisterSetting`. A contract records a stable ID, owning module, localized name and description keys, type, default, allowed scopes, storage descriptor, UI order, and optional slash path/aliases. The registry feeds both the central options UI and slash registration. `Options:SetSetting` and option slash handlers use the same module setter or `Settings:Set` path.

Some existing central groups have not yet moved to the contract registry. They still use their documented owner API and storage, and appear in the audit below. The registry is an incremental boundary; it does not replace AceDB profiles or administrative settings controlled through permissions and synchronization.

## Local setting scopes

`LIVE/Holy_Storm/Core/Settings/Settings.lua` owns personal, non-synchronized values stored below `HolyStormDB.global.localSettings`:

| Bucket | Key | Meaning |
| --- | --- | --- |
| Character | Character GUID | Local value for one character |
| Account / Global | Setting ID | Local value shared by this WoW installation |
| Guild | Guild ID, then setting ID | Local override for one guild |
| All Guilds | Setting ID | Local guild default for every guild |

The active setting resolves in this order: current guild override, All Guilds, current character, Account / Global, module default. A definition lists only scopes that make sense for that option. A per-setting selected scope controls where the next UI or slash write goes. A guild scope is unavailable without a current guild.

These local values are separate from guild administration settings managed by the permission and sync systems. `Settings:Register` rejects definitions marked synchronized. Database schema migration 14 creates the local buckets without replacing existing profile or guild data.

## Slash command registry

`LIVE/Holy_Storm/Core/Commands/Commands.lua` owns `/hs` command paths, aliases, groups, descriptions, and callbacks. Modules register commands with `Commands:RegisterSlashCommand`; option contracts with a slash path add an option command through that same registry. The help page reads the registry at display time.

The core paths include:

| Command | Action |
| --- | --- |
| `/hs` and `/hs open` | Open the main Holy Storm window |
| `/hs help` and `/hs ?` | Open registered command help |
| `/hs info` | Open addon, profile, module, and guild information |
| `/hs status` | Open addon, module, sync, task, workflow, and log status |
| `/hs reload` | Call `ReloadUI()` |
| `/hs options` and `/hs o` | Open central options |
| `/hs addons` | List loaded Holy Storm addons |
| `/hs scan …` | Request supported character scans through CharacterScans |

Equipment adds `/hs equipment scan`. Simple POI and Positions toggles and Equipment trigger toggles also register option commands. The options UI and slash commands write through the same definitions and selected scope.

The UI extension in `LIVE/Holy_Storm_UI/UI/Pages/SystemPages.lua` adds the help, info, and status pages to the existing UI page registry. These pages do not create separate windows.

## Player Profile and privacy

The Characters addon now presents itself as **Player Profile / Spielerprofil**. Internal addon IDs, SavedVariables names, Sync domains, and TwinkCore APIs remain compatible. The existing character roster page remains available as **Characters / Charaktere**.

Account-level voluntary fields are real name, structured birth date, ISO-style country code, city, player type, typical weekdays, and typical play times. Character-level fields include preferred specializations, derived role, alternate roles, and raid, Mythic+, and Delves interests. Each field stores its value separately from visibility. `PRIVATE`, `GUILD`, and `PUBLIC` are supported, and missing visibility defaults to `GUILD`. Empty and withheld fields have different exported states.

The country search stores stable country codes and displays localized names. Birth dates use day, month, and year controls; invalid dates are rejected. Parseable legacy dates are migrated. An unparseable legacy date remains stored and is marked unresolved.

The profile page lists locally owner-confirmed characters with main-character crown, class icon and color, realm, guild, and preferred specializations. It uses TwinkCore's existing exclusive account-main pointer. Specializations are filtered to the character's class, and preferred roles are derived from those selections. Legacy profile data and TwinkCore relationships remain in their existing stores.

Account profile metadata export is sanitized by TwinkCore. Character profile block export is sanitized in PlayerDataStore before Sync sees it, even if the Profiles module's optional sanitizer is not loaded. Private values are retained locally and emitted as withheld state without the value.

## Positions, POI, and Equipment

### Positions

Position sharing defaults to enabled only when there is no saved value. Legacy `false` remains `false`; migration imports the old value only when the central setting bucket is empty. Sharing can be scoped to this guild or all guilds. Display and map presentation settings use local account settings. Position snapshots and administrative rules remain on their existing sync and permission paths.

### POI

Map visibility, marker sizes, maximum synchronized entries, category filters, and target filters now register with central Options and local Settings scopes. Existing values are imported before use. The POI list, detail, create/edit, and diagnostics views remain feature UI. The Settings button opens the central POI options group. Per-POI hide state remains in the POI data manager because it is local item state, not an options panel.

### Equipment

The mandatory equipment-change trigger is displayed as checked and disabled. Optional enchant and socket triggers default on and request the same CharacterScans producer as equipment-change events. The options group displays the existing snapshot revision, schema and snapshot versions, successful timestamp, scan state, error, and retry information when available. Its Scan Now button and `/hs equipment scan` command both call `RequestManualScan`; neither writes a snapshot directly. There is no equipment-sync disable option.

The optional triggers use `WEAPON_ENCHANT_CHANGED` and `SOCKET_INFO_SUCCESS` through the existing event bus and CharacterScans debounce/merge behavior. The socketing UI uses `SOCKET_INFO_UPDATE` to refresh its panel and tooltip while `SOCKET_INFO_SUCCESS` marks a completed socket operation, so the UI refresh event is deliberately excluded. Equipment workflow requests share a one-second debounce. The current 12.1 live UI/API source was checked; a Retail client is still needed to verify event timing against the collected snapshot and the in-game options/status UI.

## Module options audit

This is an inventory of current code, not a proposal to add settings. “Central” means the setting UI is registered inside the Holy Storm options page. “Contract” means it uses the new stable-ID local settings registry.

| Module | Existing user options or state | UI / storage / scope | Slash | Duplicate or follow-up note |
| --- | --- | --- | --- | --- |
| Core | Minimap icon, window position/size, optional-module state, AceDB profiles | Central general/profile groups; AceDB profile and module registry | `/hs`, help, info, status, reload, options, addons, scans | Generic profile options remain separate from local setting scopes by design |
| UI | SavedVariables viewer/editor controls | Central `savedVariables` tab; reads and edits existing stores | None found | Administrative data tools, not module preferences |
| Achievements | Notification sound defaults on | AceDB profile area `achievements.sound`; no registered option group found | Generic `/hs scan` does not target achievements | Persisted setting exists without a visible toggle |
| Calendar | Guild event snapshot/unread state | Global Database state, not a user preference | None found | State data only |
| Characters / Player Profile | Voluntary account and character profile fields; Twink visibility and account main | Player Profile and Characters pages; TwinkCore account metadata and PlayerData character blocks | None found | Visibility sanitization is in TwinkCore/PlayerData; no separate profile options window |
| Chat | Enrichment, colors, tooltips, main/real-name labels, links, mentions, channels, diagnostics | Central `chat` tab; AceDB profile | None found | Central UI already, but settings still use direct AceDB callbacks rather than setting contracts |
| Delves | No user option registration found | No options group; character scan data uses PlayerData | Available under generic `/hs scan delves` | No settings added in this change |
| Equipment | Optional enchant/socket scan triggers | Central `equipment` tab; local Character, Account, Guild, All Guilds scopes | `/hs equipment scan`; trigger option commands | Mandatory equipment trigger is fixed; snapshot/workflow and sync remain unchanged |
| Guild | Show offline members, group account characters | Central `guildRoster` tab; AceDB profile | None found | Direct AceDB profile settings, not scope contracts |
| GuildLog | Retention maximum and age | Central `guildLog` tab; DataManager global `guildLog` retention record | None found | Central UI, direct store API; scope semantics are not in local Settings |
| Mythic+ | No user option registration found | No options group; character scan data uses PlayerData | Available under generic `/hs scan mythicplus` | No settings added in this change |
| News | No user option registration found | No options group; content/read state uses existing DataManager stores | None found | Content persistence is not a preference store |
| POI | Map/minimap visibility, sizes, receive limit, category/target filters | Central `poi` tab; local Character, Account, Guild, All Guilds scopes | Simple registered filters/toggles | Per-item hide state remains local POI state in DataManager |
| Positions | Share, roster display, map visibility, marker sizes/style | Central `positions` tab; new local Settings registry; share is Guild/All Guilds | Simple toggles registered | Legacy profile area is read only for import; permission-based administrative state remains separate |
| Professions | No user option registration found | No options group found | None found | No settings added in this change |
| Raids | No user option registration found | No options group; character scan data uses PlayerData | Available under generic `/hs scan raid` | No settings added in this change |
