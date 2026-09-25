use std::collections::HashMap;

use anyhow::{Context, Result, anyhow, bail};
use openidconnect::{
    ClientId, IssuerUrl, OAuth2TokenResponse, PkceCodeChallenge, RedirectUrl, RefreshToken, Scope,
    core::{CoreAuthenticationFlow, CoreClient, CoreProviderMetadata},
    reqwest::Client,
};
use tiny_http::{Response, Server};
use url::Url;

use crate::auth::{AuthType, StoredCredentials, load_credentials, save_credentials};

pub struct OidcTokens {
    pub access_token: String,
    pub refresh_token: Option<String>,
    pub expires_in_secs: Option<u64>,
}

pub const CLIENT_ID: &str = "TODO";

pub async fn run_oidc_flow(client_id: &str, scopes: &[&str]) -> Result<OidcTokens> {
    // Start local listener on loopback interface
    let server = Server::http("127.0.0.1:0").map_err(|e| anyhow!(e))?;
    let port = server
        .server_addr()
        .to_ip()
        .map(|addr| addr.port())
        .unwrap();
    let redirect_url = format!("http://127.0.0.1:{port}/callback");

    // Discover Roblox OIDC issuer
    let issuer_url = IssuerUrl::new("https://apis.roblox.com/oauth/".to_string())?;

    let async_http_client = Client::new();
    let provider_metadata = CoreProviderMetadata::discover_async(issuer_url, &async_http_client)
        .await
        .context("Failed to discover ROBLOX OIDC endpoints")?;

    let client = CoreClient::from_provider_metadata(
        provider_metadata,
        ClientId::new(client_id.to_string()),
        None, // Client secret is None for public PKCE clients
    )
    .set_redirect_uri(RedirectUrl::new(redirect_url)?);

    // Generate PKCE challenge and CSRF state
    let (pkce_challenge, pkce_verifier) = PkceCodeChallenge::new_random_sha256();

    let mut auth_request = client.authorize_url(
        CoreAuthenticationFlow::AuthorizationCode,
        openidconnect::CsrfToken::new_random,
        openidconnect::Nonce::new_random,
    );

    for scope in scopes {
        auth_request = auth_request.add_scope(Scope::new(scope.to_string()));
    }

    let (auth_url, csrf_token, _nonce) = auth_request.set_pkce_challenge(pkce_challenge).url();

    // Open browser
    println!("Opening browser for authentication...");
    println!(
        "If it does not open automatically, navigate to:\n{}",
        auth_url
    );

    let _ = open::that(auth_url.as_str());

    // Wait for incoming browser request
    let expected_csrf = csrf_token.secret().clone();
    let code = tokio::task::spawn_blocking(move || -> Result<openidconnect::AuthorizationCode> {
        let request = server
            .recv()
            .map_err(|e| anyhow!("Failed to receive redirect: {e}"))?;

        let req_url = format!("http://localhost{}", request.url());
        let parsed_url = Url::parse(&req_url)?;
        let query_params: HashMap<String, String> = parsed_url.query_pairs().into_owned().collect();

        // Verify CSRF state matches
        if let Some(state) = query_params.get("state") {
            if state != &expected_csrf {
                let response =
                    Response::from_string("<h1>CSRF State Mismatch</h1>").with_status_code(400);
                let _ = request.respond(response);
                bail!("CSRF state mismatch detected");
            }
        }

        let code = match query_params.get("code") {
            Some(c) => openidconnect::AuthorizationCode::new(c.to_string()),
            None => {
                let err = query_params
                    .get("error_descriptor")
                    .cloned()
                    .unwrap_or_else(|| "Authorization was denied or failed".into());

                let response =
                    Response::from_string(format!("<h1>Authentication Failed</h1><p>{err}</p>"))
                        .with_status_code(400);
                let _ = request.respond(response);
                bail!("OIDC login failed: {err}");
            }
        };

        let response =
            Response::from_string("<h1>Authentication Success</h1><p>You can close this tab.</p>");
        let _ = request.respond(response);

        Ok(code)
    })
    .await
    .context("Blocking HTTP listener task panicked")??;

    // Exchange code + pcke verifier for tokens
    let token_response = client
        .exchange_code(code)?
        .set_pkce_verifier(pkce_verifier)
        .request_async(&async_http_client)
        .await
        .context("Failed to exchange code for tokens")?;

    Ok(OidcTokens {
        access_token: token_response.access_token().secret().clone(),
        refresh_token: token_response.refresh_token().map(|t| t.secret().clone()),
        expires_in_secs: token_response.expires_in().map(|d| d.as_secs()),
    })
}

