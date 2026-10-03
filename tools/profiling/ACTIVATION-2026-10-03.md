# Budgeted whole-map activation experiment

## Implementation

`-alife_activation_queue` is opt-in and only effective with `-alife_whole_map`. The scanner continues to synchronize positions, maintain registries, check redundancy/death and run virtual eligibility/group policy. When that policy requests activation during an ordinary scan, the switch manager queues the ID instead of performing the client spawn immediately. It preserves saved client data while activation is pending. After the scan, a FIFO consumes at most 32 requests under a 3 ms soft budget per A-Life update. One indivisible activation can exceed the budget. A group and its children remain an atomic operation.

The initial update for a level, precache, actor, story objects and objects forbidden to switch offline retain synchronous activation. Calls outside scanner collection also stay synchronous. These bypasses prioritize compatibility; they do not cover every possible script assumption. This is a hybrid scanner/queue, not an event-driven replacement for reconciliation.

Pending requests live in the object registry and contain IDs and cancellation tickets, not object pointers. Removing an object cancels its ticket, so reusing its ID cannot execute an old request. Loading clears the queue; destroying/recreating the registry discards it; changing the current level clears it and restores synchronous first-update behavior. Requests are not serialized. After load, scanning reconstructs requests from actual world state.

Before consuming a request, the manager resolves its current object, verifies offline/unattached/current-level membership and a valid current-level graph vertex, then reruns synchronization and virtual transition policy. New flags, parents, group state or map travel can therefore invalidate a request. Raw script field changes still rely on the retained scanner. Work deferred this way may change when offline simulation stops and client AI starts; this remains experimental.

## Verification infrastructure

`activation-test` compiles the production queue header. Deterministic checks cover FIFO, deduplication, cancellation and immediate ID reuse, a zero time budget, count limits, stale cleanup limits, an indivisible overrun, reset during a callback, same-level continuity and changed-level reset. Release tests passed.

The regular runner now supports the activation package/flag, optional metrics, a save made while some stress IDs remain offline, restored-ID verification and an optional Tracy capture starting at readiness. A cold-load fixture checks every recorded stress ID is registered, online and client-present during each sampled measurement interval. This does not compare every inventory/script field.

With metrics enabled, `[ALife activation]` records frame, attempt count, pending count and elapsed batch time. Attempts include stale or invalid requests; they are not equivalent to successful NPC spawns. Tracy records the activation-queue scope and pending-count plot. Captured runs must be kept separate from untraced comparisons.

## Results

Release/x64 built successfully. The preserved gameplay package is `D:/Games/OGSR-Regular-Validation/bin_activation`, executable SHA-256 `E70897AAD6BC6A1EE93C9675663CA50D92C6E29D7EC94D62F028F390C1ECC464`, based on `02973d5f44c6dfe18a3f3542ebbb19a99f7ad8b5` plus the archived engine diff and new queue header. No C++ diagnostic patch or Tracy is present in this package. Existing manual-play packages remain unchanged.

All sessions below are under `D:/Games/OGSR-Regular-Validation/captures` and use scheduler compaction. They exited normally without fatal/script errors.

| Session | Workload | Result |
| --- | --- | --- |
| `2026-10-03_16-07-26-264-whole-map` | Queue on; five-phase eligibility fixture; create 400 in one batch; metrics; pending and final saves | Eligibility passed. Saved with 336 IDs still offline. Logged activation batches never exceeded 32 attempts; backlog drained. All 400 IDs stayed registered/online/client-present during measurement. |
| `2026-10-03_16-09-24-679-whole-map` | Queue on; cold load `activation_pending`; verify all 400 IDs from previous run | Every recorded ID was registered, online and client-present throughout sampled measurement intervals; restored-count acknowledgement passed. |
| `2026-10-03_16-11-08-862-whole-map` | Queue off; 400 extras created with 3 ms soft budget; no metrics/capture/save | Mean measured frame interval 9.446 ms; p99 19.042 ms; post-creation maximum 49.553 ms. All 400 IDs retained/online/client-present. |
| `2026-10-03_16-12-29-250-whole-map` | Same executable/workload; queue on | Mean 8.815 ms; p99 18.498 ms; post-creation maximum 56.850 ms. All 400 IDs retained/online/client-present. |

One comparison run per mode is not sufficient for a performance claim. The queue did not eliminate the post-creation hitch. The functional bulk-create run also retained its separate 267 ms synchronous creation cost; this server activation queue does not change creation APIs. Saving during backlog adds its own cost and that run is excluded from comparisons.

The diagnostic bulk run showed roughly 0.6 ms per 32 server requests, while the first census with all client objects was about five seconds after creation. Source inspection explains a separate throttle: `CLevel::cl_Process_Spawn` postpones monsters/traders and their children during gameplay; `ProcessGameSpawns` stops after one monster/trader and then spawns its queued children. Server activation timing therefore excludes much of the later client work. The 3 ms server budget is not an end-to-end client-spawn frame budget.

