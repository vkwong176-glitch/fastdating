import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/upgrade_matching_profile.dart';
import '../services/firebase_bootstrap.dart';
import '../services/upgrade_matching_service.dart';
import '../utils/constants.dart';

/// 升級配對表單本體（訂閱頁「升級配對」與「訂閱的配對計劃」底部編輯區共用）
class UpgradeMatchingForm extends StatefulWidget {
  const UpgradeMatchingForm({
    super.key,
    this.initial,
    this.showSubmitButton = true,
    this.submitLabel = '提交',
    this.onSaved,
    this.embedded = false,
    this.showSectionTitle = false,
    this.sectionTitle = '升級配對個人資料',
  });

  /// 若為 null，會在首幀嘗試從 Firestore 載入
  final UpgradeMatchingProfileData? initial;
  final bool showSubmitButton;
  final String submitLabel;
  final VoidCallback? onSaved;
  final bool embedded;
  final bool showSectionTitle;
  final String sectionTitle;

  @override
  State<UpgradeMatchingForm> createState() => _UpgradeMatchingFormState();
}

class _UpgradeMatchingFormState extends State<UpgradeMatchingForm> {
  late final Map<String, TextEditingController> _text;

  String? _gender;
  bool? _hasProperty;
  bool? _marriedBefore;
  bool? _wantMarriageSoon;
  bool? _wantChildren;
  bool? _urgentMarriage;
  bool? _hasDriverLicense;

  Uint8List? _personalPhotoBytes;
  bool _loadingRemote = true;
  bool _saving = false;

  static const double _personalPhotoSizePx = 4 * 37.8;
  static const Color _sectionYellow = Color(0xFFFFFDE7);
  static const Color _gridColor = Color(0x1A9E9E9E);

