import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../providers/language_provider.dart';
import '../services/activity_firestore_service.dart';
import '../services/firebase_bootstrap.dart';
import '../utils/activity_title_image.dart';
import '../utils/constants.dart';
import '../utils/event_url_slug.dart';
import '../widgets/activity_detail_registration_sheet.dart';
import '../widgets/storage_network_image.dart';

/// 單一活動資料（圖片、標題、價錢、了解詳情）
class _ActivityItem {
  final String id;
  final String title;
  final String imageUrl;
  final String price;
  final String? subtitle;

  /// 與後台選擇的付款方式一致（本地化顯示）
  final String? paymentMethodLabel;

  /// 活動內文（Firestore [activities.body]）
  final String? bodyText;

  /// 報名頁「活動詳情」（後台 [event_cms.activityDetail] → [activities.activityDetail]）
  final String? activityDetail;

  /// 報名頁「了解詳情」右上角海報（後台 [registrationPosterUrl]）
  final String? registrationPosterUrl;

  /// 報名人數上限 1–10（後台 [event_cms]／[activities.maxParticipants]）
  final int maxParticipants;

  /// 後台可填多個；會員報名頁橫向滑動選擇（[activities.activityDateOptions]）
  final List<String> activityDateOptions;

  _ActivityItem({
    required this.id,
    required this.title,
    required this.imageUrl,
    required this.price,
    this.subtitle,
    this.paymentMethodLabel,
    this.bodyText,
    this.activityDetail,
    this.registrationPosterUrl,
    this.maxParticipants = 10,
    this.activityDateOptions = const [],
  });

  /// 與後台同步：[activities.imageUrl] 優先；若僅上傳報名海報則同 [Sync] 使用 [registrationPosterUrl]。
  String get resolvedListImageUrl {
    final a = imageUrl.trim();
    if (a.isNotEmpty) return a;
    return registrationPosterUrl?.trim() ?? '';
  }
}

/// 列表／格狀廣告只顯示價錢字樣，不顯示付款方式（後台可能把金額與付款方式寫在同一欄或多行）。
String _activityCardPriceLine(_ActivityItem item) {
  final raw = item.price.trim();
  if (raw.isEmpty) return '—';
  final pm = item.paymentMethodLabel?.trim();
  for (final part in raw.split(RegExp(r'[\r\n]+'))) {
    var line = part.trim();
    if (line.isEmpty) continue;
    if (pm != null && pm.isNotEmpty) {
      if (line == pm) continue;
      if (line.contains(pm)) {
        line = line.replaceAll(pm, '').trim();
        line = line.replaceAll(RegExp(r'^[·•／/\s]+|[·•／/\s]+$'), '');
      }
    }
    if (line.isNotEmpty) return line;
  }
  return '—';
}

/// 活動頁面：淺黃底色；手機一行兩個、寬螢幕一行三個；**每頁固定 20 筆**，排滿後於底部分頁切換。
class ActivityPage extends StatefulWidget {
  const ActivityPage({
    super.key,
    this.initialEventSlug,
    this.seoPath,
  });

  /// 與 [eventUrlSlug] 一致時自動開啟該活動報名浮層（公開網址 `/event/...`）。
  final String? initialEventSlug;

  /// 非 null 時顯示 SEO 主標並調整返回鈕（`/event` 或 `/event/slug`）。
  final String? seoPath;

  @override
  State<ActivityPage> createState() => _ActivityPageState();
}

class _ActivityPageState extends State<ActivityPage> {
  final TextEditingController _searchController = TextEditingController();
  int _currentPageIndex = 0;
  String _keyword = '';

  /// 已處理過的 slug（含「找不到」），避免重複彈層。
  String? _resolvedSlugSession;

  static const double _mobileBreakpoint = 600;

  /// 每頁展示活動筆數（手機／寬螢幕一致）。
  static const int _itemsPerPage = 20;

