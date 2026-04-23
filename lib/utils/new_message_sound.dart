import 'new_message_sound_io.dart'
    if (dart.library.html) 'new_message_sound_web.dart' as sound_impl;

/// 新訊息提示音：Android 為系統預設通知鈴聲；iOS 為 [SystemSoundType.alert]；Web 為短 beep。
Future<void> playNewMessageNotificationSound() =>
    sound_impl.playNewMessageNotificationSound();
