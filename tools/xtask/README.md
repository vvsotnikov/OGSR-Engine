# Local validation

Install Visual Studio C++ Build Tools (the engine's SDK/toolset requirements),
Rust 1.89 or later with rustfmt, CMake, and Git. The workflow pins Rust 1.99.0.
Rust is the chosen language for new project tooling and the planned simulation
module. Python/PowerShell are additionally required by suites using them.
Prepare engine dependencies separately; validation never runs the destructive
`Update_Components.cmd` updater.

```powershell
cargo xtask install-hooks
cargo xtask validate
```

Both pre-commit and pre-merge-commit run formatting, Rust tests, all immediate
CMake test suites, and both x64 engine variants. `cargo xtask validate --tests-only`
omits engine builds; `--configuration Release`, `ReleaseTracyProfiler`, or `Debug`
selects one build. These options do not weaken the hooks.
The validator reads the solution configuration table: when a real Tracy
configuration exists, it selects it and clears inherited `CONFIGURATION_GA`.
Older layouts receive the legacy switch and version metadata. This prevents a
Tracy check from silently becoming a second ordinary Release build.
Set `OGSR_BUILD_JOBS` to a positive integer to override the default four workers.
CTest cases have a two-minute timeout. Rust hook integration tests require
Windows/MSVC and test failures against real disposable Git repositories.
Failed fixtures print their retained directory for diagnosis.

Validation uses the engine's existing MSBuild configuration and output paths.
Release and Tracy run sequentially; with shared output paths, switching variants
recompiles affected objects. A partial commit, or untracked
source/tooling that could enter a build, uses a persistent detached worktree of
the Git index instead. Its separate cache is cold on first use. The hook does
not stash, overwrite, or clean the developer's working files. Unrelated scratch
files such as root-level notes and logs do not force isolation. An index change
during validation fails the commit rather than approving a different tree.

The staged worktree borrows existing ignored third-party dependency checkouts
and copies provisioned LuaJIT binaries for older build layouts; these remain local inputs, so this is not
a hermetic build. It refuses staged files overlapping a borrowed dependency.
Do not edit build inputs or run another build in the checkout being validated.
An OS-backed per-worktree lock prevents overlapping validators and is released on
process termination; the lock file may persist harmlessly. If killing only the
validator leaves child build processes alive, stop those before starting another
build. `cargo xtask validate` explicitly validates the working directory rather
than the staged snapshot.

Installation writes shared dispatchers that execute the current worktree's
tracked `.githooks/pre-commit`. Hook changes take effect without reinstallation;
rerun installation to add a newly supported hook event. Linked worktrees inherit
enforcement; branches missing the
infrastructure must incorporate it before committing. Existing custom hooks,
including global configuration, are not silently overridden. Hooks and the validator
must themselves be runnable in the working directory to start staged validation.
Git hooks are a local guard that can be bypassed, not server-side enforcement.

Logs are in `target/validation` in the checkout being validated; CTest diagnostics are under
`target/validation/tests/Testing/Temporary`. Passing these checks does not
establish gameplay/E2E correctness. Game scenarios remain separate.
GitHub workflow enablement is independent and remains disabled.
