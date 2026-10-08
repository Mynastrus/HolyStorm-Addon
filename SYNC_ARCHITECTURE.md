# Holy Storm – Sync-Architektur

## Schichten

`Sync/Comms.lua` kapselt Serialisierung, AddonMessage-Präfix, Fragmentierung, Transport und Transportdiagnose. `Sync/SyncManager.lua` implementiert den generischen Domain-Vertrag und die Abläufe Discovery, Offer, Select, Fetch, Payload, Publish und passive Heilung. Versand und verzögerte Auswahl laufen über TaskManager; Module erzeugen keine eigene Transport-Queue.

Eine Domain registriert je nach Bedarf:

- `getMetadata(objectId)` und `listMetadata(since, request)`
- `export(objectId)`
- `validate(payload, metadata, objectId)`
- `authorize(payload, metadata, senderId, sender, objectId)`
- `import(objectId, payload, metadata, senderId, sender)`
- optional `getChannel`, `updateEvent`, `freshness`, `live`, `catchUp`, `priority`

Aktuell registrierte Domains sind `character`, `permissions`, `twinks`, `twinkAdmin`, `content`, `poi`, `achievements` und die flüchtige Domain `guild-position`.

## HS_Player_DB und Character-Blöcke

`HS_Player_DB` ist der kanonische persistente Player-/Account-/Character-Bestand. `PlayerDataStore` registriert die Blöcke `identity`, `equipment`, `mythicPlus`, `raid`, `delves`, `stats`, `profile`, `professions`, `addon` und `demands`.

Jeder Block besitzt eigene Metadaten mit `owner`, `version`, `updatedAt`, `source`, `receivedFrom` und `direct`. Der Objekt-Key der Character-Domain kombiniert Character-UUID und Block-ID. Ein lokaler gültiger Snapshot wird über `WriteOwnedBlock` gespeichert; ein Remote-Block durchläuft Domain-Validierung, Owner-Prüfung und `AcceptRemoteBlock`.

SnapshotManager trennt Scan, Validierung und Commit. Ein fehlgeschlagener Scan schreibt keinen leeren oder ungültigen Block über den letzten gültigen Stand. UI und Module lesen den persistenten Store und sind nach `/reload` nicht von einem neuen Scan abhängig.

## Owner Revision und Provenance

Für owner-kontrollierte Objekte ist `owner` die stabile fachliche Herkunft. `receivedFrom` bezeichnet nur die Gegenstelle, die ein Paket übertragen hat; ein Relay wird dadurch nicht zum Owner. `direct` zeigt an, ob der erkannte Sender dem Owner entspricht. Foreign Watermarks werden pro Domain fortgeschrieben und vermeiden unnötige Vollabfragen.

`CompareMetadata` entscheidet die Frische normaler Domains anhand der implementierten Version-/Zeit-/Provenance-Regeln. Domain-Validatoren und `authorize` bleiben zusätzlich verpflichtend. Ein Relay darf vorhandene Metadaten weiterreichen, aber keine Owner-Identität übernehmen.

## Discovery und Übertragung

1. `Discover` stellt eine `Sync.Discover`-Aufgabe mit lokal bekannter Version/Revision ein.
2. Gegenstellen liefern begrenzte Metadatenangebote.
3. `Sync.Select` wählt ein geeignetes Angebot; bekannte Owners werden bevorzugt gezielt angefragt.
4. `FETCH` fordert das Objekt per Whisper an.
5. `PAYLOAD` wird deserialisiert, validiert, autorisiert und importiert.
6. Domain- und Feature-Events aktualisieren Verbraucher.

Domains mit empfängerabhängiger Sichtbarkeit können `canShare(metadata, recipientGuid, recipientName, reason)` und `getRecipients(metadata, reason)` registrieren. Der SyncManager filtert damit Discovery-Metadaten vor dem Angebot, sendet solche Angebote per Whisper und prüft `FETCH` vor dem Export. `guildNotes` nutzt diesen Vertrag; private Notizen besitzen ausdrücklich keine Domain. Das ersetzt keine Kryptografie und schützt nicht vor einem manipulierten, bereits autorisierten Client.

Live-Domains wie `guild-position` nutzen direkte, kurzlebige Publishes und keinen persistenten Catch-up. Andere Domains können Discovery und passive Heilung verwenden.

## Login-Presence, Revisionen und bedarfsbasierter Sync

### Ausgangsaudit

Vor der Aenderung sendete `RunLoginPresence()` eine Guild-Presence mit Version und Session-ID und rief danach `RunCatchUp()` auf. `RunCatchUp()` startete `Discover` fuer jede geladene registrierte Domain mit `catchUp ~= false`. Zu den Laufzeit-Domains gehoerten `character`, `permissions`, `twinks`, `twinkAdmin`, `content`, `achievements`, `guildLog`, `guildAbsences`, `guildActivityPoints`, `guildNotes` und `guildActivity`. `poi` und `guild-position` waren die bestehenden `catchUp=false`-Ausnahmen.

