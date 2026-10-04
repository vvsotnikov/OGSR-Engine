# A-Life diagnostics

Launch the engine with `-alife_metrics` for population counts, cumulative online/offline switch
counts and update timings, or `-alife_reconcile_metrics` for slice totals and stage
samples every 64 slices. `-alife_diagnostics` adds a periodic offline-object inventory
only when population metrics are enabled. Exclude inventory runs from timing comparisons.
No diagnostics flags means no metric timers, counters or registry scans.

Metrics describe work accumulated during a reporting interval, not a CPU utilization
percentage. The first interval starts on the first metered update. A slice resumes a registry cursor and may stop at its time budget before visiting
all objects. `objects` counts visits in that slice, not the level population.
`budget_ms` reads the iterator's actual limit; -1 denotes an unlimited first update.
The timer is checked between objects, so one slow object can exceed the budget.
Stage timers consume that budget; sampled and unsampled slices may process different
subsets. `try_offline_ms` times dispatch for objects that were online after location
synchronization, including virtual maintenance, not just transitions. The corresponding
`try_online_ms` bucket starts from offline objects.

Frame/time reads and counter updates rely on the engine's frame phases: FrameMove
and its gameplay callbacks precede seqParallel, which is joined before the next
FrameMove. A-Life work and network processing in that worker are sequential. These
counters do not make concurrent world mutation safe; moving A-Life onto an independent
worker would require synchronization of the registries as well as the counters.

Population scans and log output cost time outside the reported switching stages.
Stage timings preserve the existing callback order. This PR does not change distance
policy, group teardown or scheduling behavior.

Build the trace tools with `Build-TracyTools.ps1 -ToolRoot <directory>`. For a matching
Tracy-enabled engine, record with `<directory>/bin/tracy-capture.exe -a 127.0.0.1 -o capture.tracy -s 60 -m 20`.
Only one collector may connect. Use `ogsr-trace-summary.exe <trace> <prefix>` and the
summary scripts in this directory to analyze it. Regular builds cannot emit Tracy traces.
Configure `tools/tests/alife-metrics` with CMake, build and run CTest for the extracted
production-method fixtures (Python 3 and C++17 required).

Historical measurements, package-specific launchers and diagnostic patches are preserved
on [archive/alife-experiments-2026-10-04](https://github.com/vvsotnikov/OGSR-Engine/tree/archive/alife-experiments-2026-10-04/tools/profiling).

`python Summarize-Reconciliation.py <xray.log> [--first-frame N --last-frame N]`
reads the emitted log directly. Frame limits are inclusive and optional. It rejects
old or malformed metric formats rather than silently treating missing data as zero.
Build traces with `MSBuild Engine.sln /p:Configuration=Release /p:Platform=x64
/p:CONFIGURATION_GA=ReleaseTracyProfiler` (one command). `CONFIGURATION_GA` enables
the Tracy definitions; it is not a solution configuration. Omit that property for
ordinary Release measurements without tracing overhead.

Tracy builds include `ALife/client spawn` and `ALife/client spawn batch` zones
to distinguish client construction from server reconciliation and ongoing AI work.
These compile out of ordinary Release builds.

The `ALife/engine frame` plot anchors log/driver frame numbers to trace time.
Use it when joining runtime evidence to Tracy; do not assume capture indices equal
engine frame numbers, especially around loading and late collector connections.
