import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugPrint, defaultTargetPlatform, kIsWeb;
import 'package:flutter/services.dart';

import '../utils/in_app_vibration.dart';
import '../utils/short_notification_wav.dart';

/// 依 [NotificationProvider] 開關播放提示音；全站共用、含去抖。
///
/// - **App 內音效**／**震動**：控制 [playForAppNotification]（邀聊邀請、FCM 非聊天類、按心等）。
/// - **訊息相關提示音**：[playForChatMessage] 是否播聲由呼叫端傳入（通常與「App 內音效」一致）。
/// - **iOS／Android**：使用 [SystemSoundType.alert]（系統提示音，貼近手機通知）。
/// - **Web**（含 fastdating1.com）：瀏覽器無法指定系統簡訊鈴聲，改播內建極短 WAV（不在全站觸控時預熱，避免與「按鍵聲」混淆）。
/// - 主殼 [IndexedStack] 會同時掛載首頁／邀聊通知／訊息等分頁，於背景更新時仍會觸發上述邏輯。
class InAppNotificationSound {
  InAppNotificationSound._();
  static final InAppNotificationSound instance = InAppNotificationSound._();

  final AudioPlayer _player = AudioPlayer();
  Uint8List? _wav;
  DateTime? _lastPlayed;
  static const int _debounceMs = 420;

  Uint8List _bytes() => _wav ??= buildShortNotificationWavBytes();

  /// 手機系統提示音（Web／桌面仍用內建 WAV）。
  bool get _usePhoneSystemAlertSound {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android;
  }

  bool _shouldDebounce() {
    final now = DateTime.now();
    if (_lastPlayed != null &&
        now.difference(_lastPlayed!).inMilliseconds < _debounceMs) {
      return true;
    }
    _lastPlayed = now;
    return false;
  }

  /// 一般通知（訊息列表、邀聊、FCM 前景、訂閱到期提醒等）
  Future<void> playForAppNotification({
    required bool inAppSound,
    bool inAppVibration = true,
  }) async {
    if (!inAppSound && !inAppVibration) return;
    if (_shouldDebounce()) return;
    await _playBody(playSound: inAppSound, vibrate: inAppVibration);
  }

  /// 對話畫面內：新訊息（對方）
  Future<void> playForChatMessage({
    required bool chatSound,
    bool inAppVibration = true,
  }) async {
    if (!chatSound && !inAppVibration) return;
    if (_shouldDebounce()) return;
    await _playBody(playSound: chatSound, vibrate: inAppVibration);
  }

  Future<void> _playBody({
    required bool vibrate,
    required bool playSound,
  }) async {
    if (vibrate) {
      await triggerInAppNotificationVibration();
    }
    if (!playSound) return;
    // iOS／Android：系統提示音（貼近「訊息／通知」）；Web 與桌面版改播內建極短 WAV。
    if (_usePhoneSystemAlertSound) {
      try {
        SystemSound.play(SystemSoundType.alert);
        return;
      } catch (e, st) {
        debugPrint('InAppNotificationSound SystemSound: $e\n$st');
      }
    }
    try {
      await _player.setPlayerMode(
        kIsWeb ? PlayerMode.mediaPlayer : PlayerMode.lowLatency,
      );
      await _player.setReleaseMode(ReleaseMode.stop);
      await _player.stop();
      await _player.play(BytesSource(_bytes()));
    } catch (e, st) {
      debugPrint('InAppNotificationSound: $e\n$st');
    }
  }
}
