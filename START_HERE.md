# ClevVPN — быстрый старт

Нужны: macOS, Xcode (App Store), [Homebrew](https://brew.sh).

## macOS (VPN сразу)

```bash
brew install xcodegen sing-box
cd ClevVPN
chmod +x scripts/*.sh
./scripts/generate-xcodeproj.sh
open ClevVPN.xcodeproj
```

Схема **ClevVPNMac** → My Mac → Run.  
При первом коннекте — пароль администратора. Ключ Remnawave вставить в приложении.

## iOS (реальный VPN + подписка Remnawave)

Нужен **платный** Apple Developer ($99/год) — без него Apple не даёт Network Extension.

```bash
cd ClevVPN
chmod +x scripts/*.sh
./scripts/setup-ios.sh          # ~15 мин: Libbox + Xcode-проект
open ClevVPN.xcodeproj
```

В Xcode:
1. Схема **ClevVPN**
2. Свой **iPhone** (симулятор VPN не поднимает)
3. Signing & Capabilities → **Team** (платный Developer)
4. Run → вставить ключ подписки → Connect → разрешить VPN в системе

Без ядра Libbox кнопка Connect покажет ошибку (не «фейковое» подключение).  
Только UI без VPN: схема **ClevVPNPreview** (можно с бесплатным Apple ID).
