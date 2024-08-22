// SPDX-FileCopyrightText: 2024 TII (SSRC) and the Ghaf contributors
// SPDX-License-Identifier: GPL-3.0-or-later

use std::sync::Arc;

use axum::{
    body::Bytes,
    http::StatusCode,
    response::Response,
    routing::{get, head},
    Router,
};
use axum_extra::{headers::Range, TypedHeader};
use axum_range::{AsyncSeekStart, KnownSize, Ranged};
use nix_compat::nixbase32;
use object_store::ObjectStore;
use tokio::io::AsyncRead;
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

async fn narinfo_get(
    axum::extract::Path(narinfo_str): axum::extract::Path<String>,
    axum::extract::State(AppState { store }): axum::extract::State<AppState>,
) -> Result<Bytes, StatusCode> {
    let digest =
        nix_compat::nix_http::parse_narinfo_str(&narinfo_str).ok_or(StatusCode::NOT_FOUND)?;
    let p = &object_store::path::Path::parse(format!("{}.narinfo", nixbase32::encode(&digest)))
        .expect("valid path");

    let resp = store.get(&p).await.map_err(|e| {
        if let object_store::Error::NotFound { path, source } = e {
            debug!(err=%source, %path, "path not found");
            StatusCode::NOT_FOUND
        } else {
            warn!(err=%e, "error from object store");
            StatusCode::INTERNAL_SERVER_ERROR
        }
    })?;

    resp.bytes().await.map_err(|e| {
        warn!(err=%e, "error collecting to bytes");
        StatusCode::INTERNAL_SERVER_ERROR
    })
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
    ranges: Option<TypedHeader<Range>>,
    axum::extract::Path(nar_str): axum::extract::Path<String>,
    axum::extract::State(AppState { store }): axum::extract::State<AppState>,
) -> Result<axum_range::Ranged<axum_range::KnownSize<impl AsyncRead + AsyncSeekStart>>, StatusCode>
{
    let (digest, compression_suffix) =
        nix_compat::nix_http::parse_nar_str(&nar_str).ok_or(StatusCode::NOT_FOUND)?;

    let p = object_store::path::Path::parse(format!(
        "nar/{}.nar{}",
        nixbase32::encode(&digest),
        compression_suffix
    ))
    .expect("valid path");

    // stat the object
    let meta = store.head(&p).await.map_err(|e| {
        if let object_store::Error::NotFound { path, source } = e {
            debug!(err=%source, %path, "path not found");
            StatusCode::NOT_FOUND
        } else {
            warn!(err=%e, "error from object store");
            StatusCode::INTERNAL_SERVER_ERROR
        }
    })?;

    let r = object_store::buffered::BufReader::with_capacity(store, &meta, 1024 * 1024);
    Ok(Ranged::new(
        ranges.map(|TypedHeader(ranges)| ranges),
        KnownSize::sized(r, meta.size as u64),
    ))
}

async fn nix_cache_info(
    axum::extract::State(AppState { store }): axum::extract::State<AppState>,
) -> Result<Bytes, StatusCode> {
    let p = object_store::path::Path::parse("nix-cache-info").expect("valid path");

    let resp = store.get(&p).await.map_err(|e| {
        if let object_store::Error::NotFound { path, source } = e {
            debug!(err=%source, %path, "path not found");
            StatusCode::NOT_FOUND
        } else {
            warn!(err=%e, "error from object store");
            StatusCode::INTERNAL_SERVER_ERROR
        }
    })?;

    resp.bytes().await.map_err(|e| {
        warn!(err=%e, "error collecting to bytes");
        StatusCode::INTERNAL_SERVER_ERROR
    })
}
