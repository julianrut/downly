use serde_json::Value;
use std::time::Duration;

use super::error::{DownlyError, Result};
use super::http::{self, SAFARI};
use super::json;
use super::link::Platform;
use super::models::{Analysis, MediaSummary, SpotifyTrack};

pub async fn resolve_short_link(url: &str) -> String {
    let final_url = http::final_url(url).await;
    if final_url.contains("open.spotify.com") {
        return final_url;
    }
    if let Ok(page) = http::get(&SAFARI, url, http::headers(&[])).await {
        if let Some(found) = json::first(r"(https://open\.spotify\.com/(?:track|album|playlist|artist)/[A-Za-z0-9]+)", &page.body, 1) {
            return found;
        }
    }
    final_url
}

pub fn parse_embed(html: &str) -> Option<Value> {
    for content in json::script_contents(html, r#"id=["']__NEXT_DATA__["']"#) {
        let value = json::parse(&content);
        let entity = &value["props"]["pageProps"]["state"]["data"]["entity"];
        if json::exists(entity) {
            return Some(entity.clone());
        }
        if let Some(found) = find_entity(&value) {
            return Some(found);
        }
    }
    for attribute in ["resource", "initial-state", "initialState"] {
        for content in json::script_contents(html, &format!(r#"id=["']{attribute}["']"#)) {
            let trimmed = content.trim();
            let mut value = json::parse(trimmed);
            if value.is_null() {
                use base64::Engine as _;
                if let Ok(data) = base64::engine::general_purpose::STANDARD.decode(trimmed) {
                    value = serde_json::from_slice(&data).unwrap_or(Value::Null);
                }
            }
            if json::exists(&value["data"]["entity"]) {
                return Some(value["data"]["entity"].clone());
            }
            if let Some(found) = find_entity(&value) {
                return Some(found);
            }
        }
    }
    for content in json::script_contents(html, r#"type=["']application/json["']"#) {
        if let Some(found) = find_entity(&json::parse(&content)) {
            return Some(found);
        }
    }
    None
}

fn find_entity(value: &Value) -> Option<Value> {
    json::find_object(value, &|map| {
        let is_spotify = map.get("uri").and_then(|v| v.as_str()).map(|u| u.starts_with("spotify:")).unwrap_or(false);
        is_spotify && (map.contains_key("name") || map.contains_key("title"))
    })
    .cloned()
}

pub fn best_image(entity: &Value) -> Option<String> {
    let mut candidates: Vec<(String, i64)> = Vec::new();
    for list in [&entity["coverArt"]["sources"], &entity["images"], &entity["visualIdentity"]["image"], &entity["album"]["images"]] {
        for image in json::arr(list) {
            if let Some(url) = json::url(&image["url"]) {
                let size = json::i(&image["width"]).or_else(|| json::i(&image["maxWidth"])).or_else(|| json::i(&image["maxHeight"])).unwrap_or(0);
                candidates.push((url, size));
            }
        }
    }
    candidates.into_iter().max_by_key(|c| c.1).map(|c| c.0)
}

pub fn split_artists(text: &str) -> Vec<String> {
    text.replace('\u{a0}', " ")
        .split(", ")
        .flat_map(|part| part.split(" & ").map(|s| s.to_string()).collect::<Vec<_>>())
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
        .collect()
}

fn track_from_entity(entity: &Value, fallback_id: &str, cover: Option<String>) -> SpotifyTrack {
    let id = json::s(&entity["uri"]).and_then(|u| u.rsplit(':').next().map(|s| s.to_string())).or_else(|| json::s(&entity["id"])).unwrap_or_else(|| fallback_id.to_string());
    let title = json::s(&entity["name"]).or_else(|| json::s(&entity["title"])).unwrap_or_else(|| "Unknown".into());
    let mut artists: Vec<String> = json::arr(&entity["artists"]).iter().filter_map(|a| json::s(&a["name"])).collect();
    if artists.is_empty() {
        if let Some(subtitle) = json::s(&entity["subtitle"]) {
            artists = split_artists(&subtitle);
        }
    }
    SpotifyTrack {
        id,
        title,
        artists,
        album: json::s(&entity["album"]["name"]).or_else(|| json::s(&entity["albumOfTrack"]["name"])),
        duration_ms: json::i(&entity["duration"]).or_else(|| json::i(&entity["duration"]["totalMilliseconds"])).or_else(|| json::i(&entity["duration_ms"])),
        cover,
        release_date: json::s(&entity["releaseDate"]["isoString"]).or_else(|| json::s(&entity["releaseDate"])),
        track_number: None,
        explicit: json::b(&entity["isExplicit"]).unwrap_or(false),
    }
}

async fn embed_entity(kind: &str, id: &str) -> Result<Value> {
    let url = format!("https://open.spotify.com/embed/{kind}/{id}");
    let mut last = DownlyError::Unavailable("Couldn’t read this from Spotify.".into());
    for attempt in 0..3u64 {
        if attempt > 0 {
            tokio::time::sleep(Duration::from_millis(400 * attempt)).await;
        }
        let page = match http::get(&SAFARI, &url, http::headers(&[("Accept", "text/html,application/xhtml+xml")])).await {
            Ok(page) => page,
            Err(error) => {
                last = error;
                continue;
            }
        };
        if page.status == 404 {
            return Err(DownlyError::Unavailable("Spotify says this doesn’t exist.".into()));
        }
        if page.ok() {
            if let Some(entity) = parse_embed(&page.body) {
                return Ok(entity);
            }
            last = DownlyError::Unavailable("Spotify changed its page format. Please update Downly.".into());
        } else {
            last = DownlyError::Http(page.status);
        }
    }
    Err(last)
}

async fn track_page_details(id: &str) -> (Option<String>, Option<String>) {
    let Ok(page) = http::get(&SAFARI, &format!("https://open.spotify.com/track/{id}"), http::headers(&[("Accept", "text/html")])).await else {
        return (None, None);
    };
    if !page.ok() {
        return (None, None);
    }
    if let Some(entity) = parse_embed(&page.body) {
        let album = json::s(&entity["albumOfTrack"]["name"]).or_else(|| json::s(&entity["album"]["name"]));
        if album.is_some() {
            return (album, json::s(&entity["albumOfTrack"]["date"]["year"]));
        }
    }
    if let Some(description) = json::meta_content("og:description", &page.body) {
        let parts: Vec<String> = description.split(" · ").map(|s| s.trim().to_string()).collect();
        if let Some(index) = parts.iter().position(|p| p.eq_ignore_ascii_case("song")) {
            if index >= 2 {
                let year = parts.last().filter(|y| y.len() == 4 && y.chars().all(|c| c.is_ascii_digit())).cloned();
                return (Some(parts[index - 1].clone()), year);
            }
        }
    }
    (None, None)
}

pub async fn fetch(kind: &str, id: &str) -> Result<Analysis> {
    let entity = embed_entity(kind, id).await?;
    let web_url = format!("https://open.spotify.com/{kind}/{id}");
    let name = json::s(&entity["name"]).or_else(|| json::s(&entity["title"])).unwrap_or_else(|| "Spotify".into());
    let cover = best_image(&entity);
    let entity_type = json::s(&entity["type"]).unwrap_or_else(|| kind.to_string());

    if entity_type == "track" || kind == "track" {
        let mut track = track_from_entity(&entity, id, cover.clone());
        if track.album.is_none() {
            let (album, year) = track_page_details(id).await;
            track.album = album;
            if track.release_date.is_none() {
                track.release_date = year;
            }
        }
        let summary = MediaSummary {
            title: track.title.clone(),
            author: Some(track.artist_line()),
            thumbnail: track.cover.clone(),
            duration: track.duration(),
            platform: Platform::Spotify,
            webpage_url: web_url,
        };
        return Ok(Analysis::Music { summary, kind: "track".into(), tracks: vec![track] });
    }

    let collection_kind = match entity_type.as_str() {
        "album" | "playlist" | "artist" => entity_type.clone(),
        _ => kind.to_string(),
    };
    let artist_names = json::arr(&entity["artists"]).iter().filter_map(|a| json::s(&a["name"])).collect::<Vec<_>>().join(", ");
    let owner = json::s(&entity["subtitle"])
        .or_else(|| json::s(&entity["authors"][0]["name"]))
        .or_else(|| json::s(&entity["ownerV2"]["data"]["name"]))
        .unwrap_or(artist_names);
    let release = json::s(&entity["releaseDate"]["isoString"]).or_else(|| json::s(&entity["releaseDate"]));
    let is_album = collection_kind == "album";
    let mut tracks = Vec::new();
    for (index, item) in json::arr(&entity["trackList"]).iter().enumerate() {
        let Some(uri) = json::s(&item["uri"]) else { continue };
        if !uri.contains(":track:") {
            continue;
        }
        let track_id = uri.rsplit(':').next().unwrap_or("").to_string();
        let names: Vec<String> = json::arr(&item["artists"]).iter().filter_map(|a| json::s(&a["name"])).collect();
        let artists = if names.is_empty() { split_artists(&json::s(&item["subtitle"]).unwrap_or_default()) } else { names };
        tracks.push(SpotifyTrack {
            id: track_id,
            title: json::s(&item["title"]).or_else(|| json::s(&item["name"])).unwrap_or_else(|| format!("Track {}", index + 1)),
            artists,
            album: if is_album { Some(name.clone()) } else { None },
            duration_ms: json::i(&item["duration"]),
            cover: if is_album { cover.clone() } else { None },
            release_date: if is_album { release.clone() } else { None },
            track_number: if is_album { Some(index as i64 + 1) } else { None },
            explicit: json::b(&item["isExplicit"]).unwrap_or(false),
        });
    }
    if tracks.is_empty() {
        return Err(DownlyError::NothingToDownload);
    }
    let total: f64 = tracks.iter().filter_map(|t| t.duration()).sum();
    let summary = MediaSummary {
        title: name,
        author: if owner.is_empty() { None } else { Some(owner) },
        thumbnail: cover,
        duration: Some(total),
        platform: Platform::Spotify,
        webpage_url: web_url,
    };
    Ok(Analysis::Music { summary, kind: collection_kind, tracks })
}

pub async fn enrich(input: &SpotifyTrack) -> SpotifyTrack {
    let mut output = input.clone();
    if output.cover.is_none() || output.release_date.is_none() {
        if let Ok(entity) = embed_entity("track", &input.id).await {
            let full = track_from_entity(&entity, &input.id, best_image(&entity));
            output.cover = output.cover.or(full.cover);
            output.release_date = output.release_date.or(full.release_date);
            if output.artists.len() < full.artists.len() {
                output.artists = full.artists;
            }
            output.duration_ms = output.duration_ms.or(full.duration_ms);
        }
    }
    if output.album.is_none() {
        let (album, year) = track_page_details(&input.id).await;
        output.album = album;
        output.release_date = output.release_date.or(year);
    }
    output
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_embed() {
        let html = r#"<html><body><script id="__NEXT_DATA__" type="application/json">{"props":{"pageProps":{"state":{"data":{"entity":{"type":"album","name":"Discovery","uri":"spotify:album:2no","subtitle":"Daft Punk","coverArt":{"sources":[{"url":"https://i.scdn.co/image/small","width":64},{"url":"https://i.scdn.co/image/big","width":640}]},"trackList":[{"uri":"spotify:track:0Di","title":"One More Time","subtitle":"Daft Punk","duration":320357}]}}}}}}</script></body></html>"#;
        let entity = parse_embed(html).unwrap();
        assert_eq!(entity["name"], "Discovery");
        assert_eq!(best_image(&entity).as_deref(), Some("https://i.scdn.co/image/big"));
        assert_eq!(split_artists("Daft Punk, Someone Else & Third"), vec!["Daft Punk", "Someone Else", "Third"]);
    }
}
