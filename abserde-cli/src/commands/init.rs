use anyhow::Context;
use clap::Args;
use inquire::Text;
use std::{fs, io::Write, path::Path};

use crate::config::AbserdeConfig;

#[derive(Args)]
pub struct InitArgs {
    /// Path to the source directory.
    ///
    /// Should be relative to the current working directory.
    #[arg(short, long, default_value = ".")]
    pub path: String,

    /// Skip interactive prompts and use defaults.
    #[arg(short, long)]
    pub yes: bool,
}

enum TemplateNode {
    File {
        name: &'static str,
        content: &'static str,
    },
    Dir {
        name: &'static str,
        children: &'static [TemplateNode],
    },
}

macro_rules! tree {
    (file $name:literal => $content:expr) => {
        TemplateNode::File { name: $name, content: $content }
    };

    (dir $name:literal { $($body:tt)* }) => {
        TemplateNode::Dir {
            name: $name,
            children: tree!(@children [] $($body)*),
        }
    };

    // Internal accumulator arms
    // Base case: no more tokens, emit the collected slice
    (@children [$($acc:expr),*]) => {
        &[$($acc),*]
    };
    // Consume a dir entry: the {} block makes the boundary unambiguous
    (@children [$($acc:expr),*] dir $name:literal { $($body:tt)* } $($rest:tt)*) => {
        tree!(@children [$($acc,)* tree!(dir $name { $($body)* })] $($rest)*)
    };
    // Consume a file entry: requires a trailing comma to resolve expr ambiguity
    (@children [$($acc:expr),*] file $name:literal => $content:expr, $($rest:tt)*) => {
        tree!(@children [$($acc,)* tree!(file $name => $content)] $($rest)*)
    };
    // Consume a file entry: last item, no trailing comma
    (@children [$($acc:expr),*] file $name:literal => $content:expr) => {
        tree!(@children [$($acc,)* tree!(file $name => $content)])
    };
}

const PROJECT_TEMPLATE: TemplateNode = tree! {
    dir "abserde_project" {
        dir "Schemas" {
            dir "Snapshots" {}
            file "ExampleSchema.luau" => include_str!("templates/schema.luau")
        }
        dir "Profiles" {
            file "ExampleProfile.luau" => include_str!("templates/profile.luau")
        }
        dir "Transforms" {
            file "ExampleTransform.luau" => include_str!("templates/transform.luau")
        }
    }
};

pub fn create_dir(path: &Path) -> anyhow::Result<()> {
    fs::create_dir_all(path)
        .with_context(|| format!("Failed to create directory: {}", path.display()))?;
    Ok(())
}

pub fn write_file(path: &Path, content: &str) -> anyhow::Result<()> {
    let mut file = match fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(path)
    {
        Ok(f) => f,
        Err(e) if e.kind() == std::io::ErrorKind::AlreadyExists => return Ok(()),
        Err(e) => {
            return Err(e)
                .with_context(|| format!("Failed to open file for writing: {}", path.display()));
        }
    };

    file.write_all(content.as_bytes())?;
    Ok(())
}

fn write_node(base: &Path, node: &TemplateNode) -> anyhow::Result<()> {
    match node {
        TemplateNode::File { name, content } => {
            let file_path = base.join(name);
            write_file(&file_path, content)?;
        }
        TemplateNode::Dir { name, children } => {
            let dir_path = base.join(name);
            create_dir(&dir_path)?;
            for child in *children {
                write_node(&dir_path, child)?;
            }
        }
    }
    Ok(())
}

pub fn run(args: InitArgs) -> anyhow::Result<()> {
    let cwd = std::env::current_dir()?;
    let target_path = cwd.join(args.path);

    let universe_id = if args.yes {
        None
    } else {
        println!("Welcome to Abserde Init.");

        let input = Text::new("(optional) Roblox Universe ID:")
            .with_help_message("Press enter to skip")
            .prompt()?;

        let trimmed = input.trim();
        if trimmed.is_empty() {
            None
        } else {
            Some(
                trimmed
                    .parse::<u64>()
                    .context("Invalid Universe ID. Please enter a positive integer.")?,
            )
        }
    };

    write_node(&target_path, &PROJECT_TEMPLATE)?;

    // Save configuration into .abserde/config.json
    let abserde_dir = cwd.join(".abserde");
    create_dir(&abserde_dir)?;

    let relative_target = target_path.strip_prefix(&cwd).unwrap_or(&target_path);
    let project_relative_path = relative_target.join("abserde_project");

    let config = AbserdeConfig {
        project_path: project_relative_path,
        universe_id,
    };

    let config_json = serde_json::to_string_pretty(&config)?;
    fs::write(abserde_dir.join("config.json"), config_json)
        .context("Failed to save .abserde/config.json")?;

    println!(
        "\nInitialized new Abserde project at {}",
        target_path.display()
    );
    println!("\nNext steps:");
    println!("  1. Rename ExampleSchema.luau or create a new one with `abserde new schema`");
    println!("  2. Run `abserde update` before modifying it");

    Ok(())
}
