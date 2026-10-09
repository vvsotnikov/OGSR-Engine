#![cfg(windows)]

use std::{
    fs,
    path::{Path, PathBuf},
    process::{Command, Output},
    time::{SystemTime, UNIX_EPOCH},
};

fn execute(root: &Path, program: &str, args: &[&str]) -> Output {
    let mut command = Command::new(program);
    command.current_dir(root).args(args);
    for (key, _) in std::env::vars().filter(|(key, _)| key.starts_with("GIT_")) {
        command.env_remove(key);
    }
    command.env("CARGO_TARGET_DIR", root.join("target"));
    command.output().unwrap()
}
fn output_text(output: &Output) -> String {
    format!(
        "{}{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    )
}
fn ok(root: &Path, program: &str, args: &[&str]) -> Output {
    let output = execute(root, program, args);
    assert!(output.status.success(), "{}", output_text(&output));
    output
}
struct Fixture(PathBuf);
impl Fixture {
    fn new(source_code: &str, assertion: &str) -> Self {
        let source = Path::new(env!("CARGO_MANIFEST_DIR")).join("../..");
        let unique = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let root = std::env::temp_dir().join(format!("ogsr-hook-{}-{unique}", std::process::id()));
        fs::create_dir_all(&root).unwrap();
        for file in [
            "Cargo.toml",
            // Nested unit tests verify dependency roots against this provisioner.
            "Update_Components.cmd",
            "Cargo.lock",
            "rust-toolchain.toml",
            ".gitattributes",
            ".cargo/config.toml",
            ".githooks/pre-commit",
            "tools/xtask/Cargo.toml",
            "tools/tests/CMakeLists.txt",
        ] {
            let dest = root.join(file);
            fs::create_dir_all(dest.parent().unwrap()).unwrap();
            fs::copy(source.join(file), dest).unwrap();
        }
        fn copy_sources(source: &Path, destination: &Path) {
            fs::create_dir_all(destination).unwrap();
            for entry in fs::read_dir(source).unwrap() {
                let entry = entry.unwrap();
                let target = destination.join(entry.file_name());
                if entry.file_type().unwrap().is_dir() {
                    copy_sources(&entry.path(), &target);
                } else {
                    fs::copy(entry.path(), target).unwrap();
                }
            }
        }
        copy_sources(
            &source.join("tools/xtask/src"),
            &root.join("tools/xtask/src"),
        );
        copy_sources(
            &source.join("ogsr_engine/npc_sim"),
            &root.join("ogsr_engine/npc_sim"),
        );
        fs::write(root.join(".gitignore"), "/target/\n/linked/\n").unwrap();
        fs::create_dir_all(root.join("tools/tests/fixture")).unwrap();
        fs::write(root.join("tools/tests/fixture/CMakeLists.txt"), format!(
            "add_executable(fixture ../fixture.cpp)\nadd_test(NAME assertion COMMAND ${{CMAKE_COMMAND}} -E {assertion})\n")).unwrap();
        fs::write(root.join("tools/tests/fixture.cpp"), source_code).unwrap();
        fs::write(root.join("Fixture.vcxproj"), r#"<Project DefaultTargets="Build" xmlns="http://schemas.microsoft.com/developer/msbuild/2003"><Target Name="Build" /></Project>"#).unwrap();
        fs::write(root.join("Engine.sln"), "Microsoft Visual Studio Solution File, Format Version 12.00\nProject(\"{8BC9CEB8-8B4A-11D0-8D11-00A0C91BC942}\") = \"Fixture\", \"Fixture.vcxproj\", \"{11111111-1111-1111-1111-111111111111}\"\nEndProject\nGlobal\n GlobalSection(SolutionConfigurationPlatforms) = preSolution\n Debug|x64 = Debug|x64\n Release|x64 = Release|x64\n ReleaseTracyProfiler|x64 = ReleaseTracyProfiler|x64\n EndGlobalSection\n GlobalSection(ProjectConfigurationPlatforms) = postSolution\n {11111111-1111-1111-1111-111111111111}.Debug|x64.ActiveCfg = Debug|x64\n {11111111-1111-1111-1111-111111111111}.Debug|x64.Build.0 = Debug|x64\n {11111111-1111-1111-1111-111111111111}.Release|x64.ActiveCfg = Release|x64\n {11111111-1111-1111-1111-111111111111}.Release|x64.Build.0 = Release|x64\n {11111111-1111-1111-1111-111111111111}.ReleaseTracyProfiler|x64.ActiveCfg = ReleaseTracyProfiler|x64\n {11111111-1111-1111-1111-111111111111}.ReleaseTracyProfiler|x64.Build.0 = ReleaseTracyProfiler|x64\n EndGlobalSection\nEndGlobal\n").unwrap();
        ok(&root, "git", &["init"]);
        ok(&root, "git", &["config", "core.autocrlf", "true"]);
        ok(&root, "git", &["config", "user.name", "Validation Fixture"]);
        ok(
            &root,
            "git",
            &["config", "user.email", "fixture@example.invalid"],
        );
        ok(&root, "git", &["add", "."]);
        ok(
            &root,
            "git",
            &[
                "-c",
                "core.hooksPath=disabled-hooks",
                "commit",
                "-m",
                "test: seed fixture",
            ],
        );
        ok(&root, env!("CARGO_BIN_EXE_xtask"), &["install-hooks"]);
        Self(root)
    }
    fn reject_at(root: &Path, expected: &str) {
        let before = ok(root, "git", &["rev-parse", "HEAD"]).stdout;
        let result = execute(
            root,
            "git",
            &["commit", "--allow-empty", "-m", "test: must fail"],
        );
        let log = output_text(&result);
        assert!(!result.status.success() && log.contains(expected), "{log}");
        assert_eq!(before, ok(root, "git", &["rev-parse", "HEAD"]).stdout);
    }
}
impl Drop for Fixture {
    fn drop(&mut self) {
        if std::thread::panicking() {
            eprintln!("Failed fixture retained at {}", self.0.display());
        } else {
            fs::remove_dir_all(&self.0).unwrap();
        }
    }
}
#[test]
fn partial_commit_preserves_working_changes_and_ignores_untracked_suite() {
    let fixture = Fixture::new("int main() {}\n", "true");
    let file = fixture.0.join("tools/tests/fixture.cpp");
    fs::write(&file, "int main() { return 0; } // staged\n").unwrap();
    ok(&fixture.0, "git", &["add", "tools/tests/fixture.cpp"]);
    fs::write(&file, "unstaged broken code\n").unwrap();
    fs::write(fixture.0.join("notes.txt"), "keep my notes\n").unwrap();
    let extra = fixture.0.join("tools/tests/extra");
    fs::create_dir(&extra).unwrap();
    fs::write(
        extra.join("CMakeLists.txt"),
        "message(FATAL_ERROR untracked)\n",
    )
    .unwrap();
    ok(
        &fixture.0,
        "git",
        &["commit", "-m", "test: staged snapshot"],
    );
    assert_eq!(fs::read_to_string(&file).unwrap(), "unstaged broken code\n");
    assert_eq!(
        fs::read_to_string(fixture.0.join("notes.txt")).unwrap(),
        "keep my notes\n"
    );
    assert!(extra.join("CMakeLists.txt").exists());
    let committed = ok(&fixture.0, "git", &["show", "HEAD:tools/tests/fixture.cpp"]);
    assert!(String::from_utf8_lossy(&committed.stdout).contains("// staged"));
}
#[test]
fn failed_partial_commit_preserves_index_and_worktree() {
    let fixture = Fixture::new("int main() {}\n", "true");
    let file = fixture.0.join("tools/tests/fixture.cpp");
    fs::write(&file, "broken staged code\n").unwrap();
    ok(&fixture.0, "git", &["add", "tools/tests/fixture.cpp"]);
    let tree = ok(&fixture.0, "git", &["write-tree"]).stdout;
    fs::write(&file, "int main() {} // working fix\n").unwrap();
    Fixture::reject_at(&fixture.0, "command failed");
    assert_eq!(tree, ok(&fixture.0, "git", &["write-tree"]).stdout);
    assert!(fs::read_to_string(&file).unwrap().contains("working fix"));
}
#[test]
fn unrelated_scratch_files_do_not_require_a_snapshot() {
    let fixture = Fixture::new("int main() {}\n", "true");
    fs::write(fixture.0.join("notes.txt"), "scratch notes").unwrap();
    fs::write(fixture.0.join("design.md"), "scratch design").unwrap();
    let result = ok(
        &fixture.0,
        "git",
        &["commit", "--allow-empty", "-m", "test: ordinary commit"],
    );
    assert!(!output_text(&result).contains("Validating staged files in"));
}
#[test]
fn automatic_merge_runs_validation() {
    let fixture = Fixture::new("int main() {}\n", "false");
    let branch = String::from_utf8(ok(&fixture.0, "git", &["branch", "--show-current"]).stdout)
        .unwrap()
        .trim()
        .to_owned();
    ok(&fixture.0, "git", &["switch", "-c", "topic"]);
    fs::write(fixture.0.join("topic.txt"), "topic").unwrap();
    ok(&fixture.0, "git", &["add", "topic.txt"]);
    ok(
        &fixture.0,
        "git",
        &[
            "-c",
            "core.hooksPath=disabled-hooks",
            "commit",
            "-m",
            "test: topic",
        ],
    );
    ok(&fixture.0, "git", &["switch", &branch]);
    fs::write(fixture.0.join("base.txt"), "base").unwrap();
    ok(&fixture.0, "git", &["add", "base.txt"]);
    ok(
        &fixture.0,
        "git",
        &[
            "-c",
            "core.hooksPath=disabled-hooks",
            "commit",
            "-m",
            "test: base",
        ],
    );
    let before = ok(&fixture.0, "git", &["rev-parse", "HEAD"]).stdout;
    let result = execute(&fixture.0, "git", &["merge", "--no-edit", "topic"]);
    assert!(
        !result.status.success() && output_text(&result).contains("ctest"),
        "{}",
        output_text(&result)
    );
    assert_eq!(before, ok(&fixture.0, "git", &["rev-parse", "HEAD"]).stdout);
}
#[test]
fn snapshot_reuses_cache_and_protects_borrowed_dependencies() {
    let fixture = Fixture::new("int main() {}\n", "true");
    let dependency = fixture.0.join("3rd_party/Src/DirectXMath/DirectXMath");
    fs::create_dir_all(&dependency).unwrap();
    ok(&dependency, "git", &["init"]);
    fs::write(dependency.join("source.cpp"), "original dependency\n").unwrap();
    fs::write(
        fixture.0.join(".gitignore"),
        "/target/\n/linked/\n/3rd_party/Src/DirectXMath/DirectXMath/\n",
    )
    .unwrap();
    ok(&fixture.0, "git", &["add", ".gitignore"]);
    let tree = String::from_utf8(ok(&fixture.0, "git", &["write-tree"]).stdout).unwrap();
    let snapshot = xtask::snapshot::prepare(&fixture.0, tree.trim()).unwrap();
    assert_eq!(
        fs::read(snapshot.join("3rd_party/Src/DirectXMath/DirectXMath/source.cpp")).unwrap(),
        b"original dependency\n"
    );
    fs::create_dir_all(snapshot.join("target")).unwrap();
    fs::write(snapshot.join("target/cache-marker"), "keep cache").unwrap();
    ok(&fixture.0, "git", &["rm", "tools/tests/fixture.cpp"]);
    let tree = String::from_utf8(ok(&fixture.0, "git", &["write-tree"]).stdout).unwrap();
    assert_eq!(
        xtask::snapshot::prepare(&fixture.0, tree.trim()).unwrap(),
        snapshot
    );
    assert!(!snapshot.join("tools/tests/fixture.cpp").exists());
    assert!(snapshot.join("target/cache-marker").exists());
    // Stage a path beneath the junction without changing the dependency itself.
    let blob = String::from_utf8(
        ok(
            &fixture.0,
            "git",
            &["rev-parse", "HEAD:tools/tests/fixture.cpp"],
        )
        .stdout,
    )
    .unwrap();
    ok(
        &fixture.0,
        "git",
        &[
            "update-index",
            "--add",
            "--cacheinfo",
            "100644",
            blob.trim(),
            "3rd_party/Src/DIRECTXMATH/DIRECTXMATH/source.cpp",
        ],
    );
    let tree = String::from_utf8(ok(&fixture.0, "git", &["write-tree"]).stdout).unwrap();
    assert!(xtask::snapshot::prepare(&fixture.0, tree.trim())
        .unwrap_err()
        .to_string()
        .contains("overlap borrowed dependency"));
    assert_eq!(
        fs::read(dependency.join("source.cpp")).unwrap(),
        b"original dependency\n"
    );
}
#[test]
fn compile_failure_blocks_commit() {
    let fixture = Fixture::new("cannot compile\n", "true");
    Fixture::reject_at(&fixture.0, "command failed");
}
#[test]
fn assertion_failure_blocks_commit() {
    let fixture = Fixture::new("int main() {}\n", "false");
    Fixture::reject_at(&fixture.0, "ctest");
}
#[test]
fn engine_failure_blocks_commit() {
    let fixture = Fixture::new("int main() {}\n", "true");
    ok(&fixture.0, "git", &["rm", "Engine.sln"]);
    Fixture::reject_at(&fixture.0, "Engine.sln");
}
#[test]
fn dispatcher_uses_current_hook_and_enforces_linked_worktrees() {
    let fixture = Fixture::new("int main() {}\n", "true");
    fs::write(
        fixture.0.join(".githooks/pre-commit"),
        "#!/bin/sh\necho UPDATED_TRACKED_HOOK >&2\nexit 1\n",
    )
    .unwrap();
    Fixture::reject_at(&fixture.0, "UPDATED_TRACKED_HOOK");
    let linked = fixture.0.join("linked");
    ok(
        &fixture.0,
        "git",
        &[
            "worktree",
            "add",
            "--detach",
            linked.to_str().unwrap(),
            "HEAD",
        ],
    );
    fs::write(linked.join("tools/tests/fixture.cpp"), "unstaged edit\n").unwrap();
    fs::write(
        linked.join(".githooks/pre-commit"),
        "#!/bin/sh\necho LINKED_HOOK >&2\nexit 1\n",
    )
    .unwrap();
    Fixture::reject_at(&linked, "LINKED_HOOK");
    fs::remove_file(linked.join(".githooks/pre-commit")).unwrap();
    Fixture::reject_at(&linked, "Bring the validation infrastructure");
}

#[test]
fn native_tracy_selection_clears_inherited_legacy_switch() {
    let fixture = Fixture::new("int main() {}\n", "true");
    fs::write(fixture.0.join("Fixture.vcxproj"), r#"<Project DefaultTargets="Build" xmlns="http://schemas.microsoft.com/developer/msbuild/2003"><Target Name="Build"><Error Condition="'$(CONFIGURATION_GA)'!=''" Text="UNEXPECTED_LEGACY_SWITCH" /><Error Condition="'$(Configuration)'=='ReleaseTracyProfiler'" Text="NATIVE_TRACY_FAILURE" /></Target></Project>"#).unwrap();
    ok(&fixture.0, "git", &["add", "Engine.sln", "Fixture.vcxproj"]);
    let before = ok(&fixture.0, "git", &["rev-parse", "HEAD"]).stdout;
    let mut command = Command::new("git");
    command
        .current_dir(&fixture.0)
        .args(["commit", "-m", "test: native Tracy must fail"])
        .env("CONFIGURATION_GA", "ReleaseTracyProfiler")
        .env("CARGO_TARGET_DIR", fixture.0.join("target"));
    for (key, _) in std::env::vars().filter(|(key, _)| key.starts_with("GIT_")) {
        command.env_remove(key);
    }
    let output = command.output().unwrap();
    let log = output_text(&output);
    assert!(
        !output.status.success() && log.contains("NATIVE_TRACY_FAILURE"),
        "{log}"
    );
    assert!(!log.contains("UNEXPECTED_LEGACY_SWITCH"), "{log}");
    assert_eq!(before, ok(&fixture.0, "git", &["rev-parse", "HEAD"]).stdout);
}

#[test]
fn dirty_snapshot_and_changed_ignore_rules_cannot_supply_source() {
    let fixture = Fixture::new("int main() {}\n", "true");
    let tree = String::from_utf8(ok(&fixture.0, "git", &["write-tree"]).stdout).unwrap();
    let snapshot = xtask::snapshot::prepare(&fixture.0, tree.trim()).unwrap();
    fs::write(snapshot.join("tools/tests/fixture.cpp"), "contaminated").unwrap();
    fs::create_dir_all(snapshot.join("tools/tests/stale")).unwrap();
    fs::write(
        snapshot.join("tools/tests/stale/CMakeLists.txt"),
        "message(FATAL_ERROR stale)",
    )
    .unwrap();
    fs::write(snapshot.join("old-input.inc"), "ignored source").unwrap();
    fs::create_dir_all(snapshot.join("target")).unwrap();
    fs::write(snapshot.join("target/cache-marker"), "keep").unwrap();
    fs::write(
        fixture.0.join(".gitignore"),
        "/target/\n/old-input.inc\n/tools/tests/stale/\n",
    )
    .unwrap();
    ok(&fixture.0, "git", &["add", ".gitignore"]);
    let tree = String::from_utf8(ok(&fixture.0, "git", &["write-tree"]).stdout).unwrap();
    xtask::snapshot::prepare(&fixture.0, tree.trim()).unwrap();
    assert!(fs::read_to_string(snapshot.join("tools/tests/fixture.cpp"))
        .unwrap()
        .contains("int main"));
    assert!(!snapshot.join("tools/tests/stale").exists());
    assert!(!snapshot.join("old-input.inc").exists());
    assert!(snapshot.join("target/cache-marker").exists());
}

#[test]
fn reset_and_missing_snapshot_preserve_dependency_targets() {
    let fixture = Fixture::new("int main() {}\n", "true");
    let dependency = fixture.0.join("3rd_party/Src/DirectXMath/DirectXMath");
    fs::create_dir_all(&dependency).unwrap();
    fs::write(dependency.join("sentinel"), "keep dependency").unwrap();
    let tree = String::from_utf8(ok(&fixture.0, "git", &["write-tree"]).stdout).unwrap();
    let snapshot = xtask::snapshot::prepare(&fixture.0, tree.trim()).unwrap();
    // A changed ignore rule must never cause cleanup to traverse this junction.
    fs::write(fixture.0.join(".gitignore"), "# no dependency exclusions\n").unwrap();
    ok(&fixture.0, "git", &["add", ".gitignore"]);
    let tree = String::from_utf8(ok(&fixture.0, "git", &["write-tree"]).stdout).unwrap();
    xtask::snapshot::prepare(&fixture.0, tree.trim()).unwrap();
    xtask::snapshot::reset(&fixture.0).unwrap();
    assert!(!snapshot.exists());
    assert_eq!(
        fs::read_to_string(dependency.join("sentinel")).unwrap(),
        "keep dependency"
    );
    xtask::snapshot::prepare(&fixture.0, tree.trim()).unwrap();
    // Simulate a missing checkout without deleting it or touching its links.
    let moved = fixture.0.join("snapshot-moved");
    fs::rename(&snapshot, &moved).unwrap();
    xtask::snapshot::prepare(&fixture.0, tree.trim()).unwrap();
    fs::remove_dir(moved.join("3rd_party/Src/DirectXMath/DirectXMath")).unwrap();
    assert_eq!(
        fs::read_to_string(dependency.join("sentinel")).unwrap(),
        "keep dependency"
    );
    xtask::snapshot::reset(&fixture.0).unwrap();
    xtask::snapshot::reset(&fixture.0).unwrap();
}

#[test]
fn ignored_resource_input_forces_staged_validation() {
    let fixture = Fixture::new("int main() {}\n", "true");
    fs::create_dir_all(fixture.0.join("ogsr_engine")).unwrap();
    fs::write(fixture.0.join("ogsr_engine/untracked.ico"), "not committed").unwrap();
    fs::write(fixture.0.join(".gitignore"), "/target/\n*.ico\n").unwrap();
    ok(&fixture.0, "git", &["add", ".gitignore"]);
    let result = ok(
        &fixture.0,
        "git",
        &["commit", "-m", "test: ignored resource"],
    );
    assert!(output_text(&result).contains("Validating staged files in"));
    assert!(
        output_text(&result).contains("Isolating: untracked build input ogsr_engine/untracked.ico")
    );
    assert!(fixture.0.join("ogsr_engine/untracked.ico").exists());
    assert!(!fixture.0.join(".git/v/ogsr_engine/untracked.ico").exists());
}

#[test]
fn build_cannot_change_snapshot_source_and_approve_commit() {
    let fixture = Fixture::new("int main() {}\n", "true");
    fs::write(fixture.0.join("Fixture.vcxproj"), r#"<Project DefaultTargets="Build" xmlns="http://schemas.microsoft.com/developer/msbuild/2003"><Target Name="Build"><WriteLinesToFile File="tools/tests/fixture.cpp" Lines="changed by build" Overwrite="true" /></Target></Project>"#).unwrap();
    ok(&fixture.0, "git", &["add", "Fixture.vcxproj"]);
    fs::write(
        fixture.0.join("tools/tests/fixture.cpp"),
        "private working edit",
    )
    .unwrap();
    Fixture::reject_at(&fixture.0, "Snapshot source changed");
    assert_eq!(
        fs::read_to_string(fixture.0.join("tools/tests/fixture.cpp")).unwrap(),
        "private working edit"
    );
}

#[test]
fn moved_repository_has_safe_documented_recovery() {
    let mut fixture = Fixture::new("int main() {}\n", "true");
    let tree = String::from_utf8(ok(&fixture.0, "git", &["write-tree"]).stdout).unwrap();
    xtask::snapshot::prepare(&fixture.0, tree.trim()).unwrap();
    let moved = fixture.0.with_extension("moved");
    fs::rename(&fixture.0, &moved).unwrap();
    fixture.0 = moved;
    assert!(xtask::snapshot::reset(&fixture.0)
        .unwrap_err()
        .to_string()
        .contains("git worktree repair"));
    let snapshot = fixture.0.join(".git/v");
    ok(
        &fixture.0,
        "git",
        &["worktree", "repair", snapshot.to_str().unwrap()],
    );
    xtask::snapshot::prepare(&fixture.0, tree.trim()).unwrap();
    xtask::snapshot::reset(&fixture.0).unwrap();
    assert!(!snapshot.exists());
}
#[test]
fn installing_hooks_twice_is_idempotent() {
    let fixture = Fixture::new("int main() {}\n", "true");
    let hook = fixture.0.join(".git/ogsr-hooks/pre-commit");
    let original = fs::read(&hook).unwrap();
    ok(&fixture.0, env!("CARGO_BIN_EXE_xtask"), &["install-hooks"]);
    assert_eq!(fs::read(hook).unwrap(), original);
}

#[test]
fn clean_validation_rejects_changed_source_and_index() {
    for (action, expected) in [
        (
            r#"<WriteLinesToFile File="tools/tests/fixture.cpp" Lines="changed source" Overwrite="true" />"#,
            "Build inputs changed",
        ),
        (
            r#"<WriteLinesToFile File="note.txt" Lines="changed index" Overwrite="true" /><Exec Command="git add note.txt" />"#,
            "Index changed",
        ),
    ] {
        let fixture = Fixture::new("int main() {}\n", "true");
        fs::write(fixture.0.join("Fixture.vcxproj"), format!(r#"<Project DefaultTargets="Build" xmlns="http://schemas.microsoft.com/developer/msbuild/2003"><Target Name="Build">{action}</Target></Project>"#)).unwrap();
        ok(&fixture.0, "git", &["add", "Fixture.vcxproj"]);
        Fixture::reject_at(&fixture.0, expected);
    }
}
#[test]
fn hidden_working_edits_validate_index_bytes() {
    for flag in ["--assume-unchanged", "--skip-worktree"] {
        let fixture = Fixture::new("int main() {}\n", "true");
        ok(
            &fixture.0,
            "git",
            &["update-index", flag, "tools/tests/fixture.cpp"],
        );
        fs::write(
            fixture.0.join("tools/tests/fixture.cpp"),
            "hidden broken source",
        )
        .unwrap();
        let result = ok(
            &fixture.0,
            "git",
            &["commit", "--allow-empty", "-m", "test: hidden input"],
        );
        assert!(output_text(&result).contains("Isolating: index contains"));
        assert_eq!(
            fs::read_to_string(fixture.0.join("tools/tests/fixture.cpp")).unwrap(),
            "hidden broken source"
        );
    }
}

#[test]
fn path_only_commit_excludes_files_staged_in_the_real_index() {
    let fixture = Fixture::new("int main() {}\n", "true");
    fs::write(fixture.0.join("tools/tests/new_api.h"), "#define VALUE 0\n").unwrap();
    ok(&fixture.0, "git", &["add", "tools/tests/new_api.h"]);
    fs::write(
        fixture.0.join("tools/tests/fixture.cpp"),
        "#include \"new_api.h\"\nint main() { return VALUE; }\n",
    )
    .unwrap();
    let tree = ok(&fixture.0, "git", &["write-tree"]).stdout;
    let head = ok(&fixture.0, "git", &["rev-parse", "HEAD"]).stdout;
    let result = execute(
        &fixture.0,
        "git",
        &[
            "commit",
            "-m",
            "test: missing header",
            "--",
            "tools/tests/fixture.cpp",
        ],
    );
    let log = output_text(&result);
    assert!(!result.status.success(), "{log}");
    assert!(
        log.contains("Isolating: untracked build input tools/tests/new_api.h"),
        "{log}"
    );
    assert!(
        log.lines()
            .any(|line| line.contains("C1083") && line.contains("new_api.h")),
        "{log}"
    );
    assert_eq!(tree, ok(&fixture.0, "git", &["write-tree"]).stdout);
    assert_eq!(head, ok(&fixture.0, "git", &["rev-parse", "HEAD"]).stdout);
    assert!(fixture.0.join("tools/tests/new_api.h").exists());
}

#[test]
fn debug_assertion_build_failure_blocks_commit() {
    let fixture = Fixture::new("int main() {}\n", "true");
    fs::write(fixture.0.join("Fixture.vcxproj"), r#"<Project DefaultTargets="Build" xmlns="http://schemas.microsoft.com/developer/msbuild/2003"><Target Name="Build"><Error Condition="'$(Configuration)'=='Debug' and '$(OgsrRequireDebugAssertions)'!='true'" Text="DEBUG_ASSERTIONS_NOT_REQUIRED" /><Error Condition="'$(Configuration)'=='Debug' and '$(OgsrRequireDebugAssertions)'=='true'" Text="NATIVE_DEBUG_FAILURE" /></Target></Project>"#).unwrap();
    ok(&fixture.0, "git", &["add", "Engine.sln", "Fixture.vcxproj"]);
    Fixture::reject_at(&fixture.0, "NATIVE_DEBUG_FAILURE");
}
