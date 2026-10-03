# Ten Bar entities: cross-map travel

The ten initial online removals are NPC cross-map movement, not deletion by the removal operation. All ten debugger call stacks follow the same movement/teleport path. This explains the local population decrease; it does not establish long-term campaign equivalence.

## Identities

| IDs | Sections | Source graph vertex |
| --- | --- | ---: |
| 19200 | ros_killer_respawn_1 | 1246 |
| 19209, 19217 | ros_killer_respawn_2 | 1246 |
| 19227 | ros_killer_respawn_4 | 1246 |
| 20736, 20753, 29966 | bar_stalker_respawn_4 | 1307 |
| 20746, 29952, 29960 | bar_stalker_respawn_3 | 1307 |

All ten had health 1.000 at removal. A temporary ReleaseTracyProfiler build logged their identities at game_ms 13511 in session `2026-10-03_10-43-52-182-whole-map`. It reproduced the ten removals. Its separate package is `bin_lifecycle`; the paired-playtest `bin_experiment` was not replaced. Build log, matching PDB and patch are preserved. Built-in stack collection failed with symbol initialization error 87; those stack attempts are not evidence of the caller.

## Independent debugger confirmation

Session `2026-10-03_10-45-16-486-whole-map` captured the first caller with CDB and the matching paired-playtest PDB. Session `2026-10-03_10-48-30-059-whole-map` then captured all ten IDs and stacks using `Trace-Lifecycle.cdb`. The ID sets match exactly. The debugger detached on the tenth breakpoint; the game resumed afterward. These runs used the original paired-test executable, not the diagnostic modification.

Call chain, oldest to newest:

`CMovementManager::process_game_path -> CMovementManager::teleport -> xrServer::OnMessage -> xrServer::Process_event -> game_sv_Single::teleport_object -> CALifeUpdateManager::teleport_object -> CSE_ALifeDynamicObject::switch_offline -> CALifeSwitchManager::remove_online`

In `movement_manager_game.cpp`, the relevant `ePathStateContinueGamePath` branch compares the current and intermediate game vertices' level IDs and invokes teleport when they differ. In `alife_update_manager.cpp`, `teleport_object` switches an online object offline, calls `graph().change` to move its registry entry to the destination graph vertex, then updates its node/position and monster next-graph ID. It does not call release. `CALifeGraphRegistry::change` removes the old graph entry, adds the destination entry and changes the object's graph ID.

Thus these ten cease contributing to the current Bar registry's count when their travel proceeds to another level. This is existing cross-map movement code reached after their earlier online activation. Exact destination levels and subsequent lifetime were not inspected; do not claim that these tests checked persistence indefinitely or that campaign timing is unaffected.

The diagnostic run also logged unrelated creature release operations elsewhere in the world. Those IDs differ from the ten above. They must not be conflated with the ten Bar online removals.

## Reproduction and limits

`Trace-Lifecycle.cdb` sets a breakpoint at remove_online, prints each server ID and nine stack frames, and detaches after ten hits. Launch CDB with `-y <matching-bin-directory> -cf <commands-file> <engine.exe>` followed by the private session's recorded game arguments. The ten-hit assumption is specific to this preserved Bar seed. The exact temporary instrumentation is retained in `lifecycle-diagnostic.patch`, based on commit f6b117940. It is not applied to the normal source tree; stack-heavy diagnostics must not be used for timing comparisons.

An attempted breakpoint at teleport_object did not capture events in this optimized build; that attempt provides no additional evidence. One earlier debugger launch used an incorrect private fsgame path and exited before loading; it was corrected before the successful debugger runs. Diagnostic sessions were explicitly process-stopped after collecting evidence, not used to validate graceful shutdown.

No gameplay change is warranted merely to keep these ten in the Bar count. Next correctness checks remain player-driven level transitions and save/reload under whole-map mode, with entity identity and script timing tracked. Controlled input-initialization failure testing remains pending.
