The seed must start in the Bar and contain a previously visited Cordon with
partly broken physics objects. An intact new game cannot exercise saved partial
bone masks. Keep the same seed for control and fixed builds; session metadata
records its path and hash. The default is the local `bar-2026-10-03` capture.

```powershell
./Run-PhysicsReload.ps1 -InstallRoot $install -Package $package -Configuration Debug -SeedAppData seeds/bar-2026-10-03 -SaveName bar_center
```

The opt-in native probe checks hidden collision geometry and element bone IDs
after shell construction in both Debug and Release. Passing requires at least
one nonempty partial shell after the Cordon save/reload, not merely a clean exit.
It does not prove that every fracture was subsequently exercised. The original
Debug control reproduces the singular-transform assertion during splitting.

The runner uses the existing isolated A-Life runtime harness to cross maps;
the regression itself is independent of the selected A-Life switching policy.
