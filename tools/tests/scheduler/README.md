# Scheduler behavior tests

```powershell
cmake -S tools/tests/scheduler -B <build-directory>
cmake --build <build-directory> --config Release
ctest --test-dir <build-directory> -C Release --output-on-failure
```

These tests compile the current production scheduler with mock objects and clocks.
They assert the scheduling contract directly; there is no frozen implementation,
expected digest, historical Git lookup, or launch flag. Assertions remain enabled
in Release and report failures outside the adapted exception handlers.

The focused cases cover:

- Strictly overdue dispatch, live queue order, survivor-before-processed order,
  future cancellation, and removal of tombstones.
- Explicit interval examples for derived bounds, fractional scaling and flooring,
  upper clamping, elapsed-time clamping, and last-execution timestamps.
- Strict budget comparison, floored budget thresholds, stopping after a callback,
  continuation on the next pass, target adjustment/clamping/smoothing, and precache.
- Not-needed removal, self-unregister with/without re-registration, cancellation of
  later and already-processed objects, deferred registration, paired pending
  registration/unregistration, and external unregister.
- RT-before-normal ordering, RT not-needed timestamp handling, and external RT removal.
- Exceptions from needed/update callbacks: removal without requeue, with and without
  a neighbor, and continued neighbor dispatch. These use C++ exceptions in the adapter.
- Bounded liveness for a fixed population: every overdue object dispatches within
  N passes with N objects, even when each callback exceeds the maximum budget.

The previous 200-seed workload (96 objects, 100 frames each) is retained with
assertions for duplicate callbacks, callbacks after cancellation, unique queue
membership, derived deadline bounds, updated timestamps and relative survivor order.
Order checks exclude canceled entries and processed/re-registered objects. Focused cases assert
exact order and numerical expectations instead of relying on a legacy digest.
The 12 shared-behavior cases were also run against pre-compaction scheduler source
from `ea325cc57`; all passed. The isolated `compaction` case failed there as expected:
legacy code retains a canceled future slot until its deadline. Current code passes
all 13 cases. That old source was substituted only in a local generated test file;
it is not a stored reference or a test dependency.

Deliberate mutations to exception handling, queue-head progress and survivor order
were detected by the corresponding tests. The generated source was restored and
all 13 cases passed again. These finite checks do not prove every possible behavior.

If intended scheduler behavior changes, update the affected explicit expectations
alongside that change. Do not weaken assertions merely to accommodate a regression.

The adapter strips engine includes and substitutes C++ catch blocks for the two
exact SEH handlers, rejecting unfamiliar SEH syntax. It does not validate Windows
SEH recovery, real shared-string reference counting or CPU cost. Real-time-list
mutation inside callbacks is excluded because of its existing iterator-invalidation
problem. The handwritten interface and string mocks do not validate interface/ABI
compatibility. `R_ASSERT` is checked, while debug-only `VERIFY` remains disabled.
Private members are exposed only in this isolated test translation unit.
Use Release for this fixture; it does not exercise the engine's DEBUG-only code.
Run a native Release build and runtime smoke check as well. Run these tests locally
while automated build checks remain disabled.
