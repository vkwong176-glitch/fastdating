import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../utils/data_url_bytes.dart';

String _voiceExtFromDataUrl(String dataUrl) {
  final lower = dataUrl.toLowerCase();
  if (lower.contains('audio/wav')) return '.wav';
  if (lower.contains('audio/mpeg') || lower.contains('audio/mp3')) return '.mp3';
  return '.m4a';
}

/// iOS／Android：data URL 先寫入暫存檔再 [DeviceFileSource] 播放（較相容於系統解碼）。
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
    final dir = await getTemporaryDirectory();
    final file = File(
      p.join(
        dir.path,
        'chat_voice_${DateTime.now().microsecondsSinceEpoch}'
            '${_voiceExtFromDataUrl(voiceDataUrl)}',
      ),
    );
    await file.writeAsBytes(bytes, flush: true);
    await player.play(DeviceFileSource(file.path));
    return;
  }
  final path = localPath?.trim() ?? '';
  if (path.isEmpty) return;
  await player.play(DeviceFileSource(path));
}
