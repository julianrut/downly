use serde_json::{json, Value};
use std::time::{SystemTime, UNIX_EPOCH};

use super::error::{DownlyError, Result};
use super::http::{self, CHROME};
use super::json as j;
use super::models::SpotifyTrack;
use super::spotify::split_artists;
use super::ytdlp::Ytdlp;

#[derive(Debug, Clone)]
pub struct Candidate {
    pub video_id: String,
    pub title: String,
    pub artists: Vec<String>,
    pub album: Option<String>,
    pub duration: Option<f64>,
    pub is_song: bool,
}

impl Candidate {
    pub fn url(&self) -> String {
        format!("https://www.youtube.com/watch?v={}", self.video_id)
    }
}

const SONGS_PARAMS: &str = "EgWKAQIIAWoKEAoQAxAEEAkQBQ==";
const VIDEOS_PARAMS: &str = "EgWKAQIQAWoKEAoQAxAEEAkQBQ==";

fn client_version() -> String {
    let seconds = SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_secs()).unwrap_or(0).saturating_sub(3 * 86400);
    let days = (seconds / 86400) as i64;
    let (y, m, d) = civil_from_days(days);
    format!("1.{y:04}{m:02}{d:02}.01.00")
}

fn civil_from_days(days: i64) -> (i64, u32, u32) {
    let z = days + 719468;
    let era = if z >= 0 { z } else { z - 146096 } / 146097;
    let doe = (z - era * 146097) as u64;
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    let y = yoe as i64 + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = (doy - (153 * mp + 2) / 5 + 1) as u32;
    let m = if mp < 10 { mp + 3 } else { mp - 9 } as u32;
    (if m <= 2 { y + 1 } else { y }, m, d)
}

pub async fn search(query: &str, songs_only: bool) -> Result<Vec<Candidate>> {
    let version = client_version();
    let body = json!({
        "context": { "client": { "clientName": "WEB_REMIX", "clientVersion": version, "hl": "en", "gl": "US" } },
        "query": query,
        "params": if songs_only { SONGS_PARAMS } else { VIDEOS_PARAMS },
    });
    let page = http::post(
        &CHROME,
        "https://music.youtube.com/youtubei/v1/search?prettyPrint=false",
        http::headers(&[
            ("Content-Type", "application/json"),
            ("Origin", "https://music.youtube.com"),
            ("Referer", "https://music.youtube.com/"),
            ("X-Youtube-Client-Name", "67"),
            ("X-Youtube-Client-Version", &version),
        ]),
        serde_json::to_vec(&body)?,
    )
    .await?;
    if !page.ok() {
        return Err(DownlyError::Http(page.status));
    }
    Ok(parse(&page.json(), songs_only))
}

pub fn parse(value: &Value, default_is_song: bool) -> Vec<Candidate> {
    let mut output: Vec<Candidate> = Vec::new();
    for renderer in j::find_all(value, "musicResponsiveListItemRenderer", 200) {
        if let Some(candidate) = candidate(renderer, default_is_song) {
            if !output.iter().any(|c| c.video_id == candidate.video_id) {
                output.push(candidate);
            }
        }
    }
    output
}

pub fn parse_duration(text: &str) -> Option<f64> {
    let parts: Vec<&str> = text.trim().split(':').collect();
    if parts.len() < 2 || parts.len() > 3 || parts.iter().any(|p| p.is_empty() || !p.chars().all(|c| c.is_ascii_digit())) {
        return None;
    }
    Some(parts.iter().fold(0.0, |acc, p| acc * 60.0 + p.parse::<f64>().unwrap_or(0.0)))
}

