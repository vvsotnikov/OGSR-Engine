# ALife service measurements

For switching throughput, run an isolated Release scenario with
`Run-RegularValidation.ps1 -ServiceSlices -FrameTimes`. Use `-ServiceTrace -FrameTimes`
only when individual switching visits/rejections are needed; it materially reduces
the visits completed within the switching budget. Use `-ServiceLifecycle -FrameTimes`
for activation/lifecycle histories without the visit/rejection stream. The runner
rejects combining modes. Omit all service switches for the tracing-off frame control.
Add `-Mode distance` or `-Mode whole-map`, `-Count 400` for density, and `-Eligibility`
for controlled whole-map permission changes. Use `-Transitions` separately for map lifecycle.
The runner records save/package hashes and configuration in `session.json`.
Run `cargo xtask service-report <capture>/appdata/alife-service-<pid>-<session>.csv`
for each completed simulator session. Add `--frames <capture>/appdata/regular-frames.csv`
to select the warmed interval. Run `cargo xtask frame-report <capture>/appdata/regular-frames.csv`
for frame percentiles by scenario stage. Keep the original capture alongside the report.

## Interpretation

- A `mode` row identifies full (`value=1`), slice-only (`value=0`), or lifecycle
  (`value=2`) recording. Lifecycle mode does not infer first/revisit waits or reasons
  for failed switching attempts; permission and construction waits remain available.
  Slice-only captures contain clocks, settings, updates and slice boundaries, with
  no object events or inferred per-object waits. Older captures without a mode row
  are reported as `legacy_full`.
- `slice_begin` precedes the iterator call; `slice_end` follows it, using its existing
  returned visit count (`value`). Their `flags` give registry sizes before/after.
  Recording is outside the iterator's timed traversal. The measured span includes
  recorder boundary overhead and possible descheduling; it is not pure CPU time.
  Every update must have exactly one completed slice in a modern capture. Full-mode
  visit rows must equal its returned visit count, even outside a selected window.
  Coverage/count errors are deferred until the footer so producer drops are identified
  as `dropped_records`; either condition fails validation.
  Slice aggregates report sum, mean and per-second rate over the selected wall-clock
  window (the complete capture duration when no window is selected). Rates of
  `slice_wall_us` are recorded microseconds per wall-clock second, not CPU utilization.
- Registration creates a new incarnation of an engine ID. Identity is scoped to one
  capture file; it is not a persistent campaign identity. Reload/map travel creates
  a new capture, and unfinished waits in the old capture remain reported.
- `enter`/`leave` delimit membership in the current-map switching registry. Leaving
  can mean attachment or registry removal, not necessarily travel to another map.
  First-visit time starts at registry insertion, not global object registration.
- `visit` is entry to `switch_object`, before redundant-object/attachment/location
  checks. It measures switching service, not a successful switch or client AI update.
- `permission_on` is recorded after the script-facing permission setter returns.
  Permission-to-online is full eligibility delay only in a controlled fixture that
  establishes the other conditions (current map, detached, matching configuration,
  whole-map mode). Ordinary permission changes do not establish spatial eligibility.
- `online` is the manager's server-online assignment before `Process_spawn`.
  `client` follows successful `net_Spawn`, before callbacks, ownership events and
  `Game().OnSpawn`. This is construction completion, not rendering or AI responsiveness.
  Client spawns without a matching tracked online transition are counted as unmatched;
  startup items may use other server paths and are not NPC activation samples.
- All event times use one process-wide monotonic wall clock, serialized under a mutex.
  They include loading, pause and debugger stops; game-time acceleration does not scale
  them. `clock` records game milliseconds/frame numbers for correlation. Settings records
  carry level, effective switch budget, policy and actual `mtALife` setting.
  Settings and scheduler configuration are emitted initially and on changes;
  update records count switching calls. Warmed reports retain pre-window settings. A negative budget is
  the initial unlimited-traversal sentinel, not a huge unsigned allowance.
- Flags: online=1, attached=2, creature=4, living creature=8, online permission=16,
  offline permission=32. Creature summaries include the actor and corpses; they are
  a subset of server objects, not an assertion that each object runs tactical AI.
  Permissions include the existing configuration filter.
  Unfinished waits retain the last observed flags/rejection; those are not proof of
  continuous eligibility between observations. No unagreed starvation threshold is used.

