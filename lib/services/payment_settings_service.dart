import 'package:cloud_firestore/cloud_firestore.dart';

import 'firebase_bootstrap.dart';
import 'firestore_paths.dart';
import '../utils/constants.dart';

/// 後台 `payment_settings/default` 與會員端讀取一致；未建立文件時視為全部開啟。
class PaymentSettingsSnapshot {
  const PaymentSettingsSnapshot({
    required this.enableIap,
    required this.enableStripe,
    required this.enableManual,
    this.stripePublishableKey,
    this.stripePriceIds,
    this.stripeCheckoutUrls,
    this.manualPaymentFpsId,
    this.manualPaymentBankAccountLine,
    this.manualPaymentAccountName,
    this.manualPaymentAccountNo,
    this.manualPaymentReceiptHint,
    this.manualPaymentWhatsappDigits,
  });

  final bool enableIap;
  final bool enableStripe;
  final bool enableManual;

  /// 僅供 Web 若日後嵌入 Stripe.js；Checkout 跳轉主要由 Callable 處理。
  final String? stripePublishableKey;

  /// Stripe Dashboard 各 Price ID，key 與 Cloud Functions [priceMapKeyFromOrder] 一致。
  final Map<String, String>? stripePriceIds;

  /// 各付款分頁／場景可獨立設定固定 Stripe URL（例如 Payment Link）。
  final Map<String, String>? stripeCheckoutUrls;

  /// 手動付款顯示資料（FPS／WeChat／銀行轉帳）。
  final String? manualPaymentFpsId;
  final String? manualPaymentBankAccountLine;
  final String? manualPaymentAccountName;
  final String? manualPaymentAccountNo;
  final String? manualPaymentReceiptHint;
  final String? manualPaymentWhatsappDigits;

  static bool _boolField(Map<String, dynamic>? m, String key,
      {bool defaultValue = true}) {
    final v = m?[key];
    if (v is bool) return v;
    return defaultValue;
  }

  /// 供後台讀取單一 Stripe 字串欄位（與 [fromMap] 相同規則，避免 Web Int64）。
  static String readStripeString(Map<String, dynamic>? map, String key) =>
      _stripeScalarToString(map?[key]);

  /// Web（dart2js）上部分 Firestore 標量不適合直接 `.toString()`（例如內部 Int64）；Stripe 欄位一律轉成純字串。
  static String _stripeScalarToString(dynamic val) {
    if (val == null) return '';
    if (val is String) return val;
    if (val is num || val is bool) return val.toString();
    try {
      return val.toString();
    } catch (_) {
      return '';
    }
  }

  static Map<String, String>? _stringMapField(
    Map<String, dynamic>? m,
    String key,
  ) {
    final raw = m?[key];
    if (raw is! Map) return null;
    final out = <String, String>{};
    for (final e in raw.entries) {
      final k = e.key.toString();
      final s = _stripeScalarToString(e.value);
      if (s.isNotEmpty) {
        out[k] = s;
      }
    }
    return out.isEmpty ? null : out;
  }

  static PaymentSettingsSnapshot fromMap(Map<String, dynamic>? m) {
    final ids = _stringMapField(m, 'stripePriceIds');
    final urls = _stringMapField(m, 'stripeCheckoutUrls');
    final pk = _stripeScalarToString(m?['stripePublishableKey']);
    return PaymentSettingsSnapshot(
      enableIap: _boolField(m, 'enableIap'),
      enableStripe: _boolField(m, 'enableStripe', defaultValue: false),
      enableManual: _boolField(m, 'enableManual'),
      stripePublishableKey: pk.isEmpty ? null : pk,
      stripePriceIds: ids,
      stripeCheckoutUrls: urls,
      manualPaymentFpsId: _stripeScalarToString(m?['manualPaymentFpsId']),
      manualPaymentBankAccountLine:
          _stripeScalarToString(m?['manualPaymentBankAccountLine']),
      manualPaymentAccountName:
          _stripeScalarToString(m?['manualPaymentAccountName']),
      manualPaymentAccountNo:
          _stripeScalarToString(m?['manualPaymentAccountNo']),
      manualPaymentReceiptHint:
          _stripeScalarToString(m?['manualPaymentReceiptHint']),
      manualPaymentWhatsappDigits:
          _stripeScalarToString(m?['manualPaymentWhatsappDigits']),
    );
  }

