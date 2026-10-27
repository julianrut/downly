use std::future::Future;
use std::sync::{Arc, Mutex};
use std::time::Instant;
use tokio_util::sync::CancellationToken;

use downly_lib::engine::analyzer::Analyzer;
use downly_lib::engine::download::{Context, DownloadJob, Engine, JobKind, JobProgress};
use downly_lib::engine::error::{DownlyError, Result};
use downly_lib::engine::instagram;
use downly_lib::engine::link::{self, LinkKind, Platform};
use downly_lib::engine::media::{self, Tags};
use downly_lib::engine::models::{Analysis, AudioFormat, EngineSettings, FilenameStyle, VideoContainer};
use downly_lib::engine::process;
use downly_lib::engine::tools::{ToolPaths, ToolPhase, Toolchain};
use downly_lib::engine::{http, spotify, ytdlp::Ytdlp, ytmusic};

static FAILURES: Mutex<Vec<String>> = Mutex::new(Vec::new());
static WARNINGS: Mutex<Vec<String>> = Mutex::new(Vec::new());

fn check(name: &str, condition: bool) {
    if condition {
        println!("✓ {name}");
    } else {
        println!("✗ {name}");
        FAILURES.lock().unwrap().push(name.to_string());
    }
}

async fn soft<F: Future<Output = Result<()>>>(name: &str, body: F) {
    let start = Instant::now();
    match body.await {
        Ok(()) => println!("✓ {name} ({:.1}s)", start.elapsed().as_secs_f64()),
        Err(error) => {
            println!("⚠︎ {name} failed ({:.1}s): {error}", start.elapsed().as_secs_f64());
            WARNINGS.lock().unwrap().push(format!("{name}: {error}"));
        }
    }
}

async fn hard<F: Future<Output = Result<()>>>(name: &str, body: F) {
    let start = Instant::now();
    match body.await {
        Ok(()) => println!("✓ {name} ({:.1}s)", start.elapsed().as_secs_f64()),
        Err(error) => {
            println!("✗ {name} failed ({:.1}s): {error}", start.elapsed().as_secs_f64());
            FAILURES.lock().unwrap().push(format!("{name}: {error}"));
        }
    }
}

fn fail(message: &str) -> DownlyError {
    DownlyError::Message(message.to_string())
}

fn quiet(_: JobProgress) {}

fn video_job(title: &str, platform: Platform, url: &str, selector: &str) -> DownloadJob {
    DownloadJob {
        id: uuid::Uuid::new_v4().to_string(),
        title: title.to_string(),
        subtitle: String::new(),
        detail: String::new(),
        thumbnail: None,
        platform,
        kind: JobKind::Video {
            url: url.to_string(),
            selector: selector.to_string(),
            sort: None,
            container: VideoContainer::Mp4,
            apple_compatible: true,
            expected_sizes: Default::default(),
        },
    }
}

async fn describe(tools: &ToolPaths, file: &std::path::Path) -> Result<()> {
    let info = media::probe(tools, file).await.ok_or_else(|| fail("probe failed"))?;
    let size = std::fs::metadata(file).map(|m| m.len()).unwrap_or(0);
    println!(
        "  {} {} KB video={}/{} audio={} {}x{}",
        file.file_name().unwrap_or_default().to_string_lossy(),
        size / 1024,
        info.video_codec.as_deref().unwrap_or("-"),
        info.video_tag.as_deref().unwrap_or("-"),
        info.audio_codec.as_deref().unwrap_or("-"),
        info.width.unwrap_or(0),
        info.height.unwrap_or(0)
    );
    if info.video_codec.is_some() && info.audio_codec.is_none() {
        return Err(fail("NO AUDIO STREAM"));
    }
    Ok(())
}

