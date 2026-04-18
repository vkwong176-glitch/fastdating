import 'dart:async' show unawaited;

import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'dart:typed_data';
import '../utils/constants.dart';
import '../utils/responsive_layout.dart';
import '../providers/feed_provider.dart';
import '../providers/language_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/nav_provider.dart';
import '../services/chat_firestore_service.dart';
import '../services/feed_firestore_service.dart';
import '../services/firebase_bootstrap.dart';
import '../services/user_firestore_service.dart';
import '../utils/ad_promotion_utils.dart';
import '../utils/hk_time_format.dart';
import '../utils/launch_url_helper.dart';
import '../utils/mock_data.dart';
import '../widgets/main_tab_app_bar.dart';
import '../widgets/chat_quota_gate.dart';
import 'settings_page.dart';
import 'chat_detail_page.dart';
import 'activity_page.dart';

/// 與登入頁一致：約 1cm ≈ 38 logical px；電腦版（寬螢幕）白框內字級 +0.4cm
const double _kPublishDesktopFontBoost = 38.0 * 0.4;
const double _kPublishContentTextBoost = 0.1 * AppConstants.logicalPxPerCm;

bool _isPublishDesktopLayout(BuildContext context) =>
    ResponsiveLayout.isWide(context) &&
    !ResponsiveLayout.preferMobilePrimaryLayout(context);

const double _kPublishLeadingInset = 0.5 * AppConstants.logicalPxPerCm;
const double _kPublishActionsRightInset = 0.7 * AppConstants.logicalPxPerCm;
const double _kPublishActionGap = 0.1 * AppConstants.logicalPxPerCm;
const double _kPublishLeadingWidth =
    MainTabAppBar.actionButtonSize + _kPublishLeadingInset;
const double _kPublishActionsWidth =
    2 * MainTabAppBar.actionButtonSize + _kPublishActionGap;

