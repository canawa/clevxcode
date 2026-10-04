#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod vpn;
mod subscription;
mod killswitch;
mod ping;

use std::sync::Mutex;
use serde::Serialize;
use serde_json::Value;
use tauri::{Manager, State};
use vpn::{AppMode, Tunnel};

struct AppState {
    tunnel: Tunnel,
    sub: Mutex<Option<subscription::Subscription>>,
}

#[derive(Serialize)]
struct StatusPayload {
    connected: bool,
    servers: Vec<subscription::ServerInfo>,
    announce: Option<String>,
    title: Option<String>,
}

// --- Команды, которые дёргает фронтенд через invoke() ---

#[tauri::command]
async fn activate(url: String, state: State<'_, AppState>) -> Result<StatusPayload, String> {
    let sub = subscription::fetch(&url).await?;
    let payload = StatusPayload {
        connected: state.tunnel.is_running(),
        servers: sub.servers.clone(),
        announce: sub.announce.clone(),
        title: sub.title.clone(),
    };
    *state.sub.lock().unwrap() = Some(sub);
    // TODO(win): сохранить url в защищённое хранилище (Windows Credential Manager / DPAPI)
    Ok(payload)
}

#[tauri::command]
fn get_status(state: State<'_, AppState>) -> StatusPayload {
    let guard = state.sub.lock().unwrap();
    match &*guard {
        Some(s) => StatusPayload {
            connected: state.tunnel.is_running(),
            servers: s.servers.clone(),
            announce: s.announce.clone(),
            title: s.title.clone(),
        },
        None => StatusPayload { connected: false, servers: vec![], announce: None, title: None },
    }
}

#[tauri::command]
fn connect(
    tag: String,
    app_mode: String,
    apps: Vec<String>,
    smart: bool,
    kill_switch: bool,
    state: State<'_, AppState>,
) -> Result<(), String> {
    let guard = state.sub.lock().unwrap();
    let sub = guard.as_ref().ok_or("no subscription")?;
    let mode = match app_mode.as_str() {
        "bypass" => AppMode::BypassSelected,
        "only" => AppMode::OnlySelected,
        _ => AppMode::Off,
    };
    state.tunnel.start(&sub.raw, &tag, mode, &apps, smart)?;
    if kill_switch {
        // Kill Switch ставим после подъёма (интерфейс ClevVPN уже поднят sing-box).
        let _ = killswitch::enable();
    }
    Ok(())
}

#[tauri::command]
fn disconnect(state: State<'_, AppState>) {
    killswitch::disable();
    state.tunnel.stop();
}

#[tauri::command]
fn ping(host: String, port: u16) -> Option<u32> {
    ping::tcp_ping(&host, port, 3000)
}

fn main() {
    tauri::Builder::default()
        .setup(|app| {
            let dir = app.path_resolver().app_data_dir().unwrap_or(std::env::temp_dir());
            // sing-box.exe кладём рядом с бинарником приложения: <exe_dir>/bin/sing-box.exe
            let exe_dir = std::env::current_exe().ok()
                .and_then(|p| p.parent().map(|d| d.to_path_buf()))
                .unwrap_or_default();
            let core = exe_dir.join("bin").join("sing-box.exe");
            app.manage(AppState {
                tunnel: Tunnel::new(core, dir),
                sub: Mutex::new(None),
            });
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            activate, get_status, connect, disconnect, ping
        ])
        .run(tauri::generate_context!())
        .expect("error while running ClevVPN");
}

// Заглушка, чтобы serde_json::Value не считался неиспользуемым в некоторых сборках.
#[allow(dead_code)]
fn _v() -> Value { Value::Null }
