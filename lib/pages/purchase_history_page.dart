import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../utils/constants.dart';
import '../providers/activity_provider.dart';
import '../providers/ad_payment_provider.dart';
import '../providers/language_provider.dart';
import '../providers/subscription_provider.dart';
import '../services/firebase_bootstrap.dart';
import '../services/subscription_order_service.dart';
import '../services/chat_receipt_cookies.dart';

class _ReceiptItem {
  final String typeLabel;
  final String content;
  final String amount;
  final DateTime date;
  final IconData icon;
  final String paymentMethodLabel;
  final String paymentStatusLabel;
  final bool isPaid;

  /// Firestore [subscription_orders] 文件 ID（訂閱／廣告訂單／活動報名等；非帳戶層級提示）
  final String? subscriptionOrderDocId;

  /// 活動報名且來自本機 [ActivityProvider] 時可刪
  final String? localActivityRecordId;

  /// 廣告合作本機紀錄（與 Firestore 訂單不重複列印時）
  final String? localAdPaymentRecordId;

  _ReceiptItem({
    required this.typeLabel,
    required this.content,
    required this.amount,
    required this.date,
    required this.icon,
    required this.paymentMethodLabel,
    required this.paymentStatusLabel,
    required this.isPaid,
    this.subscriptionOrderDocId,
    this.localActivityRecordId,
    this.localAdPaymentRecordId,
  });

  bool get showDeleteUnpaidButton =>
      !isPaid &&
      ((subscriptionOrderDocId != null && subscriptionOrderDocId!.isNotEmpty) ||
          (localActivityRecordId != null &&
              localActivityRecordId!.isNotEmpty) ||
          (localAdPaymentRecordId != null &&
              localAdPaymentRecordId!.isNotEmpty));
}

/// 購買記錄頁：訂閱方案、廣告合作、活動報名等（內容、金額、日期時間、付款方式、付款狀態）
/// 進入時會刪除 [subscription_orders] 中逾一個月仍為未付款之本人訂單。
class PurchaseHistoryPage extends StatefulWidget {
  const PurchaseHistoryPage({super.key});

  @override
  State<PurchaseHistoryPage> createState() => _PurchaseHistoryPageState();
}

