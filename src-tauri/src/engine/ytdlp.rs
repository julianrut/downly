use serde_json::Value;
use std::sync::{Arc, Mutex};
use tokio_util::sync::CancellationToken;

use super::error::{DownlyError, Result};
use super::json;
use super::link::Platform;
use super::models::CookieBrowser;
use super::paths;
use super::process::{self, Channel};
use super::tools::ToolPaths;

#[derive(Debug, Clone)]
pub struct Progress {
    pub status: String,
    pub downloaded: Option<i64>,
    pub total: Option<i64>,
    pub speed: Option<f64>,
    pub eta: Option<f64>,
    pub format_id: Option<String>,
    pub fragment_index: Option<i64>,
    pub fragment_count: Option<i64>,
}

#[derive(Debug, Clone)]
pub enum Event {
    Progress(Progress),
    Postprocess { name: String, status: String },
    File(String),
    Log(String),
}

const PROGRESS_TEMPLATE: &str = "download:DLYP|%(progress.status)s|%(progress.downloaded_bytes)s|%(progress.total_bytes)s|%(progress.total_bytes_estimate)s|%(progress.speed)s|%(progress.eta)s|%(info.format_id)s|%(progress.fragment_index)s|%(progress.fragment_count)s";
const POSTPROCESS_TEMPLATE: &str = "postprocess:DLYPP|%(progress.status)s|%(progress.postprocessor)s";

#[derive(Clone)]
pub struct Ytdlp {
    pub tools: ToolPaths,
    pub cookie_browser: Option<CookieBrowser>,
}

impl Ytdlp {
    pub fn new(tools: ToolPaths, cookie_browser: Option<CookieBrowser>) -> Self {
        Ytdlp { tools, cookie_browser }
    }

    fn base_args(&self, use_cookies: bool) -> Vec<String> {
        let mut args = process::strings(&[
            "--ignore-config",
            "--no-color",
            "--no-warnings",
            "--socket-timeout",
            "30",
            "--retries",
            "5",
            "--fragment-retries",
            "10",
            "--extractor-retries",
            "3",
        ]);
        args.push("--ffmpeg-location".into());
        args.push(self.tools.ffmpeg_dir().to_string_lossy().to_string());
        args.push("--js-runtimes".into());
        args.push(format!("deno:{}", self.tools.deno.to_string_lossy()));
        args.push("--cache-dir".into());
        args.push(paths::ytdlp_cache().to_string_lossy().to_string());
        if use_cookies {
            if let Some(browser) = self.cookie_browser {
                args.push("--cookies-from-browser".into());
                args.push(browser.as_str().into());
            }
        }
        args
    }

    pub async fn extract(&self, url: &str, playlist: bool, use_cookies: bool, extra: &[String], cancel: Option<&CancellationToken>) -> Result<Value> {
        let mut args = self.base_args(use_cookies);
        args.extend(process::strings(&["-J", "--skip-download"]));
        if playlist {
            args.extend(process::strings(&["--yes-playlist", "--flat-playlist", "--playlist-end", "1000"]));
        } else {
            args.push("--no-playlist".into());
        }
        args.extend(extra.iter().cloned());
        args.push(url.to_string());
        let output = process::run(&self.tools.ytdlp, &args, cancel, None).await?;
        let value = json::parse(&output.stdout);
        if json::exists(&value["id"]) || json::exists(&value["entries"]) || json::exists(&value["title"]) {
            return Ok(value);
        }
        Err(interpret_error(&output.stderr, output.status))
    }

    pub async fn run(
        &self,
        arguments: Vec<String>,
        url: &str,
        use_cookies: bool,
        cancel: &CancellationToken,
        on_event: &(dyn Fn(Event) + Send + Sync),
    ) -> Result<Vec<String>> {
        let mut args = self.base_args(use_cookies);
        args.extend(process::strings(&["--newline", "--progress", "--progress-template", PROGRESS_TEMPLATE, "--progress-template", POSTPROCESS_TEMPLATE, "--print", "after_move:DLYF|%(filepath)s", "--no-mtime", "--concurrent-fragments", "4"]));
        args.extend(arguments);
        args.push(url.to_string());
        let files: Arc<Mutex<Vec<String>>> = Arc::new(Mutex::new(Vec::new()));
        let collector = files.clone();
        let handler = move |line: &str, _channel: Channel| {
            if let Some(event) = parse_line(line) {
                if let Event::File(path) = &event {
                    let mut list = collector.lock().unwrap();
                    if !list.contains(path) {
                        list.push(path.clone());
                    }
                }
                on_event(event);
            }
        };
        let output = process::run(&self.tools.ytdlp, &args, Some(cancel), Some(&handler)).await?;
        let produced: Vec<String> = files.lock().unwrap().iter().filter(|p| std::path::Path::new(p).exists()).cloned().collect();
        if !produced.is_empty() && (output.ok() || !output.stderr.contains("ERROR:")) {
            return Ok(produced);
        }
        Err(interpret_error(&output.stderr, output.status))
    }
}

