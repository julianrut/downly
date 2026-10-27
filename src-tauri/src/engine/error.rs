use serde::Serialize;
use std::fmt;

use super::link::Platform;

#[derive(Debug, Clone, PartialEq)]
pub enum DownlyError {
    UnsupportedLink,
    NeedsLogin(Platform, String),
    BotCheck,
    Unavailable(String),
    Network(String),
    Http(u16),
    ToolMissing(String),
    ToolFailed(String),
    NoMatch(String),
    NothingToDownload,
    Cancelled,
    Message(String),
}

pub type Result<T> = std::result::Result<T, DownlyError>;

impl fmt::Display for DownlyError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let text = match self {
            DownlyError::UnsupportedLink => "This link isn’t supported.".to_string(),
            DownlyError::NeedsLogin(platform, detail) => {
                if detail.is_empty() {
                    format!("{} needs you to be signed in for this.", platform.display_name())
                } else {
                    detail.clone()
                }
            }
            DownlyError::BotCheck => "YouTube asked to confirm you’re not a bot.".to_string(),
            DownlyError::Unavailable(detail) => detail.clone(),
            DownlyError::Network(detail) => detail.clone(),
            DownlyError::Http(code) => format!("The server responded with an error ({code})."),
            DownlyError::ToolMissing(name) => format!("{name} isn’t installed yet."),
            DownlyError::ToolFailed(detail) => detail.clone(),
            DownlyError::NoMatch(detail) => detail.clone(),
            DownlyError::NothingToDownload => "There’s nothing downloadable at this link.".to_string(),
            DownlyError::Cancelled => "Cancelled.".to_string(),
            DownlyError::Message(text) => text.clone(),
        };
        f.write_str(&text)
    }
}

impl std::error::Error for DownlyError {}

impl DownlyError {
    pub fn suggestion(&self) -> Option<String> {
        match self {
            DownlyError::NeedsLogin(platform, _) => Some(format!(
                "Open Settings → Accounts, pick the browser where you’re signed in to {}, then try again.",
                platform.display_name()
            )),
            DownlyError::BotCheck => Some(
                "Open Settings → Accounts and pick the browser you use YouTube in. Downly will use that session.".to_string(),
            ),
            DownlyError::Network(_) => Some("Check your internet connection and try again.".to_string()),
            DownlyError::ToolMissing(_) | DownlyError::ToolFailed(_) => {
                Some("Open Settings → Engine and choose “Reinstall Components”.".to_string())
            }
            _ => None,
        }
    }

    pub fn needs_account(&self) -> bool {
        matches!(self, DownlyError::NeedsLogin(..) | DownlyError::BotCheck)
    }

    pub fn is_cancelled(&self) -> bool {
        matches!(self, DownlyError::Cancelled)
    }

    pub fn info(&self) -> ErrorInfo {
        ErrorInfo {
            message: self.to_string(),
            suggestion: self.suggestion(),
            needs_account: self.needs_account(),
            cancelled: self.is_cancelled(),
        }
    }
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ErrorInfo {
    pub message: String,
    pub suggestion: Option<String>,
    pub needs_account: bool,
    pub cancelled: bool,
}

impl Serialize for DownlyError {
    fn serialize<S: serde::Serializer>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error> {
        self.info().serialize(serializer)
    }
}

impl From<reqwest::Error> for DownlyError {
    fn from(error: reqwest::Error) -> Self {
        if error.is_timeout() {
            DownlyError::Network("The connection timed out.".to_string())
        } else if error.is_connect() {
            DownlyError::Network("Couldn’t reach the server. Check your internet connection.".to_string())
        } else if let Some(status) = error.status() {
            DownlyError::Http(status.as_u16())
        } else {
            DownlyError::Network(format!("Network error: {error}"))
        }
    }
}

impl From<std::io::Error> for DownlyError {
    fn from(error: std::io::Error) -> Self {
        DownlyError::Message(error.to_string())
    }
}

impl From<serde_json::Error> for DownlyError {
    fn from(error: serde_json::Error) -> Self {
        DownlyError::Message(format!("Unexpected data: {error}"))
    }
}
