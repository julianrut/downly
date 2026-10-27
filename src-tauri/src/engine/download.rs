use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::Mutex;
use std::time::{Duration, Instant};
use tokio_util::sync::CancellationToken;

use super::error::{DownlyError, Result};
use super::http;
use super::link::Platform;
use super::media::{self, Tags};
use super::models::{AudioFormat, EngineSettings, FilenameStyle, GalleryItem, GalleryKind, SpotifyTrack, VideoContainer};
use super::paths;
use super::spotify;
use super::tools::ToolPaths;
use super::ytdlp::{Event, Progress, Ytdlp};
use super::ytmusic;

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "camelCase")]
pub enum JobKind {
    #[serde(rename_all = "camelCase")]
    Video {
        url: String,
        selector: String,
        sort: Option<String>,
        container: VideoContainer,
        apple_compatible: bool,
        #[serde(default)]
        expected_sizes: HashMap<String, i64>,
    },
    #[serde(rename_all = "camelCase")]
    Audio { url: String, format: AudioFormat, square_cover: bool },
    #[serde(rename_all = "camelCase")]
    Spotify { track: SpotifyTrack, format: AudioFormat, folder: Option<String> },
    #[serde(rename_all = "camelCase")]
    Gallery { items: Vec<GalleryItem>, folder: Option<String> },
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DownloadJob {
    #[serde(default = "new_id")]
    pub id: String,
    pub title: String,
    pub subtitle: String,
    pub detail: String,
    pub thumbnail: Option<String>,
    pub platform: Platform,
    pub kind: JobKind,
}

fn new_id() -> String {
    uuid::Uuid::new_v4().to_string()
}

impl DownloadJob {
    pub fn is_audio(&self) -> bool {
        match &self.kind {
            JobKind::Audio { .. } | JobKind::Spotify { .. } => true,
            JobKind::Video { .. } => false,
            JobKind::Gallery { items, .. } => items.iter().all(|i| i.kind == GalleryKind::Audio),
        }
    }

    pub fn source_url(&self) -> Option<String> {
        match &self.kind {
            JobKind::Video { url, .. } | JobKind::Audio { url, .. } => Some(url.clone()),
            JobKind::Spotify { track, .. } => Some(format!("https://open.spotify.com/track/{}", track.id)),
            JobKind::Gallery { items, .. } => items.iter().find_map(|i| i.ytdlp_url.clone()),
        }
    }
}

#[derive(Debug, Clone, Serialize, PartialEq)]
#[serde(tag = "kind", rename_all = "camelCase")]
pub enum Phase {
    Preparing { message: String },
    Downloading,
    Processing { message: String },
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct JobProgress {
    pub phase: Phase,
    pub fraction: Option<f64>,
    pub speed: Option<f64>,
    pub eta: Option<f64>,
    pub downloaded: Option<i64>,
    pub total: Option<i64>,
    pub note: Option<String>,
}

impl JobProgress {
    pub fn phase(phase: Phase) -> Self {
        JobProgress { phase, fraction: None, speed: None, eta: None, downloaded: None, total: None, note: None }
    }

    fn preparing(message: &str) -> Self {
        Self::phase(Phase::Preparing { message: message.to_string() })
    }

