# A-Life experiment and profiling

## Current branch scope

The core branch contains whole-map policy, optional metrics and lifecycle refactors. Scheduler compaction from merged [PR #7](https://github.com/vvsotnikov/OGSR-Engine/pull/7) is always enabled. Scheduler callback-removal, exception-cleanup and DEBUG membership fixes are integrated from [PR #9](https://github.com/vvsotnikov/OGSR-Engine/pull/9); review that dependency before merging this branch. Deferred activation remains separate in draft [PR #8](https://github.com/vvsotnikov/OGSR-Engine/pull/8). Historical packages and dated reports may contain earlier combinations of features; they are retained as evidence, not instructions to reproduce the current build.

Script installation/tool paths are explicit required parameters. Set `$install` and `$tracy` to your local directories; no developer-specific defaults are used. Private `.cmd` launchers can supply those arguments. `Prepare-RegularValidation.ps1` likewise requires `-BaselineRoot` and `-InstallRoot`.

The dynamic-policy and reconciliation fixtures carry frozen pre-refactor reference bodies alongside their tests. Their source commits are provenance comments only: builds work from a source archive without `.git`. Current code is selected by explicit unique region boundaries, not brace counting. Update those boundaries deliberately when refactoring the tested regions.

Optional metrics and offline-inventory diagnostics are compiled into the engine and activated with flags. Additional high-volume instrumentation is kept in the archived diagnostic patches. These are distinct; the engine is not free of diagnostic code.

The experimental engine accepts these launch-only flags:

- `-alife_whole_map`: distance no longer prevents online switching on the loaded level. Without it, the original distance policy applies. Distance getters, setters and configuration still describe the normal-mode distance setting; this flag overrides native distance gates without rewriting that setting. Scripts that independently use the distance value still see the configured value.
- `-alife_metrics`: log population and cumulative spawn/removal counts once per game second, plus total switch/scheduled work during that sample. The same measurements are published as Tracy plots when profiling is compiled in.
- `-alife_diagnostics` with `-alife_metrics`: list living offline entities on the tenth metrics sample, then every 30 samples. Includes identity, parent/group, eligibility, configuration match, AI-location use and graph/node IDs. Use `Capture-Session.ps1 -Diagnostics` to enable it. Exclude these runs from performance comparisons because logging adds work.

This is an experimental distance-policy change, not a completed whole-map simulation implementation. Script eligibility, parent ownership, group logic, location validation and existing switch budgets remain in force. Off-map registries are unchanged. The living counters count server creature entities excluding the actor, not a guaranteed count of distinct visible NPCs: group representatives and script-disabled entities require inspection. Save/load, level transitions and campaign behavior still need broader testing.

## Build the tools

Run `Build-TracyTools.ps1 -ToolRoot <tools-directory>` from PowerShell with Git, CMake and VS 2022 C++ build tools available. It builds capture, CSV export and our frame/zone projection utility. Tracy is pinned to upstream commit `4a5a21cdb08c3b554bf1857b4f2f33d7f7db0207`; its version, protocol and queue headers match the embedded client. OGSR has other client modifications, so this is a compatibility match, not a claim that every client source file is identical. Both reading the original GUI trace and recording a live engine session have been tested.

## Record

Package the profiling engine under `<install>/bin_experiment`. The installation needs `fsgame-profiler.ltx` and the original SoC resources. The default seed settings/save come from `<install>/_appdata_profiler_`.

```powershell
./Capture-Session.ps1 -InstallRoot $install -ToolRoot $tracy -Mode distance
./Capture-Session.ps1 -InstallRoot $install -ToolRoot $tracy -Mode whole-map
```

Exit the first game before launching the second. Each run copies the same seed save and settings into a unique `captures/<timestamp>-<mode>/appdata` directory. It disables the loading-screen key gate in that copy only. Recording starts after 30 seconds and ends after 60 seconds, or earlier at the capture memory limit (20% of physical RAM). The game stays open. The manifest records the save and executable hashes, command line, capture status and optional packaged build provenance. Do not change the seed save between the two runs.

Keep the game in the foreground, start walking once the save loads, and repeat the same route. Timing starts at launch plus the selected delay, not at an automatically detected gameplay marker. Longer loading times, menus and alt-tab can therefore contaminate the interval; inspect the logs/trace. `-DelaySeconds`, `-Seconds`, `-MemoryPercent`, and `-SaveName` are configurable. Do not open the Tracy GUI during recording: only one collector should connect. The recorder saves automatically; there is no manual Save dialog.

## Analyze

```powershell
& <tools>/bin/ogsr-trace-summary.exe <capture.tracy> <output-prefix>
./Summarize-Timeline.ps1 -Prefix <output-prefix> -StartSeconds 120 -EndSeconds 360
```

Choose interval boundaries for the particular trace; 120–360 seconds is the selected interval for the original baseline, not a universal setting. The projection exports complete frame markers and selected inclusive CPU zones. The summary uses nearest-rank percentiles and excludes events crossing the interval boundaries. It does not classify menus or pauses automatically. Zone durations include nested work and descheduling, and concurrent worker totals cannot be added as frame time. A-Life work migrating among workers does not mean individual entities are updated concurrently.

The original full capture used about 50 GB of collector RAM; two rendering zones alone recorded over 500 million calls. Short captures limit storage/memory but do not eliminate instrumentation overhead. Compare identical profiling builds and later validate performance gains in a non-profiling build. Use the GUI for detailed causal inspection of slow frames.

For large zone projections, `python Summarize-TraceStream.py <prefix> <start-seconds> <end-seconds>` uses the standard library and avoids materializing millions of row objects. It produces `<prefix>-stream-summary.json` with the same frame/zone statistics and selection rules (without the PowerShell helper's histogram).

## Population stress

For a clean non-Tracy Release executable driven by private Lua test scripts, see `REGULAR-2026-10-03.md`. `Prepare-RegularValidation.ps1` creates a separate resource/test installation; `Run-RegularValidation.ps1` handles isolated runs and `Summarize-Regular.py` validates the evidence. `Start-RegularGame.ps1` instead launches the ordinary installation with private saves and no Lua driver, for manual play.

See `CADENCE-2026-10-03.md` for per-stalker deadlines, actual callback intervals, zero-update detection and a separate 20-fighter combat scenario. Its separate `bin_cadence` build uses `cadence-diagnostic.patch`, `CadenceStress.inl` and `SchedulerProbe.h`. Run the population harness with `-Cadence`; add `-Combat -Counts 20` for the encounter. `Summarize-Cadence.py` analyzes the buffered evidence without loading a Tracy trace. Do not combine the cadence and older stress diagnostic patches.

See `STRESS-2026-10-03.md` for the dispersed Bar population sweep and detailed CPU-scope evidence. The stress hook is deliberately a separate diagnostic build: apply `stress-diagnostic.patch`, copy `StressValidation.inl` into `ogsr_engine/xrGame/`, build, and package into `bin_stress` with matching PDB/provenance. Do not combine it with the persistence diagnostic hook or deploy it as the normal playtest binary. `Run-PopulationStress.ps1` uses fresh private Bar save copies, spawns 0–400 extra generic stalkers, records buffered frame samples, and quits. `-CaptureTrace` records an additional detailed run; exclude connected-Tracy runs from the untraced comparison. The original save is never modified.
