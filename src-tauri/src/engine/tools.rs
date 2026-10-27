use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};
use std::time::{SystemTime, UNIX_EPOCH};
use tokio_util::sync::CancellationToken;

use super::error::{DownlyError, Result};
use super::http;
use super::paths;
use super::process;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ToolId {
    Ytdlp,
    Ffmpeg,
    Ffprobe,
    Deno,
}

impl ToolId {
    pub const ALL: [ToolId; 4] = [ToolId::Ytdlp, ToolId::Ffmpeg, ToolId::Ffprobe, ToolId::Deno];

    pub fn key(&self) -> &'static str {
        match self {
            ToolId::Ytdlp => "ytdlp",
            ToolId::Ffmpeg => "ffmpeg",
            ToolId::Ffprobe => "ffprobe",
            ToolId::Deno => "deno",
        }
    }

    pub fn display_name(&self) -> &'static str {
        match self {
            ToolId::Ytdlp => "yt-dlp",
            ToolId::Ffmpeg => "FFmpeg",
            ToolId::Ffprobe => "FFprobe",
            ToolId::Deno => "Deno",
        }
    }

    fn folder_prefix(&self) -> &'static str {
        match self {
            ToolId::Ytdlp => "yt-dlp",
            ToolId::Ffmpeg => "ffmpeg",
            ToolId::Ffprobe => "ffprobe",
            ToolId::Deno => "deno",
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(tag = "state", rename_all = "camelCase")]
pub enum ToolPhase {
    Waiting,
    Downloading { fraction: f64 },
    Installing,
    Ready { version: String },
    Failed { message: String },
}

#[derive(Debug, Clone)]
pub struct ToolPaths {
    pub ytdlp: PathBuf,
    pub ffmpeg: PathBuf,
    pub ffprobe: PathBuf,
    pub deno: PathBuf,
}

impl ToolPaths {
    pub fn ffmpeg_dir(&self) -> PathBuf {
        self.ffmpeg.parent().map(|p| p.to_path_buf()).unwrap_or_default()
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
struct Entry {
    path: String,
    version: String,
    source: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
struct Manifest {
    tools: HashMap<String, Entry>,
    last_ytdlp_check: Option<u64>,
}

pub type PhaseHandler = Arc<dyn Fn(ToolId, ToolPhase) + Send + Sync>;

pub struct Toolchain {
    root: PathBuf,
    manifest: Mutex<Manifest>,
}

#[derive(Clone, Copy)]
enum Archive {
    Raw,
    Zip,
}

fn now() -> u64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_secs()).unwrap_or(0)
}

pub fn is_apple_silicon() -> bool {
    #[cfg(target_os = "macos")]
    {
        let mut value: i32 = 0;
        let mut size = std::mem::size_of::<i32>();
        let name = std::ffi::CString::new("hw.optional.arm64").unwrap();
        let result = unsafe { libc::sysctlbyname(name.as_ptr(), &mut value as *mut i32 as *mut libc::c_void, &mut size, std::ptr::null_mut(), 0) };
        if result == 0 {
            return value == 1;
        }
    }
    cfg!(target_arch = "aarch64")
}

impl Toolchain {
    pub fn new(root: PathBuf) -> Self {
        let manifest = std::fs::read(root.join("manifest.json"))
            .ok()
            .and_then(|data| serde_json::from_slice(&data).ok())
            .unwrap_or_default();
        Toolchain { root, manifest: Mutex::new(manifest) }
    }

    pub fn shared() -> Self {
        Self::new(paths::tools_dir())
    }

    fn resolve(&self, tool: ToolId) -> Option<PathBuf> {
        let manifest = self.manifest.lock().unwrap();
        let entry = manifest.tools.get(tool.key())?;
        let path = if entry.path.starts_with('/') { PathBuf::from(&entry.path) } else { self.root.join(&entry.path) };
        if is_executable(&path) {
            Some(path)
        } else {
            None
        }
    }

