// Загрузка подписки Remnawave в формате sing-box и извлечение списка серверов.
// По UA "sing-box" панель отдаёт готовый sing-box-конфиг (inbounds/outbounds/route),
// который мы переиспользуем целиком — протоколы парсить руками не нужно.

use serde::Serialize;
use serde_json::Value;

#[derive(Serialize, Clone)]
pub struct ServerInfo {
    pub tag: String,     // тег outbound (он же id для выбора)
    pub name: String,    // отображаемое имя
    pub group: Option<String>,
    pub flag: Option<String>,
    pub protocol: String,
    pub host: String,    // для TCP-пинга
    pub port: u16,
}

pub struct Subscription {
    pub raw: Value,             // полный sing-box-конфиг от панели
    pub servers: Vec<ServerInfo>,
    pub announce: Option<String>,
    pub title: Option<String>,
}

/// Загружает подписку по ссылке. Возвращает конфиг + разобранный список серверов.
pub async fn fetch(url: &str) -> Result<Subscription, String> {
    let client = reqwest::Client::builder()
        .user_agent("sing-box")
        .timeout(std::time::Duration::from_secs(20))
        .build()
        .map_err(|e| e.to_string())?;

    let resp = client.get(url).send().await.map_err(|e| e.to_string())?;
    let announce = resp.headers().get("announce")
        .and_then(|h| h.to_str().ok()).map(decode_header);
    let title = resp.headers().get("profile-title")
        .and_then(|h| h.to_str().ok()).map(decode_header);

    let body = resp.text().await.map_err(|e| e.to_string())?;
    let raw: Value = serde_json::from_str(&body)
        .map_err(|_| "subscription is not a sing-box JSON (check the UA/template on the panel)".to_string())?;

    let servers = extract_servers(&raw);
    Ok(Subscription { raw, servers, announce, title })
}

/// Из outbounds sing-box берём реальные серверы (не selector/urltest/direct/block).
fn extract_servers(cfg: &Value) -> Vec<ServerInfo> {
    let proto_ok = ["vless", "trojan", "shadowsocks", "hysteria2", "vmess", "tuic"];
    cfg.get("outbounds").and_then(|v| v.as_array()).map(|arr| {
        arr.iter().filter_map(|o| {
            let proto = o.get("type").and_then(|t| t.as_str())?;
            if !proto_ok.contains(&proto) { return None; }
            let tag = o.get("tag").and_then(|t| t.as_str())?.to_string();
            let host = o.get("server").and_then(|s| s.as_str()).unwrap_or("").to_string();
            let port = o.get("server_port").and_then(|p| p.as_u64()).unwrap_or(443) as u16;
            let (group, flag, name) = parse_remark(&tag);
            Some(ServerInfo { tag, name, group, flag, protocol: proto.to_string(), host, port })
        }).collect()
    }).unwrap_or_default()
}

/// Разбирает "Группа | 🇩🇪 Имя" на группу, флаг и имя.
fn parse_remark(remark: &str) -> (Option<String>, Option<String>, String) {
    let (group, rest) = match remark.split_once('|') {
        Some((g, r)) => (Some(g.trim().to_string()), r.trim().to_string()),
        None => (None, remark.trim().to_string()),
    };
    // Вытащим ведущий флаг-эмодзи (2 региональных индикатора).
    let flag: String = rest.chars().take_while(|c| (0x1F1E6..=0x1F1FF).contains(&(*c as u32))).collect();
    let name = rest.trim_start_matches(|c| (0x1F1E6..=0x1F1FF).contains(&(c as u32))).trim().to_string();
    let flag = if flag.is_empty() { None } else { Some(flag) };
    (group, flag, if name.is_empty() { rest } else { name })
}

/// Remnawave кодирует заголовки announce/title как MIME/base64 или percent — берём как есть.
fn decode_header(s: &str) -> String {
    s.to_string()
}
