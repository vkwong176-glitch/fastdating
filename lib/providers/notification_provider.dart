import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 一則待顯示的訊息通知
class MessageNotificationItem {
  final String title;
  final String body;
  final String? senderId;

  MessageNotificationItem({
    required this.title,
    required this.body,
    this.senderId,
  });
}

/// APP 內通知相關狀態與待顯示通知（推播音效由系統處理；新訊息列表偵測時 Android 播系統預設通知鈴聲）
class NotificationProvider with ChangeNotifier {
  static const _kHeartNotification = 'notif_heart';
  static const _kMessageSound = 'notif_message_sound';

  bool _heartNotification = true;
  bool _messageSoundEnabled = true;

  bool _prefsLoaded = false;

  bool get heartNotification => _heartNotification;

  /// 訊息列表偵測到對方新訊息時是否播放提示（預設開；Android 為系統預設通知鈴聲）。
  bool get messageSoundEnabled => _messageSoundEnabled;

  Future<void> loadFromPrefs() async {
    if (_prefsLoaded) return;
    try {
      final p = await SharedPreferences.getInstance();
      _heartNotification = p.getBool(_kHeartNotification) ?? true;
      _messageSoundEnabled = p.getBool(_kMessageSound) ?? true;
      _prefsLoaded = true;
      notifyListeners();
    } catch (_) {
      _prefsLoaded = true;
    }
  }

  Future<void> _persist() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_kHeartNotification, _heartNotification);
      await p.setBool(_kMessageSound, _messageSoundEnabled);
    } catch (_) {}
  }

  set heartNotification(bool v) {
    _heartNotification = v;
    notifyListeners();
    _persist();
  }

  set messageSoundEnabled(bool v) {
    _messageSoundEnabled = v;
    notifyListeners();
    _persist();
  }

  final List<MessageNotificationItem> _pending = [];

  /// 加入一則訊息通知（例如新訊息時呼叫）
  void addMessageNotification(String title, String body, {String? senderId}) {
    _pending.add(MessageNotificationItem(
      title: title,
      body: body,
      senderId: senderId,
    ));
    notifyListeners();
  }

  /// 所有訊息嘅通知內容同步彈出屏幕一次，顯示後清空待顯示列表
  void showAllPendingOnce(BuildContext context) {
    if (_pending.isEmpty) return;
    final list = List<MessageNotificationItem>.from(_pending);
    _pending.clear();
    notifyListeners();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(ctx).size.height * 0.5,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Text(
                    '通知',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('關閉'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: list.length,
                itemBuilder: (_, i) {
                  final item = list[i];
                  return ListTile(
                    title: Text(item.title),
                    subtitle: Text(item.body),
                    isThreeLine: item.body.length > 30,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool get hasPending => _pending.isNotEmpty;
}
