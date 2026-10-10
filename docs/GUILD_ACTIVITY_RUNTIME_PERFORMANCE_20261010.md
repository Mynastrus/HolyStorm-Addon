# Guild Activity runtime performance / Laufzeit-Performance

## Deutsch

### Bestätigte Ursache und Aufrufkette

`RaidActivity` und `MythicPlusActivity` rufen `GuildActivity:Submit` aus Blizzard-Events auf. `Submit` stellt `GuildActivity.Capture` in die zentrale TaskManager-Queue. Der Task normalisiert und validiert den Fakt, liest den Account-Shard, aktualisiert Aggregate und ruft `CommitShard` auf.

Vor der Korrektur rief `ActivityStore:PutShard` eine DataManager-Transaktion für den Guild-Unterbaum auf. Der DataManager kopierte dafür den vollständigen Schema-Root `guildManagement.activity` in einen Arbeitsstand und nochmals für den Commit, verglich die Roots rekursiv und kopierte das Ergebnis zurück. Die Kosten wuchsen damit mit den Aktivitäten aller Gildenmitglieder, obwohl ein Capture nur einen Account änderte. Der DataManager-Deep-Copy-Pfad ist der konkrete teure Pfad hinter den installierten Datenbank-Frames; die dortigen Zeilennummern passen nicht zwingend zum aktuellen Checkout.

Nach erfolgreichem Commit wurde synchron `HS_GUILD_ACTIVITY_UPDATED` ausgelöst. `ActivityPoints:ReconcileAccount` lud daraufhin den vollständigen Account-Shard und spielte alle Detailereignisse und Chat-Tagesaggregate erneut durch. Auch ein einzelner neuer Fakt konnte so die gesamte erhaltene Historie und Punkte-Persistenz bearbeiten. Ein importierter Shard konnte zudem sowohl über `UPDATED` als auch über `SYNCED` erneut reconciled werden.

Der TaskManager führt weiterhin genau eine globale Queue und dispatcht einen Task-Callback synchron. Seine Queue-Suche ist budgetiert, der aktive Callback wird jedoch nicht unterbrochen. Im aktuellen Checkout ist `TaskManager.lua:61` eine feste Diagnosefeld-Projektion; sie traversiert keine Aktivitätshistorie. Ohne exakt dieselbe installierte Add-on-Version lässt sich der dort gemeldete Zeilenverweis nicht genauer zuordnen. Die überlange Arbeit lag im synchronen Capture-/Eventpfad, der innerhalb des TaskManager-Dispatchs ausgeführt wurde.

### Korrektur

- `GuildActivityStore` und `GuildActivityPointsStore` persistieren über ihren registrierten DataManager-Eigentümer. Sie kopieren nur den zu ersetzenden Shard beziehungsweise einen neuen Punkte-Ledgereintrag und ändern keine fremden SavedVariables.
- Die Aktivitätszusammenfassung projiziert nur skalare Lifetime-Werte; sie kopiert nicht mehr die Character-Lifetime-Tabelle, um sie danach zu löschen.
- Doppelte Detail-IDs werden über eine gezielte DataManager-Existenzabfrage erkannt, bevor der Account-Shard geladen oder eine Revision erhöht wird.
- `HS_GUILD_ACTIVITY_UPDATED` behält sein erstes Argument und kann zusätzlich einen Detail- oder Chat-Aggregat-Delta liefern. Punkte verarbeiten lokale Deltas einmal. State-only-Änderungen lösen keine Historien-Reconciliation aus. Importierte Shards behalten die vollständige Reconciliation über `HS_GUILD_ACTIVITY_SYNCED`.
- Automatische Punkte-Ledgereinträge werden über den Punkte-Store angehängt; dafür wird kein kompletter Punkte-Datenbank-Root transaktional kopiert.
- Eine vollständige Punkte-Reconciliation liest zuerst nur Regeln und Account-IDs. Ohne aktive Regel wird die Historie nicht geladen; mit aktiven Regeln wird nur der gerade bearbeitete Account-Shard kopiert.

### Messung und Tests

`tools/test_guild_activity.lua` baut reproduzierbar 50 weitere Account-Shards mit je 45 Details sowie einen Capture-Ziel-Shard mit 1.200 Details und 12 Character-Identitäten auf. Beim Capture zählt das Fixture die kopierten Lua-Tabellenknoten und vergleicht sie mit der Größe des gesamten Guild-Roots. Der aktuelle Lauf ergab **4.933 kopierte Knoten über 8 Kopien** bei **7.667 Knoten im gesamten Root**. Die vorherige DataManager-Transaktion hätte bereits für ihre zwei vollständigen Root-Kopien mindestens 15.334 Knoten kopiert, zusätzlich zum rekursiven Gleichheitsvergleich und dem zurückgegebenen Guild-Unterbaum. Das ist ein reproduzierbarer struktureller Offline-Vergleich, keine WoW-Zeitmessung.

