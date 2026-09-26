--[[
    LibGuildRoster-1.0

    Tracks the WoW guild roster. THE ROSTER IS BUILT ONCE, during the login
    stream, and MAINTAINED IN PLACE from chat events for the rest of the
    session. GUILD_ROSTER_UPDATE builds it and is then ignored outright;
    CHAT_MSG_SYSTEM carries online/offline/join/leave/promote/demote, and
    CHAT_MSG_GUILD/_OFFICER is a free proof-of-online for members whose login
    announcement was never seen. Retries up to MAX_RETRIES times at login to
    handle the window where GetNumGuildMembers() returns 0.

    Why, in one line: GUILD_ROSTER_UPDATE is fired in a loop by the client's own
    calendar code and by every addon that requests a roster, so the event's cost
    had to become zero rather than merely smaller. See OnGuildRosterUpdate for
    the mechanism and CHANGELOG.md 0.5.0 for the full account.

    ⚠ THE MEASUREMENT LIVES HERE AND NOWHERE ELSE. Two captures, both on this
    user's 978-member guild, both 2026-08-15. Cite this block rather than
    restating the numbers — audit finding 15 was raised because the header and
    a code comment had drifted to different counts for one quantity, and no
    amount of reading could recover which was right.

    A LOGOFF BURST IS A RANGE, NOT A CONSTANT — six to nine events observed,
    varying by event. Do not quote either endpoint as the figure.

      Event counter, counting GUILD_ROSTER_UPDATE fires:
          3 per burst while completely idle, roughly every 30 s
          up to 9 per guildmate logoff, reproduced three times
          (Kem 00:02:09, Chingaling 00:03:29, Ulgales 00:04:53)
      Attribution wrapper, timing each rebuild — a SEPARATE capture, taken
      after a fresh /reload about fifteen minutes later:
          15 rebuilds over 5 bursts; 3.22-47.04 ms each; mean 16.45 ms
          6 rebuilds totalling 140.93 ms for one guildmate logoff (Kawto,
          ~00:20), which is the reported stutter

    THE TWO INSTRUMENTS NEVER RAN ON THE SAME LOGOFF — four different
    characters, fifteen minutes apart, with a /reload between them. So the six
    and the nine are between-event variance and NOT three events that failed to
    reach the handler; there is no dispatch defect here. Audit finding 16 asked
    exactly this question and it is the one part of it that needed someone who
    was there.

    ⛔ Do not reinstate the "140.93 / 9 = 15.7 ms agrees with the 16.45 ms
    mean" cross-check that used to sit here. It cannot be made valid: 140.93 is
    the sum of six itemised rebuilds, so dividing it by nine is the per-rebuild
    cost of nothing, and the 16.45 ms mean it was compared against is computed
    over all fifteen rebuilds INCLUDING those six — which hold the capture's two
    largest values. Neither direction of that test can discriminate.

    AFTER v0.5.0 the same wrapper on a 990-member guild reports 0.004-0.005 ms
    per post-stabilization event. That is the fix, measured in a live client.

    ⚠ CHAT PARSING IS NOW THE SOLE CORRECTNESS PATH, and that is a change in
    kind, not degree. Until 0.5.0 the rebuild was a self-healing net: a chat
    pattern that failed to match cost only latency, because the next rebuild
    reconciled membership within seconds. There is no next rebuild. A locale
    whose pattern or needle does not match now leaves an ex-member in the roster
    until the player logs out, and — because the membership hash never moves —
    propagates that stale set to every sister client. Treat any change to
    BuildChatPattern / BuildChatNeedle / StripChatLinkMarkup as correctness
    work, not string handling. Audit finding 14 was raised against exactly this
    and MINOR 15 is its fix.

    ⚠ AND DO NOT REASON ABOUT A LOCALE — RUN Tests/locale_spec.lua. It drives
    every one of the seven format strings, in all eleven locales the client
    ships, end to end through the real handler and asserts the DECLARED argument
    the code wants is the one the callback names. It exists because this library
    twice shipped a locale that was silently, totally dead: deDE kicks (never
    matched, positional specifiers) and then ruRU kicks plus ruRU/frFR/koKR rank
    changes (never matched, grammar escapes). Both were found by hand, one at a
    time, and the second was found only because the first was reported as the
    whole category. A hand-enumeration of "which locales are affected" is the
    move that produced both; the table in that spec is the enumeration.

    The HOME roster is in-memory only and is never persisted. As of MINOR 18
    the sister-guild LIST and the pulled sister ROSTERS are persisted in
    `LibGuildRosterDB` (declared by the standalone GuildRoster TOCs) so they
    answer on login before the first live pull; see the sister-sync section.

    Callbacks (via CallbackHandler-1.0):
        OnRosterReady()         Fired once after the first stabilized full
                                build. HOME roster only.
        OnRosterUpdated()       Fired after a full rebuild — which now happens
                                ONLY during the login stream, so in practice
                                this fires a handful of times at login and then
                                never again for the session. It is NOT a
                                "something changed" signal and never was; a
                                consumer wanting to know about later membership
                                or presence changes wants OnMemberJoined /
                                OnMemberLeft / OnMemberOnline / OnMemberOffline
                                / OnRosterHashChanged, all of which stay live.
                                HOME roster only — sister feeds do not fire it.
        OnMemberOnline(name)    Fired when a HOME member transitions to online —
                                from the chat announcement, or from the member
                                speaking in guild/officer chat while still
                                recorded as offline (added in MINOR 12).
        OnMemberOffline(name)   Fired when a HOME member transitions to offline.
                                (Sister presence is query-only — see MarkOnline
                                / GetOnlineMembersScoped — and fires neither.)
        OnMemberJoined(name, guildKey)
                                Fired when a member joins a guild. For the home
                                guild, driven exclusively by the CHAT_MSG_SYSTEM
                                "X has joined the guild" message (see the
                                handler comment for why the roster diff doesn't
                                drive this on retail); for a sister guild, by
                                the SetSisterRoster membership diff. guildKey is
                                the guild it happened in (added in MINOR 6;
                                one-arg consumers ignore it).
        OnMemberLeft(name, guildKey)
                                Fired when a member leaves a guild (home: chat
                                "has left" / "has been kicked"; sister: the
                                SetSisterRoster diff).
        OnMemberRankChanged(name, oldRankIndex, newRankIndex)
                                Fired when a HOME member's guild rank changes,
                                driven by the CHAT_MSG_SYSTEM promote/demote
                                messages (MINOR 14; previously the rebuild
                                diff). The message names the new RANK, so the
                                index is resolved through a rankName -> index
                                map learned from the roster rows. A promotion
                                into a rank NOBODY currently holds cannot be
                                translated: member.rankName is still updated,
                                and the callback stays silent rather than
                                inventing an index.
        OnMemberLevelChanged(name, oldLevel, newLevel, wasOnline, isOnline)
                                ⛔ NO LONGER FIRES, as of MINOR 14. Added in
                                MINOR 9 and produced only by the post-rebuild
                                diff, which build-once removed. There is nothing
                                to move it to: no CHAT_MSG_SYSTEM message
                                announces a guildmate levelling, and
                                GUILD_NEWS_FORMAT6 is a Cataclysm Guild News UI
                                feed that Classic Era does not have. Detecting a
                                level change means re-reading the whole roster,
                                which is the work build-once exists to stop.
                                member.level is still populated by the login
                                build and readable via GetMember; only the
                                notification is gone. The signature is kept here
                                because consumers still register against it —
                                registration is harmless, it simply never fires.
                                See CHANGELOG.md 0.5.0.
        OnRosterHashChanged(guildKey, newHash)
                                Fired when a roster's MEMBERSHIP set changes
                                (not presence) — for the home roster on a
                                rebuild after stabilization, and for a sister
                                roster on each SetSisterRoster that alters the
                                set. newHash is GetRosterHash(guildKey).
        OnSisterConfigChanged(names, ts, source)
                                Fired when the sister-guild LIST changes — by an
                                officer's SetSisterGuildNames ("local") or by a
                                guildmate's gossip being adopted (source is the
                                sender). names is the sorted list. MINOR 18.

    Public API (home guild). Everything here is STABLE — nothing has been
    removed or changed shape since MINOR 5 — but the list has GROWN, so an
    entry carrying an "added in MINOR N" note is absent from an older copy and
    a consumer must feature-detect it (`if GR.IsOfficer then`) rather than
    infer its presence from this heading. An earlier wording said "unchanged
    since MINOR 5" of the whole block, which stopped being true the moment
    anything was added to it — and a reviewer in a consuming addon had already
    cited that phrase as evidence for what an older copy does and does not
    have:
        lib:IsReady()             -> boolean (true once OnRosterReady has fired)
        lib:IsInGuild(name)       -> boolean
        lib:IsOfficer([name])     -> boolean|nil (added in MINOR 12)
                                  Officer privileges for the PLAYER, decided by
                                  the granted officer-note permission and never
                                  by the rank index. false when guildless. nil
                                  for any name other than the player's own —
                                  the client exposes no API for another
                                  member's permissions, and nil says "unknown"
                                  where false would assert "not an officer".
        lib:IsOnline(name)        -> boolean
        lib:GetMember(name)       -> table|nil  { name, class, level, rankIndex,
                                                  rankName, isOnline, zone,
                                                  publicNote, officerNote, status,
                                                  isMobile, lastOnline }
        lib:GetAllMembers()       -> array of "Name-Realm" strings
        lib:GetOnlineMembers()    -> array of "Name-Realm" strings currently online
        lib:GetNormalizedPlayer() -> string|nil  the local player's "Name-Realm"
        lib:NormalizeName(name)   -> string|nil  canonical "Name-Realm" for any
                                                 short or qualified name (the same
                                                 normalization used for roster keys)
        lib:CanonName(name)       -> string|nil  canonical REPRESENTATION only;
                                                 a bare name stays bare (MINOR 11)
        lib:GetRealmName()        -> string  the connected-realm-aware realm name

    NormalizeName vs CanonName — pick by the PROVENANCE of the name:
        A name read from a LOCAL client API is bare only when the character is
        on the viewer's own realm (UnitName's second return is nil for a
        same-realm unit; GetGuildRosterInfo omits the realm for same-realm
        members). Appending the local realm there is a correct inference, so
        NormalizeName is right for roster rows, units and the local player.
        A name that arrived OVER THE WIRE lost that context in transit: the
        receiver's realm is not the sender's, so appending it invents a
        different identity on every client in a connected-realm cluster. Use
        CanonName there and keep the name bare.

    NormalizeName MEMOIZES, so every method taking a `name` has a side effect:
    the string is retained until the cache is wiped. That is nine doors, not
    one — NormalizeName, IsOfficer, IsInGuild, IsOnline, GetMember,
    IsInAnyRoster, IsInGuildScoped, SetSisterRoster and MarkOnline — and a
    lookup that answers false/nil still caches the name it was asked about. The
    cache is bounded in the library (NAME_CACHE_MAX, MINOR 14) rather than by
    asking consumers to only pass roster-shaped names, because SetSisterRoster
    and MarkOnline are fed from the addon channel and no consumer can see the
    lifetime consequence from the call site.

    Cross-guild API (sister rosters — added in MINOR 6, all additive):
        lib:GetHomeGuildKey()           -> string|nil  "Faction-GuildName"
        lib:SetSisterRoster(key, members[, meta])      wipe-and-replace a fed
                                                       sister roster
        lib:RemoveSisterRoster(key)                    stop tracking a sister
        lib:MarkOnline(key, names)                     stamp sister presence
        lib:GetOnlineMembersScoped(key) -> array of online "Name-Realm" (home:
                                           live isOnline; sister: fresh presence)
        lib:IsInAnyRoster(name)         -> guildKey|nil (home takes precedence)
        lib:IsInGuildScoped(key, name)  -> boolean
        lib:GetRoster(key)              -> table|nil  { charKey = member }
        lib:GetRosterMeta(key)          -> table|nil  opaque caller metadata
        lib:GetKnownRosters()           -> array of guildKeys
        lib:GetRosterHash(key)          -> string|nil  membership-only digest
        lib:GetRosterNoteHash(key)      -> string|nil  public notes only (MINOR 19)
        lib:GetRosterRankHash(key)      -> string|nil  ranks only (MINOR 21)

    A synced sister member carries name, class, level, note (public), rankName,
    rankIndex and guild. note is nil when empty; rankName and rankIndex are nil
    when the provider's library predates MINOR 21. Presence is not a field; ask
    GetOnlineMembersScoped.

    Sister-guild SYNC (added in MINOR 18, all additive) -- the list, the
    gossip, the persistence and the pull that consumers used to carry each
    for themselves. A port of TOGProfessionMaster's cross-guild code; see the
    section comment above GetSisterDb for what was kept and what was not:
        lib:GetSisterGuildNames()       -> sorted array of configured guild NAMES
                                           (empty = nothing configured, which a
                                           consumer can now tell apart from
                                           "configured, roster not pulled yet")
        lib:SetSisterGuildNames(names)  -> ok, reason. OFFICER-ONLY (IsOfficer);
                                           array or newline-separated text.
                                           Stamps, tears down dropped guilds,
                                           gossips to the home guild.
        lib:GetSisterGuildsTs()         -> number  server-time stamp of the list
        lib:GetSisterGuildKeys()        -> array of "Faction-GuildName", sorted
        lib:IsSisterGuildKey(key)       -> boolean, case-insensitive. THE gate.
        lib:PullSisterRoster(peer)      -> boolean  pull from a named online
                                           member of a sister guild (the manual
                                           bootstrap). The library's own two
                                           messages over WHISPER; needs only
                                           Ace3 on both ends.
        lib:RequestSisterRosters()      -> number   one automatic round: pull
                                           each listed guild from its freshest
                                           known-online member
        lib:BroadcastSisterConfig()     -> boolean  gossip the list now
        lib:BroadcastSisterRosters()    -> number   relay held rosters now
        lib:RefeedSisterRosters()       -> number   re-feed the persisted copies
        lib:PersistSisterRoster(key)    -> boolean  snapshot one (listed) roster
        lib:IsSisterSyncAvailable()     -> boolean  is the pull path up (roster
                                           ready, in a guild, AceComm present)
        lib:GetSisterDb()               -> table|nil the per-home-guild
                                           SavedVariables record (read it; write
                                           through SetSisterGuildNames)
        lib:GetSisterStatus()           -> array of { name, key, held, members,
                                           online } -- what any display shows
        lib:HandleSlash(msg)            -> boolean  the body of the /guildroster
                                           (/libgr, /gr) command: no argument
                                           opens the window; `sisters [add|remove
                                           |clear <Guild>]`, `pull <Name-Realm>`,
                                           `sync` are the text backup. The list
                                           edits carry the officer gate; a
                                           consumer may route its own command here.
        lib:ToggleSisterWindow()        -> table|nil the LibAceGUIWidgets window
                                           (nil, with a chat line, when that
                                           library is absent)
        Callback OnSisterRosterUpdated(guildKey, source) fires when a sister
        roster lands by "pull" or "relay" -- what a consumer that used to hook
        RosterSync's onSisterRosterUpdated wants.

    Alt groups (added in MINOR 17, all additive) -- which characters share one
    account. A port of the alt-group code running in TOGProfessionMaster, with
    one deliberate correction; see the section comment above SetAltGroup for
    what was kept, what was dropped, and why:
        lib:SetAltGroup(owner, alts)    -> boolean  wipe-and-replace, SORTED
        lib:RemoveAltGroup(owner)       -> boolean
        lib:GetAltGroup(owner)          -> table|nil  sorted array of charKeys
        lib:GetAltOwner(altName)        -> string|nil the key it is filed under
        lib:IsSameAccount(a, b)         -> boolean
        lib:GetKnownAltOwners()         -> array of owner keys, sorted
        lib:IsAltOfRosterMember(name[, rosterKey])
                                        -> boolean. Does somebody ELSE in that
                                           roster vouch for this character?
                                           Works across sister rosters; a
                                           character already in the roster on
                                           its own account answers false,
                                           because it needs no vouching.

    THE OWNER KEY IS A KEY, NOT A "MAIN". It is whichever character the consumer
    filed the group under. This library cannot know which character a player
    mains -- no client API exposes it -- and does not claim to.

    ALT NAMES USE CanonName, NOT NormalizeName, and that is the correction: an
    alt group is wire data, so appending the RECEIVER's realm would invent a
    different identity on every client in a connected-realm cluster. A bare name
    therefore stays bare in storage. Roster comparisons still normalize, because
    "is this character in MY roster" is a local question.

    The home roster lives under self.roster (self-scanned, authoritative);
    sister rosters under self.rosters[guildKey] (externally fed). guildKey is
    "Faction-GuildName" and charKeys are "Name-Realm" — both MUST be spelled
    exactly as the consumer produces them (route everything through
    NormalizeName / GetHomeGuildKey) or cross-roster lookups match nothing.
    Because this lib is embedded in multiple addons, the MINOR bump and every
    embedder's .toc must move together, and consumers should feature-detect
    each new method (if lib.SetSisterRoster then ...) so a load race against an
    older copy degrades to a no-op rather than erroring.

    Member fields:
        name        Name-Realm string.
        class       Class file name ("WARRIOR", "MAGE", ...).
        level       Numeric character level.
        rankIndex   0 = guild leader, 1 = next rank down, etc.
        rankName   Localized rank label.
        isOnline    true if connected via game or mobile app.
        zone        Last-known zone (may be nil for offline members).
        publicNote  Public guild note ("" if empty).
        officerNote Officer note. "" if the local player's rank lacks
                    GR_RANKFLAG_VIEW_OFFICERNOTE.
        status      0 = available, 1 = AFK, 2 = DND.
        isMobile    Legacy "connected via WoW Companion app" flag. The companion
                    remote was retired in 12.0.1 and this GetGuildRosterInfo
                    slot is deprecated, so it reads false on modern clients.
                    Kept for API compatibility; do not rely on it.
        lastOnline  { years, months, days, hours } for offline members,
                    nil for online members or when the API isn't available.

                    ⚠ ITS RESOLUTION IS "AS OF LOGIN, OR AS OF THE MOMENT WE
                    SAW THEM LOG OFF" — read this before displaying it.
                    GetGuildRosterLastOnline is only readable per roster ROW,
                    and rows are only read during the login stream, so:
                      * offline at login and still offline — the login value,
                        which UNDER-reports by however long you have been
                        playing. Bounded by session length and not corrected.
                      * logged off while you watched — all zeroes, written on
                        the chat-proven transition. Accurate to the second.
                      * came online while you watched — nil, as documented.
                    A consumer wanting a live "offline for how long" should
                    treat the zero tuple as "just now" and take the login
                    value as a floor, not a reading.

    Consumers do NOT need to manage the guild panel's "Show Offline Members"
    setting, and this library no longer touches it either. Measured on a live
    Classic Era client with the box UNTICKED, iterating 1..GetNumGuildMembers()
    returned 997 of 997 rows: the iteration is not filtered, so there was
    nothing to work around. Every version up to 0.5.0 bracketed each scan
    (force the flag on, read, restore) and that bracket was itself the harm —
    SetGuildRosterShowOffline fires GUILD_ROSTER_UPDATE, so it fed the event
    that reached it. Removed in 0.5.1; see the note above ReadRosterRow.
    Earlier versions also asked retail consumers to call
    SetGuildRosterShowOffline(true) at init; that is obsolete, and doing it now
    just overwrites a user preference for no gain.

    This repo is the canonical upstream for this library. The inline
    "FGI vendor fix" markers below are historical — they date from when
    this file lived as a vendored copy inside FastGuildInvite — and carry
    no meaning here; they can be cleaned up incidentally when their lines
    are edited. Do not add new ones.
--]]

local MAJOR, MINOR = "LibGuildRoster-1.0", 24
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end

local CBH = LibStub("CallbackHandler-1.0")
lib.callbacks = lib.callbacks or CBH:New(lib)

-- ===========================================================================
-- Flavor compat. One place for every version-divergent branch so a client
-- patch that moves or retires an API is a single-section edit rather than a
-- hunt through the logic below. Kept in-file (not a separate compat.lua) so
-- the lib stays a single self-contained module that embeds cleanly as an
-- `externals:` entry — no load-order dependency, no extra TOC file lines.
-- ===========================================================================

-- Retail (Mainline) differs from every Classic flavor in the two ways this lib
-- cares about: GetGuildRosterInfo iteration is filtered by the guild panel's
-- SetGuildRosterShowOffline toggle, and CHAT_MSG_SYSTEM payloads become
-- protected "secret" values during chat-messaging lockdown. Both are gated on
-- this flag. Patch 12.0.1 brought C_ChatInfo.InChatMessagingLockdown to the
-- Classic clients too, but only retail flags CHAT_MSG_SYSTEM with
-- SecretInChatMessagingLockdown — Classic payloads are never tainted — so the
-- WOW_PROJECT_MAINLINE flag, not the mere presence of the API, stays the
-- correct discriminator.
local IS_RETAIL = (WOW_PROJECT_ID == WOW_PROJECT_MAINLINE)

-- The bare global GuildRoster() was deprecated in favor of
-- C_GuildInfo.GuildRoster() and, as of 12.0.1, is gone on every flavor
-- (Blizzard's own UI calls only the namespaced form; the bare name is shimmed
-- only under the loadDeprecationFallbacks CVar). Prefer the namespace; the
-- bare-global branch is retained purely as defense for any client that still
-- exposes it. Calling a nil global would error and break the lib's
-- PLAYER_LOGIN / retry / on-join paths, so the feature-detect stays.
local function RequestGuildRoster()
    if C_GuildInfo and C_GuildInfo.GuildRoster then
        C_GuildInfo.GuildRoster()
    elseif _G.GuildRoster then
        _G.GuildRoster()
    end
end

-- ⛔ THE SHOW-OFFLINE BRACKET IS GONE. DO NOT BRING IT BACK.
--
-- BeginFullRosterScan / EndFullRosterScan used to live here. Every roster scan
-- forced the flag on, read, and put the player's value back. Both reasons it is
-- gone are decisive on their own, and the first is the one that matters:
--
-- 1. IT WAS NEVER NECESSARY. Measured in a live Classic Era client on a
--    997-member guild with the box UNTICKED:
--        GetGuildRosterShowOffline() = false, total = 997, online = 35,
--        rows actually returned by iterating 1..total = 997
--    The iteration is NOT filtered. Blizzard's own Classic guild UI says the
--    same thing by construction: GuildStatus_Update
--    (Blizzard_UIPanels_Game/Classic/FriendsFrame.lua:2902-2909) reads BOTH
--    counts and picks the iteration bound ITSELF -- `if showOffline then
--    numGuildMembers = totalMembers else numGuildMembers = onlineMembers end`.
--    That branch would be pointless if the setting filtered the data. On retail
--    the accessor has ZERO call sites in the whole live Interface tree; the
--    modern guild UI moved to the Communities API and left the setting behind.
--
-- 2. IT WAS A POSITIVE FEEDBACK LOOP. SetGuildRosterShowOffline FIRES
--    GUILD_ROSTER_UPDATE -- engine-side, measured in-game, absent from the
--    client source and from Blizzard_APIDocumentationGenerated. Two writes per
--    scan, from a function reached BY that event. FastGuildInvite reported it
--    as an FPS collapse while recruiting: 110 fps to 20 over seven minutes,
--    cleared by /reload, and only for players with the box unticked, because
--    the old bracket returned early when the flag was already on.
--
-- The standing rule from the user, said more than once: WRITING A SHARED UI
-- SETTING TO READ OUR OWN DATA IS THE WRONG SHAPE. It mutates state the player
-- owns and every other addon can read. Even if it cost nothing, it would still
-- be wrong; it did not cost nothing.
--
-- Every scan now simply iterates `1, GetNumGuildMembers()`, which is the total
-- and returns everybody.

-- Positional decode of GetGuildRosterInfo(i) — the ONLY place that depends on
-- its return-value order. Full order (still 17 values on every current flavor):
--   1 name, 2 rankName, 3 rankIndex, 4 level, 5 classDisplayName, 6 zone,
--   7 publicNote, 8 officerNote, 9 isOnline, 10 status, 11 classFileName,
--   12 achievementPoints, 13 achievementRank, 14 <retired mobile slot>,
--   15 <deprecated>, 16 guildRepStanding, 17 GUID.
-- Slot 14 was `isMobile` (connected via the WoW Companion app). The companion
-- remote was retired in 12.0.1 and Blizzard's own source now names slots 14/15
-- `_deprecated1`/`_deprecated2`, so on modern clients slot 14 is dead and
-- isMobile resolves to false. We still READ it (rather than hardcoding false)
-- so any flavor that keeps populating the slot passes through unchanged — the
-- read is nil-safe and the caller coerces `isMobile or false`.
local function ReadRosterRow(i)
    local name, rankName, rankIndex, level, _, zone, publicNote, officerNote,
          isOnline, status, classFileName, _, _, isMobile = GetGuildRosterInfo(i)
    return name, rankName, rankIndex, level, zone, publicNote, officerNote,
           isOnline, status, classFileName, isMobile
end

-- Locale-aware chat-message patterns derived from Blizzard's global format
-- strings (ERR_FRIEND_ONLINE_SS etc.). Before this, OnChatMsgSystem matched
-- hardcoded English text and silently stopped firing on every non-English
-- client (German, French, Russian, Chinese, etc.) — online/offline/join/
-- leave transitions only got picked up on the next full GUILD_ROSTER_UPDATE
-- rebuild, never in real time.
--
-- Pattern build steps:
--   1. Strip chat-hyperlink markup (|H...|h text |h) from the format string
--      so the resulting pattern matches markup-stripped messages — we strip
--      the same markup from incoming CHAT_MSG_SYSTEM messages before match.
--   2. Escape Lua-pattern specials in the literal portions.
--   3. Replace %s placeholders with non-greedy (.-) captures.
--   4. Make any brackets `[ ]` optional, so both "[Name] has come online."
--      and bare "Name has come online." forms match — Classic and retail
--      have varied historically on whether the bracketed display name
--      appears outside the link markup.
-- Blizzard's localized format strings sometimes use POSITIONAL specifiers —
-- `%1$s`, `%2$s` — for locales whose grammar wants the arguments in a different
-- order than enUS. Neither builder below understood them, and the consequence
-- was not a degraded match but NO match at all:
--
--   deDE ERR_GUILD_REMOVE_SS = "%1$s wurde von %2$s aus der Gilde gekickt."
--
-- escaped to a pattern containing a literal `%1$s`, which no rendered message
-- ever contains, and BuildChatNeedle's `%s` split never fired either, so the
-- needle became the whole format string and rejected every line. A German
-- player kicked from the guild produced no OnMemberLeft, on every version of
-- this library that has shipped. Adding the promote/demote strings — where
-- deDE is positional too — is what surfaced it.
--
-- Rewrites them to plain `%s` and reports where each declared argument ended
-- up, because the two are NOT interchangeable: the whole reason a locale uses
-- positional specifiers is that its text order differs from its argument order,
-- so capture #1 is not necessarily argument #1. Returns nil for `order` when
-- the string has no positional specifiers, which is the common case and means
-- "capture N is argument N".
-- @param formatString string
-- @return string, table|nil  the plain form, and declaredArg -> captureIndex
local function NormalizeFormatString(formatString)
    local order, seen = nil, 0
    local plain = formatString:gsub("%%(%d+)%$s", function(index)
        seen = seen + 1
        order = order or {}
        order[tonumber(index)] = seen
        return "%s"
    end)
    return plain, order
end

--- Select the capture holding the format string's argument #n.
-- @param order table|nil  the map from BuildChatPattern; nil means identity
-- @param n number         which DECLARED argument is wanted
-- @return any
local function PickArg(order, n, ...)
    return (select(order and order[n] or n, ...))
end

-- Positional specifiers are ONE of two mechanisms that put characters into a
-- format string which never appear in the rendered message. The other is the
-- client's GRAMMAR ESCAPES, and they are engine-side, so there is no Lua
-- anywhere that resolves them — they simply are not in the line by the time
-- CHAT_MSG_SYSTEM carries it. Three appear in the seven strings this library
-- builds against, in four of the eleven locales:
--
--   ruRU  |3-N(word)   decline `word` into grammatical case N
--   frFR  |2           select the article for the word that follows
--   koKR  |1a;b;       pick postposition a or b to suit the preceding word
--
-- Every one of them lands in the LONGEST literal fragment of its string, which
-- is what BuildChatNeedle takes as the needle — so the gate rejected the line
-- before the pattern was ever tried. Silent and total, exactly like the deDE
-- positional bug, reached by a different route. ruRU kicks and ruRU/frFR/koKR
-- rank changes were dead on every version that has shipped.
--
-- ⚠ WHETHER THE ESCAPES REACH LUA HAS NOT BEEN OBSERVED on a client of those
-- locales — it is inference from the shape of the tokens, and hyperlink escapes
-- (|H…|h) demonstrably DO survive, so the inference is not free. This function
-- therefore refuses to bet: it returns the resolved form AND the original, and
-- the caller tries each. Tests/locale_spec.lua asserts both readings.
--
-- The Korean case is why this returns a LIST rather than a string. Its
-- postposition is glued to the preceding argument and one of the alternatives
-- always appears, so dropping the directive is not enough — each alternative is
-- a distinct rendering and needs its own pattern.
-- @param plain string  a format string with positional specifiers normalized
-- @return table  one or more format strings, most-resolved first
local function ExpandGrammarEscapes(plain)
    local resolved = plain
        :gsub("|3%-%d+%((.-)%)", "%1")
        :gsub("|2 ", "")

    -- Expand the Korean alternation, innermost-last, so a string carrying two
    -- of them yields the full product rather than only the first site's.
    local function expandPostpositions(text)
        local prefix, alternatives, suffix = text:match("^(.-)|1([^|]*;)(.*)$")
        if not prefix then return { text } end
        local out = {}
        for _, tail in ipairs(expandPostpositions(suffix)) do
            for alternative in alternatives:gmatch("([^;]*);") do
                out[#out + 1] = prefix .. alternative .. tail
            end
        end
        return out
    end

    local variants = expandPostpositions(resolved)

    -- The unresolved reading goes FIRST, and the order is load-bearing rather
    -- than a preference. A resolved pattern is the more general of the two: its
    -- `(.-)` sits exactly where the directive would be, so it happily matches an
    -- UNRESOLVED message and captures the escape as part of the argument —
    -- "|3-3(Bob)" as a player name, "|2 Officer" as a rank. That is worse than
    -- not matching, because it looks like a hit. The unresolved pattern carries
    -- the escape as a literal, so it can only match a line that really contains
    -- it, and trying it first costs one failed match on a normal client.
    if plain:find("|3%-%d+%(") or plain:find("|1[^|]*;") or plain:find("|2 ", 1, true) then
        table.insert(variants, 1, plain)
    end
    return variants
end

-- @return table|nil, table|nil  the patterns to try IN ORDER, and the argument
--                               order (see NormalizeFormatString) for callers
--                               that read more than the first capture
local function BuildChatPattern(formatString)
    if not formatString or formatString == "" then return nil end
    local plain, order = NormalizeFormatString(formatString)
    local patterns = {}
    for _, variant in ipairs(ExpandGrammarEscapes(plain)) do
        local stripped = variant
            :gsub("|H[^|]*|h", "")
            :gsub("|h", "")
        local pattern = stripped
            :gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
            :gsub("%%%%s", "(.-)")
        pattern = pattern
            :gsub("%%%[", "%%[?")
            :gsub("%%%]", "%%]?")
        patterns[#patterns + 1] = "^" .. pattern .. "$"
    end
    return patterns, order
end

--- Try each of a format string's patterns and return the first one's captures.
-- @param patterns table|nil  from BuildChatPattern
-- @param text string
-- @return string|nil, string|nil, string|nil
local function MatchAny(patterns, text)
    if not patterns then return nil end
    for i = 1, #patterns do
        local a, b, c = text:match(patterns[i])
        if a then return a, b, c end
    end
    return nil
end

-- Cheap relevance "needle" for a format string: the longest literal run left
-- after removing chat-link markup, the %s placeholders, and any bracket chars
-- that sit against a removed name (the brackets are optional in the rendered
-- message, so they can't be part of the needle). Used as a plain (non-pattern)
-- string.find pre-filter in ParseSystemMessage so the bulk of CHAT_MSG_SYSTEM
-- traffic is rejected without stripping markup or running an anchored capture.
-- Because the needle is a substring of every message its BuildChatPattern
-- accepts, gating on it can never drop a line the pattern would have matched.
-- Returns nil when no literal can be derived, in which case the caller falls
-- back to always attempting the match.
local function BuildChatNeedle(formatString)
    if not formatString or formatString == "" then return nil end
    -- Positional specifiers are normalized here too, and for a sharper reason
    -- than in the pattern builder: the split below looks for a literal `%s`, so
    -- a format string written with `%1$s` produces no split at all and the
    -- "longest literal fragment" becomes the ENTIRE format string. That needle
    -- is never a substring of a rendered message, so the gate rejects every
    -- line — a silent, total failure rather than a loose match.
    -- Grammar escapes are treated as PLACEHOLDER BOUNDARIES, not as literals to
    -- delete, and the difference is what keeps the needle sound. `|3-N(x)`
    -- resolves to its own content and `|2 ` to nothing, so those can collapse;
    -- but the Korean alternation renders as one of several strings, and a
    -- fragment spanning it would only be a substring of the message when that
    -- alternative happened to be chosen. Splitting there instead gives a needle
    -- drawn from text every rendering carries — including, deliberately, the
    -- reading where the escape survives literally, since the escape always sits
    -- OUTSIDE the fragment either way. See ExpandGrammarEscapes.
    local stripped = (NormalizeFormatString(formatString))
        :gsub("|3%-%d+%((.-)%)", "%1")
        :gsub("|2 ", "")
        :gsub("|1[^|]*;", "%%s")
        :gsub("|H[^|]*|h", "")
        :gsub("|h", "")
    local longest = ""
    for fragment in (stripped .. "%s"):gmatch("(.-)%%s") do
        fragment = fragment:gsub("^[%[%]]+", ""):gsub("[%[%]]+$", "")
        if #fragment > #longest then longest = fragment end
    end
    if longest == "" then return nil end
    return longest
end

local function StripChatLinkMarkup(message)
    return (message:gsub("|H[^|]*|h", ""):gsub("|h", ""))
end

local CHAT_PATTERNS_ONLINE  = BuildChatPattern(ERR_FRIEND_ONLINE_SS)
local CHAT_PATTERNS_OFFLINE = BuildChatPattern(ERR_FRIEND_OFFLINE_S)
local CHAT_PATTERNS_JOINED  = BuildChatPattern(ERR_GUILD_JOIN_S)
local CHAT_PATTERNS_LEFT    = BuildChatPattern(ERR_GUILD_LEAVE_S)
local CHAT_PATTERNS_KICKED, ARGS_KICKED = BuildChatPattern(ERR_GUILD_REMOVE_SS)

-- Rank changes, added in MINOR 14 because build-once removed the rebuild diff
-- that used to be OnMemberRankChanged's only source.
--
--   ERR_GUILD_PROMOTE_SSS = "%s has promoted %s to %s."
--   ERR_GUILD_DEMOTE_SSS  = "%s has demoted %s to %s."
--
-- Three arguments: the officer who acted, the member whose rank moved, and the
-- NAME of the new rank. We want arguments 2 and 3.
--
-- These are server-formatted CHAT_MSG_SYSTEM messages, which is why they have
-- zero call sites anywhere in the client's Interface tree — and so do
-- ERR_GUILD_JOIN_S, ERR_GUILD_LEAVE_S and ERR_GUILD_REMOVE_SS, the three this
-- library has matched successfully since it was written. Zero call sites is the
-- normal state for this whole class of string and was never evidence of absence;
-- an earlier session read it as "inconclusive" and left rank changes unwired.
local CHAT_PATTERNS_PROMOTED, ARGS_PROMOTED = BuildChatPattern(ERR_GUILD_PROMOTE_SSS)
local CHAT_PATTERNS_DEMOTED,  ARGS_DEMOTED  = BuildChatPattern(ERR_GUILD_DEMOTE_SSS)

-- The server's answer to a whisper at somebody who is not online, added in
-- MINOR 19 as the ONLY thing that retires a sister member's presence stamp
-- early. The sister pull is a handshake over WHISPER (see PullSisterRoster):
-- a request either gets an answer, or the server says this -- and that is an
-- event, which a timeout is not. The user, 2026-09-15: "TIMERS are fragile
-- ... they can't account for latency, congestion or other things" / "if you
-- try to whisper someone that is offline, you'll get screamed at". This is
-- the scream. Blizzard's own chat frame matches the same string against its
-- whisper targets (Classic ChatFrameOverrides.lua:258).
--
--   ERR_CHAT_PLAYER_NOT_FOUND_S = "No player named '%s' is currently playing."
local CHAT_PATTERNS_NOTFOUND = BuildChatPattern(ERR_CHAT_PLAYER_NOT_FOUND_S)

--- How many of the eight chat patterns actually built, out of CHAT_PATTERNS_TOTAL.
--
-- BuildChatPattern returns nil for an absent or empty format string, and every
-- branch is guarded `if CHAT_PATTERNS_X and ...`, so a client missing an ERR_*
-- global degrades to a branch that is permanently silent with nothing to see.
-- This turns "this client cannot detect kicks" from invisible into one integer.
--
-- ⚠ WHAT THIS DOES AND DOES NOT CATCH, because it was declined once for exactly
-- this reason and the reasoning should not be lost. It catches an ABSENT
-- global. It does NOT catch a pattern that builds and never matches, which is
-- the failure audit finding 14 was about -- all seven strings are present and
-- non-empty in all eleven shipped locale files, so this counter read 7/7 on a
-- Russian client for the entire time ruRU kicks were dead. The locale
-- round-trip suite is what covers that; this covers the other thing.
--
-- Read it as `LibStub("LibGuildRoster-1.0").chatPatternsBuilt`.
-- ⛔ NUMERIC LOOP, NOT ipairs, AND THAT IS THE WHOLE POINT OF THIS BLOCK.
-- `ipairs` stops at the FIRST nil, and a nil is exactly what is being counted:
-- with a hole in the middle it would stop early and under-report by more than
-- the one missing pattern. A counter that miscounts precisely when there is
-- something to count is worse than no counter. Fixed slot count, numeric loop.
--
-- ⚠ THE SLOT COUNT IS DERIVED, NOT DECLARED, AND THAT IS DELIBERATE. The count
-- used to be a literal `7` sitting beside a seven-entry probe table -- one
-- constant in two places with nothing asserting they agree. Adding an eighth
-- chat message and forgetting the literal would leave the loop reading slots
-- 1..7, ignoring the new one, and reporting a perfectly healthy "7/7" forever.
-- A counter that reads full while silently omitting a slot is worse than no
-- counter, which is the same reasoning as the ipairs note below.
--
-- SLOT_NAMES is the single source: it has no nil holes (they are strings), so
-- `#` is well-defined on it, and both the total and the loop bound come from
-- it. A name added here without a matching entry in `builtProbe` counts as
-- UNBUILT and shows up as `7/8` -- a visible false alarm rather than an
-- invisible false all-clear, which is the right way round to fail.
local SLOT_NAMES = {
    "ONLINE", "OFFLINE", "JOINED", "LEFT", "KICKED", "PROMOTED", "DEMOTED", "NOTFOUND",
}
lib.CHAT_PATTERNS_TOTAL = #SLOT_NAMES
local builtProbe = {
    ONLINE   = CHAT_PATTERNS_ONLINE,
    OFFLINE  = CHAT_PATTERNS_OFFLINE,
    JOINED   = CHAT_PATTERNS_JOINED,
    LEFT     = CHAT_PATTERNS_LEFT,
    KICKED   = CHAT_PATTERNS_KICKED,
    PROMOTED = CHAT_PATTERNS_PROMOTED,
    DEMOTED  = CHAT_PATTERNS_DEMOTED,
    NOTFOUND = CHAT_PATTERNS_NOTFOUND,
}
lib.chatPatternsBuilt = 0
for i = 1, lib.CHAT_PATTERNS_TOTAL do
    if builtProbe[SLOT_NAMES[i]] then
        lib.chatPatternsBuilt = lib.chatPatternsBuilt + 1
    end
end

-- Plain-text relevance needles paired with the patterns above (see
-- BuildChatNeedle). Each is a substring of every message its pattern accepts,
-- so a string.find for it is a sound, much cheaper pre-filter than the match.
local NEEDLE_ONLINE  = BuildChatNeedle(ERR_FRIEND_ONLINE_SS)
local NEEDLE_OFFLINE = BuildChatNeedle(ERR_FRIEND_OFFLINE_S)
local NEEDLE_JOINED  = BuildChatNeedle(ERR_GUILD_JOIN_S)
local NEEDLE_LEFT    = BuildChatNeedle(ERR_GUILD_LEAVE_S)
local NEEDLE_KICKED  = BuildChatNeedle(ERR_GUILD_REMOVE_SS)
local NEEDLE_PROMOTED = BuildChatNeedle(ERR_GUILD_PROMOTE_SSS)
local NEEDLE_DEMOTED  = BuildChatNeedle(ERR_GUILD_DEMOTE_SSS)
local NEEDLE_NOTFOUND = BuildChatNeedle(ERR_CHAT_PLAYER_NOT_FOUND_S)

-- What the sister sync last DID, for the window's status bar. The user,
-- 2026-09-15, unable to tell a stalled sync from a quiet one: "can you add a
-- syncing status into the status bar so i can see if it may be doing stuff
-- and i just can't tell". One entry, overwritten: `{ text, at }`, stamped on
-- every send and every receive the sync makes (and on the server's
-- not-online answer), read by GetSyncStatusText. Defined here, ahead of the
-- chat handler that is its earliest caller; `lib.sisterSync` exists by the
-- time anything runs.
-- Kept as a short ring as well as `lastEvent`, because the status bar shows
-- only the last one and truncates it -- "last: the serv..." was all the user
-- could see of why a /who produced nobody (2026-09-15). The diagnostics
-- print the ring in full.
lib.SYNC_EVENT_RING = 8

-- "Faction-Guild Name" -> "Guild Name", for status lines.
local function guildNameOf(guildKey)
    return (tostring(guildKey):match("^[^%-]+%-(.+)$")) or tostring(guildKey)
end

local function syncEvent(self, fmt, ...)
    local ss = self.sisterSync
    local ev = { text = string.format(fmt, ...), at = GetTime() }
    ss.lastEvent = ev
    ss.events = ss.events or {}
    ss.events[#ss.events + 1] = ev
    while #ss.events > lib.SYNC_EVENT_RING do table.remove(ss.events, 1) end
end

-- ---------------------------------------------------------------------------
-- The member on the wire, and the states a delta is computed from. Up here,
-- ahead of the two hash-change sites (the login build's and SetSisterRoster's)
-- that snapshot through them.
-- ---------------------------------------------------------------------------

-- { n = charKey, c = class, l = level, pn = publicNote, rn = rankName,
-- ri = rankIndex } -- `pn` omitted when empty (MINOR 19, LIBREQ-GR-002), `rn`
-- and `ri` omitted when absent (MINOR 21). Both senders build entries here and
-- both receivers read them with wireToFeed, so the two wires cannot drift apart.
-- The type tests are the same ones GetRosterRankHash applies, so what a
-- provider hashes is exactly what it sends.
local function wireMember(charKey, class, level, note, rankName, rankIndex)
    local e = { n = charKey, c = class, l = level }
    if type(note) == "string" and note ~= "" then e.pn = note end
    if type(rankName) == "string" and rankName ~= "" then e.rn = rankName end
    if type(rankIndex) == "number" then e.ri = rankIndex end
    return e
end

-- A roster in wire shape, sorted by name so two clients holding the same
-- membership build the same array -- DeltaSync's engine diffs arrays and
-- keys them by `n`, and a stable order keeps its work and its output small.
-- `noteField` is `publicNote` on a home record and `note` on a sister one;
-- rank is `rankName` / `rankIndex` on both.
local function toWire(roster, noteField)
    local out = {}
    for charKey, m in pairs(roster) do
        out[#out + 1] = wireMember(charKey, m.class, m.level, m[noteField], m.rankName, m.rankIndex)
    end
    table.sort(out, function(a, b) return a.n < b.n end)
    return out
end

-- THE STATES A DELTA CAN BE COMPUTED FROM. Every membership this client has
-- held -- its own guild's, and every sister roster -- is snapshotted in wire
-- shape under its hash the moment that hash changes, in a ring of the last
-- STATE_RING states. A requester sends the hash it holds; if that hash is
-- one we passed through, DeltaSync's ComputeArrayDelta between that snapshot
-- and now is the answer, and it is a few hundred bytes instead of tens of
-- kilobytes. The user, 2026-09-15: "this is a lot of data we'll be moving,
-- and once the initial bulk is sent, shouldn't we be using deltasync?" A
-- hash we never passed through -- the requester's copy predates our login,
-- or came from a member whose history differs -- gets the full roster.
--
-- Keyed by hash alone, across guilds: the hash is over the sorted charKey
-- set, and two guilds' sets do not collide. `order` is the eviction queue.
local STATE_RING = 8
local function rememberState(self, hash, wire)
    if not hash then return end
    local states = self.sisterSync.states
    if not states then
        states = { byHash = {}, order = {} }
        self.sisterSync.states = states
    end
    if states.byHash[hash] then return end
    states.byHash[hash] = wire
    states.order[#states.order + 1] = hash
    while #states.order > STATE_RING do
        local old = table.remove(states.order, 1)
        states.byHash[old] = nil
    end
end

-- The engine, when it is there. Looked up per call: DeltaSync's TOC depends
-- on this library, so it loads AFTER us and can never be a dependency of
-- ours -- but nothing here runs at load, so by the time a pull is served or
-- applied it is either registered or absent, and absent means full pulls.
local function deltaEngine()
    local DS = LibStub("DeltaSync-1.0", true)
    if DS and DS.ComputeArrayDelta and DS.ApplyArrayDelta then return DS end
    return nil
end
local DELTA_OPTS = { keyFunc = function(o) return o.n end, keyFields = { "n" } }

-- Roster: { ["Name-Realm"] = member } where member has the fields documented
-- in the file header (name, class, level, rankIndex, rankName, isOnline,
-- zone, publicNote, officerNote, status, isMobile, lastOnline).
lib.roster      = lib.roster or {}
lib.realmName   = lib.realmName or nil       -- cached, set on PLAYER_LOGIN
lib.initialized = lib.initialized or false   -- true after stabilization completes
lib.retryCount  = lib.retryCount or 0
lib.MAX_RETRIES = 5

-- The login build is allowed to be SHORT and then FINISHED, at most this many
-- times per guild. See LoginBuildIsShort for what "short" means and why a cap
-- is needed at all. Not a rebuild budget: a repair only runs when the server's
-- member total exceeds what we hold, which a healthy session never sees.
lib.loginRepairs      = lib.loginRepairs or 0
lib.MAX_LOGIN_REPAIRS = 3
-- The one post-ready roster request (see the stabilization block), and how
-- long after ready it goes out -- past the server's 10 s request throttle.
lib.loginVerified     = lib.loginVerified or false
lib.LOGIN_VERIFY_DELAY = 15

-- FGI vendor fix: stabilization-based snapshot lock for OnRosterReady.
-- On retail the roster streams in across multiple GUILD_ROSTER_UPDATE
-- events after PLAYER_LOGIN, /reload, and any RequestGuildRoster call.
-- The wasInitialized flag gates OnMemberOnline (so existing members at
-- login don't all look like fresh come-online events) and the
-- OnRosterReady callback that consumers use as "you can now trust
-- IsInGuild / GetMember etc.". We require STABLE_THRESHOLD consecutive
-- rebuilds with the same member total before flipping initialized so
-- OnRosterReady doesn't fire on a partial-roster snapshot.
--
-- The streaming roster used to also misfire OnMemberJoined (event 1
-- captured 50 partial members, event 2's full 200 looked like 150
-- joins, consumers welcomed every guildie). That path is gone -- joins
-- now fire only from CHAT_MSG_SYSTEM "X has joined the guild", which
-- is the authoritative server signal and can't be confused by partial
-- roster snapshots. See the chat handler for the join logic.
lib.stableCount      = lib.stableCount or 0
lib.previousTotal    = lib.previousTotal or 0
lib.STABLE_THRESHOLD = 2

-- FGI vendor fix: recently-left dedup so a stale GUILD_ROSTER_UPDATE
-- response (server still listing the leaver right after CHAT_MSG_SYSTEM
-- "X has left" arrived and the lib removed them) doesn't re-add them
-- and then fire OnMemberJoined for the just-departed player. The
-- OnChatMsgSystem "left" handler stamps the name into this set; the
-- post-rebuild diff seeds wasOnline from this set so the leaver is
-- treated as "existing" in the diff, suppressing the spurious join
-- fire. TTL is generous (60 s) because stale-roster races in practice
-- resolve in a few seconds; a too-tight window would still occasionally
-- miss. Legitimate rejoin within 60 s is the only side effect: that
-- specific rejoin won't fire OnMemberJoined. Considered acceptable —
-- guild rejoins within a minute are vanishingly rare.
lib.recentlyLeft     = lib.recentlyLeft or {}
lib.RECENTLY_LEFT_TTL = 60

-- The symmetric set, and the reason it exists is worth stating because the
-- asymmetry is not obvious: recentlyLeft protects a REMOVAL from a stale
-- roster response, and nothing protected a PRESENCE change until MINOR 13.
--
-- A real-time signal (CHAT_MSG_SYSTEM "has come online", or guild/officer chat
-- traffic, which can only ever prove online) sets member.isOnline and fires
-- OnMemberOnline. A GUILD_ROSTER_UPDATE whose row for that member is still
-- stale then wrote isOnline = false with NO callback — the diff has no offline
-- branch — so the library reported IsOnline() == false having just told every
-- consumer the opposite, and the NEXT rebuild carrying a fresh row saw
-- wasOnline == false with isOnline true and fired OnMemberOnline a SECOND time
-- for one login. Nothing closed the window: the chat handlers deliberately do
-- not call RequestGuildRoster, so it lasted until something else asked.
--
-- That duplicate is not theoretical — TOGProfessionMaster's OnCrafterCameOnline
-- raises a user-facing alert and carries no per-character dedup, so one login
-- produced two alerts minutes apart. Six consumers register the callback and
-- none of them dedups, which is the strongest available evidence that
-- at-most-once per real transition is what the contract ought to promise.
--
-- So the stamp says "we acted on a real-time signal; do not let a stale
-- response contradict it", exactly as recentlyLeft does for a removal, and the
-- rebuild keeps such a member online for the TTL. The bias is deliberate and
-- in the cheap direction: a false ONLINE costs a wasted comm attempt, while a
-- false OFFLINE makes DeltaSync skip a player who is actually there and the
-- data never propagates.
--
-- A chat-proven LOGOFF clears the stamp — that is a real-time signal too, and
-- a newer one, so it must win rather than be suppressed by this.
lib.recentlyOnline     = lib.recentlyOnline or {}
lib.RECENTLY_ONLINE_TTL = 60

-- Joiners whose roster ROW we have not read yet, stamped with the time the join
-- was announced.
--
-- "X has joined the guild" carries a NAME and nothing else — no class, no level,
-- no rank — and under build-once no later rebuild will supply them. So the join
-- branch inserts the member immediately from what chat proved (they are in the
-- guild, and they are online), records the key here, and the next
-- GUILD_ROSTER_UPDATE reads the rows ONCE to fill in the rest. That single pass
-- costs ~1.3 ms on a 978-member roster against ~27 ms for the allocating
-- rebuild it replaces, and it runs only while a join is actually outstanding —
-- which is why it is a targeted read and not a rebuild wearing a different name.
--
-- Stamped rather than a bare `true` because the pass has to be able to GIVE UP.
-- A joiner the server has not yet added to the roster response is not found, and
-- without a deadline the library would re-scan the whole roster on every
-- GUILD_ROSTER_UPDATE forever — reinstating exactly the per-event O(N) cost
-- build-once exists to remove, and doing it invisibly. After the TTL the member
-- simply keeps the defaults the join branch wrote; their level stays recorded as
-- invented, so the give-up can never manufacture a phantom level-up.
lib.pendingDetail      = lib.pendingDetail or {}
lib.PENDING_DETAIL_TTL = 60

-- rankName -> rankIndex, learned from the roster rows we already read.
--
-- The promote/demote system messages name the new rank ("...to Officer") while
-- OnMemberRankChanged has always carried rank INDICES, so something has to
-- translate. Every roster row carries both halves, so building this during the
-- login build costs one table store per member and no extra API call.
--
-- The gap, stated because it is real and not worth hiding: a rank that NOBODY
-- currently holds is not in this map, so a promotion into an empty rank cannot
-- be translated. The library updates member.rankName — which is always correct,
-- it came from the message — and stays silent on the callback rather than
-- inventing an index. The alternative, GuildControlGetRankName, belongs to the
-- guild-control UI and is not verified readable by a rank-and-file member on
-- Classic Era, so it is not used here on the strength of a guess.
lib.rankIndexByName = lib.rankIndexByName or {}


-- Names whose `level` we had to invent because the roster row arrived without
-- one and we had no previous value to carry forward. `member.level` is part of
-- the public shape and must always be a number, so the rebuild writes 1 — but
-- that 1 must never become the baseline for a level diff, or the next rebuild
-- (when the real level finally arrives) reports a phantom 1 -> 60. This set is
-- how the diff tells an invented level from a real one. Per-guild transient
-- state: wiped alongside recentlyLeft when the guild changes.
lib.levelUnknown     = lib.levelUnknown or {}

-- Cross-guild (sister-roster) support, added in MINOR 6.
--
-- `lib.roster` above stays the single authoritative, self-scanned HOME
-- roster — every existing method reads it unchanged, so home-only consumers
-- (and the older embedded copies that win no load race) behave exactly as
-- before. The tables below are purely additive and only the new scoped
-- methods touch them.
--
-- `rosters[guildKey]` holds externally-fed SISTER rosters (a player in two
-- "sister" guilds wants the other guild's membership). They are fed by a
-- higher layer via SetSisterRoster with wipe-and-replace semantics, which
-- preserves the lib's "stale ex-members are impossible" guarantee. guildKey
-- is "Faction-GuildName" (see GetHomeGuildKey); charKeys are the same
-- "Name-Realm" form NormalizeName produces for the home roster.
--
-- `presence[guildKey]` is a SEPARATE liveness overlay — { charKey = GetTime()
-- stamp }. It is deliberately not stored inside the member tables because
-- SetSisterRoster is wipe-and-replace: a membership resync (which is exactly
-- when a roster is re-fed) must not blow away presence. Decoupling the two
-- lifetimes is the whole point of presence being an "overlay". MarkOnline
-- stamps it; GetOnlineMembersScoped reads membership ∩ fresh-presence. We
-- never assert "offline" — the upstream presence source is sampled and
-- capped, so presence simply ages out past PRESENCE_TTL and self-corrects.
-- THAT AGEING ONLY HOLDS BECAUSE A RELAYED SIGHTING CARRIES ITS AGE (MINOR
-- 22): the relay used to carry bare names, each receiver stamped them at
-- receive time, and two holders relaying every 270 s kept a member "online"
-- indefinitely after one real sighting (TOGBankClassic's peer review
-- 653048d5688e, 2026-09-17). See MarkOnline and freshPresence.
--
-- `rosterMeta[guildKey]` is opaque caller metadata (provider charKey,
-- snapshot timestamp, ...) — stored by SetSisterRoster and read back via
-- GetRosterMeta, never interpreted here.
--
-- `rosterHashes` / `homeRosterHash` cache the last membership hash we fired
-- OnRosterHashChanged for, per roster, so the callback only fires when the
-- membership SET actually changes (not on every presence-only update).
--
-- `homeGuildKey` caches GetHomeGuildKey's result (mirrors realmName); it is
-- cleared on the not-in-guild wipe so a guild switch re-resolves cleanly.
lib.rosters        = lib.rosters or {}
lib.presence       = lib.presence or {}
lib.rosterMeta     = lib.rosterMeta or {}
lib.rosterHashes   = lib.rosterHashes or {}
lib.homeRosterHash = lib.homeRosterHash or nil
lib.homeGuildKey   = lib.homeGuildKey or nil
-- Sister presence freshness window, in seconds. Was 120 until MINOR 18, sized
-- for a consumer's /who poll that no consumer ever ran. The library owns
-- presence now and its sources are proven sightings from the wire (see the
-- sister-sync section), which are sparser; the window must outlast
-- SISTER_PULL_INTERVAL or the provider of one pull is stale before the next.
lib.PRESENCE_TTL   = 900

-- Alt groups (MINOR 17) -- "which characters share one account".
--
-- `altGroups[ownerKey]` is a SORTED array of charKeys; `altOwners[charKey]` is
-- the derived reverse index, maintained by SetAltGroup/RemoveAltGroup so a
-- lookup is O(1) instead of a scan over every group.
--
-- THE OWNER KEY IS A KEY, NOT A "MAIN". It is whichever character the consumer
-- filed the group under -- in practice the broadcaster, because that is the
-- only client entitled to state who its own alts are. This library has no way
-- to know which character a player mains and does not claim to; a consumer
-- wanting a display name picks one itself. Ported deliberately from
-- TOGProfessionMaster, whose `gdb.altClaims` is keyed the same way and carries
-- no main concept either.
--
-- NOT per-guild and NOT wiped on a guild change: an alt group is a statement
-- about an ACCOUNT, and the alts need not be in any roster (protecting a bank
-- alt of an in-guild main is the case this exists for). It IS in-memory only,
-- like everything else here -- the consumer re-feeds it each session.
--
-- `altGroupMeta[ownerKey]` is the opaque provenance blob the feeding consumer
-- passed to SetAltGroup, or nil. The library NEVER reads inside it -- same
-- contract as the sister-roster meta above, and it exists because the alt store
-- is deliberately SHARED: several addons in one client read one answer, so
-- several can write it, and without a stamp no feeder can tell its own claim
-- from somebody else's. Requested by FastGuildInvite (docs/LIBRARY_CONTRACTS.md
-- request 2). Storing it is all we do; WHICH claim wins is still the consumer's
-- call, because deciding needs clocks and sync state this library does not hold.
--
-- `altGroupSeen[ownerKey]` is INTERNAL and never exposed: the highest `setAt`
-- ever accepted for that owner. It exists because an unstamped write clears
-- `altGroupMeta` (deliberately -- see SetAltGroup), and the staleness check
-- would then have nothing to compare against, so a single write from a
-- not-yet-adopted addon would disarm the protection for every adopted one.
-- A bare number, not the caller's table: how far we have got is ours to know,
-- attributing a version is the caller's to state.
lib.altGroups      = lib.altGroups or {}
lib.altOwners      = lib.altOwners or {}
lib.altGroupMeta   = lib.altGroupMeta or {}
lib.altGroupSeen   = lib.altGroupSeen or {}

-- Re-register events cleanly on upgrade
if lib.frame then
    lib.frame:UnregisterAllEvents()
else
    lib.frame = CreateFrame("Frame", "LibGuildRoster10Frame")
end
lib.frame:RegisterEvent("PLAYER_LOGIN")
lib.frame:RegisterEvent("GUILD_ROSTER_UPDATE")
lib.frame:RegisterEvent("CHAT_MSG_SYSTEM")
-- Guild and officer chat are a free presence signal: a message can only arrive
-- from someone who is online right now. See OnChatMsgGuild.
lib.frame:RegisterEvent("CHAT_MSG_GUILD")
lib.frame:RegisterEvent("CHAT_MSG_OFFICER")
-- Every mailbox visit re-checks the Send Mail autocomplete hook; see
-- InstallMailAutocomplete for why once is not enough.
lib.frame:RegisterEvent("MAIL_SHOW")
-- The server's answer to a /who, and the end of combat (when the click-catching
-- overlay's propagation can be applied); see the who-discovery section.
lib.frame:RegisterEvent("WHO_LIST_UPDATE")
lib.frame:RegisterEvent("PLAYER_REGEN_ENABLED")
-- A flavour that loads Blizzard_Communities on demand builds the guild window
-- after our login; see InstallGuildTab.
lib.frame:RegisterEvent("ADDON_LOADED")
lib.frame:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LOGIN" then
        lib:OnPlayerLogin()
        -- Every addon has loaded by now, VersionCheck-1.0 included (its TOC
        -- depends on us, so it can never be looked up at our load).
        lib:RegisterWithVersionCheck()
    elseif event == "MAIL_SHOW" then
        lib:InstallMailAutocomplete()
    elseif event == "ADDON_LOADED" then
        if ... == "Blizzard_Communities" then lib:InstallGuildTab() end
    elseif event == "WHO_LIST_UPDATE" then
        lib:OnWhoListUpdate()
    elseif event == "PLAYER_REGEN_ENABLED" then
        lib:ShowWhoOverlay()
    elseif event == "GUILD_ROSTER_UPDATE" then
        lib:OnGuildRosterUpdate(...)
    elseif event == "CHAT_MSG_SYSTEM" then
        lib:OnChatMsgSystem(...)
    elseif event == "CHAT_MSG_GUILD" or event == "CHAT_MSG_OFFICER" then
        lib:OnChatMsgGuild(...)
    end
end)

--- Get this client's own realm name, in the normalized spelling.
--
-- CORRECTED 2026-08-26. This comment used to say GetNormalizedRealmName()
-- "returns the canonical cluster realm name", and that is WRONG. It returns
-- THIS PLAYER'S OWN realm with spaces and hyphens stripped -- a spelling
-- normalization, not a cluster collapse. Two players on different realms of one
-- connected-realm cluster get DIFFERENT strings from it.
--
-- The evidence, since the client source cannot settle behaviour: the wikis
-- describe it as the current realm without spaces or hyphens, the only call
-- site in any flavour tree uses it as the viewer's own realm
-- (Blizzard_UnitPopup/Classic/UnitPopupUtils.lua:92 compares
-- `GetNormalizedRealmName() ~= server` to detect a cross-realm character), and
-- GetAutoCompleteRealms() exists to return the cluster as an ARRAY of
-- normalized names -- which would be pointless if the cluster had one name.
--
-- WHY THE CORRECTION MATTERS RATHER THAN BEING PEDANTRY: the old wording is an
-- argument that NormalizeName is safe on wire data, because if every client in
-- a guild resolved the same realm string then appending it could not diverge.
-- It can and does diverge, which is exactly what CanonName and the alt-group
-- storage rules exist for. Believing the old comment would justify deleting
-- them. See the alt-group section and Tests/altgroup_spec.lua's cross-realm
-- block, which reproduces the divergence on demand.
--
-- What it IS right for: a name read from a LOCAL client API is bare only when
-- the character is on the viewer's own realm, so appending this is a correct
-- inference there. That is NormalizeName's whole contract.
function lib:GetRealmName()
    if not self.realmName then
        self.realmName = GetNormalizedRealmName()
    end
    return self.realmName
end

--- Canonicalize a name's REPRESENTATION, without ever supplying a realm.
--
-- The counterpart to NormalizeName: identical string cleaning, but a bare name
-- comes back bare. Use it for any name whose realm context is not knowable —
-- above all one that arrived over the wire, where appending the receiver's
-- realm yields a different identity on every client of a connected-realm
-- cluster and there is no way back to the original.
--
-- Deliberately does NOT map "unknown" to "Unknown" the way NormalizeName does.
-- That check is a hardcoded English literal, so it never fires on a localized
-- client — which makes the result depend on the running locale rather than
-- guarding against anything. Callers that must reject an unresolved name do it
-- at the point of authorship, where the placeholder is actually recognizable.
--
-- @param name any
-- @return string|nil  nil for nil, a non-string, an empty/whitespace-only
--                     name, or a name whose portion before the hyphen is empty
function lib:CanonName(name)
    -- A non-string is rejected rather than coerced. tostring(123) would yield
    -- "123", and appending a realm to it produced a well-formed-LOOKING key
    -- that is pure garbage — it then sits in a consumer's store indefinitely
    -- instead of erroring where the bad value entered.
    if type(name) ~= "string" then return nil end

    -- Trim leading/trailing whitespace
    local trimmed = string.gsub(name, "^%s+", "")
    trimmed = string.gsub(trimmed, "%s+$", "")
    if trimmed == "" then return nil end

    -- Drop a stray ":". Defensive only: no consumer has named a source that
    -- produces one, and a colon is not legal in a character name, so removing
    -- it can only ever repair a malformed string.
    trimmed = string.gsub(trimmed, ":", "")

    -- Canonicalize hyphen spacing BEFORE matching the halves — "Name - Realm"
    -- must not leave the trailing space bound into the name half, which is
    -- exactly how "Thrall - Fairbanks" and "Thrall-Fairbanks" end up as two
    -- different identities.
    local normalized = string.gsub(trimmed, "%s*%-%s*", "-")
    if normalized == "" then return nil end

    local left, right = string.match(normalized, "^(.-)%-(.-)$")
    if left and right then
        if left == "" then return nil end
        if right ~= "" then
            -- Squash any internal whitespace in the realm portion so an
            -- externally-fed "Name-Argent Dawn" matches a self-scanned
            -- "Name-ArgentDawn". This is a no-op for the home path
            -- (GetGuildRosterInfo realms are already spaceless) and for
            -- already-normalized fed charKeys; it exists purely as
            -- defense-in-depth for the cross-guild SetSisterRoster feed,
            -- where a mismatched realm spelling would silently fail every
            -- cross-roster lookup. GetNormalizedRealmName never produces
            -- internal spaces, so nothing legitimate is altered.
            right = string.gsub(right, "%s+", "")
            return left .. "-" .. right
        end
        -- has a trailing hyphen but no realm — treat as short name
        return left
    end

    return normalized
end

--- Normalize a player name to "Name-Realm" format.
-- Matches TOGBank's NormalizePlayerName defensive guards:
--   - rejects nil, non-strings and empty/unknown names
--   - canonicalizes hyphen spacing ("Name - Realm" -> "Name-Realm")
--   - appends the connected-realm name if none is present
--
-- The string cleaning is CanonName's; this adds only the two things that make
-- it a producer rather than a canonicalizer. Delegating rather than keeping a
-- parallel implementation is deliberate — two copies of this logic is the
-- defect that made a consumer reimplement it locally in the first place.
--
-- Appending the realm is a correct INFERENCE, not a fabrication, for its
-- intended input: a locally-read bare name belongs to the viewer's own realm.
-- It is wrong only for names that crossed the wire — those want CanonName.
-- Memoization cache for NormalizeName, keyed on the RAW input string.
--
-- Measured, not assumed: a full roster pass on a 978-member guild cost ~27ms on
-- high-end hardware, of which the raw GetGuildRosterInfo reads were 1.31ms. Most
-- of the remainder was this function — six gsub calls and a match per member,
-- each allocating a string, ~5,900 of them per pass. The inputs are the same 978
-- names every time, so the whole thing collapses to a table lookup.
--
-- Two things make the cache safe rather than a stale-data bug:
--
--   * The result depends on the connected-realm name (it is appended to a bare
--     name), and that resolves from nil to a real value shortly after login. So
--     the realm it was built under is stored alongside it and the cache is
--     dropped whenever that changes, rather than serving pre-realm answers
--     forever.
--   * It is created fresh on load rather than with the `or {}` idiom the rest of
--     this file uses for state. A LibStub upgrade that changed the normalization
--     rules must not inherit results computed under the old ones — and a pure
--     cache loses nothing by being rebuilt.
-- The ceiling exists because NormalizeName is PUBLIC and a library cannot bound
-- its own input. Nine methods feed it — NormalizeName, IsOfficer, IsInGuild,
-- IsOnline, GetMember, IsInAnyRoster, IsInGuildScoped, SetSisterRoster and
-- MarkOnline — and the last two normalize names that arrived over the addon
-- channel from a peer, which nothing here validates against a roster. A name
-- that matches nothing is cached just the same, so "the population is guild-
-- sized" is a claim about consumer behaviour, not a property of this code.
--
-- Checked rather than assumed for the one consumer that looked dangerous:
-- TOGBankClassic normalizes strings parsed out of chat message bodies, but its
-- TOGBankClassic_Guild:NormalizeName forwards to its own local
-- NormalizePlayerName (Modules/Guild.lua:171-180), not to this library, so
-- those never reach here. The cap is for the doors we cannot see.
--
-- 10000 is deliberately far above any legitimate population: the largest guild
-- this has been measured against is 978 members, and a client also tracking
-- several sister rosters plus chat senders is still a few thousand keys. So
-- tripping it means the input is unbounded, not that the guild is big.
--
-- A crude wipe is the right response, not an LRU: this is a pure cache, so the
-- only cost is recomputing the names still in use, and an eviction policy would
-- be more code guarding a case normal use never reaches.
--
-- On the lib rather than a file-local to match STABLE_THRESHOLD / PRESENCE_TTL /
-- RECENTLY_ONLINE_TTL, the other tuning constants here. Not public API — a
-- consumer has no reason to read it — but it is reachable, which is what lets a
-- spec drive the ceiling instead of allocating ten thousand strings to reach it.
lib.NAME_CACHE_MAX = 10000

lib.nameCache      = {}
lib.nameCacheRealm = nil
lib.nameCacheCount = 0

-- @param name any  any string is accepted, but see NAME_CACHE_MAX — a string
--                  that normalizes successfully is retained until the cache is
--                  wiped, so this is not a pure function
-- @return string|nil
function lib:NormalizeName(name)
    -- Only strings are cacheable, and only strings can hit. Everything else
    -- falls through to CanonName, which returns nil for it anyway.
    local cacheable = type(name) == "string"
    if cacheable then
        local realm = self:GetRealmName()
        if realm ~= self.nameCacheRealm then
            wipe(self.nameCache)
            self.nameCacheCount = 0
            -- Set BEFORE re-keying: RekeySisterRosters calls back into this
            -- function for every stored name, and an unset nameCacheRealm would
            -- make each of those re-enter this branch.
            self.nameCacheRealm = realm
            self:RekeySisterRosters()
        end
        local hit = self.nameCache[name]
        if hit then return hit end
    end

    local result = self:ComputeNormalizedName(name)
    -- Failures are deliberately not cached: nil is indistinguishable from
    -- "absent" as a table value, and a rejected name is rare enough that
    -- recomputing it costs nothing.
    if cacheable and result then
        -- The count is exact without re-reading the table: a key already
        -- present returned at the hit check above, so reaching here means this
        -- key is new. Wipe BEFORE storing so the ceiling is the live maximum
        -- rather than one more than it.
        if self.nameCacheCount >= self.NAME_CACHE_MAX then
            wipe(self.nameCache)
            self.nameCacheCount = 0
        end
        self.nameCache[name] = result
        self.nameCacheCount = self.nameCacheCount + 1
    end
    return result
end

-- ONE KEY FOR A PEER WE TALK TO over the addon channel, whichever spelling it
-- arrives in. AceComm hands every receiver `Ambiguate(sender, "none")`
-- (AceComm-3.0.lua, OnEvent), which is BARE for a player on our own realm and
-- `Name-Realm` for anyone else -- while the library's own records (a pull's
-- peer, a roster charKey, a /who row we normalized) are `Name-Realm`. So a
-- sender is compared with NormalizeName on both sides, never CanonName: a bare
-- addon-channel sender IS on our realm by AceComm's contract, which is exactly
-- the inference NormalizeName makes. CanonName never supplies a realm, and
-- comparing with it dropped every roster a same-realm member served as "we did
-- not ask them" (TOGBankClassic's peer review GR-SAMEREALM-001, 2026-09-16).
-- Lower-cased, because these are table keys and a typed name's case varies.
local function senderKey(self, name)
    if type(name) ~= "string" then return nil end
    return string.lower(self:NormalizeName(name) or name)
end

--- Rewrite every sister roster's keys once the connected realm resolves.
--
-- The home roster needs nothing like this, but the reason NARROWED in 0.5.0 and
-- this comment used to state the old one. It is no longer "wiped and rebuilt on
-- every GUILD_ROSTER_UPDATE": build-once means it is rebuilt only on the events
-- BEFORE `initialized`, and after that nothing re-keys it. That still covers the
-- window this function exists for, because the realm resolves at PLAYER_LOGIN —
-- before the server has sent a single roster row, and therefore before the last
-- pre-stabilization rebuild that decides the final keys. What is NOT covered any
-- more is a client where the realm somehow resolves after stabilization: those
-- keys would stay bare for the session rather than for a beat. No such client
-- has been observed and nothing here guesses at one; the honest statement is
-- that the margin shrank from "the whole session" to "the login stream".
--
-- A SISTER roster is the opposite — it is fed by a consumer and replaced only
-- wholesale by the next feed, on that consumer's schedule. Nothing in this
-- library touches it in between.
--
-- **And the consumers feed it in exactly the wrong window, by design.**
-- TOGProfessionMaster's `Scanner:RefeedSisterRosters()` exists to "re-feed
-- persisted sister rosters into LibGuildRoster on login", and DeltaSync
-- documents the same split in four places: the consumer owns persistence and
-- re-feeds from its SavedVariables at login. That is before
-- GetNormalizedRealmName() answers, so every fed name normalized bare and
-- stayed bare until the next live pull.
--
-- The cost was not cosmetic. GetRosterHash runs over sister rosters, so the
-- digest was computed over unrealmed keys and could not match what any
-- correctly-realmed client computes for the same membership — and that digest
-- is the wire signal that tells a sister client whether to re-pull. Two clients
-- holding identical membership would have disagreed permanently.
--
-- Presence stamps are re-keyed alongside, or MarkOnline's record for a member
-- would be orphaned under the old spelling and GetOnlineMembersScoped's
-- membership intersection would silently drop them.
--
-- Firing from here is deliberate and safe in that order: nameCacheRealm is
-- already updated by the caller, so a handler that calls back into
-- NormalizeName takes the fast path, and the guildKey list is snapshotted
-- first so a handler calling SetSisterRoster cannot mutate the table being
-- iterated.
function lib:RekeySisterRosters()
    local guildKeys = {}
    for guildKey in pairs(self.rosters) do guildKeys[#guildKeys + 1] = guildKey end

    for _, guildKey in ipairs(guildKeys) do
        local roster = self.rosters[guildKey]
        if roster then
            local rekeyed, rekeyedFrom, moved = {}, {}, false
            for oldKey, member in pairs(roster) do
                -- `or oldKey` keeps a name we can no longer normalize rather
                -- than silently dropping a member from a roster we do not own.
                local newKey = self:NormalizeName(oldKey) or oldKey
                if newKey ~= oldKey then moved = true end

                local existing = rekeyed[newKey]
                if existing then
                    -- COLLISION, and it is reachable precisely here: a consumer
                    -- feeding pre-realm can hold both "Bob" and "Bob-OurRealm",
                    -- which are distinct keys only while the realm is
                    -- unresolved. An unguarded assignment let the second
                    -- silently overwrite the first, and pairs() order decided
                    -- which — so the survivor was not even deterministic.
                    --
                    -- They denote ONE character, so this merges rather than
                    -- keeping both: a surviving bare key is the exact defect
                    -- this function exists to remove, and it would go straight
                    -- back into the published hash. The winner is chosen from
                    -- the DATA, never from iteration order — a canonically-fed
                    -- key beats a rewritten one, and two rewritten keys fall
                    -- back to the lexicographically smaller original.
                    -- Written as one comparison rather than a canonical-vs-
                    -- rewritten branch because that branch was UNREACHABLE and
                    -- coverage said so: SetSisterRoster normalizes at feed
                    -- time, so a character has exactly one bare spelling and
                    -- any qualified spelling is already the final key. Mapping
                    -- a canonical key to "" — which no real key can be, since
                    -- NormalizeName rejects empty — ranks it first without a
                    -- second path to leave untested.
                    local existingFrom = rekeyedFrom[newKey]
                    local mine  = (oldKey == newKey) and "" or oldKey
                    local yours = (existingFrom == newKey) and "" or existingFrom
                    local incomingWins = mine < yours

                    local winner = incomingWins and member or existing
                    local loser  = incomingWins and existing or member
                    -- Union, so the merge cannot lose a field the loser alone
                    -- carried (a feed may supply class on one spelling only).
                    for field, value in pairs(loser) do
                        if winner[field] == nil then winner[field] = value end
                    end
                    winner.name = newKey
                    rekeyed[newKey] = winner
                    rekeyedFrom[newKey] = incomingWins and oldKey or existingFrom
                else
                    member.name = newKey
                    rekeyed[newKey] = member
                    rekeyedFrom[newKey] = oldKey
                end
            end

            -- WHY GATING PRESENCE ON A *ROSTER* KEY HAVING MOVED IS SOUND, and
            -- it rests on an invariant in a different function: a presence map
            -- carrying bare keys while the roster carries none would be skipped
            -- here and never re-keyed. That state cannot arise, because
            -- MarkOnline stamps only `if norm and roster[norm]` -- it requires
            -- membership under that EXACT key before it records anything. So a
            -- bare presence key can only exist where the roster held a bare key
            -- too, which is precisely the case that sets `moved`.
            -- Written down at peer review's suggestion: the gate reads like a
            -- gap until you have gone and read MarkOnline, and every future
            -- reader would ask the same question.
            if moved then
                self.rosters[guildKey] = rekeyed

                local presence = self.presence[guildKey]
                if presence then
                    local movedPresence = {}
                    for oldKey, stamp in pairs(presence) do
                        -- Same collision, and the tie-break is different
                        -- because the data means something different: two
                        -- spellings of one character carry two sightings, and
                        -- the LATER one is the true answer to "when were they
                        -- last seen". Taking the max is also order-independent
                        -- without needing a rule about the keys.
                        local newKey = self:NormalizeName(oldKey) or oldKey
                        local held = movedPresence[newKey]
                        if not held or stamp > held then
                            movedPresence[newKey] = stamp
                        end
                    end
                    self.presence[guildKey] = movedPresence
                end

                -- The digest genuinely moved, and the one we published before
                -- was wrong, so this fires rather than correcting itself
                -- quietly — a consumer comparing against a sister client needs
                -- to know the value it was given has been superseded.
                local newHash = self:GetRosterHash(guildKey)
                if self.rosterHashes[guildKey] ~= newHash then
                    self.rosterHashes[guildKey] = newHash
                    self.callbacks:Fire("OnRosterHashChanged", guildKey, newHash)
                end
            end
        end
    end
end

--- The uncached body of NormalizeName. Split out so the memoization above reads
-- as a cache rather than being interleaved with the normalization rules. Not
-- part of the public API — call NormalizeName.
-- @param name any
-- @return string|nil
function lib:ComputeNormalizedName(name)
    local normalized = self:CanonName(name)
    if not normalized then return nil end

    -- "Unknown" stays bare, and keeps its realm stripped when it had one. This
    -- sits ABOVE the append on purpose: routing it through the realm suffix
    -- would turn the placeholder into "Unknown-Realm" and make it look like a
    -- real character key.
    local left = string.match(normalized, "^(.-)%-") or normalized
    if string.lower(left) == "unknown" then return "Unknown" end

    -- Already qualified — CanonName only returns a hyphen when a realm follows.
    if string.find(normalized, "%-") then return normalized end

    -- Append the connected-realm name — unless it has not resolved yet.
    --
    -- GetNormalizedRealmName() returns nil in the window between login and the
    -- realm arriving, and this line concatenated it unguarded: "attempt to
    -- concatenate a nil value", raised out of every caller that takes a bare
    -- name in that window — the rebuild loop, IsInGuild's pre-build scan,
    -- SetSisterRoster, and the chat handlers. GetNormalizedPlayer has always
    -- guarded the same window a few lines below; this path never did.
    --
    -- A bare name is the honest answer there. It does not outlive the window,
    -- but that took TWO mechanisms rather than the one this comment first
    -- claimed: the HOME roster heals because the login stream rebuilds it on
    -- every event until `initialized` (it was "on every GUILD_ROSTER_UPDATE"
    -- until 0.5.0 stopped rebuilding after that point — see RekeySisterRosters
    -- for what that narrowing does and does not cost), and SISTER rosters heal
    -- because RekeySisterRosters
    -- rewrites them when the realm resolves. Nothing wipes a sister roster on a
    -- roster event — it is replaced only by a fresh feed on the consumer's own
    -- schedule — so the original "the roster is wiped and rebuilt" argument
    -- covered half the store and read as if it covered all of it. Caught by
    -- peer review as finding 9; see RekeySisterRosters for why it is not
    -- hypothetical. The empty string is folded in with nil because "Bob-" is
    -- not a key, it is a bug.
    local realm = self:GetRealmName()
    if not realm or realm == "" then return normalized end
    return normalized .. "-" .. realm
end

--- Return the local player's canonical "Name-Realm" string.
-- Reuses the lib's cached GetRealmName so the result formats identically to
-- the roster keys (consumers can compare it against GetMember / GetAllMembers
-- output directly). Deliberately does NOT route through NormalizeName: it
-- keeps a bare-name fallback for the brief pre-world-enter window where
-- GetNormalizedRealmName() returns nil/"" (NormalizeName would emit a
-- trailing-hyphen "Name-" there). UnitName("player") is always a clean short
-- name, so the extra normalization NormalizeName performs isn't needed.
-- @return string|nil  "Name-Realm", or "Name" if the realm isn't resolved
--                     yet, or nil if UnitName isn't available yet.
function lib:GetNormalizedPlayer()
    local name = UnitName and UnitName("player")
    if not name or name == "" then return nil end
    local realm = self:GetRealmName()
    if realm and realm ~= "" then
        return name .. "-" .. realm
    end
    return name
end

--- PLAYER_LOGIN: cache realm name and request an initial roster update.
--
-- Deliberately does NOT touch SetGuildRosterShowOffline. Earlier versions forced
-- that flag on here, which was wrong twice over: it permanently overwrote a
-- setting the user may have chosen on purpose, and it only asserted the value
-- once, so any addon flipping the box afterwards silently degraded every later
-- rebuild. The per-scan bracket that replaced it is gone too: NOTHING in this
-- library writes that flag now. Do not add it back here or anywhere else — the
-- reasoning, the 997/997 measurement and the feedback loop it caused are in the
-- "⛔ THE SHOW-OFFLINE BRACKET IS GONE" block above ReadRosterRow, and are
-- deliberately not restated here so the two cannot drift apart again.
function lib:OnPlayerLogin()
    self.realmName = GetNormalizedRealmName()
    if IsInGuild() then
        RequestGuildRoster()
    end
    -- Classic's mail frame is built at UI load, so the box exists now; on a
    -- flavour that builds it on demand the MAIL_SHOW handler catches it.
    self:InstallMailAutocomplete()
    -- Same shape for the guild window: Classic's Blizzard_Communities has no
    -- LoadOnDemand line, so the frame exists now; ADDON_LOADED covers the rest.
    self:InstallGuildTab()
    -- And the classic Friends-frame guild tab, built at UI load on every
    -- flavour that has it.
    self:InstallClassicGuildTab()
    -- The /who hooks go in now as well as at the first borrow: FGI's Wingman
    -- and our overlay fire on the SAME click, so its send can precede our
    -- first borrow, and a send never seen never stamps the floor -- the
    -- server would eat our first query. Nothing is owed yet, so the give-back
    -- half is a no-op until a borrow.
    self:HookWhoPane()
end

--- Recompute the home roster's membership hash and announce it if it moved.
--
-- ONE implementation, called from three places: the login build's tail, and the
-- chat-driven join and leave branches that maintain membership in place for the
-- rest of the session. Before build-once there was only the rebuild tail, so
-- this was inline there; now that membership changes arrive from chat instead,
-- an inline copy per branch would be three chances for the hash and the roster
-- to disagree.
--
-- The hash is the only way a sister client learns our membership moved and it
-- should re-pull, so a join or leave that updates the roster without announcing
-- is a silent divergence between two clients, not a delayed callback.
--
-- Gated on `initialized`: during the login stream membership is still arriving,
-- and churning the hash from 50 members to 200 tells a sister client to re-pull
-- a roster we have not finished reading. The caller decides whether the set can
-- have moved at all; this decides whether the hash actually differs.
-- @param self table
local function FireHomeRosterHashChanged(self)
    if not self.initialized then return end
    local homeKey = self:GetHomeGuildKey()
    if not homeKey then return end
    local newHash = self:GetRosterHash(homeKey)
    if self.homeRosterHash ~= newHash then
        self.homeRosterHash = newHash
        -- A state a sister client may later hold and ask for a delta from.
        rememberState(self, newHash, toWire(self.roster, "publicNote"))
        self.callbacks:Fire("OnRosterHashChanged", homeKey, newHash)
    end
end

--- Drop `recentlyLeft` / `recentlyOnline` stamps that have outlived their TTL.
--
-- These aged out inside the rebuild, which was the one pass guaranteed to run
-- often. Build-once removed that runner and the tables would have grown for the
-- whole session — every guild-chat talker in `recentlyOnline`, every departure
-- in `recentlyLeft` — so the prune now rides the write sites that create the
-- stamps and the login build that still reads them.
--
-- Cost, stated rather than waved at, because the busiest caller IS a hot path:
-- MarkMemberOnline runs on every line of guild chat and prunes on each one. What
-- bounds that is the TTL, not the guild size — `recentlyOnline` can only hold
-- characters who spoke or logged in within the last 60 seconds, which is tens of
-- entries in a busy guild, not the 978-member roster. Tens of table lookups per
-- chat line is not a cost worth an eviction schedule to avoid, and the
-- alternative — pruning only on transitions — leaves the table holding every
-- talker until one happens to occur.
-- @param self table
local function PruneStamps(self)
    local now = GetTime()
    for name, leftAt in pairs(self.recentlyLeft) do
        if now - leftAt >= self.RECENTLY_LEFT_TTL then
            self.recentlyLeft[name] = nil
        end
    end
    for name, seenAt in pairs(self.recentlyOnline) do
        if now - seenAt >= self.RECENTLY_ONLINE_TTL then
            self.recentlyOnline[name] = nil
        end
    end
end

--- Fill in the fields a "has joined the guild" message could not carry.
--
-- Reads the roster rows ONCE and copies class, rank, level, zone, notes and
-- status onto the members the join branch inserted from a name alone. Returns
-- immediately when nothing is pending, which is the overwhelmingly common case —
-- so the post-login cost of a GUILD_ROSTER_UPDATE is one `next()` call.
--
-- This is a row READ, not a rebuild: nothing is wiped, no member table is
-- reallocated, no diff runs and no callback fires from here. The member already
-- exists and already answered IsInGuild the moment chat announced the join; this
-- only makes GetMember's optional fields real.
--
-- A pending key is cleared as soon as its row is FOUND, whether or not the row
-- carried a level — an absent level leaves `levelUnknown` set, which is the same
-- invented-baseline machinery the login build uses, and re-scanning for it would
-- turn a one-shot pass into a permanent per-event cost. Keys the server never
-- produces a row for are dropped on the TTL instead (see lib.pendingDetail).
-- @param self table
local function ResolvePendingDetail(self)
    if not next(self.pendingDetail) then return end

    local now = GetTime()
    for norm, joinedAt in pairs(self.pendingDetail) do
        if now - joinedAt >= self.PENDING_DETAIL_TTL then
            self.pendingDetail[norm] = nil
        end
    end
    if not next(self.pendingDetail) then return end

    -- ⛔ NO SHOW-OFFLINE BRACKET HERE, DELIBERATELY, AND DO NOT ADD ONE BACK.
    --
    -- This used to bracket the scan the way the login build does. Two reasons
    -- it is gone, and the first outranks the second:
    --
    -- 1. WRITING A SHARED UI SETTING TO READ OUR OWN DATA IS THE WRONG SHAPE.
    --    It mutates something the player owns and every other addon can read.
    --
    -- 2. It was a positive feedback loop. SetGuildRosterShowOffline FIRES
    --    GUILD_ROSTER_UPDATE -- measured in-game, engine-side, absent from the
    --    client source and from Blizzard_APIDocumentationGenerated, so reading
    --    will not confirm it. The bracket wrote the flag TWICE per scan, this
    --    function runs FROM the handler, and the handler runs on that event.
    --    Reported by FastGuildInvite 2026-08-16 as an FPS collapse while
    --    recruiting: 110 fps to 20 over seven minutes, cleared by /reload.
    --    It only bit players with the box UNTICKED, because the old bracket
    --    returned early when the flag was already on -- so the exposure was
    --    decided by a checkbox, which is the tell that the setting was
    --    load-bearing when it had no business being.
    --
    -- Nothing is lost. A joiner has just ACCEPTED AN INVITE, so they are online
    -- by construction -- that is the same premise the join branch uses to set
    -- their presence -- and an online member's row is visible whatever the
    -- filter is doing. The residual: a joiner who logs off inside the TTL, with
    -- the box unticked, may not be found, and their level stays at the invented
    -- 1 until the key expires. That is a cosmetic gap against a frame-rate
    -- collapse, and it self-corrects on the next login.
    -- This loop used to sit inside `pcall(function() ... end)` with the result
    -- re-raised immediately afterwards. The pcall was there to release the
    -- show-offline bracket on the error path; 0.5.1 deleted the bracket and left
    -- the wrapper, with nothing between the pcall and the re-raise -- so it
    -- caught an error only to throw the identical error again, one stack frame
    -- shallower. The only observable effect was a TRUNCATED TRACEBACK: BugSack
    -- reported the `error(scanErr, 0)` line instead of the line that failed.
    -- Audit finding 23. Unlike the login build's scan, this closure had no early
    -- return in it, so the whole wrapper goes rather than just the pcall.
    for i = 1, GetNumGuildMembers() do
        -- Slot 8 is the row's isOnline and is deliberately discarded here;
        -- see the presence note below.
        local name, rankName, rankIndex, level, zone, publicNote, officerNote,
              _, status, classFileName, isMobile = ReadRosterRow(i)
        if name then
            local norm = self:NormalizeName(name)
            local member = norm and self.pendingDetail[norm] and self.roster[norm]
            if norm and rankName and rankIndex then
                self.rankIndexByName[rankName] = rankIndex
            end
            if member then
                member.class       = classFileName
                member.rankIndex   = rankIndex
                member.rankName    = rankName
                member.zone        = zone
                member.publicNote  = publicNote or ""
                member.officerNote = officerNote or ""
                member.status      = status or 0
                member.isMobile    = isMobile or false
                -- Presence is NOT taken from the row. The join branch set it
                -- from a real-time signal and the chat handlers maintain it;
                -- a row is exactly the stale source recentlyOnline exists to
                -- overrule, and overwriting here would reintroduce that bug
                -- through the back door.
                if level ~= nil then
                    member.level = level
                    self.levelUnknown[norm] = nil
                end
                self.pendingDetail[norm] = nil
            end
        end
    end
end

--- Did the login build stop short of the whole roster?
--
-- Build-once rests on ONE premise: the snapshot stabilization locked on was the
-- complete roster. The stabilization guard cannot actually prove that -- the
-- file has said so since MINOR 14 ("a STABLE_THRESHOLD = 2 guard still misfires
-- when two of those partial events happen to have the same count"), and while
-- the roster was rebuilt on every event that misfire cost one event's worth of
-- wrong answers. Under build-once it is PERMANENT: the partial snapshot is
-- served to every consumer, and to every sister guild, for the whole session.
--
-- That is what a sister client saw on 2026-09-15: "27 members" for a guild of
-- 289, from a provider whose login build had locked on 27 rows. The provider
-- then served that roster with a hash over 27 names, so the pull path had
-- nothing to disagree with -- the wire was working perfectly, carrying the
-- wrong roster.
--
-- The tell is cheap and exact: the server's own member total, which every
-- GUILD_ROSTER_UPDATE makes current, EXCEEDS the number of members we hold.
-- Chat maintains membership in place, so held and total agree for the rest of
-- a healthy session, and the one legitimate gap -- a departure chat announced
-- that the server's row still lists -- is exactly what `recentlyLeft` records,
-- so the check waits it out rather than resurrecting the leaver. A total BELOW
-- what we hold is never a deficit: that is a joiner chat inserted before the
-- server's row arrived, and ResolvePendingDetail owns it.
--
-- This is the login build FINISHING, not a rebuild-on-event: it runs only on
-- a proven deficit, at most MAX_LOGIN_REPAIRS times per guild, and the common
-- case costs one API call and one pass over the roster keys. The directive is
-- "build once on login, then update from events"; a build that stopped at 27
-- of 289 has not been built once, it has been built wrong.
-- @param self table
-- @return boolean
local function LoginBuildIsShort(self)
    if self.loginRepairs >= self.MAX_LOGIN_REPAIRS then return false end
    local total = GetNumGuildMembers()
    if not total or total <= 0 then return false end
    local held = 0
    for _ in pairs(self.roster) do held = held + 1 end
    if total <= held then return false end
    PruneStamps(self)
    if next(self.recentlyLeft) then return false end
    return true
end

--- GUILD_ROSTER_UPDATE: build the roster ONCE, then resolve pending joiners.
-- Retries up to MAX_RETRIES times if the API returns 0 members (login race).
--
-- @param canRequestRosterUpdate boolean|nil  the event's ONLY payload
--        (`GuildInfoDocumentation.lua:527-530`, `Nilable = false`). It does NOT
--        mean "something changed" — it means "the server throttle has lifted,
--        you may ask again", and all three of Blizzard's own consumers gate
--        their request on it and nothing else:
--            Blizzard_Calendar.lua:3393-3396, :4172-4175
--            Blizzard_Communities/GuildRoster.lua:65-68
--        Read from the Classic Era tree, not inferred. Nil when the caller did
--        not forward it — see the retry gate for how that degrades.
function lib:OnGuildRosterUpdate(canRequestRosterUpdate)
    if not IsInGuild() then
        wipe(self.roster)
        self.initialized = false
        -- Left/changed guild: drop the cached home key and hash so the next
        -- guild resolves a fresh "Faction-GuildName" rather than keying
        -- sister rejections and GetRoster(homeKey) against a stale guild.
        self.homeGuildKey   = nil
        self.homeRosterHash = nil
        -- Reset the per-guild transient state too. Clearing `initialized`
        -- alone is not enough: stableCount/previousTotal describe the OLD
        -- guild's login stream, and carrying them over means the next guild's
        -- FIRST rebuild can find `total == previousTotal` with stableCount
        -- already at the threshold and declare a partial snapshot ready —
        -- exactly the misfire stabilization exists to prevent. recentlyLeft
        -- likewise only ever describes the guild we just left, and retryCount
        -- must not spend the new guild's budget on the old guild's races.
        self.stableCount   = 0
        self.previousTotal = 0
        self.retryCount    = 0
        self.loginRepairs  = 0
        self.loginVerified = false
        wipe(self.recentlyLeft)
        wipe(self.recentlyOnline)
        wipe(self.levelUnknown)
        -- Same reasoning as the others: an outstanding row lookup describes a
        -- joiner in the guild we just left, and carrying it over would have the
        -- next guild's first events scanning for a name that cannot be there.
        wipe(self.pendingDetail)
        return
    end

    -- THE COUNTERPART OF THE WIPE ABOVE: we are in a guild, so the home key is
    -- resolvable, and this is the moment to drop a fed copy of our OWN guild.
    -- A consumer that called SetSisterRoster before the key resolved slipped
    -- past its self-reject, which compares against a key that was still nil.
    --
    -- THIS LIVED INSIDE GetHomeGuildKey UNTIL 2026-08-28 AND THAT WAS THE WRONG
    -- PLACE (peer-review finding 30). A mutation hidden in a documented pure
    -- getter is a hazard on its own: a future memoisation, an early return, or
    -- a caller that caches the key would silently remove the cleanup with
    -- nothing failing. It also made the cleanup's timing depend on whoever
    -- happened to call the getter first, rather than on the event that makes
    -- the state identifiable. Here it is driven by the event.
    local homeKey = self:GetHomeGuildKey()
    if homeKey and self.rosters[homeKey] then
        self.rosters[homeKey]      = nil
        self.presence[homeKey]     = nil
        self.rosterMeta[homeKey]   = nil
        self.rosterHashes[homeKey] = nil
    end

    -- ⛔ BUILD ONCE. THE ROSTER IS NEVER REBUILT.
    --
    -- The roster is constructed during the login stream, and from the moment it
    -- is `initialized` it is MAINTAINED IN PLACE from events for the rest of the
    -- session. This event is then ignored outright — which is the whole point,
    -- and it is why the frequency of GUILD_ROSTER_UPDATE stopped mattering.
    --
    -- We cannot make the event rare. It comes from the client's own code
    -- (Blizzard_Calendar.lua:4170-4177 re-requests outside its own IsShown()
    -- guard, registers in OnLoad and never unregisters) and from every other
    -- addon that requests a roster.
    --
    -- The CONSEQUENCE is what belongs here: at the measured rate and per-rebuild
    -- cost, one guildmate logging off cost 140.93 ms of main-thread work in this
    -- library alone, which is the micro-stutter a player reported. The numbers
    -- themselves live in the file header and are deliberately NOT repeated here
    -- — this comment and that block disagreed on the logoff count until audit
    -- finding 15, and a citation cannot drift from its source the way a copy can.
    --
    -- So the answer is not a cheaper rebuild, a digest, or a throttle. It is to
    -- stop rebuilding: an event we ignore costs nothing however often it fires.
    --
    -- The one thing still done here is resolving a pending joiner's row, which
    -- no-ops on a single `next()` unless a join is actually outstanding. See
    -- ResolvePendingDetail — membership, presence, rank and hash are all
    -- maintained from chat events now, not from this one.
    --
    -- ...unless the login build provably stopped short, in which case it is
    -- finished here (see LoginBuildIsShort). Falling through re-reads the rows
    -- exactly as the login stream does; the stabilization block below is what
    -- a finished build skips, so OnRosterReady fires once per guild, ever.
    local finishing = false
    if self.initialized then
        ResolvePendingDetail(self)
        -- ONE more roster request after ready, on the first event whose
        -- payload says the server will take one. LoginBuildIsShort can only
        -- see a deficit the client has already been told about, and after
        -- login nothing asks the server again: our PLAYER_LOGIN request is
        -- the only one, the client's own calendar asks only while the total
        -- is zero, and the guild panel asks only when opened. So a client
        -- that stabilized on a partial TOTAL (rows and total agreeing, both
        -- short) would sit on it until the player opened the guild panel.
        -- Driven by the event's own flag, not a timer -- the same gate
        -- Blizzard's FriendsFrame uses for its re-request (Classic
        -- FriendsFrame.lua:388-391) -- so it goes out exactly when the
        -- server says it may, and a complete build answers it with the same
        -- total, which the next event ignores as always.
        if not self.loginVerified and canRequestRosterUpdate == true then
            self.loginVerified = true
            RequestGuildRoster()
        end
        if not LoginBuildIsShort(self) then return end
        finishing = true
        self.loginRepairs = self.loginRepairs + 1
    end

    -- ⚠ THE CLOSURE IS LOAD-BEARING. DO NOT INLINE IT.
    --
    -- The `needsRetry` branch inside returns out of THIS CLOSURE, not out of
    -- OnGuildRosterUpdate -- so the retry request further down still runs.
    -- Inline the body and that `return` would skip the retry entirely, leaving
    -- an empty roster that build-once never corrects.
    --
    -- It used to be wrapped in `pcall` with the error re-raised immediately
    -- afterwards. That pcall existed to release the show-offline bracket on the
    -- error path; 0.5.1 deleted the bracket and left the wrapper behind, with
    -- nothing between the pcall and the re-raise -- so it caught an error only
    -- to rethrow the identical error one frame shallower, costing a TRUNCATED
    -- TRACEBACK and buying nothing. Removed as audit finding 23; the scan is
    -- called directly and an error now propagates from the line that raised it.
    --
    -- ⛔ AND THE COMMENT THAT WAS HERE CLAIMED THE OPPOSITE. Written 2026-08-16
    -- in the same pass that deleted the bracket, it said the pcall meant "an
    -- error mid-scan cannot leave the login stream half-applied". THAT WAS
    -- FALSE -- the error was re-raised immediately, so the partially-rebuilt
    -- roster was identical with or without it. Recorded rather than quietly
    -- dropped, because inventing a safety property for an orphaned construct is
    -- the exact defect this file spent 2026-08-16 removing from eight other
    -- places, and it was written BY the session doing the removing.
    -- `short` is "the client reported more members than it gave us rows for"
    -- -- a partial stream. It spends the same retry budget as a zero total.
    local total, needsRetry, short = 0, false, false
    -- Only the LEVEL is carried across events now. `wasOnline` and
    -- `wasRankIndex` were snapshotted here for the post-rebuild diff, and that
    -- diff is gone: it could only fire when `initialized` was already true, and
    -- the early return above means this code is now reached only while it is
    -- false. Keeping the snapshots would have been two per-member table writes
    -- per login event, feeding nothing.
    local wasLevel = {}
    -- The invented-level set from the PREVIOUS event of the login stream, and
    -- the one this pass is accumulating. Swapped in once the loop completes.
    local prevUnknown, nowUnknown = self.levelUnknown, {}

    -- Membership-set change detection, so the roster hash at the end of this
    -- function is COMPUTED only when the set actually moved. Three counters are
    -- enough for exact set equality: the sets are equal iff they are the same
    -- size AND every member of the new one was in the old one.
    local wasPresent = {}
    local prevCount, newCount, matchedCount = 0, 0, 0

    local function runScan()
    total = GetNumGuildMembers()

    -- Retry if the guild roster API is not ready yet (common at login).
    -- retryCount is reset at the END of the scan, once the rows are known to
    -- be all there -- a short scan below spends from the same budget.
    if total == 0 and self.retryCount < self.MAX_RETRIES then
        needsRetry = true
        return
    end

    -- Snapshot previous state before wipe. `wasLevel[name]` carries the prior
    -- level so a row that arrives without one does not manufacture a level-up;
    -- `wasPresent[name]` answers "was this member in the previous roster?" for
    -- the membership counters.
    for name, member in pairs(self.roster) do
        wasLevel[name]   = member.level
        wasPresent[name] = true
        prevCount        = prevCount + 1
    end

    -- recentlyLeft used to be SEEDED into a wasOnline snapshot here, so the
    -- post-rebuild diff stayed silent about a player a stale response still
    -- listed. That diff is gone, and with it the only reader of the seed — so
    -- what is left is the expiry, which still has to happen somewhere. This is
    -- the login-stream runner for it; the chat write sites cover the rest of
    -- the session. See PruneStamps.
    PruneStamps(self)

    -- Wipe and rebuild from scratch — no stale entries possible. ReadRosterRow
    -- (see the flavor-compat section) owns the GetGuildRosterInfo positional
    -- decode and returns only the fields we expose — notes, zone, status, and
    -- the (now-retired) mobile flag — which consumers can't trivially recover
    -- themselves. officerNote is "" for ranks without
    -- GR_RANKFLAG_VIEW_OFFICERNOTE, which is the expected behaviour.
    -- GetGuildRosterLastOnline returns offline duration as a
    -- (years, months, days, hours) tuple — useful for inactive-member cleanup.
    wipe(self.roster)
    for i = 1, total do
        local name, rankName, rankIndex, level, zone, publicNote, officerNote, isOnline, status, classFileName, isMobile = ReadRosterRow(i)
        if name then
            local norm = self:NormalizeName(name)
            if norm then
                -- A row that says offline does NOT overrule a real-time signal
                -- we acted on inside the TTL (see lib.recentlyOnline). Resolved
                -- here, before anything else reads it, so the whole row — the
                -- last-online read below and the stored flag — agrees on one
                -- answer. A row that says ONLINE is never contradicted: it
                -- confirms the stamp rather than competing with it.
                local online = isOnline or false
                if not online and self.recentlyOnline[norm] then
                    online = true
                end
                local lastOnline
                if not online and GetGuildRosterLastOnline then
                    local years, months, days, hours = GetGuildRosterLastOnline(i)
                    if years or months or days or hours then
                        lastOnline = {
                            years  = years  or 0,
                            months = months or 0,
                            days   = days   or 0,
                            hours  = hours  or 0,
                        }
                    end
                end
                -- A roster row can arrive with a name but no level. Defaulting
                -- that to 1 manufactured a phantom level-up: the member was
                -- written down at 1, the next rebuild wrote their real level,
                -- and OnMemberLevelChanged fired (1 -> 60) with both presence
                -- flags true — indistinguishable from a real ding, so a consumer
                -- like TOGTools' Gratz announced it in guild chat. Stabilization
                -- does NOT cover this: it suppresses only the initial login
                -- stream, while the "has joined the guild" branch calls
                -- RequestGuildRoster() and starts a fresh stream with
                -- `initialized` already true.
                --
                -- Carry the previous value forward when we have one. When we
                -- don't — a member we have never seen carrying a level, i.e. a
                -- fresh joiner — the public shape still requires a number, so
                -- write 1 and record the name in nowUnknown. The diff skips any
                -- member whose baseline was invented, which is what closes the
                -- joiner case that carrying-forward alone cannot: there the
                -- invented 1 IS the previous value, so it would otherwise become
                -- a legitimate-looking baseline on the very next rebuild.
                if level == nil then
                    level = wasLevel[norm] or 1
                    if prevUnknown[norm] or wasLevel[norm] == nil then
                        nowUnknown[norm] = true
                    end
                end
                if rankName and rankIndex then
                    self.rankIndexByName[rankName] = rankIndex
                end
                self.roster[norm] = {
                    name        = norm,
                    class       = classFileName,
                    level       = level,
                    rankIndex   = rankIndex,
                    rankName    = rankName,
                    isOnline    = online,
                    zone        = zone,
                    publicNote  = publicNote or "",
                    officerNote = officerNote or "",
                    status      = status or 0,
                    isMobile    = isMobile or false,
                    lastOnline  = lastOnline,
                    -- Which guild this character is in, carried ON the
                    -- character rather than in a parallel index. Alt groups
                    -- span guilds, so a consumer walking one needs the guild
                    -- per character; putting it here means the answer travels
                    -- with the member table it belongs to. Cannot go stale: a
                    -- guild change wipes the roster and rebuilds it (see
                    -- OnGuildRosterUpdate), so every record is written under
                    -- the key that was current when it was created.
                    --
                    -- IT MEANS "THE ROSTER THIS RECORD BELONGS TO", not "the
                    -- guild this character is in". The same character can hold
                    -- a home record AND a sister record, and their `guild`
                    -- fields then differ -- each honestly naming its own
                    -- roster. A character cannot be in two guilds, so when both
                    -- exist the SISTER one is the stale side: the home roster is
                    -- live-scanned, a sister roster is fed and can be any age.
                    -- IsInAnyRoster is the authoritative answer and prefers
                    -- home, which is what makes the two consistent rather than
                    -- contradictory.
                    guild       = self:GetHomeGuildKey(),
                }
                newCount = newCount + 1
                if wasPresent[norm] then matchedCount = matchedCount + 1 end
            end
        end
    end

    -- Fewer rows than the client's own total is a partial stream: rows the
    -- server has not delivered yet read as nil past some index. Ask again
    -- while the budget lasts; once it is spent the build proceeds on what it
    -- has, and LoginBuildIsShort finishes it when the rest arrives. Only a
    -- COMPLETE scan resets the budget, so short and zero share it.
    short = newCount < total
    if short then
        if self.retryCount < self.MAX_RETRIES then needsRetry = true end
    else
        self.retryCount = 0
    end

    -- Swap in this rebuild's invented-level set. Deliberately inside the scan
    -- closure and after the loop: the early `needsRetry` return above bails
    -- before the rebuild runs, and must leave the previous set intact so a
    -- retried scan doesn't forget which levels were invented.
    self.levelUnknown = nowUnknown
    end

    -- Called directly, NOT through pcall -- see the note above the definition.
    -- An error in the scan propagates from the line that raised it, with the
    -- traceback intact, and skips everything below exactly as it did before.
    runScan()

    if needsRetry then
        -- ⛔ GATE THE REQUEST ON THE PAYLOAD, AND DO NOT SPEND A RETRY WE DID
        -- NOT MAKE. Both halves matter and the second is the one with teeth.
        --
        -- The flag says the server throttle has lifted. Asking while it is
        -- false is asking to be ignored — which is why Blizzard's own three
        -- consumers all gate on exactly this and nothing else. Incrementing
        -- retryCount for a request the server never saw would let MAX_RETRIES
        -- run out having made ZERO effective attempts, and under build-once
        -- that leaves an empty roster nothing will ever correct.
        --
        -- `~= false` rather than a truthiness test, deliberately: nil means the
        -- caller did not forward the payload, and that must degrade to the old
        -- unconditional behaviour rather than to permanent silence. The event
        -- is documented `Nilable = false`, so on a real client this is always a
        -- boolean; nil only happens if something drives the handler directly.
        --
        -- Not spending a retry is safe because another GUILD_ROSTER_UPDATE is
        -- guaranteed — the client's own calendar loop is what made this library
        -- expensive in the first place — and PLAYER_LOGIN's request is
        -- ungated, so there is always at least one real attempt in flight.
        if canRequestRosterUpdate ~= false then
            self.retryCount = self.retryCount + 1
            RequestGuildRoster()
        end
        return
    end

    -- FGI vendor fix: stabilization phase. Count consecutive events with the
    -- same total and only declare initialized after STABLE_THRESHOLD matches.
    -- Prevents the partial-snapshot misfire where the first event captures a
    -- streaming-in subset of the roster and the second event then diffs the
    -- rest as "joins". See the lib header for the full rationale.
    --
    -- Skipped entirely when a short login build is being FINISHED: the
    -- library is already initialized, the sister sync is already running, and
    -- OnRosterReady has already fired -- a second one would tell every consumer
    -- to redo its login work. OnRosterUpdated and the hash change below are
    -- what announce the completed roster.
    --
    -- `not short` is the half of "stable" the old guard lacked: a total that
    -- holds still across two events while rows are still nil past some index
    -- is a partial stream, not a stable one. Reaching here while short means
    -- the retry budget is spent (a short scan with budget left returned
    -- above), and then the build proceeds on what it has rather than waiting
    -- forever on a client that never fills the rows in -- LoginBuildIsShort
    -- finishes it if they ever do arrive.
    if not finishing then
        local complete = (not short) or self.retryCount >= self.MAX_RETRIES
        if total == self.previousTotal and total > 0 and complete then
            self.stableCount = self.stableCount + 1
        else
            self.stableCount = 0
        end
        self.previousTotal = total

        if self.stableCount >= self.STABLE_THRESHOLD then
            self.initialized = true
            -- BEFORE the ready callback: the home key is resolvable now, so
            -- the persisted sister rosters can be re-fed, and a consumer
            -- reacting to ready must see them already there rather than a
            -- beat later.
            self:StartSisterSync()
            self.callbacks:Fire("OnRosterReady")
        end
    end

    self.callbacks:Fire("OnRosterUpdated")

    -- ⛔ THE POST-REBUILD DIFF WAS DELETED HERE, and what it used to produce is
    -- worth writing down so nobody looks for it and concludes it was lost.
    --
    -- It fired OnMemberOnline, OnMemberRankChanged and OnMemberLevelChanged by
    -- comparing a pre-wipe snapshot against the freshly rebuilt roster, and it
    -- was gated on the library ALREADY being initialized. Build-once returns
    -- before this point once that is true, so the entire block became
    -- unreachable — not redundant, unreachable. It was deleted rather than left
    -- in place because dead code that looks like a live callback source is how a
    -- future session concludes a callback still fires when it cannot.
    --
    -- Where each one lives now:
    --   OnMemberOnline       — MarkMemberOnline, from CHAT_MSG_SYSTEM's "has
    --                          come online" and from guild/officer chat traffic.
    --   OnMemberRankChanged  — the promote/demote branch of ParseSystemMessage.
    --   OnMemberLevelChanged — NOWHERE. It has no event source and no longer
    --                          fires. There is no CHAT_MSG_SYSTEM message for a
    --                          guildmate levelling: GUILD_NEWS_FORMAT6 ("%s has
    --                          reached level %d!") is a Guild News UI feed from
    --                          Cataclysm's guild system, which Classic Era does
    --                          not have, and nothing else announces it. The only
    --                          way to see a level change is to re-read the whole
    --                          roster, which is the thing this design exists to
    --                          stop doing. Documented in CHANGELOG.md as a
    --                          deliberate, accepted loss.
    --
    -- OnMemberJoined and OnMemberLeft were never diff-driven — the roster diff
    -- cannot tell "new member" from "member arriving late in the login stream",
    -- so the chat messages have always been the authoritative signal.

    -- Fire OnRosterHashChanged for the HOME roster when its membership SET
    -- changes — the only way a sister client learns our roster changed so it
    -- can re-pull. The hash is membership-only (see GetRosterHash), so a
    -- presence-only GUILD_ROSTER_UPDATE produces the same hash and stays
    -- silent. Gated to `initialized` so the partial login stream (50 -> 200
    -- members) doesn't churn the hash; the first fire lands on the rebuild
    -- that completes stabilization. homeGuildKey may be unresolved for a beat
    -- at login (GetGuildInfo not ready) — we simply don't fire until it is.
    --
    -- PERF, and it is the reason this guard exists rather than just the
    -- `~=` compare below. "Produces the same hash and stays silent" was true
    -- of the CALLBACK and false of the COST: GetRosterHash was still run on
    -- every single GUILD_ROSTER_UPDATE, and it is the most expensive thing in
    -- this file by a wide margin — it collects every charKey into an array,
    -- table.sorts it, concatenates it, and then runs fnv1a32 over the result,
    -- which is an interpreted per-BYTE loop doing a bxor, two divisions and
    -- four modulos each. A 500-member roster concatenates to roughly 10,000
    -- characters, so a guildmate logging in — a presence change that cannot
    -- move the hash — cost ~10,000 iterations of that loop plus an N log N
    -- sort, on the main thread, every time.
    --
    -- That is the micro-stutter a player reported on TBC Anniversary in
    -- August 2026, tied to guildmates logging in and out. The membership
    -- counters computed during the rebuild answer "did the set move?" in O(N)
    -- table lookups, so the hash is now computed only when it can actually
    -- differ. `homeRosterHash == nil` covers the first hash after login and
    -- after a guild change, where there is no previous value to compare to.
    local membershipChanged = (newCount ~= prevCount) or (matchedCount ~= newCount)
    if membershipChanged or self.homeRosterHash == nil then
        FireHomeRosterHashChanged(self)
    end
end

--- Apply a "came online" transition, if we did not already believe it.
--
-- The single place that transition is written outside the rebuild diff. Both
-- real-time signals route through here — the system announcement parsed by
-- ParseSystemMessage, and a guild/officer chat message seen by OnChatMsgGuild —
-- so the guard, the write and the callback cannot drift apart between them.
-- Adding a third signal means calling this, not copying it.
--
-- Takes an ALREADY-NORMALIZED key and tolerates nil, so a caller can hand it
-- NormalizeName's result without checking first.
-- @param self table
-- @param norm string|nil  a roster key
local function MarkMemberOnline(self, norm)
    local member = norm and self.roster[norm]
    if member then
        -- Stamp on every proof, not only on the transition. Guild chat from
        -- someone already recorded online is still evidence they are there
        -- NOW, and refreshing the stamp is what keeps a long conversation
        -- protected from a stale row that arrives in the middle of it.
        self.recentlyOnline[norm] = GetTime()
        -- The rebuild used to be this table's only reaper. Build-once removed
        -- it, so the prune rides the write instead — see PruneStamps for why
        -- doing it on every chat line is affordable.
        PruneStamps(self)
        if not member.isOnline then
            member.isOnline = true
            -- lastOnline is documented as nil for an online member, and the
            -- login build is its only other writer, so leaving the old tuple
            -- here would hand a consumer isOnline = true alongside "last seen
            -- three days ago" for the rest of the session. Under the pre-0.5.0
            -- design the next rebuild cleared it within seconds; there is no
            -- next rebuild.
            member.lastOnline = nil
            self.callbacks:Fire("OnMemberOnline", norm)
        end
    end
end

--- CHAT_MSG_SYSTEM dispatch: skip while chat is in lockdown, otherwise parse.
--
-- Retail (TWW+) marks CHAT_MSG_SYSTEM payloads as protected "secret" values
-- ONLY during "chat messaging lockdown" — an active Mythic+/Challenge Mode, an
-- in-progress instance encounter, or an active PvP match (the three
-- ChatMessagingLockdownReason states). Outside those windows the payload is an
-- ordinary string. While locked down, ANY operation on the secret payload
-- (compare, match, gsub, concat) taints execution, and that taint leaks into
-- shared UI and surfaces as unrelated Blizzard errors (MoneyFrame, AreaPoiUtil,
-- tooltips).
--
-- So we gate on the lockdown flag and skip parsing entirely while it is set:
-- we never touch a secret value, so no taint is ever produced. This is
-- prevention at the boundary, not the doomed "operate on it, then catch or
-- contain the fallout" approach — operating on the value is itself the harm.
-- ⚠ THE COST OF THIS GREW IN 0.5.0, AND THIS COMMENT USED TO UNDERSTATE IT.
-- Transitions arriving DURING an encounter, M+ or PvP match are not picked up.
-- The old text finished "the next post-lockdown GUILD_ROSTER_UPDATE reconciles
-- membership with accessible roster names" — true when it was written, FALSE
-- now. There is no next rebuild, so a join, leave or kick announced inside a
-- lockdown window is lost for the rest of the session rather than delayed by
-- seconds.
--
-- It is still the right trade and the reasoning above is unchanged: operating
-- on a secret value is itself the harm. It is also retail-only (see below), and
-- normal play is never locked down. But the residual is now a real gap rather
-- than a latency cost, and anyone weighing a reconcile against the build-once
-- directive should weigh THIS rather than the reassurance that used to be here.
--
-- Only retail marks CHAT_MSG_SYSTEM as a secret value under lockdown. As of
-- 12.0.1 C_ChatInfo.InChatMessagingLockdown exists on the Classic clients too,
-- but only retail flags the event with SecretInChatMessagingLockdown — Classic
-- payloads are never tainted. So the IS_RETAIL flag (WOW_PROJECT_MAINLINE), not
-- the mere presence of the API, is the correct discriminator: Classic/TBC/
-- Wrath/Cata/Mists never take this branch and parse exactly as before, while
-- the C_ChatInfo feature-detect is secondary insurance for retail itself.
--
-- This used to add "the same retail guard the SetGuildRosterShowOffline path
-- uses". That path was deleted in 0.5.1, so the comparison pointed at nothing;
-- this is now the ONLY lockdown guard in the library.
-- @param message string
local ParseSystemMessage  -- forward decl; defined below, kept local (see note there)
function lib:OnChatMsgSystem(message)
    if not message then return end
    if IS_RETAIL
        and C_ChatInfo and C_ChatInfo.InChatMessagingLockdown
        and C_ChatInfo.InChatMessagingLockdown() then
        return
    end
    ParseSystemMessage(self, message)
end

--- Guild/officer chat as a presence proof: a message is evidence its sender is
-- online, at the moment it arrives.
--
-- This exists because the "X has come online" system message is not a complete
-- account of who is online. It is missed whenever the client was not listening:
-- the sender logged in before you did, during a UI reload, while the addon was
-- suppressed, or during a retail chat-messaging lockdown window (see
-- OnChatMsgSystem — those transitions are deliberately dropped). Until the next
-- full GUILD_ROSTER_UPDATE rebuild, such a member sits at isOnline = false while
-- visibly talking in guild chat. One table lookup per message closes that,
-- without asking the server for anything.
--
-- Cost, since this is registered against a channel a busy guild uses constantly:
-- a handful of table lookups per message and nothing else. There is no pattern
-- match, no roster read, and above all no RequestGuildRoster — the expensive
-- work is exactly what this path exists to avoid. NormalizeName is memoized on
-- the raw string, so a guild's regular talkers each compute once ever and every
-- later message is a hash lookup. Guild chat peaks in the tens of lines per
-- minute; the roster rebuild this replaces costs milliseconds per event.
--
-- Deliberately one-directional: chat proves online, silence proves nothing. A
-- member who stops talking is not offline, so there is no matching offline
-- inference here — going offline still comes from the system message and the
-- rebuild diff.
--
-- Same retail lockdown gate as OnChatMsgSystem, and for the same reason:
-- CHAT_MSG_GUILD and CHAT_MSG_OFFICER are both flagged
-- SecretInChatMessagingLockdown, and their playerName field is NOT marked
-- NeverSecret (verified in the retail client's ChatInfoDocumentation.lua), so
-- under lockdown the sender name is itself a secret value and normalizing it
-- would taint execution. The gate runs before anything reads the argument.
--
-- @param _ string       the message text; unused, the sender is the whole signal
-- @param sender string  arg2 of CHAT_MSG_GUILD/OFFICER: "Name" or "Name-Realm"
function lib:OnChatMsgGuild(_, sender)
    if IS_RETAIL
        and C_ChatInfo and C_ChatInfo.InChatMessagingLockdown
        and C_ChatInfo.InChatMessagingLockdown() then
        return
    end
    MarkMemberOnline(self, self:NormalizeName(sender))
end

--- Parse one CHAT_MSG_SYSTEM message into guild state transitions.
-- Patterns are built once at file load from Blizzard's localized global
-- format strings (see BuildChatPattern), so this works on every locale
-- rather than only English. Kept file-local (not a lib: method) and reached
-- ONLY through OnChatMsgSystem, which gates it behind the chat-messaging
-- lockdown check — exposing it as a public method would let a consumer call
-- it directly on retail and operate on a secret payload, tainting execution.
-- @param self table  the library
-- @param message string
ParseSystemMessage = function(self, message)
    if message == "" then return end

    -- Cheap relevance pre-filter. CHAT_MSG_SYSTEM is a firehose (loot,
    -- achievements, M+ notices, ...); only a handful of lines are guild
    -- transitions we act on. Each event type has a plain NEEDLE_* (see
    -- BuildChatNeedle) that is a substring of every message its pattern
    -- accepts, so a plain string.find for it on the RAW message is a sound
    -- gate — it can only reject lines the anchored pattern would reject anyway
    -- — and it lets the bulk of traffic exit before we pay for the markup
    -- strip and a capturing match. Only a needle hit strips markup (lazily,
    -- once, shared across branches) and runs the capture that extracts the
    -- name; a nil needle degrades to always attempting the match.
    --
    -- Explicitly initialized: `local stripped` alone makes every `stripped or
    -- ...` below a read of an uninitialized local (luacheck W321). The value is
    -- the same either way, but the declaration should say that nil-before-first-
    -- strip is the intended state rather than leaving it to be inferred.
    local stripped = nil

    -- "[Name] has come online." / locale equivalent
    if CHAT_PATTERNS_ONLINE and (not NEEDLE_ONLINE or message:find(NEEDLE_ONLINE, 1, true)) then
        stripped = stripped or StripChatLinkMarkup(message)
        local onlineName = MatchAny(CHAT_PATTERNS_ONLINE, stripped)
        if onlineName then
            MarkMemberOnline(self, self:NormalizeName(onlineName))
            return
        end
    end

    -- "[Name] has gone offline." / locale equivalent
    if CHAT_PATTERNS_OFFLINE and (not NEEDLE_OFFLINE or message:find(NEEDLE_OFFLINE, 1, true)) then
        stripped = stripped or StripChatLinkMarkup(message)
        local offlineName = MatchAny(CHAT_PATTERNS_OFFLINE, stripped)
        if offlineName then
            local norm = self:NormalizeName(offlineName)
            if norm then
                -- Clear the come-online stamp unconditionally, not only on the
                -- transition. This is a NEWER real-time signal than the one
                -- that set it, so it must win — leaving the stamp would have
                -- the next rebuild resurrect a player we have just been told
                -- logged off, which is the exact failure this machinery exists
                -- to prevent, pointed the wrong way.
                self.recentlyOnline[norm] = nil
                if self.roster[norm] and self.roster[norm].isOnline then
                    self.roster[norm].isOnline = false
                    -- They went offline THIS INSTANT, and this is the only
                    -- place that can know it: GetGuildRosterLastOnline is read
                    -- once during the login build and never again, so without
                    -- this the field stays nil forever for anyone who was
                    -- online at login — or, worse, keeps a stale pre-login
                    -- tuple for someone who logged in and back out. Zeroes are
                    -- the honest value rather than a guess; see the header for
                    -- the drift this does NOT fix.
                    self.roster[norm].lastOnline =
                        { years = 0, months = 0, days = 0, hours = 0 }
                    self.callbacks:Fire("OnMemberOffline", norm)
                end
            end
            return
        end
    end

    -- "[Name] has joined the guild." — fire OnMemberJoined DIRECTLY from
    -- this chat event, not from the GUILD_ROSTER_UPDATE diff.
    --
    -- The diff-based join path is unfixably racy on retail: the roster
    -- streams in across multiple GUILD_ROSTER_UPDATE events after login,
    -- and the server can send several events at the same partial total
    -- before the full roster arrives. A STABLE_THRESHOLD = 2 guard still
    -- misfires when two of those partial events happen to have the same
    -- count -- it "stabilizes" on the partial snapshot, then the next
    -- event's full roster looks like a flood of joins and consumers
    -- welcome every guildmember on login. Reported on retail as
    -- 20+ welcomes firing in [Guild] after /reload on a guild of ~200.
    --
    -- CHAT_MSG_SYSTEM "X has joined the guild" only fires when a real
    -- join happens, never during login roster population. It's also the
    -- authoritative signal the server itself uses to announce joins to
    -- everyone in the guild. NormalizeName handles both Classic
    -- ("Player") and retail cross-realm ("Player-Realm") forms.
    --
    -- THE MEMBER IS ADDED HERE, and that is new in MINOR 14. This branch used
    -- to fire OnMemberJoined and rely on the next rebuild to actually insert
    -- them; under build-once there is no next rebuild, so a join announced and
    -- not inserted would leave IsInGuild answering false about someone chat had
    -- just proved is in the guild — for the rest of the session.
    --
    -- We still RequestGuildRoster(), but for a different reason than before: it
    -- is what makes a GUILD_ROSTER_UPDATE arrive so ResolvePendingDetail can
    -- read the one row we need for class, rank and level. Chat gives a name and
    -- nothing else.
    if CHAT_PATTERNS_JOINED and (not NEEDLE_JOINED or message:find(NEEDLE_JOINED, 1, true)) then
        stripped = stripped or StripChatLinkMarkup(message)
        local joinedName = MatchAny(CHAT_PATTERNS_JOINED, stripped)
        if joinedName then
            local norm = self:NormalizeName(joinedName)
            if norm then
                if not self.roster[norm] then
                    self.roster[norm] = {
                        name        = norm,
                        -- class, rankIndex, rankName and zone stay nil until the
                        -- row arrives: the public shape documents them as
                        -- optional, and inventing a rank would be worse than
                        -- admitting we do not know it yet.
                        --
                        -- `level = 1` is the same invented baseline the login
                        -- build writes for a row with no level — the field is
                        -- documented as always a number. levelUnknown is what
                        -- stops that 1 from later reading as a real ding.
                        level       = 1,
                        -- Online is not a guess. A character has to be logged in
                        -- to accept a guild invitation, so the announcement is
                        -- itself proof of presence at this instant.
                        isOnline    = true,
                        publicNote  = "",
                        officerNote = "",
                        status      = 0,
                        isMobile    = false,
                        -- Same as the login build: the guild rides on the
                        -- character. A joiner is joining OUR guild by
                        -- definition, so this is known, not inferred.
                        guild       = self:GetHomeGuildKey(),
                    }
                    self.levelUnknown[norm]  = true
                    self.pendingDetail[norm] = GetTime()
                end
                -- A rejoin inside the window clears the departure stamp, or the
                -- recently-left machinery would go on suppressing diffs about a
                -- member who is demonstrably back.
                self.recentlyLeft[norm] = nil
                PruneStamps(self)

                -- 2nd arg (home guildKey) added in MINOR 6 so every join/leave
                -- carries the guild it happened in, matching the sister-roster
                -- diff's OnMemberJoined(name, guildKey). One-arg home consumers
                -- harmlessly ignore it; may be nil in the rare pre-resolve window.
                self.callbacks:Fire("OnMemberJoined", norm, self:GetHomeGuildKey())
                -- Membership moved, so the wire hash must move with it. Fired
                -- after OnMemberJoined so a consumer that re-pulls on the hash
                -- sees a roster already containing the new member.
                FireHomeRosterHashChanged(self)
            end
            RequestGuildRoster()
            return
        end
    end

    -- "[Name] has left the guild." or "[Name] has been kicked out of the
    -- guild by [Kicker]." — both arrive as CHAT_MSG_SYSTEM. The kicked
    -- pattern has two captures; we want the first (the player who left).
    if (CHAT_PATTERNS_LEFT and (not NEEDLE_LEFT or message:find(NEEDLE_LEFT, 1, true)))
        or (CHAT_PATTERNS_KICKED and (not NEEDLE_KICKED or message:find(NEEDLE_KICKED, 1, true))) then
        stripped = stripped or StripChatLinkMarkup(message)
        -- LEFT has a single argument, so its capture is the player either way.
        -- KICKED has two — the player and the officer who kicked them — and on
        -- the locales that spell it positionally the player is not necessarily
        -- capture #1, which is what PickArg resolves. Asking for argument 1
        -- rather than capture 1 is the whole difference between naming the
        -- player and naming whoever removed them.
        local leftName = MatchAny(CHAT_PATTERNS_LEFT, stripped)
        if not leftName and CHAT_PATTERNS_KICKED then
            leftName = PickArg(ARGS_KICKED, 1, MatchAny(CHAT_PATTERNS_KICKED, stripped))
        end
        if leftName then
            local norm = self:NormalizeName(leftName)
            if norm and self.roster[norm] then
                self.roster[norm] = nil
                -- Stamp the name into recentlyLeft so the next
                -- GUILD_ROSTER_UPDATE's diff treats this player as "existing"
                -- rather than "new" if the server response is stale and still
                -- includes them. Prevents OnMemberJoined from firing for a
                -- player who literally just left. Stamp lives ~60 s; see
                -- lib header.
                self.recentlyLeft[norm]   = GetTime()
                -- Drop the presence stamp and any outstanding row lookup: both
                -- describe a member who is no longer ours to track, and a
                -- surviving pendingDetail key would keep ResolvePendingDetail
                -- scanning the whole roster for someone who has left.
                self.recentlyOnline[norm] = nil
                self.pendingDetail[norm]  = nil
                PruneStamps(self)
                self.callbacks:Fire("OnMemberLeft", norm, self:GetHomeGuildKey())
                -- Membership moved — same reasoning as the join branch.
                FireHomeRosterHashChanged(self)
            end
            return
        end
    end

    -- "[Officer] has promoted [Name] to [Rank]." / "...has demoted..."
    --
    -- OnMemberRankChanged's ONLY source. It used to come from the post-rebuild
    -- diff, which build-once deleted; without this branch the callback would
    -- have gone permanently silent, and it is not an ornament — a consumer
    -- gating officer-only UI on it would never see a promotion take effect.
    --
    -- Promote and demote are handled by one block because the library reports
    -- the raw transition and lets the consumer decide what it means. The
    -- direction is already implicit in the indices, and in WoW a LOWER index is
    -- a higher rank, so a "promotion" is a decrease — which is exactly the kind
    -- of thing a library should hand over rather than interpret.
    if (CHAT_PATTERNS_PROMOTED and (not NEEDLE_PROMOTED or message:find(NEEDLE_PROMOTED, 1, true)))
        or (CHAT_PATTERNS_DEMOTED and (not NEEDLE_DEMOTED or message:find(NEEDLE_DEMOTED, 1, true))) then
        stripped = stripped or StripChatLinkMarkup(message)

        local movedName, newRankName
        if CHAT_PATTERNS_PROMOTED then
            local a, b, c = MatchAny(CHAT_PATTERNS_PROMOTED, stripped)
            if a then
                movedName   = PickArg(ARGS_PROMOTED, 2, a, b, c)
                newRankName = PickArg(ARGS_PROMOTED, 3, a, b, c)
            end
        end
        if not movedName and CHAT_PATTERNS_DEMOTED then
            local a, b, c = MatchAny(CHAT_PATTERNS_DEMOTED, stripped)
            if a then
                movedName   = PickArg(ARGS_DEMOTED, 2, a, b, c)
                newRankName = PickArg(ARGS_DEMOTED, 3, a, b, c)
            end
        end

        if movedName and newRankName then
            local norm   = self:NormalizeName(movedName)
            local member = norm and self.roster[norm]
            if member then
                local prevRank = member.rankIndex
                -- The name is authoritative — the server just told us. Write it
                -- whether or not we can translate it, so GetMember never reports
                -- a rank the member demonstrably no longer holds.
                member.rankName = newRankName

                local newRank = self.rankIndexByName[newRankName]
                if newRank and newRank ~= prevRank then
                    member.rankIndex = newRank
                    -- prevRank is nil for a member whose row we never read (a
                    -- joiner still pending detail). "Existed in the previous
                    -- roster carrying a rank" is the same precondition the old
                    -- diff enforced, and firing with a nil `from` would hand
                    -- consumers an argument the signature says is a number.
                    if prevRank ~= nil then
                        self.callbacks:Fire("OnMemberRankChanged", norm, prevRank, newRank)
                    end
                end
            end
            return
        end
    end

    -- "No player named '[Name]' is currently playing." -- the server's answer
    -- to a whisper at somebody offline, which is the ONLY way a sister
    -- member's presence stamp is retired before it ages out. The sister pull
    -- is a handshake over WHISPER, and this is the handshake's failure branch;
    -- see OnPeerUnreachable. The message names the target as typed, which for
    -- our sends is the normalized "Name-Realm".
    if CHAT_PATTERNS_NOTFOUND and (not NEEDLE_NOTFOUND or message:find(NEEDLE_NOTFOUND, 1, true)) then
        stripped = stripped or StripChatLinkMarkup(message)
        local who = MatchAny(CHAT_PATTERNS_NOTFOUND, stripped)
        if who then self:OnPeerUnreachable(who) end
    end
end

--- The server said `who` is not online. Every presence stamp we hold for them
-- in any sister roster goes, and a pull addressed to them stops waiting --
-- the next round asks somebody else. Nothing whispers them again until a
-- fresh sighting arrives on the wire. Public so a consumer that whispers
-- sister members itself can forward the same message.
-- @param who string  the name from the system message
-- @return number  stamps cleared
function lib:OnPeerUnreachable(who)
    local norm = self:NormalizeName(who)
    if not norm then return 0 end
    local cleared = 0
    for key, presence in pairs(self.presence) do
        if key ~= self:GetHomeGuildKey() and presence[norm] then
            presence[norm] = nil
            cleared = cleared + 1
        end
    end
    -- A pull addressed to them is retired -- and re-issued NOW to the next
    -- freshest member of that guild, if there is one: the server's answer is
    -- the event, and waiting a round for what it already told us would be
    -- the stopwatch this design does not have.
    local reask = {}
    local whoSlot = string.lower(norm)   -- senderKey of a name already normalized
    for key, pending in pairs(self.sisterSync.pendingPull) do
        if senderKey(self, pending.peer) == whoSlot then
            self.sisterSync.pendingPull[key] = nil
            reask[#reask + 1] = { key = key, relayed = pending.relayed }
        end
    end
    -- Their offers to our guild ask go with them.
    for _, offers in pairs(self.sisterSync.guildOffers) do
        for slot, rec in pairs(offers) do
            if senderKey(self, rec.peer) == whoSlot then offers[slot] = nil end
        end
    end
    -- A guildmate's copy is re-asked of the next guildmate who offered one,
    -- and only then of the sister guild.
    for _, r in ipairs(reask) do
        if not (r.relayed and (self:PullFromGuildOffers(r.key) or self:PullFromGuildmates(r.key))) then
            -- FinishGuildStep true means the guild's copy is current and it
            -- said the sister guild is not asked; then it is not (finding 3).
            if not (r.relayed and self:FinishGuildStep(r.key)) then self:PullFromFreshest(r.key) end
        end
    end
    -- A pull BY NAME addressed to them is answered the same way: not online.
    self.sisterSync.askedPeers[whoSlot] = nil
    -- A refusal names the one member the round keeps re-asking; offline,
    -- they are nobody to ask, so the round stops until a fresh sighting. The
    -- refusal itself is kept: the status line still says why nothing moves.
    for _, refusal in pairs(self.sisterSync.refused) do
        if senderKey(self, refusal.peer) == whoSlot then refusal.gone = true end
    end
    if cleared > 0 then syncEvent(self, "%s is not online (server)", norm) end
    return cleared
end

--- Check if a player is currently a guild member.
-- O(1) lookup once initialized. Falls back to a linear scan before the first
-- full rebuild completes (covers the brief window at login).
-- @param name string - short name or "Name-Realm"
-- @return boolean
--- Does the player hold officer privileges in their guild?
--
-- One predicate for the fleet, requested by ClassicCalendar (see
-- `docs/LIBRARY_CONTRACTS.md` for the full case). It had this written out ten times
-- across five files under TWO incompatible rules: eight sites tested
-- `rankIndex <= 2`, two tested the officer-note permission. Those answer
-- different questions, and the disagreement was not cosmetic — in the very
-- common `0 = GM, 1 = Officer, 2 = Alt` layout every Alt passed the rank tests,
-- so an alt could wipe the guild's whole world-buff dataset while failing the
-- permission test on the config screen next to it.
--
-- **The rule here is the granted PERMISSION, not the rank index**, and that is
-- the whole point rather than an implementation detail. A rank index is a
-- position in a per-guild list that the GM is free to arrange however they
-- like — nothing makes rank 2 an officer — while the officer-note permission is
-- something a GM deliberately granted, and can grant to any rank. A library
-- that shipped the rank-index version would be standardising the bug.
--
-- Flavour note, and it is the reason this is not a one-liner: the API is
-- `C_GuildInfo.CanViewOfficerNote()`. The bare `CanViewOfficerNote` global does
-- not appear in `GlobalAPI.lua` at all and has zero call sites in the Classic
-- Era, Anniversary or retail client source — Blizzard's own guild UI uses the
-- namespaced form on every flavour. The `_G` branch is insurance, not a
-- deprecation fallback, and it is ordered the same way as RequestGuildRoster's.
--
-- Side effect: normalizes `name`, which caches it (bounded — NAME_CACHE_MAX).
-- @param name string|nil  optional; only the player's own name is answerable
-- @return boolean|nil  boolean for the player (false when guildless); nil when
--                      asked about anyone else, which the client cannot answer
function lib:IsOfficer(name)
    -- Membership first: the permission API's answer is meaningless outside a
    -- guild, so it must not be consulted there.
    if not IsInGuild() then return false end

    -- A named member other than the player is UNKNOWABLE, and nil says so.
    -- There is no API for another member's permissions, and the rank index is
    -- the wrong rule — returning false would assert "not an officer" about
    -- someone who may well be one, which is precisely the defect that produced
    -- this request. nil is falsy, so a `SetShown(lib:IsOfficer(n))` call site
    -- still hides rather than erroring, while `== nil` distinguishes the case.
    if name ~= nil then
        local norm = self:NormalizeName(name)
        if not norm or norm ~= self:GetNormalizedPlayer() then return nil end
    end

    local canView = (C_GuildInfo and C_GuildInfo.CanViewOfficerNote) or _G.CanViewOfficerNote
    if not canView then return false end
    return canView() and true or false
end

--- Is this character in the HOME guild?
-- Falls back to a live roster scan before the first build completes.
-- Side effect: normalizes `name`, which caches it (bounded — NAME_CACHE_MAX).
-- @param name string - short name or "Name-Realm"
-- @return boolean
function lib:IsInGuild(name)
    local norm = self:NormalizeName(name)
    if not norm then return false end

    if self.initialized then
        return self.roster[norm] ~= nil
    end

    -- Fallback: roster not yet built — scan the live roster directly.
    -- ReadRosterRow returns the name first, which is all this pre-build lookup
    -- needs (keeps every GetGuildRosterInfo call in the flavor-compat section).
    if not IsInGuild() then return false end
    -- GetNumGuildMembers() returns the TOTAL first, and the iteration is not
    -- filtered by the show-offline setting, so this sees offline members too.
    -- Measured; see the note where the old bracket used to live.
    local found = false
    for i = 1, GetNumGuildMembers() do
        local rosterName = ReadRosterRow(i)
        if rosterName and self:NormalizeName(rosterName) == norm then
            found = true
            break
        end
    end
    return found
end

--- Check whether the lib has completed its first stabilized roster build.
-- Consumers that register callbacks after the lib has already initialized
-- (common on /reload or when the consumer addon loads later than the lib)
-- would otherwise miss the OnRosterReady fire; check IsReady() and run the
-- ready-time logic inline when it returns true.
-- @return boolean
function lib:IsReady()
    return self.initialized == true
end

--- Check if a guild member is currently online.
-- Side effect: normalizes `name`, which caches it (bounded — NAME_CACHE_MAX).
-- A `false` answer still leaves the name cached; the lookup fails, the
-- normalization does not.
-- @param name string - short name or "Name-Realm"
-- @return boolean
function lib:IsOnline(name)
    local norm = self:NormalizeName(name)
    if not norm then return false end
    local member = self.roster[norm]
    return member ~= nil and member.isOnline == true
end

--- Get the full member data table, or nil if not in guild.
-- See the file header for field documentation.
-- Side effect: normalizes `name`, which caches it (bounded — NAME_CACHE_MAX).
-- @param name string - short name or "Name-Realm"
-- @return table|nil
function lib:GetMember(name)
    local norm = self:NormalizeName(name)
    if not norm then return nil end
    return self.roster[norm]
end

--- Get an array of all current guild member names (Name-Realm format).
-- @return table
function lib:GetAllMembers()
    local result = {}
    for name in pairs(self.roster) do
        table.insert(result, name)
    end
    return result
end

--- Get an array of currently online guild member names (Name-Realm format).
-- @return table
function lib:GetOnlineMembers()
    local result = {}
    for name, member in pairs(self.roster) do
        if member.isOnline then
            table.insert(result, name)
        end
    end
    return result
end

-- ===========================================================================
-- Cross-guild (sister-roster) support — MINOR 6, fully additive.
--
-- Everything above this line is HOME-only and unchanged. The methods below
-- add a multi-roster store on top: one self-scanned home roster (lib.roster,
-- queried by the methods above) plus N externally-fed sister rosters. The
-- lib stays framework-agnostic — it knows nothing about how membership or
-- presence arrives; a higher layer feeds it and queries it. UNTIL MINOR 18
-- that higher layer was a consumer with its own SavedVariables and its own
-- DeltaSync host; it is now the sister-sync section further down, in this
-- file, and a consumer that still feeds SetSisterRoster itself is simply a
-- second feeder into the same store.
-- ===========================================================================

-- FNV-1a, 32-bit. The membership-hash algorithm is a FROZEN contract: two
-- clients holding the same membership set must produce a bit-identical hash,
-- and changing the algorithm after ship makes mixed-version peers disagree
-- forever (they'd resync in a loop). Do not alter it.
--
-- Implemented by hand because WoW's Lua is 5.1 with no native integer type:
-- a direct `hash * FNV_PRIME` overflows the 53-bit double mantissa and loses
-- precision. We split the running hash into 16-bit halves so every
-- intermediate product stays well under 2^53 and is therefore exact, then
-- reduce mod 2^32. The byte XOR uses WoW's always-present `bit` library,
-- normalized to unsigned because bit ops return signed 32-bit.
local FNV_OFFSET_32 = 2166136261   -- 0x811c9dc5
local FNV_PRIME_32  = 16777619     -- 0x01000193
local function fnv1a32(str)
    local hash = FNV_OFFSET_32
    for i = 1, #str do
        hash = bit.bxor(hash, string.byte(str, i)) % 4294967296
        local lo = hash % 65536
        local hi = (hash - lo) / 65536
        hash = ((lo * FNV_PRIME_32) + ((hi * FNV_PRIME_32) % 65536) * 65536) % 4294967296
    end
    return string.format("%08x", hash)
end

--- Return the local player's home guild key, "Faction-GuildName".
-- Faction is the locale-independent token from UnitFactionGroup ("Alliance"
-- / "Horde" / "Neutral"); the guild name is GetGuildInfo's raw display name
-- with spaces preserved (e.g. "Horde-The Brave Ones"). Consumers MUST build
-- the identical string or every cross-roster lookup silently matches nothing.
-- Cached like realmName and cleared on the not-in-guild wipe so a guild
-- switch re-resolves. Returns nil when guildless or before guild data loads
-- at login — callers must nil-guard.
-- @return string|nil
function lib:GetHomeGuildKey()
    if self.homeGuildKey then return self.homeGuildKey end
    if not IsInGuild() then return nil end
    local guildName = GetGuildInfo("player")
    if not guildName or guildName == "" then return nil end
    local faction = UnitFactionGroup("player") or "Neutral"
    self.homeGuildKey = faction .. "-" .. guildName

    return self.homeGuildKey
end

--- Get the roster table for a guildKey ({ charKey = member }), or nil.
-- The home key returns the live self-scanned roster; sister keys return the
-- fed roster. nil guildKey never resolves to home.
-- @param guildKey string
-- @return table|nil
function lib:GetRoster(guildKey)
    if not guildKey then return nil end
    local homeKey = self:GetHomeGuildKey()
    if homeKey and guildKey == homeKey then
        return self.roster
    end
    return self.rosters[guildKey]
end

--- Get the opaque metadata last stored for a sister roster via
-- SetSisterRoster, or nil. The lib never interprets meta — it's whatever the
-- consumer passed (e.g. provider charKey + snapshot timestamp for provenance /
-- relay-trust decisions). A SetSisterRoster call that omits meta (passes nil)
-- leaves the previously stored value untouched — meta is cleared only by
-- RemoveSisterRoster — so this returns the most recent NON-nil meta. The home
-- key is never fed, so it has no meta and returns nil.
-- @param guildKey string
-- @return table|nil
function lib:GetRosterMeta(guildKey)
    if not guildKey then return nil end
    return self.rosterMeta[guildKey]
end

--- Array of every guildKey this lib currently knows a roster for.
-- The home key is included only once it has resolved.
-- @return table
function lib:GetKnownRosters()
    local result = {}
    local homeKey = self:GetHomeGuildKey()
    if homeKey then table.insert(result, homeKey) end
    for guildKey in pairs(self.rosters) do
        -- Skip a sister entry colliding with the home key so it isn't listed
        -- twice. BELT AND BRACES as of 2026-08-28: GetHomeGuildKey now DELETES
        -- such an entry the moment the key resolves, and the call above is what
        -- resolves it -- so by the time this loop runs there is nothing to skip.
        -- Kept because the cost is one comparison and the alternative is a
        -- listing that reports the home guild twice if that ever stops holding.
        -- It used to be the ONLY defence, together with GetRoster's shadowing,
        -- and hiding the entry rather than dropping it is what peer-review
        -- finding 29 was about.
        if guildKey ~= homeKey then
            table.insert(result, guildKey)
        end
    end
    return result
end

--- Which roster, if any, contains this charKey? Home takes precedence.
-- A character is in exactly one guild, but a stale snapshot can transiently
-- list someone in two rosters; home wins so the authoritative self-scan is
-- never overruled by a fed roster.
-- Side effect: normalizes `name`, which caches it (bounded — NAME_CACHE_MAX).
-- @param name string - short name or "Name-Realm"
-- @return string|nil  the guildKey, or nil if not in any roster
function lib:IsInAnyRoster(name)
    local norm = self:NormalizeName(name)
    if not norm then return nil end
    if self.roster[norm] then
        -- The char is in the home roster; name it. GetHomeGuildKey may still
        -- be nil in the narrow login window before guild data resolves —
        -- returning nil there is unavoidable (we have no key to hand back).
        return self:GetHomeGuildKey()
    end
    -- SKIP A SISTER ENTRY UNDER THE HOME KEY, and resolve the key here rather
    -- than relying on somebody else having done it (peer-review finding 30).
    -- This is the ONLY accessor that reaches self.rosters on a path which never
    -- consults the home key -- the home branch above calls GetHomeGuildKey, the
    -- loop did not -- which is exactly why it was the one that vouched for a
    -- non-member. The cleanup in OnGuildRosterUpdate removes such an entry, but
    -- only once that event has fired; this guard makes the answer correct
    -- regardless of ordering, and it is a pure read.
    local homeKey = self:GetHomeGuildKey()
    for guildKey, roster in pairs(self.rosters) do
        if guildKey ~= homeKey and roster[norm] then return guildKey end
    end
    return nil
end

--- Is this charKey in the given roster?
-- Side effect: normalizes `name`, which caches it (bounded — NAME_CACHE_MAX).
-- @param guildKey string
-- @param name string - short name or "Name-Realm"
-- @return boolean
function lib:IsInGuildScoped(guildKey, name)
    local roster = self:GetRoster(guildKey)
    if not roster then return false end
    local norm = self:NormalizeName(name)
    if not norm then return false end
    return roster[norm] ~= nil
end

--- Stable membership hash for a roster — hashed over the SORTED charKey set
-- only. It deliberately excludes isOnline, zone, status, rank, and presence
-- so it does not churn every time someone logs in or out; two clients with
-- the same membership produce the identical hash. Returns nil for an unknown
-- roster. See fnv1a32 for the frozen-contract note.
-- @param guildKey string
-- @return string|nil  8 lowercase hex digits
function lib:GetRosterHash(guildKey)
    local roster = self:GetRoster(guildKey)
    if not roster then return nil end
    local keys = {}
    for charKey in pairs(roster) do
        table.insert(keys, charKey)
    end
    table.sort(keys)
    return fnv1a32(table.concat(keys, "\n"))
end

-- The two detail hashes over a { charKey = member } map. Local, not only
-- methods, because a delta is verified against them BEFORE it is stored, when
-- the map is not a roster the library holds yet (takeServedRoster).
local function noteHashOf(roster)
    local parts = {}
    for charKey, m in pairs(roster) do
        local note = m.publicNote
        if type(note) ~= "string" or note == "" then note = m.note end
        if type(note) == "string" and note ~= "" then
            parts[#parts + 1] = charKey .. "\1" .. note
        end
    end
    table.sort(parts)
    return fnv1a32(table.concat(parts, "\n"))
end

local function rankHashOf(roster)
    local parts = {}
    for charKey, m in pairs(roster) do
        local name  = type(m.rankName) == "string" and m.rankName or ""
        local index = type(m.rankIndex) == "number" and tostring(m.rankIndex) or ""
        if name ~= "" or index ~= "" then
            parts[#parts + 1] = charKey .. "\1" .. index .. "\1" .. name
        end
    end
    table.sort(parts)
    return fnv1a32(table.concat(parts, "\n"))
end

--- Stable hash of the PUBLIC NOTES in a roster, membership excluded. The
-- second half of the sync's "has anything changed" question, added because
-- the membership hash deliberately ignores notes (a note edit must not churn
-- the delta base every sister client compares against) -- which meant a note
-- edit reached nobody until the membership happened to move. TOGBankClassic
-- identifies a bank character by its `gbank` public note, so "eventually,
-- when somebody joins or leaves" is not good enough.
--
-- Only members WITH a note contribute, so an empty-note roster hashes the
-- empty string and two clients agree on it. The home roster's field is
-- `publicNote` and a sister one's is `note` (the wire's `pn`, fed through
-- wireToFeed); both are read here, so a roster fed by a consumer that uses
-- either spelling hashes the same.
-- @param guildKey string
-- @return string|nil  8 lowercase hex digits, nil for an unknown roster
function lib:GetRosterNoteHash(guildKey)
    local roster = self:GetRoster(guildKey)
    if not roster then return nil end
    return noteHashOf(roster)
end

--- Stable hash of the RANKS in a roster, membership excluded (MINOR 21). The
-- third half of "has anything changed", for the same reason the note hash
-- exists: rank rides the sister sync so another guild's roster can show it,
-- and without its own hash a copy taken before ranks were sent would never be
-- told it is missing them. A separate hash rather than folded into the note
-- hash, because a MINOR 20 peer computes the note hash over notes alone: fold
-- rank in and every mixed-version pair disagrees on every round, forever.
--
-- Only members WITH a rank contribute -- a copy served by a MINOR 20 provider
-- carries none -- and both the index and the name are hashed, since a guild
-- master can rename a rank without moving anybody.
-- @param guildKey string
-- @return string|nil  8 lowercase hex digits, nil for an unknown roster
function lib:GetRosterRankHash(guildKey)
    local roster = self:GetRoster(guildKey)
    if not roster then return nil end
    return rankHashOf(roster)
end

--- Replace a sister guild's roster (wipe-and-replace), fed from outside.
-- `members` is a list whose entries are either a bare "Name-Realm" charKey
-- string or a { name=, class=, level=, rankName=, rankIndex=, note= } table (a
-- free-form `rank=` is still accepted and stored as-is, and fills rankName when
-- it is a string or rankIndex when it is a number); every name is run
-- through NormalizeName, so callers should feed already-qualified names.
-- `meta` is opaque caller metadata, stored and read back via GetRosterMeta
-- but never interpreted here.
--
-- Ignored when guildKey is the home key — the authoritative self-scan always
-- wins. Diffs against the previous snapshot and fires OnMemberJoined(name,
-- guildKey) / OnMemberLeft(name, guildKey), then OnRosterHashChanged once the
-- set has settled. The FIRST feed for a guild (no previous snapshot) is
-- treated as a baseline: it fires the hash but NOT a join per member, so a
-- consumer re-feeding its persisted roster on every login doesn't re-welcome
-- the whole sister guild each time — the same login-flood that the home path
-- avoids. Membership diffs never fire online/offline; that is presence's job.
--
-- Side effect: EVERY name in `members` is normalized, which caches it, and
-- nothing here validates those names against a roster first. This is the widest
-- of the cache's doors because a consumer typically feeds it straight off the
-- addon channel — which is why the cache is bounded rather than trusting the
-- feed to be roster-shaped. See NAME_CACHE_MAX.
--
-- FEED REALM-QUALIFIED NAMES FOR A CROSS-REALM SISTER GUILD. This normalizes
-- with NormalizeName, which APPENDS THE RECEIVER'S REALM to a bare name -- and
-- a sister roster is by definition a guild that is not ours, so it is the case
-- where assuming our realm is least safe. Feed bare names for a guild on
-- another realm and every member is filed under `Name-OurRealm`: a character
-- who may not exist, that IsInAnyRoster then answers confidently for, and whose
-- `guild` field is written onto that invented identity. Same hazard CanonName
-- exists to avoid on the alt path; the difference is that a roster genuinely
-- needs one consistent key, and for a SAME-realm sister guild -- the common
-- case -- appending the local realm is correct and necessary.
--
-- WHY THIS IS DOCUMENTED RATHER THAN DETECTED. Not because the hazard is
-- undetectable in principle -- it is undetectable FROM WHAT THIS FUNCTION IS
-- CURRENTLY TOLD, which is a sharper and more useful statement (peer review's,
-- 2026-08-27). Every candidate guard fails on one missing fact:
--
--   `guildKey` is `Faction-GuildName` (see GetHomeGuildKey) and carries no
--   realm, so it cannot say whether the sister guild is cross-realm. A consumer
--   supplies that key itself, so one COULD contain a realm -- but this library
--   does not construct it and must not rely on a format it does not own.
--
--   Guessing from the names cannot work either: an all-bare feed is exactly
--   what a CORRECT same-realm feed looks like. Nor does "a foreign realm
--   appears somewhere in the feed, so treat the bare ones as suspect" -- a
--   guild spanning realms A and B, fed by a client on A while we are on A,
--   legitimately sends bare for A-members and `Name-B` for B-members. A foreign
--   realm present says the GUILD spans realms; it says nothing about whose
--   realm BARE means.
--
-- THE WHOLE PROBLEM IN ONE SENTENCE: bare means "the SENDER'S realm", and this
-- function is never told who the sender is. Given the feeder's realm the rule
-- would be exact and need no heuristics -- if the feeder's realm is not ours
-- and any name in the feed is bare, refuse or warn. That is a signature change
-- on a shipped method for a hazard that only bites cross-realm feeds, so it is
-- not being made on a reviewer's say-so; it is recorded here so the option is
-- not rediscovered from scratch. It would NOT go in `meta`, which is
-- contractually opaque -- reading a field out of it would be the library
-- interpreting a table it promises not to interpret.
-- @param guildKey string
-- @param members table   list of charKey strings and/or {name=...} tables
-- @param meta table|nil  opaque, stored under the roster
function lib:SetSisterRoster(guildKey, members, meta)
    if not guildKey or guildKey == "" then return end
    if guildKey == self:GetHomeGuildKey() then return end

    -- Build the replacement roster from the feed.
    local newRoster = {}
    if members then
        for _, entry in ipairs(members) do
            local rawName, class, level, rank, note, rankName, rankIndex
            if type(entry) == "table" then
                rawName, class, level, rank, note =
                    entry.name, entry.class, entry.level, entry.rank, entry.note
                -- `rankName` / `rankIndex` are the home record's spellings,
                -- so a consumer reads a sister member the way it reads
                -- GetMember. The older free-form `rank` still fills whichever
                -- one its type says it is.
                rankName  = entry.rankName
                rankIndex = entry.rankIndex
                if type(rankName) ~= "string" then rankName = type(rank) == "string" and rank or nil end
                if type(rankIndex) ~= "number" then rankIndex = type(rank) == "number" and rank or nil end
            else
                rawName = entry
            end
            local norm = self:NormalizeName(rawName)
            if norm then
                -- `guild` is per-character data, not a separate index: the
                -- character carries which roster it belongs to, so a consumer
                -- holding a member table already knows, without a second lookup
                -- and without the library maintaining a parallel structure that
                -- could drift from this one. Set from the key being fed, which
                -- is authoritative here by construction.
                --
                -- `note` (MINOR 19) is the member's PUBLIC note as the provider
                -- saw it, or nil when empty or when the feed predates it -- a
                -- consumer reads `member.note` and treats nil as "no note",
                -- which is what an old provider or an old library degrades to.
                -- `rankName` / `rankIndex` (MINOR 21) are the same: nil from a
                -- provider that predates them.
                newRoster[norm] = {
                    name = norm, class = class, level = level, rank = rank,
                    rankName = rankName, rankIndex = rankIndex,
                    note = note, guild = guildKey,
                }
            end
        end
    end

    local oldRoster = self.rosters[guildKey]
    self.rosters[guildKey] = newRoster
    -- Only overwrite meta when supplied: a membership-only re-feed (meta nil)
    -- preserves the prior provenance rather than clearing it. See GetRosterMeta.
    if meta ~= nil then self.rosterMeta[guildKey] = meta end

    -- Diff against the previous snapshot. First feed (oldRoster == nil) is a
    -- baseline — no per-member joins, just the hash below.
    if oldRoster then
        for norm in pairs(newRoster) do
            if not oldRoster[norm] then
                self.callbacks:Fire("OnMemberJoined", norm, guildKey)
            end
        end
        local presence = self.presence[guildKey]
        for norm in pairs(oldRoster) do
            if not newRoster[norm] then
                -- Prune the departed member's presence stamp so the overlay
                -- can't leak across a long session of churn (the membership
                -- intersection in GetOnlineMembersScoped would hide it, but it
                -- would still accumulate).
                if presence then presence[norm] = nil end
                self.callbacks:Fire("OnMemberLeft", norm, guildKey)
            end
        end
    end

    -- Settled signal: fire OnRosterHashChanged only if the membership set
    -- actually changed versus what we last announced for this guild.
    local newHash = self:GetRosterHash(guildKey)
    if self.rosterHashes[guildKey] ~= newHash then
        self.rosterHashes[guildKey] = newHash
        -- A guildmate asking us for this roster by relay may hold an older
        -- state of it; this is what their delta is computed from.
        rememberState(self, newHash, toWire(newRoster, "note"))
        self.callbacks:Fire("OnRosterHashChanged", guildKey, newHash)
    end

    -- MINOR 18: the library owns persistence now. A feed for a LISTED guild is
    -- snapshotted to SavedVariables whoever fed it -- DeltaSync's RosterSync,
    -- the GUILD relay, or a consumer still running its own login re-feed --
    -- so the next session starts from it. An unlisted guild is never persisted
    -- (see PersistSisterRoster); that is the accept gate, not an oversight.
    self:PersistSisterRoster(guildKey)
end

--- Stop tracking a sister guild. Silent teardown — drops the roster, its
-- presence overlay, meta, and cached hash, and fires nothing (the caller
-- initiated the removal, so a leave-flood / hash event would be noise).
-- No-op on the home key.
-- @param guildKey string
function lib:RemoveSisterRoster(guildKey)
    if not guildKey or guildKey == self:GetHomeGuildKey() then return end
    self.rosters[guildKey]      = nil
    self.presence[guildKey]     = nil
    self.rosterMeta[guildKey]   = nil
    self.rosterHashes[guildKey] = nil
    -- And the persisted copy (MINOR 18), or the login re-feed resurrects
    -- exactly the roster the caller just removed.
    local db = self:GetSisterDb()
    if db then db.sisterRosters[guildKey] = nil end
end

--- Stamp presence (lastSeenOnline = now) for sister-guild members.
-- Only stamps names that already exist in the sister roster — names not in
-- the roster are ignored. Fires NO callback: sister presence is query-only
-- (pull via GetOnlineMembersScoped), unlike the home CHAT_MSG_SYSTEM path
-- which fires OnMemberOnline/Offline. No-op on the home key, whose presence
-- is authoritative via the live member.isOnline. We only ever record a
-- last-seen timestamp, never a hard offline — presence ages out and
-- self-corrects, because the upstream source is sampled, not exhaustive.
--
-- Side effect, and note the ORDER: every name is normalized — and therefore
-- cached — BEFORE the roster membership check that discards it. "Ignored" means
-- no presence is stamped, not that the name left no trace. Bounded by
-- NAME_CACHE_MAX, which is the point of that ceiling.
--
-- TWO SHAPES (MINOR 22). An ARRAY of names is a FIRST-HAND sighting -- the
-- client just heard from them -- and is stamped now. A MAP { name = age } is
-- a RELAYED sighting, age being how long ago the relayer last saw them, and
-- is stamped `now - age`, never moving an existing stamp backwards and never
-- past PRESENCE_TTL (it would be stale on arrival). Until MINOR 22 a relayed
-- name was stamped at receive time like a first-hand one, and a guild whose
-- members relay every 270 s kept one real sighting alive forever -- A relays
-- X, B stamps X fresh, B relays X, A stamps X fresh -- so "ages out past
-- PRESENCE_TTL" was true of a sighting and false of a guild.
-- @param guildKey string
-- @param names table  array of "Name-Realm", or { ["Name-Realm"] = ageSeconds }
function lib:MarkOnline(guildKey, names)
    if not guildKey or not names then return end
    if guildKey == self:GetHomeGuildKey() then return end
    local roster = self.rosters[guildKey]
    if not roster then return end
    self.presence[guildKey] = self.presence[guildKey] or {}
    local presence = self.presence[guildKey]
    local now = GetTime()
    for k, v in pairs(names) do
        local rawName, age
        if type(k) == "number" then rawName = v else rawName, age = k, tonumber(v) end
        local norm = type(rawName) == "string" and self:NormalizeName(rawName) or nil
        if norm and roster[norm] then
            if age == nil then
                presence[norm] = now
            elseif age >= 0 and age <= self.PRESENCE_TTL then
                local seen = now - age
                if not presence[norm] or presence[norm] < seen then presence[norm] = seen end
            end
        end
    end
    -- A sighting from anywhere settles a /who still owed for that guild:
    -- the click-catcher comes down as soon as it has nothing left to ask.
    if self.whoSync and #self.whoSync.queue > 0 then self:ShowWhoOverlay() end
end

--- Scoped online query. For the home guild, uses the authoritative live
-- member.isOnline (identical to GetOnlineMembers). For a sister guild,
-- returns the members whose presence was stamped within PRESENCE_TTL —
-- membership ∩ fresh-presence. Stale or never-stamped members are simply
-- absent; we never assert offline.
-- @param guildKey string
-- @return table  array of "Name-Realm" strings
function lib:GetOnlineMembersScoped(guildKey)
    local result = {}
    if not guildKey then return result end

    local homeKey = self:GetHomeGuildKey()
    if homeKey and guildKey == homeKey then
        for name, member in pairs(self.roster) do
            if member.isOnline then table.insert(result, name) end
        end
        return result
    end

    local roster = self.rosters[guildKey]
    local presence = self.presence[guildKey]
    if not roster or not presence then return result end
    local now = GetTime()
    for charKey in pairs(roster) do
        local seen = presence[charKey]
        if seen and (now - seen) <= self.PRESENCE_TTL then
            table.insert(result, charKey)
        end
    end
    return result
end

-- ===========================================================================
-- Sister-guild SYNC (MINOR 18) -- the list, the wire, persistence, presence.
--
-- Until MINOR 17 the section above was a STORE and nothing else: a consumer fed
-- it, persisted it, and found peers to pull from. TOGProfessionMaster was that
-- consumer, and the moment TOGTools and TOGBankClassic wanted the same rosters
-- there were three lists that could disagree and three feeders doing
-- wipe-and-replace into one store. The user's words, 2026-09-13: "i need that
-- and i need it to not step on each other" / "probably best to do it in the
-- library". So the list, the gossip, the persistence and the pull now live here,
-- ONCE, and every consumer reads. TOGTools' `docs/DEPENDENCY_CONTRACTS.md`
-- section 3 is the request; `Scanner.lua:200-281` and
-- `TOGProfessionMaster.lua:2052-2400` in TOGPM are the code this is ported from.
--
-- WHAT IS A PORT AND WHAT IS NOT, so nobody "restores" the missing half:
--
--   PORTED AS-IS: the officer-edited name list with a server-time stamp;
--   last-writer-wins config gossip on GUILD (on change, ~20 s after login, every
--   ~12 min); the periodic GUILD relay of every held sister roster with a
--   recently-seen-by-hash suppression so ~one holder relays per interval; the
--   accept gate (an unlisted guild's roster is refused and dropped); persistence
--   of each pulled roster and the login re-feed; the DeltaSync RosterSync host.
--
--   NOT PORTED, BECAUSE IT NEVER EXISTED -- AND NOT TO BE ADDED: the contract
--   described "/who-driven peer discovery" and "MarkOnline fed from the /who
--   poll". TOGPM has neither -- its pull is `/togpm pullroster <Name>`, typed
--   by hand, and its own comment says discovery "comes in a later step". It
--   could not be built as described anyway: `C_FriendList.SendWho` REQUIRES A
--   HARDWARE EVENT (patch 8.2.5, carried into every Classic client --
--   `HasRestrictions = true` in the Classic Era `FriendListDocumentation.lua`,
--   and FastGuildInvite measured "one query per click"), so no timer can call
--   it. The user's ruling, 2026-09-13, on a draft that merely LISTENED for the
--   player's own /who answers: "what are you trying to do with /who, you
--   shouldn't" / "the contract was wrong". So: NO /who OF ANY KIND in this
--   library -- no query, no listener, no C_FriendList reference. Presence comes
--   from the wire, and every source is a PROVEN sighting rather than a sample:
--
--     * a sister member PULLING FROM US (RosterSync's isValidPeer sees the
--       sender) -- they are online right now;
--     * the PROVIDER of a pull we made (meta.via) -- likewise;
--     * the relay: a guildmate who pulled recently forwards who it saw online,
--       so one sighting reaches the whole home guild;
--     * a consumer calling MarkOnline or PullSisterRoster with a name it holds.
--
--   And AUTOMATIC PULLS GO ONLY TO MEMBERS WITH FRESH PRESENCE. A whisper to an
--   offline player prints "No player named 'X' is currently playing." in the
--   player's chat, and FastGuildInvite's presence module records the fleet rule:
--   one probe per name in a free-running sweep is exactly the pattern Blizzard
--   restricted /who to stop, so NOTHING drives blind whispers automatically.
--   When a logoff is missed, the first pull after it draws that very system
--   message from the server, the library parses it (OnPeerUnreachable) and
--   stops asking -- so a logoff costs at most one such line, and it is the
--   server, not a stopwatch, that says so.
--
--   Bootstrap therefore needs ONE proven sighting per sister guild, from either
--   side: a member of theirs pulling from us, or a consumer calling
--   PullSisterRoster with a name (TOGPM's `/togpm pullroster`). From then on
--   the pull response re-stamps its provider and the loop sustains itself.
--
-- PRESENCE_TTL MOVED FROM 120 TO 900 SECONDS, and the reason is above: the
-- old value was documented as "~2x the consumer's /who poll interval", and the
-- sources that replace the poll are sparser. The TTL now has to outlast
-- SISTER_PULL_INTERVAL or the provider of the last pull would be stale before
-- the next one and the loop would stall after one round.
--
-- SavedVariables: `LibGuildRosterDB`, declared in the standalone GuildRoster
-- TOCs. The library reads and writes `_G.LibGuildRosterDB` and nothing else;
-- an embedded copy in an addon whose TOC does not declare it simply holds the
-- table in memory for the session, which is the pre-MINOR-18 behaviour. The
-- header's "nothing is persisted" sentence is therefore narrowed, not broken:
-- the HOME roster is still never persisted, and the build-once rule is
-- untouched. Keyed by HOME guild key, because the list is a statement about
-- which guilds THIS guild federates with, and gossips on THIS guild's channel.
--
-- Everything here is feature-detected and additive. Ace3 is already a hard
-- dependency (it supplies LibStub and CallbackHandler), so AceComm-3.0 and
-- AceSerializer-3.0 are always present in a standalone install, and they are
-- ALL the wire needs: the pull is the library's own two-message exchange over
-- WHISPER (see PullSisterRoster). A first draft put the pull on a DeltaSync
-- RosterSync host; the user asked whether DeltaSync and AceCommQueue were
-- overkill for it, and they were -- see the note above PullSisterRoster.
-- Without AceComm every part of the sync is silent and the store still works.
-- ===========================================================================

lib.SISTER_CFG_PREFIX    = "LibGRxcfg"   -- addon-message prefix, <= 16 chars
lib.SISTER_ROSTER_PREFIX = "LibGRxrst"
lib.SISTER_PULL_PREFIX   = "LibGRxpull"
lib.SISTER_CONFIG_BROADCAST_DELAY    = 20    -- seconds after the roster is ready
lib.SISTER_CONFIG_BROADCAST_INTERVAL = 720   -- TOGPM's ~12-minute timer
lib.SISTER_ROSTER_BROADCAST_DELAY    = 35
lib.SISTER_ROSTER_BROADCAST_INTERVAL = 300
lib.SISTER_ROSTER_SUPPRESS           = 270   -- skip a relay seen this recently
lib.SISTER_PULL_DELAY                = 45
lib.SISTER_PULL_INTERVAL             = 300
lib.SISTER_PULL_SENDER_COOLDOWN      = 120   -- one pull per unknown requester per this
-- SISTER_ROSTER_RELAY_AFTER_PULL (a 10 s timer before relaying a fresh pull)
-- and SISTER_PULL_TIMEOUT (30 s, then the peer's stamp was cleared) were
-- both retired in MINOR 19: the relay is a hash and goes out at once, and a
-- pull is judged by its handshake, never by a stopwatch. See PullSisterRoster.

-- Per-session sync state. `seenRoster[guildKey] = { hash, t }` is the relay
-- suppression; `pendingPull[guildKey] = { peer, at, acked, rounds, relayed }`
-- is the pull in flight, judged by its handshake (see RequestSisterRosters);
-- `states` is the ring of held memberships a delta can be computed from;
-- `lastPull[guildKey]` is the automatic-pull pacing; `candidates`
-- remembers a proven-online requester whose guild is not yet known so it is
-- pulled from once, not on every request it makes; `refused[guildKey] =
-- { peer, at }` is the last provider who answered that their guild does not
-- list us, cleared by any roster or no-change answer for that guild.
lib.sisterSync = lib.sisterSync or {
    started = false, seenRoster = {}, pendingPull = {}, lastPull = {},
    candidates = {}, timers = {},
}
-- Added in MINOR 19; a LibStub upgrade over a MINOR 18 copy (a consumer's
-- embed that loaded first) KEEPS its table, so these are installed on it.
lib.sisterSync.refused       = lib.sisterSync.refused or {}
lib.sisterSync.pendingVerify = lib.sisterSync.pendingVerify or {}   -- [lower(sender)] = { sender, key, hs, at }: a pull awaiting the /who that places them
lib.sisterSync.askedPeers    = lib.sisterSync.askedPeers or {}      -- [lower(peer)] = at: a pull BY NAME with no guild expected, whose one answer is taken from them
lib.sisterSync.guildOffers   = lib.sisterSync.guildOffers or {}     -- [lower(guildKey)] = { [lower(peer)] = { peer, key, h, nh, t, o } }: guildmates' answers to our guild ask (MINOR 20)
lib.sisterSync.guildAsked    = lib.sisterSync.guildAsked or {}      -- [lower(guildKey)] = { [lower(peer)] = true }: guildmates the guild step has whispered (MINOR 20)
-- The AceComm-3.0 embed target. A plain table rather than an AceAddon: AceComm
-- and DeltaSync only ever call RegisterComm / SendCommMessage on it. Kept on
-- the lib so a LibStub upgrade re-uses the registered object instead of
-- registering a second listener. `owner` names it in AceComm's registry, which
-- is how the offline suite finds and evicts a previous test's instance.
lib.comm = lib.comm or { owner = MAJOR }

--- The per-home-guild SavedVariables record, created on first use.
-- @return table|nil  nil while guildless or before the home key resolves
function lib:GetSisterDb()
    local homeKey = self:GetHomeGuildKey()
    if not homeKey then return nil end
    local root = _G.LibGuildRosterDB
    if type(root) ~= "table" then
        root = {}
        _G.LibGuildRosterDB = root
    end
    root.guilds = root.guilds or {}
    local g = root.guilds[homeKey]
    if type(g) ~= "table" then
        g = {}
        root.guilds[homeKey] = g
    end
    if type(g.sisterGuilds) ~= "table" then g.sisterGuilds = {} end
    g.sisterGuildsTs = tonumber(g.sisterGuildsTs) or 0
    if type(g.sisterRosters) ~= "table" then g.sisterRosters = {} end
    return g
end

--- The configured sister guilds, as a SORTED copy of the display names.
-- Empty when nothing is configured or the home key is unresolved. Sorted so
-- two consumers rendering the list agree, and a copy so nobody edits the
-- SavedVariables through it -- edits go through SetSisterGuildNames, which
-- stamps and gossips.
-- @return table  array of guild names
function lib:GetSisterGuildNames()
    local db = self:GetSisterDb()
    local out = {}
    if not db then return out end
    for _, name in ipairs(db.sisterGuilds) do out[#out + 1] = name end
    table.sort(out)
    return out
end

--- The server-time stamp of the held list (0 = holding nothing). Exposed so a
-- consumer's settings UI can say "last changed", and so a spec can assert the
-- last-writer rule without reading the SavedVariables directly.
-- @return number
function lib:GetSisterGuildsTs()
    local db = self:GetSisterDb()
    return db and db.sisterGuildsTs or 0
end

-- Faction-prefixed keys for the configured names, home excluded (you never
-- sister-sync your own guild). Cross-faction confederations cannot sync -- no
-- whisper crosses factions -- so the player's faction is assumed, exactly as
-- GetHomeGuildKey does.
local function sisterKeysFromNames(self, names)
    local keys, set = {}, {}
    local faction = (UnitFactionGroup and UnitFactionGroup("player")) or "Neutral"
    local homeKey = self:GetHomeGuildKey()
    for _, name in ipairs(names) do
        local key = faction .. "-" .. name
        if key ~= homeKey then
            keys[#keys + 1] = key
            set[string.lower(key)] = true
        end
    end
    return keys, set
end

--- The configured sister guilds as "Faction-GuildName" keys, sorted.
-- @return table
function lib:GetSisterGuildKeys()
    local keys = sisterKeysFromNames(self, self:GetSisterGuildNames())
    return keys
end

--- Is this guild key one of the configured sister guilds?
-- CASE-INSENSITIVE, deliberately: the list is typed by an officer while every
-- key that arrives over the wire is spelled the way the PROVIDER's client
-- spells its own guild, and one capital letter must not make a whole guild
-- "unlisted". The single source of truth for "may this guild's roster be
-- accepted, persisted, relayed or pulled" -- every gate below calls it.
-- @param guildKey string
-- @return boolean
function lib:IsSisterGuildKey(guildKey)
    if type(guildKey) ~= "string" or guildKey == "" then return false end
    local _, set = sisterKeysFromNames(self, self:GetSisterGuildNames())
    return set[string.lower(guildKey)] == true
end

-- The bare name a /who can be asked about: "Name-Realm" -> "Name".
local function bareName(name)
    return (tostring(name):match("^([^%-]+)")) or tostring(name)
end

-- Forget the per-session sync state of a guild that left the list: the pull
-- in flight, the pacing, the refusal, the server's rows, and every asker
-- waiting on a /who for it (with the by-name query that verification owed).
-- Left alone, a waiting asker for an unlisted guild was still decided --
-- refused as "notmember" by RecheckPendingVerify, the wrong reason -- and
-- its /who kept the overlay up for a guild nobody lists any more.
local function forgetSyncState(self, key)
    local ss, ws = self.sisterSync, self.whoSync
    local lower = string.lower(key)
    for k in pairs(ss.pendingPull) do
        if string.lower(k) == lower then ss.pendingPull[k] = nil end
    end
    for k in pairs(ss.lastPull) do
        if string.lower(k) == lower then ss.lastPull[k] = nil end
    end
    ss.refused[lower] = nil
    ss.guildOffers[lower] = nil
    ss.guildAsked[lower] = nil
    ws.afterGuild[lower] = nil
    for k in pairs(ws.candidates) do
        if string.lower(k) == lower then ws.candidates[k] = nil end
    end
    for slot, rec in pairs(ss.pendingVerify) do
        if string.lower(rec.key) == lower then
            ss.pendingVerify[slot] = nil
            ws.nameQueries[string.lower(bareName(rec.sender))] = nil
        end
    end
    if ws.gwOwed and string.lower(ws.gwOwed) == lower then ws.gwOwed = nil end
end

-- Apply a new name list: replace, stamp, tear down whatever was dropped, tell
-- the consumers. Shared by the officer edit and the gossip adoption so the two
-- cannot diverge on what "the list changed" means.
local function applySisterGuilds(self, db, names, ts, source)
    local oldKeys = {}
    for _, key in ipairs(self:GetSisterGuildKeys()) do oldKeys[key] = true end
    -- Also whatever we HOLD or have PERSISTED, under the wire's spelling: a
    -- roster whose guild is no longer listed must go regardless of case, and
    -- a persisted copy with no in-memory roster (a re-feed that has not run
    -- yet) would otherwise be forgotten only at the next login.
    for _, key in ipairs(self:GetKnownRosters()) do
        if key ~= self:GetHomeGuildKey() then oldKeys[key] = true end
    end
    for key in pairs(db.sisterRosters) do oldKeys[key] = true end

    db.sisterGuilds   = names
    db.sisterGuildsTs = ts

    -- A guild that left the list is torn down: roster, presence, meta, hash and
    -- the persisted copy, all in RemoveSisterRoster, so the login re-feed
    -- cannot resurrect it. Ported from TOGPM's DropSisterGuildData.
    for key in pairs(oldKeys) do
        if not self:IsSisterGuildKey(key) then
            self:RemoveSisterRoster(key)
            forgetSyncState(self, key)
        end
    end
    -- A /who owed only for a dropped guild is pruned, and the catcher goes
    -- down with it.
    self:ShowWhoOverlay()
    self.callbacks:Fire("OnSisterConfigChanged", self:GetSisterGuildNames(), ts, source)
end

--- Replace the sister-guild list. OFFICER-ONLY, decided by lib:IsOfficer():
-- the list federates to every member, so letting anyone edit it lets one
-- person redirect or grief the whole guild's cross-guild sharing. Members
-- receive it by gossip instead. Names are trimmed and de-duplicated
-- case-insensitively; empty entries are dropped. Stamps server time so this
-- edit wins the last-writer race, tears down any guild dropped from the list,
-- and gossips the result to the home guild immediately.
-- @param names table|string  array of guild names, or newline-separated text
-- @return boolean ok, string|nil reason ("not-officer" | "no-guild")
function lib:SetSisterGuildNames(names)
    local db = self:GetSisterDb()
    if not db then return false, "no-guild" end
    if not self:IsOfficer() then return false, "not-officer" end

    local list = names
    if type(names) == "string" then
        list = {}
        for line in string.gmatch(names, "[^\r\n]+") do list[#list + 1] = line end
    elseif type(names) ~= "table" then
        list = {}
    end

    local out, seen = {}, {}
    for _, raw in ipairs(list) do
        if type(raw) == "string" then
            local name = string.gsub(string.gsub(raw, "^%s+", ""), "%s+$", "")
            local lower = string.lower(name)
            if name ~= "" and not seen[lower] then
                seen[lower] = true
                out[#out + 1] = name
            end
        end
    end

    local ts = (GetServerTime and GetServerTime()) or (time and time()) or 0
    -- A same-second re-edit must still win over the value it replaces, or the
    -- gossip's strictly-newer rule would treat it as a duplicate.
    if ts <= db.sisterGuildsTs then ts = db.sisterGuildsTs + 1 end
    applySisterGuilds(self, db, out, ts, "local")
    self:BroadcastSisterConfig()
    return true
end

-- ---------------------------------------------------------------------------
-- Comm plumbing
-- ---------------------------------------------------------------------------

-- Both Ace3 libraries, resolved lazily so a spec (or an embedder without Ace3)
-- can be missing either and the gossip goes quiet instead of erroring.
local function commReady(self)
    local comm = self.comm
    if type(comm.SendCommMessage) ~= "function" then
        local AceComm = LibStub("AceComm-3.0", true)
        if not (AceComm and AceComm.Embed) then return nil end
        AceComm:Embed(comm)
    end
    local serializer = LibStub("AceSerializer-3.0", true)
    if not serializer then return nil end
    return comm, serializer
end

local function serialize(serializer, payload)
    local ok, msg = pcall(serializer.Serialize, serializer, payload)
    if ok and type(msg) == "string" then return msg end
    return nil
end

local function deserialize(serializer, message)
    if type(message) ~= "string" then return nil end
    local ok, success, payload = pcall(serializer.Deserialize, serializer, message)
    if ok and success and type(payload) == "table" then return payload end
    return nil
end

-- Register both prefixes once. Idempotent: CallbackHandler overwrites a
-- re-registration for the same object and prefix rather than stacking it.
local function registerComm(self)
    local comm, serializer = commReady(self)
    if not comm then return false end
    if self.sisterSync.commRegistered then return true end
    comm:RegisterComm(self.SISTER_CFG_PREFIX, function(prefix, message, distribution, sender)
        self:OnSisterConfigComm(prefix, message, distribution, sender, serializer)
    end)
    comm:RegisterComm(self.SISTER_ROSTER_PREFIX, function(prefix, message, distribution, sender)
        self:OnSisterRosterComm(prefix, message, distribution, sender, serializer)
    end)
    comm:RegisterComm(self.SISTER_PULL_PREFIX, function(prefix, message, distribution, sender)
        self:OnSisterPullComm(prefix, message, distribution, sender)
    end)
    self.sisterSync.commRegistered = true
    return true
end

-- Is this addon-message sender the local player? Both spellings, because a
-- GUILD send is echoed back with the realm attached and the player's own key
-- may still be bare in the login window.
local function isOwnMessage(self, sender)
    local me = self:GetNormalizedPlayer()
    if not me then return false end
    if sender == me then return true end
    local norm = self:NormalizeName(sender)
    return norm ~= nil and norm == me
end

--- Gossip the held list on GUILD. No-op while guildless (the client refuses
-- the send and, with a queue installed, the refusal lands in the player's bug
-- catcher), and no-op while holding nothing (ts 0): an empty list never
-- participates in the last-writer race, so a member who has never received a
-- config cannot overwrite a real one.
-- @return boolean  whether a message was handed to the comm layer
function lib:BroadcastSisterConfig()
    local db = self:GetSisterDb()
    if not db or db.sisterGuildsTs <= 0 then return false end
    local comm, serializer = commReady(self)
    if not comm then return false end
    local msg = serialize(serializer, { g = db.sisterGuilds, t = db.sisterGuildsTs })
    if not msg then return false end
    comm:SendCommMessage(self.SISTER_CFG_PREFIX, msg, "GUILD", nil, "NORMAL")
    syncEvent(self, "gossiped the list to the guild")
    return true
end

--- A guildmate gossiped its list. Last-writer-wins by stamp; a strictly-newer
-- config is adopted WITHOUT re-stamping (the origin stamp is what makes the
-- gossip converge) and without re-broadcasting (the on-change send already
-- reached every online member; the periodic timer covers latecomers).
function lib:OnSisterConfigComm(prefix, message, _, sender, serializer)
    if prefix ~= self.SISTER_CFG_PREFIX then return end
    if isOwnMessage(self, sender) then return end
    sender = self:NormalizeName(sender) or sender   -- see OnSisterPullComm
    local db = self:GetSisterDb()
    if not db then return end
    serializer = serializer or LibStub("AceSerializer-3.0", true)
    if not serializer then return end
    local payload = deserialize(serializer, message)
    if not payload then return end
    local incomingTs = tonumber(payload.t) or 0
    if incomingTs <= db.sisterGuildsTs then return end
    if type(payload.g) ~= "table" then return end

    local clean = {}
    for _, name in ipairs(payload.g) do
        if type(name) == "string" and name ~= "" then clean[#clean + 1] = name end
    end
    applySisterGuilds(self, db, clean, incomingTs, sender)
    syncEvent(self, "adopted the list from %s", tostring(sender))
end

-- ---------------------------------------------------------------------------
-- Persistence
-- ---------------------------------------------------------------------------

--- Snapshot a held sister roster into SavedVariables. Only for a LISTED guild:
-- the accept gate is the list, and persisting an unlisted roster would let the
-- re-feed resurrect it after the list dropped it.
-- @param guildKey string
-- @return boolean  whether a copy was written
function lib:PersistSisterRoster(guildKey)
    if not self:IsSisterGuildKey(guildKey) then return false end
    local roster = self.rosters[guildKey]
    if not roster then return false end
    local db = self:GetSisterDb()
    if not db then return false end
    local members = {}
    for charKey, m in pairs(roster) do
        members[#members + 1] = {
            name = charKey, class = m.class, level = m.level, rank = m.rank, note = m.note,
            rankName = m.rankName, rankIndex = m.rankIndex,
        }
    end
    db.sisterRosters[guildKey] = {
        members = members,
        meta    = self.rosterMeta[guildKey],
        fedAt   = (GetServerTime and GetServerTime()) or nil,
    }
    return true
end

--- Re-feed every persisted sister roster, so cross-guild queries answer before
-- the first live pull of the session. A persisted roster whose guild is no
-- longer listed is forgotten instead. Runs from StartSisterSync; public so a
-- consumer that changed the list can re-run it, and so it can be specced.
-- @return number  rosters fed
function lib:RefeedSisterRosters()
    local db = self:GetSisterDb()
    if not db then return 0 end
    local n = 0
    for guildKey, entry in pairs(db.sisterRosters) do
        if not self:IsSisterGuildKey(guildKey) then
            db.sisterRosters[guildKey] = nil
        elseif type(entry) == "table" and type(entry.members) == "table" then
            self:SetSisterRoster(guildKey, entry.members, entry.meta)
            n = n + 1
        end
    end
    return n
end

-- ---------------------------------------------------------------------------
-- The member on the wire -- ONE shape for the pull response and the GUILD relay
-- ---------------------------------------------------------------------------

-- A received `m` list into SetSisterRoster's feed shape. Entries without a
-- string name are dropped; `found(norm)` is called per kept entry so the pull
-- path can run its provider-present check in the same pass. Rank is typed
-- here, not trusted: it comes off the wire and is concatenated into a hash.
local function wireToFeed(self, list, found)
    local members = {}
    for _, e in ipairs(list) do
        if type(e) == "table" and type(e.n) == "string" then
            members[#members + 1] = {
                name = e.n, class = e.c, level = e.l, note = e.pn,
                rankName  = type(e.rn) == "string" and e.rn or nil,
                rankIndex = type(e.ri) == "number" and e.ri or nil,
            }
            if found then found(self:NormalizeName(e.n)) end
        end
    end
    return members
end

-- The spelling a listed guild's roster is HELD under, or nil. The list is typed
-- by an officer and a held key is spelled by the provider's client, so they can
-- differ by case (see IsSisterGuildKey).
local function heldKey(self, key)
    local lower = string.lower(key)
    for _, k in ipairs(self:GetKnownRosters()) do
        if string.lower(k) == lower then return k end
    end
    return nil
end

-- When the copy we hold was last known CURRENT, on the provider's server
-- clock: the later of when it was taken (`ts`) and when a provider last
-- answered "no change" to it (`confirmed`, MINOR 20). Without the second half
-- a copy confirmed unchanged every five minutes all afternoon still read as
-- taken at lunchtime, and a guildmate asking "is anyone's copy newer than
-- mine?" could not tell a stale copy from a current one with the same hash.
-- nil when neither is known (a consumer-fed roster).
local function copyStamp(self, key)
    local meta = self.rosterMeta[key]
    if type(meta) ~= "table" then return nil end
    local ts, confirmed = tonumber(meta.ts), tonumber(meta.confirmed)
    if ts and confirmed then return math.max(ts, confirmed) end
    return ts or confirmed
end

-- A guildmate has just given us, or vouched for, a copy last known current at
-- `stamp`. The cross-guild pull clock restarts AS OF THAT MOMENT, not as of
-- now: a copy a guildmate took from the sister guild a minute ago defers our
-- own cross-guild pull a whole interval (the bank model), while a copy that was
-- last current an hour ago defers nothing, so the round still goes to the
-- sister guild after the guild sync. Pacing, never judging -- the round reads
-- it exactly as it reads a pull of its own. Never moves the clock BACKWARDS.
-- THE ONE STAMP ORDERING. True only when both stamps are known and `theirs` is
-- strictly older. Every "is this copy older?" in the sync goes through here:
-- until the MINOR 20 audit the comparison was written out at four sites with
-- four slightly different nil rules. A MISSING stamp is not "older" -- where no
-- stamp must mean "drop", that is said explicitly at the site.
local function olderThan(theirs, ours)
    return theirs ~= nil and ours ~= nil and theirs < ours
end

-- Record that a copy we hold was current at `stamp` -- a provider's or a
-- guildmate's "unchanged", or a guildmate's same-copy confirmation. Only a
-- library-built record (it names a provider) is written; a consumer's meta is
-- opaque (see SetSisterRoster). Never moves `confirmed` backwards. One place,
-- because the confirmation was written out twice and the two copies had
-- already drifted apart on who they accepted it from.
local function confirmCopy(self, held, stamp)
    local meta = held and self.rosterMeta[held]
    if stamp and type(meta) == "table" and meta.provider and stamp > (copyStamp(self, held) or 0) then
        meta.confirmed = stamp
    end
end

local function restartPullClock(self, key, stamp)
    local age = 0
    local now = GetServerTime and GetServerTime()
    if stamp and now and now > stamp then age = math.min(now - stamp, self.SISTER_PULL_INTERVAL) end
    local at = GetTime() - age
    local last = self.sisterSync.lastPull[key]
    if not last or at > last then self.sisterSync.lastPull[key] = at end
end

-- THE DETAIL HALF OF "SAME COPY": does a peer's note hash and rank hash agree
-- with what we hold of `key`? Absent is "cannot judge", never "differs" -- a
-- MINOR 19 first cut sends no note hash and anything before MINOR 21 no rank
-- hash, and judging them on what they cannot say would re-pull between mixed
-- versions forever. One function because the notes half of this test was
-- written out at six sites, and the rank hash had to reach every one of them;
-- the relay suppression compares two stored hashes and keeps its own form.
local function detailsMatch(self, key, noteHash, rankHash)
    return (noteHash == nil or noteHash == self:GetRosterNoteHash(key))
        and (rankHash == nil or rankHash == self:GetRosterRankHash(key))
end

-- ---------------------------------------------------------------------------
-- Roster relay on GUILD
-- ---------------------------------------------------------------------------

-- The sightings a relay carries: { ["Name-Realm"] = seconds since we last saw
-- them }, for every member of the sister roster seen within PRESENCE_TTL. THE
-- AGE IS THE FIX (MINOR 22): a receiver stamps `now - age`, so a sighting is
-- exactly as old on every client as on the one that made it and ages out on
-- schedule; a bare name list was re-stamped fresh at every hop. Whole
-- seconds -- the wire needs no finer.
local function freshPresence(self, guildKey)
    local ages = {}
    local presence = self.presence[guildKey]
    if not presence then return ages end
    local now = GetTime()
    for _, charKey in ipairs(self:GetOnlineMembersScoped(guildKey)) do
        ages[charKey] = math.floor(now - presence[charKey])
    end
    return ages
end

-- The `o` a peer sent, if it is the MINOR 22 map. A bare name list from a
-- 0.8.x peer is NOT a sighting we can date, so it is dropped rather than
-- stamped fresh -- stamping it would put this client back into the loop
-- described at MarkOnline. Nil for anything else.
local function relayedPresence(o)
    if type(o) ~= "table" then return nil end
    local k = next(o)
    if type(k) ~= "string" then return nil end
    return o
end

--- Relay every held sister roster's HASH to the home guild, unless the same
-- hash was seen circulating within SISTER_ROSTER_SUPPRESS. Whoever relays
-- records its own send, so the duty rotates rather than pinning one member,
-- and whoever holds it can take over when the usual relayer logs off.
-- Carries the names we have seen online recently, so one proven sighting
-- reaches every member's presence overlay.
--
-- HASH ONLY, since MINOR 19. Until then every relay carried the whole roster
-- -- ~44 KB on GUILD every five minutes for a 985-member sister, to members
-- who already held it -- and that was the largest thing on the wire by far.
-- Now it is a hundred bytes; a guildmate whose copy differs asks the relayer
-- for it over the whisper handshake (OnSisterRosterComm), and gets a delta
-- when the relayer has the state they hold. A member with no library
-- receives nothing either way, exactly as before.
-- @return number  rosters relayed
function lib:BroadcastSisterRosters()
    local homeKey = self:GetHomeGuildKey()
    if not homeKey then return 0 end
    if #self:GetSisterGuildNames() == 0 then return 0 end
    local comm, serializer = commReady(self)
    if not comm then return 0 end

    -- GetTime, not server time: this is "how long ago did I last see this
    -- circulate", a local interval, and the frame clock is the one that cannot
    -- jump. Same clock as every other stamp in sisterSync and in presence.
    local now = GetTime()
    local seenRoster = self.sisterSync.seenRoster
    local sent = 0
    for _, key in ipairs(self:GetKnownRosters()) do
        if key ~= homeKey and self:IsSisterGuildKey(key) and next(self.rosters[key]) then
            local hash = self:GetRosterHash(key)
            local noteHash = self:GetRosterNoteHash(key)
            local rankHash = self:GetRosterRankHash(key)
            -- WHEN the copy we are relaying was taken, from its original
            -- provider's clock (rosterMeta.ts, set by whoever served it). The
            -- receiver compares it with its own before pulling: a relay is an
            -- offer, and an older copy is not an upgrade. Absent on a copy a
            -- consumer fed us with no meta, and on a MINOR 19 first-cut relay.
            -- Since MINOR 20 it is when the copy was last known current
            -- (copyStamp), which a "no change" answer moves forward.
            local stamp = copyStamp(self, key)
            local seen = seenRoster[key]
            -- An unstamped copy is not relayed: every receiver drops it.
            -- A circulating relay that carried no note hash (a MINOR 19 first
            -- cut) or no rank hash (before MINOR 21) says nothing about them,
            -- so it does not force a re-relay: absent is "cannot judge", never
            -- "differs", the same rule the serve and receive sides use.
            if stamp and not (seen and seen.hash == hash
                and (seen.notes == nil or seen.notes == noteHash)
                and (seen.ranks == nil or seen.ranks == rankHash)
                and (now - seen.t) < self.SISTER_ROSTER_SUPPRESS) then
                local msg = serialize(serializer, {
                    k = key, h = hash, nh = noteHash, rh = rankHash, t = stamp, o = freshPresence(self, key),
                })
                if msg then
                    comm:SendCommMessage(self.SISTER_ROSTER_PREFIX, msg, "GUILD", nil, "NORMAL")
                    seenRoster[key] = { hash = hash, notes = noteHash, ranks = rankHash, t = now }
                    sent = sent + 1
                    syncEvent(self, "relayed %s to the guild", key)
                end
            end
        end
    end
    return sent
end

-- ---------------------------------------------------------------------------
-- The guild ask: IN GUILD FIRST (MINOR 20)
--
-- The user, 2026-09-16: "we should ask our guildmates first if they have a
-- newer sister guild bank list. the idea is to sync IN guild first using
-- deltasync and the guild channel for a broadcast, then do the same
-- handshakes we do with the sister guild with the guild members".
--
-- Until this a client coming online went straight to the sister guild -- a
-- /who or the confederation ask, then a cross-guild pull -- although the
-- guildmate next to it had pulled that roster two minutes earlier. The relay
-- only reached it when somebody's next relay round came up, up to five
-- minutes later, and a client holding nothing of a guild never relayed at all.
--
--   ask      GUILD   { q = 1, w = { [lower(guildKey)] = { h, nh, rh, t } } }
--            one message for every listed guild: what we hold (an empty
--            entry for a guild we hold nothing of). `rh` since MINOR 21.
--   offer    WHISPER { f = 1, k, h, nh, rh, t, o }   on the PULL prefix
--            a guildmate whose copy DIFFERS and is not older says so; the
--            asker pulls from the best offer (newest `t`, then the most
--            compatible version) with the ordinary q = 2 handshake, which
--            answers with a DeltaSync delta whenever the guildmate holds the
--            state the asker has.
--            The same shape with the SAME hash is a CONFIRMATION: our copy is
--            identical to theirs and they know it was current more recently
--            than we do. Sent only when our stamp is at least an interval old
--            and theirs is not, so after a relog the handful of guildmates who
--            actually pulled recently answer -- not the whole guild.
--   A guildmate whose own copy is OLDER than the asker's pulls from the asker
--   instead (the ask proves the asker is online). Everyone else is silent.
--
-- Then the sister guild. The copy the guild hands over restarts the cross-guild
-- pull clock as of when it was last current (restartPullClock), so a fresh
-- guild copy means no cross-guild traffic this interval, and a stale one means
-- the round still goes to the sister guild after it. The discovery owed at
-- login is held while a guildmate's copy is on its way and dropped if that copy
-- turns out current (see waitingOnGuild in the /who section). No timer decides
-- any of this: every step is a message arriving.
-- ---------------------------------------------------------------------------

--- Ask the home guild what it holds of every listed sister guild. Sent at login
-- (StartSisterSync); public so a consumer or a spec can ask again.
-- @return boolean  whether a message was handed to the comm layer
function lib:AskGuildForSisterRosters()
    if not self:GetHomeGuildKey() then return false end
    local keys = self:GetSisterGuildKeys()
    if #keys == 0 then return false end
    local comm, serializer = commReady(self)
    if not comm then return false end
    local want = {}
    for _, key in ipairs(keys) do
        local held = heldKey(self, key)
        local entry = {}
        if held and next(self.rosters[held]) then
            entry.h, entry.nh, entry.rh, entry.t = self:GetRosterHash(held), self:GetRosterNoteHash(held),
                self:GetRosterRankHash(held), copyStamp(self, held)
        end
        want[string.lower(key)] = entry
    end
    local msg = serialize(serializer, { q = 1, w = want })
    if not msg then return false end
    comm:SendCommMessage(self.SISTER_ROSTER_PREFIX, msg, "GUILD", nil, "NORMAL")
    syncEvent(self, "asked the guild for newer sister rosters")
    return true
end

-- A guildmate's ask, answered per listed guild we hold (see the note above).
local function answerGuildAsk(self, sender, payload)
    if type(payload.w) ~= "table" or not self.initialized or not self:IsInGuild(sender) then return end
    local comm, serializer = commReady(self)
    if not comm then return end
    local homeKey = self:GetHomeGuildKey()
    local now = (GetServerTime and GetServerTime()) or 0
    for _, key in ipairs(self:GetKnownRosters()) do
        local theirs = payload.w[string.lower(key)]
        if key ~= homeKey and type(theirs) == "table" and self:IsSisterGuildKey(key) and next(self.rosters[key]) then
            local hash = self:GetRosterHash(key)
            local ours, theirStamp = copyStamp(self, key), tonumber(theirs.t)
            local offer = false
            if theirs.h == hash and detailsMatch(self, key, theirs.nh, theirs.rh) then
                offer = ours ~= nil and (now - ours) < self.SISTER_PULL_INTERVAL
                    and (theirStamp == nil or (now - theirStamp) >= self.SISTER_PULL_INTERVAL)
            elseif olderThan(ours, theirStamp) then
                if not self.sisterSync.pendingPull[key] then
                    self:PullSisterRoster(sender, key, { relayed = true })
                end
            else
                -- Only a copy we can vouch for is offered: an offer with no
                -- stamp is dropped by every receiver.
                offer = ours ~= nil
            end
            if offer then
                local msg = serialize(serializer, {
                    f = 1, k = key, h = hash, nh = self:GetRosterNoteHash(key), rh = self:GetRosterRankHash(key),
                    t = ours, o = freshPresence(self, key),
                })
                if msg then
                    comm:SendCommMessage(self.SISTER_PULL_PREFIX, msg, "WHISPER", sender, "NORMAL")
                    syncEvent(self, "offered %s our copy of %s", tostring(sender), key)
                end
            end
        end
    end
end

--- A home guildmate relayed a sister roster's hash and stamp. Gated by the
-- list, and DROPPED WITHOUT A STAMP (see below). A hash we already hold is
-- noted as circulating and nothing more; a different one that is not older is
-- PULLED from the relayer over the whisper handshake -- they just spoke on
-- GUILD, so the whisper is not blind -- and lands through takeServedRoster as
-- second-hand. Presence carried with it is stamped either way -- a sighting is
-- a sighting whether or not the membership moved. NOT re-broadcast: the
-- suppression above is what keeps the relay from echoing around the guild.
function lib:OnSisterRosterComm(prefix, message, _, sender, serializer)
    if prefix ~= self.SISTER_ROSTER_PREFIX then return end
    if isOwnMessage(self, sender) then return end
    sender = self:NormalizeName(sender) or sender   -- see OnSisterPullComm
    serializer = serializer or LibStub("AceSerializer-3.0", true)
    if not serializer then return end
    local payload = deserialize(serializer, message)
    if not payload then return end
    -- The guild ask carries no `k`, so a MINOR 19 receiver drops it at the
    -- list gate below and nothing else changes for it.
    if payload.q == 1 then
        answerGuildAsk(self, sender, payload)
        return
    end
    local key = payload.k
    if not self:IsSisterGuildKey(key) then return end
    -- A relay is a GUILDMATE's. Anyone can whisper on this prefix, and until
    -- MINOR 20 a stranger's "same hash" restarted our pull clock -- enough to
    -- keep a client from ever pulling (this session's audit).
    if not self:IsInGuild(sender) then return end
    -- NO STAMP, NOT PROCESSED -- not applied, not pulled, not counted as
    -- circulating, not a sighting. The user, 2026-09-16: "why can't we just
    -- have it if they don't send the hash with the embedded timestamp WE DROP
    -- it and don't process it?" It followed "I FULLY synced the sister roster
    -- yesterday with 280 members. logging on today it's 'back' to 27": the
    -- 0.7.0 relay is `{ k, h, m, o }` on GUILD every five minutes with no `t`
    -- (read at the GuildRoster-v0.7.0 tag), guildmates still on 0.7.0 held the
    -- 27-of-289 copy, and with nothing to order the relay was applied over the
    -- 280 we had pulled and saved that way. My first fix only refused it when
    -- we held a stamped copy; the user's rule drops it whatever we hold, so an
    -- unordered copy can never land anywhere to be passed on. The applying
    -- branch for a relay carrying `m` went with it.
    if not tonumber(payload.t) then
        syncEvent(self, "dropped %s's relay of %s: no stamp", tostring(sender), key)
        return
    end
    local hash = payload.h
    self.sisterSync.seenRoster[key] = { hash = hash, notes = payload.nh, ranks = payload.rh, t = GetTime() }

    -- Every half, as in serveRoster: a relayer whose MEMBERSHIP matches ours
    -- but whose NOTES or RANKS do not is holding something we want
    -- (TOGBankClassic's `gbank` note), so it is a miss and we pull from them. A
    -- relayer that sends no `nh` / `rh` is not judged on what it cannot say.
    local mine = self:GetRosterHash(key)
    if not (mine and mine == hash and detailsMatch(self, key, payload.nh, payload.rh)) then
        -- A DIFFERENT copy is not automatically a BETTER one. Until this check
        -- the relay was adopted on arrival with no ordering at all, so a
        -- guildmate still holding last hour's copy -- the 27-of-289 short login
        -- build is exactly that -- pulled our fresh copy down to theirs, and we
        -- then relayed the stale one onward under our own name. Both stamps
        -- come from the ORIGINAL provider's clock (`rosterMeta.ts`, the `t` a
        -- server put on the roster it served), so they are comparable across
        -- clients in a way GetTime() never is. Strictly older: keep ours and
        -- say so. We still relay ours on the next round -- the suppression
        -- recorded THEIR hash, which does not match ours -- so they pull from
        -- us and the guild converges on the newer copy rather than the loudest.
        -- A copy of OURS with no stamp (consumer-fed, or saved before MINOR 20)
        -- is not ordered against: theirs has one, so theirs is the better known.
        local theirs, ours = tonumber(payload.t), copyStamp(self, key)
        if olderThan(theirs, ours) then
            syncEvent(self, "%s relayed an older %s (%ds behind); keeping ours",
                tostring(sender), key, ours - theirs)
            self:MarkOnline(key, relayedPresence(payload.o))
            return
        end
        if not self.sisterSync.pendingPull[key] then
            -- Their copy differs from ours (or we have none): ask them for it.
            -- Not while a pull for this guild is already out -- the answer to
            -- that one decides whether this hash is still news. The sightings
            -- the relay carried ride on the pending record, because MarkOnline
            -- can only stamp members of a roster we hold, and we may hold none
            -- until the answer lands (OnSisterRosterPulled applies them).
            if self:PullSisterRoster(sender, key, { relayed = true }) then
                local pending = self.sisterSync.pendingPull[key]
                if pending then pending.presence = relayedPresence(payload.o) end
            end
        end
    else
        -- THE BANK MODEL. The user, 2026-09-15: "if someone broadcasts the
        -- same hash version as you, then restart your timer. and if someone
        -- broadcasts a different hash, then you should whisper them." The
        -- different-hash half is the pull-on-miss above; this is the other
        -- half: a guildmate has just proved this roster current, so OUR
        -- cross-guild pull clock restarts as if we had pulled now (the relay
        -- clock restarts through seenRoster, checked at broadcast time).
        -- Before this every client pulled from the sister guild on its own
        -- clock -- a hundred online, a hundred "unchanged" handshakes per
        -- interval -- where one member's pull, relayed, serves everyone.
        self.sisterSync.lastPull[key] = GetTime()
        syncEvent(self, "%s relayed %s, already held", tostring(sender), key)
    end
    self:MarkOnline(key, relayedPresence(payload.o))
end

-- ---------------------------------------------------------------------------
-- The wire: the pull handshake over WHISPER
-- ---------------------------------------------------------------------------

-- Presence from a proven sighting. `who` is a "Name-Realm" the client just
-- heard from. If we hold their roster, stamp them. If we do not, and we have
-- a listed guild whose roster is missing, they are worth ONE pull: they are
-- online right now, which is the only thing a blind whisper cannot know.
-- `claimed`, when the message named the sender's guild, narrows that pull to
-- the guild they claim: a stranger from a guild we do not list is not worth
-- a whisper, and one from a listed guild is pulled for THAT guild, so the
-- pending record is filed where its answer will be looked for.
-- `stampOnly` is for an ANSWER (a roster, an ack, a refusal): every answer
-- we asked for already has its pending record, so a pull from here could
-- only be for one we did NOT ask for -- and that pull filed the very record
-- takeServedRoster's "we must have asked" gate then matched the forged
-- roster against. Found by the e2e cold-whisper scenario on 2026-09-16,
-- the day the gate went in.
local function sawOnline(self, who, claimed, stampOnly)
    local key = self:IsInAnyRoster(who)
    if key and key ~= self:GetHomeGuildKey() then
        self:MarkOnline(key, { who })
        -- The FIRST sighting of a guild this session pulls at once rather
        -- than waiting up to a round: a re-fed roster is last session's, and
        -- the member who just spoke is the freshest peer there is.
        if not stampOnly and not self.sisterSync.lastPull[key] then self:PullFromFreshest(key) end
        return key
    end
    if key or stampOnly then return nil end   -- a home guildmate; nothing to learn
    if claimed and not self:IsSisterGuildKey(claimed) then return nil end
    for _, sister in ipairs(self:GetSisterGuildKeys()) do
        -- Not while a pull for that guild is already out: the ack of our own
        -- request is itself a sighting, and would otherwise ask twice.
        if (not claimed or string.lower(claimed) == string.lower(sister))
            and not self.rosters[sister] and not self.sisterSync.pendingPull[sister] then
            local norm = self:NormalizeName(who) or who
            local now = GetTime()
            local last = self.sisterSync.candidates[norm]
            if not last or (now - last) >= self.SISTER_PULL_SENDER_COOLDOWN then
                self.sisterSync.candidates[norm] = now
                -- `expect` is the guild this pull is ABOUT even when the sender
                -- named none. Without it a stranger minted their own one-shot
                -- permission by omitting `g`: claimed = nil skips the filter
                -- above, the pull is filed under NO key, and their next message
                -- -- a roster for any listed guild -- passed the "we asked
                -- them" gate (peer review, 2026-09-16, PR-5).
                --
                -- IT IS `expect` AND NOT THE guildKey ARGUMENT, and the reason
                -- is worth more than the line: a guildKey files a pendingPull,
                -- and RequestSisterRosters falls through to that record's peer
                -- (`askedPeer`) when nothing fresher exists -- which for a
                -- guild we hold no roster of is ALWAYS, because there is no
                -- presence to pick from. So a pendingPull here would not merely
                -- let a stranger occupy the slot; it would install them as the
                -- member our own round asks, every round, for the one guild the
                -- round exists to bootstrap. A permission is a permission and a
                -- pending pull is a request; blurring them costs that.
                --
                -- AND THE SUBJECT OF THE GUESS IS ARBITRARY: `sister` is
                -- whatever GetSisterGuildKeys sorts first among the guilds we
                -- hold nothing of, not anything the sender said. That is safe
                -- -- their answer must match the bound key AND `trusted` must
                -- place them in the roster they serve -- but it is a guess, and
                -- a reader should not mistake it for their claim.
                self:PullSisterRoster(who, claimed and sister or nil, { expect = sister })
            end
            return nil
        end
    end
    return nil
end

--- A pulled roster landed. The accept gate: an unlisted guild's roster is
-- dropped again -- nothing cross-guild happens without the guild being on the
-- list. A listed one is persisted, its provider stamped online, relayed to the
-- home guild shortly, and announced with OnSisterRosterUpdated.
function lib:OnSisterRosterPulled(guildKey, secondHand)
    local pending = self.sisterSync.pendingPull[guildKey]
    self.sisterSync.pendingPull[guildKey] = nil
    if not self:IsSisterGuildKey(guildKey) then
        self:RemoveSisterRoster(guildKey)
        return false
    end
    self.sisterSync.refused[string.lower(guildKey)] = nil
    -- A SECOND-HAND copy just landed (a guildmate's, on a hash miss or the
    -- guild ask): the cross-guild pull clock restarts here too (the bank
    -- model), so it is not followed by our own cross-guild pull minutes later
    -- -- as of when that copy was last current, so an old one still sends the
    -- round to the sister guild (MINOR 20). A first-hand pull stamped the
    -- clock when it was asked.
    if secondHand then restartPullClock(self, guildKey, copyStamp(self, guildKey)) end
    self:PersistSisterRoster(guildKey)
    local meta = self.rosterMeta[guildKey]
    if not secondHand and type(meta) == "table" and meta.via then
        self:MarkOnline(guildKey, { meta.via })
    end
    -- Sightings a hash-only relay carried while we held nothing to stamp.
    if pending and type(pending.presence) == "table" then
        self:MarkOnline(guildKey, pending.presence)
    end
    -- Relayed to the guild at once: the relay is a hash now, so there is
    -- nothing to hold back for, and a copy that came second-hand is already
    -- circulating (seenRoster was stamped when its hash arrived), so the
    -- suppression keeps this from echoing it back.
    self:BroadcastSisterRosters()
    -- A pull that arrived moments before this copy did could not be placed
    -- then; it can be now (found by the two-client harness, 2026-09-15).
    self:RecheckPendingVerify()
    -- A guildmate offered something newer still while this one was in flight.
    -- If not, and the guildmate's copy was itself stale (the clock above did
    -- not defer anything), the guild has had its turn: the sister guild is
    -- asked now, from a member the copy's sightings say is online, rather than
    -- at the next round.
    if not self:PullFromGuildOffers(guildKey) then
        -- The guild step, if it was owed, is over: this copy is its answer.
        -- BEFORE the stale pull below, which stamps the clock -- the other way
        -- round the step read that clock as "current" and logged "the sister
        -- guild is not asked" straight after asking it (this session's audit).
        self:FinishGuildStep(guildKey)
        if secondHand then
            local last = self.sisterSync.lastPull[guildKey]
            if not last or (GetTime() - last) >= self.SISTER_PULL_INTERVAL then self:PullFromFreshest(guildKey) end
        end
    end
    if #self.whoSync.queue > 0 or self.whoSync.gwOwed then self:ShowWhoOverlay() end
    self.callbacks:Fire("OnSisterRosterUpdated", guildKey, secondHand and "relay" or "pull")
    return true
end

--- Is the pull path up? True once the roster is ready in a guild and AceComm
-- is present -- the pull is the library's own two-message exchange over the
-- addon channel, so nothing beyond Ace3 is needed. False while guildless or
-- before the login build settles.
-- @return boolean
function lib:IsSisterSyncAvailable()
    return self.sisterSync.commRegistered == true and self:GetHomeGuildKey() ~= nil
end

-- The pull, on the wire. ONE prefix, a HANDSHAKE over WHISPER:
--
--   request   { q = 1, g = ourHomeKey, hs = { [guildKey] = hash, ... } }
--             "send me your guild's roster" -- `g` names the asker's guild,
--             `hs` is every sister hash we hold, so a provider whose
--             membership we already have can answer with a no-change instead
--             of the whole list.
--   refusal   { x = 1, k = theirHomeKey }
--             "your guild is not on my list". THE SYNC IS MUTUAL. The user,
--             2026-09-15: "we also need to ensure the sync wont work unless
--             BOTH guilds have each other set up as sister guilds. we don't
--             want one guild 'stealing' info from another one without
--             permission." A provider serves its roster only to an asker
--             whose `g` is on ITS OWN sister list; a request with no `g` (a
--             MINOR 19 client) is refused too, because it cannot say. The
--             claim is checked against the asker's roster where we hold it
--             -- a member of a guild we list must appear in that guild's
--             roster -- and taken on trust only while we hold nothing of the
--             claimed guild yet, which is the one moment nothing on this
--             client can check it. The receive side has always had the other
--             half: a roster for a guild WE do not list is never stored.
--   ack       { a = 1, k = theirHomeKey, h = hash, n = memberCount }
--             "heard you; N members are on their way" -- sent at once on
--             NORMAL priority, BEFORE the roster, which is bulk and can take a
--             while: a 289-member roster is ~13 KB of addon messages, and a
--             985-member one ~44 KB, minutes on a busy link. The ack is what
--             turns "no answer yet" into "receiving", so a slow roster is
--             never mistaken for a dead peer.
--   response  { r = 0, k = theirHomeKey, h = hash }                     no change
--             { r = 1, k = theirHomeKey, h = hash, m = { {n,c,l,pn,rn,ri} }, p = provider, t = serverTime }
--             { r = 2, ..., b = baseHash, d = delta, nh = noteHash, rh = rankHash }   a delta
--
-- NO TIMEOUT ANYWHERE IN THIS. The user, 2026-09-15: "TIMERS are fragile ...
-- they can't account for latency, congestion or other things. that's why you
-- send handshake messages instead of timer events". A request has exactly
-- three outcomes, all of them events: the ack (then the roster), the
-- no-change answer, or the server's "No player named X is currently playing"
-- system message -- which is what retires X's presence stamp and drops the
-- pending pull (OnPeerUnreachable). A request that gets none of those (the
-- peer is online without the library, or the message was lost) simply stays
-- pending until the next round asks again; an ACKED pull whose roster has not
-- landed is left alone for one more round, because the bulk is in flight.
-- MINOR 18 retired the peer's stamp after a 30 s stopwatch, which a slow
-- roster tripped every time. That is gone.
--
-- DeltaSync's RosterSync did exactly this and nothing more, at the price of a
-- second dependency chain (DeltaSync -> AceCommQueue), seven addon-message
-- prefixes for a host that used two, and -- the real cost -- a PROVIDER that
-- also had to have DeltaSync installed before it could answer. The user's
-- question, 2026-09-13: "do we need deltasync and acecommqueue or is that
-- overkill?" It was. Anyone running this library can serve now.

--- Pull a sister guild's roster from a named online member of it. The manual
-- bootstrap (the window's "Pull from", `/guildroster pull`, TOGPM's
-- `/togpm pullroster`) and what every automatic pull goes through. Give a
-- realm-qualified name for a member on another realm: a bare name gets the
-- LOCAL realm appended, which is the one thing a cross-realm sister is not.
-- @param peerName string  "Name" or "Name-Realm"
-- @param guildKey string|nil  the guild expected; what the pending record is
--                             filed under, and what an answer is checked against
-- @param opts table|nil  `full = true` sends no hash, so the answer is the
--                        whole roster (what a failed delta falls back to);
--                        `relayed = true` asks a HOME guildmate for the copy of
--                        `guildKey` they hold (the hash-only relay's pull-on-miss);
--                        `expect` is the guild a keyless pull is ABOUT -- a
--                        guess the caller will not commit to pendingPull, which
--                        still binds the one answer it buys (see sawOnline)
-- @return boolean
function lib:PullSisterRoster(peerName, guildKey, opts)
    if type(peerName) ~= "string" or peerName == "" then return false end
    if not self:IsSisterSyncAvailable() then return false end
    local comm, serializer = commReady(self)
    if not comm then return false end
    opts = opts or {}
    local peer = self:NormalizeName(peerName) or peerName
    local request
    if opts.relayed then
        if not guildKey then return false end
        request = {
            q = 2, k = guildKey,
            h  = (not opts.full) and self:GetRosterHash(guildKey) or nil,
            nh = (not opts.full) and self:GetRosterNoteHash(guildKey) or nil,
            rh = (not opts.full) and self:GetRosterRankHash(guildKey) or nil,
        }
    else
        local held, notes, ranks = {}, {}, {}
        if not opts.full then
            for _, key in ipairs(self:GetKnownRosters()) do
                if key ~= self:GetHomeGuildKey() then
                    held[key]  = self:GetRosterHash(key)
                    notes[key] = self:GetRosterNoteHash(key)
                    ranks[key] = self:GetRosterRankHash(key)
                end
            end
        end
        -- `g` is OUR guild: the provider serves only a guild it lists back.
        -- `ns` and `rs` are the note and rank hashes beside `hs`; a peer that
        -- sends neither (before MINOR 19 / 21) is not judged on them.
        request = { q = 1, g = self:GetHomeGuildKey(), hs = held, ns = notes, rs = ranks }
    end
    local msg = serialize(serializer, request)
    if not msg then return false end
    if guildKey then
        self.sisterSync.pendingPull[guildKey] = { peer = peer, at = GetTime(), relayed = opts.relayed or nil }
    else
        -- No guild expected (the window's box, `/guildroster pull <name>`, a
        -- consumer's pull by name): the answer is filed under whatever guild
        -- THEY name, so the "we must have asked" gate (takeServedRoster)
        -- remembers the PEER instead, for one answer. `opts.expect` narrows
        -- that to one guild when the caller had a guess it did not want to
        -- commit to pendingPull -- see sawOnline.
        self.sisterSync.askedPeers[senderKey(self, peer)] = { at = GetTime(), key = opts.expect }
    end
    comm:SendCommMessage(self.SISTER_PULL_PREFIX, msg, "WHISPER", peer, "NORMAL")
    syncEvent(self, "asked %s for %s", peer, opts.relayed and ("their copy of " .. guildKey) or "their roster")
    return true
end

-- The listed spelling of a guild key, or nil when it is not listed.
local function listedKeyFor(self, claimed)
    if type(claimed) ~= "string" then return nil end
    for _, k in ipairs(self:GetSisterGuildKeys()) do
        if string.lower(k) == string.lower(claimed) then return k end
    end
    return nil
end

-- Is the asker's guild one we list, and is the asker in it? The provider
-- half of the mutual rule (see the wire note above). `claimed` is the
-- request's `g`. Three answers:
--   true   the SERVER listed the asker in that guild (our /who's rows,
--          `whoSync.candidates`), or a copy we hold does;
--   false  the guild is not listed, or the asker is in a DIFFERENT roster we
--          hold (a third guild's member claiming a listed one, or a home
--          guildmate);
--   nil    nothing says either way -- the caller owes a /who for that guild
--          and serves or refuses when the answer comes.
--
-- The first cut refused an asker ABSENT from a copy we held of the claimed
-- guild. That refused the one person the user wanted answered (2026-09-15,
-- "refused Testthese-Azuresong: Horde-The Other Gods is not on our list"):
-- the copy was the 27-of-289 partial one. Absence from a copy that may be
-- partial or stale proves nothing; the user: "the who proved they were in
-- the guild didn't it?" -- so the /who is the proof.
local function mutual(self, sender, claimed)
    local listed = listedKeyFor(self, claimed)
    if not listed then return false end
    local inKey = self:IsInAnyRoster(sender)
    if inKey then return string.lower(inKey) == string.lower(claimed) end
    local who = senderKey(self, sender)
    for _, n in ipairs(self.whoSync.candidates[listed] or {}) do
        if senderKey(self, n) == who then return true end
    end
    return nil
end

-- The refusal on the wire, `{ x = 1, k = ourHomeKey, y = reason }`; see the
-- wire note. `y` is one of REFUSAL_REASONS' keys, so the asker's status line
-- can say the right thing -- "they have not listed us" pointed the user at
-- the other guild's officer for a refusal that was really "your row was past
-- the /who cap" (Peer Review, 2026-09-16, PR-3). A MINOR 19 asker reads only
-- `k` and renders the old line.
local REFUSAL_REASONS = {
    unlisted  = "%s answered: %s has not listed us",
    notmember = "%s answered: they place us in a different guild",
    offline   = "%s answered: the server does not list us online in our guild",
}
local function refusePull(self, comm, serializer, sender, homeKey, why, reason)
    local msg = serialize(serializer, { x = 1, k = homeKey, y = reason or "unlisted" })
    if not msg then return false end
    comm:SendCommMessage(self.SISTER_PULL_PREFIX, msg, "WHISPER", sender, "NORMAL")
    syncEvent(self, "refused %s: %s", tostring(sender), why)
    return true
end

-- Serve a roster we hold to whoever asked: our own guild's (q = 1, the
-- provider path -- only to a guild we list, see `mutual`) or a sister roster
-- we hold (q = 2, a guildmate who saw our hash-only relay and lacks that
-- state). The first cut served ANYONE, as DeltaSync's default did, on the
-- reasoning that a roster is public through the guild panel of anyone who
-- joins; the user ruled that out on 2026-09-15 ("we don't want one guild
-- 'stealing' info from another one without permission"). The OFFICER note is
-- deliberately excluded; the PUBLIC note rides along as `pn` since MINOR 19
-- (TOGBank's LIBREQ-GR-002: its banker identity is the `gbank` note, and a
-- cross-guild bank cannot be built on a roster that does not carry it), and
-- the RANK as `rn` / `ri` since MINOR 21 (the user, 2026-09-16, on VersionCheck's
-- window showing a blank Rank for a sister member: "can you capture this data
-- so it's included in the sister roster sync?"). Both are visible to every
-- member of that guild through the same panel, exactly like class and level.
-- Omitted when empty. The membership hash stays over the charKey set: a note
-- edit or a promotion must not churn it -- they have hashes of their own.
--
-- THREE ANSWERS, smallest first: their hash is ours -> r = 0 (bytes). Their
-- hash is a state we passed through and DeltaSync is loaded -> r = 2, a delta
-- from that snapshot (hundreds of bytes), unless the delta is not much
-- smaller than the roster. Otherwise the ack and the full roster on BULK.
local DELTA_WORTH_IT = 0.5   -- send a delta only under this fraction of the full size
local function serveRoster(self, comm, serializer, sender, key, theirHash, secondHand, theirNoteHash, theirRankHash)
    local homeKey = self:GetHomeGuildKey()
    if not homeKey then return end
    -- Only a STABILIZED roster is served. After a guild change the home key
    -- resolves the moment GetGuildInfo answers, while the login stream is still
    -- filling the roster in -- and a partial roster served then is a partial
    -- HASH that every sister client would compare against and re-pull forever.
    -- Silence here costs one retry on their side; the wrong answer costs more.
    if not self.initialized then return end
    local roster, noteField
    if key == homeKey then
        roster, noteField = self.roster, "publicNote"
    else
        roster, noteField = self.rosters[key], "note"
        if not roster or not self:IsSisterGuildKey(key) then return end
    end
    local myHash = self:GetRosterHash(key)
    local tag = secondHand and 2 or nil
    -- "No change" means the MEMBERSHIP, the NOTES and the RANKS all match. A
    -- peer that sent no note or rank hash (before MINOR 19 / 21) is answered on
    -- what it did send: telling them "unchanged" is what they asked about.
    -- Without the note half a `gbank` note added today reached the other guild
    -- only when somebody happened to join or leave (TOGBankClassic,
    -- 2026-09-16); the rank half is the same, for a promotion.
    if theirHash == myHash and detailsMatch(self, key, theirNoteHash, theirRankHash) then
        -- Second-hand, "unchanged" carries when our copy was last current
        -- (MINOR 20), so a guildmate can tell a current copy from a stale one.
        local msg = serialize(serializer, { r = 0, k = key, h = myHash, s = tag, t = secondHand and copyStamp(self, key) or nil })
        if msg then
            comm:SendCommMessage(self.SISTER_PULL_PREFIX, msg, "WHISPER", sender, "NORMAL")
            syncEvent(self, "told %s %s is unchanged", tostring(sender), key)
        end
        return
    end
    -- A copy we hold with no provenance is never served: the taker drops it
    -- (no stamp, no provider), so the roster would cross only to be thrown
    -- away. Say so in a few bytes instead, so a guildmate's guild step ends at
    -- once rather than waiting a round on silence.
    if secondHand and not (copyStamp(self, key) and type(self.rosterMeta[key]) == "table"
        and self.rosterMeta[key].provider) then
        local msg = serialize(serializer, { r = 3, k = key, s = 2 })
        if msg then
            comm:SendCommMessage(self.SISTER_PULL_PREFIX, msg, "WHISPER", sender, "NORMAL")
            syncEvent(self, "told %s we hold no copy of %s we can vouch for", tostring(sender), key)
        end
        return
    end
    local members = toWire(roster, noteField)
    -- First-hand, the provider is us. Second-hand, it is whoever served the
    -- copy we hold: the taker files that name as the roster's provider (and
    -- ours only as the hand it came by), so a guildmate must never be
    -- stamped as a member of the sister guild.
    local stamp = { p = self:GetNormalizedPlayer(), t = (GetServerTime and GetServerTime()) or 0 }
    if secondHand then
        -- `t` is when the copy was last known CURRENT (copyStamp), so a
        -- guildmate taking it inherits our provider's latest "no change". Until
        -- MINOR 20 a copy with no provenance went out stamped NOW and naming US
        -- as the provider; such a copy is no longer served at all (above).
        stamp.p = self.rosterMeta[key].provider
        stamp.t = copyStamp(self, key)
    end

    local DS = deltaEngine()
    local base = theirHash and self.sisterSync.states and self.sisterSync.states.byHash[theirHash]
    if DS and base then
        local delta = DS:ComputeArrayDelta(base, members, DELTA_OPTS)
        local size = #delta.added + #delta.removed + #delta.modified
        if size < #members * DELTA_WORTH_IT then
            -- `nh` / `rh` (MINOR 21) let the taker verify the DETAILS too, not
            -- only the membership. The base is snapshotted when the membership
            -- hash changes, so it need not hold the notes or ranks the taker
            -- holds -- a copy served before ranks were sent is exactly that --
            -- and a delta from it can verify on membership and still leave the
            -- taker wrong. Unverified, that taker asked again every round and
            -- got the same empty delta every time.
            local msg = serialize(serializer, {
                r = 2, k = key, h = myHash, b = theirHash, d = delta, s = tag, p = stamp.p, t = stamp.t,
                nh = self:GetRosterNoteHash(key), rh = self:GetRosterRankHash(key),
            })
            if msg then
                comm:SendCommMessage(self.SISTER_PULL_PREFIX, msg, "WHISPER", sender, "NORMAL")
                syncEvent(self, "served %s to %s as a delta (+%d -%d ~%d)", key, tostring(sender),
                    #delta.added, #delta.removed, #delta.modified)
                return
            end
        end
    end

    -- The ack goes first and fast; the roster follows on BULK.
    local ack = serialize(serializer, { a = 1, k = key, h = myHash, n = #members, s = tag })
    if ack then comm:SendCommMessage(self.SISTER_PULL_PREFIX, ack, "WHISPER", sender, "NORMAL") end
    local msg = serialize(serializer, {
        r = 1, k = key, h = myHash, m = members, s = tag, p = stamp.p, t = stamp.t,
    })
    if msg then
        comm:SendCommMessage(self.SISTER_PULL_PREFIX, msg, "WHISPER", sender, "BULK")
        syncEvent(self, "served %s (%d) to %s", key, #members, tostring(sender))
    end
end

-- Did we ask `sender` for this guild -- the member the pending pull names, or
-- one an earlier round asked before re-asking somebody else (`pending.prior`,
-- carried by RequestSisterRosters)? A late answer from the member we asked
-- first is still an answer to OUR request; without `prior` it was dropped as
-- "we did not ask them" the moment the round had moved on (MINOR 20 audit).
local function askedFor(self, key, sender)
    local pending = self.sisterSync.pendingPull[key]
    if not pending then return false end
    local who = senderKey(self, sender)
    if senderKey(self, pending.peer) == who then return true end
    return type(pending.prior) == "table" and pending.prior[who] == true
end

-- A SECOND-HAND answer (s = 2) counts only against a guildmate request still
-- out: the sender is a guildmate we asked AND the pull on record is relayed.
-- Once the round has moved on to the sister guild the guildmate stays in
-- `prior`, and without the `relayed` test their late answer cleared that
-- first-hand pull (Peer Review, 2026-09-16, finding 2).
local function askedGuildmate(self, key, sender)
    local pending = self.sisterSync.pendingPull[key]
    return pending ~= nil and pending.relayed == true and self:IsInGuild(sender) and askedFor(self, key, sender)
end

-- The provider heard us and the roster is on its way. Proof they are online
-- right now, so the stamp is refreshed; the pending record is marked so the
-- next round leaves the bulk to land rather than asking again -- but only by an
-- ack that answers THAT record: a silent guildmate's late s = 2 ack used to
-- mark a first-hand pull to the sister guild acked, with their count, and hold
-- its retry a round (Peer Review, 2026-09-16, re-check).
local function takeAck(self, sender, payload)
    local key = payload.k
    if type(key) ~= "string" or not self:IsSisterGuildKey(key) then return end
    local pending = self.sisterSync.pendingPull[key]
    local answers
    if payload.s == 2 then
        answers = askedGuildmate(self, key, sender)
    else
        answers = pending ~= nil and not pending.relayed and askedFor(self, key, sender)
    end
    if answers then
        pending.acked  = true
        pending.expect = tonumber(payload.n) or 0
    end
    if payload.s ~= 2 then self:MarkOnline(key, { sender }) end
    syncEvent(self, "%s is sending %s members", tostring(sender), tostring(payload.n or "?"))
end

-- A guildmate answered our guild ask (AskGuildForSisterRosters). The SAME copy
-- is a confirmation: it was current at their stamp, so ours is too, and the
-- cross-guild clock restarts from then. A DIFFERENT one is an offer, kept and
-- pulled from the best of them (PullFromGuildOffers). Guildmates only: a
-- stranger's offer would be a way to talk us into asking them.
local function takeGuildOffer(self, sender, payload)
    local key = payload.k
    if type(key) ~= "string" or not self:IsSisterGuildKey(key) then return end
    if not self:IsInGuild(sender) then return end
    local stamp = tonumber(payload.t)
    if not stamp then
        syncEvent(self, "dropped %s's offer of %s: no stamp", tostring(sender), key)
        return
    end
    local held = heldKey(self, key)
    if held then self:MarkOnline(held, relayedPresence(payload.o)) end
    if held and payload.h == self:GetRosterHash(held) and detailsMatch(self, held, payload.nh, payload.rh) then
        confirmCopy(self, held, stamp)
        restartPullClock(self, held, copyStamp(self, held))
        syncEvent(self, "%s confirmed our copy of %s is current", tostring(sender), key)
        self:FinishGuildStep(key)
        if #self.whoSync.queue > 0 or self.whoSync.gwOwed then self:ShowWhoOverlay() end
        return
    end
    local slot = string.lower(key)
    local offers = self.sisterSync.guildOffers[slot] or {}
    self.sisterSync.guildOffers[slot] = offers
    local peer = self:NormalizeName(sender) or sender
    offers[string.lower(peer)] = {
        peer = peer, key = key, h = payload.h, nh = payload.nh, rh = payload.rh, t = stamp,
        o = relayedPresence(payload.o),
    }
    syncEvent(self, "%s offered their copy of %s", tostring(sender), key)
    self:PullFromGuildOffers(key)
end

-- The answer a pull BY NAME was waiting for has come from this peer (any
-- answer: a roster, no change, a refusal, or the server's not-found). True
-- once, then the record is gone. `key`, when the caller has one, must match
-- the guild the entry expected -- a pull we made on a GUESS answers for that
-- guess and nothing else (PR-5). An entry with no expectation (a human typed
-- the name) answers for any guild, bounded by the placement check and by
-- `trusted` at the call site.
local function consumeAskedPeer(self, sender, key)
    local slot = senderKey(self, sender)
    if not slot then return false end
    local rec = self.sisterSync.askedPeers[slot]
    if not rec then return false end
    if key and rec.key and string.lower(rec.key) ~= string.lower(key) then return false end
    self.sisterSync.askedPeers[slot] = nil
    return true
end

-- The provider does not list us. Nothing to store; the pending record is
-- retired (this IS the answer) and the refusal is kept so the status line can
-- say what is wrong instead of "asked X, no answer yet" -- the fix is on
-- THEIR officer's side, and the user needs to know which side to ask. The
-- automatic round keeps asking at its interval, because the other guild
-- listing us is an event this client cannot see; a refusal is a few bytes.
local function takeRefusal(self, sender, payload)
    local key = payload.k
    if type(key) ~= "string" or not self:IsSisterGuildKey(key) then return end
    self.sisterSync.pendingPull[key] = nil
    consumeAskedPeer(self, sender)
    -- Keyed lower-case: the refusal is spelled the provider's way and read
    -- back under the typed name's key (same rule as IsSisterGuildKey).
    local reason = type(payload.y) == "string" and REFUSAL_REASONS[payload.y] and payload.y or "unlisted"
    self.sisterSync.refused[string.lower(key)] = { peer = sender, at = GetTime(), reason = reason }
    syncEvent(self, REFUSAL_REASONS[reason], tostring(sender), key)
end

-- Who may answer for a roster. First-hand (s absent): the provider must
-- appear in the roster it served -- a member serves its own guild, so the
-- worst a liar can do is corrupt its OWN guild's roster. Second-hand (s = 2):
-- the answer came from a HOME guildmate relaying a copy, and that is the
-- trust the GUILD relay always had; they must be in our guild.
local function trusted(self, sender, payload, memberNames)
    if payload.s == 2 then return self:IsInGuild(sender) end
    local provider = self:NormalizeName(sender)
    return provider ~= nil and memberNames[provider] == true
end

-- A provider's answer: no change, a delta, or the full roster.
local function takeServedRoster(self, sender, payload)
    local key = payload.k
    if type(key) ~= "string" or key == "" then return end
    if payload.r == 0 then
        if self:IsSisterGuildKey(key) then
            -- ONLY FROM THE MEMBER WE ASKED. "Unchanged" now moves state that
            -- travels -- `meta.confirmed`, which our relays and serves carry as
            -- `t`, and the pull clock -- so an unsolicited one from anybody
            -- would let a stranger declare a stale copy current for the whole
            -- guild. Found by this session's own audit (MINOR 20): the first
            -- cut honoured any sender. Second-hand, the one we asked must also
            -- be a guildmate.
            local fromAsked = askedFor(self, key, sender)
            if payload.s == 2 then
                if not askedGuildmate(self, key, sender) then return end
            elseif not fromAsked then
                -- The by-name arm, with the same placement check the roster
                -- gate has: a peer we place in another guild cannot vouch
                -- for this one (finding 5).
                local inKey = self:IsInAnyRoster(sender)
                if inKey and string.lower(inKey) ~= string.lower(key) then return end
                if not consumeAskedPeer(self, sender, key) then return end
            else
                consumeAskedPeer(self, sender, key)
            end
            self.sisterSync.pendingPull[key] = nil
            self.sisterSync.refused[string.lower(key)] = nil
            if payload.s ~= 2 then
                self:MarkOnline(key, { sender })
                -- The provider just said our copy is current: remembered, so
                -- a guildmate asking the guild later can be told (copyStamp).
                confirmCopy(self, heldKey(self, key), GetServerTime and GetServerTime())
            end
            syncEvent(self, "%s answered: %s unchanged", tostring(sender), key)
            if payload.s == 2 then
                -- A guildmate holds our copy. With a stamp (MINOR 20) we know
                -- when it was last current; a MINOR 19 guildmate sends none,
                -- and then nothing about freshness is known.
                local held = heldKey(self, key)
                local theirs = tonumber(payload.t)
                if held and theirs then
                    confirmCopy(self, held, theirs)
                    restartPullClock(self, held, copyStamp(self, held))
                end
                -- Another guildmate may hold something newer; if not, the guild
                -- step is over.
                if not self:PullFromGuildOffers(key) then self:FinishGuildStep(key) end
                if #self.whoSync.queue > 0 or self.whoSync.gwOwed then self:ShowWhoOverlay() end
            end
        end
        return
    end
    -- Unlisted: not stored at all, so nothing to tear down. This is where the
    -- accept gate bites for a guild that lists US without us listing THEM.
    if not self:IsSisterGuildKey(key) then return end
    -- WE MUST HAVE ASKED. A first-hand roster is taken only from the peer a
    -- pending pull for that guild names -- or the peer a pull BY NAME asked,
    -- which could not say what guild to expect (askedPeers); a second-hand
    -- one only from a home guildmate (`trusted`, below). Peer Review,
    -- 2026-09-16 (PR-2): before this, anyone who knew the prefix and a listed
    -- guild's name could whisper `{ r = 1, k = <listed>, m = {...} }` COLD --
    -- no request, no pull-back -- and it was stored, persisted, relayed to
    -- the whole home guild and pulled by every guildmate on the hash miss:
    -- one whisper poisoned a guild-wide copy that survived relog. Matching an
    -- answer to the request we sent is not signing; it is the ack path's own
    -- rule applied here.
    if payload.s ~= 2 then
        if not askedFor(self, key, sender) then
            -- The by-name arm. A pull BY NAME could not say which guild to
            -- expect, so the permission is keyed on the PEER -- which means it
            -- would otherwise let them answer for ANY listed guild (Peer
            -- Review, 2026-09-16, on this session's own audit: "a human types
            -- `/guildroster pull Bob`; Bob answers with k = <any other guild
            -- on the list>"). So a peer we can PLACE must be answering for
            -- the guild we place them in -- the receive-side half of the
            -- mutual rule. A peer we cannot place is still bound by
            -- `trusted`: they must appear in the roster they serve.
            local inKey = self:IsInAnyRoster(sender)
            if inKey and string.lower(inKey) ~= string.lower(key) then
                syncEvent(self, "dropped a roster for %s from %s: we place them in %s",
                    key, tostring(sender), guildNameOf(inKey))
                return
            end
            if not consumeAskedPeer(self, sender, key) then
                syncEvent(self, "dropped a roster for %s from %s: we did not ask them", key, tostring(sender))
                return
            end
        end
    end

    -- NO STAMP, NOT TAKEN -- the user's rule (see OnSisterRosterComm): a roster
    -- answer with no `t` is dropped whatever we hold. Second-hand, the same goes
    -- for one with no provider or a provider who is our own guildmate: a real
    -- provider is a member of the sister guild, and a 0.8.0 guildmate serving a
    -- copy it has no provenance for names ITSELF and stamps the current time --
    -- an hours-old copy dressed as a new one. And a guildmate's copy OLDER than
    -- ours is not taken either: 0.8.0 serves whatever it holds when the hash
    -- differs, and the guild step asks those guildmates directly.
    -- `r = 3` is a MINOR 20 guildmate saying it holds nothing it can vouch for.
    do
        local secondHand = payload.s == 2
        -- A second-hand answer is a guildmate's or nothing; a stranger's must not
        -- end our guild step or clear what we asked for.
        -- ...and only while the guildmate request is still out (askedGuildmate).
        if secondHand and not askedGuildmate(self, key, sender) then return end
        local held = heldKey(self, key)
        local ours, theirs = held and copyStamp(self, held), tonumber(payload.t)
        local why
        if payload.r == 3 then
            why = "%s holds no copy of %s it can vouch for"
        elseif not theirs then
            why = "dropped %s's copy of %s: no stamp"
        elseif secondHand and (not payload.p or self:IsInGuild(payload.p)) then
            why = "dropped %s's copy of %s: no provider we can check"
        elseif secondHand and olderThan(theirs, ours) then
            why = "%s's copy of %s is older than ours; kept ours"
        end
        if why then
            for k in pairs(self.sisterSync.pendingPull) do
                if string.lower(k) == string.lower(key) then self.sisterSync.pendingPull[k] = nil end
            end
            syncEvent(self, why, tostring(sender), key)
            if secondHand then
                if not self:PullFromGuildOffers(key) then self:FinishGuildStep(key) end
                if #self.whoSync.queue > 0 or self.whoSync.gwOwed then self:ShowWhoOverlay() end
            end
            return
        end
    end

    local wire
    if payload.r == 2 then
        -- A delta against the state we hold. Applied to our own copy in wire
        -- shape, then VERIFIED: the result must hash to what the provider says
        -- it holds, or we ask for the whole thing. A delta we cannot apply --
        -- no DeltaSync here, or our hash moved since we asked -- is the same
        -- fallback. The pending record is kept for that second ask so the
        -- round does not count it as unanswered.
        local DS = deltaEngine()
        local held = self.rosters[key]
        if not (DS and held and type(payload.d) == "table" and payload.b == self:GetRosterHash(key)) then
            syncEvent(self, "delta from %s could not be applied; asking for the full roster", tostring(sender))
            self:PullSisterRoster(sender, key, { full = true, relayed = payload.s == 2 })
            return
        end
        wire = toWire(held, "note")
        local ok = DS:ApplyArrayDelta(wire, payload.d, DELTA_OPTS)
        if not ok then
            self:PullSisterRoster(sender, key, { full = true, relayed = payload.s == 2 })
            return
        end
    else
        if type(payload.m) ~= "table" then return end
        wire = payload.m
    end

    local names = {}
    local members = wireToFeed(self, wire, function(norm) names[norm] = true end)
    if #members == 0 or not trusted(self, sender, payload, names) then return end

    if payload.r == 2 then
        -- The hashes are the proof. Compute them over what we are about to
        -- store, before storing, so a bad delta never lands: the membership
        -- always, and the notes and ranks when the provider sent their hashes
        -- (MINOR 21; see serveRoster for the loop this closes).
        local keys, byKey = {}, {}
        for norm in pairs(names) do keys[#keys + 1] = norm end
        table.sort(keys)
        for _, m in ipairs(members) do
            local norm = self:NormalizeName(m.name)
            if norm then byKey[norm] = m end
        end
        if fnv1a32(table.concat(keys, "\n")) ~= payload.h
            or (payload.nh ~= nil and payload.nh ~= noteHashOf(byKey))
            or (payload.rh ~= nil and payload.rh ~= rankHashOf(byKey)) then
            syncEvent(self, "delta from %s did not verify; asking for the full roster", tostring(sender))
            self:PullSisterRoster(sender, key, { full = true, relayed = payload.s == 2 })
            return
        end
    end

    local meta = self.rosterMeta[key]
    local via = sender
    if payload.s == 2 and type(meta) == "table" and meta.provider then
        -- A relayed copy keeps the ORIGINAL provider on record; `via` says who
        -- handed it to us.
        self:SetSisterRoster(key, members, { provider = payload.p or meta.provider, ts = payload.t or meta.ts, via = via })
    else
        self:SetSisterRoster(key, members, { provider = payload.p, ts = payload.t, via = via })
    end
    syncEvent(self, "took %s (%d) from %s%s", key, #members, tostring(sender),
        payload.r == 2 and " as a delta" or "")
    self:OnSisterRosterPulled(key, payload.s == 2)
end

--- The pull prefix's handler, both directions. Every sender is a proven
-- sighting before anything else happens.
function lib:OnSisterPullComm(prefix, message, _, sender)
    if prefix ~= self.SISTER_PULL_PREFIX then return end
    if isOwnMessage(self, sender) then return end
    -- ONE SPELLING FROM HERE ON. AceComm hands us a same-realm sender BARE
    -- (see senderKey); everything below stores, compares and answers with it,
    -- and every record it meets is `Name-Realm`. GR-SAMEREALM-001.
    sender = self:NormalizeName(sender) or sender
    -- Both halves need the comm object to answer with, so this resolves the
    -- pair itself rather than taking the serializer the registration captured.
    local comm, serializer = commReady(self)
    if not comm then return end
    local payload = deserialize(serializer, message)
    if not payload then return end
    -- What guild the sender says they are in: `g` on a request, `k` on a
    -- first-hand answer. A second-hand answer is a home guildmate's.
    -- A guild-ask offer's `k` is the SISTER guild a guildmate holds, not theirs.
    local claimed = payload.q == 1 and payload.g
        or (payload.q == nil and payload.s ~= 2 and payload.f ~= 1 and payload.k) or nil
    -- A request is worth a pull-back; anything else -- an answer, or a shape
    -- this version does not know -- is a stamp and nothing more (see
    -- sawOnline's `stampOnly`).
    sawOnline(self, sender, type(claimed) == "string" and claimed or nil, payload.q ~= 1)
    if payload.q == 1 then
        local homeKey = self:GetHomeGuildKey()
        -- Not ready: silent, as serveRoster is -- the list is per home guild
        -- and a refusal sent before the new guild's list is read would be
        -- wrong, not merely early.
        if not (homeKey and self.initialized) then return end
        local ok = mutual(self, sender, claimed)
        if ok == false then
            local listedAtAll = listedKeyFor(self, claimed) ~= nil
            refusePull(self, comm, serializer, sender, homeKey,
                listedAtAll and ("we place them outside " .. guildNameOf(claimed))
                    or (tostring(claimed or "an unnamed guild") .. " is not on our list"),
                listedAtAll and "notmember" or "unlisted")
            return
        end
        if ok == nil then
            -- Nothing places them yet: owe a /who for the guild they claim and
            -- decide on the answer (ResolvePendingVerify). The user: "the who
            -- proved they were in the guild didn't it?"
            local listed = listedKeyFor(self, claimed)
            local pv = self.sisterSync.pendingVerify
            pv[string.lower(sender)] = {
                sender = sender, key = listed, hs = payload.hs, ns = payload.ns, rs = payload.rs, at = GetTime(),
            }
            self:QueueWho(listed, true)
            syncEvent(self, "%s claims %s; asking the server before serving (click anywhere)",
                tostring(sender), guildNameOf(listed))
            return
        end
        local theirHash = type(payload.hs) == "table" and homeKey and payload.hs[homeKey] or nil
        local theirNotes = type(payload.ns) == "table" and homeKey and payload.ns[homeKey] or nil
        local theirRanks = type(payload.rs) == "table" and homeKey and payload.rs[homeKey] or nil
        serveRoster(self, comm, serializer, sender, homeKey, theirHash, false, theirNotes, theirRanks)
    elseif payload.x == 1 then
        takeRefusal(self, sender, payload)
    elseif payload.q == 2 then
        -- A guildmate wants the copy we hold of a sister roster. Only a
        -- guildmate: the relay it answers rides GUILD, and a stranger asking
        -- for a third guild's roster gets nothing.
        if type(payload.k) == "string" and self:IsInGuild(sender) then
            serveRoster(self, comm, serializer, sender, payload.k, payload.h, true, payload.nh, payload.rh)
        end
    elseif payload.f == 1 then
        takeGuildOffer(self, sender, payload)
    elseif payload.a == 1 then
        takeAck(self, sender, payload)
    elseif payload.r ~= nil then
        takeServedRoster(self, sender, payload)
    end
end

-- ===========================================================================
-- VersionCheck-1.0: who can ANSWER a pull, and how compatibly
--
-- The user, 2026-09-15: "it might be asking someone that CAN'T respond. it
-- needs to be someone with the GR library installed, and if possible the
-- same version ... like for me, as i'm on GuildRoster-v0.9.2 dev all the
-- time, it would ask me, if someone was on v1.2.1 it would ask them first.
-- maximum compatibility first" -- and "we should also add version check
-- into GR first, so it has it".
--
-- VersionCheck-1.0's TOC depends on THIS library, so like DeltaSync it is
-- looked up by LibStub at call time and can never be declared. Its README's
-- one correct wiring is `VC:RegisterCheck(name, rawTocVersion)`, sentinel
-- and all (`GuildRoster-v0.9.2` is how it recognises a dev build); done at
-- PLAYER_LOGIN, by which time every addon has loaded. From then on every
-- guildmate's VersionCheck harvests our version from the login batch, and
-- ours theirs.
--
-- A SISTER member never hears that batch on GUILD -- but VersionCheck also
-- parks every request for GreenWall, the confederation channel, and every
-- confederated member's VersionCheck whispers back. So finding who runs the
-- library is ONE request naming only this library -- `VC:RequestAbout` --
-- and the answers land in OUR VersionCheck as `OnPeerVersion`; that event
-- is what picks the peer and pulls. The user: "a single broadcast over
-- greenwall would have all of them whisper you". A client without
-- GreenWall asks one member at a time through `VC:RequestFrom(name)`; this
-- library never builds VersionCheck's request itself -- "maybe you should
-- have VC do that work?" -- so a client with neither cannot ask and says
-- so. No timer anywhere: a member who never answers is never asked for a
-- roster, because they have nothing to answer with.
--
-- Ranking, most compatible first: our exact version, then any released
-- version (it carries digits), then a dev build, then someone who never
-- reported at all -- who is asked only when VersionCheck is not installed
-- here to ask with.
-- ===========================================================================

local VC_HOST = "GuildRoster"

local function versionCheck()
    local VC = LibStub("VersionCheck-1.0", true)
    if VC and VC.RegisterCheck and VC.GetPeerVersions then return VC end
    return nil
end

--- The version string this library reports: the standalone addon's raw TOC
-- version when it is loaded (`GuildRoster-v0.9.2` on a dev build, on
-- purpose), else the LibStub MINOR of an embedded copy.
-- @return string
function lib:GetVersionString()
    local getMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    local toc = getMeta and getMeta(VC_HOST, "Version")
    return toc or ("r" .. MINOR)
end

--- Register with VersionCheck-1.0 when it is present. Idempotent; called at
-- PLAYER_LOGIN and again when the sync starts (a LibStub upgrade re-runs it
-- harmlessly). Returns whether VersionCheck is there.
-- @return boolean
function lib:RegisterWithVersionCheck()
    local VC = versionCheck()
    if not VC then return false end
    if self.vcRegistered ~= VC then
        VC:RegisterCheck(VC_HOST, self:GetVersionString())
        if VC.RegisterCallback then
            VC.RegisterCallback(self, "OnPeerVersion", function(_, sender, addonName, version)
                if addonName == VC_HOST then self:OnPeerVersion(sender, version) end
            end)
        end
        self.vcRegistered = VC
    end
    return true
end

--- What VersionCheck has heard this member runs, or nil for never reported.
-- @param name string  "Name-Realm"
-- @return string|nil
function lib:PeerLibraryVersion(name)
    local VC = versionCheck()
    if not VC then return nil end
    local peers = VC:GetPeerVersions(VC_HOST)
    local key = self:CanonName(name) or name
    local obs = peers[key]
    -- VersionCheck keys a peer by the spelling it ARRIVED in, which AceComm
    -- makes bare for a player on our realm -- while a roster charKey is
    -- `Name-Realm`. So a local-realm name is looked up bare too; without this
    -- every same-realm member ranked "never reported" and was never pulled
    -- from (the same defect as GR-SAMEREALM-001, found fixing it).
    if not obs then
        local realm = self:GetRealmName()
        local suffix = realm and ("-" .. realm)
        if suffix and #key > #suffix and key:sub(-#suffix) == suffix then
            obs = peers[key:sub(1, #key - #suffix)]
        end
    end
    return obs and obs.version or nil
end

-- 0 = our exact RELEASED version, 1 = any released version, 2 = a dev build
-- (two "GuildRoster-v0.9.2" strings cannot be ordered, so they tie here even
-- against a dev asker -- the user: "as i'm on GuildRoster-v0.9.2 dev all the
-- time, it would ask me, if someone was on v1.2.1 it would ask them first"),
-- 3 = never reported.
local function versionRank(self, name)
    local v = self:PeerLibraryVersion(name)
    if not v then return 3 end
    v = tostring(v)
    if not v:find("%d") then return 2 end
    if v == self:GetVersionString() then return 0 end
    return 1
end

--- Ask one member what they run: VersionCheck's `RequestFrom`, its own
-- request to one player over WHISPER, answered through OnPeerVersion. False
-- when VersionCheck is not installed here (nothing could receive the reply)
-- or does not carry RequestFrom yet -- this library never builds
-- VersionCheck's wire itself.
-- @param name string
-- @return boolean  a request went out
function lib:AskPeerVersion(name)
    local VC = versionCheck()
    if not (VC and VC.RequestFrom) then return false end
    return VC:RequestFrom(name) and true or false
end

--- Step 2 of discovery. The user's design, 2026-09-15, verbatim: "1. you do
-- a /who check to see who is online 2. you do a VC through greenwall to see
-- what versions of GR the online people have 3. you FIRST whisper someone
-- with the same version of GR than you 4. if no one has the same version,
-- then you whisper anyone with a GR version" -- and "no 2 uses the OVERLAY".
--
-- So: VersionCheck builds its one-addon request (`RequestAbout`, MINOR 14)
-- and parks it for GreenWall; VersionCheck's own release is the chat hook,
-- which waits for the player to TYPE, and the user ruled that out ("i don't
-- want anything waiting for someone to say something"). The click overlay is
-- a hardware event too, so the library owes the send (`whoSync.gwOwed`) and
-- releases it from the next click -- SendConfederationAsk -- exactly as it
-- releases the /who. Every confederated member's VersionCheck whispers back
-- and OnPeerVersion ranks them (steps 3 and 4: versionRank). The full
-- `RequestCheck()` is the fallback for a VersionCheck without RequestAbout
-- (it may not fit GreenWall's 255-byte segment; measured 592 on this box).
-- Without GreenWall the listed members are whispered one by one through
-- `RequestFrom` instead (WHO_ASK_LIMIT), which needs no hardware event.
-- @param names table  the members the server listed online
-- @param key string  the listed guild key (for the status line)
-- @return number  requests that went out or were owed to the click
function lib:AskWhoRunsTheLibrary(names, key)
    local VC = versionCheck()
    if not VC then return 0 end
    local ws = self.whoSync
    if GreenWallAPI and (VC.RequestAbout or VC.RequestCheck) then
        local fired, wait
        if VC.RequestAbout then
            fired, wait = VC:RequestAbout(VC_HOST)
        else
            fired, wait = VC:RequestCheck()
        end
        -- Whatever the rate limit said, a payload VersionCheck still holds --
        -- this request, or its own login trigger, both naming this library --
        -- is what the click releases.
        if VC.gwPendingPayload then
            ws.gwOwed = key
            self:ShowWhoOverlay()
            syncEvent(self, "click anywhere to ask the confederation who runs the library%s",
                (not VC.RequestAbout) and " (VersionCheck's full batch; it may not fit GreenWall's 255-byte segment)" or "")
            return 1
        end
        if fired then
            -- Sent already (a chat keystroke beat the click): answers are coming.
            syncEvent(self, "asked the confederation who runs the library (VersionCheck over GreenWall)")
            return 1
        end
        syncEvent(self, "the confederation was asked %ds ago; waiting for the answers", math.ceil(wait or 0))
        return 0
    end
    if not VC.RequestFrom then
        syncEvent(self, "cannot ask %s who runs the library: no GreenWall, and this VersionCheck has no RequestFrom",
            guildNameOf(key))
        return 0
    end
    local asked = 0
    for _, n in ipairs(names) do
        if asked >= self.WHO_ASK_LIMIT then break end
        if self:AskPeerVersion(n) then asked = asked + 1 end
    end
    syncEvent(self, "asked %d of %s which library they run", asked, guildNameOf(key))
    return asked
end

-- An automatic pull's target: a member seen online within PRESENCE_TTL, the
-- most COMPATIBLE first (versionRank), then the most recently seen, so a
-- stale stamp is the last resort; never a member with no stamp at all.
local function freshestPeer(self, guildKey)
    local presence = self.presence[guildKey]
    local roster = self.rosters[guildKey]
    if not presence or not roster then return nil end
    local best, bestRank, bestAt = nil, nil, nil
    local now = GetTime()
    for charKey, seen in pairs(presence) do
        if roster[charKey] and (now - seen) <= self.PRESENCE_TTL then
            local rank = versionRank(self, charKey)
            if not best or rank < bestRank or (rank == bestRank and seen > bestAt) then
                best, bestRank, bestAt = charKey, rank, seen
            end
        end
    end
    return best
end

--- Pull one listed guild from its freshest known-online member, if any. What
-- OnPeerUnreachable does the moment the server says the member we asked is
-- gone (their stamp is cleared first, so this picks the next one).
-- @param guildKey string
-- @return boolean  a request went out
function lib:PullFromFreshest(guildKey)
    if not self:IsSisterGuildKey(guildKey) or self.sisterSync.pendingPull[guildKey] then return false end
    local peer = freshestPeer(self, guildKey)
    if not peer then return false end
    if self:PullSisterRoster(peer, guildKey) then
        self.sisterSync.lastPull[guildKey] = GetTime()
        return true
    end
    return false
end

--- Pull a listed guild from the best GUILDMATE offer to our guild ask, if one
-- is still better than what we hold. Offers identical to our copy, or older
-- than it, are dropped here; of the rest the newest wins, then the most
-- compatible version (versionRank -- the user's "FIRST whisper someone with
-- the same version"), then the name, so two clients agree. One ask per offer:
-- the offer is spent when it is asked, and an unanswered one is the round's
-- to retry (RequestSisterRosters). Called as each offer lands, after every
-- landing, and when the guildmate we asked is gone.
-- @param guildKey string
-- @return boolean  a request went out
function lib:PullFromGuildOffers(guildKey)
    if type(guildKey) ~= "string" then return false end
    local ss = self.sisterSync
    local slot = string.lower(guildKey)
    local offers = ss.guildOffers[slot]
    if not offers then return false end
    for k in pairs(ss.pendingPull) do
        if string.lower(k) == slot then return false end
    end
    local held = heldKey(self, guildKey)
    local myHash  = held and self:GetRosterHash(held)
    local myStamp = held and copyStamp(self, held)
    local bestSlot, best, bestT, bestRank
    for peerSlot, rec in pairs(offers) do
        local same  = myHash and rec.h == myHash and detailsMatch(self, held, rec.nh, rec.rh)
        if same or olderThan(rec.t, myStamp) then
            offers[peerSlot] = nil
        else
            -- Every kept offer is stamped: takeGuildOffer drops one without.
            local t, rank = rec.t, versionRank(self, rec.peer)
            if not best or t > bestT or (t == bestT and (rank < bestRank
                or (rank == bestRank and peerSlot < bestSlot))) then
                bestSlot, best, bestT, bestRank = peerSlot, rec, t, rank
            end
        end
    end
    if not best then
        if not next(offers) then ss.guildOffers[slot] = nil end
        return false
    end
    offers[bestSlot] = nil
    if not self:PullSisterRoster(best.peer, best.key, { relayed = true }) then return false end
    local pending = ss.pendingPull[best.key]
    if pending and best.o then pending.presence = best.o end
    return true
end

--- One round: for every listed guild, pull from the freshest known-online
-- member. The ticker calls it unforced, which honours the
-- SISTER_PULL_INTERVAL pacing; "Sync now" and `/guildroster sync` call it
-- with `force`, which pulls regardless of when the last round ran -- that is
-- what "now" means. Found by the end-to-end spec on 2026-09-15: the button
-- ran the paced round, so pressed inside five minutes of an automatic pull
-- it did nothing at all, and said nothing either. Forcing never whispers
-- blind: a guild with no member seen online recently is still skipped, and
-- is REPORTED in the second return so the caller can say why.
--
-- A pull still pending is judged by the handshake, not the clock, and only
-- by a round that is going to ACT on the guild: a paced round leaves the
-- record exactly as it found it (reported as "pending", so the status line
-- keeps saying "asked X, no answer yet"). The first cut judged it before
-- the pacing check, so the 45 s first run, inside the interval of a manual
-- pull, dropped an unanswered record and then did nothing -- the status
-- bar read "next pull in 3m57s" for a request that had simply been
-- forgotten. Found by the status-text spec on 2026-09-15. Never acked:
-- nothing came back at all, so it is asked again (the previous request was
-- lost or the peer runs no library) -- the server's not-online message, if
-- that is the reason, has already cleared the stamp and the pending record
-- through OnPeerUnreachable. Acked: the roster is in flight and may be
-- large, so it is left alone for one round, then asked again in case the
-- bulk was lost.
-- @param force boolean|nil  ignore the pacing
-- @return number  pulls issued
-- @return table   { [guildKey] = "no-peer" | "pending" | "paced" } for every
--                 listed guild NOT pulled this round
function lib:RequestSisterRosters(force)
    local skipped = {}
    if not self:IsSisterSyncAvailable() then return 0, skipped end
    local now = GetTime()
    local ss = self.sisterSync
    local issued = 0
    for _, key in ipairs(self:GetSisterGuildKeys()) do
        local pending = ss.pendingPull[key]
        local last = ss.lastPull[key]
        if not force and last and (now - last) < self.SISTER_PULL_INTERVAL then
            skipped[key] = pending and "pending" or "paced"
        else
            -- A peer whose ack proved them online is asked again directly
            -- when their bulk never landed -- we may hold no roster yet, and
            -- so no presence to pick anyone else from.
            local retryPeer, askedPeer, dropped
            if pending and pending.acked then
                pending.rounds = (pending.rounds or 0) + 1
                if pending.rounds > 1 then
                    retryPeer, dropped = pending.peer, pending
                    ss.pendingPull[key] = nil
                    pending = nil
                end
            elseif pending then
                -- Unanswered: ask again now -- somebody fresher if there is
                -- one, else the same member (the server would have said if
                -- they were gone). Never simply forgotten: the first cut
                -- dropped the record here and then found nobody to ask.
                askedPeer, dropped = pending.peer, pending
                ss.pendingPull[key] = nil
                pending = nil
            end
            if pending then
                skipped[key] = "pending"
            elseif dropped and dropped.relayed and not dropped.retried
                and self:PullSisterRoster(dropped.peer, key, { relayed = true }) then
                -- A GUILDMATE's copy we asked for is asked for again, as a
                -- guildmate's copy, once. Until MINOR 20 the retry below sent
                -- it as a first-hand request (q = 1) to the guildmate, who
                -- then served their HOME roster, which we drop. Guild first:
                -- one more try in guild, then the sister guild.
                ss.pendingPull[key].retried = true
                ss.pendingPull[key].prior = dropped.prior
                issued = issued + 1
            else
                -- The guildmate had their retry: never re-ask them first-hand.
                if dropped and dropped.relayed then retryPeer, askedPeer = nil, nil end
                -- A guild that refused us is asked again through the member
                -- who refused -- we hold no roster of theirs, so there is
                -- nobody else -- until the server says they are gone. Their
                -- officer listing us is the event this client cannot see.
                local refusal = ss.refused[string.lower(key)]
                local peer = retryPeer or freshestPeer(self, key)
                    or (refusal and not refusal.gone and refusal.peer) or askedPeer
                if peer and self:PullSisterRoster(peer, key) then
                    ss.lastPull[key] = now
                    issued = issued + 1
                    -- Whoever we asked before is still owed their answer.
                    if dropped then
                        local prior = dropped.prior or {}
                        prior[senderKey(self, dropped.peer)] = true
                        ss.pendingPull[key].prior = prior
                    end
                else
                    skipped[key] = "no-peer"
                    -- Nobody seen: ask VersionCheck (a roster held) or the
                    -- SERVER (nothing held) who is there -- both from a click.
                    self:DiscoverPeers(key)
                end
            end
        end
    end
    return issued, skipped
end

-- ===========================================================================
-- Who discovery: /who <guild> is how a sister member is FOUND
--
-- After a relog nobody has spoken on the wire yet, presence is not persisted,
-- and both clients sat at "nobody seen online" waiting for the other to go
-- first. The user, 2026-09-15: "you're relying on someone saying something in
-- chat? no, do the /who <guildname> it's immediate." That supersedes the
-- 2026-09-13 ruling against /who (which was given against a passive listener
-- on the player's OWN /who); this is the library asking, and it is immediate.
--
-- THE ONE RULE OF SendWho: IT NEEDS A HARDWARE EVENT. Called from a timer,
-- an event handler or an incoming comm it raises ADDON_ACTION_BLOCKED and the
-- query never leaves the client -- proven on a Classic client in
-- FastGuildInvite's changelog (its Recheck ticker: "5x [ADDON_ACTION_BLOCKED]
-- ... 'SendWho()'"), whatever the documentation's flags may read. So a /who
-- is QUEUED, and sent from the next click: the window's Sync now, the
-- `/guildroster sync` Enter, or -- the way FGI's Wingman does it -- the
-- player's next click ANYWHERE, caught by a full-screen frame that passes the
-- click through (SetPropagateMouseClicks). The user: "you can tie the /who
-- event button push to a lot of hardware events, like the wingman overlay
-- does, you can capture a mouse click. you only need one to kick it off ...
-- once you have a successful who you can turn the overlay off". So the
-- overlay exists only while a /who is owed, sends one per click, and goes
-- away when the queue is empty.
--
-- The results: every row is a member the server says is online RIGHT NOW,
-- with their guild on it. A row for a listed guild whose roster we hold is a
-- presence stamp (the round then pulls); a row for one we do not hold yet is
-- pulled from on the spot, because that is the bootstrap the whole design
-- needed a typed name for until now. The query is the plain guild name, the
-- /who the user described (see SendQueuedWho for why not the `g-` tag).
--
-- Blizzard's Social pane: `WhoList_Update` ends with `ShowUIPanel(FriendsFrame)`
-- (Classic FriendsFrame.lua:1003-1004), so a /who whose result reaches the
-- client's handler pops the pane open mid-play. FGI's LibWho borrows the
-- registration -- `FriendsFrame:UnregisterEvent("WHO_LIST_UPDATE")` while our
-- query is out; done the same way here, and with `SetWhoToUi(true)` so the
-- answer is delivered as the event rather than printed into chat. A /who is
-- not sent while the Social pane is open: that is the player's own /who tool,
-- and we do not fight it.
--
-- THE REGISTRATION GOES BACK WHEN THE PLAYER WANTS THE PANE, NEVER ON AN
-- ANSWER (MINOR 24, mirroring FGI v2.14.1 -- peer review c5a1a43e,
-- 2026-09-20, from two field reports of the pane popping up during Wingman
-- use). Until then every answer handed it back one frame after the event we
-- consumed. But nobody can tell whose answer a WHO_LIST_UPDATE is: with one
-- query of ours and one of FGI's out from the SAME click, whichever answer
-- landed first re-registered FriendsFrame while the other query was still
-- out, and the second answer reached Blizzard's handler alone -- pane open.
-- So the debt (`whoSync.borrowed`) now stands across as many queries as it
-- takes and is settled on exactly two occasions, both the player wanting the
-- pane: opening it (a post-hook on FriendsFrame's OnShow -- the pane repaints
-- the Who list from the client's buffer by itself, FriendsFrame_OnShow ->
-- FriendsFrame_Update -> WhoList_Update, Classic FriendsFrame.lua:442/:480),
-- or sending a /who of their own (a post-hook on C_FriendList.SendWho: every
-- Blizzard call site passes a non-nil Enum.SocialWhoOrigin -- SlashCommands
-- .lua:1111, FriendsFrame.lua:1233, ItemRefHandlers.lua:50 -- and no addon
-- does, so an addon-origin send is one that borrowed the registration itself
-- and is left alone). See GiveBackWhoList / HookWhoPane.
--
-- No timers judge anything here. The overlay is shown/hidden by the queue,
-- the query is sent by a click, the answer arrives as an event. The ONE
-- deferred call is the closing of a pane a THIRD PARTY's hand-back let our
-- answer open (an FGI older than v2.14.1 still returns it on its own answer),
-- one frame after the event, once Blizzard's handler has run.
-- ===========================================================================

lib.WHO_INTERVAL = lib.SISTER_PULL_INTERVAL   -- one /who per guild per this; pacing, not state
lib.whoSync = lib.whoSync or {
    queue = {}, queued = {}, lastWho = {}, outstanding = 0, overlay = nil,
    asked = {},        -- FIFO of the (lower-cased) names our outstanding /who queries asked about
    nameQueries = {},  -- [lower(bare name)] = true: a queued /who about ONE player, not a guild
    propagationOK = false, shown = false, borrowed = false,
    candidates = {},   -- [listedKey] = the members the server last listed online
}
-- MINOR 20: [lower(listedKey)] = true while the GUILD STEP for that guild is
-- owed -- set at login, cleared by FinishGuildStep or by any later discovery.
lib.whoSync.afterGuild = lib.whoSync.afterGuild or {}
-- [lower(listedKey)] = true once the confederation ask for that guild left this
-- session: the next discovery for it is a /who (see DiscoverPeers).
lib.whoSync.gwSent = lib.whoSync.gwSent or {}
lib.whoSync.placeAsks = lib.whoSync.placeAsks or 0   -- by-name /who owed to place a VersionCheck answerer, this session

-- THE SERVER'S /who FLOOR, and the one mitigation for a hole neither library
-- can close: nobody can tell whose WHO_LIST_UPDATE it is, so with one query
-- of ours and one of FGI's out at once the first answer is consumed by BOTH
-- (ours reads their level band's fifty strangers as the asked guild's answer
-- -- "nobody online" for the round -- and FGI credits its band as searched
-- against our guild rows). FGI's half: it refuses a send inside this floor
-- measured from ANY send its hook saw, ours included. Ours: the SendWho hook
-- stamps every send (any origin) and SendQueuedWho holds inside the floor,
-- trying again on the next click. The two can then only overlap when an
-- answer takes longer than the floor. The numbers are the operator's own
-- measurements recorded in FGI (`fn.getMinScanInterval`): "on my classic
-- pretty empty server, it's at about 4s that it doesn't eat a /who. we know
-- on retail we need 8s as a minimum" -- below the floor the server answers
-- with nothing or the previous rows, silently. A click-time read of a stamp,
-- like `lastWho`; nothing waits on it. (Peer review c5a1a43e, reply 2.)
lib.WHO_SEND_FLOOR = IS_RETAIL and 8 or 5

-- A case-insensitive read of a table keyed by guild key.
local function underKey(tbl, key)
    local lower = string.lower(key)
    for k, v in pairs(tbl) do
        if string.lower(k) == lower then return v end
    end
    return nil
end

-- Can a guildmate reporting library version `v` answer the guildmate request
-- (`q = 2`)? It arrived in 0.8.0 (MINOR 19). On 2026-09-16 the user's client
-- asked a guildmate VersionCheck had heard, waited three minutes on silence,
-- and held every click meanwhile -- the version said "runs the library", not
-- "runs one that can answer". A dev build (no digits: "GuildRoster-v0.9.2")
-- carries current code; an unparseable released string is not assumed able.
local function answersGuildPull(v)
    if v == nil then return false end
    v = tostring(v)
    -- The packager's placeholder, unsubstituted: a working copy, current code.
    if v == "GuildRoster-v0.9.2" then return true end
    -- An embedded copy with no TOC reports "r<MINOR>" (GetVersionString).
    local r = v:match("^r(%d+)$")
    if r then return tonumber(r) >= 19 end
    local major, minor = v:match("(%d+)%.(%d+)")
    major, minor = tonumber(major), tonumber(minor)
    if not major then return false end
    return major > 0 or minor >= 8
end

--- THE GUILD STEP, BY HANDSHAKE. Whisper the best online GUILDMATE known to run
-- this library for their copy of a sister guild -- the ordinary `q = 2`
-- request, which every client since MINOR 19 answers (ack and roster, a delta,
-- or "unchanged"). Known = VersionCheck has heard their version; ranked by
-- versionRank, our own version first. Each guildmate is asked once per
-- session per guild.
--
-- WHY THIS AND NOT ONLY THE BROADCAST. The first cut of MINOR 20 asked the
-- guild by a GUILD broadcast alone, which only a MINOR 20 client understands.
-- On 2026-09-16 the user's client went straight to the sister guild: every
-- guildmate online was on the released 0.8.0, so nobody could answer the
-- broadcast, and nothing held the click for the guild. The user had asked for
-- exactly this -- "do the same handshakes we do with the sister guild with the
-- guild members" -- and a whisper handshake is something 0.8.0 answers.
-- Only while the guild step is owed.
-- @param key string  the listed guild key
-- @return boolean  a request went out
function lib:PullFromGuildmates(key)
    local ss, ws = self.sisterSync, self.whoSync
    local lower = string.lower(key)
    if not ws.afterGuild[lower] or underKey(ss.pendingPull, key) then return false end
    local asked = ss.guildAsked[lower] or {}
    ss.guildAsked[lower] = asked
    local me = self:GetNormalizedPlayer()
    local best, bestRank
    for name, m in pairs(self.roster) do
        if m.isOnline and name ~= me and not asked[string.lower(name)]
            and answersGuildPull(self:PeerLibraryVersion(name)) then
            local rank = versionRank(self, name)
            if not best or rank < bestRank or (rank == bestRank and name < best) then
                best, bestRank = name, rank
            end
        end
    end
    if not best then return false end
    asked[string.lower(best)] = true
    syncEvent(self, "asking %s for the guild's copy of %s first", best, guildNameOf(key))
    return self:PullSisterRoster(best, heldKey(self, key) or key, { relayed = true })
end

--- The guild has had its say about a guild: a guildmate's copy landed, one said
-- it holds the same copy or an older one, or no guildmate running the library
-- is known. If our copy is now current (the pull clock says so) the discovery
-- owed at login is dropped and the sister guild is not asked; otherwise it
-- stays owed and, when a member of the sister guild is already known online,
-- is pulled from at once.
-- @param key string
-- @return boolean  the guild made our copy current
function lib:FinishGuildStep(key)
    local ws = self.whoSync
    local lower = string.lower(key)
    if not ws.afterGuild[lower] then return false end
    ws.afterGuild[lower] = nil
    local last = underKey(self.sisterSync.lastPull, key)
    if last and (GetTime() - last) < self.SISTER_PULL_INTERVAL then
        local name = string.lower(guildNameOf(key))
        for i = #ws.queue, 1, -1 do
            if string.lower(ws.queue[i]) == name then
                table.remove(ws.queue, i)
                ws.queued[name] = nil
            end
        end
        if ws.gwOwed and string.lower(ws.gwOwed) == lower then ws.gwOwed = nil end
        syncEvent(self, "the guild's copy of %s is current; the sister guild is not asked", guildNameOf(key))
        return true
    end
    syncEvent(self, "nothing newer of %s in the guild; the sister guild is next", guildNameOf(key))
    local held = heldKey(self, key)
    if held then self:PullFromFreshest(held) end
    return false
end

-- Is the click to hold its discovery for this guild? Only while the guild step
-- is owed: yes while a guildmate's copy is on its way, or when one can be
-- asked now; otherwise the guild step is finished here -- nobody in the guild
-- to ask -- and the click goes on to the sister guild.
--
-- A guildmate request NOBODY HAS ACKNOWLEDGED holds one click, not every click.
-- A guildmate that can answer does so in well under a second (an "unchanged",
-- a refusal to vouch, or an ack before the bulk), so a SECOND click on a
-- request still unacknowledged is itself the evidence that no answer is coming
-- -- and waiting on silence is exactly what the user ruled out. The click is an
-- event, not a clock: both OnMouseDown handlers run inside one frame, so the
-- frame's GetTime() is what makes "the same click" and "a later click" differ.
-- An acknowledged request (the roster is on its way) keeps holding.
local function waitingOnGuild(self, key)
    if not self.whoSync.afterGuild[string.lower(key)] then return false end
    local pending = underKey(self.sisterSync.pendingPull, key)
    if pending and pending.relayed then
        if pending.acked then return true end
        local now = GetTime()
        if not pending.clickHeld then
            pending.clickHeld = now
            syncEvent(self, "waiting for %s's copy of %s; click again to go on without it",
                tostring(pending.peer), guildNameOf(key))
            return true
        end
        if pending.clickHeld == now then return true end
        syncEvent(self, "%s did not answer for %s; going on to the sister guild", tostring(pending.peer), guildNameOf(key))
        -- The silent guildmate's record goes first: left in place it blocked
        -- PullFromFreshest and PullFromCandidates, and the round re-asked the
        -- same guildmate, so "going on" reached the sister guild only minutes
        -- later (Peer Review, 2026-09-16, finding 1).
        for k in pairs(self.sisterSync.pendingPull) do
            if string.lower(k) == string.lower(key) then self.sisterSync.pendingPull[k] = nil end
        end
        self:FinishGuildStep(key)
        return false
    end
    if pending then return false end
    if self:PullFromGuildmates(key) then return true end
    self:FinishGuildStep(key)
    return false
end

-- Drop queued guilds that no longer need asking: somebody from them has been
-- seen since (a pull, an ack, a relay, the player's own /who) -- or the guild
-- was unlisted. The user: "once you have a successful who you can turn the
-- overlay off, as you just need it to kickstart the sync process".
local function pruneWho(self)
    local ws = self.whoSync
    local faction = (UnitFactionGroup and UnitFactionGroup("player")) or "Neutral"
    local i = 1
    while i <= #ws.queue do
        local name = ws.queue[i]
        local key = faction .. "-" .. name
        -- A by-name query (a verification) is settled by its answer only.
        local settled = not ws.nameQueries[string.lower(name)] and not self:IsSisterGuildKey(key)
        if not settled and not ws.nameQueries[string.lower(name)] then
            for _, k in ipairs(self:GetKnownRosters()) do
                if string.lower(k) == string.lower(key) and freshestPeer(self, k) then settled = true end
            end
        end
        -- Never settled while a pull waits on this answer to place its asker:
        -- somebody seen in the guild says nothing about THEM.
        if settled then
            for _, rec in pairs(self.sisterSync.pendingVerify) do
                if string.lower(rec.key) == string.lower(key) then settled = false end
            end
        end
        if settled then
            table.remove(ws.queue, i)
            ws.queued[string.lower(name)] = nil
        else
            i = i + 1
        end
    end
end

--- Find someone to pull a listed guild from, when nobody is seen. TWO PATHS
-- (the user, 2026-09-16: "if we already have a full roster, we could go
-- right to the version check step. the beaute of VC is that it doesn't have
-- the /who cap of 50 people"):
--   * a roster of that guild is HELD -> owe the VersionCheck-over-GreenWall
--     ask (step 2, from the click). Every online member running the library
--     whispers back, uncapped, and one who is in the copy we hold is placed
--     and pulled from as they answer (OnPeerVersion's wire sighting);
--   * nothing held, or no GreenWall/VersionCheck to ask through -> owe a
--     /who (step 1) so the server names who is online, cap and all.
-- @param key string  the listed guild key
-- @return boolean  something was owed
function lib:DiscoverPeers(key)
    -- Any discovery but the one StartSisterSync owes comes after the guild's
    -- turn (a round, Sync now), so it is never held behind it.
    local ws = self.whoSync
    ws.afterGuild[string.lower(key)] = nil
    local VC = versionCheck()
    local held = self.rosters[key]
    -- The second path is for a FULL roster -- the user's word -- which means a
    -- copy we PULLED (it carries a stamp). A copy with no stamp, like the
    -- 27-of-289 one a 0.7.0 relay left behind, can place almost nobody who
    -- answers, so it goes to the server. And once the confederation has been
    -- asked this session and still nobody is placed, the next discovery is the
    -- /who: on 2026-09-16 the ask went out three times in two minutes and the
    -- /who never ran at all, because nothing ever fell back to it.
    if GreenWallAPI and VC and (VC.RequestAbout or VC.RequestCheck) and held and next(held)
        and copyStamp(self, key) and not ws.gwSent[string.lower(key)] then
        return self:AskWhoRunsTheLibrary({}, key) > 0
    end
    return self:QueueWho(key)
end

--- Owe a /who for a listed guild. Paced by WHO_INTERVAL and deduplicated; the
-- overlay comes up so the next click sends it. The round calls this for every
-- guild it could not pull; Sync now and the slash command drain it at once.
-- @param guildKey string  "Faction-GuildName"
-- @param force boolean  ignore the pacing: a pull is waiting on this answer
-- @return boolean  queued now
function lib:QueueWho(guildKey, force)
    if not self:IsSisterGuildKey(guildKey) then return false end
    local ws = self.whoSync
    local name = guildNameOf(guildKey)
    local slot = string.lower(name)
    if ws.queued[slot] then return false end
    local last = ws.lastWho[slot]
    if force then
        -- A verification: one query out for this guild is enough, its answer
        -- decides. (Only here -- a paced re-ask past WHO_INTERVAL must go out
        -- even if an older one was never answered, or a lost answer would
        -- silence this guild for the session.)
        for _, asked in ipairs(ws.asked) do
            if asked == slot then return false end
        end
    elseif last and (GetTime() - last) < self.WHO_INTERVAL then
        return false
    end
    ws.queue[#ws.queue + 1] = name
    ws.queued[slot] = true
    self:ShowWhoOverlay()
    return true
end

--- The click-catcher. Shown only while a /who is owed; hidden the moment the
-- queue empties. Built on first use, OUT of combat: SetPropagateMouseClicks is
-- protected in combat lockdown and a blocked call is not a Lua error -- the
-- frame would then swallow every click in the game -- so propagation is applied
-- behind InCombatLockdown, verified with the getter, and the overlay is never
-- shown until it has verified (PLAYER_REGEN_ENABLED retries). FGI's Wingman is
-- the proven shape of all of this.
-- @return boolean  shown
function lib:ShowWhoOverlay()
    local ws = self.whoSync
    local o = ws.overlay
    pruneWho(self)
    if #ws.queue == 0 and not ws.gwOwed then
        if o and ws.shown then o:Hide() ws.shown = false end
        return false
    end
    if not o then
        if not (CreateFrame and UIParent) then return false end
        o = CreateFrame("Frame", "LibGuildRosterWhoOverlay", UIParent)
        o:SetAllPoints(UIParent)
        o:SetFrameStrata("TOOLTIP")
        o:SetFrameLevel(9999)
        o:EnableMouse(true)
        o:Hide()
        -- Mouse DOWN is the hardware event; the click itself passes through.
        -- Both owed sends ride it: the confederation ask (step 2) and the
        -- /who (step 1); SendQueuedWho hides the catcher once nothing is owed.
        o:SetScript("OnMouseDown", function() self:SendConfederationAsk() self:SendQueuedWho() end)
        ws.overlay = o
    end
    if not ws.propagationOK then
        if InCombatLockdown and InCombatLockdown() then return false end
        if not o.SetPropagateMouseClicks then return false end
        o:SetPropagateMouseClicks(true)
        if o.SetPropagateMouseMotion then o:SetPropagateMouseMotion(true) end
        -- The getter, not the setter: a blocked setter returns nothing either way.
        if o.CanPropagateMouseClicks then
            ws.propagationOK = o:CanPropagateMouseClicks() == true
        else
            ws.propagationOK = true
        end
        if not ws.propagationOK then return false end
    end
    if not ws.shown then o:Show() ws.shown = true end
    return true
end

--- Release VersionCheck's parked GreenWall request from a hardware event --
-- the click overlay, Sync now, or the slash command -- instead of waiting for
-- VersionCheck's own chat-keystroke hook. `VC:FlushGreenWall()` when
-- VersionCheck carries it (asked for); until then the three lines its hook
-- runs, done here: VersionCheck's own bytes, under VersionCheck's own name,
-- so GreenWall's sender check and the far side's handler see exactly what
-- the hook would have sent. Nothing of the wire is built here. The user,
-- 2026-09-15: "no 2 uses the OVERLAY".
-- @return boolean  a request went out
function lib:SendConfederationAsk()
    local ws = self.whoSync
    if not ws.gwOwed then return false end
    -- (waitingOnGuild says why, once: every click used to add a line, and a
    -- player clicking through a wait filled the event ring with nothing else.)
    if waitingOnGuild(self, ws.gwOwed) then return false end
    -- The guild step may have just made our copy current and dropped the ask.
    if not ws.gwOwed then self:ShowWhoOverlay() return false end
    local VC = versionCheck()
    if not (VC and GreenWallAPI and GreenWallAPI.SendMessage) then ws.gwOwed = nil return false end
    if VC.FlushGreenWall then
        if not VC:FlushGreenWall() then ws.gwOwed = nil return false end
    else
        local payload = VC.gwPendingPayload
        if not payload then ws.gwOwed = nil return false end
        VC.gwPendingPayload = nil
        GreenWallAPI.SendMessage("VersionCheck-1.0", payload)
    end
    ws.gwSent[string.lower(ws.gwOwed)] = true
    ws.gwOwed = nil
    syncEvent(self, "asked the confederation who runs the library (VersionCheck over GreenWall, from the click)")
    return true
end

--- Send ONE queued /who. MUST run inside a hardware event (a click, an Enter)
-- or the client blocks it; the callers are the overlay's OnMouseDown, Sync
-- now, and the slash command. Returns what it did so a caller can say so.
-- @return boolean  a query went out
function lib:SendQueuedWho()
    local ws = self.whoSync
    pruneWho(self)
    if #ws.queue == 0 then self:ShowWhoOverlay() return false end
    local FL = C_FriendList
    if not (FL and FL.SendWho and FL.SetWhoToUi) then
        wipe(ws.queue) wipe(ws.queued)
        self:ShowWhoOverlay()
        return false
    end
    -- The player's own Who pane is open: theirs, not ours. Try on the next
    -- click -- and SAY so: on 2026-09-15 the bar sat at "click anywhere" through
    -- clicks and a Sync now, and this silent return was why.
    if FriendsFrame and FriendsFrame.IsShown and FriendsFrame:IsShown() then
        syncEvent(self, "a /who is owed but the Social window is open; close it and click anywhere")
        return false
    end
    -- Inside the server's floor of the last /who anyone sent (WHO_SEND_FLOOR):
    -- the server would eat ours, and if theirs is still out the two answers
    -- would be misread. The queue keeps it; the next click tries again.
    if ws.lastSendWhoAt and GetTime() - ws.lastSendWhoAt < self.WHO_SEND_FLOOR then
        syncEvent(self, "a /who is owed but one went out %ds ago; the server needs %ds between them -- click again",
            math.floor(GetTime() - ws.lastSendWhoAt), self.WHO_SEND_FLOOR)
        return false
    end
    -- The first query not held behind the guild step (waitingOnGuild). Judged
    -- over a copy: finishing a guild step can drop that guild's entry.
    local faction = (UnitFactionGroup and UnitFactionGroup("player")) or "Neutral"
    local snapshot, name = {}, nil
    for i, queued in ipairs(ws.queue) do snapshot[i] = queued end
    for _, queued in ipairs(snapshot) do
        if ws.nameQueries[string.lower(queued)] or not waitingOnGuild(self, faction .. "-" .. queued) then
            for i, still in ipairs(ws.queue) do
                if still == queued then name = table.remove(ws.queue, i) break end
            end
            if name then break end
        end
    end
    if not name then
        if #ws.queue == 0 then self:ShowWhoOverlay() end
        return false
    end
    ws.queued[string.lower(name)] = nil
    ws.lastWho[string.lower(name)] = GetTime()
    -- Unconditionally, not only when `borrowed` is false: a third party can
    -- have re-registered the frame under a standing debt (see the header),
    -- and UnregisterEvent is idempotent. The hooks that settle the debt are
    -- installed here, at the first borrow, because before one nothing is owed.
    if FriendsFrame and FriendsFrame.UnregisterEvent then
        FriendsFrame:UnregisterEvent("WHO_LIST_UPDATE")
        ws.borrowed = true
        self:HookWhoPane()
    end
    FL.SetWhoToUi(true)
    -- The PLAIN guild name, exactly what the user types: `/who the other gods`
    -- listed all six on Classic Era on 2026-09-15. The first cut sent the
    -- `g-"..."` tag form and nothing came of it -- whether the tag or the
    -- 27-member held copy (fixed in the same hour) was the cause is NOT
    -- known. Blizzard's own Classic UI builds `z-"..."` and `n-...` filters
    -- but never `g-`, so the plain form is the one with evidence. It matches
    -- names and zones too; the answer is filtered by each row's guild, so
    -- that costs nothing.
    FL.SendWho(name)
    ws.lastSendWhoAt = GetTime()   -- the hook stamps it too; this covers a client the hook could not be installed on
    ws.outstanding = ws.outstanding + 1
    ws.asked[#ws.asked + 1] = string.lower(name)   -- answers come back in send order
    syncEvent(self, ws.nameQueries[string.lower(name)] and "asked the server about %s" or "asked the server who is online in %s", name)
    self:ShowWhoOverlay()   -- hides itself once the queue is empty
    return true
end

lib.WHO_ASK_LIMIT = 10   -- members of one guild asked what they run, per /who answer

--- Pull a listed guild from the best of the members the server listed online
-- (`whoSync.candidates[key]`): the most compatible member VersionCheck has
-- heard from. Nobody heard from yet -> ask them (up to WHO_ASK_LIMIT) and
-- pull when the first answer lands (OnPeerVersion). Without VersionCheck
-- installed here there is nothing to ask with, so the first row is asked
-- outright -- best effort, and the pre-VersionCheck behaviour.
-- @param key string  the listed guild key
-- @return boolean  a pull went out
function lib:PullFromCandidates(key)
    local names = self.whoSync.candidates[key]
    if not names or #names == 0 then return false end
    if self.sisterSync.pendingPull[key] then return false end
    -- Paced like the round: a version answer landing minutes after the pull
    -- it was asked for must not pull again.
    local last = self.sisterSync.lastPull[key]
    if last and (GetTime() - last) < self.SISTER_PULL_INTERVAL then return false end
    local held
    for _, k in ipairs(self:GetKnownRosters()) do
        if string.lower(k) == string.lower(key) then held = k end
    end
    local peer
    if not versionCheck() then
        peer = names[1]
    else
        local bestRank
        for _, n in ipairs(names) do
            local r = versionRank(self, n)
            if r < 3 and (not bestRank or r < bestRank) then peer, bestRank = n, r end
        end
        if not peer then
            self:AskWhoRunsTheLibrary(names, key)
            return false
        end
    end
    -- A member we are about to ask is a sighting the round can use later.
    if held then self:MarkOnline(held, { peer }) end
    if self:PullSisterRoster(peer, key) then
        self.sisterSync.lastPull[key] = GetTime()
        return true
    end
    return false
end

--- VersionCheck heard what a member runs. If they are one of the members a
-- /who listed for a guild nothing is pending for, that guild is pulled now,
-- from the most compatible member known -- which may be someone better who
-- answered earlier. The first answer is not waited past: waiting would be a
-- timer, and a same-version member who answers later is preferred from the
-- next round on, through freshestPeer's ranking.
-- @param sender string
-- @param version string
function lib:OnPeerVersion(sender, version)
    local canon = self:CanonName(sender) or sender
    local who = senderKey(self, sender)
    -- A GUILDMATE runs the library: if the guild step is still owed for a
    -- guild and nobody has been asked, they are someone to ask. VersionCheck's
    -- login request is answered seconds after login, which is exactly when
    -- the guild step starts.
    if self:IsInGuild(sender) then
        for _, key in ipairs(self:GetSisterGuildKeys()) do self:PullFromGuildmates(key) end
        return
    end
    for key, names in pairs(self.whoSync.candidates) do
        for _, n in ipairs(names) do
            if senderKey(self, n) == who then
                syncEvent(self, "%s runs LibGuildRoster %s", canon, tostring(version))
                self:PullFromCandidates(key)
                return
            end
        end
    end
    -- Not a /who candidate, but VersionCheck fires this for a REQUEST it
    -- harvested too (via "REQ") -- a sister member's own login trigger or
    -- their RequestAbout arriving over GreenWall. That is a proven sighting:
    -- online, and running the library, in one message. Seen on 2026-09-15:
    -- The Old Gods side sat at "nobody seen online" while The Other Gods
    -- side had just asked the confederation, which is this very message.
    -- Only a member of a copy we HOLD can be placed in a guild (the request
    -- does not say which), and the pull is paced like the round -- every
    -- sister member's login batch fires this, and one pull per interval is
    -- all a roster needs.
    local key = self:IsInAnyRoster(canon)
    if key and key ~= self:GetHomeGuildKey() and self:IsSisterGuildKey(key) then
        syncEvent(self, "%s runs LibGuildRoster %s (heard on the wire)", canon, tostring(version))
        self:MarkOnline(key, { canon })
        local last = self.sisterSync.lastPull[key]
        if not last or (GetTime() - last) >= self.SISTER_PULL_INTERVAL then
            self:PullFromFreshest(key)
        end
        return
    end
    -- NOBODY CAN PLACE THEM. Until MINOR 20 this answer was dropped without a
    -- word: on 2026-09-16 the user's other character answered the confederation
    -- ask, the asking client held a 27-member copy that did not contain them,
    -- and the status bar sat at "nobody seen online" with nothing in the event
    -- ring to say why. The answer proves they run the library and are online;
    -- only their guild is unknown, and the server can say that -- a /who by name,
    -- whose row lands in `candidates` and pulls (OnWhoListUpdate). Only while a
    -- listed guild still has nobody to pull from, and at most WHO_ASK_LIMIT per
    -- session: a confederation has many guilds, most not listed.
    if key then return end
    local ws = self.whoSync
    for _, listed in ipairs(self:GetSisterGuildKeys()) do
        if not freshestPeer(self, heldKey(self, listed) or listed) and not underKey(self.sisterSync.pendingPull, listed) then
            -- Said only when the lookup is actually queued (finding 4).
            if ws.placeAsks < self.WHO_ASK_LIMIT and self:QueueWhoName(canon) then
                ws.placeAsks = ws.placeAsks + 1
                syncEvent(self, "%s runs LibGuildRoster %s but is in no copy we hold; asking the server where they are",
                    canon, tostring(version))
            end
            return
        end
    end
end

--- The server's answer to a /who -- ours or the player's own, both are free
-- sightings. Every row is a member online right now. Rows for a listed
-- guild are its CANDIDATES: the guild is pulled from the most compatible of
-- them VersionCheck has heard from, or they are asked (PullFromCandidates).
-- They are not presence yet -- the server says they are online, not that
-- they run the library -- so the round cannot pick one blind.
-- @return number  rows that were sister members
function lib:OnWhoListUpdate()
    local ws = self.whoSync
    local FL = C_FriendList
    if not (FL and FL.GetNumWhoResults and FL.GetWhoInfo) then return 0 end
    local faction = (UnitFactionGroup and UnitFactionGroup("player")) or "Neutral"
    local found = 0
    local byKey = {}
    local seenGuilds, seenOrder = {}, {}   -- what the rows DID say, for the event
    -- BOTH returns: rows we may read, and the server's total. The server caps
    -- a /who at 50 rows (Classic FriendsFrame.lua:11 MAX_WHOS_FROM_SERVER), so
    -- `total > n` means the answer is PARTIAL and absence from it proves
    -- nothing -- the exact "partial copy" mistake again, against a /who
    -- (Peer Review, 2026-09-16, PR-1).
    local n, total = FL.GetNumWhoResults()
    n = n or 0
    local partial = type(total) == "number" and total > n
    -- OUR guild-wide query REPLACES a guild's candidates (whoever is absent
    -- logged off). Any other answer -- our by-name query, or the player's own
    -- /who -- is a few rows about somebody in particular and MERGES: the
    -- first cut replaced from those too, so the one row a name query returned
    -- wiped the fifty the guild query had just listed.
    local guildWide = ws.outstanding > 0 and ws.asked[1] ~= nil and not ws.nameQueries[ws.asked[1]]
    if ws.outstanding > 0 then
        -- The user, 2026-09-15: "YOU are opening the social window". Nothing
        -- in Blizzard's Classic source opens it on this path except
        -- WhoList_Update from FriendsFrame's OWN handler, which is
        -- unregistered while our query is out -- so record, on every answer
        -- and BEFORE the rows are judged (so the per-guild events stay the
        -- latest), whether it was registered after all and whether the pane
        -- is up. The ⓘ diagnostics show it.
        local listening = FriendsFrame and FriendsFrame.IsEventRegistered
            and FriendsFrame:IsEventRegistered("WHO_LIST_UPDATE") and true or false
        local paneShown = FriendsFrame and FriendsFrame.IsShown and FriendsFrame:IsShown() and true or false
        syncEvent(self, "our /who answered: %d row(s); Blizzard's handler %s; Social window %s",
            n, listening and "was listening" or "was not listening", paneShown and "open" or "closed")
        -- Listening while we still hold the debt: SOMEBODY ELSE handed the
        -- registration back under us (an FGI older than v2.14.1 does, on its
        -- own answer). Take it back for whatever is still out. A pane the
        -- PLAYER opened is never this case: its OnShow settled the debt first.
        if listening and ws.borrowed and FriendsFrame.UnregisterEvent then
            FriendsFrame:UnregisterEvent("WHO_LIST_UPDATE")
        end
    end
    for i = 1, n do
        local info = FL.GetWhoInfo(i)
        if type(info) == "table" and type(info.fullName) == "string" and type(info.fullGuildName) == "string"
            and info.fullGuildName ~= "" then
            local key = faction .. "-" .. info.fullGuildName
            if not self:IsSisterGuildKey(key) then
                -- On connected realms the server spells a foreign guild
                -- "Guild-Realm", exactly as it spells the player. The list is
                -- typed as the bare name, so a row for "The Other Gods-Azuresong"
                -- matched nothing and the bar said "nobody seen online" beside
                -- four of them (2026-09-15, read off the ring's "guilds seen").
                local bare = info.fullGuildName:match("^(.-)%-[^%-]+$")
                if bare and self:IsSisterGuildKey(faction .. "-" .. bare) then key = faction .. "-" .. bare end
            end
            if self:IsSisterGuildKey(key) then
                local list = byKey[key]
                if not list then list = {} byKey[key] = list end
                list[#list + 1] = info.fullName
                found = found + 1
            elseif not seenGuilds[info.fullGuildName] then
                seenGuilds[info.fullGuildName] = true
                seenOrder[#seenOrder + 1] = info.fullGuildName
            end
        end
    end
    for key, names in pairs(byKey) do
        -- The server spells the guild its way; the pending record is filed
        -- under the LISTED spelling, where the round and the status line look.
        local held, listed
        for _, k in ipairs(self:GetKnownRosters()) do
            if string.lower(k) == string.lower(key) then held = k end
        end
        for _, k in ipairs(self:GetSisterGuildKeys()) do
            if string.lower(k) == string.lower(key) then listed = k end
        end
        -- The server vouches for every row, whether or not the copy we hold
        -- knows them (a partial or stale roster -- the 27-of-289 case), so
        -- the candidate list is the server's, not the intersection.
        local pendingKey = listed or held or key
        if guildWide then
            ws.candidates[pendingKey] = names
        else
            -- A few rows about somebody in particular: add, never replace.
            local merged = ws.candidates[pendingKey] or {}
            for _, row in ipairs(names) do
                local canon, dup = self:CanonName(row) or row, false
                for _, have in ipairs(merged) do
                    if (self:CanonName(have) or have) == canon then dup = true end
                end
                if not dup then merged[#merged + 1] = row end
            end
            ws.candidates[pendingKey] = merged
        end
        syncEvent(self, "the server lists %d of %s online", #names, guildNameOf(key))
        self:PullFromCandidates(pendingKey)
    end
    if found == 0 then
        -- Name what the rows DID say: a guild spelled differently from the
        -- list, or a query that matched names and zones but no member, is
        -- diagnosable from this line and from nothing else.
        local seen = #seenOrder > 0 and (" -- guilds seen: " .. table.concat(seenOrder, ", ", 1, math.min(#seenOrder, 5))
            .. (#seenOrder > 5 and (" (+" .. (#seenOrder - 5) .. ")") or "")) or ""
        syncEvent(self, "the server answered a /who with %d row(s), none in a listed guild%s", n, seen)
    end
    if ws.outstanding > 0 then
        -- OUR query asked about ONE guild (SendQueuedWho pops one name and
        -- queues it on `asked`; the server answers in send order). An answer
        -- with no rows for that guild means nobody is online there now, and
        -- the candidates from an earlier answer must go, or the status bar
        -- keeps saying "N online" about people who logged off.
        local askedSlot = table.remove(ws.asked, 1)
        for key in pairs(ws.candidates) do
            if askedSlot and string.lower(guildNameOf(key)) == askedSlot then
                local listedNow = false
                for k in pairs(byKey) do
                    if string.lower(k) == string.lower(key) then listedNow = true end
                end
                if not listedNow then ws.candidates[key] = nil end
            end
        end
        -- Pulls that waited on this answer: the server has now said who is
        -- in the guild we asked about, so serve the ones it lists; the rest
        -- are refused when the answer was complete, or asked about BY NAME
        -- when it was cut at the cap.
        if askedSlot and ws.nameQueries[askedSlot] then
            ws.nameQueries[askedSlot] = nil
            self:ResolveNameVerify(askedSlot)
        elseif askedSlot then
            for _, listed in ipairs(self:GetSisterGuildKeys()) do
                if string.lower(guildNameOf(listed)) == askedSlot then
                    self:ResolvePendingVerify(listed, ws.candidates[listed] or {}, partial)
                end
            end
        end
        ws.outstanding = ws.outstanding - 1
        -- The flag goes back off; the registration does NOT go back here --
        -- the debt stands until the player wants the pane (see the header).
        if ws.outstanding == 0 and FL.SetWhoToUi then FL.SetWhoToUi(false) end
    end
    -- Anyone still waiting is re-judged against what we hold NOW -- the rows
    -- just landed in `candidates`, and this is the ONLY thing that places an
    -- asker off the player's OWN /who (PR-4), where nothing above ran. It is
    -- deliberately AFTER the block: a by-name verification is decided by its
    -- own row (ResolveNameVerify), which knows the query was about that one
    -- player; the recheck cannot tell that apart from a guild-wide sighting.
    if next(self.sisterSync.pendingVerify) then self:RecheckPendingVerify() end
    return found
end

-- Serve or refuse one waiting asker, and forget the record. `ok` is
-- mutual()'s answer or the server's; `why` is for the ring, `reason` for
-- the wire (REFUSAL_REASONS).
local function decidePending(self, slot, rec, ok, why, reason)
    self.sisterSync.pendingVerify[slot] = nil
    local comm, serializer = commReady(self)
    local homeKey = self:GetHomeGuildKey()
    if not (comm and homeKey and self.initialized) then return end
    if ok then
        syncEvent(self, "%s; serving %s", why, tostring(rec.sender))
        local theirHash  = type(rec.hs) == "table" and rec.hs[homeKey] or nil
        local theirNotes = type(rec.ns) == "table" and rec.ns[homeKey] or nil
        local theirRanks = type(rec.rs) == "table" and rec.rs[homeKey] or nil
        serveRoster(self, comm, serializer, rec.sender, homeKey, theirHash, false, theirNotes, theirRanks)
    else
        refusePull(self, comm, serializer, rec.sender, homeKey, why, reason)
    end
end

--- Decide the pulls that waited on a /who for `key`: the server's rows are
-- the proof of membership the mutual rule needs (the user: "the who proved
-- they were in the guild didn't it?"). Listed -> served, as if the request
-- had arrived now. Not listed -> refused when the answer was COMPLETE; when
-- the server cut it at its 50-row cap (`partial`) absence proves nothing, so
-- the one asker is asked about BY NAME instead -- one row, never capped
-- (QueueWhoName, decided by ResolveNameVerify). Public so it can be specced.
-- @param key string  the listed guild key the /who asked about
-- @param names table  the members the server listed in it
-- @param partial boolean  the server had more rows than it sent
-- @return number  pulls decided
function lib:ResolvePendingVerify(key, names, partial)
    local pv = self.sisterSync.pendingVerify
    local decided = 0
    for slot, rec in pairs(pv) do
        if string.lower(rec.key) == string.lower(key) then
            local who = senderKey(self, rec.sender)
            local listedNow = false
            for _, n in ipairs(names) do
                if senderKey(self, n) == who then listedNow = true end
            end
            if listedNow then
                decided = decided + 1
                decidePending(self, slot, rec, true, "the server places them in " .. guildNameOf(key))
            elseif partial then
                syncEvent(self, "the server cut the %s list short; asking it about %s by name (click anywhere)",
                    guildNameOf(key), tostring(rec.sender))
                self:QueueWhoName(rec.sender)
            else
                decided = decided + 1
                decidePending(self, slot, rec, false, "the server does not list them in " .. guildNameOf(key), "offline")
            end
        end
    end
    return decided
end

--- Decide the askers a BY-NAME /who was about: the one row that is theirs
-- says which guild the server puts them in. Absent -> not online -> refused.
-- @param slot string  the lower-cased bare name the query was sent for
-- @return number  pulls decided
function lib:ResolveNameVerify(slot)
    local FL = C_FriendList
    local faction = (UnitFactionGroup and UnitFactionGroup("player")) or "Neutral"
    local decided = 0
    for pslot, rec in pairs(self.sisterSync.pendingVerify) do
        if string.lower(bareName(rec.sender)) == slot then
            local who = senderKey(self, rec.sender)
            local guildKey
            local n = (FL and FL.GetNumWhoResults and FL.GetNumWhoResults()) or 0
            for i = 1, n do
                local info = FL.GetWhoInfo(i)
                if type(info) == "table" and type(info.fullName) == "string"
                    and senderKey(self, info.fullName) == who then
                    local g = type(info.fullGuildName) == "string" and info.fullGuildName or ""
                    guildKey = faction .. "-" .. g
                    if not self:IsSisterGuildKey(guildKey) then
                        local bare = g:match("^(.-)%-[^%-]+$")
                        if bare then guildKey = faction .. "-" .. bare end
                    end
                end
            end
            decided = decided + 1
            if not guildKey then
                decidePending(self, pslot, rec, false, "the server does not list " .. tostring(rec.sender) .. " online", "offline")
            elseif string.lower(guildKey) == string.lower(rec.key) then
                decidePending(self, pslot, rec, true, "the server places them in " .. guildNameOf(rec.key))
            else
                decidePending(self, pslot, rec, false,
                    "the server places " .. tostring(rec.sender) .. " in " .. guildNameOf(guildKey) .. ", not " .. guildNameOf(rec.key),
                    "notmember")
            end
        end
    end
    return decided
end

--- Owe a /who for ONE player by bare name: the verification of an asker the
-- guild-wide answer could not settle (it was cut at the server's cap). Sent
-- from the click like any other; never pruned as "somebody was seen".
-- @param name string  "Name-Realm" or "Name"
-- @return boolean  queued now
function lib:QueueWhoName(name)
    local ws = self.whoSync
    local bare = bareName(name)
    local slot = string.lower(bare)
    if ws.queued[slot] then return false end
    for _, asked in ipairs(ws.asked) do
        if asked == slot then return false end
    end
    ws.queue[#ws.queue + 1] = bare
    ws.queued[slot] = true
    ws.nameQueries[slot] = true
    self:ShowWhoOverlay()
    return true
end

--- Re-judge every pull waiting on a /who against what we hold NOW: a roster
-- that just landed may place the asker (served) or contradict them (refused);
-- the ones still unplaceable keep waiting for the server's answer.
-- @return number  pulls decided
function lib:RecheckPendingVerify()
    local decided = 0
    for slot, rec in pairs(self.sisterSync.pendingVerify) do
        local ok = mutual(self, rec.sender, rec.key)
        if ok ~= nil then
            decided = decided + 1
            if ok then
                decidePending(self, slot, rec, true, "placed in " .. guildNameOf(rec.key) .. " by what we now hold")
            else
                decidePending(self, slot, rec, false,
                    "we place " .. tostring(rec.sender) .. " outside " .. guildNameOf(rec.key), "notmember")
            end
        end
    end
    return decided
end

--- Give Blizzard its WHO_LIST_UPDATE registration back. Called on the two
-- occasions the player wants the pane (HookWhoPane), never on an answer of
-- ours. Guarded on the debt so it never hands back what it did not take.
-- @return boolean  a debt was settled
function lib:GiveBackWhoList()
    local ws = self.whoSync
    if not ws.borrowed then return false end
    ws.borrowed = false
    if FriendsFrame and FriendsFrame.RegisterEvent then FriendsFrame:RegisterEvent("WHO_LIST_UPDATE") end
    syncEvent(self, "gave Blizzard's Who list its registration back")
    return true
end

--- The two post-hooks that settle the debt: FriendsFrame's OnShow (opening the
-- pane repaints the Who list from the client's buffer by itself), and
-- C_FriendList.SendWho with a non-nil `origin` -- the player's own /who, which
-- every Blizzard call site marks with an Enum.SocialWhoOrigin and no addon
-- does. Keyed to the OBJECTS, not booleans: the suite reinstalls both
-- FriendsFrame and C_FriendList between spec files, and a hook on the old
-- one is a hook on nothing. hooksecurefunc replaces `SendWho` with its
-- wrapper, so recording the wrapper is what stops a second call stacking.
function lib:HookWhoPane()
    local ws = self.whoSync
    local frame = FriendsFrame
    if type(frame) == "table" and type(frame.HookScript) == "function" and ws.paneHooked ~= frame then
        frame:HookScript("OnShow", function() self:GiveBackWhoList() end)
        ws.paneHooked = frame
    end
    local FL = C_FriendList
    if hooksecurefunc and FL and type(FL.SendWho) == "function" and ws.hookedSendWho ~= FL.SendWho then
        hooksecurefunc(FL, "SendWho", function(_, origin)
            ws.lastSendWhoAt = GetTime()   -- every send, whoever's: the server's floor counts them all
            if origin ~= nil then self:GiveBackWhoList() end
        end)
        ws.hookedSendWho = FL.SendWho
    end
end

local function ago(seconds)
    seconds = math.floor(seconds)
    if seconds < 60 then return seconds .. "s" end
    return math.floor(seconds / 60) .. "m" .. (seconds % 60) .. "s"
end

--- One line saying what the sync is doing RIGHT NOW, for the window's status
-- bar (ticked every second while it is open). The shape, in order of what
-- the user needs to know: down, or -- per listed guild -- a pull in flight,
-- nobody to ask, or the countdown to the next automatic ask; then the last
-- thing the sync did and how long ago. The point is that "idle" and
-- "stalled" read differently: a stalled sync says "nobody seen online", an
-- idle one says when it will next act and what it last did.
-- @return string
function lib:GetSyncStatusText()
    if not self:IsSisterSyncAvailable() then
        return "Sync: down -- " .. (self:GetHomeGuildKey() and "roster not ready yet" or "not in a guild")
    end
    local now = GetTime()
    local ss = self.sisterSync
    local parts = {}
    for _, row in ipairs(self:GetSisterStatus()) do
        local key = row.key
        local pending = ss.pendingPull[key]
        local text
        if pending and pending.acked then
            text = string.format("receiving %s members from %s (%s)",
                tostring(pending.expect or "?"), tostring(pending.peer), ago(now - pending.at))
        elseif pending then
            text = string.format("asked %s%s, no answer yet (%s)", pending.relayed and "guildmate " or "",
                tostring(pending.peer), ago(now - pending.at))
        elseif ss.refused[string.lower(key)] then
            -- The other guild's officer has to list us; say so, and who said it.
            local r = ss.refused[string.lower(key)]
            local what = (r.reason == "notmember" and "they place us in a different guild")
                or (r.reason == "offline" and "the server did not list us online in our guild")
                or "they have not listed us"
            text = string.format("%s (%s said so, %s ago)", what, tostring(r.peer), ago(now - r.at))
        elseif not freshestPeer(self, row.held or key) then
            local ws = self.whoSync
            local slot = string.lower(row.name)
            local listed = ws.candidates[key]
            if ws.queued[slot] then
                if FriendsFrame and FriendsFrame.IsShown and FriendsFrame:IsShown() then
                    text = "close the Social window, then click anywhere to ask the server who is online"
                elseif not ws.shown then
                    -- Queued but no catcher up: in combat (propagation cannot be
                    -- verified until PLAYER_REGEN_ENABLED) or no UIParent.
                    text = "click Sync now to ask the server who is online"
                else
                    text = "click anywhere to ask the server who is online"
                end
            elseif ws.outstanding > 0 and ws.lastWho[slot] then
                text = "asking the server who is online"
            elseif listed and #listed > 0 then
                -- The server DID list people; none is library-confirmed yet.
                -- "nobody seen online" here read as wrong to the user beside a
                -- Who List showing four of them (2026-09-15). The confederation
                -- ask is released from the click overlay (SendConfederationAsk);
                -- while it is owed, say so.
                if ws.gwOwed then
                    text = string.format("%d online, click %s to ask the confederation who runs the library",
                        #listed, ws.shown and "anywhere" or "Sync now")
                else
                    text = string.format("%d online, waiting to hear who runs the library", #listed)
                end
            elseif ws.gwOwed and string.lower(ws.gwOwed) == string.lower(key) then
                -- The second path: a roster is held, so the confederation is
                -- asked straight away, no /who (the user, 2026-09-16).
                text = string.format("click %s to ask the confederation who runs the library",
                    ws.shown and "anywhere" or "Sync now")
            else
                text = row.held and "nobody seen online" or "not pulled yet"
            end
        else
            local last = ss.lastPull[key]
            local due = last and (last + self.SISTER_PULL_INTERVAL - now) or 0
            text = due > 0 and ("next pull in " .. ago(due)) or "pull due"
        end
        parts[#parts + 1] = row.name .. ": " .. text
    end
    if #parts == 0 then parts[1] = "no sister guilds configured" end
    local last = ss.lastEvent
    if last then
        parts[#parts + 1] = string.format("last: %s, %s ago", last.text, ago(now - last.at))
    end
    return "Sync: " .. table.concat(parts, "  |  ")
end

-- Schedule a delayed first run and then a repeating one, cancelling whatever a
-- previous StartSisterSync (a guild change, or a LibStub upgrade) left behind.
local function schedule(self, name, delay, interval, fn)
    if not (C_Timer and C_Timer.After and C_Timer.NewTicker) then return end
    local timers = self.sisterSync.timers
    if timers[name] then timers[name]:Cancel() end
    timers[name] = C_Timer.NewTicker(interval, function() fn(self) end)
    C_Timer.After(delay, function() fn(self) end)
end

--- Bring the sync up for the home guild the roster just stabilized in. Called
-- from the login build the moment `initialized` flips, BEFORE OnRosterReady
-- fires, so a consumer reacting to ready already sees the re-fed rosters.
-- Re-entrant: a second call (a guild change) re-resolves the SavedVariables
-- record for the new home guild, re-feeds, and re-arms the timers; the comm
-- registration is made once.
function lib:StartSisterSync()
    local ss = self.sisterSync
    if not self:GetSisterDb() then return false end

    registerComm(self)
    self:RegisterWithVersionCheck()

    self:RefeedSisterRosters()

    -- IN GUILD FIRST (MINOR 20): ask the guild what it holds before anything
    -- goes to a sister guild. See the note above AskGuildForSisterRosters.
    local askedGuild = self:AskGuildForSisterRosters()

    -- Presence is not persisted, so a fresh login knows nobody: owe the
    -- discovery for every listed guild right away (the VersionCheck ask for a
    -- guild whose roster was re-fed, a /who for one we hold nothing of), and
    -- the player's first click sends it, rather than waiting
    -- SISTER_PULL_DELAY for the round to notice -- held behind the GUILD STEP
    -- (waitingOnGuild): a guildmate known to run the library is whispered first
    -- (PullFromGuildmates, now or as VersionCheck hears them), and the owed
    -- discovery is dropped if the guild makes our copy current.
    for _, key in ipairs(self:GetSisterGuildKeys()) do
        if not freshestPeer(self, key) then
            self:DiscoverPeers(key)
            if askedGuild then
                self.whoSync.afterGuild[string.lower(key)] = true
                self:PullFromGuildmates(key)
            end
        end
    end

    schedule(self, "config", self.SISTER_CONFIG_BROADCAST_DELAY,
        self.SISTER_CONFIG_BROADCAST_INTERVAL, self.BroadcastSisterConfig)
    schedule(self, "roster", self.SISTER_ROSTER_BROADCAST_DELAY,
        self.SISTER_ROSTER_BROADCAST_INTERVAL, self.BroadcastSisterRosters)
    schedule(self, "pull", self.SISTER_PULL_DELAY,
        self.SISTER_PULL_INTERVAL, self.RequestSisterRosters)
    ss.started = true
    return true
end

-- ===========================================================================
-- Sister-guild recipients in the Send Mail "To:" autocomplete (MINOR 19)
--
-- A PORT of TOGTools' Modules/Mailbox/Mailbox.lua (2026-09-13, requested by a
-- guild member: mailing someone in the sister guild meant typing the whole
-- name, because Blizzard's autocomplete only knows your OWN guild --
-- AUTOCOMPLETE_LIST.MAIL is ALL_CHARS: InGuild, Friend, InteractedWith,
-- AccountCharacter, Blizzard_AutoComplete/AutoComplete.lua:19-22, :106).
-- Moved here on the user's direction, 2026-09-15: "it shouldn't live in an
-- addon, it belongs in this library." The sister rosters are this library's,
-- so the one thing built on them that every player wants is too.
--
-- HOW IT HOOKS. The edit box's OnLoad (Classic Era MailFrame.xml:584) does
--   AutoCompleteEditBox_SetAutoCompleteSource(self, C_AutoComplete.GetAutoCompleteResults, include, exclude)
-- which stores a plain function in `self.autoCompleteSource` and calls it from
-- AutoComplete_Update as source(text, max, cursor, allowFullMatch, include,
-- exclude), expecting { {name=, priority=}, ... }. Replacing that field with a
-- wrapper that calls the original and appends our matches is the whole hook:
-- no secure function is touched, and it is the same field on every flavour's
-- mail frame. The wrapper checks the setting at CALL time, so switching it off
-- needs no uninstall. Home-guild members are deliberately NOT added --
-- Blizzard already lists them.
--
-- `max` IS A CONTRACT, NOT A HINT. AutoComplete_Update asks for one more result
-- than it can show, and treats "more than it can show" as "continued...".
-- Appending past `max` would make every list read as continued.
--
-- TAINT, traced 2026-09-17 when the user asked ("does the mail run taint?").
-- Yes: AutoComplete_Update (secure) calls this wrapper at AutoComplete.lua:191,
-- so everything it writes after that call is tainted for the keystroke -- the
-- five suggestion buttons' `nameInfo` and text, and the dropdown's
-- `numResults` / `selectedIndex`. The Send button's handler,
-- SendMailFrame_SendMail (MailFrame.lua:864-866), reads the To: box fresh
-- from the widget and calls SendMail -- a restricted function -- without
-- touching any of that, so by the trace the restricted call never runs
-- tainted. The next secure AutoComplete_Update on any box rewrites the
-- dropdown's fields securely. Not measured with a taint log.
--
-- The setting is a PLAYER preference, not a guild fact, so it lives at the
-- root of LibGuildRosterDB rather than in the per-home-guild record, and it
-- answers while guildless. Default ON.
-- ===========================================================================

-- The wrapper currently installed on the box, kept on the lib so a LibStub
-- upgrade recognises the previous copy's closure as its own rather than
-- wrapping it a second time (the closure calls methods on this same table,
-- which the upgrade replaced, so it stays correct).
lib.mailAutocomplete = lib.mailAutocomplete or { wrapper = nil }

--- The account-wide SavedVariables root, created on first use. Distinct from
-- GetSisterDb, which is per home guild and nil while guildless.
local function rootDb()
    local root = _G.LibGuildRosterDB
    if type(root) ~= "table" then
        root = {}
        _G.LibGuildRosterDB = root
    end
    return root
end

--- Is the mailbox autocomplete on for this account? Default true.
-- @return boolean
function lib:IsMailAutocompleteEnabled()
    return rootDb().mailAutocomplete ~= false
end

--- Switch the mailbox autocomplete on or off. Takes effect on the next
-- keystroke; nothing is installed or removed. Fires OnMailAutocompleteChanged.
-- @param enabled boolean
function lib:SetMailAutocomplete(enabled)
    local root = rootDb()
    local now = enabled and true or false
    if (root.mailAutocomplete ~= false) == now then return end
    root.mailAutocomplete = now
    self.callbacks:Fire("OnMailAutocompleteChanged", now)
end

--- Every "Name-Realm" in every sister roster, sorted, deduplicated across
-- rosters. Read live on each call -- the rosters are hundreds of names and
-- the autocomplete fires per keystroke on a box the player is typing into,
-- which is nowhere near a cost worth a cache that can go stale.
-- @return table  sorted array of "Name-Realm"
function lib:GetSisterRecipients()
    local home = self:GetHomeGuildKey()
    local seen, names = {}, {}
    for _, key in ipairs(self:GetKnownRosters()) do
        if key ~= home then
            for charKey in pairs(self:GetRoster(key) or {}) do
                if not seen[charKey] then
                    seen[charKey] = true
                    names[#names + 1] = charKey
                end
            end
        end
    end
    table.sort(names)
    return names
end

--- Append sister-roster matches for `text` to Blizzard's `results`, up to
-- `max` entries in total. Pure: takes the candidate list rather than reading
-- the rosters, so the matching rule is specced without a roster.
--
-- The match is a case-insensitive PREFIX on the character name -- the part
-- before the realm dash -- unless the typed text itself carries a dash, in
-- which case the whole "Name-Realm" is matched so a typed realm narrows rather
-- than being ignored. A name Blizzard already returned (the same character
-- being both a friend and a sister-guild member) is not added twice.
-- @param results table    Blizzard's { {name=, priority=} } list; mutated and returned
-- @param text string      what the player has typed
-- @param max number       the caller's cap on the whole list
-- @param candidates table sorted "Name-Realm" array
-- @param priority any     the priority value to stamp on appended entries
-- @return table  results
function lib:MergeRecipients(results, text, max, candidates, priority)
    results = results or {}
    if not text or text == "" or not max or #results >= max then return results end
    local wanted = string.lower(text)
    local wholeKey = string.find(wanted, "-", 1, true) ~= nil
    local seen = {}
    for _, r in ipairs(results) do
        if r.name then seen[string.lower(r.name)] = true end
    end
    for _, charKey in ipairs(candidates or {}) do
        if #results >= max then break end
        local lower = string.lower(charKey)
        local subject = wholeKey and lower or (string.match(lower, "^([^%-]+)") or lower)
        if string.sub(subject, 1, #wanted) == wanted and not seen[lower] then
            seen[lower] = true
            results[#results + 1] = { name = charKey, priority = priority }
        end
    end
    return results
end

-- The priority every appended entry carries. AutoComplete_UpdateResults
-- indexes AUTOCOMPLETE_COLOR_KEYS by it and reads `.text` off the result, so
-- it MUST be a value that table has -- an invented one would raise inside
-- Blizzard's frame code on the first keystroke. `Other` is plain, and honest:
-- these people are not in the player's guild, so the green "Guild" tag would
-- be a claim. Nil when the client has neither spelling, and the wrapper then
-- contributes nothing.
local function otherPriority()
    if Enum and Enum.AutoCompletePriority and Enum.AutoCompletePriority.Other then
        return Enum.AutoCompletePriority.Other
    end
    return rawget(_G, "LE_AUTOCOMPLETE_PRIORITY_OTHER")
end

--- Wrap SendMailNameEditBox's autocomplete source. Safe to call repeatedly and
-- before the mail frame exists (Retail loads it on demand); the MAIL_SHOW
-- handler calls it again on every mailbox visit, and that is not redundant: a
-- mail addon that assigns `autoCompleteSource` in its own OnLoad after us
-- silently removes our wrapper for the session, so each visit checks the field
-- still holds our closure and re-wraps whatever is there if not. Re-wrapping
-- chains onto the newcomer rather than replacing it, so both contribute -- and
-- MergeRecipients' dedupe means another wrapper offering the same names adds
-- no duplicate rows (TOGTools' original copy did exactly that until it was
-- dropped the day this moved in).
-- @return boolean  whether the wrapper is in place
function lib:InstallMailAutocomplete()
    local box = rawget(_G, "SendMailNameEditBox")
    local orig = box and box.autoCompleteSource
    if type(orig) ~= "function" then return false end
    if orig == self.mailAutocomplete.wrapper then return true end
    local wrapper = function(text, max, ...)
        local results = orig(text, max, ...) or {}
        if not self:IsMailAutocompleteEnabled() then return results end
        local priority = otherPriority()
        if priority == nil then return results end
        return self:MergeRecipients(results, text, max, self:GetSisterRecipients(), priority)
    end
    box.autoCompleteSource = wrapper
    self.mailAutocomplete.wrapper = wrapper
    return true
end

-- ===========================================================================
-- The guild-window tab: our own roster page inside Blizzard's guild window
-- (MINOR 22)
--
-- The user, 2026-09-17: "like how we did the mailbox integration with the
-- sister guilds ... can we populate the wow guild roster with alt guildies?"
-- -- and, on taint: "lets try it, and see, then we can back it out if it's
-- taint or fix it."
--
-- WE TRIED IT, AND THE MEASUREMENT BACKED IT OUT. The first cut appended our
-- rows to Blizzard's own member list with a post-hook on RefreshListDisplay.
-- It worked -- the user: "it's working, they populate" -- and then health-check
-- command 8 (issecurevariable per row, naming the addon that tainted it) read
-- "GuildRoster" on EVERY row of the roster, the player's own guildmates
-- included. The containment argument written here at the time was wrong: the
-- scroll box's own Lua bookkeeping is rewritten inside our insert, the next
-- secure refresh reads it, and from then on every row it initialises is
-- tainted -- which means the officer actions in that window (the rank
-- dropdown's C_GuildInfo.SetGuildRankOrder, Remove, the notes, all
-- HasRestrictions) would be blocked from a guildmate's row. The rows also
-- snapped the scroll position on every roster event, from the same cause.
--
-- WHAT REPLACES IT, chosen with the user. Their words: "can we rebuild the
-- frame exactly and replace it with ours, and then modify it? so when you
-- push the J key it opens our replication instead of theirs, turned on/off in
-- a setting" -- and, on a separate window in the style of GRM, "i'd rather
-- match the games, GRM is different and it looks odd" / "but that just opens
-- another window". So: a FOURTH TAB beside Blizzard's Chat, Roster and Guild
-- Info tabs, built from their own tab template, whose page swaps in INSIDE
-- the guild window. The page is a frame of OURS inheriting
-- CommunitiesMemberListFrameTemplate, so Blizzard's own member-list mixin
-- draws Blizzard's own row template -- it looks exactly like their roster --
-- but every table it reads is ours. And the user's other ask, the same
-- evening: "add our libaceguiwidgets search box to filter through the list" --
-- that is the box above the columns.
--
-- THE FOUR RULES THAT KEEP IT CLEAN, each one the direct lesson of the
-- measurement above. Break any of them and the taint is back.
--
--   1. NEVER WRITE INTO A BLIZZARD TABLE. Not their member arrays, not their
--      data provider, not their CallbackRegistry. Everything this section
--      fills lives on OUR page.
--   2. NEVER CALL A BLIZZARD FRAME'S Show/Hide/SetShown, and never call
--      CommunitiesFrame:SetDisplayMode. MEASURED, not argued: a switch to
--      their Roster page from ShowGuildTab left their sortedMemberList
--      tainted by "GuildRoster" in game (2026-09-18). A Show() made from tainted code runs
--      that frame's OnShow tainted -- and CommunitiesMemberListMixin:OnShow
--      calls UpdateMemberList and registers callbacks on CommunitiesFrame,
--      which is rule 1 broken from the inside. Our page is drawn OVER their
--      content area with its own opaque background instead.
--   3. HOOK, DO NOT REPLACE. `hooksecurefunc` on SetDisplayMode and
--      `HookScript` on the window's OnShow; both are post-hooks that cannot
--      taint what they follow.
--   4. THE TEMPLATE'S OWN SCRIPTS ARE REPLACED ON OUR FRAME BEFORE IT IS EVER
--      SHOWN. OnShow/OnHide/OnUpdate/OnEvent all come from the template and
--      all reach into CommunitiesFrame; ours do not. Same for the row
--      template: an acquired row is unregistered from its events and its
--      OnShow cleared, so it never re-reads itself through
--      C_Club.GetMemberInfo (which is what rejected a negative memberId 40
--      times in game, and is now simply not on the path).
--
-- THE ONE WIDGET CALL WE MAKE ON A BLIZZARD FRAME is SetChecked(false) on
-- their four tabs when ours is clicked, so two tabs do not read as active.
-- A tab is an ordinary CheckButton, nothing protected runs from one, and no
-- secure path reads a tab's checked state -- CommunitiesFrameMixin's
-- UpdateCommunitiesTabs only ever writes it (CommunitiesFrame.lua:1014-1026).
--
-- OFFICER ACTIONS STAY ON BLIZZARD'S OWN ROSTER TAB, and that is not a
-- shortfall to fix later: SetGuildRankOrder, SetNote and RemoveFromGuild are
-- HasRestrictions, so they cannot be driven from our frame at all. That is
-- also why a full replacement of the guild window on J was never possible.
--
-- WHOSE ROWS. Guildmates come from C_Club (the same GetClubMembers /
-- GetMemberInfo pair Blizzard's list uses), so zone, level, rank and note are
-- as live on our page as on theirs, and this touches nothing the library
-- holds -- build-once governs lib.roster, and nothing here writes it. Without
-- C_Club the library's own home roster is the fallback, which is what the
-- offline suite drives. Sister-guild members come from the rosters this
-- library syncs, with their guild's name in the Rank column, and their
-- presence is our own sightings (GetOnlineMembersScoped), so a sister reads
-- online for PRESENCE_TTL after a sighting. The two are interleaved by
-- whatever the list is sorted on, because that is what "the same window"
-- means; the Rank column is what tells them apart.
--
-- WHICH WINDOW. Classic Era has two guild windows and a checkbox between them
-- (`useClassicGuildUI`, Blizzard_UIParent/Vanilla/UIParent.lua:280): the
-- Communities frame, the default, and the old Friends-frame guild tab. This
-- section covers the Communities frame; the section after it puts a fifth
-- tab across the bottom of the Friends frame for the classic one, on the
-- same rules and the same rows.
--
-- Two PLAYER preferences, at the root of LibGuildRosterDB like the mailbox
-- one: whether the tab exists at all (default ON -- the cause of the old
-- default-OFF is gone with the in-list rows), and whether the guild window
-- opens on it (default OFF, so J still does what the player expects until
-- they ask otherwise).
-- ===========================================================================

local function Widgets()
    return LibStub("LibAceGUIWidgets-1.0", true)
end

-- The tab, the page and the hooks, kept on the lib so a LibStub upgrade does
-- not build a second tab or hook the window twice. The closures call methods
-- on this same table, which the upgrade repopulates, so they stay correct.
lib.guildTab = lib.guildTab or {}

-- How far classIdFor scans C_CreatureInfo.GetClassInfo. Classic Era's classes
-- are ids 1-9 and 11; retail's reach 13. A missing id answers nil and is
-- skipped, so a generous bound costs nothing.
lib.ROSTER_CLASS_ID_MAX = 20

-- Sister rows are numbered DOWN from here: row i gets memberId BASE - i, so no
-- sister ever collides with a real club member id in the page's own lookup.
-- It is the largest signed 32-bit value, which also fits an unsigned one.
--
-- IT USED TO BE A NEGATIVE NUMBER, and that cost 40 BugSack errors in one
-- evening (2026-09-17, one per sister row per roster event): the in-list rows
-- of the first cut stayed inside Blizzard's list, so every row frame re-read
-- itself with C_Club.GetMemberInfo(clubId, memberId) on GUILD_ROSTER_UPDATE
-- (CommunitiesMemberList.lua:952-968) and the client rejects a negative id
-- there. Our page's rows unregister that event, so nothing on this path calls
-- GetMemberInfo with one of these any more -- the id is an identity, not a
-- query. Kept positive regardless: the next reader of a row does not know
-- that, and a value that was once rejected by the client is not worth reusing.
lib.ROSTER_SISTER_ID_BASE = 2147483647

--- Is our tab installed on the guild window? DEFAULT ON.
--
-- The default was flipped to OFF on the evening of 2026-09-17, when
-- health-check command 8 measured this library tainting every row of
-- Blizzard's own roster. That shape is gone (see the header), and with it the
-- reason: the tab writes nothing of Blizzard's.
-- @return boolean
function lib:IsGuildTabEnabled()
    return rootDb().guildTab ~= false
end

--- Switch the tab on or off. Fires OnGuildTabChanged. Switching it off hides
-- the page and the tab; switching it on installs them if the window is built.
-- @param enabled boolean
function lib:SetGuildTab(enabled)
    local root = rootDb()
    local now = enabled and true or false
    if (root.guildTab ~= false) == now then return end
    root.guildTab = now
    local rec = self.guildTab
    if now then
        self:InstallGuildTab()
        if rec.tab then rec.tab:Show() end
        -- The classic window's tab follows the same switch, and its own
        -- visibility rule (their Guild tab shown, the player in a guild).
        self:InstallClassicGuildTab()
        self:SyncClassicTabVisibility()
    else
        self:HideGuildTab()
        if rec.tab then rec.tab:Hide() end
        self:HideClassicGuildTab()
        if self.classicTab.tab then self.classicTab.tab:Hide() end
    end
    self.callbacks:Fire("OnGuildTabChanged", now)
end

--- Does the guild window open on OUR tab? DEFAULT OFF -- J keeps doing what
-- the player expects until they ask for ours. The user, 2026-09-17: "when you
-- push the J key it opens our replication instead of theirs, turned on/off in
-- a setting".
-- @return boolean
function lib:IsGuildTabDefault()
    return rootDb().guildTabDefault == true
end

--- Switch "open the guild window on our tab" on or off. Fires
-- OnGuildTabChanged so a settings view repaints.
-- @param enabled boolean
function lib:SetGuildTabDefault(enabled)
    local root = rootDb()
    local now = enabled and true or false
    if (root.guildTabDefault == true) == now then return end
    root.guildTabDefault = now
    self.callbacks:Fire("OnGuildTabChanged", self:IsGuildTabEnabled())
end

--- Is "Show Offline Members" ticked on OUR page? Its own preference rather
-- than Blizzard's `communitiesShowOffline` CVar: writing that CVar would
-- change THEIR list too, which is a side effect nobody asked for.
-- @return boolean
function lib:IsGuildTabShowOffline()
    return rootDb().guildTabOffline == true
end

--- Tick or untick Show Offline Members on our page, and repaint it.
-- @param enabled boolean
function lib:SetGuildTabShowOffline(enabled)
    rootDb().guildTabOffline = enabled and true or false
    self:RefreshGuildTab()
end

-- classFile token ("WARRIOR", what the sister wire carries -- see wireMember)
-- to classID, which is what a roster row wants for its icon and colour
-- (CommunitiesMemberList.lua:1002, :1277). Built on first use from
-- C_CreatureInfo.GetClassInfo; nil for an unknown token or without the API,
-- and the row then draws with no class icon and the default name colour.
local classIdByToken
local function classIdFor(token)
    if type(token) ~= "string" then return nil end
    if not classIdByToken then
        classIdByToken = {}
        local api = C_CreatureInfo and C_CreatureInfo.GetClassInfo
        if api then
            for id = 1, lib.ROSTER_CLASS_ID_MAX do
                local info = api(id)
                if type(info) == "table" and info.classFile then
                    classIdByToken[info.classFile] = info.classID or id
                end
            end
        end
    end
    return classIdByToken[token]
end

-- A sister guild's display name: its key minus the faction prefix.
local function sisterGuildName(key)
    return string.match(key, "^[^%-]+%-(.+)$") or key
end

-- Whether the client has every named XML template. CreateFrame on a template
-- the client lacks is an ERROR, not nil -- "Couldn't find inherited node",
-- thrown at login on a retail client (WoW Forever, 2026-09-19) because the
-- classic tab's guards all passed there: retail's Friends frame has a Bg, a
-- fourth tab (Quick Join) and the same helpers, and has neither of the Classic
-- Guild page's templates (Blizzard_UIPanels_Game/Classic/FriendsFrame.xml:408,
-- :576, in the three Classic trees only). C_XMLUtil.GetTemplateInfo answers
-- nothing for an unknown template and is documented on all four flavours
-- (XMLUtilDocumentation.lua, MayReturnNothing), so it is asked before the
-- first CreateFrame. A client WITHOUT the API is answered true: every Blizzard
-- client has it, so that branch is a private server on an older build, where
-- the tab that built before this check existed still does.
local function hasTemplates(...)
    local xml = rawget(_G, "C_XMLUtil")
    if type(xml) ~= "table" or type(xml.GetTemplateInfo) ~= "function" then return true end
    for i = 1, select("#", ...) do
        if not xml.GetTemplateInfo((select(i, ...))) then return false end
    end
    return true
end

--- The rows for the roster window: one per sister member, in the shape a
-- CommunitiesMemberListEntry draws (a ClubMemberInfo minus what we cannot
-- know -- guid, zone, last online). Pure: reads the rosters and the presence,
-- touches no frame. `guildRankOrder` is deliberately absent (see the header)
-- and `memberId` counts down from ROSTER_SISTER_ID_BASE (see there for why
-- not a negative number).
-- @param includeOffline boolean  keep members not seen online within PRESENCE_TTL
-- @return table  array; online first, then by guild, then by name
function lib:BuildSisterRosterRows(includeOffline)
    local rows = {}
    local home = self:GetHomeGuildKey()
    local presence = Enum and Enum.ClubMemberPresence
    local roles = Enum and Enum.ClubRoleIdentifier
    local ambiguate = rawget(_G, "Ambiguate")
    for _, key in ipairs(self:GetKnownRosters()) do
        if key ~= home then
            local online = {}
            for _, name in ipairs(self:GetOnlineMembersScoped(key)) do online[name] = true end
            local guildName = sisterGuildName(key)
            for charKey, m in pairs(self:GetRoster(key) or {}) do
                local isOnline = online[charKey] == true
                if isOnline or includeOffline then
                    rows[#rows + 1] = {
                        -- Bare for a same-realm member, as Blizzard shows a guildmate.
                        name        = ambiguate and ambiguate(charKey, "guild") or charKey,
                        charKey     = charKey,
                        isSister    = true,
                        sisterGuild = guildName,
                        online      = isOnline,
                        isSelf      = false,
                        classID     = classIdFor(m.class),
                        level       = m.level,
                        memberNote  = m.note,
                        -- The Rank column and the tooltip's second line.
                        guildRank   = guildName,
                        presence    = presence and (isOnline and presence.Online or presence.Offline) or nil,
                        role        = roles and roles.Member or nil,
                    }
                end
            end
        end
    end
    table.sort(rows, function(a, b)
        if a.online ~= b.online then return a.online end
        if a.sisterGuild ~= b.sisterGuild then return a.sisterGuild < b.sisterGuild end
        return a.charKey < b.charKey
    end)
    for i, row in ipairs(rows) do row.memberId = self.ROSTER_SISTER_ID_BASE - i end
    return rows
end

--- The guildmate half of our page's rows: one per member of the player's own
-- guild, in the same ClubMemberInfo shape.
--
-- FROM C_Club WHEN THE CLIENT HAS IT, which is the same pair Blizzard's own
-- member list reads (CommunitiesMemberList.lua:351-353), so zone, level, rank
-- and note are as live on our page as on theirs. The table each call returns
-- is a fresh one, so the two fields we add are added to ours and never to
-- anything Blizzard holds.
--
-- THIS IS NOT A ROSTER REBUILD and does not touch `lib.roster`. Build-once
-- governs the library's own state; this is a read made to DRAW a window the
-- player has open, at the moment Blizzard would be making the same read.
--
-- Without C_Club -- an older or stripped client, and the path the offline
-- suite drives -- the library's own home roster answers instead, at the cost
-- of a zone and a rank frozen at the login build.
-- @param includeOffline boolean  keep members who are offline
-- @return table  array of rows
function lib:BuildHomeGuildRows(includeOffline)
    local rows = {}
    local presence = Enum and Enum.ClubMemberPresence
    local roles = Enum and Enum.ClubRoleIdentifier
    local clubId = C_Club and C_Club.GetGuildClubId and C_Club.GetGuildClubId()
    local ids = clubId and C_Club.GetClubMembers and C_Club.GetClubMembers(clubId)
    if type(ids) == "table" and C_Club.GetMemberInfo then
        for _, id in ipairs(ids) do
            local info = C_Club.GetMemberInfo(clubId, id)
            if type(info) == "table" and info.name then
                local offline = presence and (info.presence == presence.Offline
                    or info.presence == presence.Unknown)
                if not offline or includeOffline then
                    local row = {}
                    for k, v in pairs(info) do row[k] = v end
                    row.isSister = false
                    row.online   = not offline
                    -- The key every roster uses, realm included: C_Club
                    -- hands a same-realm member over bare.
                    row.charKey  = self:NormalizeName(info.name) or info.name
                    rows[#rows + 1] = row
                end
            end
        end
        return rows
    end

    local ambiguate = rawget(_G, "Ambiguate")
    for charKey, m in pairs(self.roster) do
        if m.isOnline or includeOffline then
            rows[#rows + 1] = {
                name       = ambiguate and ambiguate(charKey, "guild") or charKey,
                charKey    = charKey,
                isSister   = false,
                online     = m.isOnline == true,
                isSelf     = charKey == self:GetNormalizedPlayer(),
                classID    = classIdFor(m.class),
                level      = m.level,
                zone       = m.zone,
                guildRank  = m.rankName,
                memberNote = m.publicNote,
                memberId   = nil,
                presence   = presence and (m.isOnline and presence.Online or presence.Offline) or nil,
                role       = roles and roles.Member or nil,
            }
        end
    end
    return rows
end

-- What a row is compared on for each of Blizzard's column attributes. Their
-- Rank column sorts on `guildRankOrder`, which our rows deliberately do not
-- carry (a sister guild has no rank order in this guild), so it maps to the
-- text the column actually shows.
local GUILD_TAB_SORT_KEYS = {
    level          = "level",
    classID        = "classID",
    name           = "charKey",
    zone           = "zone",
    guildRankOrder = "guildRank",
    guildRank      = "guildRank",
    memberNote     = "memberNote",
    charKey        = "charKey",
}

-- One comparison, nils last, numbers descending and text ascending the way
-- Blizzard's CompareMembersByAttribute does (CommunitiesMemberList.lua:798),
-- and charKey as the tie-break so the order is total -- table.sort raises on
-- a comparator that says neither of two rows precedes the other.
local function compareByKey(a, b, key)
    local av, bv = a[key], b[key]
    if av ~= bv then
        if av == nil then return false end
        if bv == nil then return true end
        if type(av) == "number" and type(bv) == "number" then return av > bv end
        return tostring(av) < tostring(bv)
    end
    return nil
end

--- Every row our page shows: the player's guild and every sister roster,
-- filtered and sorted. Pure -- reads the rosters and the client, touches no
-- frame -- which is what makes the whole data half of the tab testable
-- offline.
--
-- `opts.query` is matched with the widget library's own tokenised search
-- (`W:SearchMatch`) across the name, the rank or sister-guild name, the note
-- and the zone, so typing a sister guild's name narrows the list to it.
-- Without LibAceGUIWidgets there is no search box either, and the query is
-- ignored rather than half-implemented here.
-- @param opts table|nil  { includeOffline, query, sortKey, reverse }
-- @return table  array of rows
function lib:BuildGuildTabRows(opts)
    opts = opts or {}
    local rows = self:BuildHomeGuildRows(opts.includeOffline)
    for _, row in ipairs(self:BuildSisterRosterRows(opts.includeOffline)) do
        rows[#rows + 1] = row
    end

    local W = Widgets()
    if opts.query and opts.query ~= "" and W and W.SearchMatch then
        local kept = {}
        for _, row in ipairs(rows) do
            if W:SearchMatch(opts.query, row.name, row.charKey, row.guildRank,
                    row.memberNote, row.zone) then
                kept[#kept + 1] = row
            end
        end
        rows = kept
    end

    local key = GUILD_TAB_SORT_KEYS[opts.sortKey or ""]
    table.sort(rows, function(a, b)
        if key then
            local decided = compareByKey(a, b, key)
            if decided ~= nil then
                if opts.reverse then return not decided end
                return decided
            end
        elseif a.online ~= b.online then
            -- The default order, and Blizzard's: online first, then by name.
            return a.online
        end
        return a.charKey < b.charKey
    end)
    return rows
end

-- ---------------------------------------------------------------------------
-- The frames. Everything below builds or drives OUR tab and OUR page; read
-- the four rules in this section's header before changing any of it.
-- ---------------------------------------------------------------------------

-- Blizzard's own four tabs, unchecked when ours is clicked. Named rather than
-- discovered so a future fifth tab of theirs is a deliberate addition here.
local BLIZZARD_TABS = { "ChatTab", "RosterTab", "GuildBenefitsTab", "GuildInfoTab" }

lib.GUILD_TAB_TOOLTIP = "Guild and sister guilds"
lib.GUILD_TAB_ICON    = "Interface\\Icons\\INV_Misc_GroupLooking"
-- How far above the highest frame of Blizzard's list our page goes, and our
-- border above our page. Their rows sit a few levels under their ScrollBox
-- (ScrollTarget, then the row); 20 clears that with room.
lib.GUILD_TAB_LEVEL_MARGIN = 20
-- How deep LiftGuildTabPage looks under the window. Their deepest drawn
-- thing is a list row: window > MemberList > ScrollBox > ScrollTarget > row.
lib.GUILD_TAB_LEVEL_DEPTH = 6
-- The client's strata, lowest to highest, and the highest our page will take.
lib.GUILD_TAB_STRATA_RANK = {
    BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4,
    DIALOG = 5, FULLSCREEN = 6, FULLSCREEN_DIALOG = 7, TOOLTIP = 8,
}
lib.GUILD_TAB_STRATA_CAP = "HIGH"
-- How far the patch over the Chat page's input box reaches past its left and
-- right edges, for the border's corner diamonds. 4 left them showing in game
-- (2026-09-18); the box ends far enough left of Invite Member for 10 to be safe.
lib.GUILD_TAB_FOOT_MARGIN = 10
-- The search box: wide enough for its placeholder on one line, starting past
-- Show Offline Members, centred in the 20..60 band above the page's top.
lib.GUILD_TAB_SEARCH_WIDTH = 300
lib.GUILD_TAB_SEARCH_X     = 160
-- 44, not the arithmetic middle of 20..60: measured off the user's
-- screenshot (2026-09-18), 40 sat a few pixels below the band's centre, the
-- header's top border and the title's bottom edge not being where the
-- template's numbers alone put them.
lib.GUILD_TAB_SEARCH_Y     = 44
-- The online count's distance in from the page's right edge.
lib.GUILD_TAB_COUNT_INSET  = 8
-- The PITCH of Blizzard's tab column, centre to centre: a 32-high tab
-- (CommunitiesTabs.xml:6) plus the 20 gap between them (CommunitiesFrame.xml:
-- 390). Our tab keeps that rhythm from whatever it hangs under. It used to be
-- a 20 gap from the anchor's BOTTOM, which under GRM's taller 44-high button
-- put ours visibly further down than the others (the user, 2026-09-18: "a bit
-- too far down, we need to tighten the gap up to be what the others have").
lib.GUILD_TAB_PITCH = 52

--- Where our tab goes: under the LAST thing hanging below Blizzard's Guild
-- Info tab, not under Guild Info itself. Another addon may already have put
-- something there -- Guild Roster Manager anchors its roster button TOP to
-- GuildInfoTab's BOTTOM (GRM_UI.lua:16688), and ours sat right on top of it
-- (seen in game, 2026-09-18). So the chain is followed: any SHOWN child of the
-- window anchored to the current bottom becomes the new bottom, and ours goes
-- one gap below the end. Reads only -- nothing of theirs is moved.
-- @param frame table  CommunitiesFrame
-- @param tab table    our tab, skipped in the walk
-- @return table  the frame our tab should hang under
function lib:FindGuildTabAnchor(frame, tab)
    local anchor = frame.GuildInfoTab
    for _ = 1, 10 do
        local nextFrame
        for _, child in ipairs({ frame:GetChildren() }) do
            if child ~= tab and child ~= anchor and child:IsShown() then
                for i = 1, child:GetNumPoints() do
                    local _, relativeTo = child:GetPoint(i)
                    if relativeTo == anchor then nextFrame = child end
                end
            end
        end
        if not nextFrame then break end
        anchor = nextFrame
    end
    return anchor
end

--- Whisper a character, through the API the client prefers.
--
-- `ChatFrameUtil.SendTell` is the real function in Classic Era
-- (Blizzard_ChatFrameBase/Shared/ChatFrameUtil.lua:308); the bare
-- `ChatFrame_SendTell` is only a deprecation fallback, assigned from it in
-- Blizzard_DeprecatedChatInfo/Deprecated_ChatFrame.lua:84 behind
-- `GetCVarBool("loadDeprecationFallbacks")` -- so a client with that CVar off
-- has the namespaced form and nothing else.
-- @param name string  "Name" or "Name-Realm"
-- @return boolean  whether a whisper box was opened
function lib:WhisperName(name)
    if type(name) ~= "string" or name == "" then return false end
    local util = rawget(_G, "ChatFrameUtil")
    if type(util) == "table" and type(util.SendTell) == "function" then
        util.SendTell(name)
        return true
    end
    local legacy = rawget(_G, "ChatFrame_SendTell")
    if type(legacy) == "function" then
        legacy(name)
        return true
    end
    return false
end

--- Invite a character to the group. `C_PartyInfo.InviteUnit` is the Classic
-- Era API (PartyInfoDocumentation.lua:139); the bare `InviteUnit` global is
-- NOT present on this flavour, so there is deliberately no fallback to it.
-- @param name string
-- @return boolean  whether the invite was sent
function lib:InviteName(name)
    if type(name) ~= "string" or name == "" then return false end
    if C_PartyInfo and C_PartyInfo.InviteUnit then
        C_PartyInfo.InviteUnit(name)
        return true
    end
    return false
end

--- The right-click menu for a row on our page. Public for the specs.
-- Whisper and Invite only: everything an officer does to a guildmate is
-- restricted and lives on Blizzard's own Roster tab.
-- @param name string  the character the row is for
-- @return table  menu items
function lib:GuildTabRowMenuItems(name)
    return {
        { text = "Whisper " .. name, onClick = function() self:WhisperName(name) end },
        { text = "Invite to group",  onClick = function() self:InviteName(name) end },
    }
end

--- A click on one of our rows: left whispers, right opens the menu.
-- @param button table  the row frame
-- @param mouse string  "LeftButton" / "RightButton"
-- @return boolean  whether the click did anything
function lib:OnGuildTabRowClick(button, mouse)
    local info = type(button) == "table" and button.memberInfo
    local name = type(info) == "table" and (info.charKey or info.name)
    if not name then return false end
    if mouse == "RightButton" then
        local W = Widgets()
        if not (W and W.OpenMenu) then return false end
        W:OpenMenu(button, self:GuildTabRowMenuItems(name), { width = 220 })
        return true
    end
    return self:WhisperName(name)
end

--- Our scroll box's element initializer: draw the row with Blizzard's own
-- template, then take its events away.
--
-- THE UNREGISTER IS THE LOAD-BEARING LINE. A row of theirs registers
-- CLUB_MEMBER_ROLE_UPDATED and GUILD_ROSTER_UPDATE in its OnShow and re-reads
-- itself with C_Club.GetMemberInfo (CommunitiesMemberList.lua:927-968) -- on
-- our data that is a query for a member the club does not have, which is what
-- filled the user's BugSack on 2026-09-17. Our rows answer to nothing but our
-- own refresh.
--
-- `GetMemberList` is overridden per frame because the template's own reaches
-- the list through three GetParent hops, and our page sits at a different
-- depth in nobody's control but the scroll box's.
-- @param button table  the acquired row frame
-- @param elementData table  { memberInfo = row }
function lib:InitGuildTabRow(button, elementData)
    local page = self.guildTab.page
    button.GetMemberList = function() return page end
    if not button.lgrBound then
        button.lgrBound = true
        if button.UnregisterAllEvents then button:UnregisterAllEvents() end
        button:SetScript("OnShow", nil)
        button:SetScript("OnEvent", nil)
        button:SetScript("OnClick", function(b, mouse) lib:OnGuildTabRowClick(b, mouse) end)
    end
    button:Init(elementData, true)
end

-- The page's own methods, replacing every one of CommunitiesMemberListMixin's
-- that would reach into CommunitiesFrame or C_Club for state. They are set on
-- OUR frame instance, so Blizzard's mixin table is untouched and every other
-- member list in the game still uses theirs.
local function installPageOverrides(page, clubId)
    -- The club we claim to be showing. Read only by Blizzard's own drawing
    -- code on our frame, which uses it to pick the guild column set.
    local clubInfo = { clubId = clubId, clubType = Enum and Enum.ClubType and Enum.ClubType.Guild }
    function page:GetSelectedClubId() return clubId end
    function page:GetSelectedClubInfo() return clubInfo end
    function page:GetSelectedStreamId() return nil end
    function page:IsDisplayingProfessions() return false end
    function page:ShouldShowOfflinePlayers() return lib:IsGuildTabShowOffline() end
    function page:SetShowOfflinePlayers(value) lib:SetGuildTabShowOffline(value) end
    -- Ours is filled by RefreshGuildTab; theirs would query C_Club and then
    -- call Update(), which is the re-entrant path we must not be on.
    function page:UpdateMemberList() lib:RefreshGuildTab() end
    function page:UpdateInvitations() self.invitations = {} end
    function page:UpdateVoiceChannel() self.linkedVoiceChannel = nil end
    function page:GetVoiceChannelID() return nil end
    function page:OnClubMemberButtonClicked() end
    -- Their sort reaches C_Club through CommunitiesUtil to compare members;
    -- ours reads the column's attribute and rebuilds from the library.
    function page:SortByColumnIndex(columnIndex, keepSortDirection)
        local info = self.columnInfo and self.columnInfo[columnIndex]
        local attribute = info and info.attribute
        if not attribute then return end
        local rec = lib.guildTab
        if not keepSortDirection then
            rec.reverse = (attribute == rec.sortKey) and not rec.reverse or false
        end
        rec.sortKey = attribute
        lib:RefreshGuildTab()
    end
end

--- Build the tab and its page, once, on the guild window. Safe to call
-- repeatedly and before the window exists: a flavour that loads
-- Blizzard_Communities on demand gets the ADDON_LOADED retry, and a client
-- without the frame at all is answered false rather than half-built.
-- @return boolean  whether the tab is in place
function lib:InstallGuildTab()
    local rec = self.guildTab
    if rec.page then return true end
    -- A template that was the wrong shape once is the wrong shape for the
    -- session; retrying would only build a second named tab beside the first.
    if rec.failed then return false end
    if not self:IsGuildTabEnabled() then return false end
    local frame = rawget(_G, "CommunitiesFrame")
    if type(frame) ~= "table" or type(frame.GuildInfoTab) ~= "table" then return false end
    -- The two mixins our templates carry, and the scroll plumbing our page is
    -- rebuilt on. All four ship with Blizzard_Communities / SharedXML on every
    -- flavour that has this window; a client missing one gets no tab at all
    -- rather than a half-drawn one.
    if type(rawget(_G, "CommunitiesMemberListMixin")) ~= "table"
        or type(rawget(_G, "CommunitiesFrameTabMixin")) ~= "table"
        or type(rawget(_G, "CreateScrollBoxListLinearView")) ~= "function"
        or type(rawget(_G, "ScrollUtil")) ~= "table" then
        return false
    end
    -- And the templates themselves, asked of the client (see hasTemplates):
    -- the mixins above ship in the same files, but a mixin present and a
    -- template absent is an error inside CreateFrame, not a false here.
    if not hasTemplates("CommunitiesFrameTabTemplate", "CommunitiesMemberListFrameTemplate") then
        return false
    end

    local tab = CreateFrame("CheckButton", "LibGuildRosterGuildTab", frame, "CommunitiesFrameTabTemplate")
    -- The template's OnLoad has already run and read `iconTexture`, which we
    -- could not set before it existed, so the icon is set by hand here.
    tab.iconTexture = self.GUILD_TAB_ICON
    tab.tooltip     = self.GUILD_TAB_TOOLTIP
    if tab.Icon and tab.Icon.SetTexture then tab.Icon:SetTexture(self.GUILD_TAB_ICON) end
    -- Placed by SyncGuildTabVisibility, which runs at the end of this
    -- function and on every tab pass Blizzard makes.
    -- Replaced, not hooked: theirs calls CommunitiesFrame:SetDisplayMode with
    -- a display mode we do not have, which is rule 2 of the header.
    tab:SetScript("OnClick", function() lib:ShowGuildTab() end)

    -- THE PAGE IS BORN UNDER A HOLDER OF OURS, not under the guild window.
    -- The template's OnLoad runs inside CreateFrame, before we can touch the
    -- frame, and it reaches its "communities frame" through GetParent()
    -- (CommunitiesMemberList.lua:454-472, :698-700) to read the selected club.
    -- Born under Blizzard's window, that is our tainted code calling into
    -- theirs; born under a hidden frame that answers those three questions
    -- with nil, OnLoad never learns the guild window exists. The page moves to
    -- the window only after rule 4 has replaced every script it came with.
    local holder = CreateFrame("Frame")
    holder:Hide()
    holder.GetSelectedClubId   = function() return nil end
    holder.GetSelectedClubInfo = function() return nil end
    holder.GetSelectedStreamId = function() return nil end
    local page = CreateFrame("Frame", "LibGuildRosterGuildTabPage", holder,
        "CommunitiesMemberListFrameTemplate")
    if type(page.ScrollBox) ~= "table" or type(page.RefreshListDisplay) ~= "function" then
        -- A client whose member-list template is not what this was written
        -- against. Better no tab than a blank one.
        tab:Hide()
        rec.failed = true
        return false
    end
    -- RULE 4, and it comes before the page can show or hide ANYWHERE: every
    -- script the template gave us reaches into CommunitiesFrame, OnHide
    -- included (it unregisters callbacks on it, :690-696).
    page:SetScript("OnShow", function() lib:RefreshGuildTab() end)
    page:SetScript("OnHide", nil)
    page:SetScript("OnUpdate", nil)
    page:SetScript("OnEvent", function() lib:RefreshGuildTab() end)
    page:Hide()
    page:SetParent(frame)
    for _, event in ipairs({ "GUILD_ROSTER_UPDATE", "CLUB_MEMBERS_UPDATED",
                             "CLUB_MEMBER_UPDATED", "CLUB_MEMBER_PRESENCE_UPDATED" }) do
        page:RegisterEvent(event)
    end

    page.expandedDisplay = true
    page.invitations     = {}
    page.professionDisplay = {}
    installPageOverrides(page, (C_Club and C_Club.GetGuildClubId and C_Club.GetGuildClubId()) or 0)

    -- Over Blizzard's content area, at the same inset their roster uses
    -- (CommunitiesFrame.xml:458-462, CommunitiesMemberList.lua:587). Their
    -- own list stays shown underneath because hiding it would run their
    -- OnHide tainted; the background below is what covers it.
    page:ClearAllPoints()
    page:SetPoint("TOPLEFT", frame.CommunitiesList or frame, "TOPRIGHT", 26, -60)
    page:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -26, 28)
    -- Layered above Blizzard's list -- measured, not a constant; see
    -- LiftGuildTabPage, which also runs on every show.
    rec.page = page
    self:LiftGuildTabPage(frame, page)
    -- The watermark is the chat sidebar's, and Blizzard hides it on the full
    -- roster (SetExpandedDisplay, :555-558); the template's OnLoad showed it
    -- because it ran in the collapsed mode.
    if page.WatermarkFrame then page.WatermarkFrame:Hide() end
    -- The "N/M Online" count is KEPT, but moved. Its template anchor sits
    -- just above the page's top-left, where it landed on the Lvl / Class
    -- headers; the user, 2026-09-18: "move the online counter to the top
    -- right like it is in the tab where the counters are". Right edge,
    -- centred in the same band as the search box.
    if page.MemberCount then
        page.MemberCount:ClearAllPoints()
        page.MemberCount:SetPoint("RIGHT", page, "TOPRIGHT", -self.GUILD_TAB_COUNT_INSET, self.GUILD_TAB_SEARCH_Y)
        page.MemberCount:Show()
    end
    -- EXACTLY what Blizzard's own roster page draws, from the template's own
    -- numbers (CommunitiesMemberList.xml), as TWO pieces -- one rectangle was
    -- wrong twice. The first cut guessed -6/+64/+26/-6 and spilled over the
    -- title bar and the bottom button row ("too big ... their exact
    -- settings"); the second ran the header's +22 all the way down, which put
    -- a strip right of the scrollbar where Blizzard shows the window's stone
    -- (the user, 2026-09-18: "you're extending the border on the right side
    -- too much"). Drawn at the bottom of the BACKGROUND layer so our own
    -- template's textures stay on top.
    --   * The header band: the ColumnDisplay's rectangle, -3..+22 across and
    --     up to +60 (:296-300), in its rock.
    --   * The list: the InsetFrame's rectangle, -3,+3 to 0,-2 (:353-357), in
    --     the marble of the window's inset behind Blizzard's rows.
    -- Right of the list, our own scrollbar carries its own background, and
    -- beside it the window's stone shows through as it does on theirs.
    local band = page:CreateTexture(nil, "BACKGROUND", nil, -8)
    band:SetTexture("Interface\\FrameGeneral\\UI-Background-Rock", "REPEAT", "REPEAT")
    band:SetHorizTile(true)
    band:SetVertTile(true)
    band:SetPoint("TOPLEFT", page, "TOPLEFT", -3, 60)
    band:SetPoint("BOTTOMRIGHT", page, "TOPRIGHT", 22, 0)
    local body = page:CreateTexture(nil, "BACKGROUND", nil, -8)
    body:SetTexture("Interface\\FrameGeneral\\UI-Background-Marble", "REPEAT", "REPEAT")
    body:SetHorizTile(true)
    body:SetVertTile(true)
    body:SetPoint("TOPLEFT", page, "TOPLEFT", -3, 3)
    body:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", 0, -2)
    -- One more patch, over the Chat page's input box. Left shown under us when
    -- our tab is opened from Chat, it sits 4 below the chat pane, which ends
    -- 28 above the list's bottom (CommunitiesFrame.lua:1609, :1614) -- so it
    -- hangs BELOW the list, over the window's own stone.
    --
    -- THE WINDOW'S OWN TEXTURE, LINED UP WITH THE WINDOW'S OWN. The first
    -- patch was the list's marble cut to the box's rectangle: the wrong colour
    -- against the stone around it, and the box's corner diamonds overhung it
    -- (the user: "not only did it not entirely cover the corners, but it's the
    -- wrong color ... replace this background with the exact same background
    -- up to the button"). So: the window's `Bg` texture (UI-Background-Rock,
    -- PortraitFrameTemplateNoCloseButton, SharedUIPanelTemplates.xml:444) is
    -- redrawn over its OWN full rectangle -- read from their `Bg`, so the
    -- tiles fall exactly where theirs do -- inside a frame that CLIPS it to
    -- the strip: from just under our list down to the bottom of their Bg, and
    -- across the box plus its diamonds. The box ends well left of Invite
    -- Member, so the button is untouched. Anchoring to their frames only
    -- reads them.
    local box = frame.ChatEditBox
    if type(box) == "table" and type(frame.Bg) == "table" then
        local m = self.GUILD_TAB_FOOT_MARGIN
        local clip = CreateFrame("Frame", nil, page)
        clip:SetClipsChildren(true)
        -- From UNDER the window inset's own bottom border piece, not from the
        -- inset's bottom: that piece hangs 1 below the inset's rect
        -- (Classic/NineSliceLayouts.lua:148-151), and a strip starting at the
        -- rect shaved its lowest row off, so the line read thinner than the
        -- game's beside the list's corner (the user, 2026-09-18, two crops:
        -- "we just need that bottom border in the first pic to match the
        -- 2nd"). Nothing of ours touches the inset's borders.
        local nine = type(frame.Inset) == "table" and type(frame.Inset.NineSlice) == "table"
            and frame.Inset.NineSlice or nil
        if nine and type(nine.BottomEdge) == "table" then
            clip:SetPoint("TOP", nine.BottomEdge, "BOTTOM", 0, 0)
        else
            clip:SetPoint("TOP", page, "BOTTOM", 0, -2)
        end
        -- Down to the TOP of the window's bottom border, not the bottom of its
        -- Bg: the border is drawn over the Bg's lowest pixels, and stopping at
        -- the Bg's bottom painted over it (the user, 2026-09-18: "a little
        -- too far down, as it's overlapping the bottom border"). The border
        -- is PortraitFrameTemplate's `BottomBorder`
        -- (SharedUIPanelTemplates.lua:688); without it, the Bg's bottom.
        if type(frame.BottomBorder) == "table" then
            clip:SetPoint("BOTTOM", frame.BottomBorder, "TOP", 0, 0)
        else
            clip:SetPoint("BOTTOM", frame.Bg, "BOTTOM", 0, 0)
        end
        clip:SetPoint("LEFT", box, "LEFT", -m, 0)
        clip:SetPoint("RIGHT", box, "RIGHT", m, 0)
        local fill = CreateFrame("Frame", nil, clip)
        fill:SetAllPoints(frame.Bg)
        local stone = fill:CreateTexture(nil, "BACKGROUND")
        stone:SetTexture("Interface\\FrameGeneral\\UI-Background-Rock", "REPEAT", "REPEAT")
        stone:SetHorizTile(true)
        stone:SetVertTile(true)
        stone:SetAllPoints(fill)
        rec.foot, rec.footFill, rec.footStone = clip, fill, stone
    end
    -- THE SLIDER COLUMN, REDRAWN WHOLE. The column between Blizzard's
    -- communities list and our list holds their list's scrollbar
    -- (CommunitiesList.xml:166-170: TOPLEFT at the list's TOPRIGHT +6,-45,
    -- BOTTOMLEFT at its BOTTOMRIGHT +6,+2) over the window inset's marble,
    -- and the Chat page's input box hangs its left corner art into it (see
    -- the patch above). Rather than patch round the art, the whole column is
    -- drawn again on our page (the user, 2026-09-18: "we need to fully
    -- redraw over this slider to fix our issue, just do that"): the window
    -- INSET's marble, over the inset's own Bg rectangle so the tiles line
    -- up, clipped to the column and to the inset's own height, and on it a
    -- MinimalScrollBar of OUR OWN at exactly
    -- their bar's anchors that MIRRORS theirs -- extent, allowed, position,
    -- shown -- from a post-hook on their bar's Update (rule 3). It takes no
    -- mouse, and nor does the column: a click there falls through to their
    -- real bar underneath, which scrolls their list as it always did, and the
    -- hook redraws ours. So nothing of theirs is written, and the column
    -- looks and works as before. The column stops at our list's edge, where
    -- our own InsetFrame's border -- the same InsetFrameTemplate edge the
    -- game's Roster tab has beside this column -- draws above it, being a
    -- child frame the lift keeps higher. (A second copy of that border,
    -- drawn over everything, was tried and doubled the edge; the user,
    -- 2026-09-18: "the wrong background, the edge borders, we need them to
    -- match".)
    --
    -- WHICH TEXTURE: the inset's marble. The window's lighter stone was
    -- tried twice off screenshots and both times the user sent it back
    -- ("you regressed to this"; the marble build "was much closer"). AND
    -- ONLY BETWEEN THE INSET'S OWN BORDERS: the column is drawn above the
    -- window's inset, so a column running the inset's full height painted
    -- out the inset's top and bottom border lines where they cross it, and
    -- a copy of each tile drawn back on the column was still wrong (the
    -- user, 2026-09-18, with crops of both: "see how you covered up the
    -- natural top borders of the scrollbar, you shouldn't", the same for
    -- the bottom, and of the copy: "a strip you added in there? it
    -- shouldn't"). So the column starts under the inset's own top edge
    -- piece and ends above its bottom edge piece -- InsetFrameTemplate's
    -- NineSlice child carries them as `TopEdge` / `BottomEdge`
    -- (SharedUIPanelTemplates.xml:693, NineSlice.lua:40-56) -- and nothing
    -- of ours draws on either line. A client without those pieces gets the
    -- inset's rect.
    local list = frame.CommunitiesList
    local inset = frame.Inset
    if type(list) == "table" and type(inset) == "table" and type(inset.Bg) == "table" then
        local nine = type(inset.NineSlice) == "table" and inset.NineSlice or nil
        local topEdge = nine and type(nine.TopEdge) == "table" and nine.TopEdge or nil
        local bottomEdge = nine and type(nine.BottomEdge) == "table" and nine.BottomEdge or nil
        local column = CreateFrame("Frame", nil, page)
        column:SetClipsChildren(true)
        if topEdge then
            column:SetPoint("TOP", topEdge, "BOTTOM", 0, 0)
        else
            column:SetPoint("TOP", inset, "TOP", 0, 0)
        end
        if bottomEdge then
            column:SetPoint("BOTTOM", bottomEdge, "TOP", 0, 0)
        else
            column:SetPoint("BOTTOM", inset, "BOTTOM", 0, 0)
        end
        column:SetPoint("LEFT", list, "RIGHT", 0, 0)
        column:SetPoint("RIGHT", page, "LEFT", -3, 0)
        local fill = CreateFrame("Frame", nil, column)
        fill:SetAllPoints(inset.Bg)
        local marble = fill:CreateTexture(nil, "BACKGROUND")
        marble:SetTexture("Interface\\FrameGeneral\\UI-Background-Marble", "REPEAT", "REPEAT")
        marble:SetHorizTile(true)
        marble:SetVertTile(true)
        marble:SetAllPoints(fill)
        rec.column, rec.columnFill, rec.columnMarble = column, fill, marble
        local their = list.ScrollBar
        if type(their) == "table" and type(their.Update) == "function"
            and type(their.GetScrollPercentage) == "function" then
            local bar = CreateFrame("EventFrame", nil, column, "MinimalScrollBar")
            bar:SetPoint("TOPLEFT", list, "TOPRIGHT", 6, -45)
            bar:SetPoint("BOTTOMLEFT", list, "BOTTOMRIGHT", 6, 2)
            for _, part in ipairs({ bar, bar.Track, bar.Thumb, bar.Back, bar.Forward }) do
                if type(part) == "table" and part.EnableMouse then part:EnableMouse(false) end
            end
            if bar.EnableMouseWheel then bar:EnableMouseWheel(false) end
            local function mirror()
                bar:SetVisibleExtentPercentage(their:GetVisibleExtentPercentage())
                bar:SetPanExtentPercentage(their:GetPanExtentPercentage())
                bar:SetScrollAllowed(their:IsScrollAllowed())
                bar:SetScrollPercentage(their:GetScrollPercentage(), true)
                bar:SetShown(their:IsShown())
            end
            hooksecurefunc(their, "Update", mirror)
            rec.slider, rec.mirrorSlider = bar, mirror
            mirror()
        end
    end
    -- And the page TAKES the mouse over the roster area. Their list is still
    -- there underneath: without this, a click on empty space below our last
    -- row, or on the header band where their column dropdown sits, lands on
    -- THEIR frame -- the detail panel or the officer menu for a row the
    -- player cannot see. Change the insets and the texture's points together.
    page:EnableMouse(true)
    page:SetHitRectInsets(-3, -22, -60, -2)

    -- Our own view over the template's scroll box, so the initializer is ours
    -- and every acquired row goes through InitGuildTabRow.
    local view = CreateScrollBoxListLinearView()
    view:SetElementInitializer("CommunitiesMemberListEntryTemplate", function(button, elementData)
        lib:InitGuildTabRow(button, elementData)
    end)
    ScrollUtil.InitScrollBoxListWithScrollBar(page.ScrollBox, page.ScrollBar, view)

    if page.ShowOfflineButton then
        page.ShowOfflineButton:Show()
        if page.ShowOfflineButton.SetChecked then
            page.ShowOfflineButton:SetChecked(self:IsGuildTabShowOffline())
        end
    end

    local W = Widgets()
    if W and W.CreateSearchBox then
        rec.search = W:CreateSearchBox(page, {
            width       = self.GUILD_TAB_SEARCH_WIDTH,
            placeholder = "Search name, rank, guild or note",
            onChanged   = function(text)
                rec.query = text
                lib:RefreshGuildTab()
            end,
        })
        -- Right of Show Offline Members, vertically centred in the band
        -- between the title bar and the column headers. At 180 wide the
        -- placeholder wrapped onto a second line, and sitting on the headers
        -- it read as part of them (the user, 2026-09-18: "make the search bar
        -- longer ... we have the space" / "center the text bar between the top
        -- and the bottom area it's in"). The band runs from the column
        -- header's top (page top + 20) to the ColumnDisplay's top (+60).
        rec.search:SetPoint("LEFT", page, "TOPLEFT", self.GUILD_TAB_SEARCH_X, self.GUILD_TAB_SEARCH_Y)
    end

    -- The library's own signals repaint the page -- a sister roster landing,
    -- a sighting, a join or a leave. RefreshGuildTab is a no-op while the page
    -- is hidden, so these cost nothing when nobody is looking. Registered with
    -- the record as the handle, once, because this whole function runs once.
    for _, event in ipairs({ "OnSisterRosterUpdated", "OnRosterUpdated", "OnMemberOnline",
                             "OnMemberOffline", "OnMemberJoined", "OnMemberLeft" }) do
        self.RegisterCallback(rec, event, function() lib:RefreshGuildTab() end)
    end

    -- RULE 3: post-hooks only, none able to taint what it follows.
    --
    -- WHEN BLIZZARD'S PAGE TAKES OVER. A post-hook on SetDisplayMode runs even
    -- when theirs returned early because the mode did not change
    -- (CommunitiesFrame.lua:580-583), so hiding on every call put our page
    -- away the moment anything re-asserted the page it was already on -- our
    -- tab "doesn't switch" from Guild Info (the user, 2026-09-18). So: a click
    -- on any of their tabs always puts ours away (HookScript on each, after
    -- their OnClick), and SetDisplayMode only when the mode really moved from
    -- the one ours was opened over.
    for _, key in ipairs(BLIZZARD_TABS) do
        local their = frame[key]
        if type(their) == "table" and their.HookScript then
            their:HookScript("OnClick", function() lib:HideGuildTab() end)
        end
    end
    hooksecurefunc(frame, "SetDisplayMode", function(_, mode)
        if mode ~= rec.openedOver then lib:HideGuildTab() end
    end)
    -- Blizzard shows the Guild Info tab only while a GUILD is the selected
    -- club and the window is on one of its tabbed pages
    -- (CommunitiesFrame.lua:978-1010). Ours follows it, so a community or the
    -- guild finder never shows a guild tab.
    if type(frame.UpdateCommunitiesTabs) == "function" then
        hooksecurefunc(frame, "UpdateCommunitiesTabs", function() lib:SyncGuildTabVisibility() end)
    end
    -- On every open, decide afresh. Our page is a child of the window, so it
    -- would otherwise come back with whatever shown state it had when the
    -- window closed -- while Blizzard's own OnShow re-checks THEIR tab, and
    -- the two would disagree about which page is up.
    frame:HookScript("OnShow", function() lib:OnGuildWindowShow() end)

    rec.frame, rec.tab, rec.page = frame, tab, page
    self:SyncGuildTabVisibility()
    return true
end

--- Put our page above everything of Blizzard's roster page, MEASURED.
--
-- Twice this was a guess, and twice their list drew through ours in game.
-- "The window + 20" lost to their InsetFrame, pinned at 100 by its OnLoad
-- (CommunitiesMemberList.xml:353-364). An absolute 300 then lost as soon as
-- the guild window raised itself (it is `toplevel`, CommunitiesFrame.xml:304,
-- so opening or clicking it moves its whole tree up): their scrollbar and
-- their list's bottom border showed on top of our rows (the user,
-- 2026-09-18: "you're adding a scroll bar here for some reason" -- it was
-- theirs). And it is not only their ROSTER page: we never switch their
-- display mode (rule 2), so whatever page was up when our tab was clicked
-- stays shown underneath -- from the Chat tab that is the chat pane and its
-- input box, which the XML pins at frame level 1200 (CommunitiesFrame.xml:
-- 498); the user saw the box and the chat scrollbar on our page ("it looks
-- like a holdover from the first tab"). So the page goes above the highest
-- SHOWN frame anywhere in the window's tree as it stands NOW, and this runs
-- again every time the page is shown. Reading their levels changes nothing
-- of theirs. Our own tab and page are skipped; a hidden subtree cannot draw.
-- @param frame table  CommunitiesFrame
-- @param page table   our page
-- @return number  the level the page was given
--
-- AND THE STRATA, not only the level: the page ALWAYS takes HIGH. The chat
-- pane's scrollbar is declared `frameStrata="HIGH"` (CommunitiesChatFrame.xml:
-- 29), and no level in MEDIUM beats a frame in HIGH -- it still drew over our
-- page after the level lift (the user, 2026-09-18: "the scroll bar is still
-- there"). The first cut took HIGH only while something shown was in it,
-- and MEDIUM otherwise -- and MEASURED in game (2026-09-18), opened from the
-- Roster or Guild Info tab our page was shown, MEDIUM, level 531, over a
-- window at level 1 whose member list was at 2, and THEIR page still showed;
-- from Chat, in HIGH, ours showed. Nothing in Blizzard_Communities' XML
-- puts a roster or info frame above MEDIUM, so what was over us there is not
-- established; HIGH is the one strata we can take that leaves the window's
-- DIALOG-strata popups (the stream editor, the notification settings) above
-- us, so that is the answer. The level is still measured: the highest shown
-- frame in the tree at HIGH or below, plus the margin.
function lib:LiftGuildTabPage(frame, page)
    local skip = { [page] = true, [self.guildTab.tab or page] = true }
    local rank = self.GUILD_TAB_STRATA_RANK
    local cap = rank[self.GUILD_TAB_STRATA_CAP]
    local top = frame:GetFrameLevel()
    local function walk(f, depth)
        for _, child in ipairs({ f:GetChildren() }) do
            if not skip[child] and child:IsShown() then
                if (rank[child:GetFrameStrata()] or 0) <= cap then
                    top = math.max(top, child:GetFrameLevel())
                end
                if depth < self.GUILD_TAB_LEVEL_DEPTH then walk(child, depth + 1) end
            end
        end
    end
    walk(frame, 1)
    local level = top + self.GUILD_TAB_LEVEL_MARGIN
    page:SetFrameStrata(self.GUILD_TAB_STRATA_CAP)
    page:SetFrameLevel(level)
    -- Our template's own InsetFrame (the border) was pinned by its OnLoad
    -- too; it belongs above our rows, as theirs is above theirs, and above
    -- every patch of ours.
    if page.InsetFrame then page.InsetFrame:SetFrameLevel(level + self.GUILD_TAB_LEVEL_MARGIN) end
    return level
end

--- The guild window opened: our page if the player asked for it, Blizzard's
-- otherwise.
-- @return boolean  whether our page is the one showing
function lib:OnGuildWindowShow()
    if self:IsGuildTabDefault() and self:ShowGuildTab() then return true end
    self:HideGuildTab()
    return false
end

--- Show or hide our tab to match Blizzard's Guild Info tab, and take our page
-- down with it when it goes.
-- @return boolean  whether our tab is shown
function lib:SyncGuildTabVisibility()
    local rec = self.guildTab
    if not rec.tab then return false end
    local info = rec.frame.GuildInfoTab
    local show = self:IsGuildTabEnabled() and info:IsShown() == true
    -- Re-placed on every pass: an addon's button under Guild Info can be
    -- created after ours, or shown and hidden with its own settings.
    rec.tab:ClearAllPoints()
    rec.tab:SetPoint("CENTER", self:FindGuildTabAnchor(rec.frame, rec.tab), "CENTER", 0, -self.GUILD_TAB_PITCH)
    rec.tab:SetShown(show)
    if not show then self:HideGuildTab() end
    return show
end

--- Show our page and check our tab. Unchecks Blizzard's four so only one tab
-- reads as active; see the header for why that widget call is safe.
-- @return boolean  whether the page was shown
function lib:ShowGuildTab()
    local rec = self.guildTab
    if not rec.page or not self:IsGuildTabEnabled() then return false end
    -- No guild selected (a community, the finder): there is no guild to show.
    if rec.frame.GuildInfoTab:IsShown() ~= true then return false end
    -- DO NOT SWITCH BLIZZARD'S PAGE HERE. It was tried on 2026-09-18 at the
    -- user's suggestion -- SetDisplayMode(ROSTER) before ours showed, so the
    -- Chat page's input box (level 1200) would not be left underneath -- and
    -- MEASURED: `select(2, issecurevariable(CommunitiesFrame.MemberList,
    -- "sortedMemberList"))` read "GuildRoster". Running their display-mode
    -- switch from our code runs their list's OnShow tainted, which is rule 2
    -- of the header exactly. Whatever page is underneath stays; the measured
    -- lift in LiftGuildTabPage puts ours above it, the chat box included.
    for _, key in ipairs(BLIZZARD_TABS) do
        local tab = rec.frame[key]
        if type(tab) == "table" and tab.SetChecked then tab:SetChecked(false) end
    end
    rec.tab:SetChecked(true)
    -- The page ours sits over; a SetDisplayMode that merely re-asserts it
    -- must not put ours away (see the hook in InstallGuildTab).
    rec.openedOver = rec.frame.GetDisplayMode and rec.frame:GetDisplayMode()
    self:LiftGuildTabPage(rec.frame, rec.page)
    -- The slider replica catches up here too: their bar's Update, which the
    -- hook follows, need not have run since ours was last shown.
    if rec.mirrorSlider then rec.mirrorSlider() end
    rec.page:Show()
    self:RefreshGuildTab()
    return true
end

--- Hide our page and uncheck our tab. Called by the SetDisplayMode post-hook,
-- so clicking any tab of Blizzard's puts their own page back.
-- @return boolean  whether the page had been shown
function lib:HideGuildTab()
    local rec = self.guildTab
    if not rec.page then return false end
    local was = rec.page:IsShown() == true
    rec.tab:SetChecked(false)
    rec.page:Hide()
    return was
end

--- Repaint the page from the library. Sends nothing, queries nothing of
-- Blizzard's beyond the guild club's own members, and is a no-op while the
-- page is not built or not shown -- so every callback can just call it.
-- @return boolean  whether anything was painted
function lib:RefreshGuildTab()
    local rec = self.guildTab
    local page = rec.page
    -- IsVisible, not IsShown: the page keeps its own shown flag while the
    -- guild window around it is closed, and nobody is looking then.
    if not (page and page:IsVisible()) then return false end
    local rows = self:BuildGuildTabRows({
        includeOffline = self:IsGuildTabShowOffline(),
        query          = rec.query,
        sortKey        = rec.sortKey,
        reverse        = rec.reverse,
    })
    local lookup, ids = {}, {}
    for i, row in ipairs(rows) do
        if row.memberId == nil then row.memberId = i end
        lookup[row.memberId] = row
        ids[i] = row.memberId
    end
    -- The fields Blizzard's drawing code reads off the list, all of them ours.
    page.allMemberList      = rows
    page.sortedMemberList   = rows
    page.allMemberInfoLookup = lookup
    page.sortedMemberLookup = lookup
    page.memberIds          = ids
    page.invitations        = {}
    page:UpdateMemberCount()
    page:RefreshLayout()
    page:RefreshListDisplay()
    return true
end

-- ===========================================================================
-- THE CLASSIC GUILD WINDOW: a fifth tab across the bottom of the Friends frame
-- ===========================================================================
--
-- Classic Era's OTHER guild window. Behind the "Use Classic Guild UI" checkbox
-- (`useClassicGuildUI`) the guild is a tab of the old Friends frame --
-- Friends / Who / Guild / Raid across the bottom -- and a player on it saw
-- nothing of the tab above. The user, 2026-09-18: "on the classic UI, there is
-- nothing, can we add a tab to that like we did the new UI?" and, of the
-- three shapes offered, "do 1": a fifth bottom tab of our own.
--
-- THE SAME FOUR RULES AS THE COMMUNITIES TAB, and the same trade:
--   * Our tab is built from their `FriendsFrameTabTemplate`, so it is drawn
--     by their art, but it is NOT registered with PanelTemplates: that would
--     mean writing `FriendsFrame.numTabs` (a Blizzard table), and their
--     UpdateTabs walks `FriendsFrameTab<i>` by global name, which ours is
--     not. Ours is a lookalike we select and deselect ourselves with the
--     same PanelTemplates_SelectTab / DeselectTab their code uses -- widget
--     calls on our button, and on theirs to un-press the one they left
--     pressed, the way the Communities tab unchecks theirs. Nothing of
--     theirs is written; their `selectedTab` stays where they put it.
--   * Our page covers the whole content area (their Bg's rectangle, under
--     the title bar, down to the top of the bottom border) with the window's
--     own stone, so whichever of their pages was up stays shown underneath
--     and out of sight. Never Show/Hide a page of theirs.
--   * Post-hooks only: HookScript OnClick on their four tabs puts ours away;
--     OnShow of the window decides afresh; their
--     FriendsFrame_UpdateGuildTabVisibility and InGuildCheck are followed
--     so ours shows exactly when their Guild tab does.
--   * The page is laid out from the Guild page's own XML
--     (Blizzard_UIPanels_Game/Classic/FriendsFrame.xml:1671-2392 and
--     GuildStatus_Update, FriendsFrame.lua:2894-3118), with their templates:
--     the "Show Offline Members" box, four GuildFrameColumnHeaderTemplate
--     headers (Name 83, Zone 120 / 105 with a scrollbar, Lvl 32, Class 92),
--     thirteen FriendsFrameGuildPlayerStatusButtonTemplate rows from
--     (3,-82), a FauxScrollFrameTemplate 296x237 at (-32,-87) with the
--     scrollbar art, the totals line at LEFT (13,-98), the horizontal bar at
--     BOTTOM +89 -- and, where their page has the MOTD, our search box.
--     Rows carry the same data as the Communities tab (BuildGuildTabRows);
--     a sister member's guild is in the Zone column, having no zone.
--
-- Officer actions stay on their Guild tab, as on the Communities window.
-- The one setting is shared: `guildTab` governs both windows, `guildTabDefault`
-- opens ours when the window opens ON their Guild tab, `guildTabOffline` is
-- our Show Offline box.
--
-- Ships in 0.9.0 with the Communities tab, at the same MINOR (22). It was
-- offered as "its own release after 0.9.0" and chosen so, then built and seen
-- working in game the same day 0.9.0 was being prepared; the user that
-- evening: "they are both working, lets prep for a release". One release,
-- one increment. See the CHANGELOG for what was and was not checked.
-- ===========================================================================

lib.classicTab = lib.classicTab or {}

lib.CLASSIC_TAB_TEXT       = "Sisters"
-- GUILDMEMBERS_TO_DISPLAY and FRIENDS_FRAME_GUILD_HEIGHT (FriendsFrame.lua:12-13).
lib.CLASSIC_TAB_ROWS       = 13
lib.CLASSIC_TAB_ROW_HEIGHT = 14
-- The four headers: text, the row attribute the column sorts on, the width
-- without and with a scrollbar (FriendsFrame.xml:1849-1894, .lua:3107-3111).
lib.CLASSIC_TAB_COLUMNS = {
    { text = "NAME",       sort = "name",    width = 83,  narrow = 83 },
    { text = "ZONE",       sort = "zone",    width = 120, narrow = 105 },
    { text = "LEVEL_ABBR", sort = "level",   width = 32,  narrow = 32 },
    { text = "CLASS",      sort = "classID", width = 92,  narrow = 92 },
}
-- Where the search box goes: the MOTD label's spot (FriendsFrame.xml:1705).
lib.CLASSIC_TAB_SEARCH_X, lib.CLASSIC_TAB_SEARCH_Y, lib.CLASSIC_TAB_SEARCH_WIDTH = 11, -329, 316

-- A global string of theirs, or ours when the client lacks it.
local function blizzText(key, fallback)
    local v = rawget(_G, key)
    return type(v) == "string" and v or fallback
end

-- classID to the localised class name a classic row shows ("Warrior"),
-- through C_CreatureInfo like classIdFor; "" for an unknown id.
local classNameById
local function classNameFor(classID)
    if type(classID) ~= "number" then return "" end
    if not classNameById then
        classNameById = {}
        local api = C_CreatureInfo and C_CreatureInfo.GetClassInfo
        if api then
            for id = 1, lib.ROSTER_CLASS_ID_MAX do
                local info = api(id)
                if type(info) == "table" and info.className then
                    classNameById[info.classID or id] = info.className
                end
            end
        end
    end
    return classNameById[classID] or ""
end

-- The named regions Blizzard's row template creates as `$parentName` and
-- friends (FriendsFrame.xml:414-461): globals, the way GuildStatus_Update
-- reaches them.
local function rowRegion(button, suffix)
    return rawget(_G, button:GetName() .. suffix)
end

--- Paint one classic row from a row table, the way GuildStatus_Update paints
-- theirs (FriendsFrame.lua:3058-3089): gold name and white columns online,
-- all grey offline; the Zone column narrower when the scrollbar is up.
-- @param button table  one of our thirteen row buttons
-- @param row table  a BuildGuildTabRows row
-- @param scrollBar boolean  whether the list has more rows than fit
function lib:PaintClassicRow(button, row, scrollBar)
    local nameFs, zoneFs = rowRegion(button, "Name"), rowRegion(button, "Zone")
    local levelFs, classFs = rowRegion(button, "Level"), rowRegion(button, "Class")
    nameFs:SetText(row.name or row.charKey)
    -- A sister member has no zone we can know; their guild is what tells
    -- them apart, as the Rank column does on the Communities tab.
    zoneFs:SetText(row.isSister and (row.sisterGuild or "") or (row.zone or ""))
    levelFs:SetText(row.level and tostring(row.level) or "")
    classFs:SetText(classNameFor(row.classID))
    if row.online then
        nameFs:SetTextColor(1.0, 0.82, 0.0)
        zoneFs:SetTextColor(1.0, 1.0, 1.0)
        levelFs:SetTextColor(1.0, 1.0, 1.0)
        classFs:SetTextColor(1.0, 1.0, 1.0)
    else
        nameFs:SetTextColor(0.5, 0.5, 0.5)
        zoneFs:SetTextColor(0.5, 0.5, 0.5)
        levelFs:SetTextColor(0.5, 0.5, 0.5)
        classFs:SetTextColor(0.5, 0.5, 0.5)
    end
    zoneFs:SetWidth(scrollBar and 95 or 110)
    classFs:SetWidth(scrollBar and 80 or 87)
end

--- Repaint the classic page from the library. A no-op while it is not built
-- or not visible, so every callback can call it.
-- @return boolean  whether anything was painted
function lib:RefreshClassicGuildTab()
    local rec = self.classicTab
    local page = rec.page
    if not (page and page:IsVisible()) then return false end
    -- The setting is shared with the Communities page and the slash
    -- command; the box here follows it rather than only driving it.
    rec.offlineCheck:SetChecked(self:IsGuildTabShowOffline())
    local rows = self:BuildGuildTabRows({
        includeOffline = self:IsGuildTabShowOffline(),
        query          = rec.query,
        sortKey        = rec.sortKey,
        reverse        = rec.reverse,
    })
    rec.rows = rows
    local total, online = #rows, 0
    for _, row in ipairs(rows) do
        if row.online then online = online + 1 end
    end
    local n = self.CLASSIC_TAB_ROWS
    local scrollBar = total > n
    local offset = FauxScrollFrame_GetOffset(rec.scroll)
    for i = 1, n do
        local button = rec.buttons[i]
        local row = rows[offset + i]
        button.memberInfo = row
        if row then
            self:PaintClassicRow(button, row, scrollBar)
            button:Show()
        else
            button:Hide()
        end
    end
    -- The Zone header narrows with the rows when the scrollbar is up
    -- (FriendsFrame.lua:3107-3111).
    local zone = self.CLASSIC_TAB_COLUMNS[2]
    local setWidth = rawget(_G, "WhoFrameColumn_SetWidth")
    if type(setWidth) == "function" then
        setWidth(rec.headers[2], scrollBar and zone.narrow or zone.width)
    end
    rec.totals:SetText(string.format("%d Members", total))
    rec.onlineTotals:SetText(string.format(blizzText("GUILD_TOTALONLINE", "(%d Online)"), online))
    FauxScrollFrame_Update(rec.scroll, total, n, self.CLASSIC_TAB_ROW_HEIGHT)
    return true
end

--- Press our tab and un-press whichever of theirs is pressed -- a widget
-- call on their button, as SetChecked is on the Communities tabs; their
-- `selectedTab` is not touched. Called on show, and again after their own
-- tab pass (PanelTemplates_UpdateTabs, run by InGuildCheck and every
-- SetTab) has re-pressed theirs under our open page.
function lib:PressClassicTab()
    local rec = self.classicTab
    local deselect = rawget(_G, "PanelTemplates_DeselectTab")
    local select = rawget(_G, "PanelTemplates_SelectTab")
    for i = 1, 4 do
        local their = rawget(_G, "FriendsFrameTab" .. i)
        if type(their) == "table" and their:IsShown() and type(deselect) == "function" then
            deselect(their)
        end
    end
    if type(select) == "function" then select(rec.tab) end
end

--- Show our classic page and press our tab.
-- @return boolean  whether the page was shown
function lib:ShowClassicGuildTab()
    local rec = self.classicTab
    if not rec.page or not self:IsGuildTabEnabled() then return false end
    if rec.tab:IsShown() ~= true then return false end
    self:PressClassicTab()
    -- The tab of theirs ours sits over; a SetTab that merely re-asserts it
    -- (GuildStatus_Update does, on every roster event) must not put ours
    -- away -- see the hook in InstallClassicGuildTab.
    local selected = rawget(_G, "PanelTemplates_GetSelectedTab")
    rec.openedOver = type(selected) == "function" and selected(rec.frame) or nil
    self:LiftGuildTabPage(rec.frame, rec.page)
    rec.page:Show()
    self:RefreshClassicGuildTab()
    return true
end

--- Hide our classic page and release our tab. Their own tab click has
-- already re-pressed theirs by the time this runs after it.
-- @return boolean  whether the page had been shown
function lib:HideClassicGuildTab()
    local rec = self.classicTab
    if not rec.page then return false end
    local was = rec.page:IsShown() == true
    rec.page:Hide()
    local deselect = rawget(_G, "PanelTemplates_DeselectTab")
    if type(deselect) == "function" then deselect(rec.tab) end
    return was
end

--- Show or hide our tab to match their Guild tab -- shown only with the
-- classic guild UI on and the player in a guild
-- (FriendsFrame_UpdateGuildTabVisibility, InGuildCheck) -- and take the
-- page down with it.
-- @return boolean  whether our tab is shown
function lib:SyncClassicTabVisibility()
    local rec = self.classicTab
    if not rec.tab then return false end
    local guildTab = rawget(_G, "FriendsFrameTab" .. (rawget(_G, "FRIEND_TAB_GUILD") or 3))
    local show = self:IsGuildTabEnabled() and type(guildTab) == "table"
        and guildTab:IsShown() == true and IsInGuild() == true
    rec.tab:SetShown(show)
    if not show then
        self:HideClassicGuildTab()
    elseif rec.page:IsShown() then
        -- Their pass re-pressed their tab under our open page.
        self:PressClassicTab()
    end
    return show
end

--- The Friends frame opened: ours if the player asked for it AND the window
-- opened on their Guild tab -- the O key opens it on Friends, and that is not
-- a guild window -- theirs otherwise.
-- @return boolean  whether our page is the one showing
function lib:OnFriendsFrameShow()
    local selected = rawget(_G, "PanelTemplates_GetSelectedTab")
    local onGuild = type(selected) == "function"
        and selected(self.classicTab.frame) == (rawget(_G, "FRIEND_TAB_GUILD") or 3)
    if onGuild and self:IsGuildTabDefault() and self:ShowClassicGuildTab() then return true end
    self:HideClassicGuildTab()
    return false
end

--- A click on one of our column headers: sort on it, reversing on a repeat.
-- @param attribute string  the row attribute the column sorts on
function lib:SortClassicGuildTab(attribute)
    local rec = self.classicTab
    rec.reverse = (attribute == rec.sortKey) and not rec.reverse or false
    rec.sortKey = attribute
    self:RefreshClassicGuildTab()
end

--- Build the fifth tab and its page on the Friends frame, once. False, and
-- nothing half-built, on a client without that window or its templates.
-- @return boolean  whether the tab is in place
function lib:InstallClassicGuildTab()
    local rec = self.classicTab
    if rec.page then return true end
    if rec.failed then return false end
    if not self:IsGuildTabEnabled() then return false end
    local frame = rawget(_G, "FriendsFrame")
    local raidTab = rawget(_G, "FriendsFrameTab4")
    if type(frame) ~= "table" or type(raidTab) ~= "table" or type(frame.Bg) ~= "table" then return false end
    if type(rawget(_G, "FauxScrollFrame_Update")) ~= "function"
        or type(rawget(_G, "FauxScrollFrame_GetOffset")) ~= "function"
        or type(rawget(_G, "PanelTemplates_SelectTab")) ~= "function" then
        return false
    end
    -- Everything above exists on RETAIL too (Blizzard_FriendsFrame/Mainline:
    -- the same frame, a Bg, a fourth tab, the same helpers); what retail has
    -- not got is the Classic Guild page's two templates, and the header
    -- CreateFrame threw at login there (WoW Forever, 2026-09-19). Asked of the
    -- client before anything is built, so nothing is left half-built.
    if not hasTemplates("FriendsFrameTabTemplate", "InsetFrameTemplate", "GuildFrameColumnHeaderTemplate",
                        "FriendsFrameGuildPlayerStatusButtonTemplate", "FauxScrollFrameTemplate") then
        return false
    end

    -- THE TAB, after Raid, at their -14 overlap (FriendsFrame.xml:3993). The
    -- template's OnClick is PanelTemplates_Tab_OnClick on FriendsFrame, which
    -- would write their selectedTab; replaced. Its width is set the way each
    -- of theirs sets its own in OnShow (:3947-3950).
    local tab = CreateFrame("Button", "LibGuildRosterClassicTab", frame, "FriendsFrameTabTemplate")
    tab:SetText(self.CLASSIC_TAB_TEXT)
    tab:SetPoint("LEFT", raidTab, "RIGHT", -14, 0)
    tab:SetScript("OnClick", function() lib:ShowClassicGuildTab() end)
    tab:SetScript("OnShow", function(t)
        local resize = rawget(_G, "PanelTemplates_TabResize")
        if type(resize) == "function" then
            t:SetWidth(0)
            resize(t, 0, nil)
        end
    end)

    -- THE PAGE: their Bg's rectangle (2,-21 to -2,2, PortraitFrameTemplate-
    -- NoCloseButton, SharedUIPanelTemplates.xml:444-448), stopping at the top
    -- of their bottom border so the border is not painted over, in the
    -- window's own stone from the same origin so the tiles line up.
    local page = CreateFrame("Frame", "LibGuildRosterClassicPage", frame)
    page:SetPoint("TOPLEFT", frame, "TOPLEFT", 2, -21)
    page:SetPoint("RIGHT", frame, "RIGHT", -2, 0)
    if type(frame.BottomBorder) == "table" then
        page:SetPoint("BOTTOM", frame.BottomBorder, "TOP", 0, 0)
    else
        page:SetPoint("BOTTOM", frame, "BOTTOM", 0, 2)
    end
    page:Hide()
    page:EnableMouse(true)
    local stone = page:CreateTexture(nil, "BACKGROUND", nil, -8)
    stone:SetTexture("Interface\\FrameGeneral\\UI-Background-Rock", "REPEAT", "REPEAT")
    stone:SetHorizTile(true)
    stone:SetVertTile(true)
    stone:SetAllPoints(page)
    -- Their inset, where their Guild tab puts it (FriendsFrame_Update,
    -- FriendsFrame.lua:482, on ButtonFrameTemplate's 4/-6/26): one of ours
    -- from the same template, marble and border, at the page's own level so
    -- the rows built after it draw above it.
    local inset = CreateFrame("Frame", nil, page, "InsetFrameTemplate")
    inset:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -80)
    inset:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -6, 26)
    inset:SetFrameLevel(page:GetFrameLevel())
    rec.inset = inset

    -- "Show Offline Members": their LFG frame's three-piece border and check
    -- box (FriendsFrame.xml:1741-1828), on our own setting.
    local offline = CreateFrame("Frame", nil, page)
    offline:SetSize(210, 23)
    offline:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, -25)
    local right = offline:CreateTexture(nil, "BACKGROUND")
    right:SetTexture("Interface\\ClassTrainerFrame\\UI-ClassTrainer-FilterBorder")
    right:SetSize(12, 28)
    right:SetPoint("TOPRIGHT", offline, "TOPRIGHT", 0, 0)
    right:SetTexCoord(0.90625, 1.0, 0, 1.0)
    local middle = offline:CreateTexture(nil, "BACKGROUND")
    middle:SetTexture("Interface\\ClassTrainerFrame\\UI-ClassTrainer-FilterBorder")
    middle:SetSize(186, 28)
    middle:SetPoint("RIGHT", right, "LEFT", 0, 0)
    middle:SetTexCoord(0.09375, 0.90625, 0, 1.0)
    local left = offline:CreateTexture(nil, "BACKGROUND")
    left:SetTexture("Interface\\ClassTrainerFrame\\UI-ClassTrainer-FilterBorder")
    left:SetSize(12, 28)
    left:SetPoint("RIGHT", middle, "LEFT", 0, 0)
    left:SetTexCoord(0, 0.09375, 0, 1.0)
    local check = CreateFrame("CheckButton", nil, offline)
    check:SetSize(20, 20)
    check:SetPoint("RIGHT", offline, "RIGHT", -8, 0)
    check:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
    check:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
    check:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
    check:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
    check:SetChecked(self:IsGuildTabShowOffline())
    check:SetScript("OnClick", function(box)
        lib:SetGuildTabShowOffline(box:GetChecked() and true or false)
        lib:RefreshClassicGuildTab()
    end)
    local checkText = offline:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    checkText:SetText(blizzText("SHOW_OFFLINE_MEMBERS", "Show Offline Members"))
    checkText:SetPoint("RIGHT", check, "LEFT", -10, 1)
    rec.offlineBox, rec.offlineCheck = offline, check

    -- The four column headers, from their template, sorting ours.
    rec.headers = {}
    local prev
    local setWidth = rawget(_G, "WhoFrameColumn_SetWidth")
    for i, col in ipairs(self.CLASSIC_TAB_COLUMNS) do
        local header = CreateFrame("Button", "LibGuildRosterClassicHeader" .. i, page, "GuildFrameColumnHeaderTemplate")
        header:SetText(blizzText(col.text, col.text))
        if i == 1 then
            header:SetPoint("TOPLEFT", frame, "TOPLEFT", 7, -57)
        else
            header:SetPoint("LEFT", prev, "RIGHT", -2, 0)
        end
        if type(setWidth) == "function" then setWidth(header, col.width) else header:SetWidth(col.width) end
        header:SetScript("OnClick", function() lib:SortClassicGuildTab(col.sort) end)
        rec.headers[i] = header
        prev = header
    end

    -- Thirteen rows from their template, chained down from (3,-82); every
    -- script theirs came with reaches GetGuildRosterInfo, so all are ours.
    rec.buttons = {}
    for i = 1, self.CLASSIC_TAB_ROWS do
        local button = CreateFrame("Button", "LibGuildRosterClassicRow" .. i, page,
            "FriendsFrameGuildPlayerStatusButtonTemplate")
        if i == 1 then
            button:SetPoint("TOPLEFT", frame, "TOPLEFT", 3, -82)
        else
            button:SetPoint("TOPLEFT", rec.buttons[i - 1], "BOTTOMLEFT", 0, 0)
        end
        button:SetScript("OnClick", function(b, mouse) lib:OnGuildTabRowClick(b, mouse) end)
        button:SetScript("OnEnter", nil)
        button:SetScript("OnLeave", nil)
        button:Hide()
        rec.buttons[i] = button
    end

    -- Their list's scroll frame and its art (FriendsFrame.xml:2346-2392).
    local scroll = CreateFrame("ScrollFrame", "LibGuildRosterClassicScroll", page, "FauxScrollFrameTemplate")
    scroll:SetSize(296, 237)
    scroll:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -32, -87)
    scroll:SetScript("OnVerticalScroll", function(s, offset)
        FauxScrollFrame_OnVerticalScroll(s, offset, lib.CLASSIC_TAB_ROW_HEIGHT, function()
            lib:RefreshClassicGuildTab()
        end)
    end)
    local barTop = scroll:CreateTexture(nil, "BACKGROUND")
    barTop:SetTexture("Interface\\PaperDollInfoFrame\\UI-Character-ScrollBar")
    barTop:SetSize(31, 226)
    barTop:SetPoint("TOPLEFT", scroll, "TOPRIGHT", -2, 5)
    barTop:SetTexCoord(0, 0.484375, 0, 0.8828125)
    local barBottom = scroll:CreateTexture(nil, "BACKGROUND")
    barBottom:SetTexture("Interface\\PaperDollInfoFrame\\UI-Character-ScrollBar")
    barBottom:SetSize(31, 106)
    barBottom:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", -2, -2)
    barBottom:SetTexCoord(0.515625, 1.0, 0, 0.4140625)
    rec.scroll = scroll

    -- The totals line (FriendsFrame.xml:1674-1697) and the bar under the
    -- list (:1722-1737).
    rec.totals = page:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    rec.totals:SetJustifyH("LEFT")
    rec.totals:SetHeight(16)
    rec.totals:SetPoint("LEFT", frame, "LEFT", 13, -98)
    rec.onlineTotals = page:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    rec.onlineTotals:SetJustifyH("LEFT")
    rec.onlineTotals:SetHeight(16)
    rec.onlineTotals:SetPoint("LEFT", rec.totals, "RIGHT", 3, 0)
    local barLeft = page:CreateTexture(nil, "ARTWORK")
    barLeft:SetTexture("Interface\\ClassTrainerFrame\\UI-ClassTrainer-HorizontalBar")
    barLeft:SetSize(256, 16)
    barLeft:SetPoint("LEFT", frame, "LEFT", 1, 0)
    barLeft:SetPoint("RIGHT", frame, "RIGHT", -75, 0)
    barLeft:SetPoint("BOTTOM", frame, "BOTTOM", 0, 89)
    barLeft:SetTexCoord(0, 1.0, 0, 0.25)
    local barRight = page:CreateTexture(nil, "ARTWORK")
    barRight:SetTexture("Interface\\ClassTrainerFrame\\UI-ClassTrainer-HorizontalBar")
    barRight:SetSize(70, 16)
    barRight:SetPoint("LEFT", barLeft, "RIGHT", 0, 0)
    barRight:SetTexCoord(0, 0.29296875, 0.25, 0.5)

    -- The search box, where their page has the MOTD.
    local W = Widgets()
    if W and W.CreateSearchBox then
        rec.search = W:CreateSearchBox(page, {
            width       = self.CLASSIC_TAB_SEARCH_WIDTH,
            placeholder = "Search name, rank, guild or note",
            onChanged   = function(text)
                rec.query = text
                lib:RefreshClassicGuildTab()
            end,
        })
        rec.search:SetPoint("TOPLEFT", frame, "TOPLEFT", self.CLASSIC_TAB_SEARCH_X, self.CLASSIC_TAB_SEARCH_Y)
    end

    for _, event in ipairs({ "OnSisterRosterUpdated", "OnRosterUpdated", "OnMemberOnline",
                             "OnMemberOffline", "OnMemberJoined", "OnMemberLeft" }) do
        self.RegisterCallback(rec, event, function() lib:RefreshClassicGuildTab() end)
    end

    -- Post-hooks only. A click on any of their four tabs puts ours away
    -- (their OnClick has re-pressed theirs by then); the window's OnShow
    -- decides afresh; their two visibility passes are followed. AND THE
    -- KEYBIND PATH: with the window already open, ToggleFriendsFrame(tab)
    -- and OpenFriendsFrame(tab) (FriendsFrame.lua:1210-1229) go through
    -- PanelTemplates_SetTab and a direct FriendsFrame_OnShow() call -- no
    -- tab click, no OnShow script -- so ours would stay over their new page.
    -- A post-hook on SetTab puts ours away when their tab REALLY moved from
    -- the one ours was opened over; a re-assert of the same tab
    -- (GuildStatus_Update's, on every roster event) leaves ours up, which
    -- is the lesson of the Communities tab's SetDisplayMode hook.
    for i = 1, 4 do
        local their = rawget(_G, "FriendsFrameTab" .. i)
        if type(their) == "table" and their.HookScript then
            their:HookScript("OnClick", function() lib:HideClassicGuildTab() end)
        end
    end
    frame:HookScript("OnShow", function() lib:OnFriendsFrameShow() end)
    if type(rawget(_G, "PanelTemplates_SetTab")) == "function" then
        hooksecurefunc("PanelTemplates_SetTab", function(f, id)
            if f == frame and rec.page:IsShown() and id ~= rec.openedOver then
                lib:HideClassicGuildTab()
            end
        end)
    end
    for _, name in ipairs({ "FriendsFrame_UpdateGuildTabVisibility", "InGuildCheck" }) do
        if type(rawget(_G, name)) == "function" then
            hooksecurefunc(name, function() lib:SyncClassicTabVisibility() end)
        end
    end

    rec.frame, rec.tab, rec.page = frame, tab, page
    self:SyncClassicTabVisibility()
    return true
end

-- ---------------------------------------------------------------------------
-- /guildroster -- the standalone addon's only UI
--
-- The library has no settings panel and every consumer would otherwise build
-- the same "sister guilds" box; the user's direction, 2026-09-13, once the
-- sync was seen working in game: "we need a way to configure the 'sister'
-- guild somehow into guild roster. it needs to only be configurable by an
-- officer or GM." The gate is SetSisterGuildNames' own -- lib:IsOfficer(),
-- the officer-note permission, which the guild master always holds -- so the
-- command adds nothing a `/run` could not; it adds the way to type it.
-- Output goes through print(), which lands in the default chat frame.
-- ---------------------------------------------------------------------------

local SLASH_USAGE = {
    "/guildroster sisters                 -- the configured sister guilds and their state",
    "/guildroster sisters add <Guild>     -- officer or GM only",
    "/guildroster sisters remove <Guild>  -- officer or GM only",
    "/guildroster sisters clear           -- officer or GM only",
    "/guildroster pull <Name-Realm>       -- pull a sister roster from one of its online members",
    "/guildroster sync                    -- gossip the list and relay held rosters now",
    "/guildroster mail [on|off]           -- sister-guild names in the mailbox To: box (this account)",
    "/guildroster tab [on|off|default|nodefault] -- our tab on the guild window, and whether J opens on it (this account)",
    "/guildroster diag                    -- what the library holds and where it came from",
}

local SLASH_REASONS = {
    ["not-officer"] = "only an officer or the guild master can change the sister-guild list.",
    ["no-guild"]    = "you are not in a guild.",
}

local function say(fmt, ...)
    print("|cff33ff99LibGuildRoster|r: " .. string.format(fmt, ...))
end

--- One row per configured sister guild, for anything that displays the list:
-- the slash command's listing and the window share this, so they cannot
-- disagree about what "held" means.
-- @return table  array of { name, key, held = guildKey|nil, members, online }
--                sorted by name. `key` is the typed name's key; `held` is the
--                key the roster is actually filed under, which may differ in
--                case (same rule as IsSisterGuildKey). `online` is the names
--                seen within PRESENCE_TTL, sorted.
function lib:GetSisterStatus()
    local faction = (UnitFactionGroup and UnitFactionGroup("player")) or "Neutral"
    local known = self:GetKnownRosters()
    local rows = {}
    for _, name in ipairs(self:GetSisterGuildNames()) do
        local key = faction .. "-" .. name
        local held
        for _, k in ipairs(known) do
            if string.lower(k) == string.lower(key) then held = k end
        end
        local members, online = 0, {}
        if held then
            for _ in pairs(self:GetRoster(held)) do members = members + 1 end
            online = self:GetOnlineMembersScoped(held)
            table.sort(online)
        end
        rows[#rows + 1] = { name = name, key = key, held = held, members = members, online = online }
    end
    return rows
end

-- The status line for one configured guild, for the slash listing.
local function describeSister(row)
    if not row.held then return row.name .. " -- not pulled yet" end
    return string.format("%s -- %d members, %d seen online recently",
        row.name, row.members, #row.online)
end

-- Colour helpers for the diagnostics, kept to the three tints TOGPM's page
-- uses so the two read alike: a section heading, good, bad, and dim.
local function dHead(s) return "|cffffd100" .. s .. "|r" end
local function dGood(s) return "|cff00ff00" .. s .. "|r" end
local function dBad(s)  return "|cffff4040" .. s .. "|r" end
local function dDim(s)  return "|cffaaaaaa" .. s .. "|r" end

local function clock(t)
    if type(t) ~= "number" or t <= 0 then return "?" end
    return date("%H:%M:%S", t)
end

-- What the window shows in its version slot and the diagnostics name: the TOC
-- version when the standalone addon is loaded (`GuildRoster-v0.9.2` on a dev
-- build), the LibStub MINOR when only an embedded copy is present.
local function windowVersionText()
    local getMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    local toc = getMeta and getMeta("GuildRoster", "Version")
    return "LibGuildRoster " .. (toc or ("lib r" .. MINOR))
end

--- The diagnostics block: what the library holds and where it came from, as
-- lines of text. The /gr window shows it under its own heading and
-- `/guildroster diag` prints it, both from here, so they cannot disagree. The
-- user, 2026-09-15, on seeing TOGPM's settings page: "i'm thinking we should
-- have more info in the /gr, like TOGPM does on it's settings page." It
-- answers the questions a bad sync raises in the order they get asked: is the
-- library the copy you think it is, is its own roster complete, is the wire
-- up, what does each roster hold and who fed it, and what survives a reload.
-- @return table  array of strings, colour-coded
function lib:BuildDiagnosticLines()
    local lines = {}
    local homeKey = self:GetHomeGuildKey()

    -- Library ---------------------------------------------------------------
    lines[#lines + 1] = dHead("Library")
    lines[#lines + 1] = string.format("  LibGuildRoster r%d  (%s)", MINOR, windowVersionText())
    local ready = self:IsReady()
    lines[#lines + 1] = "  Home roster: " .. (ready and dGood("ready") or dBad("not ready"))
        .. string.format("  %d members, %d online", #self:GetAllMembers(), #self:GetOnlineMembers())
        .. (self.loginRepairs > 0 and ("  " .. dBad(self.loginRepairs .. " short login build(s) finished")) or "")
    local patterns = (self.chatPatternsBuilt or 0) .. "/" .. self.CHAT_PATTERNS_TOTAL
    lines[#lines + 1] = "  Chat patterns: " .. ((self.chatPatternsBuilt or 0) == self.CHAT_PATTERNS_TOTAL
        and dGood(patterns) or dBad(patterns .. " -- a roster message cannot be parsed on this client"))

    -- Sister sync -------------------------------------------------------------
    lines[#lines + 1] = " "
    lines[#lines + 1] = dHead("Sister sync")
    local db = self:GetSisterDb()
    lines[#lines + 1] = "  Store: " .. (db and dGood("yes") or dBad("no -- not in a guild"))
        .. "   Wire: " .. (self:IsSisterSyncAvailable() and dGood("up") or dBad("down"))
        .. "   AceComm: " .. (self.sisterSync.commRegistered and dGood("registered") or dBad("absent"))
    if db then
        lines[#lines + 1] = string.format("  List: %d guild(s), stamped %s",
            #db.sisterGuilds, db.sisterGuildsTs > 0 and clock(db.sisterGuildsTs) or "never")
    end
    lines[#lines + 1] = "  Mailbox autocomplete: " .. (self:IsMailAutocompleteEnabled() and dGood("on") or dDim("off"))
        .. string.format("  (%d sister name(s) held)", #self:GetSisterRecipients())
    lines[#lines + 1] = "  Guild window tab: " .. (self:IsGuildTabEnabled() and dGood("on") or dDim("off"))
        .. "   Built: " .. (self.guildTab.page and dGood("yes") or dBad("no"))
        .. "   Opens on it: " .. (self:IsGuildTabDefault() and dGood("yes") or dDim("no"))
        .. "   Classic tab built: " .. (self.classicTab.page and dGood("yes") or dBad("no"))
    -- Who VersionCheck has heard running this library: the one thing that says
    -- whether a confederation ask got ANY answer at all, which the event ring
    -- could not show when the answerer was in no copy we hold (2026-09-16).
    local VC = versionCheck()
    if VC then
        local heard = {}
        for name, obs in pairs(VC:GetPeerVersions(VC_HOST)) do
            heard[#heard + 1] = name .. " " .. tostring(type(obs) == "table" and obs.version or obs)
        end
        table.sort(heard)
        local shown = {}
        for i = 1, math.min(#heard, 6) do shown[i] = heard[i] end
        lines[#lines + 1] = string.format("  VersionCheck has heard %d running the library%s", #heard,
            #heard > 0 and (": " .. table.concat(shown, ", ") .. (#heard > 6 and (" (+" .. (#heard - 6) .. ")") or "")) or "")
    else
        lines[#lines + 1] = "  VersionCheck: " .. dBad("not loaded")
    end

    -- Recent sync events, in full: the status bar shows only the last one and
    -- cuts it off. Newest last, so the bottom line is what the bar shows.
    local events = self.sisterSync.events or {}
    if #events > 0 then
        lines[#lines + 1] = " "
        lines[#lines + 1] = dHead("Recent sync events")
        for _, ev in ipairs(events) do
            lines[#lines + 1] = string.format("  %s  %s", dDim(math.floor(GetTime() - ev.at) .. "s ago"), ev.text)
        end
    end

    -- Known rosters -----------------------------------------------------------
    lines[#lines + 1] = " "
    lines[#lines + 1] = dHead("Known rosters")
    local known = self:GetKnownRosters()
    if #known == 0 then
        lines[#lines + 1] = "  " .. dDim("(none yet)")
    end
    for _, key in ipairs(known) do
        local n = 0
        for _ in pairs(self:GetRoster(key)) do n = n + 1 end
        if key == homeKey then
            lines[#lines + 1] = string.format("  %s |cff00ccff(home)|r  --  %d members, %d online",
                key, n, #self:GetOnlineMembers())
        else
            local listed = self:IsSisterGuildKey(key)
            local meta = self.rosterMeta[key]
            local how
            if type(meta) == "table" and meta.provider then
                how = "pulled from " .. tostring(meta.provider) .. " at " .. clock(meta.ts)
            elseif type(meta) == "table" and meta.via then
                how = "relayed by " .. tostring(meta.via)
            else
                how = "fed by a consumer"
            end
            lines[#lines + 1] = string.format("  %s %s  --  %d members, %d seen online, %s",
                key, listed and dHead("(sister)") or dBad("(unlisted)"),
                n, #self:GetOnlineMembersScoped(key), how)
            local pending = self.sisterSync.pendingPull[key]
            local last = self.sisterSync.lastPull[key]
            if pending then
                lines[#lines + 1] = string.format("    pull outstanding to %s (%ds ago)",
                    tostring(pending.peer), math.floor(GetTime() - pending.at))
            elseif last then
                lines[#lines + 1] = string.format("    last automatic pull %ds ago", math.floor(GetTime() - last))
            end
        end
    end
    -- A listed guild we hold nothing for is the state a first-time user is in.
    for _, row in ipairs(self:GetSisterStatus()) do
        if not row.held then
            lines[#lines + 1] = "  " .. row.key .. " " .. dHead("(sister)") .. "  --  " .. dDim("not pulled yet")
        end
    end

    -- Persisted ---------------------------------------------------------------
    if db and next(db.sisterRosters) then
        lines[#lines + 1] = " "
        lines[#lines + 1] = dHead("Persisted sister rosters (survive /reload)")
        local keys = {}
        for key in pairs(db.sisterRosters) do keys[#keys + 1] = key end
        table.sort(keys)
        for _, key in ipairs(keys) do
            local entry = db.sisterRosters[key]
            local n = (type(entry) == "table" and type(entry.members) == "table") and #entry.members or 0
            lines[#lines + 1] = string.format("  %s  --  %d members (fed %s)", key, n,
                clock(type(entry) == "table" and entry.fedAt))
        end
    end
    return lines
end

--- The slash command body. Public so a consumer can route its own command
-- here (`/togpm sisters ...`) and so it can be specced without SlashCmdList.
-- @param msg string  everything after the command word
function lib:HandleSlash(msg)
    local cmd, rest = string.match(tostring(msg or ""), "^%s*(%S*)%s*(.-)%s*$")
    cmd = string.lower(cmd or "")

    if cmd == "sisters" or cmd == "sister" then
        local sub, arg = string.match(rest or "", "^(%S*)%s*(.-)%s*$")
        sub = string.lower(sub or "")
        if sub == "" then
            local rows = self:GetSisterStatus()
            if #rows == 0 then
                say("no sister guilds configured. An officer adds one with /guildroster sisters add <Guild>.")
            else
                for _, row in ipairs(rows) do say("%s", describeSister(row)) end
            end
            say("pull path: %s", self:IsSisterSyncAvailable() and "ready"
                or "unavailable -- not in a guild, or the roster is not ready yet")
            return true
        end

        local ok, reason
        if sub == "add" and arg ~= "" then
            local names = self:GetSisterGuildNames()
            names[#names + 1] = arg
            ok, reason = self:SetSisterGuildNames(names)
        elseif sub == "remove" and arg ~= "" then
            local kept, found = {}, false
            for _, name in ipairs(self:GetSisterGuildNames()) do
                if string.lower(name) == string.lower(arg) then found = true else kept[#kept + 1] = name end
            end
            if not found then
                say("'%s' is not on the list.", arg)
                return false
            end
            ok, reason = self:SetSisterGuildNames(kept)
        elseif sub == "clear" then
            ok, reason = self:SetSisterGuildNames({})
        else
            for _, line in ipairs(SLASH_USAGE) do say("%s", line) end
            return false
        end

        if not ok then
            say("%s", SLASH_REASONS[reason] or tostring(reason))
            return false
        end
        local names = self:GetSisterGuildNames()
        say("sister guilds: %s (gossiped to the guild).", #names > 0 and table.concat(names, ", ") or "none")
        return true
    end

    if cmd == "pull" and rest ~= "" then
        if self:PullSisterRoster(rest) then
            say("asked %s for their guild's roster.", rest)
            return true
        end
        say("cannot pull: %s", self:IsSisterSyncAvailable()
            and "no name given" or "not in a guild, or the roster is not ready yet.")
        return false
    end

    if cmd == "sync" then
        local cfg = self:BroadcastSisterConfig()
        local relayed = self:BroadcastSisterRosters()
        local pulled, skipped = self:RequestSisterRosters(true)
        -- This runs inside the Enter keypress or the button click, which is
        -- the hardware event a /who and the GreenWall ask need: send what is
        -- owed right now.
        self:SendConfederationAsk()
        self:SendQueuedWho()
        say("list %s, %d roster(s) relayed, %d pull(s) issued.",
            cfg and "gossiped" or "not gossiped (nothing configured, or not in a guild)", relayed, pulled)
        -- A guild that was NOT pulled gets a line saying why, because a
        -- silent zero is what sent the user looking for a bug that was not
        -- there: the only pull the library will not make is a blind one.
        for _, row in ipairs(self:GetSisterStatus()) do
            local why = skipped[row.key]
            if why == "no-peer" then
                local stillOwed = self.whoSync.queued[string.lower(row.name)]
                say("%s: nobody seen online recently -- %s.", row.name,
                    stillOwed and "the next click asks the server who is online" or "asked the server who is online")
            elseif why == "pending" then
                say("%s: a pull is already out, waiting for the answer.", row.name)
            end
        end
        return true
    end

    if cmd == "mail" then
        local sub = string.lower(rest or "")
        if sub == "on" or sub == "off" then
            self:SetMailAutocomplete(sub == "on")
        elseif sub ~= "" then
            for _, line in ipairs(SLASH_USAGE) do say("%s", line) end
            return false
        end
        local n = #self:GetSisterRecipients()
        say("mailbox autocomplete of sister-guild names is %s (%d name%s held).",
            self:IsMailAutocompleteEnabled() and "on" or "off", n, n == 1 and "" or "s")
        return true
    end

    if cmd == "tab" then
        local sub = string.lower(rest or "")
        if sub == "on" or sub == "off" then
            self:SetGuildTab(sub == "on")
        elseif sub == "default" or sub == "nodefault" then
            self:SetGuildTabDefault(sub == "default")
        elseif sub ~= "" then
            for _, line in ipairs(SLASH_USAGE) do say("%s", line) end
            return false
        end
        local n = #self:BuildSisterRosterRows(true)
        say("the guild window tab is %s, and the window %s on it (%d sister-guild member%s held).",
            self:IsGuildTabEnabled() and "on" or "off",
            self:IsGuildTabDefault() and "opens" or "does not open",
            n, n == 1 and "" or "s")
        return true
    end

    if cmd == "diag" or cmd == "diagnostics" then
        for _, line in ipairs(self:BuildDiagnosticLines()) do print(line) end
        return true
    end

    if cmd == "" or cmd == "show" or cmd == "window" then
        if self:ToggleSisterWindow() then return true end
        -- No widget library: fall through to the text usage, which still works.
    end

    for _, line in ipairs(SLASH_USAGE) do say("%s", line) end
    return false
end

-- Registered at file scope, so a LibStub upgrade simply re-points the handler
-- at the newest copy. Three spellings; none is taken by the client or by any
-- addon in this install (checked 2026-09-13). `/gr` alone opens the window.
SLASH_LIBGUILDROSTER1 = "/guildroster"
SLASH_LIBGUILDROSTER2 = "/libgr"
SLASH_LIBGUILDROSTER3 = "/gr"
SlashCmdList["LIBGUILDROSTER"] = function(msg) lib:HandleSlash(msg) end

-- ===========================================================================
-- The sister-guild window -- the addon's UI, on LibAceGUIWidgets.
--
-- The user, on seeing the slash commands, 2026-09-13: "i feel like we should
-- have a little UI like what we did with version check. that means we'll
-- need libaceguiwidgets as well." / "then /gr can just open the UI, most
-- folks wont need to get to it, leave the commands as backup." So the shape
-- is VersionCheck-1.0's roster window: a ClearFrame with a RowList in it,
-- built on FIRST OPEN and never before, owning no data of its own -- every
-- row comes from GetSisterStatus and the window repaints on the library's
-- own callbacks. LibAceGUIWidgets is a TOC dependency of the standalone
-- addon; an embedded copy without it falls back to the slash commands.
--
-- The officer gate is not re-implemented here. The add box and the remove
-- icon are simply hidden for anyone lib:IsOfficer() says no to, and the calls
-- behind them refuse regardless, so a member who reaches them anyway is told
-- the same thing the slash command says.
-- ===========================================================================

local WINDOW_HELP = "Sister guilds are allied guilds whose rosters every addon on this client can read.\n\n"
    .. "The list is per guild: an officer or the guild master sets it once and every member "
    .. "receives it.\n\n"
    .. "A guild's roster arrives the first time somebody asks an ONLINE member of it -- type a "
    .. "name in 'Pull from' (with the realm for a member on another realm), or right-click a row "
    .. "once someone has been seen online. From then on it refreshes itself, is saved between "
    .. "sessions, and is relayed to the rest of your guild.\n\n"
    .. "A /who for a sister guild goes out only from your own click -- Sync now, or your next "
    .. "click anywhere while one is owed -- and nobody who has not been seen online is whispered."

local NOT_OFFICER_NOTE = "Only an officer or the guild master can change this list."

--- The rows the window draws, from GetSisterStatus plus the display fields
-- RowList sorts and formats on. Public so the specs can assert on what a user
-- sees without a frame.
-- @return table
function lib:BuildSisterWindowRows()
    local rows = self:GetSisterStatus()
    for _, row in ipairs(rows) do
        row.onlineCount = #row.online
        row.state       = row.held and "held" or "not pulled yet"
        -- RowList's comparator is not stable; `name` is unique, so the state
        -- column sorts on a composite and displays the plain word.
        row.stateSort   = row.state .. "\0" .. row.name
    end
    return rows
end

--- The right-click menu for a row: one "Pull from" entry per member seen
-- online recently (the sighting is what makes the whisper safe), and Remove
-- for an officer. Public for the specs; items with no onClick are
-- informational rows the widget library closes the menu on.
-- @param row table  a GetSisterStatus row
-- @return table  menu items
function lib:SisterRowMenuItems(row)
    local items = {}
    if #row.online == 0 then
        items[#items + 1] = { text = row.held and "Nobody seen online recently -- use 'Pull from'"
            or "Not pulled yet -- type an online member's name in 'Pull from'" }
    else
        for i = 1, math.min(#row.online, 10) do
            local who = row.online[i]
            items[#items + 1] = {
                text    = "Pull from " .. who,
                onClick = function() self:PullSisterRoster(who, row.held) end,
            }
        end
    end
    if self:IsOfficer() then
        items[#items + 1] = {
            text    = "Remove " .. row.name,
            onClick = function() self:HandleSlash("sisters remove " .. row.name) end,
        }
    end
    return items
end

-- The add / pull inputs share one shape: an EditBox that acts on Enter and a
-- button beside it that acts on click, both calling `act(text)`.
local function inputRow(AceGUI, frame, label, buttonText, width, act)
    local box = AceGUI:Create("EditBox")
    box:SetLabel(label)
    box:SetWidth(width)
    box:SetCallback("OnEnterPressed", function(widget, _, text)
        if act(text) then widget:SetText("") end
    end)
    frame:AddChild(box)
    local btn = AceGUI:Create("Button")
    btn:SetText(buttonText)
    btn:SetWidth(90)
    btn:SetCallback("OnClick", function()
        if act(box:GetText()) then box:SetText("") end
    end)
    frame:AddChild(btn)
    return box, btn
end

--- Build the window. Called once, by ToggleSisterWindow, on first open.
-- @param W table  the LibAceGUIWidgets library
-- @return table  the window record { widget, frame, list, addBox, addButton,
--                pullBox, pullButton, note, sync }
function lib:CreateSisterWindow(W)
    local AceGUI = LibStub("AceGUI-3.0")
    local win = {}

    ---@diagnostic disable-next-line: param-type-mismatch
    local frame = AceGUI:Create("ClearFrame")
    frame:SetTitle("Sister guilds")
    frame:SetStatusText(windowVersionText())
    frame:SetInfoTooltip(WINDOW_HELP)
    frame:SetLayout("Flow")
    if frame.SetWidth then frame:SetWidth(560) end
    if frame.SetHeight then frame:SetHeight(620) end
    win.widget = frame
    ---@diagnostic disable-next-line: invisible
    win.frame  = frame.frame

    win.addBox, win.addButton = inputRow(AceGUI, frame, "Add a sister guild", "Add", 300, function(text)
        text = string.gsub(string.gsub(tostring(text or ""), "^%s+", ""), "%s+$", "")
        if text == "" then return false end
        local ok = self:HandleSlash("sisters add " .. text)
        self:RefreshSisterWindow()
        return ok
    end)

    win.note = AceGUI:Create("Label")
    win.note:SetText(NOT_OFFICER_NOTE)
    win.note:SetFullWidth(true)
    frame:AddChild(win.note)

    win.pullBox, win.pullButton = inputRow(AceGUI, frame, "Pull a roster from (Name-Realm, online)", "Pull", 300, function(text)
        text = string.gsub(string.gsub(tostring(text or ""), "^%s+", ""), "%s+$", "")
        if text == "" then return false end
        return self:HandleSlash("pull " .. text)
    end)

    -- The one player preference on the window. Account-wide, so it is not
    -- gated on the officer flag, and RefreshSisterWindow keeps it honest when
    -- the slash command flips it.
    win.mailBox = AceGUI:Create("CheckBox")
    win.mailBox:SetLabel("Offer sister-guild names in the mailbox To: box")
    win.mailBox:SetFullWidth(true)
    win.mailBox:SetCallback("OnValueChanged", function(_, _, value)
        self:SetMailAutocomplete(value and true or false)
    end)
    frame:AddChild(win.mailBox)

    -- The guild-window tab's two preferences (MINOR 22), same rules as the
    -- first: whether the tab exists, and whether J opens the window on it.
    win.tabBox = AceGUI:Create("CheckBox")
    win.tabBox:SetLabel("Add a guild and sister guilds tab to the guild window")
    win.tabBox:SetFullWidth(true)
    win.tabBox:SetCallback("OnValueChanged", function(_, _, value)
        self:SetGuildTab(value and true or false)
    end)
    frame:AddChild(win.tabBox)
    win.tabDefaultBox = AceGUI:Create("CheckBox")
    win.tabDefaultBox:SetLabel("Open the guild window on that tab")
    win.tabDefaultBox:SetFullWidth(true)
    win.tabDefaultBox:SetCallback("OnValueChanged", function(_, _, value)
        self:SetGuildTabDefault(value and true or false)
    end)
    frame:AddChild(win.tabDefaultBox)

    -- The list gets a fixed band (it scrolls on its own -- RowList is a
    -- virtual list) so the diagnostics below it can take the remaining
    -- height, the way TOGPM's settings page puts its diagnostics last.
    local body = AceGUI:Create("SimpleGroup")
    body:SetFullWidth(true)
    body:SetHeight(self.SISTER_WINDOW_LIST_HEIGHT)
    body:SetLayout("Fill")
    frame:AddChild(body)

    local function showState(_, row) return row.state or "" end
    win.list = W.RowList:New(body.content or body.frame, {
        rowCount = 12,
        columns  = {
            { key = "name",        header = "Guild",   justify = "LEFT" },
            { key = "members",     header = "Members", justify = "RIGHT", width = 70 },
            { key = "onlineCount", header = "Online",  justify = "RIGHT", width = 60 },
            { key = "stateSort",   header = "State",   justify = "LEFT",  width = 120, format = showState },
        },
        actions = {
            {
                texture = "Interface\\Buttons\\UI-GroupLoot-Pass-Up",
                tooltip = "Remove from the list (officer or guild master)",
                show    = function() return self:IsOfficer() == true end,
                onClick = function(row)
                    self:HandleSlash("sisters remove " .. row.name)
                    self:RefreshSisterWindow()
                end,
            },
        },
        onRowClick = function(row, _, _, button, rowFrame)
            button = button or (GetMouseButtonClicked and GetMouseButtonClicked())
            if button == "RightButton" and W.OpenMenu then
                W:OpenMenu(rowFrame or win.frame, self:SisterRowMenuItems(row), { width = 260 })
            end
        end,
    })
    win.list:SetSort("name")

    -- The sync status, one line per guild and the last event, in its own
    -- block. It lived in the bottom status bar until 2026-09-15 and was cut
    -- off after a few words -- the user: "we need to move the sync stuff to
    -- another area, not enough space in the status bar". The bar keeps the
    -- version only.
    local syncHeading = AceGUI:Create("Heading")
    syncHeading:SetText("Sync")
    syncHeading:SetFullWidth(true)
    frame:AddChild(syncHeading)
    win.status = AceGUI:Create("Label")
    win.status:SetFullWidth(true)
    frame:AddChild(win.status)

    -- Diagnostics: the same lines `/guildroster diag` prints, in a scroll
    -- frame that takes whatever height the list left. Repainted with the
    -- rest of the window.
    local heading = AceGUI:Create("Heading")
    heading:SetText("Diagnostics")
    heading:SetFullWidth(true)
    frame:AddChild(heading)
    local scroll = AceGUI:Create("ScrollFrame")
    scroll:SetLayout("Flow")
    scroll:SetFullWidth(true)
    scroll:SetFullHeight(true)
    frame:AddChild(scroll)
    win.diag = AceGUI:Create("Label")
    win.diag:SetFullWidth(true)
    scroll:AddChild(win.diag)

    -- Sync now, on the bottom bar beside the info "i", rate-limited by the
    -- widget library's named cooldown so a click cannot spam the guild.
    if W.BindCooldownButton then
        local btn = CreateFrame("Button", nil, win.frame, "UIPanelButtonTemplate")
        btn:SetSize(90, 20)
        btn:SetPoint("RIGHT", frame.info, "LEFT", -6, 0)
        frame.statusbg:SetPoint("BOTTOMRIGHT", btn, "BOTTOMLEFT", -6, -2)
        if W.AttachTooltip then
            W:AttachTooltip(btn, "Sync now", "Gossip the list, relay the held rosters, and pull "
                .. "each sister guild from its freshest known-online member.")
        end
        local opts = {
            label   = "Sync now",
            onClick = function() self:HandleSlash("sync") self:RefreshSisterWindow() end,
            seconds = function() return self.SISTER_WINDOW_SYNC_COOLDOWN end,
            format  = function(n) return n .. "s" end,
        }
        win.sync = W:BindCooldownButton(btn, "LibGuildRoster-sync", opts)
    end

    -- Repaint on the library's own signals. Registered once, here, with the
    -- window record as the handle so a LibStub upgrade's fresh record gets its
    -- own registration rather than stacking on an old one.
    for _, event in ipairs({ "OnSisterConfigChanged", "OnSisterRosterUpdated", "OnRosterHashChanged",
                             "OnMailAutocompleteChanged", "OnGuildTabChanged", "OnRosterReady" }) do
        self.RegisterCallback(win, event, function() self:RefreshSisterWindow() end)
    end
    return win
end
lib.SISTER_WINDOW_SYNC_COOLDOWN = 20
-- Header plus six rows of the list; a longer list scrolls inside the band.
lib.SISTER_WINDOW_LIST_HEIGHT   = 130

--- Repaint from the model. Sends nothing. Cheap and idempotent, so every
-- callback can just call it; a no-op while the window is not built or hidden.
-- @return boolean  whether anything was painted
function lib:RefreshSisterWindow()
    local win = self.sisterWindow
    if not (win and win.frame and win.frame:IsShown()) then return false end
    local officer = self:IsOfficer() == true
    win.addBox:SetDisabled(not officer)
    win.note:SetText(officer and "" or NOT_OFFICER_NOTE)
    win.mailBox:SetValue(self:IsMailAutocompleteEnabled())
    win.tabBox:SetValue(self:IsGuildTabEnabled())
    win.tabDefaultBox:SetValue(self:IsGuildTabDefault())
    win.tabDefaultBox:SetDisabled(not self:IsGuildTabEnabled())
    win.list:SetData(self:BuildSisterWindowRows(), true)
    win.diag:SetText(table.concat(self:BuildDiagnosticLines(), "\n"))
    self:TickSisterWindow()
    return true
end

--- The Sync block: what the sync is doing right now, one line per guild and
-- the last event (GetSyncStatusText's segments, one per line). Run once per
-- second by the ticker ToggleSisterWindow arms on show; the ticker retires
-- itself the first time it finds the window hidden, so a closed window costs
-- nothing. The window is re-laid-out only when the text CHANGED, because a
-- label's height follows its line count and the ticker must not re-layout
-- every second for a countdown. Returns whether it painted.
-- @return boolean
function lib:TickSisterWindow()
    local win = self.sisterWindow
    if not (win and win.frame and win.frame:IsShown()) then
        if win and win.ticker then
            win.ticker:Cancel()
            win.ticker = nil
        end
        return false
    end
    local text = (self:GetSyncStatusText():gsub("^Sync: ", ""):gsub("  |  ", "\n"))
    local lines = select(2, text:gsub("\n", "\n"))
    win.status:SetText(text)
    if lines ~= win.statusLines then
        win.statusLines = lines
        if win.widget.DoLayout then win.widget:DoLayout() end
    end
    return true
end
lib.SISTER_WINDOW_TICK = 1

--- Open the window, or close it if it is open. Built on first use. Returns
-- nil -- and prints why -- when the widget library is not present, so the
-- slash handler can fall back to its text usage.
-- @return table|nil  the window record
function lib:ToggleSisterWindow()
    local W = Widgets()
    if not (W and W.RowList and LibStub("AceGUI-3.0", true)) then
        say("the window needs LibAceGUIWidgets; the /guildroster commands still work.")
        return nil
    end
    local win = self.sisterWindow
    if win and win.frame:IsShown() then
        win.frame:Hide()
        return win
    end
    if not win then
        win = self:CreateSisterWindow(W)
        self.sisterWindow = win
    end
    win.frame:Show()
    self:RefreshSisterWindow()
    if not win.ticker and C_Timer and C_Timer.NewTicker then
        win.ticker = C_Timer.NewTicker(self.SISTER_WINDOW_TICK, function() self:TickSisterWindow() end)
    end
    return win
end

-- ===========================================================================
-- Alt groups (MINOR 17). A PORT of TOGProfessionMaster's working shape, not a
-- fresh design -- read Scanner.lua:3383-3406 there before changing anything
-- here, because that code is the specification and it is in production.
--
-- WHAT IS DELIBERATELY ABSENT, so nobody adds it back as an improvement:
--
-- * NO CROSS-OWNER REFUSAL. A design round proposed rejecting a call that
--   names an alt already owned by somebody else. TOGProfessionMaster has no
--   such check and does not need one: claims are keyed by BROADCASTER, so a
--   client only ever writes its own key and there is no collision to refuse.
--   Adding a refusal here would make a legitimate whole-group update blockable
--   by one stale name held by an owner who never logs in again.
--
-- * NO ARBITRATION. Which of two competing claims wins is decided by the
--   consumer from timestamps it holds and this library does not (TOGPM does it
--   at Scanner.lua:3380, comparing a delivered timestamp against a stored hash
--   record). Pulling that in would mean teaching a roster library about wire
--   hashes and delivery times, which are none of its business. We take an
--   array and store it; the caller decides whether to call at all.
--
-- THE SORT IS LOAD-BEARING AND IS NOT COSMETIC. TOGPM sorts before storing,
-- and every downstream comparison depends on it: the "did this group actually
-- change" check is an element-wise walk of two arrays, and the sync hash is
-- computed over the array as given. Unsorted, two clients holding the identical
-- set produce different hashes and resync each other forever.
--
-- WHERE THIS IS DELIBERATELY BETTER THAN THE CODE IT WAS PORTED FROM, and it
-- is the one place the port is not a copy:
--
-- ALT NAMES GO THROUGH CanonName, NEVER NormalizeName. An alt group is WIRE
-- DATA by construction -- it is one player's client telling every other client
-- which characters it owns -- so it is the exact provenance the header's
-- "NormalizeName vs CanonName" rule is written about. NormalizeName appends the
-- RECEIVER's realm to a bare name; on a connected-realm cluster that makes
-- "Bobbank" a different identity on every listener, so the same group produces
-- a different sorted array and a different sync hash per realm and the clients
-- resync each other forever. CanonName canonicalizes the REPRESENTATION and
-- never invents a realm, so a bare name stays bare and every client agrees.
--
-- TOGProfessionMaster cannot have this right: its altClaims were built before
-- CanonName existed (MINOR 11) and it stores whatever charKeys came off the
-- wire. FastGuildInvite hit the same class of defect independently -- a bare
-- designated-announcer entry that resolved to a different Name-Realm on each
-- realm's clients, so the election disagreed. Do not "simplify" these calls to
-- NormalizeName for consistency with the roster methods; the difference is the
-- point, and the roster methods read LOCAL client APIs where appending the
-- local realm is a correct inference.
--
-- The consequence, stated so it is not a surprise: a bare name stays bare in
-- STORAGE, so it will not string-match a roster key of the form "Name-Realm".
-- That is handled at the COMPARISON boundary instead -- IsAltOfRosterMember
-- hands names to IsInGuildScoped / IsInAnyRoster, which normalize, because
-- asking "is this character in MY roster" is a local question and local
-- context is legitimate there. A caller holding LOCAL names (from
-- GetGuildRosterInfo, UnitName, its own account data) and wanting them stored
-- qualified should pass them through lib:NormalizeName itself first; that is
-- the caller's provenance to declare, and this library must not guess it.
-- ===========================================================================

-- Both spellings of one character that a LOOKUP may legitimately try.
--
-- THE PROBLEM THIS SOLVES, and it is the direct cost of storing bare names:
-- storage is exact, so "Bobbank" and "Bobbank-Testrealm" are different keys. A
-- consumer that feeds some names off the wire (bare) and some from a local API
-- (realm-qualified) ends up with two entries for one character, and every
-- lookup misses half the time.
--
-- THE RULE, and it is the only one that is safe: a bare name and a name
-- qualified with THE LOCAL REALM are the same character; a bare name and a
-- name qualified with ANY OTHER realm are not, and must never be matched.
-- That is exactly the inference NormalizeName encodes, which is why the test
-- below is spelled as a NormalizeName round trip rather than by string surgery
-- on the realm half -- the two cannot then disagree.
--
-- Applied on READS only. Writes stay exact: inventing a realm at storage time
-- is the connected-realm defect this whole section exists to avoid, and a
-- tolerant read cannot corrupt stored state or make two clients' hashes differ.
-- Before the realm resolves, NormalizeName returns the bare name, so this
-- degrades to "one form" rather than guessing.
-- Side effect: normalizes, which caches (bounded -- NAME_CACHE_MAX).
-- @return string|nil primary, string|nil equivalent alternate
local function altKeyForms(self, name)
    local canon = self:CanonName(name)
    if not canon then return nil end

    local norm = self:NormalizeName(canon)
    if norm and norm ~= canon then
        -- `canon` was bare; the local-realm spelling is its equivalent.
        return canon, norm
    end

    -- `canon` is already qualified (or the realm has not resolved). Its bare
    -- form is equivalent only when the realm IS ours, which the round trip
    -- decides: NormalizeName("Bob") == "Bob-Testrealm" only on Testrealm.
    local bare = string.match(canon, "^(.-)%-")
    if bare and bare ~= "" and self:NormalizeName(bare) == canon then
        return canon, bare
    end
    return canon
end

--- Replace the alt group filed under `ownerName`, wholesale.
-- WIPE, never merge: the stored group is exactly the picture the last caller
-- supplied. There is no "remove one alt" call because a merging API has no
-- correct way to say "this character is no longer mine" -- you re-state the
-- whole group, or you RemoveAltGroup.
-- Names are canonicalized with CanonName (NOT NormalizeName -- see the block
-- comment above; this is wire data and appending the receiver's realm would
-- invent a per-client identity), duplicates collapsed, and the result SORTED.
-- A name that fails to canonicalize is dropped rather than stored raw, so a
-- garbage entry off the wire cannot become a lookup key.
-- CanonName does NOT touch the name cache, so unlike most methods here this
-- one has no memoization side effect.
--
-- `meta` is the record's CANON, in DeltaSync's sense -- see its README, section
-- "Canonical hashes -- compute once, at save, and never again". The shape:
--
--     { source = "MyAddon", setAt = <datestamp>, hash = <the canon> }
--
-- produced ONCE, in the client that authored the version, at the moment the
-- change was saved, with `setAt` stamped FIRST and INCLUDED in the hashed
-- input. Everywhere after that -- advertising, answering a peer, handing it to
-- us -- the canon is READ AND FORWARDED, never recomputed. This library holds
-- to that: it stores `meta` verbatim and computes no hash of its own, ever.
--
-- The alt store is SHARED across every addon in the client, so several of them
-- can write it. Two questions arise and they are DIFFERENT questions:
--
--   IDENTITY -- "is this the same version?" -- answered by `hash` alone. An
--   equal hash means the same PUBLISH EVENT, not merely the same names, because
--   the datestamp is inside the hashed input. That write is a no-op and returns
--   `true, "unchanged"`: no wipe, no reverse-index churn, nothing.
--
--   ORDERING -- "which is newer?" -- which a hash CANNOT answer, and this is
--   the canon's own rule 7. Decided from `setAt`, at the apply step, which for
--   alt groups is this call. A strictly older write is REFUSED and returns
--   `false, "stale"`, so a caller can tell that from bad input (plain `false`).
--
-- `setAt` is deliberately NOT a second version-identity channel -- the canon
-- forbids that ("a second channel carrying version identity is a second thing
-- that can disagree with the first"). It is the same datestamp already sealed
-- inside `hash`, exposed only so the ordering rule has something to read.
--
-- Both checks need BOTH sides to carry the field, so a caller that passes no
-- meta -- or a pre-canon one -- gets exactly the last-write-wins behaviour it
-- always had. Nothing has to adopt this at once.
--
-- IMPORTANT: meta FOLLOWS THE WIPE. Omitting it CLEARS any previously stored
-- blob, which is the opposite of SetSisterRoster's meta (that one preserves on
-- nil). The difference is deliberate and the wipe is what forces it: this call
-- replaces the group wholesale, so a retained stamp would attribute the NEW
-- group to whoever fed the OLD one -- a stale provenance claim is worse than
-- none, because a feeder acts on it.
-- @param ownerName string - short name or "Name-Realm"
-- @param altNames table - array of names; may legitimately include the owner
-- @param meta table|nil - opaque; stored as-is, never interpreted; nil clears
-- @return boolean  true if the group was stored
function lib:SetAltGroup(ownerName, altNames, meta)
    if type(altNames) ~= "table" then return false end
    local owner = self:CanonName(ownerName)
    if not owner then return false end

    -- IDENTITY, then ORDERING -- in that order, and they are not the same
    -- question. This follows DeltaSync's canonical-hash rules (its README,
    -- "Canonical hashes -- compute once, at save, and never again").
    --
    -- `hash` is the ONE version identity. It was produced once, by the client
    -- that authored this version, at save time, over a record that INCLUDED the
    -- datestamp. That last part is what makes an equal hash mean "the same
    -- PUBLISH EVENT" rather than merely "the same names" -- two saves of
    -- coincidentally identical content hash differently, so equality here is
    -- genuinely "nothing happened". We store it verbatim and NEVER recompute
    -- it: recomputing overwrites the author's statement about their own version
    -- with our opinion of it, after which nobody is authoritative.
    --
    -- `setAt` is NOT a second identity channel -- it is the datestamp that is
    -- already inside the hash, exposed so ordering can be decided. The canon is
    -- explicit that the hash says WHETHER two versions differ and cannot say
    -- WHICH IS NEWER, and that the ordering rule belongs at the apply step. For
    -- alt groups this call IS the apply step, so the rule lives here, once, for
    -- every addon in the client -- rather than four addons each inventing one.
    -- Ordering compares against `altGroupSeen` -- the HIGHEST setAt ever
    -- accepted for this owner -- and NOT against the standing meta's setAt.
    -- The difference only shows up in the mixed-adopter window, and there it is
    -- the whole protection (finding 25). An unstamped write CLEARS the visible
    -- meta, for the crediting reason below; if the refusal read that cleared
    -- value it would find nil, skip the check, and accept a record it had
    -- already superseded. So one meta-less write from a not-yet-adopted addon
    -- would disarm staleness for every adopted one until a new stamp arrived.
    -- The high-water mark is internal and survives the clear, so it cannot.
    -- It is a bare number, never the caller's table: remembering how far we
    -- have got is ours, attributing a version is theirs.
    local standing = self.altGroupMeta[owner]
    local seenAt = self.altGroupSeen[owner]
    if type(meta) == "table" then
        if type(standing) == "table" and meta.hash ~= nil and meta.hash == standing.hash then
            return true, "unchanged"
        end
        if type(meta.setAt) == "number" and type(seenAt) == "number"
            and meta.setAt < seenAt then
            return false, "stale"
        end
    end

    local arr, seen = {}, {}
    for i = 1, #altNames do
        local canon = self:CanonName(altNames[i])
        if canon and not seen[canon] then
            seen[canon] = true
            arr[#arr + 1] = canon
        end
    end
    table.sort(arr)

    -- Retire the PREVIOUS group's reverse-index entries before writing the new
    -- ones. Without this a name dropped from the group keeps pointing at this
    -- owner forever, and GetAltOwner answers for a group that no longer lists
    -- it -- the same resurrection TOGPM's purge path guards against at
    -- TOGProfessionMaster.lua:2500-2516. The `== owner` test matters: another
    -- owner may have claimed the name in between, and clearing that would
    -- silently unparent somebody else's alt.
    local prev = self.altGroups[owner]
    if prev then
        for i = 1, #prev do
            if self.altOwners[prev[i]] == owner then self.altOwners[prev[i]] = nil end
        end
    end

    self.altGroups[owner] = arr
    -- Assigned unconditionally, so a nil meta CLEARS. See the docstring: the
    -- group was just replaced wholesale, and a surviving stamp would credit the
    -- new group to the previous feeder. The ordering high-water above is what
    -- keeps the clear from also disarming the staleness check.
    self.altGroupMeta[owner] = meta
    if type(meta) == "table" and type(meta.setAt) == "number"
        and (seenAt == nil or meta.setAt > seenAt) then
        self.altGroupSeen[owner] = meta.setAt
    end

    -- RE-PARENTING: last writer wins the CHARACTER, not merely the index.
    -- Claiming a name another owner still lists drops it from THAT owner's
    -- stored group as well. Without this the two structures disagree
    -- permanently (finding 25's sibling, finding 24): the retire loop above
    -- only ever inspects THIS owner's previous group, so Carol could go on
    -- listing Bob while altOwners said Alice -- and the `== owner` guard means
    -- no later legitimate update reconciles them. The visible cost is that
    -- IsSameAccount and IsAltOfRosterMember then answer from whichever
    -- structure they happen to read, which is how a lossy index becomes a
    -- confidently WRONG answer rather than an absent one.
    --
    -- KNOWN COST, stated rather than hidden: GetAltGroup(previousOwner) no
    -- longer returns exactly what that broadcaster said -- one name has been
    -- taken out of their picture by somebody else's later claim. That is a real
    -- departure from "the stored group is the last caller's whole picture", and
    -- it is the price of the two structures agreeing by construction.
    --
    -- The rebuild REPLACES the array; it never splices in place. Mutating it
    -- would break GetAltGroup's read-only promise for any consumer holding a
    -- reference -- the promise that makes returning the internal array safe.
    for i = 1, #arr do
        local name = arr[i]
        -- Resolve the previous owner TOLERANTLY, through both spellings.
        -- This is a READ of state we already hold, deciding which stored entry
        -- to retire -- NOT a write of the incoming name. It never invents a
        -- realm, never changes what goes into `arr`, and so cannot make two
        -- clients store different arrays or hash differently. That distinction
        -- is why it does not breach the writes-stay-exact rule above.
        --
        -- An exact lookup here was defeated by two broadcasters spelling one
        -- character differently -- Carol claiming "Bob" and Alice claiming
        -- "Bob-Ourrealm", both legitimate wire forms that CanonName preserves
        -- as distinct keys. The re-parent found nothing to retire, both
        -- entries stood, and GetAltOwner then answered a DIFFERENT owner
        -- depending on which spelling you asked with, because altKeyForms puts
        -- the queried form first. The reconciliation has to honour exactly the
        -- equivalence its readers honour, or it cannot see the conflict.
        --
        -- Best-effort before the realm resolves: altKeyForms degrades to one
        -- form there, like every other name path in this file.
        local canonName, altName = altKeyForms(self, name)
        local previousOwner = self.altOwners[canonName]
            or (altName and self.altOwners[altName]) or nil
        -- `canonName` cannot be nil here: `arr` holds only names that passed
        -- CanonName (failures were dropped above) and CanonName is idempotent.
        -- And if it somehow were, `previousOwner` would be nil and this block
        -- would not run. The check is stated anyway so the invariant is in the
        -- code rather than in a comment, and so a nil can never reach the
        -- table writes below as a key.
        if canonName and previousOwner and previousOwner ~= owner then
            local theirs = self.altGroups[previousOwner]
            if theirs then
                local rebuilt = {}
                for j = 1, #theirs do
                    -- Drop EITHER spelling: they are the same character, and
                    -- leaving the other behind is the disagreement itself.
                    if theirs[j] ~= canonName and theirs[j] ~= altName then
                        rebuilt[#rebuilt + 1] = theirs[j]
                    end
                end
                -- Still sorted: order is preserved from an already-sorted array.
                self.altGroups[previousOwner] = rebuilt
            end
            -- Retire the OTHER spelling's index entry too. Without this the
            -- reverse index keeps answering the previous owner for that form,
            -- which is the finding pointed the other way.
            if altName and self.altOwners[altName] == previousOwner then
                self.altOwners[altName] = nil
            end
            if self.altOwners[canonName] == previousOwner then
                self.altOwners[canonName] = nil
            end
        end
        self.altOwners[name] = owner
    end
    return true
end

--- Stop tracking the alt group filed under `ownerName`.
-- Keyed with CanonName, matching how SetAltGroup stored it.
-- @param ownerName string
-- @return boolean  true if a group was actually removed
function lib:RemoveAltGroup(ownerName)
    local owner = self:CanonName(ownerName)
    if not owner then return false end
    local prev = self.altGroups[owner]
    if not prev then return false end
    for i = 1, #prev do
        if self.altOwners[prev[i]] == owner then self.altOwners[prev[i]] = nil end
    end
    self.altGroups[owner] = nil
    self.altGroupMeta[owner] = nil
    -- The ordering high-water goes too. Removing is an explicit "stop tracking
    -- this owner", and keeping the mark would make the owner permanently
    -- un-refeedable from an archive whose stamps predate the removal.
    -- KNOWN COST: a remove-then-re-add can therefore land a record older than
    -- one already superseded. Deliberate -- RemoveAltGroup is a consumer
    -- decision, unlike the unstamped write finding 25 is about, which is not.
    self.altGroupSeen[owner] = nil
    return true
end

--- The alt group filed under `ownerName`, or nil.
-- Returns the INTERNAL sorted array, not a copy -- the same contract as
-- GetRoster, which is the whole reason: a consumer holding both should not have
-- to remember which of the two it may keep a reference to. Note this is NOT the
-- contract of GetAllMembers/GetOnlineMembers/GetKnownAltOwners, which build a
-- fresh array every call; those answer a QUESTION, this hands back a STORED
-- table, and that is the line. The saved allocation on a tooltip path is real
-- but UNMEASURED and is not what decides it.
-- Treat it as read-only; mutating it corrupts the reverse index, which is why
-- SetAltGroup copies on the way IN and nothing a caller holds can reach this
-- table. Nothing inside this library mutates a stored group in place -- every
-- write replaces the whole array -- so a caller that honours read-only can
-- never be surprised by us.
-- Keyed with CanonName, matching how SetAltGroup stored it.
-- @param ownerName string
-- @return table|nil  sorted array of charKeys
function lib:GetAltGroup(ownerName)
    local owner, alt = altKeyForms(self, ownerName)
    if not owner then return nil end
    return self.altGroups[owner] or (alt and self.altGroups[alt]) or nil
end

--- The canon last stored alongside this owner's group, or nil.
-- Exactly what the feeding consumer passed as SetAltGroup's third argument,
-- stored VERBATIM. The shape is `{ source, setAt, hash }` -- see SetAltGroup
-- for how it must be produced (once, at save, with `setAt` inside the hashed
-- input).
--
-- THE LIBRARY READS TWO OF THOSE FIELDS, and this docstring used to say it read
-- none. `hash` decides identity: an incoming write whose hash equals the stored
-- one is a no-op. `setAt` decides ordering: a strictly older write is REFUSED.
-- `source` is never inspected, and neither is anything else you put in here.
-- The table itself is still handed back untouched -- we store your statement,
-- we do not rewrite it.
--
-- THIS IS ALSO THE MULTI-FEEDER GUARD, and it still has a job even though the
-- library now arbitrates. The alt store is shared across every addon in the
-- client, and SetAltGroup only protects the key it is WRITING -- RemoveAltGroup
-- takes no canon and refuses nothing. A feeder sweeping stale owner keys must
-- read this on the key it is about to REMOVE and compare `setAt` itself.
--
-- nil means one of three things and they are NOT distinguishable here: no group
-- is filed under this owner, a group is filed but was fed without meta, or the
-- last write cleared it. A feeder that needs the difference should check
-- GetAltGroup for existence first.
--
-- Returns the INTERNAL table, on the same read-only terms as GetAltGroup.
-- Keyed with CanonName, matching how SetAltGroup stored it.
-- @param ownerName string
-- @return table|nil
function lib:GetAltGroupMeta(ownerName)
    local owner, alt = altKeyForms(self, ownerName)
    if not owner then return nil end
    return self.altGroupMeta[owner] or (alt and self.altGroupMeta[alt]) or nil
end

--- Which owner key is this character filed under?
-- Answers for a character that appears in some group's array. An owner who
-- listed themselves in their own group resolves to themselves; one who did not
-- resolves to nil, because nothing filed them anywhere.
-- Keyed with CanonName, matching how SetAltGroup stored it.
-- @param altName string
-- @return string|nil  the owner key
function lib:GetAltOwner(altName)
    local canon, alt = altKeyForms(self, altName)
    if not canon then return nil end
    return self.altOwners[canon] or (alt and self.altOwners[alt]) or nil
end

--- Do these two characters share an account, as far as anyone has told us?
-- True when they resolve to the same owner, and also when one IS the other's
-- owner -- an owner who did not list themselves still owns their alts, and a
-- consumer asking "are these the same player" means yes in that case.
-- Never true for two names that are simply both unknown.
-- Both keyed with CanonName, matching how SetAltGroup stored them. A caller
-- comparing a LOCAL name against a stored wire name must decide the provenance
-- itself -- pass the local one through NormalizeName first if the stored form
-- is realm-qualified, or keep both bare.
-- @param nameA string
-- @param nameB string
-- @return boolean
function lib:IsSameAccount(nameA, nameB)
    local a, aAlt = altKeyForms(self, nameA)
    local b, bAlt = altKeyForms(self, nameB)
    if not a or not b then return false end
    -- The same character spelled two ways (bare vs local-realm) counts.
    if a == b or a == bAlt or b == aAlt then return true end

    local ownerA = self.altOwners[a] or (aAlt and self.altOwners[aAlt])
    local ownerB = self.altOwners[b] or (bAlt and self.altOwners[bAlt])
    if ownerA and ownerA == ownerB then return true end
    -- One of them is the other's owner key, without having listed itself.
    -- Compared against both spellings for the same reason as above.
    if ownerA and (ownerA == b or ownerA == bAlt) then return true end
    if ownerB and (ownerB == a or ownerB == aAlt) then return true end
    return false
end

--- Every owner key we currently hold a group for, sorted.
-- Sorted so a consumer iterating it renders in a stable order across clients;
-- pairs() over the table would not.
-- @return table  array of owner keys (empty, never nil)
function lib:GetKnownAltOwners()
    local result = {}
    for owner in pairs(self.altGroups) do
        table.insert(result, owner)
    end
    table.sort(result)
    return result
end

--- Is this character an alt of somebody who IS in a roster we track?
-- This is the question TOGProfessionMaster's IsAltOfInRosterCharacter exists to
-- answer (TOGProfessionMaster.lua:2303): a bank alt is typically NOT in the
-- guild itself, so a visibility sweep keyed on roster membership deletes it
-- unless something vouches for its owner.
-- Works ACROSS SISTER ROSTERS: an alt of a member of a sister guild is still an
-- alt of somebody you know. Pass `rosterKey` to ask about one roster; omit it
-- to ask about home plus every sister.
-- THE TWO NAME FORMS MEET HERE, and that is deliberate: the alt-group lookup
-- is keyed with CanonName (wire provenance), while the roster test goes through
-- IsInGuildScoped / IsInAnyRoster, which normalize (local provenance, so
-- appending the local realm is a correct inference). Doing it either way for
-- both halves is wrong -- normalizing the alt key would invent a per-client
-- identity, and canonicalizing the roster test would fail to match a bare name
-- against a "Name-Realm" roster key.
-- Side effect: the roster half normalizes, which caches (bounded).
-- @param name string
-- @param rosterKey string|nil  a guildKey, or nil for "any roster we track"
-- @return boolean
function lib:IsAltOfRosterMember(name, rosterKey)
    local canon, alt = altKeyForms(self, name)
    if not canon then return false end

    local owner = self.altOwners[canon] or (alt and self.altOwners[alt])
    -- A character that owns a group but never listed itself in it still has a
    -- group to vouch for, so fall back to its own key.
    if not owner then
        if self.altGroups[canon] then owner = canon
        elseif alt and self.altGroups[alt] then owner = alt end
    end
    if not owner then return false end

    local function inScope(charKey)
        if rosterKey then return self:IsInGuildScoped(rosterKey, charKey) end
        return self:IsInAnyRoster(charKey) ~= nil
    end

    -- The owner vouches first; it is the common case and usually the character
    -- actually in the guild.
    -- "Is this entry the character we were asked about?" -- BOTH spellings,
    -- or a group storing the bare form would vouch for the qualified query and
    -- call it somebody else.
    local function isSelf(charKey)
        return charKey == canon or (alt and charKey == alt)
    end

    if not isSelf(owner) and inScope(owner) then return true end

    -- Otherwise any OTHER member of the same group will do. The character
    -- itself is skipped deliberately: this asks whether somebody ELSE vouches
    -- for it, and one already in the roster on its own account needs no
    -- vouching.
    local group = self.altGroups[owner]
    if group then
        for i = 1, #group do
            if not isSelf(group[i]) and inScope(group[i]) then return true end
        end
    end
    return false
end
