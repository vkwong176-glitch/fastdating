import 'package:flutter/material.dart';

/// 首頁探索：當 Firestore 無足夠對象時合併示範配對卡（id 以 `demo_match_` 開頭；不發雲端邀請；按「進入聊天」僅提示黑底訊息，不開聊天頁）。
/// 男女各 6 筆，依篩選挑選最多 [max] 筆。
const String _demoPrefix = 'demo_match_';

List<Map<String, dynamic>> _poolForGender(String gender) {
  if (gender == 'female') {
    return _femaleDemos;
  }
  return _maleDemos;
}

final List<Map<String, dynamic>> _femaleDemos = [
  {
    'id': '${_demoPrefix}f01',
    'name': '小晴',
    'age': 25,
    'gender': 'female',
    'job': '視覺設計',
    'distance': '2.5km',
    'avatar': 'https://picsum.photos/seed/fddemo01/200/200',
    'tags': ['美食', '旅行', '咖啡'],
    'sentence': '喜歡咖啡、展覽與周末小旅行，想找聊得來的你～',
    'isDemo': true,
    'fastDatingPlan': 2,
  },
  {
    'id': '${_demoPrefix}f02',
    'name': '雅琳',
    'age': 27,
    'gender': 'female',
    'job': '行銷企劃',
    'distance': '1.2km',
    'avatar': 'https://picsum.photos/seed/fddemo02/200/200',
    'tags': ['音樂', '電影', '美食'],
    'sentence': '下班後喜歡聽歌、看電影，想認識新朋友。',
    'isDemo': true,
    'fastDatingPlan': 3,
  },
  {
    'id': '${_demoPrefix}f03',
    'name': '思妤',
    'age': 24,
    'gender': 'female',
    'job': '護理師',
    'distance': '3.0km',
    'avatar': 'https://picsum.photos/seed/fddemo03/200/200',
    'tags': ['寵物', '烘焙', '閱讀'],
    'sentence': '家裡有貓，周末愛烘焙與看書。',
    'isDemo': true,
    'fastDatingPlan': 4,
  },
  {
    'id': '${_demoPrefix}f04',
    'name': '芷萱',
    'age': 26,
    'gender': 'female',
    'job': '老師',
    'distance': '800m 內',
    'avatar': 'https://picsum.photos/seed/fddemo04/200/200',
    'tags': ['旅行', '攝影', '瑜伽'],
    'sentence': '剛從日本回來，想找人分享旅行照片。',
    'isDemo': true,
    'fastDatingPlan': 5,
  },
  {
    'id': '${_demoPrefix}f05',
    'name': '沛宜',
    'age': 28,
    'gender': 'female',
    'job': '會計',
    'distance': '4.1km',
    'avatar': 'https://picsum.photos/seed/fddemo05/200/200',
    'tags': ['健身', '美食', '紅酒'],
    'sentence': '平日健身，周末愛找餐廳小酌。',
    'isDemo': true,
    'fastDatingPlan': 6,
  },
  {
    'id': '${_demoPrefix}f06',
    'name': '若彤',
    'age': 23,
    'gender': 'female',
    'job': '研究生',
    'distance': '1.8km',
    'avatar': 'https://picsum.photos/seed/fddemo06/200/200',
    'tags': ['音樂', '展覽', '手作'],
    'sentence': '論文告一段落，想放鬆認識人。',
    'isDemo': true,
    'fastDatingPlan': 2,
  },
];

