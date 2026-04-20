import 'dart:async' show unawaited;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/feed_provider.dart';
import '../utils/constants.dart';
import '../utils/ad_promotion_utils.dart';
import '../utils/launch_url_helper.dart';
import '../utils/mock_data.dart';
import '../widgets/avatar_image_box.dart';
import '../providers/auth_provider.dart';
import '../providers/language_provider.dart';
import '../providers/nearby_location_provider.dart';
import '../providers/nav_provider.dart';
import '../services/nearby_api.dart';
import '../services/screen_capture_platform.dart';
import '../services/user_firestore_service.dart';
import '../services/feed_firestore_service.dart';
import '../widgets/gender_filter.dart';
import '../widgets/main_tab_app_bar.dart';
import '../widgets/chat_quota_gate.dart';
import '../services/firebase_bootstrap.dart';
import 'chat_detail_page.dart';

/// 附近的人：篩選出來、可按入進入對話
class NearbyPage extends StatefulWidget {
  const NearbyPage({super.key});

  @override
  State<NearbyPage> createState() => _NearbyPageState();
}

class _NearbyPageState extends State<NearbyPage> with WidgetsBindingObserver {
  List<Map<String, dynamic>> _users = [];
  bool _loading = true;
  String? _error;

  /// 探索對象性別（與 [AppConstants.discoverOppositeGender] 同步，依「我的性別」自動為異性）
  String _genderFilter = 'male';
  RangeValues _ageRange = const RangeValues(18, 60);
  double _maxDistanceKm = 10;
  AuthProvider? _authForNearbyListener;
  String? _lastSyncedProfileGenderForNearby;

