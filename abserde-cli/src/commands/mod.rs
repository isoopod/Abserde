use std::{fs, path::PathBuf};

pub mod init;
pub mod new;
pub mod update;

// Utilities

pub fn get_project_path() -> anyhow::Result<Option<PathBuf>> {
    let cwd = std::env::current_dir()?;
    let record_path = std::env::current_dir()?.join(".abserde/project_path");

    if !record_path.exists() {
        return Ok(None);
    };

    let content = fs::read_to_string(&record_path)?;
    Ok(Some(cwd.join(content.trim())))
}
