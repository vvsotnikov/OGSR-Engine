# Offline inventory and input initialization

Diagnostic session: `2026-10-03_00-09-41-883-whole-map`, private copy of the same Cordon seed used for the paired playtest. No Tracy collector or player route was required. Engine SHA-256: `DCF443508EE651C1D0B783AE8F1302EBC3B3C87A16E9A0973F5A1FB71F65733E`. Build succeeded in Release with Tracy instrumentation; existing compiler warnings remain.

At game time 20,595 ms, all sixteen living offline entities returned `can_online=0`, `matches=1`, `uses_ai=1`, with no parent or group (`65535`). Subsequent inventories repeated these exclusions.

| Entities | Server IDs | Count |
| --- | --- | ---: |
| esc_fox | 300 | 1 |
| esc_stalker_fanat | 510 | 1 |
| esc_killer1/2/3/4/6/7/8 | 518, 525, 532, 538, 545, 551, 557 | 7 |
| esc_provodnik | 660 | 1 |
| esc_dog_weak and numbered variants | 740, 742, 743, 744, 745 | 5 |
| esc_pseudodog_strong (pseudodog_weak section) | 1037 | 1 |

Fox's flags were `0xFFFFFFF3`, all others `0xFFFFFFBF`. Both values contain `flSwitchOnline` (bit 1). The native `CSE_ALifeObject::can_switch_online` implementation would therefore accept them given `matches=1`. The creature implementation forwards to that base; `INHERIT_ALIFE` provides a Lua virtual override. The evidence points to script eligibility overrides, not a distance failure or group representatives. Exact script conditions have not yet been extracted/traced from the packaged resources. Do not force these entities online or claim all campaign behavior validated.

## Input change

The input fix described below was subsequently extracted unchanged into [PR #5](https://github.com/vvsotnikov/OGSR-Engine/pull/5) and removed from the whole-map branch. This section records the historical diagnostic build; retained binaries and captures still include that fix.

The October 2 dump identifies an unchecked failed DirectInput `CreateDevice` call followed by a null dereference. Release-mode `CHK_DX` does not validate HRESULTs. Initialization now checks DirectInput creation, device creation, data format, cooperative level and buffer setup, reports operation/HRESULT, and exits if the error handler returns. The existing cooperative-level `E_NOTIMPL` exception is preserved. Keyboard/mouse identity is logged immediately before setup.

This is failure handling, not recovery from the underlying intermittent DirectInput error. The USB switcher hypothesis remains unverified. The rebuilt executable initialized keyboard/mouse and loaded the seed successfully. A debugger-induced failure-path test remains pending; successful startup alone does not test that branch.

The capture script now preserves an explicit `game-exited-before-capture` status and exit code instead of leaving an early-exit session marked prepared. Its syntax and diagnostic PrepareOnly path were checked; an actual early-exit capture has not yet exercised the new status branch.

See NEXT-VALIDATION.md for crowded-location, transition and persistence checks. These are prepared procedures, not completed tests.