    fn processing(message: &str, fraction: Option<f64>) -> Self {
        let mut p = Self::phase(Phase::Processing { message: message.to_string() });
        p.fraction = fraction;
        p
    }
}

#[derive(Debug, Clone)]
pub struct JobOutput {
    pub files: Vec<PathBuf>,
    pub reveal: PathBuf,
    pub note: Option<String>,
}

#[derive(Clone)]
pub struct Context {
    pub tools: ToolPaths,
    pub settings: EngineSettings,
    pub destination: PathBuf,
    pub embed_metadata: bool,
    pub filename_style: FilenameStyle,
}

pub type ProgressFn<'a> = &'a (dyn Fn(JobProgress) + Send + Sync);

struct Aggregator {
    expected: HashMap<String, i64>,
    current: HashMap<String, (i64, Option<i64>)>,
    last: f64,
}

impl Aggregator {
    fn update(&mut self, p: &Progress) -> (Option<f64>, i64, Option<i64>) {
        let key = p.format_id.clone().unwrap_or_else(|| "default".into());
        let previous = self.current.get(&key).cloned();
        let mut downloaded = p.downloaded.or(previous.map(|v| v.0)).unwrap_or(0);
        let mut total = p.total.or(previous.and_then(|v| v.1));
        if p.status == "finished" {
            match total {
                Some(t) => downloaded = downloaded.max(t),
                None => total = Some(downloaded),
            }
        }
        if total.is_none() {
            if let (Some(index), Some(count)) = (p.fragment_index, p.fragment_count) {
                if index > 0 && count > 0 && downloaded > 0 {
                    total = Some((downloaded as f64 / index as f64 * count as f64) as i64);
                }
            }
        }
        self.current.insert(key, (downloaded, total));
        let mut keys: Vec<String> = self.expected.keys().cloned().collect();
        for key in self.current.keys() {
            if !keys.contains(key) {
                keys.push(key.clone());
            }
        }
        let mut sum_done = 0i64;
        let mut sum_total = 0i64;
        let mut unknown = false;
        for key in keys {
            let done = self.current.get(&key).map(|v| v.0).unwrap_or(0);
            let size = self.current.get(&key).and_then(|v| v.1).or(self.expected.get(&key).cloned());
            match size {
                Some(size) if size > 0 => {
                    sum_total += size.max(done);
                    sum_done += done;
                }
                _ => {
                    if self.current.contains_key(&key) {
                        unknown = true;
                    }
                }
            }
        }
        if sum_total <= 0 {
            return (None, sum_done, None);
        }
        let mut fraction = sum_done as f64 / sum_total as f64;
        if unknown {
            fraction *= 0.9;
        }
        fraction = fraction.min(0.999).max(self.last);
        self.last = fraction;
        (Some(fraction), sum_done, Some(sum_total))
    }
}

fn describe_postprocessor(name: &str) -> &'static str {
    match name {
        "Merger" | "FFmpegMerger" => "Merging video and audio",
        "ExtractAudio" | "FFmpegExtractAudio" => "Converting audio",
        "EmbedThumbnail" => "Adding cover art",
        "Metadata" | "FFmpegMetadata" => "Writing details",
        "VideoRemuxer" | "FFmpegVideoRemuxer" | "MoveFiles" | "MoveFilesAfterDownload" => "Finishing up",
        "VideoConvertor" | "FFmpegVideoConvertor" => "Converting video",
        "ThumbnailsConvertor" | "FFmpegThumbnailsConvertor" => "Preparing cover art",
        name if name.starts_with("Fixup") => "Polishing file",
        _ => "Processing",
    }
}

pub struct Engine {
    pub ctx: Context,
}

impl Engine {
    pub fn new(ctx: Context) -> Self {
        Engine { ctx }
    }

    fn ytdlp(&self) -> Ytdlp {
        Ytdlp::new(self.ctx.tools.clone(), self.ctx.settings.cookie_browser)
    }

    fn cookies_for(&self, url: &str) -> bool {
        self.ctx.settings.cookie_browser.is_some() && (self.ctx.settings.always_use_cookies || url.contains("instagram.com"))
    }

    pub async fn run(&self, job: &DownloadJob, cancel: &CancellationToken, progress: ProgressFn<'_>) -> Result<JobOutput> {
        let staging = paths::staging_for(&job.id);
        std::fs::create_dir_all(&self.ctx.destination)?;
        let result = match &job.kind {
            JobKind::Video { url, selector, sort, container, apple_compatible, expected_sizes } => {
                self.video(url, selector, sort.as_deref(), *container, *apple_compatible, expected_sizes.clone(), &staging, cancel, progress).await
            }
            JobKind::Audio { url, format, square_cover } => self.audio(url, *format, *square_cover, &staging, cancel, progress).await,
            JobKind::Spotify { track, format, folder } => self.spotify(track, *format, folder.as_deref(), &staging, cancel, progress).await,
            JobKind::Gallery { items, folder } => self.gallery(items, folder.as_deref(), &staging, cancel, progress).await,
        };
        let _ = std::fs::remove_dir_all(&staging);
        result
    }

    fn output_args(&self, staging: &Path, template: Option<&str>) -> Vec<String> {
        vec![
            "-P".into(),
            staging.to_string_lossy().to_string(),
            "-o".into(),
            template.unwrap_or(self.ctx.filename_style.template()).to_string(),
            "--no-part".into(),
            "--windows-filenames".into(),
        ]
    }