Zusaetzliche redundante Voll-Discoveries kamen von Achievements bei `PLAYER_ENTERING_WORLD`, von POI-Startup, `News:OnEnable()`, `GuildManagement:OnEnable()` und dem Achievement-Handler fuer `HS_GUILD_UPDATED`. `CharacterScanManager:BeginLogin()` setzte Scan-Zustaende zurueck, loeste aber selbst keine Producer-Scans aus. Der globale Sync-Catch-up loeste Discovery-Aufgaben aus, keine neuen Character-Producer-Scans. Separat behaelt das aktivierte und privacy-gated `guild-position` Feature seinen Live-Position-Capture und seine nur auf diese Live-Domain begrenzte Login-/Roster-Discovery; `guild-position` bleibt `catchUp=false`. POI behaelt nur einen gruppensitzungsgebundenen Resync, keine automatische Guild-Discovery.

### Neuer Ablauf

```text
PLAYER_LOGIN
  -> eine minimale Guild-PRESENCE mit Version und Session-ID
  -> kleines Manifest aktueller Owner-Revisionen
  -> jeder Empfaenger vergleicht ausschliesslich mit seinem lokalen Metadata-Stand
  -> nur fehlende oder neuere Remote-Revision erzeugt Fetch-Bedarf
  -> identische Fetch-Requests sammeln sich 0,75 Sekunden
  -> ein Empfaenger: gezielter Whisper
  -> mehrere Empfaenger: ein Guild-Transfer nur bei erlaubter gemeinsamer Sichtbarkeit
```

Die Presence enthaelt keine Snapshots oder Equipment-, Raid-, Mythic+-, Delves- oder Achievement-Payloads. Das Schema-1-Manifest ist auf 64 Eintraege begrenzt und enthaelt nur Domain, Objekt-ID, Owner, Version und gueltige Revisions-/Schema-Kopfwerte. Der Core-Provider kuendigt aktuell nur verfuegbare, aktivierte, lokal owner-kontrollierte Character-Bloecke an. Ein optionales Modul kann spaeter selbst einen Manifest-Provider registrieren; der Core braucht keine Feature-Addons. Unbekannte Domains bleiben in einer 256 Eintraege grossen, an den bestehenden Presence-TTL gebundenen Warteliste, bis das Modul geladen ist.

Der Empfaenger nutzt weiter `PlayerData:CompareMetadata` und die bestehenden Domain-Freshness-Vertraege. Gleicher Owner, gleiche Version und gleiche Revision ergeben keinen Fetch. Lokale neuere Versionen werden nicht angefordert oder ueberschrieben. Fehlende Snapshots und neuere Remote-Versionen registrieren eine normale `QueueFetch`-Aufgabe. Empfangene Angebote, echte Domain-Events und UI-/Refresh-Nutzung behalten passive Heilung bei.

Requests derselben Domain, Objekt-ID, Owner, Version und Revision werden in der bestehenden Sync-Job-Queue zusammengefuehrt. Ein Batch haelt hoechstens 64 Empfaenger und je Empfaenger vier Request-IDs. Ein einzelner Empfaenger erhaelt genau einen Whisper. Ein Guild-Broadcast wird nur verwendet, wenn alle Anfragenden im aktuellen Guild-Roster sind und die Domain entweder die Zielgruppe ausdruecklich erlaubt, jedes online Guild-Mitglied `canShare` besteht oder die Domain explizit als guild-broadcast-sicher markiert ist. Andernfalls gehen nur autorisierte Whispers heraus. Export findet erst statt, wenn mindestens eine Berechtigung nach der erneuten Pruefung besteht. Owner, Version und Revision werden vor Export erneut geprueft; Relays behalten den originalen Owner bei.

### Entfernte Startup-Pfade und Heartbeat

Der Achievement-`PLAYER_ENTERING_WORLD`-Discover und der redundante `HS_GUILD_UPDATED`-Discover wurden entfernt. POI-, Content-/News- und Achievement-Discoveries laufen beim Oeffnen ihrer jeweiligen Seiten; Guild-Management synchronisiert nur den ausgewaehlten Funktionsbereich. Character Overview fragt nur die Bloecke des aktuell ausgewaehlten Tabs ab. `RunCatchUp()` bleibt als kompatibler Einstieg erhalten, protokolliert aber `LOGIN_CATCHUP_SUPPRESSED` und startet keine Discovery.

Der periodische Presence-Heartbeat nach etwa 180-240 Sekunden wurde entfernt. Der Blizzard-Guild-Roster liefert den Online-Status; Login-Presence und angeforderte Antworten reichen fuer Versionserkennung. Die bekannte Peer-Version behaelt ihre bisherige Ablaufzeit von 300 Sekunden. `RunPresenceHeartbeat()` ist nur noch ein expliziter Einmal-Aufruf und plant weder sich selbst noch Catch-up nach.

