import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugPrint, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../providers/ad_payment_provider.dart';
import '../providers/ad_post_provider.dart';
import '../providers/language_provider.dart';
import '../services/firebase_bootstrap.dart';
import '../services/firestore_paths.dart';
import '../services/store_iap_service.dart';
import '../services/store_product_ids.dart';
import '../services/subscription_order_service.dart';
import '../services/payment_settings_service.dart';
import '../services/user_firestore_service.dart';
import '../utils/constants.dart';
import '../utils/launch_url_helper.dart';
import '../widgets/manual_payment_checkout_sheet.dart';
import '../widgets/storage_network_image.dart';
import '../seo/seo_h1_banner.dart';

/// 廣告合作頁
/// 貼文要求：30字內可加圖或link；右方瀏覽量眼睛圖標＋瀏覽數量；可點擊填寫廣告貼文
class AdPartnerPage extends StatefulWidget {
  const AdPartnerPage({super.key, this.seoPublicPath});

  /// 非 null 時為公開 SEO 路徑（例如 `/advertising`），顯示主標。
  final String? seoPublicPath;

  @override
  State<AdPartnerPage> createState() => _AdPartnerPageState();
}

class _AdPartnerPageState extends State<AdPartnerPage> {
  int _viewCount = 0;

  static const List<Map<String, String>> _plans = [
    {'months': '12', 'total': '5300', 'perMonth': '441'},
    {'months': '6', 'total': '2700', 'perMonth': '450'},
    {'months': '3', 'total': '1400', 'perMonth': '466'},
    {'months': '1', 'total': '500', 'perMonth': ''},
  ];
  int _selectedPlanIndex = 2;
  bool _adIapBusy = false;

  static const Duration _unpaidAdOrderTtl = Duration(days: 30);