    pub fn paths(&self) -> Option<ToolPaths> {
        Some(ToolPaths {
            ytdlp: self.resolve(ToolId::Ytdlp)?,
            ffmpeg: self.resolve(ToolId::Ffmpeg)?,
            ffprobe: self.resolve(ToolId::Ffprobe)?,
            deno: self.resolve(ToolId::Deno)?,
        })
    }

    pub fn versions(&self) -> HashMap<String, String> {
        let mut output = HashMap::new();
        for tool in ToolId::ALL {
            if self.resolve(tool).is_some() {
                if let Some(entry) = self.manifest.lock().unwrap().tools.get(tool.key()) {
                    output.insert(tool.key().to_string(), entry.version.clone());
                }
            }
        }
        output
    }

    pub fn missing(&self) -> Vec<ToolId> {
        ToolId::ALL.iter().copied().filter(|t| self.resolve(*t).is_none()).collect()
    }

    fn save(&self) {
        let manifest = self.manifest.lock().unwrap().clone();
        if let Ok(data) = serde_json::to_vec_pretty(&manifest) {
            let _ = std::fs::write(self.root.join("manifest.json"), data);
        }
    }

    fn record(&self, tool: ToolId, path: &Path, version: &str, source: &str) {
        let root = self.root.to_string_lossy().to_string() + "/";
        let full = path.to_string_lossy().to_string();
        let relative = full.strip_prefix(&root).map(|s| s.to_string()).unwrap_or(full);
        self.manifest.lock().unwrap().tools.insert(
            tool.key().to_string(),
            Entry { path: relative, version: version.to_string(), source: source.to_string() },
        );
        self.save();
    }

    pub async fn install(&self, tools: Vec<ToolId>, handler: PhaseHandler) -> Result<ToolPaths> {
        std::fs::create_dir_all(&self.root)?;
        let mut tasks = Vec::new();
        for tool in tools.iter().copied() {
            handler(tool, ToolPhase::Waiting);
            let root = self.root.clone();
            let handler = handler.clone();
            tasks.push(tokio::spawn(async move {
                let progress = {
                    let handler = handler.clone();
                    move |fraction: f64| handler(tool, ToolPhase::Downloading { fraction })
                };
                let phase = {
                    let handler = handler.clone();
                    move |phase: ToolPhase| handler(tool, phase)
                };
                (tool, install_tool(tool, &root, &progress, &phase).await)
            }));
        }
        let mut failures = Vec::new();
        for task in tasks {
            let Ok((tool, result)) = task.await else { continue };
            match result {
                Ok((path, version, source)) => {
                    self.record(tool, &path, &version, &source);
                    handler(tool, ToolPhase::Ready { version });
                }
                Err(error) => {
                    let fallback = system_fallback(tool);
                    let mut recovered = false;
                    if let Some(path) = fallback {
                        if let Ok(version) = verify(tool, &path).await {
                            self.record(tool, &path, &version, "system");
                            handler(tool, ToolPhase::Ready { version });
                            recovered = true;
                        }
                    }
                    if !recovered {
                        failures.push(format!("{}: {}", tool.display_name(), error));
                        handler(tool, ToolPhase::Failed { message: error.to_string() });
                    }
                }
            }
        }
        if !failures.is_empty() {
            return Err(DownlyError::ToolFailed(failures.join("\n")));
        }
        self.cleanup();
        self.paths().ok_or_else(|| DownlyError::ToolMissing("Download engine".into()))
    }

    pub async fn latest_ytdlp_version(&self) -> Option<String> {
        for url in [
            "https://github.com/yt-dlp/yt-dlp/releases/latest",
            "https://github.com/yt-dlp/yt-dlp/releases/latest/download/SHA2-256SUMS",
        ] {
            if let Some(version) = http::redirect_target(url).await.as_deref().and_then(release_tag) {
                return Some(version);
            }
        }
        None
    }

