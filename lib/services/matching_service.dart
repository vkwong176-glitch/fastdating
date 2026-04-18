import 'package:cloud_firestore/cloud_firestore.dart';

import 'firebase_bootstrap.dart';
import 'firestore_paths.dart';

/// 自動配對：請以 Cloud Function 定時任務或 Firestore Trigger 實作演算法，
/// 此處僅提供「寫入配對紀錄」的客戶端輔助。
///
/// 建議後端流程：依興趣／年齡／訂閱層級計算分數 → 寫入 [FirestorePaths.matches]。
class MatchingService {
  MatchingService._();
  static final MatchingService instance = MatchingService._();

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  /// 範例：寫入一筆配對（實際應由後端驗證雙方意願）。
  Future<void> recordMatch({
    required String userIdA,
    required String userIdB,
    String source = 'auto',
  }) async {
    if (!FirebaseBootstrap.isReady) return;
    final pair = [userIdA, userIdB]..sort();
    final id = '${pair[0]}__${pair[1]}';
    await _db.collection(FirestorePaths.matches).doc(id).set({
      'userIds': [userIdA, userIdB],
      'source': source,
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
