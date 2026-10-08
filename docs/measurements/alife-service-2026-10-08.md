# Bar service measurements, 2026-10-08

Eight matched Release runs compared stock distance and whole-map mode, with
400 added characters, tracing off/on, and two repetitions of each combination.
The fixture used a 45-second warmed window after creation and settling.
Ryzen 7 5800X, RTX 4090, 96 GiB RAM, 3840×2160; switching allowance 810 us,
mtALife enabled. Whole-map kept all 400 characters online; distance kept 59–62 online.

| Measurement | Observed result |
|---|---|
| Warmed frame p99, distance / whole-map | 7.2–8.0 / 18.1–18.9 ms |
| Warmed whole-map creature switching revisit p99 / maximum | 43–48 / 65 ms |
| Largest unfinished whole-map creature revisit at warmed boundary | 84 ms |
| Full-capture creature revisit maximum | 1.886–2.039 s, during loading |
| Whole-map server-online to client net_Spawn maximum | 4.497 s |

These are switching/construction measurements, not tactical AI response times.
The loading gaps span only two or three switching updates; most of that delay
is between updates. Device game time diverges from wall time during loading;
all reported waits use the monotonic clock.
All ten warmed frames above 27 ms occurred in one tracing-on distance run,
including a 148-ms revisit. Tracing-induced stalls remain possible. The probe
also consumes part of the switching budget; no uninstrumented latency baseline
or acceptable responsiveness threshold is established by these runs.
The unbounded 400-object creation callback produced 265–299-ms frames before
the warmed interval. This is not an ordinary Bar-entry measurement.

The raw captures, detailed report, generated tables/plots and analysis scripts
are retained locally outside Git. Capture/package identities are in that local
experiment record. These results precede the settings-record deduplication;
they are historical measurements, not a benchmark of subsequent recorder edits.
Use [the measurement contract](alife-service.md) to capture and interpret new runs.

Remaining work: [#17](https://github.com/vvsotnikov/OGSR-Engine/issues/17) calibrates
observer cost and repeats the tracing on/off comparison;
[#26](https://github.com/vvsotnikov/OGSR-Engine/issues/26) separates client queue
waiting from construction before changing the activation policy.