    pub async fn update_ytdlp(&self, force: bool) -> Option<String> {
        let last = self.manifest.lock().unwrap().last_ytdlp_check;
        if !force {
            if let Some(last) = last {
                if now().saturating_sub(last) < 20 * 3600 {
                    return None;
                }
            }
        }
        let latest = self.latest_ytdlp_version().await?;
        self.manifest.lock().unwrap().last_ytdlp_check = Some(now());
        self.save();
        let current = self.manifest.lock().unwrap().tools.get("ytdlp").map(|e| e.version.clone()).unwrap_or_default();
        if self.resolve(ToolId::Ytdlp).is_some() && !version_less(&current, &latest) {
            return None;
        }
        let noop_progress = |_: f64| {};
        let noop_phase = |_: ToolPhase| {};
        match install_tool(ToolId::Ytdlp, &self.root, &noop_progress, &noop_phase).await {
            Ok((path, version, source)) => {
                self.record(ToolId::Ytdlp, &path, &version, &source);
                self.cleanup();
                Some(version)
            }
            Err(_) => None,
        }
    }

    fn cleanup(&self) {
        let in_use: Vec<String> = self
            .manifest
            .lock()
            .unwrap()
            .tools
            .values()
            .map(|e| e.path.split('/').next().unwrap_or("").to_string())
            .collect();
        let Ok(entries) = std::fs::read_dir(&self.root) else { return };
        for entry in entries.flatten() {
            let name = entry.file_name().to_string_lossy().to_string();
            if name == "manifest.json" || in_use.contains(&name) {
                continue;
            }
            let prefixed = ToolId::ALL.iter().any(|t| name.starts_with(&format!("{}-", t.folder_prefix())));
            if prefixed || name.ends_with(".partial") {
                let _ = std::fs::remove_dir_all(entry.path());
            }
        }
    }
}

fn release_tag(url: &str) -> Option<String> {
    let parts: Vec<&str> = url.split('?').next()?.split('/').collect();
    let index = parts.iter().position(|p| *p == "tag" || *p == "download")?;
    let tag = parts.get(index + 1)?;
    if tag.chars().next().map(|c| c.is_ascii_digit()).unwrap_or(false) {
        Some(tag.to_string())
    } else {
        None
    }
}

fn version_less(current: &str, latest: &str) -> bool {
    let parse = |v: &str| v.split('.').map(|p| p.parse::<u64>().unwrap_or(0)).collect::<Vec<_>>();
    parse(current) < parse(latest)
}

pub fn is_executable(path: &Path) -> bool {
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        std::fs::metadata(path).map(|m| m.is_file() && m.permissions().mode() & 0o111 != 0).unwrap_or(false)
    }
    #[cfg(not(unix))]
    {
        path.is_file()
    }
}

fn system_fallback(tool: ToolId) -> Option<PathBuf> {
    let name = match tool {
        ToolId::Ytdlp => "yt-dlp",
        ToolId::Ffmpeg => "ffmpeg",
        ToolId::Ffprobe => "ffprobe",
        ToolId::Deno => "deno",
    };
    ["/opt/homebrew/bin", "/usr/local/bin"]
        .iter()
        .map(|dir| Path::new(dir).join(name))
        .find(|p| is_executable(p))
}

