import 'package:flutter_web_plugins/flutter_web_plugins.dart';

/// Web：使用 path 模式（無 #），利於 SEO 與真實路徑。
void configureWebUrlStrategy() {
  usePathUrlStrategy();
}
