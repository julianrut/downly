use std::collections::HashMap;
use std::sync::{LazyLock, Mutex};
use std::time::{Duration, Instant};

use super::error::{DownlyError, Result};
use super::models::CookieBrowser;
use super::process;
use super::tools::ToolPaths;

#[derive(Debug, Clone)]
pub struct Cookie {
    pub domain: String,
    pub name: String,
    pub value: String,
}

#[derive(Debug, Clone)]
pub struct CookieSnapshot {
    pub cookies: Vec<Cookie>,
    pub taken: Instant,
}

impl CookieSnapshot {
    pub fn for_domain(&self, domain: &str) -> Vec<&Cookie> {
        self.cookies
            .iter()
            .filter(|c| {
                let d = c.domain.trim_start_matches('.');
                d == domain || d.ends_with(&format!(".{domain}")) || domain.ends_with(&format!(".{d}"))
            })
            .collect()
    }

    pub fn value(&self, name: &str, domain: &str) -> Option<String> {
        self.for_domain(domain).into_iter().find(|c| c.name == name).map(|c| c.value.clone())
    }

    pub fn header(&self, domain: &str) -> String {
        let mut seen = std::collections::HashSet::new();
        let mut parts = Vec::new();
        for cookie in self.for_domain(domain) {
            if seen.insert(cookie.name.clone()) {
                parts.push(format!("{}={}", cookie.name, cookie.value));
            }
        }
        parts.join("; ")
    }
}

static CACHE: LazyLock<Mutex<HashMap<CookieBrowser, CookieSnapshot>>> = LazyLock::new(|| Mutex::new(HashMap::new()));

pub fn invalidate() {
    CACHE.lock().unwrap().clear();
}

pub fn parse_netscape(text: &str) -> Vec<Cookie> {
    let mut cookies = Vec::new();
    for raw in text.lines() {
        let mut line = raw;
        if let Some(rest) = line.strip_prefix("#HttpOnly_") {
            line = rest;
        } else if line.starts_with('#') || line.trim().is_empty() {
            continue;
        }
        let fields: Vec<&str> = line.split('\t').collect();
        if fields.len() < 7 {
            continue;
        }
        cookies.push(Cookie { domain: fields[0].to_string(), name: fields[5].to_string(), value: fields[6].to_string() });
    }
    cookies
}

fn explain(stderr: &str, browser: CookieBrowser) -> DownlyError {
    let lower = stderr.to_lowercase();
    if browser == CookieBrowser::Safari && (lower.contains("operation not permitted") || lower.contains("permission")) {
        return DownlyError::Message("Downly needs Full Disk Access to read Safari’s sign-in. Turn it on in System Settings → Privacy & Security → Full Disk Access, or pick another browser.".into());
    }
    if lower.contains("could not find") || lower.contains("no such file") {
        return DownlyError::Message(format!("Couldn’t find {}’s profile on this Mac.", browser.display_name()));
    }
    if lower.contains("keyring") || lower.contains("keychain") || lower.contains("decrypt") {
        return DownlyError::Message(format!("macOS didn’t allow reading {}’s cookies. Choose “Always Allow” when asked for keychain access.", browser.display_name()));
    }
    let line = stderr.lines().rev().find(|l| l.contains("ERROR")).unwrap_or("").replace("ERROR: ", "");
    if line.is_empty() {
        DownlyError::Message(format!("Couldn’t read cookies from {}.", browser.display_name()))
    } else {
        DownlyError::Message(line)
    }
}

pub async fn snapshot(browser: CookieBrowser, tools: &ToolPaths, force: bool) -> Result<CookieSnapshot> {
    if !force {
        if let Some(cached) = CACHE.lock().unwrap().get(&browser) {
            if cached.taken.elapsed() < Duration::from_secs(20 * 60) {
                return Ok(cached.clone());
            }
        }
    }
    let folder = std::env::temp_dir().join(format!("downly-cookies-{}", uuid::Uuid::new_v4()));
    std::fs::create_dir_all(&folder)?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let _ = std::fs::set_permissions(&folder, std::fs::Permissions::from_mode(0o700));
    }
    let file = folder.join("cookies.txt");
    let args = vec![
        "--ignore-config".to_string(),
        "--no-warnings".to_string(),
        "--cookies-from-browser".to_string(),
        browser.as_str().to_string(),
        "--cookies".to_string(),
        file.to_string_lossy().to_string(),
    ];
    let output = process::run(&tools.ytdlp, &args, None, None).await;
    let text = std::fs::read_to_string(&file).ok();
    let _ = std::fs::remove_dir_all(&folder);
    let stderr = output.as_ref().map(|o| o.stderr.clone()).unwrap_or_default();
    let Some(text) = text else { return Err(explain(&stderr, browser)) };
    let all = parse_netscape(&text);
    if all.is_empty() {
        return Err(explain(&stderr, browser));
    }
    let kept: Vec<Cookie> = all
        .into_iter()
        .filter(|c| c.domain.ends_with("instagram.com") || c.domain.ends_with("tiktok.com"))
        .collect();
    let snapshot = CookieSnapshot { cookies: kept, taken: Instant::now() };
    CACHE.lock().unwrap().insert(browser, snapshot.clone());
    Ok(snapshot)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_cookie_file() {
        let text = "# Netscape HTTP Cookie File\n.instagram.com\tTRUE\t/\tTRUE\t2000000000\tsessionid\tabc\n#HttpOnly_.instagram.com\tTRUE\t/\tTRUE\t2000000000\tcsrftoken\txyz\n";
        let snapshot = CookieSnapshot { cookies: parse_netscape(text), taken: Instant::now() };
        assert_eq!(snapshot.cookies.len(), 2);
        assert_eq!(snapshot.value("csrftoken", "instagram.com").as_deref(), Some("xyz"));
        assert!(snapshot.header("instagram.com").contains("sessionid=abc"));
    }
}
