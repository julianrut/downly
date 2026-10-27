use serde_json::Value;
use std::collections::HashMap;

use super::json;
use super::models::{AudioFormat, AudioOption, VideoChoice, VideoContainer};

#[derive(Debug, Clone, Default)]
pub struct MediaFormat {
    pub id: String,
    pub ext: Option<String>,
    pub vcodec: Option<String>,
    pub acodec: Option<String>,
    pub width: Option<i64>,
    pub height: Option<i64>,
    pub fps: Option<f64>,
    pub tbr: Option<f64>,
    pub vbr: Option<f64>,
    pub abr: Option<f64>,
    pub filesize: Option<i64>,
    pub dynamic_range: Option<String>,
    pub protocol: Option<String>,
    pub language_preference: Option<i64>,
    pub note: Option<String>,
    pub has_drm: bool,
    pub channels: Option<i64>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CodecFamily {
    H264,
    Hevc,
    Vp9,
    Av1,
    Other,
}

impl CodecFamily {
    pub fn from(codec: Option<&str>) -> Self {
        let value = codec.unwrap_or("").to_lowercase();
        if value.starts_with("avc") || value.starts_with("h264") || value == "h.264" {
            CodecFamily::H264
        } else if value.starts_with("hev") || value.starts_with("hvc") || value.starts_with("h265") || value.starts_with("bytevc1") || value == "h.265" {
            CodecFamily::Hevc
        } else if value.starts_with("vp9") || value.starts_with("vp09") {
            CodecFamily::Vp9
        } else if value.starts_with("av01") || value == "av1" {
            CodecFamily::Av1
        } else {
            CodecFamily::Other
        }
    }

    pub fn apple_friendly(&self) -> bool {
        matches!(self, CodecFamily::H264 | CodecFamily::Hevc | CodecFamily::Other)
    }

