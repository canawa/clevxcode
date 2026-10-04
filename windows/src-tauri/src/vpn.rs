// Управление ядром sing-box.exe на Windows: TUN через Wintun + маршрутизация,
// включая per-app (весь трафик через VPN, либо выбранные приложения мимо/только они).

use serde_json::{json, Value};
use std::path::PathBuf;
use std::process::{Child, Command};
use std::sync::Mutex;

#[cfg(windows)]
use std::os::windows::process::CommandExt;
#[cfg(windows)]
const CREATE_NO_WINDOW: u32 = 0x0800_0000; // не показывать консоль sing-box

/// Режим per-app маршрутизации.
#[derive(Clone, Copy, PartialEq)]
pub enum AppMode {
    Off,            // весь трафик через VPN
    BypassSelected, // выбранные приложения — мимо VPN
    OnlySelected,   // только выбранные — через VPN, остальное напрямую
}

pub struct Tunnel {
    child: Mutex<Option<Child>>,
    core_path: PathBuf,   // путь к sing-box.exe (рядом с приложением: bin/sing-box.exe)
    work_dir: PathBuf,    // куда пишем config.json и логи
}

impl Tunnel {
    pub fn new(core_path: PathBuf, work_dir: PathBuf) -> Self {
        std::fs::create_dir_all(&work_dir).ok();
        Tunnel { child: Mutex::new(None), core_path, work_dir }
    }

    pub fn is_running(&self) -> bool {
        self.child.lock().unwrap().as_mut()
            .map(|c| matches!(c.try_wait(), Ok(None)))
            .unwrap_or(false)
    }

    /// Запуск туннеля к выбранному серверу.
    /// `base` — sing-box-конфиг от панели (с outbounds). `outbound_tag` — тег
    /// выбранного сервера. `app_mode`/`apps` — per-app правила (имена .exe).
    pub fn start(
        &self,
        base: &Value,
        outbound_tag: &str,
        app_mode: AppMode,
        apps: &[String],
        smart: bool,
    ) -> Result<(), String> {
        self.stop();

        let config = build_config(base, outbound_tag, app_mode, apps, smart)?;
        let cfg_path = self.work_dir.join("config.json");
        std::fs::write(&cfg_path, serde_json::to_vec_pretty(&config).unwrap())
            .map_err(|e| format!("write config: {e}"))?;

        let log = std::fs::File::create(self.work_dir.join("core.log")).ok();

        let mut cmd = Command::new(&self.core_path);
        cmd.arg("run").arg("-c").arg(&cfg_path).arg("-D").arg(&self.work_dir);
        if let Some(f) = log {
            cmd.stdout(f.try_clone().unwrap()).stderr(f);
        }
        #[cfg(windows)]
        cmd.creation_flags(CREATE_NO_WINDOW);

        let child = cmd.spawn().map_err(|e| format!("start sing-box: {e}"))?;
        *self.child.lock().unwrap() = Some(child);
        Ok(())
    }

    pub fn stop(&self) {
        if let Some(mut c) = self.child.lock().unwrap().take() {
            let _ = c.kill();
            let _ = c.wait();
        }
    }
}

/// Собирает финальный sing-box-конфиг: TUN-inbound + outbounds панели +
/// маршрутизация (per-app / умный режим).
fn build_config(
    base: &Value,
    outbound_tag: &str,
    app_mode: AppMode,
    apps: &[String],
    smart: bool,
) -> Result<Value, String> {
    let outbounds = base.get("outbounds").and_then(|v| v.as_array())
        .ok_or("subscription has no outbounds")?
        .clone();

    // Гарантируем служебные outbounds direct/block и известный тег proxy.
    let mut outs = outbounds;
    ensure_outbound(&mut outs, "direct", json!({"type":"direct","tag":"direct"}));
    ensure_outbound(&mut outs, "block", json!({"type":"block","tag":"block"}));
    // Выбранный сервер получает тег "proxy" (на него ссылается маршрутизация).
    retag_selected(&mut outs, outbound_tag, "proxy");

    // TUN-inbound (Wintun). На Windows stack "system" передаёт имя процесса —
    // поэтому per-app правила по process_name работают.
    let tun = json!({
        "type": "tun",
        "tag": "tun-in",
        "interface_name": "ClevVPN",
        "address": ["172.19.0.1/30"],
        "mtu": 1500,
        "auto_route": true,
        "strict_route": true,
        "stack": "system"
    });

    // Правила маршрутизации.
    let mut rules: Vec<Value> = vec![
        json!({"action":"sniff"}),
        json!({"protocol":"dns","action":"hijack-dns"}),
        json!({"ip_is_private": true, "outbound": "direct"}),
    ];

    // Per-app.
    match app_mode {
        AppMode::Off => {}
        AppMode::BypassSelected if !apps.is_empty() => {
            rules.push(json!({"process_name": apps, "outbound": "direct"}));
        }
        AppMode::OnlySelected if !apps.is_empty() => {
            // только выбранные — в proxy, остальное — direct (final переопределим)
            rules.push(json!({"process_name": apps, "outbound": "proxy"}));
        }
        _ => {}
    }

    // Умный режим: RU/локальное — напрямую (rule-set geosite/geoip можно
    // подключить отдельно; здесь минимально).
    if smart {
        rules.push(json!({"domain_suffix": [".ru"], "outbound": "direct"}));
    }

    let final_out = if app_mode == AppMode::OnlySelected && !apps.is_empty() {
        "direct" // всё, что не выбрано, — мимо VPN
    } else {
        "proxy"
    };

    Ok(json!({
        "log": {"level": "warn"},
        "dns": base.get("dns").cloned().unwrap_or(json!({
            "servers": [{"tag":"remote","address":"tls://1.1.1.1"},{"tag":"local","address":"223.5.5.5","detour":"direct"}],
            "final": "remote"
        })),
        "inbounds": [tun],
        "outbounds": outs,
        "route": {
            "rules": rules,
            "final": final_out,
            "auto_detect_interface": true
        }
    }))
}

fn ensure_outbound(outs: &mut Vec<Value>, tag: &str, default: Value) {
    let has = outs.iter().any(|o| o.get("tag").and_then(|t| t.as_str()) == Some(tag));
    if !has { outs.push(default); }
}

/// Переименовывает выбранный outbound в "proxy" (и убирает чужой тег proxy).
fn retag_selected(outs: &mut [Value], selected_tag: &str, new_tag: &str) {
    for o in outs.iter_mut() {
        if o.get("tag").and_then(|t| t.as_str()) == Some(new_tag) {
            // освобождаем тег, если он занят не тем сервером
            if o.get("tag").and_then(|t| t.as_str()) != Some(selected_tag) {
                o["tag"] = json!(format!("{new_tag}-orig"));
            }
        }
    }
    for o in outs.iter_mut() {
        if o.get("tag").and_then(|t| t.as_str()) == Some(selected_tag) {
            o["tag"] = json!(new_tag);
        }
    }
}
