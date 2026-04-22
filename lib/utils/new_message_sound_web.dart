import 'package:web/web.dart' as web;

/// Web：Web Audio 短提示音（系統內 [SystemSound] 於網頁為 no-op）。
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
