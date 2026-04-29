import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' as foundation;
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../utils/constants.dart';
import '../utils/image_upload_compress.dart';
import '../utils/avatar_field.dart';
import '../widgets/avatar_circle.dart';
import '../utils/mock_data.dart';
import '../widgets/pressable_opacity.dart';
import '../widgets/chat_bubble.dart';
import '../providers/auth_provider.dart';
import '../providers/language_provider.dart';
import '../services/chat_firestore_service.dart';
import '../services/chat_quota_service.dart';
import '../services/firebase_bootstrap.dart';
import '../services/firestore_paths.dart';
import '../services/chat_receipt_cookies.dart';
import 'camera_capture_page.dart';
import '../widgets/chat_quota_gate.dart';

/// 配對人對話頁：右上角設定/活動、對話中間日期、底部可輸入文字／貼圖／拍照。
/// 已登入且對方為 Firebase uid 時，訊息經 [ChatFirestoreService] 同步至 Firestore；否則為本機 mock。
class ChatDetailPage extends StatefulWidget {
  final String userId;
  final String name;
  final String avatar;
  final String? conversationId;

  const ChatDetailPage({
    super.key,
    required this.userId,
    required this.name,
    required this.avatar,
    this.conversationId,
  });

  @override
  State<ChatDetailPage> createState() => _ChatDetailPageState();
}

