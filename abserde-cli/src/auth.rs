use anyhow::{Context, Result};
use keyring::Entry;
use reqwest::RequestBuilder;
use serde::{Deserialize, Serialize};

use crate::pkce::{CLIENT_ID, get_valid_access_token};

const SERVICE_NAME: &str = "abserde_cli";

#[derive(Debug, Serialize, Deserialize)]
pub enum AuthType {
    OpenCloudApiKey,
    OAuth2AccessToken,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct StoredCredentials {
    pub auth_type: AuthType,
    pub secret: String,
    pub refresh_token: Option<String>,
    pub expires_at: Option<i64>,
}

fn keyring_entry_for_universe(universe_id: u64) -> Result<Entry> {
    let key = format!("universe_{universe_id}");
    Entry::new(SERVICE_NAME, &key)
        .with_context(|| format!("Failed to create keyring entry for universe {universe_id}"))
}

pub fn save_credentials(universe_id: u64, creds: &StoredCredentials) -> Result<()> {
    let entry = keyring_entry_for_universe(universe_id)?;
    let serialized = serde_json::to_string(creds)?;
    entry.set_password(&serialized)?;
    Ok(())
}

pub fn load_credentials(universe_id: u64) -> Result<Option<StoredCredentials>> {
    let entry = keyring_entry_for_universe(universe_id)?;
    match entry.get_password() {
        Ok(json_str) => {
            let creds: StoredCredentials = serde_json::from_str(&json_str)?;
            Ok(Some(creds))
        }
        Err(keyring::Error::NoEntry) => Ok(None),
        Err(err) => Err(err).context("Failed to read credentials from system keyring"),
    }
}

pub fn delete_credentials(universe_id: u64) -> Result<bool> {
    let entry = keyring_entry_for_universe(universe_id)?;
    match entry.delete_credential() {
        Ok(_) => Ok(true),
        Err(keyring::Error::NoEntry) => Ok(false),
        Err(err) => Err(err).context("Failed to delete credentials from system keyring"),
    }
}

pub async fn authenticate_request(
    builder: RequestBuilder,
    universe_id: u64,
) -> Result<RequestBuilder> {
    let creds = load_credentials(universe_id)?.with_context(|| format!("No stored credentials found for Universe {universe_id}. Please run `abserde auth` first."))?;

    match creds.auth_type {
        AuthType::OpenCloudApiKey => Ok(builder.header("x-api-key", creds.secret)),
        AuthType::OAuth2AccessToken => {
            let token = get_valid_access_token(universe_id, CLIENT_ID).await?;
            Ok(builder.header("Authorization", format!("Bearer {token}")))
        }
    }
}

pub trait AuthenticateExt {
    fn authenticate(self, universe_id: u64) -> impl Future<Output = Result<RequestBuilder>> + Send;
}

impl AuthenticateExt for RequestBuilder {
    async fn authenticate(self, universe_id: u64) -> Result<RequestBuilder> {
        authenticate_request(self, universe_id).await
    }
}
