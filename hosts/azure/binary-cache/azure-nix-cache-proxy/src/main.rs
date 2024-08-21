// SPDX-FileCopyrightText: 2024 TII (SSRC) and the Ghaf contributors
// SPDX-License-Identifier: GPL-3.0-or-later

use azure_nix_cache_proxy::{gen_router, util, AppState};
use clap::Parser;
use tracing::info;

/// Expose a Azure Storage Container hosting Nix binary cache contents
/// over HTTP.
#[derive(Parser)]
#[command(version, about, long_about = None)]
struct Cli {
    /// The address to listen on
    #[clap(flatten)]
    listen_args: tokio_listener::ListenerAddressLFlag,

    /// The Container name inside the storage account.
    /// The storage account name is usually required too,
    /// and can be passed via the `AZURE_STORAGE_ACCOUNT_NAME` env var.
    container_name: String,
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    let cli = Cli::parse();

    // Setup tracing
    util::setup_tracing();

    // Setup object store
    let app_state = AppState::new(cli.container_name)?;

    let listen_address = &cli.listen_args.listen_address.unwrap_or_else(|| {
        "[::]:9000"
            .parse()
            .expect("invalid fallback listen address")
    });

    let listener = tokio_listener::Listener::bind(
        listen_address,
        &Default::default(),
        &cli.listen_args.listener_options,
    )
    .await?;

    info!(listen_address=%listen_address, "starting daemon");

    let app = gen_router().with_state(app_state);

    tokio_listener::axum07::serve(
        listener,
        app.into_make_service_with_connect_info::<tokio_listener::SomeSocketAddrClonable>(),
    )
    .await?;

    Ok(())
}