fn sources(tool: ToolId) -> Vec<(String, Archive, &'static str)> {
    let arm = is_apple_silicon();
    let mac = cfg!(target_os = "macos");
    match tool {
        ToolId::Ytdlp => {
            if mac {
                vec![
                    ("https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos.zip".into(), Archive::Zip, "yt-dlp_macos"),
                    ("https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos".into(), Archive::Raw, "yt-dlp_macos"),
                ]
            } else {
                vec![(
                    format!("https://github.com/yt-dlp/yt-dlp/releases/latest/download/{}", if arm { "yt-dlp_linux_aarch64" } else { "yt-dlp_linux" }),
                    Archive::Raw,
                    "yt-dlp",
                )]
            }
        }
        ToolId::Ffmpeg | ToolId::Ffprobe => {
            let name = if tool == ToolId::Ffmpeg { "ffmpeg" } else { "ffprobe" };
            if mac {
                vec![
                    (
                        format!("https://github.com/shaka-project/static-ffmpeg-binaries/releases/latest/download/{name}-osx-{}", if arm { "arm64" } else { "x64" }),
                        Archive::Raw,
                        name,
                    ),
                    (
                        format!("https://ffmpeg.martin-riedl.de/redirect/latest/macos/{}/release/{name}.zip", if arm { "arm64" } else { "amd64" }),
                        Archive::Zip,
                        name,
                    ),
                ]
            } else {
                vec![(
                    format!("https://github.com/shaka-project/static-ffmpeg-binaries/releases/latest/download/{name}-linux-{}", if arm { "arm64" } else { "x64" }),
                    Archive::Raw,
                    name,
                )]
            }
        }
        ToolId::Deno => {
            let triple = if mac {
                if arm { "aarch64-apple-darwin" } else { "x86_64-apple-darwin" }
            } else if arm {
                "aarch64-unknown-linux-gnu"
            } else {
                "x86_64-unknown-linux-gnu"
            };
            vec![
                (format!("https://github.com/denoland/deno/releases/latest/download/deno-{triple}.zip"), Archive::Zip, "deno"),
                (format!("https://dl.deno.land/release/v2.5.6/deno-{triple}.zip"), Archive::Zip, "deno"),
            ]
        }
    }
}

async fn unzip(archive: &Path, destination: &Path) -> Result<()> {
    std::fs::create_dir_all(destination)?;
    let output = if cfg!(target_os = "macos") {
        process::run(Path::new("/usr/bin/ditto"), &[ "-x".into(), "-k".into(), archive.to_string_lossy().to_string(), destination.to_string_lossy().to_string()], None, None).await?
    } else {
        process::run(Path::new("/usr/bin/unzip"), &["-q".into(), "-o".into(), archive.to_string_lossy().to_string(), "-d".into(), destination.to_string_lossy().to_string()], None, None).await?
    };
    if output.ok() {
        Ok(())
    } else {
        Err(DownlyError::ToolFailed("Couldn’t unpack the download.".into()))
    }
}

fn find_named(directory: &Path, name: &str) -> Option<PathBuf> {
    let direct = directory.join(name);
    if direct.is_file() {
        return Some(direct);
    }
    let mut best: Option<PathBuf> = None;
    let mut stack = vec![directory.to_path_buf()];
    while let Some(dir) = stack.pop() {
        let Ok(entries) = std::fs::read_dir(&dir) else { continue };
        for entry in entries.flatten() {
            let path = entry.path();
            if path.is_dir() {
                stack.push(path);
            } else if path.file_name().map(|n| n == name).unwrap_or(false) {
                let depth = path.components().count();
                if best.as_ref().map(|b| depth < b.components().count()).unwrap_or(true) {
                    best = Some(path);
                }
            }
        }
    }
    best
}

fn make_executable(path: &Path) {
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let _ = std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o755));
    }
}