    pub fn name(&self) -> &'static str {
        match self {
            CodecFamily::H264 => "H.264",
            CodecFamily::Hevc => "HEVC",
            CodecFamily::Vp9 => "VP9",
            CodecFamily::Av1 => "AV1",
            CodecFamily::Other => "Video",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AudioFamily {
    Aac,
    Opus,
    Mp3,
    Vorbis,
    Flac,
    Other,
}

impl MediaFormat {
    pub fn from_json(value: &Value) -> Self {
        MediaFormat {
            id: json::raw_s(&value["format_id"]).unwrap_or_else(|| "0".to_string()),
            ext: json::s(&value["ext"]),
            vcodec: json::s(&value["vcodec"]),
            acodec: json::s(&value["acodec"]),
            width: json::i(&value["width"]),
            height: json::i(&value["height"]),
            fps: json::f(&value["fps"]),
            tbr: json::f(&value["tbr"]),
            vbr: json::f(&value["vbr"]),
            abr: json::f(&value["abr"]),
            filesize: json::i(&value["filesize"]).or_else(|| json::i(&value["filesize_approx"])),
            dynamic_range: json::s(&value["dynamic_range"]),
            protocol: json::s(&value["protocol"]),
            language_preference: json::i(&value["language_preference"]),
            note: json::s(&value["format_note"]),
            has_drm: matches!(value["has_drm"], Value::Bool(true)),
            channels: json::i(&value["audio_channels"]),
        }
    }

    pub fn is_storyboard(&self) -> bool {
        self.ext.as_deref() == Some("mhtml") || self.note.as_deref().map(|n| n.to_lowercase().contains("storyboard")).unwrap_or(false)
    }

    pub fn has_video(&self) -> bool {
        if self.is_storyboard() {
            return false;
        }
        if let Some(vcodec) = &self.vcodec {
            return vcodec != "none";
        }
        if self.width.is_some() || self.height.is_some() {
            return true;
        }
        let ext = self.ext.as_deref().unwrap_or("");
        if self.acodec.as_deref().map(|a| a != "none").unwrap_or(false) && ["m4a", "mp3", "opus", "ogg", "aac", "wav", "flac", "weba"].contains(&ext) {
            return false;
        }
        ["mp4", "webm", "mov", "mkv", "flv", "3gp"].contains(&ext)
    }

    pub fn has_audio(&self) -> bool {
        if self.is_storyboard() {
            return false;
        }
        match &self.acodec {
            Some(acodec) => acodec != "none",
            None => true,
        }
    }

    pub fn known_audio(&self) -> bool {
        self.acodec.as_deref().map(|a| a != "none").unwrap_or(false)
    }

    pub fn is_audio_only(&self) -> bool {
        self.has_audio() && !self.has_video() && (self.acodec.is_some() || self.vcodec.as_deref() == Some("none"))
    }

    pub fn is_hdr(&self) -> bool {
        match &self.dynamic_range {
            Some(range) => {
                let upper = range.to_uppercase();
                !upper.is_empty() && upper != "SDR"
            }
            None => false,
        }
    }

    pub fn is_drc(&self) -> bool {
        self.id.to_lowercase().contains("drc") || self.note.as_deref().map(|n| n.to_lowercase().contains("drc")).unwrap_or(false)
    }

    pub fn codec(&self) -> CodecFamily {
        CodecFamily::from(self.vcodec.as_deref())
    }

    pub fn audio_family(&self) -> AudioFamily {
        let value = self.acodec.as_deref().unwrap_or("").to_lowercase();
        if value.starts_with("mp4a") || value.starts_with("aac") || (value.is_empty() && self.ext.as_deref() == Some("m4a")) {
            AudioFamily::Aac
        } else if value.starts_with("opus") {
            AudioFamily::Opus
        } else if value.starts_with("mp3") {
            AudioFamily::Mp3
        } else if value.starts_with("vorbis") {
            AudioFamily::Vorbis
        } else if value.starts_with("flac") {
            AudioFamily::Flac
        } else {
            AudioFamily::Other
        }
    }

    pub fn estimated_bytes(&self, duration: Option<f64>) -> Option<i64> {
        if let Some(size) = self.filesize {
            if size > 0 {
                return Some(size);
            }
        }
        let duration = duration.filter(|d| *d > 0.0)?;
        let rate = self.tbr.or(self.vbr).or(self.abr).filter(|r| *r > 0.0)?;
        Some((rate * 1000.0 / 8.0 * duration) as i64)
    }
}

#[derive(Debug, Clone, Copy)]
pub struct VideoPreferences {
    pub container: VideoContainer,
    pub apple_compatible: bool,
    pub prefer_hdr: bool,
}

pub const TIERS: [i64; 10] = [4320, 2880, 2160, 1440, 1080, 720, 480, 360, 240, 144];

pub fn label(tier: i64) -> String {
    match tier {
        4320 => "8K".into(),
        2880 => "5K".into(),
        2160 => "4K".into(),
        other => format!("{other}p"),
    }
}

pub fn caption(tier: i64) -> String {
    match tier {
        4320 => "4320p".into(),
        2880 => "2880p".into(),
        2160 => "2160p".into(),
        1440 => "Quad HD".into(),
        1080 => "Full HD".into(),
        720 => "HD".into(),
        480 => "SD".into(),
        _ => "Low".into(),
    }
}

pub fn snap(value: i64) -> i64 {
    for tier in TIERS {
        if value as f64 >= tier as f64 * 0.85 {
            return tier;
        }
    }
    144
}

pub fn tier_of(format: &MediaFormat) -> Option<i64> {
    if let Some(note) = &format.note {
        if let Some(value) = json::first(r"(\d{3,4})p", note, 1) {
            if let Ok(number) = value.parse::<i64>() {
                return Some(snap(number));
            }
        }
    }
    if let (Some(w), Some(h)) = (format.width, format.height) {
        if w > 0 && h > 0 {
            let short = w.min(h) as f64;
            let long = w.max(h) as f64;
            return Some(snap(short.max(long * 9.0 / 16.0).round() as i64));
        }
    }
    format.height.filter(|h| *h > 0).map(snap)
}

fn score_video(format: &MediaFormat, prefs: &VideoPreferences, prefer_muxed: bool) -> Vec<f64> {
    let hdr = if format.is_hdr() == prefs.prefer_hdr { 1.0 } else { 0.0 };
    let codec = if prefs.apple_compatible {
        match format.codec() {
            CodecFamily::H264 => 5.0,
            CodecFamily::Hevc => 4.5,
            CodecFamily::Other => 4.0,
            CodecFamily::Vp9 => 3.0,
            CodecFamily::Av1 => 2.0,
        }
    } else {
        match format.codec() {
            CodecFamily::Av1 => 5.0,
            CodecFamily::Vp9 => 4.5,
            CodecFamily::Hevc => 4.0,
            CodecFamily::H264 => 3.5,
            CodecFamily::Other => 3.0,
        }
    };
    let fps = format.fps.unwrap_or(30.0).round();
    let muxed = if prefer_muxed && format.known_audio() { 1.0 } else { 0.0 };
    let protocol = format.protocol.clone().unwrap_or_else(|| "https".to_string());
    let proto = if protocol.starts_with("http") {
        2.0
    } else if protocol.contains("dash") {
        1.5
    } else {
        1.0
    };
    let bitrate = format.tbr.or(format.vbr).unwrap_or(format.filesize.unwrap_or(0) as f64 / 1_000_000.0);
    if prefs.apple_compatible {
        vec![hdr, muxed, codec, fps, proto, bitrate]
    } else {
        vec![hdr, muxed, fps, codec, proto, bitrate]
    }
}

fn compare(a: &[f64], b: &[f64]) -> std::cmp::Ordering {
    a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal)
}

pub fn best_audio(formats: &[MediaFormat], prefer_aac: bool) -> Option<MediaFormat> {
    formats
        .iter()
        .filter(|f| f.is_audio_only() && !f.has_drm)
        .max_by(|a, b| compare(&audio_score(a, prefer_aac), &audio_score(b, prefer_aac)))
        .cloned()
}

fn audio_score(format: &MediaFormat, prefer_aac: bool) -> Vec<f64> {
    let language = format.language_preference.unwrap_or(0) as f64;
    let drc = if format.is_drc() { 0.0 } else { 1.0 };
    let codec = match format.audio_family() {
        AudioFamily::Aac => {
            if prefer_aac {
                3.0
            } else {
                2.0
            }
        }
        AudioFamily::Opus => {
            if prefer_aac {
                2.0
            } else {
                3.0
            }
        }
        AudioFamily::Mp3 | AudioFamily::Vorbis => 1.0,
        AudioFamily::Flac => 1.5,
        AudioFamily::Other => 0.5,
    };
    let channels = format.channels.unwrap_or(2).min(2) as f64;
    let proto = if format.protocol.as_deref().unwrap_or("https").starts_with("http") { 1.0 } else { 0.0 };
    vec![language, drc, codec, channels, proto, format.abr.or(format.tbr).unwrap_or(0.0)]
}

pub fn video_choices(formats: &[MediaFormat], duration: Option<f64>, prefs: &VideoPreferences, prefer_muxed: bool) -> Vec<VideoChoice> {
    let videos: Vec<&MediaFormat> = formats.iter().filter(|f| f.has_video() && !f.has_drm && !f.is_storyboard()).collect();
    let mut grouped: HashMap<i64, Vec<&MediaFormat>> = HashMap::new();
    for format in &videos {
        if let Some(tier) = tier_of(format) {
            grouped.entry(tier).or_default().push(format);
        }
    }
    if grouped.is_empty() {
        if let Some(best) = videos.iter().max_by(|a, b| compare(&[a.tbr.unwrap_or(0.0)], &[b.tbr.unwrap_or(0.0)])) {
            grouped.insert(720, vec![*best]);
        }
    }
    let prefer_aac = prefs.container == VideoContainer::Mp4 || prefs.apple_compatible;
    let mut choices: Vec<VideoChoice> = Vec::new();
    for (tier, candidates) in grouped {
        let Some(video) = candidates
            .iter()
            .max_by(|a, b| compare(&score_video(a, prefs, prefer_muxed), &score_video(b, prefs, prefer_muxed)))
        else {
            continue;
        };
        let video = (*video).clone();
        let audio = if video.known_audio() { None } else { best_audio(formats, prefer_aac) };
        let video_bytes = video.estimated_bytes(duration);
        let audio_bytes = audio.as_ref().and_then(|a| a.estimated_bytes(duration));
        let total = video_bytes.map(|v| v + audio_bytes.unwrap_or(0));
        let vertical = video.height.unwrap_or(0) > video.width.unwrap_or(0);
        let needs_transcode = prefs.apple_compatible && !video.codec().apple_friendly();
        let mut expected = HashMap::new();
        if let Some(size) = video_bytes {
            expected.insert(video.id.clone(), size);
        }
        if let (Some(a), Some(size)) = (&audio, audio_bytes) {
            expected.insert(a.id.clone(), size);
        }
        choices.push(VideoChoice {
            tier,
            label: label(tier),
            caption: caption(tier),
            fps: video.fps.map(|f| f.round() as i64),
            is_hdr: video.is_hdr(),
            video_id: video.id.clone(),
            audio_id: audio.as_ref().map(|a| a.id.clone()),
            codec: video.codec().name().to_string(),
            audio_codec: audio.as_ref().map(|a| match a.audio_family() {
                AudioFamily::Aac => "AAC".to_string(),
                AudioFamily::Opus => "Opus".to_string(),
                AudioFamily::Mp3 => "MP3".to_string(),
                _ => "audio".to_string(),
            }),
            muxed: audio.is_none(),
            estimated_bytes: total,
            needs_transcode,
            is_vertical: vertical,
            selector: selector(&video, audio.as_ref(), tier, vertical),
            expected_sizes: expected,
        });
    }
    choices.sort_by(|a, b| b.tier.cmp(&a.tier));
    choices
}

pub fn selector(video: &MediaFormat, audio: Option<&MediaFormat>, tier: i64, vertical: bool) -> String {
    let mut parts = Vec::new();
    if let Some(audio) = audio {
        parts.push(format!("{}+{}", video.id, audio.id));
    }
    parts.push(format!("{}+ba", video.id));
    parts.push(video.id.clone());
    let bound = if vertical { "width" } else { "height" };
    let limit = if vertical { tier } else { (tier as f64 * 1.05) as i64 };
    parts.push(format!("bv*[{bound}<={limit}]+ba"));
    parts.push(format!("b[{bound}<={limit}]"));
    parts.push("bv*+ba".to_string());
    parts.push("b".to_string());
    parts.join("/")
}

pub fn playlist_selector(tier: Option<i64>, prefs: &VideoPreferences) -> (String, String) {
    let audio_sort = if prefs.container == VideoContainer::Mp4 || prefs.apple_compatible { "acodec:aac" } else { "acodec:opus" };
    let codec = if prefs.apple_compatible { ",vcodec:h264" } else { "" };
    match tier {
        None => ("bv*+ba/b".to_string(), format!("res,fps{codec},{audio_sort}")),
        Some(tier) => (
            format!("bv*[height<={tier}]+ba/b[height<={tier}]/bv*+ba/b"),
            format!("res:{tier},fps{codec},{audio_sort}"),
        ),
    }
}

pub fn audio_options(formats: &[MediaFormat], duration: Option<f64>) -> Vec<AudioOption> {
    let aac = best_audio(formats, true);
    let opus = best_audio(formats, false);
    AudioFormat::ALL
        .iter()
        .map(|format| {
            let estimate = match format {
                AudioFormat::Mp3 => duration.map(|d| (d * 320_000.0 / 8.0) as i64),
                AudioFormat::M4a => aac.as_ref().and_then(|a| a.estimated_bytes(duration)).or(duration.map(|d| (d * 160_000.0 / 8.0) as i64)),
                AudioFormat::Opus => opus.as_ref().and_then(|a| a.estimated_bytes(duration)).or(duration.map(|d| (d * 160_000.0 / 8.0) as i64)),
                AudioFormat::Flac => duration.map(|d| (d * 900_000.0 / 8.0) as i64),
                AudioFormat::Wav => duration.map(|d| (d * 1_411_200.0 / 8.0) as i64),
            };
            AudioOption {
                format: *format,
                title: format.title().to_string(),
                detail: format.short_detail().to_string(),
                estimated_bytes: estimate,
            }
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fmt(id: &str, v: &str, a: &str, w: Option<i64>, h: Option<i64>, tbr: f64, ext: &str, note: Option<&str>) -> MediaFormat {
        MediaFormat {
            id: id.into(),
            ext: Some(ext.into()),
            vcodec: Some(v.into()),
            acodec: Some(a.into()),
            width: w,
            height: h,
            fps: Some(30.0),
            tbr: Some(tbr),
            note: note.map(|n| n.into()),
            ..Default::default()
        }
    }

    #[test]
    fn youtube_choices_always_include_audio() {
        let formats = vec![
            fmt("137", "avc1.640028", "none", Some(1920), Some(1080), 4000.0, "mp4", Some("1080p")),
            fmt("248", "vp9", "none", Some(1920), Some(1080), 3000.0, "webm", Some("1080p")),
            fmt("313", "vp9", "none", Some(3840), Some(2160), 16000.0, "webm", Some("2160p")),
            fmt("140", "none", "mp4a.40.2", None, None, 129.0, "m4a", None),
            fmt("251", "none", "opus", None, None, 140.0, "webm", None),
        ];
        let compat = VideoPreferences { container: VideoContainer::Mp4, apple_compatible: true, prefer_hdr: false };
        let choices = video_choices(&formats, Some(100.0), &compat, false);
        assert_eq!(choices.iter().map(|c| c.tier).collect::<Vec<_>>(), vec![2160, 1080]);
        assert_eq!(choices[1].video_id, "137");
        assert_eq!(choices[1].audio_id.as_deref(), Some("140"));
        assert!(choices[1].selector.starts_with("137+140/"));
        assert!(choices[0].needs_transcode);
        let original = VideoPreferences { container: VideoContainer::Mkv, apple_compatible: false, prefer_hdr: false };
        let choices = video_choices(&formats, Some(100.0), &original, false);
        assert_eq!(choices[1].video_id, "248");
        assert_eq!(choices[1].audio_id.as_deref(), Some("251"));
    }

    #[test]
    fn tiers() {
        assert_eq!(tier_of(&fmt("v", "h264", "aac", Some(1080), Some(1920), 1.0, "mp4", None)), Some(1080));
        assert_eq!(tier_of(&fmt("v", "h264", "aac", Some(1920), Some(800), 1.0, "mp4", None)), Some(1080));
        assert_eq!(tier_of(&fmt("v", "h264", "aac", Some(576), Some(1024), 1.0, "mp4", None)), Some(480));
    }

    #[test]
    fn muxed_preferred() {
        let formats = vec![
            fmt("bytevc1_1080p", "h265", "none", Some(1080), Some(1920), 2000.0, "mp4", None),
            fmt("h264_1080p", "h264", "aac", Some(1080), Some(1920), 1500.0, "mp4", None),
        ];
        let prefs = VideoPreferences { container: VideoContainer::Mp4, apple_compatible: true, prefer_hdr: false };
        let choices = video_choices(&formats, Some(30.0), &prefs, true);
        assert_eq!(choices[0].video_id, "h264_1080p");
        assert!(choices[0].audio_id.is_none());
    }
}
