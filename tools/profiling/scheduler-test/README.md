# Scheduler equivalence fixture

Run locally with CMake and a C++17 compiler:

```powershell
cmake -S tools/profiling/scheduler-test -B <build-directory>
cmake --build <build-directory> --config Release
ctest --test-dir <build-directory> -C Release --output-on-failure
```

The current engine always uses stable queue compaction. No launch flag is needed.
The fixture compiles two executables: the current scheduler, and the same scheduler
with only `ProcessStep` replaced by the checked-in pre-compaction `Baseline.inc`.
The reference's commit identifier is provenance, not a build dependency. It must
remain frozen when the implementation changes.

Across 200 deterministic scenarios the executables compare callback order,
deadlines, needed checks, removals, registrations and budget adaptation. Mock clocks
advance during callbacks; they do not measure queue-maintenance CPU cost. In a real
frame, faster maintenance may allow more callbacks before the same budget expires.
Null entries can be removed earlier without changing the order of live entries.

The fixture substitutes C++ catch blocks for the two exact Windows SEH handlers.
It does not validate SEH recovery, actual shared-string reference counting, or
real-time-list mutation during dispatch. Run a native Release engine build and
runtime smoke test as well. Private-member access is exposed only in this isolated
test translation unit to observe queue state; the production header is unchanged.
CI build checks are currently disabled by project policy; run this test locally.
