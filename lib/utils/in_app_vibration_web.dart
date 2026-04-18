import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Web：[Vibration API](https://developer.mozilla.org/en-US/docs/Web/API/Vibration_API)。
/// Android Chrome／Firefox 等可震動；iOS Safari 不支援（無效果）。
Future<void> triggerInAppNotificationVibration() async {
  try {
    web.window.navigator.vibrate(56.toJS);
  } catch (_) {}
}
