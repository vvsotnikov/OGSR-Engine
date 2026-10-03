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

The previous 200-seed workload (96 objects, 100 frames each) is retained with
assertions for duplicate callbacks, callbacks after cancellation, unique queue
membership, derived deadline bounds and updated timestamps. Focused cases assert
exact order and numerical expectations instead of relying on a legacy digest.
The old comparison passed immediately before replacement. This is not a claim
that a finite assertion suite proves every behavior previously compared.

If intended scheduler behavior changes, update the affected explicit expectations
alongside that change. Do not weaken assertions merely to accommodate a regression.

The adapter strips engine includes and substitutes C++ catch blocks for the two
exact SEH handlers, rejecting unfamiliar SEH syntax. It does not validate Windows
SEH recovery, real shared-string reference counting or CPU cost. Real-time-list
mutation inside callbacks is excluded because of its existing iterator-invalidation
problem. Private members are exposed only in this isolated test translation unit.
Use Release for this fixture; it does not exercise the engine's DEBUG-only code.
Run a native Release build and runtime smoke check as well. Run these tests locally
while automated build checks remain disabled.
