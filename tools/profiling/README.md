# A-Life diagnostics

## Collection

Use `-alife_metrics` for population counts, cumulative online/offline switch
counts and interval timings. `-alife_reconcile_metrics` reports update totals
and stage samples every 64 calls. `-alife_diagnostics` adds an offline-object
inventory only with population metrics; exclude those runs from timing comparisons.
Without diagnostics flags, no metric timers, counters or registry scans run.

`update=` counts every `update_switch` call, including loading calls outside
`CALifeUpdateManager::update()`. It therefore differs from the population log's
`updates=` interval counter. A record's `objects` counts visits, not necessarily
the population. `budget_ms` is the limit actually compared with the iterator's
seconds clock, expressed in milliseconds; -1 means an unlimited first update.

`offline_scheduled_ms` measures server-side offline A-Life updates. Online
objects leave that schedule registry: client AI, planners, visibility and
`shedule_Update`/`UpdateCL` costs are not included. Use the existing scheduler and
stalker Tracy scopes for those costs. Moving more NPCs online can reduce these
server-side timings while increasing total frame time.

When a positive budget ends an update before traversal completes, `total_ms` tends
toward `budget_ms` plus overshoot. Interval `switch_ms` also includes surrounding
work and can approach the sum of update allowances. Totals measure elapsed time
consumed, not the cost of a complete traversal. Compare visits per update and
stage shares alongside totals; equal update times need not mean equal throughput.
Neither visit counts divided by population nor the iterator's `cycle_count`
measure individual revisit or activation latency; that counter advances per update.

Stage timers consume part of the same budget and can reduce visits per sampled
update. `objectsPerSample` is instrumented throughput, not an estimate of normal
unsampled throughput. Unsampled records are emitted only for reported spikes,
so this log cannot quantify the sampling overhead or an unsampled mean.

Population scans and log output cost time outside the switching-stage totals.
Timings are accumulated work over a reporting interval, not CPU-utilization
percentages. `try_offline_ms` includes the manager checks and virtual object
switching call for objects online after location sync;
`try_online_ms` starts from offline objects. Switch counters include calls where
registry updates are disabled, so they need not equal registry-size changes.

The first spike reports immediately. Extra unsampled spike records are limited
to one per second; sampled records still report every 64 calls. `suppressed`
counts spikes since the previous record. A final unreported interval can still
contain suppressed spikes. Unsampled stage zeros are placeholders.
A spike records elapsed time of at least 10 ms. Under a smaller positive budget,
it indicates an overrun, but cannot identify its cause: slow object work, waits,
thread preemption and surrounding work can contribute. Unlimited first updates
can also spike. The record does not identify a slowest object.

Counter access relies on the engine's frame phases: FrameMove precedes
seqParallel, which is joined before the next FrameMove. A-Life and network work
in that worker are sequential; load-time calls also occur on the main thread.
These counters do not make concurrent world mutation safe.

## Reading logs and traces

`python Summarize-Reconciliation.py <xray.log> [--first-frame N --last-frame N]`
reads the log directly. Frame limits are inclusive. The default rejects malformed
or obsolete formats; `--skip-malformed` can recover complete records from a
truncated crash log and reports the skipped-line count for the whole file.
Suppression intervals may straddle a requested frame range.

Build tracing with `MSBuild Engine.sln /p:Configuration=ReleaseTracyProfiler
/p:Platform=x64` (one command). The nested `Level/client spawn` and
`Level/client spawn batch` scopes include client construction; their times are
not additive. These scopes compile out of Release builds.

The `ALife/engine frame` plot records an anchor for every emitted reconciliation
record and once per population-report interval. Capture frame indices are not
engine frame numbers, especially during loading or late collector connections.

Configure `tools/tests/alife-metrics` with CMake, build and run CTest (Python 3
and C++17 required). The production log emitter is also passed through the reader.
The engine and C++ tests include `alife_diagnostics.h` directly. Tests supply
controlled lifecycle operations and clocks to check ordering, timing attribution,
report intervals and emission. Real object/group activation and client construction
remain native integration responsibilities; these tests do not simulate them.
