use serde_json::Value;
use std::collections::HashMap;

use super::error::{DownlyError, Result};
use super::http::{self, CHROME, SAFARI};
use super::instagram::title_from;
use super::json;
use super::link::{LinkKind, ParsedLink, Platform};
use super::models::{Analysis, GalleryItem, GalleryKind, GallerySection, MediaSummary};
use super::paths::sanitize;

pub fn item_struct(html: &str) -> Option<Value> {
    for content in json::script_contents(html, r#"id=["']__UNIVERSAL_DATA_FOR_REHYDRATION__["']"#) {
        let value = json::parse(&content);
        let item = &value["__DEFAULT_SCOPE__"]["webapp.video-detail"]["itemInfo"]["itemStruct"];
        if json::exists(item) {
            return Some(item.clone());
        }
        if let Some(found) = json::find_all(&value, "itemStruct", 1).first() {
            return Some((*found).clone());
        }
    }
    for content in json::script_contents(html, r#"id=["']SIGI_STATE["']"#) {
        let value = json::parse(&content);
        if let Some(module) = value["ItemModule"].as_object().and_then(|m| m.values().next()) {
            return Some(module.clone());
        }
    }
    None
}

pub async fn photo_post(url: &str, id: &str) -> Result<Analysis> {
    let page = http::get(
        &CHROME,
        url,
        http::headers(&[("Accept", "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"), ("Sec-Fetch-Mode", "navigate"), ("Sec-Fetch-Dest", "document")]),
    )
    .await?;
    if !page.ok() {
        return Err(DownlyError::Http(page.status));
    }
    let item = item_struct(&page.body).ok_or_else(|| DownlyError::Unavailable("TikTok didn’t share this post. Try again in a moment.".into()))?;
    gallery(&item, id, url)
}

fn gallery(item: &Value, id: &str, url: &str) -> Result<Analysis> {
    let author = json::s(&item["author"]["uniqueId"]).or_else(|| json::s(&item["author"])).unwrap_or_else(|| "tiktok".into());
    let base = sanitize(&format!("{author} {id}"), 80);
    let mut headers = HashMap::new();
    headers.insert("Referer".to_string(), "https://www.tiktok.com/".to_string());
    let mut items = Vec::new();
    for (index, image) in json::arr(&item["imagePost"]["images"]).iter().enumerate() {
        let urls: Vec<String> = json::arr(&image["imageURL"]["urlList"]).iter().filter_map(json::url).collect();
        let preferred = urls.iter().find(|u| u.contains(".jpeg") || u.contains(".jpg")).or(urls.first()).cloned();
        let Some(preferred) = preferred else { continue };
        items.push(GalleryItem {
            id: format!("{id}-{index}"),
            kind: GalleryKind::Photo,
            url: preferred.clone(),
            thumbnail: Some(preferred),
            width: json::i(&image["imageWidth"]),
            height: json::i(&image["imageHeight"]),
            headers: headers.clone(),
            suggested_name: format!("{base} {}", index + 1),
            ytdlp_url: None,
            playlist_index: None,
        });
    }
    let mut sections = Vec::new();
    if !items.is_empty() {
        sections.push(GallerySection { id: "photos".into(), title: format!("{} photos", items.len()), items: items.clone() });
    }
    if let Some(music) = json::url(&item["music"]["playUrl"]) {
        let title = json::s(&item["music"]["title"]).unwrap_or_else(|| "Sound".into());
        sections.push(GallerySection {
            id: "sound".into(),
            title: "Sound".into(),
            items: vec![GalleryItem {
                id: format!("{id}-audio"),
                kind: GalleryKind::Audio,
                url: music,
                thumbnail: json::url(&item["music"]["coverLarge"]),
                width: None,
                height: None,
                headers: headers.clone(),
                suggested_name: sanitize(&format!("{author} - {title}"), 140),
                ytdlp_url: None,
                playlist_index: None,
            }],
        });
    }
    if sections.is_empty() {
        return Err(DownlyError::NothingToDownload);
    }
    Ok(Analysis::Gallery {
        summary: MediaSummary {
            title: title_from(json::s(&item["desc"]), format!("Photos by @{author}")),
            author: Some(format!("@{author}")),
            thumbnail: items.first().and_then(|i| i.thumbnail.clone()).or_else(|| json::url(&item["video"]["cover"])),
            duration: None,
            platform: Platform::Tiktok,
            webpage_url: url.to_string(),
        },
        sections,
        folder_name: base,
        is_profile: false,
    })
}

fn encode(value: &str) -> String {
    url::form_urlencoded::byte_serialize(value.as_bytes()).collect()
}

async fn oembed(url: &str) -> Option<Value> {
    let page = http::get(&SAFARI, url, http::headers(&[])).await.ok()?;
    if !page.ok() {
        return None;
    }
    let value = page.json();
    if value.is_null() {
        None
    } else {
        Some(value)
    }
}

pub async fn quick_preview(link: &ParsedLink) -> Option<MediaSummary> {
    match &link.kind {
        LinkKind::YoutubeVideo { id } => {
            let thumb = Some(format!("https://i.ytimg.com/vi/{id}/hqdefault.jpg"));
            let value = oembed(&format!("https://www.youtube.com/oembed?format=json&url={}", encode(&link.url))).await;
            Some(MediaSummary {
                title: value.as_ref().and_then(|v| json::s(&v["title"])).unwrap_or_else(|| "YouTube video".into()),
                author: value.as_ref().and_then(|v| json::s(&v["author_name"])),
                thumbnail: thumb,
                duration: None,
                platform: Platform::Youtube,
                webpage_url: link.url.clone(),
            })
        }
        LinkKind::YoutubePlaylist { .. } => {
            let value = oembed(&format!("https://www.youtube.com/oembed?format=json&url={}", encode(&link.url))).await?;
            Some(MediaSummary {
                title: json::s(&value["title"]).unwrap_or_else(|| "Playlist".into()),
                author: json::s(&value["author_name"]),
                thumbnail: json::url(&value["thumbnail_url"]),
                duration: None,
                platform: Platform::Youtube,
                webpage_url: link.url.clone(),
            })
        }
        LinkKind::TiktokVideo { .. } | LinkKind::TiktokPhoto { .. } => {
            let value = oembed(&format!("https://www.tiktok.com/oembed?url={}", encode(&link.url))).await?;
            Some(MediaSummary {
                title: json::s(&value["title"]).unwrap_or_else(|| "TikTok".into()),
                author: json::s(&value["author_name"]).map(|a| format!("@{a}")),
                thumbnail: json::url(&value["thumbnail_url"]),
                duration: None,
                platform: Platform::Tiktok,
                webpage_url: link.url.clone(),
            })
        }
        LinkKind::SpotifyTrack { .. } | LinkKind::SpotifyAlbum { .. } | LinkKind::SpotifyPlaylist { .. } | LinkKind::SpotifyArtist { .. } => {
            let value = oembed(&format!("https://open.spotify.com/oembed?url={}", encode(&link.url))).await?;
            Some(MediaSummary {
                title: json::s(&value["title"]).unwrap_or_else(|| "Spotify".into()),
                author: None,
                thumbnail: json::url(&value["thumbnail_url"]),
                duration: None,
                platform: Platform::Spotify,
                webpage_url: link.url.clone(),
            })
        }
        _ => None,
    }
}
