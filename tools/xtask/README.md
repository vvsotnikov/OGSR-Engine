# Local validation

Install Visual Studio C++ Build Tools, CMake, Git and rustup. The repository's
`rust-toolchain.toml` selects Rust and rustfmt for both local and GitHub runs.
Provision engine dependencies separately; validation never runs `Update_Components.cmd`.

```powershell
cargo xtask install-hooks
cargo xtask validate
```

`pre-commit` and `pre-merge-commit` run formatting, Rust tests, registered CTest
suites, and native x64 Release, ReleaseTracyProfiler and assertion-enabled Debug builds. An inherited
`CONFIGURATION_GA` is cleared. All variants retain separate incremental caches;
an engine change must still compile in each variant, and a shared header can
cause three broad rebuilds. `OGSR_BUILD_JOBS` overrides the default four workers.
Debug keeps the engine's full `DEBUG` path: `VERIFY` checks, diagnostic state,
and the retained AI/physics debug tools. The startup log reports
`Debug assertions: enabled`. Validation passes `OgsrRequireDebugAssertions=true`
to every engine project and rejects overrides that suppress these checks.
IDE and validation Debug builds use the same compiler definitions and cache.
A standalone developer build can opt out with `DISABLE_DBG_ASSERTIONS` and
`/p:OgsrRequireDebugAssertions=false`; that build does not satisfy validation. Adding or removing the optional override
header also invalidates compiler inputs, even if it was absent from the previous
build's dependency log.

Full Debug also enables the existing gameplay diagnostic keys: Enter/NumpadEnter
consume the key to toggle `bDebug`; F4 cycles the current entity; Alt+left-click
switches the viewed entity; keypad `/` and `*` change the game-time factor.
Use Release for ordinary gameplay without these Debug input overrides.

CTest cases have a two-minute timeout. Failed Rust integration fixtures are
retained at the path printed in the failure output.

`cargo xtask validate --tests-only` omits engine builds. `--configuration Release`,
`ReleaseTracyProfiler`, or `Debug` selects one build. These options do not weaken
the hooks. GitHub workflow enablement is independent and remains disabled.

A partial commit, hidden index flags, or extra source/tooling input uses a
persistent detached worktree of the index. Only its named build caches survive
reuse; tracked edits and stale untracked inputs are discarded there, including ignored files. This snapshot is
owned by the validator, not a place to edit source. Developer working files and
index contents are never stashed or cleaned. Root scratch notes/logs do not force
isolation. Source/tooling roots are checked regardless of file extension or ignore
rules; known dependencies, build outputs and Python bytecode caches are excluded.
The hook prints paths that force isolation. Local `.vcxproj.user` files and
`build_config_overrides/` can change build settings and therefore remain inputs.
Keep them if needed and accept isolation; move unused files outside the checkout.
Resource-editor `.aps` files and Explorer metadata are non-inputs. Obsolete
`ogsr_engine/LuaJIT/bin` output triggers isolation; archive it outside source
directories when no longer needed.
Put custom build outputs in `target/` or `tools/tests/<suite>/build/`.

The snapshot borrows the dependency directories provisioned by
`Update_Components.cmd`. They remain local inputs, so validation is not hermetic.
Staged files cannot overlap those directories or reserved cache paths. Junctions
are detached before source cleanup without following their targets. A missing
registered snapshot is recreated automatically. To discard its caches and source:

```powershell
cargo xtask reset-snapshot
```

Reset removes only this worktree's registered validation snapshot and its metadata,
never dependency targets. Use that command instead of recursively deleting the
snapshot by hand. Other registered worktrees are not pruned. After moving a
repository, repair Git's absolute worktree paths with
`git worktree repair <snapshot-path>` before retrying.
The refusal message gives the snapshot path. Do not repair a path redirected by a
junction; the ownership check intentionally rejects it.

Do not edit inputs or run another build in a checkout being validated. Per-worktree
OS locks exclude overlapping validators and reset operations, and release on
process termination. If killing a validator leaves child builds alive, stop them
before another build. An index change during validation rejects the commit.
`cargo xtask validate` checks working files rather than creating an index snapshot.

Installation creates shared dispatchers that execute the current worktree's
tracked hook; existing custom hooks are not overwritten. Linked worktrees inherit
the dispatchers, and branches lacking validation tooling cannot commit through
them. Reinstall to add newly supported hook events. Git rebase, cherry-pick,
revert, am and fast-forward merges are not gated by these hooks: explicitly run
`cargo xtask validate` on their result before publishing. Local hooks are
bypassable and require runnable tooling; they are not server-side enforcement.

Logs are in `target/validation` in the validated checkout; CTest diagnostics are
under `target/validation/tests/Testing/Temporary`. These checks do not establish
gameplay/E2E correctness; game scenarios remain separate.
