use clap::{Parser, Subcommand};

use crate::{
    commands::{auth, deauth, init, new, rtbf, update},
    s_await,
};

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
    /// Compile the RTBF templates for the abserde project and publish them.
    /// RTBF templates automatically handle right to be forgotten requests for your datastores.
    ///
    /// Will overwrite any existing RTBF templates, including those outside of Abserde.
    Rtbf(rtbf::RtbfArgs),
}

pub fn run() -> anyhow::Result<()> {
    let cli = Cli::parse();

    match cli.command {
        Commands::Init(args) => init::run(args),
        Commands::New(args) => new::run(args),
        Commands::Update => update::run(),
        Commands::Auth(args) => s_await(auth::run(args)),
        Commands::Deauth(args) => s_await(deauth::run(args)),
        Commands::Rtbf(args) => s_await(rtbf::run(args)),
    }
}
