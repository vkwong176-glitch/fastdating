import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/upgrade_matching_profile.dart';
import '../providers/language_provider.dart';
import '../services/admin_backend_service.dart';
import '../services/admin_firebase_session.dart';
import '../services/firebase_bootstrap.dart';
import '../utils/constants.dart' show AppConstants;
import '../utils/upgrade_matching_bool_labels.dart';
import '../utils/upgrade_matching_tier.dart';
import '../utils/upgrade_matching_pdf.dart';
import '../utils/web_file_download.dart';
import '../widgets/admin_upgrade_pool_editor_sheet.dart';

/// 表格內文／表頭字級（規格 15px）
const double _kPoolTableFontSize = 15;

/// 手機版「升級配對」表格：儲存格左右內距各約 **1cm**（[AppConstants.logicalPxPerCm]）。
/// 長文儲存格內文字區上限寬（約 20 個全形字），避免單欄過寬；欄寬改以 [IntrinsicColumnWidth] 貼近內容。
const double _kCompactPoolCellTextMaxW = 264;

/// 與 [AdminUpgradePoolEditorSheet] 一致：升級配對 `profile.text` 欄位中文標題
const Map<String, String> _kUpgradePoolFieldZh = {
  'nationality': '國籍',
  'name': '姓名',
  'age': '年齡',
  'dob': '出生日期 (日/月/年)',
  'heightWeight': '身高及體重',
  'phone': '電話',
  'residence': '目前居住地區',
  'education': '學歷',
  'occupationIncome': '職業及收入',
  'partnerReq': '擇偶要求是什麼？年齡範圍？',
  'debt': '有無負債嗎? 如有，負債多少?',
  'health': '有冇身體缺憾？(例如：家族遺傳病) 若有，請說明',
  'marriageDetail': '若有結過婚，結過幾多次？有小朋友嗎？',
  'pets': '會養寵物嗎? 如有，會養什麼寵物?',
  'hobbies': '平時嗜好是什麼?',
  'selfReflection': '你對自己了解嗎? 有什麼優缺點?',
  'partnerFlaws': '你最不能接受另一伴有什麼缺點?',
  'languages': '能說的語言',
  'sideBusiness': '有創業的經驗嗎？',
  'political': '有強烈政治立場嗎?',
  'religion': '有無宗教信仰嗎?',
  'diet': '有什麼東西是不進食?',
  'alcohol': '喜歡飲酒嗎?',
  'smokingFreq': '有沒有吸煙的習慣?',
  'gambling': '有無賭博習慣?',
};

/// 全形數字 → 半形，便於擷取年齡數字
String _asciiDigitsFromAgeRaw(String s) {
  const full = '０１２３４５６７８９';
  var out = StringBuffer();
  for (final ch in s.runes) {
    final c = String.fromCharCode(ch);
    final i = full.indexOf(c);
    if (i >= 0) {
      out.write('$i');
    } else {
      out.write(c);
    }
  }
  return out.toString();
}

/// 與升級配對表單 `profile.text.age` 同步：只顯示／分享年齡數字（擷取字串中 1～3 位數）
String _upgradeAgeDigits(String? raw) {
  if (raw == null) return '—';
  var s = raw.trim();
  if (s.isEmpty) return '—';
  s = _asciiDigitsFromAgeRaw(s);
  final m = RegExp(r'\d{1,3}').firstMatch(s);
  if (m == null) return '—';
  return m.group(0)!;
}

/// 由出生日期字串推算年齡（支援 D/M/YY、DD/MM/YYYY、YYYY/M/D）
int? _ageYearsFromDobString(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  final t = raw.trim();
  var y = _parseBirthYearFromDob(t);
  if (y == null) return null;
  final now = DateTime.now();
  var age = now.year - y;
  if (age < 0 || age > 120) return null;
  return age;
}

int? _parseBirthYearFromDob(String t) {
  final iso = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$').firstMatch(t);
  if (iso != null) {
    return int.tryParse(iso.group(1)!);
  }
  final dmY = RegExp(r'^(\d{1,2})[/.](\d{1,2})[/.](\d{2,4})$').firstMatch(t);
  if (dmY != null) {
    var yy = int.tryParse(dmY.group(3)!);
    if (yy == null) return null;
    if (yy < 100) {
      yy += yy >= 30 ? 1900 : 2000;
    }
    return yy;
  }
  final yMd = RegExp(r'^(\d{4})[/.](\d{1,2})[/.](\d{1,2})$').firstMatch(t);
  if (yMd != null) {
    return int.tryParse(yMd.group(1)!);
  }
  return null;
}

/// 配對表格年齡：優先 `text.age` 數字，否則由 `text.dob` 推算，再退回文件頂層 `age`（與 users 同步）
String _effectivePoolAgeDigits(Map<String, dynamic> poolDoc) {
  final text = _profileTextMap(poolDoc);
  if (text != null) {
    final fromAge = _upgradeAgeDigits(text['age']?.toString());
    if (fromAge != '—') return fromAge;
    final fromDob = _ageYearsFromDobString(text['dob']?.toString());
    if (fromDob != null) return '$fromDob';
  }
  final top = poolDoc['age'];
  if (top is int) {
    final d = _upgradeAgeDigits('$top');
    if (d != '—') return d;
  } else if (top is num) {
    final d = _upgradeAgeDigits(top.toString());
    if (d != '—') return d;
  } else if (top != null) {
    final d = _upgradeAgeDigits(top.toString());
    if (d != '—') return d;
  }
  return '—';
}

/// 供篩選比對：與表格顯示相同邏輯之「年齡數字字串」（空＝無法辨識）
String _effectivePoolAgeForFilter(Map<String, dynamic> poolDoc) {
  final d = _effectivePoolAgeDigits(poolDoc);
  return d == '—' ? '' : d;
}

Map<String, dynamic>? _profileTextMap(Map<String, dynamic> poolDoc) {
  final profile = poolDoc['profile'];
  if (profile is! Map) return null;
  final text = profile['text'];
  if (text is! Map) return null;
  final byLower = <String, dynamic>{};
  for (final e in text.entries) {
    byLower[e.key.toString().toLowerCase()] = e.value;
  }
  return byLower;
}

String _photoExtFromBytes(Uint8List bytes) {
  if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xD8) return 'jpg';
  return 'png';
}

String _adminStreamErr(LanguageProvider lang, Object? err) {
  final s = err.toString();
  if (s.contains('admin_firebase_auth_required')) {
    return lang.getString('admin_firebase_required');
  }
  return s;
}

enum _AdminFbGate { loading, ready, noFirebase, authFailed }

/// D：升級配對資料庫 — Fast Dating 1～6 分類、表格式檢視
class AdminSectionDPage extends StatefulWidget {
  const AdminSectionDPage({super.key});

  @override
  State<AdminSectionDPage> createState() => _AdminSectionDPageState();
}

class _AdminSectionDPageState extends State<AdminSectionDPage> {
  /// null＝全部；1～6＝篩選方案
  int? _filterPlan;

  /// 手機版：篩選列摺疊條是否展開
  bool _mobilePoolFilterExpanded = false;

