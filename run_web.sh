#!/usr/bin/env bash
# 在本機啟動 Flutter Web（固定埠 8080）
set -e
cd "$(dirname "$0")"
echo ""
echo "【重要】請在瀏覽器網址列手動開啟你的 App（只有這個是畫面）："
echo "    http://127.0.0.1:8080"
echo ""
echo "（終端機若出現 127.0.0.1:5xxxx 是除錯／DevTools，不是主畫面，勿當成網頁開。）"
echo "（flutter run 跑著時先不要按鍵盤 r，等網頁能開再說；r 是熱重載。）"
echo ""
exec flutter run -d web-server --web-hostname=127.0.0.1 --web-port=8080
