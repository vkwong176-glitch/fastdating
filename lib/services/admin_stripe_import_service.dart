import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

/// Cloud Function [adminStripeImportPriceIds]：依網站標價（HKD＋週期）配對 Stripe Price ID。
abstract final class AdminStripeImportService {
  static const String _region = 'us-central1';

  static FirebaseFunctions get _fn =>
      FirebaseFunctions.instanceFor(region: _region);

  /// 使用伺服器端 Stripe Secret 列出啟用中的 Price 並自動配對。
  static Future<StripePriceImportResult> fetchFromStripe(String pin) async {
    final c = _fn.httpsCallable('adminStripeImportPriceIds');
    final res = await c.call(<String, dynamic>{
      'action': 'fetch',
      'pin': pin.trim(),
    });
    return StripePriceImportResult.fromData(res.data);
  }

  /// 貼上 Stripe API 回傳的 JSON（含 `data` 陣列或價格陣列），由伺服器配對。
  static Future<StripePriceImportResult> matchPastedJson(
    String pin,
    Object pricesPayload,
  ) async {
    final c = _fn.httpsCallable('adminStripeImportPriceIds');
    final res = await c.call(<String, dynamic>{
      'action': 'match',
      'pin': pin.trim(),
      'prices': pricesPayload,
    });
    return StripePriceImportResult.fromData(res.data);
  }
}

class StripePriceImportResult {
  const StripePriceImportResult({
    required this.matches,
    required this.unmatchedSiteKeys,
    required this.notes,
    required this.strayStripePrices,
  });

  final Map<String, String> matches;
  final List<String> unmatchedSiteKeys;
  final List<String> notes;
  final List<StrayStripePrice> strayStripePrices;

  static StripePriceImportResult fromData(Object? data) {
    if (data is! Map) {
      return const StripePriceImportResult(
        matches: {},
        unmatchedSiteKeys: [],
        notes: [],
        strayStripePrices: [],
      );
    }
    final m = data['matches'];
    final matches = <String, String>{};
    if (m is Map) {
      for (final e in m.entries) {
        final id = e.value?.toString() ?? '';
        if (id.isNotEmpty) matches[e.key.toString()] = id;
      }
    }
    final u = data['unmatchedSiteKeys'];
    final unmatchedSiteKeys = <String>[];
    if (u is List) {
      for (final x in u) {
        final s = x?.toString() ?? '';
        if (s.isNotEmpty) unmatchedSiteKeys.add(s);
      }
    }
    final n = data['notes'];
    final notes = <String>[];
    if (n is List) {
      for (final x in n) {
        final s = x?.toString() ?? '';
        if (s.isNotEmpty) notes.add(s);
      }
    }
    final stray = data['strayStripePrices'];
    final strayStripePrices = <StrayStripePrice>[];
    if (stray is List) {
      for (final raw in stray) {
        if (raw is Map) {
          strayStripePrices.add(StrayStripePrice(
            id: '${raw['id'] ?? ''}',
            cents: raw['cents'] is num ? (raw['cents'] as num).toInt() : null,
            months: raw['months'] is num ? (raw['months'] as num).toInt() : null,
            currency: '${raw['currency'] ?? ''}',
          ));
        }
      }
    }
    return StripePriceImportResult(
      matches: matches,
      unmatchedSiteKeys: unmatchedSiteKeys,
      notes: notes,
      strayStripePrices: strayStripePrices,
    );
  }

  String summaryLine() {
    final n = matches.length;
    final miss = unmatchedSiteKeys.length;
    return '已配對 $n 個欄位；尚有 $miss 個網站方案未找到對應 Price';
  }
}

class StrayStripePrice {
  const StrayStripePrice({
    required this.id,
    required this.cents,
    required this.months,
    required this.currency,
  });

  final String id;
  final int? cents;
  final int? months;
  final String currency;

  @override
  String toString() {
    final hk = cents != null ? '${cents! / 100} HKD' : '?';
    final mo = months != null ? '${months}m' : '?';
    return '$id · $hk · $mo · $currency';
  }
}

/// 從貼上的文字解析出 Stripe Price 陣列（支援整段 API JSON）。
List<dynamic>? extractPricesArrayFromPaste(String text) {
  final t = text.trim();
  if (t.isEmpty) return null;
  try {
    final decoded = _decodeJsonLenient(t);
    return _coerceToPriceList(decoded);
  } catch (e, st) {
    debugPrint('extractPricesArrayFromPaste: $e\n$st');
    return null;
  }
}

dynamic _decodeJsonLenient(String t) {
  final startObj = t.indexOf('{');
  final startArr = t.indexOf('[');
  int start = -1;
  if (startObj >= 0 && startArr >= 0) {
    start = startObj < startArr ? startObj : startArr;
  } else if (startObj >= 0) {
    start = startObj;
  } else if (startArr >= 0) {
    start = startArr;
  } else {
    throw FormatException('找不到 JSON 開頭');
  }
  var slice = t.substring(start);
  if (slice.startsWith('{')) {
    final end = slice.lastIndexOf('}');
    if (end > 0) slice = slice.substring(0, end + 1);
  } else if (slice.startsWith('[')) {
    final end = slice.lastIndexOf(']');
    if (end > 0) slice = slice.substring(0, end + 1);
  }
  return jsonDecode(slice);
}

List<dynamic>? _coerceToPriceList(dynamic decoded) {
  if (decoded is List) {
    if (decoded.isEmpty) return decoded;
    final first = decoded.first;
    if (first is Map && first['object'] == 'price') return decoded;
    final out = <dynamic>[];
    for (final x in decoded) {
      if (x is Map && x['object'] == 'price') out.add(x);
    }
    if (out.isNotEmpty) return out;
    return decoded;
  }
  if (decoded is Map) {
    final data = decoded['data'];
    if (data is List) return _coerceToPriceList(data);
  }
  return null;
}