fn candidate(renderer: &Value, default_is_song: bool) -> Option<Candidate> {
    let columns: Vec<&Value> = j::arr(&renderer["flexColumns"]).iter().map(|c| &c["musicResponsiveListItemFlexColumnRenderer"]["text"]["runs"]).collect();
    let title_runs = columns.first()?;
    let title = j::s(&title_runs[0]["text"])?;
    let overlay = &renderer["overlay"]["musicItemThumbnailOverlayRenderer"]["content"]["musicPlayButtonRenderer"]["playNavigationEndpoint"]["watchEndpoint"];
    let video_id = j::s(&renderer["playlistItemData"]["videoId"])
        .or_else(|| j::s(&title_runs[0]["navigationEndpoint"]["watchEndpoint"]["videoId"]))
        .or_else(|| j::s(&overlay["videoId"]))?;
    let video_type = j::s(&title_runs[0]["navigationEndpoint"]["watchEndpoint"]["watchEndpointMusicSupportedConfigs"]["watchEndpointMusicConfig"]["musicVideoType"])
        .or_else(|| j::s(&overlay["watchEndpointMusicSupportedConfigs"]["watchEndpointMusicConfig"]["musicVideoType"]));

    let mut runs: Vec<&Value> = Vec::new();
    for column in columns.iter().skip(1) {
        runs.extend(j::arr(column).iter());
    }
    for fixed in j::arr(&renderer["fixedColumns"]) {
        runs.extend(j::arr(&fixed["musicResponsiveListItemFixedColumnRenderer"]["text"]["runs"]).iter());
    }
    let mut artists: Vec<String> = Vec::new();
    let mut album: Option<String> = None;
    let mut duration: Option<f64> = None;
    let mut groups: Vec<String> = Vec::new();
    let mut current = String::new();
    for run in runs {
        let text = j::raw_s(&run["text"]).unwrap_or_default();
        if text.trim() == "•" {
            if !current.is_empty() {
                groups.push(std::mem::take(&mut current));
            }
            continue;
        }
        let page_type = j::s(&run["navigationEndpoint"]["browseEndpoint"]["browseEndpointContextSupportedConfigs"]["browseEndpointContextMusicConfig"]["pageType"]).unwrap_or_default();
        let browse_id = j::s(&run["navigationEndpoint"]["browseEndpoint"]["browseId"]).unwrap_or_default();
        if page_type == "MUSIC_PAGE_TYPE_ARTIST" || page_type == "MUSIC_PAGE_TYPE_USER_CHANNEL" || browse_id.starts_with("UC") {
            artists.push(text.clone());
        } else if page_type == "MUSIC_PAGE_TYPE_ALBUM" || browse_id.starts_with("MPRE") {
            album = Some(text.clone());
        } else if let Some(seconds) = parse_duration(&text) {
            duration = Some(seconds);
        }
        current.push_str(&text);
    }
    if !current.is_empty() {
        groups.push(current);
    }
    let type_words = ["song", "video", "episode", "single", "ep", "album"];
    let plain: Vec<&String> = groups.iter().filter(|g| !type_words.contains(&g.to_lowercase().as_str())).collect();
    if artists.is_empty() {
        if let Some(first) = plain.first() {
            if parse_duration(first).is_none() {
                artists = split_artists(first);
            }
        }
    }
    if duration.is_none() {
        duration = plain.iter().filter_map(|g| parse_duration(g)).last();
    }
    let is_song = match video_type {
        Some(kind) => kind == "MUSIC_VIDEO_TYPE_ATV",
        None => default_is_song || groups.first().map(|g| g.eq_ignore_ascii_case("song")).unwrap_or(false),
    };
    Some(Candidate { video_id, title, artists, album, duration, is_song })
}

const SUSPICIOUS: &[&str] = &[
    "live", "remix", "cover", "karaoke", "instrumental", "acoustic", "sped up", "speed up", "slowed", "reverb", "8d", "nightcore",
    "mashup", "reaction", "tutorial", "lesson", "piano version", "bass boosted", "loop", "1 hour", "extended",
];

fn fold(text: &str) -> String {
    text.chars()
        .map(|c| match c {
            'á' | 'à' | 'â' | 'ä' | 'ã' | 'å' => 'a',
            'é' | 'è' | 'ê' | 'ë' => 'e',
            'í' | 'ì' | 'î' | 'ï' => 'i',
            'ó' | 'ò' | 'ô' | 'ö' | 'õ' | 'ø' => 'o',
            'ú' | 'ù' | 'û' | 'ü' => 'u',
            'ñ' => 'n',
            'ç' => 'c',
            'ý' | 'ÿ' => 'y',
            other => other,
        })
        .collect()
}

pub fn normalize(text: &str) -> String {
    let mut value = fold(&text.to_lowercase());
    value = value.replace('&', " and ");
    let patterns = [
        r"\((feat|ft|with)\.?[^)]*\)",
        r"\[(feat|ft|with)\.?[^\]]*\]",
        r"\b(feat|ft)\.? .*$",
        r"[\(\[](official|lyric|lyrics|audio|video|visualizer|music video|hd|hq|4k|mv|m/v)[^\)\]]*[\)\]]",
        r"\b(official music video|official video|official audio|official lyric video|lyric video|lyrics video|visualizer)\b",
        r"[^\p{L}\p{N} ]",
        r"\s+",
    ];
    for pattern in patterns {
        if let Ok(regex) = regex::Regex::new(pattern) {
            value = regex.replace_all(&value, " ").to_string();
        }
    }
    value.trim().to_string()
}

