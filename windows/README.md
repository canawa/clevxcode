# ClevVPN для Windows (Tauri + sing-box)

Windows-клиент ClevVPN с тем же видом, что и macOS-версия, и с **per-app**
маршрутизацией (весь трафик через VPN / выбранные приложения мимо / только
выбранные). Ядро — `sing-box.exe` (Wintun), UI — тот же тёмный экран.

> ⚠️ Это **каркас**. Логика написана, но приложение нужно **собрать и
> протестировать на Windows** — с macOS Windows-бинарь не собирается.

## Что нужно на Windows (один раз)
1. **Rust** — https://rustup.rs
2. **Tauri CLI**: `cargo install tauri-cli`
3. **WebView2 Runtime** — обычно уже есть в Windows 10/11.
4. **sing-box для Windows**: скачать `sing-box.exe`
   (https://github.com/SagerNet/sing-box/releases) и положить в
   `windows/src-tauri/bin/sing-box.exe`. Он попадёт в бандл (`resources`) и в
   рантайме лежит рядом с exe: `<app>/bin/sing-box.exe`.
   - Wintun sing-box подтягивает сам; если нет — положить `wintun.dll` туда же.
5. Иконка: `windows/src-tauri/icons/icon.ico`.

## Сборка и запуск
```powershell
cd windows/src-tauri
cargo tauri dev      # разработка
cargo tauri build    # установщик NSIS в target/release/bundle
```
Запускать **от администратора** — TUN (Wintun) и Windows Firewall (Kill Switch)
требуют прав. (Добавить `requestedExecutionLevel=requireAdministrator` в манифест
или через winres — TODO.)

## Как устроено
```
windows/
├── ui/index.html            # весь UI (как на Mac) + экран per-app, дёргает Tauri invoke()
└── src-tauri/
    ├── bin/sing-box.exe      # сюда положить ядро
    ├── src/
    │   ├── main.rs           # Tauri-команды: activate/connect/disconnect/ping
    │   ├── vpn.rs            # сборка sing-box-конфига (TUN + per-app) + запуск процесса
    │   ├── subscription.rs   # загрузка подписки (UA sing-box) → серверы
    │   ├── killswitch.rs     # Windows Firewall (netsh)
    │   └── ping.rs           # TCP-пинг
    ├── Cargo.toml
    ├── build.rs
    └── tauri.conf.json
```

## Логика
- **Подписка**: запрос с `User-Agent: sing-box` — Remnawave отдаёт готовый
  sing-box-конфиг (outbounds всех серверов). Переиспользуем его как есть.
- **Подключение**: берём outbounds панели, добавляем **TUN-inbound** (Wintun,
  `auto_route`, `stack: system`) и правила маршрутизации, пишем `config.json`,
  запускаем `sing-box.exe run`.
- **Per-app**: на Windows `stack: system` передаёт имя процесса, поэтому правила
  `process_name` работают:
  - «мимо VPN» → `{process_name:[...], outbound:direct}`;
  - «только выбранные» → выбранные в `proxy`, `route.final = direct`.
- **Kill Switch**: правила Windows Firewall (netsh) — блок всего исходящего,
  кроме VPN-интерфейса и LAN.
- **Пинг**: TCP-connect (как на Mac).

## Что доделать на Windows
- Вернуть `host`/`port` в `ServerInfo`, чтобы работал пинг из UI.
- Сохранять ссылку-подписку в Windows Credential Manager / DPAPI.
- Манифест `requireAdministrator`, иконки, автозапуск, трей.
- Проверить формат sing-box-подписки именно вашей панели (UA/шаблон).
- Отполировать firewall-правила Kill Switch под конкретный интерфейс ClevVPN.