  List<Map<String, dynamic>> _mergePromotionAdsIntoNearby(
    List<Map<String, dynamic>> base,
    List<UserPostItem> promotions,
  ) {
    return mergePromotionItems<Map<String, dynamic>, UserPostItem>(
      items: base,
      promotions: promotions.where((p) => p.isAdPromotion).toList(),
      pageSalt: 'nearby_page',
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

  Widget _buildPromotionNearbyCard(UserPostItem promotion) {
    final imageUrl = (promotion.imageUrl ?? '').trim();
    final link = (promotion.externalLink ?? '').trim();
    final title = promotion.name.trim();
    final hasImageBytes =
        promotion.imageBytes != null && promotion.imageBytes!.isNotEmpty;
    return InkWell(
      enableFeedback: false,
      onTap: link.isNotEmpty ? () => _openPromotionLink(promotion) : null,
      borderRadius: BorderRadius.circular(AppConstants.cardRadius),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF8E1),
          borderRadius: BorderRadius.circular(AppConstants.cardRadius),
          border: Border.all(color: const Color(0xFFFFD54F)),
          boxShadow: [
            BoxShadow(
              color: AppConstants.grey.withOpacity(0.08),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: hasImageBytes
                      ? Image.memory(
                          Uint8List.fromList(promotion.imageBytes!),
                          width: 72,
                          height: 72,
                          fit: BoxFit.cover,
                        )
                      : imageUrl.isNotEmpty
                          ? Image.network(
                              imageUrl,
                              width: 72,
                              height: 72,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                width: 72,
                                height: 72,
                                color: const Color(0xFFFFECB3),
                                child: const Icon(Icons.campaign,
                                    color: Colors.brown),
                              ),
                            )
                          : Container(
                              width: 72,
                              height: 72,
                              color: const Color(0xFFFFECB3),
                              child: const Icon(Icons.campaign,
                                  color: Colors.brown),
                            ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (title.isNotEmpty &&
                          !isAdPromotionPlaceholderName(title)) ...[
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                      ],
                      Text(
                        promotion.content,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.black,
                          height: 1.35,
                        ),
                      ),
                      if (link.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          link,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.blue.shade700,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (link.isNotEmpty)
                  const Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: Icon(Icons.open_in_new, color: Colors.black54),
                  ),
              ],
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.red, width: 1.5),
                  ),
                  alignment: Alignment.center,
                  child: const Text(
                    '廣告',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.red,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ScreenCapturePlatform.allowScreenshots();
      if (!mounted) return;
      _authForNearbyListener =
          Provider.of<AuthProvider>(context, listen: false);
      _authForNearbyListener!.addListener(_onAuthProfileForNearby);
      _syncNearbyOppositeGender();
    });
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authForNearbyListener?.removeListener(_onAuthProfileForNearby);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ScreenCapturePlatform.allowScreenshots();
    }
  }

  void _onAuthProfileForNearby() {
    _syncNearbyOppositeGender();
  }

  void _syncNearbyOppositeGender() {
    if (!mounted) return;
    final auth = Provider.of<AuthProvider>(context, listen: false);
    if (_lastSyncedProfileGenderForNearby == auth.profileGender) return;
    _lastSyncedProfileGenderForNearby = auth.profileGender;
    final target = AppConstants.discoverOppositeGender(auth.profileGender);
    setState(() => _genderFilter = target);
  }

  List<Map<String, dynamic>> get _filteredUsers {
    return _users.where((u) {
      final ug = (u['gender'] as String?)?.trim().toLowerCase() ?? 'male';
      if (ug != _genderFilter) return false;
      final age = u['age'] is int
          ? u['age'] as int
          : int.tryParse(u['age']?.toString() ?? '') ?? 0;
      if (age < _ageRange.start || age > _ageRange.end) return false;
      final distStr = (u['distance'] as String?) ?? '';
      final distKm = _parseDistanceKm(distStr);
      if (distKm != null && distKm > _maxDistanceKm) return false;
      return true;
    }).toList();
  }

  double? _parseDistanceKm(String s) {
    if (s.contains('m') || s.contains('內')) {
      final num = double.tryParse(s.replaceAll(RegExp(r'[^0-9.]'), ''));
      return num != null ? num / 1000 : null;
    }
    final num = double.tryParse(s.replaceAll(RegExp(r'[^0-9.]'), ''));
    return num;
  }

  List<Map<String, dynamic>> _mergeNearbyListsWithRealFirst(
    List<Map<String, dynamic>> realUsers,
    List<Map<String, dynamic>> fallbackUsers,
  ) {
    if (realUsers.isEmpty)
      return List<Map<String, dynamic>>.from(fallbackUsers);
    final out = realUsers.map(Map<String, dynamic>.from).toList();
    final usedIds = out.map((u) => (u['id'] ?? '').toString()).toSet();
    for (final row in fallbackUsers) {
      final id = (row['id'] ?? '').toString();
      if (id.isNotEmpty && usedIds.contains(id)) continue;
      if (id.isNotEmpty) usedIds.add(id);
      out.add(Map<String, dynamic>.from(row));
    }
    return out;
  }

  List<Map<String, dynamic>> _pickFallbackNearbyUsers(
    List<Map<String, dynamic>> users,
    int targetCount,
  ) {
    if (targetCount <= 0 || users.isEmpty) return <Map<String, dynamic>>[];
    final filtered = users
        .where((u) =>
            ((u['gender'] as String?)?.trim().toLowerCase() ?? 'male') ==
            _genderFilter)
        .toList();
    final source = filtered.isNotEmpty ? filtered : users;
    return source.take(targetCount).map(Map<String, dynamic>.from).toList();
  }

  void _openFilter() {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final langProvider = Provider.of<LanguageProvider>(context, listen: false);
    var age = _ageRange;
    var maxKm = _maxDistanceKm;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) {
          const circledLabelFs =
              14.0 + AppConstants.nearbyFilterCircledLabelsExtra;
          return Container(
            padding: const EdgeInsets.all(AppConstants.padding),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: SafeArea(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Center(
                      child: SizedBox(
                        width: 40,
                        height: 4,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.grey,
                            borderRadius: BorderRadius.all(Radius.circular(2)),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      langProvider.getString('filter'),
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '想認識異性',
                      style: TextStyle(
                        fontSize: circledLabelFs,
                        color: const Color(0xFF000000),
                      ),
                    ),
                    IgnorePointer(
                      child: GenderFilter(
                        key: ValueKey(authProvider.profileGender),
                        initialGender: AppConstants.discoverOppositeGender(
                          authProvider.profileGender,
                        ),

                        /// 首頁篩選性別基準後再加大 0.5cm（見 [AppConstants.logicalPxPerCm]）
                        fontSizeExtraDelta: -AppConstants.filterFontShrink4mm -
                            0.2 * AppConstants.logicalPxPerCm +
                            0.5 * AppConstants.logicalPxPerCm,
                        onSelect: (_) {},
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '年齡範圍 ${age.start.toInt()} - ${age.end.toInt()}',
                      style: TextStyle(fontSize: circledLabelFs),
                    ),
                    RangeSlider(
                      values: age,
                      min: AppConstants.discoverAgeFilterMin,
                      max: AppConstants.discoverAgeFilterMax,
                      divisions: AppConstants.discoverAgeFilterDivisions,
                      onChanged: (v) => setModal(() => age = v),
                      activeColor: AppConstants.primaryColor,
                    ),
                    Text(
                      '距離 ${maxKm.toInt()} km 內',
                      style: TextStyle(fontSize: circledLabelFs),
                    ),
                    Slider(
                      value: maxKm,
                      min: 1,
                      max: 50,
                      divisions: 49,
                      onChanged: (v) => setModal(() => maxKm = v),
                      activeColor: AppConstants.primaryColor,
                    ),
                    const SizedBox(height: 8),
                    Consumer<NearbyLocationProvider>(
                      builder: (context, nearbyLoc, _) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(
                                Icons.location_on_outlined,
                                color: AppConstants.primaryColor,
                                size: 22,
                              ),
                              title: Text(
                                langProvider.getString('location_for_nearby'),
                                style: TextStyle(
                                  fontSize:
                                      (14 + 0.2 * AppConstants.logicalPxPerCm)
                                          .clamp(12.0, 24.0),
                                ),
                              ),
                              trailing: Switch(
                                value: nearbyLoc.useLocationForNearby,
                                onChanged: (v) async {
                                  await nearbyLoc.setUseLocation(v);
                                  if (!v &&
                                      FirebaseBootstrap.isReady &&
                                      mounted) {
                                    await UserFirestoreService.instance
                                        .updateUserRegionGps(visible: false);
                                  }
                                  setModal(() {});
                                },
                                activeColor: AppConstants.primaryColor,
                              ),
                            ),
                            Padding(
                              padding:
                                  const EdgeInsets.only(left: 4, bottom: 8),
                              child: Text(
                                langProvider
                                    .getString('location_for_nearby_hint'),
                                style: TextStyle(
                                  fontSize:
                                      (12 + 0.2 * AppConstants.logicalPxPerCm)
                                          .clamp(11.0, 20.0),
                                  color: AppConstants.grey,
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () async {
                          final auth =
                              Provider.of<AuthProvider>(context, listen: false);
                          setState(() {
                            _genderFilter = AppConstants.discoverOppositeGender(
                                auth.profileGender);
                            _ageRange = age;
                            _maxDistanceKm = maxKm;
                          });
                          Navigator.pop(ctx);
                          await _load();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppConstants.primaryColor,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                  AppConstants.borderRadius)),
                        ),
                        child: const Text('套用'),
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

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final nearbyLoc =
          Provider.of<NearbyLocationProvider>(context, listen: false);
      final lang = Provider.of<LanguageProvider>(context, listen: false);

      double? lat;
      double? lng;
      var locationFailed = false;
      if (nearbyLoc.useLocationForNearby) {
        try {
          final pos = await nearbyLoc.getCurrentPositionIfPermitted();
          if (pos != null) {
            lat = pos.latitude;
            lng = pos.longitude;
            if (FirebaseBootstrap.isReady) {
              await UserFirestoreService.instance.updateUserRegionGps(
                visible: true,
                latitude: lat,
                longitude: lng,
              );
            }
          } else {
            locationFailed = true;
          }
        } catch (e, st) {
          locationFailed = true;
          debugPrint('NearbyPage _load position: $e\n$st');
        }
      }

      final radius = _maxDistanceKm.round().clamp(1, 500);
      List<Map<String, dynamic>> remoteList;
      try {
        remoteList = await NearbyApi.getNearbyUsers(
          radiusKm: radius,
          lat: lat,
          lng: lng,
          allowMockFallback: false,
        );
      } catch (e, st) {
        debugPrint('NearbyApi.getNearbyUsers: $e\n$st');
        remoteList = <Map<String, dynamic>>[];
      }

      final auth = Provider.of<AuthProvider>(context, listen: false);
      final realList = await UserFirestoreService.instance.fetchNearbyRealUsers(
        excludeUid: auth.uid,
        latitude: lat,
        longitude: lng,
        radiusKm: radius,
      );
      final realIds = realList.map((u) => (u['id'] ?? '').toString()).toSet();
      final dedupedRemote = remoteList
          .where((u) => !realIds.contains((u['id'] ?? '').toString()))
          .map(Map<String, dynamic>.from)
          .toList();
      final fallbackList = dedupedRemote.isNotEmpty
          ? dedupedRemote
          : _pickFallbackNearbyUsers(getMockUserList(), realList.length + 8);
      final list = _mergeNearbyListsWithRealFirst(realList, fallbackList);

      var completeOnly = list.where(isDiscoverCardCompleteForMatching).toList();
      // 後備：後端／mock 有資料但不符合配對欄位完整度時，仍顯示列表避免整頁空白
      if (completeOnly.isEmpty && list.isNotEmpty) {
        completeOnly = List<Map<String, dynamic>>.from(list);
      }

      if (!mounted) return;
      setState(() {
        _users = completeOnly;
        _loading = false;
        _error = null;
      });

      if (locationFailed && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(lang.getString('location_fetch_failed'))),
        );
      }
    } catch (e, st) {
      debugPrint('NearbyPage _load: $e\n$st');
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
        _users = [];
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final langProvider = Provider.of<LanguageProvider>(context);

    return Scaffold(
      appBar: MainTabAppBar(
        title: langProvider.getString('nearby'),
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
            icon: Icons.filter_list,
            onPressed: _loading ? null : _openFilter,
            tooltip: '篩選',
          ),
          const SizedBox(width: MainTabAppBar.actionGap),
          MainTabAppBar.buildCircleActionButton(
            icon: Icons.refresh,
            onPressed: _loading ? null : _load,
            tooltip: '重新整理',
          ),
        ],
      ),
      backgroundColor: AppConstants.backgroundColor,
      body: _loading
          ? const Center(
              child:
                  CircularProgressIndicator(color: AppConstants.primaryColor))
          : _error != null && _users.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '無法載入附近的人',
                          style: TextStyle(
                            fontSize: 16,
                            color: AppConstants.grey,
                          ),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _load,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppConstants.primaryColor,
                          ),
                          child: const Text('重試'),
                        ),
                      ],
                    ),
                  ),
                )
              : _filteredUsers.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _users.isEmpty ? '目前附近沒有用戶' : '篩選後無符合的用戶',
                            style: TextStyle(color: AppConstants.grey),
                          ),
                          if (_users.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            TextButton(
                              onPressed: _openFilter,
                              child: const Text('調整篩選條件'),
                            ),
                          ],
                        ],
                      ),
                    )
                  : Builder(
                      builder: (context) {
                        final promotionPosts =
                            Provider.of<FeedProvider>(context).userPosts;
                        final mergedUsers = _mergePromotionAdsIntoNearby(
                          _filteredUsers,
                          promotionPosts,
                        );
                        return ListView.builder(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          itemCount: mergedUsers.length,
                          itemBuilder: (context, index) {
                            final user = mergedUsers[index];
                            if (user['isPromotionAd'] == true) {
                              final promotion =
                                  user['promotion'] as UserPostItem?;
                              if (promotion == null) {
                                return const SizedBox.shrink();
                              }
                              return _buildPromotionNearbyCard(promotion);
                            }
                            final tags = user['tags'] as List<dynamic>? ?? [];
                            final userId = user['id']?.toString() ?? '';
                            final name = user['name']?.toString() ?? '';
                            final avatar = user['avatar']?.toString() ?? '';
                            final isMobile = MediaQuery.sizeOf(context).width <
                                AppConstants.layoutWideBreakpoint;

                            /// 手機：名稱行 +0.1cm；手機／電腦：次要灰字改黑並 +0.1cm（職稱距離、一句話、標籤）
                            const secondaryBoost =
                                0.1 * AppConstants.logicalPxPerCm;
                            final nameBoost = isMobile ? secondaryBoost : 0.0;
                            return InkWell(
                              enableFeedback: false,
                              onTap: () async {
                                final auth = Provider.of<AuthProvider>(
                                  context,
                                  listen: false,
                                );
                                final me = auth.uid;
                                if (FirebaseBootstrap.isReady &&
                                    me != null &&
                                    userId.length >= 20 &&
                                    !await ensureMessagingThreadAllowed(
                                      context,
                                      myUid: me,
                                      peerUserId: userId,
                                    )) {
                                  return;
                                }
                                if (!context.mounted) return;
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => ChatDetailPage(
                                      userId: userId,
                                      name: name,
                                      avatar: avatar.isNotEmpty
                                          ? avatar
                                          : 'https://picsum.photos/seed/nearby_default/100/100',
                                    ),
                                  ),
                                );
                              },
                              borderRadius: BorderRadius.circular(
                                  AppConstants.cardRadius),
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: AppConstants.white,
                                  borderRadius: BorderRadius.circular(
                                      AppConstants.cardRadius),
                                  boxShadow: [
                                    BoxShadow(
                                      color:
                                          AppConstants.grey.withOpacity(0.08),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  children: [
                                    ClipOval(
                                      child: AvatarImageBox(
                                        avatar:
                                            avatar.isNotEmpty ? avatar : null,
                                        width: 56,
                                        height: 56,
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '$name, ${user['age']}',
                                            style: TextStyle(
                                              fontSize: 17 + nameBoost,
                                              fontWeight: FontWeight.bold,
                                              color: isMobile
                                                  ? Colors.black
                                                  : null,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            '${user['job']} · ${user['distance']}',
                                            style: TextStyle(
                                              fontSize: 13 + secondaryBoost,
                                              color: Colors.black,
                                            ),
                                          ),
                                          if ((user['sentence'] ?? '')
                                              .toString()
                                              .isNotEmpty) ...[
                                            const SizedBox(height: 4),
                                            Text(
                                              (user['sentence'] ?? '')
                                                  .toString(),
                                              style: TextStyle(
                                                fontSize: 12 + secondaryBoost,
                                                color: Colors.black,
                                                fontStyle: FontStyle.italic,
                                              ),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                          if (tags.isNotEmpty) ...[
                                            const SizedBox(height: 8),
                                            Wrap(
                                              spacing: 6,
                                              runSpacing: 4,
                                              children: (tags
                                                      .take(3)
                                                      .map((e) => e.toString()))
                                                  .map<Widget>((tag) =>
                                                      Container(
                                                        padding:
                                                            const EdgeInsets
                                                                .symmetric(
                                                                horizontal: 8,
                                                                vertical: 2),
                                                        decoration:
                                                            BoxDecoration(
                                                          color: AppConstants
                                                              .backgroundColor,
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(10),
                                                        ),
                                                        child: Text(
                                                          tag,
                                                          style: TextStyle(
                                                            fontSize: 11 +
                                                                secondaryBoost,
                                                            color: Colors.black,
                                                          ),
                                                        ),
                                                      ))
                                                  .toList(),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    const Icon(
                                      Icons.chevron_right,
                                      color: Colors.black,
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
    );
  }
}
