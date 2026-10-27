pub mod commands;
pub mod engine;
pub mod menu;
pub mod queue;
pub mod settings;
pub mod state;
pub mod thumbs;

use std::path::Path;
use std::sync::atomic::Ordering;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};
use tauri::{AppHandle, Emitter, Manager, RunEvent, WebviewUrl, WebviewWindowBuilder, WindowEvent};
use tauri_plugin_deep_link::DeepLinkExt;
use tauri_plugin_dialog::{DialogExt, MessageDialogButtons, MessageDialogKind};
use tauri_plugin_notification::NotificationExt;

use engine::paths;
use engine::tools::{PhaseHandler, ToolId, ToolPhase, Toolchain};
use settings::Settings;
use state::{AppState, ToolStatus};

pub fn show_main(app: &AppHandle) {
    if let Some(window) = app.get_webview_window("main") {
        let _ = window.unminimize();
        let _ = window.show();
        let _ = window.set_focus();
    }
}

pub fn open_settings(app: &AppHandle) {
    if let Some(window) = app.get_webview_window("settings") {
        let _ = window.unminimize();
        let _ = window.show();
        let _ = window.set_focus();
        return;
    }
    let builder = WebviewWindowBuilder::new(app, "settings", WebviewUrl::default())
        .title("Settings")
        .inner_size(600.0, 470.0)
        .resizable(false)
        .minimizable(false)
        .maximizable(false)
        .visible(false)
        .center();
    #[cfg(target_os = "macos")]
    let builder = {
        use tauri::utils::config::WindowEffectsConfig;
        use tauri::window::{Effect, EffectState};
        builder
            .title_bar_style(tauri::TitleBarStyle::Overlay)
            .hidden_title(true)
            .transparent(true)
            .effects(WindowEffectsConfig {
                effects: vec![Effect::UnderWindowBackground],
                state: Some(EffectState::FollowsWindowActiveState),
                radius: None,
                color: None,
                interactive: false,
            })
    };
    let _ = builder.build();
}

pub fn open_path(path: &Path, reveal: bool) {
    #[cfg(target_os = "macos")]
    {
        let mut command = std::process::Command::new("/usr/bin/open");
        if reveal {
            command.arg("-R");
        }
        let _ = command.arg(path).spawn();
    }
    #[cfg(not(target_os = "macos"))]
    {
        let target = if reveal { path.parent().unwrap_or(path) } else { path };
        let _ = std::process::Command::new("xdg-open").arg(target).spawn();
    }
}

pub fn open_url(url: &str) {
    #[cfg(target_os = "macos")]
    let _ = std::process::Command::new("/usr/bin/open").arg(url).spawn();
    #[cfg(not(target_os = "macos"))]
    let _ = std::process::Command::new("xdg-open").arg(url).spawn();
}

pub fn open_downloads(app: &AppHandle) {
    let folder = app.state::<AppState>().settings().destination();
    let _ = std::fs::create_dir_all(&folder);
    open_path(&folder, false);
}

pub fn notify(app: &AppHandle, title: &str, body: &str) {
    let state = app.state::<AppState>();
    if !state.settings.read().unwrap().notifications {
        return;
    }
    let focused = app
        .get_webview_window("main")
        .map(|w| w.is_visible().unwrap_or(false) && w.is_focused().unwrap_or(false))
        .unwrap_or(false);
    if focused {
        return;
    }
    let _ = app.notification().builder().title(title).body(body).show();
}

pub fn notify_finished(app: &AppHandle, title: &str, detail: &str) {
    let body = if detail.is_empty() { title.to_string() } else { format!("{title}\n{detail}") };
    notify(app, "Download complete", &body);
}

