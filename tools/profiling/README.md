# A-Life diagnostics

Launch the engine with `-alife_metrics` for population counts, cumulative spawn/removal
counts and update timings, or `-alife_reconcile_metrics` for pass totals and stage
samples every 64 passes. `-alife_diagnostics` adds a periodic offline-object inventory
only when population metrics are enabled. Exclude inventory runs from timing comparisons.
No diagnostics flags means no metric timers, counters or registry scans.

Metrics describe work accumulated during a reporting interval, not a CPU utilization
percentage. The first interval starts on the first metered update. Stage timings are
inclusive and preserve the existing callback order. This PR does not change distance
policy, group teardown or scheduling behavior.

Build the trace tools with `Build-TracyTools.ps1 -ToolRoot <directory>`. For a matching
Tracy-enabled engine, record with `<directory>/bin/tracy-capture.exe -a 127.0.0.1 -o capture.tracy -s 60 -m 20`.
Only one collector may connect. Use `ogsr-trace-summary.exe <trace> <prefix>` and the
summary scripts in this directory to analyze it. Regular builds cannot emit Tracy traces.
Configure `tools/tests/alife-metrics` with CMake, build and run CTest for the extracted
production-method fixtures (Python 3 and C++17 required).

Historical measurements, package-specific launchers and diagnostic patches are preserved
on [archive/alife-experiments-2026-10-04](https://github.com/vvsotnikov/OGSR-Engine/tree/archive/alife-experiments-2026-10-04/tools/profiling).
