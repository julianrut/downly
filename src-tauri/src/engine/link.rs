use base64::Engine as _;
use regex::Regex;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use url::Url;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Platform {
    Youtube,
    Spotify,
    Instagram,
    Tiktok,
    Web,
}

impl Platform {
    pub fn display_name(&self) -> &'static str {
        match self {
            Platform::Youtube => "YouTube",
            Platform::Spotify => "Spotify",
            Platform::Instagram => "Instagram",
            Platform::Tiktok => "TikTok",
            Platform::Web => "Web",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "camelCase")]
pub enum LinkKind {
    YoutubeVideo { id: String },
    YoutubePlaylist { id: String },
    YoutubeOther,
    SpotifyTrack { id: String },
    SpotifyAlbum { id: String },
    SpotifyPlaylist { id: String },
    SpotifyArtist { id: String },
    SpotifyShort,
    InstagramPost { shortcode: String },
    InstagramStory { username: String, story_id: Option<String> },
    InstagramHighlight { id: String },
    InstagramProfile { username: String },
    InstagramShare,
    TiktokVideo { id: String },
    TiktokPhoto { id: String },
    TiktokShort,
    TiktokOther,
    Generic,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ParsedLink {
    pub url: String,
    pub platform: Platform,
    pub kind: LinkKind,
    pub playlist_id: Option<String>,
    pub is_music: bool,
}

impl ParsedLink {
    fn new(url: impl Into<String>, platform: Platform, kind: LinkKind) -> Self {
        ParsedLink { url: url.into(), platform, kind, playlist_id: None, is_music: false }
    }

    fn music(mut self) -> Self {
        self.is_music = true;
        self
    }

