import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';

import '../utils/interests_parse.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../utils/image_upload_compress.dart';
import 'firebase_bootstrap.dart';
import 'firestore_paths.dart';

/// 與 [UserFirestoreService.seedPublicProfileIfMissing] 寫入之預設句相同；後台清理占位資料時比對用。
const String kDiscoverDefaultSentence = '剛加入 Fast Dating，來打聲招呼吧～';

/// Firestore `users` 文件是否具備首頁配對展示所需：**稱呼**、**年齡**（18～120）、**職業**（非「未填寫」）、**一句話**（非空且非 [kDiscoverDefaultSentence]）。
bool isUserDocCompleteForHomeDiscover(Map<String, dynamic> data) {
  final displayName = (data['displayName'] as String?)?.trim() ?? '';
  if (displayName.isEmpty) return false;
  final rawAge = data['age'];
  final age = rawAge is int
      ? rawAge
      : (rawAge != null ? int.tryParse(rawAge.toString()) : null);
  if (age == null || age < 18 || age > 120) return false;
  final job = (data['job'] as String?)?.trim() ?? '';
  if (job.isEmpty || job == '未填寫') return false;
  final s = (data['sentence'] as String?)?.trim() ?? '';
  if (s.isEmpty || s == kDiscoverDefaultSentence) return false;
  return true;
}

/// 首頁卡片形 [Map]（`name`／`age`／`job`／`sentence`）是否視為配對資料完整（與 [isUserDocCompleteForHomeDiscover] 對齊）。
bool isDiscoverCardCompleteForMatching(Map<String, dynamic> u) {
  final name = (u['name'] ?? '').toString().trim();
  if (name.isEmpty) return false;
  final rawAge = u['age'];
  final age = rawAge is int
      ? rawAge
      : (rawAge != null ? int.tryParse(rawAge.toString()) : null);
  if (age == null || age < 18 || age > 120) return false;
  final job = (u['job'] ?? '').toString().trim();
  if (job.isEmpty || job == '未填寫') return false;
  final s = (u['sentence'] ?? '').toString().trim();
  if (s.isEmpty || s == kDiscoverDefaultSentence) return false;
  return true;
}

/// 首頁探索：由卡片 map 讀取 Fast Dating 方案層級 1～6（無則為 1）。
int discoverPeerPlanTier(Map<String, dynamic> u) {
  final p = u['fastDatingPlan'];
  if (p is int && p >= 1 && p <= 6) return p;
  if (p is num) {
    final n = p.round();
    if (n >= 1 && n <= 6) return n;
  }
  return 1;
}

/// 若目前使用者為 Fast Dating 2～6：同層會員排前，其餘依與自己層級差距由小到大。
void sortDiscoverHomeListBySubscriptionTier(
  List<Map<String, dynamic>> list,
  int? myTier,
) {
  if (myTier == null || myTier < 2 || myTier > 6) return;
  list.sort((a, b) {
    final ta = discoverPeerPlanTier(a);
    final tb = discoverPeerPlanTier(b);
    final sa = ta == myTier ? 0 : 1;
    final sb = tb == myTier ? 0 : 1;
    if (sa != sb) return sa.compareTo(sb);
    final da = (ta - myTier).abs();
    final db = (tb - myTier).abs();
    if (da != db) return da.compareTo(db);
    return '${a['id']}'.compareTo('${b['id']}');
  });
}

