// Web 推播專用：Firebase Console → 專案設定 → 雲端通訊（Cloud Messaging）→
// 「Web 推播憑證」→ 產生金鑰組，將「公開金鑰」以建置參數或下方後備帶入。
// 上線建議：flutter build web --dart-define=FCM_VAPID=以BP開頭的公鑰
// 勿把含私有金鑰的內容放進專案。

const String kFcmWebVapidKeyFromBuild = String.fromEnvironment(
  'FCM_VAPID',
  defaultValue: '',
);

/// 若建置參數未帶 [kFcmWebVapidKeyFromBuild] 時，可暫在本地填入同一串公開金鑰；公開倉庫請只留空。
const String kFcmWebVapidKeyLocalFallback = '';

String get fcmVapidKeyForWeb {
  final a = kFcmWebVapidKeyFromBuild.trim();
  if (a.isNotEmpty) return a;
  return kFcmWebVapidKeyLocalFallback.trim();
}
