# Engine builds

Build `Engine.sln` with Visual Studio 2022 C++ tools and the provisioned third-party
dependencies. Use a short checkout path such as `D:\src\OGSR-Engine`: generated
FidelityFX header names can exceed MSVC's path limit in nested checkouts.
These MSBuild commands select the two x64 release variants:

```powershell
MSBuild Engine.sln /m:4 /p:Configuration=Release /p:Platform=x64
MSBuild Engine.sln /m:4 /p:Configuration=Release /p:Platform=x64 /p:CONFIGURATION_GA=ReleaseTracyProfiler
```

`CONFIGURATION_GA=ReleaseTracyProfiler` can also be set in the environment before
starting Visual Studio. Both commands use the existing Release solution
configuration; the shared property sheets separate the effective build variants.
Debug remains available through `Configuration=Debug` and ignores the Tracy switch.

| Variant | Executables | Engine libraries and intermediates |
| --- | --- | --- |
| Release | `bin_x64` | `_LIB/Engine/Release/x64`, `_TEMP/Engine/Release/x64` |
| ReleaseTracyProfiler | `bin_x64_tracy` | `_LIB/Engine/ReleaseTracyProfiler/x64`, `_TEMP/Engine/ReleaseTracyProfiler/x64` |
| Debug | `bin_x64_debug` | `_LIB/Engine/Debug/x64`, `_TEMP/Engine/Debug/x64` |

Library and intermediate paths are under `ogsr_engine`. Visual Studio and
command-line builds use these same directories. Uninstrumented third-party release
libraries are shared by both release variants; engine libraries never fall back
to another variant. LuaJIT's provisioned library is copied into each variant only
when its source changes.

The executable's generated version header lives in its intermediate directory.
MSBuild refreshes it when executable sources/resources, input libraries, its
project/generation target, or CI version properties change. An unchanged build
keeps the timestamp and avoids a resource-only link. This is build-time metadata,
not a source revision identifier or a reproducible-build guarantee.

Do not run concurrent builds of the same variant in one worktree.
