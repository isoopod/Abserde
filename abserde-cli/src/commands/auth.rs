use anyhow::{Context, Result, anyhow, bail};
use clap::Args;
use inquire::{Confirm, Password, Select};

use crate::{
    auth::{AuthType, StoredCredentials, load_credentials, save_credentials},
    config::get_config,
    pkce::{CLIENT_ID, run_oidc_flow},
};

#[derive(Args)]
pub struct AuthArgs {
    /// Skip confirmation prompts if credentials already exist.
    #[arg(short, long)]
    force: bool,
}

pub fn run(args: AuthArgs) -> Result<()> {
    let universe_id = get_config()?
        .universe_id
        .ok_or_else(|| anyhow!("'universe_id' needs to be set in .abserde/config.json"))?;
    let force = args.force;

    // Check if we already have existing credentials
    if let Some(_existing) = load_credentials(universe_id)? {
        if !force {
            let overwrite = Confirm::new(&format!(
                "Credentials already exist for Universe {universe_id}. Overwrite?"
            ))
            .with_default(false)
            .prompt()?;

            if !overwrite {
                println!("Operation cancelled.");
                return Ok(());
            }
        }
    }

    let auth_methods = vec!["Open Cloud API Key", "OAuth 2.0 PKCE (Browser)"];
    let selection = Select::new(
        &format!("Select authentication method for Universe {universe_id}:"),
        auth_methods,
    )
    .prompt()?;

    let creds = match selection {
        "Open Cloud API Key" => {
            println!("\nGenerate a key at https://create.roblox.com/dashboard/credentials");
            println!(
                "Ensure permissions include 'universe:read' and 'universe:write' for universe {universe_id}.\n"
            );

            let api_key = Password::new("Enter Roblox Open Cloud API Key:")
                .with_display_mode(inquire::PasswordDisplayMode::Masked)
                .without_confirmation()
                .prompt()?;

            let trimmed_key = api_key.trim();
            if trimmed_key.is_empty() {
                bail!("API Key cannot be empty");
            }

            StoredCredentials {
                auth_type: AuthType::OpenCloudApiKey,
                secret: trimmed_key.to_string(),
                refresh_token: None,
                expires_at: None,
            }
        }
        "OAuth 2.0 PKCE (Browser)" => {
            todo!("not implemented yet, use Open Cloud API Key for now.");
            // Need to set CLIENT_ID when I can get around to making an OAuth client key
            // Scopes required for Open Cloud APIs
            let scopes = vec!["openid", "universe.config:read", "universe.config:write"];

            let runtime = tokio::runtime::Builder::new_multi_thread()
                .enable_all()
                .build()
                .context("Failed to build Tokio runtime")?;

            let tokens = runtime.block_on(run_oidc_flow(CLIENT_ID, &scopes))?;

            let now = std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)?
                .as_secs() as i64;

            StoredCredentials {
                auth_type: AuthType::OAuth2AccessToken,
                secret: tokens.access_token,
                refresh_token: tokens.refresh_token,
                expires_at: Some(now + tokens.expires_in_secs.unwrap_or(0) as i64),
            }
        }
        _ => unreachable!(),
    };

    save_credentials(universe_id, &creds)?;
    println!("Successfully stored credentials in system keyring for Universe {universe_id}.");

    Ok(())
}
