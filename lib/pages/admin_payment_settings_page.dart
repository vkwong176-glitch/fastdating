import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../providers/language_provider.dart';
import '../services/firestore_paths.dart';
import '../services/payment_settings_service.dart';
import '../utils/constants.dart';

/// 管理後台 H：付款方式設定（只保留 IAP 與手動付款）
class AdminSectionHPage extends StatefulWidget {
  const AdminSectionHPage({super.key});

  @override
  State<AdminSectionHPage> createState() => _AdminSectionHPageState();
}

class _AdminSectionHPageState extends State<AdminSectionHPage> {
  final TextEditingController _manualFpsCtrl = TextEditingController();
  final TextEditingController _manualBankAccountLineCtrl =
      TextEditingController();
  final TextEditingController _manualAccountNameCtrl = TextEditingController();
  final TextEditingController _manualAccountNoCtrl = TextEditingController();
  final TextEditingController _manualReceiptHintCtrl = TextEditingController();
  final TextEditingController _manualWhatsappDigitsCtrl =
      TextEditingController();

  bool _enableIap = true;
  bool _enableManual = true;
  bool _loading = true;
  bool _saving = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  @override
  void dispose() {
    _manualFpsCtrl.dispose();
    _manualBankAccountLineCtrl.dispose();
    _manualAccountNameCtrl.dispose();
    _manualAccountNoCtrl.dispose();
    _manualReceiptHintCtrl.dispose();
    _manualWhatsappDigitsCtrl.dispose();
    super.dispose();
  }

  String _paymentDocTimeIsoString() => DateTime.now().toUtc().toIso8601String();

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
      final ps = PaymentSettingsSnapshot.fromMap(snap.data());
      _enableIap = ps.enableIap;
      _enableManual = ps.enableManual;
      _manualFpsCtrl.text = ps.manualPaymentFpsId ?? '';
      _manualBankAccountLineCtrl.text = ps.manualPaymentBankAccountLine ?? '';
      _manualAccountNameCtrl.text = ps.manualPaymentAccountName ?? '';
      _manualAccountNoCtrl.text = ps.manualPaymentAccountNo ?? '';
      _manualReceiptHintCtrl.text = ps.manualPaymentReceiptHint ?? '';
      _manualWhatsappDigitsCtrl.text = ps.manualPaymentWhatsappDigits ?? '';
    } catch (e) {
      _loadError = e.toString();
    }
    if (mounted) {
      setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final manualWhatsappDigits = _manualWhatsappDigitsCtrl.text
          .trim()
          .replaceAll(RegExp(r'[^0-9]'), '');
      final payload = _jsonOnlyFirestoreData(<String, dynamic>{
        'enableIap': _enableIap,
        'enableManual': _enableManual,
        'manualPaymentFpsId': _manualFpsCtrl.text.trim(),
        'manualPaymentBankAccountLine': _manualBankAccountLineCtrl.text.trim(),
        'manualPaymentAccountName': _manualAccountNameCtrl.text.trim(),
        'manualPaymentAccountNo': _manualAccountNoCtrl.text.trim(),
        'manualPaymentReceiptHint': _manualReceiptHintCtrl.text.trim(),
        'manualPaymentWhatsappDigits': manualWhatsappDigits,
        // 一次性清理舊 Stripe 設定欄位，避免後台和文件殘留。
        'enableStripe': false,
        'stripePublishableKey': '',
        'stripePriceIds': <String, String>{},
        'stripeCheckoutUrls': <String, String>{},
        'stripeUniversalActivityPriceId': '',
        'stripeSecretsFromEnv': false,
        'stripeConnected': false,
        'stripeConnectedAt': '',
        'updatedAt': _paymentDocTimeIsoString(),
      });

      await FirebaseFirestore.instance
          .collection(FirestorePaths.paymentSettings)
          .doc(FirestorePaths.paymentSettingsDefaultDoc)
          .set(payload, SetOptions(merge: true));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已儲存付款設定。Stripe 欄位已清除。')),
      );
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
            maxLines: maxLines,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              hintText: hint,
            ),
          ),
        ],
      ),
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
                  if (_loadError != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        _loadError!,
                        style: TextStyle(color: Colors.red.shade800),
                      ),
                    ),
                  Material(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        '本頁已完全移除 Stripe 設定，只保留 App 內購與手動付款資料。',
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.35,
                          color: Colors.blue.shade900,
                        ),
                      ),
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
                    subtitle: '系統會自動去除空格與符號，只保存數字。',
                  ),
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
                  ListTile(
                    leading: const Icon(Icons.account_balance_wallet_outlined),
                    title: const Text('FPS／WeChat／銀行轉帳'),
                    subtitle: const Text('付款後需提交收據，由管理員人工確認'),
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('會員會看到你在上方填寫的手動付款資料。'),
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
