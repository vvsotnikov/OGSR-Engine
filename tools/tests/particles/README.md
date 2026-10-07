# Native particle-pool regression

A pooled particle group retains its compiled emitters and their callbacks. It
must discard both related and free children before those emitters reset their
particle arrays. Related-child indices correspond to the emitter's particle
indices; keeping old children breaks that correspondence on the next playback.

Use an isolated SoC installation prepared by the existing
`alife-policy/runtime/Prepare-RegularValidation.ps1` and an original Bar save.
Package a full-assertion Debug engine with its DLLs and a `build.json` containing
`configuration: Debug`, `tracyEnabled: false`, and the executable's `sha256`.

```powershell
./Run-ParticlePoolValidation.ps1 -InstallRoot $install -Package $package
```

The runner uses private appdata and technical Bar → Garbage → Bar transitions
twice. Loading Garbage instantiates anomaly effects that reuse pooled groups;
the engine's particle/child assertions check the actual renderer state. This is
a regression for the observed transition failure, not exhaustive coverage of all
particle definitions. No synthetic NPCs or proprietary game assets are included.
The regular local build checks do not launch this gameplay test. `-PrepareOnly`
writes inputs without launching the engine and is not runtime evidence.
