# Scheduler behavior tests

The suite compiles the production scheduler with mock objects and deterministic
clocks. Each case asserts expected behavior directly. Assertions remain active in
Release, including inside the adapted exception handlers.

## Invariants

| Case | Expected behavior |
| --- | --- |
| `ordering` | Ordinary entries dispatch only when `deadline < now`, in queue order. Entries not yet due receive no needed check. Unprocessed live entries retain their relative order and precede requeued processed entries. |
| `compaction` | A canceled future entry is removed from the slot vector at the end of the pass, even before its former deadline. |
| `intervals` | The next deadline uses the derived interval below; the last-execution timestamp becomes `now`. Callback elapsed time is clamped independently. |
| `budget` | The tested successful callbacks stop dispatch only when accumulated cost exceeds `floor(current_budget)`. Equality permits another callback. Unprocessed entries get their turn before requeued entries. Budget targets and smoothing follow the rules below. |
| `prefetch` | Precache dispatch ignores the time budget; a completed pass decreases the target. |
| `needed` | An ordinary object returning false from its needed check receives no callback and is removed; its neighbor continues to dispatch. |
| `self_remove` | Self-unregister prevents automatic requeue without skipping the neighbor. Explicit self-registration is deferred and can dispatch on the next eligible pass. |
| `remove_other` | Canceling a later entry suppresses its callback. Canceling an already-processed entry prevents its next callback. |
| `registration` | Registration during dispatch takes effect after the pass. Paired pending registration/unregistration cancels out. External deferred unregister takes effect before dispatch. |
| `realtime` | RT callbacks run before ordinary callbacks. An RT needed check returning false advances its last-update timestamp without removing it. External RT unregister removes it. |
| `exceptions` | A throwing ordinary needed check receives no update callback; a throwing update receives no automatic requeue. Both paths leave neighbors able to dispatch on this and subsequent passes. |
| `liveness` | For the fixed N-object workload, with every object due each pass and each callback exceeding the maximum budget, every object dispatches once per N passes. This is a bounded workload assertion, not a fairness guarantee for arbitrary workloads. |
| `stress` | Across mixed deadlines, costs and registration/removal interactions: no duplicate callback within a frame, no callback after cancellation, unique live membership matching registration state, correct updated timestamps and interval bounds, and preserved relative survivor order. Processed/re-registered and canceled entries are excluded from the survivor comparison. |

For the valid configurations exercised by `intervals`:

- `min_interval = max(30, t_min)` and `max_interval = (1000 + t_max) / 2`
  using integer division.
- `interval = clamp(min_interval + floor((max_interval - min_interval) * scale),
  min_interval, max_interval)`; `next_deadline = now + interval`.
- Callback elapsed time is `clamp(now - last_execution, 1, max(t_max, 1000))`.

An over-budget break adds 3 to the target; a completed pass subtracts 1.
The target is then clamped to `[3, psShedulerMax]`, and
`current_budget = 0.9 * current_budget + 0.1 * target`.

Update the affected expectations alongside an intentional contract change.
Do not weaken assertions merely to accommodate a regression.

## Running

From the repository root:

```powershell
cmake -S tools/tests/scheduler -B <build-directory>
cmake --build <build-directory> --config Release
ctest --test-dir <build-directory> -C Release --output-on-failure
```

## Limits

The adapter replaces the two Windows SEH handlers with C++ catches. Exception
cases test adapted control flow, not Windows SEH recovery or cleanup of every
internal field. The interface and string mocks do not validate ABI compatibility,
real reference counting or CPU cost. The mock clock advances during callbacks,
so tests do not model queue-maintenance time.

RT-list mutation inside callbacks is excluded because of the existing iterator
invalidation problem. Private members are exposed only in the test translation
unit. `R_ASSERT` is checked; debug-only `VERIFY` and engine DEBUG code are not.
Native Release builds and runtime smoke checks complement these tests.
