# Whole-map policy validation

`-alife_whole_map` bypasses native distance gates on the loaded map. Script
eligibility, ownership, valid-location checks and group traversal still apply.
The launch policy stays in effect even if a script changes `switch_distance`;
a large configured radius cannot guarantee that. Distance getters/setters continue to expose the normal-mode configuration.
Without the flag, distance behavior is unchanged.

Group traversal has a non-obvious legacy rule: a blocking live member stops
cleanup of later corpses, while the group's own permission may still allow the
final offline switch. The policy must not reorder those effects.

Configure this directory with CMake, build and run CTest (Python 3 and C++17).
The fixtures extract production methods and assert policy outcomes in both modes,
including distance boundaries, eligibility, cleanup and group member order.

For game validation, package a Release build as `<install>/bin_whole_lifecycle`
with its DLLs and a `build.json` containing `baseCommit`, executable `sha256`,
`configuration: Release`, and `tracyEnabled: false`. Use a separate installation
with the original SoC resources and a Bar save at
`seeds/bar-2026-10-03/savedgames/bar_center.sav`, plus its user settings.
`runtime/Prepare-RegularValidation.ps1 -BaselineRoot <baseline> -InstallRoot <new-install>`
creates that isolated resource/script copy from a prepared baseline. It must not
be used on an existing installation.

From the runtime directory:

```powershell
./Run-RegularValidation.ps1 -InstallRoot $install -Count 400 -Eligibility -SaveSnapshot
./Run-RegularValidation.ps1 -InstallRoot $install -VerifySession $firstSession -SeedAppData $relativeAppdata -SaveName regular_validation
./Run-RegularValidation.ps1 -InstallRoot $install -Count 100 -DistanceControl -Mode distance
./Run-RegularValidation.ps1 -InstallRoot $install -Count 100 -DistanceControl -Mode whole-map
./Run-RegularValidation.ps1 -InstallRoot $install -Transitions
python Summarize-Regular.py $firstSession
```

The verification session needs `$relativeAppdata` pointing from the installation
to the first session's `appdata`. Each run uses private saves; the transition test
must run alone. Population tests support both modes. `-DistanceControl` sets the same 20 m switch
distance in each mode and checks distant NPCs throughout the measurement window.
The transition probe creates a distant NPC on each arrival and checks its server
and client state after settling. These controls test policy, not default-distance performance. `BudgetMs` limits the Lua driver's spawn batches, not
engine activation. Session manifests record the executable and save hashes.
These tests establish functional behavior, not broad campaign compatibility.

The independent registry-teardown fix is intentionally absent from this branch.
Native populated-group shutdown coverage belongs to that fix; this policy must
not be described as fixing the pre-existing teardown bug.

Historical reports, preparatory refactors, native diagnostic patches and older
package runners are preserved on
[archive/alife-experiments-2026-10-04](https://github.com/vvsotnikov/OGSR-Engine/tree/archive/alife-experiments-2026-10-04/tools/profiling).