    pub fn needs_resolution(&self) -> bool {
        matches!(self.kind, LinkKind::SpotifyShort | LinkKind::TiktokShort | LinkKind::InstagramShare)
    }
}

const INSTAGRAM_RESERVED: &[&str] = &[
    "explore", "accounts", "direct", "about", "developer", "legal", "privacy", "terms", "web", "reels", "reel", "p", "tv",
    "stories", "challenge", "emails", "session", "settings", "api", "graphql", "static", "ar", "s", "share", "your_activity",
    "nametag", "topics", "locations", "tags", "directory", "press", "help", "oauth", "data", "download",
];

pub fn first_link(text: &str) -> Option<ParsedLink> {
    let trimmed = text.trim();
    if let Some(link) = parse(trimmed) {
        return Some(link);
    }
    let regex = Regex::new(r#"(?i)\bhttps?://[^\s<>"'`]+"#).ok()?;
    for found in regex.find_iter(trimmed) {
        let candidate = found.as_str().trim_end_matches(['.', ',', ')', ']', '!', '?']);
        if let Some(link) = parse(candidate) {
            return Some(link);
        }
    }
    None
}

pub fn parse(raw: &str) -> Option<ParsedLink> {
    let mut text = raw.trim().to_string();
    if text.is_empty() || text.contains(char::is_whitespace) {
        return None;
    }
    if let Some(rest) = text.strip_prefix("spotify:") {
        let parts: Vec<&str> = rest.split(':').collect();
        if parts.len() >= 2 {
            return parse_url(&Url::parse(&format!("https://open.spotify.com/{}/{}", parts[0], parts[1])).ok()?);
        }
        return None;
    }
    let lower = text.to_lowercase();
    if !lower.starts_with("http://") && !lower.starts_with("https://") {
        if !text.contains('.') || text.starts_with('.') {
            return None;
        }
        text = format!("https://{text}");
    }
    let url = Url::parse(&text).ok()?;
    let host = url.host_str()?;
    if !host.contains('.') {
        return None;
    }
    parse_url(&url)
}

fn query_map(url: &Url) -> HashMap<String, String> {
    let mut map = HashMap::new();
    for (key, value) in url.query_pairs() {
        map.entry(key.to_string()).or_insert_with(|| value.to_string());
    }
    map
}

pub fn canonical_youtube(id: &str) -> String {
    format!("https://www.youtube.com/watch?v={id}")
}

pub fn parse_url(url: &Url) -> Option<ParsedLink> {
    let raw_host = url.host_str()?.to_lowercase();
    let host = raw_host.strip_prefix("www.").unwrap_or(&raw_host).to_string();
    let segments: Vec<String> = url
        .path_segments()
        .map(|parts| parts.filter(|p| !p.is_empty()).map(|p| p.to_string()).collect())
        .unwrap_or_default();
    let query = query_map(url);
    let original = url.to_string();

    if host == "youtu.be" {
        let id = segments.first()?.clone();
        let mut link = ParsedLink::new(canonical_youtube(&id), Platform::Youtube, LinkKind::YoutubeVideo { id });
        link.playlist_id = query.get("list").cloned();
        return Some(link);
    }
    if host.ends_with("youtube.com") || host.ends_with("youtube-nocookie.com") {
        let is_music = host.starts_with("music.");
        if let Some(id) = query.get("v").filter(|v| !v.is_empty()) {
            let mut link = ParsedLink::new(canonical_youtube(id), Platform::Youtube, LinkKind::YoutubeVideo { id: id.clone() });
            link.playlist_id = query.get("list").cloned();
            link.is_music = is_music;
            return Some(link);
        }
        if let Some(first) = segments.first() {
            if ["shorts", "live", "embed", "v", "e"].contains(&first.as_str()) && segments.len() > 1 {
                let id = segments[1].clone();
                let mut link = ParsedLink::new(canonical_youtube(&id), Platform::Youtube, LinkKind::YoutubeVideo { id });
                link.is_music = is_music;
                return Some(link);
            }
            if first == "playlist" {
                if let Some(list) = query.get("list") {
                    let mut link = ParsedLink::new(
                        format!("https://www.youtube.com/playlist?list={list}"),
                        Platform::Youtube,
                        LinkKind::YoutubePlaylist { id: list.clone() },
                    );
                    link.playlist_id = Some(list.clone());
                    link.is_music = is_music;
                    return Some(link);
                }
            }
        }
        if segments.is_empty() {
            return None;
        }
        let mut target = original.clone();
        let first = &segments[0];
        if first.starts_with('@') || ["channel", "c", "user"].contains(&first.as_str()) {
            let depth = if first.starts_with('@') { 1 } else { 2 };
            if segments.len() == depth {
                target = format!("https://www.youtube.com/{}/videos", segments.join("/"));
            }
        }
        let mut link = ParsedLink::new(target, Platform::Youtube, LinkKind::YoutubeOther);
        link.is_music = is_music;
        return Some(link);
    }

    if host == "spotify.link" || host == "spotify.app.link" {
        return Some(ParsedLink::new(original, Platform::Spotify, LinkKind::SpotifyShort));
    }
    if host.ends_with("spotify.com") {
        let mut parts = segments.clone();
        if parts.first().map(|p| p.starts_with("intl-")).unwrap_or(false) {
            parts.remove(0);
        }
        if parts.first().map(|p| p == "embed").unwrap_or(false) {
            parts.remove(0);
        }
        if parts.len() < 2 {
            return None;
        }
        let kind_name = parts[0].clone();
        let id = parts[1].clone();
        let canonical = format!("https://open.spotify.com/{kind_name}/{id}");
        let kind = match kind_name.as_str() {
            "track" => LinkKind::SpotifyTrack { id },
            "album" => LinkKind::SpotifyAlbum { id },
            "playlist" => LinkKind::SpotifyPlaylist { id },
            "artist" => LinkKind::SpotifyArtist { id },
            _ => LinkKind::Generic,
        };
        return Some(ParsedLink::new(canonical, Platform::Spotify, kind).music());
    }

    if host == "instagr.am" || host.ends_with("instagram.com") {
        let mut parts = segments.clone();
        if parts.len() >= 3
            && ["p", "reel", "reels", "tv"].contains(&parts[1].as_str())
            && !["p", "reel", "reels", "tv", "stories"].contains(&parts[0].as_str())
        {
            parts.remove(0);
        }
        let first = parts.first()?.clone();
        return match first.as_str() {
            "p" | "reel" | "reels" | "tv" => {
                let code = parts.get(1)?.clone();
                let kind_path = if first == "reels" { "reel" } else { first.as_str() };
                Some(ParsedLink::new(
                    format!("https://www.instagram.com/{kind_path}/{code}/"),
                    Platform::Instagram,
                    LinkKind::InstagramPost { shortcode: code },
                ))
            }
            "stories" => {
                let second = parts.get(1)?.clone();
                if second == "highlights" {
                    let id = parts.get(2)?.clone();
                    return Some(ParsedLink::new(original, Platform::Instagram, LinkKind::InstagramHighlight { id }));
                }
                Some(ParsedLink::new(
                    original,
                    Platform::Instagram,
                    LinkKind::InstagramStory { username: second, story_id: parts.get(2).cloned() },
                ))
            }
            "s" => {
                if let Some(token) = parts.get(1) {
                    if let Some(id) = decode_highlight_share(token) {
                        return Some(ParsedLink::new(original, Platform::Instagram, LinkKind::InstagramHighlight { id }));
                    }
                }
                Some(ParsedLink::new(original, Platform::Instagram, LinkKind::InstagramShare))
            }
            "share" => Some(ParsedLink::new(original, Platform::Instagram, LinkKind::InstagramShare)),
            _ => {
                if INSTAGRAM_RESERVED.contains(&first.to_lowercase().as_str()) || !is_instagram_username(&first) {
                    return None;
                }
                Some(ParsedLink::new(
                    format!("https://www.instagram.com/{first}/"),
                    Platform::Instagram,
                    LinkKind::InstagramProfile { username: first },
                ))
            }
        };
    }

    if host == "vm.tiktok.com" || host == "vt.tiktok.com" {
        return Some(ParsedLink::new(original, Platform::Tiktok, LinkKind::TiktokShort));
    }
    if host.ends_with("tiktok.com") {
        if segments.first().map(|s| s == "t").unwrap_or(false) {
            return Some(ParsedLink::new(original, Platform::Tiktok, LinkKind::TiktokShort));
        }
        if let Some(index) = segments.iter().position(|s| s == "video") {
            if let Some(id) = segments.get(index + 1) {
                return Some(ParsedLink::new(original, Platform::Tiktok, LinkKind::TiktokVideo { id: id.clone() }));
            }
        }
        if let Some(index) = segments.iter().position(|s| s == "photo") {
            if let Some(id) = segments.get(index + 1) {
                return Some(ParsedLink::new(original, Platform::Tiktok, LinkKind::TiktokPhoto { id: id.clone() }));
            }
        }
        if segments.first().map(|s| s == "v").unwrap_or(false) && segments.len() > 1 {
            let id = segments[1].replace(".html", "");
            return Some(ParsedLink::new(original, Platform::Tiktok, LinkKind::TiktokVideo { id }));
        }
        if segments.is_empty() {
            return None;
        }
        return Some(ParsedLink::new(original, Platform::Tiktok, LinkKind::TiktokOther));
    }

    if url.scheme() != "http" && url.scheme() != "https" {
        return None;
    }
    Some(ParsedLink::new(original, Platform::Web, LinkKind::Generic))
}

fn is_instagram_username(text: &str) -> bool {
    !text.is_empty() && text.len() <= 30 && text.chars().all(|c| c.is_ascii_alphanumeric() || c == '.' || c == '_')
}

fn decode_highlight_share(token: &str) -> Option<String> {
    let mut base = token.replace('-', "+").replace('_', "/");
    while base.len() % 4 != 0 {
        base.push('=');
    }
    let data = base64::engine::general_purpose::STANDARD.decode(base).ok()?;
    let text = String::from_utf8(data).ok()?;
    text.strip_prefix("highlight:").map(|s| s.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn kind(text: &str) -> Option<LinkKind> {
        parse(text).map(|l| l.kind)
    }

    #[test]
    fn youtube_forms() {
        assert_eq!(kind("https://youtu.be/dQw4w9WgXcQ?t=3"), Some(LinkKind::YoutubeVideo { id: "dQw4w9WgXcQ".into() }));
        assert_eq!(kind("https://www.youtube.com/shorts/abc123XYZ00"), Some(LinkKind::YoutubeVideo { id: "abc123XYZ00".into() }));
        assert_eq!(parse("https://www.youtube.com/watch?v=x&list=PL1").unwrap().playlist_id.as_deref(), Some("PL1"));
        assert_eq!(kind("https://www.youtube.com/playlist?list=PLxyz"), Some(LinkKind::YoutubePlaylist { id: "PLxyz".into() }));
        assert_eq!(parse("https://www.youtube.com/@mkbhd").unwrap().url, "https://www.youtube.com/@mkbhd/videos");
        assert!(parse("https://music.youtube.com/watch?v=abc").unwrap().is_music);
    }

    #[test]
    fn spotify_forms() {
        assert_eq!(kind("https://open.spotify.com/intl-de/track/4cOdK2wGLETKBW3PvgPWqT?si=x"), Some(LinkKind::SpotifyTrack { id: "4cOdK2wGLETKBW3PvgPWqT".into() }));
        assert_eq!(kind("spotify:playlist:pl1"), Some(LinkKind::SpotifyPlaylist { id: "pl1".into() }));
        assert_eq!(kind("https://spotify.link/AbCd"), Some(LinkKind::SpotifyShort));
    }

    #[test]
    fn instagram_forms() {
        assert_eq!(kind("instagram.com/reel/C9xYz123abc/?igsh=1"), Some(LinkKind::InstagramPost { shortcode: "C9xYz123abc".into() }));
        assert_eq!(kind("https://www.instagram.com/natgeo/p/BQ0eAlwhDrw/"), Some(LinkKind::InstagramPost { shortcode: "BQ0eAlwhDrw".into() }));
        assert_eq!(kind("https://www.instagram.com/natgeo/"), Some(LinkKind::InstagramProfile { username: "natgeo".into() }));
        assert_eq!(kind("https://www.instagram.com/stories/highlights/18090946048123978/"), Some(LinkKind::InstagramHighlight { id: "18090946048123978".into() }));
        assert_eq!(kind("https://www.instagram.com/explore/"), None);
    }

    #[test]
    fn tiktok_forms() {
        assert_eq!(kind("https://www.tiktok.com/@u/video/6718335390845095173"), Some(LinkKind::TiktokVideo { id: "6718335390845095173".into() }));
        assert_eq!(kind("https://www.tiktok.com/@u/photo/7300000000000000001"), Some(LinkKind::TiktokPhoto { id: "7300000000000000001".into() }));
        assert_eq!(kind("https://vm.tiktok.com/ZMabc/"), Some(LinkKind::TiktokShort));
    }

    #[test]
    fn link_in_text() {
        assert_eq!(first_link("check https://youtu.be/dQw4w9WgXcQ lol").map(|l| l.kind), Some(LinkKind::YoutubeVideo { id: "dQw4w9WgXcQ".into() }));
        assert!(first_link("nothing here").is_none());
    }
}