/// 將 [FirestorePaths.users] 文件轉成首頁卡片用的 [Map]（與 [getMockUserList] 欄位對齊）。
Map<String, dynamic> userDocToDiscoverCard(
    String uid, Map<String, dynamic> data) {
  final displayName = (data['displayName'] as String?)?.trim() ?? '會員';
  int age = 25;
  final rawAge = data['age'];
  if (rawAge is int) {
    age = rawAge;
  } else if (rawAge != null) {
    age = int.tryParse(rawAge.toString()) ?? 25;
  }
  var gender = (data['gender'] as String?)?.trim().toLowerCase() ?? 'male';
  if (gender != 'female') gender = 'male';
  final job = (data['job'] as String?)?.trim() ?? '未填寫';
  final avatar = (data['avatar'] as String?)?.trim() ??
      'https://picsum.photos/seed/${uid.hashCode}/200/200';
  final t = data['tags'];
  final List<dynamic> tags =
      t is List ? t.map((e) => e.toString()).toList() : <String>['美食', '旅行'];
  final sentence = (data['sentence'] as String?)?.trim() ?? '';
  final distance = (data['distanceLabel'] as String?)?.trim() ?? '—';
  var planTier = 1;
  final fp = data['fastDatingPlan'];
  if (fp is int && fp >= 1 && fp <= 6) {
    planTier = fp;
  } else if (fp is num) {
    final n = fp.round();
    if (n >= 1 && n <= 6) planTier = n;
  }
  return {
    'id': uid,
    'name': displayName,
    'age': age,
    'gender': gender,
    'job': job,
    'distance': distance,
    'avatar': avatar,
    'tags': tags,
    'sentence': sentence,
    'fastDatingPlan': planTier,
  };
}

double? _toNearbyDouble(dynamic value) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  if (value == null) return null;
  return double.tryParse(value.toString());
}

String _formatNearbyDistanceLabel(double meters) {
  if (meters < 1000) {
    return '${meters.round()}m 內';
  }
  final km = meters / 1000;
  return km < 10 ? '${km.toStringAsFixed(1)}km' : '${km.round()}km';
}

