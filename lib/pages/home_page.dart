import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../data/discover_demo_profiles.dart'
    show discoverDemoProfilesFiltered, isDemoDiscoverProfile;
import '../utils/constants.dart';
import '../widgets/avatar_image_box.dart';
import '../widgets/gender_filter.dart';
import '../widgets/pressable_opacity.dart';
import '../providers/language_provider.dart';
import '../providers/nav_provider.dart';
import '../utils/mock_data.dart';
import '../providers/interest_provider.dart';
import '../providers/auth_provider.dart';
import '../services/firebase_bootstrap.dart';
import '../services/user_firestore_service.dart';
import '../services/chat_firestore_service.dart';
import '../services/chat_quota_service.dart';
import '../services/discover_filter_cookies.dart';
import 'chat_detail_page.dart';
import 'settings_page.dart';
import 'activity_page.dart';
import '../widgets/chat_quota_gate.dart';

/// 首頁（選單 tab）：搜尋欄、篩選彈窗、動態貼文列表、右滑喜歡/左滑略過、配對彈窗。
/// 已登入且 Firebase 就緒時自 [FirestorePaths.users] 載入；否則使用 mock。
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<Map<String, dynamic>> _userList = [];
  List<Map<String, dynamic>> _firestoreRawList = [];
  bool _useFirestoreDiscover = false;
  StreamSubscription<List<Map<String, dynamic>>>? _discoverSub;
  StreamSubscription<int?>? _myPlanSub;
  NavProvider? _navForHomePrompt;

  /// Firestore `users.fastDatingPlan`（1～6）；未設定為 null。Fast Dating 2～6 時首頁優先顯示同層會員。
  int? _myFastDatingPlan;
  final Set<String> _removedPeerIds = {};

  /// 篩選要顯示的會員性別（`male`／`female`）；與卡片 [gender] 欄位比對。
  String _selectedGender = 'male';
  RangeValues _ageRange = const RangeValues(18, 60);
  final Set<String> _selectedInterests = {};
  int _likeCount = 0;
  final _searchController = TextEditingController();

  /// Web：若已由 Cookie 還原性別，則不再強制改為「預設異性」
  bool _skipOppositeGenderDefault = false;
  bool _showIncompleteProfileTip = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (kIsWeb) {
        final fromCookie = DiscoverFilterCookies.applyToState(
          setGender: (g) => setState(() => _selectedGender = g),
          setAge: (r) => setState(() => _ageRange = r),
        );
        if (fromCookie) _skipOppositeGenderDefault = true;
      }
      _setupDiscoverSource();
      _bindMyDiscoverPlanStream();
      _applyInitialDefaultDiscoverGender();
      unawaited(_refreshHomeProfilePrompt());
    });
  }

  Future<void> _refreshHomeProfilePrompt() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    if (!FirebaseBootstrap.isReady || !auth.isLoginMember) {
      if (!mounted || !_showIncompleteProfileTip) return;
      setState(() => _showIncompleteProfileTip = false);
      return;
    }
    final complete = await UserFirestoreService.instance
        .isCurrentUserProfileCompleteForMatching();
    if (!mounted) return;
    if (_showIncompleteProfileTip == !complete) return;
    setState(() => _showIncompleteProfileTip = !complete);
  }

  /// 首次進入首頁時依「我的性別」預設為想看的對象（異性）；之後以使用者篩選為準。
  void _applyInitialDefaultDiscoverGender() {
    if (!mounted) return;
    if (_skipOppositeGenderDefault) {
      setState(_applyDiscoverFilters);
      return;
    }
    final auth = Provider.of<AuthProvider>(context, listen: false);
    setState(() {
      _selectedGender = AppConstants.discoverOppositeGender(auth.profileGender);
      _applyDiscoverFilters();
    });
  }

  void _onSearchChanged() {
    if (!mounted) return;
    setState(_applyDiscoverFilters);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nav = Provider.of<NavProvider>(context, listen: false);
    if (!identical(_navForHomePrompt, nav)) {
      _navForHomePrompt?.removeListener(_onHomeTabChanged);
      _navForHomePrompt = nav;
      _navForHomePrompt!.addListener(_onHomeTabChanged);
    }
  }

  void _onHomeTabChanged() {
    if (!mounted) return;
    if (_navForHomePrompt?.currentIndex == 0) {
      unawaited(_refreshHomeProfilePrompt());
    }
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _discoverSub?.cancel();
    _myPlanSub?.cancel();
    _navForHomePrompt?.removeListener(_onHomeTabChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _bindMyDiscoverPlanStream() {
    _myPlanSub?.cancel();
    _myPlanSub = UserFirestoreService.instance.watchMyDiscoverPlanTier().listen(
      (tier) {
        if (!mounted) return;
        setState(() {
          _myFastDatingPlan = tier;
          _applyDiscoverFilters();
        });
      },
    );
  }

  void _setupDiscoverSource() {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    if (FirebaseBootstrap.isReady && auth.isLogin && auth.uid != null) {
      _useFirestoreDiscover = true;
      _discoverSub?.cancel();
      _discoverSub = UserFirestoreService.instance
          .watchDiscoverUsers(excludeUid: auth.uid)
          .listen((list) {
        if (!mounted) return;
        setState(() {
          _firestoreRawList = list;
          _applyDiscoverFilters();
        });
      });
    } else {
      _useFirestoreDiscover = false;
      _loadMoreUsersMock();
    }
  }

  /// 依篩選條件從 Firestore 或 mock 重算 [_userList]（並排除已滑掉的對象）。
  void _applyDiscoverFilters() {
    final Iterable<Map<String, dynamic>> raw =
        _useFirestoreDiscover ? _firestoreRawList : getMockUserList();
    Iterable<Map<String, dynamic>> it = raw;
    it = it.where(isDiscoverCardCompleteForMatching);
    it = it.where((u) => !_removedPeerIds.contains(u['id']?.toString()));
    it = it.where((u) => (u['gender'] ?? 'male') == _selectedGender);
    it = it.where((u) {
      final age =
          u['age'] is int ? u['age'] as int : int.tryParse('${u['age']}') ?? 25;
      return age >= _ageRange.start.round() && age <= _ageRange.end.round();
    });
    if (_selectedInterests.isNotEmpty) {
      it = it.where((u) {
        final tags =
            (u['tags'] as List<dynamic>?)?.map((e) => e.toString()).toSet() ??
                {};
        return tags.intersection(_selectedInterests).isNotEmpty;
      });
    }
    final q = _searchController.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      it = it.where((u) {
        final name = (u['name'] ?? '').toString().toLowerCase();
        final job = (u['job'] ?? '').toString().toLowerCase();
        return name.contains(q) || job.contains(q);
      });
    }
    var realList = it.toList();
    sortDiscoverHomeListBySubscriptionTier(
      realList,
      _myFastDatingPlan,
    );
    var list = realList;
    if (_useFirestoreDiscover) {
      final demos = discoverDemoProfilesFiltered(
        gender: _selectedGender,
        ageRange: _ageRange,
        selectedInterests: _selectedInterests,
        excludeIds: realList
            .map((e) => e['id']?.toString())
            .whereType<String>()
            .toSet(),
        searchQuery: _searchController.text.trim(),
        max: 9999,
        preferTierFirst: _myFastDatingPlan,
      );
      list = _mixDiscoverRealAndDemo(
        realUsers: realList,
        demoUsers: demos,
      );
    }
    _userList = list;
  }

  List<Map<String, dynamic>> _mixDiscoverRealAndDemo({
    required List<Map<String, dynamic>> realUsers,
    required List<Map<String, dynamic>> demoUsers,
  }) {
    if (realUsers.isEmpty) {
      return demoUsers;
    }
    if (demoUsers.isEmpty) {
      return realUsers;
    }
    return [...realUsers, ...demoUsers];
  }

  /// 未登入或 Firebase 未就緒時：mock 列表（與 [_applyDiscoverFilters] 篩選一致）。
  void _loadMoreUsersMock() {
    setState(_applyDiscoverFilters);
  }

  /// 模擬「載入更多」：mock 模式下列表過短時補充。
  void _loadMoreUsers() {
    if (_useFirestoreDiscover) return;
    _loadMoreUsersMock();
  }

  /// 打開篩選面板（彈窗內維護本地狀態，套用時回寫父層）
  void _openFilterPanel() {
    final langProvider = Provider.of<LanguageProvider>(context, listen: false);
    final interestTags =
        Provider.of<InterestProvider>(context, listen: false).tags;
    var modalAge = _ageRange;
    var modalInterests = Set<String>.from(_selectedInterests);
    var modalGender = _selectedGender;

    /// 手機篩選彈窗：性別按鈕「男性／女性」字級 +0.3cm；其餘字加 0.1cm（1cm≈37.8 logical px）
    const mobileFilterGenderShrink = 0.2 * AppConstants.logicalPxPerCm;
    const mobileFilterGenderTextBoost = 0.3 * AppConstants.logicalPxPerCm;
    const mobileFilterOtherBoost = 0.1 * AppConstants.logicalPxPerCm;
    const modalBase =
        AppConstants.filterInnerFontExtra - AppConstants.filterFontShrink4mm;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          return Container(
            padding: const EdgeInsets.all(AppConstants.padding),
            decoration: const BoxDecoration(
              color: AppConstants.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: SafeArea(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppConstants.grey.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '篩選',
                      style: TextStyle(
                        fontSize: 20 + modalBase + mobileFilterOtherBoost,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    GenderFilter(
                      key: ValueKey(modalGender),
                      initialGender: modalGender,
                      fontSizeExtraDelta: -AppConstants.filterFontShrink4mm -
                          mobileFilterGenderShrink +
                          mobileFilterGenderTextBoost,
                      onSelect: (g) => setModalState(() => modalGender = g),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '${langProvider.getString('age_range')} ${modalAge.start.toInt()} - ${modalAge.end.toInt()}',
                      style: TextStyle(
                        fontSize: 14 + modalBase + mobileFilterOtherBoost,
                      ),
                    ),
                    RangeSlider(
                      values: modalAge,
                      min: AppConstants.discoverAgeFilterMin,
                      max: AppConstants.discoverAgeFilterMax,
                      divisions: AppConstants.discoverAgeFilterDivisions,
                      onChanged: (v) => setModalState(() => modalAge = v),
                      activeColor: AppConstants.primaryColor,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${langProvider.getString('interest')}（多選）',
                      style: TextStyle(
                        fontSize: 14 + modalBase + mobileFilterOtherBoost,
                      ),
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: interestTags.map((tag) {
                        final selected = modalInterests.contains(tag);
                        return GestureDetector(
                          onTap: () {
                            setModalState(() {
                              if (selected) {
                                modalInterests.remove(tag);
                              } else {
                                modalInterests.add(tag);
                              }
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: selected
                                  ? AppConstants.primaryColor.withOpacity(0.2)
                                  : AppConstants.backgroundColor,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: selected
                                    ? AppConstants.primaryColor
                                    : AppConstants.grey.withOpacity(0.3),
                              ),
                            ),
                            child: Text(
                              tag,
                              style: TextStyle(
                                fontSize:
                                    13 + modalBase + mobileFilterOtherBoost,
                                color: selected
                                    ? AppConstants.primaryColor
                                    : AppConstants.grey,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 24),
                    PressableOpacity(
                      onPressed: () {
                        setState(() {
                          _selectedGender = modalGender;
                          _ageRange = modalAge;
                          _selectedInterests.clear();
                          _selectedInterests.addAll(modalInterests);
                          _applyDiscoverFilters();
                        });
                        if (kIsWeb) {
                          DiscoverFilterCookies.save(
                            gender: modalGender,
                            ageRange: modalAge,
                          );
                        }
                        Navigator.pop(context);
                      },
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: AppConstants.primaryColor,
                          borderRadius:
                              BorderRadius.circular(AppConstants.borderRadius),
                        ),
                        child: Center(
                          child: Text(
                            '套用',
                            style: TextStyle(
                              fontSize: 16 +
                                  AppConstants.filterFontExtraHalfCm -
                                  AppConstants.filterFontShrink4mm +
                                  mobileFilterOtherBoost,
                              fontWeight: FontWeight.bold,
                              color: AppConstants.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _handleSlideAction(int index, String action) async {
    final user = _userList[index];
    final peerId = user['id']?.toString();
    final peerName = user['name']?.toString() ?? '';
    final peerAvatar = user['avatar']?.toString() ?? '';

    if (action == 'like') {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      if (_useFirestoreDiscover) {
        if (peerId != null && peerId.startsWith('demo_match_')) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('示範用戶僅供預覽，無法配對')),
            );
          }
        } else if (peerId != null && auth.uid != null) {
          try {
            final r = await ChatFirestoreService.instance.likePeer(
              fromUid: auth.uid!,
              toUid: peerId,
            );
            if (!mounted) return;
            if (r.isMutualMatch) {
              _showMatchSuccessDialog(
                peerId: peerId,
                peerName: peerName,
                peerAvatar: peerAvatar,
                conversationId: r.conversationId,
              );
            }
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('喜歡失敗：$e')),
              );
            }
          }
        }
      } else {
        setState(() {
          _likeCount++;
          if (_likeCount % 3 == 0) {
            _showMatchSuccessDialog();
          }
        });
      }
    }

    if (!mounted) return;
    setState(() {
      if (peerId != null) _removedPeerIds.add(peerId);
      _userList.removeAt(index);
      if (!_useFirestoreDiscover && _userList.length < 5) {
        _loadMoreUsers();
      }
    });
  }

  void _showMatchSuccessDialog({
    String? peerId,
    String? peerName,
    String? peerAvatar,
    String? conversationId,
  }) {
    final langProvider = Provider.of<LanguageProvider>(context, listen: false);
    final canEnterChat = conversationId?.isNotEmpty ?? false;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(langProvider.getString('match_success')),
        content: Text(
          canEnterChat
              ? '你和對方互相喜歡，趕緊開始聊天吧！'
              : langProvider.getString('match_mutual_invite_body'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(langProvider.getString('close')),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              if (peerId == null) return;
              if (canEnterChat) {
                await _openChatForPeer(
                  peerId: peerId,
                  peerName: peerName ?? '會員',
                  peerAvatar: peerAvatar ?? '',
                  conversationId: conversationId,
                );
              } else {
                await _sendChatInviteToPeer(peerId, peerName ?? '');
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppConstants.primaryColor,
            ),
            child: Text(
              canEnterChat
                  ? langProvider.getString('chat_now')
                  : langProvider.getString('send_chat_invitation'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openChatForPeer({
    required String peerId,
    required String peerName,
    required String peerAvatar,
    String? conversationId,
  }) async {
    if (peerId.startsWith('demo_match_')) {
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatDetailPage(
            userId: peerId,
            name: peerName,
            avatar: peerAvatar,
          ),
        ),
      );
      return;
    }
    final auth = Provider.of<AuthProvider>(context, listen: false);
    if (FirebaseBootstrap.isReady && auth.isLogin && auth.uid != null) {
      final cid = (conversationId != null && conversationId.isNotEmpty)
          ? conversationId
          : ChatFirestoreService.pairConversationId(auth.uid!, peerId);
      if (!await ensureMessagingThreadAllowed(
        context,
        myUid: auth.uid!,
        peerUserId: peerId,
      )) {
        return;
      }
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatDetailPage(
            userId: peerId,
            name: peerName,
            avatar: peerAvatar,
            conversationId: cid,
          ),
        ),
      );
      return;
    }
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatDetailPage(
          userId: peerId,
          name: peerName,
          avatar: peerAvatar,
        ),
      ),
    );
  }

  Future<void> _sendChatInviteToPeer(String peerId, String peerName) async {
    if (peerId.startsWith('demo_match_')) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('示範用戶僅供預覽，請在真實會員上使用邀請聊天')),
      );
      return;
    }
    final auth = Provider.of<AuthProvider>(context, listen: false);
    if (!FirebaseBootstrap.isReady || auth.uid == null) return;
    try {
      final sent = await ChatFirestoreService.instance.sendChatInvitation(
        fromUid: auth.uid!,
        toUid: peerId,
      );
      if (!mounted) return;
      if (!sent) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('雙方已配對，可直接按「進入聊天」')),
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            peerName.isNotEmpty
                ? '已邀請 $peerName，對方於「邀聊通知」頁接受後即可聊天'
                : '已送出邀請，對方於「邀聊通知」頁接受後即可聊天',
          ),
        ),
      );
    } on ChatQuotaExceededException {
      if (!mounted) return;
      await showChatQuotaPaywallDialog(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('邀請失敗：$e')),
      );
    }
  }

  /// 進入聊天：已有對話則開啟；否則發出邀請（對方於邀聊通知按「想」後可聊）。
  /// [isDemoProfile] 為示範／虛假配對卡：不進聊天，改顯示黑底提示（與真實會員區隔）。
  Future<void> _onDiscoverEnterChat(
    String peerId,
    String peerName,
    String peerAvatar,
    bool canCloudInvite, {
    required bool isDemoProfile,
  }) async {
    if (isDemoProfile) {
      if (!mounted) return;
      final displayName =
          peerName.trim().isEmpty ? '此會員' : peerName.trim();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.black87,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 88),
          content: Text(
            '已通知會員名稱（$displayName），對方於邀聊通知頁面接受後即可聊天',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              height: 1.35,
            ),
          ),
        ),
      );
      return;
    }
    final auth = Provider.of<AuthProvider>(context, listen: false);
    if (canCloudInvite &&
        FirebaseBootstrap.isReady &&
        auth.isLogin &&
        auth.uid != null) {
      final cid = ChatFirestoreService.pairConversationId(auth.uid!, peerId);
      final exists =
          await ChatFirestoreService.instance.conversationExists(cid);
      if (!mounted) return;
      if (exists) {
        await _openChatForPeer(
          peerId: peerId,
          peerName: peerName,
          peerAvatar: peerAvatar,
          conversationId: cid,
        );
      } else {
        await _sendChatInviteToPeer(peerId, peerName);
      }
      return;
    }
    await _openChatForPeer(
      peerId: peerId,
      peerName: peerName,
      peerAvatar: peerAvatar,
    );
  }

  /// 首頁配對卡：邀請聊天（雲端）+ 進入聊天
  Widget _buildDiscoverChatActionColumn(
    Map<String, dynamic> user, {
    required double f,
    bool compact = false,
  }) {
    final peerId = user['id']?.toString() ?? '';
    final peerName = user['name']?.toString() ?? '';
    final peerAvatar = user['avatar']?.toString() ?? '';
    final isDemo = isDemoDiscoverProfile(user);
    final showInvite = _useFirestoreDiscover && peerId.length >= 20 && !isDemo;
    final mobileInviteBoost = compact ? 0.3 * AppConstants.logicalPxPerCm : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showInvite) ...[
          PressableOpacity(
            onPressed: () => _sendChatInviteToPeer(peerId, peerName),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12 * f),
              decoration: BoxDecoration(
                color: AppConstants.white,
                borderRadius: BorderRadius.circular(AppConstants.borderRadius),
                border:
                    Border.all(color: AppConstants.primaryColor, width: 1.5),
              ),
              child: Text(
                '邀請聊天',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: (compact ? 14.0 : 15) + mobileInviteBoost,
                  fontWeight: FontWeight.w600,
                  color: AppConstants.primaryColor,
                ),
              ),
            ),
          ),
          SizedBox(height: 8 * f),
        ],
        PressableOpacity(
          onPressed: () => _onDiscoverEnterChat(
            peerId,
            peerName,
            peerAvatar,
            showInvite,
            isDemoProfile: isDemo,
          ),
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12 * f),
            decoration: BoxDecoration(
              color: AppConstants.primaryColor,
              borderRadius: BorderRadius.circular(AppConstants.borderRadius),
            ),
            child: Text(
              '進入聊天',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: compact ? 14.0 : 15,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 大頭照縮至約 5cm（約 188 邏輯像素，1cm≈37.8px）
  static const double _avatarSizePx = 188.0;

  /// 手機版配對卡：垂直高度縮短約 1/3（間距、頭像、字級一併收緊）
  static const double _mobileCardCompactFactor = 2.0 / 3.0;

  /// 電腦版配對卡紅圈內（職業·距離、一句話、興趣標籤）黑字 +0.1cm
  static const double _desktopRedCircleTextBoost =
      0.1 * AppConstants.logicalPxPerCm;

  Widget _buildUserCard(int index, {bool compact = false}) {
    final user = _userList[index];
    final isDemoCard = isDemoDiscoverProfile(user);
    final tags = user['tags'] as List<dynamic>;
    final f = compact ? _mobileCardCompactFactor : 1.0;
    final avatarSize = _avatarSizePx * f;

    /// 手機版配對人資料字級 +0.1cm（1cm≈37.8 logical px）
    final mobileProfileFs = compact ? AppConstants.logicalPxPerCm * 0.1 : 0.0;
    final desktopRedCircleFs = compact ? 0.0 : _desktopRedCircleTextBoost;
    return Slidable(
      endActionPane: ActionPane(
        motion: const ScrollMotion(),
        children: [
          SlidableAction(
            onPressed: (_) => _handleSlideAction(index, 'like'),
            backgroundColor: AppConstants.primaryColor,
            foregroundColor: AppConstants.white,
            icon: Icons.favorite,
            label: '喜歡',
          ),
        ],
      ),
      startActionPane: ActionPane(
        motion: const ScrollMotion(),
        children: [
          SlidableAction(
            onPressed: (_) => _handleSlideAction(index, 'pass'),
            backgroundColor: AppConstants.grey,
            foregroundColor: AppConstants.white,
            icon: Icons.close,
            label: '略過',
          ),
        ],
      ),
      child: Container(
        margin: EdgeInsets.symmetric(horizontal: 12, vertical: 10 * f),
        width: double.infinity,
        decoration: BoxDecoration(
          color: AppConstants.white,
          borderRadius: BorderRadius.circular(AppConstants.cardRadius),
          boxShadow: [
            BoxShadow(
              color: AppConstants.grey.withOpacity(0.1),
              blurRadius: 8,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            // 大頭照縮至 5cm，置中（手機版再乘 compact 係數）
            Padding(
              padding: EdgeInsets.only(top: 20 * f),
              child: Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(avatarSize / 2),
                  child: SizedBox(
                    width: avatarSize,
                    height: avatarSize,
                    child: AvatarImageBox(
                      avatar: user['avatar']?.toString(),
                      width: avatarSize,
                      height: avatarSize,
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16 * f),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    '${user['name']}, ${user['age']}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: (compact ? 17 : 20) + mobileProfileFs,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                  SizedBox(height: 6 * f),
                  Text(
                    isDemoCard
                        ? '${user['job']}'
                        : '${user['job']} · ${user['distance']}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: (compact ? 13.0 : 15) +
                          mobileProfileFs +
                          desktopRedCircleFs,
                    ),
                  ),
                  if ((user['sentence'] ?? '').toString().isNotEmpty) ...[
                    SizedBox(height: 8 * f),
                    Text(
                      (user['sentence'] ?? '').toString(),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: (compact ? 12.0 : 14) +
                            mobileProfileFs +
                            desktopRedCircleFs,
                        color: Colors.black,
                        fontStyle: FontStyle.italic,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  SizedBox(height: 12 * f),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8 * f,
                    runSpacing: 6 * f,
                    children: (tags.take(3).map((e) => e.toString()))
                        .map<Widget>((tag) => Container(
                              padding: EdgeInsets.symmetric(
                                  horizontal: 12 * f, vertical: 5 * f),
                              decoration: BoxDecoration(
                                color: AppConstants.backgroundColor,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                tag,
                                style: TextStyle(
                                  fontSize: (compact ? 12.0 : 13) +
                                      mobileProfileFs +
                                      desktopRedCircleFs,
                                  color: Colors.black,
                                ),
                              ),
                            ))
                        .toList(),
                  ),
                  SizedBox(height: 16 * f),
                  _buildDiscoverChatActionColumn(user, f: f, compact: compact),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final langProvider = Provider.of<LanguageProvider>(context);

    return Scaffold(
      backgroundColor: AppConstants.backgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              color: const Color(0xFFE8E8E8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: AppConstants.homeSearchHeaderVerticalPadding,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            decoration: InputDecoration(
                              hintText: '搜尋',
                              prefixIcon: const Icon(Icons.search,
                                  color: AppConstants.grey, size: 22),
                              filled: true,
                              fillColor: const Color(0xFFFFF9C4),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(20),
                                borderSide: BorderSide.none,
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(20),
                                borderSide: const BorderSide(
                                    color: AppConstants.primaryColor),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 10),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        PressableOpacity(
                          onPressed: () {
                            context.go('/setting');
                          },
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: AppConstants.primaryColor,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.settings,
                                color: AppConstants.white, size: 22),
                          ),
                        ),
                        const SizedBox(width: 8),
                        PressableOpacity(
                          onPressed: () {
                            context.go('/event');
                          },
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: AppConstants.primaryColor,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.event,
                                color: AppConstants.white, size: 22),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    child: PressableOpacity(
                      onPressed: _openFilterPanel,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF9C4),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: AppConstants.primaryColor,
                            width: 2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppConstants.primaryColor.withOpacity(0.2),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.filter_list,
                              size: 22,
                              color: AppConstants.primaryColor,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                langProvider.getString('filter'),
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: AppConstants.primaryColor,
                                ),
                              ),
                            ),
                            Icon(
                              Icons.chevron_right,
                              color: AppConstants.primaryColor,
                              size: 22,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (_showIncompleteProfileTip)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF3E0),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: AppConstants.primaryColor,
                            width: 1.5,
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Padding(
                              padding: EdgeInsets.only(top: 2),
                              child: Icon(
                                Icons.tips_and_updates_outlined,
                                color: AppConstants.primaryColor,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                langProvider.getString('home_first_tip_body'),
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.black87,
                                  height: 1.35,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            TextButton(
                              onPressed: () {
                                context.go('/talking');
                              },
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.white,
                                backgroundColor: AppConstants.primaryColor,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                minimumSize: const Size(0, 36),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: const Text('想講～'),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: _userList.isEmpty
                  ? Center(
                      child: Text(
                        '暫無匹配用戶，請調整篩選條件',
                        style: TextStyle(color: AppConstants.grey),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.only(top: 8, bottom: 16),
                      itemCount: _userList.length,
                      itemBuilder: (context, index) =>
                          _buildUserCard(index, compact: true),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
