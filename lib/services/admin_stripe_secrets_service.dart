import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../firebase_options.dart';

/// 讀寫 Firestore [payment_settings/private_stripe]（需 PIN）。
/// Web：經 Hosting `/api/admin/stripe-secrets`（純 JSON 字串），避免 Callable 回傳觸發 dart2js Int64。
/// 其他平台：Callable [adminStripeSecrets]。
abstract final class AdminStripeSecretsService {
  static const String _region = 'us-central1';

  static FirebaseFunctions get _fn =>
      FirebaseFunctions.instanceFor(region: _region);

  /// 正式站先走 Hosting 同網域；若 rewrite 尚未生效，fallback 直連 Cloud Function。
  static Uri _cloudFunctionEndpoint() {
    final pid = DefaultFirebaseOptions.web.projectId;
    return Uri.parse(
      'https://$_region-$pid.cloudfunctions.net/adminStripeSecretsHttp',
    );
  }

  static List<Uri> _httpEndpoints() {
    final host = Uri.base.host;
    if (host == 'localhost' || host == '127.0.0.1') {
      return <Uri>[_cloudFunctionEndpoint()];
    }
    return <Uri>[
      Uri.parse('${Uri.base.origin}/api/admin/stripe-secrets'),
      _cloudFunctionEndpoint(),
    ];
  }

  static bool _looksLikeHtmlError(String body) {
    final b = body.toLowerCase();
    return b.contains('<!doctype html') ||
        b.contains('<html') ||
        b.contains('cannot post');
  }

  static Future<Map<String, String>> _fetchViaHttp(String pin) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return {'stripeSecretKey': '', 'stripeWebhookSecret': ''};
    }
    final token = await user.getIdToken();
    Object? lastError;
    final endpoints = _httpEndpoints();
    for (final endpoint in endpoints) {
      final res = await http.post(
        endpoint,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(<String, dynamic>{
          'action': 'get',
          'pin': pin.trim(),
        }),
      );
      final dynamic raw = _decodeJsonBody(res.body);
      if (raw is! Map) {
        lastError = StateError(
          res.statusCode == 200 ? '伺服器回應異常' : res.body,
        );
      } else {
        final m = raw.cast<String, dynamic>();
        if (res.statusCode == 200) {
          return {
            'stripeSecretKey': '${m['stripeSecretKey'] ?? ''}',
            'stripeWebhookSecret': '${m['stripeWebhookSecret'] ?? ''}',
          };
        }
        lastError = StateError('${m['message'] ?? m['error'] ?? res.body}');
      }
      final canRetry = endpoint != endpoints.last &&
          (res.statusCode == 404 || _looksLikeHtmlError(res.body));
      if (!canRetry) break;
    }
    throw (lastError ?? StateError('無法讀取 Stripe 私密金鑰'));
  }

  static Future<void> _saveViaHttp(
    String pin, {
    required String secretKey,
    required String webhookSecret,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('必須先登入');
    }
    final token = await user.getIdToken();
    Object? lastError;
    final endpoints = _httpEndpoints();
    for (final endpoint in endpoints) {
      final res = await http.post(
        endpoint,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(<String, dynamic>{
          'action': 'set',
          'pin': pin.trim(),
          'stripeSecretKey': secretKey.trim(),
          'stripeWebhookSecret': webhookSecret.trim(),
        }),
      );
      if (res.statusCode == 200) {
        return;
      }
      final raw = _decodeJsonBody(res.body);
      final msg = raw is Map
          ? '${raw['message'] ?? raw['error'] ?? res.body}'
          : res.body;
      lastError = StateError(msg);
      final canRetry = endpoint != endpoints.last &&
          (res.statusCode == 404 || _looksLikeHtmlError(res.body));
      if (!canRetry) break;
    }
    throw (lastError ?? StateError('無法儲存 Stripe 私密金鑰'));
  }

  static dynamic _decodeJsonBody(String body) {
    try {
      return jsonDecode(body);
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, String>> fetchPrivate(String pin) async {
    final trimmed = pin.trim();
    if (trimmed.isEmpty) {
      return {'stripeSecretKey': '', 'stripeWebhookSecret': ''};
    }
    if (kIsWeb) {
      try {
        return await _fetchViaHttp(trimmed);
      } catch (e, st) {
        debugPrint('AdminStripeSecretsService.fetchPrivate (http): $e\n$st');
        rethrow;
      }
    }
    try {
      final c = _fn.httpsCallable('adminStripeSecrets');
      final res = await c.call(<String, dynamic>{
        'action': 'get',
        'pin': trimmed,
      });
      final d = res.data;
      if (d is! Map) return {'stripeSecretKey': '', 'stripeWebhookSecret': ''};
      return {
        'stripeSecretKey': '${d['stripeSecretKey'] ?? ''}',
        'stripeWebhookSecret': '${d['stripeWebhookSecret'] ?? ''}',
      };
    } on FirebaseFunctionsException catch (e, st) {
      debugPrint('AdminStripeSecretsService.fetchPrivate: $e\n$st');
      rethrow;
    }
  }

  static Future<void> savePrivate(
    String pin, {
    required String secretKey,
    required String webhookSecret,
  }) async {
    if (kIsWeb) {
      await _saveViaHttp(
        pin,
        secretKey: secretKey,
        webhookSecret: webhookSecret,
      );
      return;
    }
    final c = _fn.httpsCallable('adminStripeSecrets');
    await c.call(<String, dynamic>{
      'action': 'set',
      'pin': pin.trim(),
      'stripeSecretKey': secretKey.trim(),
      'stripeWebhookSecret': webhookSecret.trim(),
    });
  }
}
