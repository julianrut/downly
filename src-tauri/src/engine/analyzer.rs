use serde_json::Value;
use tokio_util::sync::CancellationToken;

use super::cookies;
use super::error::{DownlyError, Result};
use super::formats::{self, MediaFormat, VideoPreferences};
use super::http;
use super::instagram::Instagram;
use super::json;
use super::link::{self, LinkKind, ParsedLink, Platform};
use super::models::{Analysis, EngineSettings, MediaSummary, PlaylistEntry, VideoContainer};
use super::spotify;
use super::tiktok;
use super::tools::ToolPaths;
use super::ytdlp::Ytdlp;

#[derive(Clone)]
pub struct Analyzer {
    pub tools: ToolPaths,
    pub settings: EngineSettings,
    pub apple_compatible: bool,
    pub prefer_hdr: bool,
}

impl Analyzer {
    fn ytdlp(&self) -> Ytdlp {
        Ytdlp::new(self.tools.clone(), self.settings.cookie_browser)
    }

    pub async fn resolve(&self, input: ParsedLink) -> ParsedLink {
        if !input.needs_resolution() {
            return input;
        }
        let final_url = match input.kind {
            LinkKind::SpotifyShort => spotify::resolve_short_link(&input.url).await,
            _ => http::final_url(&input.url).await,
        };
        match url::Url::parse(&final_url).ok().and_then(|u| link::parse_url(&u)) {
            Some(parsed) if !parsed.needs_resolution() => parsed,
            _ => input,
        }
    }

    pub async fn analyze(&self, input: ParsedLink, cancel: &CancellationToken) -> Result<Analysis> {
        let link = self.resolve(input).await;
        match link.kind.clone() {
            LinkKind::YoutubeVideo { .. } => self.video(&link, false, cancel).await,
            LinkKind::YoutubePlaylist { .. } | LinkKind::YoutubeOther => self.any(&link, cancel).await,
            LinkKind::SpotifyTrack { id } => spotify::fetch("track", &id).await,
            LinkKind::SpotifyAlbum { id } => spotify::fetch("album", &id).await,
            LinkKind::SpotifyPlaylist { id } => spotify::fetch("playlist", &id).await,
            LinkKind::SpotifyArtist { id } => spotify::fetch("artist", &id).await,
            LinkKind::SpotifyShort => Err(DownlyError::Unavailable("Couldn’t open this Spotify short link.".into())),
            LinkKind::InstagramPost { shortcode } => self.instagram_post(&link, &shortcode, cancel).await,
            LinkKind::InstagramStory { username, story_id } => {
                let client = self.instagram().await;
                if username == "highlights" {
                    if let Some(id) = story_id {
                        return client.highlight(&id, &link.url).await;
                    }
                }
                client.stories(&username, story_id.as_deref(), &link.url).await
            }
            LinkKind::InstagramHighlight { id } => self.instagram().await.highlight(&id, &link.url).await,
            LinkKind::InstagramProfile { username } => self.instagram().await.profile_gallery(&username, &link.url).await,
            LinkKind::InstagramShare => self.any(&link, cancel).await,
            LinkKind::TiktokPhoto { id } => self.tiktok_photo(&link, &id, cancel).await,
            LinkKind::TiktokVideo { id } => match self.video(&link, false, cancel).await {
                Ok(Analysis::Video { has_video: false, .. }) => match tiktok::photo_post(&link.url, &id).await {
                    Ok(gallery) => Ok(gallery),
                    Err(_) => self.video(&link, false, cancel).await,
                },
                Ok(analysis) => Ok(analysis),
                Err(DownlyError::Cancelled) => Err(DownlyError::Cancelled),
                Err(error) => tiktok::photo_post(&link.url, &id).await.map_err(|_| error),
            },
            LinkKind::TiktokShort | LinkKind::TiktokOther | LinkKind::Generic => self.any(&link, cancel).await,
        }
    }

    async fn instagram(&self) -> Instagram {
        let session = match self.settings.cookie_browser {
            Some(browser) => cookies::snapshot(browser, &self.tools, false).await.ok(),
            None => None,
        };
        Instagram::new(session)
    }

    async fn instagram_post(&self, link: &ParsedLink, shortcode: &str, cancel: &CancellationToken) -> Result<Analysis> {
        let client = self.instagram().await;
        match client.post(shortcode, &link.url).await {
            Ok(gallery) => Ok(gallery),
            Err(error) => {
                if let Ok(analysis) = self.video(link, self.settings.cookie_browser.is_some(), cancel).await {
                    return Ok(analysis);
                }
                if self.settings.cookie_browser.is_none() {
                    return Err(DownlyError::NeedsLogin(Platform::Instagram, "Instagram didn’t share this post without signing in.".into()));
                }
                Err(error)
            }
        }
    }

    async fn tiktok_photo(&self, link: &ParsedLink, id: &str, cancel: &CancellationToken) -> Result<Analysis> {
        match tiktok::photo_post(&link.url, id).await {
            Ok(gallery) => Ok(gallery),
            Err(error) => {
                let video_url = link.url.replace("/photo/", "/video/");
                let alternate = ParsedLink { url: video_url, platform: Platform::Tiktok, kind: LinkKind::TiktokVideo { id: id.to_string() }, playlist_id: None, is_music: false };
                self.video(&alternate, false, cancel).await.map_err(|_| error)
            }
        }
    }

    fn use_cookies(&self, link: &ParsedLink) -> bool {
        self.settings.cookie_browser.is_some() && (self.settings.always_use_cookies || link.platform == Platform::Instagram)
    }

