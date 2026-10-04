# Engine builds

Build `Engine.sln` with Visual Studio 2022 C++ tools and the provisioned third-party
dependencies. Use a short checkout path such as `D:\src\OGSR-Engine`: generated
FidelityFX header names can exceed MSVC's path limit in nested checkouts.
These MSBuild commands select the two x64 release variants:

```powershell
MSBuild Engine.sln /m:4 /p:Configuration=Release /p:Platform=x64
MSBuild Engine.sln /m:4 /p:Configuration=ReleaseTracyProfiler /p:Platform=x64
```

Select `ReleaseTracyProfiler|x64` directly in Visual Studio's configuration selector.
Its engine projects use Tracy instrumentation; third-party projects map to Release.
For compatibility with existing scripts, `Configuration=Release` with
`CONFIGURATION_GA=ReleaseTracyProfiler` still selects the same instrumented outputs.
Use the real configuration in Visual Studio so its configuration selector reflects
what is being built. Debug ignores the legacy Tracy switch.

| Variant | Executables | Engine libraries and intermediates |
| --- | --- | --- |
| Release | `bin_x64` | `_LIB/Engine/Release/x64`, `_TEMP/Engine/Release/x64` |
| ReleaseTracyProfiler | `bin_x64_tracy` | `_LIB/Engine/ReleaseTracyProfiler/x64`, `_TEMP/Engine/ReleaseTracyProfiler/x64` |
| Debug | `bin_x64_debug` | `_LIB/Engine/Debug/x64`, `_TEMP/Engine/Debug/x64` |

Debug executables now live in `bin_x64_debug` instead of `bin_x64`. Update Debug
launch commands and executable-directory links to use that directory.

Library and intermediate paths are under `ogsr_engine`. Visual Studio and
command-line builds use these same directories. Uninstrumented third-party release
libraries are shared by both release variants; engine libraries never fall back
to another variant. LuaJIT's provisioned library is copied into each variant only
when its source changes.

The executable's generated version header lives in its intermediate directory.
MSBuild refreshes it when executable sources/resources, input libraries, its
project/generation target, or CI version properties change. An unchanged build
keeps the timestamp and avoids a resource-only link. `BUILD_DATE` and `BUILD_TIME`
record the last metadata regeneration, not every invocation of Build. Clean removes
the generated files, so Rebuild regenerates them even when sources are unchanged.

Do not run concurrent builds of the same variant in one worktree.
