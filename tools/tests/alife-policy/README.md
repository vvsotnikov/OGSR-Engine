# Whole-map policy validation

`-alife_whole_map` bypasses native distance gates on the loaded map. Script
eligibility, ownership, valid-location checks and group traversal still apply.
The launch policy stays in effect even if a script changes `switch_distance`;
distance setters store values for normal mode but do not control switching while
the flag is active. The first setter call after construction reports that fact.
Without the flag, distance behavior is unchanged.

Group traversal has a non-obvious legacy rule: a blocking live member stops
cleanup of later corpses, while the group's own permission may still allow the
final offline switch. The policy must not reorder those effects.

Configure this directory with CMake, build and run CTest (Python 3, PowerShell, and C/C++17 compilers).
The fixtures extract production methods and assert policy outcomes in both modes,
including distance boundaries, eligibility, cleanup and group member order.

For game validation, package a Release build as `<install>/bin_whole_lifecycle`
with its DLLs and a `build.json` containing `baseCommit`, executable `sha256`,
`configuration: Release`, and `tracyEnabled: false`. Use a separate installation
with the original SoC resources, its standard `fsgame.ltx`, and a Bar save at
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
distance in each mode and requires 25 consecutive passing samples at the end of a 45-second window.
Earlier samples can observe a delayed switch after an NPC crosses a distance gate.
The transition probe creates a distant NPC on each arrival and checks its server
and client state after settling. These controls test policy. `BudgetMs` limits the Lua driver's spawn batches, not
engine activation. Session manifests record the executable and save hashes.
These tests establish functional behavior, not broad campaign compatibility.

`-PrepareOnly` validates the package and writes the private session inputs without
starting the engine. Its `regular-prepared` status is not gameplay evidence.

The independent registry-teardown fix is intentionally absent from this branch.
Native populated-group shutdown coverage belongs to that fix; this policy must
not be described as fixing the pre-existing teardown bug.
