#!/bin/bash
# Сборка Libbox.xcframework (ядро sing-box) для iOS.
# Требует: Xcode, go (brew install go). Результат: Frameworks/Libbox.xcframework
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/scripts/sing-box"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export PATH="$PATH:$(go env GOPATH)/bin"

if [ ! -d "$SRC" ]; then
  git clone --depth 50 https://github.com/SagerNet/sing-box.git "$SRC"
fi

cd "$SRC"
git fetch --tags --depth 50 origin 2>/dev/null || true
# Последний стабильный тег (без -rc/-beta/-alpha)
TAG="$(git tag -l 'v*' | grep -Ev 'rc|beta|alpha' | sort -V | tail -1)"
echo "==> Building sing-box $TAG"
git checkout -q "$TAG"

echo "==> Installing gomobile fork"
make lib_install

echo "==> Building Libbox.xcframework for iOS (this takes a while)"
go run ./cmd/internal/build_libbox -target ios -platform ios

rm -rf "$ROOT/Frameworks/Libbox.xcframework"
mkdir -p "$ROOT/Frameworks"
cp -R Libbox.xcframework "$ROOT/Frameworks/"
echo "==> Done: $ROOT/Frameworks/Libbox.xcframework"

if command -v xcodegen >/dev/null 2>&1; then
  echo "==> Regenerating Xcode project with Libbox"
  "$ROOT/scripts/generate-xcodeproj.sh"
fi
echo "==> Next: open ClevVPN.xcodeproj → scheme ClevVPN → device + Team → Run"
