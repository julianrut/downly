use serde::{Deserialize, Serialize};
use std::collections::HashMap;

use super::link::Platform;

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct MediaSummary {
    pub title: String,
    pub author: Option<String>,
    pub thumbnail: Option<String>,
    pub duration: Option<f64>,
    pub platform: Platform,
    pub webpage_url: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum VideoContainer {
    Mp4,
    Mkv,
}

impl VideoContainer {
    pub fn as_str(&self) -> &'static str {
        match self {
            VideoContainer::Mp4 => "mp4",
            VideoContainer::Mkv => "mkv",
        }
    }

    pub fn title(&self) -> &'static str {
        match self {
            VideoContainer::Mp4 => "MP4",
            VideoContainer::Mkv => "MKV",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum AudioFormat {
    Mp3,
    M4a,
    Opus,
    Flac,
    Wav,
}

impl AudioFormat {
    pub const ALL: [AudioFormat; 5] = [AudioFormat::Mp3, AudioFormat::M4a, AudioFormat::Opus, AudioFormat::Flac, AudioFormat::Wav];

    pub fn as_str(&self) -> &'static str {
        match self {
            AudioFormat::Mp3 => "mp3",
            AudioFormat::M4a => "m4a",
            AudioFormat::Opus => "opus",
            AudioFormat::Flac => "flac",
            AudioFormat::Wav => "wav",
        }
    }

    pub fn title(&self) -> &'static str {
        match self {
            AudioFormat::Mp3 => "MP3",
            AudioFormat::M4a => "M4A",
            AudioFormat::Opus => "Opus",
            AudioFormat::Flac => "FLAC",
            AudioFormat::Wav => "WAV",
        }
    }

    pub fn short_detail(&self) -> &'static str {
        match self {
            AudioFormat::Mp3 => "320 kbps",
            AudioFormat::M4a => "AAC",
            AudioFormat::Opus => "Original",
            AudioFormat::Flac => "Lossless",
            AudioFormat::Wav => "PCM",
        }
    }

    pub fn supports_cover(&self) -> bool {
        !matches!(self, AudioFormat::Wav)
    }

    pub fn quality(&self) -> &'static str {
        match self {
            AudioFormat::Mp3 => "320K",
            _ => "0",
        }
    }

    pub fn source_selector(&self) -> &'static str {
        match self {
            AudioFormat::M4a => "ba[ext=m4a]/ba[acodec^=mp4a]/ba/b",
            AudioFormat::Opus => "ba[acodec=opus]/ba/b",
            _ => "ba/b",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum FilenameStyle {
    Title,
    TitleAndId,
    AuthorAndTitle,
}

impl FilenameStyle {
    pub fn template(&self) -> &'static str {
        match self {
            FilenameStyle::Title => "%(title).170B.%(ext)s",
            FilenameStyle::TitleAndId => "%(title).150B [%(id)s].%(ext)s",
            FilenameStyle::AuthorAndTitle => "%(uploader,channel,creator|Unknown).60B - %(title).140B.%(ext)s",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum CookieBrowser {
    Safari,
    Chrome,
    Firefox,
    Brave,
    Edge,
    Opera,
    Vivaldi,
    Chromium,
}

impl CookieBrowser {
    pub const ALL: [CookieBrowser; 8] = [
        CookieBrowser::Safari,
        CookieBrowser::Chrome,
        CookieBrowser::Firefox,
        CookieBrowser::Brave,
        CookieBrowser::Edge,
        CookieBrowser::Opera,
        CookieBrowser::Vivaldi,
        CookieBrowser::Chromium,
    ];

    pub fn as_str(&self) -> &'static str {
        match self {
            CookieBrowser::Safari => "safari",
            CookieBrowser::Chrome => "chrome",
            CookieBrowser::Firefox => "firefox",
            CookieBrowser::Brave => "brave",
            CookieBrowser::Edge => "edge",
            CookieBrowser::Opera => "opera",
            CookieBrowser::Vivaldi => "vivaldi",
            CookieBrowser::Chromium => "chromium",
        }
    }

    pub fn display_name(&self) -> &'static str {
        match self {
            CookieBrowser::Safari => "Safari",
            CookieBrowser::Chrome => "Google Chrome",
            CookieBrowser::Firefox => "Firefox",
            CookieBrowser::Brave => "Brave",
            CookieBrowser::Edge => "Microsoft Edge",
            CookieBrowser::Opera => "Opera",
            CookieBrowser::Vivaldi => "Vivaldi",
            CookieBrowser::Chromium => "Chromium",
        }
    }

    pub fn app_name(&self) -> &'static str {
        match self {
            CookieBrowser::Safari => "Safari.app",
            CookieBrowser::Chrome => "Google Chrome.app",
            CookieBrowser::Firefox => "Firefox.app",
            CookieBrowser::Brave => "Brave Browser.app",
            CookieBrowser::Edge => "Microsoft Edge.app",
            CookieBrowser::Opera => "Opera.app",
            CookieBrowser::Vivaldi => "Vivaldi.app",
            CookieBrowser::Chromium => "Chromium.app",
        }
    }

    pub fn is_installed(&self) -> bool {
        if matches!(self, CookieBrowser::Safari) {
            return true;
        }
        let name = self.app_name();
        let home = super::paths::home();
        std::path::Path::new("/Applications").join(name).exists() || home.join("Applications").join(name).exists()
    }
}

