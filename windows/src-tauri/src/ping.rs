// TCP-пинг серверов (как на Mac): реальное время установки TCP-соединения.
// Ядронезависимо, работает для VLESS/Trojan/SS/Hysteria2 (для hy2 — по TCP 443).

use std::net::{TcpStream, ToSocketAddrs};
use std::time::{Duration, Instant};

/// Пинг одного хоста:порта. Возвращает миллисекунды или None (недоступен).
pub fn tcp_ping(host: &str, port: u16, timeout_ms: u64) -> Option<u32> {
    let addr = format!("{host}:{port}");
    let sockaddr = addr.to_socket_addrs().ok()?.next()?;
    let start = Instant::now();
    match TcpStream::connect_timeout(&sockaddr, Duration::from_millis(timeout_ms)) {
        Ok(_) => Some(start.elapsed().as_millis() as u32),
        Err(_) => None,
    }
}