  @override
  void initState() {
    super.initState();
    StoreIapService.instance.ensureListener();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _purgeStaleUnpaidAdOrders());
  }

  Future<void> _purgeStaleUnpaidAdOrders() async {
    await SubscriptionOrderService.purgeMyUnpaidOrdersOlderThanRepeated(
      _unpaidAdOrderTtl,
    );
  }

  Future<void> _dismissAdCoopContentNotify() async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null || u.isAnonymous || !FirebaseBootstrap.isReady) return;
    try {
      await FirebaseFirestore.instance
          .collection(FirestorePaths.users)
          .doc(u.uid)
          .update({'adCoopContentNotify': FieldValue.delete()});
    } catch (e, st) {
      debugPrint('dismissAdCoopContentNotify: $e\n$st');
    }
  }

  Future<void> _dismissAdCoopBillingNotify() async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null || u.isAnonymous || !FirebaseBootstrap.isReady) return;
    try {
      await FirebaseFirestore.instance
          .collection(FirestorePaths.users)
          .doc(u.uid)
          .update({'adCoopBillingNotify': FieldValue.delete()});
    } catch (e, st) {
      debugPrint('dismissAdCoopBillingNotify: $e\n$st');
    }
  }

  double _bodyFontExtra(BuildContext context) {
    return MediaQuery.sizeOf(context).width >= AppConstants.layoutWideBreakpoint
        ? AppConstants.adPartnerPageDesktopBodyFontExtra
        : 0.0;
  }

  /// 寫入 [subscription_orders.adFeePlanSnapshot]，與後台／會員「歷史對照」一致。
  String _adFeePlanSnapshotLine(
    LanguageProvider lang,
    String months,
    String total,
  ) {
    return '${lang.getString('ad_fee_plan_title')} · $months${lang.getString('months')} · HKD\$$total';
  }

  Future<void> _finalizeAdCoopMirrorAfterSubmit({
    required String title,
    required String text,
    required String link,
    Uint8List? imageBytes,
    String existingImageUrl = '',
    bool removeImage = false,
    BuildContext? feedbackContext,
    LanguageProvider? langFeedback,

    /// 為 true 時表示訂單路徑已成功寫入鏡像，略過「僅貼文」上傳與 [adCoopStandalonePending]。
    bool skipStandaloneMirror = false,
  }) async {
    if (!FirebaseBootstrap.isReady) return;
    if (skipStandaloneMirror) {
      return;
    }
    var imgUrl = existingImageUrl.trim();
    if (!removeImage && imageBytes != null && imageBytes.isNotEmpty) {
      imgUrl = (await SubscriptionOrderService.uploadStandaloneAdCoopPostImage(
            imageBytes,
          )) ??
          '';
      // 上傳失敗時保留伺服器既有圖片 URL，避免覆寫成無圖而遺失資料。
      if (imgUrl.isEmpty) {
        final u = FirebaseAuth.instance.currentUser;
        if (u != null) {
          try {
            final snap = await FirebaseFirestore.instance
                .collection(FirestorePaths.users)
                .doc(u.uid)
                .get();
            final sub = snap.data()?['adCoopLatestSubmission'];
            if (sub is Map) {
              imgUrl = (sub['imageUrl'] ?? '').toString().trim();
            }
          } catch (e, st) {
            debugPrint('preserve ad image url: $e\n$st');
          }
        }
        if (imgUrl.isEmpty &&
            feedbackContext != null &&
            feedbackContext.mounted &&
            langFeedback != null) {
          ScaffoldMessenger.of(feedbackContext).showSnackBar(
            SnackBar(
              content:
                  Text(langFeedback.getString('event_proposal_image_failed')),
            ),
          );
        }
      }
    }
    await UserFirestoreService.instance.syncAdCoopLatestSubmissionMirror(
      title: title,
      text: text,
      link: link,
      imageUrl: imgUrl,
      linkedOrderId: null,
      standalonePending: true,
      removeImage: removeImage,
    );
  }

  /// 寫入會員廣告貼文待審資料；與廣告訂單流程分開處理。
  Future<void> _syncAdCoopPostToCloud({
    required BuildContext pageContext,
    required LanguageProvider langProvider,
    required String title,
    required String text,
    required String link,
    Uint8List? imageBytes,
    String existingImageUrl = '',
    bool removeImage = false,
  }) async {
    if (!FirebaseBootstrap.isReady) {
      if (pageContext.mounted) {
        ScaffoldMessenger.of(pageContext).showSnackBar(
          SnackBar(
            content: Text(langProvider.getString('ad_coop_firebase_not_ready')),
          ),
        );
      }
      return;
    }
    if (FirebaseAuth.instance.currentUser == null) {
      if (pageContext.mounted) {
        ScaffoldMessenger.of(pageContext).showSnackBar(
          SnackBar(
            content:
                Text(langProvider.getString('ad_coop_login_required_sync')),
          ),
        );
      }
      return;
    }

    try {
      final linkedOrderId =
          await SubscriptionOrderService.latestAdCoopOrderDocIdForCurrentUser();
      if (linkedOrderId != null && linkedOrderId.isNotEmpty) {
        final linkedOk = await SubscriptionOrderService.updateAdCoopPostContent(
          orderDocId: linkedOrderId,
          title: title,
          text: text,
          link: link,
          imageBytes: imageBytes,
          removeImage: removeImage,
        );
        if (linkedOk) {
          String mirrorImageUrl = '';
          try {
            final orderSnap = await FirebaseFirestore.instance
                .collection(FirestorePaths.subscriptionOrders)
                .doc(linkedOrderId)
                .get();
            final orderData = orderSnap.data();
            mirrorImageUrl = ((orderData?['adPostImageUrl'] ??
                        orderData?['adPostImageURL']) ??
                    '')
                .toString()
                .trim();
          } catch (e, st) {
            debugPrint('AdPartnerPage read linked ad order: $e\n$st');
          }
          await UserFirestoreService.instance.syncAdCoopLatestSubmissionMirror(
            title: title,
            text: text,
            link: link,
            imageUrl: mirrorImageUrl,
            linkedOrderId: linkedOrderId,
            standalonePending: false,
            removeImage: removeImage,
          );
          return;
        }
      }
    } catch (e, st) {
      debugPrint('AdPartnerPage sync linked order fallback: $e\n$st');
    }

    if (!pageContext.mounted) return;
    await _finalizeAdCoopMirrorAfterSubmit(
      title: title,
      text: text,
      link: link,
      imageBytes: imageBytes,
      existingImageUrl: existingImageUrl,
      removeImage: removeImage,
      feedbackContext: pageContext,
      langFeedback: langProvider,
      skipStandaloneMirror: false,
    );
  }

  /// 提交廣告貼文後以 [AlertDialog] 彈出提示（Web／手機皆清楚可見），再關閉 bottom sheet。
  Future<void> _showAdPostSubmitApprovalDialog(
    LanguageProvider lang,
    BuildContext pageContext,
  ) async {
    if (!pageContext.mounted) return;
    final msg = lang.getString('ad_post_submit_snackbar');
    await showDialog<void>(
      context: pageContext,
      useRootNavigator: true,
      barrierDismissible: true,
      builder: (dCtx) => AlertDialog(
        content: Text(
          msg,
          textAlign: TextAlign.center,
          style: const TextStyle(height: 1.45, fontSize: 16),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dCtx).pop(),
            child: Text(MaterialLocalizations.of(dCtx).okButtonLabel),
          ),
        ],
      ),
    );
  }

  Future<void> _showAdPostSubmittingDialog(
    LanguageProvider lang,
    BuildContext pageContext,
    Future<void> Function(ValueNotifier<String> message) action,
  ) async {
    if (!pageContext.mounted) return;
    final message = ValueNotifier<String>('正在提交廣告內容...');
    Timer? slowTimer;
    slowTimer = Timer(const Duration(seconds: 3), () {
      message.value = '仍在提交廣告內容，請稍候...';
    });
    showDialog<void>(
      context: pageContext,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (dialogCtx) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: ValueListenableBuilder<String>(
                  valueListenable: message,
                  builder: (_, value, __) => Text(
                    value,
                    style: const TextStyle(height: 1.4, fontSize: 15),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    try {
      await action(message);
    } finally {
      slowTimer.cancel();
      message.dispose();
      if (pageContext.mounted) {
        Navigator.of(pageContext, rootNavigator: true).pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final langProvider = Provider.of<LanguageProvider>(context);
    final bf = _bodyFontExtra(context);

    final theme = Theme.of(context);
    final titleFs = AppConstants.appBarTitleResolvedSize(context, base: 20);
    return Scaffold(
      appBar: AppBar(
        title: Text(langProvider.getString('ad_coop')),
        titleTextStyle: theme.appBarTheme.titleTextStyle?.copyWith(
              fontSize: titleFs,
            ) ??
            theme.textTheme.titleLarge?.copyWith(fontSize: titleFs),
        backgroundColor: AppConstants.appBarBackground,
        toolbarHeight: AppConstants.appBarToolbarHeight,
        elevation: 0,
        leading: widget.seoPublicPath != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.black87),
                onPressed: () => context.go('/home'),
              )
            : null,
        automaticallyImplyLeading: widget.seoPublicPath == null,
      ),
      backgroundColor: AppConstants.backgroundColor,
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.seoPublicPath != null)
              SeoH1Banner(path: widget.seoPublicPath!),
            if (FirebaseBootstrap.isReady)
              Builder(
                builder: (context) {
                  final u = FirebaseAuth.instance.currentUser;
                  if (u == null || u.isAnonymous) {
                    return const SizedBox.shrink();
                  }
                  return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    stream: FirebaseFirestore.instance
                        .collection(FirestorePaths.users)
                        .doc(u.uid)
                        .snapshots(),
                    builder: (context, snap) {
                      final data = snap.data?.data() ?? const <String, dynamic>{};
                      final contentRaw = data['adCoopContentNotify'];
                      final billingRaw = data['adCoopBillingNotify'];
                      if (contentRaw is! Map && billingRaw is! Map) {
                        return const SizedBox.shrink();
                      }

                      Widget buildNotice({
                        required Color bg,
                        required Color border,
                        required IconData icon,
                        required String title,
                        required String body,
                        required VoidCallback onDismiss,
                      }) {
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                          child: Material(
                            color: bg,
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: border.withValues(alpha: 0.45),
                                ),
                              ),
                              padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(icon, color: border, size: 22),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          title,
                                          style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 14 + bf * 0.1,
                                            color: Colors.black87,
                                          ),
                                        ),
                                        if (body.trim().isNotEmpty) ...[
                                          const SizedBox(height: 6),
                                          Text(
                                            body.trim(),
                                            style: TextStyle(
                                              fontSize: 13 + bf * 0.1,
                                              height: 1.35,
                                              color: Colors.black87,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.close),
                                    tooltip: langProvider.getString('ad_coop_notify_dismiss'),
                                    onPressed: onDismiss,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }

                      final notices = <Widget>[];
                      if (billingRaw is Map) {
                        final title = billingRaw['title']?.toString() ?? '';
                        final body = billingRaw['body']?.toString() ?? '';
                        notices.add(
                          buildNotice(
                            bg: Colors.orange.shade50,
                            border: Colors.deepOrange.shade700,
                            icon: Icons.campaign_outlined,
                            title: title.isEmpty
                                ? langProvider.getString('ad_coop_billing_notify_title')
                                : title,
                            body: body,
                            onDismiss: _dismissAdCoopBillingNotify,
                          ),
                        );
                      }
                      if (contentRaw is Map) {
                        final kind = contentRaw['kind']?.toString() ?? '';
                        final msg = contentRaw['message']?.toString() ?? '';
                        final isRevision = kind == 'needs_revision';
                        notices.add(
                          buildNotice(
                            bg: isRevision
                                ? Colors.amber.shade50
                                : Colors.green.shade50,
                            border: isRevision
                                ? Colors.amber.shade700
                                : Colors.green.shade700,
                            icon: isRevision
                                ? Icons.info_outline
                                : Icons.check_circle_outline,
                            title: isRevision
                                ? langProvider.getString('ad_coop_notify_revision')
                                : langProvider.getString('ad_coop_notify_approved'),
                            body: isRevision ? msg : '',
                            onDismiss: _dismissAdCoopContentNotify,
                          ),
                        );
                      }
                      return Column(children: notices);
                    },
                  );
                },
              ),
            // 廣告合作貼文要求：可點擊填寫；右方瀏覽眼＋瀏覽數量
            GestureDetector(
              onTap: () =>
                  _showAdPostForm(context, langProvider, editing: null),
              child: Container(
                margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: AppConstants.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: AppConstants.grey.withValues(alpha: 0.08),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        langProvider.getString('ad_post_requirement'),
                        style: TextStyle(
                          fontSize: 15 + bf,
                          fontWeight: FontWeight.w500,
                          color: const Color(0xFF333333),
                        ),
                      ),
                    ),
                    Icon(
                      Icons.visibility,
                      color: AppConstants.primaryColor,
                      size: 24 + bf * 0.35,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '$_viewCount',
                      style: TextStyle(
                        fontSize: 14 + bf,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[700],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            // 廣告貼文記錄：可點擊顯示過往貼文（圖、文字、link、日期時間、通過/不通過）
            GestureDetector(
              onTap: () => _showAdPostRecords(context, langProvider),
              child: Container(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: AppConstants.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: AppConstants.grey.withValues(alpha: 0.08),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        langProvider.getString('ad_post_record'),
                        style: TextStyle(
                          fontSize: 15 + bf,
                          fontWeight: FontWeight.w500,
                          color: const Color(0xFF333333),
                        ),
                      ),
                    ),
                    Icon(Icons.chevron_right,
                        color: AppConstants.grey, size: 24 + bf * 0.35),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                langProvider.getString('ad_need_admin_approval'),
                style: TextStyle(
                  fontSize: 12 + bf,
                  color: Colors.grey[600],
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(height: 24),
            // 心形＋對話氣泡圖標
            Center(
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFB6C1).withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(40),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(Icons.favorite,
                        color: AppConstants.primaryColor, size: 36 + bf * 0.35),
                    Positioned(
                      bottom: 12,
                      left: 14,
                      child: Icon(Icons.chat_bubble,
                          color: const Color(0xFFE57373), size: 18 + bf * 0.25),
                    ),
                    Positioned(
                      bottom: 12,
                      right: 14,
                      child: Icon(Icons.chat_bubble,
                          color: const Color(0xFF64B5F6), size: 18 + bf * 0.25),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              langProvider.getString('ad_fee_plan_title'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18 + bf,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF333333),
              ),
            ),
            const SizedBox(height: 20),
            // 選購訂閱項目
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F0F0),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    langProvider.getString('choose_subscription'),
                    style: TextStyle(
                      fontSize: 18 + bf,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...List.generate(_plans.length, (i) {
                    final plan = _plans[i];
                    final selected = _selectedPlanIndex == i;
                    return GestureDetector(
                      onTap: () => setState(() => _selectedPlanIndex = i),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: selected
                                ? AppConstants.primaryColor
                                : Colors.transparent,
                            width: selected ? 2.5 : 0,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '${plan['months']}${langProvider.getString('months')}',
                              style: TextStyle(
                                fontSize: 16 + bf,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Row(
                              children: [
                                Text(
                                  'HKD\$${plan['total']}',
                                  style: TextStyle(
                                    fontSize: 15 + bf,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if ((plan['perMonth'] ?? '').isNotEmpty) ...[
                                  const SizedBox(width: 8),
                                  Text(
                                    'HKD\$${plan['perMonth']}/月',
                                    style: TextStyle(
                                      fontSize: 13 + bf,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 12),
                  Text(
                    langProvider.getString('subscription_terms'),
                    style: TextStyle(
                      fontSize: 11 + bf,
                      color: Colors.grey[700],
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: bf > 0 ? 56 : 48,
                    child: ElevatedButton(
                      onPressed: _adIapBusy
                          ? null
                          : () => _openAdPaymentMethodChooser(langProvider),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppConstants.primaryColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                      ),
                      child: Text(
                        langProvider.getString('continue'),
                        style: TextStyle(
                            fontSize: 16 + bf, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  bool _requireLoggedInForPayment() {
    if (FirebaseAuth.instance.currentUser == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('請先登入以繼續付款')),
        );
      }
      return false;
    }
    return true;
  }

  String _adIapPaymentMethodCode() {
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return 'iap_app_store';
      case TargetPlatform.android:
        return 'iap_google_play';
      default:
        return 'iap_other';
    }
  }

  void _openAdPaymentMethodChooser(LanguageProvider lang) {
    if (!_requireLoggedInForPayment()) return;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: StreamBuilder<PaymentSettingsSnapshot>(
          stream: PaymentSettingsService.watchDefault(),
          builder: (context, snap) {
            final ps = snap.data ?? PaymentSettingsSnapshot.defaults;
            final tiles = <Widget>[];
            if (ps.enableIap && !kIsWeb) {
              tiles.add(
                ListTile(
                  leading: const Icon(Icons.smartphone),
                  title: const Text('App Store／Google Play'),
                  subtitle: const Text('依裝置使用 App Store 或 Google Play 付款'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _handleAdIapPurchase(lang);
                  },
                ),
              );
            }
            if (ps.enableManual) {
              tiles.add(
                ListTile(
                  leading: const Icon(Icons.account_balance_wallet_outlined),
                  title: const Text('FPS／WeChat／銀行戶口'),
                  subtitle: const Text('顯示轉帳資料，收據經 WhatsApp 傳送'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showAdManualTransfer(lang);
                  },
                ),
              );
            }
            if (tiles.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: Text('管理員已暫停所有付款方式，請稍後再試。'),
              );
            }
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ...tiles,
                const SizedBox(height: 8),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _showAdManualTransfer(LanguageProvider lang) async {
    final planName = lang.getString('ad_fee_plan_title');
    final selected = _plans[_selectedPlanIndex];
    final months = selected['months'] ?? '1';
    final total = selected['total'] ?? '';
    final waPrefill = '我想購買廣告合作方案：$planName  $months個月 HKD\$$total，現上傳付款收據～';
    await showManualPaymentCheckoutSheet(
      context,
      planName: planName,
      months: months,
      totalPrice: total,
      fastDatingPlan: null,
      purchaseKind: SubscriptionOrderService.purchaseKindAdCoop,
      successSnackBar: '已提交訂單，請於 WhatsApp 傳送收據；核實後處理廣告合作。',
      whatsappPrefillOverride: waPrefill,
      adFeePlanSnapshot: _adFeePlanSnapshotLine(lang, months, total),
    );
  }

  Future<void> _handleAdIapPurchase(LanguageProvider lang) async {
    final planName = lang.getString('ad_fee_plan_title');
    final selected = _plans[_selectedPlanIndex];
    final months = selected['months'] ?? '1';
    final productId = StoreProductIds.forAdPartnerPost(months);
    final adPay = Provider.of<AdPaymentProvider>(context, listen: false);

    if (!StoreIapService.instance.supportedOnThisPlatform ||
        !await StoreIapService.instance.isAvailable()) {
      if (!mounted) return;
      if (FirebaseBootstrap.isReady) {
        final u = FirebaseAuth.instance.currentUser;
        if (u != null) {
          await SubscriptionOrderService.recordOrder(
            planName: planName,
            months: months,
            totalPrice: selected['total'] ?? '',
            fastDatingPlan: null,
            paymentMethod: kIsWeb ? 'iap_unavailable_web' : 'iap_unavailable',
            purchaseKind: SubscriptionOrderService.purchaseKindAdCoop,
            status: 'demo_local',
          );
        } else {
          adPay.addRecord(
            planName: planName,
            months: months,
            totalPrice: selected['total'] ?? '',
          );
        }
      } else {
        adPay.addRecord(
          planName: planName,
          months: months,
          totalPrice: selected['total'] ?? '',
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('（示範）Web／非商店環境：僅寫入本機與訂單紀錄')),
      );
      return;
    }

    setState(() => _adIapBusy = true);
    try {
      final res = await StoreIapService.instance.queryProducts({productId});
      if (res.error != null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('無法查詢商品：${res.error}')),
        );
        return;
      }
      if (res.productDetails.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '未找到商店商品：$productId\n請在 App Store Connect／Play Console 建立同 ID 內購商品',
            ),
          ),
        );
        return;
      }
      final product = res.productDetails.first;
      final details = await StoreIapService.instance.buy(product);
      if (!mounted) return;
      await StoreIapService.instance.completePurchase(details);
      if (!mounted) return;
      await SubscriptionOrderService.recordOrder(
        planName: planName,
        months: months,
        totalPrice: product.price,
        fastDatingPlan: null,
        paymentMethod: _adIapPaymentMethodCode(),
        purchaseKind: SubscriptionOrderService.purchaseKindAdCoop,
        status: 'paid_iap',
        productId: productId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(lang.getString('payment_success_check_receipt')),
        ),
      );
    } on StorePurchaseCanceled {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已取消')),
        );
      }
    } catch (e, st) {
      debugPrint('Ad IAP error: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('購買失敗：$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _adIapBusy = false);
    }
  }

  /// 關閉 [showModalBottomSheet] 的廣告刊登表單。須傳入與 [showModalBottomSheet] 相同的 [context]。
  /// 若以表單內 [StatefulBuilder] 的 context 判斷 [Navigator.canPop] 再 pop，在 Web 上常誤判為不可 pop，導致無法關閉。
  void _popAdPostFormSheet(BuildContext openerContext) {
    if (!openerContext.mounted) return;
    Navigator.pop(openerContext);
  }

  void _showAdPostForm(
    BuildContext pageContext,
    LanguageProvider langProvider, {
    AdPostRecord? editing,
    String existingImageUrl = '',
  }) {
    final titleController = TextEditingController(text: editing?.title ?? '');
    final linkController = TextEditingController(text: editing?.link ?? '');
    final contentController = TextEditingController(text: editing?.text ?? '');
    XFile? pickedImage;
    var imageRemoved = false;

    showModalBottomSheet<void>(
      context: pageContext,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          final bf = _bodyFontExtra(context);
          Future<void> pickImage() async {
            final picker = ImagePicker();
            final xFile = await picker.pickImage(
              source: ImageSource.gallery,
              maxWidth: 1536,
              imageQuality: 75,
            );
            if (xFile != null) {
              setModalState(() {
                pickedImage = xFile;
                imageRemoved = false;
              });
            }
          }

          Widget imageArea() {
            if (pickedImage != null) {
              return FutureBuilder<Uint8List>(
                future: pickedImage!.readAsBytes(),
                builder: (context, snap) {
                  if (!snap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.memory(
                      snap.data!,
                      height: 120,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  );
                },
              );
            }
            if (!imageRemoved && editing?.imageBytes != null) {
              return ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(
                  editing!.imageBytes!,
                  height: 120,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              );
            }
            if (!imageRemoved && existingImageUrl.trim().isNotEmpty) {
              return ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: StorageNetworkImage(
                  url: existingImageUrl.trim(),
                  width: double.infinity,
                  height: 120,
                  fit: BoxFit.cover,
                ),
              );
            }
            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add_photo_alternate,
                    size: 40 + bf * 0.35, color: Colors.grey[600]),
                const SizedBox(height: 8),
                Text(
                  langProvider.getString('ad_post_image'),
                  style: TextStyle(color: Colors.grey[600], fontSize: 14 + bf),
                ),
              ],
            );
          }

          final hasImagePreview = pickedImage != null ||
              (!imageRemoved &&
                  (editing?.imageBytes != null ||
                      existingImageUrl.trim().isNotEmpty));

          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    editing == null
                        ? langProvider.getString('ad_post')
                        : langProvider.getString('ad_post_edit_title'),
                    style: TextStyle(
                      fontSize: 20 + bf,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 20),
                  GestureDetector(
                    onTap: pickImage,
                    child: Container(
                      height: 120,
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey[400]!),
                      ),
                      child: Center(child: imageArea()),
                    ),
                  ),
                  if (hasImagePreview) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () {
                          setModalState(() {
                            pickedImage = null;
                            imageRemoved = true;
                          });
                        },
                        child: Text(
                          langProvider.getString('ad_post_remove_image'),
                          style:
                              TextStyle(color: Colors.red, fontSize: 14 + bf),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  TextField(
                    controller: titleController,
                    style: TextStyle(fontSize: 14 + bf),
                    decoration: InputDecoration(
                      hintText: langProvider.getString('ad_post_title'),
                      hintStyle: TextStyle(fontSize: 14 + bf),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: linkController,
                    style: TextStyle(fontSize: 14 + bf),
                    decoration: InputDecoration(
                      hintText: langProvider.getString('ad_post_link'),
                      hintStyle: TextStyle(fontSize: 14 + bf),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: contentController,
                    maxLength: 30,
                    style: TextStyle(fontSize: 14 + bf),
                    decoration: InputDecoration(
                      hintText: langProvider.getString('ad_post_content'),
                      hintStyle: TextStyle(fontSize: 14 + bf),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      counterText: '',
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    height: bf > 0 ? 56 : 48,
                    child: ElevatedButton(
                      onPressed: () async {
                        final title = titleController.text.trim();
                        final text = contentController.text.trim();
                        final link = linkController.text.trim();
                        final ad =
                            Provider.of<AdPostProvider>(context, listen: false);
                        if (editing == null) {
                          if (!FirebaseBootstrap.isReady) {
                            if (pageContext.mounted) {
                              ScaffoldMessenger.of(pageContext).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    langProvider.getString(
                                        'ad_coop_firebase_not_ready'),
                                  ),
                                ),
                              );
                            }
                            return;
                          }
                          if (FirebaseAuth.instance.currentUser == null) {
                            if (pageContext.mounted) {
                              ScaffoldMessenger.of(pageContext).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    langProvider.getString(
                                        'ad_coop_login_required_sync'),
                                  ),
                                ),
                              );
                            }
                            return;
                          }
                          Uint8List? imageBytes;
                          try {
                            if (pickedImage != null) {
                              imageBytes = await pickedImage!.readAsBytes();
                            }
                          } catch (e, st) {
                            debugPrint('AdPartnerPage read image: $e\n$st');
                            if (pageContext.mounted) {
                              ScaffoldMessenger.of(pageContext).showSnackBar(
                                SnackBar(content: Text('無法讀取圖片：$e')),
                              );
                            }
                            return;
                          }
                          ad.addPost(
                            imagePath: pickedImage?.path,
                            imageBytes: imageBytes,
                            title: title,
                            text: text,
                            link: link,
                          );
                          if (!mounted || !pageContext.mounted) return;
                          await _showAdPostSubmitApprovalDialog(
                            langProvider,
                            pageContext,
                          );
                          if (!pageContext.mounted) return;
                          try {
                            await _showAdPostSubmittingDialog(
                              langProvider,
                              pageContext,
                              (_) => _syncAdCoopPostToCloud(
                                pageContext: pageContext,
                                langProvider: langProvider,
                                title: title,
                                text: text,
                                link: link,
                                imageBytes: imageBytes,
                                existingImageUrl: existingImageUrl,
                              ),
                            );
                          } catch (e, st) {
                            debugPrint(
                                'AdPartnerPage submit cloud sync: $e\n$st');
                          }
                          await Future<void>.delayed(
                            const Duration(milliseconds: 80),
                          );
                          if (!mounted || !pageContext.mounted) return;
                          _popAdPostFormSheet(pageContext);
                          if (!mounted) return;
                          setState(() => _viewCount++);
                          return;
                        }
                        Uint8List? newBytes;
                        String? newPath;
                        try {
                          if (pickedImage != null) {
                            newBytes = await pickedImage!.readAsBytes();
                            newPath = pickedImage!.path;
                          }
                        } catch (e, st) {
                          debugPrint('AdPartnerPage edit read image: $e\n$st');
                          if (pageContext.mounted) {
                            ScaffoldMessenger.of(pageContext).showSnackBar(
                              SnackBar(content: Text('無法讀取圖片：$e')),
                            );
                          }
                          return;
                        }
                        if (!FirebaseBootstrap.isReady) {
                          if (pageContext.mounted) {
                            ScaffoldMessenger.of(pageContext).showSnackBar(
                              SnackBar(
                                content: Text(
                                  langProvider
                                      .getString('ad_coop_firebase_not_ready'),
                                ),
                              ),
                            );
                          }
                          return;
                        }
                        if (FirebaseAuth.instance.currentUser == null) {
                          if (pageContext.mounted) {
                            ScaffoldMessenger.of(pageContext).showSnackBar(
                              SnackBar(
                                content: Text(
                                  langProvider
                                      .getString('ad_coop_login_required_sync'),
                                ),
                              ),
                            );
                          }
                          return;
                        }
                        ad.updatePost(
                          editing.id,
                          title: title,
                          text: text,
                          link: link,
                          newImageBytes: newBytes,
                          newImagePath: newPath,
                          removeImage: imageRemoved,
                        );
                        final Uint8List? syncImageBytes =
                            imageRemoved ? null : newBytes;
                        if (!mounted || !pageContext.mounted) return;
                        await _showAdPostSubmitApprovalDialog(
                          langProvider,
                          pageContext,
                        );
                        if (!pageContext.mounted) return;
                        try {
                          await _showAdPostSubmittingDialog(
                            langProvider,
                            pageContext,
                            (_) => _syncAdCoopPostToCloud(
                              pageContext: pageContext,
                              langProvider: langProvider,
                              title: title,
                              text: text,
                              link: link,
                              imageBytes: syncImageBytes,
                              existingImageUrl: existingImageUrl,
                              removeImage: imageRemoved,
                            ),
                          );
                        } catch (e, st) {
                          debugPrint('AdPartnerPage edit cloud sync: $e\n$st');
                        }
                        await Future<void>.delayed(
                          const Duration(milliseconds: 80),
                        );
                        if (!mounted || !pageContext.mounted) return;
                        _popAdPostFormSheet(pageContext);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppConstants.primaryColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                      ),
                      child: Text(
                        langProvider.getString('submit'),
                        style: TextStyle(
                            fontSize: 16 + bf, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ).whenComplete(() {
      linkController.dispose();
      contentController.dispose();
    });
  }

  Future<void> _confirmDeleteAdPost(
    BuildContext context,
    LanguageProvider langProvider,
    String id,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) {
        final bf = _bodyFontExtra(dialogCtx);
        return AlertDialog(
          title: Text(
            langProvider.getString('btn_delete'),
            style: TextStyle(fontSize: 20 + bf, fontWeight: FontWeight.w600),
          ),
          content: Text(
            langProvider.getString('ad_post_delete_confirm'),
            style: TextStyle(fontSize: 16 + bf),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx, false),
              child: Text(
                langProvider.getString('cancel'),
                style: TextStyle(fontSize: 16 + bf),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: Text(
                langProvider.getString('btn_delete'),
                style: TextStyle(fontSize: 16 + bf),
              ),
            ),
          ],
        );
      },
    );
    if (ok == true && context.mounted) {
      Provider.of<AdPostProvider>(context, listen: false).deletePost(id);
    }
  }

  Future<void> _confirmDeleteCloudAdHistory(
    BuildContext pageContext,
    LanguageProvider langProvider,
    Map<String, dynamic> entry,
  ) async {
    final ok = await showDialog<bool>(
      context: pageContext,
      builder: (dialogCtx) {
        final bf = _bodyFontExtra(dialogCtx);
        return AlertDialog(
          title: Text(
            langProvider.getString('btn_delete'),
            style: TextStyle(fontSize: 20 + bf, fontWeight: FontWeight.w600),
          ),
          content: Text(
            langProvider.getString('ad_post_delete_confirm'),
            style: TextStyle(fontSize: 16 + bf),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx, false),
              child: Text(
                langProvider.getString('cancel'),
                style: TextStyle(fontSize: 16 + bf),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: Text(
                langProvider.getString('btn_delete'),
                style: TextStyle(fontSize: 16 + bf),
              ),
            ),
          ],
        );
      },
    );
    if (ok != true || !pageContext.mounted) return;
    if (!FirebaseBootstrap.isReady) {
      ScaffoldMessenger.of(pageContext).showSnackBar(
        SnackBar(
          content: Text(
              langProvider.getString('ad_coop_unpaid_order_delete_failed')),
        ),
      );
      return;
    }
    final success =
        await UserFirestoreService.instance.removeAdCoopSubmissionHistoryEntry(
      Map<String, dynamic>.from(entry),
    );
    if (!pageContext.mounted) return;
    ScaffoldMessenger.of(pageContext).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? langProvider.getString('ad_coop_history_deleted')
              : langProvider.getString('ad_coop_unpaid_order_delete_failed'),
        ),
      ),
    );
  }

  DateTime? _tsToDateTime(dynamic v) {
    if (v is Timestamp) return v.toDate();
    return null;
  }

  List<Map<String, dynamic>> _parseAdCoopSubmissionHistoryList(dynamic raw) {
    if (raw is! List) return const [];
    final out = <Map<String, dynamic>>[];
    for (final e in raw) {
      if (e is Map) out.add(Map<String, dynamic>.from(e));
    }
    return out;
  }

  bool _localPostOverlapsCloudHistory(
    AdPostRecord r,
    List<Map<String, dynamic>> cloud,
  ) {
    final t = r.text.trim();
    final l = r.link.trim();
    for (final m in cloud) {
      if ((m['text'] ?? '').toString().trim() == t &&
          (m['link'] ?? '').toString().trim() == l) {
        return true;
      }
    }
    return false;
  }

  void _showAdPostRecords(
      BuildContext pageContext, LanguageProvider langProvider) {
    final maxH = MediaQuery.of(pageContext).size.height * 0.72;
    final u = FirebaseAuth.instance.currentUser;
    final useCloud = FirebaseBootstrap.isReady && u != null && !u.isAnonymous;

    showModalBottomSheet(
      context: pageContext,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final bf = _bodyFontExtra(sheetContext);

        Widget sheetBody(List<Map<String, dynamic>> cloudHistory) {
          return Consumer<AdPostProvider>(
            builder: (_, adPostProvider, __) {
              final contentMerged = <({DateTime at, Widget child})>[];

              for (final m in cloudHistory) {
                final at = _tsToDateTime(m['submittedAt']) ??
                    DateTime.fromMillisecondsSinceEpoch(0);
                contentMerged.add((
                  at: at,
                  child: _buildCloudAdHistoryCard(
                    pageContext,
                    sheetContext,
                    langProvider,
                    bf,
                    m,
                  ),
                ));
              }

              for (final r in adPostProvider.records) {
                if (cloudHistory.isNotEmpty &&
                    _localPostOverlapsCloudHistory(r, cloudHistory)) {
                  continue;
                }
                contentMerged.add((
                  at: r.createdAt,
                  child: _buildAdPostDraftCard(
                    pageContext,
                    sheetContext,
                    langProvider,
                    bf,
                    r,
                  ),
                ));
              }

              contentMerged.sort((a, b) => b.at.compareTo(a.at));

              final listChildren = <Widget>[];

              if (contentMerged.isNotEmpty) {
                listChildren.add(
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        langProvider
                            .getString('ad_post_record_section_content'),
                        style: TextStyle(
                          fontSize: 13 + bf * 0.12,
                          fontWeight: FontWeight.w700,
                          color: Colors.grey[700],
                        ),
                      ),
                    ),
                  ),
                );
                for (final e in contentMerged) {
                  listChildren.add(e.child);
                }
              }

              final body = listChildren.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        langProvider.getString('no_ad_posts'),
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 14 + bf,
                        ),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
                      children: listChildren,
                    );

              return Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
                ),
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: maxH),
                    child: Material(
                      color: Colors.white,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(20),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(20),
                            child: Text(
                              langProvider.getString('ad_post_record'),
                              style: TextStyle(
                                fontSize: 20 + bf,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          Flexible(child: body),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        }

        if (!useCloud) {
          return sheetBody(const []);
        }

        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection(FirestorePaths.users)
              .doc(u.uid)
              .snapshots(),
          builder: (context, snap) {
            final cloud = _parseAdCoopSubmissionHistoryList(
              snap.data?.data()?['adCoopSubmissionHistory'],
            );
            return sheetBody(cloud);
          },
        );
      },
    );
  }

  Widget _buildCloudAdHistoryCard(
    BuildContext pageContext,
    BuildContext sheetContext,
    LanguageProvider lang,
    double bf,
    Map<String, dynamic> m,
  ) {
    final title = (m['title'] ?? '').toString().trim();
    final text = (m['text'] ?? '').toString();
    final link = (m['link'] ?? '').toString();
    final imageUrl = (m['imageUrl'] ?? '').toString().trim();
    final at = _tsToDateTime(m['submittedAt']);
    final timeStr = at != null
        ? '${at.year}/${at.month}/${at.day} '
            '${at.hour.toString().padLeft(2, '0')}:'
            '${at.minute.toString().padLeft(2, '0')}'
        : '—';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  lang.getString('ad_post_record_cloud'),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12 + bf * 0.12,
                    color: Colors.blue.shade900,
                  ),
                ),
              ),
              Text(
                timeStr,
                style:
                    TextStyle(fontSize: 12 + bf * 0.1, color: Colors.grey[700]),
              ),
            ],
          ),
          if (imageUrl.isNotEmpty) ...[
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () => _showAdImageUrlPreview(pageContext, imageUrl),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: StorageNetworkImage(
                  url: imageUrl,
                  width: double.infinity,
                  height: 120,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ],
          if (title.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              title,
              style: TextStyle(
                fontSize: 15 + bf,
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
          ],
          if (text.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(text, style: TextStyle(fontSize: 14 + bf)),
          ] else if (imageUrl.isEmpty) ...[
            const SizedBox(height: 4),
            Text('——',
                style: TextStyle(
                    fontSize: 14 + bf, color: const Color(0xFF999999))),
          ],
          if (link.isNotEmpty) ...[
            const SizedBox(height: 6),
            GestureDetector(
              onTap: () => openLink(link),
              child: Text(
                link,
                style: TextStyle(
                  fontSize: 12 + bf,
                  color: Colors.blue[700],
                  decoration: TextDecoration.underline,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
          const Divider(height: 20, thickness: 1),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _confirmDeleteCloudAdHistory(
                    pageContext,
                    lang,
                    m,
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  icon: Icon(Icons.delete_outline, size: 22 + bf * 0.35),
                  label: Text(
                    lang.getString('btn_delete'),
                    style: TextStyle(
                      fontSize: 15 + bf,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!pageContext.mounted) return;
                      _showAdPostForm(
                        pageContext,
                        lang,
                        editing: AdPostRecord(
                          id: (m['id'] ?? m['submittedAt'] ?? DateTime.now())
                              .toString(),
                          title: title,
                          text: text,
                          link: link,
                          createdAt: at ?? DateTime.now(),
                          status: AdPostStatus.pending,
                        ),
                        existingImageUrl: imageUrl,
                      );
                    });
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.blue,
                    side: const BorderSide(color: Colors.blue),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  icon: Icon(Icons.edit_outlined, size: 22 + bf * 0.35),
                  label: Text(
                    lang.getString('btn_edit'),
                    style: TextStyle(
                      fontSize: 15 + bf,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showAdImageUrlPreview(BuildContext context, String url) {
    if (url.trim().isEmpty) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(24),
        child: GestureDetector(
          onTap: () => Navigator.pop(ctx),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width - 48,
              maxHeight: MediaQuery.of(context).size.height - 48,
            ),
            child: InteractiveViewer(
              child: StorageNetworkImage(
                url: url,
                width: MediaQuery.of(context).size.width - 48,
                height: MediaQuery.of(context).size.height * 0.55,
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAdPostDraftCard(
    BuildContext pageContext,
    BuildContext sheetContext,
    LanguageProvider langProvider,
    double bf,
    AdPostRecord r,
  ) {
    return Builder(
      builder: (context) {
        final statusText = r.status == AdPostStatus.approved
            ? langProvider.getString('approved')
            : r.status == AdPostStatus.rejected
                ? langProvider.getString('not_approved')
                : langProvider.getString('pending_review');
        final statusColor = r.status == AdPostStatus.approved
            ? Colors.green
            : r.status == AdPostStatus.rejected
                ? Colors.red
                : Colors.orange;

        final canEdit = r.status == AdPostStatus.pending;
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey[300]!),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    onTap: () {
                      if (r.imageBytes != null) {
                        _showImagePreview(context, r);
                      }
                    },
                    child: (r.imageBytes != null)
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.memory(
                              r.imageBytes!,
                              width: 60,
                              height: 60,
                              fit: BoxFit.cover,
                            ),
                          )
                        : Container(
                            width: 60,
                            height: 60,
                            decoration: BoxDecoration(
                              color: Colors.grey[200],
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(Icons.image_not_supported,
                                color: Colors.grey[500]),
                          ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (r.title.isNotEmpty)
                          Text(
                            r.title,
                            style: TextStyle(
                              fontSize: 15 + bf,
                              fontWeight: FontWeight.w700,
                              height: 1.35,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        if (r.title.isNotEmpty) const SizedBox(height: 6),
                        if (r.text.isNotEmpty)
                          Text(
                            r.text,
                            style: TextStyle(fontSize: 14 + bf),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          )
                        else
                          Text(
                            '——',
                            style: TextStyle(
                              fontSize: 14 + bf,
                              color: const Color(0xFF999999),
                            ),
                          ),
                        if (r.link.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          GestureDetector(
                            onTap: () => openLink(r.link),
                            child: Text(
                              r.link,
                              style: TextStyle(
                                fontSize: 12 + bf,
                                color: Colors.blue[700],
                                decoration: TextDecoration.underline,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                        const SizedBox(height: 6),
                        Text(
                          '${r.createdAt.year}/${r.createdAt.month}/${r.createdAt.day} '
                          '${r.createdAt.hour.toString().padLeft(2, '0')}:${r.createdAt.minute.toString().padLeft(2, '0')}',
                          style: TextStyle(
                            fontSize: 12 + bf,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: statusColor),
                    ),
                    child: Text(
                      statusText,
                      style: TextStyle(
                        fontSize: 12 + bf,
                        fontWeight: FontWeight.w600,
                        color: statusColor,
                      ),
                    ),
                  ),
                ],
              ),
              const Divider(height: 20, thickness: 1),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _confirmDeleteAdPost(
                        context,
                        langProvider,
                        r.id,
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      icon: Icon(Icons.delete_outline, size: 22 + bf * 0.35),
                      label: Text(
                        langProvider.getString('btn_delete'),
                        style: TextStyle(
                          fontSize: 15 + bf,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  if (canEdit) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(sheetContext);
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (pageContext.mounted) {
                              _showAdPostForm(
                                pageContext,
                                langProvider,
                                editing: r,
                              );
                            }
                          });
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.blue,
                          side: const BorderSide(color: Colors.blue),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        icon: Icon(Icons.edit_outlined, size: 22 + bf * 0.35),
                        label: Text(
                          langProvider.getString('btn_edit'),
                          style: TextStyle(
                            fontSize: 15 + bf,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  void _showImagePreview(BuildContext context, AdPostRecord r) {
    if (r.imageBytes == null) return;
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(24),
        child: GestureDetector(
          onTap: () => Navigator.pop(ctx),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width - 48,
              maxHeight: MediaQuery.of(context).size.height - 48,
            ),
            child: InteractiveViewer(
              child: Image.memory(r.imageBytes!, fit: BoxFit.contain),
            ),
          ),
        ),
      ),
    );
  }
}
