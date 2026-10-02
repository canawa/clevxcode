# ClevVPN — как запустить (Mac)

Нужны: macOS, Xcode (App Store), Homebrew (https://brew.sh).

```bash
brew install xcodegen sing-box
cd ClevVPN          # папка из архива
xcodegen generate
open ClevVPN.xcodeproj
```

В Xcode сверху выбери схему **ClevVPNMac** → My Mac → Run (▶).
При первом подключении к VPN введи пароль администратора Mac.
Ключ подписки Remnawave вставь в приложении (или `demo` в Debug).

**iOS:** схема **ClevVPNPreview** — UI без VPN (бесплатный Apple ID).
Полный VPN на iPhone — схема **ClevVPN** + платный Apple Developer ($99/год) + сборка ядра: `./scripts/build-libbox.sh` и раскомментировать Libbox в `project.yml`.
