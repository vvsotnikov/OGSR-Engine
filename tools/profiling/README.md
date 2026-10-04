# A-Life diagnostics

Launch the engine with `-alife_metrics` for population counts, cumulative online/offline switch
counts and update timings, or `-alife_reconcile_metrics` for update totals and stage
samples every 64 updates. `-alife_diagnostics` adds a periodic offline-object inventory
only when population metrics are enabled. Exclude inventory runs from timing comparisons.
No diagnostics flags means no metric timers, counters or registry scans.

Metrics describe work accumulated during a reporting interval, not a CPU utilization
percentage. Each record covers one cursor update; `objects` counts visits, not
necessarily the population. `budget_ms` is the limit actually compared by the
iterator, expressed in milliseconds; -1 denotes an unlimited first update.
The base engine's conversion bug can make this limit hundreds of seconds, so
updates normally visit the full registry. The separate switch-budget correction
restores short slices; diagnostics report either behavior without changing it.
One slow object can exceed the budget. Stage timers add observer overhead.
`try_offline_ms` times dispatch for objects online after location synchronization,
including virtual maintenance; `try_online_ms` starts from offline objects.
Unsampled spike records are limited to one per second; sampled updates are still
reported every 64 updates. Logged spikes are not an exhaustive hitch count.


Frame/time reads and counter updates rely on the engine's frame phases: FrameMove
and its gameplay callbacks precede seqParallel, which is joined before the next
FrameMove. A-Life work and network processing in that worker are sequential. These
counters do not make concurrent world mutation safe; moving A-Life onto an independent
worker would require synchronization of the registries as well as the counters.

Population scans and log output cost time outside the reported switching stages.
Stage timings preserve the existing callback order.

Configure `tools/tests/alife-metrics` with CMake, build and run CTest for the extracted
production-method fixtures (Python 3 and C++17 required).

`python Summarize-Reconciliation.py <xray.log> [--first-frame N --last-frame N]`
reads the emitted log directly. Frame limits are inclusive and optional. It rejects
old or malformed metric formats rather than silently treating missing data as zero.
Build a tracing engine with `MSBuild Engine.sln /p:Configuration=ReleaseTracyProfiler
/p:Platform=x64` (one command); ordinary Release omits tracing overhead.
Tracy builds include `ALife/client spawn` and `ALife/client spawn batch` zones
to distinguish client construction from server reconciliation and ongoing AI work.
These compile out of ordinary Release builds.

The `ALife/engine frame` plot anchors log/driver frame numbers to trace time.
Use it when joining runtime evidence to Tracy; do not assume capture indices equal
engine frame numbers, especially around loading and late collector connections.
