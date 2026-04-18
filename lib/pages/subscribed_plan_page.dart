import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../utils/constants.dart';
import '../providers/language_provider.dart';
import '../providers/subscription_provider.dart';
import '../services/firebase_bootstrap.dart';
import '../services/subscription_order_service.dart';
import 'subscription_page.dart';
import 'upgrade_matching_page.dart';

/// 訂閱的配對計劃頁
/// 與 Firestore [subscription_orders]／帳戶 [users.fastDatingPlan] 同步；「升級配對」開啟完整表單（與訂閱頁相同）
class SubscribedPlanPage extends StatefulWidget {
  const SubscribedPlanPage({super.key});

  @override
  State<SubscribedPlanPage> createState() => _SubscribedPlanPageState();
}

class _SubscribedPlanPageState extends State<SubscribedPlanPage> {
  static String _formatDate(DateTime d) {
    return '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
  }

  Future<void> _deleteUnpaidRecord(
    BuildContext context,
    LanguageProvider langProvider,
    SubscriptionRecord record,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(langProvider.getString('btn_delete')),
        content: Text(
          langProvider.getString('purchase_delete_unpaid_receipt_confirm'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(langProvider.getString('cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red[700]),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(langProvider.getString('btn_delete')),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;

    final success = FirebaseBootstrap.isReady
        ? await SubscriptionOrderService.deleteMyOrderIfOwner(record.id)
        : false;
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? langProvider.getString('purchase_activity_receipt_deleted')
              : langProvider
                  .getString('purchase_activity_receipt_delete_failed'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final langProvider = Provider.of<LanguageProvider>(context);
    final subscriptionProvider = Provider.of<SubscriptionProvider>(context);

    final theme = Theme.of(context);
    final titleFs = AppConstants.appBarTitleResolvedSize(context, base: 20);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => context.go('/home'),
        ),
        automaticallyImplyLeading: false,
        title: Text(langProvider.getString('subscribed_plan')),
        titleTextStyle: theme.appBarTheme.titleTextStyle?.copyWith(
              fontSize: titleFs,
            ) ??
            theme.textTheme.titleLarge?.copyWith(fontSize: titleFs),
        backgroundColor: AppConstants.appBarBackground,
        toolbarHeight: AppConstants.appBarToolbarHeight,
        elevation: 0,
      ),
      backgroundColor: AppConstants.backgroundColor,
      body: subscriptionProvider.subscriptionPlanRecords.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      langProvider.getString('no_subscription_records'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const SubscriptionPage(),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppConstants.primaryColor,
                        foregroundColor: Colors.white,
                      ),
                      child: Text(langProvider.getString('subscription_plan')),
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                Text(
                  langProvider.getString('subscribed_plan_content'),
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 12),
                ...subscriptionProvider.subscriptionPlanRecords.map((r) {
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(16),
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
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.card_membership,
                                color: AppConstants.primaryColor, size: 24),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                r.isAccountTierHint
                                    ? r.planName
                                    : '${r.planName} · ${r.months}${langProvider.getString('months')}',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            if (!r.isAccountTierHint)
                              Padding(
                                padding: const EdgeInsets.only(left: 8),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: (r.isPaid
                                                ? Colors.green
                                                : Colors.orange)
                                            .withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: r.isPaid
                                              ? Colors.green.shade300
                                              : Colors.orange.shade300,
                                        ),
                                      ),
                                      child: Text(
                                        '${langProvider.getString('payment_status')}：${langProvider.getString(r.isPaid ? 'payment_status_paid' : 'payment_status_unpaid')}',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: r.isPaid
                                              ? Colors.green.shade800
                                              : Colors.orange.shade800,
                                        ),
                                      ),
                                    ),
                                    if (!r.isPaid) ...[
                                      const SizedBox(height: 8),
                                      TextButton(
                                        style: TextButton.styleFrom(
                                          backgroundColor:
                                              const Color(0xFFFFC0CB),
                                          foregroundColor: Colors.black87,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 8,
                                          ),
                                          minimumSize: Size.zero,
                                          tapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                        ),
                                        onPressed: () => _deleteUnpaidRecord(
                                          context,
                                          langProvider,
                                          r,
                                        ),
                                        child: Text(
                                          langProvider.getString('btn_delete'),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            if (r.isAccountTierHint)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                  border:
                                      Border.all(color: Colors.blue.shade200),
                                ),
                                child: Text(
                                  langProvider
                                      .getString('subscribed_plan_tier_badge'),
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.blue.shade800,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        if (r.isAccountTierHint) ...[
                          const SizedBox(height: 8),
                          Text(
                            langProvider
                                .getString('subscribed_plan_tier_sync_hint'),
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade700,
                              height: 1.35,
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        _row(
                          langProvider.getString('subscription_fee'),
                          r.totalPrice == '—' ? '—' : 'HKD\$${r.totalPrice}',
                        ),
                        _row(
                          langProvider.getString('subscription_date'),
                          _formatDate(r.purchaseDate),
                        ),
                        _row(
                          langProvider.getString('expiration_date'),
                          _formatDate(r.expirationDate),
                        ),
                        if (!r.isAccountTierHint) ...[
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () {
                                subscriptionProvider.setAutoRenewal(
                                  r.id,
                                  !r.autoRenewal,
                                );
                              },
                              icon: Icon(
                                r.autoRenewal
                                    ? Icons.check_circle
                                    : Icons.circle_outlined,
                                size: 20,
                                color: r.autoRenewal
                                    ? Colors.green
                                    : AppConstants.primaryColor,
                              ),
                              label: Text(
                                langProvider.getString('enable_auto_renewal'),
                                style: TextStyle(
                                  color: r.autoRenewal
                                      ? Colors.green
                                      : AppConstants.primaryColor,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(
                                  color: r.autoRenewal
                                      ? Colors.green
                                      : AppConstants.primaryColor,
                                ),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                }),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(16),
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
                      Text(
                        langProvider.getString('upgrade_matching_action'),
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        langProvider
                            .getString('subscribed_plan_upgrade_section_body'),
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade800,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: () {
                          Navigator.push<void>(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) => const UpgradeMatchingPage(),
                            ),
                          );
                        },
                        icon: const Icon(Icons.edit_note_rounded,
                            color: Colors.white),
                        label: Text(
                          langProvider.getString('upgrade_matching_action'),
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppConstants.primaryColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
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
