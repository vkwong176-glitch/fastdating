import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/upgrade_matching_profile.dart';
import '../utils/image_upload_compress.dart';
import '../utils/upgrade_matching_tier.dart';
import 'firebase_bootstrap.dart';
import 'firestore_paths.dart';

/// 升級配對個人資料 ↔ Firestore [FirestorePaths.upgradeMatchingPool]（與管理後台「升級配對資料庫」同一集合）
class UpgradeMatchingService {
  UpgradeMatchingService._();
  static final UpgradeMatchingService instance = UpgradeMatchingService._();

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  /// 讀取目前使用者的升級配對文件（含 `profile`）
  Future<Map<String, dynamic>?> fetchMyUpgradeDoc() async {
    if (!FirebaseBootstrap.isReady) return null;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    try {
      final doc =
          await _db.collection(FirestorePaths.upgradeMatchingPool).doc(user.uid).get();
      if (!doc.exists) return null;
      return doc.data();
    } catch (e, st) {
      debugPrint('fetchMyUpgradeDoc: $e\n$st');
      return null;
    }
  }

  Future<UpgradeMatchingProfileData?> fetchMyProfile() async {
    final doc = await fetchMyUpgradeDoc();
    if (doc == null) return null;
    return UpgradeMatchingProfileData.fromFirestoreDoc(doc);
  }

  /// 寫入／更新升級配對資料（合併），供 App「提交」與「訂閱頁儲存」共用。
  Future<void> saveProfile(UpgradeMatchingProfileData data) async {
    if (!FirebaseBootstrap.isReady) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final uid = user.uid;
    final name = data.displayName;
    try {
      final ref = _db.collection(FirestorePaths.upgradeMatchingPool).doc(uid);
      final snap = await ref.get();
      final incomeText = data.text['occupationIncome'] ?? '';
      UpgradeMatchingProfileData toSave = data;
      if (data.personalPhotoBytes != null &&
          data.personalPhotoBytes!.isNotEmpty) {
        final c = compressForFirestoreImageField(data.personalPhotoBytes!);
        toSave = UpgradeMatchingProfileData(
          text: data.text,
          gender: data.gender,
          hasProperty: data.hasProperty,
          marriedBefore: data.marriedBefore,
          wantMarriageSoon: data.wantMarriageSoon,
          wantChildren: data.wantChildren,
          urgentMarriage: data.urgentMarriage,
          hasDriverLicense: data.hasDriverLicense,
          personalPhotoBytes: c,
        );
      }
      final patch = <String, dynamic>{
        'userId': uid,
        'displayName': name,
        'source': 'app_upgrade_form',
        'notes': 'upgrade_form',
        'fastDatingPlan': UpgradeMatchingTierHelper.planFromIncomeText(incomeText),
        'profile': toSave.toProfileFirestoreMap(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      final em = user.email?.trim();
      if (em != null && em.isNotEmpty) {
        patch['accountEmail'] = em;
      }
      if (!snap.exists) {
        patch['addedAt'] = FieldValue.serverTimestamp();
      }
      await ref.set(patch, SetOptions(merge: true));
    } catch (e, st) {
      debugPrint('saveProfile upgrade_matching_pool: $e\n$st');
      rethrow;
    }
  }
}
