use futures_util::StreamExt;
use reqwest::header::{HeaderMap, HeaderName, HeaderValue};
use reqwest::Client;
use std::path::Path;
use std::sync::{Arc, LazyLock};
use std::time::{Duration, Instant};
use tokio::io::AsyncWriteExt;
use tokio_util::sync::CancellationToken;

use super::error::{DownlyError, Result};

pub const SAFARI_UA: &str = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15";
pub const CHROME_UA: &str = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36";

pub fn build_client(user_agent: &str, timeout: u64, jar: Option<Arc<reqwest::cookie::Jar>>) -> Client {
    let mut headers = HeaderMap::new();
    headers.insert("Accept-Language", HeaderValue::from_static("en-US,en;q=0.9"));
    let mut builder = Client::builder()
        .user_agent(user_agent)
        .default_headers(headers)
        .timeout(Duration::from_secs(timeout))
        .connect_timeout(Duration::from_secs(15))
        .gzip(true)
        .brotli(true)
        .redirect(reqwest::redirect::Policy::limited(10));
    builder = match jar {
        Some(jar) => builder.cookie_provider(jar),
        None => builder.cookie_store(true),
    };
    builder.build().unwrap_or_else(|_| Client::new())
}

pub static SAFARI: LazyLock<Client> = LazyLock::new(|| build_client(SAFARI_UA, 25, None));
pub static CHROME: LazyLock<Client> = LazyLock::new(|| build_client(CHROME_UA, 25, None));
pub static DOWNLOADER: LazyLock<Client> = LazyLock::new(|| {
    Client::builder()
        .user_agent(SAFARI_UA)
        .connect_timeout(Duration::from_secs(20))
        .read_timeout(Duration::from_secs(60))
        .redirect(reqwest::redirect::Policy::limited(10))
        .build()
        .unwrap_or_else(|_| Client::new())
});

static NO_REDIRECT: LazyLock<Client> = LazyLock::new(|| {
    Client::builder()
        .user_agent(SAFARI_UA)
        .timeout(Duration::from_secs(20))
        .redirect(reqwest::redirect::Policy::none())
        .build()
        .unwrap_or_else(|_| Client::new())
});

pub async fn redirect_target(url: &str) -> Option<String> {
    let response = NO_REDIRECT.get(url).send().await.ok()?;
    let location = response.headers().get(reqwest::header::LOCATION)?.to_str().ok()?;
    Some(response.url().join(location).map(|u| u.to_string()).unwrap_or_else(|_| location.to_string()))
}

pub struct Page {
    pub status: u16,
    pub final_url: String,
    pub body: String,
}

impl Page {
    pub fn ok(&self) -> bool {
        (200..300).contains(&self.status)
    }

    pub fn json(&self) -> serde_json::Value {
        super::json::parse(&self.body)
    }
}

pub fn headers(pairs: &[(&str, &str)]) -> HeaderMap {
    let mut map = HeaderMap::new();
    for (key, value) in pairs {
        if let (Ok(name), Ok(value)) = (HeaderName::from_bytes(key.as_bytes()), HeaderValue::from_str(value)) {
            map.insert(name, value);
        }
    }
    map
}

pub async fn get(client: &Client, url: &str, extra: HeaderMap) -> Result<Page> {
    let response = client.get(url).headers(extra).send().await?;
    let status = response.status().as_u16();
    let final_url = response.url().to_string();
    let body = response.text().await.unwrap_or_default();
    Ok(Page { status, final_url, body })
}

pub async fn post(client: &Client, url: &str, extra: HeaderMap, body: Vec<u8>) -> Result<Page> {
    let response = client.post(url).headers(extra).body(body).send().await?;
    let status = response.status().as_u16();
    let final_url = response.url().to_string();
    let body = response.text().await.unwrap_or_default();
    Ok(Page { status, final_url, body })
}

pub async fn final_url(url: &str) -> String {
    if let Ok(response) = SAFARI.head(url).send().await {
        if response.status().as_u16() < 400 {
            return response.url().to_string();
        }
    }
    if let Ok(response) = SAFARI.get(url).send().await {
        return response.url().to_string();
    }
    url.to_string()
}

pub struct Downloaded {
    pub mime: Option<String>,
    pub bytes: u64,
}

pub async fn download_file(
    url: &str,
    destination: &Path,
    extra: HeaderMap,
    cancel: &CancellationToken,
    progress: &(dyn Fn(u64, Option<u64>) + Send + Sync),
) -> Result<Downloaded> {
    if cancel.is_cancelled() {
        return Err(DownlyError::Cancelled);
    }
    if let Some(parent) = destination.parent() {
        tokio::fs::create_dir_all(parent).await?;
    }
    let response = tokio::select! {
        _ = cancel.cancelled() => return Err(DownlyError::Cancelled),
        result = DOWNLOADER.get(url).headers(extra).send() => result?,
    };
    let status = response.status();
    if !status.is_success() {
        return Err(DownlyError::Http(status.as_u16()));
    }
    let total = response.content_length();
    let mime = response
        .headers()
        .get("content-type")
        .and_then(|v| v.to_str().ok())
        .map(|v| v.split(';').next().unwrap_or(v).trim().to_lowercase());
    let partial = destination.with_extension("partial");
    let mut file = tokio::fs::File::create(&partial).await?;
    let mut stream = response.bytes_stream();
    let mut received: u64 = 0;
    let mut last = Instant::now() - Duration::from_secs(1);
    loop {
        let next = tokio::select! {
            _ = cancel.cancelled() => {
                drop(file);
                let _ = tokio::fs::remove_file(&partial).await;
                return Err(DownlyError::Cancelled);
            }
            chunk = stream.next() => chunk,
        };
        match next {
            Some(Ok(chunk)) => {
                file.write_all(&chunk).await?;
                received += chunk.len() as u64;
                if last.elapsed() >= Duration::from_millis(120) {
                    last = Instant::now();
                    progress(received, total);
                }
            }
            Some(Err(error)) => {
                drop(file);
                let _ = tokio::fs::remove_file(&partial).await;
                return Err(error.into());
            }
            None => break,
        }
    }
    file.flush().await?;
    drop(file);
    progress(received, total.or(Some(received)));
    tokio::fs::rename(&partial, destination).await?;
    Ok(Downloaded { mime, bytes: received })
}