class _PurchaseHistoryPageState extends State<PurchaseHistoryPage> {
  static const Duration _unpaidReceiptTtl = Duration(days: 30);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _purgeStaleUnpaidReceipts());
  }

  Future<void> _purgeStaleUnpaidReceipts() async {
    await SubscriptionOrderService.purgeMyUnpaidOrdersOlderThanRepeated(
      _unpaidReceiptTtl,
    );
    if (!mounted) return;
    Provider.of<AdPaymentProvider>(context, listen: false)
        .purgeUnpaidOlderThan(_unpaidReceiptTtl);
    if (!mounted) return;
    Provider.of<ActivityProvider>(context, listen: false)
        .purgeUnpaidOlderThan(_unpaidReceiptTtl);
  }

  static String _formatDate(DateTime d) {
    return '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  /// 避免 `HKD$` 與已含前綴的金額重複；合併誤重複的 `HKD$HKD$`。
  static String _formatHkdAmount(String raw) {
    var t = raw.trim();
    while (t.contains('HKD\$HKD\$')) {
      t = t.replaceFirst('HKD\$HKD\$', 'HKD\$');
    }
    if (t.isEmpty) return 'HKD\$—';
    if (t.startsWith('HKD\$')) return t;
    if (t.startsWith(r'$')) return 'HKD$t';
    return 'HKD\$$t';
  }

  static bool _sameCalendarDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static bool _adOverlapsSubscription(
    AdPaymentRecord ad,
    List<SubscriptionRecord> subs,
  ) {
    for (final s in subs) {
      if (s.isAccountTierHint) continue;
      if (s.purchaseKind != SubscriptionOrderService.purchaseKindAdCoop) {
        continue;
      }
      if (!_sameCalendarDay(s.purchaseDate, ad.purchaseDate)) continue;
      if (s.totalPrice.trim() != ad.totalPrice.trim()) continue;
      return true;
    }
    return false;
  }

  static String _paymentStatusLabel(LanguageProvider lang, bool isPaid) {
    return isPaid
        ? lang.getString('payment_status_paid')
        : lang.getString('payment_status_unpaid');
  }

  static String _paymentMethodLabel(
    LanguageProvider lang,
    String? code, {
    required bool localOnly,
  }) {
    if (localOnly) {
      return lang.getString('payment_method_local_only');
    }
    if (code == null || code.isEmpty) {
      return lang.getString('payment_method_unknown');
    }
    switch (code) {
      case 'stripe':
      case 'pending_stripe':
        return lang.getString('payment_method_legacy_removed');
      case 'manual_fps_wechat_bank':
        return lang.getString('payment_method_manual_transfer');
      case 'iap_app_store':
        return lang.getString('payment_method_iap_app_store');
      case 'iap_google_play':
        return lang.getString('payment_method_iap_google_play');
      case 'iap_other':
        return lang.getString('payment_method_iap_other');
      case 'iap_unavailable':
      case 'iap_unavailable_web':
        return lang.getString('payment_method_iap_demo');
      default:
        return code;
    }
  }

  List<_ReceiptItem> _buildReceipts({
    required LanguageProvider lang,
    required List<SubscriptionRecord> subscriptionRecords,
    required List<AdPaymentRecord> adRecords,
    required List<ActivityRecord> activityRecords,
  }) {
    final monthsSuffix = lang.getString('months');
    final out = <_ReceiptItem>[];
    final unpaidCutoff = DateTime.now().subtract(_unpaidReceiptTtl);

    for (final r in subscriptionRecords) {
      if (r.isAccountTierHint) continue;
      if (!r.isPaid && r.purchaseDate.isBefore(unpaidCutoff)) continue;

      final kind = r.purchaseKind;
      late final String typeLabel;
      late final IconData icon;
      if (kind == SubscriptionOrderService.purchaseKindAdCoop) {
        typeLabel = lang.getString('payment_type_ad_coop');
        icon = Icons.campaign;
      } else if (kind ==
          SubscriptionOrderService.purchaseKindActivityRegistration) {
        typeLabel = lang.getString('payment_type_activity');
        icon = Icons.event_available;
      } else {
        typeLabel = lang.getString('payment_type_subscription');
        icon = Icons.card_membership;
      }

      final itemLine =
          kind == SubscriptionOrderService.purchaseKindActivityRegistration
              ? r.planName
              : '${r.planName} · ${r.months}$monthsSuffix';

      out.add(
        _ReceiptItem(
          typeLabel: typeLabel,
          content: itemLine,
          amount: _formatHkdAmount(r.totalPrice),
          date: r.purchaseDate,
          icon: icon,
          paymentMethodLabel: _paymentMethodLabel(
            lang,
            r.paymentMethod,
            localOnly: false,
          ),
          paymentStatusLabel: _paymentStatusLabel(lang, r.isPaid),
          isPaid: r.isPaid,
          subscriptionOrderDocId: r.isAccountTierHint ? null : r.id,
          localActivityRecordId: null,
          localAdPaymentRecordId: null,
        ),
      );
    }

    for (final r in adRecords) {
      if (!r.isPaid && r.purchaseDate.isBefore(unpaidCutoff)) continue;
      if (_adOverlapsSubscription(r, subscriptionRecords)) continue;
      out.add(
        _ReceiptItem(
          typeLabel: lang.getString('payment_type_ad_coop'),
          content: '${r.planName} · ${r.months}$monthsSuffix',
          amount: _formatHkdAmount(r.totalPrice),
          date: r.purchaseDate,
          icon: Icons.campaign_outlined,
          paymentMethodLabel: _paymentMethodLabel(lang, null, localOnly: true),
          paymentStatusLabel: _paymentStatusLabel(lang, r.isPaid),
          isPaid: r.isPaid,
          subscriptionOrderDocId: null,
          localActivityRecordId: null,
          localAdPaymentRecordId: !r.isPaid ? r.id : null,
        ),
      );
    }

    for (final r in activityRecords) {
      if (!r.isPaid && r.paidAt.isBefore(unpaidCutoff)) continue;
      out.add(
        _ReceiptItem(
          typeLabel: lang.getString('payment_type_activity'),
          content: r.content,
          amount: _formatHkdAmount(r.price),
          date: r.paidAt,
          icon: Icons.event,
          paymentMethodLabel: _paymentMethodLabel(
            lang,
            r.paymentMethod,
            localOnly: r.paymentMethod == null || r.paymentMethod!.isEmpty,
          ),
          paymentStatusLabel: _paymentStatusLabel(lang, r.isPaid),
          isPaid: r.isPaid,
          subscriptionOrderDocId: null,
          localActivityRecordId: r.id,
          localAdPaymentRecordId: null,
        ),
      );
    }

    out.sort((a, b) => b.date.compareTo(a.date));
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final langProvider = Provider.of<LanguageProvider>(context);
    final subscriptionProvider = Provider.of<SubscriptionProvider>(context);
    final adPaymentProvider = Provider.of<AdPaymentProvider>(context);
    final activityProvider = Provider.of<ActivityProvider>(context);

    final subscriptionRecords = subscriptionProvider.records;
    final adRecords = adPaymentProvider.records;
    final activityRecords = activityProvider.records;

    final allReceipts = _buildReceipts(
      lang: langProvider,
      subscriptionRecords: subscriptionRecords,
      adRecords: adRecords,
      activityRecords: activityRecords,
    );

    final hasRecords = allReceipts.isNotEmpty;

    final theme = Theme.of(context);
    final titleFs = AppConstants.appBarTitleResolvedSize(context, base: 20);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => context.go('/home'),
        ),
        automaticallyImplyLeading: false,
        title: Text(langProvider.getString('purchase_history')),
        titleTextStyle: theme.appBarTheme.titleTextStyle?.copyWith(
              fontSize: titleFs,
            ) ??
            theme.textTheme.titleLarge?.copyWith(fontSize: titleFs),
        backgroundColor: AppConstants.appBarBackground,
        toolbarHeight: AppConstants.appBarToolbarHeight,
        elevation: 0,
      ),
      backgroundColor: AppConstants.backgroundColor,
      body: !hasRecords
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  langProvider.getString('no_purchase_records'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey[600],
                  ),
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: allReceipts.length,
              itemBuilder: (_, i) {
                final r = allReceipts[i];
                if (kIsWeb && i == 0) {
                  final oid = r.subscriptionOrderDocId?.trim();
                  if (oid != null && oid.isNotEmpty) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      ChatReceiptCookies.setLastReceiptOrderId(oid);
                    });
                  }
                }
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: _PurchaseReceiptCard(
                    lang: langProvider,
                    item: r,
                  ),
                );
              },
            ),
    );
  }
}

