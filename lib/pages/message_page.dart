import 'dart:async' show unawaited;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../utils/constants.dart';
import '../utils/ad_promotion_utils.dart';
import '../providers/feed_provider.dart';
import '../providers/language_provider.dart';
import '../providers/notification_provider.dart';
import '../providers/nav_provider.dart';
import '../services/in_app_notification_sound.dart';
import '../providers/auth_provider.dart';
import '../services/firebase_bootstrap.dart';
import '../services/chat_firestore_service.dart';
import '../services/chat_receipt_cookies.dart';
import '../services/feed_firestore_service.dart';
import '../services/user_firestore_service.dart';
import '../utils/launch_url_helper.dart';
import '../utils/mock_data.dart';
import '../widgets/main_tab_app_bar.dart';
import '../widgets/user_avatar_live.dart';
import '../widgets/chat_quota_gate.dart';
import 'chat_detail_page.dart';
import 'settings_page.dart';
import 'activity_page.dart';

/// 訊息頁：聊天列表
/// 右上角橙色設定、活動按鈕；ListView 含頭像、暱稱、最後一則訊息、未讀紅點、時間
/// 已登入：對象列表與最後預覽來自 Firestore（互配／邀聊）；下方保留示範對話
/// 進入頁面時若有待顯示通知，會同步彈出一次
class MessagePage extends StatefulWidget {
  const MessagePage({super.key});

  @override
  State<MessagePage> createState() => _MessagePageState();
}

class _MessagePageState extends State<MessagePage> {
  /// 用於示範列表異性篩選；載入完成前不附加示範（避免閃爍）
  String? _genderForDemo;

  /// `conversationId` → 指紋；對方發話導致預覽更新時播「對話內音效」（與聊天室內一致）。
  final Map<String, String> _conversationListFingerprints = {};

