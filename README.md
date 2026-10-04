# ClevVPN — iOS-клиент

Фирменный VPN-клиент ClevVPN для iOS под панель **Remnawave**.
Ядро — **sing-box** (libbox): VLESS (включая Reality), Trojan, Hysteria2, Shadowsocks,
TUN-режим, маршрутизация, честный пинг всех протоколов.

## Возможности

- **Активация по ключу** — пользователь вставляет ссылку подписки Remnawave
- **Все протоколы** — VLESS/Reality/WS/gRPC, Trojan, Hysteria2 (+ port hopping, obfs), Shadowsocks
- **Вкладки серверов** — из админки (имя хоста вида `Группа | 🇩🇪 Франкфурт`) + свои папки и избранное у клиента
- **Пинг** — через ядро (реальный запрос через протокол, работает и для Hysteria2), цветовая индикация
- **Маршрутизация** — «весь трафик» / «умный» (RU-сайты и LAN мимо VPN) / свои правила по доменам и IP
- **Данные подписки** — трафик, срок действия, анонсы, ссылка на поддержку (заголовки Remnawave)
- **RU / EN** локализация, тёмная тема в фирменном стиле

## Сборка

Требования: macOS + Xcode, [Homebrew](https://brew.sh).

```bash
brew install xcodegen go

# 1. Собрать ядро sing-box (один раз, ~15 минут)
./scripts/build-libbox.sh

# 2. Раскомментировать блоки Libbox в project.yml (два места) и сгенерировать проект
xcodegen generate

# 3. Открыть в Xcode
open ClevVPN.xcodeproj
```

Без шага 1 проект тоже собирается (UI, парсинг, TCP-пинг), но туннель не запустится —
весь код ядра закрыт `#if canImport(Libbox)`.

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
ClevVPN/          приложение (SwiftUI): экраны, тема, логотип
ClevVPNKit/       общий фреймворк: парсеры подписки, модели, конфиг sing-box, Keychain
PacketTunnel/     Network Extension: ядро sing-box внутри туннеля
ClevVPNMac/       macOS-клиент (ядро sing-box в комплекте, brew не нужен)
ClevVPNKitTests/  юнит-тесты парсеров и генератора конфига
scripts/          сборка Libbox / bundle-singbox-mac
```

## macOS: sing-box в комплекте

Пользователю **не нужно** ставить `brew install sing-box`.
Бинарники лежат в `ClevVPNMac/Core/` (`sing-box-arm64`, `sing-box-amd64`) и
вшиваются в `.app`. При первом запуске нужная архитектура копируется в
`~/Library/Application Support/ClevVPN/bin/sing-box` (стабильный путь для sudoers).

Обновить ядро перед сборкой:

```bash
./scripts/bundle-singbox-mac.sh
# Windows: powershell -File scripts/bundle-singbox-mac.ps1
xcodegen generate
```

Остаётся только **разовый** запрос пароля админа (правило sudoers для туннеля / Kill Switch).

После сборки ядра сверьте сигнатуры `LibboxPlatformInterfaceProtocol` в
`PacketTunnel/ExtensionPlatformInterface.swift` и `ClevVPN/LibboxPingEngine.swift`
с заголовком `Frameworks/Libbox.xcframework/ios-arm64/Libbox.framework/Headers/Libbox.objc.h` —
API немного меняется между версиями sing-box.