fn tokens(text: &str) -> std::collections::HashSet<String> {
    normalize(text).split_whitespace().map(|s| s.to_string()).collect()
}

fn levenshtein_ratio(a: &str, b: &str) -> f64 {
    let lhs: Vec<char> = a.chars().collect();
    let rhs: Vec<char> = b.chars().collect();
    if lhs.is_empty() && rhs.is_empty() {
        return 1.0;
    }
    if lhs.is_empty() || rhs.is_empty() {
        return 0.0;
    }
    let mut previous: Vec<usize> = (0..=rhs.len()).collect();
    let mut current = vec![0usize; rhs.len() + 1];
    for i in 1..=lhs.len() {
        current[0] = i;
        for k in 1..=rhs.len() {
            let cost = if lhs[i - 1] == rhs[k - 1] { 0 } else { 1 };
            current[k] = (previous[k] + 1).min(current[k - 1] + 1).min(previous[k - 1] + cost);
        }
        std::mem::swap(&mut previous, &mut current);
    }
    1.0 - previous[rhs.len()] as f64 / lhs.len().max(rhs.len()) as f64
}

pub fn title_score(source: &str, candidate: &str, artists: &[String]) -> f64 {
    let a = normalize(source);
    let mut b = normalize(candidate);
    for artist in artists {
        let name = normalize(artist);
        if !name.is_empty() && b.starts_with(&format!("{name} ")) {
            b = b[name.len() + 1..].to_string();
        }
    }
    let ta: std::collections::HashSet<&str> = a.split_whitespace().collect();
    let tb: std::collections::HashSet<&str> = b.split_whitespace().collect();
    if ta.is_empty() || tb.is_empty() {
        return 0.0;
    }
    let shared = ta.intersection(&tb).count() as f64;
    let containment = shared / ta.len() as f64;
    let jaccard = shared / ta.union(&tb).count() as f64;
    levenshtein_ratio(&a, &b).max(containment * 0.92).max(jaccard)
}

pub fn artist_score(artists: &[String], candidate: &Candidate) -> f64 {
    if artists.is_empty() {
        return 0.5;
    }
    let haystack = normalize(&format!("{} {}", candidate.artists.join(" "), candidate.title));
    let candidate_tokens = tokens(&candidate.artists.join(" "));
    let mut matched = 0.0;
    for (index, artist) in artists.iter().enumerate() {
        let name = normalize(artist);
        if name.is_empty() {
            continue;
        }
        let weight = if index == 0 { 1.0 } else { 0.5 };
        if haystack.contains(&name) {
            matched += weight;
        } else {
            let artist_tokens: std::collections::HashSet<String> = name.split_whitespace().map(|s| s.to_string()).collect();
            let overlap = artist_tokens.intersection(&candidate_tokens).count() as f64 / artist_tokens.len().max(1) as f64;
            if overlap >= 0.5 {
                matched += weight * overlap * 0.8;
            }
        }
    }
    let possible = 1.0 + (artists.len().saturating_sub(1)) as f64 * 0.5;
    let base = matched / possible;
    if haystack.contains(&normalize(&artists[0])) {
        base.max(0.75)
    } else {
        base
    }
}

pub fn duration_score(expected: Option<f64>, actual: Option<f64>) -> f64 {
    match (expected, actual) {
        (Some(e), Some(a)) => {
            let diff = (e - a).abs();
            if diff <= 2.0 {
                1.0
            } else if diff >= 30.0 {
                0.0
            } else {
                1.0 - (diff - 2.0) / 28.0
            }
        }
        _ => 0.5,
    }
}

pub fn penalty(source: &str, candidate: &str) -> f64 {
    let a = normalize(source);
    let b = normalize(candidate);
    let total: f64 = SUSPICIOUS.iter().filter(|w| b.contains(*w) && !a.contains(*w)).count() as f64 * 0.22;
    total.min(0.6)
}

pub fn score(track: &SpotifyTrack, candidate: &Candidate) -> f64 {
    let mut total = title_score(&track.title, &candidate.title, &candidate.artists) * 0.45
        + artist_score(&track.artists, candidate) * 0.3
        + duration_score(track.duration(), candidate.duration) * 0.25;
    total -= penalty(&track.title, &candidate.title);
    if candidate.is_song {
        total += 0.05;
    }
    if let (Some(e), Some(a)) = (track.duration(), candidate.duration) {
        if (e - a).abs() > 60.0 {
            total -= 0.3;
        }
    }
    total
}

