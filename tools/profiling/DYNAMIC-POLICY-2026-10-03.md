# Standard dynamic-object maintenance and switching policy

## Change

The standard `CSE_ALifeDynamicObject` path now separates offline scheduling maintenance (`maintain_offline_schedule`) from online eligibility (`evaluate_online_switch`) and offline eligibility (`evaluate_offline_switch`). The existing virtual `try_switch_*` entry points compose these operations and apply transitions or saved-client-data cleanup.

Online evaluation returns denied, outside-distance or activate, retaining the distinction needed for the existing Debug messages. Offline evaluation preserves the original comparisons, including boundary and non-finite distance behavior. Scheduling still runs before online eligibility is read, including when an object remains denied or pending. The manager's additional saved-data and activation-cancellation logic is unchanged. No new object fields, serialized data or virtual methods are introduced.

This is a behavior-preserving extraction, not a performance optimization. No recurring work is skipped and no cached/event-only decision is enabled. Evaluation methods contain eligibility queries only; their virtual query implementations must still be considered before using them as a cacheable interface. These helpers describe the standard dynamic-object policy, not a universal policy for group overrides.

## Evidence from production methods

`dynamic-policy-test/Generate.py` extracts the original online/offline methods from commit `0924e934b` and the current methods and helpers directly from engine source. Only the method declaration's class name is rewritten; Debug message strings remain unchanged. Production control flow is compiled against deterministic mock operations.

Both Release-style and Debug-enabled fixtures pass 18,432 comparisons each (36,864 total), comparing operation logs, scheduling membership, online state, eligibility changes and saved client data. Cases cover schedulable/non-schedulable objects, `need_update` and current registry membership, online/offline permissions, whole-map/distance mode, saved-data retention, pending/immediate activation, mutation during scheduling, empty/nonempty data and nine distances including exact thresholds, infinity and NaN. The mock activation queue checks dispatch/retention behavior at this boundary; it does not replace the separate production queue lifetime tests.

The initial Debug fixture failed because its generator also renamed class names inside diagnostic strings. Restricting substitution to the signature fixed the fixture; engine behavior did not change. Existing manager-ordering and production activation-queue fixtures, regular/reconciliation analyzer tests and PowerShell parsing also pass.

## Remaining event dependencies

Native eligibility is more than the two switching flags. `CSE_ALifeObject` queries configuration matching; creature offline eligibility also reads health, and ammunition offline eligibility reads remaining rounds. Offline scheduling depends on direct control, AI-location use, online state and, for monsters, health. Notifications restricted to flag setters would miss these inputs.

Legacy `CSE_ALifeGroupAbstract::try_switch_offline` still interleaves live-member checks with dead-member detach/registry repair and can stop before later dead members are reached. Its loop remains unchanged. `CSE_ALifeOnlineOfflineGroup` also retains its member iteration, validation and position selection before calling the inherited standard path. Skipping either group's virtual method based only on group flags would be incorrect.

Next work should characterize legacy-group ordering with real-method fixtures before extracting its cleanup. Only then should an event implementation shadow the scanner, covering registry membership, health/ammunition/configuration changes and direct mutable Lua writes or retaining a fallback for them. The existing scanner remains authoritative throughout this increment.

## Build and runtime validation

Release/x64 succeeded without `TRACY_ENABLE` in the xrGame compile commands. The separate package `D:/Games/OGSR-Regular-Validation/bin_dynamic_policy` retains the executable, matching PDB/DLLs, build log and engine source patch against `0924e934ba2343ae581f796b7ae364020b379ce8`. Executable SHA-256: `6A48A7A09AFC8893F4DB9BFD67C6E14545764B2F2BF60E35BADD73F36AD49A57`.

Reproduce the standalone comparisons with CMake under `tools/profiling/dynamic-policy-test`. The regular runner accepts `-Package bin_dynamic_policy`; runtime session evidence is recorded below.

Sessions are retained under `D:/Games/OGSR-Regular-Validation/captures`:

- `2026-10-03_17-36-09-618-whole-map`: all five eligibility phases passed; all 400 spawned IDs stayed registered, online and client-present throughout measurement. Living counts ranged from 395 to 400; retention includes corpses and is not a claim that no NPC died. A pending save with 336 offline IDs and a final save were acknowledged; the process exited normally. This bulk-creation/save fixture is not a performance comparison.
- `2026-10-03_17-38-15-089-whole-map`: a fresh process loaded that pending save and verified all 400 recorded IDs online/client-present at each steady-state census, then exited normally. Source and copied pending-save SHA-256 match: `170239289967FEBC4D066986FB7896FFAADA182AB3CE15B851ABF3F113AA8E22`. This verifies object activation/retention, not byte-for-byte preservation of every script or inventory field.
- `2026-10-03_17-39-53-979-distance`: normal distance mode, no activation queue and no extra population, completed the regular driver and acknowledged its final save. It is a load/run/save smoke test; distance-boundary behavior is covered by the extracted-method fixture rather than a moving-player route.
- `2026-10-03_17-41-20-649-whole-map`: the controlled Bar → Garbage → Bar fixture acknowledged all three destinations in order, saved `reconcile_roundtrip` and exited normally. As documented in the reconciliation report, this fixture uses artificial jumps and god mode to isolate loading from survival; it does not replace a natural campaign transition test.

The manual-play executable and original Bar seed hashes remain unchanged. No player replay is required for this extraction. No throughput or stutter improvement is claimed.
