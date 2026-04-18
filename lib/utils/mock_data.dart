// 模擬數據：20 條使用者 + 10 條以上聊天記錄，上線時替換為 API 請求
// 頭像使用 picsum.photos（與活動頁一致）；勿用 via.placeholder.com（部分網路環境會 statusCode:0）

import 'dart:math';

/// 模擬用戶列表（含 [gender]：`male`／`female`，供首頁篩選與訊息頁示範）
List<Map<String, dynamic>> getMockUserList() {
  final r = <Map<String, dynamic>>[
    {'id': '1', 'gender': 'male', 'name': '小明', 'age': 25, 'job': '工程師', 'distance': '500m 內', 'avatar': 'https://picsum.photos/seed/user1/200/200', 'tags': ['健身', '音樂', '旅行'], 'sentence': '週末想找個人一起運動、聊聊天～'},
    {'id': '2', 'gender': 'female', 'name': '小美', 'age': 23, 'job': '設計師', 'distance': '1.2km', 'avatar': 'https://picsum.photos/seed/user2/200/200', 'tags': ['美食', '閱讀', '電影'], 'sentence': '今天心情不錯，想認識新朋友！'},
    {'id': '3', 'gender': 'male', 'name': '小李', 'age': 28, 'job': '教師', 'distance': '2.5km', 'avatar': 'https://picsum.photos/seed/user3/200/200', 'tags': ['寵物', '攝影', '烹飪'], 'sentence': '剛下班，想放鬆一下聊聊天。'},
    {'id': '4', 'gender': 'male', 'name': '小華', 'age': 26, 'job': '醫生', 'distance': '800m 內', 'avatar': 'https://picsum.photos/seed/user4/200/200', 'tags': ['健身', '聽歌', '露營'], 'sentence': '喜歡戶外，想找同好一起露營。'},
    {'id': '5', 'gender': 'female', 'name': '小琳', 'age': 24, 'job': '財務', 'distance': '3.1km', 'avatar': 'https://picsum.photos/seed/user5/200/200', 'tags': ['購物', '瑜伽', '咖啡'], 'sentence': '下午想找間咖啡廳坐坐、認識新朋友。'},
    {'id': '6', 'gender': 'male', 'name': '阿傑', 'age': 27, 'job': '產品經理', 'distance': '1.8km', 'avatar': 'https://picsum.photos/seed/user6/200/200', 'tags': ['跑步', '電影', '旅行'], 'sentence': '最近在練跑，想找跑友～'},
    {'id': '7', 'gender': 'female', 'name': '雅婷', 'age': 22, 'job': '行銷', 'distance': '4.2km', 'avatar': 'https://picsum.photos/seed/user7/200/200', 'tags': ['美食', '手作', '咖啡'], 'sentence': '心情好，想找人分享今天發生的事。'},
    {'id': '8', 'gender': 'male', 'name': '志明', 'age': 30, 'job': '律師', 'distance': '600m 內', 'avatar': 'https://picsum.photos/seed/user8/200/200', 'tags': ['閱讀', '登山', '紅酒'], 'sentence': '週末打算去爬山，有興趣一起嗎？'},
    {'id': '9', 'gender': 'female', 'name': '曉琪', 'age': 25, 'job': '護理師', 'distance': '2.0km', 'avatar': 'https://picsum.photos/seed/user9/200/200', 'tags': ['寵物', '烘焙', '電影'], 'sentence': '剛看完一部好電影，想找人討論！'},
    {'id': '10', 'gender': 'male', 'name': '大偉', 'age': 29, 'job': '軟體工程師', 'distance': '5.5km', 'avatar': 'https://picsum.photos/seed/user10/200/200', 'tags': ['電玩', '籃球', '音樂'], 'sentence': '下班想打籃球或玩遊戲，有人一起嗎？'},
    {'id': '11', 'gender': 'female', 'name': '心怡', 'age': 23, 'job': '編輯', 'distance': '1.5km', 'avatar': 'https://picsum.photos/seed/user11/200/200', 'tags': ['寫作', '咖啡', '展覽'], 'sentence': '這週末有展覽，想找伴一起去。'},
    {'id': '12', 'gender': 'male', 'name': '俊豪', 'age': 26, 'job': '建築師', 'distance': '3.8km', 'avatar': 'https://picsum.photos/seed/user12/200/200', 'tags': ['設計', '攝影', '旅行'], 'sentence': '喜歡拍照，想認識也愛攝影的朋友。'},
    {'id': '13', 'gender': 'female', 'name': '婉君', 'age': 24, 'job': '人資', 'distance': '900m 內', 'avatar': 'https://picsum.photos/seed/user13/200/200', 'tags': ['瑜伽', '閱讀', '美食'], 'sentence': '今天做了瑜伽，心情很放鬆～'},
    {'id': '14', 'gender': 'male', 'name': '家豪', 'age': 28, 'job': '業務', 'distance': '2.2km', 'avatar': 'https://picsum.photos/seed/user14/200/200', 'tags': ['健身', '電影', '唱歌'], 'sentence': '想找 K 歌夥伴或一起看電影。'},
    {'id': '15', 'gender': 'female', 'name': '雅涵', 'age': 22, 'job': '實習生', 'distance': '4.0km', 'avatar': 'https://picsum.photos/seed/user15/200/200', 'tags': ['旅行', '拍照', '手搖'], 'sentence': '實習告一段落，想出去走走認識人。'},
    {'id': '16', 'gender': 'male', 'name': '建國', 'age': 31, 'job': '主管', 'distance': '1.0km', 'avatar': 'https://picsum.photos/seed/user16/200/200', 'tags': ['高爾夫', '紅酒', '閱讀'], 'sentence': '週末想打高爾夫或喝杯紅酒聊聊天。'},
    {'id': '17', 'gender': 'female', 'name': '佩珊', 'age': 26, 'job': '會計', 'distance': '3.5km', 'avatar': 'https://picsum.photos/seed/user17/200/200', 'tags': ['烘焙', '韓劇', '貓咪'], 'sentence': '在家追劇撸貓，想找人線上聊。'},
    {'id': '18', 'gender': 'male', 'name': '志偉', 'age': 27, 'job': '攝影師', 'distance': '2.8km', 'avatar': 'https://picsum.photos/seed/user18/200/200', 'tags': ['攝影', '登山', '咖啡'], 'sentence': '在找模特兒外拍，或一起喝咖啡。'},
    {'id': '19', 'gender': 'female', 'name': '淑芬', 'age': 25, 'job': '老師', 'distance': '1.3km', 'avatar': 'https://picsum.photos/seed/user19/200/200', 'tags': ['閱讀', '繪畫', '旅行'], 'sentence': '喜歡畫畫與閱讀，想找同好交流。'},
    {'id': '20', 'gender': 'male', 'name': '俊傑', 'age': 29, 'job': '創業', 'distance': '6.0km', 'avatar': 'https://picsum.photos/seed/user20/200/200', 'tags': ['創業', '跑步', '演講'], 'sentence': '創業中，想認識不同領域的朋友。'},
    {'id': '21', 'gender': 'female', 'name': '可欣', 'age': 24, 'job': '秘書', 'distance': '2.6km', 'avatar': 'https://picsum.photos/seed/user21/200/200', 'tags': ['咖啡', '電影', '慢跑'], 'sentence': '想找個聊得來的人一起放鬆。'},
    {'id': '22', 'gender': 'female', 'name': '宜萱', 'age': 26, 'job': '設計', 'distance': '3.2km', 'avatar': 'https://picsum.photos/seed/user22/200/200', 'tags': ['插畫', '甜點', '旅行'], 'sentence': '喜歡小旅行與甜點店打卡～'},
  ];
  return [
    for (var i = 0; i < r.length; i++)
      <String, dynamic>{...r[i], 'fastDatingPlan': 2 + (i % 5)},
  ];
}

