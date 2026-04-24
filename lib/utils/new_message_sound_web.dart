import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

/// Web：瀏覽器**無法**保證與手機內建「訊息」同一條鈴聲；本頁以 Web Audio 作短提示。
/// iOS Safari 常將 [AudioContext] 置於 `suspended` 或阻擋自動播放——請配合 [index.html] 內
/// 首次觸控寫入 `window.__fdMsgAudioCtx`；播放前仍會 [AudioContext.resume]。
web.AudioContext? _localContext;

web.AudioContext? _contextFromUnlockedWindow() {
  final o = (web.window as JSObject)['__fdMsgAudioCtx'];
  if (o == null) return null;
  return o as web.AudioContext;
}

web.AudioContext _getOrCreateContext() {
  return _contextFromUnlockedWindow() ?? (_localContext ??= web.AudioContext());
}

Future<void> playNewMessageNotificationSound() async {
  try {
    final ctx = _getOrCreateContext();

    if (ctx.state == 'suspended') {
      await ctx.resume().toDart;
    }

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
