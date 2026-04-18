import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../models/upgrade_matching_profile.dart';
import '../services/admin_backend_service.dart';
import '../utils/constants.dart' show AppConstants;
import '../utils/upgrade_matching_pdf.dart';
import '../utils/upgrade_matching_tier.dart';
import '../utils/web_file_download.dart';

/// 後台「升級配對資料庫」單筆編輯（與 App [UpgradeMatchingProfileData] 欄位一致）
class AdminUpgradePoolEditorSheet extends StatefulWidget {
  const AdminUpgradePoolEditorSheet({
    super.key,
    required this.docId,
    required this.docMap,
    required this.svc,
    required this.onSaved,
  });

  final String docId;
  final Map<String, dynamic> docMap;
  final AdminBackendService svc;
  final VoidCallback onSaved;

  @override
  State<AdminUpgradePoolEditorSheet> createState() =>
      _AdminUpgradePoolEditorSheetState();
}

class _AdminUpgradePoolEditorSheetState extends State<AdminUpgradePoolEditorSheet> {
  late final Map<String, TextEditingController> _c;
  String _gender = '男';
  bool? _hasProperty;
  bool? _marriedBefore;
  bool? _wantMarriageSoon;
  bool? _wantChildren;
  bool? _urgentMarriage;
  bool? _hasDriverLicense;
  bool _saving = false;

