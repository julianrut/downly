use std::collections::{HashMap, HashSet};
use std::path::{Path, PathBuf};
use std::sync::{LazyLock, Mutex};
use std::time::{Duration, Instant};
use tokio_util::sync::CancellationToken;

use super::error::{DownlyError, Result};
use super::formats::snap;
use super::json;
use super::paths::sanitize;
use super::process::{self, Channel};
use super::tools::ToolPaths;

#[derive(Debug, Clone, Default)]
pub struct Probe {
    pub duration: Option<f64>,
    pub video_codec: Option<String>,
    pub video_tag: Option<String>,
    pub audio_codec: Option<String>,
    pub width: Option<i64>,
    pub height: Option<i64>,
    pub pixel_format: Option<String>,
    pub frame_rate: Option<f64>,
    pub bit_rate: Option<f64>,
}

#[derive(Debug, Clone, Default)]
pub struct Tags {
    pub title: String,
    pub artist: String,
    pub album_artist: Option<String>,
    pub album: Option<String>,
    pub date: Option<String>,
    pub track: Option<String>,
}

static ENCODERS: LazyLock<Mutex<HashMap<PathBuf, HashSet<String>>>> = LazyLock::new(|| Mutex::new(HashMap::new()));

fn s(path: &Path) -> String {
    path.to_string_lossy().to_string()
}

pub async fn encoders(ffmpeg: &Path) -> HashSet<String> {
    if let Some(cached) = ENCODERS.lock().unwrap().get(ffmpeg) {
        return cached.clone();
    }
    let Ok(output) = process::run_timeout(ffmpeg, &process::strings(&["-hide_banner", "-encoders"]), 20).await else {
        return HashSet::new();
    };
    let names: HashSet<String> = output
        .stdout
        .lines()
        .filter_map(|line| {
            let parts: Vec<&str> = line.split_whitespace().collect();
            if parts.len() >= 2 && parts[0].len() == 6 {
                Some(parts[1].to_string())
            } else {
                None
            }
        })
        .collect();
    ENCODERS.lock().unwrap().insert(ffmpeg.to_path_buf(), names.clone());
    names
}

pub async fn probe(tools: &ToolPaths, file: &Path) -> Option<Probe> {
    let output = process::run_timeout(&tools.ffprobe, &["-v".into(), "quiet".into(), "-print_format".into(), "json".into(), "-show_format".into(), "-show_streams".into(), s(file)], 60).await.ok()?;
    if !output.ok() {
        return None;
    }
    let value = json::parse(&output.stdout);
    let mut info = Probe { duration: json::f(&value["format"]["duration"]), bit_rate: json::f(&value["format"]["bit_rate"]), ..Default::default() };
    for stream in json::arr(&value["streams"]) {
        let kind = json::s(&stream["codec_type"]).unwrap_or_default();
        if kind == "video" && json::i(&stream["disposition"]["attached_pic"]) != Some(1) && info.video_codec.is_none() {
            info.video_codec = json::s(&stream["codec_name"]);
            info.video_tag = json::s(&stream["codec_tag_string"]);
            info.width = json::i(&stream["width"]);
            info.height = json::i(&stream["height"]);
            info.pixel_format = json::s(&stream["pix_fmt"]);
            if let Some(rate) = json::s(&stream["avg_frame_rate"]).or_else(|| json::s(&stream["r_frame_rate"])) {
                let parts: Vec<&str> = rate.split('/').collect();
                if parts.len() == 2 {
                    if let (Ok(n), Ok(d)) = (parts[0].parse::<f64>(), parts[1].parse::<f64>()) {
                        if d > 0.0 {
                            info.frame_rate = Some(n / d);
                        }
                    }
                }
            }
        } else if kind == "audio" && info.audio_codec.is_none() {
            info.audio_codec = json::s(&stream["codec_name"]);
        }
    }
    Some(info)
}

fn replace(original: &Path, produced: &Path, ext: &str) -> Result<PathBuf> {
    let _ = std::fs::remove_file(original);
    let target = original.with_extension(ext);
    let _ = std::fs::remove_file(&target);
    std::fs::rename(produced, &target)?;
    Ok(target)
}

pub fn needs_apple_fix(info: &Probe) -> bool {
    match info.video_codec.as_deref() {
        Some("h264") => false,
        Some("hevc") => info.video_tag.as_deref() != Some("hvc1"),
        Some(_) => true,
        None => false,
    }
}