pub fn best(track: &SpotifyTrack, candidates: &[Candidate]) -> Option<(Candidate, f64)> {
    candidates
        .iter()
        .map(|c| (c.clone(), score(track, c)))
        .max_by(|a, b| a.1.partial_cmp(&b.1).unwrap_or(std::cmp::Ordering::Equal))
}

pub async fn resolve(track: &SpotifyTrack, ytdlp: Option<&Ytdlp>) -> Result<(Candidate, f64)> {
    let primary = track.artists.first().cloned().unwrap_or_default();
    let mut best_match: Option<(Candidate, f64)> = None;
    let consider = |candidates: Vec<Candidate>, best_match: &mut Option<(Candidate, f64)>| {
        if let Some(found) = best(track, &candidates) {
            if best_match.as_ref().map(|b| found.1 > b.1).unwrap_or(true) {
                *best_match = Some(found);
            }
        }
    };
    for query in [format!("{} {}", track.artists.join(" "), track.title), format!("{primary} - {}", track.title)] {
        if let Ok(candidates) = search(&query, true).await {
            consider(candidates.into_iter().take(8).collect(), &mut best_match);
        }
        if best_match.as_ref().map(|b| b.1 >= 0.82).unwrap_or(false) {
            return Ok(best_match.unwrap());
        }
    }
    if let Ok(candidates) = search(&format!("{primary} {}", track.title), false).await {
        consider(candidates.into_iter().take(6).collect(), &mut best_match);
    }
    if best_match.as_ref().map(|b| b.1 >= 0.62).unwrap_or(false) {
        return Ok(best_match.unwrap());
    }
    if let Some(ytdlp) = ytdlp {
        if let Ok(value) = ytdlp.extract(&format!("ytsearch8:{primary} - {} audio", track.title), true, false, &[], None).await {
            let candidates = j::arr(&value["entries"])
                .iter()
                .filter_map(|entry| {
                    let id = j::s(&entry["id"])?;
                    let title = j::s(&entry["title"])?;
                    let channel = j::s(&entry["channel"]).or_else(|| j::s(&entry["uploader"])).unwrap_or_default();
                    let artist = channel.replace(" - Topic", "").replace("VEVO", "");
                    Some(Candidate {
                        video_id: id,
                        title,
                        artists: if artist.is_empty() { vec![] } else { vec![artist] },
                        album: None,
                        duration: j::f(&entry["duration"]),
                        is_song: channel.ends_with(" - Topic"),
                    })
                })
                .collect();
            consider(candidates, &mut best_match);
        }
    }
    match best_match {
        Some(found) if found.1 >= 0.5 => Ok(found),
        Some(found) => Err(DownlyError::NoMatch(format!("Couldn’t find a confident match for “{}” (closest: “{}”).", track.title, found.0.title))),
        None => Err(DownlyError::NoMatch(format!("Couldn’t find “{}” on YouTube Music.", track.title))),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn matcher_prefers_original() {
        let track = SpotifyTrack {
            id: "1".into(),
            title: "Get Lucky (feat. Pharrell Williams & Nile Rodgers)".into(),
            artists: vec!["Daft Punk".into(), "Pharrell Williams".into(), "Nile Rodgers".into()],
            album: None,
            duration_ms: Some(369_000),
            cover: None,
            release_date: None,
            track_number: None,
            explicit: false,
        };
        let good = Candidate { video_id: "a".into(), title: "Get Lucky (feat. Pharrell Williams & Nile Rodgers)".into(), artists: vec!["Daft Punk".into()], album: None, duration: Some(369.0), is_song: true };
        let live = Candidate { video_id: "b".into(), title: "Get Lucky (Live)".into(), artists: vec!["Daft Punk".into()], album: None, duration: Some(400.0), is_song: true };
        let cover = Candidate { video_id: "c".into(), title: "Get Lucky - Piano Cover".into(), artists: vec!["Some Pianist".into()], album: None, duration: Some(250.0), is_song: false };
        let (winner, score) = best(&track, &[cover, live, good]).unwrap();
        assert_eq!(winner.video_id, "a");
        assert!(score > 0.8);
    }

    #[test]
    fn durations() {
        assert_eq!(parse_duration("3:45"), Some(225.0));
        assert_eq!(parse_duration("1:02:03"), Some(3723.0));
        assert_eq!(parse_duration("1.2M plays"), None);
    }

    #[test]
    fn version_date() {
        assert_eq!(civil_from_days(0), (1970, 1, 1));
        assert_eq!(civil_from_days(20000), (2024, 10, 4));
    }
}
