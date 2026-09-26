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

## Login-Presence, Versionen und Diagnose

Nach einem echten `PLAYER_LOGIN` sendet jeder Client genau eine verzögerte
Guild-Presence mit Semantic Version und Session-ID. Gegenstellen antworten mit
einer kleinen Whisper-Presence. Erkannte Versionen bleiben sitzungslokal und
werden in der Gildenliste angezeigt. Erst nachdem die eigene Presence erfolgreich
an die gedrosselte Transportqueue übergeben und eine Peer-Version empfangen wurde, vergleicht der Client die
Versionen nach SemVer; ein Hinweis auf eine neuere Version erscheint höchstens
einmal pro Login-Sitzung.

Ein fachlicher Sync-Vorgang kann auf dem Transport in mehrere Pakete
fragmentiert werden. Dadurch entstehen kurze Task-Bursts mit mehreren
`Sync.Send`-/Comms-Einträgen; zusätzlich können beim Login Presence sowie je
Domain Discovery/Offer gleichzeitig anfallen. Das ist kein Character-Ping-Pong:
nur lokale `HS_PLAYERDATA_OWNED_UPDATED`-Ereignisse publizieren erneut, während
akzeptierte Remote-Blöcke ausschließlich das Remote-Update-Ereignis auslösen.
Die bestehende Transportdrosselung und Paketierung bleiben unverändert.

Strukturierte Sync-/Comms-Diagnosen beschreiben Richtung, Sender, Empfänger,
Kanal, Domain, logisches Objekt und Character/Block, Nachrichtenklasse und
-typ, Version, Grund, Request-/Transmission-/Correlation-ID sowie
Original-Owner, Relay- und Retry-Kontext. Payload-Inhalte werden nicht geloggt.

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
