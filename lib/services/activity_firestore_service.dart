import 'package:cloud_firestore/cloud_firestore.dart';

import 'firebase_bootstrap.dart';
import 'firestore_paths.dart';

/// 活動 CRUD：編輯／列表可綁定至活動頁 UI；進階權限請用 Firestore Rules。
class ActivityFirestoreService {
  ActivityFirestoreService._();
  static final ActivityFirestoreService instance = ActivityFirestoreService._();

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  /// 若改用 [orderBy] 請在 Firebase Console 建立對應索引。
  Stream<QuerySnapshot<Map<String, dynamic>>> watchActivities() {
    return _db.collection(FirestorePaths.activities).snapshots();
  }

  Future<void> upsertActivity({
    required String id,
    required Map<String, dynamic> data,
  }) async {
    if (!FirebaseBootstrap.isReady) {
      throw StateError('activity_firestore_bootstrap_not_ready');
    }
    await _db.collection(FirestorePaths.activities).doc(id).set({
      ...data,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// 與後台「活動內容編輯」[event_cms] 同 ID 同步，供活動頁列表顯示。
  /// [explicitPrice]／[paymentMethod] 為後台表單欄位；若未填 [explicitPrice] 則沿用舊版（內文第一行為價錢）。
  Future<void> syncFromEventCms({
    required String docId,
    required String title,
    required String body,
    required List<String> imageUrls,
    String explicitPrice = '',
    String paymentMethod = '',
    int maxParticipants = 10,
    String activityDetail = '',
    String registrationPosterUrl = '',
  }) async {
    if (!FirebaseBootstrap.isReady) {
      throw StateError('activity_firestore_bootstrap_not_ready');
    }
    final trimmedFirst =
        imageUrls.isNotEmpty ? imageUrls.first.trim() : '';
    final posterTrim = registrationPosterUrl.trim();
    // 列表主視覺：優先 imageUrls；若僅上傳報名海報（後台多為此欄）則沿用海報網址。
    final imageUrl = trimmedFirst.isNotEmpty ? trimmedFirst : posterTrim;
    final bodyTrim = body.trim();
    final priceTrim = explicitPrice.trim();

    String displayPrice;
    String? subtitle;
    if (priceTrim.isNotEmpty) {
      displayPrice = priceTrim;
      subtitle = bodyTrim.isNotEmpty ? bodyTrim : null;
    } else {
      final lines = body
          .split(RegExp(r'[\r\n]+'))
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      if (lines.isNotEmpty) {
        displayPrice = lines.first;
        if (lines.length > 1) {
          subtitle = lines.sublist(1).join(' ');
        }
      } else {
        displayPrice = '—';
      }
    }

    final pm = paymentMethod.trim();
    final cap = maxParticipants.clamp(1, 10);
    final detailTrim = activityDetail.trim();
    await upsertActivity(
      id: docId,
      data: {
        'title': title,
        'body': body,
        'imageUrl': imageUrl,
        'price': displayPrice,
        'maxParticipants': cap,
        if (pm.isNotEmpty) 'paymentMethod': pm,
        if (subtitle != null && subtitle.isNotEmpty) 'subtitle': subtitle,
        'activityDetail': detailTrim.isNotEmpty ? detailTrim : FieldValue.delete(),
        'eventCmsId': docId,
        if (posterTrim.isNotEmpty)
          'registrationPosterUrl': posterTrim
        else
          'registrationPosterUrl': FieldValue.delete(),
      },
    );
  }

  Future<void> deletePublishedActivity(String docId) async {
    if (!FirebaseBootstrap.isReady) return;
    await _db.collection(FirestorePaths.activities).doc(docId).delete();
  }
}
