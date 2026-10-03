# Scheduler behavior tests

## Constraints behind the tests

Queue order is part of scheduling behavior: when the frame budget runs out,
entries left behind wait until another pass. Compaction must preserve the relative
order of live survivors and keep them ahead of processed entries being requeued.
Sorting by deadline or swapping erased entries with the tail would change who waits.

A processed entry must disappear from unregister lookups before its update callback
runs. Otherwise self-unregister could find the old queue slot instead of clearing
`m_current_step_obj`, allowing the object to be requeued incorrectly. Tombstoning
provides this logical removal without shifting the vector during dispatch. Deferred
registration is also essential: callbacks must not grow the vector being traversed.

Preserving the scheduling contract means preserving order, interval rules and the
budget policy, not identical callback counts per frame. Reducing queue-maintenance
cost can allow more callbacks before the same elapsed-time budget expires. A null
slot carries no live scheduling obligation, so removing it before its former
deadline need not change live dispatch behavior.

The bounded-liveness check assumes a fixed population whose entries remain due,
with one callback consuming the budget per pass. It does not establish a waiting-time
bound under arbitrary arrivals, cancellations or changing callback costs.

## Running

From the repository root:

```powershell
cmake -S tools/tests/scheduler -B <build-directory>
cmake --build <build-directory> --config Release
ctest --test-dir <build-directory> -C Release --output-on-failure
```

## Interpretation limits

The tests compile the production scheduler with mock objects and a clock advanced
by callbacks. They do not measure queue-maintenance cost or validate the real
interface ABI and shared-string reference counting. C++ catches substitute for
Windows SEH handlers, so exception cases validate adapted control flow, not native
SEH recovery or complete exception-state cleanup.

RT callbacks may cancel themselves or another entry without invalidating traversal.
Canceled entries must not receive further callbacks; re-registration takes effect
at the end of the pass. No timestamp is written to a canceled entry after its
callback. The same rule applies when cancellation occurs in the needed check.

After an ordinary update exception, there is no current callback. Otherwise a
stale pointer could consume an unregister meant to cancel a pending registration.
DEBUG membership checks include queued, current and already-processed objects,
with pending registration operations applied in request order.

The fixture builds both Release semantics and a DEBUG-defined variant with
registration assertions active. This exercises scheduler DEBUG code, not the full
engine's debug configuration. Native builds and runtime checks remain necessary
complements.