pub fn parse_line(line: &str) -> Option<Event> {
    if let Some(rest) = line.strip_prefix("DLYP|") {
        let parts: Vec<&str> = rest.split('|').collect();
        if parts.len() < 9 {
            return None;
        }
        let int = |v: &str| v.parse::<i64>().ok().or_else(|| v.parse::<f64>().ok().map(|f| f as i64));
        return Some(Event::Progress(Progress {
            status: parts[0].to_string(),
            downloaded: int(parts[1]),
            total: int(parts[2]).or_else(|| int(parts[3])),
            speed: parts[4].parse().ok(),
            eta: parts[5].parse().ok(),
            format_id: if parts[6] == "NA" { None } else { Some(parts[6].to_string()) },
            fragment_index: int(parts[7]),
            fragment_count: int(parts[8]),
        }));
    }
    if let Some(rest) = line.strip_prefix("DLYPP|") {
        let parts: Vec<&str> = rest.split('|').collect();
        if parts.len() < 2 {
            return None;
        }
        return Some(Event::Postprocess { status: parts[0].to_string(), name: parts[1].to_string() });
    }
    if let Some(path) = line.strip_prefix("DLYF|") {
        return Some(Event::File(path.to_string()));
    }
    Some(Event::Log(line.to_string()))
}

pub fn interpret_error(stderr: &str, status: i32) -> DownlyError {
    let lines: Vec<&str> = stderr.lines().collect();
    let error_line = lines
        .iter()
        .rev()
        .find(|l| l.starts_with("ERROR:"))
        .or_else(|| lines.iter().rev().find(|l| l.contains("ERROR")))
        .copied()
        .unwrap_or("");
    let mut message = error_line.replacen("ERROR: ", "", 1);
    if let Ok(regex) = regex::Regex::new(r"^\[[^\]]+\] [^:]+: ") {
        message = regex.replace(&message, "").to_string();
    }
    let lower = stderr.to_lowercase();
    if lower.contains("sign in to confirm") && lower.contains("bot") || lower.contains("not a bot") {
        return DownlyError::BotCheck;
    }
    if lower.contains("instagram") && (lower.contains("login") || lower.contains("log in") || lower.contains("rate-limit") || lower.contains("cookies")) {
        return DownlyError::NeedsLogin(Platform::Instagram, "Instagram wants you to be signed in to view this.".into());
    }
    if lower.contains("private video") || lower.contains("this video is private") {
        return DownlyError::Unavailable("This video is private.".into());
    }
    if lower.contains("sign in to confirm your age") || lower.contains("age-restricted") || lower.contains("inappropriate for some users") {
        return DownlyError::NeedsLogin(Platform::Youtube, "This video is age-restricted.".into());
    }
    if lower.contains("members-only") || lower.contains("join this channel") {
        return DownlyError::Unavailable("This video is for channel members only.".into());
    }
    if lower.contains("unsupported url") {
        return DownlyError::UnsupportedLink;
    }
    if lower.contains("drm") {
        return DownlyError::Unavailable("This content is DRM-protected and can’t be downloaded.".into());
    }
    if lower.contains("requested format is not available") {
        return DownlyError::Unavailable("That quality isn’t available anymore. Try another one.".into());
    }
    if lower.contains("video unavailable") || lower.contains("has been removed") || lower.contains("not available") || lower.contains("http error 404") {
        return DownlyError::Unavailable(if message.is_empty() { "This content isn’t available.".into() } else { message });
    }
    if lower.contains("unable to download webpage") || lower.contains("timed out") || lower.contains("network is unreachable") || lower.contains("nodename nor servname") || lower.contains("connection reset") {
        return DownlyError::Network("Couldn’t connect. Check your internet connection.".into());
    }
    if message.is_empty() {
        let tail = lines.iter().rev().take(2).rev().cloned().collect::<Vec<_>>().join(" ");
        return DownlyError::ToolFailed(if tail.trim().is_empty() { format!("The download engine stopped unexpectedly (code {status}).") } else { tail });
    }
    DownlyError::Message(message)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_progress() {
        match parse_line("DLYP|downloading|1048576|10485760|NA|524288.5|17|137|NA|NA") {
            Some(Event::Progress(p)) => {
                assert_eq!(p.downloaded, Some(1_048_576));
                assert_eq!(p.total, Some(10_485_760));
                assert_eq!(p.format_id.as_deref(), Some("137"));
                assert_eq!(p.eta, Some(17.0));
            }
            _ => panic!("no progress"),
        }
        assert!(matches!(parse_line("DLYF|/tmp/a b.mp4"), Some(Event::File(p)) if p == "/tmp/a b.mp4"));
    }

    #[test]
    fn interprets_errors() {
        assert_eq!(interpret_error("ERROR: [youtube] abc: Sign in to confirm you’re not a bot.", 1), DownlyError::BotCheck);
        assert_eq!(interpret_error("ERROR: [generic] Unsupported URL: https://x.y", 1), DownlyError::UnsupportedLink);
        assert_eq!(interpret_error("ERROR: [youtube] abc: Private video. Sign in", 1), DownlyError::Unavailable("This video is private.".into()));
    }
}
