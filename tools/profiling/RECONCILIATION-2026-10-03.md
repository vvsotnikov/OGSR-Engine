# Reconciliation boundaries and low-frequency timing

## Scope and preserved behavior

The switch manager now explicitly calls `maintain_before_switch`, `evaluate_switch` and `maintain_after_switch` in the same order as the original body. Before maintenance releases redundant objects or synchronizes their location; a failed synchronization stops processing. Dispatch observes the online state **after** synchronization. After maintenance checks redundancy again. Queue consumption uses this same sequence, with revalidation unchanged.

This is a manager-level separation, not yet a pure policy/lifecycle split inside every virtual object method. In particular, legacy group dispatch interleaves cleanup with member eligibility checks and stops on an eligible member. Moving all cleanup ahead of that loop would change behavior. Dispatch timing must not be presented as fully removable decision overhead.

The production method bodies, extracted directly from this source and baseline `d89893ca1`, pass 256 deterministic comparisons with controlled lifecycle operations. Both sampled and unsampled branches preserve call order and state for early redundancy, failed synchronization, online-state changes during synchronization/dispatch and post-dispatch redundancy. This tests the manager sequence, not every engine group implementation.

## Responsibility and notification audit

| Responsibility | Current implementation | Requirement before decisions can stop recurring |
| --- | --- | --- |
| Object redundancy/removal | Pre/post checks around dispatch; group emptiness | Group membership/death notifications plus safe removal; keep registry/queue cancellation |
| Position and graph consistency | `synchronize_location`, graph/node updates | Continue necessary movement reconciliation independently; map arrival/departure notifications must follow authoritative graph updates |
| Offline scheduling | Dynamic-object `try_switch_online` adds/removes schedulable membership based on `need_update` | Extract this maintenance without changing virtual/group call order; death or scheduling-state events must cover it |
| Group dead-member cleanup | Legacy `try_switch_offline` detaches members and repairs registries inside eligibility loop | Preserve traversal/break semantics or explicitly test and accept a behavior change; cannot simply skip stable online groups |
| Saved client data | Dynamic and manager online checks clear or retain data | Preserve denied-activation and pending-activation rules, including script overrides |
| Eligibility | Native flag setters, configuration matching and direct mutable Lua flags | Instrument all supported mutation paths or retain reconciliation for raw writes; setter-only notifications are insufficient |
| Actual transitions | `switch_online/offline`, spawn/destruction and parent inventory/group operations | Continue atomic dependencies and queue revalidation; do not equate policy simplification with deleting lifecycle code |

Candidate event boundaries are current-level registry add/remove, object registration/removal, native eligibility setters, group membership/death changes and load/level reset. Raw Lua `m_flags` references and graph/node properties still bypass notifications. No event-only policy or decision cache is enabled by this change. A cache keyed only on online status would incorrectly suppress virtual cleanup and script changes.

## Timing method

`-alife_reconcile_metrics` enables a lightweight non-Tracy probe. It times each current-level traversal but emits totals only for every 64th pass or any traversal lasting at least 10 ms. Every 64th pass also measures before maintenance, online-object dispatch, offline-object dispatch and after maintenance. Other passes have **no per-object timing calls**. Logging happens outside the traversal, and samples are disabled before the separate activation queue drains.

The sampled totals include measurement overhead; they are not exclusive CPU times and do not represent every pass. There is no all-pass mean in this log. Unsampled phase zeros are placeholders. `Summarize-Reconciliation.py` rejects invalid cadence/counts, overlapping phase totals, unsampled phase values and insufficient measured samples. It aligns phase samples with the regular driver's steady-state worker frames and labels spike membership in that window.

A pass means one invocation of the current-level registry update, whose existing iterator may stop at its time budget; it is not a guarantee that every map object was processed. The separate activation-queue drain and offline simulator update are excluded from these traversal timings.

## Validation

Release/x64 built successfully from `d89893ca157fd71ecbcb3664735b728bbac3e1e8` plus the archived engine patch. Candidate SHA-256: `379A6C6D8130BB0E675D943EAEACBEE938A785D2DF455E003577595F3A24AE53`. Matching executable/PDB/DLLs, build log and patch are retained in `D:/Games/OGSR-Regular-Validation/bin_reconcile`. The original manual-play package and Bar saves are preserved.

The new technical transition fixture uses existing `jump_to_level` commands, requiring Bar/Garbage/Bar readiness acknowledgements in order, a successful final save and normal exit. This is not a natural level-changer playtest or a full world-state census.

Sessions live under `D:/Games/OGSR-Regular-Validation/captures`:

