import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/services.dart';

const _messageSoundChannel = MethodChannel('app.message_sound');

/// Android：透過原生 [RingtoneManager.TYPE_NOTIFICATION]，與系統「預設通知鈴聲」一致。
/// iOS：透過 [AudioServicesPlaySystemSound] 播放可聽見的系統提示音（與 Android 同 channel）。
/// 其餘平台：觸感 + 點按聲。
Future<void> playNewMessageNotificationSound() async {
  try {
    if (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS) {
      await _messageSoundChannel.invokeMethod<void>('playDefaultNotification');
      return;
    }
    await HapticFeedback.lightImpact();
    SystemSound.play(SystemSoundType.click);
  } catch (_) {
    try {
      await HapticFeedback.lightImpact();
      SystemSound.play(SystemSoundType.click);
    } catch (_) {}
  }
}
