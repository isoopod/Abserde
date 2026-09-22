use std::{fs, path::PathBuf};

use anyhow::{Context, anyhow};
use serde::{Deserialize, Serialize};

#[derive(Debug, Serialize, Deserialize)]
pub struct AbserdeConfig {
    pub project_path: PathBuf,
    pub universe_id: Option<u64>,
}

impl AbserdeConfig {
    /// Reads and parses the `.abserde/config.json` file relative to the CWD.
    /// Returns `Ok(None)` if `.abserde/config.json` does not exist.
    pub fn load() -> anyhow::Result<Option<Self>> {
        let cwd = std::env::current_dir()?;
        let config_path = cwd.join(".abserde/config.json");

        if !config_path.exists() {
            return Ok(None);
        }

        let content = fs::read_to_string(&config_path)
            .with_context(|| format!("Failed to read {}", config_path.display()))?;

        let config: Self = serde_json::from_str(&content)
            .with_context(|| format!("Failed to parse JSON in {}", config_path.display()))?;

        Ok(Some(config))
    }

    /// Resolves `project_path` against CWD to get the absolute / fully-qualified path.
    pub fn resolved_project_path(&self) -> anyhow::Result<PathBuf> {
        let cwd = std::env::current_dir()?;
        Ok(cwd.join(&self.project_path))
    }
}

/// Retrieves the configuration, failing with a `Result::Err` if the directory is not an Abserde project.
pub fn get_config() -> anyhow::Result<AbserdeConfig> {
    AbserdeConfig::load()?.ok_or_else(|| {
        anyhow!(
            "Not an Abserde project (missing `.abserde/config.json`). Run `abserde init` first."
        )
    })
}

/// Retrieves the resolved absolute project path directly, failing if not inside an Abserde project.
pub fn get_project_path() -> anyhow::Result<PathBuf> {
    let config = get_config()?;
    config
        .resolved_project_path()
        .context("Invalid project path in .abserde/config.json")
}
