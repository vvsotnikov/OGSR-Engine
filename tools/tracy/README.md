# Tracy capture and export

Build with `Build-TracyTools.ps1 -ToolRoot <directory>` using CMake 3.24+,
Visual Studio C++ Build Tools, Git and PowerShell. The script pins the collector
revision and compares the embedded client's protocol headers before building.
Version labels alone cannot establish compatibility. `-Jobs` defaults to two
to bound compiler memory use and can be raised on larger machines.

Build the engine with `MSBuild Engine.sln /p:Configuration=ReleaseTracyProfiler
/p:Platform=x64` (one command). Record with
`<directory>/bin/tracy-capture.exe -a 127.0.0.1 -o capture.tracy -s 60 -m 20`.
Only one collector may connect. Regular Release builds cannot emit traces.

`ogsr-trace-export.exe <trace> <prefix>` loads the trace through Tracy's reader
and exports complete CPU zones with static source names, base-frame boundaries,
and plots. GPU timelines, dynamic zone names/text and messages remain available
in the original trace but are not exported. Thread IDs are OS IDs accompanied by
Tracy thread names; they are not stable identities across runs. Plot export also
supports existing captures with instrumentation absent from the current engine;
it does not require an engine-side plot producer in this PR.

Run `python summarize_trace.py <prefix> <start-seconds> <end-seconds>` to write
`<prefix>-summary.json`, or `python trace_peaks.py <prefix> <start> <end>` to print
scopes and plot samples overlapping the largest complete frames. Selection uses
the explicit trace-time window, without discarding numbered frames implicitly.
The aggregate includes only complete events inside the window; the peak report
includes intersecting zones. Durations are inclusive and overlap across threads,
so their sum is not elapsed wall time or CPU utilization. Recursive zones with
the same name can sum to more than the frame duration. Capture frame indices do
not identify engine frame numbers after late collector connections or loading.

TSV fields use CSV quoting and preserve embedded newlines; readers require UTF-8
and report invalid input rather than silently replacing names. Exports can be
large, and aggregation retains selected durations in memory. Keep the original
trace for GPU analysis and other data not represented by these reports.

The `tools/tests/tracy-report` CTest project compiles the production TSV writer
and feeds its output into both Python readers, including names with tabs,
quotes, Unicode and newlines. It is run by the local validation hook; GitHub
builds remain disabled. It can also be configured, built and run with CMake and
CTest independently (Python 3 required).
