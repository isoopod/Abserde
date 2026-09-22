use anyhow::{Context, Result};
use keyring::Entry;
use serde::{Deserialize, Serialize};

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