class _ChatDetailPageState extends State<ChatDetailPage> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late List<Map<String, dynamic>> _messages;

  /// 已登入且對方為真實 Firebase uid：使用 Firestore 一對一對話同步。
  bool _useCloudChat(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    if (!FirebaseBootstrap.isReady || auth.uid == null) return false;
    final id = widget.userId;
    if (id.startsWith('demo_')) return false;
    return id.length >= 15;
  }

  String _conversationId(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    if (!FirebaseBootstrap.isReady || auth.uid == null) return '';
    if (widget.conversationId != null && widget.conversationId!.isNotEmpty) {
      return widget.conversationId!;
    }
    if (widget.userId.length >= 15 && !widget.userId.startsWith('demo_')) {
      return ChatFirestoreService.pairConversationId(auth.uid!, widget.userId);
    }
    return '';
  }

  final ImagePicker _imagePicker = ImagePicker();

  bool _scheduledEnsureConversation = false;
  bool _scheduledVerifyMessagingAccess = false;
  Timer? _markPeerReadDebounce;

  @override
  void initState() {
    super.initState();
    if (foundation.kIsWeb && widget.userId.length >= 20) {
      ChatReceiptCookies.setLastChatPeerUid(widget.userId);
    }
    // 替換為 API 請求
    _messages = List.from(getMockMessages(widget.userId));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_useCloudChat(context)) return;
    if (!_scheduledEnsureConversation) {
      _scheduledEnsureConversation = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _ensureFirestoreConversation();
      });
    }
    if (!_scheduledVerifyMessagingAccess) {
      _scheduledVerifyMessagingAccess = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _verifyMessagingAccess();
      });
    }
  }

  Future<void> _verifyMessagingAccess() async {
    if (!mounted) return;
    if (!_useCloudChat(context)) return;
    final auth = Provider.of<AuthProvider>(context, listen: false);
    if (auth.uid == null) return;
    final ok = await ChatFirestoreService.instance.canOpenMessagingConversation(
      myUid: auth.uid!,
      peerUid: widget.userId,
    );
    if (!mounted || ok) return;
    final lang = Provider.of<LanguageProvider>(context, listen: false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(lang.getString('messaging_requires_invite_accept')),
      ),
    );
    Navigator.of(context).pop();
  }

  Future<void> _ensureFirestoreConversation() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    if (auth.uid == null) return;
    final cid = _conversationId(context);
    if (cid.isEmpty) return;
    try {
      await ChatFirestoreService.instance.ensureConversationForPair(
        conversationId: cid,
        myUid: auth.uid!,
        peerUid: widget.userId,
      );
    } catch (e, st) {
      debugPrint('ensureFirestoreConversation $e\n$st');
    }
  }

  /// 與 [ChatFirestoreService.sendImageMessage] 相容之 data URL。
  String _imageDataUrlFromBytes(List<int> bytes) {
    final isPng = bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47;
    final mime = isPng ? 'image/png' : 'image/jpeg';
    return 'data:$mime;base64,${base64Encode(bytes)}';
  }

  @override
  void dispose() {
    _markPeerReadDebounce?.cancel();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  static const List<String> _emojiList = [
    '😀',
    '😃',
    '😄',
    '😁',
    '😅',
    '😂',
    '🤣',
    '😊',
    '😇',
    '🙂',
    '🙃',
    '😉',
    '😌',
    '😍',
    '🥰',
    '😘',
    '😗',
    '😙',
    '😚',
    '😋',
    '😛',
    '😜',
    '🤪',
    '😝',
    '🤑',
    '🤗',
    '🤭',
    '🤫',
    '🤔',
    '🤐',
    '🤨',
    '😐',
    '😑',
    '😶',
    '😏',
    '😒',
    '🙄',
    '😬',
    '🤥',
    '😌',
    '😔',
    '😪',
    '🤤',
    '😴',
    '😷',
    '🤒',
    '🤕',
    '🤢',
    '🤮',
    '🤧',
    '🥵',
    '🥶',
    '🥴',
    '😵',
    '🤯',
    '🤠',
    '🥳',
    '😎',
    '🤓',
    '🧐',
    '😕',
    '😟',
    '🙁',
    '☹️',
    '😮',
    '😯',
    '😲',
    '😳',
    '🥺',
    '😦',
    '😧',
    '😨',
    '😰',
    '😥',
    '😢',
    '😭',
    '😤',
    '😡',
    '😠',
    '🤬',
    '😈',
    '💀',
    '👻',
    '💩',
    '🤡',
    '👽',
    '👾',
    '🤖',
    '😺',
    '😸',
    '😹',
    '😻',
    '😼',
    '😽',
    '🙀',
    '😿',
  ];

  void _showEmojiPicker() {
    FocusScope.of(context).unfocus();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: 340,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('所有貼圖',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                        padding: EdgeInsets.zero,
                        constraints:
                            const BoxConstraints(minWidth: 40, minHeight: 40),
                      ),
                      TextButton(
                        onPressed: () {
                          final text = _controller.text.trim();
                          if (text.isNotEmpty) _sendMessage();
                          Navigator.pop(context);
                        },
                        child: const Text('傳送'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.all(12),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 8,
                  mainAxisSpacing: 4,
                  crossAxisSpacing: 4,
                  childAspectRatio: 1,
                ),
                itemCount: _emojiList.length,
                itemBuilder: (context, index) {
                  final emoji = _emojiList[index];
                  return InkWell(
                    enableFeedback: false,
                    onTap: () {
                      _controller.text = _controller.text + emoji;
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Center(
                      child: Text(emoji, style: const TextStyle(fontSize: 28)),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _takePhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('拍照'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('從相簿選擇'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;

    XFile? picked;
    if (source == ImageSource.camera && foundation.kIsWeb) {
      final path = await Navigator.push<String>(
        context,
        MaterialPageRoute(builder: (_) => const CameraCapturePage()),
      );
      if (path == null || !mounted) return;
      picked = XFile(path);
    } else {
      try {
        picked = await _imagePicker.pickImage(
          source: source,
          imageQuality: 78,
          maxWidth: 1280,
          maxHeight: 1280,
        );
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(
                    '無法開啟${source == ImageSource.camera ? '相機' : '相簿'}: $e')),
          );
        }
        return;
      }
    }
    if (picked == null || !mounted) return;

    var bytes = await picked.readAsBytes();
    if (bytes.isEmpty) return;
    bytes = compressForFirestoreImageField(bytes);
    if (!mounted) return;

    if (_useCloudChat(context)) {
      const maxRaw = 4 * 1024 * 1024;
      if (bytes.length > maxRaw) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('圖片過大，請選較小或裁切後再傳')),
          );
        }
        return;
      }
      final auth = Provider.of<AuthProvider>(context, listen: false);
      final cid = _conversationId(context);
      if (auth.uid == null || cid.isEmpty) return;
      try {
        final dataUrl = _imageDataUrlFromBytes(bytes);
        if (dataUrl.length > 950000) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('圖片過大，無法上傳')),
            );
          }
          return;
        }
        await ChatFirestoreService.instance.sendImageMessage(
          conversationId: cid,
          senderId: auth.uid!,
          imageDataUrl: dataUrl,
        );
      } on ChatQuotaExceededException {
        if (mounted) await showChatQuotaPaywallDialog(context);
      } catch (e) {
        _handleOutboundSendFailure(e);
      }
      return;
    }

    _addAttachmentMessage(
      source == ImageSource.camera ? '照片' : '圖片',
      picked.path,
    );
  }

  void _addAttachmentMessage(String type, String path) {
    setState(() {
      _messages.add({
        'id': 'new_${DateTime.now().millisecondsSinceEpoch}',
        'isMe': true,
        'text': '[$type] $path',
        'time': _formatTime(DateTime.now()),
      });
    });
    _scrollToBottom();
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    if (_useCloudChat(context)) {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      final cid = _conversationId(context);
      if (auth.uid != null && cid.isNotEmpty) {
        try {
          await ChatFirestoreService.instance.sendTextMessage(
            conversationId: cid,
            senderId: auth.uid!,
            text: text,
          );
        } on ChatQuotaExceededException {
          if (mounted) await showChatQuotaPaywallDialog(context);
        } catch (e) {
          _handleOutboundSendFailure(e);
        }
      }
      _controller.clear();
      return;
    }
    setState(() {
      _messages.add({
        'id': 'new_${DateTime.now().millisecondsSinceEpoch}',
        'isMe': true,
        'text': text,
        'time': _formatTime(DateTime.now()),
      });
    });
    _controller.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  void _handleOutboundSendFailure(Object e) {
    if (!mounted) return;
    if (e.toString().contains('messaging_requires_invitation_accept')) {
      final lang = Provider.of<LanguageProvider>(context, listen: false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(lang.getString('messaging_requires_invite_accept')),
        ),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('傳送失敗：$e')),
    );
  }

  String _formatTime(DateTime t) {
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  void _showPeerAvatarLightbox(String avatar) {
    final a = avatar.trim();
    if (a.isEmpty) return;
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(20),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Center(
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 4,
                child: _peerAvatarPreviewChild(a),
              ),
            ),
            Positioned(
              right: -8,
              top: -8,
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

  Widget _peerAvatarPreviewChild(String avatar) {
    final bytes = decodeAvatarFieldToBytes(avatar);
    if (bytes != null) {
      return Image.memory(bytes, fit: BoxFit.contain);
    }
    final u = avatar.trim();
    if (u.startsWith('http')) {
      return Image.network(
        u,
        fit: BoxFit.contain,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return const SizedBox(
            width: 120,
            height: 120,
            child:
                Center(child: CircularProgressIndicator(color: Colors.white)),
          );
        },
        errorBuilder: (_, __, ___) => const Icon(
          Icons.broken_image_outlined,
          size: 80,
          color: Colors.white54,
        ),
      );
    }
    return const Icon(Icons.person, size: 120, color: Colors.white54);
  }

  /// 對話對象頭像（點擊放大預覽）；Firestore 模式下即時讀取 [users]。
  Widget _buildPeerAvatarForAppBar() {
    final fallback = widget.avatar;
    if (!FirebaseBootstrap.isReady || widget.userId.length < 20) {
      return GestureDetector(
        onTap: () => _showPeerAvatarLightbox(fallback),
        child: AvatarCircle(radius: 18, avatar: fallback),
      );
    }
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection(FirestorePaths.users)
          .doc(widget.userId)
          .snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data();
        final url = (data?['avatar'] as String?)?.trim();
        final resolved = (url != null && url.isNotEmpty) ? url : fallback;
        return GestureDetector(
          onTap: () => _showPeerAvatarLightbox(resolved),
          child: AvatarCircle(radius: 18, avatar: resolved),
        );
      },
    );
  }

  Widget _buildFirestoreMessageList(BuildContext context, String dateStr) {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final cid = _conversationId(context);
    final myUid = auth.uid!;
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: ChatFirestoreService.instance.watchMessages(cid),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('讀取失敗：${snapshot.error}'));
        }
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final extra = MediaQuery.sizeOf(context).width >=
                AppConstants.layoutWideBreakpoint
            ? AppConstants.chatDetailDesktopMessageExtraTenthCm
            : 0.0;
        final docs = snapshot.data?.docs ?? [];
        /// 對方留在對話內時仍會持續收到新訊息；僅首次標已讀會漏掉後續訊息之 [readAt]，故用 debounce 重複標記。
        /// 空對話也需呼叫：將 [unreadCountByUid] 歸零（訊息列表紅點）。
        _markPeerReadDebounce?.cancel();
        _markPeerReadDebounce = Timer(const Duration(milliseconds: 450), () {
          if (!mounted) return;
          ChatFirestoreService.instance
              .markPeerOutgoingMessagesAsReadByViewer(
            conversationId: cid,
            peerUid: widget.userId,
            viewerUid: myUid,
          ).catchError((Object e, StackTrace st) {
            debugPrint('markPeerRead $e\n$st');
          });
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController
                .jumpTo(_scrollController.position.maxScrollExtent);
          }
        });
        final docCount = docs.length;

        /// 有訊息：日期列 + N 則；無訊息：日期列 + 空狀態（避免只剩日期看似「壞掉」）。
        final listItemCount = docCount == 0 ? 2 : docCount + 1;
        return ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          itemCount: listItemCount,
          itemBuilder: (context, index) {
            if (index == 0) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Center(
                  child: Text(
                    '日期: $dateStr',
                    style: TextStyle(
                      fontSize: 13 + extra,
                      color: AppConstants.grey,
                    ),
                  ),
                ),
              );
            }
            if (docCount == 0 && index == 1) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(8, 24, 8, 24),
                child: Center(
                  child: Text(
                    '尚無聊天紀錄。\n個人資料與聊天是分開儲存的；在下方輸入即可傳送第一則訊息。',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14 + extra,
                      height: 1.45,
                      color: AppConstants.grey,
                    ),
                  ),
                ),
              );
            }
            final doc = docs[index - 1];
            final data = doc.data();
            final senderId = data['senderId'] as String? ?? '';
            final isMe = senderId == myUid;
            final text = data['text'] as String? ?? '';
            final msgType = data['type'] as String? ?? 'text';
            final imageDataUrl = data['imageDataUrl'] as String?;
            final voiceDataUrl = data['voiceDataUrl'] as String?;
            final fileName = data['fileName'] as String?;
            final fileDataUrl = data['fileDataUrl'] as String?;
            final createdAt = data['createdAt'];
            DateTime? t;
            if (createdAt is Timestamp) {
              t = createdAt.toDate();
            }
            final timeStr = t != null ? _formatTime(t) : '';
            final readAt = data['readAt'];
            final readByPeer = isMe && readAt != null;
            return ChatBubble(
              isMe: isMe,
              text: text,
              time: timeStr,
              fontSizeExtra: extra,
              messageType: msgType,
              imageDataUrl: msgType == ChatFirestoreService.messageTypeImage
                  ? imageDataUrl
                  : null,
              voiceDataUrl: voiceDataUrl,
              fileName: fileName,
              fileDataUrl: fileDataUrl,
              showReadReceipt: isMe,
              readByPeer: readByPeer,
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final dateStr =
        '${now.year}/${now.month.toString().padLeft(2, '0')}/${now.day.toString().padLeft(2, '0')}';
    final chatDesktopExtra =
        MediaQuery.sizeOf(context).width >= AppConstants.layoutWideBreakpoint
            ? AppConstants.chatDetailDesktopMessageExtraTenthCm
            : 0.0;
    final viewPad = MediaQuery.viewPaddingOf(context);
    /// Android：底部輸入列避開系統導航列，並依需求再上移 1.5cm，避免被遮擋。
    final chatInputBottomInset = viewPad.bottom +
        (foundation.defaultTargetPlatform == foundation.TargetPlatform.android
            ? 1.5 * AppConstants.logicalPxPerCm
            : 0.0);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            _buildPeerAvatarForAppBar(),
            const SizedBox(width: 10),
            Text(
              widget.name,
              style: TextStyle(
                color: Colors.black87,
                fontSize:
                    AppConstants.appBarTitleResolvedSize(context, base: 20),
              ),
            ),
          ],
        ),
        backgroundColor: AppConstants.appBarBackground,
        toolbarHeight: AppConstants.appBarToolbarHeight,
        foregroundColor: Colors.black87,
        elevation: 0,
        actions: [
          PressableOpacity(
            onPressed: () {
              context.go('/setting');
            },
            child: Container(
              width: 40,
              height: 40,
              margin: const EdgeInsets.only(right: 4),
              decoration: BoxDecoration(
                color: AppConstants.primaryColor,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.settings, color: Colors.white, size: 22),
            ),
          ),
          PressableOpacity(
            onPressed: () {
              context.go('/event');
            },
            child: Container(
              width: 40,
              height: 40,
              margin: const EdgeInsets.only(right: 12),
              decoration: BoxDecoration(
                color: AppConstants.primaryColor,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.event, color: Colors.white, size: 22),
            ),
          ),
        ],
      ),
      backgroundColor: AppConstants.backgroundColor,
      body: Column(
        children: [
          Expanded(
            child: _useCloudChat(context)
                ? _buildFirestoreMessageList(context, dateStr)
                : ListView.builder(
                    controller: _scrollController,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    itemCount: _messages.length + 1,
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Center(
                            child: Text(
                              '日期: $dateStr',
                              style: TextStyle(
                                fontSize: 13 + chatDesktopExtra,
                                color: AppConstants.grey,
                              ),
                            ),
                          ),
                        );
                      }
                      final m = _messages[index - 1];
                      final isMeMock = m['isMe'] as bool;
                      return ChatBubble(
                        isMe: isMeMock,
                        text: m['text'] as String,
                        time: m['time'] as String,
                        fontSizeExtra: chatDesktopExtra,
                        messageType: m['type'] as String?,
                        imageDataUrl: m['imageDataUrl'] as String?,
                        voiceDataUrl: m['voiceDataUrl'] as String?,
                        localVoicePath: m['localVoicePath'] as String?,
                        fileName: m['fileName'] as String?,
                        fileDataUrl: m['fileDataUrl'] as String?,
                        showReadReceipt: isMeMock,
                        readByPeer: isMeMock && m['readByPeer'] == true,
                      );
                    },
                  ),
          ),
          Container(
            padding: EdgeInsets.only(
              left: 4,
              right: 8,
              top: 10,
              bottom: 10 + chatInputBottomInset,
            ),
            decoration: BoxDecoration(
              color: AppConstants.white,
              boxShadow: [
                BoxShadow(
                  color: AppConstants.grey.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, -1),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton(
                  icon: const Icon(Icons.emoji_emotions_outlined),
                  onPressed: _showEmojiPicker,
                  color: AppConstants.grey,
                  iconSize: 26,
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  constraints:
                      const BoxConstraints(minWidth: 40, minHeight: 40),
                ),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: InputDecoration(
                      hintText: '訊息',
                      filled: true,
                      fillColor: AppConstants.backgroundColor.withOpacity(0.6),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                    ),
                    maxLines: 4,
                    minLines: 1,
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.camera_alt_outlined),
                      onPressed: _takePhoto,
                      color: AppConstants.grey,
                      iconSize: 24,
                      padding: const EdgeInsets.all(4),
                      visualDensity: VisualDensity.compact,
                      constraints:
                          const BoxConstraints(minWidth: 36, minHeight: 36),
                    ),
                    const SizedBox(width: 4),
                    ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _controller,
                      builder: (context, value, _) {
                        final enabled = value.text.trim().isNotEmpty;
                        return PressableOpacity(
                          onPressed: enabled ? _sendMessage : null,
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: enabled
                                  ? AppConstants.primaryColor
                                  : AppConstants.grey,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.send,
                                color: Colors.white, size: 22),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
