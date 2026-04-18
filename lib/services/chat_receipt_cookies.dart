import 'package:flutter/foundation.dart';

import '../utils/cookie_constants.dart';
import 'web_cookies.dart';

/// 聊天：僅 UID 與未讀數摘要（不含訊息本文）
class ChatReceiptCookies {
  ChatReceiptCookies._();

  static void setLastChatPeerUid(String uid) {
    if (!kIsWeb) return;
    if (uid.length > 128) return;
    WebCookies.write(
      CookieNames.lastChatPeerUid,
      uid,
      maxAgeSeconds: kPreferenceCookieMaxAgeDays * 24 * 60 * 60,
    );
  }

  /// [totalUnread]：列表上未讀則數加總（僅數字）
  static void setUnreadTotalHint(int totalUnread) {
    if (!kIsWeb) return;
    final v = totalUnread.clamp(0, 999999);
    WebCookies.write(
      CookieNames.unreadTotalHint,
      '$v',
      maxAgeSeconds: kPreferenceCookieMaxAgeDays * 24 * 60 * 60,
    );
  }

  static void setLastReceiptOrderId(String docId) {
    if (!kIsWeb) return;
    if (docId.length > 200) return;
    WebCookies.write(
      CookieNames.lastReceiptOrderId,
      docId,
      maxAgeSeconds: kPreferenceCookieMaxAgeDays * 24 * 60 * 60,
    );
  }
}
