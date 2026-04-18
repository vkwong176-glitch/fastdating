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
import '../seo/seo_h1_banner.dart';
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
  });
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
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// 固定 6 筆虛擬活動（與後台真實活動合併顯示；其餘舊 mock 已移除）。
  List<_ActivityItem> _buildMockActivities() {
    const titles = [
      '單身男女手工藝工作坊',
      '近期有客問以下~異性搭伙生活配對',
      '全年無限次配對計劃',
      '周末咖啡約會',
      '行山郊遊活動',
      '電影分享會',
    ];
    const prices = [
      '\$380/堂 每週3堂\$1100',
      '配對費\$1000 全年無限次',
      '全年無限次配對\$1000',
      '\$150/位',
      '\$200/位',
      '\$180/位',
    ];
    return List.generate(titles.length, (i) {
      final id = 'act_$i';
      return _ActivityItem(
        id: id,
        title: titles[i],
        imageUrl: '',
        price: prices[i],
      );
    });
  }

  /// 後台真實活動置前，再接固定虛擬活動；同 [id] 只保留先出現的一筆（真實優先）。
  List<_ActivityItem> _mergeRealWithVirtual(List<_ActivityItem> real) {
    final virtual = _buildMockActivities();
    final seen = <String>{};
    final out = <_ActivityItem>[];
    for (final r in real) {
      if (seen.add(r.id)) out.add(r);
    }
    for (final v in virtual) {
      if (seen.add(v.id)) out.add(v);
    }
    return out;
  }

  List<_ActivityItem> _filteredActivities(List<_ActivityItem> all) {
    if (_keyword.isEmpty) return all;
    final k = _keyword.toLowerCase();
    return all
        .where(
          (a) =>
              a.title.toLowerCase().contains(k) ||
              a.price.toLowerCase().contains(k) ||
              (a.subtitle?.toLowerCase().contains(k) ?? false) ||
              (a.paymentMethodLabel?.toLowerCase().contains(k) ?? false) ||
              (a.activityDetail?.toLowerCase().contains(k) ?? false),
        )
        .toList();
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
            ratio = _mobileGridAspectRatio;
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
                cellWidth: cellWidth,
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
        body: _buildActivityListBody(
          allActivities: _buildMockActivities(),
          seoPath: widget.seoPath,
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
        final realActivities = docs
            .map((d) => _itemFromFirestoreDoc(d, lang))
            .whereType<_ActivityItem>()
            .toList();
        final allActivities = _mergeRealWithVirtual(realActivities);

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

  /// 8cm ≈ 302px；1cm ≈ 38px；手機活動框：寬 4cm、高 4.5cm
  static const double _imageSizePx = 302;
  static const double _contentBoxMaxHeightPx = 492;
  static const double _edgePadding1cmPx = 38;
  static const double _imageTopGap1cmPx = 38;
  static const double _cardGapPx = 8;
  static const double _detailBottomGap1cmPx = 38;
  static const double _cmLogicalPx = 38.0;
  static const double _halfCmLogicalPx = 0.5 * _cmLogicalPx;
  static const double _activitySpacingHalfCmPx = _halfCmLogicalPx;
  static const double _mobileBoxWidthCm = 4;
  static const double _mobileBoxHeightCm = 4.5;
  static const double _mobileBoxWidthPx = _mobileBoxWidthCm * _cmLogicalPx;
  static const double _mobileBoxHeightPx = _mobileBoxHeightCm * _cmLogicalPx;

  /// Grid `childAspectRatio` = 寬／高（寬 4cm、高 4.5cm）
  static const double _mobileGridAspectRatio =
      _mobileBoxWidthPx / _mobileBoxHeightPx;

  /// 手機活動字體：基礎約 10；「增大 1cm」以 1cm≈38 邏輯像素取 38/3 加於標題（其餘按比例），格內 FittedBox 防溢出
  static const double _mobileFontBump1Cm = 38 / 3;
  static const double _mobileTitleFontSize = 10 + _mobileFontBump1Cm;
  static const double _mobilePriceFontSize = 10 + _mobileFontBump1Cm * 0.78;

  /// 「了解詳情」字體：加大以避免手機卡片內文字過細。
  static const double _mobileDetailButtonFontSize =
      10 + _mobileFontBump1Cm * 0.72;

  /// 按鈕高度放大 40%，令「了解詳情」文字更清楚。
  static const double _mobileDetailButtonHeightPx = 36 * 1.4;

  /// 「了解詳情」按鈕加闊 40%（若超出卡片可用寬度則取上限）。
  static const double _detailButtonWidthMultiplier = 1.4;

  /// 寬螢幕「了解詳情」字體同步加大。
  static const double _wideDetailButtonFontSize = 18 * 1.2;

  /// 標題衍生漸層＋可選後台上傳圖（載入失敗時仍顯示漸層）。
  Widget _activityHeroBackground(_ActivityItem item) {
    final url = item.imageUrl.trim();
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
    final img = item.imageUrl.trim();
    final poster = item.registrationPosterUrl?.trim();
    showActivityDetailRegistrationSheet(
      context,
      activityId: item.id,
      title: item.title,
      unitPriceDisplay: item.price,
      activityDetail: item.activityDetail,
      bodyText: item.bodyText ?? item.subtitle,
      activityImageUrl: img.isNotEmpty ? img : null,
      registrationPosterUrl:
          poster != null && poster.isNotEmpty ? poster : null,
      maxParticipants: item.maxParticipants,
    );
  }

  Widget _buildActivityCard(
    BuildContext context,
    _ActivityItem item, {
    required bool compact,
    double? cellWidth,
  }) {
    if (compact) {
      final cw = cellWidth ?? _mobileBoxWidthPx;
      final w = math.min(cw, _mobileBoxWidthPx);
      final h = w * (_mobileBoxHeightPx / _mobileBoxWidthPx);
      return Center(
        child: Material(
          elevation: 2,
          borderRadius: BorderRadius.circular(10),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: w,
            height: h,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _activityHeroBackground(item),
                Positioned.fill(
                  child: Container(
                    color: Colors.black.withOpacity(0.28),
                  ),
                ),
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      6,
                      _halfCmLogicalPx,
                      6,
                      _halfCmLogicalPx,
                    ),
                    child: Column(
                      children: [
                        Expanded(
                          child: Align(
                            alignment: Alignment.topCenter,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.topCenter,
                              child: ConstrainedBox(
                                constraints: BoxConstraints(maxWidth: w - 12),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Text(
                                      item.title,
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: _mobileTitleFontSize,
                                        fontWeight: FontWeight.w600,
                                        height: 1.2,
                                        shadows: [
                                          Shadow(
                                            color: Colors.black54,
                                            blurRadius: 4,
                                            offset: Offset(0, 1),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      item.price,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontSize: _mobilePriceFontSize,
                                        color: AppConstants.primaryColor,
                                        fontWeight: FontWeight.w600,
                                        shadows: [
                                          Shadow(
                                            color: Colors.black45,
                                            blurRadius: 3,
                                            offset: Offset(0, 1),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: math.min(
                            w - 12,
                            math.max(100.0, w * 0.88) *
                                _detailButtonWidthMultiplier,
                          ),
                          height: _mobileDetailButtonHeightPx,
                          child: ElevatedButton(
                            onPressed: () => _openActivityDetail(context, item),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppConstants.primaryColor,
                              foregroundColor: Colors.white,
                              elevation: 2,
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
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: _contentBoxMaxHeightPx),
      child: Card(
        elevation: 2,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: _imageTopGap1cmPx),
            SizedBox(
              height: _imageSizePx,
              width: double.infinity,
              child: Center(
                child: SizedBox(
                  width: _imageSizePx,
                  height: _imageSizePx,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: _activityHeroBackground(item),
                  ),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(10, 0, 10, _detailBottomGap1cmPx),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(height: _cardGapPx),
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: _cardGapPx),
                  Text(
                    _activityCardPriceLine(item),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 16,
                      color: AppConstants.primaryColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: _cardGapPx),
                  SizedBox(
                    width: double.infinity,
                    height: _mobileDetailButtonHeightPx,
                    child: FractionallySizedBox(
                      widthFactor: 1.0,
                      child: OutlinedButton(
                        onPressed: () => _openActivityDetail(context, item),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppConstants.primaryColor,
                          side: const BorderSide(
                              color: AppConstants.primaryColor, width: 2),
                          padding: const EdgeInsets.symmetric(
                              vertical: 8, horizontal: 22),
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
                  ),
                ],
              ),
            ),
          ],
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
