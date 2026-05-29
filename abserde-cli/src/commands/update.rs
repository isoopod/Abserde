use std::{
    collections::HashMap,
    fs::{self, File},
    io::{self, Read},
    path::Path,
};

use serde::{Deserialize, Serialize};
use xxhash_rust::xxh3::Xxh3;

use crate::commands::get_project_path;

#[derive(Serialize, Deserialize, Default)]
struct SnapshotState {
    hashes: HashMap<String, u64>,
}

fn hash_file(path: &Path) -> io::Result<u64> {
    let mut file = File::open(path)?;
    let mut hasher = Xxh3::new();
    let mut buffer = [0; 8192];

    loop {
        let bytes_read = file.read(&mut buffer)?;
        if bytes_read == 0 {
            break;
        }
        hasher.update(&buffer[..bytes_read]);
    }

    Ok(hasher.digest())
}

pub fn run() -> anyhow::Result<()> {
    let project = get_project_path()?.ok_or_else(|| {
        anyhow::anyhow!("No project found in the current directory. Run `abserde init` first.")
    })?;
    let schemas = project.join("Schemas");

    let cwd = std::env::current_dir()?;
    let snapshots_file = cwd.join(".abserde/snapshots.json");
    let existing = match fs::read(&snapshots_file) {
        Ok(bytes) => serde_json::from_slice::<SnapshotState>(&bytes).unwrap_or_default(),
        Err(_) => SnapshotState::default(),
    };

    let mut new = SnapshotState {
        hashes: HashMap::new(),
    };

    println!("Searching for updated schemas");
    let mut n_updated = 0;

    for entry in fs::read_dir(&schemas)? {
        let entry = entry?;
        let path = entry.path();

        if path.extension() == Some(std::ffi::OsStr::new("luau")) {
            let name = entry.file_name().to_string_lossy().into_owned();
            let hash = hash_file(&path)?;
            new.hashes.insert(name.clone(), hash);

            if existing.hashes.contains_key(&name) && existing.hashes[&name] != hash {
                let versions = schemas.join("Snapshots").join(&name);
                fs::create_dir_all(&versions)?;

                let mut max_version = 0;
                for snapshot_version in fs::read_dir(&versions)? {
                    let snapshot_version = snapshot_version?;
                    let version: i32 =
                        match snapshot_version.path().file_stem().and_then(|s| s.to_str()) {
                            Some(s) => match s.parse() {
                                Ok(n) => n,
                                Err(_) => continue,
                            },
                            None => continue,
                        };
                    max_version = max_version.max(version)
                }

                let version = max_version + 1;
                fs::copy(path, versions.join(format!("{version}.luau")))?;

                println!("Created new snapshot (v{version}) for schema {name}");
                n_updated += 1;
            }
        }
    }

    fs::write(&snapshots_file, serde_json::to_string_pretty(&new)?)?;

    if n_updated == 0 {
        println!("Nothing to do")
    } else {
        println!("Created {n_updated} new snapshots")
    }

    Ok(())
}
