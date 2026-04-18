# SEO 與伺服器路由（SPA path 模式）

Flutter Web 已改為 **path URL**（無 `#/`），公開路徑由 `lib/router/app_router.dart` 定義。  
靜態部署時必須讓**任意路徑**都回傳 `index.html`，否則直接開啟子路徑會 404。

## Firebase Hosting（本專案 `firebase.json`）

已設定：

```json
"rewrites": [ { "source": "**", "destination": "/index.html" } ]
```

部署後 `https://fastdating1.com/subscription/fast-dating-1/` 等路徑會正確載入 SPA。  
（尾隨 `/` 會由 `GoRouter` 的 `redirect` 正規化成無尾隨斜線。）

## Nginx 範例

```nginx
server {
    listen 443 ssl;
    server_name fastdating1.com;

    root /var/www/fastdating/build/web;
    index index.html;

    location / {
        try_files $uri $uri/ /index.html;
    }

    # 靜態資源快取（可依實際檔名調整）
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|webp|woff2?|ttf|wasm)$ {
        try_files $uri =404;
        add_header Cache-Control "public, max-age=31536000, immutable";
    }

    location = /sitemap.xml {
        try_files $uri =404;
        add_header Cache-Control "public, max-age=3600";
    }
}
```

## Google Search Console

1. 驗證網域或 URL 前綴 `https://fastdating1.com/`  
2. **Sitemaps** 新增：`https://fastdating1.com/sitemap.xml`  
3. 來源檔：`web/sitemap.xml`（建置後在網站根目錄）

活動詳情頁 `/events/{slug}` 可依後台活動動態擴充 sitemap（需另行腳本或手動維護）。

## 備註

- 各頁 `title`／`meta description` 由 Web 執行期透過 `lib/seo/seo_apply_web.dart` 更新；搜尋引擎若執行 JavaScript 可讀取。  
- 若需「首屏即為完整 HTML」可另行導入預渲染（prerender）或 SSR，非本變更範圍。
