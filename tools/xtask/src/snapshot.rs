use std::{
    env, fs,
    path::{Path, PathBuf},
    process::Command,
};
type Result<T = ()> = std::result::Result<T, Box<dyn std::error::Error>>;

// Provisioned by Update_Components.cmd, never populated from arbitrary ignored inputs.
pub const DEPENDENCIES: &[&str] = &[
    "3rd_party/Src/DirectXMath/DirectXMath",
    "3rd_party/Src/DirectXMesh/DirectXMesh",
    "3rd_party/Src/DirectXTex/DirectXTex",
    "3rd_party/Src/DiscordRPC/DiscordRPC",
    "3rd_party/Src/FidelityFX-SDK/FidelityFX-SDK",
    "3rd_party/Src/NVIDIA_DLSS/DLSS",
    "3rd_party/Src/concurrentqueue/concurrentqueue",
    "3rd_party/Src/cpputils/cpputils",
    "3rd_party/Src/libsquashfs/squashfs-tools-ng",
    "3rd_party/Src/lz4/lz4",
    "3rd_party/Src/mimalloc/mimalloc",
    "3rd_party/Src/zstd/zstd",
];
const CACHES: &[&str] = &[
    "target",
    "ogsr_engine/_TEMP",
    "ogsr_engine/_LIB",
    "3rd_party/_TEMP",
    "3rd_party/_LIB",
    "bin_x64",
    "bin_x64_tracy",
    "bin_x64_debug",
];
fn within(path: &str, root: &str) -> bool {
    path.eq_ignore_ascii_case(root)
        || path
            .to_ascii_lowercase()
            .starts_with(&format!("{}/", root.to_ascii_lowercase()))
}
pub fn is_build_input(path: &str) -> bool {
    if path.is_empty() || DEPENDENCIES.iter().chain(CACHES).any(|r| within(path, r)) {
        return false;
    }
    let lower = path.to_ascii_lowercase();
    let filename = lower.rsplit('/').next().unwrap_or("");
    if lower.ends_with(".aps") || ["thumbs.db", "ehthumbs.db", "desktop.ini"].contains(&filename) {
        return false;
    }
    let parts: Vec<_> = lower.split('/').collect();
    if parts.contains(&"__pycache__")
        || (parts.len() >= 4 && parts[0] == "tools" && parts[1] == "tests" && parts[3] == "build")
    {
        return false;
    }
    ["ogsr_engine", "3rd_party", "tools", ".githooks", ".cargo"]
        .iter()
        .any(|r| within(path, r))
        || (!path.contains('/')
            && (lower.starts_with("cargo.")
                || lower == "rust-toolchain.toml"
                || [
                    "sln", "props", "targets", "cmake", "cmd", "bat", "ps1", "py",
                ]
                .contains(
                    &Path::new(&lower)
                        .extension()
                        .and_then(|x| x.to_str())
                        .unwrap_or(""),
                )
                || lower == "cmakelists.txt"))
}
pub enum GitEnvironment {
    Inherit,
    Isolated,
}

pub fn extra_inputs(root: &Path, environment: GitEnvironment) -> Result<Vec<String>> {
    let exclusions: Vec<_> = DEPENDENCIES
        .iter()
        .chain(CACHES)
        .map(|path| format!(":(top,icase,exclude){path}"))
        .collect();
    let mut args = vec![
        "ls-files",
        "--others",
        "-z",
        "--",
        ":(top,icase)ogsr_engine",
        ":(top,icase)3rd_party",
        ":(top,icase)tools",
        ":(top,icase).githooks",
        ":(top,icase).cargo",
        ":(top,icase,glob)Cargo.*",
        ":(top,icase)rust-toolchain.toml",
        ":(top,icase)CMakeLists.txt",
        ":(top,icase,exclude,glob)tools/tests/*/build/**",
        ":(top,icase,exclude,glob)**/__pycache__/**",
    ];
    let roots: Vec<_> = [
        "sln", "props", "targets", "cmake", "cmd", "bat", "ps1", "py",
    ]
    .iter()
    .map(|extension| format!(":(top,icase,glob)*.{extension}"))
    .collect();
    args.extend(roots.iter().map(String::as_str));
    args.extend(exclusions.iter().map(String::as_str));
    Ok(git_with_environment(root, &args, environment)?
        .split('\0')
        .filter(|p| is_build_input(p))
        .map(str::to_owned)
        .collect())
}

