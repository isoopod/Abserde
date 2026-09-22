use clap::{Parser, Subcommand};

use crate::commands::{auth, deauth, init, new, update};

#[derive(Parser)]
#[command(
    name = "abserde",
    version,
    about = "Manages the Abserde datastore library"
)]
pub struct Cli {
    #[command(subcommand)]
    pub command: Commands,
}

#[derive(Subcommand)]
pub enum Commands {
    /// Initializes the Abserde project.
    Init(init::InitArgs),
    /// Creates a new schema, profile, or transform with the default template.
    New(new::NewArgs),
    /// Looks for updates to schema definitions and creates snapshots accordingly.
    ///
    /// Changes to comments or code format will trigger an update.
    Update,
    /// Authenticate and save credentials for this universe.
    Auth(auth::AuthArgs),
    /// Revoke and remove the saved credential for this universe.
    Deauth(deauth::DeauthArgs),
}

pub fn run() -> anyhow::Result<()> {
    let cli = Cli::parse();

    match cli.command {
        Commands::Init(args) => init::run(args),
        Commands::New(args) => new::run(args),
        Commands::Update => update::run(),
        Commands::Auth(args) => auth::run(args),
        Commands::Deauth(args) => deauth::run(args),
        // _ => anyhow::bail!("Unexpected command"),
    }
}