#[derive(Debug, Clone, Default)]
pub struct EngineSettings {
    pub cookie_browser: Option<CookieBrowser>,
    pub always_use_cookies: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PlaylistEntry {
    pub id: String,
    pub title: String,
    pub url: String,
    pub duration: Option<f64>,
    pub thumbnail: Option<String>,
    pub author: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SpotifyTrack {
    pub id: String,
    pub title: String,
    pub artists: Vec<String>,
    pub album: Option<String>,
    pub duration_ms: Option<i64>,
    pub cover: Option<String>,
    pub release_date: Option<String>,
    pub track_number: Option<i64>,
    #[serde(default)]
    pub explicit: bool,
}

impl SpotifyTrack {
    pub fn artist_line(&self) -> String {
        if self.artists.is_empty() {
            "Unknown Artist".to_string()
        } else {
            self.artists.join(", ")
        }
    }

    pub fn duration(&self) -> Option<f64> {
        self.duration_ms.map(|ms| ms as f64 / 1000.0)
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum GalleryKind {
    Photo,
    Video,
    Audio,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct GalleryItem {
    pub id: String,
    pub kind: GalleryKind,
    pub url: String,
    pub thumbnail: Option<String>,
    pub width: Option<i64>,
    pub height: Option<i64>,
    #[serde(default)]
    pub headers: HashMap<String, String>,
    pub suggested_name: String,
    pub ytdlp_url: Option<String>,
    pub playlist_index: Option<i64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct GallerySection {
    pub id: String,
    pub title: String,
    pub items: Vec<GalleryItem>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct VideoChoice {
    pub tier: i64,
    pub label: String,
    pub caption: String,
    pub fps: Option<i64>,
    pub is_hdr: bool,
    pub video_id: String,
    pub audio_id: Option<String>,
    pub codec: String,
    pub audio_codec: Option<String>,
    pub muxed: bool,
    pub estimated_bytes: Option<i64>,
    pub needs_transcode: bool,
    pub is_vertical: bool,
    pub selector: String,
    pub expected_sizes: HashMap<String, i64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AudioOption {
    pub format: AudioFormat,
    pub title: String,
    pub detail: String,
    pub estimated_bytes: Option<i64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "camelCase")]
pub enum Analysis {
    #[serde(rename_all = "camelCase")]
    Video {
        summary: MediaSummary,
        id: String,
        source_url: String,
        is_live: bool,
        playlist_url: Option<String>,
        is_music: bool,
        has_video: bool,
        mp4_choices: Vec<VideoChoice>,
        mkv_choices: Vec<VideoChoice>,
        audio_options: Vec<AudioOption>,
    },
    #[serde(rename_all = "camelCase")]
    Playlist {
        summary: MediaSummary,
        entries: Vec<PlaylistEntry>,
        is_music: bool,
    },
    #[serde(rename_all = "camelCase")]
    Music {
        summary: MediaSummary,
        kind: String,
        tracks: Vec<SpotifyTrack>,
    },
    #[serde(rename_all = "camelCase")]
    Gallery {
        summary: MediaSummary,
        sections: Vec<GallerySection>,
        folder_name: String,
        is_profile: bool,
    },
}

impl Analysis {
    pub fn summary(&self) -> &MediaSummary {
        match self {
            Analysis::Video { summary, .. } => summary,
            Analysis::Playlist { summary, .. } => summary,
            Analysis::Music { summary, .. } => summary,
            Analysis::Gallery { summary, .. } => summary,
        }
    }
}