  static int _compareDocsByUpdatedAtDesc(
    QueryDocumentSnapshot<Map<String, dynamic>> a,
    QueryDocumentSnapshot<Map<String, dynamic>> b,
  ) {
    final ta = a.data()['updatedAt'];
    final tb = b.data()['updatedAt'];
    final da = ta is Timestamp ? ta.millisecondsSinceEpoch : 0;
    final db = tb is Timestamp ? tb.millisecondsSinceEpoch : 0;
    return db.compareTo(da);
  }

  static _ActivityItem? _itemFromFirestoreDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> d,
    LanguageProvider lang,
  ) {
    final m = d.data();
    final title = (m['title'] as String?)?.trim();
    if (title == null || title.isEmpty) return null;
    final imageUrl = (m['imageUrl'] ?? '').toString().trim();
    final price = (m['price'] as String?)?.trim() ?? '—';
    final sub = (m['subtitle'] as String?)?.trim();
    final pm = (m['paymentMethod'] as String?)?.trim();
    final pmLabel = (pm != null && pm.isNotEmpty)
        ? lang.paymentMethodLabelForActivity(pm)
        : null;
    final bodyRaw = (m['body'] as String?)?.trim();
    final detailRaw = (m['activityDetail'] as String?)?.trim();
    final posterRaw = (m['registrationPosterUrl'] ?? '').toString().trim();
    final capRaw = m['maxParticipants'];
    var cap = 10;
    if (capRaw is int) {
      cap = capRaw.clamp(1, 10);
    } else if (capRaw is num) {
      cap = capRaw.toInt().clamp(1, 10);
    }
    final dateOpts = <String>[];
    final rawDates = m['activityDateOptions'];
    if (rawDates is List) {
      for (final e in rawDates) {
        final s = e.toString().trim();
        if (s.isNotEmpty) dateOpts.add(s);
      }
    }
    return _ActivityItem(
      id: d.id,
      title: title,
      imageUrl: imageUrl,
      price: price,
      subtitle: sub != null && sub.isNotEmpty ? sub : null,
      paymentMethodLabel: pmLabel,
      bodyText: bodyRaw != null && bodyRaw.isNotEmpty ? bodyRaw : null,
      activityDetail:
          detailRaw != null && detailRaw.isNotEmpty ? detailRaw : null,
      registrationPosterUrl: posterRaw.isNotEmpty ? posterRaw : null,
      maxParticipants: cap,
      activityDateOptions: dateOpts,
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// 搜尋依活動標題、副標題與顯示價錢字串（不比對長篇內文）。
  List<_ActivityItem> _filteredActivities(List<_ActivityItem> all) {
    final raw = _keyword.trim();
    if (raw.isEmpty) return all;
    final k = raw.toLowerCase();
    return all.where((a) {
      if (a.title.toLowerCase().contains(k)) return true;
      final sub = a.subtitle?.trim() ?? '';
      if (sub.isNotEmpty && sub.toLowerCase().contains(k)) return true;
      if (a.price.toLowerCase().contains(k)) return true;
      return false;
    }).toList();
  }

  int _totalPages(List<_ActivityItem> filtered, int perPage) =>
      (filtered.length / perPage).ceil().clamp(1, 999999);

  List<_ActivityItem> _currentPageItems(
    List<_ActivityItem> filtered,
    int perPage,
  ) {
    final start = _currentPageIndex * perPage;
    if (start >= filtered.length) return [];
    final end = (start + perPage).clamp(0, filtered.length);
    return filtered.sublist(start, end);
  }

  Widget _buildActivityListBody({
    required List<_ActivityItem> allActivities,
    String? seoPath,
  }) {
    const perPage = _itemsPerPage;
    final filtered = _filteredActivities(allActivities);
    final totalPages = _totalPages(filtered, perPage);
    final pageItems = _currentPageItems(filtered, perPage);
    if (_currentPageIndex >= totalPages && totalPages > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _currentPageIndex = totalPages - 1);
      });
    }

    Widget gridOrEmpty() {
      if (allActivities.isEmpty) {
        return ColoredBox(
          color: _activityPageBackground,
          child: const Center(child: Text('尚無活動')),
        );
      }
      if (pageItems.isEmpty) {
        return ColoredBox(
          color: _activityPageBackground,
          child: const Center(child: Text('暫無符合的活動')),
        );
      }
      return LayoutBuilder(
        builder: (context, constraints) {
          final isMobile = constraints.maxWidth < _mobileBreakpoint;
          final paddingH = _edgePadding1cmPx * 2;
          final gap = _activitySpacingHalfCmPx;
          final crossCount = isMobile ? 2 : 3;
          final gapsH = gap * (crossCount - 1);
          final cellWidth =
              (constraints.maxWidth - paddingH - gapsH) / crossCount;
          final double ratio;
          if (isMobile) {
            /// 格高 ≈ 固定區塊 + 正方形圖邊長（≈ contentW），避免白底卡面在按鈕下多出空白。
            final contentW = (cellWidth - _compactCardHorizontalPadPx * 2)
                .clamp(0.0, double.infinity);
            final targetCellHeight =
                _compactCellFixedNoImagePx + contentW;
            ratio = targetCellHeight > 1.0
                ? cellWidth / targetCellHeight
                : _mobileGridAspectRatioFallback;
          } else {
            final cellHeight = _contentBoxMaxHeightPx;
            ratio = cellWidth / cellHeight;
          }
          return ColoredBox(
            color: _activityPageBackground,
            child: GridView.builder(
              padding: EdgeInsets.fromLTRB(
                _edgePadding1cmPx,
                _edgePadding1cmPx,
                _edgePadding1cmPx,
                12,
              ),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossCount,
                childAspectRatio: ratio,
                crossAxisSpacing: gap,
                mainAxisSpacing: gap,
              ),
              itemCount: pageItems.length,
              itemBuilder: (context, index) => _buildActivityCard(
                context,
                pageItems[index],
                compact: isMobile,
              ),
            ),
          );
        },
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          color: _activitySearchStripBackground,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: TextField(
            controller: _searchController,
            onChanged: (v) => setState(() {
              _keyword = v;
              _currentPageIndex = 0;
            }),
            decoration: InputDecoration(
              hintText: 'Q 搜尋關鍵字...',
              prefixIcon:
                  const Icon(Icons.search, color: AppConstants.grey, size: 22),
              filled: true,
              fillColor: const Color(0xFFFFF9C4),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: BorderSide.none,
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
        ),
        Expanded(child: gridOrEmpty()),
        if (totalPages > 1) _buildPaginationBar(totalPages),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<LanguageProvider>(context);

    if (!FirebaseBootstrap.isReady) {
      return Scaffold(
        backgroundColor: _activityPageBackground,
        appBar: _buildActivityAppBar(context),
        body: const ColoredBox(
          color: _activityPageBackground,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: ActivityFirestoreService.instance.watchActivities(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            backgroundColor: _activityPageBackground,
            appBar: _buildActivityAppBar(context),
            body: ColoredBox(
              color: _activityPageBackground,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    '無法載入活動：${snapshot.error}',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return Scaffold(
            backgroundColor: _activityPageBackground,
            appBar: _buildActivityAppBar(context),
            body: const ColoredBox(
              color: _activityPageBackground,
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }
        final docs = snapshot.data!.docs.toList()
          ..sort(_compareDocsByUpdatedAtDesc);
        final allActivities = docs
            .map((d) => _itemFromFirestoreDoc(d, lang))
            .whereType<_ActivityItem>()
            .toList();

        final wantSlug = widget.initialEventSlug?.toLowerCase().trim();
        if (wantSlug != null &&
            wantSlug.isNotEmpty &&
            _resolvedSlugSession != wantSlug &&
            allActivities.isNotEmpty) {
          _ActivityItem? hit;
          for (final item in allActivities) {
            if (eventUrlSlug(item.title, item.id).toLowerCase() == wantSlug) {
              hit = item;
              break;
            }
          }
          _resolvedSlugSession = wantSlug;
          if (hit != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              _openActivityDetail(context, hit!);
            });
          }
        }

        return Scaffold(
          backgroundColor: _activityPageBackground,
          appBar: _buildActivityAppBar(context),
          body: _buildActivityListBody(
            allActivities: allActivities,
            seoPath: widget.seoPath,
          ),
        );
      },
    );
  }

  PreferredSizeWidget _buildActivityAppBar(BuildContext context) {
    return AppBar(
      title: Text(
        '活動',
        style: TextStyle(
          fontSize: AppConstants.appBarTitleResolvedSize(context, base: 20),
          color: Colors.black87,
        ),
      ),
      backgroundColor: AppConstants.appBarBackground,
      toolbarHeight: AppConstants.appBarToolbarHeight,
      foregroundColor: Colors.black87,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => context.go('/home'),
      ),
    );
  }

  /// 活動頁淺黃底色（與搜尋列略分層）
  static const Color _activityPageBackground = Color(0xFFFFF9E6);
  static const Color _activitySearchStripBackground = Color(0xFFFFF3CC);

  /// 1cm ≈ 38px；手機格寬 4cm；高度與 [childAspectRatio] 一致，略緊貼內容以減少卡底留白。
  /// 過矮時 [Column] 內 [Expanded] 會變 0，畫面變成標題下直接接價錢（圖被擠沒）。
  static const double _imageSizePx = 302;
  /// 寬螢幕（例：iPad）格線單格最大高度；與內文＋0.15cm 底內距對齊，避免格內大塊淺黃或卡下留白。
  static const double _contentBoxMaxHeightPx = 454;
  static const double _edgePadding1cmPx = 38;
  static const double _cmLogicalPx = 38.0;
  /// 手機／寬螢幕活動卡：「了解詳情」下緣到白卡底內距（0.15cm）
  static const double _activityCardButtonBottomClearancePx = 0.15 * _cmLogicalPx;
  static const double _halfCmLogicalPx = 0.5 * _cmLogicalPx;
  /// 手機活動卡頂部白邊（0.15cm）
  static const double _compactCardTopEdgePx = 0.15 * _cmLogicalPx;
  /// 標題與活動圖之間（題述圖向下 0.2cm）
  static const double _compactTitleToImageGapPx = 0.2 * _cmLogicalPx;
  /// 圖與價錢間緊貼
  static const double _compactImageToPriceGapPx = 4.0;
  /// 0.2cm 邏輯像素（價錢字級加量等）
  static const double _pointTwoCmLogicalPx = 0.2 * _cmLogicalPx;
  /// 活動標題字級加量（題述 +0.15cm）
  static const double _activityTitleFontBump015cmPx = 0.15 * _cmLogicalPx;
  static const double _activitySpacingHalfCmPx = _halfCmLogicalPx;
  /// 手機緊湊卡左右內距（須與 [_buildActivityCard] compact 一致）
  static const double _compactCardHorizontalPadPx = 6.0;
  /// 僅手機格狀卡用；基底字級 + [_activityTitleFontBump015cmPx]。
  static const double _mobileCardTitleFontSize =
      14.5 + _activityTitleFontBump015cmPx;
  /// 寬螢幕活動卡標題（與原 18 同步加 0.15cm）
  static const double _wideCardTitleFontSize = 18 + _activityTitleFontBump015cmPx;
  /// 預留兩行標題高度（與標題 [Text] height 1.15 對齊）
  static const double _compactTitleMaxLinesHeightPx =
      _mobileCardTitleFontSize * 1.15 * 2;
  /// 原字級 + 0.2cm（與示意「價錢放大」一致）
  static const double _mobileCardPriceFontSize =
      13.5 + _pointTwoCmLogicalPx;
  static const double _wideCardPriceFontSize = 16 + _pointTwoCmLogicalPx;

  /// 價錢兩行預留（與 compact 卡 [fixedNoImage] 內 [compactPriceBlockMinPx] 一致）
  static const double _compactPriceBlockMinPx = 22.0;
  static const double _compactGapBeforeDetailButtonPx = 6.0;

  /// 「了解詳情」按鈕字級用 [ _mobileFontBump1Cm ]。
  static const double _mobileFontBump1Cm = 38 / 3;

  /// 「了解詳情」按鈕整體縮小 20%，並相對原位置下移 0.5cm（見下方 [SizedBox]）。
  static const double _detailButtonScale = 0.8;

  /// 「了解詳情」字體：加大以避免手機卡片內文字過細。
  static const double _mobileDetailButtonFontSize =
      (10 + _mobileFontBump1Cm * 0.72) * _detailButtonScale;

  /// 按鈕高度放大 40% 後再縮小 20%。
  static const double _mobileDetailButtonHeightPx =
      36 * 1.4 * _detailButtonScale;

  /// 緊湊卡除「正方形圖」以外之固定高度；須與 [_buildActivityCard] compact 內計算一致。
  static double get _compactCellFixedNoImagePx =>
      _compactCardTopEdgePx +
      _activityCardButtonBottomClearancePx +
      _compactTitleMaxLinesHeightPx +
      _compactTitleToImageGapPx +
      _compactImageToPriceGapPx +
      _compactPriceBlockMinPx +
      _compactGapBeforeDetailButtonPx +
      _mobileDetailButtonHeightPx;

  /// 手機格線寬／高比後備（異常窄螢幕時避免除零）
  static const double _mobileGridAspectRatioFallback = 4 / 6.85;

  /// 「了解詳情」按鈕加闊 40%（若超出卡片可用寬度則取上限）。
  static const double _detailButtonWidthMultiplier = 1.4;

  /// 寬螢幕「了解詳情」字體同步加大（含縮小 20%）。
  static const double _wideDetailButtonFontSize =
      18 * 1.2 * _detailButtonScale;

  /// 標題衍生漸層＋可選後台上傳圖（載入失敗時仍顯示漸層）。
  Widget _activityHeroBackground(_ActivityItem item) {
    final url = item.resolvedListImageUrl;
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: activityHeroDecorationForTitle(item.title, seed: item.id),
        ),
        if (url.isNotEmpty)
          LayoutBuilder(
            builder: (context, constraints) {
              return StorageNetworkImage(
                url: url,
                width: constraints.maxWidth,
                height: constraints.maxHeight,
                fit: BoxFit.cover,
                borderRadius: 0,
              );
            },
          ),
      ],
    );
  }

  void _openActivityDetail(BuildContext context, _ActivityItem item) {
    final poster = item.registrationPosterUrl?.trim();
    final resolved = item.resolvedListImageUrl;
    showActivityDetailRegistrationSheet(
      context,
      activityId: item.id,
      title: item.title,
      unitPriceDisplay: item.price,
      activityDetail: item.activityDetail,
      bodyText: item.bodyText ?? item.subtitle,
      activityImageUrl: resolved.isNotEmpty ? resolved : null,
      registrationPosterUrl:
          poster != null && poster.isNotEmpty ? poster : null,
      maxParticipants: item.maxParticipants,
      activityDateOptions: item.activityDateOptions,
    );
  }

  Widget _buildActivityCard(
    BuildContext context,
    _ActivityItem item, {
    required bool compact,
  }) {
    if (compact) {
      /// 必須與 [GridView] 配發的格線寬高一致；[Expanded] 內圖方塊可吸收一／兩行標題高度差，避免按鈕下白帶。
      return LayoutBuilder(
        builder: (context, constraints) {
          final cellW = constraints.maxWidth;
          final cellH = constraints.maxHeight;
          final contentW = (cellW - _compactCardHorizontalPadPx * 2)
              .clamp(0.0, double.infinity);
          return Material(
            color: Colors.white,
            elevation: 2,
            borderRadius: BorderRadius.circular(10),
            clipBehavior: Clip.antiAlias,
            child: SizedBox(
              width: cellW,
              height: cellH,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  _compactCardHorizontalPadPx,
                  _compactCardTopEdgePx,
                  _compactCardHorizontalPadPx,
                  _activityCardButtonBottomClearancePx,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF333333),
                        fontSize: _mobileCardTitleFontSize,
                        fontWeight: FontWeight.w600,
                        height: 1.15,
                      ),
                    ),
                    SizedBox(height: _compactTitleToImageGapPx),
                    Expanded(
                      child: Center(
                        child: LayoutBuilder(
                          builder: (context, imgConstraints) {
                            final side = math.max(
                              0.0,
                              math.min(
                                contentW,
                                imgConstraints.maxHeight,
                              ),
                            );
                            return SizedBox(
                              width: side,
                              height: side,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: _activityHeroBackground(item),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    SizedBox(height: _compactImageToPriceGapPx),
                    Text(
                      item.price,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: _mobileCardPriceFontSize,
                        color: AppConstants.primaryColor,
                        fontWeight: FontWeight.w600,
                        height: 1.0,
                      ),
                    ),
                    SizedBox(height: _compactGapBeforeDetailButtonPx),
                    Center(
                      child: SizedBox(
                        width: math.min(
                          contentW,
                          math.max(100.0, contentW * 0.88) *
                              _detailButtonWidthMultiplier *
                              _detailButtonScale,
                        ),
                        height: _mobileDetailButtonHeightPx,
                        child: ElevatedButton(
                          onPressed: () =>
                              _openActivityDetail(context, item),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppConstants.primaryColor,
                            foregroundColor: Colors.white,
                            elevation: 1,
                            shadowColor: Colors.black26,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 6,
                            ),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: const Text(
                              '了解詳情',
                              maxLines: 1,
                              style: TextStyle(
                                fontSize: _mobileDetailButtonFontSize,
                                fontWeight: FontWeight.w700,
                              ),
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
      );
    }

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: _contentBoxMaxHeightPx),
      child: Card(
        elevation: 2,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        clipBehavior: Clip.antiAlias,
        color: Colors.white,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            10,
            10,
            10,
            _activityCardButtonBottomClearancePx,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                item.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: _wideCardTitleFontSize,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF333333),
                  height: 1.0,
                ),
              ),
              Center(
                child: SizedBox(
                  width: _imageSizePx,
                  height: _imageSizePx,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: _activityHeroBackground(item),
                  ),
                ),
              ),
              Text(
                _activityCardPriceLine(item),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: _wideCardPriceFontSize,
                  color: AppConstants.primaryColor,
                  fontWeight: FontWeight.w600,
                  height: 1.0,
                ),
              ),
              SizedBox(
                width: double.infinity,
                height: _mobileDetailButtonHeightPx,
                child: OutlinedButton(
                  onPressed: () => _openActivityDetail(context, item),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppConstants.primaryColor,
                    side: const BorderSide(
                      color: AppConstants.primaryColor,
                      width: 2,
                    ),
                    padding: const EdgeInsets.symmetric(
                      vertical: 8,
                      horizontal: 22,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: const Text(
                      '了解詳情',
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: _wideDetailButtonFontSize,
                        fontWeight: FontWeight.w700,
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
  }

  Widget _buildPaginationBar(int totalPages) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      color: _activityPageBackground,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (_currentPageIndex > 0)
            TextButton(
              onPressed: () => setState(() => _currentPageIndex--),
              child: const Text('上一頁'),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              '第 ${_currentPageIndex + 1} / $totalPages 頁',
              style: TextStyle(
                fontSize: 14,
                color: AppConstants.grey,
              ),
            ),
          ),
          if (_currentPageIndex < totalPages - 1)
            TextButton(
              onPressed: () => setState(() => _currentPageIndex++),
              child: const Text('下一頁'),
            ),
        ],
      ),
    );
  }
}
