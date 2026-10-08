# Bar observer calibration, 2026-10-09

Eighteen fresh-process Release runs used the same executable and Bar save:
400 added characters, distance/whole-map policies, tracing off/slice-only/full,
three repetitions per combination. Mode order rotated between repetitions;
policy order alternated. Every run recorded frames, with 15 seconds of settling
and a 45-second warmed window after creation. No builds or analysis overlapped games.
Ryzen 7 5800X, RTX 4090, 96 GiB RAM, 3840×2160 windowed, VSync off, no frame cap;
mtALife enabled, switching allowance 810 us, scheduler 1/1 ms and 10 objects/update.
Caches were not flushed. The fixture's creation burst is not ordinary map entry.

Ranges below span the three paired repetitions, not confidence intervals.

| Full tracing relative to slice-only | Distance | Whole-map |
|---|---:|---:|
| Mean visits per slice | −34.1% to −36.8% | −37.4% to −37.8% |
| Visits per second | −34.0% to −37.2% | −35.6% to −38.6% |

Median slice spans remained 811–812 us: the budget hid the observer cost by allowing
fewer visits. Full-mode visit records exactly matched the iterator's returned count
in every recorded slice. Distance registries stayed at 820 objects; whole-map
registries ranged from 810–816 as gameplay changed them. All 400 fixture characters
stayed online in whole-map mode versus 60–62 with distance; living counts varied
393–400 in whole-map mode. AI was not deterministic between runs.

Slice-only versus off changed frame p50 by −1.7% to +0.8% and p99 by −2.1% to +1.9%,
with no consistent increase. Full versus off changed p99 by −0.1% to +5.2%.
Two warmed frames exceeded 27 ms, both in the third whole-map full-trace run
(27.8 and 32.8 ms). Nearby switching slices lasted 810–816 us; the long intervals
were between update clocks. This locates the delay outside those traversals but
does not distinguish recorder-worker effects, other engine work or OS scheduling.
No outliers were removed. Three repetitions do not bound rare stalls or other maps.

Use slice-only recording for throughput comparisons and tracing-off frame controls.
Use full tracing for identity/lifecycle diagnosis: its per-object waits describe a
materially slowed traversal, not untraced latency or tactical AI response time.
Do not correct individual waits by multiplying by the aggregate throughput ratio.
Slice-only does not measure individual starvation; its outside-budget collection
still has a cost. This experiment supports that tool choice, not a zero-overhead claim.

All 12 benchmark traces and six traces from two Bar → Garbage → Bar checks had
complete footers and zero drops. Both travel scenarios completed. Full traces retain
unmatched lifecycle/client events separately; format integrity does not imply complete
activation pairing. Raw data, plots, scripts and package/save identities stay local,
outside Git. See [the measurement contract](alife-service.md) for reusable commands.

## Lifecycle-only follow-up

A subsequent single-binary matrix repeated both policies twice with all four modes
(off, slices, lifecycle, full), reversing mode and policy order: 16 more runs with
the same fixture, settings and warm window. Lifecycle mode omits both visit and
repeated rejection events. Relative to slices, mean visits/slice changed −1.4% to
+2.1% and visits/second −0.9% to +4.1%; relative to off, frame p99 changed −2.3% to
+0.1%. Full tracing still lost 35–39% of mean visits/slice. No warmed frames exceeded
27 ms. These comparisons support separating the high-rate stream, not attributing
all cost to `visit` alone or claiming zero lifecycle cost during heavy transitions.

Use lifecycle mode for permission/activation histories without the high-rate stream;
retain full mode only when the individual visit/rejection history is itself needed.
The shipped reader reproduced all slice sums, means and rates from the raw records,
and verified full-mode visit counts. All 12 traces passed integrity checks. Native
permission scenarios passed in lifecycle and full modes, as did lifecycle map travel;
all five resulting traces passed, with no invented first/revisit waits in lifecycle
reports. Both matrices' data and plots remain local. Their measurements are not pooled
as if they shared one binary, and neither establishes untraced per-object latency.