pub async fn refresh_oidc_token(client_id: &str, refresh_token_str: &str) -> Result<OidcTokens> {
    let issuer_url = IssuerUrl::new("https://apis.roblox.com/oauth/".to_string())?;

    let async_http_client = Client::new();
    let provider_metadata = CoreProviderMetadata::discover_async(issuer_url, &async_http_client)
        .await
        .context("Failed to discover ROBLOX OIDC endpoints")?;

    let client = CoreClient::from_provider_metadata(
        provider_metadata,
        ClientId::new(client_id.to_string()),
        None, // Client secret is None for public PKCE clients
    );

    let refresh_token = RefreshToken::new(refresh_token_str.to_string());

    let token_response = client
        .exchange_refresh_token(&refresh_token)?
        .request_async(&async_http_client)
        .await
        .context("Failed to refresh Roblox OAuth token")?;

    Ok(OidcTokens {
        access_token: token_response.access_token().secret().clone(),
        refresh_token: token_response
            .refresh_token()
            .map(|t| t.secret().clone())
            .or_else(|| Some(refresh_token_str.to_string())),
        expires_in_secs: token_response.expires_in().map(|d| d.as_secs()),
    })
}

const ROBLOX_REVOKE_URL: &str = "https://apis.roblox.com/oauth/v1/token/revoke";

pub async fn revoke_oidc_token(client_id: &str, refresh_token_str: &str) -> Result<()> {
    let client = reqwest::Client::new();

    let response = client
        .post(ROBLOX_REVOKE_URL)
        .form(&[
            ("client_id", client_id),
            ("token", refresh_token_str),
            ("token_type_hint", "refresh_token"),
        ])
        .send()
        .await
        .context("Failed to send revocation request to Roblox")?;

    if !response.status().is_success() {
        let status = response.status();
        let body = response.text().await.unwrap_or_default();
        bail!("Revocation request failed with status {status}: {body}");
    }

    Ok(())
}

pub async fn get_valid_access_token(universe_id: u64, client_id: &str) -> Result<String> {
    let creds = match load_credentials(universe_id)? {
        Some(c) => c,
        None => bail!("No credentials found for Universe {universe_id}. Please run `auth` first."),
    };

    match creds.auth_type {
        AuthType::OpenCloudApiKey => Ok(creds.secret),

        AuthType::OAuth2AccessToken => {
            let now = std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)?
                .as_secs() as i64;

            // Buffer by 60 seconds to prevent edge-case expiration during request
            let is_expired = creds.expires_at.map_or(false, |exp| now >= (exp - 60));

            if is_expired {
                let refresh_token = creds
                    .refresh_token
                    .as_deref()
                    .context("Access token is expired and no refresh token was found.")?;

                println!("Access token expired. Refreshing...");
                let new_tokens = refresh_oidc_token(client_id, refresh_token).await?;

                let updated_creds = StoredCredentials {
                    auth_type: AuthType::OAuth2AccessToken,
                    secret: new_tokens.access_token.clone(),
                    refresh_token: new_tokens.refresh_token,
                    expires_at: new_tokens.expires_in_secs.map(|secs| now + secs as i64),
                };

                save_credentials(universe_id, &updated_creds)?;
                Ok(new_tokens.access_token)
            } else {
                Ok(creds.secret)
            }
        }
    }
}
