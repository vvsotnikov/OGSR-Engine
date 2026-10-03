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

RT cancellation can originate in either scheduling phase. RT slots are compacted
only after ordinary callbacks finish, so successful updates leave no canceled RT
slots behind. Re-registration is deferred; it cannot invalidate active traversal.

An ordinary object remains registered during both scale and update callbacks.
Cancellation during scale suppresses the subsequent update, including when the
object re-registers itself for a later pass. No object access may follow a scale
callback that cancels and destroys its object.

After an ordinary callback exception, there is no current callback. Otherwise a
stale pointer could consume an unregister meant to cancel a pending registration.
An object dropped after an exception is absent; unregistering it again without
re-registering is a DEBUG contract violation.

DEBUG membership includes queued, current and processed objects, with pending
operations applied in request order. Duplicate membership and operations against
the wrong prior state must assert. The temporary processed-queue observer must be
cleared on every exit from the step, including failures outside callback handlers.
This cleanup does not promise recovery of an entire aborted engine update.

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
Windows SEH handlers and an exact C++ cleanup expansion substitutes for the native
finally block. Exception cases validate adapted control flow, not native SEH recovery.

The fixture builds both Release semantics and a DEBUG-defined variant with
registration assertions active. This exercises scheduler DEBUG code, not the full
engine's debug configuration. Native builds and runtime checks remain necessary
complements.