  /// 批量勾選：合併 PDF／電郵分享
  final Set<String> _selectedPoolDocIds = <String>{};

  static const int _kMaxBulkMergeMembers = 40;

  /// 方案橫幅下方：年齡／職業／性別／居住地區（子字串篩選，空白＝不篩）
  final TextEditingController _filterAgeCtrl = TextEditingController();
  final TextEditingController _filterOccupationCtrl = TextEditingController();
  final TextEditingController _filterGenderCtrl = TextEditingController();
  final TextEditingController _filterResidenceCtrl = TextEditingController();

  /// 必須先完成 Firebase 身分（匿名或後台對應之 Email／密碼）再訂閱後台流。
  _AdminFbGate _fbGate = _AdminFbGate.loading;

  /// [build] 每次重跑若重取 [watchMatchingPool] 會重訂閱；快取同一條流（含 auth 重連）避免篩選時誤判無登入。
  Stream<QuerySnapshot<Map<String, dynamic>>>? _matchingPoolStream;

  void _onFilterFieldChanged() {
    if (!mounted) return;
    setState(() {});
  }

  /// 手機直向／窄視窗：隱藏篩選列與同步按鈕，且不套用文字篩選（資料依方案完整列出）
  bool _compactMatchingPoolUi(BuildContext context) {
    return MediaQuery.sizeOf(context).shortestSide < 600;
  }

  void _togglePoolRowSelected(String docId, bool? selected) {
    setState(() {
      if (selected == true) {
        _selectedPoolDocIds.add(docId);
      } else {
        _selectedPoolDocIds.remove(docId);
      }
    });
  }

  void _selectAllVisibleRows(List<_PoolRow> rows, bool selectAll) {
    setState(() {
      if (selectAll) {
        for (final r in rows) {
          _selectedPoolDocIds.add(r.docId);
        }
      } else {
        for (final r in rows) {
          _selectedPoolDocIds.remove(r.docId);
        }
      }
    });
  }

  List<_PoolRow> _selectedRowsInFilterOrder(List<_PoolRow> filtered) {
    return filtered
        .where((r) => _selectedPoolDocIds.contains(r.docId))
        .toList();
  }

  String _bulkMergedMailBody(List<_PoolRow> rows) {
    final b = StringBuffer();
    b.writeln('你好，');
    b.writeln('');
    b.writeln('以下為所選會員之升級配對資料（內容見合併 PDF：個人照與每條問答）。');
    b.writeln('');
    for (final r in rows) {
      final name = (r.data['displayName'] as String?)?.trim() ?? '';
      b.writeln(
        '— FD${r.plan} · ${name.isEmpty ? '（無顯示名稱）' : name} · UID ${r.docId}',
      );
    }
    b.writeln('');
    b.writeln(
      '【網頁版】已自動下載合併 PDF，請將該檔案加入郵件附檔後寄出。',
    );
    return b.toString();
  }

