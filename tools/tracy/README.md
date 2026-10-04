# Tracy capture and export

Build the tools with `Build-TracyTools.ps1 -ToolRoot <directory>` using CMake 3.24+
and Visual Studio C++ Build Tools. The script pins the collector revision and
compares the embedded client's protocol headers before building. Version labels
alone cannot establish compatibility with an unreleased client.

Build the engine with `MSBuild Engine.sln /p:Configuration=ReleaseTracyProfiler
/p:Platform=x64` (one command). Record with
`<directory>/bin/tracy-capture.exe -a 127.0.0.1 -o capture.tracy -s 60 -m 20`.
Only one collector may connect. Regular Release builds cannot emit traces.

`ogsr-trace-summary.exe <trace> <prefix>` loads the trace through Tracy's own
reader and exports frame boundaries, every zone, and every plot. The TSV can be
large; retain the original trace for later inspection. `Summarize-TraceStream.py`
aggregates a time window; `Trace-Peaks.py` reports individual frame peaks.
Zone durations are inclusive and overlap across threads, so their sum is not
elapsed wall time or CPU utilization. Capture frame indices do not identify
engine frame numbers after late collector connections or loading.