  static const Map<String, String> _zh = {
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

  @override
  void initState() {
    super.initState();
    _c = UpgradeMatchingProfileData.createControllers();
    final data = UpgradeMatchingProfileData.fromFirestoreDoc(widget.docMap);
    if (data != null) {
      data.applyToControllers(_c);
      final g = data.gender?.toLowerCase().trim() ?? '';
      if (g == 'female' || g == '女') {
        _gender = '女';
      } else {
        _gender = '男';
      }
      _hasProperty = data.hasProperty;
      _marriedBefore = data.marriedBefore;
      _wantMarriageSoon = data.wantMarriageSoon;
      _wantChildren = data.wantChildren;
      _urgentMarriage = data.urgentMarriage;
      _hasDriverLicense = data.hasDriverLicense;
    }
  }

  @override
  void dispose() {
    for (final e in _c.entries) {
      e.value.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final data = UpgradeMatchingProfileData.fromControllers(
        c: _c,
        gender: _gender == '女' ? 'female' : 'male',
        hasProperty: _hasProperty,
        marriedBefore: _marriedBefore,
        wantMarriageSoon: _wantMarriageSoon,
        wantChildren: _wantChildren,
        urgentMarriage: _urgentMarriage,
        hasDriverLicense: _hasDriverLicense,
      );
      final name = data.displayName.trim();
      final fallbackName = (widget.docMap['displayName'] as String?)?.trim() ?? '';
      await widget.svc.saveMatchingPoolProfile(
        docId: widget.docId,
        profileFirestoreMap: data.toProfileFirestoreMap(),
        displayName: name.isNotEmpty ? name : (fallbackName.isNotEmpty ? fallbackName : null),
      );
      if (mounted) {
        widget.onSaved();
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// 兩擇一（無「未填」按鈕）；未選時兩粒皆不選
  Widget _boolRowDual({
    required String label,
    required bool? value,
    required String positiveLabel,
    required String negativeLabel,
    required ValueChanged<bool?> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: Color(0xFF212121),
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: Text(
                  positiveLabel,
                  style: const TextStyle(color: Color(0xFF212121)),
                ),
                selected: value == true,
                onSelected: (_) => onChanged(true),
              ),
              ChoiceChip(
                label: Text(
                  negativeLabel,
                  style: const TextStyle(color: Color(0xFF212121)),
                ),
                selected: value == false,
                onSelected: (_) => onChanged(false),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _downloadPdf() async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final plan = UpgradeMatchingTierHelper.planFromPoolDoc(widget.docMap);
      final bytes = await buildUpgradeMatchingProfilePdf(
        poolDoc: widget.docMap,
        plan: plan,
      );
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      final name = 'FD${plan}_${widget.docId}.pdf';
      if (kIsWeb) {
        downloadBytesFile(name, bytes, 'application/pdf');
      } else {
        await Printing.sharePdf(bytes: bytes, filename: name);
      }
    } catch (e, st) {
      debugPrint('$e\n$st');
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('無法產生 PDF：$e')),
      );
    }
  }

  Widget _textField(String key) {
    final label = _zh[key] ?? key;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: _c[key],
        decoration: InputDecoration(
          labelText: label,
          alignLabelWithHint: true,
          border: const OutlineInputBorder(),
        ),
        maxLines: key == 'occupationIncome' || key == 'partnerReq' ? 4 : 3,
        minLines: 1,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.docMap['displayName']?.toString().trim().isNotEmpty == true
        ? widget.docMap['displayName'].toString()
        : widget.docId;

    return Material(
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 4, 0),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
                Expanded(
                  child: Text(
                    '編輯升級配對資料 · $title',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                FilledButton.tonal(
                  onPressed: _saving ? null : _downloadPdf,
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.picture_as_pdf_outlined, size: 20),
                      SizedBox(width: 6),
                      Text('下載 PDF'),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined, size: 20),
                  label: const Text('同步儲存'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppConstants.primaryColor,
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                Text('UID：${widget.docId}', style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                const SizedBox(height: 12),
                _textField('nationality'),
                _textField('name'),
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('性別', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      const SizedBox(height: 6),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: '男', label: Text('男')),
                          ButtonSegment(value: '女', label: Text('女')),
                        ],
                        selected: {_gender},
                        onSelectionChanged: (s) => setState(() => _gender = s.first),
                      ),
                    ],
                  ),
                ),
                _textField('age'),
                _textField('dob'),
                _textField('heightWeight'),
                _textField('phone'),
                _textField('residence'),
                _boolRowDual(
                  label: '有自置物業嗎？',
                  value: _hasProperty,
                  positiveLabel: '有',
                  negativeLabel: '無',
                  onChanged: (v) => setState(() => _hasProperty = v),
                ),
                _textField('education'),
                _textField('occupationIncome'),
                _textField('partnerReq'),
                _textField('debt'),
                _textField('health'),
                _boolRowDual(
                  label: '有曾結過婚嗎？',
                  value: _marriedBefore,
                  positiveLabel: '有',
                  negativeLabel: '無',
                  onChanged: (v) => setState(() => _marriedBefore = v),
                ),
                _textField('marriageDetail'),
                _boolRowDual(
                  label: '想結婚嗎？',
                  value: _wantMarriageSoon,
                  positiveLabel: '想',
                  negativeLabel: '不想',
                  onChanged: (v) => setState(() => _wantMarriageSoon = v),
                ),
                _boolRowDual(
                  label: '日後想生孩子嗎？',
                  value: _wantChildren,
                  positiveLabel: '想',
                  negativeLabel: '不想',
                  onChanged: (v) => setState(() => _wantChildren = v),
                ),
                _boolRowDual(
                  label: '有急切想結婚生孩嗎？',
                  value: _urgentMarriage,
                  positiveLabel: '有',
                  negativeLabel: '無',
                  onChanged: (v) => setState(() => _urgentMarriage = v),
                ),
                _textField('pets'),
                _textField('hobbies'),
                _textField('selfReflection'),
                _textField('partnerFlaws'),
                _boolRowDual(
                  label: '有無車牌？',
                  value: _hasDriverLicense,
                  positiveLabel: '有',
                  negativeLabel: '無',
                  onChanged: (v) => setState(() => _hasDriverLicense = v),
                ),
                _textField('languages'),
                _textField('sideBusiness'),
                _textField('political'),
                _textField('religion'),
                _textField('diet'),
                _textField('alcohol'),
                _textField('smokingFreq'),
                _textField('gambling'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
