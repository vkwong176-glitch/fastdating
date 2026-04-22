import 'package:flutter/services.dart';

/// 原生：短觸感 + 系統點按聲作為新訊息提示音。
Future<void> playNewMessageNotificationSound() async {
  try {
    await HapticFeedback.lightImpact();
    SystemSound.play(SystemSoundType.click);
  } catch (_) {}
}