The trace package adds only the archived `activation-trace.patch` (client packet, spawn and queue scopes plus the requested GC-budget plot) to the gameplay changes, with Tracy enabled. `TraceSummary.cpp` exports those scopes, activation work, GC, scheduler and rendering/wait scopes. `Trace-Peaks.py` reports inclusive overlaps with selected long frames; nested and parallel timings must not be added or treated as exclusive CPU time. A synthetic interval fixture verified frame selection, clipped overlap and plot matching.

## Trace findings

The separate trace executable SHA-256 is `55EB3CF7CDB06EBD7BF21566D46516AF1B9FC6DEB19126A49C7FD2F42847EC05`, retained with its matching PDB, build log and full patch in `bin_activation_tracy`. Build uses solution configuration Release/x64 and environment `CONFIGURATION_GA=ReleaseTracyProfiler`; the latter enables Tracy in the property sheets. Client instrumentation was reversed out of gameplay sources after building. Both traced runs completed with all 400 IDs retained/online/client-present:

- Queue off: `2026-10-03_16-20-53-526-whole-map`, 651,169,406-byte trace. Driver measured a 93.042 ms post-creation peak.
- Queue on: `2026-10-03_16-22-20-711-whole-map`. Driver measured a 55.423 ms post-creation peak. These single, instrumented, variable-simulation runs are not evidence of a queue speedup; the untraced pair did not show reduced peaks.

Trace frame markers and Lua callback intervals measure different boundaries, so their durations need not match exactly. The exported 28â€“44 second trace window contains creation and subsequent activation, excluding initial connection frames. In the queue-off trace, frame 3935 at 34.185680 s took 92.379 ms. Main-thread worker wait was 83.019 ms, while the worker's inclusive `seqParallel` scope was 82.893 ms. Within that worker interval, A-Life switching took 42.267 ms and the client spawn queue took 36.556 ms (one individual client spawn took 35.848 ms). This is a localized long frame, not a steady-state average.

An unwrapped `ALife` export examines that 42.267 ms switch interval: 800 location-sync scopes total 11.240 ms, 747 offline-check scopes total 28.115 ms and 39 online-check scopes total 2.769 ms. There are **no add-online or remove-online scopes in that interval**. Thus this particular A-Life spike is reconciliation/checking, not an activation burst. These are instrumented elapsed scopes, not CPU samples; scheduling, tracing overhead and the exact costly instructions remain unresolved.

Client spawning is a separate reproducible hotspot. The queue-off trace contains an individual client-spawn scope of 44.993 ms. In the queue-on trace, a post-creation example at 32.259 s has a 52.055 ms frame, a 43.550 ms client queue scope and only 1.636 ms in A-Life switching. Other client queue calls in the selected window reach approximately 45â€“47 ms. A server-side request budget cannot split these indivisible client operations.

The requested GC budget at the highlighted long frames was 2,000 microseconds. The queue-off 92 ms frame overlaps only the start of a roughly 2.005 ms GC call. Other frames contain longer GC calls (including an 18.071 ms overlap in a 30.978 ms queue-on frame), so GC is relevant, but the hypothesis that expanded GC budgets explain the largest reproduced stalls is unsupported. No GC policy was changed.

Next profiling should subdivide `g_sv_Spawn`/client `net_Spawn` into resource loading, object initialization and script callbacks, and isolate reconciliation costs with lower-overhead per-pass timing or sampling. Do not remove lifecycle checks based on this trace alone. Keep the new server queue experimental until campaign/group/transition coverage improves.

Raw traces, `activation-trace-{frames,zones,plots}.tsv`, `activation-peaks.json` and regular summaries are retained in each trace session; the queue-off session also contains `alife-detail.csv` and its peak excerpt. Reproduce projection with `ogsr-trace-summary <capture.tracy> <prefix>`, peaks with `python -B Trace-Peaks.py <prefix> 28 44`, and full A-Life details with `tracy-csvexport -u -f ALife <capture.tracy>`.

The pending-save source and reload copy have identical SHA-256 `61F45070B777C9C310378C20C2B7872AA3406A5270FFBAE8B9B10CC978984236`. Original Bar seed and manual-play binary hashes remain unchanged.

## Remaining coverage

Campaign task hand-ins and natural level transitions, dense visible crowds, large group activation, script-forced immediate client lookups and long campaigns remain necessary before making this the default. The queue tests validate cancellation and map-reset mechanics; they do not substitute for a full engine-level death/group/attachment/level-travel test. The current scan is retained deliberately until lifecycle work and mutation notifications can be separated more fully.
