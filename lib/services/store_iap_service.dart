import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

/// 使用者於系統付款面板取消購買
class StorePurchaseCanceled implements Exception {
  @override
  String toString() => '已取消購買';
}

/// App Store IAP（iOS）與 Google Play Billing（Android）共用封裝。
///
/// Web 不支援內購；請在 UI 層改走 Stripe／網頁或僅示範。
class StoreIapService {
  StoreIapService._();
  static final StoreIapService instance = StoreIapService._();

  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _sub;
  bool _listenerReady = false;

  Completer<PurchaseDetails>? _pending;
  String? _pendingProductId;

  bool get supportedOnThisPlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);

  /// 註冊購買結果串流（可重複呼叫，僅第一次生效）
  Future<void> ensureListener() async {
    if (!supportedOnThisPlatform || _listenerReady) return;
    _listenerReady = true;
    _sub = _iap.purchaseStream.listen(
      _onPurchaseUpdate,
      onError: (Object e, StackTrace st) {
        _pending?.completeError(e, st);
        _clearPending();
      },
    );
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
    _listenerReady = false;
    _clearPending();
  }

  Future<bool> isAvailable() async {
    if (!supportedOnThisPlatform) return false;
    return _iap.isAvailable();
  }

  Future<ProductDetailsResponse> queryProducts(Set<String> ids) =>
      _iap.queryProductDetails(ids);

  /// 訂閱與非消耗型內購在 Flutter 外掛中皆透過 [InAppPurchase.buyNonConsumable]。
  Future<PurchaseDetails> buy(ProductDetails product) async {
    if (!supportedOnThisPlatform) {
      throw UnsupportedError('內購僅適用於 iOS / Android');
    }
    await ensureListener();
    final completer = Completer<PurchaseDetails>();
    _pending = completer;
    _pendingProductId = product.id;

    final started = await _iap.buyNonConsumable(
      purchaseParam: PurchaseParam(productDetails: product),
    );
    if (!started) {
      _clearPending();
      throw StateError('無法開啟商店付款流程');
    }

    return completer.future.timeout(
      const Duration(minutes: 5),
      onTimeout: () {
        _clearPending();
        throw TimeoutException('購買逾時');
      },
    );
  }

  /// 交付權益後務必呼叫，否則訂單會維持未確認狀態（Android 尤其重要）。
  Future<void> completePurchase(PurchaseDetails p) async {
    if (p.pendingCompletePurchase) {
      await _iap.completePurchase(p);
    }
  }

  void _clearPending() {
    _pending = null;
    _pendingProductId = null;
  }

  Future<void> _onPurchaseUpdate(List<PurchaseDetails> purchases) async {
    for (final p in purchases) {
      if (p.status == PurchaseStatus.pending) continue;

      final matchesPending =
          _pendingProductId != null && p.productID == _pendingProductId;

      if (matchesPending) {
        switch (p.status) {
          case PurchaseStatus.error:
            _pending?.completeError(
              p.error ?? Exception('purchase error'),
            );
            _clearPending();
            break;
          case PurchaseStatus.canceled:
            _pending?.completeError(StorePurchaseCanceled());
            _clearPending();
            break;
          case PurchaseStatus.purchased:
          case PurchaseStatus.restored:
            _pending?.complete(p);
            _clearPending();
            break;
          case PurchaseStatus.pending:
            break;
        }
        continue;
      }

      // 非本次流程的舊訂單／還原：僅完成商店端掛帳，避免卡住佇列
      if (p.pendingCompletePurchase) {
        await _iap.completePurchase(p);
      }
    }
  }
}
