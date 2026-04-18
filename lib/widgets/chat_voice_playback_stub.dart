import 'package:audioplayers/audioplayers.dart';

import '../utils/data_url_bytes.dart';

/// Web：以 [BytesSource] 播放 data URL；本機路徑以 [UrlSource]。
Future<void> playChatVoiceAudio(
  AudioPlayer player, {
  required String? voiceDataUrl,
  required String? localPath,
}) async {
  await player.setPlayerMode(PlayerMode.mediaPlayer);
  await player.setReleaseMode(ReleaseMode.stop);
  await player.stop();
  if (voiceDataUrl != null && voiceDataUrl.trim().isNotEmpty) {
    final bytes = decodeDataUrlBase64ToBytes(voiceDataUrl);
    if (bytes == null || bytes.isEmpty) return;
    await player.play(BytesSource(bytes));
    return;
  }
  final p = localPath?.trim() ?? '';
  if (p.isEmpty) return;
  await player.play(UrlSource(p));
}
