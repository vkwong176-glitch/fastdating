import 'package:web/web.dart' as web;

/// Web：瀏覽器**無法**播放與手機內建「訊息」或系統**同一條**通知鈴聲，僅能以 Web Audio 作短提示。
/// 與內建鈴聲完全一致請使用 **Android／iOS App**；若需與 FCM 相同聲音，可依賴系統推播（非本頁內偵測路徑）。
Future<void> playNewMessageNotificationSound() async {
  try {
    final ctx = web.AudioContext();
    final osc = ctx.createOscillator();
    final gain = ctx.createGain();
    osc.frequency.value = 880;
    gain.gain.value = 0.07;
    osc.connect(gain);
    gain.connect(ctx.destination);
    final now = ctx.currentTime;
    osc.start(now);
    osc.stop(now + 0.12);
  } catch (_) {}
}
