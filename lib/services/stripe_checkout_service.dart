import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../firebase_options.dart';
import 'firebase_bootstrap.dart';

/// 呼叫 Cloud Function [createStripeCheckout]，取得 Stripe Checkout URL 並開啟瀏覽器／外開。
abstract final class StripeCheckoutService {
  static const String _region = 'us-central1';

  static FirebaseFunctions get _fn {
    return FirebaseFunctions.instanceFor(region: _region);
  }

  static Uri _cloudFunctionEndpoint() {
    final pid = DefaultFirebaseOptions.web.projectId;
    return Uri.parse(
      'https://$_region-$pid.cloudfunctions.net/createStripeCheckoutHttp',
    );
  }

  static Uri _verifyCloudFunctionEndpoint() {
    final pid = DefaultFirebaseOptions.web.projectId;
    return Uri.parse(
      'https://$_region-$pid.cloudfunctions.net/verifyStripeOrderPaymentHttp',
    );
  }

  static List<Uri> _httpEndpoints() {
    final host = Uri.base.host;
    if (host == 'localhost' || host == '127.0.0.1') {
      return <Uri>[_cloudFunctionEndpoint()];
    }
    return <Uri>[
      Uri.parse('${Uri.base.origin}/api/stripe/checkout'),
      _cloudFunctionEndpoint(),
    ];
  }

  static List<Uri> _verifyHttpEndpoints() {
    final host = Uri.base.host;
    if (host == 'localhost' || host == '127.0.0.1') {
      return <Uri>[_verifyCloudFunctionEndpoint()];
    }
    return <Uri>[
      Uri.parse('${Uri.base.origin}/api/stripe/verify'),
      _verifyCloudFunctionEndpoint(),
    ];
  }

  static bool _looksLikeHtmlError(String body) {
    final b = body.toLowerCase();
    return b.contains('<!doctype html') ||
        b.contains('<html') ||
        b.contains('cannot post');
  }

  static dynamic _decodeJsonBody(String body) {
    try {
      return body.isEmpty ? null : jsonDecode(body);
    } catch (_) {
      return null;
    }
  }

  static Future<String?> _createViaHttp(String orderId) async {
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
        body: jsonEncode(<String, dynamic>{'orderId': orderId}),
      );
      final raw = _decodeJsonBody(res.body);
      if (res.statusCode == 200 && raw is Map) {
        final url = raw['url'];
        if (url is String && url.isNotEmpty) return url;
        lastError = StateError('伺服器未回傳付款連結');
      } else if (raw is Map) {
        lastError = StateError('${raw['message'] ?? raw['error'] ?? res.body}');
      } else {
        lastError = StateError(res.body);
      }
      final canRetry = endpoint != endpoints.last &&
          (res.statusCode == 404 || _looksLikeHtmlError(res.body));
      if (!canRetry) break;
    }
    throw (lastError ?? StateError('無法建立 Stripe Checkout'));
  }

  static Future<bool> _verifyViaHttp(
    String orderId, {
    String? sessionId,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('必須先登入');
    }
    final token = await user.getIdToken();
    Object? lastError;
    final endpoints = _verifyHttpEndpoints();
    for (final endpoint in endpoints) {
      final res = await http.post(
        endpoint,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(<String, dynamic>{
          'orderId': orderId,
          if (sessionId != null && sessionId.trim().isNotEmpty)
            'sessionId': sessionId.trim(),
        }),
      );
      final raw = _decodeJsonBody(res.body);
      if (res.statusCode == 200 && raw is Map) {
        return raw['paid'] == true || raw['status'] == 'paid_stripe';
      } else if (raw is Map) {
        lastError = StateError('${raw['message'] ?? raw['error'] ?? res.body}');
      } else {
        lastError = StateError(res.body);
      }
      final canRetry = endpoint != endpoints.last &&
          (res.statusCode == 404 || _looksLikeHtmlError(res.body));
      if (!canRetry) break;
    }
    throw (lastError ?? StateError('無法核實 Stripe 付款'));
  }

  /// 回傳 Checkout Session URL；失敗時拋出或回 null。
  static Future<String?> createCheckoutSessionUrl(String orderId) async {
    if (!FirebaseBootstrap.isReady) {
      debugPrint('StripeCheckoutService: Firebase not ready');
      return null;
    }
    final trimmed = orderId.trim();
    if (trimmed.isEmpty) return null;

    try {
      if (kIsWeb) {
        return await _createViaHttp(trimmed);
      }
      final callable = _fn.httpsCallable('createStripeCheckout');
      final result = await callable.call(<String, dynamic>{'orderId': trimmed});
      final data = result.data;
      if (data is Map) {
        final url = data['url'];
        if (url is String && url.isNotEmpty) return url;
      }
      debugPrint('StripeCheckoutService: unexpected response $data');
      return null;
    } on FirebaseFunctionsException catch (e, st) {
      debugPrint('StripeCheckoutService: ${e.code} ${e.message}\n$st');
      rethrow;
    } catch (e, st) {
      debugPrint('StripeCheckoutService: $e\n$st');
      rethrow;
    }
  }

  static Future<bool> verifyCheckoutSuccess(
    String orderId, {
    String? sessionId,
  }) async {
    if (!FirebaseBootstrap.isReady) return false;
    final trimmed = orderId.trim();
    if (trimmed.isEmpty) return false;

    try {
      if (kIsWeb) {
        return await _verifyViaHttp(trimmed, sessionId: sessionId);
      }
      final callable = _fn.httpsCallable('verifyStripeOrderPayment');
      final result = await callable.call(<String, dynamic>{
        'orderId': trimmed,
        if (sessionId != null && sessionId.trim().isNotEmpty)
          'sessionId': sessionId.trim(),
      });
      final data = result.data;
      if (data is Map) {
        return data['paid'] == true || data['status'] == 'paid_stripe';
      }
      return false;
    } on FirebaseFunctionsException catch (e, st) {
      debugPrint('StripeCheckoutService verify: ${e.code} ${e.message}\n$st');
      rethrow;
    } catch (e, st) {
      debugPrint('StripeCheckoutService verify: $e\n$st');
      rethrow;
    }
  }

  static Future<bool> launchCheckoutUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return true;
    }
    return false;
  }
}