  @override
  void initState() {
    super.initState();
    _text = UpgradeMatchingProfileData.createControllers();
    final pre = widget.initial;
    if (pre != null) {
      _applyDataToState(pre);
      _loadingRemote = false;
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadRemote());
    }
  }

  /// 不觸發 rebuild；僅供 [initState] 使用。
  void _applyDataToState(UpgradeMatchingProfileData d) {
    d.applyToControllers(_text);
    _gender = d.gender;
    _hasProperty = d.hasProperty;
    _marriedBefore = d.marriedBefore;
    _wantMarriageSoon = d.wantMarriageSoon;
    _wantChildren = d.wantChildren;
    _urgentMarriage = d.urgentMarriage;
    _hasDriverLicense = d.hasDriverLicense;
    _personalPhotoBytes = d.personalPhotoBytes;
  }

  Future<void> _loadRemote() async {
    if (!FirebaseBootstrap.isReady || FirebaseAuth.instance.currentUser == null) {
      if (mounted) setState(() => _loadingRemote = false);
      return;
    }
    try {
      final data = await UpgradeMatchingService.instance.fetchMyProfile();
      if (!mounted) return;
      if (data != null) {
        if (mounted) {
          setState(() {
            _applyDataToState(data);
            _loadingRemote = false;
          });
        }
        return;
      }
    } catch (_) {}
    if (mounted) setState(() => _loadingRemote = false);
  }

  @override
  void dispose() {
    for (final c in _text.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickPersonalPhoto() async {
    final picker = ImagePicker();
    final x = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      imageQuality: 88,
    );
    if (x == null || !mounted) return;
    final bytes = await x.readAsBytes();
    setState(() => _personalPhotoBytes = bytes);
  }

  Future<void> _submit() async {
    if ((_text['nationality']?.text.trim().isEmpty ?? true) ||
        (_text['name']?.text.trim().isEmpty ?? true) ||
        (_text['age']?.text.trim().isEmpty ?? true) ||
        (_text['dob']?.text.trim().isEmpty ?? true) ||
        _gender == null ||
        _gender!.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('請填寫國籍、姓名、性別、年齡、出生日期')),
        );
      }
      return;
    }
    if (_text['political']?.text.trim().isEmpty ?? true) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('請填寫「有強烈政治立場嗎」欄位')),
        );
      }
      return;
    }
    if (!FirebaseBootstrap.isReady || FirebaseAuth.instance.currentUser == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('請先登入，才能儲存升級配對資料')),
        );
      }
      return;
    }
    setState(() => _saving = true);
    try {
      final data = UpgradeMatchingProfileData.fromControllers(
        c: _text,
        gender: _gender,
        hasProperty: _hasProperty,
        marriedBefore: _marriedBefore,
        wantMarriageSoon: _wantMarriageSoon,
        wantChildren: _wantChildren,
        urgentMarriage: _urgentMarriage,
        hasDriverLicense: _hasDriverLicense,
        personalPhotoBytes: _personalPhotoBytes,
      );
      await UpgradeMatchingService.instance.saveProfile(data);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.submitLabel == '儲存' ? '已儲存升級配對資料' : '已提交升級配對資料')),
      );
      widget.onSaved?.call();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('儲存失敗：$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingRemote) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final bottomPad = widget.embedded ? 24.0 : 100.0;

    final formColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
          if (widget.showSectionTitle) ...[
            Text(
              widget.sectionTitle,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '與管理後台「升級配對資料庫」同步；可隨時修改後按「${widget.submitLabel}」。',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700, height: 1.35),
            ),
            const SizedBox(height: 12),
          ],
          _section(
            children: [
              _personalPhotoField(),
              _textLine('國籍', _text['nationality']!),
              _textLine('姓名', _text['name']!, hint: 'Name (like David, Anna)'),
              _radioRow(
                label: '性別',
                value: _gender,
                opt1: '男',
                opt2: '女',
                onChanged: (v) => setState(() => _gender = v),
              ),
              _textLine('年齡', _text['age']!),
              _textLine('出生日期 (日/月/年)', _text['dob']!),
              _textLine('身高及體重', _text['heightWeight']!),
            ],
          ),
          _section(
            children: [
              _textLine('電話', _text['phone']!, hint: '(國家號，電話號碼)'),
              _textLine('目前居住地區', _text['residence']!, hint: 'Location'),
              _boolRadioRow(
                label: '有自置物業嗎？',
                value: _hasProperty,
                yes: '有',
                no: '沒有',
                onChanged: (v) => setState(() => _hasProperty = v),
              ),
              _textLine('學歷 (請 Wtps+852 62379385學歷核對)', _text['education']!),
              _textLine('職業及收入', _text['occupationIncome']!),
              _textLine('擇偶要求是什麼？年齡範圍？', _text['partnerReq']!),
              _textLine('有無負債嗎? 如有，負債多少?', _text['debt']!),
            ],
          ),
          _section(
            children: [
              _textLine('有冇身體缺憾？(例如：家族遺傳病) 若有，請說明', _text['health']!),
              _boolRadioRow(
                label: '有曾結過婚嗎？',
                value: _marriedBefore,
                yes: '有',
                no: '無',
                onChanged: (v) => setState(() => _marriedBefore = v),
              ),
              _textLine(
                '若有結過婚，結過幾多次？有小朋友嗎？(若有幾大？男或女？)',
                _text['marriageDetail']!,
                required: false,
              ),
              _boolRadioRow(
                label: '想結婚嗎？',
                value: _wantMarriageSoon,
                yes: '想',
                no: '不想',
                onChanged: (v) => setState(() => _wantMarriageSoon = v),
              ),
              _boolRadioRow(
                label: '日後想生孩子嗎?',
                value: _wantChildren,
                yes: '想',
                no: '不想',
                onChanged: (v) => setState(() => _wantChildren = v),
              ),
              _boolRadioRow(
                label: '有急切想結婚生孩嗎？',
                value: _urgentMarriage,
                yes: '有',
                no: '無',
                onChanged: (v) => setState(() => _urgentMarriage = v),
              ),
              _textLine('會養寵物嗎? 如有，會養什麼寵物?', _text['pets']!),
            ],
          ),
          _section(
            children: [
              _textLine('平時嗜好是什麼?', _text['hobbies']!),
              _textLine('你對自己了解嗎? 有什麼優缺點?', _text['selfReflection']!),
              _textLine('你最不能接受另一伴有什麼缺點?', _text['partnerFlaws']!),
              _boolRadioRow(
                label: '有無車牌？',
                value: _hasDriverLicense,
                yes: '有',
                no: '無',
                onChanged: (v) => setState(() => _hasDriverLicense = v),
              ),
              _textLine('能說的語言', _text['languages']!),
              _textLine('有創業的經驗嗎？(如有請講創什麼業？年資)', _text['sideBusiness']!),
            ],
          ),
          _section(
            children: [
              _textLine('有強烈政治立場嗎? 若有，解釋', _text['political']!),
              _textLine('有無宗教信仰嗎? 若有，請說明', _text['religion']!),
              _textLine('有什麼東西是不進食? 若有說明', _text['diet']!),
              _textLine('喜歡飲酒嗎? 若鍾意，一星期飲幾多? 系咪飲到醉為止?', _text['alcohol']!),
              _textLine('有沒有吸煙的習慣? 若有，平均每星期幾次煙?', _text['smokingFreq']!),
              _textLine('有無賭博習慣? 若有，最大賭博金額是多少?', _text['gambling']!),
            ],
          ),
          if (widget.showSubmitButton) ...[
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saving ? null : _submit,
              style: FilledButton.styleFrom(
                backgroundColor: AppConstants.primaryColor,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: _saving
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Text(
                      widget.submitLabel,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
            ),
          ],
        ],
    );

    final padded = Padding(
      padding: EdgeInsets.fromLTRB(16, widget.embedded ? 8 : 20, 16, bottomPad),
      child: formColumn,
    );

    final scrollable = widget.embedded
        ? padded
        : SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: padded,
          );

    return Stack(
      children: [
        Positioned.fill(
          child: CustomPaint(painter: _LightGridPainter(color: _gridColor)),
        ),
        scrollable,
      ],
    );
  }

  Widget _section({required List<Widget> children}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _sectionYellow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.amber.shade100),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      ),
    );
  }

  Widget _personalPhotoField() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Center(child: _labelRow('個人照（上載）')),
          Text(
            '顯示區 4cm × 4cm',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 8),
          Center(
            child: GestureDetector(
              onTap: _pickPersonalPhoto,
              child: Container(
                width: _personalPhotoSizePx,
                height: _personalPhotoSizePx,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                clipBehavior: Clip.antiAlias,
                child: _personalPhotoBytes == null
                    ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_photo_alternate_outlined, size: 36, color: Colors.grey.shade500),
                          const SizedBox(height: 6),
                          Text(
                            '點擊選擇相片',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      )
                    : Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.memory(_personalPhotoBytes!, fit: BoxFit.cover),
                          Positioned(
                            top: 4,
                            right: 4,
                            child: Material(
                              color: Colors.black45,
                              shape: const CircleBorder(),
                              child: IconButton(
                                icon: const Icon(Icons.close, color: Colors.white, size: 18),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                onPressed: () => setState(() => _personalPhotoBytes = null),
                                tooltip: '移除',
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _labelRow(String label, {bool required = true}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: RichText(
        text: TextSpan(
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey.shade900),
          children: [
            TextSpan(text: label),
            if (required)
              const TextSpan(
                text: ' *',
                style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600),
              ),
          ],
        ),
      ),
    );
  }

  Widget _textLine(String label, TextEditingController c, {String? hint, bool required = true}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _labelRow(label, required: required),
          TextField(
            controller: c,
            maxLines: label.length > 24 ? 3 : 1,
            decoration: InputDecoration(
              hintText: hint,
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _radioRow({
    required String label,
    required String? value,
    required String opt1,
    required String opt2,
    required ValueChanged<String?> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _labelRow(label),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: Text(opt1),
                selected: value == opt1,
                onSelected: (_) => onChanged(opt1),
                selectedColor: AppConstants.primaryColor.withValues(alpha: 0.25),
                labelStyle: TextStyle(
                  color: value == opt1 ? AppConstants.primaryColor : Colors.black87,
                  fontWeight: value == opt1 ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
              ChoiceChip(
                label: Text(opt2),
                selected: value == opt2,
                onSelected: (_) => onChanged(opt2),
                selectedColor: AppConstants.primaryColor.withValues(alpha: 0.25),
                labelStyle: TextStyle(
                  color: value == opt2 ? AppConstants.primaryColor : Colors.black87,
                  fontWeight: value == opt2 ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _boolRadioRow({
    required String label,
    required bool? value,
    required String yes,
    required String no,
    required ValueChanged<bool?> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _labelRow(label),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: Text(yes),
                selected: value == true,
                onSelected: (_) => onChanged(true),
                selectedColor: AppConstants.primaryColor.withValues(alpha: 0.25),
                labelStyle: TextStyle(
                  color: value == true ? AppConstants.primaryColor : Colors.black87,
                  fontWeight: value == true ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
              ChoiceChip(
                label: Text(no),
                selected: value == false,
                onSelected: (_) => onChanged(false),
                selectedColor: AppConstants.primaryColor.withValues(alpha: 0.25),
                labelStyle: TextStyle(
                  color: value == false ? AppConstants.primaryColor : Colors.black87,
                  fontWeight: value == false ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LightGridPainter extends CustomPainter {
  _LightGridPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 0.5;
    const step = 24.0;
    for (double x = 0; x <= size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y <= size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _LightGridPainter oldDelegate) => oldDelegate.color != color;
}