/// 公開顯示用：不顯示系統／舊資料中的 #反邀約
String? _stripCounterInviteHashtag(String? hashtags) {
  if (hashtags == null || hashtags.trim().isEmpty) return null;
  final parts = hashtags
      .split(RegExp(r'\s+'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty && !s.contains('反邀約'))
      .join(' ');
  return parts.isEmpty ? null : parts;
}

/// 配對邀請一則（接受進入聊天、拒絕則從列表移除）
class _InvitationItem {
  final String id;
  final String text;
  final String userId;
  final String name;
  final String avatar;
  _InvitationItem(
      {required this.id,
      required this.text,
      required this.userId,
      required this.name,
      required this.avatar});
}

/// 發布頁面：左手白框內容 — 異性配對邀聊通知、不同人發佈嘅貼文
class PublishFeedPage extends StatefulWidget {
  const PublishFeedPage({super.key});

  @override
  State<PublishFeedPage> createState() => _PublishFeedPageState();
}

class _PublishFeedPageState extends State<PublishFeedPage> {
  late List<_InvitationItem> _invitations;
  final Set<String> _likedPostIds = {};

  @override
  void initState() {
    super.initState();
    _invitations = _invitationItemsFromDemoMaps(
      getRandomOppositeSexChatList(myGender: 'male', count: 3),
    );
  }

  List<_InvitationItem> _invitationItemsFromDemoMaps(
    List<Map<String, dynamic>> maps,
  ) {
    return maps
        .map(
          (m) => _InvitationItem(
            id: 'demo_${m['userId']}',
            text: '${m['name']}：${m['lastMessage']}',
            userId: m['userId'] as String,
            name: m['name'] as String,
            avatar: m['avatar'] as String,
          ),
        )
        .toList();
  }

  Future<void> _onAcceptInvitation(_InvitationItem item) async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    if (auth.uid != null &&
        item.userId.length >= 20 &&
        !await ensureMessagingThreadAllowed(
          context,
          myUid: auth.uid!,
          peerUserId: item.userId,
        )) {
      return;
    }
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatDetailPage(
          userId: item.userId,
          name: item.name,
          avatar: item.avatar,
        ),
      ),
    );
  }

  void _onRejectInvitation(_InvitationItem item) {
    setState(() {
      _invitations.removeWhere((i) => i.id == item.id);
    });
  }

  Future<void> _onAcceptFirestoreInvitation(Map<String, dynamic> item) async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    if (auth.uid == null) return;
    final inviterUid = item['inviterUid'] as String? ?? '';
    if (inviterUid.isEmpty) return;
    try {
      final r = await ChatFirestoreService.instance.acceptChatInvitation(
        accepterUid: auth.uid!,
        inviterUid: inviterUid,
      );
      if (!mounted) return;
      if (r == null || !r.isMutualMatch || r.conversationId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('無法接受邀請（可能已過期）')),
        );
        return;
      }
      Provider.of<NavProvider>(context, listen: false).setCurrentIndex(1);
      if (!await ensureMessagingThreadAllowed(
        context,
        myUid: auth.uid!,
        peerUserId: inviterUid,
      )) {
        return;
      }
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatDetailPage(
            userId: inviterUid,
            name: item['name'] as String? ?? '',
            avatar: item['avatar'] as String? ?? '',
            conversationId: r.conversationId,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('接受失敗：$e')),
      );
    }
  }

  Future<void> _openOneSentencePage() async {
    final ok = await ensureChatQuotaBeforeEnterChatArea(context);
    if (!mounted || !context.mounted) return;
    if (!ok) return;
    context.go('/talking');
  }

  Future<void> _onRejectFirestoreInvitation(Map<String, dynamic> item) async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    if (auth.uid == null) return;
    final inviterUid = item['inviterUid'] as String? ?? '';
    if (inviterUid.isEmpty) return;
    try {
      await ChatFirestoreService.instance.declineChatInvitation(
        accepterUid: auth.uid!,
        inviterUid: inviterUid,
      );
    } catch (_) {}
  }

  Widget _buildInvitationSection(double desktopFs) {
    final auth = Provider.of<AuthProvider>(context);
    if (FirebaseBootstrap.isReady && auth.isLogin && auth.uid != null) {
      return StreamBuilder<List<Map<String, dynamic>>>(
        stream:
            ChatFirestoreService.instance.watchIncomingInvitations(auth.uid!),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '讀取邀請失敗：${snapshot.error}',
                style: TextStyle(fontSize: 14 + desktopFs, color: Colors.red),
              ),
            );
          }
          final list = snapshot.data ?? [];
          if (snapshot.connectionState == ConnectionState.waiting &&
              list.isEmpty) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          }
          if (list.isEmpty) {
            return FutureBuilder<String>(
              future: UserFirestoreService.instance.fetchUserGender(auth.uid!),
              builder: (context, genderSnap) {
                if (genderSnap.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Center(
                      child: SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  );
                }
                final myGender = genderSnap.data ?? 'male';
                return _DemoOppositeInvitesList(
                  key: ValueKey<String>('demo_inv_$myGender'),
                  myGender: myGender,
                  desktopFs: desktopFs,
                  cardBuilder: (item, onAccept, onReject) {
                    return _buildInvitationCard(
                      context,
                      desktopFs: desktopFs,
                      icon: Icons.chat_bubble_outline,
                      iconColor: Colors.blue,
                      text: '${item['name']}：${item['lastMessage']}',
                      onAccept: onAccept,
                      onReject: onReject,
                    );
                  },
                );
              },
            );
          }
          return Column(
            children: list.map((item) {
              final name = item['name'] as String? ?? '會員';
              final text = item['text'] as String? ?? '';
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _buildInvitationCard(
                  context,
                  desktopFs: desktopFs,
                  icon: Icons.chat_bubble_outline,
                  iconColor: Colors.blue,
                  text: '$name\n$text',
                  onAccept: () => _onAcceptFirestoreInvitation(item),
                  onReject: () => _onRejectFirestoreInvitation(item),
                ),
              );
            }).toList(),
          );
        },
      );
    }
    return Column(
      children: [
        ..._invitations.map((item) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _buildInvitationCard(
                context,
                desktopFs: desktopFs,
                icon: Icons.chat_bubble_outline,
                iconColor: Colors.blue,
                text: item.text,
                onAccept: () => _onAcceptInvitation(item),
                onReject: () => _onRejectInvitation(item),
              ),
            )),
        if (_invitations.isEmpty) const SizedBox(height: 4),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final langProvider = Provider.of<LanguageProvider>(context);
    final desktopFs =
        _isPublishDesktopLayout(context) ? _kPublishDesktopFontBoost : 0.0;
    return Scaffold(
      backgroundColor: AppConstants.backgroundColor,
      appBar: MainTabAppBar(
        title: langProvider.getString('publish'),
        slotWidth: _kPublishActionsWidth,
        leading: MainTabAppBar.buildHomeLeadingButton(
          onPressed: MainTabAppBar.buildReturnHomeHandler(
            context,
            mobileFallback: () =>
                Provider.of<NavProvider>(context, listen: false)
                    .setCurrentIndex(0),
          ),
        ),
        leadingLeftInset: _kPublishLeadingInset,
        leadingWidth: _kPublishLeadingWidth,
        actionsRightInset: _kPublishActionsRightInset,
        actions: [
          MainTabAppBar.buildCircleActionButton(
            onPressed: () {
              context.go('/setting');
            },
            icon: Icons.settings,
            tooltip: '設定',
          ),
          const SizedBox(width: _kPublishActionGap),
          MainTabAppBar.buildCircleActionButton(
            onPressed: () {
              context.go('/event');
            },
            icon: Icons.event,
            tooltip: '活動',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppConstants.padding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 左手白框：異性配對邀請 + 不同人貼文
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppConstants.white,
                borderRadius: BorderRadius.circular(AppConstants.cardRadius),
                boxShadow: [
                  BoxShadow(
                    color: AppConstants.grey.withOpacity(0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 異性配對邀聊通知
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            '異性配對邀聊通知',
                            style: TextStyle(
                              fontSize:
                                  15 + desktopFs + _kPublishContentTextBoost,
                              fontWeight: FontWeight.w600,
                              color: AppConstants.grey,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        TextButton(
                          onPressed: _openOneSentencePage,
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white,
                            backgroundColor: AppConstants.primaryColor,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            minimumSize: const Size(0, 36),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            textStyle: TextStyle(
                              fontSize: 13 + desktopFs,
                              fontWeight: FontWeight.w600,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                          child: const Text('想講～'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildInvitationSection(desktopFs),
                    const SizedBox(height: 20),
                    const Divider(height: 1),
                    const SizedBox(height: 16),
                    // 不同人發佈嘅貼文
                    Text(
                      '不同人發佈嘅貼文',
                      style: TextStyle(
                        fontSize: 15 + desktopFs + _kPublishContentTextBoost,
                        fontWeight: FontWeight.w600,
                        color: AppConstants.grey,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Builder(
                      builder: (context) {
                        final allPosts =
                            Provider.of<FeedProvider>(context).userPosts;
                        final promotionPosts =
                            allPosts.where((p) => p.isAdPromotion).toList();
                        final normalPosts =
                            allPosts.where((p) => !p.isAdPromotion).toList();
                        final posts =
                            mergePromotionItems<UserPostItem, UserPostItem>(
                          items: normalPosts,
                          promotions: promotionPosts,
                          pageSalt: 'publish_feed',
                          promotionId: (p) => p.id,
                          buildPromotionItem: (p) => p,
                          maxPromotions: null,
                        );
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            ...posts.map(
                              (post) => Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: _buildPostCard(
                                  desktopFs: desktopFs,
                                  postId: post.id,
                                  name: post.name,
                                  authorAge: post.authorAge,
                                  tag: post.tag,
                                  content: post.content,
                                  hashtags: post.hashtags,
                                  iconColor: post.iconColor,
                                  imageBytes: post.imageBytes,
                                  imageUrl: post.imageUrl,
                                  viewCount: post.viewCount,
                                  authorUid: post.authorUid,
                                  externalLink: post.externalLink,
                                  isAdPromotion: post.isAdPromotion,
                                  timeLabel: post.createdAtUtc != null
                                      ? formatHongKongTimeFromDateTime(
                                          post.createdAtUtc,
                                        )
                                      : null,
                                  mockPost: !post.isAdPromotion &&
                                      post.authorUid == null,
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    _buildPostCard(
                      desktopFs: desktopFs,
                      postId: 'p1',
                      name: 'POOLD',
                      tag: '貼文',
                      content: '遊車河聽CD 吹海風睇夜景',
                      hashtags: '#180橫膊胸肌人魚線 #白淨斯文肌肉 #車河',
                      iconColor: AppConstants.primaryColor,
                      userId: 'p1',
                      viewCount: 128,
                      mockPost: true,
                      timeLabel: '示範 · 2025/04/01 14:30',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            // 限時貼文
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '限時貼文',
                  style: TextStyle(
                    fontSize: 15 + _kPublishContentTextBoost,
                    fontWeight: FontWeight.w600,
                    color: AppConstants.grey,
                  ),
                ),
                TextButton(
                  onPressed: () {},
                  child: const Text('查看更多'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInvitationCard(
    BuildContext context, {
    required double desktopFs,
    required IconData icon,
    required Color iconColor,
    required String text,
    required VoidCallback? onAccept,
    required VoidCallback? onReject,
  }) {
    final lang = Provider.of<LanguageProvider>(context, listen: false);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: AppConstants.backgroundColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 15 + desktopFs + _kPublishContentTextBoost,
              ),
            ),
          ),
          TextButton(
            onPressed: onReject,
            style: TextButton.styleFrom(
              backgroundColor: Colors.grey.shade600,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              textStyle: TextStyle(fontSize: 13 + desktopFs),
            ),
            child: Text(lang.getString('chat_invite_btn_decline')),
          ),
          const SizedBox(width: 4),
          TextButton(
            onPressed: onAccept,
            style: TextButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              textStyle: TextStyle(fontSize: 13 + desktopFs),
            ),
            child: Text(lang.getString('chat_invite_btn_want')),
          ),
        ],
      ),
    );
  }

  Future<void> _onPostHeartPressed({
    required String postId,
    required String authorName,
    required String? authorUid,
    required bool mockPost,
  }) async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    if (mockPost) {
      setState(() {
        if (_likedPostIds.contains(postId)) {
          _likedPostIds.remove(postId);
        } else {
          _likedPostIds.add(postId);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('已發送按心，$authorName 會收到按心通知（示範）')),
          );
        }
      });
      return;
    }
    if (!FirebaseBootstrap.isReady || !auth.isLogin || auth.uid == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('請先登入會員')),
        );
      }
      return;
    }
    if (authorUid == null || authorUid == auth.uid) return;
    if (_likedPostIds.contains(postId)) return;
    try {
      await FeedFirestoreService.instance.sendHeartOnPost(
        postId: postId,
        authorUid: authorUid,
      );
      if (!mounted) return;
      setState(() => _likedPostIds.add(postId));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已發送按心，$authorName 會收到按心通知')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('按心失敗：$e')),
        );
      }
    }
  }

  Future<void> _onInvitePressed({
    required String postId,
    required String peerName,
    required String? authorUid,
    required bool mockPost,
  }) async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    if (mockPost) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('此為示範貼文，無法發出邀約')),
        );
      }
      return;
    }
    if (!FirebaseBootstrap.isReady || !auth.isLogin || auth.uid == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('請先登入會員')),
        );
      }
      return;
    }
    if (authorUid == null || authorUid == auth.uid) return;
    try {
      final ok = await FeedFirestoreService.instance.inviteFromFeedPost(
        postId: postId,
        authorUid: authorUid,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok ? '已發送邀約給 $peerName' : '無法發送（可能已有對話或名額已滿）'),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('邀約失敗：$e')),
        );
      }
    }
  }

  void _openPromotionLink(String postId, String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return;
    openLink(trimmed);
    unawaited(FeedFirestoreService.instance.incrementViewCount(postId));
  }

  Widget _buildFeedPostReportButton({
    required double desktopFs,
    required String postId,
    required String name,
    required String authorUid,
    required String content,
  }) {
    final langFeed = Provider.of<LanguageProvider>(context, listen: false);
    return TextButton(
      style: TextButton.styleFrom(
        foregroundColor: const Color(0xFF2E7D32),
        backgroundColor: const Color(0xFFE8F5E9),
        minimumSize: Size.zero,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: TextStyle(
          fontSize: 13 + desktopFs,
          fontWeight: FontWeight.w600,
        ),
      ),
      onPressed: () {
        _openFeedPostReport(
          postId: postId,
          authorUid: authorUid,
          authorName: name,
          content: content,
        );
      },
      child: Text(langFeed.getString('feed_report_button')),
    );
  }

  Future<void> _openFeedPostReport({
    required String postId,
    required String authorUid,
    required String authorName,
    required String content,
  }) async {
    final lang = Provider.of<LanguageProvider>(context, listen: false);
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(lang.getString('feed_report_need_login'))),
      );
      return;
    }
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(lang.getString('feed_report_title')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                lang.getString('feed_report_hint'),
                style: TextStyle(fontSize: 13, color: AppConstants.grey),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                maxLines: 5,
                minLines: 3,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  hintText: lang.getString('feed_report_field_hint'),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(lang.getString('feed_report_cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(lang.getString('feed_report_submit')),
          ),
        ],
      ),
    );
    final detail = ctrl.text.trim();
    ctrl.dispose();
    if (ok != true || !mounted) return;
    if (detail.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(lang.getString('feed_report_empty'))),
      );
      return;
    }
    try {
      final preview =
          content.length > 400 ? content.substring(0, 400) : content;
      await FeedFirestoreService.instance.submitFeedPostReport(
        postId: postId,
        postAuthorUid: authorUid,
        reporterUid: u.uid,
        detailText: detail,
        contentPreview: preview,
        postAuthorDisplayName: authorName,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(lang.getString('feed_report_ok'))),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${lang.getString('feed_report_fail')}: $e')),
      );
    }
  }

  Widget _buildPostCard({
    required double desktopFs,
    required String postId,
    required String name,
    int? authorAge,
    String? tag,
    required String content,
    String? hashtags,
    required Color iconColor,
    String? userId,
    List<int>? imageBytes,
    String? imageUrl,
    int viewCount = 0,
    String? authorUid,
    String? externalLink,
    String? timeLabel,
    bool mockPost = false,
    bool isAdPromotion = false,
  }) {
    final auth = Provider.of<AuthProvider>(context);
    final myUid = auth.uid;
    final isOwnPost = !mockPost &&
        !isAdPromotion &&
        myUid != null &&
        authorUid != null &&
        authorUid == myUid;
    final showInvite = !isAdPromotion &&
        !isOwnPost &&
        (mockPost ? userId != null : authorUid != null);
    final canReport = !isAdPromotion &&
        !mockPost &&
        !isOwnPost &&
        authorUid != null &&
        myUid != null &&
        FirebaseBootstrap.isReady;
    final displayTime = timeLabel ?? '';
    final displayHashtags = _stripCounterInviteHashtag(hashtags);
    final isLiked = _likedPostIds.contains(postId);
    final headline = authorAge != null ? '$name, $authorAge' : name;
    final trimmedExternalLink = (externalLink ?? '').trim();
    final trimmedImageUrl = (imageUrl ?? '').trim();
    final hasImageBytes = imageBytes != null && imageBytes.isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppConstants.backgroundColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            headline,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize:
                                  14 + desktopFs + _kPublishContentTextBoost,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (tag != null && !isAdPromotion) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.amber.shade100,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              tag,
                              style: TextStyle(
                                fontSize:
                                    11 + desktopFs + _kPublishContentTextBoost,
                                color: Colors.amber.shade800,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (displayTime.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          displayTime,
                          style: TextStyle(
                            fontSize:
                                11 + desktopFs + _kPublishContentTextBoost,
                            color: AppConstants.grey,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (showInvite)
                    TextButton(
                      onPressed: () => _onInvitePressed(
                        postId: postId,
                        peerName: headline,
                        authorUid: authorUid,
                        mockPost: mockPost,
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: AppConstants.primaryColor,
                        side:
                            const BorderSide(color: AppConstants.primaryColor),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        minimumSize: const Size(0, 32),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                        textStyle: TextStyle(fontSize: 13 + desktopFs),
                      ),
                      child: const Text('邀約'),
                    ),
                  Padding(
                    padding: const EdgeInsets.only(left: 4, right: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Icon(Icons.visibility,
                            size: 18, color: AppConstants.grey),
                        const SizedBox(width: 4),
                        Text(
                          '$viewCount',
                          style: TextStyle(
                            fontSize:
                                13 + desktopFs + _kPublishContentTextBoost,
                            color: AppConstants.grey,
                            height: 1.0,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!isAdPromotion)
                    IconButton(
                      icon: Icon(
                        isLiked ? Icons.favorite : Icons.favorite_border,
                        size: 22,
                        color: isLiked ? Colors.red : AppConstants.grey,
                      ),
                      onPressed: isOwnPost
                          ? null
                          : () => _onPostHeartPressed(
                                postId: postId,
                                authorName: headline,
                                authorUid: authorUid,
                                mockPost: mockPost,
                              ),
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                      constraints:
                          const BoxConstraints(minWidth: 40, minHeight: 40),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (isAdPromotion &&
              (hasImageBytes || trimmedImageUrl.isNotEmpty)) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: hasImageBytes
                  ? Image.memory(
                      Uint8List.fromList(imageBytes!),
                      height: 160,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    )
                  : Image.network(
                      trimmedImageUrl,
                      height: 160,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
            ),
            const SizedBox(height: 10),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      content,
                      style: TextStyle(
                        fontSize: 14 + desktopFs + _kPublishContentTextBoost,
                        height: 1.4,
                      ),
                    ),
                    if (displayHashtags != null &&
                        displayHashtags.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        displayHashtags,
                        style: TextStyle(
                          fontSize: 12 + desktopFs + _kPublishContentTextBoost,
                          color: Colors.blue.shade700,
                        ),
                      ),
                    ],
                    if (trimmedExternalLink.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      InkWell(
                        enableFeedback: false,
                        onTap: () =>
                            _openPromotionLink(postId, trimmedExternalLink),
                        child: Text(
                          trimmedExternalLink,
                          style: TextStyle(
                            fontSize:
                                12 + desktopFs + _kPublishContentTextBoost,
                            color: Colors.blue.shade700,
                            decoration: TextDecoration.underline,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (isAdPromotion && trimmedExternalLink.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: TextButton(
                    onPressed: () =>
                        _openPromotionLink(postId, trimmedExternalLink),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: AppConstants.primaryColor,
                      minimumSize: Size.zero,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      '前往連結',
                      style: TextStyle(fontSize: 13 + desktopFs),
                    ),
                  ),
                )
              else if (canReport)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: _buildFeedPostReportButton(
                    desktopFs: desktopFs,
                    postId: postId,
                    name: headline,
                    authorUid: authorUid,
                    content: content,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Firestore 尚無邀請時：顯示 3 則隨機異性邀聊示範（接受／拒絕僅影響本機列表）
class _DemoOppositeInvitesList extends StatefulWidget {
  const _DemoOppositeInvitesList({
    super.key,
    required this.myGender,
    required this.desktopFs,
    required this.cardBuilder,
  });

  final String myGender;
  final double desktopFs;
  final Widget Function(
    Map<String, dynamic> item,
    VoidCallback onAccept,
    VoidCallback onReject,
  ) cardBuilder;

  @override
  State<_DemoOppositeInvitesList> createState() =>
      _DemoOppositeInvitesListState();
}

class _DemoOppositeInvitesListState extends State<_DemoOppositeInvitesList> {
  late List<Map<String, dynamic>> _items;

  @override
  void initState() {
    super.initState();
    _items = List<Map<String, dynamic>>.from(
      getRandomOppositeSexChatList(myGender: widget.myGender, count: 3),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(
          '目前沒有聊天邀請',
          style: TextStyle(
            fontSize: 14 + widget.desktopFs + _kPublishContentTextBoost,
            color: AppConstants.grey,
          ),
        ),
      );
    }
    return Column(
      children: _items.map((item) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: widget.cardBuilder(
            item,
            () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ChatDetailPage(
                    userId: item['userId'] as String,
                    name: item['name'] as String,
                    avatar: item['avatar'] as String,
                  ),
                ),
              );
            },
            () {
              setState(() {
                _items.remove(item);
              });
            },
          ),
        );
      }).toList(),
    );
  }
}
