use std::collections::{HashMap, VecDeque};
use std::sync::{Arc, LazyLock, Mutex};
use tauri::http::{header, Request, Response, StatusCode};
use tauri::{Runtime, UriSchemeContext, UriSchemeResponder};

use crate::engine::http;

struct Entry {
    mime: String,
    bytes: Arc<Vec<u8>>,
}

#[derive(Default)]
struct Cache {
    entries: HashMap<String, Entry>,
    order: VecDeque<String>,
    size: usize,
}

const MAX_BYTES: usize = 80 * 1024 * 1024;

static CACHE: LazyLock<Mutex<Cache>> = LazyLock::new(|| Mutex::new(Cache::default()));

impl Cache {
    fn get(&self, key: &str) -> Option<(String, Arc<Vec<u8>>)> {
        self.entries.get(key).map(|e| (e.mime.clone(), e.bytes.clone()))
    }

    fn insert(&mut self, key: String, mime: String, bytes: Arc<Vec<u8>>) {
        if self.entries.contains_key(&key) {
            return;
        }
        self.size += bytes.len();
        self.order.push_back(key.clone());
        self.entries.insert(key, Entry { mime, bytes });
        while self.size > MAX_BYTES {
            let Some(oldest) = self.order.pop_front() else { break };
            if let Some(entry) = self.entries.remove(&oldest) {
                self.size -= entry.bytes.len();
            }
        }
    }
}

fn decode(input: &str) -> String {
    let bytes = input.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'%' && i + 2 < bytes.len() {
            if let Some(value) = std::str::from_utf8(&bytes[i + 1..i + 3]).ok().and_then(|h| u8::from_str_radix(h, 16).ok()) {
                out.push(value);
                i += 3;
                continue;
            }
        }
        out.push(bytes[i]);
        i += 1;
    }
    String::from_utf8_lossy(&out).to_string()
}

fn referer(url: &str) -> Option<&'static str> {
    let host = url::Url::parse(url).ok()?.host_str()?.to_string();
    if host.contains("cdninstagram") || host.contains("fbcdn") || host.contains("instagram") {
        Some("https://www.instagram.com/")
    } else if host.contains("tiktok") {
        Some("https://www.tiktok.com/")
    } else {
        None
    }
}

fn respond(responder: UriSchemeResponder, status: StatusCode, mime: &str, bytes: Vec<u8>) {
    let response = Response::builder()
        .status(status)
        .header(header::CONTENT_TYPE, mime)
        .header(header::CACHE_CONTROL, "max-age=86400")
        .header(header::ACCESS_CONTROL_ALLOW_ORIGIN, "*")
        .body(bytes)
        .unwrap_or_else(|_| Response::new(Vec::new()));
    responder.respond(response);
}

async fn fetch(target: &str) -> Option<(String, Vec<u8>)> {
    let mut request = http::DOWNLOADER.get(target).header("Accept", "image/avif,image/webp,image/png,image/*;q=0.8,*/*;q=0.5");
    if let Some(referer) = referer(target) {
        request = request.header("Referer", referer);
    }
    let response = request.send().await.ok()?;
    if !response.status().is_success() {
        return None;
    }
    let mime = response
        .headers()
        .get(header::CONTENT_TYPE)
        .and_then(|v| v.to_str().ok())
        .unwrap_or("image/jpeg")
        .to_string();
    let bytes = response.bytes().await.ok()?;
    Some((mime, bytes.to_vec()))
}

pub fn handle<R: Runtime>(_ctx: UriSchemeContext<'_, R>, request: Request<Vec<u8>>, responder: UriSchemeResponder) {
    let target = decode(request.uri().path().trim_start_matches('/'));
    if !(target.starts_with("https://") || target.starts_with("http://")) {
        respond(responder, StatusCode::BAD_REQUEST, "text/plain", Vec::new());
        return;
    }
    if let Some((mime, bytes)) = CACHE.lock().unwrap().get(&target) {
        respond(responder, StatusCode::OK, &mime, bytes.to_vec());
        return;
    }
    tauri::async_runtime::spawn(async move {
        match fetch(&target).await {
            Some((mime, bytes)) => {
                CACHE.lock().unwrap().insert(target, mime.clone(), Arc::new(bytes.clone()));
                respond(responder, StatusCode::OK, &mime, bytes);
            }
            None => respond(responder, StatusCode::NOT_FOUND, "text/plain", Vec::new()),
        }
    });
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn decodes_components() {
        assert_eq!(decode("https%3A%2F%2Fi.ytimg.com%2Fvi%2Fx%2Fhq.jpg%3Fa%3D1%26b%3D2"), "https://i.ytimg.com/vi/x/hq.jpg?a=1&b=2");
        assert_eq!(decode("abc%2"), "abc%2");
    }
}
