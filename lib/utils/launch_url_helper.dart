import 'launch_url_helper_stub.dart'
    if (dart.library.html) 'launch_url_helper_web.dart' as impl;

/// 開啟連結（Web 使用同步 window.open 避免被瀏覽器阻擋）
void openLink(String url) {
  impl.openLink(url);
}