// Snapshot operations must not inherit the developer hook's index or Git directory.
pub fn git_isolated(root: &Path, args: &[&str]) -> Result<String> {
    git_with_environment(root, args, GitEnvironment::Isolated)
}

fn git_with_environment(root: &Path, args: &[&str], environment: GitEnvironment) -> Result<String> {
    let mut cmd = Command::new("git");
    cmd.current_dir(root).args(args);
    if matches!(environment, GitEnvironment::Isolated) {
        for (key, _) in env::vars().filter(|(key, _)| key.starts_with("GIT_")) {
            cmd.env_remove(key);
        }
    }
    let out = cmd.output()?;
    if !out.status.success() {
        return Err(format!("git {args:?}: {}", String::from_utf8_lossy(&out.stderr)).into());
    }
    Ok(String::from_utf8(out.stdout)?
        .trim_end_matches(['\r', '\n'])
        .to_owned())
}

fn snapshot_path(root: &Path) -> Result<PathBuf> {
    // A short path avoids MSVC's path-length limit in generated dependency headers.
    Ok(PathBuf::from(git_isolated(
        root,
        &["rev-parse", "--path-format=absolute", "--git-path", "v"],
    )?))
}
fn reparse(metadata: &fs::Metadata) -> bool {
    #[cfg(windows)]
    {
        use std::os::windows::fs::MetadataExt;
        metadata.file_attributes() & 0x400 != 0
    }
    #[cfg(not(windows))]
    {
        metadata.file_type().is_symlink()
    }
}
// Never recurse through a junction, including unexpected links.
fn unlink(path: &Path, metadata: &fs::Metadata) -> Result {
    #[cfg(windows)]
    let directory = {
        use std::os::windows::fs::MetadataExt;
        metadata.file_attributes() & 0x10 != 0
    };
    #[cfg(not(windows))]
    let directory = metadata.is_dir();
    #[cfg(windows)]
    if !reparse(metadata) && metadata.permissions().readonly() {
        let mut permissions = metadata.permissions();
        permissions.set_readonly(false);
        fs::set_permissions(path, permissions)?;
    }
    let result = if directory {
        fs::remove_dir(path)
    } else {
        fs::remove_file(path)
    };
    result.map_err(|e| format!("Cannot unlink {}: {e}", path.display()))?;
    Ok(())
}
fn detach_links(root: &Path, path: &Path) -> Result {
    for entry in fs::read_dir(path)? {
        let path = entry?.path();
        let metadata = fs::symlink_metadata(&path)?;
        if reparse(&metadata) {
            unlink(&path, &metadata)?;
        } else if metadata.is_dir() {
            let relative = path
                .strip_prefix(root)?
                .to_string_lossy()
                .replace('\\', "/");
            if !CACHES.iter().any(|cache| within(&relative, cache)) {
                detach_links(root, &path)?;
            }
        }
    }
    Ok(())
}
fn remove_owned_tree(path: &Path) -> Result {
    let metadata = fs::symlink_metadata(path)?;
    if reparse(&metadata) || !metadata.is_dir() {
        return unlink(path, &metadata);
    }
    for entry in fs::read_dir(path)? {
        remove_owned_tree(&entry?.path())?;
    }
    fs::remove_dir(path)?;
    Ok(())
}
fn registered(root: &Path, path: &Path) -> Result<bool> {
    let expected = format!("worktree {}", path.to_string_lossy().replace('\\', "/"));
    Ok(
        git_isolated(root, &["worktree", "list", "--porcelain", "-z"])?
            .split('\0')
            .any(|line| line.eq_ignore_ascii_case(&expected)),
    )
}
fn check_owned(root: &Path, path: &Path) -> Result {
    if let Ok(metadata) = fs::symlink_metadata(path) {
        if reparse(&metadata) || !registered(root, path)? {
            return Err(format!(
                concat!(
                    "Refusing unregistered or redirected snapshot {}. ",
                    "If the repository moved, run git worktree repair with this snapshot path, ",
                    "then retry. A redirected snapshot must not be repaired this way."
                ),
                path.display()
            )
            .into());
        }
    }
    Ok(())
}
pub fn reset(root: &Path) -> Result {
    let path = snapshot_path(root)?;
    check_owned(root, &path)?;
    // Remove only this worktree's generated snapshot, without following links.
    if path.exists() {
        remove_owned_tree(&path)?;
    }
    if registered(root, &path)? {
        git_isolated(
            root,
            &[
                "worktree",
                "remove",
                "--force",
                path.to_str().ok_or("Non-Unicode snapshot path")?,
            ],
        )?;
    }
    Ok(())
}

