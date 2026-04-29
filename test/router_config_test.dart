import 'package:flutter_test/flutter_test.dart';

import 'package:fastdating/router/app_router.dart';

/// 若任一路徑少 [GoRoute.builder]／[pageBuilder]／[redirect]，載入 [appRouter] 時就會 assert。
void main() {
  test('GoRouter 設定可載入（go_router 父層須有 builder 等）', () {
    // 僅引用 [appRouter] 即會執行 [GoRoute] 建構子；有誤則在載入階段 assert。
    expect(appRouter, isNotNull);
  });
}
