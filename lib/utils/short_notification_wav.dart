import 'dart:math' as math;
import 'dart:typed_data';

/// 產生極短 PCM WAV（無需 assets），供 Web／桌面／行動裝置播放提示音。
Uint8List buildShortNotificationWavBytes({
  int sampleRate = 22050,
  double durationSec = 0.22,
  double frequencyHz = 880,
  double volume = 0.22,
}) {
  final n = (sampleRate * durationSec).round();
  final pcm = Int16List(n);
  final twoPiF = 2 * math.pi * frequencyHz;
  for (var i = 0; i < n; i++) {
    final t = i / sampleRate;
    final env = i < n * 0.08 ? i / (n * 0.08) : (1.0 - (i - n * 0.08) / (n * 0.92)).clamp(0.0, 1.0);
    final s = volume * env * math.sin(twoPiF * t);
    pcm[i] = (s * 32767).round().clamp(-32768, 32767);
  }
  final dataSize = pcm.length * 2;
  final buf = ByteData(44 + dataSize);
  var o = 0;
  void wStr(String s) {
    for (var i = 0; i < s.length; i++) {
      buf.setUint8(o++, s.codeUnitAt(i));
    }
  }

  wStr('RIFF');
  buf.setUint32(o, 36 + dataSize, Endian.little);
  o += 4;
  wStr('WAVE');
  wStr('fmt ');
  buf.setUint32(o, 16, Endian.little);
  o += 4;
  buf.setUint16(o, 1, Endian.little);
  o += 2;
  buf.setUint16(o, 1, Endian.little);
  o += 2;
  buf.setUint32(o, sampleRate, Endian.little);
  o += 4;
  buf.setUint32(o, sampleRate * 2, Endian.little);
  o += 4;
  buf.setUint16(o, 2, Endian.little);
  o += 2;
  buf.setUint16(o, 16, Endian.little);
  o += 2;
  wStr('data');
  buf.setUint32(o, dataSize, Endian.little);
  o += 4;
  for (var i = 0; i < pcm.length; i++) {
    buf.setInt16(o, pcm[i], Endian.little);
    o += 2;
  }
  return buf.buffer.asUint8List();
}