- `2026-10-03_16-48-23-434-whole-map`: candidate, activation queue and timing on; eligibility fixture, bulk creation of 400, pending and final saves. All eligibility phases passed and all 400 IDs stayed registered/online/client-present during measurement. Its bulk-creation/save costs exclude it from frame-time comparisons. Across 51 steady-state sampled passes (about 811 objects each), traversal mean was 1.652 ms: before 0.463, online dispatch 0.714, offline dispatch 0.273 and after 0.021 ms. Unclassified timer/loop overhead occupies the remainder. Sampled maximum was 3.435 ms, but the always-on pass timer also caught unsampled 11.994, 22.055 and 13.064 ms traversals within the measured window. Their phases are unknown.
- `2026-10-03_16-50-37-240-whole-map`: candidate cold-loaded the pending save and verified every one of the 400 recorded IDs during measurement. Sampled traversal mean was 1.577 ms (54 samples); no traversal at least 10 ms was logged inside the measured window, though startup/warmup contained spikes. Source and copied pending saves share SHA-256 `69A913007C382C619E3208093FB005A48FA4002A5633C6682C1188AC15E2CF7E`.

These observations show that rare long elapsed traversals can occur without Tracy; they do not establish exclusive CPU consumption or prove the responsible instructions. Ordinary sampled dispatch is only part of the traversal, and some dispatch work is mandatory maintenance. No decision-skipping optimization is enabled on the strength of these numbers.

The frame analyzer now excludes the last creation batch's interval from its post-creation maximum: interval F includes work after callback F-1, even when its stage is already labelled warmup. A regression fixture checks this boundary. Save operations can still contribute to warmup maxima, so save fixtures remain excluded from performance comparisons.

## Comparison runs

All three runs below used 400 extras, 3 ms budgeted creation and the compact scheduler/activation queue, with no Tracy or save operation. Each retained all 400 IDs online and client-present during measurement and exited normally.

| Session | Build/probe | Mean frame ms | p99 ms | Post-creation maximum ms |
| --- | --- | ---: | ---: | ---: |
| `2026-10-03_16-51-58-980-whole-map` | Previous `bin_activation`, no probe | 9.629 | 19.601 | 50.541 |
| `2026-10-03_16-53-19-264-whole-map` | Candidate, probe off | 9.030 | 18.512 | 85.324 |
| `2026-10-03_16-54-39-500-whole-map` | Candidate, probe on | 8.885 | 18.500 | 74.972 |

This single baseline/candidate/probe sequence is a functional and timing sanity check, not a reliable speedup, regression or overhead estimate. The refactor intentionally skips no work. Variable simulation and transient stalls remain. Probe-on steady state produced 52 sampled traversals averaging 1.616 ms: before 0.444, online dispatch 0.713, offline dispatch 0.249 and after 0.023 ms. No traversal at least 10 ms occurred inside that measured window. Warmup did contain unsampled traversal spikes up to 57.360 ms; their internal phase attribution remains unknown.

## Transition fixture and limitations

The initial candidate roundtrip (`2026-10-03_16-55-59-619-whole-map`) acknowledged all three destinations but failed before its final save because the actor became dead or paused. The original assertion combined those conditions, so that run cannot distinguish them and is not counted as a pass. It exited normally after the driver reported failure; the runner correctly rejected the incomplete roundtrip.

The corrected fixture distinguishes death from pause and enables `g_god` at each destination, only in disposable test sessions, to isolate loading/reconciliation from survival at an artificial jump destination. The previous build completed this controlled roundtrip and acknowledged its save in `2026-10-03_16-58-54-478-whole-map`. Natural level exits, campaign encounters and unprotected actor survival remain outside this fixture's claims.

The candidate completed the same fixture with reconciliation timing enabled in `2026-10-03_17-00-01-913-whole-map`, acknowledged all three destinations and `reconcile_roundtrip.sav`, and exited with code zero. Overall: five regular sessions and two controlled transition sessions passed; the initial uncontrolled transition attempt is retained as a failed fixture. The real-method ordering fixture, activation lifetime/budget fixture and both evidence-analyzer fixtures passed. Original manual-play binary and Bar seed hashes were rechecked and are unchanged.

## Next boundary

Before suppressing recurring decisions, extract the scheduling/client-data obligations of the standard offline-object path and preserve the legacy group's cleanup/early-break behavior under tests. Then add notifications at registry membership and eligibility setters, initially retaining reconciliation for mutable Lua references and configuration changes. Compare event decisions against the scanner before letting events control transitions. This commit establishes the manager boundary and measurement baseline; it does not implement that event-driven policy or remove the fallback scan.

Reproduce the real-method fixture with CMake under `tools/profiling/reconciliation-test`; the evidence analyzer fixture is `python -B tools/profiling/Test-Reconciliation.py`. Run the game fixture with `Run-RegularValidation.ps1 -Package bin_reconcile -Count 400 -BudgetMs 3 -CompactQueue -ActivationQueue -ReconcileMetrics`; use `-Transitions` with zero extras for the controlled map roundtrip. Analyze ordinary timing sessions with `Summarize-Regular.py` and `Summarize-Reconciliation.py`. Both operate only on completed session evidence.
