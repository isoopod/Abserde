use std::sync::LazyLock;

use tokio::runtime::{Handle, Runtime};

pub mod auth;
pub mod cli;
pub mod commands;
pub mod config;
pub mod pkce;

static RUNTIME: LazyLock<Runtime> = LazyLock::new(|| {
    tokio::runtime::Builder::new_multi_thread()
        .enable_all()
        .build()
        .expect("Failed to create Tokio runtime")
});

/// Get a reference to the global runtime's Handle
pub fn runtime_handle() -> &'static Handle {
    RUNTIME.handle()
}

/// Block the current synchronous thread until the given future resolves
pub fn s_await<F>(future: F) -> F::Output
where
    F: std::future::Future,
{
    RUNTIME.block_on(future)
}

fn main() -> anyhow::Result<()> {
    if let Err(e) = cli::run() {
        eprintln!("{e:?}");
        std::process::exit(1);
    }
    Ok(())
}
