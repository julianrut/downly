use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};
use tauri::{AppHandle, Emitter, Manager};
use tokio_util::sync::CancellationToken;

use crate::engine::download::{Context, DownloadJob, Engine, JobProgress, Phase};
use crate::engine::paths;
use crate::state::AppState;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ItemState {
    Queued,
    Running,
    Finished,
    Failed,
    Cancelled,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ItemView {
    pub id: String,
    pub job: DownloadJob,
    pub state: ItemState,
    #[serde(skip_deserializing)]
    pub phase: Option<Phase>,
    pub fraction: Option<f64>,
    pub speed: Option<f64>,
    pub eta: Option<f64>,
    pub downloaded: Option<i64>,
    pub total: Option<i64>,
    pub note: Option<String>,
    pub error: Option<String>,
    pub hint: Option<String>,
    pub files: Vec<String>,
    pub reveal: Option<String>,
    pub finished_at: Option<u64>,
    pub file_size: Option<u64>,
    pub files_exist: bool,
    #[serde(default)]
    pub source_url: Option<String>,
}

pub struct Item {
    pub view: ItemView,
    pub cancel: Option<CancellationToken>,
}

fn now() -> u64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_secs()).unwrap_or(0)
}

fn refresh_files(view: &mut ItemView) {
    let existing: Vec<&String> = view.files.iter().filter(|f| Path::new(f).exists()).collect();
    view.files_exist = !existing.is_empty();
    let size: u64 = existing.iter().filter_map(|f| std::fs::metadata(f).ok()).map(|m| m.len()).sum();
    view.file_size = if size > 0 { Some(size) } else { None };
}

pub fn snapshot(app: &AppHandle) -> Vec<ItemView> {
    let state = app.state::<AppState>();
    let items = state.queue.lock().unwrap();
    items.iter().map(|i| i.view.clone()).collect()
}

pub fn active_count(app: &AppHandle) -> usize {
    let state = app.state::<AppState>();
    let items = state.queue.lock().unwrap();
    items.iter().filter(|i| matches!(i.view.state, ItemState::Queued | ItemState::Running)).count()
}

fn running_count(items: &[Item]) -> usize {
    items.iter().filter(|i| i.view.state == ItemState::Running).count()
}

pub fn broadcast(app: &AppHandle) {
    let _ = app.emit("downloads", snapshot(app));
    update_badge(app);
}

fn emit_item(app: &AppHandle, id: &str) {
    let state = app.state::<AppState>();
    let view = state.queue.lock().unwrap().iter().find(|i| i.view.id == id).map(|i| i.view.clone());
    if let Some(view) = view {
        let _ = app.emit("download", view);
    }
}

fn update_badge(app: &AppHandle) {
    let count = active_count(app);
    if let Some(window) = app.get_webview_window("main") {
        let _ = window.set_badge_count(if count > 0 { Some(count as i64) } else { None });
    }
}

pub fn add(app: &AppHandle, jobs: Vec<DownloadJob>) {
    {
        let state = app.state::<AppState>();
        let mut items = state.queue.lock().unwrap();
        for mut job in jobs.into_iter().rev() {
            if job.id.is_empty() {
                job.id = uuid::Uuid::new_v4().to_string();
            }
            items.insert(
                0,
                Item {
                    view: ItemView {
                        id: job.id.clone(),
                        source_url: job.source_url(),
                        job,
                        state: ItemState::Queued,
                        phase: None,
                        fraction: None,
                        speed: None,
                        eta: None,
                        downloaded: None,
                        total: None,
                        note: None,
                        error: None,
                        hint: None,
                        files: vec![],
                        reveal: None,
                        finished_at: None,
                        file_size: None,
                        files_exist: false,
                    },
                    cancel: None,
                },
            );
        }
    }
    pump(app);
}

