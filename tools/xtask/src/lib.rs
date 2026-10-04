use std::{
    fs::{File, OpenOptions},
    io,
    path::Path,
};

pub mod snapshot;

/// Keep the handle alive for the entire validation. The OS releases the lock
/// even when the owner is terminated; the persistent file is not a sentinel.
pub fn validation_lock(path: &Path) -> io::Result<File> {
    let file = OpenOptions::new()
        .read(true)
        .write(true)
        .create(true)
        .truncate(false)
        .open(path)?;
    file.try_lock().map_err(io::Error::other)?;
    Ok(file)
}

#[cfg(test)]
mod tests {
    use super::snapshot::is_build_input;
    #[test]
    fn build_roots_include_resources_but_exclude_known_outputs() {
        for path in [
            "ogsr_engine/new.ico",
            "ogsr_engine/new.manifest",
            "ogsr_engine/new.hlsl",
            "ogsr_engine/new.inc",
            "tools/fixture/data.md",
            "tools/new.py",
            "tools/fixture/ leading space.inc",
        ] {
            assert!(is_build_input(path), "{path}");
        }
        for path in [
            "notes.txt",
            "build.log",
            "target/a.rs",
            "ogsr_engine/_TEMP/generated.cpp",
            "3rd_party/Src/DirectXMath/DirectXMath/source.h",
            "tools/tests/scheduler/build/CMakeCache.txt",
            "tools/__pycache__/a.pyc",
        ] {
            assert!(!is_build_input(path), "{path}");
        }
        assert!(is_build_input(
            "3rd_party/Src/DirectXMath/DirectXMath-extra/source.h"
        ));
    }
    #[test]
    fn provisioned_dependency_roots_match_updater() {
        let source = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../..");
        let script = std::fs::read_to_string(source.join("Update_Components.cmd")).unwrap();
        let destinations: Vec<_> = script
            .lines()
            .filter(|l| l.starts_with("git clone "))
            .map(|l| l.split_whitespace().last().unwrap().replace('\\', "/"))
            .collect();
        for path in &destinations {
            assert!(
                super::snapshot::DEPENDENCIES
                    .iter()
                    .any(|root| path == root || path.starts_with(&format!("{root}/"))),
                "Missing dependency: {path}"
            );
        }
        for root in super::snapshot::DEPENDENCIES {
            assert!(
                destinations.iter().any(|path| path == root),
                "Stale dependency: {root}"
            );
        }
    }
}
