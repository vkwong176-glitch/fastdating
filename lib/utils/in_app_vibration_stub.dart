import 'package:flutter/services.dart';

/// 原生：觸覺回饋（非 Web）。
Future<void> triggerInAppNotificationVibration() async {
  try {
    await HapticFeedback.lightImpact();
  } catch (_) {}
}
