import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../utils/constants.dart';
import 'firebase_bootstrap.dart';
import 'firestore_paths.dart';

/// 管理員變更密碼後寫入 [FirestorePaths.adminNotifyOutbox]，供 **Firebase Extension「Trigger Email」**
/// 或自訂 Cloud Function 寄信至 [AppConstants.adminPasswordChangeNotifyEmail]。
///
/// 若未部署擴充／函式，文件仍會寫入 Firestore 作紀錄，但不會實際寄出電郵。
abstract final class AdminPasswordNotifyService {
  static Future<void> enqueuePasswordChangeEmail({
    required String loginHint,
  }) async {
    if (!FirebaseBootstrap.isReady) return;
    if (FirebaseAuth.instance.currentUser == null) return;

    final to = AppConstants.adminPasswordChangeNotifyEmail.trim();
    if (to.isEmpty) return;

    try {
      await FirebaseFirestore.instance
          .collection(FirestorePaths.adminNotifyOutbox)
          .add({
        'to': to,
        'message': {
          'subject': 'Fast Dating：管理員密碼已更新',
          'text': _body(loginHint),
        },
        'template': 'admin_password_changed',
        'loginHint': loginHint,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e, st) {
      debugPrint('AdminPasswordNotifyService: $e\n$st');
    }
  }

  static String _body(String loginHint) {
    final b = StringBuffer()
      ..writeln('Fast Dating 管理員帳號設定中的「密碼」已變更。')
      ..writeln()
      ..writeln('帳號欄位：$loginHint')
      ..writeln()
      ..writeln('本通知不含新密碼。若非本人操作，請立即檢查 Firebase Authentication 與專案安全。');
    return b.toString();
  }
}
