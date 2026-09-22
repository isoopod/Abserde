pub mod auth;
pub mod cli;
pub mod commands;
pub mod config;
pub mod pkce;

fn main() -> anyhow::Result<()> {
    if let Err(e) = cli::run() {
        eprintln!("{e:?}");
        std::process::exit(1);
    }
    Ok(())
}