/// Replace source inputs with the index tree; retain only named build caches.
pub fn prepare(root: &Path, tree: &str) -> Result<PathBuf> {
    let path = snapshot_path(root)?;
    check_owned(root, &path)?;
    let tracked = git_isolated(root, &["ls-tree", "-r", "--name-only", "-z", tree])?;
    for item in tracked.split('\0').filter(|p| !p.is_empty()) {
        if DEPENDENCIES
            .iter()
            .chain(CACHES)
            .any(|prefix| within(item, prefix) || within(prefix, item))
        {
            return Err(format!(
                "Staged files overlap borrowed dependency or reserved cache: {item}"
            )
            .into());
        }
    }
    let commit = git_isolated(
        root,
        &[
            "-c",
            "user.name=Local validation",
            "-c",
            "user.email=validation@example.invalid",
            "commit-tree",
            tree,
            "-m",
            "Local staged validation snapshot",
        ],
    )?;
    if !path.exists() {
        if registered(root, &path)? {
            reset(root)?;
        }
        git_isolated(
            root,
            &[
                "worktree",
                "add",
                "--detach",
                path.to_str().ok_or("Non-Unicode snapshot path")?,
                &commit,
            ],
        )?;
    } else {
        detach_links(&path, &path)?;
        git_isolated(&path, &["checkout", "--force", "--detach", &commit])?;
    }
    // Materialize the full index even if repository sparse-checkout settings
    // were inherited.
    git_isolated(
        &path,
        &[
            "read-tree",
            "--reset",
            "-u",
            "--no-sparse-checkout",
            &commit,
        ],
    )?;
    // Ignore rules may change between staged trees. They must not preserve stale source.
    let mut clean = vec!["clean", "-ffdx"];
    let exclusions: Vec<_> = CACHES.iter().map(|p| format!("/{p}/")).collect();
    for exclusion in &exclusions {
        clean.extend(["-e", exclusion.as_str()]);
    }
    git_isolated(&path, &clean)?;
    for item in DEPENDENCIES {
        let source = root.join(item);
        let target = path.join(item);
        if !source.is_dir() {
            continue;
        }
        fs::create_dir_all(target.parent().ok_or("Missing dependency parent")?)?;
        #[cfg(windows)]
        {
            let status = Command::new("cmd")
                .args(["/d", "/c", "mklink", "/J"])
                .arg(target.to_string_lossy().replace('/', "\\"))
                .arg(source.to_string_lossy().replace('/', "\\"))
                .output()?;
            if !status.status.success() {
                return Err(format!(
                    "Cannot link dependency: {}",
                    String::from_utf8_lossy(&status.stderr)
                )
                .into());
            }
        }
        #[cfg(not(windows))]
        std::os::unix::fs::symlink(&source, &target)?;
    }
    Ok(path)
}