final List<Map<String, dynamic>> _maleDemos = [
  {
    'id': '${_demoPrefix}m01',
    'name': '子軒',
    'age': 28,
    'gender': 'male',
    'job': '軟體工程師',
    'distance': '1.5km',
    'avatar': 'https://picsum.photos/seed/fddemo_m01/200/200',
    'tags': ['健身', '音樂', '旅行'],
    'sentence': '周末喜歡爬山或找間咖啡廳寫 code。',
    'isDemo': true,
    'fastDatingPlan': 2,
  },
  {
    'id': '${_demoPrefix}m02',
    'name': '冠宇',
    'age': 30,
    'gender': 'male',
    'job': '業務',
    'distance': '2.2km',
    'avatar': 'https://picsum.photos/seed/fddemo_m02/200/200',
    'tags': ['籃球', '電影', '美食'],
    'sentence': '想找一起吃宵夜聊電影的伴。',
    'isDemo': true,
    'fastDatingPlan': 3,
  },
  {
    'id': '${_demoPrefix}m03',
    'name': '承恩',
    'age': 26,
    'gender': 'male',
    'job': '建築師',
    'distance': '3.5km',
    'avatar': 'https://picsum.photos/seed/fddemo_m03/200/200',
    'tags': ['攝影', '閱讀', '咖啡'],
    'sentence': '喜歡街拍與老屋咖啡館。',
    'isDemo': true,
    'fastDatingPlan': 4,
  },
  {
    'id': '${_demoPrefix}m04',
    'name': '柏翰',
    'age': 29,
    'gender': 'male',
    'job': '醫師',
    'distance': '900m 內',
    'avatar': 'https://picsum.photos/seed/fddemo_m04/200/200',
    'tags': ['跑步', '紅酒', '旅行'],
    'sentence': '夜班後想找人輕鬆聊天放鬆。',
    'isDemo': true,
    'fastDatingPlan': 5,
  },
  {
    'id': '${_demoPrefix}m05',
    'name': '奕辰',
    'age': 27,
    'gender': 'male',
    'job': '創業',
    'distance': '5.0km',
    'avatar': 'https://picsum.photos/seed/fddemo_m05/200/200',
    'tags': ['創業', '演講', '健身'],
    'sentence': '想認識不同領域的朋友互相交流。',
    'isDemo': true,
    'fastDatingPlan': 6,
  },
  {
    'id': '${_demoPrefix}m06',
    'name': '宥翔',
    'age': 25,
    'gender': 'male',
    'job': '設計師',
    'distance': '2.0km',
    'avatar': 'https://picsum.photos/seed/fddemo_m06/200/200',
    'tags': ['藝術', '電影', '美食'],
    'sentence': '剛看完展覽，想找人討論心得。',
    'isDemo': true,
    'fastDatingPlan': 2,
  },
];

/// 依篩選從示範池挑選，排除已在列表中的 id；[max] 為本次最多追加筆數。
/// [preferTierFirst]：若為 Fast Dating 2～6，優先挑同層示範卡（訂閱同層真人不足時與其他層／示範融合）。
List<Map<String, dynamic>> discoverDemoProfilesFiltered({
  required String gender,
  required RangeValues ageRange,
  required Set<String> selectedInterests,
  required Set<String> excludeIds,
  required String searchQuery,
  required int max,
  int? preferTierFirst,
}) {
  if (max <= 0) return [];
  final q = searchQuery.trim().toLowerCase();
  final pool = _poolForGender(gender);
  final out = <Map<String, dynamic>>[];
  for (final raw in pool) {
    if (out.length >= max) break;
    final id = raw['id']?.toString() ?? '';
    if (excludeIds.contains(id)) continue;
    final age = raw['age'] is int
        ? raw['age'] as int
        : int.tryParse('${raw['age']}') ?? 25;
    if (age < ageRange.start.round() || age > ageRange.end.round()) continue;
    if (selectedInterests.isNotEmpty) {
      final tags = (raw['tags'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toSet() ??
          {};
      if (tags.intersection(selectedInterests).isEmpty) continue;
    }
    if (q.isNotEmpty) {
      final name = (raw['name'] ?? '').toString().toLowerCase();
      final job = (raw['job'] ?? '').toString().toLowerCase();
      if (!name.contains(q) && !job.contains(q)) continue;
    }
    out.add(Map<String, dynamic>.from(raw));
  }
  if (preferTierFirst != null &&
      preferTierFirst >= 2 &&
      preferTierFirst <= 6 &&
      out.length > 1) {
    out.sort((a, b) {
      final ta = a['fastDatingPlan'];
      final tb = b['fastDatingPlan'];
      final ia = ta is int ? ta : int.tryParse('$ta') ?? 1;
      final ib = tb is int ? tb : int.tryParse('$tb') ?? 1;
      final sa = ia == preferTierFirst ? 0 : 1;
      final sb = ib == preferTierFirst ? 0 : 1;
      if (sa != sb) return sa.compareTo(sb);
      return (ia - preferTierFirst).abs().compareTo((ib - preferTierFirst).abs());
    });
  }
  return out;
}

bool isDemoDiscoverProfile(Map<String, dynamic> user) =>
    user['isDemo'] == true ||
    (user['id']?.toString().startsWith(_demoPrefix) ?? false);
