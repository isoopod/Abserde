use anyhow::{Context, Result, anyhow};
use clap::Args;
use inquire::Confirm;

use crate::{
    auth::{AuthType, delete_credentials, load_credentials},
    config::get_config,
    pkce::{CLIENT_ID, revoke_oidc_token},
};

#[derive(Args)]
pub struct DeauthArgs {
    /// Skip removal confirmation prompt.
    #[arg(short, long)]
    force: bool,
}

pub async fn run(args: DeauthArgs) -> Result<()> {
    let universe_id = get_config()?
        .universe_id
        .ok_or_else(|| anyhow!("'universe_id' needs to be set in .abserde/config.json"))?;
    let force = args.force;

    let existing = load_credentials(universe_id)?;

    let creds = match existing {
        Some(c) => c,
        None => {
            println!("No stored credentials found for Universe ID {universe_id}.");
            return Ok(());
        }
    };

    if !force {
        let confirm = Confirm::new(&format!(
            "Are you sure you want to remove stored credentials for Universe ID {universe_id}?"
        ))
        .with_default(false)
        .prompt()
        .context("Failed to prompt for deletion confirmation")?;

        if !confirm {
            println!("Operation cancelled.");
            return Ok(());
        }
    }

    if matches!(creds.auth_type, AuthType::OAuth2AccessToken) {
        if let Some(ref refresh_token) = creds.refresh_token {
            print!("Revoking OAuth session with Roblox...");

            match revoke_oidc_token(CLIENT_ID, refresh_token).await {
                Ok(_) => println!(" Done."),
                Err(err) => {
                    eprintln!("\nFailed to revoke OAuth token upstream: {err}");
                    let proceed = Confirm::new("Delete local credentials anyway?")
                        .with_default(true)
                        .prompt()
                        .context("Failed to prompt for force local deletion")?;

                    if !proceed {
                        println!("Operation cancelled.");
                        return Ok(());
                    }
                }
            }
        }
    }

    if delete_credentials(universe_id)? {
        println!(
            "Successfully removed credentials from system keyring for Universe ID {universe_id}."
        );

        if matches!(creds.auth_type, AuthType::OpenCloudApiKey) {
            println!("\nNote: Removing local credentials does not revoke API keys on Roblox.");
            println!("To permanently disable or delete this key, visit:");
            println!("https://create.roblox.com/dashboard/credentials\n");
        }
    }

    Ok(())
}
