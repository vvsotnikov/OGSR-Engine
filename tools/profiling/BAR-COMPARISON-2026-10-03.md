# Paired Bar playtest

Normal: `2026-10-03_10-09-57-329-distance`. Whole-map: `2026-10-03_10-30-25-176-whole-map`. Both collectors saved approximately 90 seconds and exited with code 0; both games shut down normally. User reports the same route with no perceived difference or unusual behavior.

Both used executable SHA-256 `DCF443508EE651C1D0B783AE8F1302EBC3B3C87A16E9A0973F5A1FB71F65733E` and bar_approach seed SHA-256 `5009A2FBB29DAD185BC9EF4F892D5A0A69ACABD7E55AC1CE66CF31B5E3114FB3`. Both had 3840x2160, VSync off and Lua GC timeout 2000. Verbose diagnostics were disabled. No save/screenshot events were found in the run logs. Loading completed before recording, and shutdown occurred afterward.

Comparison window: complete positive frames and complete selected zones within seconds 35–115 of each trace origin. This excludes the capture boundaries and loading. Each run contributes 80 approximately one-second population log samples using game_ms 35000–114999; game and trace clocks are approximate alignments. Percentiles use nearest rank. Raw projections, summaries and population samples are saved alongside each trace.

| Metric | Normal | Whole-map |
| --- | ---: | ---: |
| Complete frames | 18,457 | 17,948 |
| Mean frame, ms | 4.334 | 4.457 |
| Median frame, ms | 4.218 | 4.419 |
| p95 frame, ms | 4.975 | 5.247 |
| p99 frame, ms | 5.473 | 6.059 |
| Maximum frame, ms | 38.620 | 14.926 |
| Frames >16.67 ms | 2 | 0 |
| Frames >33.33 ms | 1 | 0 |
| Frames >50 ms | 0 | 0 |
| Mean living online entities | 24.41 | 75.71 |
| Living online range | 22–30 | 75–80 |
| Mean living offline entities | 98.59 | 37.55 |
| Mean scheduler update, inclusive ms | 0.171490 | 0.355949 |
| Mean A-Life switch pass, inclusive ms | 0.642704 | 0.514594 |
| Mean offline scheduled pass, inclusive ms | 0.052793 | 0.054750 |
| Mean script GC zone, ms | 1.933126 | 2.087297 |

Whole-map mode simulated about 3.1 times as many living online entities on this route. Median frame duration rose about 4.8%, and p99 about 10.7%. Scheduler elapsed time approximately doubled, an absolute increase of 0.184 ms per update. The largest normal frame began at trace second 111.079; its cause has not been established. The lower maximum in whole-map mode is not evidence of a repeatable stutter improvement from one pair.

There were 11 add-online zones in normal mode; whole-map mode had 7 add-online and 4 remove-online zones in the measured interval. Eligibility-driven churn remains possible even with the native distance threshold removed.

## Correctness follow-up

Subsequent investigation resolved the initial ten removals as cross-map NPC travel; see [the lifecycle investigation](BAR-LIFECYCLE-2026-10-03.md). The paragraph below records the original observation and uncertainty before that investigation.

Whole-map startup initially reported 79 living online and 45 offline (124 total) at game_ms 14664. At game_ms 15666 this became 69 online and 45 offline, with 10 cumulative removals. These events precede the Tracy recording. The repeated activation-associated population reduction seen in smoke runs also occurred here. This is an unresolved entity-lifecycle difference, not proof of death, deletion, or a defect. Identify those ten entities and trace the removal reason before claiming behavioral equivalence or enabling the policy by default.

This remains one human-controlled run pair under heavy instrumentation: the normal trace contains about 285 million zones and whole-map about 623 million. Rendering/view differences and profiler overhead are confounders. Zone timings include children and descheduling; do not sum parallel or nested zones as total frame cost. No statistical significance or performance guarantee is claimed.

The result supports further correctness work: no severe frame-time regression appeared on this route despite substantially more online entities. Next priority is entity-lifecycle diagnostics and transition/save-reload validation, not another repetition of this route. Controlled input-failure testing remains separate and pending.
