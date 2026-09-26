# Embedded infrastructure library sources

These sources are loaded by the `Holy_Storm` core addon. The upstream Lua files are kept unmodified.

| Library | Source and version | License / dependency notes |
| --- | --- | --- |
| LibDataBroker-1.1 | [tekkub/libdatabroker-1-1](https://github.com/tekkub/libdatabroker-1-1), commit `1a63ede0248c11aa1ee415187c1f9c9489ce3e02`, LibStub minor 4 | The source repository has no license file or license declaration. The CurseForge package metadata marks it All Rights Reserved. Depends on the core LibStub and CallbackHandler. Retail compatibility is established by the current LibDBIcon v12.0.3 package, which embeds and uses this exact stable API. |
| LibDBIcon-1.0 | [CurseForge project](https://www.curseforge.com/wow/addons/libdbicon-1-0), v12.0.3, library minor 56 | Its package metadata marks it All Rights Reserved. Depends on LibDataBroker-1.1, LibStub, and CallbackHandler. Its current package lists Retail interface 120100. |
| LibSharedMedia-3.0 | [CurseForge project](https://www.curseforge.com/wow/addons/libsharedmedia-3-0), v12.0.3, library minor 12000001 | LGPL-2.1, as declared in the upstream source header. Depends on LibStub and CallbackHandler. The upstream package lists Retail interface 120100. |
| AceCommQueue-1.0 | [CurseForge project](https://www.curseforge.com/wow/addons/acecommqueue-1-0), v1.1.0, library minor 7 | MIT; upstream `LICENSE` included. Depends on AceComm-3.0 and ChatThrottleLib, both loaded centrally from the repository's Ace3 source. The upstream TOC lists Retail interface 120100. |
| LibGuildRoster-1.0 | [CurseForge project](https://www.curseforge.com/wow/addons/libguildroster), v0.9.2, library minor 24 | MIT; upstream `LICENSE` included. Depends on LibStub and CallbackHandler for its base library. Its optional peer-sync/UI features feature-detect AceComm, AceSerializer, VersionCheck, and AceGUI integrations. The upstream mainline TOC lists Retail interfaces 120007 and 120100. |
| AceComm-3.0 | [Ace3 source](https://github.com/WoWUIDev/Ace3), library minor 14 | BSD-style Ace3 license; `LICENSE.txt` included. Requires CallbackHandler and ChatThrottleLib. |
| ChatThrottleLib | [Ace3 source](https://github.com/WoWUIDev/Ace3), source bundled with AceComm-3.0 | BSD-style Ace3 license; same `LICENSE.txt`. |
| LibQTip-1.0 | Existing Holy Storm UI integration, library minor 49 | Existing source and ownership remain in `Holy_Storm_UI`; no duplicate was added to Core. |

LibDataBroker and LibDBIcon do not ship an explicit license grant in their upstream source archives. Their restrictive upstream package metadata is recorded above; this repository preserves the upstream source and does not claim a more permissive license. Review redistribution rights before publishing a package containing those two sources.

The embedded LibGuildRoster has its own internal roster and event hooks as part of the upstream library. Holy Storm does not read or use that roster, does not declare `LibGuildRosterDB`, and keeps `Persistence/GuildStore.lua` as its authoritative guild model. AceCommQueue is loaded but not embedded into an addon or used by the Sync Framework.
