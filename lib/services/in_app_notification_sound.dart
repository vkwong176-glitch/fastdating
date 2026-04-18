import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugPrint, defaultTargetPlatform, kIsWeb;
import 'package:flutter/services.dart';

import '../utils/in_app_vibration.dart';
import '../utils/short_notification_wav.dart';

/// 依 [NotificationProvider] 開關播放提示音；全站共用、含去抖。
///
/// - **App 內音效**／**震動**：控制 [playForAppNotification]（邀聊邀請、FCM 非聊天類、按心等）。
/// - **對話內音效**：控制 [playForChatMessage]（訊息列表預覽更新、聊天室內對方新訊息、FCM `data.type=chat` 等）。
/// - **iOS／Android**：使用 [SystemSoundType.alert]（系統提示音，貼近手機通知）。
/// - **Web**（含 fastdating1.com）：瀏覽器無法指定系統簡訊鈴聲，改播內建極短 WAV；需曾於頁面內觸控以解鎖音訊（見 [onUserPointerDown]）。
/// - 主殼 [IndexedStack] 會同時掛載首頁／邀聊通知／訊息等分頁，於背景更新時仍會觸發上述邏輯。
class InAppNotificationSound {
  InAppNotificationSound._();
  static final InAppNotificationSound instance = InAppNotificationSound._();

  final AudioPlayer _player = AudioPlayer();
  Uint8List? _wav;
  DateTime? _lastPlayed;
  static const int _debounceMs = 420;

  Uint8List _bytes() => _wav ??= buildShortNotificationWavBytes();

  /// Web（尤其 iOS Safari）會阻擋非手勢觸發的播放；進入主殼後任一次觸控呼叫以解鎖。
  bool _webAudioPrimed = false;

  Future<void> onUserPointerDown() async {
    if (!kIsWeb || _webAudioPrimed) return;
    _webAudioPrimed = true;
    try {
      await _player.setPlayerMode(PlayerMode.mediaPlayer);
      await _player.setReleaseMode(ReleaseMode.stop);
      await _player.stop();
      await _player.play(
        BytesSource(
          buildShortNotificationWavBytes(volume: 0.04, durationSec: 0.06),
        ),
      );
    } catch (e, st) {
      debugPrint('InAppNotificationSound: web prime failed: $e\n$st');
      _webAudioPrimed = false;
    }
  }

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