#[tokio::main]
async fn main() {
    let args: Vec<String> = std::env::args().collect();
    let network = !args.iter().any(|a| a == "--offline");
    let downloads = args.iter().any(|a| a == "--downloads");
    println!("== Downly self-test ==");

    let kind = |raw: &str| link::parse(raw).map(|l| l.kind);
    check("Link: YouTube", kind("https://youtu.be/dQw4w9WgXcQ?t=3") == Some(LinkKind::YoutubeVideo { id: "dQw4w9WgXcQ".into() }));
    check("Link: Shorts", kind("https://www.youtube.com/shorts/abc123XYZ00") == Some(LinkKind::YoutubeVideo { id: "abc123XYZ00".into() }));
    check("Link: Spotify", kind("https://open.spotify.com/intl-de/track/4cOdK2wGLETKBW3PvgPWqT?si=x") == Some(LinkKind::SpotifyTrack { id: "4cOdK2wGLETKBW3PvgPWqT".into() }));
    check("Link: Instagram reel", kind("instagram.com/reel/C9xYz123abc/?igsh=1") == Some(LinkKind::InstagramPost { shortcode: "C9xYz123abc".into() }));
    check("Link: Instagram profile", kind("https://www.instagram.com/natgeo/") == Some(LinkKind::InstagramProfile { username: "natgeo".into() }));
    check("Link: TikTok photo", kind("https://www.tiktok.com/@user/photo/7300000000000000000") == Some(LinkKind::TiktokPhoto { id: "7300000000000000000".into() }));
    check("Instagram shortcode decoding", instagram::media_id("B").as_deref() == Some("1"));

    if !network {
        finish();
    }

    println!("\n-- Installing components --");
    let started = Instant::now();
    let toolchain = Toolchain::shared();
    let missing = toolchain.missing();
    let tools = if missing.is_empty() {
        toolchain.paths()
    } else {
        let handler = Arc::new(|tool: downly_lib::engine::tools::ToolId, phase: ToolPhase| match phase {
            ToolPhase::Ready { version } => println!("  {} ready: {version}", tool.display_name()),
            ToolPhase::Failed { message } => println!("  {} FAILED: {message}", tool.display_name()),
            _ => {}
        });
        match toolchain.install(missing, handler).await {
            Ok(paths) => Some(paths),
            Err(error) => {
                FAILURES.lock().unwrap().push(format!("Toolchain install: {error}"));
                None
            }
        }
    };
    let Some(tools) = tools else { finish() };
    println!("  installed in {:.1}s", started.elapsed().as_secs_f64());
    let mut versions: Vec<_> = toolchain.versions().into_iter().collect();
    versions.sort();
    for (tool, version) in versions {
        println!("  {tool}: {version}");
    }
    let encoders = media::encoders(&tools.ffmpeg).await;
    println!(
        "  encoders: hevc_videotoolbox={} h264_videotoolbox={} libx264={} libmp3lame={} libopus={} aac={}",
        encoders.contains("hevc_videotoolbox"),
        encoders.contains("h264_videotoolbox"),
        encoders.contains("libx264"),
        encoders.contains("libmp3lame"),
        encoders.contains("libopus"),
        encoders.contains("aac")
    );
    match toolchain.latest_ytdlp_version().await {
        Some(latest) => println!("  latest yt-dlp release: {latest}"),
        None => WARNINGS.lock().unwrap().push("Could not read latest yt-dlp version".into()),
    }

    let analyzer = Analyzer { tools: tools.clone(), settings: EngineSettings::default(), apple_compatible: true, prefer_hdr: false };
    let cancel = CancellationToken::new();

    println!("\n-- Spotify --");
    soft("Spotify track + YouTube Music match", async {
        let Analysis::Music { tracks, .. } = spotify::fetch("track", "4cOdK2wGLETKBW3PvgPWqT").await? else { return Err(fail("not music")) };
        let track = tracks.first().ok_or_else(|| fail("no track"))?;
        println!("  {} — {} | album: {} | {:?}ms | cover: {}", track.title, track.artist_line(), track.album.as_deref().unwrap_or("-"), track.duration_ms, track.cover.as_deref().unwrap_or("-"));
        if track.artists.is_empty() || track.duration_ms.is_none() {
            return Err(fail("missing fields"));
        }
        let ytdlp = Ytdlp::new(tools.clone(), None);
        let (candidate, score) = ytmusic::resolve(track, Some(&ytdlp)).await?;
        println!("  match: {} — {} [{}] score {score:.2} dur {:?}", candidate.title, candidate.artists.join(", "), candidate.video_id, candidate.duration);
        Ok(())
    })
    .await;
    soft("Spotify album", async {
        let Analysis::Music { summary, tracks, .. } = spotify::fetch("album", "4aawyAB9vmqN3uQ7FjRGTy").await? else { return Err(fail("not music")) };
        println!("  {} by {}: {} tracks", summary.title, summary.author.as_deref().unwrap_or("-"), tracks.len());
        if tracks.is_empty() {
            return Err(fail("no tracks"));
        }
        Ok(())
    })
    .await;
    soft("Spotify playlist", async {
        let Analysis::Music { summary, tracks, .. } = spotify::fetch("playlist", "37i9dQZF1DXcBWIGoYBM5M").await? else { return Err(fail("not music")) };
        println!("  {}: {} tracks", summary.title, tracks.len());
        Ok(())
    })
    .await;
    soft("YouTube Music search", async {
        let results = ytmusic::search("Daft Punk Get Lucky", true).await?;
        for item in results.iter().take(3) {
            println!("  {} — {} | {:?}s | song={} [{}]", item.title, item.artists.join(", "), item.duration, item.is_song, item.video_id);
        }
        if results.is_empty() {
            return Err(fail("no results"));
        }
        Ok(())
    })
    .await;

    println!("\n-- YouTube --");
    soft("YouTube analysis", async {
        let link = link::parse("https://www.youtube.com/watch?v=aqz-KE-bpKQ").unwrap();
        let Analysis::Video { summary, mp4_choices, mkv_choices, .. } = analyzer.analyze(link, &cancel).await? else { return Err(fail("not a video")) };
        println!("  {} | {}", summary.title, summary.author.as_deref().unwrap_or("-"));
        for (name, choices) in [("mp4", &mp4_choices), ("mkv", &mkv_choices)] {
            let text: Vec<String> = choices.iter().map(|c| format!("{}[{}{}]", c.label, c.codec, if c.needs_transcode { "*" } else { "" })).collect();
            println!("  {name}: {}", text.join(" "));
        }
        if mp4_choices.iter().any(|c| c.audio_id.is_none() && !c.muxed) {
            return Err(fail("a choice has no audio"));
        }
        Ok(())
    })
    .await;

    println!("\n-- TikTok --");
    soft("TikTok analysis", async {
        let link = link::parse("https://www.tiktok.com/@scout2015/video/6718335390845095173").unwrap();
        match analyzer.analyze(link, &cancel).await? {
            Analysis::Video { summary, mp4_choices, .. } => {
                let text: Vec<String> = mp4_choices.iter().map(|c| format!("{}[{}]", c.label, c.codec)).collect();
                println!("  {} | {} | {}", summary.title.chars().take(60).collect::<String>(), summary.author.as_deref().unwrap_or("-"), text.join(" "));
            }
            Analysis::Gallery { sections, .. } => println!("  gallery: {} sections", sections.len()),
            _ => println!("  other analysis"),
        }
        Ok(())
    })
    .await;

    println!("\n-- Instagram --");
    soft("Instagram post (anonymous)", async {
        let link = link::parse("https://www.instagram.com/p/BQ0eAlwhDrw/").unwrap();
        match analyzer.analyze(link, &cancel).await? {
            Analysis::Gallery { summary, sections, .. } => {
                let items: Vec<String> = sections.iter().flat_map(|s| s.items.iter()).map(|i| format!("{:?} {}x{}", i.kind, i.width.unwrap_or(0), i.height.unwrap_or(0))).collect();
                println!("  {} | {} | {}", summary.title.chars().take(60).collect::<String>(), summary.author.as_deref().unwrap_or("-"), items.join(", "));
            }
            Analysis::Video { summary, .. } => println!("  video via yt-dlp: {}", summary.title.chars().take(60).collect::<String>()),
            _ => println!("  other analysis"),
        }
        Ok(())
    })
    .await;

    if downloads {
        println!("\n-- Downloads --");
        let destination = std::env::temp_dir().join(format!("downly-selftest-{}", uuid::Uuid::new_v4()));
        let engine = Engine::new(Context {
            tools: tools.clone(),
            settings: EngineSettings::default(),
            destination: destination.clone(),
            embed_metadata: true,
            filename_style: FilenameStyle::Title,
        });
        let tiktok_url = "https://www.tiktok.com/@scout2015/video/6718335390845095173";

        soft("Download TikTok video with sound", async {
            let Analysis::Video { summary, source_url, mp4_choices, .. } = analyzer.analyze(link::parse(tiktok_url).unwrap(), &cancel).await? else { return Err(fail("not a video")) };
            let choice = mp4_choices.first().ok_or_else(|| fail("no choices"))?;
            let output = engine.run(&video_job(&summary.title, Platform::Tiktok, &source_url, &choice.selector), &cancel, &quiet).await?;
            describe(&tools, &output.files[0]).await
        })
        .await;

        soft("Extract TikTok sound as MP3", async {
            let Analysis::Video { summary, source_url, .. } = analyzer.analyze(link::parse(tiktok_url).unwrap(), &cancel).await? else { return Err(fail("not a video")) };
            let mut job = video_job(&summary.title, Platform::Tiktok, &source_url, "");
            job.kind = JobKind::Audio { url: source_url.clone(), format: AudioFormat::Mp3, square_cover: true };
            let output = engine.run(&job, &cancel, &quiet).await?;
            let file = output.files[0].to_string_lossy().to_string();
            let result = process::run(&tools.ffprobe, &process::strings(&["-v", "quiet", "-show_entries", "stream=codec_name,codec_type:format_tags=title,artist", "-of", "compact", &file]), None, None).await?;
            println!("  {} | {}", output.files[0].file_name().unwrap_or_default().to_string_lossy(), result.stdout.lines().collect::<Vec<_>>().join(" | "));
            Ok(())
        })
        .await;

        hard("Tag MP3 with Spotify cover & metadata", async {
            let work = std::env::temp_dir().join(format!("downly-tag-{}", uuid::Uuid::new_v4()));
            std::fs::create_dir_all(&work)?;
            let source = work.join("raw.mp3");
            let generated = process::run(&tools.ffmpeg, &process::strings(&["-hide_banner", "-y", "-f", "lavfi", "-i", "sine=frequency=440:duration=4", "-c:a", "libmp3lame", "-b:a", "192k", &source.to_string_lossy()]), None, None).await?;
            if generated.status != 0 {
                return Err(fail("ffmpeg sine failed"));
            }
            let mut cover_file = None;
            let mut tags = Tags { title: "Test Tone".into(), artist: "Downly".into(), album_artist: Some("Downly".into()), album: Some("Self Test".into()), date: Some("2026".into()), track: Some("1".into()) };
            if let Ok(Analysis::Music { tracks, .. }) = spotify::fetch("track", "4cOdK2wGLETKBW3PvgPWqT").await {
                if let Some(track) = tracks.first() {
                    let track = spotify::enrich(track).await;
                    tags = Tags {
                        title: track.title.clone(),
                        artist: track.artist_line(),
                        album_artist: track.artists.first().cloned(),
                        album: track.album.clone(),
                        date: track.release_date.as_ref().map(|d| d.chars().take(10).collect()),
                        track: Some("1".into()),
                    };
                    if let Some(url) = &track.cover {
                        let target = work.join("cover.jpg");
                        let noop = |_: u64, _: Option<u64>| {};
                        if http::download_file(url, &target, Default::default(), &cancel, &noop).await.is_ok() {
                            cover_file = Some(target);
                        }
                    }
                }
            }
            if cover_file.is_none() {
                let target = work.join("cover.jpg");
                process::run(&tools.ffmpeg, &process::strings(&["-hide_banner", "-y", "-f", "lavfi", "-i", "color=c=violet:s=600x600", "-frames:v", "1", &target.to_string_lossy()]), None, None).await?;
                cover_file = Some(target);
            }
            let tagged = media::tag_audio(&tools, &source, &tags, cover_file.as_deref(), &format!("{} - {}", tags.artist, tags.title)).await?;
            let file = tagged.to_string_lossy().to_string();
            let result = process::run(&tools.ffprobe, &process::strings(&["-v", "quiet", "-show_entries", "stream=codec_name,codec_type:stream_disposition=attached_pic:format_tags", "-of", "compact", &file]), None, None).await?;
            println!("  {} | {}", tagged.file_name().unwrap_or_default().to_string_lossy(), result.stdout.lines().collect::<Vec<_>>().join(" | "));
            let _ = std::fs::remove_dir_all(&work);
            if !result.stdout.contains("attached_pic=1") {
                return Err(fail("cover not embedded"));
            }
            Ok(())
        })
        .await;

        hard("Convert VP9 to QuickTime-ready HEVC", async {
            let work = std::env::temp_dir().join(format!("downly-vp9-{}", uuid::Uuid::new_v4()));
            std::fs::create_dir_all(&work)?;
            let source = work.join("clip.webm");
            let generated = process::run(
                &tools.ffmpeg,
                &process::strings(&[
                    "-hide_banner", "-y", "-f", "lavfi", "-i", "testsrc2=size=1920x1080:rate=30", "-f", "lavfi", "-i", "sine=frequency=330:sample_rate=48000", "-t", "4", "-c:v", "libvpx-vp9", "-b:v", "2M", "-deadline", "realtime", "-cpu-used", "8", "-c:a", "libopus", "-shortest",
                    &source.to_string_lossy(),
                ]),
                None,
                None,
            )
            .await?;
            if generated.status != 0 {
                return Err(fail(&format!("ffmpeg vp9 failed: {}", generated.stderr.chars().rev().take(300).collect::<String>().chars().rev().collect::<String>())));
            }
            let start = Instant::now();
            let noop = |_: f64| {};
            let converted = media::make_apple_compatible(&tools, &source, &cancel, &noop).await?;
            let info = media::probe(&tools, &converted).await.ok_or_else(|| fail("probe failed"))?;
            println!(
                "  converted in {:.1}s → video={}/{} audio={}",
                start.elapsed().as_secs_f64(),
                info.video_codec.as_deref().unwrap_or("-"),
                info.video_tag.as_deref().unwrap_or("-"),
                info.audio_codec.as_deref().unwrap_or("-")
            );
            let _ = std::fs::remove_dir_all(&work);
            let video_ok = matches!(info.video_codec.as_deref(), Some("hevc") | Some("h264"));
            if !video_ok || info.audio_codec.as_deref() != Some("aac") {
                return Err(fail("unexpected codecs"));
            }
            Ok(())
        })
        .await;

        soft("Download Instagram reel with sound", async {
            let link = link::parse("https://www.instagram.com/reel/CDUMkliABpa/").unwrap();
            let job = match analyzer.analyze(link, &cancel).await? {
                Analysis::Gallery { summary, sections, folder_name, .. } => {
                    let mut job = video_job(&summary.title, Platform::Instagram, "", "");
                    job.kind = JobKind::Gallery { items: sections.into_iter().flat_map(|s| s.items).collect(), folder: Some(folder_name) };
                    job
                }
                Analysis::Video { summary, source_url, mp4_choices, .. } => {
                    let selector = mp4_choices.first().map(|c| c.selector.clone()).unwrap_or_else(|| "bv*+ba/b".into());
                    video_job(&summary.title, Platform::Instagram, &source_url, &selector)
                }
                _ => return Err(fail("unexpected analysis")),
            };
            let output = engine.run(&job, &cancel, &quiet).await?;
            for file in &output.files {
                describe(&tools, file).await?;
            }
            Ok(())
        })
        .await;

        soft("Download YouTube 360p with sound", async {
            let link = link::parse("https://www.youtube.com/watch?v=aqz-KE-bpKQ").unwrap();
            let Analysis::Video { summary, source_url, mp4_choices, .. } = analyzer.analyze(link, &cancel).await? else { return Err(fail("not a video")) };
            let choice = mp4_choices.iter().find(|c| c.tier == 360).or(mp4_choices.last()).ok_or_else(|| fail("no choices"))?;
            let output = engine.run(&video_job(&summary.title, Platform::Youtube, &source_url, &choice.selector), &cancel, &quiet).await?;
            describe(&tools, &output.files[0]).await
        })
        .await;

        let _ = std::fs::remove_dir_all(&destination);
    }
    finish();
}

fn finish() -> ! {
    let failures = FAILURES.lock().unwrap().clone();
    let warnings = WARNINGS.lock().unwrap().clone();
    println!("\n== Summary ==");
    if !warnings.is_empty() {
        println!("{} network checks did not pass (sites can block CI machines):", warnings.len());
        for warning in &warnings {
            println!("  ⚠︎ {warning}");
        }
    }
    if failures.is_empty() {
        println!("All required checks passed.");
        std::process::exit(0);
    }
    println!("{} required checks failed:", failures.len());
    for failure in &failures {
        println!("  ✗ {failure}");
    }
    std::process::exit(1);
}