  Future<void> _downloadMergedPdfForRows(
    BuildContext context,
    List<_PoolRow> rows,
  ) async {
    if (rows.isEmpty) return;
    if (rows.length > _kMaxBulkMergeMembers) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('一次最多合併 $_kMaxBulkMergeMembers 筆，請減少勾選'),
          ),
        );
      }
      return;
    }
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final members = rows
          .map(
            (r) => (
              poolDoc: r.data,
              plan: r.plan,
              docId: r.docId,
            ),
          )
          .toList();
      final bytes = await buildMergedUpgradeMatchingProfilePdf(members);
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      final name = '升級配對_合併_${rows.length}人.pdf';
      if (kIsWeb) {
        downloadBytesFile(name, bytes, 'application/pdf');
      } else {
        await Printing.sharePdf(bytes: bytes, filename: name);
      }
    } catch (e, st) {
      debugPrint('$e\n$st');
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('無法產生合併 PDF：$e')),
        );
      }
    }
  }

  Future<void> _emailShareMergedPdfs(
    BuildContext context,
    List<_PoolRow> rows,
  ) async {
    if (rows.isEmpty) return;
    if (rows.length > _kMaxBulkMergeMembers) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('一次最多合併 $_kMaxBulkMergeMembers 筆，請減少勾選'),
          ),
        );
      }
      return;
    }
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final members = rows
          .map(
            (r) => (
              poolDoc: r.data,
              plan: r.plan,
              docId: r.docId,
            ),
          )
          .toList();
      final bytes = await buildMergedUpgradeMatchingProfilePdf(members);
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      final filename = '升級配對_合併_${rows.length}人.pdf';
      if (kIsWeb) {
        downloadBytesFile(filename, bytes, 'application/pdf');
        await _openMailtoPrefill(
          context: context,
          subject: 'Fast Dating 升級配對資料（合併 PDF）',
          body: _bulkMergedMailBody(rows),
        );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('已下載合併 PDF，請將檔案附加於郵件後寄出。'),
            ),
          );
        }
      } else {
        await Printing.sharePdf(bytes: bytes, filename: filename);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('請在分享選單中選擇郵件 App，合併 PDF 已附上。'),
            ),
          );
        }
      }
    } catch (e, st) {
      debugPrint('$e\n$st');
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('無法產生合併 PDF：$e')),
        );
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _ensureFirebaseThenListen();
    _filterAgeCtrl.addListener(_onFilterFieldChanged);
    _filterOccupationCtrl.addListener(_onFilterFieldChanged);
    _filterGenderCtrl.addListener(_onFilterFieldChanged);
    _filterResidenceCtrl.addListener(_onFilterFieldChanged);
  }

  @override
  void dispose() {
    _filterAgeCtrl.removeListener(_onFilterFieldChanged);
    _filterOccupationCtrl.removeListener(_onFilterFieldChanged);
    _filterGenderCtrl.removeListener(_onFilterFieldChanged);
    _filterResidenceCtrl.removeListener(_onFilterFieldChanged);
    _filterAgeCtrl.dispose();
    _filterOccupationCtrl.dispose();
    _filterGenderCtrl.dispose();
    _filterResidenceCtrl.dispose();
    super.dispose();
  }

  Future<void> _ensureFirebaseThenListen() async {
    if (!FirebaseBootstrap.isReady) {
      if (mounted) {
        setState(() {
          _fbGate = _AdminFbGate.noFirebase;
          _matchingPoolStream = null;
        });
      }
      return;
    }
    final ok = await ensureFirebaseIdentityForAdminBackend();
    if (!mounted) return;
    if (ok) {
      setState(() => _fbGate = _AdminFbGate.ready);
    } else {
      setState(() {
        _fbGate = _AdminFbGate.authFailed;
        _matchingPoolStream = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<LanguageProvider>(context);
    final svc = AdminBackendService.instance;

    return Scaffold(
      appBar: AppBar(
        title: Text(lang.getString('admin_sec_d')),
        backgroundColor: AppConstants.appBarBackground.withValues(alpha: 0.92),
        toolbarHeight: AppConstants.appBarToolbarHeight,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddPool(context, lang, svc),
        icon: const Icon(Icons.person_add),
        label: Text(lang.getString('admin_sec_d_add')),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _buildPoolBody(context, lang, svc),
          ),
        ],
      ),
    );
  }

  /// 篩選列下方：依 FD1～FD6 顯示方案名稱與資產說明（「全部」時顯示總標題）
  Widget _buildPlanTitleBanner() {
    return Material(
      color: AppConstants.primaryColor.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: _filterPlan == null
            ? Text(
                '全部方案（Fast Dating 1～6）',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: AppConstants.primaryColor,
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    UpgradeMatchingTierHelper.labelForPlan(_filterPlan!),
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: AppConstants.primaryColor,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    UpgradeMatchingTierHelper.assetSummaryZh(_filterPlan!),
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Colors.grey.shade800,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  void _showEditPoolSheet(
    BuildContext context,
    LanguageProvider lang,
    AdminBackendService svc,
    _PoolRow r,
  ) {
    final h = MediaQuery.sizeOf(context).height;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: SizedBox(
          height: h * 0.92,
          child: AdminUpgradePoolEditorSheet(
            docId: r.docId,
            docMap: r.data,
            svc: svc,
            onSaved: () {
              Navigator.pop(ctx);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(lang.getString('admin_sec_saved'))),
                );
              }
            },
          ),
        ),
      ),
    );
  }

  Widget _buildPoolBody(
    BuildContext context,
    LanguageProvider lang,
    AdminBackendService svc,
  ) {
    if (_fbGate == _AdminFbGate.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_fbGate == _AdminFbGate.noFirebase) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Firebase 尚未初始化，請檢查網路與 firebase 設定。',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade800),
          ),
        ),
      );
    }
    if (_fbGate == _AdminFbGate.authFailed) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.orange),
              const SizedBox(height: 12),
              Text(
                '無法建立 Firebase 連線。\n'
                '方式一：在 Firebase Console → Authentication → Sign-in method 啟用「匿名」。\n'
                '方式二：啟用「電子郵件／密碼」，並新增與後台相同的帳密（預設管理員會對應至 '
                '${AppConstants.adminFirebaseLinkedEmail}，密碼須與後台登入密碼一致）。\n'
                '並確認 Firestore 規則允許已登入使用者讀寫 upgrade_matching_pool。',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade900, height: 1.4),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  setState(() {
                    _fbGate = _AdminFbGate.loading;
                    _matchingPoolStream = null;
                  });
                  _ensureFirebaseThenListen();
                },
                child: const Text('重試'),
              ),
            ],
          ),
        ),
      );
    }

    _matchingPoolStream ??= svc.watchMatchingPool();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _matchingPoolStream,
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _adminStreamErr(lang, snap.error),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  FilledButton.tonal(
                    onPressed: () {
                      setState(() {
                        _fbGate = _AdminFbGate.loading;
                        _matchingPoolStream = null;
                      });
                      _ensureFirebaseThenListen();
                    },
                    child: const Text('重新連線'),
                  ),
                ],
              ),
            ),
          );
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final totalRegistered = snap.data!.docs.length;
        final compactPool = _compactMatchingPoolUi(context);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Material(
                color: AppConstants.primaryColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '統計會員登記人數：$totalRegistered',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: _kPoolTableFontSize,
                          fontWeight: FontWeight.w800,
                          color: AppConstants.primaryColor,
                        ),
                      ),
                      if (!compactPool) ...[
                        const SizedBox(height: 10),
                        Center(
                          child: FilledButton.tonal(
                            onPressed: () async {
                              final n = await svc
                                  .syncSubscribedUsersIntoMatchingPool();
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      '${lang.getString('admin_sec_d_sync_ok')}: $n',
                                    ),
                                  ),
                                );
                              }
                            },
                            child: Text(lang.getString('admin_sec_d_sync')),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: FilterChip(
                        label: const Text('全部'),
                        selected: _filterPlan == null,
                        onSelected: (_) => setState(() {
                          _filterPlan = null;
                          _selectedPoolDocIds.clear();
                        }),
                      ),
                    ),
                    for (var p = 1; p <= 6; p++)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: FilterChip(
                          label: Text('FD$p'),
                          tooltip: UpgradeMatchingTierHelper.assetSummaryZh(p),
                          selected: _filterPlan == p,
                          onSelected: (_) => setState(() {
                            _filterPlan = p;
                            _selectedPoolDocIds.clear();
                          }),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: _buildPlanTitleBanner(),
            ),
            if (compactPool)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: _buildMobilePoolFilterStrip(),
              )
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: _buildProfileFilterBar(),
              ),
            Expanded(
              child: _buildPoolTableFromDocs(
                context,
                lang,
                svc,
                snap.data!.docs,
              ),
            ),
          ],
        );
      },
    );
  }

  /// 年齡／職業／性別／居住地區：子字串比對（不分大小寫，性別／年齡除外）
  Widget _buildProfileFilterBar() {
    final gap = AppConstants.logicalPxPerCm * 0.25;
    InputDecoration deco(String hint) {
      return InputDecoration(
        isDense: true,
        hintText: hint,
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      );
    }

    Widget fieldExpanded(String label, TextEditingController c,
        {required String hint}) {
      return Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade800,
              ),
            ),
            const SizedBox(height: 4),
            TextField(
              controller: c,
              decoration: deco(hint),
            ),
          ],
        ),
      );
    }

    Widget fieldFullWidth(String label, TextEditingController c,
        {required String hint}) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade800,
            ),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: c,
            decoration: deco(hint),
          ),
        ],
      );
    }

    return Material(
      color: Colors.blue.shade50.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '篩選',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade800,
              ),
            ),
            SizedBox(height: gap),
            LayoutBuilder(
              builder: (context, c) {
                if (c.maxWidth < 520) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      fieldFullWidth('年齡：', _filterAgeCtrl,
                          hint: '例如 25-35、33、1至33'),
                      SizedBox(height: gap),
                      fieldFullWidth('職業：', _filterOccupationCtrl,
                          hint: '輸入關鍵字'),
                      SizedBox(height: gap),
                      fieldFullWidth('性別：', _filterGenderCtrl, hint: '輸入關鍵字'),
                      SizedBox(height: gap),
                      fieldFullWidth('居住地區：', _filterResidenceCtrl,
                          hint: '輸入關鍵字'),
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    fieldExpanded('年齡：', _filterAgeCtrl,
                        hint: '例如 25-35、33、1至33'),
                    SizedBox(width: gap),
                    fieldExpanded('職業：', _filterOccupationCtrl, hint: '輸入關鍵字'),
                    SizedBox(width: gap),
                    fieldExpanded('性別：', _filterGenderCtrl, hint: '輸入關鍵字'),
                    SizedBox(width: gap),
                    fieldExpanded('居住地區：', _filterResidenceCtrl, hint: '輸入關鍵字'),
                  ],
                );
              },
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () {
                  _filterAgeCtrl.clear();
                  _filterOccupationCtrl.clear();
                  _filterGenderCtrl.clear();
                  _filterResidenceCtrl.clear();
                  setState(() {});
                },
                icon: const Icon(Icons.clear_all, size: 18),
                label: const Text('清除篩選'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 手機版：淺黃摺疊列，點擊展開與桌面相同的篩選表單
  Widget _buildMobilePoolFilterStrip() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: const Color(0xFFFFF8E1),
          borderRadius: BorderRadius.circular(10),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            enableFeedback: false,
            onTap: () => setState(
                () => _mobilePoolFilterExpanded = !_mobilePoolFilterExpanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Icon(Icons.filter_list,
                      color: Colors.grey.shade800, size: 22),
                  const SizedBox(width: 10),
                  Text(
                    '篩選',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: Colors.grey.shade900,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    _mobilePoolFilterExpanded
                        ? Icons.expand_less
                        : Icons.chevron_right,
                    color: Colors.grey.shade700,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_mobilePoolFilterExpanded) ...[
          const SizedBox(height: 8),
          _buildProfileFilterBar(),
        ],
      ],
    );
  }

  /// 手機版表格：居住地、職業等欄位文字
  ({
    String age,
    String phone,
    String residence,
    String occupation,
  }) _compactPoolRowStrings(_PoolRow r) {
    var age = _effectivePoolAgeDigits(r.data);
    var phone = '—';
    var residence = '—';
    var occupation = '—';
    final profile = r.data['profile'];
    if (profile is Map) {
      final text = profile['text'];
      if (text is Map) {
        final ph = text['phone']?.toString().trim() ?? '';
        if (ph.isNotEmpty) phone = ph;
        final res = text['residence']?.toString().trim() ?? '';
        if (res.isNotEmpty) residence = res;
        final occ = text['occupationIncome']?.toString().trim() ?? '';
        if (occ.isNotEmpty) {
          occupation = occ.length > 120 ? '${occ.substring(0, 120)}…' : occ;
        }
      }
    }
    return (
      age: age,
      phone: phone,
      residence: residence,
      occupation: occupation,
    );
  }

  static Map<String, String> _rowProfileStrings(_PoolRow r) {
    var occ = '';
    var gen = '';
    var res = '';
    final profile = r.data['profile'];
    if (profile is Map) {
      gen = profile['gender']?.toString().trim() ?? '';
      final text = profile['text'];
      if (text is Map) {
        occ = text['occupationIncome']?.toString() ?? '';
        res = text['residence']?.toString() ?? '';
      }
    }
    return {
      'age': _effectivePoolAgeForFilter(r.data),
      'occupation': occ,
      'gender': gen,
      'residence': res,
    };
  }

  /// 年齡篩選：例如 `1-33`、`1至33`、`1到33`（整數範圍，含端點）
  (int, int)? _parseAgeRangeFilter(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return null;
    final re = RegExp(r'^\s*(\d{1,3})\s*[-至到~～]\s*(\d{1,3})\s*$');
    final m = re.firstMatch(t);
    if (m == null) return null;
    final a = int.tryParse(m.group(1)!);
    final b = int.tryParse(m.group(2)!);
    if (a == null || b == null) return null;
    final lo = a <= b ? a : b;
    final hi = a <= b ? b : a;
    return (lo, hi);
  }

  int? _parseProfileAgeYears(String ageRaw) {
    final t = ageRaw.trim();
    if (t.isEmpty) return null;
    final m = RegExp(r'-?\d+').firstMatch(t);
    if (m == null) return null;
    return int.tryParse(m.group(0)!);
  }

  bool _matchesAgeFilter(String ageFromProfile, String filterText) {
    final f = filterText.trim();
    if (f.isEmpty) return true;
    final range = _parseAgeRangeFilter(f);
    if (range != null) {
      final n = _parseProfileAgeYears(ageFromProfile);
      if (n == null) return false;
      return n >= range.$1 && n <= range.$2;
    }
    // 單一數字：與辨識後的年齡（歲）精確相符
    if (RegExp(r'^\d{1,3}$').hasMatch(f)) {
      final target = int.tryParse(f);
      if (target == null) return true;
      final n = _parseProfileAgeYears(ageFromProfile);
      if (n == null) return false;
      return n == target;
    }
    return true;
  }

  bool _matchesProfileFilters(_PoolRow r) {
    final q = _rowProfileStrings(r);
    final a = _filterAgeCtrl.text.trim();
    final o = _filterOccupationCtrl.text.trim();
    final g = _filterGenderCtrl.text.trim();
    final res = _filterResidenceCtrl.text.trim();
    if (a.isNotEmpty && !_matchesAgeFilter(q['age'] ?? '', a)) return false;
    if (o.isNotEmpty &&
        !q['occupation']!.toLowerCase().contains(o.toLowerCase())) {
      return false;
    }
    if (g.isNotEmpty && !q['gender']!.contains(g)) return false;
    if (res.isNotEmpty &&
        !q['residence']!.toLowerCase().contains(res.toLowerCase())) {
      return false;
    }
    return true;
  }

  Widget _buildPoolTableFromDocs(
    BuildContext context,
    LanguageProvider lang,
    AdminBackendService svc,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    if (docs.isEmpty) {
      return Center(child: Text(lang.getString('admin_sec_empty')));
    }
    final enriched = docs.map((d) {
      final m = d.data();
      final plan = UpgradeMatchingTierHelper.planFromPoolDoc(m);
      return _PoolRow(docId: d.id, data: m, plan: plan);
    }).toList();
    enriched.sort((a, b) {
      final c = a.plan.compareTo(b.plan);
      if (c != 0) return c;
      return a.docId.compareTo(b.docId);
    });
    final planFiltered = _filterPlan == null
        ? enriched
        : enriched.where((e) => e.plan == _filterPlan).toList();
    final filtered = planFiltered.where(_matchesProfileFilters).toList();
    if (planFiltered.isEmpty) {
      return const Center(child: Text('此分類暫無資料'));
    }
    if (filtered.isEmpty) {
      return const Center(child: Text('無符合篩選條件的資料'));
    }
    final compactTable = _compactMatchingPoolUi(context);
    final selectedOrdered = _selectedRowsInFilterOrder(filtered);
    return LayoutBuilder(
      builder: (context, constraints) {
        return Scrollbar(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 88),
            scrollDirection: Axis.vertical,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (selectedOrdered.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Material(
                      elevation: 1,
                      borderRadius: BorderRadius.circular(10),
                      color: AppConstants.primaryColor.withValues(alpha: 0.1),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        child: Wrap(
                          spacing: 10,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              '已選 ${selectedOrdered.length} 筆',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                                color: Colors.grey.shade900,
                              ),
                            ),
                            TextButton(
                              onPressed: () =>
                                  setState(() => _selectedPoolDocIds.clear()),
                              child: const Text('清除勾選'),
                            ),
                            FilledButton.tonal(
                              onPressed: () => _downloadMergedPdfForRows(
                                context,
                                selectedOrdered,
                              ),
                              child: const Text('下載合併 PDF'),
                            ),
                            FilledButton(
                              onPressed: () => _emailShareMergedPdfs(
                                context,
                                selectedOrdered,
                              ),
                              child: const Text('電郵分享（合併 PDF）'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minWidth: constraints.maxWidth - 24,
                    ),
                    child: _buildExcelTable(
                      context,
                      lang,
                      svc,
                      filtered,
                      filtered,
                      compactLayout: compactTable,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _rowAccountEmail(Map<String, dynamic> data) {
    final v = data['accountEmail'] ?? data['email'];
    if (v == null) return '';
    return v.toString().trim();
  }

  Uint8List? _profilePhotoBytes(Map<String, dynamic> doc) {
    final profile = doc['profile'];
    if (profile is! Map) return null;
    final b64 = profile['personalPhotoBase64']?.toString();
    if (b64 == null || b64.isEmpty) return null;
    try {
      final bytes = base64Decode(b64);
      return bytes.isEmpty ? null : bytes;
    } catch (_) {
      return null;
    }
  }

  /// 電郵／WhatsApp 共用（不含帳戶電郵行、不含 UID）
  String _planSharePlainText(_PoolRow r) {
    final profile = r.data['profile'];
    final age = _effectivePoolAgeDigits(r.data);
    var income = '—';
    var phone = '—';
    var residence = '—';
    var genderStr = '—';
    final name = (r.data['displayName'] as String?)?.trim() ?? '';
    if (profile is Map) {
      genderStr = profile['gender']?.toString().trim() ?? '—';
      final text = profile['text'];
      if (text is Map) {
        income = text['occupationIncome']?.toString() ?? '—';
        phone = text['phone']?.toString() ?? '—';
        residence = text['residence']?.toString() ?? '—';
      }
    }
    final buf = StringBuffer();
    buf.writeln(
      '【升級配對】FD${r.plan} ${UpgradeMatchingTierHelper.labelForPlan(r.plan)} 介紹',
    );
    buf.writeln('顯示名稱：${name.isEmpty ? "—" : name}');
    buf.writeln('年齡：$age');
    buf.writeln('性別：$genderStr');
    buf.writeln('電話：$phone');
    buf.writeln('居住地區：$residence');
    buf.writeln('職業／收入：$income');
    return buf.toString();
  }

  /// 供下載：升級配對表格每條問題與答案（純文字）
  String _memberDetailTextFileBody(_PoolRow r) {
    final parsed = UpgradeMatchingProfileData.fromFirestoreDoc(r.data);
    final b = StringBuffer();
    b.writeln('Fast Dating 升級配對資料');
    b.writeln(
        '方案：FD${r.plan} ${UpgradeMatchingTierHelper.labelForPlan(r.plan)}');
    b.writeln('---');
    if (parsed == null) {
      b.writeln('（無法讀取 profile）');
      return b.toString();
    }
    b.writeln('性別：${_genderZhDisplay(parsed.gender)}');
    for (final k in UpgradeMatchingProfileData.textKeys) {
      final label = _kUpgradePoolFieldZh[k] ?? k;
      b.writeln('$label：${parsed.text[k]?.trim() ?? ''}');
    }
    b.writeln('有自置物業嗎：${zhHaveNone(parsed.hasProperty)}');
    b.writeln('有曾結過婚嗎：${zhHaveNone(parsed.marriedBefore)}');
    b.writeln('想結婚嗎：${zhWantNotWant(parsed.wantMarriageSoon)}');
    b.writeln('日後想生孩子嗎：${zhWantNotWant(parsed.wantChildren)}');
    b.writeln('有急切想結婚生孩嗎：${zhHaveNone(parsed.urgentMarriage)}');
    b.writeln('有無車牌：${zhHaveNone(parsed.hasDriverLicense)}');
    return b.toString();
  }

  void _downloadMemberDetailTxt(BuildContext context, _PoolRow r) {
    final name = 'FD${r.plan}_upgrade_${r.docId}.txt';
    final body = _memberDetailTextFileBody(r);
    if (kIsWeb) {
      downloadTextFile(name, body);
    } else if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('下載文字檔請使用網頁版管理後台')),
      );
    }
  }

  void _downloadMemberPhoto(BuildContext context, _PoolRow r) {
    final bytes = _profilePhotoBytes(r.data);
    if (bytes == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('此會員未有上載個人照')),
        );
      }
      return;
    }
    final ext = _photoExtFromBytes(bytes);
    final mime = ext == 'jpg' ? 'image/jpeg' : 'image/png';
    final filename = 'member_${r.docId}.$ext';
    if (kIsWeb) {
      downloadBytesFile(filename, bytes, mime);
    } else if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('下載個人照請使用網頁版管理後台')),
      );
    }
  }

  String _genderZhDisplay(String? raw) {
    if (raw == null || raw.isEmpty) return '—';
    final s = raw.toLowerCase().trim();
    if (s == 'female' || s == '女') return '女';
    if (s == 'male' || s == '男') return '男';
    return raw;
  }

  Widget _detailQaBlock(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: Color(0xFF212121),
            ),
          ),
          const SizedBox(height: 4),
          SelectableText(
            value.isEmpty ? '—' : value,
            style: const TextStyle(fontSize: 14, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _buildUpgradeProfileReadOnly(Map<String, dynamic> poolDoc) {
    final parsed = UpgradeMatchingProfileData.fromFirestoreDoc(poolDoc);
    if (parsed == null) {
      return const Text('無法讀取升級配對 profile');
    }
    final children = <Widget>[
      _detailQaBlock('性別', _genderZhDisplay(parsed.gender)),
    ];
    for (final k in UpgradeMatchingProfileData.textKeys) {
      final label = _kUpgradePoolFieldZh[k] ?? k;
      final v = parsed.text[k]?.trim() ?? '';
      children.add(_detailQaBlock(label, v));
    }
    children.addAll([
      _detailQaBlock('有自置物業嗎', zhHaveNone(parsed.hasProperty)),
      _detailQaBlock('有曾結過婚嗎', zhHaveNone(parsed.marriedBefore)),
      _detailQaBlock('想結婚嗎', zhWantNotWant(parsed.wantMarriageSoon)),
      _detailQaBlock('日後想生孩子嗎', zhWantNotWant(parsed.wantChildren)),
      _detailQaBlock('有急切想結婚生孩嗎', zhHaveNone(parsed.urgentMarriage)),
      _detailQaBlock('有無車牌', zhHaveNone(parsed.hasDriverLicense)),
    ]);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  void _showMemberUpgradeDetailDialog(BuildContext context, _PoolRow r) {
    final h = MediaQuery.sizeOf(context).height;
    final photoBytes = _profilePhotoBytes(r.data);
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: SizedBox(
          width: 560,
          height: h * 0.88,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '會員詳細資料（升級配對表格）',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: Colors.grey.shade900,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.picture_as_pdf_outlined),
                      onPressed: () => _downloadUpgradeMatchingPdf(ctx, r),
                      tooltip: '下載 PDF（個人照＋每條問答，方便列印閱讀）',
                    ),
                    IconButton(
                      icon: const Icon(Icons.download_outlined),
                      onPressed: () => _downloadMemberDetailTxt(ctx, r),
                      tooltip: '下載純文字（.txt）',
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx),
                      tooltip: '關閉',
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: Colors.grey.shade300),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '會員個人照（與列表「圖片」欄同步）',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: Colors.grey.shade900,
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (photoBytes != null)
                        Center(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxHeight: 280),
                              child: Image.memory(
                                photoBytes,
                                fit: BoxFit.contain,
                              ),
                            ),
                          ),
                        )
                      else
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '此會員尚未上載個人照',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ),
                      const SizedBox(height: 20),
                      Divider(color: Colors.grey.shade300),
                      const SizedBox(height: 12),
                      Text(
                        '升級配對問卷內容',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: Colors.grey.shade900,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _buildUpgradeProfileReadOnly(r.data),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAfterEmailShareDialog(
      BuildContext context, _PoolRow r, Uint8List? bytes) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('已填會員個人照（JPG／PNG）'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (bytes != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(bytes, fit: BoxFit.contain),
                ),
                const SizedBox(height: 12),
              ] else
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    '此會員尚未上載個人照。',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                  ),
                ),
              Text(
                '請將上方圖片拖入郵件附檔，或使用下方「下載個人照」。',
                style: TextStyle(
                    fontSize: 12, color: Colors.grey.shade700, height: 1.35),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.tonal(
                    onPressed: () => _downloadMemberPhoto(ctx, r),
                    child: const Text('下載個人照'),
                  ),
                  FilledButton.tonal(
                    onPressed: () => _downloadMemberDetailTxt(ctx, r),
                    child: const Text('下載升級配對詳情（.txt）'),
                  ),
                  FilledButton.tonal(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _showMemberUpgradeDetailDialog(context, r);
                    },
                    child: const Text('會員詳細資料'),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('關閉'),
          ),
        ],
      ),
    );
  }

  Future<void> _openMailtoPrefill({
    required BuildContext context,
    required String subject,
    required String body,
  }) async {
    final uri = Uri.parse(
      'mailto:?subject=${Uri.encodeComponent(subject)}&body=${Uri.encodeComponent(body)}',
    );
    final ok = await launchUrl(uri, mode: LaunchMode.platformDefault);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('無法開啟郵件程式')),
      );
    }
  }

  Future<void> _shareOneRowMail(BuildContext context, _PoolRow r) async {
    final body = _planSharePlainText(r);
    await _openMailtoPrefill(
      context: context,
      subject: 'Fast Dating 升級配對資料庫 介紹',
      body: body,
    );
    if (!context.mounted) return;
    _showAfterEmailShareDialog(context, r, _profilePhotoBytes(r.data));
  }

  Future<void> _shareFilteredRowsMail(
    BuildContext context,
    List<_PoolRow> rows,
  ) async {
    if (rows.isEmpty) return;
    const maxRows = 60;
    final slice = rows.length > maxRows ? rows.take(maxRows).toList() : rows;
    final buf = StringBuffer();
    for (var i = 0; i < slice.length; i++) {
      if (i > 0) buf.writeln('---');
      buf.writeln(_planSharePlainText(slice[i]));
    }
    if (rows.length > maxRows) {
      buf.writeln('\n…（其餘 ${rows.length - maxRows} 筆請縮小篩選後再寄）');
    }
    await _openMailtoPrefill(
      context: context,
      subject: 'Fast Dating 升級配對資料庫 介紹',
      body: buf.toString(),
    );
  }

  Future<void> _showWhatsAppAttachmentSheet(
      BuildContext context, _PoolRow r) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'WhatsApp 網頁連結無法自動夾帶圖片與附件，請下載後於對話中手動傳送。',
                style: TextStyle(
                    fontSize: 14, color: Colors.grey.shade800, height: 1.35),
              ),
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: () => _downloadMemberPhoto(ctx, r),
                child: const Text('下載個人照（JPG／PNG）'),
              ),
              const SizedBox(height: 8),
              FilledButton.tonal(
                onPressed: () => _downloadMemberDetailTxt(ctx, r),
                child: const Text('下載升級配對詳情（.txt）'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _showMemberUpgradeDetailDialog(context, r);
                },
                child: const Text('預覽會員詳細資料'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _shareRowWhatsApp(BuildContext context, _PoolRow r) async {
    final text = _planSharePlainText(r);
    final phoneCtrl = TextEditingController();
    if (!context.mounted) return;
    try {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('WhatsApp 分享升級配對'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '收方 WhatsApp 電話（只填數字，含國碼，例如 85298765432）。留空則只開啟分享文字。',
                  style: TextStyle(
                      fontSize: 13, color: Colors.grey.shade800, height: 1.35),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: '85298765432',
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '預覽內容',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: Colors.grey.shade900,
                  ),
                ),
                const SizedBox(height: 6),
                SelectableText(
                  text,
                  style: const TextStyle(fontSize: 12, height: 1.35),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.pop(ctx);
                final digits = phoneCtrl.text.replaceAll(RegExp(r'\D'), '');
                final path = digits.length >= 8 ? digits : '';
                final uri = Uri.parse(
                  path.isNotEmpty
                      ? 'https://wa.me/$path?text=${Uri.encodeComponent(text)}'
                      : 'https://wa.me/?text=${Uri.encodeComponent(text)}',
                );
                final ok =
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                if (!context.mounted) return;
                if (!ok) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('無法開啟 WhatsApp')),
                  );
                  return;
                }
                await _showWhatsAppAttachmentSheet(context, r);
              },
              child: const Text('開啟 WhatsApp'),
            ),
          ],
        ),
      );
    } finally {
      phoneCtrl.dispose();
    }
  }

  Future<void> _downloadUpgradeMatchingPdf(
    BuildContext context,
    _PoolRow r,
  ) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final bytes = await buildUpgradeMatchingProfilePdf(
        poolDoc: r.data,
        plan: r.plan,
      );
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      final name = 'FD${r.plan}_${r.docId}.pdf';
      if (kIsWeb) {
        downloadBytesFile(name, bytes, 'application/pdf');
      } else {
        await Printing.sharePdf(bytes: bytes, filename: name);
      }
    } catch (e, st) {
      debugPrint('$e\n$st');
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('無法產生 PDF：$e')),
        );
      }
    }
  }

  Widget _buildCompactPoolTable(
    BuildContext context,
    LanguageProvider lang,
    AdminBackendService svc,
    List<_PoolRow> rows,
    List<_PoolRow> allFilteredRows,
  ) {
    final border = TableBorder.all(
      color: const Color(0xFFBDBDBD),
      width: 1,
      borderRadius: BorderRadius.circular(4),
    );
    const headStyle = TextStyle(
      fontWeight: FontWeight.w700,
      fontSize: 13,
      color: Color(0xFF212121),
    );
    final poolCellH = AppConstants.logicalPxPerCm;

    Widget compactHead(String t, {bool singleLine = true}) {
      return Padding(
        padding: EdgeInsets.symmetric(
          horizontal: poolCellH,
          vertical: 10,
        ),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            t,
            style: headStyle,
            maxLines: singleLine ? 1 : null,
            softWrap: !singleLine,
            textAlign: TextAlign.start,
          ),
        ),
      );
    }

    return Material(
      color: Colors.white,
      elevation: 2,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(10),
      child: Table(
        border: border,
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        columnWidths: const <int, TableColumnWidth>{
          // 方案／操作欄固定；其餘依內容寬度收緊，避免電郵旁大片空白。
          0: FixedColumnWidth(120),
          1: IntrinsicColumnWidth(),
          2: IntrinsicColumnWidth(),
          3: IntrinsicColumnWidth(),
          4: IntrinsicColumnWidth(),
          5: IntrinsicColumnWidth(),
          6: FixedColumnWidth(118),
        },
        children: [
          TableRow(
            decoration: BoxDecoration(
              color: AppConstants.primaryColor.withValues(alpha: 0.18),
            ),
            children: [
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: poolCellH,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 36,
                      height: 36,
                      child: Checkbox(
                        tristate: true,
                        value: rows.isNotEmpty &&
                                rows.every(
                                  (r) => _selectedPoolDocIds.contains(r.docId),
                                )
                            ? true
                            : (rows.any(
                                (r) => _selectedPoolDocIds.contains(r.docId),
                              )
                                ? null
                                : false),
                        onChanged: (v) {
                          if (v == true) {
                            _selectAllVisibleRows(rows, true);
                          } else {
                            _selectAllVisibleRows(rows, false);
                          }
                        },
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                    const Text('方案', style: headStyle),
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: poolCellH,
                  vertical: 8,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('帳戶', style: headStyle, maxLines: 1),
                    IconButton(
                      icon: const Icon(Icons.forward_to_inbox_outlined,
                          size: 18, color: Color(0xFF1565C0)),
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 30, minHeight: 30),
                      tooltip: '以電郵分享目前篩選結果（介紹）',
                      onPressed: () =>
                          _shareFilteredRowsMail(context, allFilteredRows),
                    ),
                  ],
                ),
              ),
              compactHead('年齡'),
              compactHead('電話'),
              compactHead('居住地區', singleLine: false),
              compactHead('職業', singleLine: false),
              compactHead('操作'),
            ],
          ),
          for (final r in rows) _compactPoolDataRow(context, r),
        ],
      ),
    );
  }

  TableRow _compactPoolDataRow(
    BuildContext context,
    _PoolRow r,
  ) {
    final s = _compactPoolRowStrings(r);
    final accountEmail = _rowAccountEmail(r.data);
    const dataStyle = TextStyle(
      fontSize: 13,
      color: Color(0xFF212121),
      height: 1.35,
    );
    final poolCellH = AppConstants.logicalPxPerCm;
    Widget compactData(Widget child) {
      return Padding(
        padding: EdgeInsets.symmetric(
          horizontal: poolCellH,
          vertical: 8,
        ),
        child: child,
      );
    }

    return TableRow(
      children: [
        compactData(
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: _selectedPoolDocIds.contains(r.docId),
                onChanged: (v) => _togglePoolRowSelected(r.docId, v),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              Text(
                'FD${r.plan}',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.clip,
              ),
            ],
          ),
        ),
        compactData(
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: _kCompactPoolCellTextMaxW,
                ),
                child: Tooltip(
                  message: '與會員註冊電郵同步',
                  child: SelectableText(
                    accountEmail.isEmpty ? '—' : accountEmail,
                    style: TextStyle(
                      fontSize: 13,
                      color: accountEmail.isEmpty
                          ? Colors.grey.shade600
                          : const Color(0xFF1565C0),
                      height: 1.35,
                    ),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.share_outlined, size: 20),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                tooltip: '電郵分享此列（介紹）',
                onPressed: () => _shareOneRowMail(context, r),
              ),
            ],
          ),
        ),
        compactData(
          Text(
            s.age,
            style: dataStyle,
            maxLines: 1,
            softWrap: false,
            textAlign: TextAlign.start,
          ),
        ),
        compactData(
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: _kCompactPoolCellTextMaxW,
                ),
                child: Tooltip(
                  message: 'UID：${r.docId}',
                  child: SelectableText(
                    s.phone,
                    style: dataStyle,
                    maxLines: 3,
                    textAlign: TextAlign.start,
                  ),
                ),
              ),
              Tooltip(
                message: 'WhatsApp 分享升級配對（介紹）',
                child: InkWell(
                  enableFeedback: false,
                  onTap: () => _shareRowWhatsApp(context, r),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: const Color(0xFF25D366),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.chat_bubble_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        compactData(
          ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: _kCompactPoolCellTextMaxW,
            ),
            child: Text(
              s.residence,
              style: dataStyle,
              softWrap: true,
            ),
          ),
        ),
        compactData(
          ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: _kCompactPoolCellTextMaxW,
            ),
            child: Text(
              s.occupation,
              style: dataStyle,
              softWrap: true,
            ),
          ),
        ),
        compactData(
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _downloadUpgradeMatchingPdf(context, r),
              icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
              label: const Text('下載表格', style: TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildExcelTable(
    BuildContext context,
    LanguageProvider lang,
    AdminBackendService svc,
    List<_PoolRow> rows,
    List<_PoolRow> allFilteredRows, {
    bool compactLayout = false,
  }) {
    if (compactLayout) {
      return _buildCompactPoolTable(
        context,
        lang,
        svc,
        rows,
        allFilteredRows,
      );
    }
    final border = TableBorder.all(
      color: const Color(0xFFBDBDBD),
      width: 1,
      borderRadius: BorderRadius.circular(4),
    );
    final hPad = AppConstants.logicalPxPerCm;
    const headStyle = TextStyle(
      fontWeight: FontWeight.w700,
      fontSize: _kPoolTableFontSize,
      color: Color(0xFF212121),
    );
    Widget headText(String t) {
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 12),
        child: Text(t, style: headStyle),
      );
    }

    return Material(
      color: Colors.white,
      elevation: 2,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(10),
      child: Table(
        border: border,
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        columnWidths: const {
          0: FixedColumnWidth(248),
          1: FixedColumnWidth(200),
          2: FixedColumnWidth(200),
          3: FixedColumnWidth(88),
          4: FixedColumnWidth(56),
          5: FixedColumnWidth(180),
          6: FixedColumnWidth(76),
          7: FixedColumnWidth(156),
        },
        children: [
          TableRow(
            decoration: BoxDecoration(
              color: AppConstants.primaryColor.withValues(alpha: 0.18),
            ),
            children: [
              Padding(
                padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 40,
                      height: 40,
                      child: Checkbox(
                        tristate: true,
                        value: rows.isNotEmpty &&
                                rows.every(
                                  (r) => _selectedPoolDocIds.contains(r.docId),
                                )
                            ? true
                            : (rows.any(
                                (r) => _selectedPoolDocIds.contains(r.docId),
                              )
                                ? null
                                : false),
                        onChanged: (v) {
                          if (v == true) {
                            _selectAllVisibleRows(rows, true);
                          } else {
                            _selectAllVisibleRows(rows, false);
                          }
                        },
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text('方案', style: headStyle),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Tooltip(
                        message: '與會員註冊電郵同步（accountEmail）',
                        child: Text('帳戶', style: headStyle),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.forward_to_inbox_outlined,
                          size: 20, color: Color(0xFF1565C0)),
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 34, minHeight: 34),
                      tooltip: '以電郵分享目前篩選結果（介紹）',
                      onPressed: () =>
                          _shareFilteredRowsMail(context, allFilteredRows),
                    ),
                  ],
                ),
              ),
              headText('電話'),
              headText('名稱'),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('年', style: headStyle),
                    Text('齡', style: headStyle),
                  ],
                ),
              ),
              headText('職業／收入（摘要）'),
              headText('圖片'),
              headText('操作'),
            ],
          ),
          for (final r in rows) _dataRow(context, lang, svc, r),
        ],
      ),
    );
  }

  TableRow _dataRow(
    BuildContext context,
    LanguageProvider lang,
    AdminBackendService svc,
    _PoolRow r,
  ) {
    final profile = r.data['profile'];
    final age = _effectivePoolAgeDigits(r.data);
    String incomeShort = '—';
    String phone = '—';
    if (profile is Map) {
      final text = profile['text'];
      if (text is Map) {
        final inc = text['occupationIncome']?.toString() ?? '';
        incomeShort = inc.length > 36 ? '${inc.substring(0, 36)}…' : inc;
        if (incomeShort.isEmpty) incomeShort = '—';
        final ph = text['phone']?.toString().trim() ?? '';
        if (ph.isNotEmpty) phone = ph;
      }
    }
    final name = (r.data['displayName'] as String?)?.trim() ?? '';
    final accountEmail = _rowAccountEmail(r.data);

    const dataStyle = TextStyle(
      fontSize: _kPoolTableFontSize,
      color: Color(0xFF212121),
    );

    return TableRow(
      children: [
        _cell(
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Checkbox(
                  value: _selectedPoolDocIds.contains(r.docId),
                  onChanged: (v) => _togglePoolRowSelected(r.docId, v),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              const SizedBox(width: 2),
              Expanded(
                child: _filterPlan == null
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'FD${r.plan}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: _kPoolTableFontSize,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            UpgradeMatchingTierHelper.labelForPlan(r.plan),
                            style: TextStyle(
                              fontSize: _kPoolTableFontSize - 1,
                              color: Colors.grey.shade800,
                              height: 1.25,
                            ),
                          ),
                        ],
                      )
                    : Text(
                        'FD${r.plan}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: _kPoolTableFontSize,
                        ),
                      ),
              ),
            ],
          ),
        ),
        _cell(
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Tooltip(
                  message: '與會員註冊電郵同步',
                  child: SelectableText(
                    accountEmail.isEmpty ? '—' : accountEmail,
                    style: TextStyle(
                      fontSize: _kPoolTableFontSize,
                      color: accountEmail.isEmpty
                          ? Colors.grey.shade600
                          : const Color(0xFF1565C0),
                    ),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.share_outlined, size: 22),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                tooltip: '電郵分享此列（介紹）',
                onPressed: () => _shareOneRowMail(context, r),
              ),
            ],
          ),
        ),
        _cell(
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Tooltip(
                  message: 'UID：${r.docId}',
                  child: SelectableText(
                    phone,
                    style: dataStyle,
                  ),
                ),
              ),
              Tooltip(
                message: 'WhatsApp 分享升級配對（介紹）',
                child: InkWell(
                  enableFeedback: false,
                  onTap: () => _shareRowWhatsApp(context, r),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: const Color(0xFF25D366),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.chat_bubble_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        _cell(
          Text(
            name.isEmpty ? '—' : name,
            style: dataStyle,
          ),
        ),
        _cell(
          Text(
            age,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            style: dataStyle,
          ),
        ),
        _cell(Text(incomeShort, style: dataStyle)),
        _cell(_poolProfilePhotoThumb(context, r.data)),
        _cell(
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              IconButton(
                tooltip: '會員詳細資料',
                icon: const Icon(Icons.article_outlined, size: 22),
                onPressed: () => _showMemberUpgradeDetailDialog(context, r),
              ),
              IconButton(
                tooltip: '編輯／同步儲存',
                icon: const Icon(Icons.edit_note_outlined, size: 22),
                onPressed: () => _showEditPoolSheet(context, lang, svc, r),
              ),
              IconButton(
                tooltip: lang.getString('admin_sec_deleted'),
                icon: const Icon(Icons.delete_outline,
                    size: 20, color: Colors.redAccent),
                onPressed: () async {
                  await svc.removeFromMatchingPool(r.docId);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text(lang.getString('admin_sec_deleted'))),
                    );
                  }
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showPhotoZoom(BuildContext context, Uint8List bytes) {
    final size = MediaQuery.sizeOf(context);
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(12),
          child: Stack(
            alignment: Alignment.center,
            children: [
              InteractiveViewer(
                minScale: 0.5,
                maxScale: 5,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: size.width - 24,
                    maxHeight: size.height * 0.88,
                  ),
                  child: Image.memory(bytes, fit: BoxFit.contain),
                ),
              ),
              Positioned(
                top: 0,
                right: 0,
                child: Material(
                  color: Colors.black54,
                  shape: const CircleBorder(),
                  child: IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    tooltip: '關閉',
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _poolProfilePhotoThumb(
      BuildContext context, Map<String, dynamic> doc) {
    final bytes = _profilePhotoBytes(doc);
    if (bytes == null) return _poolPhotoPlaceholder();
    return Material(
      color: Colors.transparent,
      child: InkWell(
        enableFeedback: false,
        onTap: () => _showPhotoZoom(context, bytes),
        borderRadius: BorderRadius.circular(8),
        child: Tooltip(
          message: '點擊放大',
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.memory(
              bytes,
              width: 56,
              height: 56,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _poolPhotoPlaceholder(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _poolPhotoPlaceholder() {
    return Container(
      width: 56,
      height: 56,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(Icons.photo_camera_back_outlined,
          size: 26, color: Colors.grey.shade500),
    );
  }

  Widget _cell(Widget child) {
    final h = AppConstants.logicalPxPerCm;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: h, vertical: 8),
      child: child,
    );
  }

  Future<void> _showAddPool(
    BuildContext context,
    LanguageProvider lang,
    AdminBackendService svc,
  ) async {
    final uidCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(lang.getString('admin_sec_d_add')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: uidCtrl,
              decoration:
                  InputDecoration(labelText: lang.getString('admin_field_uid')),
            ),
            TextField(
              controller: nameCtrl,
              decoration: InputDecoration(
                  labelText: lang.getString('admin_sec_display_name')),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(lang.getString('close'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(lang.getString('btn_save'))),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await svc.addToMatchingPool(
          userId: uidCtrl.text, displayName: nameCtrl.text);
      uidCtrl.dispose();
      nameCtrl.dispose();
    } else {
      uidCtrl.dispose();
      nameCtrl.dispose();
    }
  }
}

class _PoolRow {
  _PoolRow({required this.docId, required this.data, required this.plan});
  final String docId;
  final Map<String, dynamic> data;
  final int plan;
}
