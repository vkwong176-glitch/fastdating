import 'dart:convert';

import 'package:http/browser_client.dart';
/// Web：呼叫 Hosting 同網域 `/api/auth/*`，由 Cloud Functions 下發 HttpOnly Session Cookie
Future<void> syncAuthSessionCookie(String idToken) async {
  final origin = Uri.base.origin;
  final uri = Uri.parse('$origin/api/auth/session');
  final client = BrowserClient();
  try {
    final res = await client.post(
      uri,
      headers: const {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode({'idToken': idToken}),
    );
    if (res.statusCode != 200) {
      throw Exception('session cookie HTTP ${res.statusCode}');
    }
  } finally {
    client.close();
  }
}

Future<void> clearAuthSessionCookie() async {
  final origin = Uri.base.origin;
  final uri = Uri.parse('$origin/api/auth/session/clear');
  final client = BrowserClient();
  try {
    final res = await client.post(
      uri,
      headers: const {'Content-Type': 'application/json'},
    );
    if (res.statusCode != 200) {
      throw Exception('clear session HTTP ${res.statusCode}');
    }
  } finally {
    client.close();
  }
}
