use serde::Serialize;
use std::collections::HashMap;
use tauri::{AppHandle, Emitter, Manager, State, WebviewWindow};
use tauri_plugin_clipboard_manager::ClipboardExt;
use tauri_plugin_dialog::DialogExt;
use tokio_util::sync::CancellationToken;

use crate::engine::analyzer::Analyzer;
use crate::engine::download::DownloadJob;
use crate::engine::error::{DownlyError, Result};
use crate::engine::link::{self, ParsedLink};
use crate::engine::models::{Analysis, CookieBrowser, MediaSummary};
use crate::engine::tools::{self, ToolId};
use crate::engine::{cookies, paths, tiktok};
use crate::queue::{self, ItemView};
use crate::settings::Settings;
use crate::state::{AppState, SetupView};

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Bootstrap {
    settings: Settings,
    setup: SetupView,
    downloads: Vec<ItemView>,
    version: String,
    platform: &'static str,
    apple_silicon: bool,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct BrowserInfo {
    id: CookieBrowser,
    name: &'static str,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct EngineReport {
    updated: Option<String>,
    versions: HashMap<String, String>,
}

fn engine_missing() -> DownlyError {
    DownlyError::ToolMissing("The download engine".into())
}

fn apply_settings(app: &AppHandle, settings: Settings) -> Settings {
    let state = app.state::<AppState>();
    let previous = state.settings();
    settings.save();
    *state.settings.write().unwrap() = settings.clone();
    if previous.cookie_browser != settings.cookie_browser {
        cookies::invalidate();
    }
    let _ = app.emit("settings", &settings);
    queue::pump(app);
    settings
}

#[tauri::command]
pub fn bootstrap(app: AppHandle, state: State<AppState>) -> Bootstrap {
    Bootstrap {
        settings: state.settings(),
        setup: state.setup.lock().unwrap().clone(),
        downloads: queue::snapshot(&app),
        version: app.package_info().version.to_string(),
        platform: std::env::consts::OS,
        apple_silicon: tools::is_apple_silicon(),
    }
}

#[tauri::command]
pub fn start_setup(app: AppHandle, state: State<AppState>) -> bool {
    let missing = state.toolchain.missing();
    if missing.is_empty() {
        crate::emit_setup(&app);
        return false;
    }
    crate::start_install(&app, missing)
}

#[tauri::command]
pub fn parse_link(text: String) -> Option<ParsedLink> {
    link::first_link(&text)
}

#[tauri::command]
pub async fn quick_preview(text: String) -> Option<MediaSummary> {
    let link = link::first_link(&text)?;
    tiktok::quick_preview(&link).await
}

#[tauri::command]
pub async fn analyze(app: AppHandle, text: String) -> Result<Analysis> {
    let link = link::first_link(&text).ok_or(DownlyError::UnsupportedLink)?;
    let state = app.state::<AppState>();
    let tools = state.current_tools().ok_or_else(engine_missing)?;
    let settings = state.settings();
    let token = CancellationToken::new();
    let previous = state.analysis.lock().unwrap().replace(token.clone());
    if let Some(previous) = previous {
        previous.cancel();
    }
    let analyzer = Analyzer {
        tools,
        settings: settings.engine(),
        apple_compatible: settings.apple_compatible,
        prefer_hdr: settings.prefer_hdr,
    };
    tokio::select! {
        result = analyzer.analyze(link, &token) => result,
        _ = token.cancelled() => Err(DownlyError::Cancelled),
    }
}

#[tauri::command]
pub fn cancel_analysis(state: State<AppState>) {
    let token = state.analysis.lock().unwrap().take();
    if let Some(token) = token {
        token.cancel();
    }
}

#[tauri::command]
pub fn enqueue(app: AppHandle, jobs: Vec<DownloadJob>) {
    queue::add(&app, jobs);
}

#[tauri::command]
pub fn cancel_download(app: AppHandle, id: String) {
    queue::cancel(&app, &id);
}

#[tauri::command]
pub fn retry_download(app: AppHandle, id: String) {
    queue::retry(&app, &id);
}

#[tauri::command]
pub fn remove_download(app: AppHandle, id: String) {
    queue::remove(&app, &id);
}

#[tauri::command]
pub fn clear_finished(app: AppHandle) {
    queue::clear_finished(&app);
}

#[tauri::command]
pub fn reveal_download(app: AppHandle, id: String) {
    let Some(view) = queue::find(&app, &id) else { return };
    let (files, reveal) = queue::targets(&view);
    match (files.as_slice(), reveal) {
        ([single], _) => crate::open_path(single, true),
        (_, Some(reveal)) => crate::open_path(&reveal, true),
        ([first, ..], None) => crate::open_path(first, true),
        _ => crate::open_downloads(&app),
    }
}

#[tauri::command]
pub fn open_download(app: AppHandle, id: String) {
    let Some(view) = queue::find(&app, &id) else { return };
    let (files, reveal) = queue::targets(&view);
    match (files.as_slice(), reveal) {
        ([single], _) => crate::open_path(single, false),
        (_, Some(reveal)) if reveal.is_dir() => crate::open_path(&reveal, false),
        (_, Some(reveal)) => crate::open_path(&reveal, true),
        ([first, ..], None) => crate::open_path(first, true),
        _ => crate::open_downloads(&app),
    }
}

#[tauri::command]
pub fn open_url(url: String) {
    let allowed = ["https://", "http://", "x-apple.systempreferences:"];
    if allowed.iter().any(|prefix| url.starts_with(prefix)) {
        crate::open_url(&url);
    }
}

#[tauri::command]
pub fn copy_text(app: AppHandle, text: String) {
    let _ = app.clipboard().write_text(text);
}

#[tauri::command]
pub fn open_downloads_folder(app: AppHandle) {
    crate::open_downloads(&app);
}

#[tauri::command]
pub fn get_settings(state: State<AppState>) -> Settings {
    state.settings()
}

#[tauri::command]
pub fn update_settings(app: AppHandle, settings: Settings) -> Settings {
    apply_settings(&app, settings)
}

#[tauri::command]
pub fn reset_settings(app: AppHandle) -> Settings {
    apply_settings(&app, Settings::default())
}

#[tauri::command]
pub async fn choose_download_folder(app: AppHandle, window: WebviewWindow) -> Option<Settings> {
    let current = app.state::<AppState>().settings();
    let (sender, receiver) = tokio::sync::oneshot::channel();
    app.dialog()
        .file()
        .set_title("Choose Download Folder")
        .set_directory(current.destination())
        .set_parent(&window)
        .pick_folder(move |picked| {
            let _ = sender.send(picked);
        });
    let picked = receiver.await.ok().flatten()?;
    let path = picked.into_path().ok()?;
    let mut settings = current;
    settings.download_folder = path.to_string_lossy().to_string();
    Some(apply_settings(&app, settings))
}

#[tauri::command]
pub async fn check_engine_updates(app: AppHandle) -> Result<EngineReport> {
    if queue::active_count(&app) > 0 {
        return Err(DownlyError::Message("Let your downloads finish first, then check again.".into()));
    }
    if app.state::<AppState>().current_tools().is_none() {
        return Err(engine_missing());
    }
    let updated = crate::update_engine(&app, true).await;
    let versions = app.state::<AppState>().toolchain.versions();
    Ok(EngineReport { updated, versions })
}

#[tauri::command]
pub fn reinstall_engine(app: AppHandle) -> Result<bool> {
    if queue::active_count(&app) > 0 {
        return Err(DownlyError::Message("Let your downloads finish first, then try again.".into()));
    }
    Ok(crate::start_install(&app, ToolId::ALL.to_vec()))
}

#[tauri::command]
pub fn open_tools_folder() {
    let folder = paths::tools_dir();
    let _ = std::fs::create_dir_all(&folder);
    crate::open_path(&folder, false);
}

#[tauri::command]
pub async fn check_instagram_login(app: AppHandle, browser: CookieBrowser) -> Result<bool> {
    let tools = app.state::<AppState>().current_tools().ok_or_else(engine_missing)?;
    let snapshot = cookies::snapshot(browser, &tools, true).await?;
    Ok(snapshot.value("sessionid", "instagram.com").is_some())
}

#[tauri::command]
pub fn installed_browsers() -> Vec<BrowserInfo> {
    CookieBrowser::ALL
        .iter()
        .filter(|b| b.is_installed())
        .map(|b| BrowserInfo { id: *b, name: b.display_name() })
        .collect()
}

#[cfg(target_os = "macos")]
fn pasteboard_change_count() -> Option<i64> {
    Some(objc2_app_kit::NSPasteboard::generalPasteboard().changeCount() as i64)
}

#[cfg(not(target_os = "macos"))]
fn pasteboard_change_count() -> Option<i64> {
    None
}

#[tauri::command]
pub fn read_clipboard_link(app: AppHandle, force: Option<bool>) -> Option<ParsedLink> {
    let state = app.state::<AppState>();
    let force = force.unwrap_or(false);
    if !force && !state.settings().watch_clipboard {
        return None;
    }
    if let Some(count) = pasteboard_change_count() {
        let mut memory = state.clipboard.lock().unwrap();
        if !force && memory.change_count == Some(count) {
            return None;
        }
        memory.change_count = Some(count);
    }
    let text = app.clipboard().read_text().ok()?;
    if text.len() > 2000 {
        return None;
    }
    let link = link::first_link(&text)?;
    if !force && link.platform == crate::engine::link::Platform::Web {
        return None;
    }
    let mut memory = state.clipboard.lock().unwrap();
    if !force && memory.last_text == link.url {
        return None;
    }
    memory.last_text = link.url.clone();
    Some(link)
}

#[tauri::command]
pub fn open_settings_window(app: AppHandle) {
    crate::open_settings(&app);
}

#[tauri::command]
pub fn show_main_window(app: AppHandle) {
    crate::show_main(&app);
}