/// 會員基本資料寫入 [FirestorePaths.users]；供註冊、個人檔案同步。
class UserFirestoreService {
  UserFirestoreService._();
  static final UserFirestoreService instance = UserFirestoreService._();

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  /// 註冊或登入後建立／合併使用者文件。
  /// [emailOverride]：註冊當下 [User.email] 有時尚未同步（尤其 Web），請傳入表單 Email。
  /// [assignMemberNo]：僅在 **註冊成功** 時為 `true` 才派發 [memberNo]；登入同步請用 `false`，避免失敗流程也佔用編號。
  Future<void> ensureUserProfile({
    required User user,
    String? loginName,
    String? phone,
    String? emailOverride,
    bool assignMemberNo = false,
  }) async {
    if (!FirebaseBootstrap.isReady) return;
    final ref = _db.collection(FirestorePaths.users).doc(user.uid);
    final existing = await ref.get();
    final email = (user.email ?? emailOverride)?.trim() ?? '';
    var displayName = (loginName != null && loginName.trim().isNotEmpty)
        ? loginName.trim()
        : (user.displayName ?? '');
    if (displayName.trim().isEmpty && existing.exists) {
      final prev = existing.data()?['displayName'];
      if (prev is String && prev.trim().isNotEmpty) {
        displayName = prev.trim();
      }
    }
    final data = <String, dynamic>{
      'email': email,
      'displayName': displayName,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (!existing.exists) {
      data['createdAt'] = FieldValue.serverTimestamp();
    }
    final p = phone?.trim();
    if (p != null && p.isNotEmpty) {
      data['phone'] = p;
    } else if (existing.exists) {
      final prevPhone = existing.data()?['phone'];
      if (prevPhone != null && prevPhone.toString().trim().isNotEmpty) {
        data['phone'] = prevPhone;
      }
    }
    if (!assignMemberNo && existing.exists) {
      final prevMn = existing.data()?['memberNo'];
      if (prevMn is String && prevMn.trim().isNotEmpty) {
        data['memberNo'] = prevMn.trim();
      }
    }

    final hasMemberNo = existing.exists &&
        existing.data()?['memberNo'] is String &&
        (existing.data()!['memberNo'] as String).trim().isNotEmpty;

    if (assignMemberNo && !hasMemberNo) {
      try {
        await _db.runTransaction<void>((transaction) async {
          final counterRef = _db
              .collection(FirestorePaths.counters)
              .doc(FirestorePaths.memberSeqDoc);
          final snap = await transaction.get(counterRef);
          final last = (snap.data()?['seq'] as int?) ?? 10000;
          final assigned = last + 1;
          transaction.set(
              counterRef, {'seq': assigned}, SetOptions(merge: true));
          final withMember = Map<String, dynamic>.from(data)
            ..['memberNo'] = 'FD-$assigned';
          transaction.set(ref, withMember, SetOptions(merge: true));
        });
        return;
      } catch (e, st) {
        debugPrint('memberNo 交易失敗，改用 uid 後綴並單次寫入: $e\n$st');
        data['memberNo'] =
            'FD-${user.uid.replaceAll('-', '').substring(0, 8).toUpperCase()}';
      }
    }

    await ref.set(data, SetOptions(merge: true));
  }

  /// 更新目前使用者的 `gender`（`male`／`female`）。
  Future<void> updateUserGender(String uid, String gender) async {
    if (!FirebaseBootstrap.isReady) return;
    final g = gender.toLowerCase().trim() == 'female' ? 'female' : 'male';
    try {
      await _db.collection(FirestorePaths.users).doc(uid).set({
        'gender': g,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e, st) {
      debugPrint('updateUserGender 失敗: $e\n$st');
    }
  }

  /// 讀取會員文件中的 `gender`（`female` 或預設 `male`），供訊息頁示範列表等使用。
  Future<String> fetchUserGender(String uid) async {
    if (!FirebaseBootstrap.isReady) return 'male';
    try {
      final doc = await _db.collection(FirestorePaths.users).doc(uid).get();
      if (!doc.exists) return 'male';
      var g =
          (doc.data()?['gender'] as String?)?.trim().toLowerCase() ?? 'male';
      return g == 'female' ? 'female' : 'male';
    } catch (e, st) {
      debugPrint('fetchUserGender 失敗: $e\n$st');
      return 'male';
    }
  }

  Future<String?> fetchDisplayNameForUid(String uid) async {
    if (!FirebaseBootstrap.isReady) return null;
    try {
      final doc = await _db.collection(FirestorePaths.users).doc(uid).get();
      if (!doc.exists) return null;
      final n = (doc.data()?['displayName'] as String?)?.trim();
      if (n == null || n.isEmpty) return null;
      return n;
    } catch (_) {
      return null;
    }
  }

  Future<String?> fetchAvatarForUid(String uid) async {
    if (!FirebaseBootstrap.isReady) return null;
    try {
      final doc = await _db.collection(FirestorePaths.users).doc(uid).get();
      if (!doc.exists) return null;
      return (doc.data()?['avatar'] as String?)?.trim();
    } catch (_) {
      return null;
    }
  }

  /// 首頁「探索」：即時監聽 [FirestorePaths.users] 全部會員（不限筆數），並可選排除自己。
  /// 需已登入且規則允許讀取該集合。會員極多時請改成分頁或 Cloud Function 聚合。
  Stream<List<Map<String, dynamic>>> watchDiscoverUsers({
    String? excludeUid,
  }) {
    if (!FirebaseBootstrap.isReady) {
      return Stream<List<Map<String, dynamic>>>.value([]);
    }
    return _db.collection(FirestorePaths.users).snapshots().map((snap) {
      final out = <Map<String, dynamic>>[];
      for (final d in snap.docs) {
        if (excludeUid != null && d.id == excludeUid) continue;
        final raw = d.data();
        if (!isUserDocCompleteForHomeDiscover(raw)) continue;
        out.add(userDocToDiscoverCard(d.id, raw));
      }
      return out;
    });
  }

  /// 「附近的人」真實會員：讀取已開啟定位之 [users]，以目前座標計算距離。
  /// 若未能取得目前座標，則仍回傳真實會員，但距離顯示為「附近」。
  Future<List<Map<String, dynamic>>> fetchNearbyRealUsers({
    String? excludeUid,
    double? latitude,
    double? longitude,
    int? radiusKm,
    int limit = 200,
  }) async {
    if (!FirebaseBootstrap.isReady) return <Map<String, dynamic>>[];
    try {
      final snap = await _db
          .collection(FirestorePaths.users)
          .where('regionVisible', isEqualTo: true)
          .limit(limit)
          .get();
      final out = <Map<String, dynamic>>[];
      final hasCurrentLocation = latitude != null && longitude != null;
      final radiusMeters = (radiusKm ?? 0) > 0 ? radiusKm! * 1000.0 : null;
      for (final d in snap.docs) {
        if (excludeUid != null && d.id == excludeUid) continue;
        final raw = d.data();
        final name = (raw['displayName'] as String?)?.trim() ?? '';
        final rawAge = raw['age'];
        final age = rawAge is int
            ? rawAge
            : (rawAge != null ? int.tryParse(rawAge.toString()) : null);
        if (name.isEmpty || age == null || age < 18 || age > 120) continue;
        final peerLat = _toNearbyDouble(raw['latitude']);
        final peerLng = _toNearbyDouble(raw['longitude']);
        if (peerLat == null || peerLng == null) continue;
        double? meters;
        if (hasCurrentLocation) {
          meters = Geolocator.distanceBetween(
            latitude!,
            longitude!,
            peerLat,
            peerLng,
          );
          if (radiusMeters != null && meters > radiusMeters) continue;
        }
        final card = userDocToDiscoverCard(d.id, raw);
        card['distance'] =
            meters == null ? '附近' : _formatNearbyDistanceLabel(meters);
        if (meters != null) {
          card['distanceMeters'] = meters;
        }
        card['isRealNearby'] = true;
        out.add(card);
      }
      out.sort((a, b) {
        final am = _toNearbyDouble(a['distanceMeters']);
        final bm = _toNearbyDouble(b['distanceMeters']);
        if (am == null && bm == null) return 0;
        if (am == null) return 1;
        if (bm == null) return -1;
        return am.compareTo(bm);
      });
      return out;
    } catch (e, st) {
      debugPrint('fetchNearbyRealUsers: $e\n$st');
      return <Map<String, dynamic>>[];
    }
  }

  /// 補齊首頁／篩選所需之公開欄位（僅填缺漏，不覆寫使用者已填資料）。
  Future<void> seedPublicProfileIfMissing(String uid) async {
    if (!FirebaseBootstrap.isReady) return;
    final ref = _db.collection(FirestorePaths.users).doc(uid);
    final snap = await ref.get();
    if (!snap.exists) return;
    final data = snap.data() ?? {};
    final h = uid.hashCode.abs();
    final patch = <String, dynamic>{};

    if (data['gender'] == null) {
      patch['gender'] = (h % 2 == 0) ? 'male' : 'female';
    }
    if (data['age'] == null) {
      patch['age'] = 22 + (h % 19);
    }
    final job = (data['job'] as String?)?.trim();
    if (job == null || job.isEmpty) {
      patch['job'] = '未填寫';
    }
    final av = (data['avatar'] as String?)?.trim();
    if (av == null || av.isEmpty) {
      patch['avatar'] = 'https://picsum.photos/seed/${uid.hashCode}/200/200';
    }
    if (data['tags'] == null) {
      patch['tags'] = ['美食', '旅行'];
    }
    final s = (data['sentence'] as String?)?.trim();
    if (s == null || s.isEmpty) {
      patch['sentence'] = kDiscoverDefaultSentence;
    }
    if (data['distanceLabel'] == null) {
      patch['distanceLabel'] = '附近';
    }

    if (patch.isEmpty) return;
    patch['updatedAt'] = FieldValue.serverTimestamp();
    try {
      await ref.set(patch, SetOptions(merge: true));
    } catch (e, st) {
      debugPrint('seedPublicProfileIfMissing 失敗: $e\n$st');
    }
  }

  /// 是否已填寫配對所需基本公開資料（稱呼／職業／一句話；一句話非預設占位）。
  /// 供「想講～」等入口提示補齊資料；讀取失敗時回傳 `true` 以免擋住流程。
  Future<bool> isCurrentUserProfileCompleteForMatching() async {
    if (!FirebaseBootstrap.isReady) return true;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return true;
    try {
      final doc =
          await _db.collection(FirestorePaths.users).doc(user.uid).get();
      if (!doc.exists) return false;
      final d = doc.data() ?? {};
      final displayName = (d['displayName'] as String?)?.trim() ?? '';
      if (displayName.isEmpty) return false;
      final job = (d['job'] as String?)?.trim() ?? '';
      if (job.isEmpty || job == '未填寫') return false;
      final s = (d['sentence'] as String?)?.trim() ?? '';
      if (s.isEmpty || s == kDiscoverDefaultSentence) return false;
      return true;
    } catch (e, st) {
      debugPrint('isCurrentUserProfileCompleteForMatching: $e\n$st');
      return true;
    }
  }

  /// 想講～上傳圖片：寫入 [avatar] 為 `data:image/jpeg;base64,...`（供訊息列表／聊天大頭照同步）
  /// 單欄長度需低於 Firestore 限制，過大時略過寫入。
  Future<void> saveProfileAvatarFromImageBytes(List<int> bytes) async {
    if (!FirebaseBootstrap.isReady) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || bytes.isEmpty) return;
    final compressed = compressForAvatarDataUrl(Uint8List.fromList(bytes));
    const maxRaw = 600000;
    if (compressed.length > maxRaw) {
      debugPrint(
          'saveProfileAvatarFromImageBytes: 圖片過大 (${compressed.length})，略過');
      return;
    }
    final dataUrl = 'data:image/jpeg;base64,${base64Encode(compressed)}';
    if (dataUrl.length > 950000) {
      debugPrint('saveProfileAvatarFromImageBytes: base64 過長，略過');
      return;
    }
    try {
      await _db.collection(FirestorePaths.users).doc(user.uid).set({
        'avatar': dataUrl,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e, st) {
      debugPrint('saveProfileAvatarFromImageBytes: $e\n$st');
    }
  }

  /// 「想講～」送出時合併寫入稱呼（[displayName]）、[age]、職業與一句話（供配對卡與首頁顯示）。
  Future<void> updateJobAndSentenceFromOneSentencePage({
    required String displayName,
    required int age,
    required String job,
    required String sentence,
  }) async {
    if (!FirebaseBootstrap.isReady) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final dn = displayName.trim();
    final j = job.trim();
    final s = sentence.trim();
    if (dn.isEmpty) return;
    if (j.isEmpty || j == '未填寫') return;
    if (s.isEmpty || s == kDiscoverDefaultSentence) return;
    if (age < 1 || age > 120) return;
    try {
      await _db.collection(FirestorePaths.users).doc(user.uid).set({
        'displayName': dn,
        'age': age,
        'job': j,
        'sentence': s,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e, st) {
      debugPrint('updateJobAndSentenceFromOneSentencePage: $e\n$st');
    }
  }

  /// 將想講～「興趣」欄（逗號分隔）合併至 [users.tags]，供首頁興趣篩選與配對卡；與既有標籤重複者不新增。
  Future<void> mergeDiscoverTagsFromCommaSeparated(String interestsRaw) async {
    if (!FirebaseBootstrap.isReady) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final parts = parseCommaSeparatedInterests(interestsRaw);
    if (parts.isEmpty) return;
    try {
      final ref = _db.collection(FirestorePaths.users).doc(user.uid);
      final snap = await ref.get();
      final list = <String>[];
      final raw = snap.data()?['tags'];
      if (raw is List) {
        for (final e in raw) {
          final s = normalizeInterestToken(e.toString());
          if (s.isEmpty) continue;
          if (!interestTagsContains(list, s)) list.add(s);
        }
      }
      for (final p in parts) {
        if (!interestTagsContains(list, p)) list.add(p);
      }
      if (list.length > 40) {
        list.removeRange(40, list.length);
      }
      await ref.set(
        {
          'tags': list,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } catch (e, st) {
      debugPrint('mergeDiscoverTagsFromCommaSeparated: $e\n$st');
    }
  }

  /// 「想講～」地區開關：寫入是否公開地區與 GPS 座標（關閉時刪除座標欄位）。
  Future<void> updateUserRegionGps({
    required bool visible,
    double? latitude,
    double? longitude,
  }) async {
    if (!FirebaseBootstrap.isReady) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final patch = <String, dynamic>{
        'regionVisible': visible,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (visible && latitude != null && longitude != null) {
        patch['latitude'] = latitude;
        patch['longitude'] = longitude;
      } else {
        patch['latitude'] = FieldValue.delete();
        patch['longitude'] = FieldValue.delete();
      }
      await _db.collection(FirestorePaths.users).doc(user.uid).set(
            patch,
            SetOptions(merge: true),
          );
    } catch (e, st) {
      debugPrint('updateUserRegionGps: $e\n$st');
    }
  }

  /// 訂閱狀態（供 [ChatQuotaService] 略過每日免費兩位不同會員上限）。
  /// 手動／轉帳方案須由管理員於後台確認收款後再設為 true；僅有訂單未核實者應維持 false。
  /// [fastDatingPlan]：Fast Dating 1～6，與訂閱頁／參加者資產分級同步；非 null 時一併寫入。
  Future<void> setSubscriptionActive(
    bool active, {
    int? fastDatingPlan,
  }) async {
    if (!FirebaseBootstrap.isReady) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final data = <String, dynamic>{
        'subscriptionActive': active,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (fastDatingPlan != null &&
          fastDatingPlan >= 1 &&
          fastDatingPlan <= 6) {
        data['fastDatingPlan'] = fastDatingPlan;
      }
      await _db.collection(FirestorePaths.users).doc(user.uid).set(
            data,
            SetOptions(merge: true),
          );
    } catch (e, st) {
      debugPrint('setSubscriptionActive 失敗: $e\n$st');
    }
  }

  /// 會員提交／同步廣告貼文後寫入 [adCoopLatestSubmission]，並標記 [adCoopStandalonePending]（無訂單時為 true）
  /// 與 [adCoopAdminReviewPending]（兩種路徑皆 true，供後台「廣告審批」列出；與訂單付款資料無關）。
  Future<void> syncAdCoopLatestSubmissionMirror({
    required String title,
    required String text,
    required String link,
    required String imageUrl,
    String? linkedOrderId,
    required bool standalonePending,
    required bool removeImage,
  }) async {
    if (!FirebaseBootstrap.isReady) return;
    final user = FirebaseAuth.instance.currentUser;
    // 含匿名登入（仍有 uid）；Firestore 規則為 request.auth != null 即可寫入本人文件
    if (user == null) return;
    final uid = user.uid;
    final ref = _db.collection(FirestorePaths.users).doc(uid);
    try {
      await _db.runTransaction((transaction) async {
        final snap = await transaction.get(ref);
        final existing = snap.data()?['adCoopLatestSubmission'];
        final next = <String, dynamic>{};
        if (existing is Map) {
          for (final e in existing.entries) {
            next['${e.key}'] = e.value;
          }
        }
        next['title'] = title.trim();
        next['text'] = text.trim();
        next['link'] = link.trim();
        if (linkedOrderId != null && linkedOrderId.isNotEmpty) {
          next['linkedOrderId'] = linkedOrderId;
        } else {
          next.remove('linkedOrderId');
        }
        // 僅在明確刪圖或帶入新 URL 時變更；空字串且非刪圖時保留既有 imageUrl（避免快取讀訂單失準時誤清）
        if (removeImage) {
          next.remove('imageUrl');
        } else if (imageUrl.trim().isNotEmpty) {
          next['imageUrl'] = imageUrl.trim();
        }
        // 每次提交更新，供後台「廣告審批」顯示最新提交時間。
        next['submittedAt'] = FieldValue.serverTimestamp();
        final historyEntry = <String, dynamic>{
          'title': title.trim(),
          'text': text.trim(),
          'link': link.trim(),
          if (imageUrl.trim().isNotEmpty) 'imageUrl': imageUrl.trim(),
          if (linkedOrderId != null && linkedOrderId.isNotEmpty)
            'linkedOrderId': linkedOrderId,
          'submittedAt': Timestamp.fromDate(DateTime.now()),
        };
        final linked = linkedOrderId != null && linkedOrderId.isNotEmpty;
        final patch = <String, dynamic>{
          'adCoopLatestSubmission': next,
          'adCoopStandalonePending': standalonePending,
          // 含「僅貼文」與「已綁廣告訂單」兩種；後台廣告審批頁以此列出待審（不依賴訂單付款欄位）。
          'adCoopAdminReviewPending': true,
          'adCoopApprovalArchiveVisible': true,
          'updatedAt': FieldValue.serverTimestamp(),
        };
        // 僅「無綁定訂單」之提交寫入使用者歷史；有訂單者以 [subscription_orders] 與 [adContentHistory] 為準，避免與訂單卡片重複。
        if (!linked) {
          patch['adCoopSubmissionHistory'] =
              FieldValue.arrayUnion([historyEntry]);
        }
        transaction.set(
          ref,
          patch,
          SetOptions(merge: true),
        );
      });
    } catch (e, st) {
      debugPrint('syncAdCoopLatestSubmissionMirror: $e\n$st');
    }
  }

  /// 從目前使用者的 [adCoopSubmissionHistory] 移除與 [entry] 相符的一筆（無訂單綁定之提交歷史）。
  /// [entry] 通常來自 [DocumentSnapshot] 內之 Map，需含與寫入時一致之 [submittedAt]（[Timestamp]）以便精準比對。
  Future<bool> removeAdCoopSubmissionHistoryEntry(
      Map<String, dynamic> entry) async {
    if (!FirebaseBootstrap.isReady) return false;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    final ref = _db.collection(FirestorePaths.users).doc(user.uid);
    try {
      final removed = await _db.runTransaction<bool>((transaction) async {
        final snap = await transaction.get(ref);
        final raw = snap.data()?['adCoopSubmissionHistory'];
        if (raw is! List) {
          return false;
        }
        final list = <Map<String, dynamic>>[];
        for (final e in raw) {
          if (e is Map) {
            list.add(Map<String, dynamic>.from(e));
          }
        }
        final filtered =
            list.where((row) => !_matchesAdCoopHistoryRow(row, entry)).toList();
        if (filtered.length == list.length) {
          return false;
        }
        transaction.set(
          ref,
          {
            'adCoopSubmissionHistory': filtered,
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
        return true;
      });
      return removed;
    } catch (e, st) {
      debugPrint('removeAdCoopSubmissionHistoryEntry: $e\n$st');
      return false;
    }
  }

  static bool _matchesAdCoopHistoryRow(
    Map<String, dynamic> row,
    Map<String, dynamic> toRemove,
  ) {
    final t1 = (row['text'] ?? '').toString().trim();
    final t2 = (toRemove['text'] ?? '').toString().trim();
    final l1 = (row['link'] ?? '').toString().trim();
    final l2 = (toRemove['link'] ?? '').toString().trim();
    if (t1 != t2 || l1 != l2) return false;
    final ts1 = row['submittedAt'];
    final ts2 = toRemove['submittedAt'];
    if (ts1 is Timestamp && ts2 is Timestamp) {
      return ts1.seconds == ts2.seconds && ts1.nanoseconds == ts2.nanoseconds;
    }
    return true;
  }

  /// Cookie 私隱同意（首頁橫幅）：`essential` | `analytics`；未設定表示尚未選擇。
  static const String fieldCookieConsent = 'cookieConsent';

  /// 讀取會員已儲存之 Cookie 同意；未設定為 null。
  Future<String?> getCookieConsent(String uid) async {
    if (!FirebaseBootstrap.isReady) return null;
    try {
      final snap = await _db.collection(FirestorePaths.users).doc(uid).get();
      final v = snap.data()?[fieldCookieConsent];
      if (v is String) {
        final t = v.trim();
        if (t == 'essential' || t == 'analytics') return t;
      }
    } catch (e, st) {
      debugPrint('getCookieConsent: $e\n$st');
    }
    return null;
  }

  /// 寫入會員 Cookie 選擇（登入後首頁橫幅確認時呼叫）。
  Future<void> setCookieConsent(String uid, String level) async {
    if (!FirebaseBootstrap.isReady) return;
    final normalized = level == 'analytics' ? 'analytics' : 'essential';
    try {
      await _db.collection(FirestorePaths.users).doc(uid).set(
        {
          fieldCookieConsent: normalized,
          'cookieConsentRecordedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } catch (e, st) {
      debugPrint('setCookieConsent: $e\n$st');
      rethrow;
    }
  }

  /// 設定頁「重新選擇 Cookie 偏好」：清除紀錄，下次進首頁可再顯示橫幅。
  Future<void> clearCookieConsentForUid(String uid) async {
    if (!FirebaseBootstrap.isReady) return;
    try {
      await _db.collection(FirestorePaths.users).doc(uid).set(
        {
          fieldCookieConsent: FieldValue.delete(),
          'cookieConsentRecordedAt': FieldValue.delete(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } catch (e, st) {
      debugPrint('clearCookieConsentForUid: $e\n$st');
    }
  }

  /// 目前使用者清除 Cookie 同意欄位（需已登入）。
  Future<void> clearMyCookieConsent() async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return;
    await clearCookieConsentForUid(u.uid);
  }

  /// 目前使用者 `users.fastDatingPlan`（1～6），未設定或離線為 null。
  Stream<int?> watchMyDiscoverPlanTier() {
    if (!FirebaseBootstrap.isReady) {
      return Stream<int?>.value(null);
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Stream<int?>.value(null);
    }
    return _db.collection(FirestorePaths.users).doc(user.uid).snapshots().map(
      (s) {
        final d = s.data();
        if (d == null) return null;
        final p = d['fastDatingPlan'];
        if (p is int && p >= 1 && p <= 6) return p;
        if (p is num) {
          final n = p.round();
          if (n >= 1 && n <= 6) return n;
        }
        return null;
      },
    );
  }

  /// 寫入 FCM 裝置 token，供 [functions/index.js] 在未開啟 App／瀏覽器時推播新訊息用。
  Future<void> syncFcmTokenForCurrentPlatform(String? token) async {
    if (!FirebaseBootstrap.isReady) return;
    final u = FirebaseAuth.instance.currentUser;
    if (u == null || token == null || token.isEmpty) return;
    final String field;
    if (kIsWeb) {
      field = 'fcmTokenWeb';
    } else {
      switch (defaultTargetPlatform) {
        case TargetPlatform.iOS:
          field = 'fcmTokenIos';
          break;
        case TargetPlatform.android:
          field = 'fcmTokenAndroid';
          break;
        default:
          field = 'fcmTokenOther';
      }
    }
    try {
      await _db.collection(FirestorePaths.users).doc(u.uid).set(
        {
          field: token,
          'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } catch (e, st) {
      debugPrint('syncFcmTokenForCurrentPlatform: $e\n$st');
    }
  }

  /// 與 [NotificationProvider.messageSoundEnabled] 同步；後端讀 [notifNewMessagePush] 是否發送 FCM。缺省當作 `true`。
  Future<void> syncNotifNewMessagePushToServer(bool enabled) async {
    if (!FirebaseBootstrap.isReady) return;
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return;
    try {
      await _db.collection(FirestorePaths.users).doc(u.uid).set(
        {
          'notifNewMessagePush': enabled,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } catch (e, st) {
      debugPrint('syncNotifNewMessagePushToServer: $e\n$st');
    }
  }
}