  static final PaymentSettingsSnapshot defaults = PaymentSettingsSnapshot(
    enableIap: true,
    enableStripe: false,
    enableManual: true,
    stripePublishableKey: null,
    stripePriceIds: null,
    stripeCheckoutUrls: null,
    manualPaymentFpsId: null,
    manualPaymentBankAccountLine: null,
    manualPaymentAccountName: null,
    manualPaymentAccountNo: null,
    manualPaymentReceiptHint: null,
    manualPaymentWhatsappDigits: null,
  );

  String? stripeCheckoutUrlForKey(String key) {
    final raw = stripeCheckoutUrls?[key]?.trim();
    if (raw == null || raw.isEmpty) return null;
    return raw;
  }

  static String _stringOrFallback(String? raw, String fallback) {
    final v = raw?.trim() ?? '';
    return v.isEmpty ? fallback : v;
  }

  String get resolvedManualPaymentFpsId =>
      _stringOrFallback(manualPaymentFpsId, AppConstants.manualPaymentFpsId);

  String get resolvedManualPaymentBankAccountLine => _stringOrFallback(
        manualPaymentBankAccountLine,
        AppConstants.manualPaymentBankLineEn1,
      );

  String get resolvedManualPaymentAccountName => _stringOrFallback(
        manualPaymentAccountName,
        AppConstants.manualPaymentAccountNameValue,
      );

  String get resolvedManualPaymentAccountNo => _stringOrFallback(
        manualPaymentAccountNo,
        AppConstants.manualPaymentBankLineEn3.replaceFirst('Account No: ', ''),
      );

  String get resolvedManualPaymentReceiptHint => _stringOrFallback(
        manualPaymentReceiptHint,
        '請轉賬後按下面WhatsApp上傳收據圖片～',
      );

  String get resolvedManualPaymentWhatsappDigits {
    final raw = _stringOrFallback(
      manualPaymentWhatsappDigits,
      AppConstants.subscriptionReceiptWhatsAppDigits,
    );
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    return digits.isEmpty
        ? AppConstants.subscriptionReceiptWhatsAppDigits
        : digits;
  }
}

/// 讀取 [FirestorePaths.paymentSettings]／[FirestorePaths.paymentSettingsDefaultDoc]。
abstract final class PaymentSettingsService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static Stream<PaymentSettingsSnapshot> watchDefault() {
    if (!FirebaseBootstrap.isReady) {
      return Stream<PaymentSettingsSnapshot>.value(
          PaymentSettingsSnapshot.defaults);
    }
    return _db
        .collection(FirestorePaths.paymentSettings)
        .doc(FirestorePaths.paymentSettingsDefaultDoc)
        .snapshots()
        .map((snap) {
      if (!snap.exists || snap.data() == null) {
        return PaymentSettingsSnapshot.defaults;
      }
      return PaymentSettingsSnapshot.fromMap(snap.data());
    });
  }

  static Future<PaymentSettingsSnapshot> getDefault() async {
    if (!FirebaseBootstrap.isReady) return PaymentSettingsSnapshot.defaults;
    final snap = await _db
        .collection(FirestorePaths.paymentSettings)
        .doc(FirestorePaths.paymentSettingsDefaultDoc)
        .get();
    if (!snap.exists || snap.data() == null) {
      return PaymentSettingsSnapshot.defaults;
    }
    return PaymentSettingsSnapshot.fromMap(snap.data());
  }
}
