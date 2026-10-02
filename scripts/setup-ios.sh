#!/bin/bash
# Полная подготовка iOS VPN: зависимости → Libbox → Xcode-проект.
# Нужны: macOS, Xcode, платный Apple Developer ($99), Homebrew.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "==> Homebrew: xcodegen, go"
brew install xcodegen go

echo "==> Сборка ядра sing-box (Libbox), ~10–20 мин…"
chmod +x scripts/build-libbox.sh scripts/generate-xcodeproj.sh
./scripts/build-libbox.sh

echo "==> XcodeGen"
./scripts/generate-xcodeproj.sh

echo ""
echo "Готово. Дальше:"
echo "  open ClevVPN.xcodeproj"
echo "  схема ClevVPN → свой iPhone → Signing: выбрать Team (платный Developer)"
echo "  Run → вставить ключ подписки Remnawave → Connect"
echo ""
echo "Симулятор VPN не поднимает — только реальное устройство."