class _PurchaseReceiptCard extends StatelessWidget {
  const _PurchaseReceiptCard({
    required this.lang,
    required this.item,
  });

  final LanguageProvider lang;
  final _ReceiptItem item;

  static const Color _deletePinkBg = Color(0xFFFFC0CB);

  Future<void> _onDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(lang.getString('btn_delete')),
        content: Text(lang.getString('purchase_delete_unpaid_receipt_confirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(lang.getString('cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red[700]),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(lang.getString('btn_delete')),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;

    var success = true;
    final docId = item.subscriptionOrderDocId?.trim();
    if (docId != null && docId.isNotEmpty) {
      if (FirebaseBootstrap.isReady) {
        success = await SubscriptionOrderService.deleteMyOrderIfOwner(docId);
      } else {
        success = false;
      }
    } else if (item.localActivityRecordId != null) {
      Provider.of<ActivityProvider>(context, listen: false)
          .removeRecord(item.localActivityRecordId!);
    } else if (item.localAdPaymentRecordId != null) {
      Provider.of<AdPaymentProvider>(context, listen: false)
          .removeRecord(item.localAdPaymentRecordId!);
    } else {
      success = false;
    }

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? lang.getString('purchase_activity_receipt_deleted')
              : lang.getString('purchase_activity_receipt_delete_failed'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                Icon(item.icon, color: AppConstants.primaryColor, size: 24),
                const SizedBox(width: 8),
                Text(
                  lang.getString('receipt_title'),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _receiptRow(
                    lang.getString('payment_receipt_content'), item.content),
                _receiptRow(lang.getString('payment_amount'), item.amount),
                _receiptRow(
                  lang.getString('payment_date'),
                  _PurchaseHistoryPageState._formatDate(item.date),
                ),
                _receiptRow(
                    lang.getString('payment_method'), item.paymentMethodLabel),
                _receiptRow(
                    lang.getString('payment_status'), item.paymentStatusLabel),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppConstants.primaryColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          item.typeLabel,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppConstants.primaryColor,
                          ),
                        ),
                      ),
                      if (item.showDeleteUnpaidButton) ...[
                        const SizedBox(width: 8),
                        TextButton(
                          style: TextButton.styleFrom(
                            backgroundColor: _deletePinkBg,
                            foregroundColor: Colors.black87,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          onPressed: () => _onDelete(context),
                          child: Text(lang.getString('btn_delete')),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _receiptRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
