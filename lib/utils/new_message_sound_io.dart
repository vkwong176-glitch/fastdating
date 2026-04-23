import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/services.dart';

const _messageSoundChannel = MethodChannel('app.message_sound');

/// Android：透過原生 [RingtoneManager.TYPE_NOTIFICATION]，與系統「預設通知鈴聲」一致。
/// iOS：無法讀取「訊息」App 專用鈴聲，改以 [SystemSoundType.alert] 近似系統提示。
/// 其餘平台：觸感 + 點按聲。
Future<void> playNewMessageNotificationSound() async {
  try {
    if (defaultTargetPlatform == TargetPlatform.android) {
      await _messageSoundChannel.invokeMethod<void>('playDefaultNotification');
      return;
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      await HapticFeedback.lightImpact();
      SystemSound.play(SystemSoundType.alert);
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