Structured Logs zeigen Manifest-Empfang, aktuell/alt/neu-Entscheidung, zusammengefuehrte Requests und Empfaengerzahl, Whisper-/Broadcast-Auswahl, Privacy-Verweigerung, unterdrueckte Payloads und die bewusste Catch-up-Unterdrueckung. Payload-Inhalte werden nicht protokolliert. HSC1, AceCommQueue, das aktuelle Protokoll v3, PlayerData-Persistenz, Owner-Revisionen und Relay-Provenance bleiben bestehen.
## PermissionSync

Die Permission-Domain wird in `Core/Permissions/PermissionSync.lua` registriert und nutzt `freshness="revision-chain"`. Ihre Payload enthält aktuellen Revisionskopf, History und Snapshot. Der generische SyncManager überspringt für diese Domain die normale „neuere Metadaten gewinnen“-Entscheidung; PermissionSync prüft stattdessen die Kette.

- Nur die exakte direkte Vorgängerrevision kann sequenziell angewendet werden.
- Lücken führen zu Catch-up und gegebenenfalls `RECOVERY_REQUIRED`.
- Geschwisterrevisionen oder Snapshot-Abweichungen führen zu `CONFLICT`.
- Recovery aus einem Snapshot verlangt den implementierten Blizzard-Gildenleiter-Trust-Anchor.
- Es gibt ausdrücklich kein „highest version wins“ für Permission-State.

## Account- und Twink-Identität

PlayerStore und TwinkCore verwalten Account-/Player-UUIDs, Character-Zuordnungen und Main-Informationen. Die Domains `twinks` und `twinkAdmin` synchronisieren die vorgesehenen Identitäts- beziehungsweise administrativen Zuordnungsdaten. Character-Blöcke bleiben trotzdem Eigentum ihrer Character-UUID; Account-Zuordnung ändert keine Block-Provenance.

## Sicherheit und Grenzen

Alle eingehenden Daten werden als untrusted behandelt. IDs, Payloadstruktur, Guild-Kontext, Owner und fachliche Berechtigungen werden in der jeweiligen Domain geprüft. Logs enthalten Metadaten und Korrelationsdaten, keine vollständigen Payloads. Da WoW-Addons keine Kryptografie oder serverseitige Autorität besitzen, kann ein modifizierter Client nicht vollständig ausgeschlossen werden; Revision Chain, Blizzard-Ränge, Owner-Bindung und Konflikterkennung sind die vorhandenen Schutzmechanismen.

## Guild Activity

`guildActivity` verwendet denselben Metadaten-/Offer-/Fetch-/Payload-Pfad wie andere persistente Domains. Objekt-ID ist die Account UUID; übertragen wird ein begrenzter owner-autoritärer Shard mit Revision, unveränderlichem Ursprung, Tages-/Wochenaggregaten und bounded Detail. Einzelne Chat-Nachrichten oder Hot Events werden nicht transportiert. `canShare` und `getRecipients` filtern Metadaten und Payloads über `guild-activity-view`; Import lehnt stale Revisionen und Owner-/Account-/Guild-Abweichungen ab und hält Relay-Provenance getrennt als `receivedFrom`.

## Compatibility und Restschuld

Bestehende öffentliche APIs von Comms, SyncManager, PlayerDataStore und den Stores bleiben erhalten.

Die Autorisierungsprüfung ergibt folgende Abgrenzung:

- `character` transportiert normale ownergebundene Character-Blöcke. Es gibt bewusst kein separates Share-Recht; Payload, Objekt-ID und Owner müssen übereinstimmen, und `PlayerDataStore` erzwingt Provenance sowie Versionsregeln.
- `twinks` transportiert ownerbestätigte Identität und benötigt Owner-/Senderbindung, aber kein allgemeines Share-Recht. `twinkAdmin` verändert dagegen administrative Zuordnungen und bleibt permission-gesteuert.
- `content`, `poi` und `achievements` enthalten gildenweit veränderbare beziehungsweise veröffentlichte Objekte. Create/Edit/Delete/Publish/Award/Revoke bleiben legitime PermissionEngine-Prüfungen.
- `guild-position` ist ausdrücklich sensible, freiwillig aktivierte Live-Standortinformation. `position-share`/`position-view`, direkte Sender-/Owner-Bindung, Gildenkontext und Ablauf bleiben erforderlich.
- `permissions` synchronisiert den administrativen Revision-State und verwendet statt normaler Feature-Rechte Revision Chain, Payloadvalidierung und Blizzard-Gildenleiter-Trust-Anchor.

Produktive Feature-Autorisierung verwendet `PermissionEngine`; der Fallback auf `HolyStorm.Policy` bleibt ausschließlich als Compatibility-Pfad für ältere beziehungsweise isolierte Verbraucher. Normale Character-Daten erhielten kein neues Share-Recht.