pub fn pump(app: &AppHandle) {
    let state = app.state::<AppState>();
    let limit = state.settings.read().unwrap().concurrency();
    let tools = state.tools.read().unwrap().clone();
    let mut to_start: Vec<(String, DownloadJob, CancellationToken)> = Vec::new();
    {
        let mut items = state.queue.lock().unwrap();
        let mut running = running_count(&items);
        let Some(_) = tools.as_ref() else {
            drop(items);
            broadcast(app);
            return;
        };
        for item in items.iter_mut().rev() {
            if running >= limit {
                break;
            }
            if item.view.state == ItemState::Queued {
                let token = CancellationToken::new();
                item.view.state = ItemState::Running;
                item.view.phase = Some(Phase::Preparing { message: "Starting".into() });
                item.view.fraction = None;
                item.view.error = None;
                item.view.hint = None;
                item.cancel = Some(token.clone());
                to_start.push((item.view.id.clone(), item.view.job.clone(), token));
                running += 1;
            }
        }
    }
    broadcast(app);
    let Some(tools) = tools else { return };
    for (id, job, token) in to_start {
        let settings = state.settings.read().unwrap().clone();
        let context = Context {
            tools: tools.clone(),
            settings: settings.engine(),
            destination: settings.destination(),
            embed_metadata: settings.embed_metadata,
            filename_style: settings.filename_style,
        };
        let app = app.clone();
        tauri::async_runtime::spawn(async move {
            let engine = Engine::new(context);
            let last = std::sync::Mutex::new(Instant::now() - Duration::from_secs(1));
            let progress_app = app.clone();
            let progress_id = id.clone();
            let progress = move |update: JobProgress| {
                {
                    let state = progress_app.state::<AppState>();
                    let mut items = state.queue.lock().unwrap();
                    let Some(item) = items.iter_mut().find(|i| i.view.id == progress_id) else { return };
                    if item.view.state != ItemState::Running {
                        return;
                    }
                    let downloading = matches!(update.phase, Phase::Downloading);
                    item.view.phase = Some(update.phase.clone());
                    if update.fraction.is_some() {
                        item.view.fraction = update.fraction;
                    } else if !downloading {
                        item.view.fraction = None;
                    }
                    item.view.speed = update.speed;
                    item.view.eta = update.eta;
                    if update.downloaded.is_some() {
                        item.view.downloaded = update.downloaded;
                    }
                    if update.total.is_some() {
                        item.view.total = update.total;
                    }
                    if update.note.is_some() {
                        item.view.note = update.note.clone();
                    }
                }
                let mut guard = last.lock().unwrap();
                let important = !matches!(update.phase, Phase::Downloading);
                if important || guard.elapsed() >= Duration::from_millis(120) {
                    *guard = Instant::now();
                    emit_item(&progress_app, &progress_id);
                }
            };
            let result = engine.run(&job, &token, &progress).await;
            finish(&app, &id, result);
        });
    }
}

fn finish(app: &AppHandle, id: &str, result: crate::engine::error::Result<crate::engine::download::JobOutput>) {
    let mut notify: Option<(bool, String, String)> = None;
    {
        let state = app.state::<AppState>();
        let mut items = state.queue.lock().unwrap();
        if let Some(item) = items.iter_mut().find(|i| i.view.id == id) {
            item.cancel = None;
            match result {
                Ok(output) => {
                    if item.view.state == ItemState::Running {
                        item.view.state = ItemState::Finished;
                        item.view.files = output.files.iter().map(|f| f.to_string_lossy().to_string()).collect();
                        item.view.reveal = Some(output.reveal.to_string_lossy().to_string());
                        item.view.note = output.note.or(item.view.note.clone());
                        item.view.fraction = Some(1.0);
                        item.view.finished_at = Some(now());
                        item.view.phase = None;
                        refresh_files(&mut item.view);
                        notify = Some((true, item.view.job.title.clone(), item.view.job.detail.clone()));
                    }
                }
                Err(error) => {
                    if error.is_cancelled() || item.view.state == ItemState::Cancelled {
                        item.view.state = ItemState::Cancelled;
                    } else {
                        item.view.state = ItemState::Failed;
                        item.view.error = Some(error.to_string());
                        item.view.hint = error.suggestion();
                        notify = Some((false, item.view.job.title.clone(), error.to_string()));
                    }
                    item.view.phase = None;
                }
            }
        }
    }
    persist(app);
    pump(app);
    match notify {
        Some((true, title, detail)) => crate::notify_finished(app, &title, &detail),
        Some((false, title, message)) => crate::notify(app, "Download failed", &format!("{title}\n{message}")),
        None => {}
    }
}