    async fn run_ytdlp(&self, args: Vec<String>, url: &str, expected: HashMap<String, i64>, note: Option<String>, scale: Option<(f64, f64)>, cancel: &CancellationToken, progress: ProgressFn<'_>) -> Result<Vec<String>> {
        let aggregator = Mutex::new(Aggregator { expected, current: HashMap::new(), last: 0.0 });
        let last_emit = Mutex::new(Instant::now() - Duration::from_secs(1));
        let handler = |event: Event| match event {
            Event::Progress(p) => {
                let (fraction, done, total) = aggregator.lock().unwrap().update(&p);
                let mut guard = last_emit.lock().unwrap();
                if guard.elapsed() >= Duration::from_millis(150) || p.status == "finished" {
                    *guard = Instant::now();
                    let scaled = match (fraction, scale) {
                        (Some(f), Some((base, span))) => Some(base + f * span),
                        (f, _) => f,
                    };
                    progress(JobProgress { phase: Phase::Downloading, fraction: scaled, speed: p.speed, eta: p.eta, downloaded: Some(done), total, note: note.clone() });
                }
            }
            Event::Postprocess { name, status } => {
                if status == "started" || status == "processing" {
                    let mut update = JobProgress::processing(describe_postprocessor(&name), None);
                    update.note = note.clone();
                    progress(update);
                }
            }
            _ => {}
        };
        let cookies = self.cookies_for(url);
        match self.ytdlp().run(args.clone(), url, cookies, cancel, &handler).await {
            Err(error) if error.needs_account() && !cookies && self.ctx.settings.cookie_browser.is_some() => self.ytdlp().run(args, url, true, cancel, &handler).await,
            other => other,
        }
    }

    #[allow(clippy::too_many_arguments)]
    async fn video(&self, url: &str, selector: &str, sort: Option<&str>, container: VideoContainer, apple_compatible: bool, expected: HashMap<String, i64>, staging: &Path, cancel: &CancellationToken, progress: ProgressFn<'_>) -> Result<JobOutput> {
        progress(JobProgress::preparing("Starting"));
        let mut args = vec!["-f".to_string(), selector.to_string()];
        if let Some(sort) = sort.filter(|s| !s.is_empty()) {
            args.push("-S".into());
            args.push(sort.into());
        }
        args.extend(["--merge-output-format", container.as_str(), "--remux-video", container.as_str(), "--no-playlist"].iter().map(|s| s.to_string()));
        if self.ctx.embed_metadata {
            args.push("--embed-metadata".into());
        }
        args.extend(self.output_args(staging, None));
        let files = self.run_ytdlp(args, url, expected, None, None, cancel, progress).await?;
        let mut finals = Vec::new();
        for path in files {
            let mut file = PathBuf::from(path);
            if apple_compatible && container == VideoContainer::Mp4 {
                if let Some(info) = media::probe(&self.ctx.tools, &file).await {
                    if media::needs_apple_fix(&info) {
                        progress(JobProgress::processing("Optimizing for QuickTime", Some(0.0)));
                        let report = |fraction: f64| progress(JobProgress::processing("Optimizing for QuickTime", Some(fraction)));
                        file = media::make_apple_compatible(&self.ctx.tools, &file, cancel, &report).await?;
                    }
                }
            }
            finals.push(paths::move_into(&file, &self.ctx.destination, None)?);
        }
        let reveal = finals.first().cloned().ok_or(DownlyError::NothingToDownload)?;
        Ok(JobOutput { files: finals, reveal, note: None })
    }

    async fn audio(&self, url: &str, format: AudioFormat, square_cover: bool, staging: &Path, cancel: &CancellationToken, progress: ProgressFn<'_>) -> Result<JobOutput> {
        progress(JobProgress::preparing("Starting"));
        let mut args: Vec<String> = vec!["-f".into(), format.source_selector().into(), "-x".into(), "--audio-format".into(), format.as_str().into(), "--audio-quality".into(), format.quality().into(), "--no-playlist".into()];
        if self.ctx.embed_metadata {
            args.push("--embed-metadata".into());
            if format.supports_cover() {
                args.extend(["--embed-thumbnail", "--convert-thumbnails", "jpg"].iter().map(|s| s.to_string()));
                if square_cover {
                    args.push("--ppa".into());
                    args.push("ThumbnailsConvertor+ffmpeg_o:-c:v mjpeg -qmin 1 -qscale:v 1 -vf crop=\"'if(gt(ih,iw),iw,ih)':'if(gt(iw,ih),ih,iw)'\"".into());
                }
            }
        }
        args.extend(self.output_args(staging, None));
        let files = self.run_ytdlp(args, url, HashMap::new(), None, None, cancel, progress).await?;
        let mut finals = Vec::new();
        for path in files {
            finals.push(paths::move_into(Path::new(&path), &self.ctx.destination, None)?);
        }
        let reveal = finals.first().cloned().ok_or(DownlyError::NothingToDownload)?;
        Ok(JobOutput { files: finals, reveal, note: None })
    }

