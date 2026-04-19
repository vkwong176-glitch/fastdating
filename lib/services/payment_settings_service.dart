import 'package:cloud_firestore/cloud_firestore.dart';

import 'firebase_bootstrap.dart';
import 'firestore_paths.dart';
import '../utils/constants.dart';

/// 後台 `payment_settings/default` 與會員端讀取一致；未建立文件時視為全部開啟。
class PaymentSettingsSnapshot {
  const PaymentSettingsSnapshot({
    required this.enableIap,
    required this.enableManual,
    this.manualPaymentFpsId,
    this.manualPaymentBankAccountLine,
    this.manualPaymentAccountName,
    this.manualPaymentAccountNo,
    this.manualPaymentReceiptHint,
    this.manualPaymentWhatsappDigits,
  });

  final bool enableIap;
  final bool enableManual;

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

  static String _scalarToString(dynamic val) {
    if (val == null) return '';
    if (val is String) return val;
    if (val is num || val is bool) return val.toString();
    try {
      return val.toString();
    } catch (_) {
      return '';
    }
  }

  static PaymentSettingsSnapshot fromMap(Map<String, dynamic>? m) {
    return PaymentSettingsSnapshot(
      enableIap: _boolField(m, 'enableIap'),
      enableManual: _boolField(m, 'enableManual'),
      manualPaymentFpsId: _scalarToString(m?['manualPaymentFpsId']),
      manualPaymentBankAccountLine:
          _scalarToString(m?['manualPaymentBankAccountLine']),
      manualPaymentAccountName: _scalarToString(m?['manualPaymentAccountName']),
      manualPaymentAccountNo: _scalarToString(m?['manualPaymentAccountNo']),
      manualPaymentReceiptHint:
          _scalarToString(m?['manualPaymentReceiptHint']),
      manualPaymentWhatsappDigits:
          _scalarToString(m?['manualPaymentWhatsappDigits']),
    );
  }

  static const PaymentSettingsSnapshot defaults = PaymentSettingsSnapshot(
    enableIap: true,
    enableManual: true,
    manualPaymentFpsId: null,
    manualPaymentBankAccountLine: null,
    manualPaymentAccountName: null,
    manualPaymentAccountNo: null,
    manualPaymentReceiptHint: null,
    manualPaymentWhatsappDigits: null,
  );

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
