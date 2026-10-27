use serde::{Deserialize, Serialize};

use crate::engine::models::{AudioFormat, CookieBrowser, EngineSettings, FilenameStyle, VideoContainer};
use crate::engine::paths;

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct Settings {
    pub download_folder: String,
    pub video_container: VideoContainer,
    pub apple_compatible: bool,
    pub prefer_hdr: bool,
    pub default_quality: i64,
    pub audio_format: AudioFormat,
    pub music_format: AudioFormat,
    pub embed_metadata: bool,
    pub filename_style: FilenameStyle,
    pub cookie_browser: Option<CookieBrowser>,
    pub always_use_cookies: bool,
    pub max_concurrent: u32,
    pub notifications: bool,
    pub watch_clipboard: bool,
    pub auto_update_engine: bool,
    pub default_mode: String,
}

impl Default for Settings {
    fn default() -> Self {
        Settings {
            download_folder: paths::default_downloads().to_string_lossy().to_string(),
            video_container: VideoContainer::Mp4,
            apple_compatible: true,
            prefer_hdr: false,
            default_quality: 1080,
            audio_format: AudioFormat::Mp3,
            music_format: AudioFormat::Mp3,
            embed_metadata: true,
            filename_style: FilenameStyle::Title,
            cookie_browser: None,
            always_use_cookies: false,
            max_concurrent: 3,
            notifications: true,
            watch_clipboard: true,
            auto_update_engine: true,
            default_mode: "video".into(),
        }
    }
}

impl Settings {
    pub fn load() -> Self {
        std::fs::read(paths::settings_file())
            .ok()
            .and_then(|data| serde_json::from_slice(&data).ok())
            .unwrap_or_default()
    }

    pub fn save(&self) {
        if let Ok(data) = serde_json::to_vec_pretty(self) {
            let _ = std::fs::write(paths::settings_file(), data);
        }
    }

    pub fn engine(&self) -> EngineSettings {
        EngineSettings { cookie_browser: self.cookie_browser, always_use_cookies: self.always_use_cookies }
    }

    pub fn destination(&self) -> std::path::PathBuf {
        paths::expand(&self.download_folder)
    }

    pub fn concurrency(&self) -> usize {
        self.max_concurrent.clamp(1, 6) as usize
    }
}