    async fn spotify(&self, input: &SpotifyTrack, format: AudioFormat, folder: Option<&str>, staging: &Path, cancel: &CancellationToken, progress: ProgressFn<'_>) -> Result<JobOutput> {
        progress(JobProgress::preparing("Finding on YouTube Music"));
        let mut track = spotify::enrich(input).await;
        if cancel.is_cancelled() {
            return Err(DownlyError::Cancelled);
        }
        let ytdlp = self.ytdlp();
        let (matched, _) = ytmusic::resolve(&track, Some(&ytdlp)).await?;
        if track.album.is_none() {
            track.album = matched.album.clone().filter(|a| !a.is_empty());
        }
        let note = if matched.artists.is_empty() {
            format!("Matched “{}”", matched.title)
        } else {
            format!("Matched “{}” by {}", matched.title, matched.artists.join(", "))
        };
        let mut update = JobProgress::preparing("Downloading audio");
        update.note = Some(note.clone());
        progress(update);
        let mut args: Vec<String> = vec!["-f".into(), format.source_selector().into(), "-x".into(), "--audio-format".into(), format.as_str().into(), "--audio-quality".into(), format.quality().into(), "--no-playlist".into()];
        args.extend(self.output_args(staging, Some("%(id)s.%(ext)s")));
        let files = self.run_ytdlp(args, &matched.url(), HashMap::new(), Some(note.clone()), None, cancel, progress).await?;
        let downloaded = files.first().map(PathBuf::from).ok_or(DownlyError::NothingToDownload)?;
        let mut update = JobProgress::processing("Adding cover art & tags", None);
        update.note = Some(note.clone());
        progress(update);
        let mut cover_file = None;
        if format.supports_cover() {
            if let Some(cover) = &track.cover {
                let target = staging.join("cover.jpg");
                let noop = |_: u64, _: Option<u64>| {};
                if http::download_file(cover, &target, http::headers(&[]), cancel, &noop).await.is_ok() {
                    cover_file = Some(target);
                }
            }
        }
        let tags = Tags {
            title: track.title.clone(),
            artist: track.artists.join(", "),
            album_artist: track.artists.first().cloned(),
            album: track.album.clone(),
            date: track.release_date.as_ref().map(|d| d.chars().take(10).collect()),
            track: track.track_number.map(|n| n.to_string()),
        };
        let name = format!("{} - {}", track.artists.first().cloned().unwrap_or_else(|| "Unknown Artist".into()), track.title);
        let tagged = media::tag_audio(&self.ctx.tools, &downloaded, &tags, cover_file.as_deref(), &name).await?;
        let directory = match folder.filter(|f| !f.is_empty()) {
            Some(folder) => self.ctx.destination.join(paths::sanitize(folder, 140)),
            None => self.ctx.destination.clone(),
        };
        let final_path = paths::move_into(&tagged, &directory, Some(&name))?;
        Ok(JobOutput { files: vec![final_path.clone()], reveal: final_path, note: Some(note) })
    }