pub fn cancel(app: &AppHandle, id: &str) {
    {
        let state = app.state::<AppState>();
        let mut items = state.queue.lock().unwrap();
        if let Some(item) = items.iter_mut().find(|i| i.view.id == id) {
            if matches!(item.view.state, ItemState::Queued | ItemState::Running) {
                item.view.state = ItemState::Cancelled;
                item.view.phase = None;
                if let Some(token) = item.cancel.take() {
                    token.cancel();
                }
            }
        }
    }
    pump(app);
}

pub fn cancel_all(app: &AppHandle) {
    let state = app.state::<AppState>();
    let mut items = state.queue.lock().unwrap();
    for item in items.iter_mut() {
        if matches!(item.view.state, ItemState::Queued | ItemState::Running) {
            item.view.state = ItemState::Cancelled;
            if let Some(token) = item.cancel.take() {
                token.cancel();
            }
        }
    }
}

pub fn retry(app: &AppHandle, id: &str) {
    {
        let state = app.state::<AppState>();
        let mut items = state.queue.lock().unwrap();
        if let Some(index) = items.iter().position(|i| i.view.id == id) {
            if matches!(items[index].view.state, ItemState::Queued | ItemState::Running) {
                return;
            }
            let mut item = items.remove(index);
            item.view.state = ItemState::Queued;
            item.view.fraction = None;
            item.view.error = None;
            item.view.hint = None;
            item.view.files = vec![];
            item.view.reveal = None;
            item.view.downloaded = None;
            item.view.total = None;
            items.insert(0, item);
        }
    }
    pump(app);
}

pub fn remove(app: &AppHandle, id: &str) {
    {
        let state = app.state::<AppState>();
        let mut items = state.queue.lock().unwrap();
        if let Some(index) = items.iter().position(|i| i.view.id == id) {
            if let Some(token) = items[index].cancel.take() {
                token.cancel();
            }
            items.remove(index);
        }
    }
    persist(app);
    pump(app);
}

pub fn clear_finished(app: &AppHandle) {
    {
        let state = app.state::<AppState>();
        let mut items = state.queue.lock().unwrap();
        items.retain(|i| matches!(i.view.state, ItemState::Queued | ItemState::Running));
    }
    persist(app);
    broadcast(app);
}

pub fn find(app: &AppHandle, id: &str) -> Option<ItemView> {
    let state = app.state::<AppState>();
    let items = state.queue.lock().unwrap();
    items.iter().find(|i| i.view.id == id).map(|i| i.view.clone())
}

pub fn persist(app: &AppHandle) {
    let records: Vec<ItemView> = snapshot(app).into_iter().filter(|v| v.state == ItemState::Finished).take(300).collect();
    if let Ok(data) = serde_json::to_vec(&records) {
        let _ = std::fs::write(paths::history_file(), data);
    }
}

pub fn restore(app: &AppHandle) {
    let Ok(data) = std::fs::read(paths::history_file()) else { return };
    let Ok(mut records) = serde_json::from_slice::<Vec<ItemView>>(&data) else { return };
    for record in records.iter_mut() {
        refresh_files(record);
    }
    let state = app.state::<AppState>();
    let mut items = state.queue.lock().unwrap();
    *items = records.into_iter().map(|view| Item { view, cancel: None }).collect();
}

pub fn targets(view: &ItemView) -> (Vec<PathBuf>, Option<PathBuf>) {
    let files: Vec<PathBuf> = view.files.iter().map(PathBuf::from).filter(|p| p.exists()).collect();
    let reveal = view.reveal.as_ref().map(PathBuf::from).filter(|p| p.exists());
    (files, reveal)
}
