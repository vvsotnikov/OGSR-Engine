# First paired Cordon playtest

Normal session: `2026-10-02_23-38-02-483-distance`.
Whole-map session: `2026-10-02_23-41-27-511-whole-map`.
Both trace files saved successfully and were read by the CLI projection tool. Both games shut down normally. Identical executable SHA-256 and seed-save SHA-256 are recorded in their local session manifests. User reports no perceived difference and approximately the same route.

Analysis uses complete frames/zones contained in seconds 35–85 from each engine's trace origin: 50 seconds inside each 60-second capture, excluding loading and shutdown. This is one pair of human-controlled routes, not a deterministic benchmark. Resolution is 3840x2160, VSync off, Lua GC timeout 2000 in both configurations. No save or screenshot log entries were found in either run.

| Metric | Normal | Whole map |
| --- | ---: | ---: |
| Complete frames | 10,924 | 11,050 |
| Median frame, ms | 4.541 | 4.507 |
| p95 frame, ms | 5.216 | 5.302 |
| p99 frame, ms | 5.611 | 6.166 |
| Maximum frame, ms | 31.907 | 16.837 |
| Frames over 33.33 ms | 0 | 0 |
| Mean living online server entities, 50 log samples | 96.2 | 148.1 |
| Living online range | 91–101 | 147–151 |
| Living offline range | 64–75 | 16 |
| Mean engine scheduler update, inclusive ms | 0.273 | 0.319 |
| Mean A-Life switch pass, inclusive ms | 0.713 | 0.667 |
| Mean offline scheduled pass, inclusive ms | 0.038 | 0.039 |
| Mean Lua GC zone, ms | 1.989 | 2.043 |

Whole-map mode raised the sampled living online population by about 54%. Typical frame times were nearly unchanged. Scheduler elapsed time increased about 17% (0.046 ms per update), while p99 frame time increased about 10% (0.555 ms). These observations do not establish a speedup or a statistically reliable regression from one run pair. Nested and parallel zone times must not be added as total frame cost. Full instrumentation remains a confounder.

There were no add-online or remove-online zones in the selected whole-map interval; normal mode recorded both. This supports that distance-driven churn was removed during that interval. The 16 remaining offline creature entities require individual classification before claiming all eligible NPCs are online. Campaign behavior, transitions, crowded locations, save/reload and non-instrumented performance remain unvalidated.

A separate whole-map launch at `23:40:36` crashed before loading the save, with access violation `c0000005` on `TTAPI thread id16`. The retry succeeded. Its log and minidump are preserved under session `2026-10-02_23-40-35-630-whole-map`. Subsequent analysis with matching private symbols places the fault on the startup thread in CInput::CreateInputDevice, called from InitInput/WinMain_impl. The TTAPI log label was misleading. DirectInput CreateDevice returned HRESULT 0x80040154, left the device pointer null, and release-mode CHK_DX ignored the error before SetDataFormat dereferenced it. This establishes the immediate crash mechanism, not the cause of the DirectInput failure. A USB switcher was suggested by the user as a possible contributor; this remains unverified. Debugger outputs are preserved beside the dump.

Next priorities: classify remaining offline entities, harden DirectInput startup error handling and investigate its intermittent failure, and validate the policy in a crowded location and across level transitions. No additional Cordon replay is needed immediately.