  /// 略過首次快照，否則登入載入列表會對每一列誤判為「新訊息」。
  bool _skipFirstConversationListSnapshot = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final provider =
          Provider.of<NotificationProvider>(context, listen: false);
      if (provider.hasPending) provider.showAllPendingOnce(context);
      _loadGenderForDemoList();
    });
  }

  void _seedConversationListFingerprints(List<Map<String, dynamic>> real) {
    for (final item in real) {
      final cid = item['conversationId'] as String? ?? '';
      if (cid.isEmpty) continue;
      final sender = item['lastMessageSenderId'] as String? ?? '';
      final ms = item['lastMessageAtMs'] as int? ??
          (item['firestoreListMs'] as int? ?? 0);
      final preview = item['lastMessage'] as String? ?? '';
      _conversationListFingerprints[cid] = '$ms|$sender|$preview';
    }
  }

  /// [IndexedStack] 下訊息分頁仍會收到列表串流，故在其他分頁也能聽到新訊息提示音。
  void _maybePlayNewMessageFromPeerSound(
    List<Map<String, dynamic>> real,
    String myUid,
  ) {
    if (_skipFirstConversationListSnapshot) {
      _skipFirstConversationListSnapshot = false;
      _seedConversationListFingerprints(real);
      return;
    }
    for (final item in real) {
      final cid = item['conversationId'] as String? ?? '';
      if (cid.isEmpty) continue;
      final sender = item['lastMessageSenderId'] as String? ?? '';
      final ms = item['lastMessageAtMs'] as int? ??
          (item['firestoreListMs'] as int? ?? 0);
      final preview = item['lastMessage'] as String? ?? '';
      final fp = '$ms|$sender|$preview';
      final prev = _conversationListFingerprints[cid];
      if (prev != null && fp == prev) continue;
      _conversationListFingerprints[cid] = fp;
      if (sender.isEmpty || sender == myUid) continue;
      final notif = Provider.of<NotificationProvider>(context, listen: false);
      InAppNotificationSound.instance.playForChatMessage(
        chatSound: notif.inAppSound,
        inAppVibration: notif.inAppVibration,
      );
      return;
    }
  }

  Future<void> _loadGenderForDemoList() async {
    if (!FirebaseBootstrap.isReady) return;
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final uid = auth.uid;
    if (uid == null) return;
    final g = await UserFirestoreService.instance.fetchUserGender(uid);
    if (!mounted) return;
    setState(() => _genderForDemo = g);
  }

  /// 真實對話在上；示範在下。[seed] 固定為 uid hash，串流更新時示範列不重排。
  List<Map<String, dynamic>> _mergedChatList({
    required List<Map<String, dynamic>> real,
    required String uid,
  }) {
    final sortedReal = _sortChatsByUnreadThenTime(real);
    if (_genderForDemo == null) return sortedReal;
    final demo = getRandomOppositeSexChatList(
      myGender: _genderForDemo!,
      seed: uid.hashCode,
    );
    return [...sortedReal, ..._sortChatsByUnreadThenTime(demo)];
  }

  List<Map<String, dynamic>> _mergePromotionAdsIntoChats(
    List<Map<String, dynamic>> base,
    List<UserPostItem> promotions, {
    required String pageSalt,
  }) {
    return mergePromotionItems<Map<String, dynamic>, UserPostItem>(
      items: base,
      promotions: promotions.where((p) => p.isAdPromotion).toList(),
      pageSalt: pageSalt,
      promotionId: (p) => p.id,
      buildPromotionItem: (p) => {
        'isPromotionAd': true,
        'promotion': p,
      },
      maxPromotions: null,
    );
  }

  void _openPromotionLink(UserPostItem promotion) {
    final link = (promotion.externalLink ?? '').trim();
    if (link.isEmpty) return;
    openLink(link);
    unawaited(FeedFirestoreService.instance.incrementViewCount(promotion.id));
  }

  Widget _buildPromotionMessageTile(
    UserPostItem promotion, {
    required double previewBoost,
    required double mobileTimeFs,
    required Color timeColor,
  }) {
    final link = (promotion.externalLink ?? '').trim();
    final imageUrl = (promotion.imageUrl ?? '').trim();
    final title = promotion.name.trim();
    final hasImageBytes =
        promotion.imageBytes != null && promotion.imageBytes!.isNotEmpty;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3E0),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFCC80)),
      ),
      child: InkWell(
        enableFeedback: false,
        onTap: link.isNotEmpty ? () => _openPromotionLink(promotion) : null,
        borderRadius: BorderRadius.circular(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: hasImageBytes
                  ? Image.memory(
                      Uint8List.fromList(promotion.imageBytes!),
                      width: 64,
                      height: 64,
                      fit: BoxFit.cover,
                    )
                  : imageUrl.isNotEmpty
                      ? Image.network(
                          imageUrl,
                          width: 64,
                          height: 64,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            width: 64,
                            height: 64,
                            color: const Color(0xFFFFE0B2),
                            child:
                                const Icon(Icons.campaign, color: Colors.brown),
                          ),
                        )
                      : Container(
                          width: 64,
                          height: 64,
                          color: const Color(0xFFFFE0B2),
                          child:
                              const Icon(Icons.campaign, color: Colors.brown),
                        ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (title.isNotEmpty && title != '宣傳貼文')
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        )
                      else
                        const Spacer(),
                      Text(
                        '推廣',
                        style: TextStyle(
                          color: timeColor,
                          fontSize: 12 + mobileTimeFs,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    promotion.content,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 13 + previewBoost,
                    ),
                  ),
                  if (link.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      link,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.blue.shade700,
                        decoration: TextDecoration.underline,
                        fontSize: 12 + previewBoost * 0.7,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  int _unreadCount(Map<String, dynamic> item) {
    final u = item['unread'];
    if (u is int) return u;
    if (u is num) return u.toInt();
    return 0;
  }

  int _chatSortMs(Map<String, dynamic> item) {
    final lastMs = item['lastMessageAtMs'];
    if (lastMs is int) return lastMs;
    if (lastMs is num) return lastMs.toInt();
    final fallbackMs = item['firestoreListMs'];
    if (fallbackMs is int) return fallbackMs;
    if (fallbackMs is num) return fallbackMs.toInt();
    return 0;
  }

  List<Map<String, dynamic>> _sortChatsByUnreadThenTime(
    List<Map<String, dynamic>> chats,
  ) {
    final sorted = List<Map<String, dynamic>>.from(chats);
    sorted.sort((a, b) {
      final unreadA = _unreadCount(a) > 0;
      final unreadB = _unreadCount(b) > 0;
      if (unreadA != unreadB) {
        return unreadA ? -1 : 1;
      }
      return _chatSortMs(b).compareTo(_chatSortMs(a));
    });
    return sorted;
  }

  Widget _buildConversationListView({
    required BuildContext context,
    required List<Map<String, dynamic>> chatList,
    required double previewBoost,
    required double mobileTimeFs,
    required Color timeColor,
  }) {
    return ListView.builder(
      itemCount: chatList.length,
      itemBuilder: (context, index) {
        final item = chatList[index];
        if (item['isPromotionAd'] == true) {
          final promotion = item['promotion'] as UserPostItem?;
          if (promotion == null) return const SizedBox.shrink();
          return _buildPromotionMessageTile(
            promotion,
            previewBoost: previewBoost,
            mobileTimeFs: mobileTimeFs,
            timeColor: timeColor,
          );
        }
        final lastMsg = item['lastMessage'] as String? ?? '';
        final displayMsg =
            lastMsg.length > 10 ? '${lastMsg.substring(0, 10)}...' : lastMsg;
        final avatarUrl = item['avatar'] as String? ?? '';
        final peerUserId = item['userId'] as String? ?? '';
        final unread = _unreadCount(item);
        return ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: ClipOval(
            child: UserAvatarLive(
              userId: peerUserId,
              fallbackAvatar: avatarUrl.isNotEmpty ? avatarUrl : null,
              width: 50,
              height: 50,
            ),
          ),
          title: Text(
            item['name'] as String? ?? '會員',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: Text(
            displayMsg.isEmpty ? '（尚無訊息）' : displayMsg,
            style: TextStyle(
              color: Colors.black,
              fontSize: 13 + previewBoost,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                item['time'] as String? ?? '',
                style: TextStyle(
                  color: timeColor,
                  fontSize: 12 + mobileTimeFs,
                ),
              ),
              if (unread > 0) ...[
                const SizedBox(height: 4),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    unread > 99 ? '99+' : '$unread',
                    style: const TextStyle(color: Colors.white, fontSize: 10),
                  ),
                ),
              ],
            ],
          ),
          onTap: () async {
            final auth = Provider.of<AuthProvider>(context, listen: false);
            final uid = auth.uid;
            final peerId = item['userId'] as String;
            if (uid != null &&
                !await ensureMessagingThreadAllowed(
                  context,
                  myUid: uid,
                  peerUserId: peerId,
                )) {
              return;
            }
            if (!context.mounted) return;
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ChatDetailPage(
                  userId: peerId,
                  name: item['name'] as String? ?? '',
                  avatar: item['avatar'] as String? ?? '',
                  conversationId: item['conversationId'] as String?,
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final langProvider = Provider.of<LanguageProvider>(context);
    final auth = Provider.of<AuthProvider>(context);
    final isMobile =
        MediaQuery.sizeOf(context).width < AppConstants.layoutWideBreakpoint;

    /// 最後訊息預覽：手機／電腦皆 +0.1cm；電腦版額外由灰改黑（紅圈區）
    const previewBoost = 0.1 * AppConstants.logicalPxPerCm;
    final mobileTimeFs = isMobile ? previewBoost : 0.0;
    final timeColor = isMobile ? Colors.black : AppConstants.grey;

    if (FirebaseBootstrap.isReady && auth.isLogin && auth.uid != null) {
      return Scaffold(
        appBar: MainTabAppBar(
          title: langProvider.getString('message'),
          leading: MainTabAppBar.buildHomeLeadingButton(
            onPressed: MainTabAppBar.buildReturnHomeHandler(
              context,
              mobileFallback: () =>
                  Provider.of<NavProvider>(context, listen: false)
                      .setCurrentIndex(0),
            ),
          ),
          actions: [
            MainTabAppBar.buildCircleActionButton(
              onPressed: () {
                context.go('/setting');
              },
              icon: Icons.settings,
              tooltip: '設定',
            ),
            const SizedBox(width: MainTabAppBar.actionGap),
            MainTabAppBar.buildCircleActionButton(
              onPressed: () {
                context.go('/event');
              },
              icon: Icons.event,
              tooltip: '活動',
            ),
          ],
        ),
        backgroundColor: Colors.white,
        body: StreamBuilder<List<Map<String, dynamic>>>(
          stream:
              ChatFirestoreService.instance.watchMyConversationList(auth.uid!),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(child: Text('讀取失敗：${snapshot.error}'));
            }
            final real = snapshot.data ?? [];
            if (_genderForDemo == null && real.isEmpty) {
              return const Center(child: CircularProgressIndicator());
            }
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              _maybePlayNewMessageFromPeerSound(real, auth.uid!);
              if (kIsWeb) {
                var sum = 0;
                for (final item in real) {
                  sum += _unreadCount(item);
                }
                ChatReceiptCookies.setUnreadTotalHint(sum);
              }
            });
            final baseChatList = _mergedChatList(real: real, uid: auth.uid!);
            final promotionPosts = Provider.of<FeedProvider>(context).userPosts;
            final chatList = _mergePromotionAdsIntoChats(
              baseChatList,
              promotionPosts,
              pageSalt: 'message_${auth.uid!}',
            );
            return _buildConversationListView(
              context: context,
              chatList: chatList,
              previewBoost: previewBoost,
              mobileTimeFs: mobileTimeFs,
              timeColor: timeColor,
            );
          },
        ),
      );
    }

    final promotionPosts = Provider.of<FeedProvider>(context).userPosts;
    final chatList = _mergePromotionAdsIntoChats(
      getMockChatList(),
      promotionPosts,
      pageSalt: 'message_guest',
    );

    return Scaffold(
      appBar: MainTabAppBar(
        title: langProvider.getString('message'),
        leading: MainTabAppBar.buildHomeLeadingButton(
          onPressed: MainTabAppBar.buildReturnHomeHandler(
            context,
            mobileFallback: () =>
                Provider.of<NavProvider>(context, listen: false)
                    .setCurrentIndex(0),
          ),
        ),
        actions: [
          MainTabAppBar.buildCircleActionButton(
            onPressed: () {
              context.go('/setting');
            },
            icon: Icons.settings,
            tooltip: '設定',
          ),
          const SizedBox(width: MainTabAppBar.actionGap),
          MainTabAppBar.buildCircleActionButton(
            onPressed: () {
              context.go('/event');
            },
            icon: Icons.event,
            tooltip: '活動',
          ),
        ],
      ),
      backgroundColor: Colors.white,
      body: _buildConversationListView(
        context: context,
        chatList: chatList,
        previewBoost: previewBoost,
        mobileTimeFs: mobileTimeFs,
        timeColor: timeColor,
      ),
    );
  }
}