pub fn request_quit(app: &AppHandle) {
    let state = app.state::<AppState>();
    let active = queue::active_count(app);
    if active == 0 || state.quitting.load(Ordering::SeqCst) {
        state.quitting.store(true, Ordering::SeqCst);
        app.exit(0);
        return;
    }
    show_main(app);
    let message = if active == 1 {
        "A download is still in progress. Quitting now will stop it.".to_string()
    } else {
        format!("{active} downloads are still in progress. Quitting now will stop them.")
    };
    let mut dialog = app
        .dialog()
        .message(message)
        .title("Quit Downly?")
        .kind(MessageDialogKind::Warning)
        .buttons(MessageDialogButtons::OkCancelCustom("Quit".into(), "Keep Downloading".into()));
    if let Some(window) = app.get_webview_window("main") {
        dialog = dialog.parent(&window);
    }
    let handle = app.clone();
    dialog.show(move |confirmed| {
        if confirmed {
            queue::cancel_all(&handle);
            handle.state::<AppState>().quitting.store(true, Ordering::SeqCst);
            handle.exit(0);
        }
    });
}

pub fn emit_setup(app: &AppHandle) {
    let view = app.state::<AppState>().setup.lock().unwrap().clone();
    let _ = app.emit("setup", view);
}

pub fn start_install(app: &AppHandle, tools: Vec<ToolId>) -> bool {
    let state = app.state::<AppState>();
    {
        let mut setup = state.setup.lock().unwrap();
        if setup.running {
            return false;
        }
        setup.running = true;
        setup.error = None;
        setup.tools = tools
            .iter()
            .map(|t| ToolStatus { id: *t, name: t.display_name().to_string(), phase: ToolPhase::Waiting })
            .collect();
    }
    emit_setup(app);
    let app = app.clone();
    tauri::async_runtime::spawn(async move {
        let last = Arc::new(Mutex::new(Instant::now() - Duration::from_secs(1)));
        let handler_app = app.clone();
        let handler: PhaseHandler = Arc::new(move |tool, phase| {
            let urgent = !matches!(phase, ToolPhase::Downloading { .. });
            {
                let state = handler_app.state::<AppState>();
                let mut setup = state.setup.lock().unwrap();
                if let Some(entry) = setup.tools.iter_mut().find(|t| t.id == tool) {
                    entry.phase = phase;
                }
            }
            let mut guard = last.lock().unwrap();
            if urgent || guard.elapsed() >= Duration::from_millis(90) {
                *guard = Instant::now();
                emit_setup(&handler_app);
            }
        });
        let toolchain = app.state::<AppState>().toolchain.clone();
        let result = toolchain.install(tools, handler).await;
        {
            let state = app.state::<AppState>();
            let paths = toolchain.paths();
            let mut setup = state.setup.lock().unwrap();
            setup.running = false;
            setup.ready = paths.is_some();
            setup.versions = toolchain.versions();
            setup.error = result.err().map(|e| e.to_string());
            *state.tools.write().unwrap() = paths;
        }
        emit_setup(&app);
        queue::pump(&app);
    });
    true
}

fn refresh_engine(app: &AppHandle) {
    let state = app.state::<AppState>();
    let paths = state.toolchain.paths();
    {
        let mut setup = state.setup.lock().unwrap();
        setup.ready = paths.is_some();
        setup.versions = state.toolchain.versions();
    }
    if paths.is_some() {
        *state.tools.write().unwrap() = paths;
    }
    emit_setup(app);
}

pub async fn update_engine(app: &AppHandle, force: bool) -> Option<String> {
    let toolchain = app.state::<AppState>().toolchain.clone();
    if queue::active_count(app) > 0 && !force {
        return None;
    }
    let updated = toolchain.update_ytdlp(force).await;
    refresh_engine(app);
    updated
}

fn link_from_deep_link(raw: &str) -> Option<String> {
    let url = url::Url::parse(raw).ok()?;
    if url.scheme() != "downly" {
        return Some(raw.to_string());
    }
    if let Some((_, value)) = url.query_pairs().find(|(k, _)| k == "url") {
        return Some(value.to_string());
    }
    let rest = raw.trim_start_matches("downly://").trim_start_matches("download/");
    let rest = rest.trim_start_matches('/');
    for scheme in ["https", "http"] {
        if let Some(tail) = rest.strip_prefix(&format!("{scheme}//")) {
            return Some(format!("{scheme}://{tail}"));
        }
    }
    if rest.starts_with("http") {
        Some(rest.to_string())
    } else {
        None
    }
}

fn handle_deep_links(app: &AppHandle, urls: Vec<url::Url>) {
    for url in urls {
        if let Some(link) = link_from_deep_link(url.as_str()) {
            show_main(app);
            let _ = app.emit("open-link", link);
            break;
        }
    }
}

