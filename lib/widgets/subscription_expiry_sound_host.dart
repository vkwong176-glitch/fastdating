import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/notification_provider.dart';
import '../providers/subscription_provider.dart';
import '../services/in_app_notification_sound.dart';

/// 訂閱將於 7 日內到期時播放一次提示音（依 App 內音效／震動）。
class SubscriptionExpirySoundHost extends StatefulWidget {
  const SubscriptionExpirySoundHost({super.key});

  @override
  State<SubscriptionExpirySoundHost> createState() =>
      _SubscriptionExpirySoundHostState();
}

class _SubscriptionExpirySoundHostState
    extends State<SubscriptionExpirySoundHost> {
  final Set<String> _playedOrderIds = {};

  void _checkExpiringSoon(SubscriptionProvider sub, NotificationProvider notif) {
    for (final r in sub.subscriptionPlanRecords) {
      if (!r.isPaid || r.isAccountTierHint) continue;
      final days = r.expirationDate.difference(DateTime.now()).inDays;
      if (days < 0 || days > 7) continue;
      if (_playedOrderIds.contains(r.id)) continue;
      _playedOrderIds.add(r.id);
      InAppNotificationSound.instance.playForAppNotification(
        inAppSound: notif.inAppSound,
        inAppVibration: notif.inAppVibration,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    context.watch<SubscriptionProvider>();
    final sub = context.read<SubscriptionProvider>();
    final notif = context.read<NotificationProvider>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _checkExpiringSoon(sub, notif);
    });
    return const SizedBox.shrink();
  }
}