Der Regressionstest deckt außerdem kleine Captures, wiederholte identische Tasks, einen Trigger während des laufenden Captures, keine Event-Rekursion, stabile Revisionen bei Duplikaten, geänderte Persistenz, fehlerhafte Snapshots, Punkte-Deltas, Queue-Konkurrenz und optionale Provider ab. `tools/test_task_workflow.lua` prüft weiterhin Continuations, Queue-Fairness gegenüber wartenden Tasks, Retry, Timeout und Workflow-Coalescing.

### Restpunkte

Capture und vollständige Shard-Validierung bleiben ein synchroner Task-Schritt. Sie sind durch die bestehenden Grenzen für Details und Zeit-Buckets begrenzt, aber nicht durch WoW unterbrochen. Eine vollständige Reconciliation nach Aktivierung einer Regel oder einem Sync kann weiterhin Details aller Accounts durchsuchen; sie vermeidet jetzt den Guild-weiten Shard-Copy, und ohne aktive Punkte-Regel wird sie beim Start übersprungen. Eine echte WoW-Runtime-Validierung und Messung unter realen SavedVariables steht aus; die Offline-Regression belegt daher die entfernten vollständigen Root-Kopien und Replays bei jedem Capture, nicht die vollständige Beseitigung jedes möglichen `script ran too long` in der Spielruntime.

## English

### Confirmed cause and call path

`RaidActivity` and `MythicPlusActivity` call `GuildActivity:Submit` from Blizzard events. `Submit` queues `GuildActivity.Capture` on the central TaskManager queue. The task normalizes and validates the fact, reads the account shard, updates aggregates, and calls `CommitShard`.

Before the fix, `ActivityStore:PutShard` used a DataManager transaction on the guild subtree. The DataManager copied the complete `guildManagement.activity` schema root into a working value and again for commit, recursively compared the roots, and copied the result back. Work therefore grew with every member's activity even though a capture changed one account. The DataManager deep-copy path is the concrete expensive path behind the installed database frames; installed line numbers may differ from this checkout.

After each successful commit, `HS_GUILD_ACTIVITY_UPDATED` ran synchronously. `ActivityPoints:ReconcileAccount` then loaded the complete account shard and replayed all detail events and daily chat aggregates. One new fact could therefore revisit the entire retained history and write points persistence. An imported shard could also be reconciled through both `UPDATED` and `SYNCED`.

The TaskManager still owns one global queue and dispatches one task callback synchronously. Queue scanning is budgeted, but the active callback is not preempted. In this checkout, `TaskManager.lua:61` is a fixed diagnostic-field projection; it does not traverse activity history. Without the exact installed add-on version, the reported line reference cannot be mapped more precisely. The long work was in the synchronous capture/event path invoked by TaskManager dispatch.

### Fix

- `GuildActivityStore` and `GuildActivityPointsStore` persist through their registered DataManager ownership contracts. They copy only the shard being replaced or a new points ledger entry and do not manipulate another module's SavedVariables.
- Activity summaries project scalar lifetime values and no longer copy a per-character lifetime table just to discard it.
- Duplicate detail IDs use a targeted DataManager existence check before loading the account shard or advancing its revision.
- `HS_GUILD_ACTIVITY_UPDATED` keeps its first argument and may include a detail or chat-aggregate delta. Points process local deltas once. State-only changes do not replay history. Imported shards retain full reconciliation through `HS_GUILD_ACTIVITY_SYNCED`.
- Automatic points ledger entries append through the points store without a transactional copy of the complete points database root.
- Full points reconciliation reads rules and account IDs first. It skips history entirely when no rule is enabled and copies only the current account shard when active rules exist.

### Measurement and tests

`tools/test_guild_activity.lua` reproducibly creates 50 additional account shards with 45 details each and a capture target shard with 1,200 details across 12 Character identities. During capture, the fixture counts copied Lua table nodes and compares them with the complete guild root. The current run reported **4,933 copied nodes across 8 copies** against **7,667 nodes in the full root**. The previous DataManager transaction would have copied at least 15,334 nodes for its two full-root copies alone, plus the recursive equality comparison and returned guild subtree. This is a reproducible structural offline comparison, not a WoW timing measurement.

The regression also covers small captures, repeated identical tasks, a trigger during an active capture, absence of event recursion, stable revisions for duplicates, changed persistence, invalid snapshots, points deltas, competition in the global queue, and optional providers. `tools/test_task_workflow.lua` continues to cover continuations, queue access by waiting tasks, retry, timeout, and workflow coalescing.

### Remaining validation

Capture and complete shard validation remain one synchronous task step. Existing detail and time-bucket limits bound the work, but WoW does not preempt it. Full reconciliation after enabling a rule or importing a synced snapshot can still scan details across accounts; it now avoids the guild-wide shard copy and is skipped at startup when no points rule is enabled. A real WoW runtime check and measurement against live SavedVariables remain necessary. Offline regression confirms removal of full-root copies and per-capture history replays; it does not prove that every possible `script ran too long` in the game runtime is eliminated.
