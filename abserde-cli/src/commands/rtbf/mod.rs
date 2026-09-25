use anyhow::{Context, Result, anyhow, bail};
use clap::Args;
use inquire::Confirm;
use reqwest::Client;
use serde_json::json;

use crate::{
    auth::AuthenticateExt,
    commands::rtbf::parse_profile::{
        DataStoresConfigPayload, UserDataTemplates, parse_profile_rtbf_templates,
    },
    config::{get_config, get_project_path},
};

mod parse_profile;

#[derive(Args)]
pub struct RtbfArgs {
    /// Skip confirmation prompt.
    #[arg(short, long)]
    force: bool,

    /// Print what the command would have published (JSON)
    #[arg(long)]
    dry_run: bool,
}

pub async fn run(args: RtbfArgs) -> Result<()> {
    let universe_id = get_config()?
        .universe_id
        .ok_or_else(|| anyhow!("'universe_id' needs to be set in .abserde/config.json"))?;

    let mut templates = Vec::new();

    let project = get_project_path()?;
    for profile in project
        .join("profiles")
        .read_dir()
        .context("Failed to read project profiles")?
    {
        if let Ok(profile) = profile {
            let path = &profile.path();
            parse_profile_rtbf_templates(path, &mut templates)
                .with_context(|| format!("Failed to parse profile {}", path.display()))?
        }
    }

    let repository = format!(
        "https://apis.roblox.com/creator-configs-public-api/v1/configs/universes/{universe_id}/repositories/DataStoresConfig/"
    );

    let draft_url = format!("{repository}/draft:overwrite");
    let draft_payload = DataStoresConfigPayload {
        entries: UserDataTemplates {
            user_data_templates: templates,
        },
    };

    if args.dry_run {
        let json = serde_json::to_string_pretty(&draft_payload)?;

        println!("[DRY RUN]: Would have set RTBF templates for Universe {universe_id} to:");
        println!("{json}");

        return Ok(());
    }

    if !args.force {
        let confirm = Confirm::new("[WARNING]: This will overwrite existing RTBF templates, including ones not managed by Abserde.")
            .with_default(false)
            .prompt()
            .context("Failed to promnpt for confirmation")?;

        if !confirm {
            println!("Operation cancelled.");
            return Ok(());
        }
    }

    let client = Client::new();

    let draft_response = client
        .put(&draft_url)
        .json(&draft_payload)
        .authenticate(universe_id)
        .await?
        .send()
        .await
        .context("Failed to connect to Roblox Open Cloud Configs API")?;

    if !draft_response.status().is_success() {
        let status = draft_response.status();
        let body = draft_response.text().await.unwrap_or_default();
        bail!("Open Cloud Configs API error ({status}): {body}");
    }

    println!("Uploaded RTBF template draft. Comitting...");

    let commit_url = format!("{repository}/publish");
    let commit_payload = json!({
        "deploymentStrategy": "Immediate"
    });

    let commit_response = client
        .post(&commit_url)
        .json(&commit_payload)
        .authenticate(universe_id)
        .await?
        .send()
        .await
        .context("Failed to commit DataStoresConfig draft")?;

    if !commit_response.status().is_success() {
        let status = commit_response.status();
        let body = commit_response.text().await.unwrap_or_default();
        bail!("Failed to commit DataStoresConfig draft ({status}): {body}");
    }

    println!("Successfully published RTBF Templates for Universe {universe_id}.");
    Ok(())
}
