import 'new_message_sound_io.dart'
    if (dart.library.html) 'new_message_sound_web.dart' as sound_impl;

/// 新訊息短提示音（依平台：原生系統聲；Web 為 [AudioContext] 短 beep）。
Future<void> playNewMessageNotificationSound() =>
    sound_impl.playNewMessageNotificationSound();
