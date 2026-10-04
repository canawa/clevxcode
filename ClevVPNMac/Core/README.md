# Bundled sing-box (macOS)

Сюда кладутся официальные бинарники SagerNet sing-box:

- `sing-box-arm64` — Apple Silicon  
- `sing-box-amd64` — Intel  
- `VERSION` — версия релиза  

Скачать/обновить:

```bash
./scripts/bundle-singbox-mac.sh
# или: SINGBOX_VERSION=1.14.2 ./scripts/bundle-singbox-mac.sh
```

Приложение при старте копирует нужную архитектуру в  
`~/Library/Application Support/ClevVPN/bin/sing-box`  
и запускает её оттуда (стабильный путь для sudoers). Homebrew **не обязателен**.
