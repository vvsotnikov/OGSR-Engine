# ALife service measurements

Run an isolated Release scenario with `Run-RegularValidation.ps1 -ServiceTrace -FrameTimes`.
Add `-Mode distance` or `-Mode whole-map`, `-Count 400` for density, and `-Eligibility`
for controlled whole-map permission changes. Use `-Transitions` separately for map lifecycle.
The runner records save/package hashes and configuration in `session.json`.
Run `cargo xtask service-report <capture>/appdata/alife-service-<pid>-<session>.csv`
for each completed simulator session. Keep the original capture alongside the report.

## Interpretation

- Registration creates a new incarnation of an engine ID. Identity is scoped to one
  capture file; it is not a persistent campaign identity. Reload/map travel creates
  a new capture, and unfinished waits in the old capture remain reported.
- `enter`/`leave` delimit membership in the current-map switching registry. Leaving
  can mean attachment or registry removal, not necessarily travel to another map.
  First-visit time starts at registry insertion, not global object registration.
- `visit` is entry to `switch_object`, before redundant-object/attachment/location
  checks. It measures switching service, not a successful switch or client AI update.
- `eligible_observed` is the dynamic object's existing decision to switch online.
  It is observed during evaluation: its delay excludes the earlier wait for evaluation.
  Group-specific decisions that bypass this path have no such sample.
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
  them. `clock` records game milliseconds/frame numbers for correlation. Update records
  carry level, effective switch budget, policy and actual `mtALife` setting. A negative budget is
  the initial unlimited-traversal sentinel, not a huge unsigned allowance.
- Flags: online=1, attached=2, creature=4, living creature=8, online permission=16,
  offline permission=32. Permissions include the existing configuration filter.
  Unfinished waits retain the last observed flags/rejection; those are not proof of
  continuous eligibility between observations. No unagreed starvation threshold is used.

## Capture integrity and cost

Collection is opt-in (`-alife_service_trace`), uses two fixed-capacity 65,536-event buffers,
then counts every dropped event if its writer cannot keep up. A writer thread formats
and writes batches outside switching callbacks; no file I/O occurs inside the switching budget. Disabled event sites perform a gate check without
clock reads, allocations or scans. Enabled sites serialize on a mutex; this cost is
inside the engine's existing switching budget and must be measured with matched runs.
Final draining and the end record occur before simulator teardown. A crash has no
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
cold-cache measurement. Service summaries currently cover the entire simulator capture,
including loading; report them separately from warmed frame intervals.
