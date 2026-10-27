use tauri::menu::{AboutMetadata, Menu, MenuEvent, MenuItem, PredefinedMenuItem, Submenu};
use tauri::{AppHandle, Emitter, Runtime};

pub fn build<R: Runtime>(app: &AppHandle<R>) -> tauri::Result<Menu<R>> {
    let about = PredefinedMenuItem::about(
        app,
        Some("About Downly"),
        Some(AboutMetadata {
            name: Some("Downly".into()),
            version: Some(app.package_info().version.to_string()),
            comments: Some("Download anything, beautifully.".into()),
            ..Default::default()
        }),
    )?;
    let settings = MenuItem::with_id(app, "settings", "Settings…", true, Some("CmdOrCtrl+,"))?;
    let quit = MenuItem::with_id(app, "quit", "Quit Downly", true, Some("CmdOrCtrl+Q"))?;
    let app_menu = Submenu::with_items(
        app,
        "Downly",
        true,
        &[
            &about,
            &PredefinedMenuItem::separator(app)?,
            &settings,
            &PredefinedMenuItem::separator(app)?,
            &PredefinedMenuItem::services(app, None)?,
            &PredefinedMenuItem::separator(app)?,
            &PredefinedMenuItem::hide(app, Some("Hide Downly"))?,
            &PredefinedMenuItem::hide_others(app, None)?,
            &PredefinedMenuItem::show_all(app, None)?,
            &PredefinedMenuItem::separator(app)?,
            &quit,
        ],
    )?;
    let file = Submenu::with_items(
        app,
        "File",
        true,
        &[
            &MenuItem::with_id(app, "new-download", "New Download", true, Some("CmdOrCtrl+N"))?,
            &MenuItem::with_id(app, "paste-link", "Paste Link and Go", true, Some("CmdOrCtrl+Shift+V"))?,
            &PredefinedMenuItem::separator(app)?,
            &MenuItem::with_id(app, "open-folder", "Open Downloads Folder", true, Some("CmdOrCtrl+Shift+D"))?,
            &MenuItem::with_id(app, "clear-finished", "Clear Finished Downloads", true, Some("CmdOrCtrl+Shift+K"))?,
            &PredefinedMenuItem::separator(app)?,
            &PredefinedMenuItem::close_window(app, None)?,
        ],
    )?;
    let edit = Submenu::with_items(
        app,
        "Edit",
        true,
        &[
            &PredefinedMenuItem::undo(app, None)?,
            &PredefinedMenuItem::redo(app, None)?,
            &PredefinedMenuItem::separator(app)?,
            &PredefinedMenuItem::cut(app, None)?,
            &PredefinedMenuItem::copy(app, None)?,
            &PredefinedMenuItem::paste(app, None)?,
            &PredefinedMenuItem::select_all(app, None)?,
        ],
    )?;
    let view = Submenu::with_items(app, "View", true, &[&PredefinedMenuItem::fullscreen(app, None)?])?;
    let window = Submenu::with_items(
        app,
        "Window",
        true,
        &[
            &PredefinedMenuItem::minimize(app, None)?,
            &PredefinedMenuItem::maximize(app, Some("Zoom"))?,
            &PredefinedMenuItem::separator(app)?,
            &MenuItem::with_id(app, "show-main", "Downly", true, Some("CmdOrCtrl+0"))?,
        ],
    )?;
    #[cfg(target_os = "macos")]
    {
        let _ = window.set_as_windows_menu_for_nsapp();
    }
    Menu::with_items(app, &[&app_menu, &file, &edit, &view, &window])
}

pub fn handle(app: &AppHandle, event: MenuEvent) {
    match event.id().as_ref() {
        "settings" => crate::open_settings(app),
        "quit" => crate::request_quit(app),
        "new-download" => {
            crate::show_main(app);
            let _ = app.emit("focus-link", ());
        }
        "paste-link" => {
            crate::show_main(app);
            let _ = app.emit("paste-link", ());
        }
        "open-folder" => crate::open_downloads(app),
        "clear-finished" => crate::queue::clear_finished(app),
        "show-main" => crate::show_main(app),
        _ => {}
    }
}
