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

/// Read only the solution's configuration table, not project-level mappings.
pub fn has_solution_configuration(solution: &str, configuration: &str) -> bool {
    let expected = format!("{configuration}|x64");
    let mut in_configurations = false;
    for line in solution.lines().map(str::trim) {
        if line.starts_with("GlobalSection(SolutionConfigurationPlatforms)") {
            in_configurations = true;
        } else if line == "EndGlobalSection" {
            in_configurations = false;
        } else if in_configurations
            && line
                .split_once('=')
                .is_some_and(|(key, value)| key.trim() == expected && value.trim() == expected)
        {
            return true;
        }
    }
    false
}

#[cfg(test)]
mod tests {
    use super::has_solution_configuration;

    #[test]
    fn configuration_requires_a_solution_entry() {
        let mapping = "GlobalSection(ProjectConfigurationPlatforms) = postSolution\nReleaseTracyProfiler|x64 = ReleaseTracyProfiler|x64\nEndGlobalSection";
        assert!(!has_solution_configuration(mapping, "ReleaseTracyProfiler"));
        let configurations = "GlobalSection(SolutionConfigurationPlatforms) = preSolution\n  ReleaseTracyProfiler|x64 = ReleaseTracyProfiler|x64\nEndGlobalSection";
        assert!(has_solution_configuration(
            configurations,
            "ReleaseTracyProfiler"
        ));
        assert!(!has_solution_configuration(configurations, "Release"));
    }
}
