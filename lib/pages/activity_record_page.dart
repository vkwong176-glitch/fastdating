import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../utils/constants.dart';
import '../providers/language_provider.dart';
import '../providers/activity_provider.dart';
import '../providers/subscription_provider.dart';
import '../services/subscription_order_service.dart';

/// 參加活動記錄頁
/// 同步 Firestore [subscription_orders] 中已付款之活動報名（與購買記錄／後台活動訂單一致），
/// 並合併本機已標記為已付款之活動紀錄（若有）。
class ActivityRecordPage extends StatelessWidget {
  const ActivityRecordPage({super.key});

  static String _formatDateTime(DateTime d) {
    return '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

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

  static String _paymentMethodLabel(LanguageProvider lang, String? code) {
    if (code == null || code.isEmpty) {
      return lang.getString('payment_method_unknown');
    }
    switch (code) {
      case 'stripe':
        return lang.getString('payment_method_stripe');
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
        if (code.startsWith('iap_')) {
          return lang.getString('payment_method_iap_ios');
        }
        return code;
    }
  }

  @override
  Widget build(BuildContext context) {
    final langProvider = Provider.of<LanguageProvider>(context);
    final subscriptionProvider = Provider.of<SubscriptionProvider>(context);
    final activityProvider = Provider.of<ActivityProvider>(context);

    final fromOrders = subscriptionProvider.records
        .where(
          (r) =>
              !r.isAccountTierHint &&
              r.purchaseKind ==
                  SubscriptionOrderService.purchaseKindActivityRegistration &&
              r.isPaid,
        )
        .toList();

    final fromLocal = activityProvider.records.where((r) => r.isPaid).toList();

    final merged = <({DateTime at, Widget card})>[];
    for (final r in fromOrders) {
      merged.add((
        at: r.purchaseDate,
        card: Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: _buildReceiptCard(
            langProvider,
            content: r.planName,
            amount: _formatHkdAmount(r.totalPrice),
            dateTime: r.purchaseDate,
            participants: int.tryParse(r.months.trim()),
            paymentMethodLabel: _paymentMethodLabel(
              langProvider,
              r.paymentMethod,
            ),
          ),
        ),
      ));
    }
    for (final r in fromLocal) {
      merged.add((
        at: r.paidAt,
        card: Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: _buildReceiptCard(
            langProvider,
            content: r.content,
            amount: _formatHkdAmount(r.price),
            dateTime: r.paidAt,
            participants: r.participants,
            paymentMethodLabel: _paymentMethodLabel(
              langProvider,
              r.paymentMethod,
            ),
          ),
        ),
      ));
    }
    merged.sort((a, b) => b.at.compareTo(a.at));

    final hasAny = merged.isNotEmpty;

    final theme = Theme.of(context);
    final titleFs = AppConstants.appBarTitleResolvedSize(context, base: 20);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => context.go('/home'),
        ),
        automaticallyImplyLeading: false,
        title: Text(langProvider.getString('activity_history')),
        titleTextStyle: theme.appBarTheme.titleTextStyle?.copyWith(
              fontSize: titleFs,
            ) ??
            theme.textTheme.titleLarge?.copyWith(fontSize: titleFs),
        backgroundColor: AppConstants.appBarBackground,
        toolbarHeight: AppConstants.appBarToolbarHeight,
        elevation: 0,
      ),
      backgroundColor: AppConstants.backgroundColor,
      body: !hasAny
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  langProvider.getString('no_activity_records'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey[600],
                  ),
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: merged.map((e) => e.card).toList(),
            ),
    );
  }

  Widget _buildReceiptCard(
    LanguageProvider langProvider, {
    required String content,
    required String amount,
    required DateTime dateTime,
    int? participants,
    required String paymentMethodLabel,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppConstants.white,
        borderRadius: BorderRadius.circular(12),
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
                Icon(Icons.event, color: AppConstants.primaryColor, size: 24),
                const SizedBox(width: 8),
                Text(
                  langProvider.getString('receipt_title'),
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
                    langProvider.getString('activity_content'), content),
                if (participants != null)
                  _receiptRow(
                    langProvider.getString('activity_reg_headcount'),
                    '$participants',
                  ),
                _receiptRow(langProvider.getString('payment_amount'), amount),
                _receiptRow(
                  langProvider.getString('payment_method'),
                  paymentMethodLabel,
                ),
                _receiptRow(
                  langProvider.getString('payment_date'),
                  _formatDateTime(dateTime),
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
            width: 80,
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
