import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../services/chat_firestore_service.dart';
import '../utils/avatar_field.dart';
import '../utils/constants.dart';
import '../utils/save_data_url.dart';
import 'chat_voice_playback.dart';

/// 聊天氣泡：文字／圖片（可點放大）／語音（可播放）／檔案（可開啟或下載）
class ChatBubble extends StatelessWidget {
  final bool isMe;
  final String text;
  final String time;
  final double fontSizeExtra;
  final String? imageDataUrl;
  final String? messageType;
  final String? voiceDataUrl;
  final String? localVoicePath;
  final String? fileName;
  final String? fileDataUrl;

  /// 本人發出之雲端訊息：顯示右下角剔號（已送達／對方已讀）。
  final bool showReadReceipt;

  /// 對方已讀（雙剔）；否則單剔表示已送達伺服器。
  final bool readByPeer;

  const ChatBubble({
    super.key,
    required this.isMe,
    required this.text,
    required this.time,
    this.fontSizeExtra = 0,
    this.imageDataUrl,
    this.messageType,
    this.voiceDataUrl,
    this.localVoicePath,
    this.fileName,
    this.fileDataUrl,
    this.showReadReceipt = false,
    this.readByPeer = false,
  });

  void _openImageFullScreen(BuildContext context, Uint8List bytes) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(12),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Center(
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 5,
                child: Image.memory(bytes, fit: BoxFit.contain),
              ),
            ),
            Positioned(
              right: 0,
              top: 0,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 28),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final imageBytes =
        imageDataUrl != null ? decodeAvatarFieldToBytes(imageDataUrl) : null;
    final align = isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final mt = messageType ?? '';

    final isImageType = mt == ChatFirestoreService.messageTypeImage ||
        (imageDataUrl != null && imageDataUrl!.trim().isNotEmpty);
    final isVoice = mt == ChatFirestoreService.messageTypeVoice ||
        voiceDataUrl != null ||
        localVoicePath != null;
    final isFile = mt == ChatFirestoreService.messageTypeFile ||
        (fileDataUrl != null && (fileName ?? '').isNotEmpty);

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: isMe ? AppConstants.blue : AppConstants.grey.withOpacity(0.2),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMe ? 16 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment: align,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isImageType) ...[
              if (imageBytes != null)
                GestureDetector(
                  onTap: () => _openImageFullScreen(context, imageBytes),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: 220,
                        maxWidth: MediaQuery.of(context).size.width * 0.68,
                      ),
                      child: Image.memory(
                        imageBytes,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    '圖片無法顯示',
                    style: TextStyle(
                      color: isMe ? AppConstants.white : AppConstants.grey,
                      fontSize: 14 + fontSizeExtra,
                    ),
                  ),
                ),
              if (text.trim().isNotEmpty && text.trim() != '📷 圖片') ...[
                const SizedBox(height: 6),
                Text(
                  text,
                  style: TextStyle(
                    color: isMe ? AppConstants.white : Colors.black87,
                    fontSize: 15 + fontSizeExtra,
                  ),
                  textAlign: isMe ? TextAlign.right : TextAlign.left,
                ),
              ],
            ] else if (isVoice) ...[
              if (voiceDataUrl != null || (localVoicePath ?? '').isNotEmpty)
                _VoicePlaybackTile(
                  isMe: isMe,
                  fontSizeExtra: fontSizeExtra,
                  voiceDataUrl: voiceDataUrl,
                  localPath: localVoicePath,
                )
              else
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.mic_off_outlined,
                      size: 20,
                      color: isMe ? Colors.white70 : AppConstants.grey,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '語音訊息（無法播放）',
                      style: TextStyle(
                        color: isMe ? AppConstants.white : Colors.black87,
                        fontSize: 14 + fontSizeExtra,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
            ] else if (isFile) ...[
              InkWell(
                enableFeedback: false,
                onTap: fileDataUrl != null && (fileName ?? '').isNotEmpty
                    ? () async {
                        try {
                          await saveDataUrlToDevice(fileDataUrl!, fileName!);
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('無法開啟檔案：$e')),
                            );
                          }
                        }
                      }
                    : null,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.attach_file,
                        color: isMe
                            ? AppConstants.white
                            : AppConstants.primaryColor,
                        size: 22,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          fileName ?? text,
                          style: TextStyle(
                            color: isMe ? AppConstants.white : Colors.black87,
                            fontSize: 15 + fontSizeExtra,
                            fontWeight: FontWeight.w500,
                            decoration: TextDecoration.underline,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.open_in_new,
                        size: 18,
                        color: isMe ? Colors.white70 : AppConstants.grey,
                      ),
                    ],
                  ),
                ),
              ),
            ] else ...[
              Text(
                text,
                style: TextStyle(
                  color: isMe ? AppConstants.white : Colors.black87,
                  fontSize: 15 + fontSizeExtra,
                ),
              ),
            ],
            const SizedBox(height: 2),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  time,
                  style: TextStyle(
                    color: isMe
                        ? AppConstants.white.withOpacity(0.8)
                        : AppConstants.grey,
                    fontSize: 11 + fontSizeExtra,
                  ),
                ),
                if (isMe && showReadReceipt) ...[
                  const SizedBox(width: 4),
                  Icon(
                    readByPeer ? Icons.done_all : Icons.done,
                    size: 16,
                    color: isMe
                        ? AppConstants.white.withOpacity(0.88)
                        : AppConstants.grey,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _VoicePlaybackTile extends StatefulWidget {
  const _VoicePlaybackTile({
    required this.isMe,
    required this.fontSizeExtra,
    this.voiceDataUrl,
    this.localPath,
  });

  final bool isMe;
  final double fontSizeExtra;
  final String? voiceDataUrl;
  final String? localPath;

  @override
  State<_VoicePlaybackTile> createState() => _VoicePlaybackTileState();
}

class _VoicePlaybackTileState extends State<_VoicePlaybackTile> {
  final AudioPlayer _player = AudioPlayer();
  StreamSubscription<void>? _completeSub;
  bool _playing = false;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _completeSub = _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playing = false);
    });
  }

  @override
  void dispose() {
    _completeSub?.cancel();
    unawaited(_player.dispose());
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_loading) return;
    final st = _player.state;
    if (st == PlayerState.playing) {
      await _player.pause();
      if (mounted) setState(() => _playing = false);
      return;
    }
    if (st == PlayerState.paused) {
      await _player.resume();
      if (mounted) setState(() => _playing = true);
      return;
    }
    setState(() => _loading = true);
    try {
      await _player.stop();
      await playChatVoiceAudio(
        _player,
        voiceDataUrl: widget.voiceDataUrl,
        localPath: widget.localPath,
      );
      if (mounted) {
        setState(() {
          _playing = true;
          _loading = false;
        });
      }
    } catch (e, st) {
      debugPrint('voice play $e\n$st');
      if (mounted) {
        setState(() {
          _loading = false;
          _playing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final fg = widget.isMe ? AppConstants.white : AppConstants.primaryColor;
    final playIconSize = 40.0 - 0.3 * AppConstants.logicalPxPerCm;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          onPressed: _loading ? null : _toggle,
          icon: _loading
              ? SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: fg,
                  ),
                )
              : Icon(
                  _playing
                      ? Icons.pause_circle_filled
                      : Icons.play_circle_filled,
                  color: fg,
                  size: playIconSize.clamp(22.0, 40.0),
                ),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
        ),
        const SizedBox(width: 6),
        Text(
          '語音訊息',
          style: TextStyle(
            color: widget.isMe ? AppConstants.white : Colors.black87,
            fontSize: 15 + widget.fontSizeExtra,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 4),
        Icon(Icons.mic, size: 18, color: fg.withOpacity(0.9)),
      ],
    );
  }
}
