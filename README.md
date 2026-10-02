# ClevVPN — iOS + macOS

Фирменный VPN-клиент ClevVPN под панель **Remnawave**.
Ядро — **sing-box** (libbox на iOS / brew `sing-box` на Mac): VLESS (включая Reality),
Trojan, Hysteria2, Shadowsocks, TUN, маршрутизация, пинг.

## Быстрый старт на Mac

```bash
git clone https://github.com/canawa/clevxcode.git
cd clevxcode
brew install xcodegen
xcodegen generate
open ClevVPN.xcodeproj
```

В Xcode выбери схему:

| Схема | Что это |
|---|---|
| **ClevVPN** | iOS (нужен платный Apple Developer для реального VPN-туннеля) |
| **ClevVPNPreview** | iOS UI без Network Extension (можно на бесплатном Apple ID) |
| **ClevVPNMac** | macOS-клиент (`brew install sing-box`, при первом коннекте — пароль админа) |

Без сборки Libbox iOS-сборка всё равно открывается (UI, парсинг, TCP-пинг), но туннель
не стартует — код ядра под `#if canImport(Libbox)`.

### iOS: ядро Libbox (один раз, ~15 мин)

```bash
brew install go
./scripts/build-libbox.sh
# Раскомментировать блоки Libbox в project.yml (два места), затем:
xcodegen generate
```

## Возможности

- **Активация по ключу** — ссылка подписки Remnawave
- **Протоколы** — VLESS/Reality/WS/gRPC, Trojan, Hysteria2 (+ port hopping, obfs), Shadowsocks
- **Вкладки серверов** — категории по имени (как Android/Windows) + на iOS группы/папки
- **Пинг** — через ядро, цветовая индикация
- **Маршрутизация** — весь трафик / умный (iOS) / свои правила; на Mac ещё per-app + Kill Switch
- **Данные подписки** — трафик, срок, анонсы, support-url (заголовки Remnawave)
- **RU / EN**, тёмная тема

### Тесты

```bash
xcodebuild -project ClevVPN.xcodeproj -scheme ClevVPN \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```

### Демо-режим (без сервера)

В Debug-сборке введите ключ `demo` на экране активации — загрузятся тестовые серверы.

## Настройка Remnawave

1. Клиент запрашивает подписку с User-Agent `Happ/3.13.0` (мимикрия под Happ) и передаёт
   `X-Hwid` — Remnawave отдаёт Happ-шаблон со ссылками `vless://`, `trojan://`,
   `hysteria2://`, `ss://` и корректно применяет лимит устройств. Отдельный шаблон
   для ClevVPN заводить не нужно.
2. **Вкладки из админки**: назовите хосты в Remnawave по схеме `Группа | 🇩🇪 Имя`,
   например `Premium | 🇩🇪 Франкфурт`. Часть до `|` станет вкладкой в приложении.
3. Заголовки `Subscription-Userinfo`, `profile-title`, `announce`, `support-url`
   подхватываются автоматически.

## Важные ограничения Apple

- **TUN (Network Extension) не работает с бесплатным Apple-аккаунтом.**
  Нужен платный Apple Developer Program ($99/год) — иначе туннель не стартует на устройстве.
- **App Store**: VPN-приложения публикуются только с аккаунта типа «Организация»
  (App Review Guideline 5.4). Для TestFlight/личных устройств хватит обычного платного.
- **Per-app split tunneling на iOS невозможен** для обычных приложений (только MDM).
  Вместо него — правила маршрутизации по доменам и IP.
- В симуляторе VPN не работает в принципе — туннель проверяется только на устройстве.

## Структура

```
ClevVPN/          iOS UI + общие Theme/Resources
ClevVPNMac/       macOS UI, туннель, Kill Switch, menu bar
ClevVPNKit/       общий фреймворк: парсеры, модели, конфиг sing-box, Keychain
PacketTunnel/     iOS Network Extension (Libbox)
ClevVPNKitTests/  юнит-тесты
scripts/          сборка Libbox.xcframework
windows/          черновик Windows (Tauri) — на Mac не нужен
```

После сборки ядра сверьте сигнатуры `LibboxPlatformInterfaceProtocol` в
`PacketTunnel/ExtensionPlatformInterface.swift` и `ClevVPN/LibboxPingEngine.swift`
с заголовком `Frameworks/Libbox.xcframework/ios-arm64/Libbox.framework/Headers/Libbox.objc.h` —
API немного меняется между версиями sing-box.
