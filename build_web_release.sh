#!/usr/bin/env bash
# 正式 Web 建置：產生 main.dart.js.map，並補上 flutter.js.map（SDK 內建，預設未複製到 build/web，
# 否則 flutter.js 尾端 //# sourceMappingURL=flutter.js.map 會被 Hosting SPA 回退成 index.html）。
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

# CanvasKit 使用官方 CDN（gstatic），與 main.dart.js 並行下載，慢速網路下通常比單一來源連續拉整包 wasm 更有利 Speed Index。
echo ">> flutter build web --release --source-maps -O4 (CanvasKit via CDN)"
flutter build web --release --source-maps --no-wasm-dry-run --optimization-level=4

FLUTTER_ROOT="$(python3 <<'PY'
import os
import shutil
p = shutil.which("flutter")
if not p:
    raise SystemExit("flutter not on PATH")
print(os.path.dirname(os.path.dirname(os.path.realpath(p))))
PY
)"
MAP_SRC="$FLUTTER_ROOT/bin/cache/flutter_web_sdk/flutter_js/flutter.js.map"
if [[ -f "$MAP_SRC" ]]; then
  cp -f "$MAP_SRC" build/web/flutter.js.map
  echo ">> copied flutter.js.map from Flutter SDK"
else
  echo "Warning: flutter.js.map not found at $MAP_SRC (Lighthouse 仍可能對 flutter.js 報 source map 錯誤)" >&2
fi

echo ">> done: build/web (main.dart.js.map + flutter.js.map if available)"
