use std::{
    env, fs,
    path::{Path, PathBuf},
    process::{Command, ExitCode},
};

type Result<T = ()> = std::result::Result<T, Box<dyn std::error::Error>>;

fn run(command: &mut Command) -> Result {
    eprintln!("+ {command:?}");
    let status = command.status()?;
    if !status.success() {
        return Err(format!("command failed ({status}): {command:?}").into());
    }
    Ok(())
}

fn output(command: &mut Command) -> Result<String> {
    let result = command.output()?;
    if !result.status.success() {
        return Err(format!("{command:?}: {}", String::from_utf8_lossy(&result.stderr)).into());
    }
    Ok(String::from_utf8(result.stdout)?
        .trim_end_matches(['\r', '\n'])
        .to_owned())
}

fn git(args: &[&str]) -> Result<String> {
    output(Command::new("git").args(args))
}

fn tracked_edits() -> Result<bool> {
    let out = Command::new("git").args(["diff", "--quiet"]).output()?;
    match out.status.code() {
        Some(0) => Ok(false),
        Some(1) => Ok(true),
        _ => Err(format!(
            "Cannot inspect worktree: {}",
            String::from_utf8_lossy(&out.stderr)
        )
        .into()),
    }
}

fn lock() -> Result<fs::File> {
    let path = PathBuf::from(git(&["rev-parse", "--git-path", "ogsr-validation.lock"])?);
    Ok(xtask::validation_lock(&path)
        .map_err(|e| format!("Validation lock {}: {e}", path.display()))?)
}

fn validate_index() -> Result {
    let _lock = lock()?;
    let before = git(&["write-tree"])?;
    let unstaged = tracked_edits()?;
    let extra = xtask::snapshot::extra_inputs(
        &env::current_dir()?,
        xtask::snapshot::GitEnvironment::Inherit,
    )?;
    let hidden = git(&["ls-files", "-v", "-z"])?.split('\0').any(|entry| {
        entry
            .as_bytes()
            .first()
            .is_some_and(|tag| *tag == b'S' || tag.is_ascii_lowercase())
    });
    let isolated = unstaged || hidden || !extra.is_empty();
    if hidden {
        eprintln!("Isolating: index contains assume-unchanged or skip-worktree entries.");
    }
    if unstaged {
        eprintln!("Isolating: tracked working changes differ from the index.");
    }
    for path in extra.iter().take(5) {
        eprintln!("Isolating: untracked build input {path}");
    }
    if extra.len() > 5 {
        eprintln!("... and {} more build inputs", extra.len() - 5);
    }
    if isolated {
        let root = env::current_dir()?;
        let snapshot = xtask::snapshot::prepare(&root, &before)?;
        eprintln!("Validating staged files in {}", snapshot.display());
        let mut command = Command::new("cargo");
        command.current_dir(&snapshot).args(["xtask", "validate"]);
        for (key, _) in env::vars().filter(|(key, _)| key.starts_with("GIT_")) {
            command.env_remove(key);
        }
        command.env("CARGO_TARGET_DIR", snapshot.join("target"));
        run(&mut command)?;
        xtask::snapshot::git_isolated(&snapshot, &["diff", "--quiet", &before])
            .map_err(|e| format!("Snapshot source changed during validation: {e}"))?;
        if xtask::snapshot::git_isolated(&snapshot, &["write-tree"])? != before
            || !xtask::snapshot::extra_inputs(&snapshot, xtask::snapshot::GitEnvironment::Isolated)?
                .is_empty()
        {
            return Err("Snapshot inputs changed during validation; retry the commit.".into());
        }
    } else {
        validate(None, false, false)?;
        if tracked_edits()?
            || !xtask::snapshot::extra_inputs(
                &env::current_dir()?,
                xtask::snapshot::GitEnvironment::Inherit,
            )?
            .is_empty()
        {
            return Err("Build inputs changed during validation; retry the commit.".into());
        }
    }
    if git(&["write-tree"])? != before {
        return Err("Index changed during validation; retry the commit.".into());
    }
    Ok(())
}

fn msbuild() -> Result<PathBuf> {
    if Command::new("MSBuild.exe")
        .arg("-version")
        .output()
        .is_ok_and(|r| r.status.success())
    {
        return Ok("MSBuild.exe".into());
    }
    let vswhere =
        PathBuf::from(env::var("ProgramFiles(x86)").map_err(|_| {
            "MSBuild discovery requires Windows and Visual Studio C++ Build Tools."
        })?)
        .join("Microsoft Visual Studio/Installer/vswhere.exe");
    let found = output(Command::new(vswhere).args([
        "-latest",
        "-products",
        "*",
        "-requires",
        "Microsoft.Component.MSBuild",
        "-find",
        "MSBuild/Current/Bin/MSBuild.exe",
    ]))?;
    found
        .lines()
        .next()
        .filter(|s| !s.is_empty())
        .map(PathBuf::from)
        .ok_or_else(|| "MSBuild not found; install Visual Studio C++ Build Tools.".into())
}