/// 模擬單一聊天室的訊息列表（10 條以上）
List<Map<String, dynamic>> getMockMessages(String peerId) {
  return [
    {'id': 'm1', 'isMe': false, 'text': '嗨，你好！', 'time': '10:00'},
    {'id': 'm2', 'isMe': true, 'text': '你好呀～', 'time': '10:01'},
    {'id': 'm3', 'isMe': false, 'text': '看到你也喜歡健身，平常都去哪運動？', 'time': '10:02'},
    {'id': 'm4', 'isMe': true, 'text': '我都在家附近的健身房，你呢？', 'time': '10:05'},
    {'id': 'm5', 'isMe': false, 'text': '我也是！說不定我們見過面哈哈', 'time': '10:06'},
    {'id': 'm6', 'isMe': true, 'text': '有可能喔，有機會可以一起練', 'time': '10:08'},
    {'id': 'm7', 'isMe': false, 'text': '好呀，這週末你有空嗎？', 'time': '10:10'},
    {'id': 'm8', 'isMe': true, 'text': '週六下午可以～', 'time': '10:12'},
    {'id': 'm9', 'isMe': false, 'text': '那就約週六下午兩點？', 'time': '10:13'},
    {'id': 'm10', 'isMe': true, 'text': '沒問題，到時見！', 'time': '10:15'},
    {'id': 'm11', 'isMe': false, 'text': '到時見～', 'time': '10:16'},
  ];
}

const _mockLastMessages = <String>[
  '到時見～',
  '這週末有空一起喝咖啡嗎？',
  '謝謝你昨天的建議！',
  '我已經到囉',
  '晚安，早點休息',
  '照片拍得很棒耶',
  '好啊，下次再約',
  '下班了嗎？',
  '那家餐廳真的不錯',
  '哈哈我也喜歡這部電影',
  '今天天氣真好，出去走走？',
  '剛看到你也喜歡旅行～',
  '週末市集一起去嗎？',
  '收到，等等回你',
];

const _mockTimes = <String>[
  '10:16',
  '09:45',
  '昨天',
  '11:20',
  '14:05',
  '08:30',
  '12:00',
  '18:22',
  '週一',
  '16:40',
  '剛剛',
];

/// 自 [getMockUserList] 中隨機挑 10 位**與 [myGender] 異性**的配對對象，產生聊天列表列項目。
/// [seed] 固定時可重現同一組（測試用）；未傳則每次進頁不同。
List<Map<String, dynamic>> getRandomOppositeSexChatList({
  required String myGender,
  int? seed,
  int count = 10,
}) {
  final mine = myGender.toLowerCase() == 'female' ? 'female' : 'male';
  final rng = Random(seed ?? DateTime.now().millisecondsSinceEpoch);
  final opposite =
      getMockUserList().where((u) => (u['gender'] as String? ?? 'male') != mine).toList();
  opposite.shuffle(rng);
  final pick = opposite.take(count).toList();
  return pick.map((u) {
    final id = u['id'].toString();
    return {
      'userId': id,
      'name': u['name'] as String,
      'avatar': 'https://picsum.photos/seed/chat$id/100/100',
      'lastMessage': _mockLastMessages[rng.nextInt(_mockLastMessages.length)],
      'time': _mockTimes[rng.nextInt(_mockTimes.length)],
      'unread': rng.nextInt(5),
      'conversationId': null,
    };
  }).toList();
}

/// 模擬聊天列表（未登入 Firebase 時；預設視為男性，顯示 10 位女性示範）
List<Map<String, dynamic>> getMockChatList() {
  return getRandomOppositeSexChatList(myGender: 'male');
}
