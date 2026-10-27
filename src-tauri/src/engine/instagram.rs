use reqwest::header::HeaderMap;
use reqwest::Client;
use serde_json::Value;
use std::collections::HashMap;
use std::sync::Arc;

use super::cookies::CookieSnapshot;
use super::error::{DownlyError, Result};
use super::http::{self, SAFARI_UA};
use super::json;
use super::link::Platform;
use super::models::{Analysis, GalleryItem, GalleryKind, GallerySection, MediaSummary};
use super::paths::sanitize;

const APP_ID: &str = "936619743392459";
const ALPHABET: &str = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";

pub fn media_id(shortcode: &str) -> Option<String> {
    let code: String = if shortcode.len() > 28 { shortcode[..shortcode.len() - 28].to_string() } else { shortcode.to_string() };
    let mut value: u64 = 0;
    for c in code.chars() {
        let index = ALPHABET.find(c)? as u64;
        value = value.checked_mul(64)?.checked_add(index)?;
    }
    Some(value.to_string())
}

fn media_headers() -> HashMap<String, String> {
    let mut map = HashMap::new();
    map.insert("Referer".into(), "https://www.instagram.com/".into());
    map
}

pub fn title_from(caption: Option<String>, fallback: String) -> String {
    let Some(caption) = caption else { return fallback };
    let first = caption.lines().next().unwrap_or("").trim().to_string();
    if first.is_empty() {
        return fallback;
    }
    if first.chars().count() > 120 {
        format!("{}…", first.chars().take(117).collect::<String>())
    } else {
        first
    }
}

pub struct Instagram {
    client: Client,
    jar: Arc<reqwest::cookie::Jar>,
    session: Option<CookieSnapshot>,
}

impl Instagram {
    pub fn new(session: Option<CookieSnapshot>) -> Self {
        let jar = Arc::new(reqwest::cookie::Jar::default());
        let client = http::build_client(SAFARI_UA, 25, Some(jar.clone()));
        Instagram { client, jar, session }
    }

    pub fn logged_in(&self) -> bool {
        self.session.as_ref().and_then(|s| s.value("sessionid", "instagram.com")).map(|v| !v.is_empty()).unwrap_or(false)
    }

    fn api_headers(&self) -> HeaderMap {
        let mut pairs: Vec<(String, String)> = vec![
            ("X-IG-App-ID".into(), APP_ID.into()),
            ("X-ASBD-ID".into(), "359341".into()),
            ("X-IG-WWW-Claim".into(), "0".into()),
            ("X-Requested-With".into(), "XMLHttpRequest".into()),
            ("Origin".into(), "https://www.instagram.com".into()),
            ("Referer".into(), "https://www.instagram.com/".into()),
            ("Accept".into(), "*/*".into()),
            ("Sec-Fetch-Site".into(), "same-origin".into()),
            ("Sec-Fetch-Mode".into(), "cors".into()),
            ("Sec-Fetch-Dest".into(), "empty".into()),
        ];
        if let Some(session) = &self.session {
            let cookie = session.header("instagram.com");
            if !cookie.is_empty() {
                pairs.push(("Cookie".into(), cookie));
            }
            if let Some(csrf) = session.value("csrftoken", "instagram.com") {
                pairs.push(("X-CSRFToken".into(), csrf));
            }
        }
        let refs: Vec<(&str, &str)> = pairs.iter().map(|(k, v)| (k.as_str(), v.as_str())).collect();
        http::headers(&refs)
    }

    async fn api(&self, path: &str) -> Result<Value> {
        let page = http::get(&self.client, &format!("https://www.instagram.com/api/v1/{path}"), self.api_headers()).await?;
        if page.status == 401 || page.status == 403 || page.final_url.contains("/accounts/login") {
            return Err(DownlyError::NeedsLogin(Platform::Instagram, "Instagram wants you to be signed in to see this.".into()));
        }
        if page.status == 429 {
            return Err(DownlyError::NeedsLogin(Platform::Instagram, "Instagram is limiting requests right now. Signing in usually fixes this.".into()));
        }
        if page.status == 404 {
            return Err(DownlyError::Unavailable("This Instagram content doesn’t exist or was removed.".into()));
        }
        if !page.ok() {
            return Err(DownlyError::Http(page.status));
        }
        let value = page.json();
        if json::b(&value["require_login"]) == Some(true) || json::s(&value["message"]).as_deref() == Some("login_required") {
            return Err(DownlyError::NeedsLogin(Platform::Instagram, "Instagram wants you to be signed in to see this.".into()));
        }
        Ok(value)
    }

