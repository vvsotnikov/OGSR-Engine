# Whole-map validation procedure

Use private session saves. Keep the original seed and the October 2 paired captures unchanged. Diagnostic runs establish correctness; timing comparisons must omit verbose diagnostics and use identical executables/settings/saves.

## Offline inventory

Prepare a whole-map session with `Capture-Session.ps1 -Diagnostics -PrepareOnly`. Launch its recorded command line, allow at least ten unpaused metrics samples, and inspect `[ALife offline]` entries. No walking route or Tracy connection is needed for this inventory. Classify each entity against the corresponding script/configuration and switching code. A false `can_online` flag is a reason for exclusion, not permission to override story logic. Group representatives are not necessarily individual NPCs.

## Crowded location

Prefer a campaign save near the Bar entrance. Preserve a copy as the common seed. Run normal and whole-map policies on the same build: wait for loading, walk into the Bar, follow the same route, then stand still for a minute. Record population and long frames; distinguish activation work from steady-state work. Keep quicksaves and screenshots outside the measured interval, then test a quicksave separately.

The engine console supports `jump_to_level l05_bar` for a disposable technical smoke test. This exercises a direct engine level jump; it does not validate natural campaign transitions or establish that the location's population matches normal campaign progress.

## Transitions and persistence

First perform a technical jump from Cordon to the Bar and back, checking level IDs, population settling, logs and shutdown. Then test a natural level changer from a suitable campaign save. Verify that old-map objects go offline, destination eligibility remains respected, and no entities are duplicated. Counts alone cannot establish identity or campaign correctness.

Create a separately named save, reload it, and compare identities and switching flags after settling. Repeat with a full process restart. Check an NPC conversation, task completion and a scripted encounter. Preserve failures and their private saves; do not overwrite the common seed.

## Input initialization

This separate validation belongs to [DirectInput PR #5](https://github.com/vvsotnikov/OGSR-Engine/pull/5), now merged and included via main. Its failure injection passed; PR #6 subsequently fixed and verified readable HRESULT text. The procedure below is retained for future regression checks, not an outstanding whole-map gate.

The release build must check DirectInput creation, device creation, data format, cooperative level and buffer setup. Preserve the existing E_NOTIMPL cooperative-level exception. A failure should identify the operation and HRESULT and stop before registering frame callbacks. Successful launches do not validate the failure path or prove the USB switcher's involvement. Test failure handling separately using a debugger-induced HRESULT failure; never disable physical input devices or change their registration for this test.
