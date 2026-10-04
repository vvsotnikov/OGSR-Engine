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
and typed plots (user, CPU usage, memory and power). Source IDs, files and lines keep same-named scopes distinct; IDs are
local to one capture. GPU timelines, dynamic zone names/text and messages remain available
in the original trace but are not exported. Thread IDs are OS IDs accompanied by
Tracy thread names; they are not stable identities across runs. Plot export also
supports existing captures with instrumentation absent from the current engine;
the report does not require the current engine to produce plots.

Run `python summarize_trace.py <prefix> <start-seconds> <end-seconds>` to write
`<prefix>-summary.json`, or `python trace_peaks.py <prefix> <start> <end>` to print
scopes and plot samples overlapping the largest complete frames. Selection uses
the explicit trace-time window, without discarding numbered frames implicitly.
The aggregate includes only complete events inside the window; the peak report
includes intersecting zones. Durations are inclusive and overlap across threads,
so their sum is not elapsed wall time or CPU utilization. Recursive zones with
the same name can sum to more than the frame duration. Capture frame indices do
not identify engine frame numbers after late collector connections or loading.

TSV fields use CSV quoting and preserve embedded newlines; readers decode UTF-8 with surrogate escapes for undecodable bytes, such as
legacy Windows source paths. JSON escapes preserve those bytes without guessing
a code page. Plot type/name pairs distinguish built-in and same-named user plots. Exports can be
large, and aggregation retains selected durations in memory. Keep the original
trace for GPU analysis and other data not represented by these reports.

The `tools/tests/tracy-report` CTest project compiles the production TSV writer
and feeds its output into both Python readers, including names with tabs,
quotes, Unicode and newlines. Run it with (Python 3 required):

```
cmake -S tools/tests/tracy-report -B <build-dir> -A x64
cmake --build <build-dir> --config Release
ctest --test-dir <build-dir> -C Release --output-on-failure
```

The tools are compiled for the local machine's instruction set; rebuild them
when moving to a machine with different CPU capabilities.

`tools.json` records the pinned tool-source revision and compatibility headers
for identifying a copied binary package.
