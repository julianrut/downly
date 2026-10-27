use std::path::{Path, PathBuf};

pub const APP_NAME: &str = "Downly";

fn ensure(path: PathBuf) -> PathBuf {
    let _ = std::fs::create_dir_all(&path);
    path
}

pub fn support_dir() -> PathBuf {
    let base = dirs::data_dir().unwrap_or_else(|| home().join("Library/Application Support"));
    ensure(base.join(APP_NAME))
}

pub fn home() -> PathBuf {
    dirs::home_dir().unwrap_or_else(|| PathBuf::from("/tmp"))
}

pub fn tools_dir() -> PathBuf {
    if let Ok(custom) = std::env::var("DOWNLY_TOOLS_DIR") {
        if !custom.is_empty() {
            return ensure(PathBuf::from(custom));
        }
    }
    ensure(support_dir().join("Tools"))
}

pub fn cache_dir() -> PathBuf {
    let base = dirs::cache_dir().unwrap_or_else(std::env::temp_dir);
    ensure(base.join(APP_NAME))
}

pub fn ytdlp_cache() -> PathBuf {
    ensure(cache_dir().join("yt-dlp"))
}

pub fn staging() -> PathBuf {
    ensure(cache_dir().join("Staging"))
}

pub fn staging_for(id: &str) -> PathBuf {
    ensure(staging().join(id))
}

pub fn clean_staging() {
    let _ = std::fs::remove_dir_all(staging());
}

pub fn history_file() -> PathBuf {
    support_dir().join("History.json")
}

pub fn settings_file() -> PathBuf {
    support_dir().join("Settings.json")
}

pub fn default_downloads() -> PathBuf {
    dirs::download_dir().unwrap_or_else(|| home().join("Downloads"))
}

pub fn expand(path: &str) -> PathBuf {
    if let Some(rest) = path.strip_prefix("~/") {
        home().join(rest)
    } else if path == "~" {
        home()
    } else {
        PathBuf::from(path)
    }
}

pub fn sanitize(raw: &str, max_chars: usize) -> String {
    let mut text: String = raw
        .replace(['\n', '\r', '\t'], " ")
        .replace('/', "-")
        .replace(':', " -")
        .replace('\\', "-")
        .chars()
        .filter(|c| !c.is_control())
        .collect();
    while text.contains("  ") {
        text = text.replace("  ", " ");
    }
    let trim_set = |c: char| c == ' ' || c == '.' || c == '-' || c.is_whitespace();
    text = text.trim_matches(trim_set).to_string();
    if text.chars().count() > max_chars {
        let mut cut: String = text.chars().take(max_chars).collect();
        if let Some(space) = cut.rfind(' ') {
            if cut[..space].chars().count() > max_chars / 2 {
                cut.truncate(space);
            }
        }
        text = cut.trim_matches(|c: char| c == ' ' || c == '.' || c == '-' || c == ',').to_string();
    }
    if text.is_empty() {
        "Download".to_string()
    } else {
        text
    }
}

pub fn unique_path(directory: &Path, base: &str, ext: &str) -> PathBuf {
    let ext = ext.trim_start_matches('.');
    let make = |name: &str| {
        if ext.is_empty() {
            directory.join(name)
        } else {
            directory.join(format!("{name}.{ext}"))
        }
    };
    let mut candidate = make(base);
    let mut counter = 2;
    while candidate.exists() {
        candidate = make(&format!("{base} {counter}"));
        counter += 1;
    }
    candidate
}

pub fn unique_dir(parent: &Path, name: &str) -> PathBuf {
    let mut candidate = parent.join(name);
    let mut counter = 2;
    while candidate.exists() {
        candidate = parent.join(format!("{name} {counter}"));
        counter += 1;
    }
    candidate
}

pub fn move_into(file: &Path, directory: &Path, name: Option<&str>) -> std::io::Result<PathBuf> {
    std::fs::create_dir_all(directory)?;
    let ext = file.extension().and_then(|e| e.to_str()).unwrap_or("").to_string();
    let stem = file.file_stem().and_then(|s| s.to_str()).unwrap_or("Download").to_string();
    let base = sanitize(name.unwrap_or(&stem), 140);
    let destination = unique_path(directory, &base, &ext);
    if std::fs::rename(file, &destination).is_err() {
        std::fs::copy(file, &destination)?;
        let _ = std::fs::remove_file(file);
    }
    Ok(destination)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sanitizes() {
        assert_eq!(sanitize("a/b: c\nd", 140), "a-b - c d");
        assert_eq!(sanitize("   ", 140), "Download");
    }
}
