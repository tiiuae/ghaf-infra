// SPDX-FileCopyrightText: 2024 TII (SSRC) and the Ghaf contributors
// SPDX-License-Identifier: GPL-3.0-or-later

use std::sync::Arc;

use axum::{
    body::Body,
    http::StatusCode,
    response::Response,
    routing::{get, head},
    Router,
};
use nix_compat::nixbase32;
use object_store::ObjectStore;
use tracing::{debug, warn};

pub mod util;

#[derive(Clone)]
pub struct AppState {
    store: Arc<object_store::azure::MicrosoftAzure>,
}

impl AppState {
    pub fn new(container_name: impl Into<String>) -> object_store::Result<Self> {
        Ok(Self {
            store: Arc::new(
                object_store::azure::MicrosoftAzureBuilder::from_env()
                    .with_container_name(container_name)
                    .build()?,
            ),
        })
    }
}

pub fn gen_router() -> Router<AppState> {
    Router::new()
        .route("/", get(root))
        .route("/:narinfo_str", get(narinfo_get))
        .route("/:narinfo_str", head(narinfo_head))
        .route("/nar/:nar_str", get(nar_get))
        .route("/nix-cache-info", get(nix_cache_info))
}

async fn root() -> String {
    format!(
        "Hello from {} {}",
        clap::crate_name!(),
        clap::crate_version!()
    )
}

async fn response_from_store(
    store: impl ObjectStore,
    p: &object_store::path::Path,
) -> Result<Response, StatusCode> {
    match store.get(p).await {
        Err(object_store::Error::NotFound { path, source }) => {
            debug!(err=%source, %path, "path not found");
            Err(StatusCode::NOT_FOUND)
        }
        Err(e) => {
            warn!(err=%e, "error from object store");
            Err(StatusCode::INTERNAL_SERVER_ERROR)
        }
        Ok(resp) => Ok(Response::builder()
            .status(StatusCode::OK)
            .header("content-length", resp.meta.size)
            .body(Body::from_stream(resp.into_stream()))
            .unwrap()),
    }
}

async fn narinfo_get(
    axum::extract::Path(narinfo_str): axum::extract::Path<String>,
    axum::extract::State(AppState { store }): axum::extract::State<AppState>,
) -> Result<Response, StatusCode> {
    let digest =
        nix_compat::nix_http::parse_narinfo_str(&narinfo_str).ok_or(StatusCode::NOT_FOUND)?;
    let p = &object_store::path::Path::parse(format!("{}.narinfo", nixbase32::encode(&digest)))
        .expect("valid path");

    response_from_store(store as Arc<dyn ObjectStore>, p).await
}

async fn narinfo_head(
    axum::extract::Path(narinfo_str): axum::extract::Path<String>,
    axum::extract::State(AppState { store }): axum::extract::State<AppState>,
) -> Result<Response, StatusCode> {
    let digest =
        nix_compat::nix_http::parse_narinfo_str(&narinfo_str).ok_or(StatusCode::NOT_FOUND)?;
    let path = object_store::path::Path::parse(format!("{}.narinfo", nixbase32::encode(&digest)))
        .expect("valid path");

    match store.head(&path).await {
        Ok(_) => Ok(Response::builder()
            .status(StatusCode::NO_CONTENT)
            .body("".into())
            .unwrap()),
        Err(object_store::Error::NotFound { path, source }) => {
            debug!(err=%source, %path, "path not found");
            Err(StatusCode::NOT_FOUND)
        }
        Err(_) => {
            debug!(%path, "failed to stat");
            Err(StatusCode::INTERNAL_SERVER_ERROR)
        }
    }
}

async fn nar_get(
    axum::extract::Path(nar_str): axum::extract::Path<String>,
    axum::extract::State(AppState { store }): axum::extract::State<AppState>,
) -> Result<Response, StatusCode> {
    let (digest, compression_suffix) =
        nix_compat::nix_http::parse_nar_str(&nar_str).ok_or(StatusCode::NOT_FOUND)?;

    let p = object_store::path::Path::parse(format!(
        "nar/{}.nar{}",
        nixbase32::encode(&digest),
        compression_suffix
    ))
    .expect("valid path");

    response_from_store(store as Arc<dyn ObjectStore>, &p).await
}

async fn nix_cache_info(
    axum::extract::State(AppState { store }): axum::extract::State<AppState>,
) -> Result<Response, StatusCode> {
    let p = object_store::path::Path::parse("nix-cache-info").expect("valid path");

    response_from_store(store as Arc<dyn ObjectStore>, &p).await
}