pub fn run() {
    paths::clean_staging();
    let settings = Settings::load();
    let toolchain = Arc::new(Toolchain::shared());
    tauri::Builder::default()
        .plugin(tauri_plugin_deep_link::init())
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_notification::init())
        .plugin(tauri_plugin_clipboard_manager::init())
        .manage(AppState::new(settings, toolchain))
        .register_asynchronous_uri_scheme_protocol("thumb", thumbs::handle)
        .menu(menu::build)
        .on_menu_event(menu::handle)
        .setup(|app| {
            let handle = app.handle().clone();
            queue::restore(&handle);
            let deep_handle = handle.clone();
            app.deep_link().on_open_url(move |event| handle_deep_links(&deep_handle, event.urls()));
            if let Ok(Some(urls)) = app.deep_link().get_current() {
                let start_handle = handle.clone();
                tauri::async_runtime::spawn(async move {
                    tokio::time::sleep(Duration::from_millis(900)).await;
                    handle_deep_links(&start_handle, urls);
                });
            }
            let state = handle.state::<AppState>();
            let missing = state.toolchain.missing();
            if !missing.is_empty() {
                start_install(&handle, missing);
            } else if state.settings().auto_update_engine {
                let update_handle = handle.clone();
                tauri::async_runtime::spawn(async move {
                    tokio::time::sleep(Duration::from_secs(4)).await;
                    if update_engine(&update_handle, false).await.is_some() {
                        emit_setup(&update_handle);
                    }
                });
            }
            Ok(())
        })
        .on_window_event(|window, event| {
            if let WindowEvent::CloseRequested { api, .. } = event {
                if window.label() == "main" {
                    let state = window.app_handle().state::<AppState>();
                    if !state.quitting.load(Ordering::SeqCst) {
                        api.prevent_close();
                        let _ = window.hide();
                    }
                }
            }
        })
        .invoke_handler(tauri::generate_handler![
            commands::bootstrap,
            commands::start_setup,
            commands::parse_link,
            commands::quick_preview,
            commands::analyze,
            commands::cancel_analysis,
            commands::enqueue,
            commands::cancel_download,
            commands::retry_download,
            commands::remove_download,
            commands::clear_finished,
            commands::reveal_download,
            commands::open_download,
            commands::open_url,
            commands::copy_text,
            commands::open_downloads_folder,
            commands::get_settings,
            commands::update_settings,
            commands::reset_settings,
            commands::choose_download_folder,
            commands::check_engine_updates,
            commands::reinstall_engine,
            commands::open_tools_folder,
            commands::check_instagram_login,
            commands::installed_browsers,
            commands::read_clipboard_link,
            commands::open_settings_window,
            commands::show_main_window,
        ])
        .build(tauri::generate_context!())
        .expect("error while building Downly")
        .run(|app, event| match event {
            #[cfg(target_os = "macos")]
            RunEvent::Reopen { has_visible_windows, .. } => {
                if !has_visible_windows {
                    show_main(app);
                }
            }
            RunEvent::ExitRequested { api, code, .. } => {
                let state = app.state::<AppState>();
                if code.is_none() && !state.quitting.load(Ordering::SeqCst) && queue::active_count(app) > 0 {
                    api.prevent_exit();
                    request_quit(app);
                }
            }
            RunEvent::Exit => {
                queue::cancel_all(app);
                std::thread::sleep(Duration::from_millis(350));
                paths::clean_staging();
            }
            _ => {}
        });
}

#[cfg(test)]
mod tests {
    use super::link_from_deep_link;

    #[test]
    fn deep_links() {
        assert_eq!(
            link_from_deep_link("downly://download?url=https%3A%2F%2Fyoutu.be%2Fabc").as_deref(),
            Some("https://youtu.be/abc")
        );
        assert_eq!(link_from_deep_link("downly://https://youtu.be/abc").as_deref(), Some("https://youtu.be/abc"));
        assert_eq!(link_from_deep_link("downly://https//youtu.be/abc").as_deref(), Some("https://youtu.be/abc"));
        assert_eq!(link_from_deep_link("downly://settings"), None);
    }
}