    pub async fn video(&self, link: &ParsedLink, force_cookies: bool, cancel: &CancellationToken) -> Result<Analysis> {
        let cookies = force_cookies || self.use_cookies(link);
        match self.ytdlp().extract(&link.url, false, cookies, &[], Some(cancel)).await {
            Ok(value) => Ok(self.interpret(&value, link)),
            Err(error) if error.needs_account() && !cookies && self.settings.cookie_browser.is_some() => {
                let value = self.ytdlp().extract(&link.url, false, true, &[], Some(cancel)).await?;
                Ok(self.interpret(&value, link))
            }
            Err(error) => Err(error),
        }
    }

    pub async fn any(&self, link: &ParsedLink, cancel: &CancellationToken) -> Result<Analysis> {
        let cookies = self.use_cookies(link);
        match self.ytdlp().extract(&link.url, true, cookies, &[], Some(cancel)).await {
            Ok(value) => Ok(self.interpret(&value, link)),
            Err(error) if error.needs_account() && !cookies && self.settings.cookie_browser.is_some() => {
                let value = self.ytdlp().extract(&link.url, true, true, &[], Some(cancel)).await?;
                Ok(self.interpret(&value, link))
            }
            Err(error) => Err(error),
        }
    }

    fn interpret(&self, value: &Value, link: &ParsedLink) -> Analysis {
        let kind = json::s(&value["_type"]).unwrap_or_else(|| "video".into());
        if kind == "playlist" || (json::exists(&value["entries"]) && !json::exists(&value["formats"])) {
            let entries: Vec<PlaylistEntry> = json::arr(&value["entries"])
                .iter()
                .filter_map(|entry| {
                    let id = json::s(&entry["id"])?;
                    let url = json::s(&entry["webpage_url"]).or_else(|| json::s(&entry["url"])).unwrap_or_else(|| id.clone());
                    let thumbnail = json::arr(&entry["thumbnails"]).last().and_then(|t| json::url(&t["url"])).or_else(|| json::url(&entry["thumbnail"]));
                    Some(PlaylistEntry {
                        id,
                        title: json::s(&entry["title"]).unwrap_or_else(|| "Untitled".into()),
                        url,
                        duration: json::f(&entry["duration"]),
                        thumbnail,
                        author: json::s(&entry["channel"]).or_else(|| json::s(&entry["uploader"])),
                    })
                })
                .collect();
            let thumbnail = json::arr(&value["thumbnails"]).last().and_then(|t| json::url(&t["url"])).or_else(|| entries.first().and_then(|e| e.thumbnail.clone()));
            let duration: f64 = entries.iter().filter_map(|e| e.duration).sum();
            return Analysis::Playlist {
                summary: MediaSummary {
                    title: json::s(&value["title"]).unwrap_or_else(|| "Playlist".into()),
                    author: json::s(&value["channel"]).or_else(|| json::s(&value["uploader"])),
                    thumbnail,
                    duration: Some(duration),
                    platform: link.platform,
                    webpage_url: link.url.clone(),
                },
                entries,
                is_music: link.is_music,
            };
        }
        let mut formats: Vec<MediaFormat> = json::arr(&value["formats"]).iter().map(MediaFormat::from_json).collect();
        if formats.is_empty() && json::s(&value["url"]).is_some() {
            formats.push(MediaFormat::from_json(value));
        }
        let title = json::s(&value["title"]).or_else(|| json::s(&value["fulltitle"])).unwrap_or_else(|| "Untitled".into());
        let author = json::s(&value["channel"]).or_else(|| json::s(&value["uploader"])).or_else(|| json::s(&value["creator"]));
        let thumbnail = json::url(&value["thumbnail"]).or_else(|| json::arr(&value["thumbnails"]).iter().rev().find_map(|t| json::url(&t["url"])));
        let webpage = json::s(&value["webpage_url"]).unwrap_or_else(|| link.url.clone());
        let duration = json::f(&value["duration"]);
        let social = matches!(link.platform, Platform::Tiktok | Platform::Instagram);
        let title = if social {
            let flat = title.replace('\n', " ");
            if flat.chars().count() > 140 { format!("{}…", flat.chars().take(137).collect::<String>()) } else { flat }
        } else {
            title
        };
        let author = if social { author.map(|a| if a.starts_with('@') { a } else { format!("@{a}") }) } else { author };
        let prefer_muxed = link.platform != Platform::Youtube;
        let mp4 = VideoPreferences { container: VideoContainer::Mp4, apple_compatible: self.apple_compatible, prefer_hdr: self.prefer_hdr };
        let mkv = VideoPreferences { container: VideoContainer::Mkv, apple_compatible: false, prefer_hdr: self.prefer_hdr };
        let playlist_url = match &link.playlist_id {
            Some(list) if link.platform == Platform::Youtube && !list.starts_with("RD") => Some(format!("https://www.youtube.com/playlist?list={list}")),
            _ => None,
        };
        Analysis::Video {
            summary: MediaSummary { title, author, thumbnail, duration, platform: link.platform, webpage_url: webpage.clone() },
            id: json::s(&value["id"]).unwrap_or_else(|| uuid::Uuid::new_v4().to_string()),
            source_url: webpage,
            is_live: json::b(&value["is_live"]).unwrap_or(false),
            playlist_url,
            is_music: link.is_music,
            has_video: formats.iter().any(|f| f.has_video()),
            mp4_choices: formats::video_choices(&formats, duration, &mp4, prefer_muxed),
            mkv_choices: formats::video_choices(&formats, duration, &mkv, prefer_muxed),
            audio_options: formats::audio_options(&formats, duration),
        }
    }
}
