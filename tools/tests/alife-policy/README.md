# Whole-map policy validation

`-alife_whole_map` is experimental; campaign compatibility and performance
acceptance are not established. It bypasses native distance gates on the loaded map. Script
eligibility, ownership, valid-location checks and group traversal still apply.
The launch policy stays in effect even if a script changes `switch_distance`;
distance setters store values for normal mode but do not control switching while
the flag is active. The first setter call after construction reports that fact.
Without the flag, distance gates and switching-permission decisions are unchanged.
Legacy-group iterator, activation-dispatch and ownership repairs apply in both modes.

Distance-mode group traversal has a non-obvious legacy rule: a blocking live member stops
cleanup of later corpses, while the group's own permission may still allow the
final offline switch. The policy must not reorder those effects.
Whole-map legacy groups instead reconcile every member. Both group and member
must permit activation; both must permit deactivation. Conflicting denials retain
the member's existing state. Excluded members do not prevent eligible siblings
from activating, and a living member cannot postpone cleanup of later corpses.
The server-only owner is online while any retained member is online. Indirect
members have no independent simulation registry entry until detached from the
group; releasing a member must remove its membership before its ID can be reused.

Configure this directory with CMake, build and run CTest (Python 3, PowerShell, and C/C++17 compilers).
The engine and tests compile `alife_switch_policy.h` directly. Operations bind
real engine objects and registries in the engine and controlled state in tests.
No method text or engine class declarations are copied into the fixtures.
The tests cover distance boundaries, eligibility, cleanup and group member order;
real registry effects and client construction require native scenarios. The
controlled-operation tests do not compile the engine adapters. Release, Tracy and Debug
builds compile those adapters; native scenarios exercise their effects only for
the object types used by each scenario.

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
Whole-map runs require the experimental startup message for every loaded map.
Scenarios that change switching distance also require exactly one override
message per map; normal-mode runs must contain neither message.

Package metadata identifies the built engine. The separate checkout-at-launch
fields identify the runner checkout, which may differ from the package source.
Unavailable Git metadata is `null`, including dirty state; it must never be
interpreted as a clean checkout. A valid detached snapshot revision is retained.

`runtime/Run-GroupValidation.ps1` tests a saved `ON_OFF_G` with one living member
in both modes. It verifies membership and near-to-far transitions (online to
offline in distance mode, retained online in
whole-map mode), both group permission
changes, client presence and member removal on death. It requires a seed using
the `validation_online_group` section and known group/member IDs; it creates
that section only in a private copy of the loose game configuration. The seed
used for local evidence was created by the archived native group fixture in
`archive/alife-experiments-2026-10-04:tools/profiling/GroupCleanupValidation.inl`.
The forced-online phase requires a distant member; only distance mode distinguishes
that permission override from normal whole-map activation. Each run copies the
entire loose `gamedata` tree into its private session, consuming the same disk
space as that tree; game archives are hard-linked.
This scenario does not exercise the separate legacy `flesh_group` adapter (#18).

`runtime/Run-LegacyGroupValidation.ps1` uses a private four-member `AI_FLE_G`
fixture. Its setup writes serialized membership and indirect-control flags, saves
and exits; only a fresh process may test that save, after native registries have
been reconstructed. Fixture members are immune to incidental combat; scripted
death still uses native `kill()`. These sections and saves never alter the user's
installation. The packet helper is specific to this small fixture and the current
legacy serialization layout.

```powershell
./Run-LegacyGroupValidation.ps1 -InstallRoot $install -Package $debugPackage -SeedAppData $barSeed -SaveName bar_center -Stage setup -Mode distance
./Run-LegacyGroupValidation.ps1 -InstallRoot $install -Package $debugPackage -SeedAppData $fixtureAppdata -Stage policy
./Run-LegacyGroupValidation.ps1 -InstallRoot $install -Package $debugPackage -SeedAppData $policyAppdata -SaveName legacy_group_result -Stage verify
./Run-LegacyGroupValidation.ps1 -InstallRoot $install -Package $debugPackage -SeedAppData $fixtureAppdata -Stage control -Mode distance
./Run-LegacyGroupValidation.ps1 -InstallRoot $install -Package $debugPackage -SeedAppData $fixtureAppdata -Stage control -Mode whole-map
./Run-LegacyGroupValidation.ps1 -InstallRoot $install -Package $debugPackage -SeedAppData $fixtureAppdata -Stage roundtrip
./Run-LegacyGroupValidation.ps1 -InstallRoot $install -Package $debugPackage -SeedAppData $fixtureAppdata -Stage ownership
```

The legacy runner defaults to an assertion-enabled Debug package and checks its
manifest and executable hash. Appdata arguments are relative to the installation;
each preceding run prints its private session path. Roundtrips use technical
`jump_to_level` transitions (Bar → Garbage → Bar twice), including an excluded
offline member; this does not test walking through campaign exits. Distance
controls preserve the inherited near-group churn and require distant members to
stay offline. Whole-map controls require persistent clients in both intervals.

```powershell
./Run-GroupValidation.ps1 -InstallRoot $install -Package $package -SeedAppData $groupSeed -Mode distance -GroupId 22016 -MemberId 22017
./Run-GroupValidation.ps1 -InstallRoot $install -Package $package -SeedAppData $groupSeed -Mode whole-map -GroupId 22016 -MemberId 22017
```

`-PrepareOnly` validates the package and writes the private session inputs without
starting the engine. The `regular-prepared` or `group-prepared` status is not gameplay evidence.

Registry teardown and switching-budget fixes are inherited from main. Their
tests remain separate from this policy's fixtures; the whole-map flag does not
itself fix lifecycle or budget defects.
