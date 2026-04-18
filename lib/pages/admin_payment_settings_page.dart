import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../providers/language_provider.dart';

import '../services/admin_stripe_secrets_service.dart';
import '../services/firestore_paths.dart';
import '../services/payment_settings_service.dart';
import '../utils/constants.dart';
import '../utils/stripe_admin_price_labels.dart';

/// 管理後台 H：付款方式設定（開關、Stripe 金鑰與 Price ID、儲存至 Firestore／Callable）
class AdminSectionHPage extends StatefulWidget {
  const AdminSectionHPage({super.key});

  @override
  State<AdminSectionHPage> createState() => _AdminSectionHPageState();
}

class _AdminSectionHPageState extends State<AdminSectionHPage> {
  static const List<String> _months = ['1', '3', '6', '12'];
  static const Map<String, String> _stripeCheckoutUrlLabels = {
    'subscription_ad': '訂閱方案：移除所有廣告',
    'subscription_fd1': '訂閱方案：Fast Dating 1',
    'subscription_fd2': '訂閱方案：Fast Dating 2',
    'subscription_fd3': '訂閱方案：Fast Dating 3',
    'subscription_fd4': '訂閱方案：Fast Dating 4',
    'subscription_fd5': '訂閱方案：Fast Dating 5',
    'subscription_fd6': '訂閱方案：Fast Dating 6',
    'ad_partner': '廣告合作頁',
    'activity_registration': '活動報名頁',
  };

  static List<String> get _allPriceKeys {
    final out = <String>[];
    for (final m in _months) {
      out.add('ad_${m}m');
    }
    for (var tier = 1; tier <= 6; tier++) {
      for (final m in _months) {
        out.add('fd${tier}_${m}m');
      }
    }
    for (final m in _months) {
      out.add('adpost_${m}m');
    }
    return out;
  }

  final TextEditingController _pinCtrl = TextEditingController();
  final TextEditingController _publishableCtrl = TextEditingController();
  final TextEditingController _secretCtrl = TextEditingController();
  final TextEditingController _webhookSecretCtrl = TextEditingController();
  final TextEditingController _universalActivityPriceCtrl =
      TextEditingController();
  final TextEditingController _manualFpsCtrl = TextEditingController();
  final TextEditingController _manualBankAccountLineCtrl =
      TextEditingController();
  final TextEditingController _manualAccountNameCtrl = TextEditingController();
  final TextEditingController _manualAccountNoCtrl = TextEditingController();
  final TextEditingController _manualReceiptHintCtrl = TextEditingController();
  final TextEditingController _manualWhatsappDigitsCtrl =
      TextEditingController();

  late final Map<String, TextEditingController> _priceCtrls;
  late final Map<String, TextEditingController> _checkoutUrlCtrls;

  bool _enableIap = true;
  bool _enableStripe = true;
  bool _enableManual = true;

  bool _loading = true;
  bool _saving = false;
  bool _loadingSecrets = false;
  String? _loadError;

  /// 最近一次成功儲存且判定 Stripe 可運作（僅畫面狀態）
  bool _stripeUiConnected = false;

  bool _obscureSecret = true;
  bool _obscureWebhook = true;

  /// 勾選表示 sk／whsec 已由 `firebase functions:config:set` 或主機環境變數設定，僅在此頁填 Price ID 即可。
  bool _stripeSecretsFromEnv = false;

  bool get _showStripeControls => false;

  @override
  void initState() {
    super.initState();
    _priceCtrls = {
      for (final k in _allPriceKeys) k: TextEditingController(),
    };
    _checkoutUrlCtrls = {
      for (final k in _stripeCheckoutUrlLabels.keys) k: TextEditingController(),
    };
    unawaited(_reload());
  }

