#!/usr/bin/env bash
# Скачивает официальные бинарники sing-box для macOS (arm64 + amd64)
# в ClevVPNMac/Core/ — они попадают в .app и пользователю не нужен brew.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/ClevVPNMac/Core"
VER="${SINGBOX_VERSION:-1.14.2}"
BASE="https://github.com/SagerNet/sing-box/releases/download/v${VER}"

mkdir -p "$OUT"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

for ARCH in arm64 amd64; do
  NAME="sing-box-${VER}-darwin-${ARCH}.tar.gz"
  echo "==> Downloading $NAME"
  curl -fsSL "$BASE/$NAME" -o "$TMP/$NAME"
  mkdir -p "$TMP/$ARCH"
  tar -xzf "$TMP/$NAME" -C "$TMP/$ARCH"
  BIN="$(find "$TMP/$ARCH" -type f -name sing-box | head -n1)"
  if [[ -z "$BIN" ]]; then
    echo "sing-box binary not found in $NAME" >&2
    exit 1
  fi
  cp "$BIN" "$OUT/sing-box-${ARCH}"
  chmod +x "$OUT/sing-box-${ARCH}"
  echo "    -> $OUT/sing-box-${ARCH}"
done

printf '%s\n' "$VER" > "$OUT/VERSION"
echo "==> Bundled sing-box v${VER} (arm64 + amd64)"
