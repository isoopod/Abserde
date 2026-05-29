mod cli;
mod commands;

fn main() -> anyhow::Result<()> {
    if let Err(e) = cli::run() {
        eprintln!("{e:?}");
        std::process::exit(1);
    }
    Ok(())
}