pub async fn make_apple_compatible(tools: &ToolPaths, file: &Path, cancel: &CancellationToken, progress: &(dyn Fn(f64) + Send + Sync)) -> Result<PathBuf> {
    let Some(info) = probe(tools, file).await else { return Ok(file.to_path_buf()) };
    let Some(codec) = info.video_codec.clone() else { return Ok(file.to_path_buf()) };
    if codec == "h264" {
        return Ok(file.to_path_buf());
    }
    let audio_args: Vec<String> = match info.audio_codec.as_deref() {
        Some("aac") | None => process::strings(&["-c:a", "copy"]),
        _ => process::strings(&["-c:a", "aac", "-b:a", "256k"]),
    };
    let stem = file.file_stem().map(|s| s.to_string_lossy().to_string()).unwrap_or_else(|| "video".into());
    let parent = file.parent().map(|p| p.to_path_buf()).unwrap_or_default();
    if codec == "hevc" {
        if info.video_tag.as_deref() == Some("hvc1") && file.extension().map(|e| e == "mp4").unwrap_or(false) {
            return Ok(file.to_path_buf());
        }
        let output = parent.join(format!("{stem}.remux.mp4"));
        let mut args = vec!["-hide_banner".into(), "-nostdin".into(), "-y".into(), "-i".into(), s(file)];
        args.extend(process::strings(&["-map", "0:v:0", "-map", "0:a?", "-c:v", "copy", "-tag:v", "hvc1"]));
        args.extend(audio_args.clone());
        args.extend(process::strings(&["-movflags", "+faststart"]));
        args.push(s(&output));
        let result = process::run(&tools.ffmpeg, &args, Some(cancel), None).await?;
        if !result.ok() {
            let _ = std::fs::remove_file(&output);
            return Ok(file.to_path_buf());
        }
        return replace(file, &output, "mp4");
    }

    let available = encoders(&tools.ffmpeg).await;
    let width = info.width.unwrap_or(1920);
    let height = info.height.unwrap_or(1080);
    let tier = snap((width.min(height) as f64).max(width.max(height) as f64 * 9.0 / 16.0) as i64);
    let fps = info.frame_rate.unwrap_or(30.0);
    let mut megabits: f64 = match tier {
        t if t >= 4320 => 60.0,
        t if t >= 2880 => 45.0,
        t if t >= 2160 => 28.0,
        t if t >= 1440 => 14.0,
        t if t >= 1080 => 8.0,
        _ => 5.0,
    };
    if fps > 40.0 {
        megabits *= 1.45;
    }
    if let Some(source) = info.bit_rate {
        megabits = megabits.min((source / 1_000_000.0 * 1.6).max(megabits * 0.5));
    }
    let bitrate = format!("{}k", (megabits * 1000.0) as i64);
    let ten_bit = info.pixel_format.as_deref().map(|p| p.contains("10")).unwrap_or(false);
    let mut attempts: Vec<Vec<String>> = Vec::new();
    if available.contains("hevc_videotoolbox") {
        let mut a = process::strings(&["-c:v", "hevc_videotoolbox", "-b:v", &bitrate, "-tag:v", "hvc1"]);
        if ten_bit {
            a.extend(process::strings(&["-profile:v", "main10", "-pix_fmt", "p010le"]));
        } else {
            a.extend(process::strings(&["-pix_fmt", "yuv420p"]));
        }
        attempts.push(a);
    }
    if available.contains("h264_videotoolbox") && tier <= 2160 {
        attempts.push(process::strings(&["-c:v", "h264_videotoolbox", "-b:v", &bitrate, "-pix_fmt", "yuv420p", "-profile:v", "high"]));
    }
    if available.contains("libx265") {
        attempts.push(process::strings(&["-c:v", "libx265", "-preset", "faster", "-crf", "21", "-tag:v", "hvc1", "-pix_fmt", if ten_bit { "yuv420p10le" } else { "yuv420p" }]));
    }
    if available.contains("libx264") || attempts.is_empty() {
        attempts.push(process::strings(&["-c:v", "libx264", "-preset", "veryfast", "-crf", "19", "-pix_fmt", "yuv420p"]));
    }
    let output = parent.join(format!("{stem}.apple.mp4"));
    let mut last = DownlyError::ToolFailed("Couldn’t convert the video for QuickTime.".into());
    for video_args in attempts {
        if cancel.is_cancelled() {
            return Err(DownlyError::Cancelled);
        }
        let _ = std::fs::remove_file(&output);
        let mut args: Vec<String> = vec!["-hide_banner".into(), "-nostdin".into(), "-y".into(), "-i".into(), s(file)];
        args.extend(process::strings(&["-map", "0:v:0", "-map", "0:a?", "-map_metadata", "0"]));
        args.extend(video_args);
        args.extend(audio_args.clone());
        args.extend(process::strings(&["-movflags", "+faststart", "-progress", "pipe:1", "-nostats"]));
        args.push(s(&output));
        match run_ffmpeg(tools, &args, info.duration, cancel, progress).await {
            Ok(()) => return replace(file, &output, "mp4"),
            Err(DownlyError::Cancelled) => {
                let _ = std::fs::remove_file(&output);
                return Err(DownlyError::Cancelled);
            }
            Err(error) => last = error,
        }
    }
    let _ = std::fs::remove_file(&output);
    Err(last)
}

