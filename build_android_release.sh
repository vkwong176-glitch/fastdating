#!/usr/bin/env bash
# 產生 Google Play 用 Android App Bundle（.aab）。
# 須先設定 android/key.properties（可參考 key.properties.example），且 storePassword／keyPassword 須與 .jks 一致。
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

if [[ ! -f android/key.properties ]]; then
  echo "Error: 缺少 android/key.properties。請複製 android/key.properties.example 並填入路徑與密碼。" >&2
  exit 1
fi

echo ">> flutter build appbundle --release"
flutter build appbundle --release

AAB="build/app/outputs/bundle/release/app-release.aab"
if [[ -f "$AAB" ]]; then
  echo ">> 完成：$ROOT/$AAB"
  ls -la "$AAB"
  echo ""
  echo "下一步：登入 Google Play Console → 你的應用程式 → 測試或正式 → 建立新版本 → 上傳上述 .aab"
  echo "詳見：docs/ANDROID_RELEASE_PRECHECK.md"
else
  echo "Error: 未找到 $AAB" >&2
  exit 1
fi