    async fn gallery(&self, items: &[GalleryItem], folder: Option<&str>, staging: &Path, cancel: &CancellationToken, progress: ProgressFn<'_>) -> Result<JobOutput> {
        if items.is_empty() {
            return Err(DownlyError::NothingToDownload);
        }
        let directory = match folder.filter(|f| !f.is_empty() && items.len() > 1) {
            Some(folder) => paths::unique_dir(&self.ctx.destination, &paths::sanitize(folder, 140)),
            None => self.ctx.destination.clone(),
        };
        let count = items.len() as f64;
        let mut finals = Vec::new();
        for (index, item) in items.iter().enumerate() {
            if cancel.is_cancelled() {
                return Err(DownlyError::Cancelled);
            }
            let base = index as f64 / count;
            let note = if items.len() > 1 { Some(format!("Item {} of {}", index + 1, items.len())) } else { None };
            let mut update = JobProgress::phase(Phase::Downloading);
            update.fraction = Some(base);
            update.note = note.clone();
            progress(update);
            let mut produced: Option<PathBuf> = None;
            if item.kind == GalleryKind::Video {
                if let Some(source) = &item.ytdlp_url {
                    let mut args: Vec<String> = ["-f", "bv*+ba/b", "-S", "vcodec:h264,res,acodec:aac", "--merge-output-format", "mp4", "--remux-video", "mp4"].iter().map(|s| s.to_string()).collect();
                    match item.playlist_index {
                        Some(position) => args.extend(["--yes-playlist".to_string(), "--playlist-items".to_string(), position.to_string()]),
                        None => args.push("--no-playlist".into()),
                    }
                    let template = format!("{}.%(ext)s", paths::sanitize(&item.suggested_name, 140));
                    args.extend(self.output_args(staging, Some(&template)));
                    match self.run_ytdlp(args, source, HashMap::new(), note.clone(), Some((base, 1.0 / count)), cancel, progress).await {
                        Ok(files) => produced = files.first().map(PathBuf::from),
                        Err(DownlyError::Cancelled) => return Err(DownlyError::Cancelled),
                        Err(_) => {}
                    }
                }
            }
            if produced.is_none() {
                produced = Some(self.direct(item, staging, base, count, note.clone(), cancel, progress).await?);
            }
            let Some(mut file) = produced else { continue };
            file = media::webp_to_jpeg(&file).await;
            finals.push(paths::move_into(&file, &directory, Some(&item.suggested_name))?);
        }
        let first = finals.first().cloned().ok_or(DownlyError::NothingToDownload)?;
        let reveal = if finals.len() > 1 { directory } else { first };
        Ok(JobOutput { files: finals, reveal, note: None })
    }

    #[allow(clippy::too_many_arguments)]
    async fn direct(&self, item: &GalleryItem, staging: &Path, base: f64, count: f64, note: Option<String>, cancel: &CancellationToken, progress: ProgressFn<'_>) -> Result<PathBuf> {
        let temp = staging.join(format!("item-{}", uuid::Uuid::new_v4()));
        let pairs: Vec<(&str, &str)> = item.headers.iter().map(|(k, v)| (k.as_str(), v.as_str())).collect();
        let report = |received: u64, total: Option<u64>| {
            let fraction = total.filter(|t| *t > 0).map(|t| received as f64 / t as f64).unwrap_or(0.0).min(1.0);
            progress(JobProgress {
                phase: Phase::Downloading,
                fraction: Some(base + fraction / count),
                speed: None,
                eta: None,
                downloaded: Some(received as i64),
                total: total.map(|t| t as i64),
                note: note.clone(),
            });
        };
        let downloaded = http::download_file(&item.url, &temp, http::headers(&pairs), cancel, &report).await?;
        let ext = extension_for(item, downloaded.mime.as_deref());
        let named = staging.join(format!("{}.{ext}", paths::sanitize(&item.suggested_name, 140)));
        let _ = std::fs::remove_file(&named);
        std::fs::rename(&temp, &named)?;
        Ok(named)
    }
}

fn extension_for(item: &GalleryItem, mime: Option<&str>) -> String {
    if let Some(mime) = mime {
        let ext = match mime {
            "image/jpeg" | "image/jpg" => Some("jpg"),
            "image/png" => Some("png"),
            "image/webp" => Some("webp"),
            "image/heic" | "image/heif" => Some("heic"),
            "image/avif" => Some("avif"),
            "image/gif" => Some("gif"),
            "video/mp4" => Some("mp4"),
            "video/quicktime" => Some("mov"),
            "video/webm" => Some("webm"),
            "audio/mpeg" | "audio/mp3" => Some("mp3"),
            "audio/mp4" | "audio/x-m4a" | "audio/aac" => Some("m4a"),
            _ => None,
        };
        if let Some(ext) = ext {
            return ext.to_string();
        }
    }
    let path_ext = url::Url::parse(&item.url)
        .ok()
        .and_then(|u| u.path().rsplit('.').next().map(|e| e.to_lowercase()))
        .unwrap_or_default();
    if ["jpg", "jpeg", "png", "webp", "heic", "mp4", "mov", "mp3", "m4a", "gif"].contains(&path_ext.as_str()) {
        return if path_ext == "jpeg" { "jpg".into() } else { path_ext };
    }
    match item.kind {
        GalleryKind::Photo => "jpg".into(),
        GalleryKind::Video => "mp4".into(),
        GalleryKind::Audio => "m4a".into(),
    }
}
