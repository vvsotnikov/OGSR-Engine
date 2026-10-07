# Native particle-pool regression

Use an isolated SoC installation prepared by `Prepare-RegularValidation.ps1`
and an original Bar save. Package a full-assertion Debug engine with its DLLs
and a `build.json` containing `configuration: Debug`, `tracyEnabled: false`,
and the executable's `sha256`.

```powershell
./Run-ParticlePoolValidation.ps1 -InstallRoot $install -Package $package
```

The runner uses private appdata and makes two technical Bar → Garbage → Bar
roundtrips. Passing requires the Debug engine to confirm that a group returned
to the pool with children was subsequently played with empty child lists.
Successful map loads alone are insufficient. This exercises the observed pooling
failure; it does not cover every particle definition.

CTest checks session preparation, failure recording, evidence rejection and Lua
syntax. It does not launch the game. `-PrepareOnly` is not runtime evidence.
`-TimeoutSeconds` changes the native run's 600-second watchdog for slower machines.

This probe lives beside the shared session/bootstrap helpers it uses. The runner
sets `-particle_pool_probe` to enable the Debug reuse log; ordinary Debug gameplay
does not emit it. The child-list assertion remains active in every Debug build.
