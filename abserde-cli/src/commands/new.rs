use anyhow::{Context, Result};
use clap::{Args, ValueEnum};

use crate::commands::{
    get_project_path,
    init::{create_dir, write_file},
};

#[derive(Args)]
pub struct NewArgs {
    /// The type of artefact to create
    pub kind: ArtefactKind,

    /// Name of the new artefact
    #[arg(short, long)]
    pub name: String,
}

#[derive(ValueEnum, Clone)]
pub enum ArtefactKind {
    Schema,
    Profile,
    Transform,
}

impl ArtefactKind {
    fn directory(&self) -> &'static str {
        match self {
            Self::Schema => "Schemas",
            Self::Profile => "Profiles",
            Self::Transform => "Transforms",
        }
    }

    fn content(&self) -> &'static str {
        match self {
            Self::Schema => include_str!("templates/schema.luau"),
            Self::Profile => include_str!("templates/profile.luau"),
            Self::Transform => include_str!("templates/transform.luau"),
        }
    }
}

pub fn run(args: NewArgs) -> Result<()> {
    let project_path = get_project_path()?.ok_or_else(|| {
        anyhow::anyhow!("No project found in the current directory. Run `abserde init` first.")
    })?;

    let dir = project_path.join(args.kind.directory());
    let file_path = dir.join(format!("{}.luau", args.name));

    // Directory should already exist from init
    create_dir(&dir)?;
    write_file(&file_path, args.kind.content())
        .with_context(|| format!("Failed to create artefact: {}", file_path.display()))?;

    println!("Created {} at {}", args.name, file_path.display());
    Ok(())
}