    pub async fn post(&self, shortcode: &str, url: &str) -> Result<Analysis> {
        let id = media_id(shortcode).ok_or(DownlyError::UnsupportedLink)?;
        let mut product: Option<Value> = None;
        let mut last_error: Option<DownlyError> = None;
        if self.logged_in() {
            match self.api(&format!("media/{id}/info/")).await {
                Ok(value) if json::exists(&value["items"][0]) => product = Some(value["items"][0].clone()),
                Ok(_) => {}
                Err(error) => last_error = Some(error),
            }
        }
        if product.is_none() {
            match self.anonymous_product(shortcode, &id).await {
                Ok(found) => product = found,
                Err(error) => last_error = last_error.or(Some(error)),
            }
        }
        if let Some(product) = product {
            return self.gallery_from_product(&product, shortcode, url);
        }
        if let Ok(Some(legacy)) = self.embed_legacy(shortcode, url).await {
            return Ok(legacy);
        }
        Err(last_error.unwrap_or_else(|| DownlyError::NeedsLogin(Platform::Instagram, "Instagram didn’t share this post without signing in.".into())))
    }

    pub async fn anonymous_product(&self, shortcode: &str, id: &str) -> Result<Option<Value>> {
        let page_url = format!("https://www.instagram.com/p/{shortcode}/");
        let page = http::get(
            &self.client,
            &page_url,
            http::headers(&[
                ("Accept", "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"),
                ("Sec-Fetch-Mode", "navigate"),
                ("Sec-Fetch-Dest", "document"),
                ("Sec-Fetch-Site", "none"),
            ]),
        )
        .await?;
        if let Some(found) = find_product_html(&page.body) {
            return Ok(Some(found));
        }
        let lsd = json::first(r#""LSD",\[\],\{"token":"([^"]+)""#, &page.body, 1)
            .or_else(|| json::first(r#""lsd":"([^"]+)""#, &page.body, 1))
            .or_else(|| json::first(r#"name="lsd" value="([^"]+)""#, &page.body, 1));
        let _ = http::get(&self.client, &format!("https://www.instagram.com/api/v1/web/get_ruling_for_content/?content_type=MEDIA&target_id={id}"), self.api_headers()).await;
        let Some(lsd) = lsd else { return Ok(None) };
        let csrf = {
            use reqwest::cookie::CookieStore;
            let base = url::Url::parse("https://www.instagram.com/").unwrap();
            self.jar
                .cookies(&base)
                .and_then(|h| h.to_str().ok().map(|s| s.to_string()))
                .and_then(|header| header.split("; ").find_map(|p| p.strip_prefix("csrftoken=").map(|s| s.to_string())))
        };
        let variables = format!("{{\"media_id\":\"{id}\"}}");
        let form: Vec<(&str, &str)> = vec![
            ("lsd", lsd.as_str()),
            ("fb_api_caller_class", "RelayModern"),
            ("fb_api_req_friendly_name", "PolarisLoggedOutDesktopWWWPostRootContentQuery"),
            ("server_timestamps", "true"),
            ("variables", variables.as_str()),
            ("doc_id", "27130156389949648"),
        ];
        let body = form
            .iter()
            .map(|(k, v)| format!("{}={}", urlencode(k), urlencode(v)))
            .collect::<Vec<_>>()
            .join("&");
        let mut headers = self.api_headers();
        let mut add = |k: &str, v: &str| {
            if let (Ok(name), Ok(value)) = (reqwest::header::HeaderName::from_bytes(k.as_bytes()), reqwest::header::HeaderValue::from_str(v)) {
                headers.insert(name, value);
            }
        };
        add("Content-Type", "application/x-www-form-urlencoded");
        add("X-FB-LSD", &lsd);
        add("X-FB-Friendly-Name", "PolarisLoggedOutDesktopWWWPostRootContentQuery");
        add("Referer", &page_url);
        if let Some(csrf) = &csrf {
            add("X-CSRFToken", csrf);
        }
        let response = http::post(&self.client, "https://www.instagram.com/api/graphql", headers, body.into_bytes()).await?;
        let value = response.json();
        let media = &value["data"]["xig_polaris_media"]["if_not_gated_logged_out"];
        if json::exists(media) {
            return Ok(Some(media.clone()));
        }
        Ok(find_product(&value))
    }

    fn gallery_from_product(&self, product: &Value, shortcode: &str, url: &str) -> Result<Analysis> {
        let username = json::s(&product["user"]["username"]).or_else(|| json::s(&product["owner"]["username"]));
        let caption = json::s(&product["caption"]["text"]);
        let carousel = json::arr(&product["carousel_media"]);
        let medias: Vec<&Value> = if carousel.is_empty() { vec![product] } else { carousel.iter().collect() };
        let base = sanitize(&format!("{} {shortcode}", username.clone().unwrap_or_else(|| "instagram".into())), 80);
        let mut items = Vec::new();
        for (index, media) in medias.iter().enumerate() {
            let suffix = if medias.len() > 1 { format!(" {}", index + 1) } else { String::new() };
            if let Some(mut item) = item_from(media, &format!("{shortcode}-{index}"), &format!("{base}{suffix}")) {
                if item.kind == GalleryKind::Video {
                    item.ytdlp_url = Some(url.to_string());
                    if medias.len() > 1 {
                        item.playlist_index = Some(index as i64 + 1);
                    }
                }
                items.push(item);
            }
        }
        if items.is_empty() {
            return Err(DownlyError::NothingToDownload);
        }
        let title = title_from(caption, username.as_ref().map(|u| format!("Post by @{u}")).unwrap_or_else(|| "Instagram post".into()));
        let section_title = section_title(&items);
        Ok(Analysis::Gallery {
            summary: MediaSummary {
                title,
                author: username.map(|u| format!("@{u}")),
                thumbnail: items.first().and_then(|i| i.thumbnail.clone().or(Some(i.url.clone()))),
                duration: json::f(&product["video_duration"]),
                platform: Platform::Instagram,
                webpage_url: url.to_string(),
            },
            sections: vec![GallerySection { id: "post".into(), title: section_title, items }],
            folder_name: base,
            is_profile: false,
        })
    }

    async fn embed_legacy(&self, shortcode: &str, url: &str) -> Result<Option<Analysis>> {
        let page = http::get(&self.client, &format!("https://www.instagram.com/p/{shortcode}/embed/captioned/"), http::headers(&[("Accept", "text/html")])).await?;
        if !page.ok() {
            return Ok(None);
        }
        let html = &page.body;
        let mut media: Option<Value> = None;
        if let Some(context) = json::first(r#""contextJSON":"((?:\\.|[^"\\])*)""#, html, 1) {
            let value = json::parse(&json::unescape_json_string(&context));
            if json::exists(&value["gql_data"]["shortcode_media"]) {
                media = Some(value["gql_data"]["shortcode_media"].clone());
            }
        }
        if media.is_none() {
            if let Some(extra) = json::first(r"window\.__additionalDataLoaded\('extra',\s*(\{.*?\})\);", html, 1) {
                let value = json::parse(&extra);
                if json::exists(&value["shortcode_media"]) {
                    media = Some(value["shortcode_media"].clone());
                }
            }
        }
        let base = sanitize(&format!("instagram {shortcode}"), 80);
        let mut items = Vec::new();
        let mut username = None;
        if let Some(media) = &media {
            username = json::s(&media["owner"]["username"]);
            let nodes: Vec<&Value> = json::arr(&media["edge_sidecar_to_children"]["edges"]).iter().map(|e| &e["node"]).collect();
            let all: Vec<&Value> = if nodes.is_empty() { vec![media] } else { nodes };
            for (index, node) in all.iter().enumerate() {
                let suffix = if all.len() > 1 { format!(" {}", index + 1) } else { String::new() };
                let width = json::i(&node["dimensions"]["width"]);
                let height = json::i(&node["dimensions"]["height"]);
                if json::b(&node["is_video"]) == Some(true) {
                    if let Some(video) = json::url(&node["video_url"]) {
                        items.push(GalleryItem {
                            id: format!("{shortcode}-{index}"),
                            kind: GalleryKind::Video,
                            url: video,
                            thumbnail: json::url(&node["display_url"]),
                            width,
                            height,
                            headers: media_headers(),
                            suggested_name: format!("{base}{suffix}"),
                            ytdlp_url: Some(url.to_string()),
                            playlist_index: if all.len() > 1 { Some(index as i64 + 1) } else { None },
                        });
                    }
                } else if let Some(display) = json::url(&node["display_url"]) {
                    items.push(GalleryItem {
                        id: format!("{shortcode}-{index}"),
                        kind: GalleryKind::Photo,
                        url: display.clone(),
                        thumbnail: Some(display),
                        width,
                        height,
                        headers: media_headers(),
                        suggested_name: format!("{base}{suffix}"),
                        ytdlp_url: None,
                        playlist_index: None,
                    });
                }
            }
        }
        if items.is_empty() {
            if let Some(image) = json::first(r#"class="EmbeddedMediaImage"[^>]*src="([^"]+)""#, html, 1).or_else(|| json::first(r#"<img[^>]*class="EmbeddedMediaImage"[^>]*src="([^"]+)""#, html, 1)) {
                let decoded = json::decode_entities(&image);
                items.push(GalleryItem {
                    id: format!("{shortcode}-0"),
                    kind: GalleryKind::Photo,
                    url: decoded.clone(),
                    thumbnail: Some(decoded),
                    width: None,
                    height: None,
                    headers: media_headers(),
                    suggested_name: base.clone(),
                    ytdlp_url: None,
                    playlist_index: None,
                });
            }
        }
        if items.is_empty() {
            return Ok(None);
        }
        let caption = media.as_ref().and_then(|m| json::s(&m["edge_media_to_caption"]["edges"][0]["node"]["text"]));
        let section_title = section_title(&items);
        Ok(Some(Analysis::Gallery {
            summary: MediaSummary {
                title: title_from(caption, username.as_ref().map(|u| format!("Post by @{u}")).unwrap_or_else(|| "Instagram post".into())),
                author: username.map(|u| format!("@{u}")),
                thumbnail: items.first().and_then(|i| i.thumbnail.clone()),
                duration: None,
                platform: Platform::Instagram,
                webpage_url: url.to_string(),
            },
            sections: vec![GallerySection { id: "post".into(), title: section_title, items }],
            folder_name: base,
            is_profile: false,
        }))
    }

    pub async fn profile(&self, username: &str) -> Result<Profile> {
        let mut profile: Option<Profile> = None;
        let mut api_error: Option<DownlyError> = None;
        match self.api(&format!("users/web_profile_info/?username={username}")).await {
            Ok(value) => {
                let user = &value["data"]["user"];
                if let Some(id) = json::s(&user["id"]) {
                    profile = Some(Profile {
                        id,
                        username: json::s(&user["username"]).unwrap_or_else(|| username.to_string()),
                        full_name: json::s(&user["full_name"]),
                        picture: json::url(&user["profile_pic_url_hd"]).or_else(|| json::url(&user["profile_pic_url"])),
                        followers: json::i(&user["edge_followed_by"]["count"]),
                    });
                }
            }
            Err(error) => api_error = Some(error),
        }
        if profile.is_none() {
            match self.profile_from_page(username).await {
                Ok(found) => profile = found,
                Err(error) => api_error = api_error.or(Some(error)),
            }
        }
        let Some(mut resolved) = profile else {
            if let Some(error) = api_error.filter(|e| e.needs_account()) {
                return Err(error);
            }
            return Err(DownlyError::NeedsLogin(Platform::Instagram, format!("Instagram didn’t share @{username}’s profile without signing in.")));
        };
        if self.logged_in() && !resolved.id.is_empty() {
            if let Ok(value) = self.api(&format!("users/{}/info/", resolved.id)).await {
                let user = &value["user"];
                if let Some(hd) = json::url(&user["hd_profile_pic_url_info"]["url"]) {
                    resolved.picture = Some(hd);
                } else if let Some(best) = json::arr(&user["hd_profile_pic_versions"]).iter().max_by_key(|v| json::i(&v["width"]).unwrap_or(0)).and_then(|v| json::url(&v["url"])) {
                    resolved.picture = Some(best);
                }
            }
        }
        Ok(resolved)
    }

    async fn profile_from_page(&self, username: &str) -> Result<Option<Profile>> {
        let page = http::get(&self.client, &format!("https://www.instagram.com/{username}/"), http::headers(&[("Accept", "text/html")])).await?;
        if page.status == 404 {
            return Err(DownlyError::Unavailable(format!("Couldn’t find @{username} on Instagram.")));
        }
        if !page.ok() {
            return Ok(None);
        }
        let html = &page.body;
        let id = json::first(r#""profilePage_(\d+)""#, html, 1)
            .or_else(|| json::first(r#""user_id":"(\d+)""#, html, 1))
            .or_else(|| json::first(r#""id":"(\d+)","username":""#, html, 1))
            .unwrap_or_default();
        let picture = json::first(r#""profile_pic_url_hd":"([^"]+)""#, html, 1)
            .map(|raw| json::unescape_json_string(&raw))
            .or_else(|| json::meta_content("og:image", html));
        if picture.is_none() && id.is_empty() {
            return Ok(None);
        }
        let full_name = json::meta_content("og:title", html).and_then(|t| t.split(" (@").next().map(|s| s.to_string()));
        Ok(Some(Profile { id, username: username.to_string(), full_name, picture, followers: None }))
    }

    pub async fn profile_gallery(&self, username: &str, url: &str) -> Result<Analysis> {
        let profile = self.profile(username).await?;
        let mut sections = Vec::new();
        if let Some(picture) = &profile.picture {
            sections.push(GallerySection {
                id: "pfp".into(),
                title: "Profile picture".into(),
                items: vec![GalleryItem {
                    id: format!("pfp-{}", profile.id),
                    kind: GalleryKind::Photo,
                    url: picture.clone(),
                    thumbnail: Some(picture.clone()),
                    width: None,
                    height: None,
                    headers: media_headers(),
                    suggested_name: sanitize(&format!("{} profile picture", profile.username), 140),
                    ytdlp_url: None,
                    playlist_index: None,
                }],
            });
        }
        if self.logged_in() && !profile.id.is_empty() {
            if let Ok(stories) = self.reel_items(&profile.id, &profile.username).await {
                if !stories.is_empty() {
                    sections.push(GallerySection { id: "stories".into(), title: "Stories".into(), items: stories });
                }
            }
        }
        if sections.is_empty() {
            return Err(DownlyError::NothingToDownload);
        }
        let followers = profile.followers.map(|f| format!(" · {} followers", compact(f))).unwrap_or_default();
        Ok(Analysis::Gallery {
            summary: MediaSummary {
                title: profile.full_name.clone().unwrap_or_else(|| format!("@{}", profile.username)),
                author: Some(format!("@{}{followers}", profile.username)),
                thumbnail: profile.picture.clone(),
                duration: None,
                platform: Platform::Instagram,
                webpage_url: url.to_string(),
            },
            sections,
            folder_name: sanitize(&format!("{} instagram", profile.username), 140),
            is_profile: true,
        })
    }

    pub async fn stories(&self, username: &str, story_id: Option<&str>, url: &str) -> Result<Analysis> {
        if !self.logged_in() {
            return Err(DownlyError::NeedsLogin(Platform::Instagram, "Instagram only shows stories to signed-in people.".into()));
        }
        let profile = self.profile(username).await?;
        let items = self.reel_items(&profile.id, username).await?;
        if items.is_empty() {
            return Err(DownlyError::Unavailable(format!("@{username} has no active stories right now.")));
        }
        let mut sections = Vec::new();
        let matched = story_id.and_then(|sid| items.iter().find(|i| i.id == sid || i.id.starts_with(&format!("{sid}_"))).cloned());
        if let Some(story) = matched {
            let others: Vec<GalleryItem> = items.iter().filter(|i| i.id != story.id).cloned().collect();
            sections.push(GallerySection { id: "story".into(), title: "This story".into(), items: vec![story] });
            if !others.is_empty() {
                sections.push(GallerySection { id: "stories".into(), title: "All stories".into(), items: others });
            }
        } else {
            let title = if items.len() == 1 { "1 story".to_string() } else { format!("{} stories", items.len()) };
            sections.push(GallerySection { id: "stories".into(), title, items: items.clone() });
        }
        Ok(Analysis::Gallery {
            summary: MediaSummary {
                title: format!("Stories by @{username}"),
                author: profile.full_name.clone(),
                thumbnail: profile.picture.clone().or_else(|| items.first().and_then(|i| i.thumbnail.clone())),
                duration: None,
                platform: Platform::Instagram,
                webpage_url: url.to_string(),
            },
            sections,
            folder_name: sanitize(&format!("{username} stories"), 140),
            is_profile: false,
        })
    }

    pub async fn highlight(&self, id: &str, url: &str) -> Result<Analysis> {
        if !self.logged_in() {
            return Err(DownlyError::NeedsLogin(Platform::Instagram, "Instagram only shows highlights to signed-in people.".into()));
        }
        let reel_id = format!("highlight:{id}");
        let value = self.api(&format!("feed/reels_media/?reel_ids={}", urlencode(&reel_id))).await?;
        let reel = if json::exists(&value["reels"][reel_id.as_str()]) { &value["reels"][reel_id.as_str()] } else { &value["reels_media"][0] };
        let username = json::s(&reel["user"]["username"]).unwrap_or_else(|| "instagram".into());
        let title = json::s(&reel["title"]).unwrap_or_else(|| "Highlight".into());
        let items = story_items(json::arr(&reel["items"]), &username);
        if items.is_empty() {
            return Err(DownlyError::NothingToDownload);
        }
        Ok(Analysis::Gallery {
            summary: MediaSummary {
                title: title.clone(),
                author: Some(format!("@{username}")),
                thumbnail: json::url(&reel["cover_media"]["cropped_image_version"]["url"]).or_else(|| items.first().and_then(|i| i.thumbnail.clone())),
                duration: None,
                platform: Platform::Instagram,
                webpage_url: url.to_string(),
            },
            sections: vec![GallerySection { id: "highlight".into(), title: format!("{} items", items.len()), items }],
            folder_name: sanitize(&format!("{username} {title}"), 140),
            is_profile: false,
        })
    }

    async fn reel_items(&self, reel_id: &str, username: &str) -> Result<Vec<GalleryItem>> {
        let value = self.api(&format!("feed/reels_media/?reel_ids={reel_id}")).await?;
        let reel = if json::exists(&value["reels"][reel_id]) { &value["reels"][reel_id] } else { &value["reels_media"][0] };
        Ok(story_items(json::arr(&reel["items"]), username))
    }
}

pub struct Profile {
    pub id: String,
    pub username: String,
    pub full_name: Option<String>,
    pub picture: Option<String>,
    pub followers: Option<i64>,
}

fn section_title(items: &[GalleryItem]) -> String {
    if items.len() == 1 {
        if items[0].kind == GalleryKind::Video { "Video".into() } else { "Photo".into() }
    } else {
        format!("{} items", items.len())
    }
}

fn find_product_html(html: &str) -> Option<Value> {
    for content in json::script_contents(html, r#"type=["']application/json["']"#) {
        if content.contains("image_versions2") || content.contains("video_versions") {
            if let Some(found) = find_product(&json::parse(&content)) {
                return Some(found);
            }
        }
    }
    None
}

fn find_product(value: &Value) -> Option<Value> {
    json::find_object(value, &|map| {
        (map.contains_key("image_versions2") || map.contains_key("carousel_media")) && (map.contains_key("code") || map.contains_key("pk"))
    })
    .cloned()
}

fn area(v: &Value) -> i64 {
    json::i(&v["width"]).unwrap_or(0) * json::i(&v["height"]).unwrap_or(0)
}

pub fn item_from(media: &Value, fallback_id: &str, name: &str) -> Option<GalleryItem> {
    let images = json::arr(&media["image_versions2"]["candidates"]);
    let best_image = images.iter().rev().max_by_key(|v| area(v));
    let original_width = json::i(&media["original_width"]).or_else(|| json::i(&media["dimensions"]["width"]));
    let original_height = json::i(&media["original_height"]).or_else(|| json::i(&media["dimensions"]["height"]));
    let thumbnail = images
        .iter()
        .min_by_key(|v| (json::i(&v["width"]).unwrap_or(0) - 640).abs())
        .and_then(|v| json::url(&v["url"]))
        .or_else(|| best_image.and_then(|v| json::url(&v["url"])));
    let id = json::s(&media["pk"]).or_else(|| json::s(&media["id"])).unwrap_or_else(|| fallback_id.to_string());
    let videos = json::arr(&media["video_versions"]);
    if let Some(best) = videos.iter().rev().max_by_key(|v| area(v)) {
        let url = json::url(&best["url"])?;
        return Some(GalleryItem {
            id,
            kind: GalleryKind::Video,
            url,
            thumbnail,
            width: json::i(&best["width"]).or(original_width),
            height: json::i(&best["height"]).or(original_height),
            headers: media_headers(),
            suggested_name: name.to_string(),
            ytdlp_url: None,
            playlist_index: None,
        });
    }
    if let Some(video) = json::url(&media["video_url"]) {
        return Some(GalleryItem {
            id,
            kind: GalleryKind::Video,
            url: video,
            thumbnail: json::url(&media["display_url"]).or(thumbnail),
            width: json::i(&media["dimensions"]["width"]),
            height: json::i(&media["dimensions"]["height"]),
            headers: media_headers(),
            suggested_name: name.to_string(),
            ytdlp_url: None,
            playlist_index: None,
        });
    }
    if let Some(best) = best_image {
        let url = json::url(&best["url"])?;
        return Some(GalleryItem {
            id,
            kind: GalleryKind::Photo,
            url,
            thumbnail,
            width: json::i(&best["width"]).or(original_width),
            height: json::i(&best["height"]).or(original_height),
            headers: media_headers(),
            suggested_name: name.to_string(),
            ytdlp_url: None,
            playlist_index: None,
        });
    }
    let display = json::url(&media["display_url"])?;
    Some(GalleryItem {
        id,
        kind: GalleryKind::Photo,
        url: display.clone(),
        thumbnail: Some(display),
        width: json::i(&media["dimensions"]["width"]),
        height: json::i(&media["dimensions"]["height"]),
        headers: media_headers(),
        suggested_name: name.to_string(),
        ytdlp_url: None,
        playlist_index: None,
    })
}

fn story_items(raw: &[Value], username: &str) -> Vec<GalleryItem> {
    raw.iter()
        .enumerate()
        .filter_map(|(index, media)| {
            let stamp = json::i(&media["taken_at"]).map(format_stamp).unwrap_or_else(|| format!("{}", index + 1));
            let pk = json::s(&media["pk"]).or_else(|| json::s(&media["id"])).unwrap_or_else(|| index.to_string());
            let mut item = item_from(media, &pk, &sanitize(&format!("{username} story {stamp}"), 140))?;
            item.id = pk;
            Some(item)
        })
        .collect()
}

fn format_stamp(seconds: i64) -> String {
    let days = seconds.div_euclid(86400);
    let secs = seconds.rem_euclid(86400);
    let z = days + 719468;
    let era = z.div_euclid(146097);
    let doe = z - era * 146097;
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    let y = yoe + era * 400 + if m <= 2 { 1 } else { 0 };
    format!("{y:04}-{m:02}-{d:02} {:02}.{:02}", secs / 3600, (secs % 3600) / 60)
}

pub fn compact(value: i64) -> String {
    if value >= 1_000_000 {
        format!("{:.1}M", value as f64 / 1_000_000.0).replace(".0M", "M")
    } else if value >= 10_000 {
        format!("{:.1}K", value as f64 / 1_000.0).replace(".0K", "K")
    } else {
        value.to_string()
    }
}

pub fn urlencode(text: &str) -> String {
    url::form_urlencoded::byte_serialize(text.as_bytes()).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn picks_first_version_when_sizes_are_missing() {
        let media = serde_json::json!({
            "pk": "1",
            "original_width": 1080,
            "original_height": 1920,
            "video_versions": [{"url": "https://cdn.example/best.mp4"}, {"url": "https://cdn.example/low.mp4"}],
            "image_versions2": {"candidates": [{"url": "https://cdn.example/a.jpg", "width": 1080, "height": 1920}]}
        });
        let item = item_from(&media, "x", "name").unwrap();
        assert_eq!(item.url, "https://cdn.example/best.mp4");
        assert_eq!((item.width, item.height), (Some(1080), Some(1920)));
    }

    #[test]
    fn shortcode() {
        assert_eq!(media_id("BQ0eAlwhDrw").as_deref(), Some("1455920561485265648"));
        assert_eq!(media_id("B").as_deref(), Some("1"));
    }

    #[test]
    fn stamps() {
        assert_eq!(format_stamp(0), "1970-01-01 00.00");
        assert_eq!(compact(1_300_000), "1.3M");
    }
}