fn validate(configuration: Option<&str>, tests_only: bool, acquire_lock: bool) -> Result {
    if !cfg!(windows) {
        return Err(
            "Engine validation requires Windows with Visual Studio C++ Build Tools.".into(),
        );
    }
    let _lock = if acquire_lock { Some(lock()?) } else { None };
    let jobs = env::var("OGSR_BUILD_JOBS").unwrap_or_else(|_| "4".into());
    if jobs.parse::<usize>().ok().filter(|n| *n > 0).is_none() {
        return Err("OGSR_BUILD_JOBS must be a positive integer.".into());
    }
    run(Command::new("cargo").args(["fmt", "--all", "--", "--check"]))?;
    run(Command::new("cargo").args(["test", "--workspace", "--locked"]))?;
    run(Command::new("cmake").args([
        "-S",
        "tools/tests",
        "-B",
        "target/validation/tests",
        "-A",
        "x64",
    ]))?;
    run(Command::new("cmake").args([
        "--build",
        "target/validation/tests",
        "--config",
        "Release",
        "--parallel",
        &jobs,
    ]))?;
    run(Command::new("ctest").args([
        "--test-dir",
        "target/validation/tests",
        "-C",
        "Release",
        "--output-on-failure",
        "--no-tests=error",
        "--timeout",
        "120",
    ]))?;
    if !tests_only {
        let build = msbuild()?;
        let configurations = configuration
            .map(|c| vec![c])
            .unwrap_or_else(|| vec!["Release", "ReleaseTracyProfiler"]);
        for variant in configurations {
            let log = format!("target/validation/{variant}.log");
            let mut command = Command::new(&build);
            command.env_remove("CONFIGURATION_GA");
            run(command.args([
                "Engine.sln",
                &format!("/m:{jobs}"),
                &format!("/p:Configuration={variant}"),
                "/p:Platform=x64",
                "/verbosity:minimal",
                "/nologo",
                "/fl",
                &format!("/flp:logfile={log};verbosity=normal"),
            ]))?;
        }
    }
    eprintln!("Validation passed. Gameplay/E2E scenarios were not run.");
    Ok(())
}

fn install_hook(root: &Path) -> Result {
    // The shared bootstrap only dispatches; the tracked hook owns behavior.
    let common = PathBuf::from(git(&[
        "rev-parse",
        "--path-format=absolute",
        "--git-common-dir",
    ])?);
    let destination = common.join("ogsr-hooks");
    let configured = Command::new("git")
        .args(["config", "--get", "core.hooksPath"])
        .output()?;
    if configured.status.success()
        && String::from_utf8(configured.stdout)?.trim() != destination.to_string_lossy()
    {
        return Err(
            "A custom hooksPath already exists; integrate it explicitly instead of replacing it."
                .into(),
        );
    }
    if common.join("hooks").is_dir() {
        for entry in fs::read_dir(common.join("hooks"))? {
            let entry = entry?;
            if entry.file_type()?.is_file()
                && !entry.file_name().to_string_lossy().ends_with(".sample")
            {
                return Err(format!(
                    "Existing hook {} needs explicit integration.",
                    entry.path().display()
                )
                .into());
            }
        }
    }
    if !root.join(".githooks/pre-commit").is_file() {
        return Err("Missing tracked pre-commit hook.".into());
    }
    fs::create_dir_all(&destination)?;
    let bootstrap = r#"#!/bin/sh
set -eu
if [ ! -f .githooks/pre-commit ]; then
    echo 'Local validation is required. Bring the validation infrastructure onto this branch before committing.' >&2
    exit 1
fi
exec sh .githooks/pre-commit
"#;
    for name in ["pre-commit", "pre-merge-commit"] {
        fs::write(destination.join(name), bootstrap)?;
    }
    run(Command::new("git")
        .args(["config", "--local", "core.hooksPath"])
        .arg(&destination))?;
    eprintln!(
        "Installed hook for this repository and its linked worktrees: {}",
        destination.display()
    );
    Ok(())
}

fn main_result() -> Result {
    let args: Vec<_> = env::args().skip(1).collect();
    let root = PathBuf::from(git(&["rev-parse", "--show-toplevel"])?);
    env::set_current_dir(&root)?;
    match args
        .iter()
        .map(String::as_str)
        .collect::<Vec<_>>()
        .as_slice()
    {
        ["install-hooks"] => install_hook(&root),
        ["reset-snapshot"] => {
            let _lock = lock()?;
            xtask::snapshot::reset(&root)
        }
        ["pre-commit"] => validate_index(),
        ["validate"] => validate(None, false, true),
        ["validate", "--tests-only"] => validate(None, true, true),
        ["validate", "--configuration", c @ ("Debug" | "Release" | "ReleaseTracyProfiler")] => {
            validate(Some(c), false, true)
        }
        _ => Err(concat!(
            "Usage: cargo xtask {validate [--tests-only | ",
            "--configuration Debug|Release|ReleaseTracyProfiler] | ",
            "install-hooks | pre-commit | reset-snapshot}"
        )
        .into()),
    }
}

fn main() -> ExitCode {
    match main_result() {
        Ok(()) => ExitCode::SUCCESS,
        Err(error) => {
            eprintln!("Validation failed: {error}");
            ExitCode::FAILURE
        }
    }
}
