#!/bin/bash
# Генерация ClevVPN.xcodeproj.
# Если Libbox ещё не собран — зависимости на xcframework временно убираются,
# чтобы можно было собрать Mac / Preview. Для реального iOS VPN сначала:
#   ./scripts/setup-ios.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# Важно: временный spec должен лежать в ROOT.
# XcodeGen резолвит относительные sources относительно папки --spec,
# а не текущей директории.
generate_from_spec() {
  local spec="$1"
  xcodegen generate --spec "$spec" --project "$ROOT"
}

if [ ! -d "Frameworks/Libbox.xcframework" ]; then
  echo "==> Libbox.xcframework не найден — генерирую проект БЕЗ ядра (Mac / Preview UI)."
  echo "    Для VPN на iPhone: ./scripts/setup-ios.sh"
  TMP="$ROOT/.project.generated.yml"
  # Удаляем блоки framework: Frameworks/Libbox.xcframework (+ следующая строка embed)
  awk '
    /framework: Frameworks\/Libbox\.xcframework/ { skip=1; next }
    skip && /embed:/ { skip=0; next }
    skip { next }
    { print }
  ' project.yml > "$TMP"
  generate_from_spec "$TMP"
  rm -f "$TMP"
else
  echo "==> Libbox.xcframework найден — генерирую полный iOS VPN проект."
  generate_from_spec "$ROOT/project.yml"
fi

echo "==> Готово: $ROOT/ClevVPN.xcodeproj"
