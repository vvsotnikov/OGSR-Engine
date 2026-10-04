use std::{
    collections::HashSet,
    env, fs,
    path::{Path, PathBuf},
    process::Command,
};

type Result<T> = std::result::Result<T, Box<dyn std::error::Error>>;

fn overlaps_dependency(path: &str, directory: &str) -> bool {
    let (path, directory) = if cfg!(windows) {
        (path.to_lowercase(), directory.to_lowercase())
    } else {
        (path.to_owned(), directory.to_owned())
    };
    path == directory.trim_end_matches('/') || path.starts_with(&directory)
}

pub fn git_at(root: &Path, args: &[&str]) -> Result<String> {
    let mut cmd = Command::new("git");
    cmd.current_dir(root).args(args);
    for (key, _) in env::vars().filter(|(key, _)| key.starts_with("GIT_")) {
        cmd.env_remove(key);
    }
    let out = cmd.output()?;
    if !out.status.success() {
        return Err(format!("git {args:?}: {}", String::from_utf8_lossy(&out.stderr)).into());
    }
    Ok(String::from_utf8(out.stdout)?
        .trim_end_matches(['\r', '\n'])
        .to_owned())
}

/// A persistent detached worktree caches builds without checking out or
/// stashing anything in the developer's worktree. Only the index tree enters it.
pub fn prepare(root: &Path, tree: &str) -> Result<PathBuf> {
    let path = PathBuf::from(git_at(
        root,
        &[
            "rev-parse",
            "--path-format=absolute",
            "--git-path",
            // Keep this short: generated FidelityFX header names approach
            // MSVC's path-length limit even in an ordinary engine checkout.
            "v",
        ],
    )?);
    let tracked: HashSet<_> = git_at(root, &["ls-tree", "-r", "--name-only", "-z", tree])?
        .split('\0')
        .filter(|p| !p.is_empty())
        .map(str::to_owned)
        .collect();
    let manifest = path.with_extension("dependencies");
    let mut borrowed: HashSet<String> = if manifest.exists() {
        fs::read_to_string(&manifest)?
            .lines()
            .map(str::to_owned)
            .collect()
    } else {
        HashSet::new()
    };
    // Check before checkout: never write staged files through a dependency
    // junction into the developer's worktree.
    for prefix in &borrowed {
        if tracked.iter().any(|p| overlaps_dependency(p, prefix)) {
            return Err(format!("Staged files overlap borrowed dependency {prefix}; use a fresh validation checkout.").into());
        }
    }
    let commit = git_at(
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
    if !path.join(".git").exists() {
        git_at(
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
        git_at(&path, &["checkout", "--detach", &commit])?;
    }
    // These are the existing, separately provisioned engine dependencies.
    // They are not a copy of arbitrary untracked source or developer scratch files.
    for item in git_at(
        root,
        &[
            "ls-files",
            "--others",
            "--ignored",
            "--exclude-standard",
            "-z",
            "--",
            "3rd_party/Src",
            "ogsr_engine/LuaJIT/bin",
        ],
    )?
    .split('\0')
    .filter(|p| !p.is_empty())
    {
        if item.split('/').any(|p| p == ".git") || tracked.contains(item) {
            continue;
        }
        let source = root.join(item);
        let target = path.join(item);
        if source.is_dir() {
            if tracked.iter().any(|p| overlaps_dependency(p, item)) {
                return Err(format!("Dependency directory overlaps staged files: {item}").into());
            }
            if !target.exists() {
                borrowed.insert(item.to_owned());
                fs::write(
                    &manifest,
                    borrowed.iter().cloned().collect::<Vec<_>>().join("\n"),
                )?;
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
        } else {
            let info = fs::metadata(&source)?;
            let same = fs::metadata(&target)
                .is_ok_and(|t| t.len() == info.len() && t.modified().ok() == info.modified().ok());
            if !same {
                fs::create_dir_all(target.parent().ok_or("Missing dependency parent")?)?;
                fs::copy(&source, &target)?;
                fs::File::options()
                    .write(true)
                    .open(&target)?
                    .set_times(fs::FileTimes::new().set_modified(info.modified()?))?;
            }
        }
    }
    Ok(path)
}
