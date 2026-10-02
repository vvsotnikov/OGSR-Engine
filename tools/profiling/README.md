# A-Life experiment and profiling

The experimental engine accepts two launch-only flags:

- `-alife_whole_map`: distance no longer prevents online switching on the loaded level. Without it, the original distance policy applies.
- `-alife_metrics`: log population and cumulative spawn/removal counts once per game second, plus total switch/scheduled work during that sample. The same measurements are published as Tracy plots when profiling is compiled in.

This is an experimental distance-policy change, not a completed whole-map simulation implementation. Script eligibility, parent ownership, group logic, location validation and existing switch budgets remain in force. Off-map registries are unchanged. The living counters count server creature entities excluding the actor, not a guaranteed count of distinct visible NPCs: group representatives and script-disabled entities require inspection. Save/load, level transitions and campaign behavior still need broader testing.

## Build the tools

Run `Build-TracyTools.ps1 -ToolRoot <tools-directory>` from PowerShell with Git, CMake and VS 2022 C++ build tools available. It builds capture, CSV export and our frame/zone projection utility. Tracy is pinned to upstream commit `4a5a21cdb08c3b554bf1857b4f2f33d7f7db0207`; its version, protocol and queue headers match the embedded client. OGSR has other client modifications, so this is a compatibility match, not a claim that every client source file is identical. Both reading the original GUI trace and recording a live engine session have been tested.

## Record

Package the profiling engine under `<install>/bin_experiment`. The installation needs `fsgame-profiler.ltx` and the original SoC resources. The default seed settings/save come from `<install>/_appdata_profiler_`.

```powershell
./Capture-Session.ps1 -InstallRoot D:/Games/OGSR-Baseline -ToolRoot C:/Users/vladimir/Documents/Codex/tools/tracy -Mode distance
./Capture-Session.ps1 -InstallRoot D:/Games/OGSR-Baseline -ToolRoot C:/Users/vladimir/Documents/Codex/tools/tracy -Mode whole-map
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
