# Whole-map persistence and technical transitions

The diagnostic sequence completed save, same-process reload, Bar-to-Garbage-to-Bar console jumps, and normal shutdown. A separate process then loaded the newly created save and exited normally (exit code 0). No fatal assertion or script-error marker appeared. Both logs contain an OpenAL extension `Invalid Enum` warning at startup; this is not a clean-warning-free claim.

## Evidence

Sessions below are under `D:/Games/OGSR-Baseline/captures/`:

- `2026-10-03_11-12-11-367-whole-map`: save/reload and two console transitions; 13 complete world snapshots.
- `2026-10-03_11-14-23-807-whole-map`: fresh-process load; 3 snapshots, exit code 0.

The first session's harness initially failed because the live log requires read/write sharing. It resumed the same process before any command had been sent, with shared file reading. Its process exit code is unavailable because the resumed harness attached with Get-Process; the explicit quit marker and orderly renderer/device teardown are the shutdown evidence. An earlier session `2026-10-03_11-10-50-535-whole-map` tested startup and quit but its harness expected an untimestamped log name. It is not included in the persistence results.

The separate `bin_validation` package contains matching binaries, PDB, build log and source patch, based on commit `96fe9ec89`. Executable SHA-256: `F42120EC959EDF783BB69E076C469E16D5B0CAEBAE70819077182B7C26AB19F2`. Build completed successfully using ReleaseTracyProfiler. No Tracy collector was connected; these verbose runs are not performance measurements. The paired-test `bin_experiment` and original Bar seed hashes remain unchanged.

New save `validation_bar.sav` SHA-256: `14290532D6A7E1847A76E492ADBD48AB48C36CC0EBD2ACBDE00280391DA5B248`.

## Identity and state results

| Comparison with post-save snapshot | Before | After | Missing IDs | Added IDs | Changed recorded fields |
| --- | ---: | ---: | ---: | ---: | --- |
| First same-process reload snapshot | 1,697 | 1,697 | 0 | 0 | 30 graph vertices |
| First fresh-process snapshot | 1,697 | 1,697 | 0 | 0 | 30 graph vertices |
| Final Bar-return snapshot | 1,697 | 1,701 | 0 | 4 | 83 graph vertices, 13 health values, 11 level IDs |

The first snapshots from both reload methods are identical across every recorded entity field, including online state. All 1,697 pre-reload creature IDs, sections, health values, flags, parent IDs and group IDs match. The comparison baseline was sampled after saving, rather than at the serialization boundary; graph differences against that baseline do not establish corruption. Reload restores an earlier simulation time. The two reload methods produce exactly the same recorded graph values.

Across all 16 complete snapshots, there are no repeated IDs and no online creatures assigned to a different map than the currently loaded map. Observed loaded level IDs are Bar 7, Garbage 2, then Bar 7. This checks creature server registry entries (including dead creatures and actor), not every item, script table, client instance or conceptual NPC identity. A keyed registry naturally prevents duplicate keys; absence of repeated keys alone cannot exclude a duplicate character created under a new ID.

The four added IDs after the round trip and changes in health/position occurred while the simulation ran. Their exact causes were not individually traced; these checks do not prove campaign equivalence or absence of unintended new spawns.

All ten previously investigated travelers are still present at the end, offline and with health 1.0. IDs 19200, 19209, 19217 and 19227 are on level 11 (map name not independently resolved here). IDs 20736, 20746, 20753, 29952, 29960 and 29966 are on Garbage (level 2).

## Reproduction and remaining validation

`persistence-diagnostic.patch` is temporary instrumentation, not applied to the gameplay source. It adds an opt-in `-alife_validation` main-thread numbered command-file reader and creature-world inventories every ten metrics samples. It only allows the validation save/load names, the two selected level jumps, and quit. Publish command files atomically inside the private session appdata. Build/package this patch separately before using `Run-PersistenceValidation.ps1`; do not package the repository's current bin_x64 output as an unmodified gameplay build.

Run `Read-WorldValidation.ps1 -Session <session>` for each completed run, then `Compare-WorldValidation.ps1 -Session <first> -RestartSession <second>`. Each session retains raw logs, full snapshots and summaries; the first also contains detailed field comparisons. These sampled diagnostics are not serialization-boundary assertions.

Still required: a natural level-changer pass, conversation/task completion, and a scripted encounter in whole-map mode. Console jumps exercise the engine's transition/save/load path but bypass the trigger and its surrounding script conditions. Long campaign timing, non-creature persistence and duplicate characters under distinct IDs remain unproven. DirectInput failure-path injection is separately pending.