## Capture integrity and cost

Collection is opt-in (`-alife_service_trace`, `-alife_service_lifecycle`, or
`-alife_service_slices`), uses two fixed-capacity 65,536-event buffers,
then counts every dropped event if its writer cannot keep up. A writer thread formats
and writes batches outside switching callbacks; no file I/O occurs inside the switching budget. Disabled event sites perform a gate check without
clock reads, allocations or scans. Enabled sites serialize on a mutex; this cost is
inside the engine's existing switching budget in full mode. Slice-only mode retains
only the cheap detail gates on object paths, with no object clocks, mutexes or
snapshots. Both modes share slice-boundary recording outside that budget; the
low-rate control is not literally uninstrumented. Lifecycle mode skips visits and
repeated rejections but still records actual transitions inside the traversal.
Compare frame effects with tracing off and visits per slice across modes.
When reconciliation metrics are enabled too, their outer slice timer includes
trace-boundary recording; do not compare that timer with tracing-off measurements
as if the instrumentation were identical.
The writer wakes at 4,096 queued events; smaller batches wait until that threshold
or capture end. Final draining and the end record occur before simulator teardown. A crash has no
completed export; never treat its absence as zero latency. The reader fails on missing
end records, a footer row count that differs from the parsed record count, malformed data or clock regression and returns failure for dropped records.

Completed gaps and unfinished ages are distinct outputs. Quantiles use nearest rank;
maxima describe this capture, not a worst-case guarantee. Every member still registered
at capture end has an unfinished first/revisit wait, even a normally serviced object.
A large unfinished count alone does not establish starvation.

Frame recording is independent of service tracing and must be enabled in both sides
of overhead comparisons. Lua buffers wall-clock frame intervals and writes them only
at scenario completion. Stage 4 is the existing warmed 45-second measurement window;
other stages contain initial settling, creation and subsequent settling. This fixture
loads a save into a new process but does not flush filesystem caches; do not call it a
cold-cache measurement. Default service summaries cover the entire simulator capture, including loading.
With `--frames`, service samples are selected by completion time between the first and
last recorded ALife update clocks in stage 4. Frame numbers and game milliseconds must
match. Pre-window history remains available: waits begun earlier are not reset or hidden.
The report gives the actual clock bounds, and right-censors pending waits at window end.
`capture_integrity=ok` certifies format/clock/footer integrity with no dropped events,
not successful event pairing or gameplay. Unmatched counts remain separate: also require the runner
to acknowledge completion in session.json and retain the engine log.

The recorder stores event-kind pointers until the writer drains them; call sites must
use static-lifetime literals from the schema vocabulary. It never stores object pointers.

The [observer calibration](alife-service-2026-10-09.md) compares both modes with
tracing off. Full-mode per-object times describe the instrumented engine; do not
scale them by the throughput ratio to claim untraced latencies. Slice totals cannot
identify an individual object that is starved. Across the Bar comparisons, warmed frames above 27 ms occurred only in full-trace
runs (two of fourteen full runs, none of twenty-eight other runs); this is a reason to avoid full tracing for performance measurement,
not proof that it caused those stalls. The earlier
[Bar results](alife-service-2026-10-08.md) have the same observer limitation.

The offline reader streams input and stores each latency sample once for exact
nearest-rank quantiles and worst-object identities across both summaries. Sample
memory still grows with capture length; the producer buffer bound does not apply
to analysis. Warmed analysis makes two streaming passes to find the exact window
and then measure it, retaining pre-window object state. Frame recording likewise buffers the bounded runtime fixture's
frames until completion; it is not an unlimited-duration frame recorder.

The recorded `Device` frame/game-clock pair relies on engine synchronization, not
the recorder mutex. `CRenderDevice::on_idle` calls `FrameMove` (which writes the pair)
before submitting `seqParallel`, and waits for that worker and its child tasks before
returning to the next frame. `CALifeUpdateManager::shedule_Update` queues subsequent
MT updates there; the first update is synchronous. Loading draws increment the frame
on the synchronous loading path, before a frame worker is submitted. Any future change
to this ownership order must supply a synchronized clock snapshot to the recorder.
