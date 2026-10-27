use serde::Serialize;
use std::collections::HashMap;
use std::sync::atomic::AtomicBool;
use std::sync::{Arc, Mutex, RwLock};
use tokio_util::sync::CancellationToken;

use crate::engine::tools::{ToolId, ToolPaths, ToolPhase, Toolchain};
use crate::queue::Item;
use crate::settings::Settings;

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ToolStatus {
    pub id: ToolId,
    pub name: String,
    pub phase: ToolPhase,
}

#[derive(Debug, Clone, Serialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct SetupView {
    pub ready: bool,
    pub running: bool,
    pub tools: Vec<ToolStatus>,
    pub error: Option<String>,
    pub versions: HashMap<String, String>,
}

pub struct AppState {
    pub settings: RwLock<Settings>,
    pub toolchain: Arc<Toolchain>,
    pub tools: RwLock<Option<ToolPaths>>,
    pub queue: Mutex<Vec<Item>>,
    pub analysis: Mutex<Option<CancellationToken>>,
    pub setup: Mutex<SetupView>,
    pub quitting: AtomicBool,
    pub clipboard: Mutex<ClipboardMemory>,
}

#[derive(Default)]
pub struct ClipboardMemory {
    pub change_count: Option<i64>,
    pub last_text: String,
}

impl AppState {
    pub fn new(settings: Settings, toolchain: Arc<Toolchain>) -> Self {
        let tools = toolchain.paths();
        let setup = SetupView {
            ready: tools.is_some(),
            running: false,
            tools: vec![],
            error: None,
            versions: toolchain.versions(),
        };
        AppState {
            settings: RwLock::new(settings),
            toolchain,
            tools: RwLock::new(tools),
            queue: Mutex::new(Vec::new()),
            analysis: Mutex::new(None),
            setup: Mutex::new(setup),
            quitting: AtomicBool::new(false),
            clipboard: Mutex::new(ClipboardMemory::default()),
        }
    }

    pub fn current_tools(&self) -> Option<ToolPaths> {
        self.tools.read().unwrap().clone()
    }

    pub fn settings(&self) -> Settings {
        self.settings.read().unwrap().clone()
    }
}
