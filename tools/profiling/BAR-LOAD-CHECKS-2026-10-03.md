# Bar load checks

Four fresh-process, stationary load checks passed using the preserved campaign seed `seeds/bar-2026-10-03`. Engine SHA-256: `DCF443508EE651C1D0B783AE8F1302EBC3B3C87A16E9A0973F5A1FB71F65733E`. Seed save hashes still match the seed manifest after testing.

| Save | Mode | Local session | Observed living online/offline |
| --- | --- | --- | --- |
| bar_approach | distance | 2026-10-03_10-02-20-700-distance | 23 / 101 |
| bar_approach | whole-map | 2026-10-03_10-04-06-568-whole-map | 68–69 / 45 |
| bar_center | distance | 2026-10-03_10-05-07-680-distance | 55 / 69 |
| bar_center | whole-map | 2026-10-03_10-05-45-182-whole-map | 75 / 39 initially |

These are load/correctness smoke observations, not a performance comparison. Whole-map runs included verbose offline diagnostics, and no Tracy collector ran. Some population totals changed after activation; do not interpret online counts as a conserved total or proof of identical campaign outcomes. Bar script-controlled switching remains in effect, including visitor exclusions. Exact conditions and activation-related removals require further investigation.

Automated keypresses did not operate the game menu. Each test process was stopped explicitly after its private log demonstrated successful loading and simulation. Therefore normal shutdown, save/reload within a session, natural transitions and campaign correctness are not established by these checks.

## Prepared paired playtest

Local launchers `Profile-Bar-Normal.cmd` and `Profile-Bar-Whole-Map.cmd` use `bar_approach` from the same preserved seed. Each creates private appdata, waits 30 seconds after process launch, then records up to 90 seconds with the existing 20% collector memory cap. Verbose offline diagnostics are disabled for these comparisons.

For both runs: after loading, stay still for 30 seconds, then walk through the checkpoint into the central Bar area along the same route. Keep the game open for at least two minutes after loading. Avoid menus, screenshots and saves during recording. Close normally before the second run. Inspect actual recorded intervals and memory-limit status before comparing; the launcher delay is not a gameplay-ready marker.
