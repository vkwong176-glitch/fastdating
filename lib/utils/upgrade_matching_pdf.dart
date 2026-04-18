import 'dart:convert';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/upgrade_matching_profile.dart';
import 'upgrade_matching_bool_labels.dart';
import 'upgrade_matching_tier.dart';

/// 單筆會員合併 PDF 時使用的資料
typedef UpgradeMatchingPdfMember = ({
  Map<String, dynamic> poolDoc,
  int plan,
  String docId,
});

/// 與管理後台表格一致的中文欄位標題
const Map<String, String> _kFieldZh = {
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

String _genderZh(String? raw) {
  if (raw == null || raw.isEmpty) return '—';
  final s = raw.toLowerCase().trim();
  if (s == 'female' || s == '女') return '女';
  if (s == 'male' || s == '男') return '男';
  return raw;
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

/// 單一會員 PDF 內容（widgets），供單檔與合併檔共用。
List<pw.Widget> buildMemberPdfWidgets(
  pw.Font base, {
  required Map<String, dynamic> poolDoc,
  required int plan,
  int? memberIndex,
  int? memberTotal,
}) {
  final parsed = UpgradeMatchingProfileData.fromFirestoreDoc(poolDoc);
  final photo = _profilePhotoBytes(poolDoc);

  pw.Widget qaLine(String label, String value) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 10),
      padding: const pw.EdgeInsets.only(bottom: 8),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
        ),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(font: base, fontSize: 11, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            value.isEmpty ? '—' : value,
            style: pw.TextStyle(font: base, fontSize: 12, lineSpacing: 1.15),
          ),
        ],
      ),
    );
  }

  final children = <pw.Widget>[];

  if (memberTotal != null && memberTotal > 1 && memberIndex != null) {
    children.addAll([
      pw.Text(
        '第 $memberIndex / $memberTotal 位會員',
        style: pw.TextStyle(
          font: base,
          fontSize: 13,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.blue800,
        ),
      ),
      pw.SizedBox(height: 10),
    ]);
  }

  children.addAll([
    pw.Text(
      'Fast Dating 升級配對資料表格',
      style: pw.TextStyle(font: base, fontSize: 18, fontWeight: pw.FontWeight.bold),
    ),
    pw.SizedBox(height: 10),
    pw.Text(
      '方案：FD$plan ${UpgradeMatchingTierHelper.labelForPlan(plan)}',
      style: pw.TextStyle(font: base, fontSize: 12),
    ),
    pw.SizedBox(height: 14),
    pw.Text(
      '一、會員個人照',
      style: pw.TextStyle(font: base, fontSize: 13, fontWeight: pw.FontWeight.bold),
    ),
    pw.SizedBox(height: 8),
  ]);

  if (photo != null && photo.isNotEmpty) {
    children.add(
      pw.Center(
        child: pw.Image(
          pw.MemoryImage(photo),
          width: 260,
          fit: pw.BoxFit.contain,
        ),
      ),
    );
  } else {
    children.add(pw.Text('（未上載）', style: pw.TextStyle(font: base, fontSize: 11)));
  }

  children.addAll([
    pw.SizedBox(height: 16),
    pw.Text(
      '二、升級配對問卷（每條問題與答案）',
      style: pw.TextStyle(font: base, fontSize: 13, fontWeight: pw.FontWeight.bold),
    ),
    pw.SizedBox(height: 10),
  ]);

  if (parsed != null) {
    children.add(qaLine('性別', _genderZh(parsed.gender)));
    for (final k in UpgradeMatchingProfileData.textKeys) {
      final label = _kFieldZh[k] ?? k;
      final v = parsed.text[k]?.trim() ?? '';
      children.add(qaLine(label, v));
    }
    children.addAll([
      qaLine('有自置物業嗎', zhHaveNone(parsed.hasProperty)),
      qaLine('有曾結過婚嗎', zhHaveNone(parsed.marriedBefore)),
      qaLine('想結婚嗎', zhWantNotWant(parsed.wantMarriageSoon)),
      qaLine('日後想生孩子嗎', zhWantNotWant(parsed.wantChildren)),
      qaLine('有急切想結婚生孩嗎', zhHaveNone(parsed.urgentMarriage)),
      qaLine('有無車牌', zhHaveNone(parsed.hasDriverLicense)),
    ]);
  } else {
    children.add(pw.Text('（無法讀取 profile）', style: pw.TextStyle(font: base, fontSize: 10)));
  }

  return children;
}

/// 升級配對 PDF：含個人照（如有）及每條問答。
Future<Uint8List> buildUpgradeMatchingProfilePdf({
  required Map<String, dynamic> poolDoc,
  required int plan,
}) async {
  final base = await PdfGoogleFonts.notoSansTCRegular();
  final theme = pw.ThemeData.withFont(base: base);
  final doc = pw.Document(theme: theme);
  final children = buildMemberPdfWidgets(
    base,
    poolDoc: poolDoc,
    plan: plan,
  );
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(40),
      build: (context) => children,
    ),
  );
  return doc.save();
}

/// 多筆會員合併為單一 PDF（依序排列，含分隔）。
Future<Uint8List> buildMergedUpgradeMatchingProfilePdf(
  List<UpgradeMatchingPdfMember> members,
) async {
  if (members.isEmpty) {
    throw ArgumentError('members 不可為空');
  }
  final base = await PdfGoogleFonts.notoSansTCRegular();
  final theme = pw.ThemeData.withFont(base: base);
  final doc = pw.Document(theme: theme);
  final all = <pw.Widget>[];
  final n = members.length;
  for (var i = 0; i < n; i++) {
    final m = members[i];
    if (i > 0) {
      all.addAll([
        pw.SizedBox(height: 24),
        pw.Divider(thickness: 1.2, color: PdfColors.grey500),
        pw.SizedBox(height: 24),
      ]);
    }
    all.addAll(
      buildMemberPdfWidgets(
        base,
        poolDoc: m.poolDoc,
        plan: m.plan,
        memberIndex: i + 1,
        memberTotal: n,
      ),
    );
  }
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(40),
      build: (context) => all,
    ),
  );
  return doc.save();
}