async fn run_ffmpeg(tools: &ToolPaths, args: &[String], duration: Option<f64>, cancel: &CancellationToken, progress: &(dyn Fn(f64) + Send + Sync)) -> Result<()> {
    let last = Mutex::new(Instant::now() - Duration::from_secs(1));
    let handler = |line: &str, channel: Channel| {
        if channel != Channel::Stdout {
            return;
        }
        let Some(total) = duration.filter(|d| *d > 0.0) else { return };
        if let Some(value) = line.strip_prefix("out_time_us=").or_else(|| line.strip_prefix("out_time_ms=")) {
            let micros: f64 = value.trim().parse().unwrap_or(0.0);
            let mut guard = last.lock().unwrap();
            if guard.elapsed() >= Duration::from_millis(200) {
                *guard = Instant::now();
                progress((micros / 1_000_000.0 / total).clamp(0.0, 1.0));
            }
        } else if line == "progress=end" {
            progress(1.0);
        }
    };
    let output = process::run(&tools.ffmpeg, args, Some(cancel), Some(&handler)).await?;
    if output.ok() {
        Ok(())
    } else {
        let detail = output.stderr.lines().rev().take(2).collect::<Vec<_>>().join(" ");
        Err(DownlyError::ToolFailed(if detail.is_empty() { "FFmpeg failed.".into() } else { detail }))
    }
}

pub async fn tag_audio(tools: &ToolPaths, file: &Path, tags: &Tags, cover: Option<&Path>, output_name: &str) -> Result<PathBuf> {
    let ext = file.extension().map(|e| e.to_string_lossy().to_lowercase()).unwrap_or_else(|| "mp3".into());
    let parent = file.parent().map(|p| p.to_path_buf()).unwrap_or_default();
    let output = parent.join(format!("tagged-{}.{ext}", &uuid::Uuid::new_v4().to_string()[..8]));
    let mut metadata: Vec<String> = Vec::new();
    let mut add = |key: &str, value: Option<&str>| {
        if let Some(value) = value.filter(|v| !v.is_empty()) {
            metadata.push("-metadata".into());
            metadata.push(format!("{key}={value}"));
        }
    };
    add("title", Some(&tags.title));
    add("artist", Some(&tags.artist));
    add("album_artist", tags.album_artist.as_deref());
    add("album", tags.album.as_deref());
    add("date", tags.date.as_deref());
    add("track", tags.track.as_deref());

    let supports_cover = ["mp3", "m4a", "flac", "mp4", "aac"].contains(&ext.as_str());
    let mut attempts: Vec<Vec<String>> = Vec::new();
    if supports_cover {
        if let Some(cover) = cover.filter(|c| c.exists()) {
            let mut args: Vec<String> = vec!["-hide_banner".into(), "-nostdin".into(), "-y".into(), "-i".into(), s(file), "-i".into(), s(cover)];
            args.extend(process::strings(&["-map", "0:a:0", "-map", "1:0", "-c", "copy"]));
            if ext == "mp3" {
                args.extend(process::strings(&["-id3v2_version", "3", "-metadata:s:v", "title=Album cover", "-metadata:s:v", "comment=Cover (front)"]));
            }
            args.extend(process::strings(&["-disposition:v:0", "attached_pic"]));
            args.extend(metadata.clone());
            args.push(s(&output));
            attempts.push(args);
        }
    }
    let mut plain: Vec<String> = vec!["-hide_banner".into(), "-nostdin".into(), "-y".into(), "-i".into(), s(file)];
    plain.extend(process::strings(&["-map", "0:a:0", "-c", "copy"]));
    if ext == "mp3" {
        plain.extend(process::strings(&["-id3v2_version", "3"]));
    }
    plain.extend(metadata.clone());
    plain.push(s(&output));
    attempts.push(plain);

    let final_path = parent.join(format!("{}.{ext}", sanitize(output_name, 140)));
    for args in attempts {
        let result = process::run(&tools.ffmpeg, &args, None, None).await?;
        if result.ok() && output.exists() {
            let _ = std::fs::remove_file(file);
            let _ = std::fs::remove_file(&final_path);
            std::fs::rename(&output, &final_path)?;
            return Ok(final_path);
        }
        let _ = std::fs::remove_file(&output);
    }
    if final_path != file {
        let _ = std::fs::remove_file(&final_path);
        std::fs::rename(file, &final_path)?;
    }
    Ok(final_path)
}

pub async fn webp_to_jpeg(file: &Path) -> PathBuf {
    if file.extension().map(|e| e.to_string_lossy().to_lowercase()) != Some("webp".into()) || !cfg!(target_os = "macos") {
        return file.to_path_buf();
    }
    let output = file.with_extension("jpg");
    let result = process::run(Path::new("/usr/bin/sips"), &["-s".into(), "format".into(), "jpeg".into(), "-s".into(), "formatOptions".into(), "best".into(), s(file), "--out".into(), s(&output)], None, None).await;
    if result.map(|r| r.ok()).unwrap_or(false) && output.exists() {
        let _ = std::fs::remove_file(file);
        return output;
    }
    file.to_path_buf()
}
