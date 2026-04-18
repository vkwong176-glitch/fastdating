/// 避免 [AuthProvider] ↔ [GoRouter] 循環引用：由 [main] 在建立路由後注入。
void Function(String location)? navigateToLocation;

void navigateToMain() => navigateToLocation?.call('/main');

void navigateToLogin() => navigateToLocation?.call('/login');
