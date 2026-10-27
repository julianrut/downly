use std::path::{Path, PathBuf};
use std::process::Stdio;
use std::time::Duration;
use tokio::io::AsyncReadExt;
use tokio::process::Command;
use tokio_util::sync::CancellationToken;

use super::error::{DownlyError, Result};
use super::paths;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Channel {
    Stdout,
    Stderr,
}

#[derive(Debug, Clone)]
pub struct Output {
    pub status: i32,
    pub stdout: String,
    pub stderr: String,
}

impl Output {
    pub fn ok(&self) -> bool {
        self.status == 0
    }
}

pub type LineHandler<'a> = &'a (dyn Fn(&str, Channel) + Send + Sync);

pub fn search_path() -> String {
    let tools = paths::tools_dir();
    let mut parts = vec![tools.to_string_lossy().to_string()];
    parts.extend(
        ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
            .iter()
            .map(|s| s.to_string()),
    );
    parts.join(":")
}

fn command(exe: &Path, args: &[String]) -> Command {
    let mut cmd = Command::new(exe);
    cmd.args(args)
        .env("PATH", search_path())
        .env("LC_ALL", "en_US.UTF-8")
        .env("LANG", "en_US.UTF-8")
        .env("PYTHONIOENCODING", "utf-8")
        .env("PYTHONUTF8", "1")
        .env("NO_COLOR", "1")
        .env("DENO_NO_UPDATE_CHECK", "1")
        .env("DENO_NO_PROMPT", "1")
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .kill_on_drop(true);
    #[cfg(unix)]
    {
        cmd.process_group(0);
    }
    cmd
}

fn split_lines(buffer: &mut Vec<u8>) -> Vec<String> {
    let mut lines = Vec::new();
    let mut start = 0;
    for index in 0..buffer.len() {
        if buffer[index] == b'\n' || buffer[index] == b'\r' {
            if index > start {
                lines.push(String::from_utf8_lossy(&buffer[start..index]).to_string());
            }
            start = index + 1;
        }
    }
    buffer.drain(..start);
    lines
}

#[cfg(unix)]
fn signal_group(pid: u32, signal: i32) {
    unsafe {
        libc::kill(-(pid as i32), signal);
    }
}

pub async fn run(exe: &Path, args: &[String], cancel: Option<&CancellationToken>, on_line: Option<LineHandler<'_>>) -> Result<Output> {
    if cancel.map(|c| c.is_cancelled()).unwrap_or(false) {
        return Err(DownlyError::Cancelled);
    }
    let mut child = command(exe, args)
        .spawn()
        .map_err(|e| DownlyError::ToolFailed(format!("Couldn’t start {}: {e}", exe.file_name().map(|n| n.to_string_lossy().to_string()).unwrap_or_default())))?;
    let pid = child.id().unwrap_or(0);
    let mut stdout = child.stdout.take().ok_or_else(|| DownlyError::ToolFailed("No output pipe".into()))?;
    let mut stderr = child.stderr.take().ok_or_else(|| DownlyError::ToolFailed("No error pipe".into()))?;

    let read_all = async {
        let mut out_data: Vec<u8> = Vec::new();
        let mut err_data: Vec<u8> = Vec::new();
        let mut out_partial: Vec<u8> = Vec::new();
        let mut err_partial: Vec<u8> = Vec::new();
        let mut out_buf = [0u8; 16384];
        let mut err_buf = [0u8; 16384];
        let mut out_open = true;
        let mut err_open = true;
        while out_open || err_open {
            tokio::select! {
                read = stdout.read(&mut out_buf), if out_open => {
                    match read {
                        Ok(0) | Err(_) => out_open = false,
                        Ok(n) => {
                            out_data.extend_from_slice(&out_buf[..n]);
                            if let Some(handler) = on_line {
                                out_partial.extend_from_slice(&out_buf[..n]);
                                for line in split_lines(&mut out_partial) {
                                    handler(&line, Channel::Stdout);
                                }
                            }
                        }
                    }
                }
                read = stderr.read(&mut err_buf), if err_open => {
                    match read {
                        Ok(0) | Err(_) => err_open = false,
                        Ok(n) => {
                            err_data.extend_from_slice(&err_buf[..n]);
                            if err_data.len() > 512 * 1024 {
                                let cut = err_data.len() - 256 * 1024;
                                err_data.drain(..cut);
                            }
                            if let Some(handler) = on_line {
                                err_partial.extend_from_slice(&err_buf[..n]);
                                for line in split_lines(&mut err_partial) {
                                    handler(&line, Channel::Stderr);
                                }
                            }
                        }
                    }
                }
            }
        }
        if let Some(handler) = on_line {
            if !out_partial.is_empty() {
                handler(&String::from_utf8_lossy(&out_partial), Channel::Stdout);
            }
            if !err_partial.is_empty() {
                handler(&String::from_utf8_lossy(&err_partial), Channel::Stderr);
            }
        }
        (out_data, err_data)
    };

    let never = CancellationToken::new();
    let token = cancel.unwrap_or(&never);
    tokio::select! {
        (out, err) = read_all => {
            let status = child.wait().await.map(|s| s.code().unwrap_or(-1)).unwrap_or(-1);
            Ok(Output {
                status,
                stdout: String::from_utf8_lossy(&out).to_string(),
                stderr: String::from_utf8_lossy(&err).to_string(),
            })
        }
        _ = token.cancelled() => {
            #[cfg(unix)]
            {
                if pid > 0 {
                    signal_group(pid, libc::SIGTERM);
                }
            }
            if tokio::time::timeout(Duration::from_millis(2500), child.wait()).await.is_err() {
                #[cfg(unix)]
                {
                    if pid > 0 {
                        signal_group(pid, libc::SIGKILL);
                    }
                }
                let _ = child.kill().await;
            }
            Err(DownlyError::Cancelled)
        }
    }
}

pub async fn run_timeout(exe: &Path, args: &[String], seconds: u64) -> Result<Output> {
    let token = CancellationToken::new();
    let guard = token.clone();
    let timer = tokio::spawn(async move {
        tokio::time::sleep(Duration::from_secs(seconds)).await;
        guard.cancel();
    });
    let result = run(exe, args, Some(&token), None).await;
    timer.abort();
    match result {
        Err(DownlyError::Cancelled) => Err(DownlyError::ToolFailed(format!(
            "{} didn’t respond in time.",
            exe.file_name().map(|n| n.to_string_lossy().to_string()).unwrap_or_default()
        ))),
        other => other,
    }
}

pub fn strings(items: &[&str]) -> Vec<String> {
    items.iter().map(|s| s.to_string()).collect()
}

pub fn path_string(path: &PathBuf) -> String {
    path.to_string_lossy().to_string()
}