async fn install_tool(
    tool: ToolId,
    root: &Path,
    progress: &(dyn Fn(f64) + Send + Sync),
    phase: &(dyn Fn(ToolPhase) + Send + Sync),
) -> Result<(PathBuf, String, String)> {
    let mut last_error = DownlyError::ToolMissing(tool.display_name().into());
    for (url, archive, binary) in sources(tool) {
        let stamp = SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_millis()).unwrap_or(0);
        let folder = format!("{}-{}", tool.folder_prefix(), stamp);
        let work = root.join(format!("{folder}.partial"));
        let final_dir = root.join(&folder);
        let _ = std::fs::remove_dir_all(&work);
        let attempt = async {
            std::fs::create_dir_all(&work)?;
            let target = work.join(match archive {
                Archive::Zip => "archive.zip",
                Archive::Raw => binary,
            });
            let cancel = CancellationToken::new();
            let report = |received: u64, total: Option<u64>| {
                if let Some(total) = total.filter(|t| *t > 0) {
                    progress((received as f64 / total as f64).min(1.0));
                }
            };
            http::download_file(&url, &target, http::headers(&[]), &cancel, &report).await?;
            phase(ToolPhase::Installing);
            let executable = match archive {
                Archive::Zip => {
                    let extracted = work.join("contents");
                    unzip(&target, &extracted).await?;
                    let _ = std::fs::remove_file(&target);
                    find_named(&extracted, binary).ok_or_else(|| DownlyError::ToolFailed(format!("{} archive looked different than expected.", tool.display_name())))?
                }
                Archive::Raw => target,
            };
            make_executable(&executable);
            if cfg!(target_os = "macos") {
                let _ = process::run(Path::new("/usr/bin/xattr"), &["-dr".into(), "com.apple.quarantine".into(), work.to_string_lossy().to_string()], None, None).await;
            }
            let version = match verify(tool, &executable).await {
                Ok(version) => version,
                Err(_) if cfg!(target_os = "macos") => {
                    let _ = process::run(Path::new("/usr/bin/codesign"), &["--force".into(), "--deep".into(), "--sign".into(), "-".into(), executable.to_string_lossy().to_string()], None, None).await;
                    verify(tool, &executable).await?
                }
                Err(error) => return Err(error),
            };
            let _ = std::fs::remove_dir_all(&final_dir);
            std::fs::rename(&work, &final_dir)?;
            let relative = executable.strip_prefix(&work).map(|p| p.to_path_buf()).unwrap_or_else(|_| PathBuf::from(binary));
            let host = url::Url::parse(&url).ok().and_then(|u| u.host_str().map(|h| h.to_string())).unwrap_or_default();
            Ok::<_, DownlyError>((final_dir.join(relative), version, host))
        };
        match attempt.await {
            Ok(result) => return Ok(result),
            Err(error) => {
                let _ = std::fs::remove_dir_all(&work);
                last_error = error;
            }
        }
    }
    Err(last_error)
}

pub async fn verify(tool: ToolId, path: &Path) -> Result<String> {
    let args: Vec<String> = match tool {
        ToolId::Ytdlp => vec!["--version".into()],
        ToolId::Ffmpeg | ToolId::Ffprobe => vec!["-hide_banner".into(), "-version".into()],
        ToolId::Deno => vec!["--version".into()],
    };
    let output = process::run_timeout(path, &args, 120).await?;
    if !output.ok() {
        let detail = output.stderr.lines().last().unwrap_or("").to_string();
        return Err(DownlyError::ToolFailed(format!("{} didn’t start ({detail}).", tool.display_name())));
    }
    let first = output.stdout.lines().next().unwrap_or("").trim().to_string();
    Ok(match tool {
        ToolId::Ytdlp => first,
        ToolId::Ffmpeg | ToolId::Ffprobe => {
            let parts: Vec<&str> = first.split_whitespace().collect();
            parts.iter().position(|p| *p == "version").and_then(|i| parts.get(i + 1)).map(|s| s.to_string()).unwrap_or(first)
        }
        ToolId::Deno => first.split_whitespace().nth(1).map(|s| s.to_string()).unwrap_or(first),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn release_tags() {
        assert_eq!(release_tag("https://github.com/yt-dlp/yt-dlp/releases/tag/2026.10.26").as_deref(), Some("2026.10.26"));
        assert_eq!(release_tag("https://github.com/yt-dlp/yt-dlp/releases/download/2026.10.26/SHA2-256SUMS").as_deref(), Some("2026.10.26"));
        assert_eq!(release_tag("https://github.com/yt-dlp/yt-dlp/releases"), None);
    }

    #[test]
    fn versions_compare() {
        assert!(version_less("2025.12.01", "2026.10.26"));
        assert!(!version_less("2026.10.26", "2026.10.26"));
        assert!(version_less("2026.9.30", "2026.10.1"));
    }
}