  @override
  void dispose() {
    _pinCtrl.dispose();
    _publishableCtrl.dispose();
    _secretCtrl.dispose();
    _webhookSecretCtrl.dispose();
    _universalActivityPriceCtrl.dispose();
    _manualFpsCtrl.dispose();
    _manualBankAccountLineCtrl.dispose();
    _manualAccountNameCtrl.dispose();
    _manualAccountNoCtrl.dispose();
    _manualReceiptHintCtrl.dispose();
    _manualWhatsappDigitsCtrl.dispose();
    for (final c in _priceCtrls.values) {
      c.dispose();
    }
    for (final c in _checkoutUrlCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Web（dart2js）寫入 [Timestamp]／[FieldValue.serverTimestamp] 可能觸發 Int64；改存 ISO 字串。
  String _paymentDocTimeIsoString() => DateTime.now().toUtc().toIso8601String();

  /// 所有 Stripe 金鑰與 Price ID 一律以純字串寫入 Firestore。
  Map<String, String> _stripePriceIdsMapForSave() {
    final out = <String, String>{};
    for (final e in _priceCtrls.entries) {
      final v = e.value.text.trim();
      if (v.isEmpty) continue;
      out[e.key] = v;
    }
    return out;
  }

  Map<String, String> _stripeCheckoutUrlsMapForSave() {
    final out = <String, String>{};
    for (final e in _checkoutUrlCtrls.entries) {
      final v = e.value.text.trim();
      if (v.isEmpty) continue;
      out[e.key] = v;
    }
    return out;
  }

  /// Stripe Price ID 必須喺 Dashboard 複製嘅完整 ID（例如 `price_1Abc…`），
  /// 唔可以填金額、亦唔可以自拼 `price_50`／`price_300`（Stripe 會報 No such price）。
  static bool _isValidStripePriceId(String raw) {
    final v = raw.trim().replaceFirst(RegExp(r'^\$+'), '').trim();
    if (v.isEmpty) return true;
    if (!v.startsWith('price_')) return false;
    final suffix = v.substring('price_'.length);
    if (suffix.length < 14) return false;
    if (!RegExp(r'^[0-9a-zA-Z]+$').hasMatch(suffix)) return false;
    // 常見誤填：用港幣金額拼出 price_50、price_300 等（後綴全數字）
    if (RegExp(r'^\d+$').hasMatch(suffix)) return false;
    return true;
  }

  /// 回傳 null 表示通過；否則為給管理員睇嘅錯誤說明。
  String? _validateStripePriceIdsBeforeSave() {
    final bad = <String>[];
    for (final e in _priceCtrls.entries) {
      final raw = e.value.text.trim();
      if (raw.isEmpty) continue;
      if (!_isValidStripePriceId(raw)) {
        bad.add('${e.key}（目前：$raw）');
      }
    }
    final act = _universalActivityPriceCtrl.text.trim();
    if (act.isNotEmpty && !_isValidStripePriceId(act)) {
      bad.add('通用活動 Price ID（目前：$act）');
    }
    if (bad.isEmpty) return null;
    final head = bad.take(6).join('\n');
    final tail = bad.length > 6 ? '\n…共 ${bad.length} 個欄位格式錯誤' : '';
    return '以下欄位格式唔啱：請到 Stripe「產品→價格」複製完整 price_…（約廿幾個字元），'
        '唔好用金額自拼 price_50／price_300。\n$head$tail';
  }

  /// Web（dart2js）寫入前以 JSON 往返，確保僅含 JSON 原生型別，避免混入 Timestamp／Int64。
  Map<String, dynamic> _jsonOnlyFirestoreData(Map<String, dynamic> data) {
    return Map<String, dynamic>.from(
      json.decode(json.encode(data)) as Map<dynamic, dynamic>,
    );
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final snap = await FirebaseFirestore.instance
          .collection(FirestorePaths.paymentSettings)
          .doc(FirestorePaths.paymentSettingsDefaultDoc)
          .get();
      final m = snap.data();
      final ps = PaymentSettingsSnapshot.fromMap(m);
      _enableIap = ps.enableIap;
      _enableStripe = ps.enableStripe;
      _enableManual = ps.enableManual;
      _publishableCtrl.text = ps.stripePublishableKey ?? '';
      _universalActivityPriceCtrl.text =
          PaymentSettingsSnapshot.readStripeString(
              m, 'stripeUniversalActivityPriceId');
      _manualFpsCtrl.text = ps.manualPaymentFpsId ?? '';
      _manualBankAccountLineCtrl.text = ps.manualPaymentBankAccountLine ?? '';
      _manualAccountNameCtrl.text = ps.manualPaymentAccountName ?? '';
      _manualAccountNoCtrl.text = ps.manualPaymentAccountNo ?? '';
      _manualReceiptHintCtrl.text = ps.manualPaymentReceiptHint ?? '';
      _manualWhatsappDigitsCtrl.text = ps.manualPaymentWhatsappDigits ?? '';
      _stripeUiConnected = m?['stripeConnected'] == true;
      _stripeSecretsFromEnv = m?['stripeSecretsFromEnv'] == true;

      final ids = ps.stripePriceIds ?? {};
      for (final k in _allPriceKeys) {
        _priceCtrls[k]!.text = ids[k] ?? '';
      }
      final urls = ps.stripeCheckoutUrls ?? {};
      for (final k in _stripeCheckoutUrlLabels.keys) {
        _checkoutUrlCtrls[k]!.text = urls[k] ?? '';
      }
    } catch (e) {
      _loadError = e.toString();
    }
    if (mounted) {
      setState(() => _loading = false);
    }
  }

  Future<void> _loadSecretsFromServer() async {
    final pin = _pinCtrl.text.trim();
    if (pin.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('請先填寫管理員 PIN')),
        );
      }
      return;
    }
    setState(() => _loadingSecrets = true);
    try {
      final map = await AdminStripeSecretsService.fetchPrivate(pin);
      _secretCtrl.text = map['stripeSecretKey'] ?? '';
      _webhookSecretCtrl.text = map['stripeWebhookSecret'] ?? '';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已載入密鑰（僅顯示於此裝置）')),
        );
      }
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message ?? e.code)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('載入失敗：$e')),
        );
      }
    }
    if (mounted) {
      setState(() => _loadingSecrets = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final invalidPriceMsg = _validateStripePriceIdsBeforeSave();
      if (invalidPriceMsg != null) {
        throw StateError(invalidPriceMsg);
      }

      final timeIso = _paymentDocTimeIsoString();
      final manualWhatsappDigits = _manualWhatsappDigitsCtrl.text
          .trim()
          .replaceAll(RegExp(r'[^0-9]'), '');
      final payload = _jsonOnlyFirestoreData(<String, dynamic>{
        'enableIap': _enableIap,
        'enableStripe': false,
        'enableManual': _enableManual,
        'stripePublishableKey': '',
        'stripePriceIds': <String, String>{},
        'stripeCheckoutUrls': <String, String>{},
        'stripeUniversalActivityPriceId': '',
        'manualPaymentFpsId': _manualFpsCtrl.text.trim(),
        'manualPaymentBankAccountLine': _manualBankAccountLineCtrl.text.trim(),
        'manualPaymentAccountName': _manualAccountNameCtrl.text.trim(),
        'manualPaymentAccountNo': _manualAccountNoCtrl.text.trim(),
        'manualPaymentReceiptHint': _manualReceiptHintCtrl.text.trim(),
        'manualPaymentWhatsappDigits': manualWhatsappDigits,
        'stripeSecretsFromEnv': false,
        'updatedAt': timeIso,
        'stripeConnected': false,
        'stripeConnectedAt': '',
      });

      /// 先寫 Firestore（純 JSON），再 Callable；Web 上 Callable 回傳偶發 Int64 問題時，公開欄位仍會存檔。
      await FirebaseFirestore.instance
          .collection(FirestorePaths.paymentSettings)
          .doc(FirestorePaths.paymentSettingsDefaultDoc)
          .set(
            payload,
            SetOptions(merge: true),
          );

      if (mounted) {
        setState(() {
          _enableStripe = false;
          _stripeUiConnected = false;
          _stripeSecretsFromEnv = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('已儲存。Stripe 已完全移除。'),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('儲存失敗：$e')),
        );
      }
    }
    if (mounted) {
      setState(() => _saving = false);
    }
  }

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 8),
        child: Text(t, style: const TextStyle(fontWeight: FontWeight.w700)),
      );

  Widget _field(
    String label,
    TextEditingController c, {
    bool obscure = false,
    String? hint,
    int maxLines = 1,
    String? subtitle,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 13)),
          if (subtitle != null && subtitle.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 11.5,
                height: 1.25,
                color: Colors.grey.shade800,
              ),
            ),
          ],
          const SizedBox(height: 4),
          TextField(
            controller: c,
            obscureText: obscure,
            maxLines: maxLines,
            style: maxLines > 1
                ? const TextStyle(fontFamily: 'monospace', fontSize: 12)
                : null,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              hintText: hint,
            ),
          ),
        ],
      ),
    );
  }

  String? _memberPriceCaption(String key) {
    final line = StripeAdminPriceLabels.captionForKey(key);
    if (line == null || line.isEmpty) return null;
    return '會員端標價：$line';
  }

  Widget _priceGrid(String title, List<String> keys) {
    return ExpansionTile(
      title: Text(title),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Column(
            children: [
              for (final k in keys)
                _field(
                  k,
                  _priceCtrls[k]!,
                  hint: '貼 Dashboard 複製嘅 price_1…（約廿幾字）',
                  subtitle: _memberPriceCaption(k),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _checkoutUrlFields() {
    return Column(
      children: [
        for (final e in _stripeCheckoutUrlLabels.entries)
          _field(
            e.value,
            _checkoutUrlCtrls[e.key]!,
            hint: 'https://checkout.stripe.com/... 或 Stripe Payment Link',
            subtitle: '此場景如有填 URL，會員端會優先直接開啟；留空則改用現有動態 Checkout。',
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<LanguageProvider>(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              context.pop();
            } else {
              context.go('/login');
            }
          },
        ),
        automaticallyImplyLeading: false,
        title: Text(lang.getString('admin_sec_h')),
        backgroundColor: AppConstants.appBarBackground.withValues(alpha: 0.92),
        toolbarHeight: AppConstants.appBarToolbarHeight,
        actions: [
          IconButton(
            tooltip: '重新載入',
            onPressed: _loading ? null : _reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_showStripeControls && _stripeUiConnected)
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.green.shade100,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.green.shade300),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.check_circle,
                              color: Colors.green.shade800),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Stripe 已連線',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                          IconButton(
                            tooltip: '關閉',
                            onPressed: () =>
                                setState(() => _stripeUiConnected = false),
                            icon: const Icon(Icons.close, size: 20),
                          ),
                        ],
                      ),
                    ),
                  if (_loadError != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        _loadError!,
                        style: TextStyle(color: Colors.red.shade800),
                      ),
                    ),
                  _sectionTitle('會員端付款選項'),
                  SwitchListTile(
                    title: const Text('App Store／Google Play'),
                    subtitle: const Text('關閉後會員端不顯示應用程式內購買'),
                    value: _enableIap,
                    onChanged: (v) => setState(() => _enableIap = v),
                  ),
                  SwitchListTile(
                    title: const Text('FPS／WeChat／銀行轉帳'),
                    subtitle: const Text('關閉後不顯示手動轉帳'),
                    value: _enableManual,
                    onChanged: (v) => setState(() => _enableManual = v),
                  ),
                  _sectionTitle('手動付款資料'),
                  _field(
                    'FPS 編號',
                    _manualFpsCtrl,
                    hint: '例如：68789453',
                  ),
                  _field(
                    '銀行資料第一行',
                    _manualBankAccountLineCtrl,
                    hint: '例如：Bank Account: Dah Sing Bank 040',
                  ),
                  _field(
                    'Account Name 戶名',
                    _manualAccountNameCtrl,
                    hint: '例如：VK Sparkle Life LIMITED',
                  ),
                  _field(
                    'Account No 戶口號碼',
                    _manualAccountNoCtrl,
                    hint: '例如：76532813686',
                  ),
                  _field(
                    '收據提示文字',
                    _manualReceiptHintCtrl,
                    hint: '例如：請轉賬後按下面WhatsApp上傳收據圖片～',
                  ),
                  _field(
                    'WhatsApp 號碼（只填數字，含國碼）',
                    _manualWhatsappDigitsCtrl,
                    hint: '例如：85262379385',
                  ),
                  if (_showStripeControls)
                    CheckboxListTile(
                    title: const Text('Secret Key／Webhook Secret 已在伺服器設定'),
                    subtitle: const Text(
                      '勾選後：唔再顯示 PIN／sk／whsec；儲存只寫公開設定與 Price ID（密鑰由 Firebase Functions 設定提供）。',
                    ),
                    value: _stripeSecretsFromEnv,
                    onChanged: (v) =>
                        setState(() => _stripeSecretsFromEnv = v ?? false),
                  ),
                  if (_showStripeControls && !_stripeSecretsFromEnv) ...[
                    _sectionTitle('管理員 PIN（載入／儲存 Secret 用）'),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _pinCtrl,
                            obscureText: true,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              hintText: '與 Functions stripe.settings_pin 相同',
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.tonal(
                          onPressed:
                              _loadingSecrets ? null : _loadSecretsFromServer,
                          child: _loadingSecrets
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text('載入密鑰'),
                        ),
                      ],
                    ),
                  ] else if (_showStripeControls) ...[
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        '目前密鑰由伺服器提供，無需填寫下方 Secret／Webhook；'
                        '只需填 Publishable Key 與訂閱 Price ID 後即可儲存。',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.35,
                          color: Colors.grey.shade800,
                        ),
                      ),
                    ),
                  ],
                  if (_showStripeControls) ...[
                    _sectionTitle('Stripe API 金鑰'),
                    _field(
                      'Stripe Publishable Key（pk_...）',
                      _publishableCtrl,
                      hint: 'pk_live_... 或 pk_test_...',
                    ),
                    if (!_stripeSecretsFromEnv) ...[
                      _field(
                        'Stripe Secret Key（sk_...）',
                        _secretCtrl,
                        obscure: _obscureSecret,
                        hint: 'sk_live_... 或 sk_test_...',
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () =>
                              setState(() => _obscureSecret = !_obscureSecret),
                          child: Text(_obscureSecret ? '顯示' : '隱藏'),
                        ),
                      ),
                      _field(
                        'Webhook Signing Secret（whsec_...）',
                        _webhookSecretCtrl,
                        obscure: _obscureWebhook,
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () =>
                              setState(() => _obscureWebhook = !_obscureWebhook),
                          child: Text(_obscureWebhook ? '顯示' : '隱藏'),
                        ),
                      ),
                    ],
                    _sectionTitle('活動／通用'),
                    _field(
                      '通用活動 Price ID（選填）',
                      _universalActivityPriceCtrl,
                      hint: 'price_...（報表用；結帳金額仍以訂單為準）',
                    ),
                    const Text(
                      '說明：活動報名預設以訂單金額動態建立 Checkout（price_data）。'
                      '若填此欄，僅寫入中繼資料供對帳，不強制改結帳邏輯。',
                      style: TextStyle(fontSize: 12),
                    ),
                    _sectionTitle('訂閱與廣告 Price ID（price_...）'),
                    const Text(
                      '各欄下方為會員端標價（與 App／網站訂閱及廣告刊登方案一致）；請填入 Stripe Dashboard 複製之 price_…，'
                      '唔好填「\$50」等金額；金額只供對照。',
                      style: TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    Material(
                      color: const Color(0xFFFFF3E0),
                      borderRadius: BorderRadius.circular(8),
                      child: const Padding(
                        padding: EdgeInsets.all(12),
                        child: Text(
                          '常見錯誤：唔好用「港幣總價」自造 ID，例如 price_300、price_2300、'
                          'price_73600、price_5300 — Stripe 冇呢啲 ID，結帳會報 No such price。\n'
                          '正確做法：Stripe → 產品 → 揀對應定價 → 按「複製 Price ID」，'
                          '貼上嘅字串通常約 25～32 個字元，且 price_ 後面會有英文字母。',
                          style: TextStyle(fontSize: 12, height: 1.35),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    _priceGrid(
                      '移除所有廣告',
                      _months.map((m) => 'ad_${m}m').toList(),
                    ),
                    for (var tier = 1; tier <= 6; tier++)
                      _priceGrid(
                        'Fast Dating $tier',
                        _months.map((m) => 'fd${tier}_${m}m').toList(),
                      ),
                    _priceGrid(
                      '商家廣告刊登',
                      _months.map((m) => 'adpost_${m}m').toList(),
                    ),
                  ],
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('儲存設定'),
                  ),
                  const Divider(height: 40),
                  const Text(
                    '會員端預覽',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  ListTile(
                    leading: const Icon(Icons.smartphone),
                    title: const Text('App Store／Google Play'),
                    subtitle: kIsWeb
                        ? const Text('請使用 iOS／Android App')
                        : const Text('依裝置使用 App Store 或 Google Play 付款'),
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('會員請於手機 App 內完成付款。'),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }
}
