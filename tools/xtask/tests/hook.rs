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
            "Cargo.lock",
            ".gitattributes",
            ".cargo/config.toml",
            ".githooks/pre-commit",
            "tools/xtask/Cargo.toml",
            "tools/xtask/src/main.rs",
            "tools/xtask/src/lib.rs",
            "tools/xtask/src/snapshot.rs",
            "tools/tests/CMakeLists.txt",
        ] {
            let dest = root.join(file);
            fs::create_dir_all(dest.parent().unwrap()).unwrap();
            fs::copy(source.join(file), dest).unwrap();
        }
        fs::write(root.join(".gitignore"), "/target/\n/linked/\n").unwrap();
        fs::create_dir_all(root.join("tools/tests/fixture")).unwrap();
        fs::write(root.join("tools/tests/fixture/CMakeLists.txt"), format!(
            "add_executable(fixture ../fixture.cpp)\nadd_test(NAME assertion COMMAND ${{CMAKE_COMMAND}} -E {assertion})\n")).unwrap();
        fs::write(root.join("tools/tests/fixture.cpp"), source_code).unwrap();
        fs::write(root.join("Fixture.vcxproj"), r#"<Project DefaultTargets="Build" xmlns="http://schemas.microsoft.com/developer/msbuild/2003"><Target Name="Build" /></Project>"#).unwrap();
        fs::write(root.join("Engine.sln"), "Microsoft Visual Studio Solution File, Format Version 12.00\nProject(\"{8BC9CEB8-8B4A-11D0-8D11-00A0C91BC942}\") = \"Fixture\", \"Fixture.vcxproj\", \"{11111111-1111-1111-1111-111111111111}\"\nEndProject\nGlobal\n GlobalSection(SolutionConfigurationPlatforms) = preSolution\n Release|x64 = Release|x64\n EndGlobalSection\n GlobalSection(ProjectConfigurationPlatforms) = postSolution\n {11111111-1111-1111-1111-111111111111}.Release|x64.ActiveCfg = Release|x64\n {11111111-1111-1111-1111-111111111111}.Release|x64.Build.0 = Release|x64\n EndGlobalSection\nEndGlobal\n").unwrap();
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
    let dependency = fixture.0.join("3rd_party/Src/borrowed dependency");
    fs::create_dir_all(&dependency).unwrap();
    ok(&dependency, "git", &["init"]);
    fs::write(dependency.join("source.cpp"), "original dependency\n").unwrap();
    fs::write(
        fixture.0.join(".gitignore"),
        "/target/\n/linked/\n/3rd_party/Src/borrowed dependency/\n",
    )
    .unwrap();
    ok(&fixture.0, "git", &["add", ".gitignore"]);
    let tree = String::from_utf8(ok(&fixture.0, "git", &["write-tree"]).stdout).unwrap();
    let snapshot = xtask::snapshot::prepare(&fixture.0, tree.trim()).unwrap();
    assert_eq!(
        fs::read(snapshot.join("3rd_party/Src/borrowed dependency/source.cpp")).unwrap(),
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
            "3rd_party/Src/BORROWED DEPENDENCY/source.cpp",
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
fn tracy_failure_blocks_commit_after_release_passes() {
    let fixture = Fixture::new("int main() {}\n", "true");
    fs::write(fixture.0.join("Fixture.vcxproj"), r#"<Project DefaultTargets="Build" xmlns="http://schemas.microsoft.com/developer/msbuild/2003"><Target Name="Build"><Error Condition="'$(CONFIGURATION_GA)'==''" Text="LEGACY_METADATA_MISSING" /><Error Condition="'$(CONFIGURATION_GA)'=='ReleaseTracyProfiler'" Text="TRACY_FIXTURE_FAILURE" /></Target></Project>"#).unwrap();
    ok(&fixture.0, "git", &["add", "Fixture.vcxproj"]);
    Fixture::reject_at(&fixture.0, "TRACY_FIXTURE_FAILURE");
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
    let path = fixture.0.join("Engine.sln");
    let solution = fs::read_to_string(&path).unwrap()
        .replace(" Release|x64 = Release|x64", " Release|x64 = Release|x64\n ReleaseTracyProfiler|x64 = ReleaseTracyProfiler|x64")
        .replace(" {11111111-1111-1111-1111-111111111111}.Release|x64.Build.0 = Release|x64", " {11111111-1111-1111-1111-111111111111}.Release|x64.Build.0 = Release|x64\n {11111111-1111-1111-1111-111111111111}.ReleaseTracyProfiler|x64.ActiveCfg = ReleaseTracyProfiler|x64\n {11111111-1111-1111-1111-111111111111}.ReleaseTracyProfiler|x64.Build.0 = ReleaseTracyProfiler|x64");
    fs::write(path, solution).unwrap();
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
